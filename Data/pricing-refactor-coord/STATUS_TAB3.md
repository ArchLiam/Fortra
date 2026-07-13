# STATUS — Tab 3

## 🚩 2026-07-09 SC-3384 (multi-currency configured pricing) — LIAM OWNS ALL WORKSTREAMS
Per owner directive: the entire pricing-engine RCA (SC-3384) is Liam's — the A(data)/B(config)/C(code)/D(net-channel)/
E(auto-add) load-share in `Jira/Defects/sc3384.../02_ROOT_CAUSE_AND_FIX_SPEC.md` (suggesting Marc=data, Nir=config) is
NOT the ownership; do not hand off. Authoritative design = "Currency Conversion for Pricebooks" (Marc-confirmed): per-currency
prices are pre-generated STATIC stored values, read directly at quote time (no runtime conversion). SC-3384 = that design applied
to list PBEs but never extended to the configured layer (ABA + tier data USD-only + currency-blind lookups).
- **C (Apex prehook, AttributeVolume currency-key):** ✅ DONE — committed `255f7c5`, 75/75 tests + 37/37 real-EUR-tier smoke.
  Matches the fix spec §5.4 exactly. Deployed to UAT; DATA-first (non-seeded non-USD lines reset-to-list until data seed).
- **E (PIAMBK auto-add):** ✅ DEPLOYED to UAT (2026-07-09) — **HEADS-UP TAB 1/2: `QuoteLineItemTrigger` changed** (added a
  before-insert step) + new class `QuoteLineItemCurrencyCorrectionHandler` (+`QuoteLineItemCurrencyCorrectionTest`, 3/3).
  Mechanism confirmed via UI repro: PCRs `14OWC0000027izF2AQ`/`14OWC0000022Eyb2AE` AutoAdd PIAMBK by Product2 Id (no
  PBE/currency in action) → managed RLM resolved the **USD** PBE `01uWC000005wsbUYAQ` on a EUR quote (seen in the /aura
  pricing log) → platform "price book entry currency code is different" on save. FIX = QLI before-insert guard re-points any
  PBE whose currency ≠ parent Quote's to the SAME Product2+Pricebook2+PSM sibling in the quote currency (EUR PBE
  `01uWC000005wzX8YAI`), BEFORE native validation (order-of-exec step4<step5). No-op when PBE already matches (0-delta happy
  path); leaves genuine data gaps to surface natively. ✅ **CONFIRMED LIVE** on quote 00781700 (0Q0WC000003JXMj0AO): Save
  succeeded; both auto-added PIAMBK maintenance lines persisted on the EUR PBE `01uWC000005wzX8YAI` (swapped from USD
  `01uWC000005wsbUYAQ`), all 3 QLIs EUR-consistent. Tests 3/3.
- **B (ABA decision-table currency key), A (per-currency data seed), D (Total-Price Net=0):** Liam's — pending.

### 2026-07-09 SMOKE (real UAT records, adversarially verified — `Data/sc3384/smoke_20260709.md`)
Ticket's 5 mechanisms collapse to 3 root causes. Verdicts:
- **L5 auto-add maint = ✅ PASS** (E fix): 0 mis-currencied QLIs across ~131k non-USD lines; PIAMBK has PBEs in all 10 currencies.
- **L4 attr-tier-storage = ⚠️ PARTIAL** (C code done, DATA-blocked): currency key live+correct, but `Attribute_Tier_Pricing_Storage__c` EUR rows exist for **1 SKU only** (37 EUR/37 USD on HRM-CLSAAS); CAD/GBP/AUD/JPY = **0 tier rows** → those lines now get NO tier (e.g. 1,075 CAD lines on that SKU). Needs A.
- **L1 tier-based + L2 server-discount + L3 attribute-based = ❌ FAIL** — ALL THREE run through ABA decision table `0lDa50000007BEuEAM` (currency-blind, no CurrencyIsoCode input) over **13,073/13,073 USD-only** AttributeBasedAdjustment rows. **Blast radius = 71,502 non-USD QLIs on 603 ABA products** (EUR 35,641/GBP 26,098/AUD 7,843/CAD 1,920). ~7% EUR overcharge or raw-USD-list leak or Net=0. **B (currency key) + A (data seed) MUST ship together** — key without data → list/0; data without key → non-deterministic USD match.
- Base list price = ✅ PASS (per-currency PBE ~100%). D (Net=0) observed on L2 GBP line (TotalPrice=0), rides the ABA path.
- Next live check (only genuine PASS-candidate): UI-reprice a EUR HRM-CLSAAS line → expect EUR tier 2,373.60 not USD 2,580.
  Clean test quote created: 00781712 (`0Q0WC000003JasT0AS`, EUR Draft, empty) via `scripts/apex/setupHrmClsaasEurRepro.apex`.

