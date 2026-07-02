# SC-3350 — COLA Renewal Pricing: Code/Tests + Coverage (CURRENT TRUTH)

**Author:** research subagent · **Date:** 2026-06-10 (~17:10 UTC) · **Org:** FortraUAT (read-only)
**Scope of this stream:** Analyze the CURRENT `COLAUpliftTest.cls` (2494 lines, doubled today), diff vs the
cola-renewal-review snapshot, pull LIVE coverage, and rule on the 75% prod gate.

**Headline:** Marc's afternoon rework MATERIALLY changed the coverage picture. The brief's "NO-GO on coverage"
(Handler 42% / Prehook 3% / ACQH 0% / org 39%) is **STALE**. Current TRUE per-class coverage clears 75% on all
four COLA classes. The new tests are **genuinely behavioral**, not tautologies. The remaining blocker is org-wide
coverage (44%, separate concern) and the still-thin AssetContractQueryHelper aggregate read (a stale-metadata
artifact — true value is 86%).

---

## 0. CRITICAL METHODOLOGY NOTE — coverage was mid-recompute; do NOT trust a single aggregate read

While researching, Marc (or a CI job) was **actively running full-org tests** (runs at 16:40, 16:46, 16:51,
16:58→17:06 UTC). `ApexCodeCoverageAggregate` is rewritten transactionally during a run, so I caught it in
three different states within ~10 minutes:

| Read time | Handler | Prehook | ACQH (aggregate) | QLDescGen |
|---|---|---|---|---|
| First read (~16:55) | 168/183 = 91.8% | **12/530 = 2.3%** | 8/43 = 18.6% | 208/260 = 80.0% |
| Mid-recompute (~17:00) | **0/183 = 0.0%** | **0/530 = 0.0%** | 0/43 = 0.0% | 208/260 = 80.0% |
| **After 17:06:10 run done (STABLE)** | **168/183 = 91.8%** | **398/530 = 75.1%** | 8/43 = 18.6% | 208/260 = 80.0% |

The 2.3% / 0% prehook reads were **transient artifacts of an in-flight recompute**, NOT the truth. I waited for
the 17:06:10 run to finish (`ApexTestRunResult` Status=Completed, 50 methods, 0 failed) before taking the stable read.

