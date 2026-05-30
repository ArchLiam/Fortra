/**
 * DocuSignEnvelopeService
 *
 * Sends a Fortra quote PDF to a recipient via DocuSign for electronic signature.
 * Uses the DocuSignAPI Named Credential for authentication.
 *
 * Signature placement: right-bottom of the last page via absolute x/y coordinates.
 * US Letter = 612 x 792 points (72 DPI). DocuSign origin is top-left.
 *
 * Page count resolution:
 *   1. Explicit pageCount param (if > 0) takes precedence
 *   2. Auto-detect from PDF hex scan
 *   3. Fallback to 2 (Fortra quotes are always 2+ pages)
 *
 * Entry points:
 *   - OmniStudio IP Remote Action: implements Callable
 *   - Flow / Screen Flow: @InvocableMethod
 *   - Execute Anonymous / Apex: DocuSignEnvelopeService.sendEnvelope(...)
 */
public without sharing class DocuSignEnvelopeService implements Callable {

    private static final String LOG_PREFIX = '[DocuSign] ';
    private static final String ACCOUNT_ID = 'b97bed00-53ac-4769-ae52-3c775da2c2fe';
    private static final String ENVELOPE_ENDPOINT = 'callout:DocuSignAPI/v2.1/accounts/'
        + ACCOUNT_ID + '/envelopes';

    // Hex-conversion doubles in-memory size. Cap to keep under the 6MB
    // synchronous heap limit during page detection.
    private static final Integer MAX_DETECT_BYTES = 2 * 1024 * 1024;

    // Fortra quotes are always at least 2 pages. If detection returns < 2,
    // fall back to 2 rather than placing signature on page 1.
    private static final Integer MIN_FORTRA_PAGES = 2;

    // ────────────────────────────────────────────────────────────────────────
    // Callable interface — OmniStudio IP Remote Action
    // ────────────────────────────────────────────────────────────────────────
    public Object call(String action, Map<String, Object> args) {
        Map<String, Object> input = args;
        Map<String, Object> output = null;

        if (args != null && args.containsKey('input') && args.get('input') instanceof Map<String, Object>) {
            input = (Map<String, Object>) args.get('input');
            if (args.get('output') instanceof Map<String, Object>) {
                output = (Map<String, Object>) args.get('output');
            } else {
                output = new Map<String, Object>();
                args.put('output', output);
            }
        }

        try {
            if (action != 'sendEnvelope') {
                throw new DocuSignException('Invalid action: ' + action);
            }

            Integer pgCount = null;
            Object pgObj = input.get('pageCount');
            if (pgObj != null) {
                String pgStr = String.valueOf(pgObj).trim();
                if (String.isNotBlank(pgStr) && !pgStr.startsWith('%') && pgStr.isNumeric()) {
                    pgCount = Integer.valueOf(pgStr);
                }
            }            

            Map<String, Object> result = sendEnvelope(
                (String) input.get('contentVersionId'),
                (String) input.get('signerEmail'),
                (String) input.get('signerName'),
                (String) input.get('emailSubject'),
                pgCount
            );

            if (output != null) {
                output.putAll(result);
            }

            return result;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'EXCEPTION in call(): '
                + e.getTypeName() + ': ' + e.getMessage()
                + ' | line ' + e.getLineNumber()
                + ' | stack: ' + e.getStackTraceString());

            Map<String, Object> errResult = new Map<String, Object>{
                'success' => false,
                'errorMessage' => e.getTypeName() + ': ' + e.getMessage()
            };
            if (output != null) {
                output.putAll(errResult);
            }
            return errResult;
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // @InvocableMethod — Flow / Screen Flow
    // ────────────────────────────────────────────────────────────────────────
    @InvocableMethod(label='Send DocuSign Envelope' description='Sends a PDF for DocuSign signature')
    public static List<EnvelopeResult> sendEnvelopeInvocable(List<EnvelopeRequest> requests) {
        List<EnvelopeResult> results = new List<EnvelopeResult>();
        for (EnvelopeRequest req : requests) {
            Map<String, Object> outcome = sendEnvelope(
                req.contentVersionId,
                req.signerEmail,
                req.signerName,
                req.emailSubject,
                req.pageCount
            );
            EnvelopeResult res = new EnvelopeResult();
            res.envelopeId = (String) outcome.get('envelopeId');
            res.success = (Boolean) outcome.get('success');
            res.errorMessage = (String) outcome.get('errorMessage');
            results.add(res);
        }
        return results;
    }

    // ────────────────────────────────────────────────────────────────────────
    // Core method
    // ────────────────────────────────────────────────────────────────────────
    public static Map<String, Object> sendEnvelope(
        String contentVersionId,
        String signerEmail,
        String signerName,
        String emailSubject,
        Integer pageCount
    ) {
        // ── 1. Read the generated PDF ─────────────────────────────────────
        ContentVersion cv = [
            SELECT VersionData, Title, FileExtension, ContentSize
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        if (cv.ContentSize > 4000000) {
            return errorResult('PDF exceeds 4MB limit for synchronous DocuSign send. Size: '
                + cv.ContentSize + ' bytes.');
        }

        // ── 2. Resolve page count: explicit override > auto-detect > fallback ─
        Integer resolvedPageCount;
        if (pageCount != null && pageCount > 0) {
            resolvedPageCount = pageCount;
            System.debug(LoggingLevel.INFO, LOG_PREFIX + 'Using explicit pageCount: ' + resolvedPageCount);
        } else {
            resolvedPageCount = detectPdfPageCount(cv.VersionData);
            System.debug(LoggingLevel.INFO, LOG_PREFIX + 'Auto-detected pageCount: ' + resolvedPageCount);
            if (resolvedPageCount < MIN_FORTRA_PAGES) {
                System.debug(LoggingLevel.WARN, LOG_PREFIX + 'Detection returned ' + resolvedPageCount
                    + ', falling back to minimum ' + MIN_FORTRA_PAGES);
                resolvedPageCount = MIN_FORTRA_PAGES;
            }
        }

        String base64Doc = EncodingUtil.base64Encode(cv.VersionData);
        String fileName = cv.Title;
        if (!fileName.toLowerCase().endsWith('.pdf')) {
            fileName += '.pdf';
        }

        // ── 3. Build envelope JSON ────────────────────────────────────────
        String envelopeJson = buildEnvelopeJson(
            base64Doc, fileName, signerEmail, signerName, emailSubject, resolvedPageCount
        );

        // ── 4. POST to DocuSign ───────────────────────────────────────────
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENVELOPE_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(envelopeJson);
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);

        // ── 5. Parse response ─────────────────────────────────────────────
        Map<String, Object> result = new Map<String, Object>();

        if (res.getStatusCode() == 201) {
            Map<String, Object> body = (Map<String, Object>)
                JSON.deserializeUntyped(res.getBody());
            result.put('success', true);
            result.put('envelopeId', (String) body.get('envelopeId'));
            result.put('status', (String) body.get('status'));
            result.put('statusDateTime', (String) body.get('statusDateTime'));
            result.put('pageCount', resolvedPageCount);
        } else {
            result.put('success', false);
            result.put('errorCode', res.getStatusCode());
            result.put('errorMessage', res.getBody());
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'DocuSign returned ' + res.getStatusCode()
                + ': ' + res.getBody());
        }

        return result;
    }

    // ────────────────────────────────────────────────────────────────────────
    // PDF page detection
    // ────────────────────────────────────────────────────────────────────────
    // Counts "/Type /Page" object headers in the PDF, subtracting "/Type /Pages"
    // (the root catalog object) to get just the leaf page objects.
    //
    // NOTE: This works on uncompressed PDF object streams. For heavily-compressed
    // PDFs (where /Type /Page markers live inside compressed streams), this will
    // under-count. The MIN_FORTRA_PAGES fallback in sendEnvelope() covers this.
    public static Integer detectPdfPageCount(Blob pdfBlob) {
        if (pdfBlob == null) {
            return 0;
        }
        if (pdfBlob.size() > MAX_DETECT_BYTES) {
            System.debug(LoggingLevel.WARN, LOG_PREFIX + 'PDF too large for page detection ('
                + pdfBlob.size() + ' bytes); returning 0');
            return 0;
        }

        // "/Type /Page"  → 2f54797065202f50616765
        // "/Type /Pages" → 2f54797065202f5061676573
        String pdfHex = EncodingUtil.convertToHex(pdfBlob);
        Integer pageMarkers = countOccurrences(pdfHex, '2f54797065202f50616765');
        Integer pagesMarkers = countOccurrences(pdfHex, '2f54797065202f5061676573');

        return Math.max(0, pageMarkers - pagesMarkers);
    }

    private static Integer countOccurrences(String haystack, String needle) {
        Integer count = 0;
        Integer idx = haystack.indexOf(needle);
        while (idx != -1) {
            count++;
            idx = haystack.indexOf(needle, idx + needle.length());
        }
        return count;
    }

    // ────────────────────────────────────────────────────────────────────────
    // Envelope JSON builder — absolute x/y positioning on last page
    // ────────────────────────────────────────────────────────────────────────
    // US Letter = 612 x 792 points. DocuSign origin = top-left of page.
    //
    //   ┌──────────────────────────────────┐
    //   │  (quote content above)           │
    //   │                                  │
    //   │                                  │
    //   │                                  │
    //   │                   ┌─────────────┐│  y ≈ 680
    //   │                   │  Sign Here  ││
    //   │                   └─────────────┘│
    //   │                   Date: _______  │  y ≈ 730
    //   │                   Name: _______  │  y ≈ 755
    //   │                                  │
    //   └──────────────────────────────────┘
    //   x=360 → right half of page
    //
    private static String buildEnvelopeJson(
        String base64Doc,
        String fileName,
        String signerEmail,
        String signerName,
        String emailSubject,
        Integer lastPage
    ) {
        String pageStr = String.valueOf(lastPage);

        Map<String, Object> envelope = new Map<String, Object>();
        envelope.put('status', 'sent');
        envelope.put('emailSubject', emailSubject);
        envelope.put('emailBlurb',
            'Please review and sign the attached Fortra quote. '
            + 'If you have any questions, please contact your Fortra sales representative.');

        // ── Document ──────────────────────────────────────────────────────
        Map<String, Object> doc = new Map<String, Object>();
        doc.put('documentBase64', base64Doc);
        doc.put('name', fileName);
        doc.put('fileExtension', 'pdf');
        doc.put('documentId', '1');
        envelope.put('documents', new List<Object>{ doc });

        // ── Signer ────────────────────────────────────────────────────────
        Map<String, Object> signer = new Map<String, Object>();
        signer.put('email', signerEmail);
        signer.put('name', signerName);
        signer.put('recipientId', '1');
        signer.put('routingOrder', '1');

        // ── Tabs — right-bottom positioning on last page ─────────────────

        // Sign Here — right-bottom of last page
        Map<String, Object> signHere = new Map<String, Object>();
        signHere.put('documentId', '1');
        signHere.put('pageNumber', pageStr);
        signHere.put('xPosition', '360');
        signHere.put('yPosition', '680');

        // Date Signed — below signature
        Map<String, Object> dateSigned = new Map<String, Object>();
        dateSigned.put('documentId', '1');
        dateSigned.put('pageNumber', pageStr);
        dateSigned.put('xPosition', '360');
        dateSigned.put('yPosition', '730');
        dateSigned.put('fontSize', 'Size10');

        // Full Name — below date
        Map<String, Object> fullName = new Map<String, Object>();
        fullName.put('documentId', '1');
        fullName.put('pageNumber', pageStr);
        fullName.put('xPosition', '360');
        fullName.put('yPosition', '755');
        fullName.put('fontSize', 'Size10');

        Map<String, Object> tabs = new Map<String, Object>();
        tabs.put('signHereTabs', new List<Object>{ signHere });
        tabs.put('dateSignedTabs', new List<Object>{ dateSigned });
        tabs.put('fullNameTabs', new List<Object>{ fullName });

        signer.put('tabs', tabs);

        // ── Recipients ────────────────────────────────────────────────────
        Map<String, Object> recipients = new Map<String, Object>();
        recipients.put('signers', new List<Object>{ signer });
        envelope.put('recipients', recipients);

        return JSON.serialize(envelope);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Helpers
    // ────────────────────────────────────────────────────────────────────────
    private static Map<String, Object> errorResult(String message) {
        return new Map<String, Object>{
            'success' => false,
            'errorMessage' => message
        };
    }

    // ── Invocable input/output wrappers ───────────────────────────────────
    public class EnvelopeRequest {
        @InvocableVariable(required=true label='ContentVersion Id')
        public String contentVersionId;
        @InvocableVariable(required=true label='Signer Email')
        public String signerEmail;
        @InvocableVariable(required=true label='Signer Name')
        public String signerName;
        @InvocableVariable(label='Email Subject')
        public String emailSubject;
        @InvocableVariable(label='PDF Page Count (optional - auto-detected if blank)')
        public Integer pageCount;
    }

    public class EnvelopeResult {
        @InvocableVariable public String envelopeId;
        @InvocableVariable public Boolean success;
        @InvocableVariable public String errorMessage;
    }

    public class DocuSignException extends Exception {}
}