### 2026-07-09 Workstream B+A SCOPE (`Data/sc3384/workstream_BA_scope_20260709.md`) — 2 SHOWSTOPPERS, DO NOT BUILD YET
Root: L1/L2/L3 all resolve through native DecisionTable `Attribute_Based_Adjustment_Decision_Table` (0lDa50000007BEuEAM), currency-blind,
13,073/13,073 USD `AdjustmentType='Override'` (absolute price). B=add CurrencyIsoCode input; A=seed per-currency rows. **BUT adversarial verify refuted the easy path:**
1. **B likely NOT a PBE-mirror.** The ABA proc step is `actionType=AttributeDiscount` (BKM) with a FIXED param contract (no CurrencyIsoCode)
   + its own `AttributeAdjConditionsHash` match key (no currency). Adding a currency `<parameters>` block is probably INERT; and a `isRequired=true`
   7th DT column with no supplied currency → NO rows match → regresses EVEN USD to list/$0. Zero in-org precedent for AttributeDiscount forwarding currency.
   → Real fix likely needs Apex/generic-DT (Workstream C pattern), NOT the native column. **HARD GATE: Phase-0 sandbox proof before any A build.**
2. **A value-factor is AMBIGUOUS + contradicts live data.** Two EUR regimes live: ABA/PBE ratio = **0.9346** (CMDT/list), but existing EUR ATPS
   tiers (HRM) = **0.92** (runtime CurrencyType.ConversionRate). Uniform-0.9346 rule reproduces AAMP (1471.995) but NOT HRM (gives 2411.27 vs live 2373.60).
   Which factor is authoritative for net/tier = OPEN Finance/Marc decision; existing EUR ATPS data must be reconciled. **Escalate before seeding.**
