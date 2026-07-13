# Pricing Refactor — Multi-Tab Coordination Board

Three Claude Code sessions (separate tabs, **same repo working tree** at
`/Users/liamjeong/Documents/Code/Fortra`) are refactoring the Fortra pricing layer in
parallel. Separate sessions can't see each other's chat — but they all see these files
on disk. This is the shared status board.

**Source of truth for the rules is THIS file (owned by Tab 1). Read it before you deploy.**

---

## The 3 workstreams
| Tab | Task | Primary files it edits |
|-----|------|------------------------|
| **Tab 1** | Wave 2 — posthook decomposition (build*Update / inner-DTO tier) | `PartnerNetPricePosthook.cls` + shared `*Calculator` classes + new calculators |
| **Tab 2** | Wave 1 — delete dead code (D-1/D-2/D-3) | deletes `PartnerPricingPrehook`, `SourceListPrice*`, `RenewalMaintenanceFlip` (+ their tests) |
| **Tab 3** | Wave 2 — thin `CancelLineCreditPosthook` | `CancelLineCreditPosthook.cls` + new `CancelLineCreditCalculator` |

---

## Rule 1 — File ownership (never edit another tab's files)
- **Tab 1 owns** (edit): `PartnerNetPricePosthook.cls` and ALL shared calculators —
  `ContextTagReader`, `ContextUpdateNavigator`, `PartnerNetResolutionCalculator`,
  `ListPriceStampCalculator`, `PartnerPricingGate`, `NewMaintenanceNetCalculator`,
  `RenewalMaintenanceColaCalculator`, `DerivedMaintenanceClassifier`,
  `NewMaintenanceBandCalculator`, `NewMaintenanceInputResolver`, `ContributorPricingCalculator`
  — plus new ones it creates (`SequentialDiscountCalculator`, `DerivedMaintenancePayloadBuilder`,
  `NewBusinessMaintenanceNets`). Tabs 2/3 may **read** these, never edit.
- **Tab 2 owns**: only the classes it deletes. Edits nothing shared.
- **Tab 3 owns**: `CancelLineCreditPosthook.cls` + its new `CancelLineCreditCalculator`(+Test).
  May **read** (not edit) `ContextTagReader` etc.
- **Nobody** touches: the pricing procedure / ExpressionSet **V21**; the uncommitted-modified
  files (`PartnerPricingService`, `PartnerPricingServiceV2`, `HardwareAttributePricingPrehook`,
  `RegionalServicesPricingPrehook`); the untracked WIP (`RegionalPricingCalculator`,
  `HardwarePricingCalculator`).

## Rule 2 — Reprice scenario reservations (never reprice a quote another tab owns)
Two tabs repricing the **same quote at the same time** corrupts both gates. Primary reservations:

| Tab | Reserved scenarios | Quote ids |
|-----|-------------------|-----------|
| **Tab 1** | S1 S3 S4 S5 S6 S7 S9 S11 | S1=0Q0WC000003IIT0 · S3=0Q0WC000003IKkv · S4=0Q0WC0000028bsk · S5=0Q0WC000003IKeT · S6=0Q0WC0000035dGj · S7=0Q0WC0000039bwH · S9=0Q0WC000003Fr77 · S11=0Q0WC000003GMu5 |
| **Tab 2** | S12 S14 | S12=0Q0WC000002RK6g · S14=0Q0WC0000028HhT |
| **Tab 3** | S10 S13 | S10=0Q0WC000003ICoz · S13=0Q0WC000003FapR |

The final full-matrix regression (ALL scenarios) is run by **Tab 1 only**, after the others
mark themselves quiescent in their status file. (Full map: `Data/pricing-refactor-scratch/harness/scenarios.tsv`.)

## Rule 3 — Deploy protocol (shared org FortraUAT)
1. Before `sf project deploy start`, read the other two `STATUS_TAB*.md`. If either shows
   `MID-DEPLOY: yes`, wait ~30s and re-check.
2. Set your own status `MID-DEPLOY: yes` while deploying; `MID-DEPLOY: no` when done.
3. All deploys use `--test-level NoTestRun`; verify with a targeted `sf apex run test`.
4. Gate 0-delta only on YOUR reserved scenarios (Rule 2).

