# RN-MULTIYEAR — Synthesis Verdict (SC-3346 / SC-3404 domain, FortraUAT)

**Date:** 2026-06-14  **Mode:** READ-ONLY adversarial re-verification of the 2026-06-14 E2E retest reclassification.
**Subject:** The retest moved scenario **RN-MULTIYEAR** from `fail/high (SC-3404)` to `OUT-OF-SCOPE / not a defect`, asserting that multi-year / out-year / MyCAP COLA pricing is **inert at the commit layer** and that **single-year** is the intended scope per both SDDs.

---

## 1. The Proposition Under Test

> "Multi-year / out-year / MyCAP COLA pricing on renewal lines is INERT at the commit layer (no committed money is ever wrong because of it), single-year is the intended design scope, and the prior `RN-MULTIYEAR fail/SC-3404` verdict was a **mislabel** of the single-year RN-COLA-COMMIT defect."

## 2. VERDICT (decisive)

**RN-MULTIYEAR is NOT a real commit-money defect. The retest's reclassification is mechanically and design-intent correct: multi-year COLA is OUT-OF-DOCUMENTED-SCOPE and inert at the commit layer.** Classification: **not-a-defect-confirmed** for the committed-money question, with the explicit qualifier below.

However, the retest's flat label "not a defect / nothing to do" **under-describes one real, separate artifact**: a broken, deployed, multi-year-intent **formula field `Final_Year_COLA_Calculated_Price__c` that is in an INVALID_FIELD / un-queryable state** today. That is genuine tech-debt (SC-3350 B3/B4) but it touches **no committed money** and does not make RN-MULTIYEAR a pricing defect.

**What "fix RN-MULTIYEAR" actually means** (since the owner asked to fix it): it is **not** a one-line repair of a broken-but-wired commit path — that path never existed. It is one of:
- **(A) — the genuine in-spec defect:** fix the **single-year RN-COLA-COMMIT gap (SC-3404)** that the canary actually exhibits (Net 60.64 ≠ single-year calc 67.38). This is the real, owner-relevant work and is already a tracked ticket.
- **(B) — a NET-NEW feature build:** if the business wants multi-year/out-year COLA to *commit*, that requires an owner/design decision (Marc DeBrey / German) plus building a committable out-year-aware step (see §6). Not a defect fix.
- **(C) — tech-debt cleanup:** remove/shelve the broken `Final_Year_COLA_Calculated_Price__c` formula and inert MyCAP price scaffolding, OR formally spec-and-finish it.

`isFixableInUAT = true` only for path (A) (the single-year SC-3404 defect, separately ticketed) and path (C) (declarative removal). Path (B) is `ownerGated`.

---

## 3. Per-Claim Verdict Table (C1–C6)

