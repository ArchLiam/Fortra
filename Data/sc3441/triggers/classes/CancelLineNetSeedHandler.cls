/**
 * @description SC-3441 — seeds the original asset NET unit price onto cancellation /
 *              negative-quantity lines so the shared pricing procedure can credit them.
 *
 *              WHY A BEFORE TRIGGER (not the RevSignaling prehook): RLM pricing is
 *              invoked SEPARATELY from the record save (Reprice / Calculate Price /
 *              PlaceQuote) and hydrates its input context from the SAVED field values.
 *              A before-save trigger runs inside the DML save (before commit), so the
 *              value it writes is persisted and is then hydrated into the procedure's
 *              INPUT — where the `Cancel Net Seed` block reads it. The prehook wrote to
 *              the runtime context too late (after the procedure had already read its
 *              input), so its seed never fired. This handler is the correct delivery.
 *
 *              WHAT IT DOES: for Quantity < 0 lines ONLY, resolves the originating
 *              asset's NET unit price and stamps it onto CancelNetUnitPrice__c on the
 *              line (in memory). Positive-qty lines are never touched.
 *
 *              ORDER vs QUOTE delivery:
 *                - OrderItem.NetUnitPrice is WRITEABLE -> we stamp NetUnitPrice DIRECTLY
 *                  on order cancel lines, so the procedure's line-total computes
 *                  NetUnitPrice * Quantity = net * -1 with NO dependency on the seed
 *                  block (the platform does not hydrate the custom attribute into the
 *                  pricing procedure for the cancel path).
 *                - QuoteLineItem.NetUnitPrice is READ-ONLY -> quote cancel lines carry
 *                  only CancelNetUnitPrice__c (staging field) for the procedure seed
 *                  block; that path is pending a platform-side hydration fix (SC-3441
 *                  quote-side escalation).
 *
 *              ASSET-NET RESOLUTION (RCA-validated, reused from CancelLineNetSeedPrehook):
 *                Order line: OrderItem.OrderActionId -> OrderAction.SourceAssetId
 *                Quote line: QuoteLineItem.QuoteActionId -> QuoteAction.SourceAssetId
 *                -> AssetActionSource.NetUnitPrice, currency-matched, with a
 *                   'Generate'/Initial-Sale row preferred and only POSITIVE nets folded.
 *                FALLBACK: the line's own ListPrice (LOSSY) only when no positive
 *                asset-net exists in the line's currency AND ListPrice > 0. Never seeds 0.
 *
 *              BULKIFICATION: a constant number of SOQL regardless of line count — at
 *              most one Action query and one AssetActionSource query per invocation.
 *
 *              IDEMPOTENT: only writes when the resolved value differs from the current
 *              field value, so a re-save never churns the field.
 *
 *              Convention mirrors COLAUpliftHandler (static handler methods called from
 *              the object trigger's before-insert / before-update context).
 *
 * @author LJ (SC-3441)
 * @date June 2026
 */
