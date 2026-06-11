# SC-3350 — Fix Seed-Source Correctness + Alternatives

**Stream:** Design / Seed-source correctness + alternatives for the `InputUnitPrice → NetUnitPrice`
renewal seed in `Rev_Mgmt_Default_Pricing_Procedure` V10.
**Method:** static trace of the active V10 procedure XML (52,499 lines) + `COLAUpliftPrehook.cls`,
read-only, cited to element name + line number. **~90% confidence; residual is runtime-only
(waterfall/debug-log confirmable).**
**Source XML:** `Data/sc3350/retrieve/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`
(byte-identical to the brief artifact per `research/live_procedure_v10.md`).

---

## 0. Waterfall order of the relevant ListGroups (by `sequenceNumber`)

The procedure body is a flat list of `<steps>`; ListGroup `sequenceNumber` governs execution order.
Verified group seqs (first canonical variant):

| ListGroup | seq (line) | Role on a NON-derived renewal line (`ItemPricingSource='LastTransaction'`, `DerivedPricingAttribute=false`) |
|---|---|---|
| `ListContainer2` | **6** (L2013-2015) | **Path A COLA** → writes `InputUnitPrice` := `COLACalculatedPrice__c` (4697.946) |
| `ListContainer3` | **7** (L2035-2037) | **PartnerDiscount13** — base `InputUnitPrice` → writes `NetUnitPrice`. Gate = Deal_Type only (RUNS for renewals) |
| `ListContainer35` | **15** (L2057-2059) | **AttributeBasedPrice** — base `NetUnitPrice` → writes `NetUnitPrice`. Gate = `NotEquals LastTransaction` (SKIPPED for renewals) |
| `ListContainer47` | **19** (L2112-2114) | **QuantityPrice49** seed `InputUnitPrice` → `NetUnitPrice`. Gate = `NotEquals LastTransaction` (SKIPPED for renewals) |
| `ListContainer51` | **20** (L2136) | ManualQuoteLevel* discretionary discounts. Gate = `NotEquals LastTransaction AND (Amend OR Add)` (SKIPPED for renewals) |
| `ListContainer55` | **21** (L2145-2147) | **Renewal branch** (`ItemPricingSource Equals 'LastTransaction'`, `ListOperation56` L2377). Only FormulaBasedPricing that *reads* `NetUnitPrice*Qty` (L1837); never *seeds* NetUnitPrice. **<-- proposed fix site** |
| `TermDefinedSubscriptionFilter…` | **22** (L4227) | **SubscriptionPricing** — input `NetUnitPrice` → output `NetUnitPrice`/`ItemNetTotalPrice`. Gate `ListOperation59` = `SellingModelType='TermDefined'` only |

So on a non-derived renewal line, the ONLY thing that touches the Net track before SubscriptionPricing
is **PartnerDiscount13 (seq 7)** — and only when the deal is partner-originated. Everything else that
seeds/recomputes NetUnitPrice (QuantityPrice49, AttributeBasedPrice, discretionary) is gated out by
`ItemPricingSource NotEquals 'LastTransaction'`.

---

## 1. Seed SOURCE correctness — `InputUnitPrice` is the RIGHT source (verified)

### What `InputUnitPrice` holds on our line, and why it is correct
- **Path A COLA assignment `COLAUpliftonRenewal10`** (stepType BusinessKnowledgeModel /
  actionType `AssignmentElement`, `parentStep ListContainer2`, L1499-1500): maps
  `section-0-input1 = COLACalculatedPrice__c (Currency)` → `section-0-output = InputUnitPrice (Currency)`
  (JSON whereCondition L1486; output param L1490-1493). → after seq 6, `InputUnitPrice = COLACalculatedPrice__c = 4697.946`.
- The COLA'd price IS the correct net base for a renewal: it is `Asset.Price × (1 + COLA%/100)`
  computed by the prehook (`COLAUpliftPrehook.buildLineItemUpdates`, L454 `colaAdjustedPrice = assetPrice * (1 + (colaPercent/100))`),
  with the override hierarchy (Line / Contract / CMDT) already resolved. There are no further
  list-side adjustments between seq 6 and the renewal branch that should NOT carry to net.
