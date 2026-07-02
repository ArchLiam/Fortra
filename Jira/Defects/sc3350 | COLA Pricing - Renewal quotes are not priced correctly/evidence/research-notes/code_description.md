# SC-3350 — Defect #2 (Line Item Description) — CURRENT-truth code analysis of QLDescriptionGeneratorPrehook

**Date:** 2026-06-10. **Org:** FortraUAT (read-only). **Analyst task:** verify CURRENT state vs the 08:13 UTC brief and flag deltas from Marc DeBrey's same-day re-edits.

**Headline:** Today's edit to `QLDescriptionGeneratorPrehook` (live `LastModifiedDate=2026-06-10T14:41:27Z`, Marc DeBrey) is a **pure testability/coverage refactor**. It extracts three pure-logic methods out of try/catch blocks and adds `@TestVisible`; it explicitly documents that the swallow-and-continue contract is "**preserved byte-for-byte**." **No behavior changed.** The prehook still only fires during a pricing-procedure reprice, so renewals (which don't reprice) still get NO description. **Defect #2 is NOT addressed by today's edit.**

---

## 0. Provenance — the disk file IS the live org body (verified, not stale)

| Artifact | Evidence |
|---|---|
| Live ApexClass `QLDescriptionGeneratorPrehook` | Id `01pWC000002LYbrYAG`, ApiVersion 65, `LengthWithoutComments=16506`, `LastModifiedDate=2026-06-10T14:41:27.000+0000`, `LastModifiedBy=Marc DeBrey` (tooling SOQL on ApexClass) |
| CURRENT disk file | `/Users/liamjeong/Documents/Code/Fortra/Data/sc3350/live/unpackaged/classes/QLDescriptionGeneratorPrehook.cls`, 730 lines, mtime `Jun 10 16:54` |
| OLD comparison file | `/Users/liamjeong/Documents/Code/Fortra/Data/cola-renewal-review/live/classes/QLDescriptionGeneratorPrehook.cls`, 656 lines, mtime `Jun 9 20:59` |
| **Disk == live org** | Pulled live `Body` via tooling API to `/tmp/live_QLDesc.cls` (731 lines incl. trailing newline) and `diff` against the disk file → **IDENTICAL**. My line-cited analysis of the disk file is therefore authoritative for the live org. |

SOQL used:
```
sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Id, Name, ApiVersion, LengthWithoutComments, LastModifiedDate, LastModifiedBy.Name FROM ApexClass WHERE Name='QLDescriptionGeneratorPrehook'"
sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Body FROM ApexClass WHERE Name='QLDescriptionGeneratorPrehook'" --json   # → /tmp/live_QLDesc.cls
diff /tmp/live_QLDesc.cls <disk file>   # IDENTICAL
```

The COLA-class re-edit timeline the prompt cited is confirmed in the org:
```
AssetContractQueryHelper          2026-06-10T14:00:37Z  Marc DeBrey
QLDescriptionGeneratorPrehook     2026-06-10T14:41:27Z  Marc DeBrey   <-- this file
QLDescriptionGeneratorPrehookTest 2026-06-10T14:49:18Z  Marc DeBrey   <-- test bumped 8 min later
COLAUpliftHandler                 2026-06-10T16:29:57Z  Marc DeBrey
COLAUpliftPrehook                 2026-06-10T16:51:20Z  Marc DeBrey
COLAUpliftTest                    2026-06-10T16:51:20Z  Marc DeBrey
```
Note the prompt said the prehook test was at 14:41Z; the live class is 14:41:27Z and its **test** is 14:49:18Z (8 minutes later). Minor delta, same author/window.

---

## 1. What the +192/-118 today actually is (exact diff)

`diff -u <OLD 656-line> <CURRENT 730-line>` (full diff captured in this research session). Every hunk is a **refactor-for-testability**, not a behavior change. Three changes:

### (a) `execute()` Step-4 loop extracted → `buildContextUpdates(...)`
The inline `for (Id lineId : attrsByLineId.keySet()) {...}` loop (OLD lines ~230-249) is replaced by a single call:
```apex
List<Map<String, Object>> contextUpdates =
    buildContextUpdates(attrsByLineId, dataPathByLineId, productNameByLineId);
```
The extracted method (`QLDescriptionGeneratorPrehook.cls:618-642`, `@TestVisible private`) contains the **identical** loop body — same defensive `dataPath == null` skip, same `buildDescription(...)`, same `descriptionText == null` skip, same `buildContextUpdate(...)` add. Pure move.

### (b) `queryConfiguredAttributes` split into query + `parseConfiguredAttributes(Map)`
OLD: one method did `ctx.queryTags(...)` AND inline parsing, all inside one try/catch.
CURRENT: `queryConfiguredAttributes` (`:277-296`) keeps only the live `queryTags` call inside the try/catch and delegates parsing to a new pure `@TestVisible private Map<Id,Map<String,String>> parseConfiguredAttributes(Map apiResponse)` (`:309-382`). The parse logic (queryResult/flat-shape handling, tagValue-vs-flat, ParentReference vs dataPath-parent, Attribute vs AttributeKeyName fallback, `Id.valueOf` guard) is moved byte-identical. A NOTE comment (`:285-289`) states the swallow-and-continue contract "is preserved byte-for-byte."