## Rule 4 — How to share status
- Write **ONLY** your own `STATUS_TAB{N}.md` (Tab 1 → `STATUS_TAB1.md`, etc.).
  Never edit another tab's status file, and never edit this `COORDINATION.md`.
- Update your file after each increment (commit) and whenever you start/stop a deploy.
- To see everyone's live status, read all three `STATUS_TAB*.md`.

## Rule 5 — Memory + commits
- The shared memory dir (`~/.claude/.../memory`) is owned by **Tab 1**. Tabs 2/3 don't write it.
- All work commits to branch `uat`. Keep each commit to your OWN files so commits never conflict.
- Do **not** commit this `Data/pricing-refactor-coord/` directory — it's ephemeral coordination scratch.

---

## ROUND 2 (2026-07-07) — hook-thinning fan-out
Round 1 ✅: Tab 1 posthook build\*Update tier (2054 ln, full-matrix 0-delta) · Tab 2 D-1/D-2 deleted
· Tab 3 CancelLineCreditCalculator. New assignments — all **behavior-preserving Wave-2 hook-thinning**,
same proven pattern (extract pure math → a new `*Calculator` you own, leave context I/O + SOQL in the
hook as thin seams, 0-delta gate on your reserved scenarios):

| Tab | New hook | Reserved scenarios |
|-----|----------|-------------------|
| **Tab 1** | `PartnerPricingPrehookV2` (1089 ln, LIVE V2 partner prehook) | S1 S4 S5 S6 S7 S9 |
| **Tab 2** | `COLAUpliftPrehook` (1463 ln) | S3 |
| **Tab 3** | `AttributeVolumePricingPrehook` (894 ln) | S2 S11 |

Quote ids: S1=0Q0WC000003IIT0 · S2=0Q0WC000003GMu5 · S3=0Q0WC000003IKkv · S4=0Q0WC0000028bsk ·
S5=0Q0WC000003IKeT · S6=0Q0WC0000035dGj · S7=0Q0WC0000039bwH · S9=0Q0WC000003Fr77 ·
S11=0Q0WC000003GMu5. Spare (Tab-1 final full-matrix only): S10 S12 S13 S14.

**AVOID** `RegionalServicesPricingPrehook` + `HardwareAttributePricingPrehook` — uncommitted mods +
untracked `RegionalPricingCalculator`/`HardwarePricingCalculator` WIP (another workstream).
Same Rule-3 deploy protocol applies. Files are disjoint; each tab creates its own new `*Calculator`
(don't edit another tab's calculators or the shared ones from round 1).

---

## ROUND 3 (2026-07-08) — DESIGN-COMPLIANCE (fix-to-SDD). ⚠️ PHASE SHIFT: THE GATE FLIPS.
Rounds 1–2 were **behavior-PRESERVING** (0-delta gate). Round 3 is the opposite: we **deliberately
change code to match the RCA Solution-Design docs** (`docs/RCA Solution Guide/kb/*.md`). A fix is
SUPPOSED to move its scenario off baseline. So the discipline changes — see **Rule 6**.

The full design-compliance backlog + triage lives in memory `project_pricing_refactor_plan.md`
(SDD REFLECTION 2026-07-08). Only the **clear bucket-A** items are in-scope for tabs; ambiguous /
SDD-self-inconsistent items are ESCALATED to Marc (Tab 1 owns that doc), not blind-fixed.

