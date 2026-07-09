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
 *              VALUE SOURCE (two-tier, self-contained as of v2.1 — needs NO seed prehook
 *              and NO manual staging):
 *                1. PREFERRED — the context staging attribute CancelNetUnitPrice__c when it
 *                   is already populated (fixture-seeded lines / any upstream seeder).
 *                2. FALLBACK — when CancelNetUnitPrice__c is null/<=0 (EVERY real,
 *                   UI-created cancellation: nothing seeds it, since the CancelLineNetSeed-
 *                   Prehook branch was abandoned), the hook resolves the source asset's
 *                   original NET itself: QuoteAction/OrderAction.SourceAssetId ->
 *                   AssetActionSource.NetUnitPrice (Generate / Initial-Sale, currency-
 *                   matched, > 0), with a LOSSY line-ListPrice last resort.
 *              We deliberately do NOT read QuoteLineDetail: verified live in FortraUAT
 *              2026-06-26/27 our QLD is 0 (NetUnitPrice/TotalPrice/TotalLineAmount all 0),
 *              so there is no negative on the detail to copy. credit = resolvedNet * qty.
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
 *              SCOPE / SAFETY: only NEGATIVE-quantity lines that resolve a positive
 *              per-unit net (staged OR asset-resolved) are touched. Positive/zero-qty lines
 *              and lines with no resolvable net are never written. Currency-safe: a foreign-
 *              currency asset net is never seeded onto a line (SC-3384 guard). The self-
 *              resolution adds at most two READ-ONLY SOQL queries (line->asset,
 *              AssetActionSource) and only when an unseeded cancel line is present.
 *
 *              SWALLOW CONTRACT: never throws out of execute() in a way that breaks the
 *              reprice; outer try/catch downgrades any error to SUCCESS-with-warnings,
 *              and submitContextUpdates swallows the "not in updatable state" path.
 *
 *              REGISTRATION: POST section on the active Procedure Plan
 *              (Fortra_Pricing_PreHook), AFTER the PricingProcedure section.
 *
 *              WAVE-2 DECOMPOSITION (behavior-preserving): all PURE cancellation/credit
 *              math + context-node shaping was extracted VERBATIM into
 *              CancelLineCreditCalculator. This class is now a thin adapter — it owns the
 *              context fetch (queryTags), the read-only asset-net SOQL, and the context
 *              submit (updateContextAttributes), and delegates the gating/credit/shape
 *              seams to the calculator. Every @TestVisible seam below keeps its original
 *              signature so CancelLineCreditPosthookTest is unaffected.
 *
 * @author Liam Jeong (SC-3441)
 * @date June 2026 (v2.1 2026-07-01: self-resolves asset NET — no seed prehook / no staging;
 *       Wave-2 2026-07-07: pure logic extracted to CancelLineCreditCalculator)
 * @version 2.2
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
     *              row (rows folded oldest -> newest). (SC-3384 currency-blindness guard.)
     *              (STAYS: SOQL; the per-row fold delegates to the calculator.)
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

    @TestVisible
    private List<Object> parseLineNodes(Map<String, Object> apiResponse) {
        return calc.parseLineNodes(apiResponse);
    }

    /** Overload: no pre-resolved asset nets (already-seeded lines / pure-seam tests). */
    @TestVisible
    private List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes) {
        return calc.buildCreditUpdates(lineNodes);
    }

    @TestVisible
    private List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes, Map<Id, Decimal> resolvedNetByLine) {
        return calc.buildCreditUpdates(lineNodes, resolvedNetByLine);
    }

    @TestVisible
    private Map<String, Object> buildNodeUpdate(List<Object> dataPath, Decimal cancelNet, Decimal credit) {
        return calc.buildNodeUpdate(dataPath, cancelNet, credit);
    }

    /**
     * @description Collect the negative-qty, un-staged cancel lines needing asset-net
     *              resolution. Delegates the pure gather to the calculator and maps the
     *              result back to the hook-local PendingLine so the @TestVisible seam
     *              (CancelLineCreditPosthook.PendingLine) is unchanged.
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

    @TestVisible
    private String resolveScope(List<Object> lineNodes) {
        return calc.resolveScope(lineNodes);
    }

    @TestVisible
    private void applyAssetNetSource(Map<Id, Map<String, Decimal>> netByCurrency, AssetActionSource s) {
        calc.applyAssetNetSource(netByCurrency, s);
    }

    @TestVisible
    private Decimal resolveSeedNet(Id assetId, String lineCurrency, Decimal listPrice,
                                   Map<Id, Map<String, Decimal>> assetNetByCurrency) {
        return calc.resolveSeedNet(assetId, lineCurrency, listPrice, assetNetByCurrency);
    }

    @TestVisible
    private Id lineIdFromDataPath(List<Object> dataPath) {
        return calc.lineIdFromDataPath(dataPath);
    }

    @TestVisible
    private String getStringFromTag(Map<String, Object> tagMap, String fieldName) {
        return calc.getStringFromTag(tagMap, fieldName);
    }

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
