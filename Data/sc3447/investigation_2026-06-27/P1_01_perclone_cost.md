# SC-3447 P1 — Per-Clone Cost Quantification + Flow-Suppression Safety (LIVE, read-only)

Date: 2026-06-27
Org: FortraUAT (00DWC000006eUFF2A2)
Method: `sf sobject describe`, read-only anonymous Apex (debug only, 0 SOQL/0 DML/0 CPU-write),
Tooling queries (Flow, FieldDefinition, ValidationRule, ApexTrigger, ApexClass, MetadataComponentDependency),
`sf project retrieve start` of both live flow XMLs. NO mutations.
Retrieve artifacts:
- `Data/sc3447/investigation_2026-06-27/P1_perclone_retrieve/flows/Fortra_OrderItem_Set_Dates.flow-meta.xml`
- `Data/sc3447/investigation_2026-06-27/P1_perclone_retrieve/flows/Fortra_OrderItem_Set_Workday_Contract_Line_Type.flow-meta.xml`
Subject class: `force-app/main/default/classes/PowerOrderSplittingService.cls`
(local copy has P0 cap + P3 gate; live org = P0 + older, `LengthWithoutComments=17569`, API 62 — P1 targets
`createFullClone` and the flows, which are unchanged by P3, so this analysis is version-independent.)

---

## TL;DR — the per-clone cost, today vs after P1

| Cost component (per clone) | TODAY | AFTER P1 |
|---|---|---|
| `getDescribe()` calls in `createFullClone` | **208** (one per field in `fields.getMap()`) | **0** (hoisted to static field-name list) |
| `get()`/`put()` field copies | ~149 (createable) | ~149 (unchanged) |
| Flow interviews fired on the clone insert | **3** (Set_Dates insert + Set_Workday after-save + Set_Dates re-fire) | **0** |
| SOQL caused by per-clone flows | **1** (Get_Product in Set_Workday) | **0** |
| DML caused by per-clone flows | **1** (Set_Workday after-save `recordUpdate $Record`) | **0** |
| Re-entrancy (extra Set_Dates re-fire) | **yes** (1 extra interview) | **none** |

**Per-clone fixed-overhead reduction: ~208 getDescribe ops + 3 flow interviews + 1 SOQL + 1 re-entrant DML
removed.** The dominant CPU saving is the **208 schema describes/clone** plus the **3 flow interviews/clone**
(flow interview setup/teardown is the heavier of the two in wall-CPU). The describe ops are the most
load-bearing because they scale 1:1 with clones AND with field count (208), and `getDescribe()` is a
relatively expensive reflection call. **Estimated per-clone CPU drops to roughly one-tenth to one-quarter
of today's** (see §4). That is what raises the synchronous ceiling from "single/low-double digits today"
into the low hundreds (where the 10k-DML-row wall, not CPU, becomes the next limit — that is P2/P3 scope).

---

## 1. OrderItem field counts — the describe multiplier (LIVE)

`sf sobject describe -s OrderItem -o FortraUAT`:
- **Total fields (describe API): 208**
- **Createable: 149**
- Not createable: 59
- Updateable: 142
- Custom: 100 / Standard: 108

Verified via read-only anonymous Apex run AS the convert user (the exact map the class uses):
```
Schema.SObjectType.OrderItem.fields.getMap().size() = 208
  isCreateable() = 149
  isAccessible() = 208   (all 208 fields are visible to this user → describe == getMap)
```
(`fields.getMap()` is FLS-independent and returns every referenceable field; the running user can read all
208, so `queryOrderItemsToSplit` selects 149+ accessible fields and `createFullClone` evaluates all 208.)

### getDescribe() call accounting

`createFullClone` (`PowerOrderSplittingService.cls:404-421`):
```apex
for (String fieldName : fieldMap.keySet()) {          // 208 iterations
    Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();   // <-- 1 getDescribe PER FIELD
    if (dfr.isCreateable()) { ... clone.put(...) ... }
}
```
- **getDescribe() calls per clone TODAY = 208.**
- For N clones the per-clone loop does **208 × N** getDescribe() calls (e.g. 200 clones → 41,600 describes).
- `getOrderItemFieldMap()` (L423-428) DOES cache `fields.getMap()` in a static, but it does **NOT** cache
  the per-field `getDescribe()` results — so the describe work repeats on every clone. This is the un-hoisted
  cost P1#1 targets.

`queryOrderItemsToSplit` (`PowerOrderSplittingService.cls:365-373`) runs the SAME 208-field
`getDescribe()` loop once (calling `isAccessible()`), but that is **once per transaction**, not per clone —
≈208 describes total regardless of N. Still worth hoisting to the same static list for tidiness, but it is
not the per-clone amplifier.

