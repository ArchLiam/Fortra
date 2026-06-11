# SC-3350 — Fix Blast-Radius Analysis: seed NetUnitPrice for renewals (V10 verified)

**Date:** 2026-06-10. **Method:** static trace of the ACTIVE V10 block (lines 46677–52499) of
`Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` + `COLAUpliftPrehook.cls`.
**Read-only.** All line numbers below are in the **active V10 block** unless noted.

> Source XML: `/Users/liamjeong/Documents/Code/Fortra/Data/sc3350/retrieve/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`

---

## 0. CRITICAL CORRECTION — the brief's container map is STALE (V1, not V10)

The XML contains **10 full `<versions>` blocks** (V1 … V10), each ~5,000 lines and each containing the
**entire** procedure tree (24 ListGroups + steps). The brief / RCA cite line numbers (1408, 2299, 2377,
3422, 3473) and element names (`COLAUpliftonRenewal10`, `QuantityPrice49`, `ListContainer47`,
`ListContainer35`, `ListOperation56`/`ListOperation36`) that live in the **V1 block** (lines 1–4872). They
do **NOT** describe the active V10. Verified facts about V10:

| Brief/RCA claim (V1-era) | V10 reality (active) |
|---|---|
| renewal container = **ListContainer55**, filter **ListOperation56** = `ItemPricingSource Equals 'LastTransaction'` | **FALSE in V10.** `ListOperation56` does not exist past line 22455 (V5). In V10, **ListContainer55 (seq 21)** is gated by filter `QuantityPrice` (L50593) = `ItemPricingSource **NotEquals** 'LastTransaction'`. The true `Equals 'LastTransaction'` container in V10 is **ListContainer62 (seq 23)**, filter `ListOperation63` (L49491). |
| seed step `QuantityPrice49` in `ListContainer47` does `NetUnitPrice := InputUnitPrice` | **No `ListContainer47`, no `QuantityPrice49` in V10.** No step in V10 does a bare `NetUnitPrice := InputUnitPrice`. |
| discount computers `AttributeBasedPrice` / `PartnerDiscount13` in `ListContainer35` | In V10: `AttributeBasedPrice` is in **ListContainer43 (seq 17)**; the partner-discount NetUnitPrice writer is **`PartnerDiscount24`** in **ListContainer3 (seq 10)**. No `ListContainer35`/`PartnerDiscount13`. |
| COLA Path A = `COLAUpliftonRenewal10`, container `ListContainer2` | In V10: filter `COLAUpliftonRenewal` (L48145) + assignment **`COLAUpliftonRenewal21`** (L48196), parent **ListContainer2 (seq 9)**. Mapping `COLACalculatedPrice__c → InputUnitPrice` confirmed (L48196–48238). |
| Path B = `DerivedPricingRenewals`, MDT-gated | **Confirmed in V10:** `DerivedPricingRenewals` (L48603, action FormulaBasedPricing) under `ListContainer` (seq 7), gated `DerivedPricingAttribute=true AND AttributeDefinitionCode='MDT'`. Outputs NetUnitPrice. |

