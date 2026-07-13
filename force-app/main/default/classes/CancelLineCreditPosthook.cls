/**
 * @description RevSignaling pricing posthook that writes a negative credit onto
 *              cancellation (negative-quantity) Quote/Order lines after the pricing
 *              procedure runs. The pricing engine prices such lines at $0 rather than a
 *              negative credit, and the line net/total fields are engine-only (not writable
 *              by trigger or flow), so the credit is applied through the context update API
 *              in a posthook. The per-unit net comes from the staged context attribute
 *              CancelNetUnitPrice__c when populated, otherwise it is self-resolved from the
 *              source asset's original net (currency-matched, positive) with the line list
 *              price as a last resort, and credit = net * quantity is written to
 *              NetUnitPrice, NetTotalPrice, TotalPrice, Subtotal, and TotalLineAmount. Only
 *              negative-quantity lines that resolve a positive per-unit net are touched, a
 *              foreign-currency asset net is never applied, and any error is downgraded to
 *              success so the whole reprice is never broken. Acts as a thin adapter that owns
 *              the context fetch, the read-only asset-net SOQL, and the context submit, and
 *              delegates the pure credit math and node shaping to CancelLineCreditCalculator.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
global class CancelLineCreditPosthook implements RevSignaling.SignalingApexProcessor {

    // Recursion prevention (a context update can re-trigger the pricing engine).
    private static Boolean isProcessing = false;

    /**
     * Pure cancellation/credit math + node shaping, extracted verbatim (Wave-2).
     * ONE instance per hook execution — mirrors the old per-execute instance state
     * (the Generate-lock set inside the calculator must not leak between reprices).
     */
    @TestVisible
    private CancelLineCreditCalculator calc = new CancelLineCreditCalculator();

    // ============================================================
    // ENTRY POINT
    // ============================================================

    /**
     * @description Entry point invoked by the RevSignaling pricing engine; forwards the
     *              request's context instance id to the unit-testable core logic.
     * @param request The signaling transaction request carrying the context instance id.
     * @return The transaction response reporting how many cancellation lines were credited.
     */
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        return process(request != null ? request.ctxInstanceId : null);
    }

    /**
     * @description Core logic, split out by contextId so it is unit-testable without a
     *              RevSignaling.TransactionRequest (which has no public constructor). Reads
     *              the line nodes, resolves asset nets for unseeded cancel lines, builds the
     *              credit updates, and submits them, guarding against re-entrancy and
     *              downgrading any error to success.
     * @param contextId The runtime pricing context instance id to credit.
     * @return The transaction response describing the outcome and lines credited.
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

            // Step 2 — resolve the original asset NET for every negative-qty line whose
            //          context CancelNetUnitPrice__c is null/<=0 (real UI cancellations).
            //          Bulk, read-only SOQL; empty when every line is already seeded.
            Map<Id, Decimal> resolvedNetByLine = resolveAssetNetsForUnseededLines(lineNodes);

            // Step 3 — build the credit updates for negative-qty lines. The staged context
            //          value wins; otherwise the self-resolved asset NET is used. Positive
            //          / zero-qty lines and lines with no resolvable net are never touched.
            List<Map<String, Object>> updates = buildCreditUpdates(lineNodes, resolvedNetByLine);
            if (updates.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No cancellation (negative-qty) lines with a resolvable net - nothing to credit';
                return response;
            }

            // Step 4 — submit.
            Integer submitted = submitContextUpdates(ctx, contextId, updates);

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Credited ' + submitted + ' cancellation line(s)';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CancelLineCreditPosthook error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            // D-18: surface the swallowed degrade (fire-and-forget; never throws; status unchanged).
            PricingHookLogger.logPosthook('CancelLineCreditPosthook', contextId, e);
            // SUCCESS even on error — never break the whole reprice.
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Cancel-credit posthook completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    // ============================================================
    // CONTEXT FETCH — swallow-and-continue, mirrors the prehook (STAYS: context API)
    // ============================================================

    /**
     * @description Read the SalesTransactionItem line nodes from the runtime context via
     *              queryTags; swallows any error and returns null so the reprice continues.
     * @param ctx The industries context used to query the pricing context.
     * @param contextId The runtime pricing context instance id to query.
     * @return The parsed line nodes, or null if the query fails.
     */
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

    // ============================================================
    // ASSET-NET SELF-RESOLUTION (v2.1) — SOQL orchestration STAYS here.
    // The pure gather/scope/pick seams delegate to CancelLineCreditCalculator.
    // ============================================================

    /**
     * @description For every negative-qty line whose staged context CancelNetUnitPrice__c
     *              is null/<=0, resolve the original asset NET so the posthook can credit
     *              it with no upstream seeder. Constant SOQL: one line->asset query for the
     *              scope + one AssetActionSource query. Returns line Id -> per-unit NET
     *              (> 0); empty when nothing needs resolving. READ-ONLY — safe under the
     *              RLM Quote/Order DML lock (SOQL, no DML).
     * @param lineNodes The SalesTransactionItem line nodes read from the context.
     * @return A map of line Id to resolved positive per-unit net; empty when nothing needs resolving.
     */
    @TestVisible
    private Map<Id, Decimal> resolveAssetNetsForUnseededLines(List<Object> lineNodes) {
        Map<Id, Decimal> netByLine = new Map<Id, Decimal>();
        List<PendingLine> pending = collectUnseededCancelLines(lineNodes);
        if (pending.isEmpty()) {
            return netByLine;
        }
        String scope = resolveScope(lineNodes);
        if (scope == null) {
            return netByLine;
        }
        Set<Id> lineIds = new Set<Id>();
        for (PendingLine pl : pending) {
            lineIds.add(pl.lineId);
        }
        Map<Id, Id> lineToAssetId = resolveSourceAssetIds(scope, lineIds);
        Map<Id, Map<String, Decimal>> assetNetByCurrency =
            resolveAssetNetByCurrency(new Set<Id>(lineToAssetId.values()));

        Decimal net;
        for (PendingLine pl : pending) {
            net = resolveSeedNet(lineToAssetId.get(pl.lineId), pl.currencyIso, pl.listPrice, assetNetByCurrency);
            if (net != null && net > 0) {
                netByLine.put(pl.lineId, net);
            }
        }
        return netByLine;
    }

    /**
     * @description Resolve each cancel line's source asset Id. ORDER lines via
     *              OrderItem.OrderAction.SourceAssetId; QUOTE lines via
     *              QuoteLineItem.QuoteAction.SourceAssetId. ONE SOQL for the scope,
     *              null-safe at every hop. (STAYS: SOQL.)
     * @param scope The line scope, either 'Order' or 'Quote'.
     * @param lineIds The set of cancel-line Ids to resolve source assets for.
     * @return A map of line Id to its source asset Id; empty when none resolve.
     */
    @TestVisible
    private Map<Id, Id> resolveSourceAssetIds(String scope, Set<Id> lineIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (String.isBlank(scope) || lineIds == null || lineIds.isEmpty()) {
            return result;
        }
        if (scope == 'Order') {
            for (OrderItem oi : [
                SELECT Id, OrderAction.SourceAssetId
                FROM OrderItem
                WHERE Id IN :lineIds
            ]) {
                if (oi.OrderAction != null && oi.OrderAction.SourceAssetId != null) {
                    result.put(oi.Id, oi.OrderAction.SourceAssetId);
                }
            }
        } else if (scope == 'Quote') {
            for (QuoteLineItem qli : [
                SELECT Id, QuoteAction.SourceAssetId
                FROM QuoteLineItem
                WHERE Id IN :lineIds
            ]) {
                if (qli.QuoteAction != null && qli.QuoteAction.SourceAssetId != null) {
                    result.put(qli.Id, qli.QuoteAction.SourceAssetId);
                }
            }
        }
        return result;
    }

    /**
     * @description Resolve the asset NET per source asset, keyed by currency so a non-USD
     *              line never inherits a USD net. ONE SOQL for ALL assets, positive nets
     *              only. A Generate / Initial-Sale row wins; else the most-recent priced
     *              row (rows folded oldest -> newest). (Currency-blindness guard.)
     *              (STAYS: SOQL; the per-row fold delegates to the calculator.)
     * @param assetIds The source asset Ids to resolve nets for.
     * @return A map of asset Id to a currency-keyed map of positive per-unit net.
     */
    @TestVisible
    private Map<Id, Map<String, Decimal>> resolveAssetNetByCurrency(Set<Id> assetIds) {
        Map<Id, Map<String, Decimal>> netByCurrency = new Map<Id, Map<String, Decimal>>();
        Set<Id> cleanIds = new Set<Id>();
        if (assetIds != null) {
            for (Id a : assetIds) {
                if (a != null) {
                    cleanIds.add(a);
                }
            }
        }
        if (cleanIds.isEmpty()) {
            return netByCurrency;
        }
        for (AssetActionSource s : [
            SELECT AssetAction.AssetId, AssetAction.Type, NetUnitPrice, CurrencyIsoCode, CreatedDate
            FROM AssetActionSource
            WHERE AssetAction.AssetId IN :cleanIds
              AND NetUnitPrice > 0
            ORDER BY CreatedDate ASC
        ]) {
            applyAssetNetSource(netByCurrency, s);
        }
        return netByCurrency;
    }

    // ============================================================
    // SUBMIT — swallow "not in updatable state", mirrors the prehook (STAYS: context API)
    // ============================================================

    /**
     * @description Submit the built credit updates to the context via updateContextAttributes;
     *              swallows the "not in updatable state" path (returns 0) and rethrows any
     *              other error to the caller's outer swallow.
     * @param ctx The industries context used to submit the updates.
     * @param contextId The runtime pricing context instance id to update.
     * @param updates The node-path-and-attribute update payloads to apply.
     * @return The number of updates submitted, or 0 when there is nothing to submit or the context is not updatable.
     */
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
    // DELEGATING SEAMS — thin adapters over CancelLineCreditCalculator.
    // Signatures + @TestVisible preserved verbatim so call sites (incl. the hook's own
    // test) are unchanged; all real logic lives in the calculator.
    // ============================================================

    /**
     * @description Extract the line nodes from a queryTags API response; delegates to the calculator.
     * @param apiResponse The raw queryTags response map.
     * @return The list of line node objects parsed from the response.
     */
    @TestVisible
    private List<Object> parseLineNodes(Map<String, Object> apiResponse) {
        return calc.parseLineNodes(apiResponse);
    }

    /**
     * @description Build the credit updates using only staged context nets (no pre-resolved
     *              asset nets); used for already-seeded lines and pure-seam tests. Delegates
     *              to the calculator.
     * @param lineNodes The SalesTransactionItem line nodes to build updates from.
     * @return The list of node-path-and-attribute update payloads for cancellation lines.
     */
    @TestVisible
    private List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes) {
        return calc.buildCreditUpdates(lineNodes);
    }

    /**
     * @description Build the credit updates for negative-qty lines, preferring the staged
     *              context net and falling back to the self-resolved asset net. Delegates to
     *              the calculator.
     * @param lineNodes The SalesTransactionItem line nodes to build updates from.
     * @param resolvedNetByLine A map of line Id to self-resolved per-unit net for unseeded lines.
     * @return The list of node-path-and-attribute update payloads for cancellation lines.
     */
    @TestVisible
    private List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes, Map<Id, Decimal> resolvedNetByLine) {
        return calc.buildCreditUpdates(lineNodes, resolvedNetByLine);
    }

    /**
     * @description Shape a single node update payload from a line's data path, per-unit net,
     *              and total credit. Delegates to the calculator.
     * @param dataPath The context node data path identifying the line.
     * @param cancelNet The positive per-unit net to write as NetUnitPrice.
     * @param credit The negative line credit to write to the total fields.
     * @return The node-path-and-attribute update payload for the line.
     */
    @TestVisible
    private Map<String, Object> buildNodeUpdate(List<Object> dataPath, Decimal cancelNet, Decimal credit) {
        return calc.buildNodeUpdate(dataPath, cancelNet, credit);
    }

    /**
     * @description Collect the negative-qty, un-staged cancel lines needing asset-net
     *              resolution. Delegates the pure gather to the calculator and maps the
     *              result back to the hook-local PendingLine so the @TestVisible seam
     *              (CancelLineCreditPosthook.PendingLine) is unchanged.
     * @param lineNodes The SalesTransactionItem line nodes to scan.
     * @return The hook-local PendingLine carriers for negative-qty, unstaged cancel lines.
     */
    @TestVisible
    private List<PendingLine> collectUnseededCancelLines(List<Object> lineNodes) {
        List<PendingLine> out = new List<PendingLine>();
        PendingLine hookPl;
        for (CancelLineCreditCalculator.PendingLine p : calc.collectUnseededCancelLines(lineNodes)) {
            hookPl = new PendingLine();
            hookPl.lineId = p.lineId;
            hookPl.currencyIso = p.currencyIso;
            hookPl.listPrice = p.listPrice;
            out.add(hookPl);
        }
        return out;
    }

    /**
     * @description Determine whether the line nodes are Order or Quote scoped. Delegates to the calculator.
     * @param lineNodes The SalesTransactionItem line nodes to inspect.
     * @return 'Order', 'Quote', or null when the scope cannot be determined.
     */
    @TestVisible
    private String resolveScope(List<Object> lineNodes) {
        return calc.resolveScope(lineNodes);
    }

    /**
     * @description Fold one AssetActionSource row into the asset/currency net map, letting a
     *              Generate / Initial-Sale row win over later priced rows. Delegates to the calculator.
     * @param netByCurrency The asset-to-currency-keyed net map being accumulated.
     * @param s The AssetActionSource row to fold in.
     */
    @TestVisible
    private void applyAssetNetSource(Map<Id, Map<String, Decimal>> netByCurrency, AssetActionSource s) {
        calc.applyAssetNetSource(netByCurrency, s);
    }

    /**
     * @description Pick the per-unit seed net for a cancel line: the currency-matched asset
     *              net when available, otherwise the line list price as a last resort.
     *              Delegates to the calculator.
     * @param assetId The source asset Id for the line, may be null.
     * @param lineCurrency The line's currency iso code used to currency-match the asset net.
     * @param listPrice The line list price used as a last-resort fallback.
     * @param assetNetByCurrency The asset-to-currency-keyed net map to look up.
     * @return The resolved positive per-unit net, or null when none can be determined.
     */
    @TestVisible
    private Decimal resolveSeedNet(Id assetId, String lineCurrency, Decimal listPrice,
                                   Map<Id, Map<String, Decimal>> assetNetByCurrency) {
        return calc.resolveSeedNet(assetId, lineCurrency, listPrice, assetNetByCurrency);
    }

    /**
     * @description Extract the line record Id from a context node data path. Delegates to the calculator.
     * @param dataPath The context node data path to read the line Id from.
     * @return The line record Id, or null when it cannot be resolved.
     */
    @TestVisible
    private Id lineIdFromDataPath(List<Object> dataPath) {
        return calc.lineIdFromDataPath(dataPath);
    }

    /**
     * @description Read a String field from a context tag map. Delegates to the calculator.
     * @param tagMap The context tag map to read from.
     * @param fieldName The field name to read.
     * @return The field value as a String, or null when absent.
     */
    @TestVisible
    private String getStringFromTag(Map<String, Object> tagMap, String fieldName) {
        return calc.getStringFromTag(tagMap, fieldName);
    }

    /**
     * @description Read a Decimal field from a context tag map. Delegates to the calculator.
     * @param tagMap The context tag map to read from.
     * @param fieldName The field name to read.
     * @return The field value as a Decimal, or null when absent.
     */
    @TestVisible
    private Decimal getDecimalFromTag(Map<String, Object> tagMap, String fieldName) {
        return calc.getDecimalFromTag(tagMap, fieldName);
    }

    // ============================================================
    // DTO — retained hook-local so the CancelLineCreditPosthook.PendingLine @TestVisible
    // seam is unchanged; the calculator owns the canonical carrier it maps from.
    // ============================================================

    /** Per-cancel-line carrier for lines that need asset-net resolution. */
    @TestVisible
    private class PendingLine {
        public Id lineId;
        public String currencyIso;
        public Decimal listPrice;
    }
}