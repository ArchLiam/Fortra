# SC-3447 — PowerOrderSplittingService Apex Class Audit (read-only)
Date: 2026-06-27 · Org: FortraUAT (00DWC000006eUFF2A2) · Investigator: subagent (read-only)

Live retrieve dir: `Data/sc3447/investigation_2026-06-27/live_retrieve/unpackaged/classes/`
Local source: `force-app/main/default/classes/PowerOrderSplittingService(.Test).cls`

---

## 1. DRIFT — live vs force-app (Task 1)

Retrieved live `PowerOrderSplittingService` + `PowerOrderSplittingServiceTest` from FortraUAT (MDAPI, v66 metadata over v67 SOAP). Diffed against force-app.

| Class | Diff result |
|---|---|
| PowerOrderSplittingService.cls | **No drift beyond trailing newline.** `diff -w -B` = IDENTICAL. The only literal diff: live file has NO final newline (`\ No newline at end of file`); force-app has one. 444 vs 445 lines. |
| PowerOrderSplittingServiceTest.cls | **No drift beyond trailing newline.** `diff -w -B` = IDENTICAL. Same trailing-newline-only diff. 624 vs 625 lines. |

MD5 differs only because of that 1-byte trailing newline. **Source is trustworthy — force-app == live for both classes.** No churn since the 2026-06-09 deploy.

Live ApexClass metadata:
- `PowerOrderSplittingService` Id `01pWC000001xm1eYAA`, **ApiVersion 62**, LengthWithoutComments 16635, LastModified **2026-06-09T05:42:19Z**.
- `PowerOrderSplittingServiceTest` Id `01pWC000001xm1fYAA`, ApiVersion 62, LengthWithoutComments 22227, LastModified 2026-06-09T05:42:19Z.

Note: class is **API v62**. The org's pricing-proc deploy-mechanics memory uses api 67; if a fix is deployed, decide whether to bump the class API version (not required for the fix, just flagging).

---

## 2. PER-CLONE CPU PROFILE & N-SCALING (Task 2)

`N = Σ over qualifying lines of (qty − 1)` = total clones created.

### 2a. createFullClone() — lines 363-380 — THE HOT LOOP
```
private static OrderItem createFullClone(OrderItem original) {        // L363
    OrderItem clone = new OrderItem();
    Map<String, Schema.SObjectField> fieldMap = getOrderItemFieldMap();// cached map (good)
    for (String fieldName : fieldMap.keySet()) {                       // L366 — iterates ALL fields
        Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe(); // L367 — NOT HOISTED
        if (dfr.isCreateable()) {                                      // L368
            try {
                Object val = original.get(fieldName);                 // L370
                if (val != null) { clone.put(fieldName, val); }       // L372
            } catch (Exception e) { }
        }
    }
    return clone;
}
```
- **`getDescribe()` is recomputed PER CLONE, PER FIELD.** It is NOT hoisted. The field MAP is cached (`getOrderItemFieldMap`, L382-387), but the per-field `getDescribe()`/`isCreateable()` resolution runs every single call.
- **OrderItem has 208 fields total, 149 createable** (verified via `sf sobject describe`).
- **Per-clone op count:**
  - 208 `Map.get()` + **208 `getDescribe()`** + 208 `isCreateable()` (the dominant, repeated describe cost)
  - up to 149 `original.get()` + 149 `clone.put()` (createable & non-null)
  - ≈ **~700+ field-level operations per clone**, of which the **208 getDescribe() are the expensive ones** (describe resolution is markedly more costly than get/put).
- Total describe operations across the split = **208 × N**. At N=455 (the qty-456 repro) that is **~94,640 getDescribe() calls** — the bulk of the >10,000 ms CPU burn. Hoisting collapses this to 208 calls TOTAL.