### After P1#1 (hoist)
Compute the createable-field-name `List<String>` (and the accessible-field-name list) **ONCE** in a static
initializer / lazy static, by iterating the 208 fields a single time per transaction. Then `createFullClone`
becomes a pure `for (String f : CREATEABLE_FIELDS) { Object v = original.get(f); if (v != null) clone.put(f, v); }`
loop — **0 getDescribe() in the per-clone path.** Per-clone describe cost: **208 → 0.**
Transaction-level describe cost: ~208 once (build the static lists), down from 208 + 208×N.

---

## 2. The two OrderItem record-triggered flows (LIVE, re-verified) — per-clone cost

Active versions (Tooling `Flow`, re-verified 2026-06-27):
| Flow | Active Ver | Flow Id | Trigger | API | Entry filter |
|---|---|---|---|---|---|
| Fortra_OrderItem_Set_Dates | **V6** | 301WC00000knsJNYAY | RecordBeforeSave, CreateAndUpdate | 67 | **NONE** |
| Fortra_OrderItem_Set_Workday_Contract_Line_Type | **V11** | 301WC00000kUYVFYA4 | RecordAfterSave, CreateAndUpdate | 66 | **NONE** |

Both `<start>` blocks were inspected in the freshly-retrieved XML: neither has a `<filters>`/`<filterLogic>`
entry condition. Both fire on EVERY OrderItem insert and update → both fire on every clone.

### 2a. Set_Dates V6 (before-save) — per invocation
- `<recordLookups>`: **0** → **0 SOQL.**
- `<recordUpdates>`: 3 (Backstop_Std_Term_Fields, Non_Perpetual_Set_Dates, Perpetual_Set_Dates), ALL
  `<inputReference>$Record</inputReference>` in a **before-save** flow → in-memory field writes → **0 DML.**
- Decisions: Is_Termed_Blank, Perpetual; formulas: Calculated_From_Date, Calculated_To_Date, Std_PricingTermCount.
- Stamps: `Billing_Schedule_From_Date__c`, `Billing_Schedule_To_Date__c`, `End_Date_Calculated__c`,
  `Start_Date_Calculated__c`; termed-backstop branch also `EndDate`, `PricingTermCount` (SC-3411 backstop).
- **Per-invocation: 0 SOQL, 0 DML, modest CPU (one flow interview).**

### 2b. Set_Workday V11 (after-save) — per invocation (Power line = non-services, non-subsplit)
- Element graph: `Get_Product` (recordLookup Product2 by `$Record.Product2Id`) → `Decision_Is_Services_Product`
  (reads `Get_Product.pse__IsServicesProduct__c`) → (No) `Decision_Is_Subsplit`
  (reads `$Record.Product2.Is_Subsplit_Product__c`, cross-object on `$Record`, no SOQL) → (No)
  `Update_LineType_Fixed_Amount` (`recordUpdate $Record`, sets `Workday_Contract_Line_Type__c='FIXED AMOUNT'`).
- **SOQL: 1** (Get_Product, always). The services-only branch would add a 2nd SOQL (Get_Prepaid_Order_Attribute)
  but Power lines never enter it.
- **DML: 1** — `recordUpdate` with `<inputReference>$Record</inputReference>` in an **after-save** flow is a
  REAL update DML on the just-saved record.
- **Re-entrancy:** that after-save `$Record` update re-saves the record → **re-fires the before-save
  Set_Dates** (CreateAndUpdate) → **+1 extra Set_Dates interview** per clone.
- Subsplit is decided by `$Record.Product2.Is_Subsplit_Product__c` — **the live V11 has NO
  `Original_Order_Item__c` reverse-lookup** (the V9/V10-era reverse-lookup is gone; see §3).

### 2c. Per-clone flow totals (one inserted clone, Power line)
- **Flow interviews: 3** = Set_Dates (insert/before-save) + Set_Workday (after-save) + Set_Dates (re-fired by
  the after-save DML).
