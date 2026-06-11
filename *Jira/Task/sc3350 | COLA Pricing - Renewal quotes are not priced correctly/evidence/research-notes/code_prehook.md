# SC-3350 — COLAUpliftPrehook.cls: CURRENT-state code analysis (vs 08:13 brief)

**Date:** 2026-06-10 (research run AFTER Marc's 16:51Z edit)
**Org:** FortraUAT (read-only)
**Files compared:**
- NEW (current): `/Users/liamjeong/Documents/Code/Fortra/Data/sc3350/live/unpackaged/classes/COLAUpliftPrehook.cls` — **1276 lines**
- OLD (brief baseline): `/Users/liamjeong/Documents/Code/Fortra/Data/cola-renewal-review/live/classes/COLAUpliftPrehook.cls` — **1127 lines**

## Live org metadata (tooling API, confirmed)
SOQL (`--use-tooling-api`):
`SELECT Id,Name,LengthWithoutComments,LastModifiedDate,LastModifiedBy.Name,ApiVersion FROM ApexClass WHERE Name IN (...)`

| Class | Id | LastModified (UTC) | By | LenNoComments | ApiVer |
|---|---|---|---|---|---|
| COLAUpliftPrehook | 01pWC000001wNGbYAM | **2026-06-10T16:51:20Z** | Marc DeBrey | 39956 | 65 |
| COLAUpliftTest | 01pWC000001wN3jYAE | 2026-06-10T16:51:20Z | Marc DeBrey | 93445 | 64 |
| COLAUpliftHandler | 01pWC000001wN3iYAE | 2026-06-10T16:29:57Z | Marc DeBrey | 13066 | 59 |
| AssetContractQueryHelper | 01pWC000001wN3hYAE | 2026-06-10T14:00:37Z | Marc DeBrey | 3063 | 66 |
| QLDescriptionGeneratorPrehook | 01pWC000002LYbrYAG | 2026-06-10T14:41:27Z | Marc DeBrey | 16506 | 65 |

The local `sc3350/live/unpackaged` copy matches the 16:51Z live edit (the prehook + test share that timestamp).

## Diff summary (the headline finding)
Full diff: `/tmp/cola_codeonly_diff.txt`. After stripping comments/blank lines: 122 removed, 168 added.

**The +325/-176 rework is a pure extract-method *testability* refactor. It changes ZERO pricing behavior.** Every added non-comment line is one of: (a) a new `@TestVisible` method signature, (b) a delegating call to that new overload, or (c) the *verbatim* original code body relocated into the new method. No formula, no target field, no tier order, no gate, no fail-silent behavior was altered.

Evidence the change is structural-only:
- `@TestVisible` seam count: **OLD 5 → NEW 14** (+9 new test seams).
- Three monolithic methods were each split into a thin live-API wrapper + a pure `@TestVisible` seam that takes the already-parsed payload:
  1. `isOrderTransaction(String)` → now delegates the dataPath[0]/"801" peek to new `@TestVisible isOrderTransaction(List<Object>)` (NEW L158-171).
  2. `processLineItems(String,...)` → split into 3: the live wrapper (unwrap + submit) + new `@TestVisible processLineItems(List<Object>,...)` (parse→SOQL→override, NEW L269-333) + new `@TestVisible buildLineItemUpdates(...)` (the pure tier/price core loop, NEW L348-472).
  3. `getContractOverrides(Set<Id>)` → SOQL stays in wrapper; validity-matrix loop extracted to new `@TestVisible buildOverrideMap(List<SObject>)` (NEW L718-758).
  4. `processMyCAPEligibility(String,...)` → split into live wrapper (NEW L857-873) + new `@TestVisible processMyCAPEligibility(List<Object>,...)` (NEW L889-1128, the real evaluation).
- Verified byte-identity of the relocated logic:
  - Contract-override / CMDT-fallback loop: `diff` of OLD inline L609-641 vs NEW `buildOverrideMap` L725-757 → **identical** (only relocated).
  - `buildCOLAContextUpdate` (MyCAP-path price calc): only diff is one comment em-dash → `--`. Logic unchanged.
  - `execute()` fail-silent catch: **byte-identical** OLD L90-99 vs NEW L90-99.

---

## Answers to the 5 task questions

### (1) Prehook's current role — does it still claim to "replace" the trigger? Both still live?
**YES to both — UNCHANGED from the brief.**
- Header comment NEW L1-20 still reads: *"This prehook replaces the trigger-based COLAUpliftHandler for Revenue Cloud integration."* `@version 1.0`, `@date January 2026` — header not even bumped.
- The trigger is **still Active**: `QuoteLineItemTrigger` Status=`Active`, LastModified 2026-06-10T00:05:44Z (tooling `ApexTrigger`). `COLAUpliftHandler` was itself re-edited at 16:29Z and is at **91.8%** coverage (168/183). So the "replaces" claim is still aspirational; **both engines remain live** (split-brain B7 from the brief persists). Confidence: HIGH.

### (2) execute() → processLineItems(): what formula writes COLA price, to InputUnitPrice or NetUnitPrice?
**UNCHANGED. The prehook does NOT write InputUnitPrice or NetUnitPrice directly.** It writes the COLA price to the **context attribute `COLACalculatedPrice__c`**; the pricing procedure (V10 Path A per brief §4) is what maps `COLACalculatedPrice__c → InputUnitPrice`.
- Formula (NEW L454, was OLD L358, identical): `Decimal colaAdjustedPrice = assetPrice * (1 + (colaPercent / 100));` then `.setScale(2, HALF_UP)`. Base = `QuoteAction.SourceAsset.Price` (gross, no discounts — Path A semantics, brief §4).
- Write: `buildItemUpdate(...)` (NEW L507-577) emits attribute `COLACalculatedPrice__c = colaPrice` (NEW L540-543) plus `Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Applied_Date__c`, optional `COLA_Solution_Category__c`. `COLA_Uplift_Percent__c`/`COLAUpliftPercent__c` are still **deliberately excluded** ("poisons the batch", synced by the handler instead — NEW L545-548). `COLAExplainer__c`/`COLAApplied__c` still excluded (no hydration mapping).
- `grep InputUnitPrice|NetUnitPrice` over the NEW file = **0 hits**. Confirmed the prehook never touches either field name. Confidence: HIGH.
- The MyCAP-path writer `buildCOLAContextUpdate` (NEW L1223-1276) also writes `COLACalculatedPrice__c` (compounded across `PricingTermCount`) — unchanged.

### (3) Did Marc change the fail-silent behavior (B2: returns SUCCESS on every exception)?
**NO. B2 is UNCHANGED and still live.** `execute()` catch (NEW L90-96) is byte-identical to OLD: sets `response.status = SUCCESS` with message "COLA pricing completed with warnings" on any exception. Also unchanged:
- `processLineItems` wrapper catch swallows to debug, returns processedCount-so-far (NEW L247-249).
- `getContractOverrides` still swallows `QueryException` → empty map → silent CMDT degrade (NEW L696-699). (This is the same fail-silent-to-CMDT degrade the brief flagged.)
- `submitContextUpdates` still swallows "not in updatable state" (NEW L600-606).
- `processMyCAPEligibility` (both overloads) still catch-all → return 0.

The new `@TestVisible` seams **preserve** the swallow contract — Marc's seam doc-comments explicitly say so (e.g. NEW L120-124, L191-194, L682-687: *"the swallow-and-continue is preserved"*). So the refactor makes the fail-silent paths *testable* but does not remove them. Confidence: HIGH.

### (4) Contract-override + CMDT fallback path
**Logic UNCHANGED; only relocated for testability.**
- Tier hierarchy (NEW `buildLineItemUpdates` L382-432): Tier1 Line Override → Tier2 Contract Override → Tier3 CMDT Lookup. Identical ordering and the shared predicate `COLAUpliftHandler.isManualLineOverride(lineOverridePercent, cmdtDefault, null, contractOverridePct)` (NEW L416-417). That static still exists in the handler (verified, sig at `COLAUpliftHandler.cls:224 public static Boolean isManualLineOverride(Decimal pct, Decimal cmdtDefaultPct, Decimal mycapDefaultPct, Decimal contractPct)`).
- Contract-override resolution: `getContractOverrides` (NEW L672-702) runs the live `AssetContractRelationship` SOQL (Contract.Status='Activated'), then delegates the validity matrix to new `@TestVisible buildOverrideMap` (NEW L718-758). Validity rules unchanged: skip null override %, null persist-until = valid (one-time), future persist = valid, past persist = excluded, first ACR per Asset wins (B5 "one-time never consumed" and B1 multi-asset-per-contract collapse both still present — keyed per-Asset in the prehook, so the prehook is *not* affected by B1, same as brief).
- CMDT fallback: `getCOLARulesMap()` (NEW L636-665) unchanged — active rules by `Solution_Category__c` with effective-date gating. Confidence: HIGH.

### (5) The big +325 — what new capability/fix did Marc add? Be specific.
**No new runtime capability. The +325 is the testability refactor + its doc comments.** Specifically Marc added:
- 5 new `@TestVisible` parsed-payload seams (the 4 method splits above + `buildLineItemUpdates`), each with a long explanatory doc-comment block (these comments are most of the +325 line count).
- Made several pre-existing private helpers `@TestVisible` (`getStringFromTag`/`getDecimalFromTag`/`getBooleanFromTag`/`extractLineItemData`) so unit tests can drive them. Seam count 5→14.
- The companion test class `COLAUpliftTest` ~doubled: **1297 → 2494 lines**.

**The measurable payoff is coverage, not behavior:**
- `COLAUpliftPrehook` coverage **3% (brief) → 75.1% live now** (398 covered / 132 uncovered, `ApexCodeCoverageAggregate`). This crosses the 75% prod gate for this one class.
- This directly addresses the brief's §7 finding that the prehook was "untestable as written (needs a Context.IndustriesContext that can't be fabricated)" and the recommended "extract pure math into @TestVisible static methods." Marc did exactly that.