### 2b. EVERY place work scales with N (Σ(qty−1))
| Phase | Lines | Per-clone work | Scales with |
|---|---|---|---|
| **Phase 1 clone build** | L139-185 (inner `for i=1..qty`, L157-170) | `createFullClone` (208 describes) + 5 field puts + list.add | **N** (dominant CPU) |
| Phase 1 hardware clone | L173-180 | only when `cloneHw` (OLH split-type — effectively dead, 1 of 3,406 products) | N (OLH only) |
| **Phase 2** insert hardware | L188-190 | one bulk DML | DML rows = N (OLH only) |
| **Phase 3 hw reindex** | L195-210 (inner `for i`) | pure in-memory index walk; recomputes splitType per original (cheap String compare) | **N** |
| **Phase 4** insert clone OrderItems | L213-216 | one bulk DML | **DML rows = N** + per-row record-triggered flows (see 2c) |
| Phase 5 originals update | L219-239 | one update per qualifying line (not per clone) | # qualifying lines (small) |
| **Phase 6 partition build** | L242-270 (inner `for i`) | `clonePartitionRecord` (cheap, ~8 assigns) | **N** (when origPartition != null — the common path) |
| Phase 6 insert partitions | L272-274 | one bulk DML | **DML rows = N** |
| **Phase 7 partition reindex** | L277-297 (inner `for i`) | in-memory; builds `itemsToUpdatePartition` list of size N | **N** |
| Phase 7 update clones | L295-297 | one bulk DML | **DML rows = N** |
| Phase 8 ValidationResult restore | L301-311 | one update per order | # orders (small) |

**SOQL is flat** (4-5 queries regardless of N: 1 Order, 1 dynamic OrderItem, 1 Partition, 1 Hardware). DML *statements* are flat (~5). **DML ROWS scale 1:1 with N** in 3-4 phases. CPU scales with N dominated by the 208 describes/clone.

### 2c. Re-entrancy multiplier (NOT in this class, but triggered by Phase 4/7 DML)
The Phase-4 `insert newItems` and Phase-7 `update itemsToUpdatePartition` each fire the per-OrderItem record-triggered flows ONCE PER ROW:
- `Fortra_OrderItem_Set_Dates` V6 (RecordBeforeSave) — cheap, $Record assigns.
- `Fortra_OrderItem_Set_Workday_Contract_Line_Type` V11 (RecordAfterSave) — does a `Get_Product` SOQL + `recordUpdate` on $Record → re-fires Set Dates = the per-clone flow-interview cost. This is the FLOW_INTERVIEW_LIMIT contributor and runs N times. (Confirmed both flows active; deprecated Autolaunched subflow has no active version.)

---

## 3. TEST CLASS REVIEW + COVERAGE (Task 3)

### 3a. Scenarios covered (`PowerOrderSplittingServiceTest`, 9 methods)
| Method | Qty | What it asserts |
|---|---|---|
| testOrderLineOnlySplit | 4 | 3 lines, 0 hw cloned, 3 partitions; all qty=1; **shared** hardware; Manual_Discount/Displaced_ARR divided evenly; 4 partitions all same hw |
| testOrderLineAndHardwareSplit | 3 | 2 lines, 2 hw cloned, 2 partitions; unique hardware per line (cloned); amounts divided |
| testNonPowerProductNotSplit | 5 | Solution_Group='Security' → 0 lines/hw/partitions; original qty unchanged |
| testQuantityOneNotSplit | 1 | 0 lines created |
| testNullOrderId | – | success=false, error message present |
| testSplitWithoutHardwarePartition | 2 | 1 line, 0 hw, 0 partitions; 2 items total |
| testWrapperClasses | – | SplitRequest/SplitResult default-value coverage only |
| testMultipleItemsMixedSplitTypes | 2+2 | mixed OLO+OLH on one order: 2 lines, 1 hw, 2 partitions |
| testBulkMultipleOrders | 3×2 orders | bulk path: each order 2 lines/2 partitions; **asserts soqlUsed<50 and dmlUsed<50** |

### 3b. Gaps in the test class (relevant to the fix)
- **Max qty tested = 5; bulk max = 6 clones total.** NO high-qty / governor-ceiling test. Nothing exercises N in the hundreds/thousands. A regression that re-introduces per-clone describe would NOT be caught.
- **Clone STAMPING of derived fields is NOT asserted.** Tests check `Quantity`, `Hardware__c`, `Partition_Record__c`, `Manual_Discount__c`, `Displaced_ARR__c`, `Is_Split_Line__c`. They do NOT assert `Workday_Contract_Line_Type__c`, `EndDate`, `PricingTermCount`, or billing dates on clones — exactly the fields the production defect leaves null. So the existing suite cannot validate the P1 stamping fix.
- **`Is_Split_Line__c=true` on clones is never asserted** (only checked indirectly). `Original_Order_Item__c` FK stamping is queried but never asserted in any method.
- **Record-triggered flows:** `@isTest` classes by default run WITH active record-triggered flows. There is NO `@TestSetup`/`Test.isRunningTest()` guard or flow-bypass. So the tests DO run with Set_Dates V6 + Set_Workday_Contract_Line_Type V11 firing — but at qty≤6 the cost is invisible. The `testBulkMultipleOrders` comment explicitly acknowledges org automation fires on the DML and only asserts <50, which is why it passes despite the re-entrancy.

