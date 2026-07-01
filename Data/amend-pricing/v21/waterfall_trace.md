# V21 Waterfall Execution Trace — Subject Amend Line (AA Modes Qty2)

Proc: "Revenue Management Default Pricing Procedure" ACTIVE V21 (ESV 9QMWC00000025LN4AY).
Snapshot: `Data/amend-pricing/retrieve/v21_live.json` -> `result.records[0].Metadata.steps[]` (122 steps).
Subject: Quote 0Q0WC000003FNXF0A4 (CAD), QLI 0QLWC000003kXyX4AU "Advanced Authentication Modes" Qty2.

## Live QLI state (post-V21 reprice 19:43)
```
ListPrice            = 4252.5
UnitPrice            = 5906.29725   (= AssetActionSource.NetUnitPrice asset seed, CARRIED OK)
TotalLineAmount      = 11812.5945   (= UnitPrice * 2, OK)
Subtotal             = 11812.5945   (OK)
NetUnitPrice         = 0            (WRONG)
NetTotalPrice        = 0            (WRONG)
TotalPrice           = 0            (WRONG)
TotalAdjustmentAmount= -11812.5945  (= NetTotal - TotalLineAmount = 0 - 11812.59, computed)
DiscountAmount       = null
PriceWaterfallIdentifier = 0QLWC000003kXyX4AU:892551213421448
```
Line facts: PBE IsDerived=false (NON-derived), SellingModelType=**OneTime**, Quantity=2.

## Stored waterfall / adjustments
- `QuoteLinePriceAdjustment` WHERE QuoteLineItemId=subject: **0 rows**. The -11812.59 in
  TotalAdjustmentAmount is NOT a persisted adjustment record — it is the computed delta
  (NetTotal - TotalLineAmount) stamped by the aggregate/total steps. So the net collapse is
  upstream of any adjustment, not caused by one.
- No PriceAdjustmentSchedule/Tier rows drive this line.

## Top-level execution order (parentStep=None), sequenceNumber
```
 1  PricingSetting                    (PricingSettings, RevSignaling Get)
 2  PriceBookEntries
 3  PricingEffectiveDates
 4..34  ListContainer* (line-scoped pricing containers, each gated by a child filter)
 35 CurrencyConversionNetUnitPrice    NetUnitPrice      = NetUnitPrice      * rate
 36 CurrencyConversionUnitPriceDisplay InputUnitPrice    = InputUnitPrice    * rate
 37 CurrencyConversionNetTotalSubtotal ItemNetTotalPrice = ItemNetTotalPrice * rate
 38 CurrencyConversionTotalLineAmount  TotalLineAmount   = TotalLineAmount   * rate
 39 TotalAmount                       SUM(ItemNetTotalPrice) -> TotalAmount
 40 FormulaBasedPricing3              TotalLineAmount = IF(ItemNetTotalPrice>TotalLineAmount, ItemNetTotalPrice, TotalLineAmount)
 41 AggregatePrice                    SUM(TotalLineAmount) -> Subtotal
 42 AggregatePrice115                 SUM(ItemNetTotalPrice) -> ItemGroupSummarySubtotal
 43 ListContainer11 (NullSafeLineAdjustment)
 44 Assignment119                     ItemSubtotal = TotalLineAmount ; ItemTotalPrice = ItemNetTotalPrice
```

## The two parallel rails

### GROSS rail (rides InputUnitPrice) — gets the seed correctly
- `InputUnitPrice` defaults from QLI.UnitPrice at context load. The amendment flow stamped
  QLI.UnitPrice = asset seed 5906.29725 before pricing ran, so InputUnitPrice = 5906.30.
- OneTime line => ListContainer86 fires (filter ListOperation87: SellingModelType NotEquals
  'Evergreen' AND NotEquals 'TermDefined').
- **SubscriptionPricing89 (seq3, parent ListContainer86):** inputs `NetUnitPrice=InputUnitPrice`,
  Quantity=LineItemQuantity; OUTPUTS `TotalSubscriptionPrice=TotalLineAmount`,
  `SubscriptionNetUnitPrice=InputUnitPrice`. => TotalLineAmount = 5906.30 * 2 = 11812.59.
  NOTE: the param literally named "NetUnitPrice" here is a LOCAL input fed from InputUnitPrice;
  this step does NOT write the context NetUnitPrice field. Its only outputs are TotalLineAmount
  and InputUnitPrice.
- CurrencyConversionUnitPriceDisplay(36)/TotalLineAmount(38): CAD rate 1.3889... but the seed was
  already in the displayed currency, so net effect leaves UnitPrice/TotalLineAmount = 5906.30 / 11812.59.