- **The list-price seeds of InputUnitPrice are gated OUT for renewals**, so InputUnitPrice is NOT $46:
  - `Assignment` (`ListPrice → InputUnitPrice`, `parentStep ListContainer32`, L388-389; JSON L375) is gated by
    `ListOperation` (L2260, parent ListContainer32): `InputUnitPrice IsNull AND ItemPricingSource NotEquals 'LastTransaction' AND DerivedPricingAttribute=false`.
  - The PBE lookup itself (`PriceBookEntries`, actionType `ListPrice`, L3018-3019) outputs **`ListPrice → ListPrice`** ($46)
    and `Subtotal → ItemNetTotalPrice`; it writes neither `InputUnitPrice` nor `NetUnitPrice` (param block L2987-3014).
  - Conclusion: on the renewal line, `InputUnitPrice` is sourced ONLY by Path A = the COLA'd 4697.946. **Correct.**

### Why the alternatives are WRONG
| Candidate source | Verdict | Evidence |
|---|---|---|
| **`InputUnitPrice` (4697.946)** | ✅ **CORRECT** | Holds the COLA'd net base after Path A `COLAUpliftonRenewal10` (L1490-1493). Same currency dataType as NetUnitPrice; identical shape to the proven `QuantityPrice49` seed. |
| `NetUnitPrice` from PBE ($46) | ❌ WRONG | PBE writes `ListPrice` ($46), not `NetUnitPrice` (`PriceBookEntries` out-params L2987-3014). NetUnitPrice was never set → engine default **0**. Seeding from $46 (the list price) would also strip the COLA uplift. |
| `COLACalculatedPrice__c` directly | ❌ avoid | Functionally equal to InputUnitPrice here (Path A copied it 1:1), BUT it is the RAW prehook output that has NOT passed through Path A's `Renew/COLA%-not-null/DerivedPricingAttribute=false` gate. Seeding from it directly would bypass that gate and could fire on non-renewal or derived lines where COLACalculatedPrice__c is stale/populated. `InputUnitPrice` is the gate-respecting, post-COLA value — strictly safer and consistent with `QuantityPrice49`. (Ref count: COLACalculatedPrice__c appears 20× — all are the 10 Path-A assignment copies.) |
| `Pre_COLA_Price__c` | ❌ NOT AVAILABLE | **0 references in the procedure** (grep) — handler/context-only field, never mapped into the pricing context as a usable parameter. Also it is the PRE-uplift price, so it would strip COLA. |
| `COLA_Source__c` | n/a | **0 references** — text audit field, not a price. |

---

## 2. The waterfall "Price Book Entries $46 → Net Unit Price $0.00" — PBE never applied to net

**Question:** does the seed need to run AFTER PBE to override $46, or did PBE never apply?
**Answer: PBE never applied to NetUnitPrice. NetUnitPrice stayed 0 because nothing seeded it; $46 only ever lived in `ListPrice`.**

- `PriceBookEntries` (actionType `ListPrice`, L2880, label "Price Book Entries", L3018) output params (L2987-3014):
  - `Id → ItemPricebookEntry`
  - `IsDerived → DerivedPricingAttribute`
  - `ListPrice → ListPrice`  ← **this is the $46**
  - `Subtotal → ItemNetTotalPrice`
  It writes **no `NetUnitPrice` and no `InputUnitPrice`**. So $46 enters the `ListPrice` slot only.
- The waterfall renders PBE as the row that carries the net column lineage (its `Subtotal → ItemNetTotalPrice` output threads the net total), so the Explainability panel shows "Price Book Entries $46" adjacent to "Net Unit Price $0.00" — but the **$0.00 is the unseeded default**, not a value PBE wrote. PBE's $46 → `ListPrice` (correct list side, why the list track is right).
- **Implication for the fix:** the seed does NOT have to "beat" a $46 already sitting in NetUnitPrice. There is nothing to override; we are *initializing* a slot that is otherwise 0. Sequencing only matters w.r.t. (a) Path A (must run after — it does, seq 6 < 21) and (b) PartnerDiscount13 (see §4) and (c) SubscriptionPricing (must run before — it does, 21 < 22).

---

## 3. Three fix options — precise change, blast radius, why procedure-seed is safest

