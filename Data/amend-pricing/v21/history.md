# V21 history / change-lane detail — amend NetUnitPrice=0 (2026-06-29)

Active proc: ExpressionSet "Revenue Management Default Pricing Procedure" 9QLWC0000015cDl4AI.
ACTIVE version V21 = ESV 9QMWC00000025LN4AY / DefVer 9QBWC0000000oWH4AY, status=Active, 122 steps,
created today 18:57 by Liam Jeong.
Description: "...V21 - V20 (COLA proration + guards + currency) with Derived Pricing Formula reverted to 3-tier. DRAFT."
(label says DRAFT, status field = Active — same "label lies" pattern as V20.)

Snapshots: V21 = Data/amend-pricing/retrieve/v21_live.json ; V20 = Data/derived_pricing_demo/versions/v20.json ;
V16 = Data/derived_pricing_demo/versions/v16.json. Each = result.records[0].Metadata.steps[].

## 1. WHAT V21 ACTUALLY CHANGED vs V20 (content-level diff, suffix-normalized)

The membership diff (V20=119 steps, V21=122 steps) is mostly RENUMBERING noise — the engine re-indexes
step name suffixes on every save. Comparing by stable label + criteria + formula/assignment body, only
SIX labels differ in content:

1. **'Derived Pricing Formula'** (step `DerivedPricingFormula`, seq2, parent `ListContainer9`) — REVERTED
   from V20's 7-tier table to a 3-tier table (matches the V21 description):
   - V20: `IF(QuoteTypeText__c='Renewal', NetUnitPrice, IF(AttributeValue='Expert',0.35, ...'Premier',0.30, 'Express',0.30, 'Premium',0.24, 'Standard',0.20, 'Professional',0.20, 'Basic',0.15, 0)) * IF(Base_Price__c>0, Base_Price__c, IF(Pre_Partner_Price__c>0, Pre_Partner_Price__c, IF(InputUnitPrice>0, InputUnitPrice, 0)))`
   - V21: `IF(QuoteTypeText__c='Renewal', NetUnitPrice, IF(AttributeValue='Premier',0.30, 'Standard',0.20, 'Professional',0.20, 0)) * IF(Base_Price__c>0,...)`
   - Gated inside ListContainer9 / "Derived Maintenance Net Filter" (ItemIsDerived__std=true). Affects
     DERIVED/maintenance lines only, NOT the non-derived AA subject line.

2. **'Proration' / 'Term-Defined proration filter (Line level)'** — V21 RE-ADDED the TermDefined proration
   that V20 had dropped (SC-3420 PTC restore): new ListGroup `TermDefinedProrationFilterLinelevel` (seq27),
   `ListOperationTermDefinedPTC` (adv gate: SellingModelType='TermDefined' AND StartProrationPeriod IsNotNull
   AND ItemSubscriptionTerm IsNotNull), and `ProrationTermDefined` (Proration BKM → ProrationMultiplier=PricingTermCount).

3. **'Software Aggregate Price' / 'Subscription Aggregate Price'** (`SoftwareAggregatePrice` / `SubscriptionAggregatePrice`)
   — V21 added a `where-condition` `ItemNetTotalPrice isNotNull` guard on the SUM rollup. This is the
   conditional-aggregate STALE-VALUE guard ([[project_quote_pricing_rollups]]), not amend-net related.

These are the "guards" referenced in the V21 description. **NONE of them touch the amend (LastTransaction) net path.**

## 2. THE NAMED TARGET STEPS DID **NOT** CHANGE V20->V21 (lane brief premise corrected)

The lane brief asked to read changed bodies for CurrencyConversion* (all 4), ManualQuoteLevelDiscount,
QuantityPrice, VolumeDiscounts, and "guard Assignments." Verified BYTE-IDENTICAL V20 vs V21:

- **CurrencyConversionNetUnitPrice (seq35), UnitPriceDisplay (seq36), NetTotalSubtotal (seq37), TotalLineAmount (seq38)**
  — all 4 unchanged. Each = `<field> * IF(STICurrencyIsoCode='EUR',0.9346, 'GBP',0.7874, 'CAD',1.3889, 'AUD',1.5385,
  'CHF',0.8850, 'ILS',3.6251, 'JPY',149.2537, 'NZD',1.6667, 'ARS',666.6667, 1.0)`. Unconditional, pure multiply.
  USD x1.0; CAD x1.3889. They CANNOT create 0 from nonzero and they CANNOT recover a 0. They preserve whatever
  arrives. The "all 4 changed" in the membership diff was renumber-only.
- **ManualQuoteLevelDiscount** (parent ListContainer56) — unchanged; gated NotEquals 'LastTransaction' => SKIPS amend.
- **QuantityPrice** filter (parent ListContainer76) — unchanged gate: `ItemPricingSource NotEquals 'LastTransaction'
  AND DerivedPricingAttribute IsNotNull AND DerivedPricingAttribute Equals false` => SKIPS amend.