**The most reliable measurement is the UNION of per-method `ApexCodeCoverage.Coverage` line sets** (these reflect the
latest run's attribution and don't suffer the aggregate's lag). I computed that union for all four classes — see §3.

---

## 1. What Marc changed today (deltas vs the 08:13 brief)

### 1a. Class edit timestamps (live `ApexClass` tooling query)
| Class | LastModifiedDate (UTC) | By |
|---|---|---|
| AssetContractQueryHelper | 2026-06-10 **14:00:37** | Marc DeBrey |
| **AssetContractQueryHelperTest** (NEW) | 2026-06-10 **14:00:38** | Marc DeBrey |
| QLDescriptionGeneratorPrehook | 2026-06-10 14:41:27 | Marc DeBrey |
| QLDescriptionGeneratorPrehookTest | 2026-06-10 14:49:18 | Marc DeBrey |
| COLAUpliftHandler | 2026-06-10 16:29:57 | Marc DeBrey |
| COLAUpliftPrehook | 2026-06-10 16:51:20 | Marc DeBrey |
| **COLAUpliftTest** | 2026-06-10 **16:58:15** | Marc DeBrey |

**NEW finding the brief missed:** a dedicated test class **`AssetContractQueryHelperTest`** was created today at
14:00:38. It is NOT in the sc3350 retrieve (only `AssetContractQueryHelper.cls` was pulled, not its test). It is the
reason ACQH is no longer 0%.

### 1b. COLAUpliftTest grew from 31 → 51 test methods (+20), 0 removed
Local sc3350 retrieve body is **byte-identical** to the deployed live `Body` (diff = empty), so analysis is on
current truth. Diff of method names (`comm -23 new old`):

**20 methods added today** (none removed):
```
Handler / populateCOLAFields path (6):
  testHandleBeforeInsert_RenewalCMDTLookup
  testHandleBeforeInsert_RenewalNoCMDTMatch
  testPopulateCOLAFields_Tier2ContractOverride
  testBuildContractOverrideMap_ValidityMatrix
  testHandleBeforeUpdate_RecalculatesOnPercentRaise
  testHandleBeforeUpdate_OutyearDefaultThenOverride
Prehook path (14):
  testPrehook_GetCOLARulesMap
  testPrehook_BuildOverrideMap_ValidityMatrix
  testPrehook_BuildLineItemUpdates_CoreLoop
  testPrehook_BuildLineItemUpdates_TiersAndSkips
  testPrehook_BuildLineItemUpdates_EmptyDataPathSkipped
  testPrehook_ProcessLineItems_InvalidIdAndMyCapFallback
  testPrehook_ProcessMyCAPEligibility_RealPath
  testPrehook_ProcessMyCAPEligibility_NonOverriddenQualifying
  testPrehook_ProcessMyCAPEligibility_EmptyAndNonRenewal
  testPrehook_MyCAPFlagApplier_Execute
  testPrehook_IsOrderTransaction_OrderVsQuote
  testPrehook_BuildExplainerText
  testPrehook_TagHelpers
  testPrehook_HelperEdgeCases
```

### 1c. The PREHOOK was refactored for testability — exactly the brief's §7 recommendation
The live `COLAUpliftPrehook.cls` now has **14 `@TestVisible private` seams** (grep count = 14), including the
parsed-payload overloads the new tests drive:
- `processLineItems(List<Object> rawLineItems, ...)` — L270 (vs the live-context `processLineItems(String ctxInstanceId,...)` L179)
- `buildLineItemUpdates(...)` L349, `buildOverrideMap(List<SObject>)` L719, `getContractOverrides(Set<Id>)` L673
- `processMyCAPEligibility(List<Object> rawLineItems,...)` L890, `getCOLARulesMap()` L637
- `isOrderTransaction(List<Object>)` L159, `buildExplainerText(...)` L482
- tag helpers `extractLineItemData` L615, `getStringFromTag` L765, `getDecimalFromTag` L771, `getBooleanFromTag` L787

This is the "extract the pure pricing/override math into `@TestVisible static` methods, mirror the
`QLDescriptionGeneratorPrehookTest` pattern" prereq the brief called out. **Marc did it.**

---

## 2. Are the +20 tests REAL or tautologies? → REAL (behavioral), with the formula-mirror caveat

The brief flagged ~14/31 old tests as pure tautologies (re-implement the formula inline, never call prod code).
The 20 NEW tests are different in kind: **every one calls production code and asserts on production OUTPUT.**

### 2a. Handler/populate tests genuinely exercise the defect-#1 insert path
- `testHandleBeforeInsert_RenewalCMDTLookup` (L1327): builds a real Quote→QuoteAction(Renew)→SourceAsset graph,
  calls **`COLAUpliftHandler.handleBeforeInsert(...)`** (the real entry), asserts `COLA_Source__c='CMDT Lookup'`,
  `UnitPrice == assetPrice*(1+cmdtDefault/100)`, `Pre_COLA_Price__c`, etc. This is the renewal-insert happy path the
  brief said was **0%-covered**. Now covered.
- `testPopulateCOLAFields_Tier2ContractOverride` (L1432): drives **`COLAUpliftHandler.populateCOLAFields(items, qaMap,
  overrideMap)`** (the `@TestVisible` seam) with a real Activated Contract override (`PricingPrehookTestFixtures.
  assetWithActivatedContractOverride`), asserts `'Contract Override'` wins and the override-% math.
- `testBuildContractOverrideMap_ValidityMatrix` (L1515): calls **`COLAUpliftHandler.buildContractOverrideMap(...)`**
  across null/future/past persist + null-% → asserts which entries survive. Real branch coverage of the validity logic.
- `testHandleBeforeUpdate_RecalculatesOnPercentRaise` (L1569) and `_OutyearDefaultThenOverride` (L1637): call
  **`handleBeforeUpdate(new, oldMap)`** and assert recompute / Line-Override promotion / outyear defaulting.

**Caveat (honest):** the *expected* values are still computed by mirroring the formula inline
(`assetPrice*(1+cmdtDefault/100)`). But because the **actual** side is the production method's output (not a re-impl),
these are legitimate behavioral assertions, not the old self-asserting tautologies. The formula-mirror only risks
masking a *wrong-but-consistent* formula; it does NOT make the test a no-op.

### 2b. Prehook tests exercise the real renewal COLA loop (the brief's "all of execute()→processLineItems() = 0%")
- `testPrehook_BuildLineItemUpdates_CoreLoop` (L1861): inserts a real renewal QLI graph, re-queries with the
  prehook's SOQL shape, then calls **`prehook.processLineItems(rawItems, rulesMap, mycap)`** (parsed-payload overload
  → parse → renewal SOQL → getContractOverrides → loop) AND **`prehook.buildLineItemUpdates(...)`**. Asserts
  `COLACalculatedPrice__c == assetPrice*(1+cmdt/100)`, `COLA_Source__c`, `Pre_COLA_Price__c`, and the Contract-Override
  tier (9%). This is the **InputUnitPrice-feeding price path** that was 0%.
