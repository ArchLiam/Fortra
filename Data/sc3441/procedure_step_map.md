# SC-3441 — Rev_Mgmt_Default_Pricing_Procedure step map (cancellation $0 RCA)

File: `Data/sc3441/retrieve/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition` (api v66, 92,611 lines).
The file holds ALL 17 `<versions>` blocks (V1..V17). They are version copies, NOT pipeline variants.

## Active versions (live, FortraUAT, tooling API)
ExpressionSetDefinition Id `9QAWC0000003mg14AA`.
Two versions are Active simultaneously (anomaly):
- V14 `9QBWC0000000nIT4AY` Active, startDate 2026-06-18, created 06-13, mod 06-23
- V16 `9QBWC0000000niH4AQ` Active, startDate 2026-06-18, created 06-21, mod 06-23

Both same startDate / no rank / no endDate -> RLM resolves to highest version number = **V16** executes.
- V14 block: file lines 69795–75411
- V16 block: file lines 80964–86874  (description: "V16 - waterfall pricing (Active)")

## V16 relevant pipeline (sequence within the line-pricing tree)
| role | step name | actionType | file line | what it does |
|---|---|---|---|---|
| list lookup | PriceBookEntries | ListPrice | 84890 | PBE V2 decision table -> outputs **ListPrice** (=3000) and Subtotal->ItemNetTotalPrice. Does NOT write InputUnitPrice/NetUnitPrice/UnitPrice |
| native waterfall | PricingSetting | PricingSettings | 85089 | native price waterfall -> outputs **NetUnitPrice**, PriceWaterfall, Subtotal. Keyed off LineItem/Contract/IsDerived. Returns NULL NetUnitPrice + null PriceWaterfallIdentifier for the cancellation line |
| **seed (REGRESSED)** | Assignment "Sync InputUnitPrice from Net" | AssignmentElement | 81321 | **copies NetUnitPrice -> InputUnitPrice** (V14 copied **ListPrice -> InputUnitPrice** here). parent ListContainer47 |
| seed gate | "List Operation" filter | AdvancedListFilter | 83866 | gates ListContainer47: `InputUnitPrice IsNull AND ItemPricingSource != 'LastTransaction' AND DerivedPricingAttribute = false`. This IS the null-fallback hook |
| subscription | SubscriptionPricing86 | SubscriptionPricing | 86081 | TermDefined/Evergreen path (ListContainer84 filter @84046). reads NetUnitPrice=InputUnitPrice INPUT, outputs InputUnitPrice/TotalLineAmount. Pure multiplier — null in => null out |
| line total | QuantityPrice64 "Quantity * Price" | FormulaBasedPricing | 85362 | **ItemNetTotalPrice = NetUnitPrice * LineItemQuantity** (gate @85294: DerivedPricingAttribute=false, not LastTransaction). NetUnitPrice null => 0 |
| total copy | Assignment108 | AssignmentElement | ~81443 | TotalLineAmount->ItemSubtotal, **ItemNetTotalPrice->ItemTotalPrice** |

## Only ListPrice->NetUnitPrice path in V16 = derived/renewal (does NOT apply)
- `Derived Products - Renewals` (DerivedPricing, file 83121) reads ListPrice, writes NetUnitPrice — but gated to IsDerived/Renewal. Arcus Hosting line is IsDerived=false, non-renewal.
- `grep` confirms: V16 has **0** `section-0-input1=ListPrice -> InputUnitPrice/NetUnitPrice` assignments; V14 has **1**.

## ROOT CAUSE
For the cancellation line (Qty -1, TermDefined subscription, IsDerived=false):
1. PBE lookup fills ListPrice=3000 only.
2. Native PricingSettings waterfall returns NULL NetUnitPrice (PriceWaterfallIdentifier=null) — the cancellation/negative-delta line has no waterfall.
3. ListContainer47 seed fires (`InputUnitPrice IsNull`) but in V16 copies **NetUnitPrice (null) -> InputUnitPrice**, so InputUnitPrice stays null. In V14 it copied **ListPrice (3000) -> InputUnitPrice**, which rescued it.
4. SubscriptionPricing86 multiplies null -> null InputUnitPrice/NetUnitPrice.
5. `NetUnitPrice * LineItemQuantity` = null*-1 = 0 -> ItemNetTotalPrice 0 -> ItemTotalPrice 0 => TotalPrice 0.

## DATA PROOF
- Cancel line 802WC00000OugI7YAJ: ListPrice 3000, **UnitPrice null, NetUnitPrice null, PriceWaterfallIdentifier null**, TotalPrice 0, Fortra_Product_Type__c null.
- Normal +1 Arcus Hosting lines (e.g. 802WC00000OtSYxYAN): UnitPrice 3000, NetUnitPrice 3000, **PriceWaterfallIdentifier populated**, TotalPrice 3000.
- The differentiator is the native waterfall (PriceWaterfallIdentifier) — populated on normal lines, null on the cancellation line; V16 removed the ListPrice fallback that previously covered the null-waterfall case.

## CLASSIFICATION
MISSING FALLBACK (regression). The line→net seed at ListContainer47/Assignment (file 81321) was changed in V16 from `ListPrice -> InputUnitPrice` to `NetUnitPrice -> InputUnitPrice`. No condition actively excludes the negative-qty line; the line total formula does run — it just multiplies a null base price. Fix lever: restore a ListPrice (or COALESCE(NetUnitPrice, ListPrice)) source on the InputUnitPrice null-seed, or ensure the cancellation line carries the asset/original net price.
