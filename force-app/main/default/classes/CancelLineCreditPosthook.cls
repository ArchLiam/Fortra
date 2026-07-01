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
 * @author Liam Jeong (SC-3441)
 * @date June 2026 (v2.1 2026-07-01: self-resolves asset NET — no seed prehook / no staging)
 * @version 2.1
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
    // SELF-RESOLUTION TAGS / ANCHORS (v2.1) — used ONLY when the staged
    // CancelNetUnitPrice__c is absent (real UI-created cancellations).
    // ============================================================

    /** Per-line transaction currency tag (currency-aware asset-net match). */
    @TestVisible private static final String TAG_CURRENCY = 'STICurrencyIsoCode';

    /** Per-line catalog list price tag (LOSSY last-resort fallback only). */
    @TestVisible private static final String TAG_LIST_PRICE = 'ListPrice';

    /** Asset action types that anchor the priced original-sale net (most-preferred). */
    @TestVisible private static final Set<String> PRICED_SALE_TYPES = new Set<String>{ 'Generate' };

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
    // CREDIT BUILD — pure seam, negative-qty lines; staged net OR resolved asset net
    // ============================================================

    /** Overload: no pre-resolved asset nets (already-seeded lines / pure-seam tests). */
    @TestVisible
    private List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes) {
        return buildCreditUpdates(lineNodes, new Map<Id, Decimal>());
    }

    /**
     * @description Build the context node updates for every cancellation line. A line
     *              qualifies iff LineItemQuantity < 0 AND a positive per-unit net is
     *              available — the staged context CancelNetUnitPrice__c (preferred), or,
     *              when that is null/<=0, the self-resolved asset NET in resolvedNetByLine
     *              (keyed by line Id). The credit written is net * qty (negative).
     *              Positive/zero-qty lines and lines with no net are skipped (no write).
     */
    @TestVisible
    private List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes, Map<Id, Decimal> resolvedNetByLine) {
        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        if (lineNodes == null) {
            return updates;
        }
        Map<Id, Decimal> resolved = resolvedNetByLine == null ? new Map<Id, Decimal>() : resolvedNetByLine;
        Map<String, Object> node;
        Map<String, Object> tagMap;
        List<Object> dataPath;
        Decimal qty;
        Decimal cancelNet;
        Id lineId;
        Decimal credit;
        for (Object raw : lineNodes) {
            if (!(raw instanceof Map<String, Object>)) {
                continue;
            }
            node = (Map<String, Object>) raw;
            tagMap = extractTagMap(node);
            dataPath = getDataPath(node);
            if (dataPath == null || dataPath.isEmpty()) {
                continue;
            }

            // GATE 1: negative qty only. Null/zero/positive => skip (never touch a normal line).
            qty = getDecimalFromTag(tagMap, TAG_QUANTITY);
            if (qty == null || qty >= 0) {
                continue;
            }

            // Per-unit net: the staged context value wins; else the self-resolved asset NET.
            cancelNet = getDecimalFromTag(tagMap, TAG_CANCEL_NET);
            if (cancelNet == null || cancelNet <= 0) {
                lineId = lineIdFromDataPath(dataPath);
                cancelNet = lineId == null ? null : resolved.get(lineId);
            }
            // GATE 2: still no positive net (no asset source / zero-net asset) => skip.
            if (cancelNet == null || cancelNet <= 0) {
                continue;
            }

            credit = (cancelNet * qty).setScale(2, System.RoundingMode.HALF_UP);
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
    // ASSET-NET SELF-RESOLUTION (v2.1) — lets the posthook stand alone
    // (no seed prehook, no manual staging). Bulk, read-only, currency-aware.
    // Mirrors the resolution proven on the abandoned CancelLineNetSeedPrehook.
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
     * @description Pure seam: collect the negative-qty lines that carry NO usable staged
     *              net (context CancelNetUnitPrice__c null/<=0) and therefore need asset-net
     *              resolution. Positive/zero-qty and already-seeded lines are excluded (they
     *              need no SOQL). Captures the line's currency + ListPrice tags for the
     *              currency-aware pick.
     */
    @TestVisible
    private List<PendingLine> collectUnseededCancelLines(List<Object> lineNodes) {
        List<PendingLine> pending = new List<PendingLine>();
        if (lineNodes == null) {
            return pending;
        }
        Map<String, Object> node;
        Map<String, Object> tagMap;
        Decimal qty;
        Decimal staged;
        Id lineId;
        PendingLine pl;
        for (Object raw : lineNodes) {
            if (!(raw instanceof Map<String, Object>)) {
                continue;
            }
            node = (Map<String, Object>) raw;
            tagMap = extractTagMap(node);

            qty = getDecimalFromTag(tagMap, TAG_QUANTITY);
            if (qty == null || qty >= 0) {
                continue;
            }
            staged = getDecimalFromTag(tagMap, TAG_CANCEL_NET);
            if (staged != null && staged > 0) {
                continue; // already seeded — the direct path credits it, no SOQL needed
            }
            lineId = lineIdFromDataPath(getDataPath(node));
            if (lineId == null) {
                continue;
            }
            pl = new PendingLine();
            pl.lineId = lineId;
            pl.currencyIso = getStringFromTag(tagMap, TAG_CURRENCY);
            pl.listPrice = getDecimalFromTag(tagMap, TAG_LIST_PRICE);
            pending.add(pl);
        }
        return pending;
    }

    /**
     * @description Resolve transaction scope from the LINE record Id (the last dataPath
     *              element): a QuoteLineItem => 'Quote', an OrderItem => 'Order'. Uses the
     *              Id SObjectType — robust, because dataPath[0] is the 64-char context path
     *              (NOT the root entity Id), so a prefix read of element 0 is wrong. Null
     *              when no node yields a Quote/Order line Id.
     */
    @TestVisible
    private String resolveScope(List<Object> lineNodes) {
        if (lineNodes == null) {
            return null;
        }
        Id lineId;
        Schema.SObjectType sType;
        for (Object raw : lineNodes) {
            if (!(raw instanceof Map<String, Object>)) {
                continue;
            }
            lineId = lineIdFromDataPath(getDataPath((Map<String, Object>) raw));
            if (lineId == null) {
                continue;
            }
            sType = lineId.getSObjectType();
            if (sType == QuoteLineItem.SObjectType) {
                return 'Quote';
            }
            if (sType == OrderItem.SObjectType) {
                return 'Order';
            }
        }
        return null;
    }

    /**
     * @description Resolve each cancel line's source asset Id. ORDER lines via
     *              OrderItem.OrderAction.SourceAssetId; QUOTE lines via
     *              QuoteLineItem.QuoteAction.SourceAssetId. ONE SOQL for the scope,
     *              null-safe at every hop.
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

    /**
     * @description Pure seam: fold one AssetActionSource into the asset/currency net map.
     *              A Generate row is sticky (only another Generate replaces it); a
     *              non-Generate row only replaces another non-Generate (newest-wins). Only
     *              positive nets fold, so a zero-net Generate can never lock a pair at 0.
     */
    @TestVisible
    private void applyAssetNetSource(Map<Id, Map<String, Decimal>> netByCurrency, AssetActionSource s) {
        if (s == null || s.AssetAction == null || s.AssetAction.AssetId == null) {
            return;
        }
        if (s.NetUnitPrice == null || s.NetUnitPrice <= 0) {
            return;
        }
        String currencyCode = s.CurrencyIsoCode;
        if (String.isBlank(currencyCode)) {
            return;
        }
        Id assetId = s.AssetAction.AssetId;
        if (!netByCurrency.containsKey(assetId)) {
            netByCurrency.put(assetId, new Map<String, Decimal>());
        }
        Map<String, Decimal> byCur = netByCurrency.get(assetId);
        Boolean isGenerate = PRICED_SALE_TYPES.contains(s.AssetAction.Type);
        String key = assetId + '|' + currencyCode;

        if (!byCur.containsKey(currencyCode)) {
            byCur.put(currencyCode, s.NetUnitPrice);
            if (isGenerate) {
                generateLocked.add(key);
            }
            return;
        }
        if (isGenerate) {
            byCur.put(currencyCode, s.NetUnitPrice);
            generateLocked.add(key);
        } else if (!generateLocked.contains(key)) {
            byCur.put(currencyCode, s.NetUnitPrice);
        }
    }

    /** Tracks (asset|currency) keys whose kept value came from a Generate row. */
    @TestVisible
    private Set<String> generateLocked = new Set<String>();

    /**
     * @description Pure seam: pick the per-unit NET to credit for one cancel line.
     *              1) asset NET in the line's OWN currency; 2) asset NET when the line has
     *              no currency tag and the asset is single-currency; 3) LOSSY ListPrice
     *              fallback (> 0, already line-currency); else null. NEVER seeds a
     *              foreign-currency net.
     */
    @TestVisible
    private Decimal resolveSeedNet(Id assetId, String lineCurrency, Decimal listPrice,
                                   Map<Id, Map<String, Decimal>> assetNetByCurrency) {
        if (assetId != null && assetNetByCurrency != null && assetNetByCurrency.containsKey(assetId)) {
            Map<String, Decimal> byCur = assetNetByCurrency.get(assetId);
            if (byCur != null && !byCur.isEmpty()) {
                if (String.isNotBlank(lineCurrency)) {
                    if (byCur.containsKey(lineCurrency)) {
                        Decimal net = byCur.get(lineCurrency);
                        if (net != null && net > 0) {
                            return net;
                        }
                    }
                    // currency mismatch => fall through to the lossy ListPrice fallback
                } else if (byCur.size() == 1) {
                    Decimal only = byCur.values()[0];
                    if (only != null && only > 0) {
                        return only;
                    }
                }
            }
        }
        if (listPrice != null && listPrice > 0) {
            return listPrice;
        }
        return null;
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

    /**
     * @description The line record Id is the LAST element of the dataPath (QuoteLineItem
     *              for a Quote, OrderItem for an Order). Null when the last element is not
     *              a valid Id — mirrors the prehook / COLA / QLDescription hooks.
     */
    @TestVisible
    private Id lineIdFromDataPath(List<Object> dataPath) {
        if (dataPath == null || dataPath.isEmpty()) {
            return null;
        }
        try {
            return Id.valueOf(String.valueOf(dataPath.get(dataPath.size() - 1)));
        } catch (Exception e) {
            return null;
        }
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
    private String getStringFromTag(Map<String, Object> tagMap, String fieldName) {
        Object val = extractFieldValue(tagMap, fieldName);
        return val != null ? String.valueOf(val) : null;
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

    // ============================================================
    // DTO
    // ============================================================

    /** Per-cancel-line carrier for lines that need asset-net resolution. */
    @TestVisible
    private class PendingLine {
        public Id lineId;
        public String currencyIso;
        public Decimal listPrice;
    }
}
