# Owner-Decision Packet — Pricing Refactor open items

**Round 6 · Tab 3 · READ-ONLY assembly · 2026-07-08 · for owner: Liam**
One packet to clear the remaining non-code decisions in one sitting. Each section: **Question / Options /
Recommendation / Risk / Next-action.** Detailed briefs are referenced, not re-derived — see
`Data/pricing-refactor-scratch/round5/` (`parked_multicurrency_D21_owner_brief.md`, `D23_clone_consolidation_guide.md`,
`INV28_regional_gate_confirmation.md`) and memory `reference_rlm_multicurrency_best_practice`.

## TL;DR — all five at a glance
| # | Decision | Recommendation |
|---|----------|----------------|
| 1 | OQ-2 / D-10b — Quote currency-change handler | **Force-reprice through the engine** (never FX-multiply / rebuild lines). **Defer build** until the Part-A FX-removal lands. |
| 2 | OQ-4 / OQ-5 — sign off D-14 + D-15 admin MDTs | **Approve both** (0-delta, tests prove MDT == prior tables). Assign a named owner per MDT; confirm D-14 open-ended 501+ band. |
| 3 | OQ-6 — `Currency_Conversion_Formula__mdt` string-vs-decimal | **Defer** until after Part-A step 2; then re-grep → **retire if unreferenced**, else decide. |
| 4 | INV-28 adjacent — US-services null-assignment sanity | **Run one UI reprice** on quote `0Q0WC000003J3tJ0AS`; expected PASS (non-$0). |
| 5 | D-23 — clone-clutter consolidation | **Label-rename hygiene only, 0 deletions.** 4-step canvas checklist below. |

---

## Decision 1 — OQ-2 / D-10b: Quote currency-change handler
*(downstream of the multi-currency FX fix — see `parked_multicurrency_D21_owner_brief.md` Part A)*

**Question.** When a Quote's currency changes, should we (a) activate a handler that **converts prices / rebuilds
lines** (the pattern of the now-deleted `QuoteCurrencyChangeService_Fixed`), or (b) **Force-reprice through the
pricing engine**? (The wired `QuoteCurrencyChangeService` is a no-op behind a **Draft/inactive** flow today; its
orphan `_Fixed` clone was deleted in Round 4 as dead code — nothing runs on a currency change right now.)

**Options.**
- **A — Activate a converting handler.** Point/activate the Draft flow at real logic that looks up the new-currency
  PBE and rebuilds QLIs (per `_Fixed`), or FX-multiplies existing amounts.
- **B — Force-reprice through the engine.** Stamp the new `CurrencyIsoCode`, then reprice via Place Sales Transaction
  `pricingPreference=Force` (the existing `Fortra_Quote_Reprice` flow path). No line rebuild, no FX math in code.
- **C — Leave inert.** Keep the no-op; a currency change does nothing until repriced by other means.

**Recommendation — B, but DEFERRED.** Per memory `reference_rlm_multicurrency_best_practice` (Salesforce-doc-grounded):
a currency change must be a **forced reprice through the engine**, **never** a line-rebuild or `base × FX-constant`.
Option A is the documented anti-pattern twice over — `_Fixed` did direct QLI DML (blocked by design under RLM) and
would layer on the hardcoded-FX pattern. **And this is strictly downstream of Part A**: building any currency-change
handler before the list-price lookup is currency-aware just Force-reprices onto an engine that still strands non-USD
lines at USD. So: keep it inert now, implement B only after Part A steps 1–2.

**Risk.** Activating A → RLM blocks direct Quote/QLI DML + reintroduces FX-multiply mispricing. Building B early →
reprices onto the un-fixed engine (wrong prices, false confidence). Doing nothing (today) is safe — the flow is Draft.

**Next-action.** **Defer.** Sequence: Part A #1 (currency-aware PBE lookup) → #2 (delete the 4 FX steps) → **then**
implement the currency-change handler as a Force-reprice Flow (not `_Fixed`), gated on a real currency-change scenario.
No action needed today; the Round-4 orphan delete already removed the misleading `_Fixed` clone.

---

## Decision 2 — OQ-4 / OQ-5: sign off the new admin MDTs (Round 4)

**Question.** Confirm the two new admin-editable Custom Metadata Types are **seeded with the exact prior hardcoded
values**, and assign an ongoing config **owner** for each.

**D-15 — `Country_Currency_Map__mdt`** (Tab 3; 15 records live in org). Behavior-preserving extraction of
`CurrencySelectionService`'s inline map; unit test `currencyMap_matchesLegacyHardcodedMap` pins MDT == the exact prior
map; S9/S10 0-delta. *(Note: prior "14-country" label undercounted — the code map is **15** entries; seeded 15.)*
- USD: United States · CAD: Canada · AUD: Australia
- EUR (12): Germany, France, Italy, Spain, Netherlands, Belgium, Austria, Ireland, Portugal, Finland, Greece, Luxembourg