---

## DELTAS vs the 08:13 brief
1. **Prehook coverage 3% → 75.1%** (the single biggest change today). Brief §7 is stale on this number.
2. **@TestVisible seams 5 → 14**; test class 1297 → 2494 lines. The prehook is now largely unit-testable (brief called it "untestable as written").
3. **AssetContractQueryHelper now 18.6%** (8/43) — was "0%" in brief §7 (it was re-edited 14:00Z).
4. **COLAUpliftHandler now 91.8%** (168/183) — brief said "42%". Big jump (handler re-edited 16:29Z, separate stream).
5. **Pricing behavior: NO CHANGE.** Formula, `COLACalculatedPrice__c` target, tier order, contract/CMDT fallback, MyCAP compounding, B2 fail-silent, B5/B7 — all identical to the brief baseline. The brief's defect/bug analysis of the prehook remains valid against the current code.
6. Both engines (prehook + `QuoteLineItterTrigger`) **still live** — unchanged.

## Open / needs-trace
- The brief's defect #1 root cause is on the **handler/headless-renewal** path, not the prehook; the prehook refactor does not touch that. Whether the 16:29Z handler edit changed the `QuoteActionId.isEmpty()` early-return needs the handler stream to confirm (out of scope here).
- Whether the 75.1% prehook coverage comes from *behavioral* assertions or re-tautologies needs a read of the doubled `COLAUpliftTest` (out of scope for this stream).
- Whether the prehook is currently **registered/active** in the pricing procedure waterfall (V10) — coverage proves the class compiles+executes in tests, not that it's wired into the live reprice. (Brief §4 says it is, via `COLAUpliftonRenewal`.) Not re-verified here.
