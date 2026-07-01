/**
 * @description RevSignaling pricing POSTHOOK for amendment line net totals.
 *
 *              PROBLEM: on an Amendment quote line (QuoteAction.Type='Amend',
 *              ItemPricingSource='LastTransaction') the Rev Mgmt Default Pricing
 *              procedure leaves NetUnitPrice / NetTotalPrice / TotalPrice = 0. Every
 *              in-procedure net writer is gated NotEquals 'LastTransaction' (so it skips
 *              amend lines), the only amend-passing container just multiplies the (still
 *              zero) net by quantity, and an in-proc ListGroup seed does NOT fire at
 *              runtime for a LastTransaction line (same wall SC-3441 hit). The supported
 *              fix is a POSTHOOK that writes the carried-forward net onto the
 *              QuoteLineItem AFTER the pricing procedure (the QLI net/total fields are
 *              updateable=false / engine-only, so a trigger/flow cannot set them; the
 *              context API is the only path). Mirrors CancelLineCreditPosthook (SC-3441).
 *
 *              VALUE SOURCE = the per-line context tag AssetActionSourceNetUnitPrice (the
 *              amended Asset's negotiated net unit price, already in the line currency).
 *              This is idempotent (the asset value is stable across reprices, unlike the
 *              gross UnitPrice which compounds the CAD conversion) and discount-correct
 *              (it is the negotiated net, not list). Net per unit = AssetActionSourceNetUnitPrice;
 *              line total = AssetActionSourceNetUnitPrice * LineItemQuantity.
 *
 *              CRITICAL — ATTRIBUTE NAMES: updateContextAttributes must use the
 *              QuoteLineItem FIELD API NAMES (save-mapped ContextInputAttributeName):
 *                NetUnitPrice, NetTotalPrice, TotalPrice, Subtotal, TotalLineAmount
 *              NOT the procedure internal tags (ItemNetTotalPrice / ItemTotalPrice /
 *              ItemSubtotal). Writing the Item* tags returns SUCCESS but nothing persists
 *              (proven SC-3441, log_posthook_v2.txt).
 *
 *              SCOPE / SAFETY: only lines that are ALL of —
 *                ItemSalesTransactionAction == 'Amend'   (amend lines only; excludes New/Renew)
 *                LineItemQuantity > 0                     (excludes cancellation/negative lines)
 *                DerivedPricingAttribute != true          (excludes derived-maintenance; tier net left alone)
 *                NetUnitPrice == 0 / null                 (only seed when the procedure left it 0)
 *                AssetActionSourceNetUnitPrice > 0        (a real asset net to carry)
 *              are written. Everything else is never touched. Currency-safe by construction
 *              (value already in line currency). Never throws out of execute().
 *
 *              REGISTRATION: Apex POST section on the active Procedure Plan
 *              (Fortra_Pricing_PreHook), AFTER the PricingProcedure section (sequence 10).
 *
 * @author Liam Jeong
 * @date June 2026
 * @version 1.0
 */
