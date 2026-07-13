# Wave 4 — Remaining-Work Checklist (owner + UI-canvas actions)

**Date:** 2026-07-10 · **Mode:** read-only verification (no deploys) · **Active proc:** `Rev_Mgmt_Default_Pricing_Procedure`, SOQL VersionNumber **24 & 23 both Active**.

Wave 4's engineering is essentially done. What remains is **owner decisions**, **UI-canvas-only work**, and a little **deploy-gated hygiene**. This is the action list. Verification evidence is from a live read-only ESD retrieve + class snapshot under `Data/pricing-refactor-scratch/live/`.

---

## 0. Verified this pass (read-only — no action needed)
- **D-19** — StampBaseFilter is null-safe on the **active V24**: `<criteria><operator>IsNull</operator><sourceFieldName>NetUnitPrice</sourceFieldName>` (seq 6) → the `NetUnitPrice > 0 OR IsNull` pattern (K-01/F-12). **CLOSED on active.**
- **INV-28** — `RegionalNetReconcileGate` = **0 occurrences** in both active version blocks → structurally removed from active. **CLOSED.**
- **D-3** — `RenewalMaintenanceFlip` is fully unreferenced (0 metadata deps, 0 flows, 0 repo refs). A **deprecation banner was added to the class ApexDoc** (repo only, not deployed). Deletion is safe whenever the owner rules (see §2).

---

## 1. ⚠️ PRIORITY — resolve the two Active procedure versions (owner, Setup UI)
The definition has **two Active versions — V24 and V23 — and they are structurally different** (~8 KB apart, distinct md5), not a clean backup copy. The team's pattern is **one Active + one *Inactive* backup**. V24 was activated 2026-07-10 02:59 but V23 was never deactivated.

- **Action (owner, Pricing Procedure canvas → Versions list):** confirm **V24** is the intended runtime version, then **deactivate V23** (keep it Inactive as the backup). Follow the reactivation hygiene from the plan (close all canvas tabs, fresh tab, activate/deactivate from the Versions list, re-retrieve to confirm).
- **Why it matters:** with two different active versions, which one the engine prices with is ambiguous; this outranks the remaining debt items.
- **Gate:** after deactivation, run the golden harness (you reprice a Quote + an Order; I diff) to confirm 0-delta vs. current behavior.

---

## 2. Owner / business decisions (cannot be made in code)
| # | Decision | Recommendation | Owner |
|---|---|---|---|
| **D-3 / OQ-3** | Is the renewal-maintenance "flip" strategy permanently abandoned? | Class is now commented deprecated + unreferenced → **delete `RenewalMaintenanceFlip` + its test** once confirmed | Marc / pricing owner |
| **OQ-2 / D-10b** | Should Quote currency-change actually **convert prices** + activate the currently-Draft flow? (today the wired `QuoteCurrencyChangeService` is a no-op) | Business call — either activate+convert, or delete the dormant path | Marc / owner |
| **D-21 / OQ-6** | Move `Currency_Conversion_Formula__mdt` off config-as-code (executable string parsed at runtime)? | Boundary item — low urgency; decide at leisure | owner |
| **A-5** | Non-Power product carrying hardware linkage | Deferred; revisit only if such a product appears | owner |

---

## 3. UI-canvas-only work (I cannot do via CLI — MDAPI ≠ runtime)
- **D-23** — cosmetic step renames in the V24 canvas (16 dup-label groups, Copy-of-Copy triad). **Reduced to rename-only** per Round-5 (0 deletions); do by label+function, never by `<name>`. Low urgency, do when convenient.
- **Two-active-versions deactivation** — see §1.

---

## 4. Deploy-gated code hygiene (needs a UAT deploy + golden gate when you're ready)
- **D-8** — extract a shared MDT selector: `COLA_Uplift_Rules__mdt` is loaded by both `COLAUpliftPrehook` and `COLAUpliftHandler`; `Maintenance_Rate__mdt` by both `MaintenanceOrderDecompositionService` and `PartnerNetPricePosthook`. Behavior-preserving Wave-2-style extract. *Low value; optional.*
- **D-7** — label/git-ignore the non-authoritative repo ESD serializations (`.bak_preedit`). Repo-only housekeeping.
- **D-3 deletion** — execute once §2 ruling is "delete" (destructive deploy, golden-gate).

---

## Standing constraints for any of the above (from the plan)
- Retrieve-live-first; every ESD edit is **in-place on the active version, canvas-only** (never MDAPI); classify formula-literal (no context resync) vs field-signature (resync + dual Quote/Order mapping).
- The golden gate requires **a human to perform the reprices** (the only writes); snapshot + diff are read-only (`Data/pricing-refactor-scratch/harness/RUNBOOK.md`).
- Any UAT deploy needs explicit authorization at the time.