**D-14 — `Hardware_Attribute_Pricing__mdt`** (Tab 2; 16 records; deployed). Extraction of `HardwarePricingCalculator`'s
inline pGroup / user-tier / system-type tables:
- **SystemType** (`Value__c`): Production **0.0** · Staging **25.0** · Test **50.0**
- **UserTier** (Min–Max → `Value__c`): 1–10 **1.0** · 11–50 **1.25** · 51–100 **1.5** · 101–250 **2.0** · 251–500 **2.5** · **501+ (Max open-ended) 3.0**
- **pGroup** (`Attribute_Key__c` → `Value__c`): P05 **0.5** · P10 **0.75** · P20 **1.0** · P30 **1.5** · P40 **2.0** · P50 **3.0** · P60 **4.0**

**Options.** (A) Approve both as-is. (B) Approve with value corrections. (C) Hold pending business value review.

**Recommendation — A, approve both.** Both are proven behavior-preserving (0-delta gates green + unit tests assert
MDT == prior hardcoded tables), so sign-off is a values eyeball, not a risk decision. Assign owners: **D-15 → Finance /
Pricing-config owner** (currency defaults); **D-14 → Hardware pricing owner**. One thing to explicitly confirm on D-14:
the **501+ band is intentionally open-ended** (`Max_Users__c` null) — that was Tab 2's D-14 design point.

**Risk.** Low today (values match code, tests prove it). The *forward* risk is that these are now **live config** (edits
take effect with no deploy/gate) — hence naming an owner matters more than the initial sign-off.

**Next-action.** Owner eyeballs the two value tables above → replies "confirmed" + names an owner per MDT. No code/deploy.

---

## Decision 3 — OQ-6: `Currency_Conversion_Formula__mdt` (config-as-code)
*(full analysis: `parked_multicurrency_D21_owner_brief.md` Part B / D-21)*

**Question.** The MDT stores **executable formula strings parsed/evaluated at runtime**. Keep the executable strings,
or migrate to a plain `Conversion_Rate__c` **decimal** (data, not code)?

**Options.** (A) Keep executable strings. (B) Migrate to decimal rate. (C) **Defer** and decide as a consequence of the
FX-removal.

**Recommendation — C, defer (do not invest yet).** If Part A proceeds, FX is removed from price derivation entirely and
this MDT likely becomes **legacy/unreferenced** — in which case the correct move is to **retire** it, not refactor its
strings into decimals. Converting string→decimal now risks polishing an object that's about to be deleted.

**Risk.** Map-only today (no live action either way). Migrating string→decimal is behavioral (parallel-run gated);
retiring after Part A is low-risk (reference-proof + 0-delta). Leaving executable `eval` strings indefinitely is the only
"do-nothing" downside — an opaque, untestable parse/injection surface — but Part A resolves it by removal.

**Next-action.** **Defer until after Part A step 2.** Then **re-grep** live references (`procedure / Apex / flows`):
0 readers → **retire the MDT** (OQ-6 closes by deletion); a genuine non-price-derivation reader remains → *then* decide
decimal-vs-string for that residual use only.

---

## Decision 4 — INV-28 adjacent: US-services null-assignment sanity check
*(INV-28 / OQ-11 itself is CONFIRMED-CLOSED — see `INV28_regional_gate_confirmation.md`. This is the one open runtime
question that brief flagged, §5.)*

**Question.** On active V21, `RegionalServicesPrice33` unconditionally assigns `RegionalNetUnitPrice__c → InputUnitPrice`
whenever `AllowRegionalPricing__c = true`. On a **US services line** that field is **null** (it's populated only via the
regional path / and is an Order-side field). Does that **null assignment** propagate to a **$0 / null** price on US
services lines, or does the engine treat it as a no-op / overwrite it downstream?

**Exact quote + steps to run (owner, ~2 min, UI):**
1. Open Quote **`0Q0WC000003J3tJ0AS`** ("Q-Wren Test - Order Processing Groups-2026-07-08", **USD**), which has a
   regional-eligible services line **"24 X 7 X 365 Monitoring"** (`Allow_Regional_Pricing__c = true`, US → no regional
   multiplier). *(Static read today: UnitPrice = NetUnitPrice = 15000 — i.e. NOT $0 — but the definitive check is a live
   reprice.)*
2. In the Transaction Line Editor → **Reprice All**.
3. **Confirm the services line's Unit/Net price stays non-$0** (≈15000). If you want proof of the internal, capture a
   FINEST debug log on the reprice and check `InputUnitPrice` is not null-zeroed by the `RegionalServicesPrice33` assignment.
   *(Alternate fixtures with US regional-eligible services lines: `0Q0WC000002RK6g` GoAnywhere QuickStart $8500 / GoAnywhere $250.)*

