/**
 * @description RevSignaling pricing POSTHOOK for SC-3441.
 *
 *              PROBLEM (SC-3441): a user-initiated cancellation / negative-quantity
 *              line (Qty < 0) prices TotalPrice $0.00 instead of a negative credit.
 *              Salesforce confirmed (case w/ Supratik/Sai) this is BY DESIGN: on a
 *              cancellation the pricing action runs at the Quote Line DETAIL level and
 *              the Quote Line ITEM net/total fields are left blank/0. The supported fix
 *              is a POSTHOOK that writes the negative onto the QuoteLineItem AFTER the
 *              pricing procedure (the QLI total fields are updateable=false / engine-only,
 *              so a trigger/flow cannot set them; the context API is the only path).
 *
 *              VALUE SOURCE = the custom staging field CancelNetUnitPrice__c (already
 *              populated upstream from the source asset's net unit price). We deliberately
 *              do NOT read QuoteLineDetail: verified live in FortraUAT 2026-06-26/27 our
 *              QLD is 0 (NetUnitPrice/TotalPrice/TotalLineAmount all 0), so there is no
 *              negative on the detail to copy. credit = CancelNetUnitPrice__c * LineItemQuantity.
 *
 *              CRITICAL — ATTRIBUTE NAMES (root cause of the earlier no-persist):
 *              updateContextAttributes must use the QuoteLineItem FIELD API NAMES, which
 *              are the SAVE-mapped ContextInputAttributeName values:
 *                NetUnitPrice, NetTotalPrice, TotalPrice, Subtotal, TotalLineAmount
 *              NOT the procedure's internal pricing tags (ItemNetTotalPrice / ItemTotalPrice
 *              / ItemSubtotal). Writing the Item* tags updates internal attributes the SAVE
 *              ignores — updateContextAttributes returns SUCCESS but NOTHING persists
 *              (verified 2026-06-27, log_posthook_v2.txt). Salesforce's reference posthook
 *              proved 'NetTotalPrice' persists; all five names above are confirmed
 *              save-mapped on the QLI node of QuoteEntitiesMapping.
 *
 *              WHAT IT WRITES (context attributes, via updateContextAttributes):
 *                NetUnitPrice    = CancelNetUnitPrice__c              (positive per-unit)
 *                NetTotalPrice   = credit                            (-> QLI Net Total Price)
 *                TotalPrice      = credit                            (-> QLI Total Price)  <-- business need
 *                Subtotal        = credit                            (-> QLI Subtotal)
 *                TotalLineAmount = credit                            (-> carries to Order)
 *
 *              SCOPE / SAFETY: only NEGATIVE-quantity lines that carry a non-null,
 *              positive CancelNetUnitPrice__c are touched. Positive/zero-qty lines and
 *              lines without the staging value are never written. Currency-safe by
 *              construction (value already in the line currency).
 *
 *              SWALLOW CONTRACT: never throws out of execute() in a way that breaks the
 *              reprice; outer try/catch downgrades any error to SUCCESS-with-warnings,
 *              and submitContextUpdates swallows the "not in updatable state" path.
 *
 *              REGISTRATION: POST section on the active Procedure Plan
 *              (Fortra_Pricing_PreHook), AFTER the PricingProcedure section.
 *
 * @author Liam Jeong (SC-3441)
 * @date June 2026
 * @version 2.0
 */