Also: PAT tier-table OUT of scope (L1 goes via ABA not PAT); proc live=**v23** (repo stale v20/v22); 61 $0-USD-PBE products overlap Workstream D (don't seed $0);
dedup needs GearsetExternalId uniqueness check + handle pre-existing USD dup rows (AAMP has 2× identical 1575). Est 6–10 dev-days IF B is wireable; +3–5 if Apex fallback.

---


## 🚩 2026-07-09 OUT-OF-BAND (user-directed) — LIVE V21 CHANGED: 4 hardcoded-FX steps REMOVED (SC-3384)
Owner (Liam) neutralized then DELETED the 4 "Currency Conversion" steps (seq 38-41: NetUnitPrice/InputUnitPrice/
ItemNetTotalPrice/TotalLineAmount × hardcoded-FX ladder) from **active V21** in the canvas. **Proven 0-delta** (Tab-3
repriced EUR/USD/GBP/EUR-regional; before vs after = byte-identical, incl. a populated multi-line GBP quote). The FX
steps were inert — persisted net sources from the currency-aware per-currency PBE (ListPrice, seq 2). **HEADS-UP TO TAB 1:**
⚠️ **ACTIVE VERSION IS NOW V22, not V21** — the canvas activation promoted a new version: **V22 Active, V21 → Draft**
(V22 ≈ V21 minus the 4 FX steps; ~247 fewer lines = the 4 steps). This VIOLATES the "edit V21 in-place, no new versions"
guidance — flagging so Tab 1's full-matrix + any V21 canvas work (D-19) target the right version (V22). Full-matrix should
still be 0-delta but the FX steps are gone and the active version number changed.
NOT yet done: DT staleness (`Price_Book_Entry_Decision_Table_v2.isIncrementalSyncEnabled=false` — now the SOLE currency
source), Scenario-D divergence proof, derived-maint/renewal branch coverage, Workday Mule extendedAmount validation (deferred).
Runbook: `Data/pricing-refactor-scratch/round6/multicurrency_fx_removal_runbook.md`.

---


- **Updated:** 2026-07-08 (Tab 3) — COORD ROUND 4 (WAVE-3/4 TAIL — 0-delta gate returns)
- **MID-DEPLOY:** no — OUT-OF-BAND retirement DONE (2 destructive deploys: classes then CMDT), window released.
- **Branch:** uat
- **Quiescent:** YES — dead country-currency path retired + committed `4e5279b`. Safe for Tab 1 full matrix.

## OUT-OF-BAND (2026-07-08, user-directed) — retired dead country-currency path — committed `4e5279b`
Brainstorm on "merge the currency CMDTs" resolved to RETIRE, not merge (reader-map workflow `w5523i0ft`):
Country_Currency_Map__mdt's only reader = CurrencySelectionService = superseded zero-caller legacy (MultiCurrency SDD
A-005). Org-side MetadataComponentDependency: only the test depends on the service. So deleted the dead cluster —
CurrencySelectionService(+meta), CurrencySelectionServiceTest(+meta), Country_Currency_Map__mdt (object + 2 fields + 15
records) — from org + repo. This UNWINDS R4's D-15 extraction (`3a338ec`, dead code; unwinding is 0-delta). Live tables
untouched: Legal_Entity_Currency (the actual live currency-selection, via Active Fortra_Opportunity_LE_Currency_Validation),
Currency_Conversion_Formula (live admin bulk-PBE tool), Hardware_Attribute_Pricing (live, different domain).
DEFERRED (separate, owner-gated): delete the 2 Obsolete LE flows + the orphan Create-PBE flow; `Currency —` label prefix +
docs registry; FX dual-ISO field collapse (needs org-equality check).

## ROUND 4 RESULT ✅
- **Deploy** (D-15+A-6): via scoped `-x` manifest (the `-m CustomMetadata` wildcard first pulled Tab-2's uncommitted
  `Hardware_Attribute_Pricing__mdt` records → failed; re-scoped to my 15 records + object + 2 fields + 4 classes). Succeeded.
- **Tests 22/22**: CurrencySelectionServiceTest 3/3 (incl. `currencyMap_matchesLegacyHardcodedMap` = MDT reproduces the exact
  15 legacy entries), RegionalPricingCalculatorTest 4/4 (incl. A-6 null-multiplier test), RegionalServicesPricingPrehookTest 15/15.
- **Gate**: S9 + S10 reprice → **0-delta** vs baseline (25 cols).
- **D-10 delete**: `QuoteCurrencyChangeService_Fixed` + `_FixedTest` destructive-deleted (org 0 remaining, local removed). 0-delta (was orphan).
- **Commit** `3a338ec` — 26 files, own only (D-15 MDT+object+2 fields+15 records+service+test; A-6 calc+test; D-10 deletes). Explicit git add, NOT -A.

## ROUND 4 — D-15 + D-10 + A-6. Gate = 0-delta (Wave-2 discipline).
Files I own: `CurrencySelectionService`(+new Test), `QuoteCurrencyChangeService*`, `RegionalServicesPricingPrehook`,
`RegionalPricingCalculator`(+Test), new `Country_Currency_Map__mdt`.

