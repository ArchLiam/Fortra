# V21 In-Place Draft — Consolidated Fix Design & Implementation Plan

Date: 2026-06-29
Scope: Consolidate the 4 vetted fix designs (D-01, E-03, G-03, F-07) into a single
in-place V21 draft edit plan. Active proc = V16 / active context = SalesTransactionContextExt_v2 v23.
Each fix below states the exact element(s) + FROM/TO (or new-step def), whether it is V21-only
or also needs a context/Apex change, the adversarial side-effect verdict, and a SAFE-NOW vs
NEEDS-MORE gate.

---

## Summary verdict table

| Fix  | What it fixes | Scope | V21-only? | Side-effect verdict | Draft gate |
|------|---------------|-------|-----------|---------------------|------------|
| D-01 | Attribute Calculated-mode net = base×mult (part a) | V21 bridge edit **+ context regen** | **NO** — needs context flip + new ctx ver + re-sync | LOW for the V21 edit alone; context-regen is the real risk | **DEFER context; V21 bridge edit alone does not fix without hydration** |
| E-03 | OneTime/Perpetual non-derived net=0 → seed net before partner | New ListGroup @seq19 (renumbers) | **YES** | Guarded no-op everywhere except null/0-net non-derived OneTime | **SAFE NOW** (needs idempotency confirmed by guard — it is) |
| G-03 | Double currency-multiply compounding (EUR/GBP) | 4 in-place formula swaps (seq35–38) | **YES** | Identity is a true fixed point; USD unchanged; AT-RISK only for currency-blind attr/tier/regional lines that depend on G-02/G-04 | **SAFE NOW for plain PBE lines; scope caveat — see below** |
| F-07 | Partner-discount compounding (×0.85^N) on contributor base | 1 convert+edit @gseq2 + 1 new step @gseq3, top-seq14 | **YES** | Idempotent by construction; AT-RISK: partner line also carrying vol/bundle/attr-entry discount | **SAFE NOW with the PartnerDiscountPercent>0 gate kept; flag stacking for follow-up** |

---

## D-01 — Attribute Value Pricing Calculated-Mode Net Bridge
**v21OnlyFixable = NO (needs context). Confidence: high.**

### Context change (REQUIRED, not V21):
- Context: `SalesTransactionContextExt_v2` (`11OWC000002m21Z2AQ`)
- contextAttributes def `title=Attribute_Multiplier_Pct__c` (dataType=percent):
  - **FROM** `<fieldType>output</fieldType>`
  - **TO** `<fieldType>inputoutput</fieldType>`
- Query mappings already present (`QLI.AttributeMultiplierPct__c`, `OrderItem.Attribute_Multiplier_Pct__c`) — **no mapping add**; the flip alone hydrates it as input.
- MUST regenerate + activate a **NEW context version** (next ver after V23) then re-sync / republish the active V21 ESV to that ctx ver.

### V21 edit (the proc-side half):
- Element: builder label `Attribute Value Pricing - Calculated Mode Net Bridge`,
  api `AttributeValuePricingCalculatedModeNetBridge`, parentStep `ListContainer6`, seq 3,
  param `formula-section-0-input`.
  - **FROM:** `IF ( NetUnitPrice > 0 , NetUnitPrice , InputUnitPrice )`
  - **TO:**   `IF ( InputUnitPrice > 0 , InputUnitPrice , IF ( NetUnitPrice > 0 , NetUnitPrice , Base_Price__c ) )`
- `CalculatedMode17` (seq2, `InputUnitPrice := Base_Price__c * Attribute_Multiplier_Pct__c`) **UNCHANGED** — correct once mult hydrates; percent stored as decimal `0.5`.