global class AmendNetSeedPosthook implements RevSignaling.SignalingApexProcessor {

    // Recursion prevention (a context update can re-trigger the pricing engine).
    private static Boolean isProcessing = false;

    // ---- Context tags we READ (node SalesTransactionItem) ----
    @TestVisible private static final String TAG_QUANTITY  = 'LineItemQuantity';
    @TestVisible private static final String TAG_ACTION    = 'ItemSalesTransactionAction';
    @TestVisible private static final String TAG_DERIVED   = 'DerivedPricingAttribute';
    @TestVisible private static final String TAG_NET_UNIT  = 'NetUnitPrice';
    @TestVisible private static final String TAG_ASSET_NET = 'AssetActionSourceNetUnitPrice';

    private static final String ACTION_AMEND = 'Amend';

    // ---- Context attributes we WRITE — QLI FIELD API NAMES (save-mapped) ----
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

    @TestVisible
    private RevSignaling.TransactionResponse process(String contextId) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        if (isProcessing) {
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'AmendNetSeedPosthook skipped - already processing';
            return response;
        }

        try {
            isProcessing = true;

            if (String.isBlank(contextId)) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No context instance id - nothing to seed';
                return response;
            }

            Context.IndustriesContext ctx = new Context.IndustriesContext();

            List<Object> lineNodes = fetchSalesTransactionItems(ctx, contextId);
            if (lineNodes == null || lineNodes.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No SalesTransactionItem nodes - nothing to seed';
                return response;
            }

            List<Map<String, Object>> updates = buildSeedUpdates(lineNodes);
            if (updates.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No amend lines needing a net seed';
                return response;
            }

            Integer submitted = submitContextUpdates(ctx, contextId, updates);

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Seeded net on ' + submitted + ' amend line(s)';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AmendNetSeedPosthook error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            // SUCCESS even on error — never break the whole reprice.
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Amend net-seed posthook completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    // ============================================================
    // CONTEXT FETCH — swallow-and-continue
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
    // SEED BUILD — amend, positive-qty, non-derived, net==0, asset net>0
    // ============================================================
    @TestVisible
    private List<Map<String, Object>> buildSeedUpdates(List<Object> lineNodes) {
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

            String action  = getStringFromTag(tagMap, TAG_ACTION);
            Decimal qty     = getDecimalFromTag(tagMap, TAG_QUANTITY);
            Decimal curNet  = getDecimalFromTag(tagMap, TAG_NET_UNIT);
            Decimal assetNet = getDecimalFromTag(tagMap, TAG_ASSET_NET);
            Boolean isDerived = getBooleanFromTag(tagMap, TAG_DERIVED);

            // GATE: amend line, positive qty, non-derived, proc left net 0, real asset net.
            if (action == null || action != ACTION_AMEND) { continue; }
            if (qty == null || qty <= 0) { continue; }
            if (isDerived == true) { continue; }
            if (curNet != null && curNet != 0) { continue; }
            if (assetNet == null || assetNet <= 0) { continue; }

            Decimal lineTotal = (assetNet * qty).setScale(2, System.RoundingMode.HALF_UP);
            updates.add(buildNodeUpdate(dataPath, assetNet, lineTotal));
        }
        return updates;
    }

    /**
     * @description Build one line's context node-update. nodePath is the line's dataPath
     *              with the FIRST element (the context path) removed, leaving [rootId, lineId]
     *              (matches Salesforce's reference posthook). Writes per-unit net + line total
     *              using the QLI FIELD API NAMES so the engine save persists them.
     */
    @TestVisible
    private Map<String, Object> buildNodeUpdate(List<Object> dataPath, Decimal netUnit, Decimal lineTotal) {
        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }
        List<Object> attributes = new List<Object>{
            attr(ATTR_NET_UNIT_PRICE,    netUnit),
            attr(ATTR_NET_TOTAL_PRICE,   lineTotal),
            attr(ATTR_TOTAL_PRICE,       lineTotal),
            attr(ATTR_SUBTOTAL,          lineTotal),
            attr(ATTR_TOTAL_LINE_AMOUNT, lineTotal)
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
    // SUBMIT — swallow "not in updatable state"
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
                System.debug(LoggingLevel.INFO, 'Context not in updatable state - skipping amend net-seed');
                return 0;
            }
            throw e;
        }
    }

    // ============================================================
    // DATAPATH / TAG HELPERS
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

    @TestVisible
    private String getStringFromTag(Map<String, Object> tagMap, String fieldName) {
        Object val = extractFieldValue(tagMap, fieldName);
        return (val == null) ? null : String.valueOf(val);
    }

    @TestVisible
    private Boolean getBooleanFromTag(Map<String, Object> tagMap, String fieldName) {
        Object val = extractFieldValue(tagMap, fieldName);
        if (val == null) {
            return null;
        }
        if (val instanceof Boolean) {
            return (Boolean) val;
        }
        return 'true'.equalsIgnoreCase(String.valueOf(val));
    }

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
