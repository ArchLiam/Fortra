# 09 — Remaining-work execution plan (M-2, SC-3404, B-5, M-3+M-6)

Scoped 2026-06-12/13 (read-only, live FortraUAT). All four open items are execution-ready below. Two findings change the picture materially.

## Finding 1 — SC-3404 (NEW ticket): the native element overrides B-4's price → $0
**This is why B-4's correct 67.38 won't display.** In active V14, the renewal chain (ListContainer seq7) runs: `DerivedPricingRenewals` (B-4 ISNULL formula, `resultIncluded=false`, computes 67.38 in-flight) → then `DerivedProductsNativePull › DerivedProductsRenewals` (the **native** `actionType=DerivedPricing`, `resultIncluded=TRUE`, runs **last** = authoritative committer). The native element overwrites the formula's 67.38 and, because the contributing license `PIA-PIA-NRPS-PIAP` is not a *line* on the cart, sets `ValidationResult=MissingContributor` → committed `NetUnitPrice=0`.
- **Fix (Option C):** clone V14→V15, set native `DerivedProductsRenewals` `resultIncluded` **true→false** so the formula's value commits.
- **⚠️ Load-bearing risk:** per SC-3372 RCA_v2, **167/170 config-covered FIM/RPA/PIA products price ONLY via the native path** (no MTD attribute → the formula yields $0). Option C could **silently zero** those. **Mandatory gate:** a renewal of an MTD-less config product (`FIM-FIM-RNM-CCMLSE`) must STILL price **462**, not $0, after the change.
- **Decision needed:** business confirmation that renewal maintenance should price **standalone** from stamped fields (the SDD intent) and that **67.38 is correct**; owner (Nir/Marc) sign-off (it's their procedure).

## Finding 2 — M-2 is dead-code removal, and the dossier was WRONG
`MTD` vs `MDT` is a **typo**: exactly one `AttributeDefinition` exists — Code=`MTD` (`Maintenance_Type_Defn`, `0tjWC000000096bYAA`); **no `MDT` record**. So `DerivedPricingNewBusiness` (the `Base_Price__c × tier`, MDT-gated formula) is **permanently unreachable dead code** (Renewal-only branches, no-op on renewal, zero downstream refs). The formula that actually prices new business is `DerivedPricingFormula` (`tier × Source_List_Price__c`, MTD gate) — **live-proven**: new-biz BoKS QLIs price Net=71 = 0.20×355, and the SDD already documents exactly this.
- **CORRECTION:** [02_BLOCKERS_AND_DEFECTS.md](02_BLOCKERS_AND_DEFECTS.md) and [07_B4_FIX_PLAN.md](07_B4_FIX_PLAN.md) say to *keep `Base_Price__c`* and "update the SDD to Base_Price__c" — **that is wrong**. The system uses `Source_List_Price__c`, and the SDD is already correct. M-2's fix = **delete the dead step** (+ optionally clean the orphan `MDT` filter branch). No new-business semantics change. Near-zero risk.

## Recommended execution order
**M-2 and SC-3404 edit the SAME procedure (V14) and need the SAME ritual** (clone→deploy inactive→per-row Activate→context resync). Do them as **ONE bundled V15** — halves the risky activate/resync cycle. M-2 is inert dead code (not worth its own cutover); it rides with SC-3404 (the functional fix that closes SC-3346 renewal).

| Phase | What | Gate |
|---|---|---|
| **0 — now (zero live change)** | Collect 4 owner decisions; stage the bundled M-2+SC-3404 V15 delta; write SC-3404 ticket; build M-3+M-6 prod manifest | none |
| **1 — UAT cutover (one ack)** | Deploy bundled V15 inactive → per-row Activate → resync → **FIM-462 regression gate** + no-gack + B-4 renewal=67.38 + M-2 new-biz=71 + SC-3393/3372/3359/3384 no-ops | fresh UAT activate ack **+** owner decision **+** FIM-462 passes |
| **2 — B-5 (separate window)** | Split OUT of SC-3346. Add Asset.Id Equals col (UI). Deactivate 3 discovery procs (org-wide discovery offline) → edit → refresh → reactivate | maintenance window + ack + B1 native-renewal repro confirming it's on the failing path |
| **3 — prod cutover (M-3+M-6)** | Full V14 bundle (no carve-out — V14 fuses SC-3346+3393+3372+3359+3384). Context BEFORE PartnerNetPricePosthook. 3-way merge COLAUpliftPrehook | explicit prod-auth + ALL UAT blockers green + ≥75% coverage |

## Risk ranking (blunt)
1. **M-3+M-6 prod cutover** — highest (org-wide, ordering trap, no carve-out).
2. **B-5** — high during window (org-wide discovery offline), low after.
3. **SC-3404 Option C** — high if mis-scoped (could zero 167/170 native-priced products → FIM-462 gate is mandatory).
4. **M-2** — near-zero (inert dead-code removal).

## Decisions that unblock everything (free — collect now)
1. **M-2:** confirm canonical new-biz = `tier × Source_List_Price__c` (already runs + SDD says so) → just a nod.
2. **SC-3404:** renewal prices standalone from stamped fields? Is 67.38 correct? → Nir/Marc/Finance.
3. **B-5:** split out of SC-3346 as a separate platform item? → + a B1 native-renewal repro.
4. **M-3+M-6:** ship full V14 bundle to prod (no carve-out possible)? → Marc/German.
