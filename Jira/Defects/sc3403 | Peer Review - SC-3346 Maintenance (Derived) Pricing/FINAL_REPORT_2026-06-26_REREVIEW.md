# SC-3403 — Maintenance (Derived) Pricing (SC-3346): peer RE-review

**Reviewer:** Liam Jeong · **Date:** 2026-06-26 · **Org:** FortraUAT (`00DWC000006eUFF2A2`), read-only
**Method:** 61-agent live-grounded workflow — Capture (7 parallel probes of the live procedure / flows / Apex / tests / data / delta / prod-gap) → Assess (6 AC + prior-findings clusters) → adversarial Verify (one skeptic per material verdict, 47 challenged, 10 overturned) → Synthesize.
**Supersedes:** `FINAL_REPORT.md` (2026-06-13) and `README.md` (2026-06-11) — the build advanced materially since (active proc V14→**V16**; Apex stack churned through 2026-06-24).

---

## VERDICT: 🟡 CONDITIONAL-GO

**The maintenance pricing LOGIC is correct in UAT for the sanctioned BoKS scope, and demonstrably works on live data. Production deployment is a hard NO-GO** — the entire SC-3346 layer is from-zero in PROD, two load-bearing classes are below the 75 % coverage gate, and the renewal commit is not yet proven end-to-end on V16.

| Dimension | State |
|---|---|
| New-business pricing logic (BoKS) | ✅ correct & reproduced live (Base 355 → Net 71, ratio 0.20; Premier → 106.50) |
| Renewal pricing logic (SC-3404) | 🟡 root cause structurally fixed in V16; **unproven E2E** on current stack |
| Prior blockers B-3/B-4/B-6, majors M-2/M-4 | ✅ resolved |
| Test suite functional pass/fail | ✅ all 302 maintenance test methods green; COLAUpliftTest drift gone |
| Per-class coverage gate (M-7) | 🔴 PartnerNetPricePosthook 59.5 %, QuoteToOrderFieldMapper 65.2 % (<75 %) |
| Production packaging / parity (B-2) | 🔴 from-zero: 8/11 classes, all triggers, `_v2` context, V16 proc, 7 rate rows, 23+32 fields all absent in PROD |

---

## What genuinely changed since the last review

1. **SC-3404 root cause structurally fixed (V16).** The native `DerivedProductsRenewals` element (`resultIncluded=true`) is now scoped *out* of renewal lines by the sibling `DerivedProductsNonRenewal` `AdvancedListFilter` (`QuoteTypeText__c NotEquals 'Renewal'`) that runs before the native pull. It can no longer overwrite the renewal COLA value. `List Container 2` (`COLACalculatedPrice__c → NetUnitPrice`, gated `SalesTransactionActionType='Renew'`) is the last NetUnitPrice writer on renewal lines. Implemented as list-scope, **not** by toggling `resultIncluded` off — which sidesteps the 536 K mass-misprice risk the old SC-3404 design carried.
2. **NB-DERIVED-TIER resolved.** Active V16 `DerivedPricingFormula` encodes **all 7 tiers** (Basic .15 / Professional .20 / Standard .20 / Premium .24 / Express .30 / Premier .30 / Expert .35) matching `Maintenance_Rate__mdt`, vs the V14 3-of-7 hard-code that zeroed the rest.
3. **M-2 dead competing formula gone** from the active proc: 0 `Source_List_Price__c`, 0 `platinum` references in V16; exactly one formula reading the stamped `Base_Price__c`.
4. **B-3 fixed.** `PartnerPricingService` bulk overload no longer hard-returns `'Software'` on a map-miss; it falls through to the single-arg resolver (`'Software'` is only the terminal fallback).
5. **SC-3410/3412 born-zero fix live.** `PartnerNetPricePosthook.buildNewMaintenanceUpdate` fires only when `procedureNet<=0` ("never override a priced line") and computes `pricingBase × rate × (1−partner%) × (1−software%)`. Reproduced live: 21 BoKS New-Maint lines Base 355 → Net 71.
6. **COLAUpliftTest 41-error drift gone** — suite compiles, 302 named maintenance test methods pass (0 fail/skip).
7. **⚠️ RenewalMaintenanceFlip was DE-WIRED on the 2026-06-24 republish** — `Fortra_Create_Renewal_Quote` V7 called it; the active V8 dropped that node (the SC-3371 lost-fix-on-republish pattern). Renewal commit now runs via `RenewalMaintenancePricingService` wired into `Fortra_Quote_Reprice`. Flip is dead-wired but still in the org.

