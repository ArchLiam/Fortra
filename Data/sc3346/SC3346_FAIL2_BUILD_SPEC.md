# SC-3346 FAIL 2 — Renewal Derived-Maintenance $0 — Build Spec

**Owner:** Liam (RCA / pricing engine)  ·  **Date:** 2026-07-09  ·  **Org:** FortraUAT, active proc **V23**
**Status:** reprice-time fix **DEAD** (proven). Real fix = make the line a **priced node** (born-net). One diagnostic can still change the verdict — run it first.

---

## 1. Confirmed root cause (debug-log proven)

Renewal derived-maintenance lines are **never in the writable pricing context** (`SalesTransactionItem` is empty), so **every** COLA-net write no-ops.

Evidence — FINEST log `Data/sc3346/flush_test.log` (ApexLog `07LWC00000Q9OLw2AN`), reprice of 7AKH `0Q0WC0000037AKH0A2` line 04266205 (Draft, healthy status, USD):
- The `Fortra_Quote_Reprice` flow = Build_Context → **Apply_Renewal_Maintenance_Net** → Run_Pricing (`runSalesforcePricing`) → Apply_Partner_Net_Posthook → **Finalize_Renewal_Maintenance_Net** → Persist.
- `RenewalMaintenancePricingService` (now WIRED; used to be dead code) computes the **correct 3-component net**: `preColaNet = 71 − 8.52 = 62.48`, `colaNet = 62.48 × 1.0785 = 67.38` — matches the SDD, and is *better* than the stored single-component `COLACalculatedPrice__c = 76.57`.
- It calls `Context.IndustriesContext.updateContextAttributes(...)` → **`{isSuccess:true}`** — twice (applyToContext + applyColaNetFinalizeToContext).
- BUT `queryTags({tags:['SalesTransactionItem']})` returns **`SalesTransactionItem:[]`** — empty — **before Run_Pricing AND after Run_Pricing AND in the post-pricing finalize pass**. So both writes hit an empty context and are silently discarded. NetUnitPrice stays 0 on 7AKH and DOpB.

**Why the line isn't a priced node:** renewal derived lines are excluded from native derived pull (`DerivedProductsNativePull` → filter `DerivedProductsNonRenewal` = `QuoteTypeText__c ≠ 'Renewal'`), and there is no resolvable contributor asset for them (customers own the New-Maint `-RNM-` asset, the renewal line is the derived `-RRM-` product — SKU mismatch, no Asset-Discovery → LastTransaction). With no contributor and no native pull, the engine never materializes a `SalesTransactionItem` for the line → nothing to write to.

**This is the same wall as FAIL 1's qty=10 line** (NetUnitPrice = null, not 0 → not processed → not a priced node; contributor-starved: 2 BoKS licenses vs 3 maint lines).

## 2. What is already built and correct (all blocked by §1)

| Component | State | Verdict |
|---|---|---|
| `RenewalMaintenancePricingService` (applyToContext + applyColaNetFinalizeToContext) | Wired into `Fortra_Quote_Reprice`; computes **67.38** correctly | Correct value, **write no-ops on empty context** |
| Procedure `DerivedPricingFormula` renewal branch (canvas-editable) | Test edit `IF(NetUnitPrice>0,…,IF(COLACalc>0,COLACalc,…))` applied live | Ran, **did not flush** (line not in context) — **revert it** |
| `PartnerNetPricePosthook` renewal-maint path | live | no-ops on empty context |
| `COLAUpliftPrehook.computeStampedMaintenanceColaNet` | live | 3-component math correct; stamps `COLACalculatedPrice__c` (audit field only) |

**Conclusion:** the math is solved five times over. The *only* missing thing is getting the line into `SalesTransactionItem`. No further reprice-time / formula / hook / service change can do that.

## 3. Decisive diagnostic — ✅ RUN 2026-07-09, verdict = FUNDAMENTAL (not fossil-degradation)

Ran real `initiateRenewal` on a **fresh** BoKS contract (00069410) → fresh renewal quote, then repriced via the **full Place-Sales-Transaction Force engine** (the UI "Reprice All" engine, not the lighter `Fortra_Quote_Reprice` flow — which by itself priced nothing on a fresh quote). Result on the otherwise-fully-priced fresh quote:

| Line | Selling model / QuoteAction | NetUnitPrice |
|---|---|---|
| BoKS license `PIA-PIA-NRPS-PIAP` | Perpetual / No Change (non-derived) | **312.40 ✓** |
| beSECURE `VM-BSL-RSL-BESECB` | Subscription / **Renew** | **6257.16 ✓** |
| BoKS maint `PIA-PIA-RNM-PIAMBK` | New Maintenance / **Amend** (derived) | **$0 ✗** |

