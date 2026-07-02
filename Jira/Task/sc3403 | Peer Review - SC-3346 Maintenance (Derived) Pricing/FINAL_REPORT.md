# SC-3346 / SC-3403 — Final Remediation Report (2026-06-13)

**Scope:** re-verify and remediate the 11 SC-3403 peer-review findings on **FortraUAT only** (per directive: *no prod changes*). Owner of remediation: Liam. Build owner: Nir/Marc.

## Verdict
Peer review opened at **NO-GO (4 RESOLVED / 3 PARTIAL / 4 NOT RESOLVED)**. After this remediation: **8 closed, 1 cleared/dropped, 2 out-of-scope (prod), 1 remaining blocker (owner-gated).** The renewal *engine* fix is live and proven correct; the only thing standing between here and a renewal that prices end-to-end is **SC-3404**, which is designed but cannot be safely executed without owner confirmation or a clone test.

## Scorecard (all 11 findings)
| # | Finding | Final state | Evidence |
|---|---------|-------------|----------|
| B-3 | Partner picks 15% not 12% | ✅ RESOLVED | bulk overload falls through to Product2 lookup; test green |
| B-4 | Renewal formula null-guards | ✅ RESOLVED (engine) | **V14 deployed + active** with ISNULL guard; computes 67.38 in-flight (proven in log). *Display* gated by SC-3404. |
| B-5 | Decision-table refresh failing | ✅ CLEARED / DROPPED | **B1 repro:** renewing both assets succeeded, never touched the table, no error. Not on the failing path → no window needed. |
| B-6 | Decomposition inconsistent | ✅ RESOLVED | persistFromWork unconditional; 0 license-base leaks |
| M-1 | "No prehook" SDD false | ✅ RESOLVED | reconciliation note delivered ([08](08_M1_SDD_RECONCILIATION.md)); owner applies the .docx text |
| M-2 | Competing new-biz formulas | 🟡 READY (rides w/ SC-3404) | dead-code removal; **dossier corrected** (system uses Source_List_Price__c, not Base_Price__c; MDT is a typo) |
| M-3 | Prod lacks `_v2` context | ⛔ OUT OF SCOPE | prod item — excluded per UAT-only directive |
| M-4 | Source_List_Price mapping | ✅ RESOLVED | live deployed class has mapping active |
| M-5 | 2 of 4 derived PBEs uncovered | ✅ RESOLVED | Nir created the 2 PBEDP rows |
| M-6 | Prod prehook stale | ⛔ OUT OF SCOPE | prod item — excluded per UAT-only directive |
| M-7 | Renewal classes untested | ✅ RESOLVED | solo runs: 100% / 98% / 92% (review's 15%/36% was a stale partial-aggregate) |
| **SC-3404** | **NEW: native element zeros the renewal maintenance line** | 🔴 **REMAINING — designed, owner-gated** | the actual cause of $0 renewals; see below |

## Fixed this session
- **B-4** — cloned V14 from V13 with the **ISNULL**-guarded renewal formula (corrected from the review's invalid `BLANKVALUE`), deployed inactive, activated (recovered an 8-versions-active LWC corruption via per-row Activate), context healthy, reprice clean. The formula computes the correct 67.38 in-flight (proven in FINEST log).
- **M-7** — verified the existing dedicated tests already deliver ≥75% (solo runs); no new code needed.
- **M-1** — wrote the exact SDD reconciliation (the prehook stack is real and necessary; "no prehook" is true only for the new-business derived path).

## B-5 — cleared by repro (key result)
Native "renew both assets" on the BoKS test contract (#00069255) **succeeded**: created a 2-line renewal quote, `ValidationResult=None`, FINEST log clean with **zero** hits for the AssetActionSource table / "Hash Key Group" / "MissingContributor". The table has been unsynced ~12 months while renewals work via Q2O carry-forward. **B-5 is not on the renewal failing path → dropped from SC-3346; the disruptive maintenance window is off the table.**

## SC-3404 — the real renewal blocker (designed, NOT executed)
**What it is:** in active V14, the native `DerivedProductsRenewals` element (`resultIncluded=true`, authoritative) **overwrites** B-4's correct 67.38 with the native value (0) for the maintenance line. Proven twice in live FINEST logs (formula computes 67.38; committed NetUnitPrice = 0). This is why renewal maintenance shows $0 — *not* B-4, which is correct.

**Design (ready):** make the native element non-authoritative **only** for the stamped SC-3346 cohort (5 lines) while it stays authoritative for the **536,195** native-priced lines. Two drafted edits: amend the `DerivedProductsNonRenewal` filter to exclude the stamped cohort, and set `DerivedPricingRenewals` `resultIncluded=true`. Full design + line refs: `Data/sc-maint/sc3404/`.

**Why it was NOT executed (NO-GO for blind/in-place):** three load-bearing facts are unknowable from the metadata, and any one wrong **silently zeros the 536,195 lines** with no rollback net (in-place V14, no clone, version-delete platform-blocked):
1. **Commit-precedence** (last vs first `resultIncluded=true` writer wins) — decides one edit vs two.
2. **Filter polarity** — `DerivedProductsNonRenewal` "keeps non-renewals" yet native commits 31 live renewal lines; retain-vs-exclude semantics unproven.
3. **Formula container Branch B** (`Renewal AND ItemIsDerived`, no stamp) is broader than the stamped cohort → flipping `resultIncluded` would commit `(0 − priors)×(1+uplift)` = 0/negative for unstamped derived renewals → mass-misprice.

**Path to GO (pick one):**
- **(a)** Nir/Marc confirm commit-precedence + filter polarity (they built V14) → apply the verified edits in-place with the FIM-462 regression gate + context resync + V14 backup; **or**
- **(b)** validate on a V14 **clone** with an authorized reprice (positive 67.38 test + FIM-462 native-preserve + Branch-B no-zero) — requires relaxing "no new versions" for the test (delete is platform-blocked).

## Current UAT live state
- Pricing procedure **V14 active** (sole) — carries B-4's ISNULL renewal fix; new-business + non-renewal pricing clean (no gack, healthy limits).
- Renewal maintenance **still displays $0** pending SC-3404.
- Nothing left in a broken/half-applied state; B-4's V14 is healthy and reversible (re-activate V13 + resync).

## Out of scope (per "UAT only — no prod changes")
- **M-3 + M-6** (prod context + prod prehook) — not prepared or touched. A prod-cutover manifest exists in [09](09_REMAINING_EXECUTION_PLAN.md) for whenever a prod cutover is separately authorized.

## Recommended next steps (owner)
1. **SC-3404** — get Nir/Marc to confirm the engine semantics (a/above) or authorize a clone test; then execute the verified edit (M-2 rides along). This closes renewal E2E.
2. Apply the M-1 SDD text edits (doc owner).
3. Treat B-5 as a latent platform item (no action needed for SC-3346).
4. Prod cutover (M-3/M-6 + the validated V14) — separate, explicitly-authorized engagement.

**Dossier:** 02 (blockers) · 05 (re-verification) · 06 (B-5) · 07 (B-4) · 08 (M-1) · 09 (remaining plan) · 10 (B-5 runbook) · this report. Artifacts: `Data/sc-maint/reverify/`, `Data/sc-maint/sc3346_b4/`, `Data/sc-maint/sc3404/`.
