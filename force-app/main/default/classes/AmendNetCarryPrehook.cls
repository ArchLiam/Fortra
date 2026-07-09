/**
 * @description SC-3501: Amend net-carry prehook. A genuine (non-migrated) amendment line is born with
 *              QuoteLineItem.NetUnitPrice = 0, and no layer carries the prior negotiated net onto it:
 *              the V23 pricing procedure has no SourceAsset read, and Amend is the ONLY lifecycle action
 *              with no Apex net-carry hook (Renew has COLAUpliftPrehook, Cancel has CancelLineCreditPosthook).
 *              This prehook mirrors COLAUpliftPrehook's proven SC-3350 context NetUnitPrice-seed: for Amend
 *              lines whose incoming net is null/<=0, it seeds NetUnitPrice (and UnitPrice) from
 *              QuoteAction.SourceAsset.Price into the pricing context BEFORE the waterfall, so V23
 *              AmendSeedNetUnit = IF(NetUnitPrice>0, NetUnitPrice, InputUnitPrice) preserves it and any
 *              discounts apply on top. Idempotent (seeds only when net<=0); currency-safe (Asset.Price is in
 *              line currency); Quote-scoped (skips Order transactions, whose SourceAsset carry is on the
 *              Order side). Registered via ProcedurePlanOption (PrimaryObject=Quote) like the sibling hooks.
 */