- **VolumeDiscounts** (parent ListContainer28) — unchanged; gated NotEquals 'LastTransaction' => SKIPS amend.
- The 4 Assignment steps (PricingTermCount writers + Assignment98 TotalLineAmount + Assignment119 ItemSubtotal/ItemTotalPrice
  tail) — no amend-specific net guard added.

Steps mentioning 'LastTransaction' = 11 in BOTH V20 and V21 (no new amend gating in V21).
`DerivedPricingNetUnitPriceValueReset` (formula IF(QuoteTypeText__c='Renewal', NetUnitPrice, 0)) present
unchanged in both, still gated ItemIsDerived__std=true => inert for the non-derived AA line, but WOULD zero
a derived/maintenance amend line's NetUnitPrice.

## 3. THE AMEND NET PATH — IDENTICAL V16/V20/V21, AND IT ONLY CONSUMES NetUnitPrice

The amend lane's net IS produced by a real step, but that step never SETS NetUnitPrice:

- `ListContainer79` (V21; = `ListContainer73` in V20 — renumber) gated `ItemPricingSource Equals 'LastTransaction'`
  (op `ListOperation80` in V21 / `ListOperation74` in V20).
- Child `FormulaBasedPricing` (BKM): `formula-section-0-input = NetUnitPrice * LineItemQuantity`
  -> output `ItemNetTotalPrice`. **CONSUMES NetUnitPrice, never writes it.**
- BYTE-IDENTICAL across V16, V20, V21.

So the amend line's NetUnitPrice must arrive ALREADY SEEDED (from PricingSetting hydration / asset net seed),
because every base/list/attr/volume/quantity/net-derivation step is gated `ItemPricingSource NotEquals
'LastTransaction'` and SKIPS the amend line. If NetUnitPrice arrives 0 -> `0 * qty = 0` -> ItemNetTotalPrice=0
-> tail Assignment119 copies 0 into ItemSubtotal/ItemTotalPrice -> Subtotal/TotalPrice=0. The downstream
CurrencyConversionNetUnitPrice/NetTotalSubtotal just multiply the 0 through.

PricingSetting (seq1, Apex RevSignaling 'Get'): outputs PriceWaterfall=price_water_fall, NetUnitPrice=NetUnitPrice,
Subtotal=ItemNetTotalPrice. This is the sole hydration of NetUnitPrice for an amend line. It is returning 0
for NetUnitPrice on the subject amend line (while the asset net seed 5906.29725 DID reach UnitPrice/InputUnitPrice
and carried through TotalLineAmount/Subtotal-gross).

## 4. WHAT V21 FIXED vs WHAT IT MISSED

FIXED (partial): the GROSS carry. UnitPrice=5906.29725, TotalLineAmount=11812.5945, Subtotal(gross)=11812.5945
now carry the asset seed correctly on the amend line (this changed between the broken V20 state and V21 —
most plausibly via the republish/context-resync that accompanied creating V21, NOT via any new step body, since
no gross-seeding amend step was added). The 3-tier derived revert + TermDefined proration + aggregate-isNotNull
guards are unrelated correctness fixes for derived/renewal/rollup lines.

MISSED (remaining defect): the NET carry. NetUnitPrice still arrives 0 from PricingSetting for the amend line,
so NetUnitPrice / NetTotalPrice / TotalPrice = 0. V21 added NO step that seeds NetUnitPrice (or ItemNetTotalPrice)
for ItemPricingSource='LastTransaction' lines. The asymmetry: the gross seed lands, the net seed does not.

## 5. DESIGN CONTEXT — SC-3441 (the cancel-line twin defect) is the same gate family

SC-3441 (cancellation TotalPrice=$0) is the SAME structural class: a special-pricing-source line (Cancel: null
ItemPricingSource; Amend: 'LastTransaction') is excluded from the QuantityPrice net-total step
(`ListContainer76`/`QuantityPrice` gate NotEquals 'LastTransaction' AND DerivedPricingAttribute=false), so its
net total stays 0. SC-3441's resolved fix did NOT touch the amend path:
- SC-3441 added custom field `CancelNetUnitPrice__c` (QLI+OrderItem) + context `SalesTransactionContextExt_v2`
  v23 hydration (BOTH Quote+Order nodes) + before-save triggers + a V18 in-proc seed group `CancelNetSeedContainer`/
  `ListContainer12` (top seq13, gate `CancelNetUnitPrice__c IsNotNull AND NetUnitPrice IsNull`).
- The proc-seed approach proved DEAD at runtime (ListGroups skip the special line) -> SC-3441 was RESOLVED via a
  **RevSignaling POSTHOOK** `CancelLineCreditPosthook` writing the QLI FIELD-API attr names
  (NetUnitPrice / NetTotalPrice / TotalPrice / Subtotal / TotalLineAmount — the save-mapped ContextInputAttributeName
  on QuoteEntitiesMapping), NOT the internal pricing-tag names (ItemNetTotalPrice etc, which save ignores).
