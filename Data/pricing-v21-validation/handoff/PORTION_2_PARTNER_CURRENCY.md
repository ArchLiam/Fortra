You are fixing **3 critical pricing defects in the V21 procedure** in the **Fortra FortraUAT** org —
the Partner-net + Currency-idempotency cluster. Two sibling tabs are concurrently editing **other steps of the
same procedure**; follow the shared-procedure merge discipline below so you don't clobber them.

## Environment & rules
- **Org = `FortraUAT` only** (`-o FortraUAT`). The `uat` alias is a DIFFERENT (5sInfusion) org — never use it.
- **Active procedure:** `Rev_Mgmt_Default_Pricing_Procedure` **V21** — design `9QBWC0000000oWH4AY`, runtime ESV
  `9QMWC00000025LN4AY`, context `SalesTransactionContextExt_v2` v23. Confirm Active first (tooling query on
  `ExpressionSetDefinitionVersion`).
- This is a **FIX** task. **Get a fresh explicit human ack before any UAT deploy / version activation.**
- Diagnosis + evidence: `Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md` (§3 → E-03, F-07, G-03).
  Step skeleton: `Data/pricing-v21-validation/V21_step_skeleton.md`.

## ⚠ Shared-procedure merge discipline (all 3 tabs edit ONE metadata file)
1. **Start from the shared baseline** at `Data/pricing-v21-validation/v21_fix_baseline/` (a single live retrieve
   all tabs share — do NOT re-retrieve at a different time; the proc drifts/oscillates). If absent, ask the
   integrator (Portion 1) to create it, then branch from it.
2. **Edit ONLY your steps:** the **Subscription Pricing One-Time branch** (skeleton steps 110-112), **Stamp
   Base_Price and Pre_Partner from Net** (step 106) + **Partner Discount** (steps 87-88), and **Currency
   Conversion** (steps 33-36). Do not touch cancel/proration/derived/category steps (other tabs own those).
3. **Do NOT deploy on your own.** Commit your step edits to a branch; the integrator (Portion 1) merges all
   three portions into **one new draft version** for a single deactivate→deploy→reactivate.
4. **7-tier trap:** preserve the live 7-tier derived formula in the integrated version (don't ship a stale
   3-tier snapshot). Keep the 2 `PricingActionParameters` context bindings; never hard-delete versions.
- **Verify (after the integrated deploy)** with a Force-reprice on each record, then re-query:
  `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place`
  body `{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<id>"}}}]}}`

## Your 3 defects

**E-03 — One-Time/Perpetual partner net zeroed.** (SC-3359, CRITICAL — whole deal type mis-priced)
- Cause: on the One-Time/Perpetual branch of `Subscription Pricing`, the partner discount % is resolved but the
  net is left at 0 (the branch re-reads the undiscounted `InputUnitPrice`/zeroes `NetUnitPrice`), while
  `TotalLineAmount` stays at list.
- Fix: on the **One-Time branch**, write the discounted net to `NetUnitPrice` (mirror the working TermDefined
  branch): `NetUnitPrice = InputUnitPrice × (1 − PartnerDiscountPercent/100)`. Keep `TotalLineAmount=list` via a
  deliberate list seeder if that channel must show list.
- Verify: Quote `0Q0WC000003FWCM0A4` → `NetUnitPrice` **1706.8** (=2008×0.85), not 0.

**F-07 — Order Reprice-All not idempotent: partner discount compounds.** (SC-3346, CRITICAL — price erodes each reprice)
- Cause: `Stamp Base_Price and Pre_Partner from Net` (step 106) seeds `Base_Price__c` **from the already-
  discounted net**, so every Reprice-All re-applies the 15% (301.75 → 256.49 → 218.01 → 157.52).
- Fix: on the **order context**, derive the partner-discount base from the immutable pre-partner list/base
  (stable across passes), and recompute the partner NET from that base each pass — idempotent. (Mirror the
  SC-3346 `PartnerNetPricePosthook` approach: stable base, recompute net, don't feed discounted net back into base.)
- Verify: Order `801WC00000knHDLYA2` → run Reprice-All 3× and the partner net **holds stable** (no geometric drift).

**G-03 — EUR FX re-applied every reprice (×0.9346^n).** (SC-3384, CRITICAL — price erodes each reprice)
- Cause: `Currency Conversion` steps 33-36 multiply the **already-converted stored value** by the EUR
  multiplier again on each pass (Unit 93460 → 81635 over 3 reprices), and partner net isn't stamped for
  non-UI-seeded lines.
- Fix: make the conversion **idempotent** — convert from an immutable USD/list base each pass, OR guard each FX
  step to apply only when the source value is not already in quote currency. Stamp the partner net on lines
  that weren't UI-seeded.
- Verify: Quote `0Q0WC000003FYMD0A4` → `UnitPrice` and `ALE_Base` **stable across 3 reprices** (compare to the
  USD control E-02 quote `0Q0WC000003FO1u0AG` which is already stable).
- Note: this fixes only the FX *idempotency*. The related **currency-blind tier KEY overcharge** (G-02/D-09,
  +19.82 EUR) lives in the `AttributeVolumePricingPrehook` Apex class, which is **out of scope** here (deferred).

## Done criteria
Your 3 step edits are on a branch from the shared baseline; after the integrated deploy the 3 records reprice
to expected; you confirmed your **Stamp Base_Price (step 106)** edit is the only one touching that step
(Portion 1 owns the adjacent Stamp Base Filter 105, Portion 3 owns Stamp Contributor Base 107 — distinct
elements). Then join the **final joint reprice** on the shared records with the other tabs.