| Tab | Workstream (bucket-A, SDD-backed) | Files it OWNS (edit) | Gate scenarios | KB doc |
|-----|-----------------------------------|----------------------|----------------|--------|
| **Tab 1** | **Maintenance (derived) SDD-compliance** + coordination + Marc-escalation doc + final full-matrix | `NewMaintenanceInputResolver`, `NewMaintenanceNetCalculator`, `DerivedMaintenanceClassifier`, `NewMaintenanceBandCalculator`, `ContributorPricingCalculator`, `PartnerNetPricePosthook` (maint path) | **S4** (0Q0WC0000028bsk) | `Fortra-Maintenance-Derived-Pricing-Solution-Design.md` |
| **Tab 2** | **Hardware/Power SDD-compliance** (source-label→'Configurator', open-ended top user-band, product-gate) | `HardwareAttributePricingPrehook`, `HardwarePricingCalculator`(+Test) | **S12** (0Q0WC000002RK6g) | `Fortra-Products-Hardware-Solution-Design-Doc.md` |
| **Tab 3** | **Regional** (null-multiplier guard + effective-dating) **and** **AttrVolume** (D-17 no-match / null-volume) | `RegionalServicesPricingPrehook`, `RegionalPricingCalculator`(+Test), `AttributeVolumePricingPrehook`, `AttributeVolumeCalculator`(+Test) | Regional **S9** (0Q0WC000003Fr77) + **S10** (0Q0WC000003ICoz); AttrVolume **S11** (0Q0WC000003GMu5) | `Fortra-Pricing-RegionalPricing-*.md`, `Fortra-Pricing-AttributeVolumePricing-*.md` |

COLA (Tab-1 domain): investigated 2026-07-08 → **already SDD-compliant, NO Apex change.** Applied_Date is
written once at first-application (insert); rounding SDD says "preserve current"; the audit-field
reprice-persistence residual is a **context/ESD** item (inputoutput on `SalesTransactionContextExt`) → escalation tail.

Files are disjoint across tabs. **Nobody touches:** V21/ESD; `PartnerPricingService*`, `PricingCharacterizationTest`
(co-owned Nir, uncommitted); Partner-warning writers + COLA context config + net-new MDTs (escalation/OQ tail).