- `testPrehook_BuildLineItemUpdates_TiersAndSkips` (L2173): three renewal lines → Line-Override / MyCAP-Default /
  zero-price-skip → asserts each source resolves correctly + the no-valid-price skip. Also exercises
  `getContractOverrides` empty/null/live-SOQL.
- `testPrehook_ProcessMyCAPEligibility_RealPath` (L1974): drives the MyCAP eligibility branch, **enqueues the real
  `MyCAPFlagApplier` Queueable inside start/stopTest**, and asserts `Quote.Mycap__c` flips true (real DML side effect).
- `testPrehook_MyCAPFlagApplier_Execute` (L2049): enqueues the Queueable and asserts the flag-true/flag-false DML.
- Helper tests (`testPrehook_TagHelpers` L2136, `_HelperEdgeCases` L2335, `_BuildExplainerText` L2109,
  `_IsOrderTransaction_OrderVsQuote` L2078, `_GetCOLARulesMap` L1753, `_BuildOverrideMap_ValidityMatrix` L1787):
  call the `@TestVisible` helpers with hand-built payloads and assert exact outputs.

**Per-method coverage proves these run real prehook code** (post-17:06 run, `ApexCodeCoverage` per-method):
```
testPrehook_ProcessLineItems_InvalidIdAndMyCapFallback   covers 231 prehook lines
testPrehook_ProcessMyCAPEligibility_NonOverriddenQualifying  206
testPrehook_ProcessMyCAPEligibility_RealPath                 199
testPrehook_BuildLineItemUpdates_CoreLoop                    165
testPrehook_BuildLineItemUpdates_TiersAndSkips               140
testPrehook_BuildLineItemUpdates_EmptyDataPathSkipped         99
...
```
A tautology cannot register 231 covered prod lines. These are real.

### 2c. All 51 methods PASS (live run 16:51:39, Completed, 0 failed; re-confirmed in the 17:06 run)
`ApexTestResult` for the run: 51 COLAUpliftTest methods, **0 non-pass**, all 14 `testPrehook_*` = Pass.

---

## 3. CURRENT coverage — STABLE reading (after 17:06:10 full-org run)

### 3a. Aggregate (`ApexCodeCoverageAggregate`) — beware ACQH is stale here
SOQL (tooling):
`SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate WHERE ApexClassOrTrigger.Name IN (...)`
```
COLAUpliftHandler                168/183 =  91.8%   PASS
COLAUpliftPrehook                398/530 =  75.1%   PASS (exactly clears)
QLDescriptionGeneratorPrehook    208/260 =  80.0%   PASS
AssetContractQueryHelper           8/ 43 =  18.6%   <-- STALE; see 3b
4-class combined (aggregate)     782/1016 = 77.0%
```

### 3b. TRUE union coverage (computed from per-method `ApexCodeCoverage.Coverage` line sets) — authoritative
The ACQH aggregate (8/43) is provably stale: a single method `testBuildResults_ActivatedContractWithOverride` alone
covers 17 lines (> 8). Union of all per-method covered-line sets:
```
COLAUpliftHandler              168/183 =  91.8%   PASS   uncovered={43,133,134,135,183,200,281,286,292,362-364,390,393,412}
COLAUpliftPrehook              398/530 =  75.1%   PASS   132 uncovered (live-context entry, see §4)
QLDescriptionGeneratorPrehook  208/260 =  80.0%   PASS
AssetContractQueryHelper        37/ 43 =  86.0%   PASS   uncovered={46,49,52,57,58,64}  (NOT 18.6%)
```
ACQH covered by the new `AssetContractQueryHelperTest` (`testBuildResults_*`=17/11/5, `testQueryAssetContracts_*`=10/6,
`testCollectContractIds`=10) plus COLAUpliftTest's handler/prehook tests touching the live ACR query (8 each).

### 3c. Org-wide coverage (`ApexOrgWideCoverage`) = **44%**
Below the 75% org-wide prod gate — but this is the WHOLE ORG, dominated by other untested classes; not a COLA defect.

---

## 4. What the 132 uncovered prehook lines ARE (and why they're acceptable)

Grouping the uncovered prehook lines into ranges, the bulk are the **un-mockable live-context wrappers**:
- `execute(RevSignaling.TransactionRequest)` L31-101 — the Revenue Cloud orchestration entry; needs a real
  `RevSignaling.TransactionRequest` with a live ctxInstanceId.
