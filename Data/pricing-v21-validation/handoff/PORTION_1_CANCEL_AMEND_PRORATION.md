You are fixing **3 critical pricing defects in the V21 procedure** in the **Fortra FortraUAT** org —
the Cancel / Amend / Proration cluster. Two sibling tabs are concurrently editing **other steps of the same
procedure**; you must follow the shared-procedure merge discipline below so you don't clobber them.

## Environment & rules
- **Org = `FortraUAT` only** (`-o FortraUAT`). The `uat` alias is a DIFFERENT (5sInfusion) org — never use it.
- **Active procedure:** `Rev_Mgmt_Default_Pricing_Procedure` **V21** — design `9QBWC0000000oWH4AY`, runtime ESV
  `9QMWC00000025LN4AY`, context `SalesTransactionContextExt_v2` v23. Confirm still Active:
  `sf data query --use-tooling-api -o FortraUAT -q "SELECT VersionNumber,Status FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName='Rev_Mgmt_Default_Pricing_Procedure' ORDER BY VersionNumber DESC"`
- This is a **FIX** task. **Get a fresh explicit human ack before any UAT deploy / version activation.**
- Diagnosis + evidence: `Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md` (§3 → K-01, F-12, I-03).
  Step skeleton: `Data/pricing-v21-validation/V21_step_skeleton.md`.

## ⚠ Shared-procedure merge discipline (all 3 tabs edit ONE metadata file)
1. **Start from the shared baseline** at `Data/pricing-v21-validation/v21_fix_baseline/` (one live retrieve all
   tabs share). If it doesn't exist yet, you are the integrator — retrieve it once
   (`sf project retrieve start -o FortraUAT -m "ExpressionSet:Rev_Mgmt_Default_Pricing_Procedure" -r Data/pricing-v21-validation/v21_fix_baseline`, API 67)
   and tell the others to branch from it. **Do not re-retrieve at a different time** (the proc drifts/oscillates).
2. **Edit ONLY your steps:** the **Stamp Base Filter** (skeleton step 105), a **new cancel-seed step** inserted
   just before it, and the **Proration** cluster (steps 97 + 121-123). Do not touch partner/currency/derived/
   category steps (other tabs own those).
3. **Do NOT deploy on your own.** Commit your step edits to a branch; the integrator merges all three portions
   into **one new draft version** and does a single deactivate→deploy→reactivate.
4. **7-tier trap:** before the integrated deploy, diff the baseline's derived formula against the live runtime
   and preserve the **7-tier** formula (a stale 3-tier snapshot ships $0 on Basic/Premium/Express/Expert).
5. Keep the 2 `PricingActionParameters` context bindings; never hard-delete versions.
- **Verify (after the integrated deploy)** with a Force-reprice on each record below, then re-query:
  `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place`
  body `{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<id>"}}}]}}`

## Your 3 defects

**K-01 — Fresh cancel line aborts at Stamp Base Filter.** (SC-3441, CRITICAL — cancellations broken from a clean state)
- Cause: `Stamp Base Filter` criterion `NetUnitPrice GreaterThan 0` is **not null-safe**, AND the V18-era
  cancel-seed step (`CancelNetUnitPrice__c → NetUnitPrice`) was dropped in V20/V21.
- Fix: (a) re-add a seed step **before** Stamp Base Filter — gate `CancelNetUnitPrice__c IsNotNull AND
  NetUnitPrice IsNull` → set `NetUnitPrice` and `InputUnitPrice` from `CancelNetUnitPrice__c`; (b) make the
  filter null-safe: `NetUnitPrice IsNotNull AND > 0` (or a Cancel / qty<0 bypass).
- Verify: Quote `0Q0WC000003FZ3l0AG` Force-reprices with **no SF-Pricing-00006**; the cancel line nets the
  negative credit (NetUnitPrice = the seeded value, totals negative).

**F-12 — Partial amend-remove aborts; needs a prorated negative delta.** (SC-3441, CRITICAL) — build ON TOP of K-01.
- After K-01's seed/filter fix lets the negative line price, route `ItemSalesTransactionAction='Amend'` lines
  with qty<0 through the TermDefined proration with their remaining-term window so `PricingTermCount` (≈0.5 for
  6/12 months) multiplies the negative net — a prorated credit, not a flat full-credit or $0.
- Decide product intent WITH the user: should a mid-term remove credit only the unused remaining term
  (prorated) or the full line (flat)? Implement accordingly.
- Verify: Quote `0Q0WC000003FapR0AS` (QLI `0QLWC000003kkKf4AI`, −50000 of 100000, 6/12 months) →
  TotalPrice ≈ **−37500** (=−50000×1.5×0.5), not 0 and not −75000.

**I-03 — Mid-term TermDefined derives correct PTC but never prorates the net.** (SC-3420/3411, CRITICAL — over-billing)
- Cause: the `Proration` step derives the fractional `PricingTermCount` correctly, but NO downstream
  `Quantity × Price` / Aggregate / Total step multiplies the net by it (the net-proration leg was dropped in
  the V11→V12 rebuild; SC-3420 restored the PTC writer but not the price leg).
- Fix: add a **TermDefined-gated** step that sets `NetTotalPrice = NetUnitPrice × Quantity × PricingTermCount`
  before/within the Total aggregation, guarded `SellingModelType='TermDefined' AND StartProrationPeriod
  IsNotNull AND ItemSubscriptionTerm IsNotNull` so full-term (PTC=1) lines stay inert. Mirror native RLM term-price behaviour.
- Verify: QLI `0QLWC000002LCwH4AW` (PTC 0.7397) → NetTotal **554.79** (=250×3×0.7397); QLI
  `0QLWC000002SYdV4AW` (PTC 0.9616) → **240.41**; full-term control `0QLWC000003kaUz4AI` (PTC 1) unchanged at 5900.

## Done criteria
Your 3 step edits are on a branch from the shared baseline; after the integrated deploy, the 3 records above
reprice to their expected numbers; you flagged any adjacency on Stamp step 105 to the integrator (Portion 2
owns the adjacent step 106). Then join the **final reprice** on the shared records (BoKS demo
`0Q0WC000003FKRJ0A4`, an EUR quote, a cancel quote) with the other tabs.