### 3c. Code coverage (Tooling)
- `ApexCodeCoverageAggregate` for `PowerOrderSplittingService`: **NumLinesCovered=0, NumLinesUncovered=231 → 0% coverage.**
- `ApexCodeCoverage` (per-test rows): **0 rows** — no test run has ever been recorded against this class in this org.
- Interpretation: the test class clearly exercises the service, so 0% means **tests have not been executed in FortraUAT since the 2026-06-09 deploy** (coverage tables are empty, not low). Any deploy of a fix will need a fresh test run to (re)establish coverage; production org-wide 75% gate is currently UNVERIFIED for this class. **This is a deploy blocker until tests are run.**

---

## 4. MINIMAL-RISK FIX TARGETS (Task 4, with line numbers)

All line numbers are force-app (== live).

### (a) Hoist the createable-field list to a static computed once
- **Current cost:** `createFullClone` L366-377 calls `getDescribe()` (L367) inside the per-field loop, executed once per clone → 208 describes × N.
- **Fix:** add a static `List<String> createableFieldNames` (or `Set<String>`) lazily computed once (iterate `getOrderItemFieldMap()`, keep names where `getDescribe().isCreateable()`), mirroring the existing `getOrderItemFieldMap()` cache pattern at L382-387. Then `createFullClone` L366-377 iterates that pre-filtered name list and does only `original.get()` / `clone.put()` (no describe in the loop).
- **Bonus:** the SAME filter is recomputed in `queryOrderItemsToSplit` L337-342 (`isAccessible()` per field). A parallel `accessibleFieldNames` static removes that too (one-time, runs once not per-clone, smaller win).
- **Risk:** very low — pure CPU optimization, identical output set. Net per-clone describe cost drops from 208 to 0 (computed once total).

