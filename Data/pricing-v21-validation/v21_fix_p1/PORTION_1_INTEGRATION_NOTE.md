# Portion 1 (Cancel / Amend / Proration) — Integration Note

**Org:** FortraUAT only. **Procedure:** `Rev_Mgmt_Default_Pricing_Procedure` V21 (Active, design `9QBWC0000000oWH4AY`, runtime ESV `9QMWC00000025LN4AY`, context `SalesTransactionContextExt_v2` v23).
**Status:** edits staged on a branch from the shared baseline. **NO DEPLOY done — awaiting fresh human ack + the other two portions.**

## Shared baseline (I am the integrator — I retrieved it once)
- `Data/pricing-v21-validation/v21_fix_baseline/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition`
- **md5 `d403d9618f21a20053b01437a59e16fd`**, 117,572 lines, retrieved 2026-06-29 ~22:14 @ API 67 (MDAPI manifest). **Frozen read-only.**
- This md5 was IDENTICAL to the 21:57 `proc_retrieve/` snapshot → the proc had stabilized.
- **All three tabs MUST branch from this exact file.** Do not re-retrieve (the proc drifts/oscillates between retrieves — confirmed: today's 4 retrieves all had different md5s).

## What Portion 1 changed (defects K-01 + I-03; F-12 de-scoped)
Working copy: `v21_fix_p1/unpackaged/.../Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition`. All edits confined to the **last `<versions>` block (V21)**. Versions 1–20 untouched.

### K-01 — fresh cancel line aborts at Stamp Base Filter (SC-3441, CRITICAL)
**Root cause:** `StampBaseFilter` criterion `NetUnitPrice GreaterThan 0` is not null-safe, AND the V18-era cancel-seed step (`CancelNetUnitPrice__c → NetUnitPrice`) was dropped in V20/V21. A fresh cancel line has `NetUnitPrice=null` → SF-Pricing-00006 abort.

- **K-01a (in-place, by name):** `StampBaseFilter` (child seq1 of `StampContributorBasePreDiscount`):
  conditionLogic `(1 OR 2) AND 3 AND 4 AND 5` → **`(1 OR 2) AND 3 AND 4 AND 6 AND 5`**; added criterion **6 = `NetUnitPrice IsNotNull`**. (Defense; the seed is the primary fix.)
- **K-01b (new top-level ListGroup):** `CancelSeedNetUnit` at **top-level seq 14**, modeled on V19 `ListContainer12`:
  - `CancelSeedFilter` (seq1, AdvancedListFilter): `CancelNetUnitPrice__c IsNotNull AND NetUnitPrice IsNull` (logic `1 AND 2`; the `NetUnitPrice IsNull` clause is a new idempotency guard not in V19).
  - `SeedInputUnitPriceFromCancel` (seq2, AssignmentElement): `CancelNetUnitPrice__c → InputUnitPrice`.
  - `SeedNetUnitPriceFromCancel` (seq3, AssignmentElement): `CancelNetUnitPrice__c → NetUnitPrice`.
  - Runs at seq14, immediately **before** `StampContributorBasePreDiscount` (now seq15) and **after** `SyncInputUnitPriceforDiscountBase` (seq13, which no-ops on cancel lines). So `NetUnitPrice` is non-null when `StampBaseFilter` evaluates → no abort.
- **Verify:** Quote `0Q0WC000003FZ3l0AG` (QLI `0QLWC000003kicD4AQ`, CancelNetUnitPrice__c=15000, qty −1) Force-reprices with **no SF-Pricing-00006**; `NetUnitPrice=15000`, `NetTotalPrice = −15000`.

### I-03 — mid-term TermDefined derives correct PTC but never prorates the net (SC-3420/3411, CRITICAL over-billing)
**Root cause:** V21 has **no TermDefined proration path at all** (the V20 `TermDefinedProrationFilterLinelevel`/`ProrationTermDefined` cluster was dropped; the only `Proration` step lives in the Evergreen-only container). `PricingTermCount` is Apex-stamped & persisted on the QLI (read-only) but the proc multiplies net by qty only — never by PTC.

- **I-03 (new child, by container):** `TermDefinedNetProration` (FormulaBasedPricing) added as **child seq3 of `ListContainer76`** (top-level seq27, the non-LastTransaction Quantity×Price container), right after `QuantityPrice78` (which sets `ItemNetTotalPrice = NetUnitPrice × LineItemQuantity`). Formula:
  `IF ( ISNULL ( PricingTermCount ) , ItemNetTotalPrice , IF ( SellingModelType = 'TermDefined' , ItemNetTotalPrice * PricingTermCount , ItemNetTotalPrice ) )` → output `ItemNetTotalPrice`.
  - Gate excludes OneTime (`OneTimePricingTermCountConstant=0` would zero the line), Evergreen, and null-PTC lines; TermDefined full-term (PTC=1) is a no-op.
  - Propagates to `TotalPrice` via `Assignment123` (seq47, `ItemNetTotalPrice → ItemTotalPrice`) and to the quote total via `TotalAmount` (seq42 SUM). **No top-level renumber.**
- **Verify:** QLI `0QLWC000002LCwH4AW` (PTC 0.7397) → NetTotal **554.79**; QLI `0QLWC000002SYdV4AW` (PTC 0.9616) → **240.41**; control `0QLWC000003kaUz4AI` (PTC 1) unchanged at **5900**.

### F-12 — DE-SCOPED (user direction: "don't touch it")
No amend-remove proration machinery was built. **Side effect to note:** because amend-remove lines also carry `CancelNetUnitPrice__c`, the K-01 seed will let the F-12 line (`0QLWC000003kkKf4AI`, CancelNetUnitPrice__c=1.5, qty −50000) price to a **flat −75000** credit instead of aborting. It will NOT be prorated (−37500). Suppressing this would require *adding* amend-exclusion logic (i.e. touching F-12), so the seed is left general per the de-scope.

## ⚠ Integration-critical items
1. **TOP-LEVEL RENUMBER (K-01b):** I inserted `CancelSeedNetUnit` at seq14 and renumbered **all 33 V21 top-level steps with seq≥14 by +1** (e.g. `StampContributorBasePreDiscount` 14→15, currency 36–39→37–40, `AmendNetCarry` 40→41, `TotalAmount` 41→42, … `Assignment123` 46→47). When merging Portion 2/3, **resolve steps by api `<name>`, not raw seq**, and re-emit ONE consistent ordered `steps[]`. Portion 2 (G-03/F-07) edits by name and does not renumber top-level; Portion 3 (K-09) may insert top-level steps near the category totals (seq42+) — reconcile both inserts into one final numbering.
2. **STAMP-STEP ADJACENCY (handoff-flagged):** `StampContributorBasePreDiscount` children — **I (P1) edited only the FILTER child `StampBaseFilter` (criteria), and did NOT reorder its children.** **Portion 2 (P2) owns `StampBase_PriceandPre_PartnerfromNet` (child seq2) and adds `ResetNetToPrePartnerBase`.** A git merge of these two child-level edits should be clean; integrator re-checks the child seq ordering after merge.
3. **7-TIER TRAP (CRITICAL — Portion 3 / integrator, NOT a P1 step):** the V21 `<description>` literally reads *"…Derived Pricing Formula reverted to 3-tier. DRAFT."* The frozen baseline carries the **stale 3-tier** derived formula. **Before the integrated deploy, diff the baseline's derived formula against the LIVE RUNTIME and restore the 7-tier formula**, or the deploy ships $0 on Basic/Premium/Express/Expert.
4. Keep the 2 `PricingActionParameters` context bindings; never hard-delete versions.

## Deploy / verify (DO NOT run without fresh human ack + all 3 portions integrated)
- Deploy mechanics: API 67, `--metadata-dir`, **deactivate active V21 → deploy combined version → reactivate in UI**, then Force-reprice each evidence record.
- Force-reprice recipe: `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place` body `{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<id>"}}}]}}`, then re-query the fields.
- Final shared reprice (with the other tabs): BoKS demo `0Q0WC000003FKRJ0A4`, an EUR quote, a cancel quote.