---

## Scorecard

### Acceptance criteria
| AC | Verdict | Note |
|---|---|---|
| AC1 base = source UnitPrice × tier | ✅ PASS | 21 live BoKS lines 355→71 (0.20); 106.50 on Premier path |
| AC2 base discount-immune | ✅ PASS | 3 layers key on pre-discount source fields; `StampContributorBasePreDiscount` runs before discount containers |
| AC3 base tracks attribute change | ✅ PASS | source attribute-priced (seq 6/7/8) before LC9 captures it |
| AC4 discounts after base | ✅ PASS | LC9 (seq 17) then maintenance discount group (seq 21) |
| AC5 stable across reprices | ✅ PASS | multiplies stamped license base, never the line's own NetUnitPrice |
| AC6 tier change 0.20→0.30 | ✅ PASS | both APVs exist; formula + Apex data-driven |
| AC7 selling-model backfill | ✅ PASS | BoKS chain fully aligned; both maint PBEs have PBEDP |
| AC8 renewal 3-component carry-forward | ✅ PASS *(skeptic overturned PARTIAL)* | live in `RenewalMaintenancePricingService.computeColaNet` + Flow fallback; 67.38 = 62.48×1.0785 |
| AC9 renewal overrides native pull | ✅ PASS | native pull filtered out; LC2 last writer |
| AC10 COLA + components from Flow, no double-discount | ✅ PASS | Apex guard returns null for COLA-owned lines before deferred-partner |
| AC11 branch partition by QuoteTypeText__c | ✅ PASS | every shared step gated on `QuoteTypeText__c='Renewal'` |
| AC12 no Apex prehook / one Flow only | 🔴 FAIL (minor) | TWO active stamp flows + real Apex prehook+posthook write net — architecture deviates from SDD principle (no mispricing) |
| AC13 fallback / straggler tiers | 🔴 FAIL (major, latent) | active SKU `GS-GSE-RRM-EFSMB` defaults to off-list `platinum` (no rate row) → silent $0 |
| AC14 source Unit-Volume attribute | ✅ PASS *(skeptic overturned PARTIAL)* | wired & functional (SC-3390 tiered-pricing) |
| AC15 decision tables refreshed | ✅ PASS *(skeptic overturned PARTIAL)* | all tables V16 consumes Completed/refreshed 2026-06-25 |

### Prior findings reconciled to today
| # | Verdict | Note |
|---|---|---|
| B-3 partner map-miss 15→12 | ✅ PASS | fixed (class 2026-06-21) |
| B-4 renewal null-guard + carry-forward | ✅ PASS | every prior component null-guarded; carried QLI→OI |
| B-5 AssetActionSource table Failed | ⛔ OUT-OF-SCOPE *(skeptic)* | real (>200-row Hash Key Group) but **not referenced by V16 maintenance path**; track separately |
| B-6 maintenance-base decomposition | ✅ PASS *(skeptic overturned PARTIAL)* | all 6,162 live New-Maint OIs stamp maintenance base, 0 with Base==Source_List_Price |
| M-1 SDD "no prehook" reconciliation | 🔴 FAIL (minor) | 4 Apex automations touch maintenance pricing — SDD must be reconciled |
| M-2 competing formulas / dead code | ✅ PASS *(skeptic overturned PARTIAL)* | gone from V16 |
| M-3 prod lacks `_v2` context | 🔴 FAIL (prod blocker) | PROD has only `SalesTransactionContextExt`; `_v2` absent |
| M-4 Source_List_Price__c Q2O mapping | ✅ PASS | live mapper maps it; 8/8 sampled OIs match |
| M-5 PBEDP gap (SC-3372) | 🟡 PARTIAL (major) | 197/1889 active derived maint PBEs covered (~89.6 % still uncovered); BoKS fine, broad rollout gated on Marc crosswalk |
| M-6 prod prehook stale | ⛔ OUT-OF-SCOPE | prod-only (PROD 39,956 vs UAT 47,235 chars) |
| M-7 class coverage ≥75 % | 🔴 FAIL (blocker) *(skeptic overturned PARTIAL)* | PartnerNetPricePosthook 59.5 %, QuoteToOrderFieldMapper 65.2 % |
| SC-3404 RN-COLA-COMMIT | 🟡 PARTIAL (major) | structurally fixed, **unproven E2E** — instrumented lines predate V16; 5/6 still 60.64/0 |
| NB-DERIVED-TIER | ✅ PASS | all 7 tiers in V16 |
| FLIP-WIRING | 🔴 FAIL (major hygiene) | Flip dropped from active flow V8; dead-wired class left in org |