public with sharing class CancelLineNetSeedHandler {

    /** AssetAction types that anchor the original priced sale, most-preferred first. */
    @TestVisible
    private static final Set<String> PRICED_SALE_TYPES = new Set<String>{ 'Generate' };

    // ============================================================
    // PUBLIC ENTRY POINTS — called from the object triggers (before insert/update)
    // ============================================================

    /** OrderItem entry point. Treats the call as an insert (NetUnitPrice writeable). */
    public static void handleOrderItems(List<OrderItem> newItems) {
        handleOrderItems(newItems, true);
    }

    /**
     * OrderItem before-insert / before-update entry point.
     * @param isInsert true on before-insert ONLY. NetUnitPrice is writeable on OrderItem
     *        only until OrderItemDetail records exist (created during pricing); editing it
     *        afterward throws INVALID_FIELD_FOR_INSERT_UPDATE. So the direct NetUnitPrice
     *        write is restricted to before-insert (no detail yet). On update we only
     *        refresh the custom staging field.
     */
    public static void handleOrderItems(List<OrderItem> newItems, Boolean isInsert) {
        stampCancelLines((List<SObject>) newItems, ScopeType.ORDER, isInsert == true);
    }

    /** QuoteLineItem before-insert / before-update entry point. */
    public static void handleQuoteLines(List<QuoteLineItem> newItems) {
        // Quote lines never get a direct NetUnitPrice write (read-only) -> isInsert N/A.
        stampCancelLines((List<SObject>) newItems, ScopeType.QUOTE, false);
    }

    private enum ScopeType { ORDER, QUOTE }

    // ============================================================
    // CORE — bulkified, scope-agnostic
    // ============================================================

    /**
     * @description Stamp CancelNetUnitPrice__c on every Quantity < 0 line, resolving the
     *              asset net once per asset. Pure-bulk: builds Id sets first, queries
     *              outside any loop. Never throws out of the trigger.
     */
    private static void stampCancelLines(List<SObject> lines, ScopeType scope, Boolean isInsert) {
        if (lines == null || lines.isEmpty()) {
            return;
        }

        String actionField = (scope == ScopeType.ORDER) ? 'OrderActionId' : 'QuoteActionId';

        // 1) collect cancel lines (qty < 0) and their action Ids — single pass, no SOQL.
        List<SObject> cancelLines = new List<SObject>();
        Set<Id> actionIds = new Set<Id>();
        for (SObject line : lines) {
            Decimal qty = toDecimal(line.get('Quantity'));
            if (qty == null || qty >= 0) {
                continue; // GATE: positive / zero / null quantity => never touched.
            }
            cancelLines.add(line);
            Id actionId = (Id) line.get(actionField);
            if (actionId != null) {
                actionIds.add(actionId);
            }
        }
        if (cancelLines.isEmpty()) {
            return;
        }

        // 2) action -> SourceAssetId (one query for the scope).
        Map<Id, Id> actionToAsset = resolveActionAssets(scope, actionIds);

        // 3) asset -> (currency -> NET) (one query for all assets).
        Map<Id, Map<String, Decimal>> netByCurrency =
            resolveAssetNetByCurrency(new Set<Id>(actionToAsset.values()));

        // OrderItem.NetUnitPrice is writeable ONLY before OrderItemDetail records exist
        // (created during pricing); editing it afterward throws INVALID_FIELD_FOR_INSERT_
        // UPDATE. So we stamp NetUnitPrice DIRECTLY only on the ORDER before-INSERT (no
        // detail yet) — never on update. QuoteLineItem.NetUnitPrice is always read-only.
        Boolean writeNetDirect = (scope == ScopeType.ORDER && isInsert);

        // 4) stamp each cancel line in memory (idempotent).
        for (SObject line : cancelLines) {
            Id actionId = (Id) line.get(actionField);
            Id assetId = (actionId == null) ? null : actionToAsset.get(actionId);

            Decimal seedNet = resolveSeedNet(
                assetId,
                (String) line.get('CurrencyIsoCode'),
                toDecimal(line.get('ListPrice')),
                netByCurrency
            );
            if (seedNet == null || seedNet <= 0) {
                continue; // nothing safe to credit — leave for the data ticket.
            }

            // Staging field — consumed by the procedure seed block on the quote path and
            // retained on orders for parity / once platform hydration is resolved.
            Decimal current = toDecimal(line.get('CancelNetUnitPrice__c'));
            if (current == null || current != seedNet) {
                line.put('CancelNetUnitPrice__c', seedNet);
            }

            // ORDER lines: direct NetUnitPrice write (positive per-unit magnitude; the
            // procedure computes TotalPrice = NetUnitPrice * Quantity = seedNet * -1).
            if (writeNetDirect) {
                Decimal curNet = toDecimal(line.get('NetUnitPrice'));
                if (curNet == null || curNet != seedNet) {
                    line.put('NetUnitPrice', seedNet);
                }
            }
        }
    }

    // ============================================================
    // SOURCE-ASSET RESOLUTION — by scope, one query
    // ============================================================

    @TestVisible
    private static Map<Id, Id> resolveActionAssets(ScopeType scope, Set<Id> actionIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (actionIds == null || actionIds.isEmpty()) {
            return result;
        }
        if (scope == ScopeType.ORDER) {
            for (OrderAction oa : [
                SELECT Id, SourceAssetId FROM OrderAction WHERE Id IN :actionIds
            ]) {
                if (oa.SourceAssetId != null) {
                    result.put(oa.Id, oa.SourceAssetId);
                }
            }
        } else {
            for (QuoteAction qa : [
                SELECT Id, SourceAssetId FROM QuoteAction WHERE Id IN :actionIds
            ]) {
                if (qa.SourceAssetId != null) {
                    result.put(qa.Id, qa.SourceAssetId);
                }
            }
        }
        return result;
    }

    // ============================================================
    // ASSET-NET RESOLUTION — currency-aware, Generate-anchored (reused from prehook)
    // ============================================================

    /**
     * @description assetId -> (CurrencyIsoCode -> NetUnitPrice), all values > 0. ONE
     *              query for ALL assets. A 'Generate' / Initial-Sale row wins per
     *              (asset, currency); otherwise the most-recent positive priced row.
     *              SOQL filters NetUnitPrice > 0 so a zero-net Generate can never lock
     *              an (asset, currency) at 0 and starve a later positive row / the
     *              ListPrice fallback.
     */
    @TestVisible
    private static Map<Id, Map<String, Decimal>> resolveAssetNetByCurrency(Set<Id> assetIds) {
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

        Set<String> generateLocked = new Set<String>();
        // Oldest -> newest so a later non-Generate replaces an earlier one; Generate
        // rows are sticky (a Generate may only be replaced by another Generate).
        for (AssetActionSource s : [
            SELECT AssetAction.AssetId, AssetAction.Type, NetUnitPrice, CurrencyIsoCode
            FROM AssetActionSource
            WHERE AssetAction.AssetId IN :cleanIds
              AND NetUnitPrice > 0
            ORDER BY CreatedDate ASC
        ]) {
            if (s.AssetAction == null || s.AssetAction.AssetId == null) {
                continue;
            }
            if (s.NetUnitPrice == null || s.NetUnitPrice <= 0) {
                continue;
            }
            if (String.isBlank(s.CurrencyIsoCode)) {
                continue;
            }
            Id assetId = s.AssetAction.AssetId;
            String cur = s.CurrencyIsoCode;
            String key = assetId + '|' + cur;
            Boolean isGenerate = PRICED_SALE_TYPES.contains(s.AssetAction.Type);

            if (!netByCurrency.containsKey(assetId)) {
                netByCurrency.put(assetId, new Map<String, Decimal>());
            }
            Map<String, Decimal> byCur = netByCurrency.get(assetId);

            if (!byCur.containsKey(cur)) {
                byCur.put(cur, s.NetUnitPrice);
                if (isGenerate) {
                    generateLocked.add(key);
                }
            } else if (isGenerate) {
                byCur.put(cur, s.NetUnitPrice);     // newest Generate wins
                generateLocked.add(key);
            } else if (!generateLocked.contains(key)) {
                byCur.put(cur, s.NetUnitPrice);     // newest non-Generate wins (no Generate yet)
            }
        }
        return netByCurrency;
    }

    /**
     * @description Per-line NET magnitude to seed (positive), currency-aware. Order:
     *              (1) asset net in the line's currency; (2) asset net when the line has
     *              no currency and the asset is single-currency; (3) LOSSY ListPrice
     *              fallback (> 0 only); else null (skip). Pure — no SOQL.
     */
    @TestVisible
    private static Decimal resolveSeedNet(
        Id assetId,
        String lineCurrency,
        Decimal listPrice,
        Map<Id, Map<String, Decimal>> netByCurrency
    ) {
        if (assetId != null && netByCurrency != null && netByCurrency.containsKey(assetId)) {
            Map<String, Decimal> byCur = netByCurrency.get(assetId);
            if (byCur != null && !byCur.isEmpty()) {
                if (String.isNotBlank(lineCurrency)) {
                    if (byCur.containsKey(lineCurrency)) {
                        Decimal net = byCur.get(lineCurrency);
                        if (net != null && net > 0) {
                            return net;
                        }
                    }
                    // currency mismatch / non-positive -> fall through to ListPrice.
                } else if (byCur.size() == 1) {
                    Decimal only = byCur.values()[0];
                    if (only != null && only > 0) {
                        return only;
                    }
                }
            }
        }
        // LOSSY fallback: line's own catalog ListPrice (already line-currency), > 0 only.
        if (listPrice != null && listPrice > 0) {
            return listPrice;
        }
        return null;
    }

    // ============================================================
    // HELPERS
    // ============================================================

    /** Null-safe numeric coercion for dynamically-read SObject field values. */
    @TestVisible
    private static Decimal toDecimal(Object val) {
        if (val == null) {
            return null;
        }
        if (val instanceof Decimal) {
            return (Decimal) val;
        }
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }
}
