/**
 * Smart fault handler for the Convert-Quote-to-Order flow. Invoked once per conversion
 * fault from the flow's fault path (single Request per call — this is NOT a bulk entry
 * point and is intentionally not bulkified). For a single non-limit fault, the per-request
 * DB access is intentional and bounded: at most one Quote lookup, one Order lookup, and one
 * Order delete. The governor-limit branch runs in the SAME exhausted transaction as the
 * failed conversion, so it performs string classification ONLY — no SOQL/DML.
 */
public with sharing class Q2OConversionFaultHandler {

    @TestVisible private static final String CAT_GOVERNOR_LIMIT = 'GOVERNOR_LIMIT';
    @TestVisible private static final String CAT_MISLEADING_LE  = 'MISLEADING_LEGAL_ENTITY';
    @TestVisible private static final String CAT_REAL_LE        = 'REAL_LEGAL_ENTITY';
    @TestVisible private static final String CAT_OTHER          = 'OTHER';

    @TestVisible private static final String LE_STATUS_ACTIVE   = 'Active';
    @TestVisible private static final String ORDER_STATUS_DRAFT = 'Draft';

    // Test seam: when set during a test run, handleOne throws this message from inside the
    // try block so the catch path (non-limit fallback and mid-cleanup limit re-classification)
    // can be exercised. Always null in production.
    @TestVisible private static String simulateThrowMessageForTest = null;

    @TestVisible private class SimulatedFaultException extends Exception {}

    public class Request {
        @InvocableVariable(required=true) public Id quoteId;
        @InvocableVariable public String faultMessage;
        @InvocableVariable public Id attemptedOrderId;
    }

    public class Response {
        @InvocableVariable public String friendlyMessage;
        @InvocableVariable public String category;
        @InvocableVariable public Boolean orphanCleaned;
    }

    // Invoked with a SINGLE request per conversion fault from the flow's fault path. The loop
    // exists only to satisfy the invocable contract; this is not a bulk operation and the
    // per-request DB access (one Quote lookup + one Order lookup + one delete max) is
    // intentional and bounded.
    @InvocableMethod(label='Handle Q2O Conversion Fault'
        description='Classifies a Convert-Quote-to-Order failure into actionable guidance and cleans up an orphan Draft order.')
    public static List<Response> handle(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            results.add(handleOne(req));
        }
        return results;
    }

    @TestVisible
    private static Response handleOne(Request req) {
        Response resp = new Response();
        resp.orphanCleaned = false;
        String msg = (req == null || req.faultMessage == null) ? '' : req.faultMessage;

        // Governor-limit: pure string only — the transaction may be exhausted, so NO SOQL/DML here.
        if (isGovernorLimit(msg)) {
            resp.category = CAT_GOVERNOR_LIMIT;
            resp.friendlyMessage = governorLimitGuidance();
            return resp;
        }

        try {
            if (Test.isRunningTest() && simulateThrowMessageForTest != null) {
                throw new SimulatedFaultException(simulateThrowMessageForTest);
            }
            if (mentionsLegalEntity(msg)) {
                LegalEntityInfo info = loadLegalEntityInfo(req.quoteId);
                resp.category = classifyLegalEntity(info.status);
                resp.friendlyMessage = (resp.category == CAT_MISLEADING_LE)
                    ? misleadingLegalEntityGuidance(info.name)
                    : realLegalEntityGuidance();
            } else {
                resp.category = CAT_OTHER;
                resp.friendlyMessage = String.isBlank(msg) ? genericGuidance() : msg;
            }
            if (req.attemptedOrderId != null) {
                resp.orphanCleaned = cleanupOrphanDraftOrder(req.attemptedOrderId);
            }
        } catch (Exception e) {
            // The SOQL/DML above can throw a System.LimitException if the transaction was
            // already near its ceiling when this handler ran. Re-classify those as
            // GOVERNOR_LIMIT so the user gets accurate guidance. (Note: a CPU-time
            // LimitException is uncatchable and can still escape this block — acceptable.)
            if (isGovernorLimit(e.getMessage())) {
                resp.category = CAT_GOVERNOR_LIMIT;
                resp.friendlyMessage = governorLimitGuidance();
            } else {
                resp.category = CAT_OTHER;
                if (String.isBlank(resp.friendlyMessage)) {
                    resp.friendlyMessage = String.isBlank(msg) ? genericGuidance() : msg;
                }
            }
        }
        return resp;
    }

    @TestVisible
    private static Boolean isGovernorLimit(String msg) {
        if (String.isBlank(msg)) return false;
        String m = msg.toLowerCase();
        return m.contains('too many soql queries')
            || m.contains('too many query rows')
            || m.contains('too many dml')
            || m.contains('apex cpu time')
            || m.contains('apex heap size');
    }

    @TestVisible
    private static Boolean mentionsLegalEntity(String msg) {
        return String.isNotBlank(msg) && msg.toLowerCase().contains('legal entity');
    }

    @TestVisible
    private static String classifyLegalEntity(String status) {
        return (status == LE_STATUS_ACTIVE) ? CAT_MISLEADING_LE : CAT_REAL_LE;
    }

    private class LegalEntityInfo {
        String name;
        String status;
    }

    // Deliberate null-collapse: a null quoteId, a missing quote, and a quote with no
    // LegalEntity all yield status == null. That maps to REAL_LEGAL_ENTITY ("select an
    // active Legal Entity") guidance via classifyLegalEntity — intentional and harmless,
    // since none of those cases represents a valid active Legal Entity.
    @TestVisible
    private static LegalEntityInfo loadLegalEntityInfo(Id quoteId) {
        LegalEntityInfo info = new LegalEntityInfo();
        if (quoteId == null) return info;
        List<Quote> quotes = [
            SELECT LegalEntityId, LegalEntity.Name, LegalEntity.Status
            FROM Quote WHERE Id = :quoteId LIMIT 1
        ];
        if (!quotes.isEmpty() && quotes[0].LegalEntityId != null) {
            info.name = quotes[0].LegalEntity.Name;
            info.status = quotes[0].LegalEntity.Status;
        }
        return info;
    }

    @TestVisible
    private static Boolean cleanupOrphanDraftOrder(Id orderId) {
        if (orderId == null) return false;
        List<Order> orders = [SELECT Id, Status FROM Order WHERE Id = :orderId LIMIT 1];
        if (!orders.isEmpty() && orders[0].Status == ORDER_STATUS_DRAFT) {
            delete orders[0];
            return true;
        }
        return false;
    }

    @TestVisible
    private static String governorLimitGuidance() {
        return 'This quote is too large for the order-creation engine to process in one step. '
            + 'Open the Lines tab, click Reprice All, wait for repricing to finish, then convert again. '
            + 'If the quote has many lines, consider splitting it. If it keeps failing, contact your administrator.';
    }

    @TestVisible
    private static String misleadingLegalEntityGuidance(String leName) {
        String le = String.isBlank(leName) ? 'on the quote' : '"' + leName + '"';
        return 'Your Legal Entity ' + le + ' is valid and active. This is a known intermittent '
            + 'order-creation error, not a Legal Entity problem. Click Reprice All, wait for repricing '
            + 'to finish, then try converting again. If it persists, contact your administrator.';
    }

    @TestVisible
    private static String realLegalEntityGuidance() {
        return 'Select an active Legal Entity on the Quote before converting it to an Order.';
    }

    @TestVisible
    private static String genericGuidance() {
        return 'An unexpected error occurred while creating the order. Please try again, '
            + 'and contact your administrator if the problem continues.';
    }
}