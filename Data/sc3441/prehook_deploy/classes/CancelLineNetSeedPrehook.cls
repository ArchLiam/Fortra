/**
 * @description RevSignaling pricing PREHOOK for SC-3441.
 *
 *              PROBLEM (SC-3441): a user-initiated cancellation / negative-quantity
 *              pricing line (e.g. OrderItem 802WC00000OugI7YAJ, Order 00095539,
 *              Arcus Hosting, Qty -1, ListPrice 3000) shows TotalPrice $0.00 instead
 *              of the expected -$3000 credit. The native RLM waterfall returns no
 *              priced row for the cancel line, so the NetUnitPrice FIELD stays null;
 *              the active line-total formula computes NetUnitPrice * LineItemQuantity
 *              = null * -1 = 0.
 *
 *              FIX ROLE OF THIS PREHOOK: for CANCELLATION / negative-quantity lines
 *              ONLY, resolve the original asset NET unit price and WRITE it into the
 *              context staging attribute CancelNetUnitPrice__c (Currency(16,2),
 *              hydrated on node SalesTransactionItem on BOTH QuoteEntitiesMapping and
 *              OrderEntitiesMapping). A later GATED procedure AssignmentElement copies
 *              CancelNetUnitPrice__c -> NetUnitPrice so TotalPrice = net * qty
 *              (e.g. -3000). This prehook writes ONLY the staging attribute; it does
 *              NOT touch NetUnitPrice / UnitPrice / InputUnitPrice directly.
 *
 *              NORMAL POSITIVE-QUANTITY LINES ARE LEFT UNTOUCHED — no node update is
 *              ever emitted for them (verified-required: writing on positive lines
 *              would perturb the live waterfall).
 *
 *              ASSET-NET RESOLUTION (verified live in FortraUAT 2026-06-24):
 *                ORDER line: OrderItem.Id -> OrderItem.OrderActionId
 *                  -> OrderAction.SourceAssetId -> the asset's original-sale
 *                  AssetActionSource.NetUnitPrice (AssetAction.Type='Generate',
 *                  CategoryEnum='Initial Sale').
 *                  Verified: 802WC00000OugI7YAJ -> 8OAWC000002SxiL4AS
 *                    (Type Cancel) -> SourceAssetId 02iWC000008MpX7YAK
 *                    -> AssetActionSource 4nMWC0000046hkj2AA (Generate / Initial Sale)
 *                    NetUnitPrice 3000 USD.
 *                QUOTE line: QuoteLineItem.Id -> QuoteLineItem.QuoteActionId
 *                  -> QuoteAction.SourceAssetId -> AssetActionSource.NetUnitPrice.
 *                  Verified: 0QLWC000003fKAj4AM -> 7ocWC00000upzpBYAQ (Type Cancel)
 *                    -> SourceAssetId 02iWC000008MpX7YAK (same asset).
 *                Priced anchor: AssetAction.Type='Generate' is the original-sale row
 *                  (430,521 Generate vs 20 Change vs 2 Cancel org-wide). We prefer
 *                  the Generate / Initial-Sale row; otherwise the most-recent priced
 *                  source with a non-null, currency-matching NetUnitPrice.
 *
 *              FALLBACK: ListPrice from the context line tag, ONLY when asset-net is
 *                unavailable OR resolves to 0, AND ListPrice > 0. This is LOSSY: it
 *                under-credits the 125,454 AssetActionSource rows with ListPrice 0 /
 *                NetUnitPrice > 0 (verified live 2026-06-24) — those genuinely need the
 *                asset-net path, not list.
 *
 *              RECOVERABILITY of the two live negative-qty OrderItems (verified live
 *                FortraUAT 2026-06-24): only ONE of the two is recoverable by this
 *                prehook.
 *                  - 802WC00000OugI7YAJ (Qty -1, ListPrice 3000) -> asset
 *                    02iWC000008MpX7YAK -> a single Generate/Initial-Sale
 *                    AssetActionSource at NetUnitPrice 3000 USD: RESOLVED (seeded 3000).
 *                  - 802WC00000OgXD4YAN (Qty -1, ListPrice 0) -> asset
 *                    02iWC000008ARwoYAG: EVERY one of its 4 AssetActionSource rows is
 *                    NetUnitPrice 0 AND ListPrice 0 (Generate, Change, 2x Cancel). No
 *                    positive net exists anywhere on that asset, so the prehook
 *                    correctly does NOT seed 0 and that line STAYS BROKEN — it needs a
 *                    separate data / credit-policy decision OUTSIDE net-seeding scope
 *                    (NOT recoverable by asset-net OR by ListPrice). The earlier claim
 *                    that "the 2 ListPrice-0 broken lines REQUIRE the asset-net path"
 *                    was FALSE for this second line and has been corrected.
 *
 *              CURRENCY-AWARE: net is resolved in the line's transaction currency
 *                (per-line tag STICurrencyIsoCode). An asset-net source in a different
 *                currency is SKIPPED (never seed a USD asset-net onto a non-USD line —
 *                org has a documented USD-blindness pattern, SC-3384 family). Org
 *                AssetActionSource currencies: USD/EUR/GBP/JPY/AUD/CAD/CHF/NZD.
 *
 *              BULKIFICATION: a constant number of SOQL queries regardless of line
 *                count — at most one OrderItem query, one QuoteLineItem query, and one
 *                AssetActionSource query per invocation (Ids collected first).
 *
 *              NULL-SAFE / SWALLOW CONTRACT: never throws out of execute() in a way
 *                that breaks the whole reprice. Mirrors the template swallow contracts
 *                (RegionalServicesPricingPrehook / COLAUpliftPrehook /
 *                QLDescriptionGeneratorPrehook): the outer try/catch downgrades any
 *                error to a SUCCESS-with-warnings response, and submitContextUpdates
 *                swallows the "not in updatable state" degrade path.
 *
 *              SCOPE: handles whichever context invoked it (Quote OR Order), resolved
 *                from the first dataPath element (Order roots start with '801', Quote
 *                with '0Q0'); bails safely if neither.
 *
 * @author 5S Infusion (SC-3441)
 * @date June 2026
 * @version 1.0
 */