**Consequence for the proposed fix:** "add the step inside **ListContainer55**, gated `LastTransaction
Equals`" targets the **wrong container** in V10. ListContainer55 is the **NotEquals-LastTransaction** branch.

---

## 1. V10 execution order (container sequence) — the waterfall

Root-level steps run interleaved by `sequenceNumber`; ListGroups are themselves steps with a `sequenceNumber`.
Ordered:

```
seq 1  PricingSetting            (root, PricingSettings)
seq 2  PriceBookEntries          (root, ListPrice → InputUnitPrice/ListPrice base)
seq 3  PricingEffectiveDates     (root, AssignmentElement)
seq 4  ListContainer10           DerivedPricingNetUnitPriceValueReset  [ItemIsDerived__std=true]
seq 5  DerivedProductsRenewals   (root, DerivedPricing → NetUnitPrice for contributing/bundle rollups)
seq 6  ListContainer9            DerivedPricingFormula                 [AttributeDefinitionCode='MTD']
seq 7  ListContainer             DerivedPricingNewBusiness, **DerivedPricingRenewals**, DerivedPricingValuesAssignment  [DerivedPricingAttribute=true AND code='MDT']  ← Path B
seq 8  ListContainer1            GSAPricing18                          [GSW__c=true]
seq 9  **ListContainer2**        COLAUpliftonRenewal21 → InputUnitPrice  ← Path A (COLA list write)
seq 10 **ListContainer3**        **PartnerDiscount24 → NetUnitPrice**   [Deal_Type__c≠'Fortra Originated']
seq 11 ListContainer4            RegionalServicesPrice27 → InputUnitPrice [AllowRegionalPricing__c=true]
seq 12-14 ListContainer5/6/7     AttributeValuePricing* (Unit/Total/Calc modes) → InputUnitPrice
seq 15 ListContainer37           ContactedPricing      [IsContracted=true AND PricingDate null]
seq 16 ListContainer40           Assignment ListPrice→InputUnitPrice  [InputUnitPrice null AND NotEq LT AND non-derived]
seq 17 ListContainer43           **AttributeBasedPrice → NetUnitPrice** [NotEquals LastTransaction, non-derived]
seq 18 ListContainer46           AttributeDiscountEntries → NetUnitPrice [NotEquals LastTransaction]
seq 19 ListContainer49           BundleBasedAdjustmentEntries → NetUnitPrice [NotEquals LastTransaction]
seq 20 ListContainer52           VolumeDiscountEntries → NetUnitPrice    [NotEquals LastTransaction]
seq 21 **ListContainer55**       QuantityPrice57 (NetUnitPrice*Qty→ItemNetTotalPrice) [**NotEquals** LastTransaction]
seq 22 ListContainer58           ManualQuoteLevel* → NetUnitPrice        [NotEquals LastTransaction ...]
seq 23 **ListContainer62**       FormulaBasedPricing (NetUnitPrice*Qty→ItemNetTotalPrice) [**Equals** LastTransaction]  ← TRUE renewal container
seq 24 TermDefined…filter        **SubscriptionPricing** (reads NetUnitPrice, writes back) [SellingModelType='TermDefined']
seq 25 Evergreen…filter          SubscriptionPricing72 (Evergreen)
seq 26-32 ListContainer73/77/80/83/8/Copy*  proration / inclusive / total rollups by product type
seq 33 RegionalNetReconcile      RegionalNetUnitPrice → NetUnitPrice, RegionalInputUnitPrice → InputUnitPrice [AllowRegionalPricing AND RegionalNetUnitPrice__c>0]
seq 34-42 (root) TotalAmount, aggregates, DiscountPercent, etc.
```

### NetUnitPrice writers and whether they can fire for a NON-DERIVED RENEWAL line (ItemPricingSource='LastTransaction', DerivedPricingAttribute=false)

| Writer | Container (seq) | Gate | Fires for non-derived renewal? |
|---|---|---|---|
| DerivedPricingNetUnitPriceValueReset | LC10 (4) | ItemIsDerived__std=true | No (derived only) |
| DerivedProductsRenewals | root (5) | (none) but DerivedPricing action over contributors | Only for derived/contributing bundle lines |
| DerivedPricingFormula | LC9 (6) | AttributeDefinitionCode='MTD' | No (MTD derived) |
| DerivedPricingNewBusiness / **DerivedPricingRenewals** | LC (7) | DerivedPricingAttribute=true AND 'MDT' | No — **Path B**, derived only |
| **PartnerDiscount24** | **LC3 (10)** | Deal_Type__c≠'Fortra Originated' | **YES — fires for PARTNER renewals** |
| AttributeBasedPrice | LC43 (17) | NotEquals LastTransaction | No |
| AttributeDiscountEntries | LC46 (18) | NotEquals LastTransaction | No |
| BundleBasedAdjustmentEntries | LC49 (19) | NotEquals LastTransaction | No |
| VolumeDiscountEntries | LC52 (20) | NotEquals LastTransaction | No |
| ManualQuoteLevel* | LC58 (22) | NotEquals LastTransaction | No |
| **SubscriptionPricing** | (24) | SellingModelType='TermDefined' | YES — but reads NetUnitPrice as INPUT (propagator, not seeder) |
| RegionalNetUnitPrice | RegionalNetReconcile (33) | AllowRegionalPricing AND RegionalNetUnitPrice__c>0 | YES — but seq 33, AFTER SubscriptionPricing |

**Root-cause confirmation (V10):** For a **Fortra-Originated, non-derived COLA renewal**, the only writers
that could fire are SubscriptionPricing (a propagator that reads NetUnitPrice=0) and RegionalNetReconcile
(needs AllowRegionalPricing). **No step seeds NetUnitPrice from InputUnitPrice → NetUnitPrice stays 0 →
SubscriptionPricing reads 0, writes 0.** RCA holds for V10 (container names differ from the brief).

SubscriptionPricing I/O (L51351): `in NetUnitPrice=NetUnitPrice`, `out SubscriptionNetUnitPrice→NetUnitPrice`,
`out TotalSubscriptionPrice→ItemNetTotalPrice`. ⇒ multiplies NetUnitPrice by quantity/proration; 0×n=0.

Prehook (`COLAUpliftPrehook.cls`) writes **only** `COLACalculatedPrice__c` + audit fields to context (L540–
570); it never writes InputUnitPrice or NetUnitPrice. The COLA→InputUnitPrice hop is the procedure's Path A.
So the net side is 100% the procedure's responsibility — Apex cannot be blamed and the prehook is not a
double-seed risk.

---

## 2. STRUCTURAL constraint: one filter per ListGroup (no two-filter groups exist)

Every ListGroup in V10 has **exactly one** leading `AdvancedListFilter` (seq 1) that scopes all subsequent
`BusinessKnowledgeModel` steps in that group. **There is no precedent anywhere in V10 for two filters in one
group.** This is decisive for the proposed "inside ListContainer55" placement:

- **If the new seed has NO own filter** → it inherits ListContainer55's `QuantityPrice` filter =
  `NotEquals 'LastTransaction'` → it **never fires for a renewal** → the fix is **INERT** (does nothing).
- **If the new seed carries its OWN `Equals 'LastTransaction'` filter inside ListContainer55** → you create
  an **unprecedented two-filter group** with **mutually contradictory** filters (NotEquals vs Equals
  LastTransaction). Engine scoping of a second filter in a ListGroup is **unverified** in this codebase; it
  either (a) re-scopes so the new step fires but corrupts the row scope that the existing `QuantityPrice57`
  step depends on, or (b) AND-combines so the new step never fires. **Either way: high risk / unverified.**

**Correct V10 placements** (both run after Path A seq 9 and before SubscriptionPricing seq 24):
1. **Add the seed step into the existing TRUE renewal container `ListContainer62` (seq 23)** as a new step
   sequenced *before* its `FormulaBasedPricing` child — it already gates `Equals 'LastTransaction'`. Cleanest:
   no new filter, reuses the existing renewal scope.
2. **Add a brand-new ListGroup** (mirroring ListContainer62's single-filter pattern) with its own
   `ItemPricingSource Equals 'LastTransaction' AND DerivedPricingAttribute=false` filter, inserted at a seq
   between 9 and 23 (e.g., new seq 23.x / renumber). Matches house style; avoids touching LC62's internals.

Either way the seed must run **after seq 10 (PartnerDiscount24)** so it does not clobber partner nets — see §3(e).

---

## 3. Scenario-by-scenario blast radius

Notation: seed = the proposed `InputUnitPrice → NetUnitPrice` assignment, gated
`ItemPricingSource Equals 'LastTransaction' AND DerivedPricingAttribute = false`.

### (a) Non-derived COLA renewal — OUR CASE — **FIXED** ✅
- ItemPricingSource=LastTransaction, DerivedPricingAttribute=false, Deal_Type='Fortra Originated',
  COLA% set. Path A (seq 9) wrote InputUnitPrice = COLACalculatedPrice (e.g. 4697.946). No NetUnitPrice
  writer fires → NetUnitPrice=0. Seed sets NetUnitPrice := InputUnitPrice (4697.946). SubscriptionPricing
  (seq 24) then reads the correct value and multiplies. **Correct.** This is the intended fix.

### (b) Non-derived renewal, NO COLA (COLA% null) — **FIXED, base is correct** ✅ (with one caveat)
- Path A does NOT fire (filter requires `COLA_Uplift_Percent__c IsNotNull`), so InputUnitPrice is whatever
  the earlier list steps set. Trace: `PriceBookEntries` (seq 2) seeds ListPrice/InputUnitPrice from PBE;
  `ListContainer40` (seq 16) assigns `ListPrice → InputUnitPrice` **only if `InputUnitPrice IsNull AND
  NotEquals LastTransaction`** — so for a renewal (Equals LastTransaction) LC40 does **not** run. Thus for a
  no-COLA renewal, InputUnitPrice = the PBE list price (the LastTransaction price comes from context, not a
  procedure step). Seed copies that to NetUnitPrice. **Net = list, no discount — which is the correct
  behavior for a plain renewal with no discount and no COLA.**
- **Caveat (verify at runtime):** confirm InputUnitPrice for a no-COLA LastTransaction line actually carries
  the prior/last-transaction unit price (it is a context attribute fed by the LastTransaction pricing source,
  not written by any V10 step we can see). If InputUnitPrice were 0/null for such a line, the seed would
  propagate 0 — but that is no worse than today (today it is 0 regardless). **Low risk; no regression.**

### (c) DERIVED / MDT maintenance renewal (Path B) — **EXCLUDED, no regression** ✅
- DerivedPricingAttribute=true ⇒ seed's `DerivedPricingAttribute=false` clause is FALSE ⇒ **seed never
  fires.** Path B `DerivedPricingRenewals` (L48603, seq 7) already wrote NetUnitPrice via
  `(Base_Price − Prior_Partner_Discount − Prior_Discretionary_Discount) × (1+COLA%/100)`. The non-derived
  gate is **load-bearing and correct** — it prevents the seed from overwriting Path B's net. **Verified.**

### (d) TermDefined subscription renewal — **ORDER IS CORRECT** ✅
- SubscriptionPricing (seq 24) reads NetUnitPrice and multiplies by quantity/proration. The seed at seq 23
  (LC62) or a new seq 23.x runs **before** seq 24, so SubscriptionPricing reads the seeded value (not 0).
  **Ordering holds for both proposed placements.** (NOTE: it does NOT hold for the brief's ListContainer55
  placement if that placement were inert per §2 — then SubscriptionPricing would still read 0.)
- Evergreen renewals (SubscriptionPricing72, seq 25) similarly read the seeded NetUnitPrice. ✅

### (e) Partner-discounted renewal — **REAL COLLISION RISK** ⚠️ (the load-bearing finding)
- A partner renewal: ItemPricingSource=LastTransaction, DerivedPricingAttribute=false,
  **Deal_Type__c ≠ 'Fortra Originated'**. This line **matches the seed's gate** (LastTransaction + non-derived).
- **PartnerDiscount24** (LC3, seq 10) gate is *only* `Deal_Type__c ≠ 'Fortra Originated'` (no LastTransaction
  exclusion, no derived exclusion). It reads `InputUnitPrice` and writes `NetUnitPrice = InputUnitPrice −
  PartnerDiscountPercent`. So a partner renewal **already has a correctly discounted NetUnitPrice today**
  (it is likely NOT broken). 
- If the seed runs **after** seq 10 (which it must, at seq 23 / new 23.x) **and** its gate matches the partner
  renewal, the seed **overwrites the discounted NetUnitPrice with the full InputUnitPrice**, **erasing the
  partner discount** → net jumps up to list. **This is a regression the proposed gate does NOT prevent.**
- **Mitigation:** tighten the seed gate to also require **`Deal_Type__c = 'Fortra Originated'`** (or
  equivalently `NetUnitPrice IsNull OR NetUnitPrice = 0` guard, or exclude lines PartnerDiscount24 already
  touched). Recommended explicit gate:
  `ItemPricingSource Equals 'LastTransaction' AND DerivedPricingAttribute = false AND Deal_Type__c Equals 'Fortra Originated'`.
  Confirm at runtime whether partner renewals are in scope of SC-3350 before finalizing; if they were ALSO
  $0 in the field, then PartnerDiscount24 is being bypassed for them and a different root cause applies.

### (f) Regional-priced renewal (RegionalServicesPrice27 / RegionalNetReconcile) — **MOSTLY OK, sequencing nuance** ⚠️(low)
- `RegionalServicesPrice27` (LC4, seq 11) writes `RegionalNetUnitPrice__c → InputUnitPrice` (LIST channel)
  if `AllowRegionalPricing__c=true`. It runs at seq 11, **before** the seed (seq 23). So for a regional
  renewal, InputUnitPrice = regional price, and the seed copies the regional price into NetUnitPrice — which
  is the *intended* regional behavior (regional price applied to net). ✅
- `RegionalNetReconcile` (seq 33) runs **after** SubscriptionPricing and re-writes BOTH InputUnitPrice and
  NetUnitPrice when `AllowRegionalPricing AND RegionalNetUnitPrice__c>0`. This final reconcile would override
  the seed anyway for regional lines, so the seed is harmless there. **No regression; the reconcile wins.**
- Nuance: per memory (`Regional services pricing mechanism`), regional writes the LIST channel and NET stays
  catalog by design, producing a structural `TotalLineAmount≠NetTotalPrice`. The seed copying InputUnitPrice
  (= regional list) into NetUnitPrice could *change* that structural relationship for regional renewals.
  **Verify regional renewals on a regional test line** — but note RegionalNetReconcile at seq 33 is the final
  authority, so the practical impact is bounded.

### (g) Multi-line / hardware (perpetual, non-subscription) — **OK** ✅
- The seed sets NetUnitPrice for any LastTransaction non-derived line regardless of SellingModelType. For a
  perpetual/hardware renewal that does NOT hit SubscriptionPricing (not TermDefined/Evergreen), the seeded
  NetUnitPrice still feeds the net total formulas (`QuantityPrice57` / LC62 `FormulaBasedPricing`:
  `NetUnitPrice × LineItemQuantity → ItemNetTotalPrice`). Without the seed these are 0 today; with it they
  are correct. **Improvement, no regression.** Mixed-line orders: each line is evaluated independently by its
  own ItemPricingSource/DerivedPricingAttribute, so non-renewal lines on the same quote are untouched (their
  ItemPricingSource ≠ LastTransaction ⇒ seed skips them).

---

## 4. Double-seed check (do not write NetUnitPrice twice for renewals)

- **ListContainer62** (true renewal, seq 23) children: `ListOperation63` (filter) + `FormulaBasedPricing`
  (`NetUnitPrice × LineItemQuantity → ItemNetTotalPrice`). **Neither outputs NetUnitPrice** — they consume it.
- **ListContainer55** (seq 21) children: `QuantityPrice` (filter) + `QuantityPrice57`
  (`NetUnitPrice × LineItemQuantity → ItemNetTotalPrice`). **Neither outputs NetUnitPrice.**
- ⇒ **No existing step seeds NetUnitPrice for the LastTransaction branch. No double-seed risk.** The seed is
  genuinely missing, confirming the gap. (The only renewal NetUnitPrice writers are Path B for derived MDT
  and PartnerDiscount24 for partner deals — both correctly excluded by the recommended gate.)

---

## 5. Verdict

| Item | Finding |
|---|---|
| Does the fix concept (seed `InputUnitPrice→NetUnitPrice` for non-derived LastTransaction, before SubscriptionPricing) fix our case? | **Yes** — scenario (a), provided it is placed in a container that actually matches LastTransaction lines. |
| Is the proposed container **ListContainer55** correct in V10? | **NO.** ListContainer55 (seq 21) is the **NotEquals-LastTransaction** branch in V10. Place the seed in **ListContainer62 (seq 23, the Equals-LastTransaction container)** or a new dedicated single-filter ListGroup. |
| Is the non-derived gate sufficient to protect Path B (derived)? | **Yes** — scenario (c) verified. |
| Any scenario where seeding NetUnitPrice=InputUnitPrice is WRONG? | **YES — partner renewals (e).** PartnerDiscount24 already discounts NetUnitPrice; the seed (running later) would overwrite it back to list. **Add `Deal_Type__c Equals 'Fortra Originated'` to the gate** (or a "only if NetUnitPrice still 0" guard). |
| Regional renewals (f) | Bounded — RegionalNetReconcile (seq 33) is the final authority; verify on a regional line. |
| Double-seed | None — no existing LastTransaction NetUnitPrice seed. |
| Ordering vs SubscriptionPricing | Holds for LC62 (seq 23) or a new seq 23.x; **does NOT** hold if the step is placed inertly in LC55. |

**Recommended gate (V10):**
`ItemPricingSource Equals 'LastTransaction' AND DerivedPricingAttribute = false AND Deal_Type__c Equals 'Fortra Originated'`
placed as a new assignment in **ListContainer62** (before its `FormulaBasedPricing` child) or a new
single-filter ListGroup at seq ~23.x.

**Open runtime confirmations (cannot be settled statically):**
1. For a no-COLA LastTransaction line, confirm InputUnitPrice carries the prior unit price (scenario b caveat).
2. Confirm whether partner renewals are in scope / currently broken (decides whether the Deal_Type clause is a
   guard or a true exclusion).
3. Regional renewal: verify net relationship on a regional test line (scenario f).
Confirm all three via the pricing waterfall / Explainability panel or a Reprice-All debug log before publishing.

---

## 6. Key V10 line cites (active block)
- Version map: V10 `<versions>` opens L46677; `<status>Active</status>` L46687; fullName `…_V100` L46678.
- Path A filter `COLAUpliftonRenewal` L48145–48196 (6 criteria incl. ItemPricingSource Equals LastTransaction).
- Path A assignment `COLAUpliftonRenewal21` L48196–48238 (`COLACalculatedPrice__c → InputUnitPrice`).
- Path B `DerivedPricingRenewals` formula L48611; output NetUnitPrice L48653; MDT gate `DerivedPricing` filter L48352.
- `PartnerDiscount` filter L49967 (`Deal_Type__c NotEquals 'Fortra Originated'`); `PartnerDiscount24` L49989
  (`in InputUnitPrice`, `out NetUnitPrice`, AdjustmentValue `PartnerDiscountPercent` L50004).
- ListContainer55 filter `QuantityPrice` L50593 (`ItemPricingSource NotEquals 'LastTransaction'`);
  child `QuantityPrice57` L50627 (`NetUnitPrice × LineItemQuantity → ItemNetTotalPrice`).
- ListContainer62 filter `ListOperation63` L49491 (`ItemPricingSource Equals 'LastTransaction'`);
  child `FormulaBasedPricing` L48943 (`NetUnitPrice × LineItemQuantity → ItemNetTotalPrice`).
- SubscriptionPricing L51351 (`in NetUnitPrice`, `out SubscriptionNetUnitPrice→NetUnitPrice`).
- RegionalServicesPrice27 L51021 (`RegionalNetUnitPrice__c → InputUnitPrice`); RegionalNetReconcile gate L50840.
- Prehook writes COLACalculatedPrice__c only: COLAUpliftPrehook.cls L540–570; no NetUnitPrice/InputUnitPrice write.