### (b) Stamp derived fields onto clones from the already-queried original
- **IMPORTANT — verified field names** (`sf sobject describe OrderItem`): the billing-date fields are **`Billing_Schedule_From_Date__c`** and **`Billing_Schedule_To_Date__c`** (NOT `Billing_Start/End_Date__c`). Term/date fields confirmed present and **createable=true**: `Workday_Contract_Line_Type__c` (picklist), `EndDate` (date), `PricingTermCount` (double), `Billing_Schedule_From_Date__c`, `Billing_Schedule_To_Date__c`. Also present: `Start_Date_Calculated__c`, `End_Date_Calculated__c`, `Is_Term__c`, `SubscriptionTerm`, `ServiceDate`.
- **Subtlety:** `createFullClone` ALREADY copies every createable non-null field (L368-372). So if these fields are populated on the original at split time, the clone already inherits them. The defect is a TIMING problem: these fields are stamped by the record-triggered flows that fire AFTER the original is created, and during conversion the split runs on a freshly-cloned-from-quote order whose OrderItems may not yet have line-type/term/dates derived. The proper P1 fix (per memory) is to suppress the per-clone flows AND explicitly re-derive+stamp on clones in Apex.
- **Fix location:** the clone-customization block at **L159-167** (already sets Quantity, Manual_Discount__c, Displaced_ARR__c, Is_Split_Line__c, Original_Order_Item__c). Add explicit stamps here, e.g. `splitItem.Workday_Contract_Line_Type__c = original.Workday_Contract_Line_Type__c;` etc. — but only meaningful if the original itself carries the value. If the original is also unstamped at split time, the fix must instead compute the values (mirroring Set_Dates V6 / Set_Workday_Contract_Line_Type V11 logic) — a larger change. **Recommend: add the explicit copy at L159-167 AND add entry-condition `Is_Split_Line__c = false` to both record-triggered flows so the original keeps deriving via flow once, then clones inherit via the Apex copy.** Confirm at build time whether original is stamped pre-split (single Apex describe of a converted order's OrderItem).
- **Risk:** low-medium. Field names are verified; all createable. The behavioral question (is the original stamped at split time?) must be resolved before committing to "copy" vs "derive."

### (c) Hard-cap guard with a catchable error
- **Fix location:** at the top of `processOrders` after `itemsToSplit` is loaded (**after L113, before L115**), or inside `splitPowerOrderLines` after computing total clones. Compute `Integer totalClones = Σ(qty-1)` over `itemsToSplit`; if `totalClones > CAP`, set `result.success=false` + a clear `result.errorMessage` (e.g. "Power split would create N lines, exceeding the supported maximum of CAP; contact admin") and `return` WITHOUT DML. Because the invocable returns a SplitResult (not a thrown exception), the screen flow can branch on `success=false` and show a friendly message instead of the FLOW_INTERVIEW gack.
- **CAP recommendation:** well below the DML-row ceiling (see §5) and below the empirical CPU ceiling — suggest **CAP ≈ 200-300** clones per transaction for the synchronous path (the real fix is async/aggregate per P2/P3). Make it a single named constant.
- **Risk:** very low — pure guard, no behavior change under the cap.

---

## 5. 10,000-DML-ROW HARD-CEILING MATH (Task 5)

Synchronous transaction limit: **10,000 DML rows total.**

DML rows attributable to N = Σ(qty−1) clones, by phase (common path = "Order Line Only" with a partition; OLH is effectively dead — 1 of 3,406 products):

| Phase | DML rows | Common path (OLO + partition) |
|---|---|---|
| Phase 2 insert hardware | N (OLH only) | 0 |
| Phase 4 insert clone OrderItems | N | **N** |
| Phase 5 update originals | # qualifying lines (≈1) | ~1 |
| Phase 6 insert partitions | N (if partition) | **N** |
| Phase 7 update clone partitions | N (if partition) | **N** |
| Phase 8 ValidationResult restore | # orders (≈1) | ~1 |

**Break-even (this class's own DML only):**
- **OLO WITH partition (most common):** rows ≈ 3N + 2 (insert clones + insert partitions + update clone partitions). `3N + 2 ≤ 10000 → N ≤ 3332`. Above **N ≈ 3,333 clones (qty ≈ 3,334)** the transaction fails on DML rows ALONE, regardless of CPU or async.
- **OLO WITHOUT partition:** rows ≈ N + 1 (clones only). `N ≤ 9999 → qty ≤ 10,000`.
- **OLH (cloneHw, partition):** rows ≈ 4N (hardware + clones + partitions + clone-partition update). `4N ≤ 10000 → N ≤ 2500 → qty ≤ 2,501`. (Dead path in practice.)

**Critical implication:** Live Power Quantity is routinely in the thousands and uses "unlimited" sentinels (9,999 / 99,999 / 999,999; 134 lines at 999,999). At qty 999,999 the DML-row ceiling is exceeded by ~100-300×. **No amount of CPU optimization or moving to async/Queueable fixes this** — Queueable still has the same 10,000-DML-rows-per-transaction ceiling; Batch chunking would need ~100+ chunks for a single 999,999-qty line and produce a million OrderItems, which is absurd. This confirms the per-unit split is structurally wrong for sentinel/seat-count Power lines (P3 business fix: aggregate / don't split sentinel & seat-count lines).

Add the per-clone record-triggered flow DML (each flow's recordUpdate adds rows too) and the effective sync ceiling is even lower — but the class's own 3N+2 is the hard arithmetic floor.

---

## DRIFT FROM 2026-06-26 KNOWN STATE
- **Class code:** no drift (force-app == live, trailing newline only). Active flows unchanged (Set_Dates V6, Set_Workday_Contract_Line_Type V11; deprecated subflow inactive).
- **NEW: code coverage = 0%** (tables empty; tests never run in-org since 2026-06-09) — not previously called out; this is a deploy-gate concern.
- **NEW: verified billing field names** are `Billing_Schedule_From_Date__c` / `Billing_Schedule_To_Date__c` (the fix's assumed `Billing_Start/End_Date__c` do NOT exist). `Workday_Contract_Line_Type__c`, `EndDate`, `PricingTermCount` all exist & createable.
- **NEW: precise per-clone cost = 208 getDescribe()** (208 fields, 149 createable), confirming describe-not-hoisted is the dominant CPU.
- **DRIFT: repro quote `0Q0WC000003AuQb0AK` (Q-00781200) NO LONGER EXISTS** in FortraUAT (0 rows for the Quote and its lines). The repro PRODUCT "Abstract" `01tWC00000DD11GYAT` (Power / Order Line Only / Active) still exists. A new repro quote will need to be created to re-test.
- Class API version is **v62** (deploy memory uses 67).