### D-15 — CurrencySelectionService country→currency map → MDT (config extraction, behavior-preserving)
- New admin-editable **`Country_Currency_Map__mdt`** (fields `Country__c` Text100, `Currency_Code__c` Text3) +
  seed records = EXACT current hardcoded entries. Service Priority-2 now reads them via zero-SOQL `getAll()`;
  lookup semantics unchanged (exact `containsKey`/`get`).
- ⚠️ **Count note:** prompt said "14-country map" but the live code map has **15 entries** (3 non-EUR: US/CAD/AUD +
  **12** EUR: DE/FR/IT/ES/NL/BE/AT/IE/PT/FI/GR/LU). Seeded **15** to match the code EXACTLY — dropping one would
  drop a country = NOT 0-delta. Unit test `currencyMap_matchesLegacyHardcodedMap` pins MDT == the exact 15 legacy entries.
- Reach: `CurrencySelectionService` has **no callers in force-app** and is not in the reprice path → S9/S10 reprice
  trivially 0-delta; the MDT==map unit test is the real proof.

### A-6 — Regional Active + null `Multiplier__c` → skip (defensive, provably 0-delta)
- `RegionalPricingCalculator.getMultiplierForCountry` now coalesces a null map value → `DEFAULT_MULTIPLIER` (1.0),
  so the prehook's existing default-multiplier short-circuit SKIPS the line (leaves it untouched) instead of
  adjusting off a null. Reuses the tested skip path; only new behavior is contained-but-null → DEFAULT.
- **0 live rows** have a null Multiplier__c (verified prior round) → provably 0-delta. Unit test
  `getMultiplierForCountry_nullMultiplier_resolvesToDefault_A6`.

### D-10 — QuoteCurrencyChangeService_Fixed orphan
- **Verified wiring:** flow `Quote_Handle_Quote_Currency_Change` (**Draft/inactive**, org V1) invokes the WIRED
  `QuoteCurrencyChangeService` (a no-op: clones lines with UNCHANGED UnitPrice, does NOT set CurrencyIsoCode, no
  conversion). `QuoteCurrencyChangeService_Fixed` = the real converter (sets CurrencyIsoCode + re-prices from
  new-currency PBE) but is referenced **only by its own test** → genuine orphan dead code.
- **(a) DELETE** `QuoteCurrencyChangeService_Fixed` + `QuoteCurrencyChangeService_FixedTest` → 0-delta (unreferenced;
  behind nothing). _Fixed's converter logic is preserved in git history (pre-deletion commit) as the reference impl.
- **(b) FLIP = 🅲 ESCALATE (NOT done):** whether the wired no-op should be replaced with real currency conversion
  (and its Draft flow activated) is a BEHAVIORAL/business design call (OQ-2). I did NOT flip or activate anything.
  Question for the team: is Quote currency-change meant to convert line prices (per _Fixed), or is the no-op intentional?
  Today it's inert (Draft flow), so deleting the orphan changes nothing at runtime.

### Plan
1. Deploy D-15 + A-6 additive set (NoTestRun) → tests (CurrencySelectionServiceTest, RegionalPricingCalculatorTest, RegionalServicesPricingPrehookTest).
2. Reprice S9 + S10 → 0-delta gate.
3. Destructive-delete _Fixed + _FixedTest (D-10a).
4. Commit own files only (NEVER git add -A). Mark quiescent. D-10b flip stays escalated.

---
## Prior rounds — history
- R3 design-compliance: Fix B (Regional effective-dating) shipped `8d1ec19`; A & C escalated. Out-of-band: removed Liam's
  `Stamp_Sales_Price` flow (Marc "Sales Price not landing on renewals/amendments" incident; Jira ticket drafted).
- R1/R2 hook-thinning (Cancel/AttrVolume/Hardware/QLDesc) + R4-prev test-hardening — all committed, 0-delta.