### (c) `queryLineItemDataPaths` split into query + `parseLineItemDataPaths(Map)`
Same pattern as (b). `queryLineItemDataPaths` (`:498-517`) keeps the live `queryTags` inside try/catch; new pure `@TestVisible private Map<Id,List<Object>> parseLineItemDataPaths(Map apiResponse)` (`:528-572`) holds the moved parse logic. NOTE comment `:506-510` again asserts byte-for-byte preservation.

### Plus: doc-only NOTE comments
- `queryProductNames` (`:589-591`): a NOTE explaining the SOQL is intentionally NOT in a try/catch (lets failure propagate to `execute()`'s outer catch). No code change.
- `submitContextUpdates` (`:689-692`): a NOTE explaining the catch swallows ALL failures (both the "not in updatable state" degrade and the generic warning) and returns 0. **The catch body is unchanged.**

**Net: the +192/-118 is method extraction + `@TestVisible` + explanatory comments. Zero functional behavior delta.** The version header still reads `@version 8.0 — Product Name prepended...` / `@author Marc DeBrey / @date April 2026` — he did NOT bump the version comment, reinforcing that this was a non-functional refactor.

---

## 2. Answers to the four task questions

### Q1 — Did Marc make it fire on renewals today? **NO.**
- The brief's mechanism stands: this `RevSignaling.SignalingApexProcessor.execute(...)` (`:177`) runs only when the pricing engine invokes the prehook chain, i.e. during a **pricing-procedure reprice**. The entry path (`isProcessing` guard `:180`, blank-context guard `:190`, `queryLineItemDataPaths` `:200`, `isQuoteLineSet` scope guard `:210`, attribute query `:217`) is **byte-identical to OLD** in the diff — no new renewal trigger, no new entry point, no flow/trigger hook added inside this class.
- There is **no code in this class** that would cause it to run on a headless renewal that never reprices. Today's edit changed only the internal structure of helper methods.
- **Live data confirms no new firing:** of 52 renewal QLIs (lines under a `QuoteAction.Type='Renew'` quote), only **3** carry a pipe-format description — all created 2026-04-18, last modified 2026-05-15 (weeks before today's 14:41Z edit, single quote `0Q0WC000002iO2H0AU`). **Zero** renewal lines have a pipe description modified after 14:41Z; **zero** renewal lines were modified at all today. So nothing fired the generator on a renewal post-edit.
- **Confidence: HIGH.** Whether/how renewals get descriptions is a question for the rework's reprice-on-renewal design (brief §2 fix anchors), NOT something today's edit touched.

### Q2 — Does `submitContextUpdates` still silently swallow "not in updatable state"? **YES, unchanged.**
`QLDescriptionGeneratorPrehook.cls:695-702`: the catch matches `e.getMessage().containsIgnoreCase('not in updatable state')` → `System.debug(INFO, ...)` and `return 0`; the else-branch logs `WARN` and also `return 0`. It **never re-throws**. Today added only a NOTE comment (`:689-692`) stating this contract is preserved byte-for-byte. **This is still a live risk for the fix:** if a forced renewal reprice runs in a non-updatable context, the description writes drop invisibly and the prehook still reports SUCCESS. Confidence: HIGH (code).

### Q3 — Qty source `Attribute_Volume` else `Number_of_Units` still there? **YES, unchanged.**
- Constants intact: `UNIT_QUANTITY_ATTR='Attribute_Volume'` (`:145`), `NUMBER_OF_UNITS_ATTR='Number_of_Units'` (`:152`).
- `resolveUnitQuantity(attrs)` (`:471-485`): returns `Attribute_Volume` (trimmed) when non-blank, else `Number_of_Units` (trimmed), else null. Preference order unchanged.
- Confirmed in live body: `'Attribute_Volume' in body == True`, `'Number_of_Units' in body == True`. Confidence: HIGH.

### Q4 — Summary of the +192 and whether it addresses defect #2.
The +192 added today = the three new `@TestVisible` extracted methods (`parseConfiguredAttributes`, `parseLineItemDataPaths`, `buildContextUpdates`) plus their javadoc and the four NOTE comments. **It does NOT address defect #2.** Its purpose is **test coverage** — making the previously-untestable inline parse/build logic unit-testable (mirrors the proven extract-pure-math pattern noted in the brief §7 for the COLA prehook). Evidence it's a coverage play:
- The test class `QLDescriptionGeneratorPrehookTest` (Id `01pWC000002LYbsYAG`, modified 2026-06-10T14:49:18Z, 8 min after the class) now has **55 `@IsTest` methods**, including the exact new targets:
  - `parseConfiguredAttributes_*` ×7 (NullAndEmpty, ParentReferenceGroupsByLine, ParentFromDataPathAndKeyNameFallback, BadParentRefSkipped, NullNodeAndNonMapTagValueSkipped, NestedTagValueWrapperAndNullField, FlatShapeAndSingleObject)
  - `parseLineItemDataPaths_*` ×5 (NullAndEmpty, ValidLastElementMapped, NullNodeAndNonMapSkipped, SingleObjectNotList, InvalidLastElementSkipped)
  - `buildContextUpdates_BuildsSkipsNullAndAbsentDataPath` ×1
- Live coverage now **208/(208+52) = 80%** for `QLDescriptionGeneratorPrehook` (`ApexCodeCoverageAggregate`). This is ABOVE the 75% prod gate — a meaningful jump consistent with the brief noting the class needed extraction to become testable. (Brief §7 quoted COLA-class coverage numbers, not this class's prior %, so I can't state an exact before→after delta; the intent is unambiguous.)

**Confidence: HIGH** that the +192 is a coverage refactor and **HIGH** that it does not address defect #2.

---

## 3. Deltas vs the 08:13 brief

| Brief claim (§2) | Current truth | Delta |
|---|---|---|
| Prehook only fires during a pricing reprice; renewals never reprice → no description | **Still true.** execute() entry path byte-identical; today's edit is internal-only. | **No delta** — brief mechanism holds. |
| `submitContextUpdates` silently swallows "not in updatable state" (`...:622`) | Still swallows; now at `...:696` (line shifted by the extractions); added a NOTE documenting the contract | Line number moved (622→~696); behavior identical. Minor cite delta. |
| Qty from `Attribute_Volume` else `Number_of_Units` | Unchanged (`:145`,`:152`,`resolveUnitQuantity :471`) | No delta. |
| "0 of 1,222,003 renewal lines have a description" | I measured **3 of 52** renewal lines (scoped via `QuoteAction.Type='Renew'`) have a pipe description; **332** non-renewal lines do | **Scope delta, not a contradiction.** Brief counted `Quote.QuoteActionId != null` (a superset: amendments/cancels too, ~1.2M). The 3 hits are a single quote manually repriced on 2026-05-15, not renewal-engine output. Tighter scoping shows the generator essentially never fires on renewals — same conclusion. |
| Description logic lives in `QLDescriptionGeneratorPrehook`, NOT a COLA class | Confirmed; today Marc edited it for coverage but did not move description logic into a COLA class | No delta. |
| Class needed pure-math extraction to be testable (brief §7, said of the COLA prehook) | Marc applied exactly this pattern to the description prehook today | **New since brief** — the testability refactor the brief recommended is now partly done for this class (coverage 80%). |

---

## 4. Bottom line for the rework

- Defect #2's root cause is **unchanged** by today's edit: the description prehook fires only on a procedure reprice, and renewals don't reprice. The fix still has to come from the rework (force a Reprice-All on renewal creation — which also fixes Defect #1 — or port description generation onto the renewal trigger/flow path). Today's edit neither helps nor hurts that.
- **Watch item preserved:** `submitContextUpdates` still silently drops writes if the (forced) renewal reprice runs in a non-updatable context, returning SUCCESS. Any "force reprice" fix MUST verify the renewal reprice context is updatable, else descriptions still won't land and nothing will signal the failure.
- **Net positive from today:** the class is now 80% covered and its parse/build logic is unit-testable — that removes one of the brief's blockers (untestable-as-written) for this specific class.

## 5. Evidence index (record IDs / SOQL)
- Live class: `01pWC000002LYbrYAG` @ 2026-06-10T14:41:27Z, ApiVersion 65, 80% cov (208/52).
- Test class: `01pWC000002LYbsYAG` @ 2026-06-10T14:49:18Z, 55 `@IsTest` methods incl. parse*/buildContextUpdates tests.
- Renewal-with-description lines: `0QLWC0000035JbO4AU`, `0QLWC0000035KIv4AM`, `0QLWC0000035KNl4AM` (all Quote `0Q0WC000002iO2H0AU`, Created 2026-04-18, LastModified 2026-05-15).
- Counts: 45 `QuoteAction Type='Renew'`; 52 renewal QLIs; 3 with pipe description; 332 non-renewal with pipe description; 0 renewal lines modified today.
- Key SOQL:
  - `SELECT COUNT(Id) c FROM QuoteLineItem WHERE QuoteId IN (SELECT QuoteId FROM QuoteAction WHERE Type='Renew')` → 52
  - `... AND Description LIKE '% | %'` → 3
  - `... WHERE Description LIKE '% | %' AND QuoteId NOT IN (renew)` → 332
  - `... AND LastModifiedDate > 2026-06-10T14:41:27Z` → 0
  - `SELECT NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate WHERE ApexClassOrTrigger.Name='QLDescriptionGeneratorPrehook'` (tooling) → 208 / 52