global class AmendNetCarryPrehook implements RevSignaling.SignalingApexProcessor {

    private static Boolean isProcessing = false;

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        if (isProcessing) {
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Amend net-carry skipped - already processing';
            return response;
        }

        try {
            isProcessing = true;
            String ctxInstanceId = request != null ? request.ctxInstanceId : null;

            if (String.isBlank(ctxInstanceId)) {
                response.status = RevSignaling.TransactionStatus.FAILED;
                response.message = 'Context instance ID is required';
                return response;
            }

            // Quote-scoped: the SourceAsset carry attributes are mapped on the Quote side only.
            if (isOrderTransaction(ctxInstanceId)) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'Amend net-carry skipped - Order transaction';
                return response;
            }

            Integer seeded = seedAmendNets(ctxInstanceId);
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Amend net-carry seeded ' + seeded + ' line(s)';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AmendNetCarryPrehook error: ' + e.getMessage());
            // D-18: surface the swallowed degrade (fire-and-forget; never throws; status unchanged).
            PricingHookLogger.logPrehook('AmendNetCarryPrehook', request != null ? request.ctxInstanceId : null, e);
            // Return SUCCESS even on error to avoid blocking pricing.
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Amend net-carry completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    /**
     * @description For each Amend line with net null/<=0, seed NetUnitPrice + UnitPrice from
     *              QuoteAction.SourceAsset.Price into the pricing context.
     */
    @TestVisible
    private Integer seedAmendNets(String ctxInstanceId) {
        Context.IndustriesContext ctx = new Context.IndustriesContext();
        List<Object> rawLineItems = queryContextItems(ctx, ctxInstanceId);
        if (rawLineItems.isEmpty()) {
            return 0;
        }

        // Map QLI Id -> context item wrapper (the QLI Id is the last dataPath element).
        Set<Id> qliIds = new Set<Id>();
        Map<Id, Map<String, Object>> qliIdToWrapper = new Map<Id, Map<String, Object>>();
        for (Object rawItem : rawLineItems) {
            Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;
            Object dpObj = itemWrapper.get('dataPath');
            if (dpObj instanceof List<Object>) {
                List<Object> dp = (List<Object>) dpObj;
                if (!dp.isEmpty()) {
                    try {
                        Id qliId = Id.valueOf(String.valueOf(dp.get(dp.size() - 1)));
                        qliIds.add(qliId);
                        qliIdToWrapper.put(qliId, itemWrapper);
                    } catch (Exception ignore) {
                        // Not a valid QLI Id — skip.
                    }
                }
            }
        }
        if (qliIds.isEmpty()) {
            return 0;
        }

        // New Maintenance amend lines are owned by the derived-maintenance pricing path (SC-3346):
        // a flat prior-net carry there is both overridden by the derive steps and would collide with
        // that fix, so they are excluded. Software lines are seeded but the subscription pricing steps
        // (unconditional, not ItemPricingSource-gated) recompute the net after this prehook — carrying
        // those to completion needs a procedure-level gate (tracked separately), not a class change.
        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        for (QuoteLineItem qli : [
            SELECT Id, NetUnitPrice, Fortra_Product_Type__c, QuoteAction.Type, QuoteAction.SourceAsset.Price
            FROM QuoteLineItem
            WHERE Id IN :qliIds
            AND QuoteAction.Type = 'Amend'
            AND (Fortra_Product_Type__c = null OR Fortra_Product_Type__c != 'New Maintenance')
        ]) {
            Decimal priorNet = (qli.QuoteAction != null && qli.QuoteAction.SourceAsset != null)
                ? qli.QuoteAction.SourceAsset.Price
                : null;
            Boolean netUnset = qli.NetUnitPrice == null || qli.NetUnitPrice <= 0;
            if (netUnset && priorNet != null && priorNet > 0) {
                Map<String, Object> upd = buildAmendSeedUpdate(qliIdToWrapper.get(qli.Id), priorNet);
                if (upd != null) {
                    updates.add(upd);
                }
            }
        }

        if (!updates.isEmpty()) {
            submitContextUpdates(ctx, ctxInstanceId, updates);
        }
        return updates.size();
    }

    /**
     * @description Context-update entry (mirrors COLAUpliftCalculator.buildNetUnitPriceUpdate shape),
     *              seeding both NetUnitPrice and UnitPrice (→ InputUnitPrice) so V23 AmendSeedNetUnit
     *              carries the prior net whichever branch it reads.
     */
    @TestVisible
    private Map<String, Object> buildAmendSeedUpdate(Map<String, Object> itemWrapper, Decimal priorNet) {
        if (itemWrapper == null || priorNet == null || priorNet <= 0) {
            return null;
        }
        Object dpObj = itemWrapper.get('dataPath');
        if (!(dpObj instanceof List<Object>)) {
            return null;
        }
        List<Object> updatePath = ((List<Object>) dpObj).clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }
        Decimal net = priorNet.setScale(2, System.RoundingMode.HALF_UP);
        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => net },
            new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => net }
        };
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    private List<Object> queryContextItems(Context.IndustriesContext ctx, String ctxInstanceId) {
        try {
            Map<String, Object> apiResponse = ctx.queryTags(new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            });
            Map<String, Object> queryResult = extractQueryResult(apiResponse);
            if (queryResult == null || !queryResult.containsKey('SalesTransactionItem')) {
                return new List<Object>();
            }
            Object itemsObj = queryResult.get('SalesTransactionItem');
            return (itemsObj instanceof List<Object>) ? (List<Object>) itemsObj : new List<Object>{ itemsObj };
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AmendNetCarryPrehook.queryContextItems failed: ' + e.getMessage());
            return new List<Object>();
        }
    }

    @TestVisible
    private Map<String, Object> extractQueryResult(Map<String, Object> apiResponse) {
        if (apiResponse == null) {
            return null;
        }
        if (apiResponse.containsKey('queryResult') && apiResponse.get('queryResult') instanceof Map<String, Object>) {
            return (Map<String, Object>) apiResponse.get('queryResult');
        }
        if (apiResponse.containsKey('SalesTransactionItem')) {
            return apiResponse;
        }
        return null;
    }

    private void submitContextUpdates(Context.IndustriesContext ctx, String ctxInstanceId, List<Map<String, Object>> updates) {
        try {
            ctx.updateContextAttributes(new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'nodePathAndAttributes' => updates
            });
        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().containsIgnoreCase('not in updatable state')) {
                System.debug(LoggingLevel.INFO, 'AmendNetCarryPrehook: context not in updatable state - skipping updates');
            } else {
                System.debug(LoggingLevel.ERROR, 'AmendNetCarryPrehook.submitContextUpdates error: ' + e.getMessage());
            }
        }
    }

    private Boolean isOrderTransaction(String ctxInstanceId) {
        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();
            List<Object> items = queryContextItems(ctx, ctxInstanceId);
            if (items.isEmpty()) {
                return false;
            }
            Map<String, Object> firstItem = (Map<String, Object>) items.get(0);
            Object dpObj = firstItem.get('dataPath');
            if (!(dpObj instanceof List<Object>)) {
                return false;
            }
            List<Object> dp = (List<Object>) dpObj;
            if (dp.isEmpty()) {
                return false;
            }
            String rootId = String.valueOf(dp.get(0));
            return rootId != null && rootId.startsWith('801');
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AmendNetCarryPrehook.isOrderTransaction failed — assuming Quote: ' + e.getMessage());
            return false;
        }
    }
}