- V18/V19 carried the SC-3441 branch; **V20 forked off V16 and DROPPED it; V21 (off V20) also lacks it.**
  So the V21 active proc currently has NEITHER the SC-3441 cancel branch NOR any amend NetUnitPrice seed.

KEY transferable lesson for the amend fix: QLI total fields (NetUnitPrice/NetTotalPrice/TotalPrice/Subtotal/
TotalLineAmount) are updateable=false (engine-managed) -> only the pricing-engine context path (a proc step that
fires for the line, or a posthook) can set them; a trigger/flow cannot. And the save-mapped names are the QLI
FIELD API NAMES, not the internal Item* pricing tags.

## 6. CORRECT DEPLOY MECHANICS FOR THE FIX ([[reference_pricing_procedure_deploy_mechanics]])

- **API version 67.0 REQUIRED** in package.xml (v66 fails: "Property 'dataType' not valid in version 66.0").
- **Use `--metadata-dir`, NOT `-d`/`--source-dir`** (project sourceApiVersion=66 hijacks -d to v66 and fails):
  `sf project deploy start --metadata-dir <dir> --api-version 67.0 -o FortraUAT`.
- **Can't modify an ACTIVE version** -> must **Deactivate (UI) -> deploy -> Activate (UI)**. In-place edit of the
  active version updates the DESIGN (Simulator sees it) but does NOT recompile the RUNTIME (ExpressionSetVersion);
  a genuine inactive->active transition forces a fresh runtime compile. Lower-risk alt = clone to a NEW version,
  deploy while current stays active, then one atomic UI Activate (adds an un-deletable version,
  [[project_pricing_proc_version_delete_blocked]]).
- **Activation/deactivation is UI-ONLY** (Setup -> Pricing Procedures -> Revenue Management Default Pricing
  Procedure -> Versions -> row -> Activate/Deactivate). `<status>` in metadata does NOT activate on deploy.
  **NEVER "Reactivate All Dependencies"** (it activated 8 versions = past corruption).
- **In-place deploy has a pricing-OFFLINE window** (0 active versions while deactivated; pricing down org-wide).
- **Always pull live first** (proc drifts daily, co-owned Nir/Marc/Ben): `sf project retrieve start -m
  "ExpressionSetDefinition:Rev_Mgmt_Default_Pricing_Procedure" --target-metadata-dir <dir> --unzip -o FortraUAT`.
  Edit by the highest-version block only (formula text is byte-identical across versions).
- **Context resync (`SalesTransactionContextExt_v2`) needed ONLY if you add/remove context fields.** A pure
  formula/criteria-literal change does NOT need a resync. Adding a NEW field the proc reads requires the field on
  BOTH QuoteLineItem AND OrderItem AND hydrated on BOTH context nodes (QuoteEntitiesMapping + OrderEntitiesMapping,
  node SalesTransactionItem), else context-fetch hard-fails ("couldn't fetch SalesTransactionContextExt_v2",
  [[project_v16_order_pricing_contextfetch_incident]]). Resync-without-republish-match = the "Specify
  contextDefinitionName" gack ([[project_reprice_contextdef_error]]).
- **Verify with non-destructive Force reprice:** POST /services/data/v64.0/connect/rev/sales-transaction/actions/place
  body {"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"1","records":
  [{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<quoteId>"}}}]}}.
  Subject quote 0Q0WC000003FNXF0A4; expect AA Qty2 NetUnitPrice~5906.30 CAD, NetTotalPrice/TotalPrice~11812.59.
  DRAFT quotes only; never reprice the good pre-Jun27 demo amends (they hold correct values only because they
  were never repriced under the regression).

## 7. FIX LOCUS (for the build lane)

Two viable patterns, both consistent with the SC-3441 precedent:
- (A) A **posthook** (mirror of CancelLineCreditPosthook) that, for ItemPricingSource='LastTransaction' lines with
  NetUnitPrice arriving 0 but a valid asset-net seed (UnitPrice/asset AssetActionSource.NetUnitPrice present),
  writes the QLI FIELD-API attrs NetUnitPrice/NetTotalPrice/TotalPrice/Subtotal/TotalLineAmount = seed (x qty for
  totals). Field-API names, NOT Item* tags.
- (B) An **in-proc amend-net seed** inside the existing `ListContainer79` (Equals 'LastTransaction') group:
  before the `NetUnitPrice * LineItemQuantity` formula, add an Assignment that sets NetUnitPrice from the carried
  gross seed when NetUnitPrice IsNull/0 (e.g. from InputUnitPrice/UnitPrice which already carries 5906.29725).
  Risk: SC-3441 proved in-proc seeds in a ListGroup can be invisible to runtime for special-source lines -> verify
  on a live FINEST reprice; if it stays 0, fall back to the posthook (A).
- Do NOT rely on guards that only set the GROSS fields; the asymmetry (gross seeded, net not) is the exact gap.