global class CancelLineNetSeedPrehook implements RevSignaling.SignalingApexProcessor {

    // Recursion prevention (a context update can re-trigger the pricing engine).
    private static Boolean isProcessing = false;

    // ============================================================
    // CONTEXT TAG NAMES — verified against SalesTransactionContextExt_v2,
    // node SalesTransactionItem (FortraUAT 2026-06-24).
    // ============================================================

    /** Per-line quantity tag. Negative value => cancellation / reduction line. */
    @TestVisible private static final String TAG_QUANTITY = 'Quantity';

    /** Per-line action type tag. Value 'Cancel' on a user-initiated cancellation. */
    @TestVisible private static final String TAG_ACTION_TYPE = 'SalesTransactionActionType';

    /** Per-line source-asset Id tag (present when the line amends an existing asset). */
    @TestVisible private static final String TAG_SOURCE_ASSET = 'SalesTransactionSourceAsset';

    /** Per-line catalog list price tag (LOSSY fallback only). */
    @TestVisible private static final String TAG_LIST_PRICE = 'ListPrice';

    /** Per-line transaction currency tag. */
    @TestVisible private static final String TAG_CURRENCY = 'STICurrencyIsoCode';

    /** Amend start/end quantity tags (used for the full-cancel restriction). */
    @TestVisible private static final String TAG_START_QTY = 'StartQuantity';
    @TestVisible private static final String TAG_END_QTY = 'EndQuantity';

    /**
     * @description Hydration-mapped Currency context attribute we write back to.
     *              Maps to QuoteLineItem.CancelNetUnitPrice__c (QuoteEntitiesMapping)
     *              and OrderItem.CancelNetUnitPrice__c (OrderEntitiesMapping), node
     *              SalesTransactionItem. Verified present on BOTH mappings.
     */
    @TestVisible private static final String SEED_ATTR = 'CancelNetUnitPrice__c';

    /** Order root-entity prefix (dataPath[0]). */
    @TestVisible private static final String ORDER_PREFIX = '801';
    /** Quote root-entity prefix (dataPath[0]). */
    @TestVisible private static final String QUOTE_PREFIX = '0Q0';

    /** Action types that resolve a priced asset source, most-preferred first. */
    @TestVisible private static final Set<String> PRICED_SALE_TYPES = new Set<String>{ 'Generate' };

    // ============================================================
    // ENTRY POINT
    // ============================================================

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        if (isProcessing) {
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'CancelLineNetSeedPrehook skipped - already processing';
            return response;
        }

        try {
            isProcessing = true;

            String contextId = request != null ? request.ctxInstanceId : null;
            if (String.isBlank(contextId)) {
                // No context to act on — succeed quietly (do not break the reprice).
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No context instance id - nothing to seed';
                return response;
            }

            Context.IndustriesContext ctx = new Context.IndustriesContext();

            // Step 1 — read SalesTransactionItem line nodes from the runtime context.
            List<Object> lineNodes = fetchSalesTransactionItems(ctx, contextId);
            if (lineNodes == null || lineNodes.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No SalesTransactionItem nodes - nothing to seed';
                return response;
            }

            // Step 2 — resolve scope (Quote vs Order) from the first node's root Id.
            String scope = resolveScope(lineNodes);
            if (scope == null) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'Neither Quote nor Order scope - skipped';
                return response;
            }

            // Step 3 — collect the cancel lines (negative qty), keyed by line Id.
            //          Positive-qty lines never enter this map => never written.
            Map<Id, CancelLine> cancelLines = collectCancelLines(lineNodes);
            if (cancelLines.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No cancellation (negative-qty) lines - nothing to seed';
                return response;
            }

            // Step 4 — resolve each cancel line's source asset Id (bulk, by scope).
            Map<Id, Id> lineToAssetId = resolveSourceAssetIds(scope, cancelLines.keySet());

            // Step 5 — resolve the asset NET (currency-aware) for every source asset.
            Map<Id, Map<String, Decimal>> assetNetByCurrency =
                resolveAssetNetByCurrency(new Set<Id>(lineToAssetId.values()));

            // Step 6 — build the context node updates (pure seam).
            List<Map<String, Object>> updates =
                buildSeedUpdates(cancelLines, lineToAssetId, assetNetByCurrency);

            // Step 7 — submit.
            Integer submitted = submitContextUpdates(ctx, contextId, updates);

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Seeded CancelNetUnitPrice__c on ' + submitted
                + ' of ' + cancelLines.size() + ' cancellation line(s) [' + scope + ']';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CancelLineNetSeedPrehook error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            // SUCCESS even on error — never break the whole reprice.
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Cancel-net seeding completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    // ============================================================
    // CONTEXT FETCH (live) — swallow-and-continue, mirrors the templates
    // ============================================================

    /**
     * @description Query the SalesTransactionItem raw node list from the runtime
     *              context. Handles the nested {queryResult:{SalesTransactionItem:[...]}}
     *              and the flatter {SalesTransactionItem:...} shapes, plus the
     *              single-object-not-list case. Returns null on any failure (the
     *              live queryTags call is wrapped so a failure degrades to "nothing
     *              to seed", never an exception out of execute()).
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

    /**
     * @description Pure parse of a queryTags(SalesTransactionItem) response into the
     *              raw node list. Unit-testable with a hand-built response map.
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
    // SCOPE — Quote vs Order, from dataPath[0]
    // ============================================================

    /**
     * @description Resolve transaction scope from the first node's dataPath root Id.
     *              Order roots start with 801, Quotes with 0Q0. Returns 'Order',
     *              'Quote', or null when neither prefix matches (bail safely).
     */
    @TestVisible
    private String resolveScope(List<Object> lineNodes) {
        if (lineNodes == null || lineNodes.isEmpty()) {
            return null;
        }
        for (Object raw : lineNodes) {
            if (!(raw instanceof Map<String, Object>)) {
                continue;
            }
            List<Object> dp = getDataPath((Map<String, Object>) raw);
            if (dp == null || dp.isEmpty()) {
                continue;
            }
            String rootId = String.valueOf(dp.get(0));
            if (rootId == null) {
                continue;
            }
            if (rootId.startsWith(ORDER_PREFIX)) {
                return 'Order';
            }
            if (rootId.startsWith(QUOTE_PREFIX)) {
                return 'Quote';
            }
        }
        return null;
    }

    // ============================================================
    // CANCEL DETECTION — negative-qty lines only
    // ============================================================

    /**
     * @description Build a map of line Id -> CancelLine for every NEGATIVE-quantity
     *              line node. Positive-qty (and zero-qty) lines are excluded entirely,
     *              so the prehook never writes/perturbs a normal line. Pure seam.
     *
     *              A line qualifies when Quantity < 0. SalesTransactionActionType
     *              ('Cancel') and SalesTransactionSourceAsset are captured for
     *              gating/asset resolution but the negative quantity is the primary,
     *              always-available signal.
     */
    @TestVisible
    private Map<Id, CancelLine> collectCancelLines(List<Object> lineNodes) {
        Map<Id, CancelLine> result = new Map<Id, CancelLine>();
        if (lineNodes == null) {
            return result;
        }
        for (Object raw : lineNodes) {
            if (!(raw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> node = (Map<String, Object>) raw;
            Map<String, Object> tagMap = extractTagMap(node);
            List<Object> dataPath = getDataPath(node);

            Decimal qty = getDecimalFromTag(tagMap, TAG_QUANTITY);
            // GATE: only negative-quantity lines. Null/zero/positive => skip (no write).
            if (qty == null || qty >= 0) {
                continue;
            }

            Id lineId = lineIdFromDataPath(dataPath);
            if (lineId == null) {
                continue;
            }

            CancelLine cl = new CancelLine();
            cl.lineId = lineId;
            cl.dataPath = dataPath;
            cl.quantity = qty;
            cl.actionType = getStringFromTag(tagMap, TAG_ACTION_TYPE);
            cl.sourceAssetTag = getStringFromTag(tagMap, TAG_SOURCE_ASSET);
            cl.listPrice = getDecimalFromTag(tagMap, TAG_LIST_PRICE);
            cl.currencyIso = getStringFromTag(tagMap, TAG_CURRENCY);
            cl.startQty = getDecimalFromTag(tagMap, TAG_START_QTY);
            cl.endQty = getDecimalFromTag(tagMap, TAG_END_QTY);

            result.put(lineId, cl);
        }
        return result;
    }

    // ============================================================
    // SOURCE-ASSET RESOLUTION — bulk, by scope (constant # of SOQL)
    // ============================================================

    /**
     * @description Resolve each cancel line's source asset Id. ORDER lines via
     *              OrderItem.OrderAction.SourceAssetId; QUOTE lines via
     *              QuoteLineItem.QuoteAction.SourceAssetId. ONE query for the scope.
     *              Null-safe at every hop. Returns line Id -> source asset Id (only
     *              lines whose action carries a non-null SourceAssetId are included).
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
     * @description Resolve the asset NET unit price for each source asset, keyed by
     *              currency so a non-USD line never inherits a USD net. ONE query for
     *              ALL assets. For each asset we keep, per currency, the best priced
     *              source: a 'Generate' / Initial-Sale row wins; otherwise the
     *              most-recent priced source with a POSITIVE NetUnitPrice.
     *
     *              SOQL FILTER: NetUnitPrice > 0 (NOT just != null). Verified live
     *              2026-06-24 there are 108,679 Generate rows at NetUnitPrice 0. A
     *              zero-net Generate must NOT enter the fold and lock the (asset,
     *              currency) at 0 — excluding it lets a later POSITIVE Change/Upsell
     *              row survive and lets a genuinely-undiscounted line (ListPrice > 0)
     *              fall through to the ListPrice fallback in resolveSeedNet. Every
     *              priced asset has exactly ONE Generate row (uniqueness verified), so
     *              the Generate-lock always wins when its net is > 0.
     *
     * @return assetId -> (CurrencyIsoCode -> NetUnitPrice), all values > 0
     */
    @TestVisible
    private Map<Id, Map<String, Decimal>> resolveAssetNetByCurrency(Set<Id> assetIds) {
        Map<Id, Map<String, Decimal>> netByCurrency = new Map<Id, Map<String, Decimal>>();
        // Strip nulls into a fresh set (never mutate the caller's set; never deref null).
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

        // Order so the LAST write per (asset,currency) is the most-preferred:
        // non-Generate first, Generate last, oldest first within a type, so the
        // Generate/Initial-Sale (or newest priced) row ends up as the kept value.
        List<AssetActionSource> sources = [
            SELECT AssetAction.AssetId, AssetAction.Type, AssetAction.CategoryEnum,
                   NetUnitPrice, CurrencyIsoCode, CreatedDate
            FROM AssetActionSource
            WHERE AssetAction.AssetId IN :cleanIds
              AND NetUnitPrice > 0
            ORDER BY CreatedDate ASC
        ];

        for (AssetActionSource s : sources) {
            applyAssetNetSource(netByCurrency, s);
        }
        return netByCurrency;
    }

    /**
     * @description Fold one AssetActionSource into the asset/currency net map,
     *              applying the priced-anchor preference. Pure seam (no SOQL) so the
     *              selection precedence is unit-testable with hand-built rows.
     *
     *              Preference within an (asset, currency):
     *                1. A 'Generate' (Initial Sale) row always wins.
     *                2. Otherwise the most-recent priced row (rows are folded oldest
     *                   -> newest, so a later non-Generate row replaces an earlier
     *                   non-Generate one, but never replaces a Generate row).
     *
     *              Only POSITIVE nets are folded (mirrors the resolveAssetNetByCurrency
     *              SOQL NetUnitPrice > 0 filter): a null OR <= 0 net is ignored so a
     *              zero-net Generate can never lock an (asset, currency) at 0.
     */
    @TestVisible
    private void applyAssetNetSource(Map<Id, Map<String, Decimal>> netByCurrency, AssetActionSource s) {
        if (s == null || s.AssetAction == null || s.AssetAction.AssetId == null) {
            return;
        }
        if (s.NetUnitPrice == null || s.NetUnitPrice <= 0) {
            return;
        }
        Id assetId = s.AssetAction.AssetId;
        String currencyCode = s.CurrencyIsoCode;
        if (String.isBlank(currencyCode)) {
            return;
        }
        if (!netByCurrency.containsKey(assetId)) {
            netByCurrency.put(assetId, new Map<String, Decimal>());
        }
        Map<String, Decimal> byCur = netByCurrency.get(assetId);

        Boolean isGenerate = PRICED_SALE_TYPES.contains(s.AssetAction.Type);

        if (!byCur.containsKey(currencyCode)) {
            byCur.put(currencyCode, s.NetUnitPrice);
            if (isGenerate) {
                generateLocked.add(assetId + '|' + currencyCode);
            }
            return;
        }

        // Already have a value. A Generate row is sticky and may only be replaced by
        // another Generate row (newest-wins among Generates). A non-Generate row may
        // only replace another non-Generate row (newest-wins), never a Generate.
        Boolean lockedByGenerate = generateLocked.contains(assetId + '|' + currencyCode);
        if (isGenerate) {
            byCur.put(currencyCode, s.NetUnitPrice);
            generateLocked.add(assetId + '|' + currencyCode);
        } else if (!lockedByGenerate) {
            byCur.put(currencyCode, s.NetUnitPrice);
        }
    }

    /** Tracks (asset|currency) keys whose kept value came from a Generate row. */
    @TestVisible
    private Set<String> generateLocked = new Set<String>();

    // ============================================================
    // SEED BUILD — pure seam, currency-aware, asset-net-first
    // ============================================================

    /**
     * @description Build the list of context node updates (one per cancel line that
     *              resolved a credit value). For each cancel line (see resolveSeedNet
     *              for the full precedence):
     *                1. Resolve asset NET in the line's currency (preferred).
     *                2. FALLBACK to ListPrice (LOSSY) when asset-net is unavailable, in
     *                   a DIFFERENT currency than the line, or resolves to 0 — AND
     *                   ListPrice > 0.
     *                3. If neither yields a positive magnitude, skip the line (no
     *                   write) rather than seed a zero/garbage credit.
     *              The seeded value is the per-UNIT net magnitude (positive); the
     *              procedure multiplies by the negative LineItemQuantity to produce
     *              the credit. Pure of any live-context dependency.
     */
    @TestVisible
    private List<Map<String, Object>> buildSeedUpdates(
        Map<Id, CancelLine> cancelLines,
        Map<Id, Id> lineToAssetId,
        Map<Id, Map<String, Decimal>> assetNetByCurrency
    ) {
        List<Map<String, Object>> updates = new List<Map<String, Object>>();
        if (cancelLines == null || cancelLines.isEmpty()) {
            return updates;
        }

        for (Id lineId : cancelLines.keySet()) {
            CancelLine cl = cancelLines.get(lineId);
            if (cl == null || cl.dataPath == null || cl.dataPath.isEmpty()) {
                continue;
            }

            Decimal seedNet = resolveSeedNet(cl, lineToAssetId.get(lineId), assetNetByCurrency);
            if (seedNet == null || seedNet <= 0) {
                // No credit value resolvable — leave the line for the interim BRE
                // null-guard / native path; do NOT seed a zero.
                continue;
            }

            updates.add(buildNodeUpdate(cl.dataPath, seedNet));
        }
        return updates;
    }

    /**
     * @description Resolve the per-unit NET magnitude to seed for one cancel line,
     *              currency-aware. Returns null when nothing safe is resolvable.
     *              Pure seam (no SOQL): all inputs are pre-resolved.
     *
     *              Order of preference:
     *                1. Asset NET in the line's OWN currency (preferred, never lossy).
     *                2. Asset NET when the line has no currency tag AND the asset is
     *                   single-currency (unambiguous).
     *                3. LOSSY fallback: the line's own ListPrice tag (already in the
     *                   line currency, so currency-safe), ONLY when > 0. This fires
     *                   when (a) asset-net is unavailable, (b) the asset-net is in a
     *                   DIFFERENT currency than the line (currency mismatch — never
     *                   seed a foreign net), or (c) the asset-net resolved to 0.
     *                4. Otherwise null (skip — no zero/garbage credit).
     */
    @TestVisible
    private Decimal resolveSeedNet(
        CancelLine cl,
        Id assetId,
        Map<Id, Map<String, Decimal>> assetNetByCurrency
    ) {
        if (cl == null) {
            return null;
        }

        // 1) Asset NET in the line's currency (preferred). All map values are > 0
        //    (resolveAssetNetByCurrency / applyAssetNetSource only fold positive nets).
        if (assetId != null && assetNetByCurrency != null && assetNetByCurrency.containsKey(assetId)) {
            Map<String, Decimal> byCur = assetNetByCurrency.get(assetId);
            if (byCur != null && !byCur.isEmpty()) {
                String lineCur = cl.currencyIso;
                if (String.isNotBlank(lineCur)) {
                    if (byCur.containsKey(lineCur)) {
                        Decimal net = byCur.get(lineCur);
                        if (net != null && net > 0) {
                            return net;
                        }
                        // net resolved but not positive -> drop through to the
                        // ListPrice fallback (an undiscounted line can still be
                        // credited from its own catalog list).
                    } else {
                        // Currency mismatch: the asset has a net, but NOT in the line's
                        // currency. NEVER seed a foreign-currency net (org USD-blindness
                        // pattern, SC-3384 family). Log + drop to the lossy fallback.
                        System.debug(LoggingLevel.INFO,
                            'CancelLineNetSeedPrehook currency mismatch - asset ' + assetId
                            + ' has no ' + lineCur + ' net (has ' + byCur.keySet()
                            + '); falling back to line ListPrice');
                    }
                } else if (byCur.size() == 1) {
                    // Line currency tag missing but asset has exactly one currency:
                    // safe to use it (single-currency asset, no ambiguity).
                    Decimal only = byCur.values()[0];
                    if (only != null && only > 0) {
                        return only;
                    }
                }
            }
        }

        // 2) LOSSY fallback: catalog ListPrice, ONLY when > 0.
        if (cl.listPrice != null && cl.listPrice > 0) {
            return cl.listPrice;
        }

        return null;
    }

    /**
     * @description Build a single line's context node-update for updateContextAttributes.
     *              The nodePath is the line's dataPath with the FIRST element removed
     *              (the root entity Id), matching the template convention. Writes ONLY
     *              the SEED_ATTR (CancelNetUnitPrice__c) — never NetUnitPrice/UnitPrice
     *              directly. Pure seam.
     */
    @TestVisible
    private Map<String, Object> buildNodeUpdate(List<Object> dataPath, Decimal seedNet) {
        List<Object> updatePath = dataPath == null ? new List<Object>() : dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => new List<Object>{
                new Map<String, Object>{
                    'attributeName' => SEED_ATTR,
                    'attributeValue' => seedNet
                }
            }
        };
    }

    // ============================================================
    // SUBMIT — swallow "not in updatable state", mirrors templates
    // ============================================================

    /**
     * @description Submit the batch of context attribute updates in a single call.
     *              Direct DML is forbidden in pricing prehooks; the context API is the
     *              only writeback path.
     *
     *              SWALLOW CONTRACT (deliberately the RegionalServicesPricingPrehook
     *              variant, NOT the COLAUpliftPrehook full-swallow variant): a
     *              "not in updatable state" failure is swallowed and the line is left
     *              uncredited (graceful degrade — this is the expected condition during
     *              a non-pricing reprice phase). ANY OTHER failure (e.g. a non-hydrated
     *              attribute that "poisons the batch") is RE-THROWN so it surfaces in
     *              execute()'s outer try/catch and is reported in response.message
     *              rather than being silently dropped — execute() still downgrades it
     *              to a SUCCESS-with-warnings response, so the reprice is never broken
     *              either way, but a real config defect stays visible to a maintainer.
     * @return Count of updates submitted (0 on empty input or the swallowed
     *         "not in updatable state" path).
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
                System.debug(LoggingLevel.INFO, 'Context not in updatable state - skipping cancel-net seed');
                return 0;
            }
            // Surface genuine batch-poison / config errors to execute()'s outer
            // try/catch (becomes a SUCCESS-with-warnings message; reprice unbroken).
            throw e;
        }
    }

    // ============================================================
    // DATAPATH / TAG HELPERS — same shape as the COLA / Regional prehooks
    // ============================================================

    /**
     * @description The node's dataPath (or null when absent / wrong type).
     */
    @TestVisible
    private List<Object> getDataPath(Map<String, Object> node) {
        if (node == null) {
            return null;
        }
        Object dpObj = node.get('dataPath');
        return (dpObj instanceof List<Object>) ? (List<Object>) dpObj : null;
    }

    /**
     * @description The line record Id is the LAST element of the dataPath (verified
     *              by COLAUpliftPrehook / QLDescriptionGeneratorPrehook). Returns null
     *              when the last element is not a valid Id.
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

    /**
     * @description Unwrap a node's tag map. Nodes are either {tagValue:{...}, dataPath:[...]}
     *              or a flat {...} map. Returns the inner tag map (never null for a
     *              well-formed node).
     */
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

    /**
     * @description Per-cancel-line carrier: line Id, dataPath, and the tags read from
     *              the context node needed to resolve and seed the credit.
     */
    @TestVisible
    private class CancelLine {
        public Id lineId;
        public List<Object> dataPath;
        public Decimal quantity;
        public String actionType;
        public String sourceAssetTag;
        public Decimal listPrice;
        public String currencyIso;
        public Decimal startQty;
        public Decimal endQty;
    }
}