| Claim | Verdict | Evidence (live-verified 2026-06-14) |
|---|---|---|
| **C1** — Active V14 procedure has 0 outyear/mycap/final_year/multi-year refs | **CONFIRMED** | Tooling: `ExpressionSetDefinitionVersion 9QBWC0000000nIT4AY` VersionNumber=14 **Status=Active**; V1–V13 all Inactive (queried live). Active V14 block (`live_v14_block.xml`, fullName `…Rev_Mgmt_Default_Pricing_V140`, `<status>Active</status>` L10, `<versionNumber>14</versionNumber>` L5550): `grep -inE 'outyear\|out_year\|out-year\|mycap\|final_year\|finalyear\|multiyear\|multi-year\|multi_year\|Final_Year_COLA'` = **ZERO HITS**. Only COLA tokens: `COLACalculatedPrice__c`×7, `COLA_Uplift_Percent__c`×3 (year-1), `COLAUpliftonRenewal`×2, `COLAUpliftonRenewalNet`×1. Renewal commit formula = single-year `IF(QuoteTypeText__c='Renewal', IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, (Base − PriorPartner − PriorDisc)*(1+COLA_Uplift_Percent__c/100)), NetUnitPrice)`. *(One investigator miscounted "V13"; Tooling is authoritative — V14 is the sole Active.)* |
| **C2** — Prehook reads `COLA_Outyear_Uplift_Percent__c` ONLY for below-minimum approval check (~L1064-1067), not pricing | **CONFIRMED** | Freshest live body `COLAUpliftPrehook` (`01pWC000001wNGbYAM`, LastModified **2026-06-14T13:57:38Z** — re-edited after digest seeds; pulled fresh, byte-identical to the 13:53 seed). All `COLA_Outyear_Uplift_Percent__c` refs: L310 (comment), L965/968 (SELECT→`qliIdToOutyearPct`). Sole consumer L1064-1067: `outyearPct = qliIdToOutyearPct.get(qliId); outyearBelowMin = outyearPct != null && outyearPct < minimumUplift; if (year1BelowMin \|\| outyearBelowMin) quotesToFlagTrue.add(quoteId);` → feeds only the MyCAP approval flag. **Nuance:** a SEPARATE compounding loop exists in `buildCOLAContextUpdate` (compounds the **year-1** rate, not out-year) but its output is **dead code** (see C2-nuance below). Out-year never reaches any committed price. |
| **C3** — Prehook enqueues `MyCAPFlagApplier` which only sets `Quote.Mycap__c`, no reprice | **CONFIRMED** | `MyCAPFlagApplier` is an **inner Queueable** of the prehook (no standalone ApexClass). Enqueued L1093. `execute()` does only `Database.update` on `new Quote(Id, Mycap__c=desired)`. In-code comments state QLI DML was deliberately removed to avoid a DML→reprice loop and "Quote-level DML does not trigger the pricing engine." No QLI DML, no Place-Sales-Transaction, no reprice. |
| **C4** — Out-year populated on ~15 QLIs, ALL Subscription/null non-maintenance, committed price tracks year-1 | **CONFIRMED (with a correction to the descriptor)** | Live SOQL: exactly **15** QLIs have `COLA_Outyear_Uplift_Percent__c != null`; **0** in maintenance family (verified live: maint+renewal-maint outyear count = 0). Breakdown 11 null-type + 4 Subscription, all `SellingModelType=TermDefined`. **Correction:** out-year is a genuinely **distinct stored value** (e.g. y1=9.85/oy=3, y1=7.85/oy=4, ptc 3/12/36) — NOT a trivial copy of year-1. The *conclusion* "committed price tracks year-1" still holds (arithmetic: `0QLWC0000037ljd4AA` 282000×1.05=296100=Net, ptc=36 inert; `0QLWC0000034WxF4AU` 6063.75×1.0785=6539.75=Net, oy=4 inert), but it holds *because of* the inertness, not because these are trivially single-year lines. |
| **C5** — Canary `0QLWC000003e2Sn4AI` is Renewal Maintenance with out-year=null (the prior "multi-year defect" = single-year RN-COLA-COMMIT/SC-3404 mislabeled) | **CONFIRMED** | Live SOQL (re-run today): `Fortra_Product_Type__c='Renewal Maintenance'`, `COLA_Outyear_Uplift_Percent__c=NULL`, `COLA_Uplift_Percent__c=7.85`, `COLACalculatedPrice__c=67.38`, **NetUnitPrice=60.64**, `PricingTermCount=null`. Out-year is NULL ⇒ cannot be a multi-year case. The 60.64≠67.38 gap is the single-year RN-COLA-COMMIT (SC-3404) gap. Origin proof: the ORIGINAL `verdicts_merged.json` RN-MULTIYEAR verdict used THIS canary and its own notes conceded the failure was "the known open SC-3404 engine-persistence defect (ItemIsDerived + qty 0 + ListPrice 0 + No-Change)" — i.e. a multi-year *name* over a single-year *defect*. |
| **C6** — Both SDDs scope renewal COLA as SINGLE-YEAR only | **CONFIRMED (with precision)** | COLA SDD (`docs/Fortra-Pricing-COLA-Solution-Design-Doc.docx`): BR-002 `UnitPrice = Asset.Price × (1 + COLA%/100)`; §6.3 `Pre_COLA_Price__c × (1 + COLA_Uplift_Percent__c/100)`; worked example $10,000×1.0785=$10,785. Enumerates exactly 10 QLI COLA fields — `COLA_Outyear_Uplift_Percent__c` and `Final_Year_COLA_Calculated_Price__c` are NOT among them. ZERO hits for out-year/multi-year/mycap/final-year/year-2/escalat. Maintenance-Derived SDD: **silent** on COLA (0 hits) — tier-rate × `Source_List_Price__c` only. **Precision:** the Maintenance SDD does not *mandate* single-year, it is *silent*; but the COLA SDD + canonical User Story Req #5 (`Final Price = Base × (1 + COLA_Uplift_Percent__c/100)`, "single-year only … no out-year/MyCAP/multi-year compounding") + Confluence Overview + Increase Table **unanimously** specify single-year. |

