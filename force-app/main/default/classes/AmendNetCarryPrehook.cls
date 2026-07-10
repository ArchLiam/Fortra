/**
 * @description SC-3501: Amend net-carry prehook. A genuine (non-migrated) amendment line is born with
 *              QuoteLineItem.NetUnitPrice = 0, and no layer carries the prior negotiated net onto it:
 *              the V23 pricing procedure has no SourceAsset read, and Amend is the ONLY lifecycle action
 *              with no Apex net-carry hook (Renew has COLAUpliftPrehook, Cancel has CancelLineCreditPosthook).
 *              This prehook mirrors COLAUpliftPrehook's proven SC-3350 context NetUnitPrice-seed: for Amend
 *              lines whose incoming net is null/<=0, it seeds NetUnitPrice (and UnitPrice) from
 *              QuoteAction.SourceAsset.Price into the pricing context BEFORE the waterfall, so V23
 *              AmendSeedNetUnit = IF(NetUnitPrice>0, NetUnitPrice, InputUnitPrice) preserves it and any
 *              discounts apply on top. It also recomputes the line total (NetTotalPrice cluster) = carried
 *              net x current quantity so a qty change recalculates — superseding the procedure Amend Net
 *              Carry group (AmendSeedNetUnit + AmendSeedNetTotal), whose preserve/seed formulas the prehook
 *              now owns authoritatively (the procedure steps remain only as a fallback and no-op on
 *              prehook-stamped lines). Idempotent (unit seeded only when net<=0, total only when stale);
 *              currency-safe (Asset.Price is in
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
     * @description Amend net-carry: for each Amend line, (a) seed NetUnitPrice + UnitPrice from
     *              QuoteAction.SourceAsset.Price when the incoming net is null/<=0, and (b) recompute the
     *              line total (NetTotalPrice cluster) = carried net x CURRENT quantity so a qty change
     *              recalculates. Together these supersede the procedure's Amend Net Carry group.
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
            SELECT Id, NetUnitPrice, NetTotalPrice, Quantity, Fortra_Product_Type__c,
                   QuoteAction.Type, QuoteAction.SourceAsset.Price
            FROM QuoteLineItem
            WHERE Id IN :qliIds
            AND QuoteAction.Type = 'Amend'
            AND (Fortra_Product_Type__c = null OR Fortra_Product_Type__c != 'New Maintenance')
        ]) {
            Decimal priorNet = (qli.QuoteAction != null && qli.QuoteAction.SourceAsset != null)
                ? qli.QuoteAction.SourceAsset.Price
                : null;
            Boolean netUnset = qli.NetUnitPrice == null || qli.NetUnitPrice <= 0;

            // The unit net the line carries after this prehook: keep an already-priced net, else the prior
            // asset net. No prior net to carry (e.g. no SourceAsset) -> leave it to the procedure fallback.
            Decimal carriedNet = netUnset ? priorNet : qli.NetUnitPrice;
            if (carriedNet == null || carriedNet <= 0) {
                continue;
            }

            // (a) Only (re)stamp the unit when it is missing; an already-carried net is preserved.
            Decimal unitSeed = netUnset ? priorNet : null;

            // (b) Recompute the line total = carried net x CURRENT quantity (the standard-line invariant
            // that feeds ItemNetTotalPrice). AmendSeedNetTotal preserves a stale total on a qty change, so
            // stamp the qty-correct total here — only when it actually differs, to keep unchanged-qty
            // reprices idempotent.
            Decimal qty = qli.Quantity == null ? 0 : qli.Quantity;
            Decimal expectedTotal = (carriedNet * qty).setScale(2, System.RoundingMode.HALF_UP);
            Boolean totalStale = qty > 0 &&
                (qli.NetTotalPrice == null || (qli.NetTotalPrice - expectedTotal).abs() > 0.005);
            Decimal totalSeed = totalStale ? expectedTotal : null;

            if (unitSeed != null || totalSeed != null) {
                Map<String, Object> upd = buildAmendSeedUpdate(qliIdToWrapper.get(qli.Id), unitSeed, totalSeed);
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
     * @description Unit-only overload (original signature): seeds NetUnitPrice + UnitPrice from the carried
     *              net. Retained for seed-only callers/tests; delegates to the full builder with no total.
     */
    @TestVisible
    private Map<String, Object> buildAmendSeedUpdate(Map<String, Object> itemWrapper, Decimal priorNet) {
        return buildAmendSeedUpdate(itemWrapper, priorNet, null);
    }

    /**
     * @description Build one context-update entry for an amend line. Seeds the per-unit net
     *              (NetUnitPrice + UnitPrice -> InputUnitPrice) when unitNet is given, and/or the line total
     *              (NetTotalPrice + TotalPrice + Subtotal + TotalLineAmount) when lineTotal is given — the
     *              same four-attribute total cluster used by DerivedMaintenancePayloadBuilder /
     *              PartnerNetPricePosthook / RenewalMaintenancePricingService. TotalLineAmount is also the
     *              AmendSeedNetTotal fallback branch, so the seed survives whichever branch that step takes.
     *              This is what makes the prehook the authoritative amend net-carry, superseding the
     *              procedure's AmendSeedNetUnit / AmendSeedNetTotal.
     */
    @TestVisible
    private Map<String, Object> buildAmendSeedUpdate(Map<String, Object> itemWrapper, Decimal unitNet, Decimal lineTotal) {
        if (itemWrapper == null) {
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
        List<Map<String, Object>> attributes = new List<Map<String, Object>>();
        if (unitNet != null && unitNet > 0) {
            Decimal net = unitNet.setScale(2, System.RoundingMode.HALF_UP);
            attributes.add(new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => net });
            attributes.add(new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => net });
        }
        if (lineTotal != null && lineTotal > 0) {
            Decimal total = lineTotal.setScale(2, System.RoundingMode.HALF_UP);
            attributes.add(new Map<String, Object>{ 'attributeName' => 'NetTotalPrice', 'attributeValue' => total });
            attributes.add(new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => total });
            attributes.add(new Map<String, Object>{ 'attributeName' => 'Subtotal', 'attributeValue' => total });
            attributes.add(new Map<String, Object>{ 'attributeName' => 'TotalLineAmount', 'attributeValue' => total });
        }
        if (attributes.isEmpty()) {
            return null;
        }
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