### Side-effect verdict (adversarial): PASS — LOW for the V21 edit in isolation
- Both edits scoped to `ListContainer6` (filter `Has_Attribute_Adjustment__c=true AND Attribute_Price_Mode__c='Calculated'`), running at top-seq7 **before** all partner/contracted/COLA/currency steps → pre-bridge `NetUnitPrice` is only a base/list seed; no real discount overwritten.
- Unit-Price mode (`ListContainer5`) and Total-Price mode (`ListContainer720`) are separate, mutually-exclusive, untouched.
- New-sale / non-attr lines never enter container6 → unchanged. Renewal COLA (top-seq26+) later → unaffected. Derived (separate `DerivedPricingFormula`) → unaffected. Other-currency conversion (seq35–38) runs AFTER → multiplies the corrected net, fine. GSA `GSW__c` InputUnitPrice write at top-seq12 is AFTER the bridge → no read-before-write.
- AT-RISK only if a Calculated line ever needed a pre-seq7 contracted net — none exists (ListContainer/7 write nothing). Mult=0 → InputUnitPrice=0 → bridge falls to NetUnitPrice (safe).

### Real risk:
Context-version regen. Any **other** proc bound to `SalesTransactionContextExt_v2` must be re-synced to the new ctx ver or it breaks. Execute as deactivate → republish → reactivate window.

### Expected:
QLI `0QLWC000003khGL4AY`: `Base_Price__c=100`, `Attribute_Multiplier_Pct__c` hydrates `0.5` → InputUnitPrice=50 → Net Bridge `NetUnitPrice=50` (was 100). UnitPrice/NetUnitPrice=50.

### Draft gate: **DEFER (split)**
- The V21 bridge formula edit is itself safe and idempotent and CAN go into the draft now.
- BUT without the context flip the multiplier stays null and net=100 — **the V21-only edit cannot fix part (a) on its own.** Do NOT activate the bridge expecting the fix until the context regen lands.
- **Decision:** Stage the V21 bridge edit in the draft, but it is INERT until the context regen + re-sync window. Treat the context regen as a separate, gated change item (D-01-CTX) requiring a fresh deploy ack and a full deactivate→republish→reactivate of every proc bound to the context.

---

## E-03 — Seed OneTime Net Before Partner
**v21OnlyFixable = YES. Confidence: high.**

### New element — ListGroup `Seed OneTime Net Before Partner`
- api `OneTimeNetSeedPrePartner`, parent `null`, **sequenceNumber=19** (renumber existing 19+ up by 1; `ListContainer3`/PartnerDiscount becomes 20).
- **CHILD-1** AdvancedListFilter `OneTimeNetSeedFilter`, parent `OneTimeNetSeedPrePartner`, seq=1,
  logic `"1 AND 2 AND 3 AND (4 OR 5)"`:
  1. `SellingModelType NotEquals 'Evergreen'`
  2. `SellingModelType NotEquals 'TermDefined'`
  3. `ItemPricingSource NotEquals 'LastTransaction'`
  4. `DerivedPricingAttribute IsNull`
  5. `DerivedPricingAttribute Equals false`
- **CHILD-2** BKM `OneTimeNetSeed`, parent `OneTimeNetSeedPrePartner`, seq=2,
  `actionType=FormulaBasedPricing`, `selectedFunction=Get`;
  `formula-section-0-input = IF ( NetUnitPrice > 0 , NetUnitPrice , InputUnitPrice )`;
  `formula-section-0-output = NetUnitPrice`; Output Variable=`NetUnitPrice`.
- Modeled exactly on `AmendNetCarry`/`AmendSeedNetUnit` (seq39) + `SubscriptionPricing89`'s SellingModelType filter.

### Side-effect verdict (adversarial): PASS — guarded no-op
- New-sale OneTime that already prices: NetUnitPrice>0 → IF returns NetUnitPrice unchanged (no-op).
- Derived line: excluded by `DerivedPricingAttribute` gate AND would no-op anyway.
- Attribute-priced: net-bridges already seeded NetUnitPrice>0 upstream → no-op.
- TermDefined/Evergreen: excluded by filter (seeded later by SubscriptionPricing).
- Amend/LastTransaction: excluded by `ItemPricingSource` filter (AmendNetCarry handles).
- Currency: runs before seq35–38 conversion → seeds pre-conversion net like every other rail → consistent.
- No line type goes net-negative; only OneTime null/0-net non-derived lines change.

### Expected:
QLI `0QLWC000003kgXC4AY`: seed NetUnitPrice=InputUnitPrice=2008; PartnerDiscount55 applies 15% → NetUnitPrice=1706.8, TotalPrice=1706.8 (qty1). Was net 0 / total 0.

