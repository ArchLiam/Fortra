# V21 NET-PATH MAP — every NetUnitPrice / ItemNetTotalPrice writer and whether an amend line reaches a nonzero value

Source: `Data/amend-pricing/retrieve/v21_live.json` (ACTIVE V21, ESV `9QMWC00000025LN4AY`, 122 steps).
Subject AA line profile: `ItemPricingSource='LastTransaction'`, `QuoteTypeText__c='Amendment'`, `ItemIsDerived__std=false`, `DerivedPricingAttribute=false`, `SellingModelType='OneTime'`, CAD.
Derived-amend-maintenance profile (2nd class): same but `ItemIsDerived__std=true`, `DerivedPricingAttribute=true`.

Gate mechanism: each `ListGroup` container has one child `AdvancedListFilter` (`advancedCondition.criteria`) that decides which lines enter the container. A leaf BusinessKnowledgeModel writer runs only if its container's filter passes.

## A. Steps that WRITE NetUnitPrice (12)

| seq | step (writer) | container (seq) | container gate | AA amend | derived amend-maint |
|----|----|----|----|----|----|
| 2 | AttributeBasedPrice | ListContainer (4) | `ItemContractAttributePasId IsNotNull AND ItemPricingSource NotEquals 'LastTransaction' AND DerivedPricingAttribute IsNotNull AND =false` | **SKIP** (gate#2 LastTransaction) | SKIP |
| 2 | AttributeDiscountEntries | ListContainer7 (5) | `(IsContracted IsNull OR =false) AND ItemPricingSource NotEquals 'LastTransaction'` | **SKIP** | SKIP |
| 3 | AttributeValuePricingUnitPriceModeNetBridge | ListContainer5 (6) | `Has_Attribute_Adjustment__c=true AND Attribute_Price_Mode__c='Unit Price'` | SKIP (no attr adj / not LastTxn-relevant; AA has none) | SKIP |
| 3 | AttributeValuePricingCalculatedModeNetBridge | ListContainer6 (7) | `Has_Attribute_Adjustment__c=true AND Attribute_Price_Mode__c='Calculated'` | SKIP | SKIP |
| 3 | AttributeValuePricingTotalPriceModeNetBridge | ListContainer720 (8) | `Has_Attribute_Adjustment__c=true AND Attribute_Price_Mode__c='Total Price'` | SKIP | SKIP |
| 2 | BundleBasedAdjustmentEntries | ListContainer25 (9) | `ItemPricingSource NotEquals 'LastTransaction'` | **SKIP** | SKIP |
| 2 | VolumeDiscountEntries | ListContainer28 (10) | `(IsContracted IsNull OR =false) AND ItemPricingSource NotEquals 'LastTransaction'` | **SKIP** | SKIP |
| 2 | PartnerDiscount55 | ListContainer3 (19) | `Deal_Type__c NotEquals 'Fortra Originated' AND (ItemIsDerived__std IsNull OR =false)` — **no LastTransaction guard** | enters IF deal-type≠FortraOriginated, BUT writes `NetUnitPrice = PartnerNet of an already-0 base` → still 0 (no asset seed) | n/a (derived excluded by gate#2) |
| 3/4 | ManualQuoteLevelAmountBased / PercentageBasedLineLevel | ListContainer56 (20) | `ItemPricingSource NotEquals 'LastTransaction' AND (Action Amend/Add/null) AND (Derived null/false)` | **SKIP** (gate#1 LastTransaction) | SKIP |
| 2 | PartnerDiscountDerivedMaintenance63 | PartnerDiscountDerivedMaintenance (21) | `ItemIsDerived__std=true AND Deal_Type≠'Fortra Originated' AND ItemPricingSource NotEquals 'LastTransaction' AND QuoteTypeText__c NotEquals 'Renewal'` | SKIP (not derived) | **SKIP** (gate#3 LastTransaction) |
| 4 | ManualDiscountDerivedMaintenance | PartnerDiscountDerivedMaintenance (21) | same as above | SKIP | **SKIP** |
| 3 | COLAUpliftNetonRenewal | ListContainer2 (23) | `ItemPricingSource='LastTransaction' AND Derived IsNotNull AND =false AND SalesTransactionActionType='Renew' AND COLA_Uplift_Percent__c IsNotNull` | **SKIP** (gate#5 ActionType='Renew'; amend ActionType='Amend') | SKIP (derived) |
| 2 | DerivedPricingFormula | ListContainer9 (17) | `ItemIsDerived__std=true` | SKIP (not derived) | **PASS** → see §C |
| 2 | DerivedPricingNetUnitPriceValueReset | ListContainer10 (22) | `ItemIsDerived__std=true` | SKIP (not derived) | **PASS** → see §C (RESETS to 0) |
| 3 | SubscriptionPricing | Evergreenanytimeproration… (27) | `SellingModelType='Evergreen' AND AllowPartialProrationPeriods=true AND itemTransientEndDate IsNotNull` | SKIP (OneTime) | SKIP |
| 35 | **CurrencyConversionNetUnitPrice** | (top-level, ungated) | none | **RUNS**: `NetUnitPrice = NetUnitPrice * rate(CAD 1.3889)` → `0 * 1.3889 = 0` (preserves 0) | RUNS, preserves whatever §C produced |
| 1 | **PricingSetting** (Get) | (top-level, ungated) | none | **RUNS** — the ONLY NET seed for amend lines; returns **NetUnitPrice=0** for the amend line | RUNS, =0 |

## B. Steps that WRITE ItemNetTotalPrice (15) — derived from NetUnitPrice, never independently seed it
| seq | step | container (seq) | gate | AA amend |
|----|----|----|----|----|
| 1 | PricingSetting (Get) | top-level | none | RUNS, ItemNetTotalPrice=0 |
| 2 | PriceBookEntries | top-level | none | RUNS but writes list `Subtotal`/ItemNetTotalPrice base; overwritten downstream; net path still 0 |
| 2 | FormulaBasedPricing | **ListContainer79 (26)** | **`ItemPricingSource Equals 'LastTransaction'`** | **PASS — the ONLY container the AA amend line passes** → `ItemNetTotalPrice = NetUnitPrice * LineItemQuantity = 0 * 2 = 0` |
| 2 | QuantityPrice78 | ListContainer76 (25) | `ItemPricingSource NotEquals 'LastTransaction' AND Derived=false` | SKIP |
| 2 | AttributeBasedPrice/AttributeDiscountEntries/Bundle/Volume/Partner* | (as §A) | (as §A) | SKIP/0 |
| 3 | SubscriptionPricing | (27) | Evergreen | SKIP |
| 2 | ServicesAggregatePrice / SoftwareAggregatePrice / SubscriptionAggregatePrice | ListContainer8 / copies (32-34) | `Fortra_Product_Type__c = Services/Software/Subscription` | group rollups, read-only over line nets (all 0) |
| 37 | CurrencyConversionNetTotalSubtotal | top-level | none | RUNS: `ItemNetTotalPrice * rate` → `0 * 1.3889 = 0` |
| 39 | TotalAmount | top-level | `ItemNetTotalPrice IsNotNull AND Derived=false` | rollup of 0 |
| 42 | AggregatePrice115 | top-level | `SalesTransactionItemGroup IsNotNull AND Derived=false` | rollup |

## C. DERIVED amend-maintenance path (2nd defect class) — ListContainer9 + ListContainer10 both gate ONLY on `ItemIsDerived__std=true` (NO ItemPricingSource guard)

- **DerivedPricingFormula** (seq2, ListContainer9, gate `ItemIsDerived__std=true`):
  `NetUnitPrice = IF(QuoteTypeText__c='Renewal', NetUnitPrice, <attr% * base>)`
  For a **Renewal** derived line: keeps existing NetUnitPrice. For an **Amendment** derived line: falls into the ELSE and recomputes from `Base_Price__c / Pre_Partner_Price__c / InputUnitPrice` — on an amend line those base inputs are typically null/0 (derivation steps were skipped) → **0**.
- **DerivedPricingNetUnitPriceValueReset** (seq2, ListContainer10, gate `ItemIsDerived__std=true`):
  `NetUnitPrice = IF(QuoteTypeText__c='Renewal', NetUnitPrice, 0)`
  For an **Amendment** derived line: `QuoteTypeText__c='Amendment' ≠ 'Renewal'` → **NetUnitPrice forcibly RESET to 0.**

So a DERIVED Amendment maintenance line is zeroed by BOTH the formula ELSE branch AND the explicit reset — even if a seed had been carried. This is a SECOND, distinct defect class from the non-derived AA gross/net case. The AA subject line (`ItemIsDerived__std=false`) does NOT hit these (gates require true), confirming the prompt's note.

## D. Proof the AA amend line reaches NO nonzero NetUnitPrice writer
1. Only the seed `PricingSetting` (seq1, Get) and the ungated `CurrencyConversionNetUnitPrice` (seq35) run for the AA amend line on the NET path. Seq1 returns 0; seq35 multiplies 0 → 0.
2. Every derivation/discount writer of NetUnitPrice is gated `ItemPricingSource NotEquals 'LastTransaction'` (AttributeBasedPrice, AttributeDiscountEntries, Bundle, Volume, ManualQuoteLevel, QuantityPrice78) — SKIP.
3. The one container that DOES pass LastTransaction lines — **ListContainer79 (gate `ItemPricingSource Equals 'LastTransaction'`)** — contains only `FormulaBasedPricing` which writes **ItemNetTotalPrice = NetUnitPrice * Qty**. It never writes NetUnitPrice, so it cannot inject the asset seed; it just propagates the 0.
4. **No step anywhere in V21 writes `UnitPrice`** (the gross field that carried 5906.29725). UnitPrice is hydrated natively/by PricingSetting input; the V21 "gross guards" (CurrencyConversionTotalLineAmount seq38, FormulaBasedPricing3 seq40 = `MAX(ItemNetTotalPrice,TotalLineAmount)`) only touch TotalLineAmount, never NetUnitPrice. That asymmetry is exactly why GROSS carries but NET collapses.

## E. The seed value is available
`5906.29725 = AssetActionSource.NetUnitPrice` lands in UnitPrice (carried) but PricingSetting seq1 returns 0 for the NET output of the amend line. The asset net seed exists; nothing copies it into NetUnitPrice on the LastTransaction path.

## F. FIX LOCUS
**Primary (covers the AA non-derived case): one place.** Add a NetUnitPrice carry for LastTransaction lines BEFORE the currency conversion (seq35) and ideally right after PricingSetting (seq ~1–2), inside (or as a sibling of) **ListContainer79** (gate `ItemPricingSource Equals 'LastTransaction'`). It must set `NetUnitPrice` from the asset net seed (the same source that now lands in UnitPrice, e.g. `AssetActionSource.NetUnitPrice` / carried UnitPrice / PriceWaterfall net), then let the existing `FormulaBasedPricing` (`NetUnitPrice * Qty`) produce ItemNetTotalPrice and currency steps multiply by rate. This single carry restores NetUnitPrice/NetTotalPrice/TotalPrice for non-derived amend lines.

**Secondary (covers DERIVED amend-maintenance lines): yes, a 2nd fix is needed.** ListContainer9/ListContainer10 must treat `Amendment` like `Renewal`:
- DerivedPricingNetUnitPriceValueReset: `IF(QuoteTypeText__c='Renewal' OR QuoteTypeText__c='Amendment', NetUnitPrice, 0)` (or add `AND ItemPricingSource NotEquals 'LastTransaction'` to the ListContainer10 gate so amend/LastTransaction derived lines are excluded from the reset).
- DerivedPricingFormula: same `OR 'Amendment'` in the leading IF so the carried net is preserved for amend derived lines.

Without the secondary fix, derived/maintenance amendment lines remain $0 even after the primary carry, because both ListContainer9 and ListContainer10 gate only on `ItemIsDerived__std=true` and zero non-Renewal nets.