### C2-nuance — the dead-code compounding loop (load-bearing for the bug-vs-feature call)
`buildCOLAContextUpdate` (live) contains a real compounding loop `for (i=0;i<terms;i++){ yearPrice = yearPrice*(1+uplift/100); }` over `pricingTermCount`. It is **dead code**: (1) it compounds the **year-1** `uplift`, not the distinct out-year rate; (2) its output goes into local `List allContextUpdates` (declared L1020, added L1076) which is **NEVER** passed to a context write. Live grep confirms the only two `submitContextUpdates` calls are **L378** (subscription year-1 path) and **L440** (maintenance year-1 path); the lone `updateContextAttributes` is L637 inside `submitContextUpdates`. A comment near L1083 confirms the second context write was deliberately removed. Empirically inert: 12 of the 15 out-year lines have `pricingTermCount>1` (3/12/36) — exactly where the loop *would* fire if wired — yet every one commits a single-year figure.

---

## 4. Adversarial Outcome

All three adversarial reviewers (DATA/REPRO, DESIGN/SDD, MECHANISM) returned **`isActuallyADefect = false`, confidence HIGH**, each having independently re-derived from the LIVE org (incl. catching that the prehook was re-edited to 2026-06-14T13:53/13:57Z after the digest, and re-verifying line numbers against the current body).