global class CancelLineCreditPosthook implements RevSignaling.SignalingApexProcessor {

    // Recursion prevention (a context update can re-trigger the pricing engine).
    private static Boolean isProcessing = false;

    // ============================================================
    // CONTEXT TAG NAMES we READ — verified on SalesTransactionContextExt_v2,
    // node SalesTransactionItem (FortraUAT).
    // ============================================================

    /** Per-line quantity tag. Negative => cancellation / reduction line. */
    @TestVisible private static final String TAG_QUANTITY = 'LineItemQuantity';

    /** Per-line staging field holding the asset net unit price to credit. */
    @TestVisible private static final String TAG_CANCEL_NET = 'CancelNetUnitPrice__c';

    // ============================================================
    // CONTEXT ATTRIBUTE NAMES we WRITE — must be the QLI FIELD API NAMES
    // (save-mapped ContextInputAttributeName), NOT the internal Item* tags.
    // ============================================================

    @TestVisible private static final String ATTR_NET_UNIT_PRICE    = 'NetUnitPrice';
    @TestVisible private static final String ATTR_NET_TOTAL_PRICE   = 'NetTotalPrice';
    @TestVisible private static final String ATTR_TOTAL_PRICE       = 'TotalPrice';
    @TestVisible private static final String ATTR_SUBTOTAL          = 'Subtotal';
    @TestVisible private static final String ATTR_TOTAL_LINE_AMOUNT = 'TotalLineAmount';

    // ============================================================
    // ENTRY POINT
    // ============================================================

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        return process(request != null ? request.ctxInstanceId : null);
    }

    /**
     * @description Core logic, split out by contextId so it is unit-testable without a
     *              RevSignaling.TransactionRequest (which has no public constructor).
     */
    @TestVisible
    private RevSignaling.TransactionResponse process(String contextId) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        if (isProcessing) {
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'CancelLineCreditPosthook skipped - already processing';
            return response;
        }

        try {
            isProcessing = true;

            if (String.isBlank(contextId)) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No context instance id - nothing to credit';
                return response;
            }

            Context.IndustriesContext ctx = new Context.IndustriesContext();

            // Step 1 — read SalesTransactionItem line nodes from the runtime context.
            List<Object> lineNodes = fetchSalesTransactionItems(ctx, contextId);
            if (lineNodes == null || lineNodes.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No SalesTransactionItem nodes - nothing to credit';
                return response;
            }

            // Step 2 — build the credit updates for negative-qty lines that carry a
            //          positive CancelNetUnitPrice__c (positive lines never touched).
            List<Map<String, Object>> updates = buildCreditUpdates(lineNodes);
            if (updates.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No cancellation (negative-qty) lines with a staged net - nothing to credit';
                return response;
            }

            // Step 3 — submit.
            Integer submitted = submitContextUpdates(ctx, contextId, updates);

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Credited ' + submitted + ' cancellation line(s)';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CancelLineCreditPosthook error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            // SUCCESS even on error — never break the whole reprice.
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Cancel-credit posthook completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    // ============================================================
    // CONTEXT FETCH — swallow-and-continue, mirrors the prehook
    // ============================================================

    @TestVisible
    private List<Object> fetchSalesTransactionItems(Context.IndustriesContext ctx, String contextId) {
        try {
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => contextId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            };
            Map<String, Object> apiResponse = ctx.queryTags(queryInput);
            return parseLineNodes(apiResponse);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'fetchSalesTransactionItems error: ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description Pure parse of a queryTags(SalesTransactionItem) response into the
     *              raw node list. Handles {queryResult:{SalesTransactionItem:[...]}},
     *              the flatter {SalesTransactionItem:...}, and single-object cases.
     */
    @TestVisible
    private List<Object> parseLineNodes(Map<String, Object> apiResponse) {
        if (apiResponse == null) {
            return null;
        }
        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            queryResult = (qrObj instanceof Map<String, Object>) ? (Map<String, Object>) qrObj : null;
        } else if (apiResponse.containsKey('SalesTransactionItem')) {
            queryResult = apiResponse;
        }
        if (queryResult == null || !queryResult.containsKey('SalesTransactionItem')) {
            return null;
        }
        Object itemsObj = queryResult.get('SalesTransactionItem');
        if (itemsObj instanceof List<Object>) {
            return (List<Object>) itemsObj;
        }
        return new List<Object>{ itemsObj };
    }

    // ============================================================
    // CREDIT BUILD — pure seam, negative-qty + staged-net lines only
    // ============================================================

    /**
     * @description Build the context node updates for every cancellation line. A line
     *              qualifies iff LineItemQuantity < 0 AND CancelNetUnitPrice__c is a
     *              positive value. The credit written is CancelNetUnitPrice__c * qty
     *              (negative). Positive/zero-qty lines and lines without a staged net
     *              are skipped (no write).
     */
    @TestVisible
    private List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes) {
        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        if (lineNodes == null) {
            return updates;
        }
        for (Object raw : lineNodes) {
            if (!(raw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> node = (Map<String, Object>) raw;
            Map<String, Object> tagMap = extractTagMap(node);
            List<Object> dataPath = getDataPath(node);
            if (dataPath == null || dataPath.isEmpty()) {
                continue;
            }

            Decimal qty = getDecimalFromTag(tagMap, TAG_QUANTITY);
            Decimal cancelNet = getDecimalFromTag(tagMap, TAG_CANCEL_NET);

            // GATE: negative qty AND a positive staged net. Anything else => skip.
            if (qty == null || qty >= 0 || cancelNet == null || cancelNet <= 0) {
                continue;
            }

            Decimal credit = (cancelNet * qty).setScale(2, System.RoundingMode.HALF_UP);

            updates.add(buildNodeUpdate(dataPath, cancelNet, credit));
        }
        return updates;
    }

    /**
     * @description Build one line's context node-update. nodePath is the line's dataPath
     *              with the FIRST element (the 64-char context path) removed, leaving
     *              [rootId, lineId] — matching Salesforce's reference posthook
     *              (fullDataPath.get(1), get(2)). Writes the per-unit net (positive) and
     *              the credit (negative) using the QLI FIELD API NAMES so the engine save
     *              persists them. Pure seam.
     */
    @TestVisible
    private Map<String, Object> buildNodeUpdate(List<Object> dataPath, Decimal cancelNet, Decimal credit) {
        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }
        List<Object> attributes = new List<Object>{
            attr(ATTR_NET_UNIT_PRICE,    cancelNet),
            attr(ATTR_NET_TOTAL_PRICE,   credit),
            attr(ATTR_TOTAL_PRICE,       credit),
            attr(ATTR_SUBTOTAL,          credit),
            attr(ATTR_TOTAL_LINE_AMOUNT, credit)
        };
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    @TestVisible
    private Map<String, Object> attr(String name, Decimal value) {
        return new Map<String, Object>{ 'attributeName' => name, 'attributeValue' => value };
    }

    // ============================================================
    // SUBMIT — swallow "not in updatable state", mirrors the prehook
    // ============================================================

    @TestVisible
    private Integer submitContextUpdates(
        Context.IndustriesContext ctx,
        String contextId,
        List<Map<String, Object>> updates
    ) {
        if (updates == null || updates.isEmpty()) {
            return 0;
        }
        try {
            Map<String, Object> updateInput = new Map<String, Object>{
                'contextId' => contextId,
                'nodePathAndAttributes' => updates
            };
            ctx.updateContextAttributes(updateInput);
            return updates.size();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'submitContextUpdates error: ' + e.getMessage());
            if (e.getMessage() != null && e.getMessage().containsIgnoreCase('not in updatable state')) {
                System.debug(LoggingLevel.INFO, 'Context not in updatable state - skipping cancel-credit');
                return 0;
            }
            throw e;
        }
    }

    // ============================================================
    // DATAPATH / TAG HELPERS — same shape as the prehook
    // ============================================================

    @TestVisible
    private List<Object> getDataPath(Map<String, Object> node) {
        if (node == null) {
            return null;
        }
        Object dpObj = node.get('dataPath');
        return (dpObj instanceof List<Object>) ? (List<Object>) dpObj : null;
    }

    @TestVisible
    private Map<String, Object> extractTagMap(Map<String, Object> node) {
        if (node == null) {
            return null;
        }
        if (node.containsKey('tagValue')) {
            Object tv = node.get('tagValue');
            return (tv instanceof Map<String, Object>) ? (Map<String, Object>) tv : null;
        }
        return node;
    }

    @TestVisible
    private Decimal getDecimalFromTag(Map<String, Object> tagMap, String fieldName) {
        Object val = extractFieldValue(tagMap, fieldName);
        if (val == null) {
            return null;
        }
        if (val instanceof Decimal) {
            return (Decimal) val;
        }
        if (val instanceof Integer || val instanceof Long || val instanceof Double) {
            return Decimal.valueOf(String.valueOf(val));
        }
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Extract a raw tag value, handling both the nested {tagValue:...}
     *              wrapper and the flat value layout.
     */
    @TestVisible
    private Object extractFieldValue(Map<String, Object> tagMap, String fieldName) {
        if (tagMap == null || !tagMap.containsKey(fieldName)) {
            return null;
        }
        Object fieldObj = tagMap.get(fieldName);
        if (fieldObj == null) {
            return null;
        }
        if (fieldObj instanceof Map<String, Object>) {
            Map<String, Object> wrapper = (Map<String, Object>) fieldObj;
            if (wrapper.containsKey('tagValue')) {
                return wrapper.get('tagValue');
            }
            return null;
        }
        return fieldObj;
    }
}