**The derived maintenance line is the SOLE non-committer** while the license and subscription price correctly → it is genuinely the derived-maint wall, not fossil data or a reprice-mechanism artifact. **Determinant: the renewal assigns the subscription `Renew` (→ priced node → commits) but the OneTime derived maint `Amend` (→ never a priced node → $0).** PST Force body that works (id INSIDE attributes, lowercase): `{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"g1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<quoteId>"}}}]}}`.

### (superseded) original diagnostic plan

All my tests used the **old canary quotes** (7AKH, DOpB, DLBO) which may be **degraded fossils** (the empty `SalesTransactionItem` might be quote-specific, not fundamental). Before building any architecture:

> **Create a FRESH renewal quote today** (via the real `initiate-renewal` / `Fortra_Create_Renewal_Quote` on a BoKS maintenance asset), reprice it, and grep the log for `queryTags … SalesTransactionItem`.
> - **Fresh quote's context has the maint line** → the old quotes are just degraded; renewal maint may already price on real renewals → **likely no live defect** (close as data). 
> - **Fresh quote's context is ALSO empty** → fundamental; proceed to §4.

## 4. Real fix options (if §3 confirms fundamental) — all make the line a priced node

**Option A — Born-net via Renew QuoteAction + resolvable contributor (recommended).** Make the renewal flow attach a `Type='Renew'` QuoteAction whose `SourceAsset` the engine's Asset Discovery resolves → `ItemPricingSource=LastTransaction` → the line becomes a priced node → the existing `RenewalMaintenancePricingService` write (67.38) lands. **Sub-wall (from prior sessions):** the owned asset is `-RNM-` (New Maint) but the line is derived `-RRM-`; Asset Discovery needs a match. Bridges: (a) `Map Products` mapping RNM→RRM in the discovery procedure so the owned RNM asset resolves as contributor; (b) create the maintenance asset as RRM on new-business so renewals have a matching asset; (c) point the QuoteAction SourceAsset at the license and re-derive. Each needs a live born-net test (set NUP at creation, before the line settles).

**Option B — Non-derived renewal-maintenance line.** Model the renewal-maint line as a regular priced line with its own PBE (not `ItemIsDerived`). A non-derived line is always a `SalesTransactionItem` priced node → the COLA net commits normally. Catalog/selling-model change; largest blast radius but removes the derived-pricing dependency entirely.

**Option C — Selling-model → term-based renewable.** Model maintenance as a term-based subscription (like beSECURE) so `initiate-renewal` renews it natively as a priced 'Renew' line that enters the context. Product decision; the RRM product already carries a term-based selling-model option, so the modeling exists.

## 5. Recommendation (updated after §3 verdict)

§3 confirmed the wall is real, and the **beSECURE control validated the fix direction**: a term-based line renewed as `Renew` and committed (6257.16); the OneTime derived maint renewed as `Amend` and stayed $0.

1. **Option C (recommended) — model BoKS maintenance as a term-based renewable** (like the subscription). Then `initiateRenewal` gives it a `Renew` action → priced node → the already-correct COLA path (`RenewalMaintenancePricingService` computes 67.38) commits. Corroborated twice: the beSECURE control this run, and the prior IP360 term-based-maint renewal committing 2097.9. Catalog/selling-model change (a product decision you own), lowest engine risk.
2. **Option A** — if keeping OneTime maint, make the renewal assign the maint line `Type='Renew'` bound to a resolvable contributor (Map Products RNM→RRM). More engine plumbing; the contributor SKU-match is the make-or-break.
3. **Option B** — non-derived renewal-maint line (the No-Change *license* proves non-derived commits). Larger catalog change.
4. **Revert** the V23 canvas test edit (inert) — user taking the canvas action. Posthook FAIL-1 default already reverted.

**Bottom line:** the COLA math + committer are done and correct; the only gap is the maint line renewing as `Amend`/derived instead of `Renew`/priced-node. Fix that (Option C simplest) and FAIL 2 resolves.

## 6. FAIL 1 note

FAIL 1's qty=10 line is the same wall (not a priced node — contributor-starved). Its qty=1 siblings price correctly (4000). It is most likely a **malformed test line** (an extra maint line with no matching license), so `$0` is arguably correct — confirm the quote's intent. Real 1:1 new-maint lines are unaffected. No pricing-code change fixes a starved line; the fix (if it's a real scenario) is 1:1 maint↔license matching at quote build.
