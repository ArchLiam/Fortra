# V21 Amend-line NET collapse — PricingSetting + Guard-step analysis

Subject: amend quote `0Q0WC000003FNXF0A4` (CAD), line "Advanced Authentication Modes" Qty2,
QLI `0QLWC000003kXyX4AU`. Repriced 19:43 under V21.

Observed (V21): ListPrice=4252.5 ; UnitPrice=5906.29725 (CARRIES) ; TotalLineAmount=11812.5945 (OK) ;
Subtotal=11812.5945 (OK) ; **NetUnitPrice=0 ; NetTotalPrice=0 ; TotalPrice=0 (WRONG)**.

Source: `Data/amend-pricing/retrieve/v21_live.json` (ACTIVE V21, ESV 9QMWC00000025LN4AY).
Decoded steps: `Data/amend-pricing/v21/_steps_pretty.json` (result.records[0].Metadata.steps[]).

---

## 1. PricingSetting element — there is NO customer Apex behind it

`PricingSetting` (seq1, `stepType=BusinessKnowledgeModel`, **`actionType="PricingSettings"`**) is a
**native Salesforce RLM platform element** (Revenue Cloud "Pricing Settings" / price-waterfall hydration),
not a `RevSignaling.SignalingApexProcessor` custom class. Verified by Tooling query:

    SELECT Name FROM ApexClass WHERE Name LIKE '%PricingSetting%' OR '%RevSignaling%'
       OR '%SignalingApex%' OR '%PricingStore%' OR '%Signal%' OR '%Waterfall%'  -> 0 / no match

The only Apex pricing extensions in the org are the prehook/posthook plugins
(AttributeVolumePricingPrehook, PartnerNetPricePosthook, RegionalServicesPricingPrehook,
ConfigurablePricingPlugin*, RenewalMaintenancePricingService, …) — none implements PricingSettings.
**So "Get" is a platform black box; the fix cannot and must not be done in Apex. It is a proc-config fix.**

PricingSetting parameters (from v21_live.json):
- INPUTS: LineItemId=LineItem, CurrencyIsoCode, IsDerived=DerivedPricingAttribute,
  ContractId=ItemContract, selectedFunction=**Get**, IsRealTime=false, IsPropagationEnabled=false.
- OUTPUTS: PriceWaterfall->`price_water_fall`, NetUnitPrice->**`NetUnitPrice`**, Subtotal->`ItemNetTotalPrice`.

For an amend line (`ItemPricingSource='LastTransaction'`) "Get" hydrates the waterfall from the carried
transaction. It lands the carried unit price into the **gross** lane (`InputUnitPrice`, the waterfall base)
but returns **NetUnitPrice = 0 / ItemNetTotalPrice = 0** — the net store is empty for the carried line.
That single platform behavior is the root: NetUnitPrice is born 0 on amend lines and nothing re-seeds it.

---

## 2. Why UnitPrice (5906.30) CARRIES but NetUnitPrice does NOT — the two lanes

5906.29725 = AssetActionSource.NetUnitPrice (the asset net seed). It rides the **gross/InputUnitPrice lane**,
which has steps that pass amend lines, while the **NetUnitPrice lane** has none.

GROSS lane (carries — passes amend lines, NO LastTransaction exclusion):
- `SubscriptionPricing95` (seq2, parent `ListContainer93`, gate = SellingModelType `TermDefined`/`Evergreen`):
  in NetUnitPrice=**InputUnitPrice**, Quantity=LineItemQuantity, ProrationMultiplier=PricingTermCount;
  OUT TotalSubscriptionPrice->**TotalLineAmount**, SubscriptionNetUnitPrice->**InputUnitPrice**.
  => TotalLineAmount = InputUnitPrice x Qty x proration = 11812.5945.  (this container is NOT gated off amend lines)
- `CurrencyConversionUnitPriceDisplay` (seq36): InputUnitPrice x rate(CAD 1.3889) -> InputUnitPrice  => the
  displayed **UnitPrice** = 5906.30.
- `CurrencyConversionTotalLineAmount` (seq38): TotalLineAmount x rate -> TotalLineAmount (OK).
- `Assignment119` (seq44): `ItemSubtotal = TotalLineAmount` -> Subtotal = 11812.59 (OK).

NET lane (collapses — the ONLY amend-gated guard consumes NetUnitPrice, never seeds it):
- `ListContainer79` (seq26, ListGroup; member filter = child `ListOperation80`:
  ItemPricingSource **Equals** 'LastTransaction') — the amend-line guard container. Its sole action:
  - `FormulaBasedPricing` (seq2): **`ItemNetTotalPrice = NetUnitPrice * LineItemQuantity`** = 0 x 2 = **0**.
    It READS NetUnitPrice (still 0 from PricingSetting) and writes the net total. It never sets NetUnitPrice.
- `CurrencyConversionNetUnitPrice` (seq35): 0 x rate -> 0.  `CurrencyConversionNetTotalSubtotal` (seq37): 0 x rate -> 0.
- `Assignment119` (seq44): `ItemTotalPrice = ItemNetTotalPrice` -> **TotalPrice = 0**.