### Option 1 (PREFERRED) — procedure seed step inside `ListContainer55`
- **Precise change:** add a `BusinessKnowledgeModel` / actionType `AssignmentElement` step, `parentStep ListContainer55`,
  modeled byte-for-byte on `QuantityPrice49` (L3432-3481): `section-0-input1 = InputUnitPrice (Currency)` →
  `section-0-output = NetUnitPrice (Currency)`, with `sectionJsonString2` =
  `{"whereConditions":[{"field":{"dataType":"Currency","name":"section-0-input1","value":"InputUnitPrice",…},"value":{"dataType":"Currency","name":"section-0-output","value":"NetUnitPrice",…}}]}`
  (identical to QuantityPrice49 JSON L3460). Sequence it as the FIRST priced step inside ListContainer55,
  **before** the existing FormulaBasedPricing (`NetUnitPrice*LineItemQuantity`, L1837) so the formula reads the seeded value,
  and necessarily before SubscriptionPricing (group seq 22).
- **Gate:** ListContainer55 is already gated `ItemPricingSource Equals 'LastTransaction'` (`ListOperation56`, L2377).
  The RCA's proposal to additionally require `DerivedPricingAttribute=false` is sound: it guarantees no collision
  with Path B (`DerivedPricingRenewals`, MDT-derived, container gate `DerivedPricingAttribute=true`). Add it as a
  per-step `advancedCondition` OR rely on the fact that Path-B lines also carry `LastTransaction` — **must add the
  `DerivedPricingAttribute=false` criterion** (Path B renewals ALSO satisfy `ListOperation56`; without the extra gate the
  seed would clobber the derived formula's NetUnitPrice). See §4 for the partner-discount ordering caveat.
- **Blast radius:** narrowest. Only fires on lines matching `LastTransaction AND DerivedPricingAttribute=false`
  — i.e. exactly the non-derived renewal class that is currently broken. Derived renewals (Path B) untouched;
  new-business / amend / add lines never enter ListContainer55. Net-new version → V11.
- **Why safest:** symmetric counterpart of the existing, proven `QuantityPrice49` seed (same element type, same
  currency mapping, same engine primitive). No new field, no Apex, no decision-table, no context-attribute hydration risk.

### Option 2 — relax the `QuantityPrice` filter to also allow renewals
- **Precise change:** edit `QuantityPrice` filter (L3397-3429, parent ListContainer47): drop/loosen criterion 1
  (`ItemPricingSource NotEquals 'LastTransaction'`).
- **Blast radius:** WIDE and dangerous. ListContainer47 (seq 19) ALSO contains `QuantityPrice50`
  (`InputUnitPrice * LineItemQuantity → ItemNetTotalPrice`, L3545) and any sibling steps; relaxing the container
  filter re-enables ALL of them for every LastTransaction line, INCLUDING derived (Path B) renewals, which would
  then get NetUnitPrice overwritten from InputUnitPrice and lose the `DerivedPricingRenewals` formula result.
  It also changes the seq-19 group, which runs before the renewal branch's own formula at seq 21.
- **Why not:** clobbers Path-B derived renewals; touches a shared standard-path container. **Not recommended.**

### Option 3 — Apex: `COLAUpliftPrehook.buildItemUpdate` also writes `NetUnitPrice`
- **Precise change:** add `{'attributeName' => 'NetUnitPrice', 'attributeValue' => colaPrice}` to the `attributes`
  list in `buildItemUpdate` (L538-570) and/or `buildCOLAContextUpdate` (L1257-1270).
- **Blast radius / risk:** HIGH and likely INERT.
  - The class explicitly warns (L534-548, L1254-1256) that context attributes **without a verified
    `contextAttrHydrationDetails` mapping "poison the entire `updateContextAttributes` batch"** — and that even
    a mapped attribute (`COLAUpliftPercent__c`) had to be PULLED from the batch because it poisoned it. There is no
    evidence `NetUnitPrice` is a write-back-mapped *custom* context attribute the prehook may set; it is a pricing
    engine output the procedure owns. A poisoned batch would silently drop the COLACalculatedPrice__c write too,
    regressing the list side.
  - Timing: prehook runs as a signaling pre-processor; the procedure recomputes NetUnitPrice downstream
    (SubscriptionPricing reads NetUnitPrice). Even if the write landed, SubscriptionPricing/PartnerDiscount could
    overwrite it depending on ordering. Far less deterministic than a procedure step placed at a known seq.
  - Also COLAUpliftPrehook/Handler were Marc-edited 14:00Z-16:58Z TODAY (per live_procedure_v10.md §7) — a moving target.
- **Why not:** unverified hydration → batch-poison regression risk on the already-working list side; non-deterministic
  vs the procedure waterfall. Use only if the procedure cannot be re-versioned.

**Ranking:** Option 1 ≫ Option 3 ≫ Option 2. Option 1 is the missing symmetric twin of `QuantityPrice49`; it is the
least-surprising, smallest-radius, no-new-primitive change.

---

## 4. Do discounts land on NetUnitPrice ELSEWHERE for a renewal line? (ordering correctness)

**This is the one place the RCA is materially WRONG and the seed design must account for it.**

### Finding: PartnerDiscount13 DOES run for renewal lines, BEFORE the proposed seed.
- `PartnerDiscount13` (actionType `ManualDiscount`, label "Partner Discount", L2869-2870) lives in
  **`ListContainer3` (seq 7)** — NOT `ListContainer35` as the RCA states.
- Its container gate is the `PartnerDiscount` filter (L2772-2791, parent ListContainer3): conditionLogic `1`, single
  criterion **`Deal_Type__c NotEquals 'Fortra Originated'`**. **There is NO `ItemPricingSource` gate and NO action-type gate.**
  → On a partner-originated renewal line, PartnerDiscount13 RUNS.
- Its I/O (L2817-2865): base input `InputUnitPrice = InputUnitPrice` (L2819-2822), output `NetUnitPrice → NetUnitPrice`
  (L2852-2857) + `Subtotal → ItemNetTotalPrice`. So at **seq 7** it reads the COLA'd InputUnitPrice (4697.946),
  applies the partner %, and **writes the discounted result into NetUnitPrice**.

### Consequence for the seed (CRITICAL):
A plain `InputUnitPrice → NetUnitPrice` seed placed at seq 21 (inside ListContainer55) would run **AFTER**
PartnerDiscount13 (seq 7) and **OVERWRITE** the partner-discounted NetUnitPrice with the undiscounted COLA'd list,
**silently dropping a legitimate partner discount** on renewal lines.

This was masked in the reported repro because that line had **NetUnitPrice = 0**, i.e. PartnerDiscount13 did NOT run
(non-partner deal, or `Deal_Type__c = 'Fortra Originated'`). For a partner-originated renewal, the proposed seed as-written
would regress.

### Mitigation — seed must be conditional ("seed only if not already set"):
Mirror the existing list-side seed guard. `ListContainer32`'s `ListOperation` (L2231-2257) seeds InputUnitPrice
**only when `InputUnitPrice IsNull`**. Apply the same idempotent guard to the new step's gate:
add criterion **`NetUnitPrice IsNull`** (and the recommended `DerivedPricingAttribute=false`).
Then the seed fires only when nothing upstream populated NetUnitPrice — i.e. it fills the gap for non-partner renewals
and stays inert when PartnerDiscount13 already set NetUnitPrice.
- ⚠️ Verify the engine default for an unwritten Currency parameter is **null (IsNull true)**, not literal `0`. The RCA
  says NetUnitPrice "stays at the engine default 0". If the default is a hard `0` rather than null, an `IsNull` guard
  won't catch it and you'd need `NetUnitPrice IsNull OR NetUnitPrice Equals 0` — but an `Equals 0` guard would also
  re-seed a legitimately $0 partner-discounted line. **Confirm null-vs-0 on the waterfall/debug log before finalizing
  the guard.** (This is the principal residual runtime uncertainty.)

### Other discounts — confirmed they do NOT run on renewal lines (so no other ordering hazard):
- `AttributeBasedPrice` (actionType `AttributeDiscount`, L789) base `InputUnitPrice = NetUnitPrice` (L687-692),
  container `ListContainer35` gated `ListOperation36` (L2299): `… AND ItemPricingSource NotEquals 'LastTransaction' …`
  → **SKIPPED for renewals.** (It also depends on NetUnitPrice being pre-seeded, which it isn't for renewals — so even
  if it ran it would be 0-based. Not in play.)
- Discretionary / manual quote-level (`ManualQuoteLevelDiscount` filter L2650-2683, container ListContainer51 seq 20):
  gated `ItemPricingSource NotEquals 'LastTransaction' AND (ItemSalesTransactionAction = 'Amend' OR 'Add')`
  → **SKIPPED for renewals** (LastTransaction excluded AND action is 'Renew', not Amend/Add).
- Net: on a renewal line, **PartnerDiscount13 is the ONLY discount that touches NetUnitPrice.** The seed must defer to it.

---

## 5. Multi-variant propagation caveat (implementation)
The procedure compiles the same logic into multiple ListGroup variant copies. Counts (grep):
`ListContainer55` group def ×7; `QuantityPrice49` ×5; `COLAUpliftonRenewal10`-family Path-A assignments ×10;
FormulaBasedPricing parented to ListContainer55 ×14 (≈2 per variant).
→ A hand-edited XML seed must be added to **every** ListContainer55 variant (≈7), not just the first canonical block,
or only some sales-transaction contexts get fixed. Adding the step via the Pricing Procedure UI builder normally
propagates to variants automatically; verify post-build that all variants carry the step (grep the new step name count).

---

## 6. Bottom line
1. **Seed source = `InputUnitPrice` is correct** (= post-Path-A COLA'd 4697.946). $46 PBE/NetUnitPrice and
   `Pre_COLA_Price__c` are wrong; `COLACalculatedPrice__c` direct is gate-bypassing and inferior. (high confidence)
2. **PBE $46 never applied to NetUnitPrice** — it only set `ListPrice`; NetUnitPrice was an unseeded 0. The seed
   initializes, it does not override $46. (high confidence)
3. **Option 1 (procedure seed in ListContainer55) is safest** — symmetric twin of QuantityPrice49, narrowest radius.
   Option 3 (Apex) risks batch-poison + non-determinism; Option 2 (relax filter) clobbers Path-B derived renewals. (high confidence)
4. **The seed MUST be conditional (`NetUnitPrice IsNull` + `DerivedPricingAttribute=false`), NOT a plain copy** —
   because **PartnerDiscount13 (ListContainer3, seq 7, Deal_Type-only gate) DOES run on partner renewal lines and
   writes NetUnitPrice before the seed**; an unconditional seed would erase legitimate partner discounts. The RCA's
   placement of PartnerDiscount13 in ListContainer35/NotEquals-LastTransaction is incorrect. AttributeBasedPrice and
   discretionary discounts ARE correctly gated out of renewals. (high confidence on the run/skip matrix; the only
   residual is null-vs-literal-0 for the guard operator — confirm on a waterfall/debug log.)

## Evidence index
- Path A COLA assignment `COLAUpliftonRenewal10`: L1457-1507 (COLACalculatedPrice__c→InputUnitPrice JSON L1486, output L1490-1493).
- `QuantityPrice49` seed template: L3432-3481 (InputUnitPrice→NetUnitPrice JSON L3460).
- `ListContainer55` group (seq 21): L2142-2152; gate `ListOperation56` (Equals LastTransaction): L2364-2385.
- ListContainer55 formula reading NetUnitPrice*Qty: L1830-1899 (formula L1837).
- `PriceBookEntries` (ListPrice) out-params (no NetUnitPrice): L2880-3019 (ListPrice→ListPrice L3001-3006).
- `ListPrice→InputUnitPrice` Assignment (ListContainer32, NotEquals-LastTransaction gate): L347-395 / filter L2230-2267.
- `PartnerDiscount13` (ManualDiscount, ListContainer3, base InputUnitPrice→NetUnitPrice): L2793-2877; gate `PartnerDiscount` (Deal_Type only): L2771-2791; ListContainer3 seq 7: L2034-2037.
- `AttributeBasedPrice` (ListContainer35, base NetUnitPrice, gate NotEquals LastTransaction): L621-789 (base L687-692); gate `ListOperation36`: L2269-2306; ListContainer35 seq 15: L2055-2059.
- Discretionary `ManualQuoteLevelDiscount` gate (NotEquals LastTransaction AND Amend/Add): L2649-2683; ListContainer51 seq 20: L2136.
- `SubscriptionPricing` (reads/writes NetUnitPrice): L3906-3984; gate `ListOperation59` (TermDefined): L2386-2407; group seq 22: L4222-4232.
- Reverse seed `DerivedPricing31` (NetUnitPrice→InputUnitPrice, derived path only): L1640-1690 (ListContainer29, gate DerivedPricing=true L1613-1638).
- Ref counts: COLACalculatedPrice__c ×20, Pre_COLA_Price__c ×0, COLA_Source__c ×0; ListContainer55 ×7, QuantityPrice49 ×5.
- Prehook COLA math: `COLAUpliftPrehook.cls` L454 (`assetPrice * (1 + colaPercent/100)`); batch-poison warnings L534-548 / L1254-1256.
