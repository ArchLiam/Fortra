/**
 * @description Amend net-carry prehook. A genuine (non-migrated) amendment line is born with
 *              QuoteLineItem.NetUnitPrice = 0, and no layer carries the prior negotiated net onto it:
 *              the pricing procedure has no SourceAsset read, and Amend is the ONLY lifecycle action
 *              with no Apex net-carry hook (Renew has COLAUpliftPrehook, Cancel has CancelLineCreditPosthook).
 *              This prehook mirrors COLAUpliftPrehook's proven context NetUnitPrice-seed: for Amend
 *              lines whose incoming net is null/<=0, it seeds NetUnitPrice (and UnitPrice) with the prior
 *              per-unit net — QuoteAction.SourceAsset.Price / SourceAsset.Quantity, because Asset.Price is
 *              the EXTENDED line total (per-unit x qty) in this org, not the per-unit — into the pricing
 *              context BEFORE the waterfall, so the
 *              procedure's AmendSeedNetUnit step preserves it and any
 *              discounts apply on top. It also recomputes the line total (NetTotalPrice cluster) = carried
 *              net x current quantity so a qty change recalculates — superseding the procedure Amend Net
 *              Carry group (AmendSeedNetUnit + AmendSeedNetTotal), whose preserve/seed formulas the prehook
 *              now owns authoritatively (the procedure steps remain only as a fallback and no-op on
 *              prehook-stamped lines). Idempotent (unit seeded only when net<=0, total only when stale);
 *              currency-safe (Asset.Price is in
 *              line currency); Quote-scoped (skips Order transactions, whose SourceAsset carry is on the
 *              Order side). Registered via ProcedurePlanOption (PrimaryObject=Quote) like the sibling hooks.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
global class AmendNetCarryPrehook implements RevSignaling.SignalingApexProcessor {

    private static Boolean isProcessing = false;

    /**
     * @description Prehook entry point invoked by the RLM signaling framework: seeds the prior negotiated
     *              net onto Amend quote lines before the pricing waterfall. Reentrancy-guarded, Quote-scoped
     *              (skips Order transactions), and non-blocking — always returns SUCCESS even on error.
     * @param request The signaling transaction request carrying the pricing context instance id.
     * @return The transaction response with status and a human-readable message.
     */
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
     * @description Amend net-carry: for each Amend line, (a) seed NetUnitPrice + UnitPrice with the prior
     *              per-unit net (SourceAsset.Price / SourceAsset.Quantity — see AssetNetUnitPrice.perUnit) when the
     *              incoming net is null/<=0, and (b) recompute the
     *              line total (NetTotalPrice cluster) = carried net x CURRENT quantity so a qty change
     *              recalculates. Together these supersede the procedure's Amend Net Carry group.
     * @param ctxInstanceId The pricing context instance id whose Amend lines are seeded.
     * @return The number of context line updates submitted.
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
            SELECT Id, NetUnitPrice, NetTotalPrice, UnitPrice, Subtotal, Quantity, Fortra_Product_Type__c,
                   QuoteAction.Type, QuoteAction.SourceAsset.Price, QuoteAction.SourceAsset.Quantity
            FROM QuoteLineItem
            WHERE Id IN :qliIds
            AND QuoteAction.Type = 'Amend'
            AND (Fortra_Product_Type__c = null OR Fortra_Product_Type__c != 'New Maintenance')
        ]) {
            // Asset.Price is the EXTENDED line total (per-unit x asset qty), NOT the per-unit — verified
            // across the live asset book (EFT 7 Enterprise 273540/10=27354, ARC 2160/100=21.60,
            // EFT 8 Enterprise 82062/3=27354). Recover the per-unit by dividing by the source asset
            // quantity so a multi-quantity asset amends at the correct unit; a qty-1 asset divides by 1
            // (no-op), which is why single-unit source assets never surfaced the 10x inflation.
            Decimal priorNet = (qli.QuoteAction != null && qli.QuoteAction.SourceAsset != null)
                ? AssetNetUnitPrice.perUnit(qli.QuoteAction.SourceAsset.Price, qli.QuoteAction.SourceAsset.Quantity)
                : null;
            Boolean netUnset = qli.NetUnitPrice == null || qli.NetUnitPrice <= 0;

            // The unit net the line carries after this prehook: keep an already-priced net, else the prior
            // asset net. No prior net to carry (e.g. no SourceAsset) -> leave it to the procedure fallback.
            Decimal carriedNet = netUnset ? priorNet : qli.NetUnitPrice;
            if (carriedNet == null || carriedNet <= 0) {
                continue;
            }

            // (a) Seed the unit when the net is missing; ALSO reconcile a stale Sales Price (UnitPrice)
            // that doesn't match the carried per-unit even when the net is already correct. The amend
            // net-carry sets Sales Price = net (buildAmendSeedUpdate writes NetUnitPrice + UnitPrice
            // together), so a line inflated pre-fix — UnitPrice = the Asset.Price total (e.g. 599.90) while
            // NetUnitPrice is already the correct per-unit (59.99) — is corrected here. Re-writing an
            // already-correct net is a no-op, so this stays idempotent once UnitPrice matches.
            Boolean unitStale = qli.UnitPrice == null || (qli.UnitPrice - carriedNet).abs() > 0.005;
            Decimal unitSeed = (netUnset || unitStale) ? carriedNet : null;

            // (b) Recompute the line total = carried net x CURRENT quantity (the standard-line invariant
            // that feeds ItemNetTotalPrice), stamping the whole cluster (NetTotalPrice + TotalPrice +
            // Subtotal + TotalLineAmount) when EITHER the net total OR the Subtotal is stale. Subtotal rolls
            // up from the (pre-fix) Sales Price, so it can still read the inflated total (e.g. 599.90) even
            // when NetTotalPrice is already correct (59.99) — include it in the guard so it heals. Stamped
            // only when actually different, so unchanged-qty reprices stay idempotent.
            Decimal qty = qli.Quantity == null ? 0 : qli.Quantity;
            Decimal expectedTotal = (carriedNet * qty).setScale(2, System.RoundingMode.HALF_UP);
            Boolean totalStale = qty > 0 &&
                (qli.NetTotalPrice == null || (qli.NetTotalPrice - expectedTotal).abs() > 0.005
                 || qli.Subtotal == null || (qli.Subtotal - expectedTotal).abs() > 0.005);
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
     * @param itemWrapper The context line item wrapper carrying the dataPath to update.
     * @param priorNet The per-unit net to seed onto the line.
     * @return The context-update entry, or null when there is nothing to update.
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
     * @param itemWrapper The context line item wrapper carrying the dataPath to update.
     * @param unitNet The per-unit net to seed (NetUnitPrice + UnitPrice); skipped when null/<=0.
     * @param lineTotal The line total to seed across the four-attribute total cluster; skipped when null/<=0.
     * @return The context-update entry, or null when there is nothing to update.
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

    /**
     * @description Queries the pricing context for its SalesTransactionItem tags and returns the raw line
     *              item wrappers; returns an empty list on any failure.
     * @param ctx The industries context accessor used to query the context store.
     * @param ctxInstanceId The pricing context instance id to query.
     * @return The list of raw context line item wrappers, or an empty list.
     */
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

    /**
     * @description Normalizes the queryTags API response into the queryResult map, tolerating both the
     *              wrapped ('queryResult') and flattened ('SalesTransactionItem') response shapes.
     * @param apiResponse The raw response map returned by Context.queryTags.
     * @return The query result map, or null when neither known shape is present.
     */
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

    /**
     * @description Submits the assembled node-path attribute updates back to the pricing context; silently
     *              tolerates the 'not in updatable state' condition and logs other failures.
     * @param ctx The industries context accessor used to update the context store.
     * @param ctxInstanceId The pricing context instance id to update.
     * @param updates The node-path/attribute update entries to apply.
     */
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

    /**
     * @description Determines whether the pricing context is an Order transaction by inspecting the root
     *              data-path id prefix (801 = Order); defaults to Quote (false) on any failure.
     * @param ctxInstanceId The pricing context instance id to inspect.
     * @return True when the context root is an Order, false otherwise.
     */
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