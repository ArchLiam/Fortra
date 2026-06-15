# Lever-d (H5) Procedure-Commit Test — Runbook

**Goal:** settle the one CONTINGENT question from the deep RCA — *does an ungated, `resultIncluded=true`
procedure element that writes `NetUnitPrice = COLACalculatedPrice__c` overwrite a **settled** derived
renewal-maintenance node (which the posthook write cannot), without rollup staleness or regression?*
If yes → lever-d is the single change that self-heals existing **and** new fossils → ship it. If no →
fall back to H3 born-net for new lines + data-remediate the existing.

**Owner-gated.** This deploys + activates a new version of the **co-owned** `Rev_Mgmt_Default_Pricing_Procedure`
(~100k-line blast radius) and reprices Draft test quotes. Run only inside an authorized offline republish
window, coordinated with Nir/Marc. Read-only steps (preflight) are safe anytime.

---

## The element under test (validated, self-contained)
Group `RenMaintCOLACommit` (ListGroup, **seq 41 = last**, after the partner committers at seq 8/11):
| Sub-element | Type | resultIncluded | Effect |
|---|---|---|---|
| `RenMaintCOLAFilter` | AdvancedListFilter | false | Gate: `(FPT='New Maintenance' OR FPT='Renewal Maintenance') AND QuoteTypeText__c='Renewal' AND COLACalculatedPrice__c > 0`. The New-Maint arm is inert (prehook only stamps COLACalc on Renewal-Maint), so effectively **Renewal-Maint on a Renewal quote with a computed COLA**. |
| `RenMaintCOLAInput` | BusinessKnowledgeModel | **true** | `InputUnitPrice ← COLACalculatedPrice__c` |
| `RenMaintCOLANet` | BusinessKnowledgeModel | **true** | `NetUnitPrice ← COLACalculatedPrice__c` ← the committer |

All `parentStep`s point to `RenMaintCOLACommit`; no external refs → safe to inject anywhere in the steps list.

---

## Test matrix (locked baseline, 2026-06-14, org FortraUAT `00DWC000006eUFF2A2`)
| Line | Quote | Status | Before | COLAcalc | Expect after | Role |
|---|---|---|---|---|---|---|
| `0QLWC000003e2Sn4AI` | `0Q0WC0000038aXd0AI` 00781109 | Draft | 60.64 | 67.38 | **67.38** | TARGET (canary) |
| `0QLWC000003ck6X4AQ` | `0Q0WC0000037XvB0AU` | Draft | **0** | 67.38 | **67.38** | TARGET — $0 overwrite crux |
| `0QLWC000003cN584AE` | `0Q0WC0000037AKH0A2` | Draft | **0** | 67.38 | **67.38** | TARGET — $0 overwrite crux |
| `0QLWC000003eMph4AE` | `0Q0WC0000039AMb0AM` | Draft | 54.58 | 60.64 | **60.64** | TARGET |
| `0QLWC000003cy334AA` | `0Q0WC0000037muD0AQ` | Draft | 54.58 | 60.64 | **60.64** | TARGET |
| `0QLWC000003dEW24AM` | `0Q0WC00000382MH0AY` 00382MH | Draft | 67.38 | 67.38 | **67.38** | CONTROL (must not move) |
| `0QLWC000003d2Q14AI` | `0Q0WC0000037rFZ0AY` | Draft | 71 | — | **71** | REGRESSION (NB-derive) |
| `0QLWC000003NO7x4AG` | `0Q0WC000002sjLZ0AY` | Draft | 355 | — | **355** | REGRESSION (perpetual) |
| `0QLWC000003dAaT4AU` | `0Q0WC0000037yTx0AI` | **Accepted** | 60.64 | 67.38 | unchanged | ⛔ **DO NOT REPRICE** |

> Add a FIM renewal-maintenance line (target 462) to the regression set if one is available as Draft at
> test time — none matched `FIM-FIM-RRM-CCMLSE` / Draft / Net>0 in the baseline query; find the live FIM
> renewal SKU and confirm it stays unchanged.

---

## Pass criteria (all three must hold)
1. **CRUX 1 — overwrite-settled-node:** every TARGET flips to its COLAcalc, **including the two $0 lines → 67.38**.
   This is the crux the posthook could not clear.
2. **CRUX 2 — rollup not stale:** each TARGET's `NetTotalPrice` (and the Quote `GrandTotal`) reflects the new
   net, not the old 60.64/0. The element writes `NetUnitPrice`+`InputUnitPrice` only — confirm the totals
   recompute downstream.
3. **REGRESSION:** CONTROL stays 67.38; NB-derive stays 71; perpetual stays 355; (FIM stays 462). No other
   line moves.

Also confirm via FINEST that the `NetUnitPrice` write **lands in the post-settle context dump** (not merely
emitted) — that is the H2 failure mode the posthook hit.

---

## Sequence
| Step | File | Mutating? | Notes |
|---|---|---|---|
| 0 Preflight | `00_preflight.sh` | no (read-only) | Confirms active V14 clean (gate-check ABSENT) + fresh retrieve + before-baseline. Safe anytime. |
| 1 Build+Deploy | `01_build_and_deploy.sh` | **yes** | Rebuilds from the **fresh retrieve** (NOT stale deploy_v4) via `build_deploy.py`; deactivate→deploy(api67,NoTestRun). Cosmetic "Finalizing" error expected — verify by Deploy ID. |
| 2 Activate | `02_activate_and_04_rollback.md` §2 | **yes** | UI-only. **Record the current active version Id for rollback.** |
| 3 Verify | `03_verify.sh` | yes (Draft test quotes only) | Reprices targets+regression, asserts the 3 cruxes. Never touches the Accepted line. |
| 4 Rollback | `02_activate_and_04_rollback.md` §4 | **yes** | Re-activate prior V14 unless shipping. ESV delete is platform-blocked. |

## Hard guardrails
- **Drift-safe:** never deploy the stale 3.4MB `deploy_v4` snapshot blindly — `build_deploy.py` rebuilds from a
  fresh live retrieve so concurrent Marc/Nir edits aren't reverted. It aborts if the retrieve already contains
  `RenMaintCOLA`.
- **Never delete** anything (ESV hard-delete is blocked anyway). **Never** touch Accepted quote `00781068` /
  line `0QLWC000003dAaT4AU`, or any Ordered/In-Review quote.
- **No Order activation / no Workday-MuleSoft events** during the test.
- Test-drift (`COLAUpliftTest.buildOverrideMap`) does **not** block this `NoTestRun` UAT deploy, but **must**
  be fixed before any prod promotion.
- Re-confirm **V14 sole-Active + gate-check ABSENT** immediately before deploy — the procedure churns.
