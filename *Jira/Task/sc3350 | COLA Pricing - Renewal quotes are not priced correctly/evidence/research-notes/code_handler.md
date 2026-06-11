# SC-3350 — Code/Defect#1 + Handler: CURRENT live truth vs the 08:13 brief

**Date:** 2026-06-10 (research run after Marc DeBrey's 16:29Z COLAUpliftHandler edit)
**Org:** FortraUAT (read-only)
**Scope:** `COLAUpliftHandler.cls` + `QuoteLineItemTrigger.trigger` — does today's edit fix Defect #1?

---

## 0. Provenance / freshness verification (so this is CURRENT truth, not stale)

Live org metadata (SOQL, `--use-tooling-api`):

```
SELECT Name, LastModifiedDate, LastModifiedBy.Name, LengthWithoutComments
FROM ApexClass
WHERE Name IN ('COLAUpliftHandler','COLAUpliftPrehook','COLAUpliftTest','AssetContractQueryHelper','QLDescriptionGeneratorPrehook')
```

| Class | LastModifiedDate (UTC) | By | LenWoComments |
|---|---|---|---|
| AssetContractQueryHelper | 2026-06-10T14:00:37Z | Marc DeBrey | 3063 |
| **COLAUpliftHandler** | **2026-06-10T16:29:57Z** | **Marc DeBrey** | 13066 |
| COLAUpliftPrehook | 2026-06-10T16:51:20Z | Marc DeBrey | 39956 |
| COLAUpliftTest | 2026-06-10T16:51:20Z | Marc DeBrey | 93445 |
| QLDescriptionGeneratorPrehook | 2026-06-10T14:41:27Z | Marc DeBrey | 16506 |

The handler's live `LastModifiedDate` = **16:29:57Z**, matching the task brief's stated "COLAUpliftHandler 16:29Z" edit. **This is the latest version; no newer edit landed during research.**

**Identity proof that the file I analyzed IS the org body:** fetched `ApexClass.Body` for COLAUpliftHandler from the org and diffed against `Data/sc3350/live/unpackaged/classes/COLAUpliftHandler.cls` → **IDENTICAL** (495 lines org body vs local; only trailing-newline difference). So every line cite below is against the **live 16:29Z body**.

Trigger:
```
SELECT Name, LastModifiedDate, LastModifiedBy.Name FROM ApexTrigger WHERE Name='QuoteLineItemTrigger'
→ QuoteLineItemTrigger | 2026-06-10T00:05:44Z | Nir Kailash
```
Trigger last touched **00:05Z by Nir Kailash** — BEFORE all of Marc's COLA edits today. The COLA path inside it was **not** modified today.

---

## 1. Q1 — Does `handleBeforeInsert` still early-return on empty QuoteActionId? Did Marc fix it today?

**Answer: YES, the early return is STILL THERE. NO, Marc did NOT change it today.**

Current live `COLAUpliftHandler.handleBeforeInsert` (lines 16–48), verbatim, with the early return at **lines 29–31**:

```apex
16  public static void handleBeforeInsert(List<QuoteLineItem> newItems) {
17      if (newItems == null || newItems.isEmpty()) {
18          return;
19      }
20
21      // Collect QuoteActionIds from the new items
22      Set<Id> quoteActionIds = new Set<Id>();
23      for (QuoteLineItem qli : newItems) {
24          if (qli.QuoteActionId != null) {
25              quoteActionIds.add(qli.QuoteActionId);
26          }
27      }
28
29      if (quoteActionIds.isEmpty()) {
30          return;                        // <-- DEFECT #1 ROOT CAUSE, UNCHANGED
31      }
32
33      Map<Id, QuoteAction> quoteActionMap = new Map<Id, QuoteAction>([
34          SELECT Id, Type, SourceAssetId, SourceAsset.Price, SourceAsset.Product2Id,
35                 SourceAsset.Product2.Solution_Category__c
36          FROM QuoteAction
37          WHERE Id IN :quoteActionIds
38          AND Type = 'Renew'
39      ]);
40
41      if (quoteActionMap.isEmpty()) {
42          return;
43      }
44
45      populateCOLAFields(newItems, quoteActionMap);
46  }
```

- The brief said "live lines 29-31 `if (quoteActionIds.isEmpty()) return;`". **Still at lines 29–31, character-for-character identical.**
- `quoteActionIds` is still populated **only** from `qli.QuoteActionId` read off `Trigger.new` (lines 23–26). If the RLM headless-renewal engine has not yet stamped `QuoteActionId` on the row at before-insert (the brief's documented ~35s-later write), the set is empty and the method returns at line 30 — **no COLA stamped, line keeps list price.**
- **The +59/-10 edit today did NOT touch `handleBeforeInsert` at all.** Confirmed by the unified diff (see §4): the first changed hunk starts at the doc-comment of `populateCOLAFields` (line ~230). Lines 16–48 are unchanged from the brief-basis copy.

**Confidence: HIGH.** The early-return bug for Defect #1 is unaddressed by today's edit.

---

## 2. Q2 — Where does UnitPrice / Pre_COLA_Price__c / COLA_Source__c get stamped NOW (renewal insert path)?

**Answer: same place as before — the (now-overloaded) `populateCOLAFields` core, lines 327–335. The write LOGIC is byte-identical to the brief-basis; only the method was split into a wrapper + `@TestVisible` core.**

Insert-path call chain (current):
`QuoteLineItemTrigger` before-insert (line 26) → `handleBeforeInsert` (line 16) → **`populateCOLAFields(items, quoteActions)` thin wrapper (line 240)** → resolves Tier-2 contract overrides → **`populateCOLAFields(items, quoteActions, contractOverridesByAssetId)` testable core (line 270, `@TestVisible`)**.

The actual stamps are in the core loop, lines 279–336:

```apex
324      // Calculate new price with COLA
325      Decimal newPrice = assetPrice * (1 + (colaPercent / 100));
326
327      // Populate COLA fields
328      qli.UnitPrice = newPrice;                                   // UnitPrice
329      qli.Pre_COLA_Price__c = assetPrice;                         // Pre_COLA_Price__c = raw Asset.Price (gross base)
330      qli.COLA_Uplift_Percent__c = colaPercent;
331      qli.Default_COLA_Uplift_Percent__c = colaPercent;
332      qli.COLA_Solution_Category__c = solutionCategory;
333      qli.COLA_Applied_Date__c = DateTime.now();
334      qli.Is_COLA_Overridden__c = false;
335      qli.COLA_Source__c = colaSource;                            // 'Contract Override' | 'CMDT Lookup' (default), L302-303/335
336  }
```

- `colaSource` is initialized `'CMDT Lookup'` (line 303), promoted to `'Contract Override'` (line 310) when a valid Tier-2 override exists. `colaPercent` is `0` default (line 302), set from contract override (line 309) or CMDT rule (line 319).
- Base for the price = `qa.SourceAsset.Price` (line 290), guarded only against `null` (line 291) — still **no `<=0` guard** (brief B6 divergence vs prehook still stands; this file unchanged there).
- **CRITICAL — this stamping code only runs if `handleBeforeInsert` got past the line-30 early return.** On a true headless renewal where `QuoteActionId` isn't in `Trigger.new`, **none of lines 327–335 execute.** So the *write path itself is unchanged and correct, but it is still unreachable on the defect-#1 renewal scenario.*

**Confidence: HIGH.**

---

## 3. Q3 — Is the before-update self-heal still gated on `Pre_COLA_Price__c != null`?

**Answer: YES, still gated. Unchanged today.**

`handleBeforeUpdate` collects `changedItems` for repricing at lines 159–164:

```apex
158      // Check if COLA percentage was changed (by user or by sync above)
159      if (qli.COLA_Uplift_Percent__c != null &&
160          qli.COLA_Uplift_Percent__c != oldQli.COLA_Uplift_Percent__c &&
161          qli.Pre_COLA_Price__c != null) {                     // <-- self-heal precondition, UNCHANGED
162
163          changedItems.add(qli);
164      }
```

And `recalculateCOLAPrice` re-guards on the same field at line 345:

```apex
344  for (QuoteLineItem qli : changedItems) {
345      if (qli.Pre_COLA_Price__c != null && qli.COLA_Uplift_Percent__c != null) {
346          Decimal newPrice = qli.Pre_COLA_Price__c * (1 + (qli.COLA_Uplift_Percent__c / 100));
347          qli.UnitPrice = newPrice;
348          ...
```

- The brief's claim ("`handleBeforeUpdate` can't self-heal an unstamped line: its recalc requires `Pre_COLA_Price__c != null`, `COLAUpliftHandler.cls:161`") **still holds** — same field, same line number (161). A renewal line that was never stamped at insert (because of the line-30 early return) has `Pre_COLA_Price__c = null`, so it is excluded from `changedItems` at line 161, and `recalculateCOLAPrice` would skip it at line 345 anyway. **The before-update path cannot derive COLA from scratch; it only recalculates a previously-stamped line.**
- Note: the *whole* `handleBeforeUpdate` body (lines 55–208), including the year-1 override-detection block (lines 81–107), the system-source CMDT sync (lines 123–137), the outyear defaulting (lines 147–156), and the outyear-override block (lines 171–202), is **byte-identical to the brief-basis copy.** None of it was edited today.

**Confidence: HIGH.**

---

## 4. Q4 — Exactly what changed in the +59/-10 diff, and does it address Defect #1?

**Diff line counts (verified):** `diff` reports **59 added (`>`)** / **10 removed (`<`)** lines between
`Data/cola-renewal-review/live/classes/COLAUpliftHandler.cls` (brief-basis, file mtime 2026-06-09 20:59) and
`Data/sc3350/live/unpackaged/classes/COLAUpliftHandler.cls` (current, file mtime 2026-06-10 16:54).
File length 445 → 494 lines (+49 net). This **matches the task's stated "+59/-10".**

**The entire change is a pure test-enablement refactor (split-for-testability + `@TestVisible`), NOT a behavior change.** Three edits, all in the lower half of the class:

1. **`populateCOLAFields` split into wrapper + testable core.**
   - Old single method `populateCOLAFields(items, quoteActions)` did contract-override resolution AND the per-line tier loop inline.
   - New: the 2-arg method (line 240) becomes a thin wrapper that resolves `contractOverridesByAssetId` then delegates to a new **`@TestVisible private static populateCOLAFields(items, quoteActions, contractOverridesByAssetId)`** 3-arg core (line 269–270). The per-line loop (and the stamping at 327–335) moved verbatim into the core. Doc comments expanded. The `getCOLARulesMap()` call moved from the top of the old method into the new core (line 276).

2. **`getContractOverrides` split: extracted `buildContractOverrideMap`.**
   - The persist-date validity transform moved out of `getContractOverrides` into a new **`@TestVisible private static Map<Id,ContractOverride> buildContractOverrideMap(contractDataList)`** (line 436–438). `getContractOverrides` (line 410) now just guards empties, calls `AssetContractQueryHelper.queryAssetContracts`, and delegates. Comments expanded ("runs the live AssetContractRelationship + Contract SOQL inside its own try/catch").

3. **`ContractOverride` inner class annotated `@TestVisible`** (line 487).

**Rationale is explicit in the new doc-comments:** the extractions exist so tests can drive the Tier-2 (Contract Override) branch and the validity logic with in-memory `AssetContractData` rows, "because the underlying AssetContractRelationship cannot be inserted in a test on this org (the linked Asset needs platform-owned HasLifecycleManagement=true)." This is test-coverage scaffolding aimed at the brief's §7 finding (handler 42% cov; `populateCOLAFields`, `getContractOverrides`, `buildContractOverrideMap` were 0-covered) — consistent with the COLAUpliftTest 93445-char body also being rewritten at 16:51Z.

**Does it address Defect #1? NO.**
- `handleBeforeInsert` (lines 16–48), including the line-30 early-return root cause, is **untouched**.
- The renewal insert price stamps (lines 327–335) are byte-identical; the price still derives from `assetPrice * (1 + colaPercent/100)` with `Pre_COLA_Price__c = assetPrice`.
- The before-update self-heal `Pre_COLA_Price__c != null` gate (line 161 / 345) is **untouched**.
- No new after-insert reconcile, no forced reprice, no relaxation of the `QuoteActionId`-in-`Trigger.new` dependency. None of brief fix-anchors A/B/C/Unifying were implemented.

**Net:** today's COLAUpliftHandler edit is **testability-only**; the runtime behavior — and therefore Defect #1 — is **unchanged**. The defect's mechanism (headless renewal → `QuoteActionId` not in `Trigger.new` at before-insert → line-30 early return → no COLA, no `Pre_COLA_Price__c` → before-update can't self-heal) is **fully intact in the live 16:29Z code.**

**Confidence: HIGH** (diff is mechanical; the three new methods are wrappers/extractions whose moved code is line-for-line identical to the original).

---

## 5. Deltas vs the 08:13 brief (explicit)

| Brief claim | Current truth | Status |
|---|---|---|
| `handleBeforeInsert` early-return `if (quoteActionIds.isEmpty()) return;` at lines 29–31 | Still at lines 29–31, identical | **UNCHANGED — brief still correct** |
| Insert stamps UnitPrice/Pre_COLA_Price__c/COLA_Source__c in `populateCOLAFields` (~L237-309) | Same writes, now at **L327–335** inside a `@TestVisible` 3-arg core (method split; line numbers shifted +~20) | **MOVED, logic unchanged** |
| Before-update self-heal gated on `Pre_COLA_Price__c != null` (L161) | Still at L161 (collect) and L345 (recalc) | **UNCHANGED — brief still correct** |
| Handler 42% coverage; populateCOLAFields/getContractOverrides 0-covered | 16:29Z edit splits these for `@TestVisible` testing; COLAUpliftTest rewritten 16:51Z (93445 chars) | **NEW: test scaffolding added today (coverage not re-measured in this stream)** |
| B1 multi-asset (AssetContractQueryHelper:47-52), B6 Asset.Price≤0 guard mismatch | Handler-side untouched today; AssetContractQueryHelper separately edited 14:00Z (out of scope for this file) | **Handler side unchanged** |

**Bottom line for the parent:** Marc's 16:29Z COLAUpliftHandler edit is a **+59/-10 testability refactor only**. **Defect #1 is NOT fixed** in the current live handler — the early-return root cause and the un-self-healable before-update gate are both still present and unmodified. Any claim that "Marc fixed defect #1 today in the handler" is FALSE against live evidence.

---

## 6. SOQL / commands used (for reproducibility)

```
# Freshness + identity
sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Name, LastModifiedDate, LastModifiedBy.Name, LengthWithoutComments FROM ApexClass WHERE Name IN ('COLAUpliftHandler','COLAUpliftPrehook','COLAUpliftTest','AssetContractQueryHelper','QLDescriptionGeneratorPrehook') ORDER BY Name" -r csv
sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Name, LastModifiedDate, LastModifiedBy.Name FROM ApexTrigger WHERE Name='QuoteLineItemTrigger'" -r csv
sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Body FROM ApexClass WHERE Name='COLAUpliftHandler'" --json   # -> diff vs local = IDENTICAL

# Diffs
diff -u Data/cola-renewal-review/live/classes/COLAUpliftHandler.cls Data/sc3350/live/unpackaged/classes/COLAUpliftHandler.cls   # +59/-10
diff -u Data/cola-renewal-review/live/triggers/QuoteLineItemTrigger.trigger Data/sc3350/live/unpackaged/triggers/QuoteLineItemTrigger.trigger   # EMPTY (identical)
```

## 7. Key record IDs (from brief, not re-verified this stream — flagged)
- Repro renewal line `0QLWC000003bHpl4AE` / Quote `0Q0WC00000365Uj0AI`; QuoteAction `7ocWC00000tYaFtYAK`; SourceAsset `02iWC000007DXlJYAW` (Price 10000, Brand Protection 5% → expected 10500). These were the brief's data; this stream confirmed CODE only. The data-side re-verification (whether the repro line is still unpriced post-16:29Z) is a separate stream / open question.