- **SOQL: 1** (Set_Workday Get_Product).
- **DML: 1** (Set_Workday after-save `recordUpdate $Record`).
- Plus the re-entrant re-save itself (counts toward DML-row pressure on top of the split's own inserts).

For N clones the flows alone cost **3N interviews + N SOQL + N DML** — pure redundant work, because the clone
already carries the parent's stamped values by copy (§3).

---

## 3. Suppression mechanism safety — `Is_Split_Line__c = false` entry condition

### (a) The flag is set on clones IN MEMORY before insert
- `PowerOrderSplittingService.cls:193` — each clone: `splitItem.Is_Split_Line__c = true;` (and L194
  `Original_Order_Item__c = original.Id;`) BEFORE the Phase-4 `insert newItems` (L244). So at the moment
  both flows evaluate their (new) entry condition on a clone, `Is_Split_Line__c = true` → clone is SKIPPED.
- `PowerOrderSplittingService.cls:264-265` — the ORIGINAL (slot 0) is updated with `Is_Split_Line__c = false`
  and `Original_Order_Item__c = null`. So the original always satisfies `=false` → still stamped by both flows
  (on its own createOrderFromQuote insert AND on the Phase-5 update). Originals never regress.
- `Is_Split_Line__c` is a **Checkbox** on OrderItem (FieldDefinition, LIVE). A new line's default is `false`,
  so EVERY normal (non-split) OrderItem keeps satisfying `=false` and keeps running both flows. Only the
  qty-1 clones are excluded.

### (b) Entry condition skips with ~0 CPU
A Start `<filters>` entry condition is evaluated by the platform **before** the interview is created. A clone
that fails the filter incurs no interview, no Get_Product SOQL, no `recordUpdate` DML, and no re-entrant
re-fire. Adding the SAME filter to BOTH flows removes all 3 interviews + 1 SOQL + 1 DML per clone. (Adding it
only to the after-save Set_Workday would also stop Set_Dates' re-fire on clones, because the clone's after-save
DML would no longer happen — but the clone's INITIAL before-save Set_Dates would still run; add to both.)

### (c) Nothing downstream depends on the per-clone flow run or on `Is_Split_Line__c`
Authoritative LIVE checks:

- **MetadataComponentDependency on `Is_Split_Line__c` (00NWC000005952W):** consumers = **Order Product Layout
  (Layout)** + **PowerOrderSplittingService** + **PowerOrderSplittingServiceTest** (Apex). No flow, no VR,
  no trigger, no workflow, no rollup. (Layout is display-only — irrelevant to automation.)
- **MetadataComponentDependency on `Original_Order_Item__c` (00NWC000005952X):** consumers = Order Product
  Layout + PowerOrderSplittingService(+Test) + **`Fortra | OrderItem | Set Workday Contract Line Type` (Flow,
  3 rows)**. The 3 Flow rows are from **OBSOLETE versions** (the V9/V10-era reverse-lookup). The **ACTIVE V11
  XML has 0 references to `Original_Order_Item__c`** (`grep -c = 0`). All 8 non-active versions (V1-5, V8-10)
  are Obsolete. So no LIVE automation reads `Original_Order_Item__c`; the dependency is dormant.
- **0 Apex triggers** on OrderItem (Tooling ApexTrigger).
- **0 active validation rules** on OrderItem (Tooling ValidationRule).
- **No active flows on the clone child objects** (Order Product Attribute / Partition) per file 02.
- The only consumer of `Workday_Contract_Line_Type__c` is the Workday integration at order-complete time;
  it reads the stamped value, which the clone carries via copy. Date fields are read by billing/activation,
  also present via copy.

**Conclusion:** suppressing both flows on clones breaks nothing downstream. The clone inherits identical
stamped values because `createFullClone` copies every createable field from the already-stamped original.

### (d) The originals are already stamped before cloning (sequence proof, LIVE convert flow V28)
`Fortra_Quote_to_Order_Conversion` is **V28 Active** (was V27 in earlier docs — daily churn, not material).
Connector chain, all `flowTransactionModel=CurrentTransaction` (one sync request, one CPU budget):
`Get_Quote_Details → Call_Create_Order_From_Quote (createOrderFromQuote: INSERTS originals → both flows fire
& STAMP the originals) → Assign_Created_Order_Id → MapQuoteLineFieldsToOrderItems → SplitPowerOrderLines
(clones the already-stamped originals) → Get_Created_Order → Reprice → Activate.`
So when `createFullClone` reads the original (queried with all accessible fields in `queryOrderItemsToSplit`),
the stamped values (`Workday_Contract_Line_Type__c`, the 4 date fields, EndDate/PTC where present) are already
on the record and get copied to every clone. The per-clone flow runs are redundant for these fields.

### (e) Required companion: Apex MUST stamp the derived fields on clones (it already does, by copy)
P1#2 is safe ONLY IF clones still end up correctly stamped without the flows. They do, because
`createFullClone` copies the parent's stamped values. **Caveat (pre-existing, NOT a P1 regression):** for the
dominant `FIXED AMOUNT` (non-subsplit) case, freshly-created NON-split Power originals currently carry
`EndDate=null / PricingTermCount=0` (the SC-3411/3420 backstop not firing on those lines). Copy faithfully
propagates that existing ~36% null-EndDate/PTC gap onto clones — it does **not** regress (clones match a
non-split line) and it does **not** close the gap. Closing it is SC-3411/3420 scope; **do NOT block P1 on it.**
If the team wants clones to be MORE correct than the original, switch P1#2a from "copy" to "re-derive"
(mirror Set_Dates V6 logic in Apex); for no-regression, "copy" is sufficient.

---

## 4. Net per-clone CPU budget — today vs after P1, and the ceiling estimate

### Per-clone cost model
- **TODAY:** 208 `getDescribe()` + 149 `get()/put()` + **3 flow interviews** (Set_Dates, Set_Workday,
  Set_Dates-refire) + 1 SOQL + 1 DML (+ re-entrant re-save).
- **AFTER P1:** 0 `getDescribe()` (in-loop) + 149 `get()/put()` + **0 flow interviews** + 0 SOQL + 0 DML.

### Relative reduction (estimate — to be confirmed by the measurement plan below)
The two removed costs are the per-clone fixed overhead that dominates at scale:
1. **208 schema describes/clone.** `getDescribe()` is a reflection call; 208 of them per clone is the single
   largest deterministic per-clone CPU item. Removing it is the biggest win.
2. **3 flow interviews/clone.** Flow interview setup/teardown (variable init, decision eval, recordUpdate,
   re-entrant re-fire) is heavier per-interview than a field copy; 3 per clone is the second-largest item.

After P1 the per-clone work is essentially the ~149 `get()/put()` copies (cheap in-memory ops) plus the
record's share of the bulk insert. **Conservative estimate: per-clone CPU drops ~4×–10× (≈one-tenth to
one-quarter of today's cost).** Equivalently, the synchronous clone ceiling rises by a similar factor — from
the single/low-double-digit successes seen today into the **low-to-mid hundreds** before CPU is the wall again.

### The NEXT wall after P1 is DML rows, not CPU
P1 does NOT remove the 10,000-DML-rows/transaction wall (identical sync & async). With flows suppressed, the
clone-insert DML drops by the flow's 1 re-entrant row/clone, but the split still emits its own rows:
- no-partition (P3-genuine path is partition-only, but the legacy path) ~1 DML row/clone → wall ≈10,000 clones;
- partition path ~3 DML rows/clone (Phase 4 insert clones + Phase 6 insert partitions + Phase 7 update clones)
  → wall ≈3,333 clones.
So after P1, CPU stops being the binding constraint somewhere in the low hundreds–low thousands; the DML-row
wall (and the seat/sentinel decomposition mismatch) is what P2 (async+chunk) and P3 (don't explode seats)
address. The existing **MAX_SYNC_CLONES=200** cap remains a defensible conservative floor below all of these.

---

## 5. Measurement plan (to run later WITH deploy/exec authorization)

We are NOT authorized to run a live convert or measure CPU, so the §4 numbers are component estimates. To
confirm:
1. In a sandbox with auth, build a Power quote whose line has a Partition (P3-genuine) at increasing
   quantities (e.g. 10, 25, 50, 100, 150, 200). Capture `Limits.getCpuTime()` and `getDmlRows()` via a debug
   log / wrapper around the convert (or a test method that calls `PowerOrderSplittingService.processOrder`).
2. Run the convert (a) on the CURRENT class+flows (baseline), then (b) after deploying the hoisted
   `createFullClone` + the `Is_Split_Line__c=false` entry condition on both flows. Plot CPU(ms) vs clone count
   for both; the slope (ms/clone) ratio is the real per-clone reduction.
3. Verify clones are byte-identical in stamped fields between baseline and P1 (assert
   `Workday_Contract_Line_Type__c`, the 4 date fields, EndDate/PTC, prices-post-reprice) to prove suppression
   did not change output. Confirm `Get_Product` SOQL count drops by N and DML rows drop by ~N (re-entrant
   row removed).
4. Extrapolate the P1 slope to find the clone count at which CPU hits 10,000ms; confirm it now sits ABOVE the
   DML-row wall (so DML rows, not CPU, is the new ceiling), validating that P2/P3 own the remaining gap.

---

## 6. Cross-checks vs prior state (drift log)

| Item | Prior doc | LIVE 2026-06-27 | Drift |
|---|---|---|---|
| Set_Dates active version | V6 | **V6** (301WC00000knsJNYAY) | none |
| Set_Workday active version | V11 | **V11** (301WC00000kUYVFYA4) | none |
| Set_Workday subsplit logic | `$Record.Product2.Is_Subsplit_Product__c` (no reverse-lookup) | **CONFIRMED** (active V11 XML, 0 `Original_Order_Item__c`) | none (obsolete versions still carry it) |
| OrderItem field count | (n/a) | **208 total / 149 createable / 208 accessible** | new measurement |
| OrderItem triggers / VRs | 0 / 0 | **0 / 0** | none |
| Convert flow active version | V27 | **V28** Active | minor (non-material to P1) |
| Live class length | 16635 (per adversarial) | **17569** (LengthWithoutComments) live; differs from local P3 copy | expected (live=P0-only, local=P0+P3) |
| Is_Split_Line__c / Original_Order_Item__c consumers | Apex-only | **Is_Split: Layout+Apex; Original: Layout+Apex+OBSOLETE flow versions** | dependency confirms no live automation consumer |