### Production deploy gates (all confirmed live)
| Gate | Verdict |
|---|---|
| Maintenance test suite green | ✅ PASS (302/302) |
| Org-wide ≥75 % | ⛔ OUT-OF-SCOPE *(skeptic)* — 42 % real but dominated by ~147 non-SC-3346 classes at 0 %; deploy via RunSpecifiedTests |
| Per-class ≥75 % | 🔴 FAIL (M-7) |
| PROD class layer | 🔴 FAIL — 3 of 11 (all stale 2026-06-11), 8 absent |
| PROD trigger dispatch | 🔴 FAIL — 0 unmanaged custom triggers in PROD |
| PROD `Maintenance_Rate__mdt` | 🔴 FAIL — 0 rows (order-side decomposition would price $0) |
| PROD `SalesTransactionContextExt_v2` | 🔴 FAIL — absent (posthook hard-codes it → order-side no-op) |
| PROD QLI/OI field parity | 🔴 FAIL — 23 QLI + 32 OI UAT-only fields |
| Procedure version parity (V1 vs V16) | 🔴 FAIL — PROD V1, ExpressionSetVersion not source-deployable |
| force-app classes present | 🔴 FAIL — none of the 10 build classes in force-app |
| force-app Q2O mapper current | 🔴 FAIL — committed copy scans 0 SC-3346 tokens (would regress M-4) |
| force-app proc XML = V16 | 🔴 FAIL — committed XML carries only V1–V3, binds old context |
| `rca_diagnostic.cls-meta.xml` orphan | 🔴 FAIL — blocks `sf project convert source` |

---

## Blockers (production)
1. **B-2 packaging** — from-zero, non-deployable bundle (classes/triggers/`_v2`/V16 proc/7 rate rows/55 fields all missing in PROD; force-app holds none of it + a deploy-blocking orphan).
2. **M-7 coverage** — `PartnerNetPricePosthook` 59.5 % and `QuoteToOrderFieldMapper` 65.2 % below 75 %; the 521 uncovered posthook lines are the newly-absorbed regional/multi-currency/SC-3441 paths on the class that writes the production net.
3. **SC-3404 verification gap** — fix is structurally real but every instrumented BoKS renewal-maintenance line predates V16; need one live V16 renewal reprice committing 67.38 to TotalPrice.

## Open items
- **AC13 platinum straggler** — `GS-GSE-RRM-EFSMB` defaults to off-list `platinum` → silent $0; decide fallback + re-tag/retire the 3 platinum APVs.
- **FLIP de-wiring** — confirm `RenewalMaintenanceFlip` is intentionally retired for `RenewalMaintenancePricingService`; remove the dead class + its usage header.
- **Year-2 PCR `14OWC0000022Eyb2AE`** is Active — confirm the design intentionally pivoted to the AutoAdd-PCR model (the old Flip-deactivates-PCR checklist step is void).
- **Single-source-of-truth** — the 3-component renewal COLA math is triplicated (COLAUpliftPrehook / PartnerNetPricePosthook / RenewalMaintenancePricingService) and has begun to diverge; consolidate or document the canonical writer.
- **Interactive vs migration reprice** — the Apex renewal-COLA backstop is wired only into `Fortra_Quote_Reprice` (Quote Migration Tool); confirm the interactive reprice commits 67.38 via the proc LC2 path alone.
- **M-5 PBEDP backfill** (~1,692 rows) — staged but not applied; broad non-BoKS rollout gated on Marc crosswalk + DML auth.
- **B-5** — `Asset_Action_Source_Entries_Decision_Table_V2` refresh Failed; out of SC-3346 scope but a real native-RLM/SC-3415 defect to track.
- **SC-3346 deploy-manifest scoping** — not all 23/32 UAT-only fields are SC-3346 (several Workday/regional/MEA); needs a minimal-cutover scoping pass.

---

*Evidence: V16 procedure slice + execution tree at `Data/sc3403/retrieve/V16.xml`; capture/verdicts in the workflow result. Read-only review — no org changes made.*