- `isOrderTransaction(String ctxInstanceId)` L113-145 — calls `new Context.IndustriesContext().queryTags(...)`.
- the `String`-overload `processLineItems(ctxInstanceId,...)` L179-251 and `processMyCAPEligibility(ctxInstanceId,...)`
  — both call `Context.IndustriesContext().queryTags` / `updateContextAttributes`, which **cannot be fabricated in a
  unit test** (the exact constraint the brief named in §7).
- scattered late lines (1008-1028, 1123-1162) = the context-write/`submitContextUpdates` paths.

Marc's pattern: every line-of-business algorithm is extracted into a `@TestVisible` parsed-payload seam that the new
tests cover; only the thin live-context shims (`queryTags` / `updateContextAttributes` callers and the `execute`
entry) remain uncovered. This is the maximum achievable without an integration-level pricing run, and it is enough to
clear 75% on the class.

---

## 5. VERDICT on the 75% prod gate

**Per-class gate (each Apex class must be ≥75% for the classes IN a deployment): CLEARED for all four COLA classes**
(Handler 91.8%, Prehook 75.1%, QLDescGen 80.0%, ACQH 86.0% true / 18.6% stale-aggregate).

**Caveats / residual risk:**
1. **Prehook is at 75.1% — a 1-line regression drops it below the gate.** Razor-thin. Any future prehook edit must
   re-run coverage. Treat 75.1% as "passing but fragile," not comfortable.
2. **The ACQH aggregate still reads 18.6%.** A naive `sf project deploy` gate-check that reads the *aggregate*
   (not the per-method union) could FALSE-FAIL the deploy until a fresh full-org run repopulates it. Force a clean
   `RunSpecifiedTests`/`RunLocalTests` pass at deploy time so the aggregate reflects reality (86%).
3. **Org-wide is 44%** (`ApexOrgWideCoverage`) — for a *production* deploy of these classes, Salesforce evaluates
   org-wide ≥75% on the destination org, not UAT's 44%. UAT's org-wide number is not the prod gate, but it signals
   the broader org is under-covered; verify prod org-wide before promoting.
4. **Coverage was being recomputed live by Marc's runs.** Anyone re-checking must wait for the in-flight
   `ApexTestRunResult` to reach Completed before trusting an aggregate read (I caught it at 2.3%, 0%, and 75.1% within
   10 min). Prefer the per-method union.
5. **Behavioral-vs-tautology caveat:** the new tests assert production OUTPUT (good), but still compute EXPECTED
   values by mirroring the formula inline. They will not catch a *wrong-but-internally-consistent* formula
   (e.g., the §3/§4 brief bugs B1/B6/regional). They prove the code RUNS and produces self-consistent numbers; they
   do NOT independently validate the COLA business math against the spreadsheet. Peer test must add at least one
   golden-value assertion tied to the design spreadsheet, not the formula.

**Bottom line:** On the narrow question the brief raised ("coverage is a NO-GO blocker"), **that blocker is now
CLEARED** — every COLA class individually exceeds 75% (true union). The coverage NO-GO from the 08:13 brief is STALE.
What remains is *quality* risk (formula-mirror tests, the un-mockable live-context paths uncovered, thin 75.1% prehook
margin) and the *org-wide 44%* / *stale-ACQH-aggregate* deploy-mechanics caveats — not a per-class coverage failure.

---

## 6. Evidence index (SOQL / files)

- Coverage aggregate (stable): `ApexCodeCoverageAggregate` WHERE Name IN (4 classes), taken after
  `ApexTestRunResult` 2026-06-10T17:06:10 Completed (50 methods, 0 failed).
- True union: `SELECT Coverage FROM ApexCodeCoverage WHERE ApexClassOrTrigger.Name='<cls>'`, union of
  `coveredLines` / `uncoveredLines`.
- Org-wide: `SELECT PercentCovered FROM ApexOrgWideCoverage` = 44.
- Test outcomes: `ApexTestResult` for run `05mWC000001D1wzYAC` (16:51:39) = 51 COLAUpliftTest methods, 0 non-pass.
- Class edit times: `ApexClass` tooling (see §1a).
- Test body identity: `diff` of live `ApexClass.Body` vs `Data/sc3350/live/unpackaged/classes/COLAUpliftTest.cls` = empty.
- Method diff: `comm -23` of current vs `Data/cola-renewal-review/live/classes/COLAUpliftTest.cls` = +20 / -0.
- Prehook `@TestVisible` seams: grep count 14 in `Data/sc3350/live/unpackaged/classes/COLAUpliftPrehook.cls`.
- New test class not in retrieve: `AssetContractQueryHelperTest` (live only; created 14:00:38).