All other NetUnitPrice writers are gated OFF amend lines (ItemPricingSource **NotEquals** 'LastTransaction')
or off-context: AttributeBasedPrice, AttributeDiscountEntries, BundleBasedAdjustmentEntries (LC25),
VolumeDiscountEntries, PartnerDiscount55, ManualQuoteLevel*, SyncInputUnitPricefromNet, QuantityPrice78, etc.
The only amend-gated (Equals LastTransaction) NetUnitPrice writers are the COLA-renewal pair in `ListContainer2`
(`COLAUpliftonRenewal71`->InputUnitPrice, `COLAUpliftNetonRenewal`->NetUnitPrice), but they require
SalesTransactionActionType='Renew' + DerivedPricingAttribute=false + COLA_Uplift_Percent__c not null — the
AA Amend line is Action='Amend', so it does not qualify. => Net is NEVER re-seeded for plain amend lines.

### Confirmation: NONE of the V21 guard steps writes NetUnitPrice/ItemNetTotalPrice as a SEED for amend lines
- `Assignment98` (LC96, gate InclusivePrice=true): writes TotalLineAmount=InclusivePriceConstant only.
- `Assignment119` (top-level): writes ItemSubtotal & ItemTotalPrice (copies, downstream of the 0).
- `SubscriptionPricing95` (LC93): writes TotalLineAmount & InputUnitPrice (gross), not Net.
- `FormulaBasedPricing` (LC79, the LastTransaction guard): writes ItemNetTotalPrice = NetUnitPrice*Qty (consumes 0).
=> The asymmetry is real: V21 seeds the gross lane (InputUnitPrice) but never the net lane (NetUnitPrice).

---

## 3. Minimal fix — seed NetUnitPrice from the carried gross seed inside the existing amend guard

The carried asset seed already sits in `InputUnitPrice` (that is what becomes UnitPrice=5906.30). For a plain
amend line the credit/net should equal the carried asset net (= the same value). So mirror the gross carry into
the net lane by copying InputUnitPrice -> NetUnitPrice **before** the existing `FormulaBasedPricing` recompute,
so that `ItemNetTotalPrice = NetUnitPrice * Qty` then yields the correct net total automatically.

Implement as ONE new BusinessKnowledgeModel step inside `ListContainer79` (already filtered to
ItemPricingSource='LastTransaction'), ordered to run BEFORE `FormulaBasedPricing` (give it a lower
sequenceNumber within the container, e.g. seq=1.5 / re-rank child FormulaBasedPricing after it).

Preferred (AssignmentElement, no proration ambiguity) — new child of ListContainer79:

    name: AmendNetSeedFromCarry   (actionType=AssignmentElement)
    parent: ListContainer79
    run-order: BEFORE FormulaBasedPricing
    assignment:  NetUnitPrice = InputUnitPrice
    (section-0-input1 = InputUnitPrice ; section-0-output = NetUnitPrice ; sectionCount=1)

Then the EXISTING `FormulaBasedPricing` (ItemNetTotalPrice = NetUnitPrice * LineItemQuantity) produces
ItemNetTotalPrice = 5906.29725 * 2 = 11812.5945, the CAD currency-conversion steps scale both consistently,
and `Assignment119` stamps Subtotal/TotalPrice correctly. Net result on the subject line:
NetUnitPrice=5906.30, NetTotalPrice=11812.59, TotalPrice=11812.59.

Equivalent single-formula alternative (if you prefer to also fix the total in the same step), REPLACE the
ListContainer79 `FormulaBasedPricing` input formula AND add the net-unit assignment — but the 2-step
assignment-then-existing-formula keeps proration handling identical and is the smaller diff.

### Guards / safety
- Scope is exact: ListContainer79 already filters to `ItemPricingSource='LastTransaction'`, so only amend
  (carried) lines are touched; new-sale/list/derivation lines are untouched.
- DERIVED / maintenance amend lines: those carry through `DerivedPricingNetUnitPriceValueReset`
  (LC10, formula `IF(QuoteTypeText__c='Renewal', NetUnitPrice, 0)`, gated ItemIsDerived__std=true) which
  zeroes NetUnitPrice for non-Renewal derived lines. If we seed NetUnitPrice in LC79 (seq26) it runs BEFORE
  LC10 work? — verify run order: LC10 is seq22 (earlier) so it runs before LC79; the AA subject line is
  NON-derived (PBE IsDerived=false) so LC10 does not apply. For derived amend lines confirm LC79 (seq26)
  fires after LC10 (seq22) — it does — so the seed survives. Add a guard `NetUnitPrice IsNull OR = 0` on the
  new assignment if there is any risk of clobbering a legitimately re-derived non-zero net.
- Currency: seed BEFORE the CurrencyConversion* steps (seq35-38) so the CAD scaling applies once, consistently
  with UnitPrice/TotalLineAmount. LC79 at seq26 is already before them. Good.

### Deploy mechanics (when human-acked; READ-ONLY for now)
Per memory "Pricing procedure deploy mechanics": api 67 + --metadata-dir; UI-only activation;
deactivate -> deploy -> reactivate window; Force-reprice the subject quote to verify. ExpressionSet
"Revenue Management Default Pricing Procedure" 9QLWC0000015cDl4AI.