Key adversarial findings that **failed to refute** out-of-scope:
- **DATA/REPRO:** No live multi-year maintenance data exists to mis-price — Renewal-Maintenance population (~498k–559k QLIs) has **0** rows with `PricingTermCount>1`, **0** with `SubscriptionTerm>12`, **0** with out-year populated. All 15 out-year lines commit year-1 (arithmetically verified against year-1, compounded, and final-year candidates — none match a compounded figure). No row where committed money is wrong due to multi-year.
- **DESIGN/SDD:** Every authoritative artifact scopes single-year; the one richer artifact (Leah Guenther's "Perpetual Sales Calculations" spreadsheet) is **not in the repo**, "medium confidence," and the scope fork was **already adjudicated toward single-year (Option A) on 2026-06-10** on the strength of the canonical user story.
- **MECHANISM:** No active procedure step or Apex path *attempts* to commit a multi-year/out-year price and fails. Multi-year is feature-scaffolded-for-display-but-never-wired-to-commit.

**Consensus caveat (does not flip the verdict):** the org ships deliberately-built, post-SDD multi-year machinery (Marc DeBrey 2026-04-16/17): the `COLA_Outyear_Uplift_Percent__c` field, the `Final_Year_COLA_Calculated_Price__c` compounding formula, `MyCAP_Rules__mdt` Default/Minimum_Out_Year=3, and the dead compounding loop. This is a **half-wired feature / out-of-spec gold-plating** with a **broken** display field — SC-3350 graded it B3 HIGH(design) + B4 HIGH-if-activated. It is real tech-debt, but it commits no money.

---

## 5. Design-Intent Quotes (the anchor)

- **COLA SDD, BR-002:** "Calculate renewal pricing using the formula: **UnitPrice = Asset.Price × (1 + COLA% / 100)**."
- **COLA SDD, §6.3:** "**UnitPrice = Pre_COLA_Price__c × (1 + COLA_Uplift_Percent__c / 100)**. For example, Asset.Price = $10,000 with 7.85% COLA yields UnitPrice = $10,000 × 1.0785 = $10,785.00." — one rate, one application, no across-year term.
- **Canonical User Story (SC-3350 evidence/USER_STORY.md) Req #5:** "RCA Pricing Procedure applies **Final Price = Base Renewal Price × (1 + COLA_Uplift_Percent__c / 100)**. Apply **only to renewal** quote lines." Header note: "**Note it is single-year only** … no out-year / MyCAP / multi-year compounding."
- **SC-3350 conformance audit (03_USERSTORY_CONFORMANCE.md):** "Live adds **inert out-year / MyCAP** machinery … computed but **referenced 0× in pricing**, and the formula is broken. ➕ **OUT-OF-SPEC EXTRA (gold-plating)**." "the user story is explicitly single-year (Req #5) … That resolves the scope fork decisively toward Option A."
- **Maintenance-Derived SDD:** silent on COLA/renewal-year escalation entirely (tier-rate × `Source_List_Price__c` → NetUnitPrice).

**Conclusion on intent:** No design artifact REQUIRES per-year-distinct or compounded renewal COLA. Therefore the commit-layer inertness of multi-year **cannot be a defect against the spec.** It is an unbuilt (and undocumented) feature, deliberately deferred.

---

## 6. The Exact Fix / Scoping (per disposition)

### (A) The genuine in-spec defect the canary exhibits — SINGLE-YEAR RN-COLA-COMMIT (SC-3404)
This is the real, owner-relevant work mislabeled as "multi-year." Canary `0QLWC000003e2Sn4AI`: committed NetUnitPrice **60.64** vs in-spec single-year calc **67.38** (`Base 71 × 1.0785`, less partner net). This is the no-priced-node / engine-persistence gap (ItemIsDerived + qty 0 + ListPrice 0 + No-Change action) already tracked as SC-3404 and partially addressed by `PartnerNetPricePosthook v1.5` (60.64→67.38). **This** is what "fix RN-MULTIYEAR" should resolve in-spec. Fixable in UAT; tracked separately as SC-3404.

### (B) If the business wants multi-year to COMMIT — NET-NEW feature (owner-gated)
Owner decision required (Marc DeBrey / German): does committed renewal money escalate per out-year, on which lines (license only, or maintenance too), and at which rate (year-1 CMDT vs MyCAP 3% out-year)? Building it entails:
1. Repair `Final_Year_COLA_Calculated_Price__c` first (it is INVALID_FIELD / un-queryable today; the formula also uses `PricingTermCount` (months) as a years-exponent with no unit guard — wrong base + months-as-years bug, SC-3350 B4) OR add a stored out-year price field.
2. Add a committable procedure step in V15 of `Rev_Mgmt_Default_Pricing_Procedure` that reads the corrected out-year/final-year value and writes NetUnitPrice — currently the active V14 references it **0×**.
3. Wire the prehook's compounding output (today dead `allContextUpdates`) to a context write, using the **distinct out-year rate** not year-1, with a term-unit guard.
Not behavior-preserving; not a UAT one-liner; requires a spec.

### (C) Tech-debt cleanup (declarative, UAT-safe)
Remove or shelve the broken `Final_Year_COLA_Calculated_Price__c` formula field and the inert MyCAP price scaffolding (the dead compounding loop), per SC-3350 §8 B3/B4, so a non-operational INVALID_FIELD formula does not ship. Leaves committed money unchanged (it already touches none). Owner should still choose remove-vs-finish.

---

## 7. Open Questions (block full certainty)

1. **Business intent on multi-year commit** — does Fortra actually want out-year COLA to bill, or is single-year final? Leah Guenther's spreadsheet (multi-year, NOT in repo, medium-confidence) vs the canonical single-year User Story; the fork was adjudicated to single-year on 2026-06-10 but the owner asked to "fix RN-MULTIYEAR," so re-confirm. (Marc DeBrey / German)
2. **Disposition of the broken `Final_Year_COLA_Calculated_Price__c`** — remove/shelve (path C) or repair-and-wire (path B)? It is INVALID_FIELD today and is latent integrity debt regardless.
3. **Is RN-MULTIYEAR being conflated with SC-3403's distinct carry-forward defect?** SC-3403 finds a *real* multi-year renewal **carry-forward** break (Y2→Y3 priors persist null → next-cycle mis-price, e.g. order 00095475 UnitPrice=0/null priors; B-6 order carries license base 355 instead of maint base 71). That is a separate, genuine defect from the out-year *commit* question — clarify which "multi-year" the owner means by "fix RN-MULTIYEAR."
4. **Whether SC-3404 (the single-year canary defect) is the intended target** of the "fix RN-MULTIYEAR" directive — if so, route there; RN-MULTIYEAR as a multi-year commit bug is closed.

---

## 8. Bottom Line

The 2026-06-14 retest was **right**: RN-MULTIYEAR is **out-of-scope / not a commit-money defect**, multi-year COLA is inert at the commit layer, and the prior `fail/SC-3404` canary was the **single-year** RN-COLA-COMMIT defect wearing a multi-year label. Confidence **HIGH** (all six claims live-verified; three adversarial lenses independently concur). "Fix RN-MULTIYEAR" resolves to: **fix the single-year SC-3404 gap (in-spec)**, and make an **owner decision** on the half-built out-year machinery (build-it-as-a-feature vs remove-the-broken-scaffolding). It is **not** a one-line repair of a broken-but-wired multi-year commit path — that path was never built.
