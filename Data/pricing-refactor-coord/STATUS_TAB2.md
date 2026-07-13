# STATUS — Tab 2

- **Updated:** 2026-07-08 (Tab 2)
- **Round:** 5 — TEST-COVERAGE HARDENING (assert-only; no calculator .cls edits). Deployed 5 test files NoTestRun; ran them.
- **MID-DEPLOY:** no — Round-6 Track-1 DONE: deployed, 115/115 tests, 5/5 anon-smoke, S12 GATE PASS 0-delta, **committed `af3a470` + pushed to origin/uat** (6 clean files only).

## ROUND 6 — Track-1 SDD-reconciliation fixes (deploy + gate + leave uncommitted)
Audit: `Data/pricing-refactor-scratch/round6/SDD_reconciliation_audit.md`. Track-1 = the no-owner-ruling-needed
code fixes in CLEAN files (NOT Nir's `PartnerPricingServiceV2`/`PartnerNetPricePosthook`). 6 files changed:
- **D-PARTNER-1 (HIGH)** — `PartnerMarginDispatcher` now flags a participating partner configured on the Quote
  but missing a matching model (Result.warning); `PartnerPricingPayloadBuilder` writes it to
  `Partner_Pricing_Warning__c` (was hardcoded null); `PartnerPricingPrehookV2` threads it. **Audit field —
  NOT in the snapshot oracle → 0-delta.**
- **D-PARTNER-5 (MED)** — `PartnerPricingPayloadBuilder` now stamps the custom `Partner_Discount_Percent__c`
  on the success path (was only nulled on the stale path), symmetric with the standard `PartnerDiscountPercent`.
  ⚠️ **`Partner_Discount_Percent__c` IS a captured oracle column** → this is an INTENDED delta on PARTNER
  scenarios (S5/S6/S7): the field goes blank→total% on partner lines. **0-delta on S12** (no partner lines).
  **FLAG for Tab 1:** when your full matrix reprices S5/S6/S7, expect `Partner_Discount_Percent__c` populated —
  intended, not a regression.
- **D-PARTNER-6 (LOW)** — `PartnerPricingPrehookV2` blank `ctxInstanceId` now returns SUCCESS (skip) not FAILED
  (fail-safe TR-004). Unreachable path → 0-delta.
- **D-COLA-5 (LOW)** — corrected the `COLAUpliftPrehook` header write-set comment (no runtime) → 0-delta.
- **D-COLA-6 (LOW)** — removed the dead `allContextUpdates` accumulation in `COLAUpliftPrehook` (built but
  never submitted; its `buildCOLAContextUpdate` reverse-derives Pre-COLA from UnitPrice = a §11 r1 invariant
  violation if ever re-wired). Dead code → 0-delta.
- **Deferred (Nir-entangled, NOT touched):** D-PARTNER-3 (needs `PartnerPricingServiceV2.selectBestModelForLine`)
  + D-MAINT-3 (price change feeding `PartnerNetPricePosthook`) — wait for Nir to commit.
- **Deploy `0Af…` NoTestRun** (Tab1/Tab3 no at claim). **Tests 115/115**: PartnerMarginDispatcherTest 11 +
  PartnerPricingPayloadBuilderTest 3 + PartnerPricingPrehookV2Test 24 + COLAUpliftTest 58 + COLAUpliftCalculatorTest 19.
- **NOT committed** (left in tree for review). Did NOT touch Nir's 3 files, V21/ESD, or other tabs' files.
- **Branch:** uat
- **Gate scenario:** S12 (`0Q0WC000002RK6g`) — **GATE PASS 0-delta** (23 lines, 25 cols). KB: `Fortra-Products-Hardware-Solution-Design-Doc.md` §8 Rules 2/3/4 (frozen SDD, not edited).
- **Quiescent:** YES — D-14 done (MDT + calculator + tests shipped, S12 0-delta, committed). Safe for Tab 1's full matrix.
- **Files I own this round (edit):** `HardwarePricingCalculator.cls` (+Test), new `Hardware_Attribute_Pricing__mdt` + 16 records.

## ROUND 4 — D-14: Hardware pricing tables → admin-editable MDT (behavior-preserving)
- **New MDT `Hardware_Attribute_Pricing__mdt`** (Public), 5 fields: `Table_Type__c` (pGroup|UserTier|SystemType
  discriminator), `Attribute_Key__c` (pGroup/SystemType key), `Min_Users__c`/`Max_Users__c` (UserTier band;
  Max blank = open-ended), `Value__c` (multiplier or discount %). **16 records seeded with the EXACT current
  values** (== SDD §8 Rules 2/3/4): 7 pGroup (P05=0.5 … P60=4.0), 6 UserTier (1–10=1.0 … 501+=3.0 open-ended),
  3 SystemType (Production=0/Staging=25/Test=50). No org value differed from code → nothing to escalate.
- **Calculator** now loads the three tables from the MDT via `getAll()` (NOT SOQL — no query-governor cost,
  matters for SC-3447) lazily once per txn; lookup semantics + miss-defaults (1.0x / 0%) unchanged; P20/Production/1
  system-default fallback (in the hook, not this class) untouched. Kept a `@TestVisible loadFromRecords` inject seam.
- **Tests:** injected-canonical-table tests prove MDT-driven == old hardcoded for **every tier**; plus
  `deployedSeed_reproducesSdd` (shipped 16-row seed integrity), `mdtIsAdminEditable_valueFlowsThrough`
  (edit flows through — the D-14 payoff), `emptyConfig_fallsToDefaults` (safety). Prehook test unchanged
  (its getter calls now resolve through the deployed seed).
- **Deploy set:** MDT type + 5 fields + 16 records + `HardwarePricingCalculator`(+Test). Deploy `0Af…` NoTestRun
  (Tab 3 cleared first, Tab 1 no). 16 records verified value-for-value == code. Commit `96a7f62` (24 files, explicit add).

### RESULT — GATE PASS 0-delta + debug-log corroboration
- **S12 reprice:** `snapshot.sh` → `diff.py` = **GATE PASS — 0 delta** (23 lines, 25 cols) vs the current
  (Tab-1 re-baselined) baseline. Behavior-preserving confirmed.
- **CORRECTION to a prior note:** S12 *does* exercise the hardware calculator. The `/aura` reprice debug log
  (`07LWC00000Q6xOF2AZ`) shows the prehook priced **17 of 23 lines** (6 skipped = no valid price / $0), the
  **calculator ran 240×** through the MDT path, and **`Hardware_Attribute_Pricing__mdt` was read 25×** via
  getAll(). Every line resolved to pGroup **P20 (System Default) → combined multiplier 1.000** (P20×1-user×
  Production-0%), so prices are unchanged → that is *why* the gate is 0-delta. So the MDT path is proven in the
  LIVE waterfall, not just unit tests. (21 lines show Server Type = Production **(Configurator)** — confirms
  last round's F1 'Configurator' source label is live; audit-only, not a captured column.)
- **Governor / getAll() claim verified:** SOQL peak **9/100** (getAll added none), CPU **2843/10000**,
  **0 exceptions/FATAL** — no SC-3447 risk.
- **"Contributing products missing" banner:** 0 mentions in the Apex log → it is the native RLM managed-pricing
  flag (SC-3372), not custom Apex and not caused by D-14; pre-existing on this quote.

## ROUND 3 (design-compliance) — candidate fixes triaged against KB §8

### F1 — Source label → SDD-canonical (KB §8 Rule 5). **FIX (SHIPPED to tree; deploying).**
- **Defect:** prehook stamped `Hardware_Pricing_Source__c = 'User Override'`, which is NOT one of the
  three SDD-valid values. Rule 5 requires it record WHICH override tier won using exactly one of
  `Configurator | Hardware Default | System Default` (priority: Configurator > Hardware > System).
- **Fix:** added canonical constants `SOURCE_CONFIGURATOR/HARDWARE/SYSTEM`; the configurator-tier
  label is now `'Configurator'` (was `'User Override'`) across per-attribute resolution + the
  `dominantSource` rollup + the JSON audit (`Hardware_Pricing_Detail__c`). Maps the RESOLVED tier —
  does NOT hardcode 'Configurator' (Hardware/System paths unchanged; parse-error stays a diagnostic
  variant of System Default). 'Hardware Default' / 'System Default' were already SDD-valid, untouched.
- **Gate impact:** `Hardware_Pricing_Source__c` and `Hardware_Pricing_Detail__c` are audit-only and
  are **NOT in the snapshot oracle** (snapshot.sh captures pricing cols only). ⇒ **0-delta** on every
  scenario by construction. Proof is the unit test, not the gate.
- **Test:** new `testProcessLineItem_sourceLabel_rule5_allTiers` asserts Configurator/Hardware
  Default/System Default across all three tiers; 4 existing assertions flipped 'User Override'→
  'Configurator' (they pinned the pre-SDD value).

### F2 — Top user-band open-ended (KB §8 Rule 3). **FIX (SHIPPED to tree; deploying).**
- **Defect:** `USER_TIER_RANGES` top band was `(501, 999999, 3.0)` — a finite cap. Users ≥ 1,000,000
  fell through to the 1.0x default instead of the top 3.0x. Rule 3's top band is `501+ = 3.0`
  (open-ended).
- **Fix:** top band → `(501, null, 3.0)`; matcher treats `maxUsers == null` as no-upper-bound.
- **Gate impact:** only changes lines with `Users_Per_Partition ≥ 1,000,000` — no such line exists in
  any scenario (S12 is software lines, maxQty 20). ⇒ **0-delta**. Proof is the unit test.
- **Test:** `userTierMultiplier_topBandOpenEnded_rule3` flipped to assert 1,000,000 & 2,000,000,000
  → 3.0x (previously pinned the 1.0x default). 999999→3.0 assertion retained.

### F3 — Product-eligibility gate (KB §8 Rule 12 / §4.7). **⚠️ ESCALATE — NOT fixing.**
- **What the KB says:** Rule 12 — "Only Power products get hardware pricing: eligibility gated by
  `HardwareProductEligibilityService` on product family / solution category." §4.7 + BR/TR echo this.
  So the SDD is NOT silent — it clearly wants a gate, and the prehook currently has none (it applies
  to any line with a `Hardware_Id__c` OR configured hardware attributes).
- **Why escalate rather than fix (Rule 6.1 — risks changing non-hardware pricing):**
  1. **No per-line API exists.** The deployed `HardwareProductEligibilityService` exposes only
     `filterProducts(Id hardwareId)` → bulk-filters the WHOLE active Product2 catalog by
     processor-count / feature-codes for the hardware-first *UI* workflow. It has no
     `isEligible(productId | family | category)` the pricing prehook could call per line. Wiring it
     in would require authoring a NEW method on a class I do NOT own, on unvalidated
     family/solution-category semantics (the KB even warns class/field names may differ from live).
  2. **Blast radius on pricing.** Today's implicit gate = "has hardware link or configured hardware
     attrs", which in practice only Power products satisfy (only they get assigned to hardware groups
     / expose the hardware AttributeDefinitions). Adding an explicit eligibility gate could newly
     EXCLUDE a line that is priced today (hardware-linked but deemed ineligible) → a pricing change on
     that line. I can't bound that blast radius without validating the service against the full matrix.
  3. **Governor risk (SC-3447 / INV-HW-FIRST).** S12 is the hardware-first governor case. Adding a new
     gate (and its SOQL, if per-line) into this load-bearing waterfall position (Rule 7) risks the
     CPU/SOQL budget the SC-3447 guard protects.
- **Recommendation for Marc/Tab-1 escalation doc:** decide (a) the exact eligibility predicate
  (product family? solution category? a `Fortra_Product_Type__c` value like 'Power'?), and (b) add a
  per-line `isHardwareEligible(...)` API on `HardwareProductEligibilityService` (owner-gated), then
  re-scope the prehook gate as a follow-up with a full-matrix regression. Until then the de-facto
  hardware-linkage gate stands.

## Deploy / gate RESULT (Rule 3 + Rule 6) — DONE
- **Deploy** `0AfWC00000GkzP30AJ` (NoTestRun, 4 hardware classes; both other tabs MID-DEPLOY:no at claim, no race).
- **Tests 71/71 green** (synchronous re-run): `HardwarePricingCalculatorTest` 13/13 + `HardwareAttributePricingPrehookTest` 58/58.
  (An async pass earlier showed a spurious "time limit exceeded" cancellation on a pure-math method that also had a
  Pass row + null stack — platform flake, not a code failure; the synchronous re-run is clean.)
- **S12 gate:** user repriced `0Q0WC000002RK6g`; read-only snapshot → `post/S12_quote.tsv`; `diff.py`:
  **0-delta w.r.t. Tab-2 change.** 22/23 lines identical. The only diffs = **3 EXOGENOUS deltas on line 3
  (GoAnywhere Services)**: `UnitPrice`/`Base_Price__c`/`Pre_Partner_Price__c` blank→250 (NetUnitPrice/Total UNCHANGED).
  These are base/pre-partner STAMPS my hardware classes reference **0 times** (writers = `ListPriceStampCalculator`/
  `PartnerPricingPrehookV2`/`PartnerNetPricePosthook`/`ContributorPricingCalculator` — Tab-1/Nir). Tab 3 had S12
  0-delta on Jul-7, so this drift is Jul-7→Jul-8 base/partner deploys, NOT this deploy. Full evidence +
  attribution in `baselines/S12_REBASE_NOTE.md`.
- **No rebase:** `baselines/S12_quote.tsv` left FROZEN (my change moved no captured column; absorbing Tab-1's
  base-price drift under Tab 2 would misattribute it). **⚠️ FLAG for Tab 1:** reconcile the S12 line-3 base/pre-partner
  stamp against your Round-3 base-price work in the final full-matrix; re-baseline S12 under Tab 1 if intended.
- The "contributing products are missing" banner on S12 is the pre-existing native **SC-3372** derived/contributing
  condition (IsDerived PBE, native element) — unrelated to hardware, present before this change.
- **Commit `173431a`** on uat — exactly the 4 owned files (explicit `git add`, never `-A`). Did NOT touch
  V21/ESD, Nir's `PartnerPricingService*` (left in their prior M state), other tabs' files, or the
  coord/scratch dirs in git.

## Prior rounds (hook-thinning) — DONE + quiescent
- R1 D-1/D-2 deletes (`ea51906`,`849fdf4`); R2 `COLAUpliftCalculator` (`23c6c4e`); R3 Regional
  (`0df19e7`); R4 `QLDescriptionCalculator` (`9383f8f`). (Hardware WIP thinning was finalized by Tab 3
  in the earlier hook-thinning round, commit `9a814b0` — that is the base I'm now design-fixing.)