## Rule 6 — Behavioral-change gate (Round-3 ONLY — replaces the 0-delta gate for the CHANGED scenario)
A fix is a DELIBERATE behavior change, so its scenario **will** diverge from baseline. To ship one:
1. **Confirm the SDD is unambiguous** for this item (cite the KB rule #). If the SDD is self-inconsistent
   or silent → **STOP, write it to your STATUS file as an escalation, do NOT fix.**
2. Deploy, reprice your gate scenario, snapshot, diff vs baseline. **Read every diff line:** the ONLY
   changes may be the intended field(s) moving to the SDD-correct value. Any collateral change = bug, revert.
3. **Re-baseline** that scenario: overwrite `baselines/S#_quote.tsv` and drop a `baselines/S#_REBASE_NOTE.md`
   (what changed, which KB rule, before→after). This is the ONLY time you overwrite a baseline.
4. Prove **no collateral regression:** every OTHER scenario you can reach must still diff **0-delta** vs its
   (unchanged) baseline. If another tab owns a scenario, don't reprice it — Tab 1's final full-matrix covers it.
5. Add a unit test asserting the new SDD-correct behavior (name it for the KB rule).

Rules 1 (own only your files), 3 (deploy protocol / MID-DEPLOY flag), 4 (write only your STATUS), 5
(commit only your files, never `git add -A`; Tab 1 owns memory) all still apply.

---

## ROUND 4 (2026-07-08) — WAVE-3/4 TAIL. ↩️ GATE RETURNS TO 0-DELTA (behavior-preserving).
Round 3 (design-compliance) is CLOSED — all 7 escalations ruled/fixed/deferred. Round 4 is the remaining
Wave-3/4 backlog. NOTE (verified 2026-07-08): **D-9 (recursion guards) and D-16 (order bulkification) are
already DONE** — do not redo them. The config-to-MDT extractions are **behavior-preserving**: seed the new
MDT with the EXACT current hardcoded values → identical reprice output → **0-delta gate (Wave-2 discipline,
NOT Round-3's re-baseline)**.

| Tab | Items | Files it OWNS (edit) | Gate |
|-----|-------|----------------------|------|
| **Tab 1** | D-19 (ESD `StampBaseFilter` null-safety, canvas) + D-11 assessment (partner posthook V1→V2 — parallel-run V1 vs V2 `getMarginForProductType`, blocked on Nir's A-2) + coordination + final full-matrix | ESD canvas; `PartnerNetPricePosthook` (assess only) | ESD careful; parallel-run, no flip until Nir resolves A-2 |
| **Tab 2** | **D-14** — extract `HardwarePricingCalculator`'s inline pGroup / user-tier / system-type tables into a new admin-editable Custom Metadata Type, **seeded with the current values** | `HardwarePricingCalculator`(+Test), new `*__mdt` + records | **0-delta S12** |
| **Tab 3** | **D-15** — extract `CurrencySelectionService`'s hardcoded 14-country map into a new MDT (seeded w/ current values); **D-10** — remove the `QuoteCurrencyChangeService_Fixed` orphan (delete + flip the wired no-op if safe); **A-6** — Regional Active+null-`Multiplier__c` skip guard | `CurrencySelectionService`(+Test), `QuoteCurrencyChangeService*`, `RegionalServicesPricingPrehook`/`RegionalPricingCalculator`(+Test), new `*__mdt` | **0-delta** (Regional S9/S10; currency scenarios) |

**Do NOT touch:** the SDD/KB (client-approved, frozen); V21 pricing procedure except Tab-1's D-19 canvas edit;
`PartnerPricingService*` + `PricingCharacterizationTest` (Nir co-owned, uncommitted); the already-done D-9/D-16.
Gate is the SAME 0-delta harness as Waves 1–2 (`Data/pricing-refactor-scratch/harness/`). Rules 1/3/4/5 apply.

---

## ROUND 5 (2026-07-08) — THE TAIL. Gate = 0-delta (behavior-preserving) / tests / docs.
Waves 0–4 are essentially SHIPPED. Verified-DONE this round: D-1..D-8, D-9, D-10, D-13, D-14, D-15, D-16,
D-17, D-19, A-1..A-6, B-1. D-20 = captured as doc (waterfall). D-24 = won't-fix (delete blocked).
INV-28/OQ-11 (`RegionalNetReconcileGate` un-null-guarded `>0`) = **already closed by SC-3393 V13** (confirm).
**Only substantive open item is D-18.** Blocked/parked (NOT fanned out): D-11/D-12 (Nir's A-2 uncommitted
`PartnerPricingServiceV2` + `Non_Orig_*` data), D-21 + multi-currency FX removal (owner-gated, parked).

| Tab | Items | Files it OWNS (edit) | Gate |
|-----|-------|----------------------|------|
| **Tab 1** | **D-18** — swallow-to-SUCCESS observability. New `PricingHookTelemetry` helper + `Pricing_Degrade__e` platform event; wire `emit(...)` into every hook's `catch` block. **KEEP swallow→SUCCESS (SDD-mandated: never block pricing)** — this is additive telemetry only. Plus D-11 parallel-run assessment (blocked on Nir) + coordination + final full-matrix. | all 8 hook `.cls` (`*Prehook`/`*Posthook`), new `PricingHookTelemetry`(+Test), new `Pricing_Degrade__e` PE | **0-delta** (telemetry adds no pricing math) |
| **Tab 2** | **Test-coverage hardening** — raise the THIN calculator tests to real behavioral coverage (golden-value asserts): `PartnerMarginDispatcher` (7 asserts), `PartnerParticipationResolver` (8), `NewMaintenanceNetCalculator` (19/72ln), `NewMaintenanceBandCalculator` (11/99ln), `ContributorPricingCalculator` (18). **Behavior is frozen — tests only, do NOT edit the calculator `.cls`.** | ONLY the listed `*CalculatorTest.cls` / `*ResolverTest.cls` / `*DispatcherTest.cls` | tests pass; NO calculator `.cls` edits |
| **Tab 3** | **ESD close-out + parked-item briefs** (read-only + guide docs — NO canvas; user executes any canvas). (a) confirm INV-28/OQ-11 closed on active V21; (b) D-23 intra-version clone inventory (~4 dup-`Copy` groups in active block) → exact canvas consolidation guide; (c) one owner-decision brief consolidating parked multi-currency FX removal + D-21. | NEW docs under `Data/pricing-refactor-scratch/round5/` only | none (analysis/docs) |

**Do NOT touch:** SDD/KB (frozen); V21 canvas (Tab 3 produces guides, does not edit); `PartnerPricingService*` +
`PricingCharacterizationTest` (Nir co-owned, uncommitted); each other's files. Rules 1/3/4/5 apply.
**Honest note:** this is polish/close-out — D-18 (Tab 1) is the only heavy item; Tabs 2/3 are optional value.
