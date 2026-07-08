/**
 * @description Pure cancellation/credit arithmetic + context-node shaping for the SC-3441
 *              cancel-line-credit posthook, extracted VERBATIM from `CancelLineCreditPosthook`
 *              (Wave-2 hook-thinning). No SOQL, no DML, no RCA context API — every method here
 *              operates only on already-fetched context tag maps / SObjects, so it is fully
 *              unit-testable. The hook stays a thin adapter: it does the context fetch, the
 *              read-only asset-net SOQL, and the context submit, and delegates all of the
 *              math/gating/node-shaping below.
 *
 *              WHAT LIVES HERE (pure):
 *                - parseLineNodes        — parse a queryTags(SalesTransactionItem) response
 *                - buildCreditUpdates    — negative-qty gating + credit = net * qty node updates
 *                - buildNodeUpdate / attr — the QLI field-API-name attribute payload shape
 *                - resolveScope          — Quote vs Order from the line record Id type
 *                - collectUnseededCancelLines — the negative-qty, un-staged lines needing asset-net
 *                - applyAssetNetSource   — fold one AssetActionSource row (Generate-wins-and-sticks)
 *                - resolveSeedNet        — currency-aware asset-net pick + lossy ListPrice fallback
 *                - tag/dataPath helpers  — getDecimalFromTag / getStringFromTag / lineIdFromDataPath /
 *                                          getDataPath / extractTagMap / extractFieldValue
 *
 *              STATE: `generateLocked` is per-instance (mirrors the hook's per-execute instance
 *              field) — the hook holds ONE calculator per execute so a Generate lock accumulates
 *              across the fold loop but never leaks between reprices. Do NOT make this static.
 *
 * @see CancelLineCreditPosthook (the adapter/seam owner)
 * @author Liam Jeong (SC-3441)
 * @date July 2026 (Wave-2 decomposition — extracted verbatim, behavior-preserving)
 */
public with sharing class CancelLineCreditCalculator {

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
    // CREDIT BUILD — pure seam, negative-qty lines; staged net OR resolved asset net
    // ============================================================

    /** Overload: no pre-resolved asset nets (already-seeded lines / pure-seam tests). */
    public List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes) {
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
    public List<Map<String, Object>> buildCreditUpdates(List<Object> lineNodes, Map<Id, Decimal> resolvedNetByLine) {
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
    public Map<String, Object> buildNodeUpdate(List<Object> dataPath, Decimal cancelNet, Decimal credit) {
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
    // RESPONSE PARSE — pure parse of a queryTags(SalesTransactionItem) response
    // ============================================================

    /**
     * @description Pure parse of a queryTags(SalesTransactionItem) response into the
     *              raw node list. Handles {queryResult:{SalesTransactionItem:[...]}},
     *              the flatter {SalesTransactionItem:...}, and single-object cases.
     */
    public List<Object> parseLineNodes(Map<String, Object> apiResponse) {
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
    // ASSET-NET SELF-RESOLUTION seams (v2.1) — the PURE parts. The SOQL
    // orchestration (line->asset, AssetActionSource) stays in the hook.
    // ============================================================

    /**
     * @description Pure seam: collect the negative-qty lines that carry NO usable staged
     *              net (context CancelNetUnitPrice__c null/<=0) and therefore need asset-net
     *              resolution. Positive/zero-qty and already-seeded lines are excluded (they
     *              need no SOQL). Captures the line's currency + ListPrice tags for the
     *              currency-aware pick.
     */
    public List<PendingLine> collectUnseededCancelLines(List<Object> lineNodes) {
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
    public String resolveScope(List<Object> lineNodes) {
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
     * @description Pure seam: fold one AssetActionSource into the asset/currency net map.
     *              A Generate row is sticky (only another Generate replaces it); a
     *              non-Generate row only replaces another non-Generate (newest-wins). Only
     *              positive nets fold, so a zero-net Generate can never lock a pair at 0.
     */
    public void applyAssetNetSource(Map<Id, Map<String, Decimal>> netByCurrency, AssetActionSource s) {
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
    public Decimal resolveSeedNet(Id assetId, String lineCurrency, Decimal listPrice,
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
    public Id lineIdFromDataPath(List<Object> dataPath) {
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

    public String getStringFromTag(Map<String, Object> tagMap, String fieldName) {
        Object val = extractFieldValue(tagMap, fieldName);
        return val != null ? String.valueOf(val) : null;
    }

    public Decimal getDecimalFromTag(Map<String, Object> tagMap, String fieldName) {
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
     * @description Per-cancel-line carrier for lines that need asset-net resolution.
     *              PUBLIC (was a hook-private inner) so the adapter hook can consume the
     *              list this calculator returns.
     */
    public class PendingLine {
        public Id lineId;
        public String currencyIso;
        public Decimal listPrice;
    }
}