### Risk:
Inserting at seq19 renumbers downstream top-level steps → must deploy the **full ordered `steps[]`** (deactivate → deploy api67 `--metadata-dir` → reactivate, UI activation) then Force-reprice verify. Low correctness risk (guarded no-op); only OneTime/Perpetual non-derived path affected.

### Draft gate: **SAFE NOW**
Idempotency requirement (G-03's concern for new steps) is satisfied: the `IF(NetUnitPrice>0,...)` guard makes the second pass a no-op. SAFE to put in the draft.

---

## G-03 — Remove Double Currency Multiply
**v21OnlyFixable = YES. Confidence: high.**

### Edits — 4 top-level FormulaBasedPricing steps (parentStep=None), drop the `* IF(...)` multiply only, keep output param + step shell:

| Step | api | seq | FROM | TO |
|------|-----|-----|------|----|
| Currency Conversion - Net Unit Price | `CurrencyConversionNetUnitPrice` | 35 | `NetUnitPrice * IF(STICurrencyIsoCode='EUR',0.9346,...,1.0)` | `NetUnitPrice` |
| Currency Conversion - Unit Price Display | `CurrencyConversionUnitPriceDisplay` | 36 | `InputUnitPrice * IF(...)` | `InputUnitPrice` |
| Currency Conversion - Net Total / Subtotal | `CurrencyConversionNetTotalSubtotal` | 37 | `ItemNetTotalPrice * IF(...)` | `ItemNetTotalPrice` |
| Currency Conversion - Total Line Amount | `CurrencyConversionTotalLineAmount` | 38 | `TotalLineAmount * IF(...)` | `TotalLineAmount` |

Each nested-IF is the identical 9-ISO chain with `1.0` default.

### Side-effect verdict (adversarial): PASS — with a scope caveat
- USD new sale: was `*1.0`, now identity → unchanged (G-05 invariant holds).
- EUR/GBP renewal+COLA, EUR partner-discount: net already currency-native from EUR PBE (PBE=USD×rate EXACTLY, verified all 9 ISO); removing the 2nd multiply yields the correct single conversion; no change to USD.
- No derived-maint risk (derived net from contributor, currency-native).
- **AT-RISK:** attribute/tier (G-02) & regional-services (G-04) lines IF they reach seq35 holding a USD-base value (currency-blind lookups) lose their only FX → stay USD. **But today they are wrongly USD×rate anyway**; the true fix is G-02/G-04 currency-keyed lookups, not this step.

### Expected:
EUR repro `0QLWC000003ki7Z4AQ` (Cobalt Strike, qty3, EUR PBE 19159.30): NetUnitPrice settles at 19159.30 (was compounding to 81635.18); idempotent across N repricings (X=X fixed point). NetTotal/TotalLineAmount=19159.30×3=57477.90. USD same product=20500 unchanged.

### Risk:
Low-mech (4 in-place identity swaps, true fixed point, deterministic). Deploy via api67 deactivate→deploy→reactivate. Real risk is **SCOPE**: assumes PBE/all lookups are currency-native (proven for plain PBE lines + all 9 ISO PBEs); attribute/tier/regional lines that are currency-blind today depend on G-02/G-04 landing first, else they drop to USD.

### Draft gate: **SAFE NOW (with scope note)**
SAFE to put in the draft for the plain-PBE currency path. Scope caveat: this is the correct fix; it does NOT regress attribute/tier/regional lines beyond their current (already-wrong) state, but those lines remain wrong until G-02/G-04 land. Document that dependency; do not block G-03 on it.

---

## F-07 — Stamp Contributor Base (Pre-Discount), Idempotent Partner Discount
**v21OnlyFixable = YES. Confidence: high.**

Container `Stamp Contributor Base (Pre-Discount)` (api `StampContributorBasePreDiscount`, ListGroup, top-seq14; filter `StampBaseFilter` already gates non-derived / non-renewal / non-LastTransaction / Net>0).

Let **B = `IF(Has_Attribute_Adjustment__c=true, InputUnitPrice, IF(GSW__c=true, InputUnitPrice, ListPrice))`**.

### EDIT-1 — convert AssignmentElement → FormulaBasedPricing
- Step `Stamp Base_Price and Pre_Partner from Net` (api `StampBase_PriceandPre_PartnerfromNet`, parent `StampContributorBasePreDiscount`, seq2):
  - out `Base_Price__c`: **FROM** `NetUnitPrice` **TO** `B`
  - out `Pre_Partner_Price__c`: **FROM** `NetUnitPrice` **TO** `B`

### ADD-2 — new FormulaBasedPricing (model on `DerivedPricingNetUnitPriceValueReset`)
- label `Reset Net to Pre-Partner Base`, api `ResetNetToPrePartnerBase`, parent `StampContributorBasePreDiscount`, seq3,
  `formula-section-0-input = IF(PartnerDiscountPercent>0, B, NetUnitPrice)`, output `NetUnitPrice`,
  `formulaSectionCount=1`, `selectedFunction=Get`.
- Partner Discount (`PartnerDiscount55`, gseq19) then applies ×(1−0.15) **once**.

### Side-effect verdict (adversarial): PASS — idempotent, one stacking caveat
- New-sale plain partner: B=ListPrice=net pre-partner → ×0.85 once = correct (fresh quote no-op).
- Attribute partner (10 in org): B=InputUnitPrice (fresh attr base) → ×0.85 once, idempotent.
- GSA partner: B=InputUnitPrice=List×0.5.
- Non-partner (Fortra Originated): reset gated by `PartnerDiscountPercent>0` → NetUnitPrice untouched; Partner Discount filter also skips → unchanged.
- Derived: `StampBaseFilter` excludes `ItemIsDerived` → skipped, reads parent's now-correct base.
- Renewal/LastTransaction: filter excludes → untouched.
- **AT-RISK:** a plain partner line ALSO carrying a Volume/Bundle/AttributeDiscount-entry adjustment (gseq4–10) — reset to B drops that non-partner discount. **Mitigate:** keep the reset gated `PartnerDiscountPercent>0`; flag vol/bundle+partner stacking for follow-up.

### Expected:
OrderItem `802WC00000OpoppYAB`: NetUnitPrice=NetTotalPrice=301.75 (=355×0.85), Base_Price__c=Pre_Partner_Price__c=355.00, stable across every Reprice-All (was 133.888=355×0.85^6 / Base 157.515=×0.85^5). Matches locked UnitPrice/PartnerUnitPrice 301.75.

### Risk:
Low-moderate proc edit, UI-activate (deactivate→deploy→reactivate, api67). Idempotent by construction (B from ListPrice/InputUnitPrice, both re-seeded each pass). Verify `GSW__c` / `Has_Attribute_Adjustment__c` / `InputUnitPrice` / `ListPrice` all map in `SalesTransactionContextExt_v2` v23 (confirmed present). Boolean `=true` formula syntax to be smoke-tested in Simulate.

### Draft gate: **SAFE NOW**
SAFE with the `PartnerDiscountPercent>0` gate kept. Two pre-activation smoke tests: (i) Boolean `=true` syntax in Simulate; (ii) the vol/bundle+partner stacking case flagged for a separate follow-up (do not widen the reset gate to fix it here).

---

## SAFE-NOW vs NEEDS-MORE

**SAFE to put in the V21 draft now:**
- **E-03** — guarded no-op, idempotency satisfied by the `IF(NetUnitPrice>0,...)` seed guard.
- **G-03** — identity fixed point; correct for plain-PBE currency lines (scope dependency on G-02/G-04 documented, not blocking).
- **F-07** — idempotent by construction; keep the `PartnerDiscountPercent>0` gate; 2 Simulate smoke tests pre-activation.
- **D-01 (V21 bridge formula edit only)** — the formula swap is safe/idempotent and may be staged, but is INERT/no-fix until the context regen.

**NEEDS MORE before it actually fixes:**
- **D-01 context (D-01-CTX)** — `Attribute_Multiplier_Pct__c` output→inputoutput flip requires a NEW context version (next after V23), re-sync/republish of EVERY proc bound to `SalesTransactionContextExt_v2`, in a deactivate→republish→reactivate window. This is a context change, not a V21-only edit. **Defer and handle as a separate gated item with a fresh deploy ack.**
- **G-03 scope dependency (informational)** — G-03 itself is safe; full correctness of attribute/tier/regional currency lines additionally needs G-02/G-04 currency-keyed lookups. Not a blocker for G-03; track separately.
- **F-07 stacking follow-up (informational)** — partner+vol/bundle stacking handled by keeping the gate narrow; widening it is a separate ticket.

---

## Ordered list of concrete metadata edits to apply to the V21 draft

Apply in this order. The two STRUCTURAL inserts (E-03, F-07) must renumber/re-emit the full
ordered `steps[]`. Deploy api67, `--metadata-dir`, UI-only activation, deactivate→deploy→reactivate
window, then Force-reprice verify.

1. **F-07 EDIT-1** — `StampBase_PriceandPre_PartnerfromNet` (parent `StampContributorBasePreDiscount`, seq2): convert AssignmentElement→FormulaBasedPricing; set `Base_Price__c` out FROM `NetUnitPrice` TO `B`; set `Pre_Partner_Price__c` out FROM `NetUnitPrice` TO `B`  (B = `IF(Has_Attribute_Adjustment__c=true,InputUnitPrice,IF(GSW__c=true,InputUnitPrice,ListPrice))`).
2. **F-07 ADD-2** — insert new FormulaBasedPricing `ResetNetToPrePartnerBase` (parent `StampContributorBasePreDiscount`, seq3): input `IF(PartnerDiscountPercent>0,B,NetUnitPrice)`, output `NetUnitPrice`, `formulaSectionCount=1`, `selectedFunction=Get`.
3. **E-03 insert** — new top-level ListGroup `OneTimeNetSeedPrePartner` at **sequenceNumber=19**; renumber all existing top-level steps ≥19 up by 1 (`ListContainer3`/PartnerDiscount → 20); add CHILD-1 `OneTimeNetSeedFilter` (seq1, logic `1 AND 2 AND 3 AND (4 OR 5)`) and CHILD-2 `OneTimeNetSeed` (seq2, FormulaBasedPricing/Get, input `IF(NetUnitPrice>0,NetUnitPrice,InputUnitPrice)`, output `NetUnitPrice`).  *(Re-emit full ordered `steps[]`; confirm F-07's top-seq14 and the seq35–38 currency steps land at their post-renumber positions.)*
4. **G-03 ×4** — drop the `* IF(...)` multiply, keep output param + shell:
   - `CurrencyConversionNetUnitPrice` (seq35): input → `NetUnitPrice`
   - `CurrencyConversionUnitPriceDisplay` (seq36): input → `InputUnitPrice`
   - `CurrencyConversionNetTotalSubtotal` (seq37): input → `ItemNetTotalPrice`
   - `CurrencyConversionTotalLineAmount` (seq38): input → `TotalLineAmount`
   *(Note: post-E-03 these top-level seqs shift +1 — re-resolve by api name, not raw seq.)*
5. **D-01 V21 bridge edit (stage INERT)** — `AttributeValuePricingCalculatedModeNetBridge` (parent `ListContainer6`, seq3), `formula-section-0-input` FROM `IF(NetUnitPrice>0,NetUnitPrice,InputUnitPrice)` TO `IF(InputUnitPrice>0,InputUnitPrice,IF(NetUnitPrice>0,NetUnitPrice,Base_Price__c))`. Safe to stage; does not fix part (a) until D-01-CTX lands.

### Pre-activation smoke tests (Simulate, before reactivate):
- F-07: Boolean `=true` formula syntax compiles.
- F-07: partner+vol/bundle stacking line does NOT lose its non-partner discount (gate stays narrow).
- E-03 + G-03: re-run Reprice twice → idempotent (no second-pass drift).

### Deferred / handled separately (NOT in the draft activation):
- **D-01-CTX** — context `Attribute_Multiplier_Pct__c` output→inputoutput flip on `SalesTransactionContextExt_v2` (`11OWC000002m21Z2AQ`); regenerate + activate a NEW context version after V23; re-sync/republish EVERY proc bound to the context; deactivate→republish→reactivate window; requires a fresh explicit deploy ack. The staged D-01 bridge edit is inert until this lands.
- **G-02 / G-04** — currency-keyed lookups for attribute/tier/regional lines (G-03's scope dependency); separate work, does not block G-03.
- **F-07 stacking follow-up** — partner + volume/bundle/attribute-entry discount stacking; separate ticket; do not widen the reset gate.