**Recommendation — run it; expected PASS.** INV-28's crash surface is structurally removed (no `RegionalNetUnitPrice__c > 0`
predicate anywhere on V21), and V21 validation runs price services lines correctly, so the null is almost certainly a
no-op/overwritten. The reprice is a cheap confirmation of the one thing that couldn't be proven statically.

**Risk.** Low. If the line DOES come back $0, that is a **new, separate** finding (null-assignment zeroing), **not** a
reopen of INV-28 — log it as its own item. Note: the amendment line on `0Q0WC000003J4m90AC` (24×7×365, NetUnitPrice 0) is
a **different** issue (amendment-not-pricing / the Sales-Price ticket), not this US-new-business case — don't conflate.

**Next-action.** Owner runs the reprice on `0Q0WC000003J3tJ0AS`, confirms non-$0. Closes the INV-28 §5 tail.

**RESULT (2026-07-08, Tab 3, authorized Force-reprice via `Fortra_Quote_Reprice`) — ✅ PASS / benign.**
Before → after the reprice, line `04267477` "24 X 7 X 365 Monitoring" (`Allow_Regional_Pricing__c = true`, US/USD,
`PrehookRSNetUnitPrice__c` null) held **UnitPrice = Base_Price__c = NetUnitPrice = 15000** (unchanged, NOT $0); the two
non-regional control lines also unchanged (94000, 10000). The null `RegionalNetUnitPrice__c → InputUnitPrice` assignment
does **not** zero US services lines — no-op / overwritten downstream. **INV-28 §5 closed as benign.** Caveat: programmatic
Force-reprice proves the *outcome* (final price) but not the FINEST *internal* (`InputUnitPrice` momentary null) — a UI
reprice with a FINEST log is the only way to see the engine internal, if belt-and-suspenders proof is wanted.

---

## Decision 5 — D-23: clone-clutter consolidation → owner checklist
*(full guide: `D23_clone_consolidation_guide.md`. Headline: this is **label debt**, not dead code.)*

**Question.** How to consolidate the V21 "clone clutter" (the "Copy of Copy" triad + 16 duplicate-label groups + ~28
ListContainer sprawl)?

**Options.** (A) Delete the clones as dead code. (B) **Label-rename hygiene only** (0 deletions). (C) Structural merge of
the duplicate paths.

**Recommendation — B.** In an ExpressionSetDefinition, runtime identity = `<name>` + field I/O + `<conditionLogic>`;
`<label>` is display-only and referenced by nothing → **renaming a label is provably 0-delta**, while **deleting any
clone is NOT** (each writes a distinct wired field, e.g. `Total_Software__c`). Recommended **deletions = 0**.

**Owner canvas checklist (all 0-delta, in-place V21):**
- [ ] **Rename the "Copy of Copy" triad** (seq 35/36/37) — highest value; kills the misleading dead-code look:
  "Copy 1 of List Container 8" → **Aggregate Total Software (K-09)** (`Total_Software__c`); "Copy 1 of Copy 1 …" →
  **Aggregate Total Subscription (K-09)** (`Total_Subscription__c`); "List Container 8" → **Aggregate Total Services (K-09)**.
- [ ] **Rename the 12 "List Container"** ListGroups + **8 "List Operation"** filters to their function (enables label-based waterfall diffing).
- [ ] **Rename the 2 "Aggregate Price"** elements (seq 45/46) → **Aggregate Price (ungrouped)** / **Aggregate Price (per item group)**.
- [ ] **Investigate — do NOT merge** the two `Attribute Pricing Filter` paths (different criteria sets) until a full-matrix parallel-run proves them disjoint/redundant.
- [ ] **Delete nothing.** Every clone carries a wired output; and **remove no `AdvancedListFilter` criterion** (D-20 positional-renumber hazard silently rewrites logic).

**Risk.** Label rename = 0-delta and reversible. The only hazards are (a) using "Delete Group" on a clone (strands a wired
field) and (b) removing a filter criterion (positional renumber) — the checklist explicitly avoids both.

**Next-action.** Schedule a short in-place V21 canvas rename pass (steps 1–3), owner-gated per the co-owned V21 window;
park the §4c investigation (step 4) behind a parallel-run.

---

### Cross-item sequencing (one picture)
`Part A #1 currency-aware PBE lookup` → `Part A #2 delete 4 FX steps (0-delta cutover)` → **Decision 1** (currency-change
Force-reprice) + **Decision 3** (retire/decide the FX MDT) fall out as consequences. **Decisions 2, 4, 5 are independent
and can be cleared now** (2 = eyeball+sign, 4 = one reprice, 5 = schedule a rename pass).