### NET rail (rides context NetUnitPrice / ItemNetTotalPrice) — never re-seeded, stays 0
- **PricingSetting (seq1, parent None):** OUTPUTS `NetUnitPrice<-NetUnitPrice`,
  `Subtotal<-ItemNetTotalPrice`, `PriceWaterfall<-price_water_fall`. For a brand-new amendment
  QLI there is no prior waterfall/contract net row for this line in the RevSignaling store, so it
  returns **NetUnitPrice = 0 and ItemNetTotalPrice = 0**. THIS IS THE ZERO SEED.
- Every step that could put a nonzero value into context NetUnitPrice or ItemNetTotalPrice is
  inside a container gated `ItemPricingSource NotEquals 'LastTransaction'` (amend lines carry
  ItemPricingSource='LastTransaction'), so ALL of them SKIP the amend line:
    - QuantityPrice78 (ListContainer76): `ItemNetTotalPrice = NetUnitPrice * LineItemQuantity`
      — gate QuantityPrice requires ItemPricingSource NotEquals 'LastTransaction'. SKIPPED.
      (This is the step that would have made ItemNetTotalPrice follow NetUnitPrice; it never runs.)
    - SyncInputUnitPricefromNet (ListOperation38 gate: ItemPricingSource NotEquals 'LastTransaction'
      AND InputUnitPrice IsNull AND non-derived). SKIPPED (also InputUnitPrice already non-null).
    - StampBase_PriceandPre_PartnerfromNet (StampBaseFilter: ... AND ItemPricingSource NotEquals
      'LastTransaction' AND NetUnitPrice>0). SKIPPED.
    - AttributeBasedPrice / AttributeDiscountEntries / VolumeDiscountEntries / PartnerDiscount55 /
      BundleBasedAdjustmentEntries / QuantityPrice78 / SubscriptionPricing(net) / GSA / Regional —
      all gated off for LastTransaction (or for Renewal / derived / attribute-mode only).
- **DerivedPricingNetUnitPriceValueReset (seq2, ListContainer10):**
  `NetUnitPrice = IF(QuoteTypeText__c='Renewal', NetUnitPrice, 0)`. Gate DerivedPricingFilter =
  `ItemIsDerived__std = true`. Subject line is NON-derived => this step does NOT run on the AA line,
  so it is NOT the cause here. (It WOULD zero NetUnitPrice for DERIVED/maintenance amend lines on
  non-Renewal quotes — check it for those.)
- CurrencyConversionNetUnitPrice(35) and CurrencyConversionNetTotalSubtotal(37) multiply 0 by the
  rate => still 0. They preserve, never create, the zero.

## Collapse point into TotalPrice
- **TotalAmount (seq39):** SUM(ItemNetTotalPrice)=0.
- **FormulaBasedPricing3 (seq40):** TotalLineAmount = IF(ItemNetTotalPrice(0) > TotalLineAmount(11812.59), 0, 11812.59) = 11812.59. (gross preserved)
- **Assignment119 (seq44):** `ItemSubtotal = TotalLineAmount` = 11812.59 (Subtotal OK);
  `ItemTotalPrice = ItemNetTotalPrice` = **0** => TotalPrice = 0.
  TotalAdjustmentAmount is then NetTotal(0) - TotalLineAmount(11812.59) = -11812.59.

## VERDICT
NetUnitPrice is **NEVER SEEDED** (not "zeroed later"):
- It comes out of **PricingSetting (seq1)** as 0 for the amendment line.
- No subsequent step writes a nonzero value into the context NetUnitPrice / ItemNetTotalPrice for a
  LastTransaction line, because every net-writing step is gated `ItemPricingSource NotEquals
  'LastTransaction'`. The would-be rescuer **QuantityPrice78** (ItemNetTotalPrice = NetUnitPrice *
  Qty) is itself gated off.
- The gross fields are correct only because they ride a SEPARATE variable, **InputUnitPrice**
  (defaulted from QLI.UnitPrice = the flow-stamped asset seed), through SubscriptionPricing89.

## FIX LOCUS (for the owner; do not deploy here)
V21's "guards" land the asset seed in InputUnitPrice (=> UnitPrice/TotalLineAmount) but do NOT
mirror it into the context NetUnitPrice/ItemNetTotalPrice. The symmetric guard is missing:
for ItemPricingSource='LastTransaction' (amend) lines, seed
  NetUnitPrice      = InputUnitPrice (asset seed), and
  ItemNetTotalPrice = NetUnitPrice * LineItemQuantity
in an amend-only container that runs BEFORE the CurrencyConversion steps (seq35-38), mirroring the
existing SubscriptionPricing89 gross path. DerivedPricingNetUnitPriceValueReset is a separate hazard
ONLY for derived/maintenance amend lines on non-Renewal quotes.
