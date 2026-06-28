# SC-3447 — Per-Clone OrderItem Automation Verification (read-only, FortraUAT)

Date: 2026-06-27
Org: FortraUAT (00DWC000006eUFF2A2), liam.jeong.c@fortra.com.uat
Method: live read-only queries (FlowDefinitionView, ApexTrigger, ValidationRule via Tooling, FieldDefinition) + `sf project retrieve start` of flow XML. No mutations.
Retrieve artifact: `Data/sc3447/investigation_2026-06-27/retrieve/unpackaged/flows/`

---

## TL;DR

The CPU amplifier is confirmed structural and the proposed fix is SAFE.

- Exactly **two** active record-triggered flows fire on OrderItem **insert** (per Power clone):
  `Fortra_OrderItem_Set_Dates` (V6, RecordBeforeSave) and
  `Fortra_OrderItem_Set_Workday_Contract_Line_Type` (V11, RecordAfterSave).
- **Neither has any entry/start filter today** — both fire on every OrderItem insert AND update.
- `Set Workday` (after-save) does **1 SOQL (Get_Product) + 1 recordUpdate on $Record** for a Power line; the recordUpdate is a real DML that re-saves the record → **re-fires the before-save Set Dates** flow (the documented re-entrancy). For the rare services branch it does a 2nd SOQL; Power lines are non-services so the per-clone cost is 1 SOQL + 1 DML.
- `Set Dates` (before-save) does **0 SOQL / 0 DML** (in-memory `$Record` assignments only).
- The clones already inherit the parent's stamped values via `createFullClone` (copies ALL createable fields from the already-stamped original). The original is inserted and flow-stamped in `createOrderFromQuote` **before** `splitPowerOrderLines` clones it. So re-running both flows on each clone is **pure redundant CPU**.
- `Fortra_Autolaunched_Set_Workday_Contract_Line_Type` = **Draft (inactive)**; its only caller `Fortra_Order_After_Save_Set_Workday_Contract_Line_Type` = **Obsolete (inactive)**. No live flow invokes the subflow.
- **No OrderItem Apex triggers, no active OrderItem validation rules, no active flows on the clone children (OrderItemAttribute / Partition__c).**
- Adding entry condition `Is_Split_Line__c = false` to BOTH flows is SAFE: clones carry `Is_Split_Line__c = true` at insert (set in memory before Phase-4 insert), so they'd be skipped; the original is `Is_Split_Line__c = false`, so it still gets stamped; clones inherit identical stamped values by copy.

---

## 1. All record-triggered flows on OrderItem ("Order Product")

Query: `SELECT ApiName, TriggerType, RecordTriggerType, IsActive, ActiveVersionId, VersionNumber, TriggerOrder FROM FlowDefinitionView WHERE TriggerObjectOrEventLabel='Order Product'`

| ApiName | TriggerType | RecordTriggerType | Active | Active Version Id | Ver | Entry/start filter |
|---|---|---|---|---|---|---|
| Fortra_OrderItem_Set_Dates | RecordBeforeSave | CreateAndUpdate | true | 301WC00000knsJNYAY | 6 | NONE |
| Fortra_OrderItem_Set_Workday_Contract_Line_Type | RecordAfterSave | CreateAndUpdate | true | 301WC00000kUYVFYA4 | 11 | NONE |
| Order_Product_Disallow_delete_for_Globalscape_Integration_User | RecordBeforeDelete | Delete | true | 301WC00000gGIbuYAG | 1 | n/a (delete-only, irrelevant to insert) |

- Only the first two fire on insert. Both versions match the 2026-06-26 known state (V6, V11) — **no drift**.
- TriggerOrder is blank (null) on all three → default ordering.
- **Neither insert flow has a `<start><filters>` block.** The `Set Dates` XML has 0 `<filters>`/`filterLogic`. The `Set Workday` XML has 2 `<filters>` blocks but both are inside `recordLookups` (Get_Product `Id` filter, Get_Prepaid_Order_Attribute `OrderItemId` filter) — NOT entry conditions. The `<start>` block contains only connector/object/recordTriggerType/triggerType.

No active flows on the clone child objects: query for `TriggerObjectOrEventLabel IN ('Order Product Attribute','Partition') AND IsActive=true` returned **0 rows**.

---

## 2. Fortra_OrderItem_Set_Workday_Contract_Line_Type — V11 trace

- Active version confirmed: V11, id `301WC00000kUYVFYA4`. RecordAfterSave, CreateAndUpdate, AutoLaunchedFlow, apiVersion 66.0. `HasAsyncAfterCommitPath=false` (runs in the same synchronous transaction → counts against the convert flow's 10,000ms CPU budget).
- Element graph (start → Get_Product):
  1. `Get_Product` (recordLookup, Product2 by `$Record.Product2Id`) — **SOQL #1**, always runs.
  2. `Decision_Is_Services_Product` (reads `Get_Product.pse__IsServicesProduct__c`).
     - Yes → `Get_Prepaid_Order_Attribute` (recordLookup OrderItemAttribute by `$Record.Id`) — **SOQL #2 (services only)** → Decision_Is_Prepaid_Service → PREPAID or USAGE BASED recordUpdate.
     - No (Power lines are non-services) → `Decision_Is_Subsplit`.
  3. `Decision_Is_Subsplit` reads `$Record.Product2.Is_Subsplit_Product__c` (cross-object on `$Record`, **no extra SOQL**).
     - Yes → `Update_LineType_Fixed_Amount_Billing_Only` (recordUpdate $Record).
     - No → `Update_LineType_Fixed_Amount` (recordUpdate $Record).

- **Per-invocation cost for a Power clone** (non-services, non-subsplit): **1 SOQL (Get_Product) + 1 recordUpdate on $Record (DML)** that stamps `Workday_Contract_Line_Type__c = 'FIXED AMOUNT'`.
- The recordUpdate uses `<inputReference>$Record</inputReference>` in an **after-save** flow → it issues a real DML update on the just-saved record → **re-triggers the before-save `Fortra_OrderItem_Set_Dates`** (CreateAndUpdate). This is the re-entrancy / cascade documented in MEMORY. So each clone effectively runs: Set Dates (insert) + Set Workday (after-save: 1 SOQL + 1 DML) + Set Dates again (re-fired by the after-save DML).
- Worst case (services prepaid line) the after-save flow would be 2 SOQL + 1 DML, but Power lines never hit that branch.

---

## 3. Fortra_OrderItem_Set_Dates — V6 trace

- Active version confirmed: V6, id `301WC00000knsJNYAY`. **RecordBeforeSave**, CreateAndUpdate, AutoLaunchedFlow, apiVersion 67.0.
- **0 SOQL, 0 DML.** Only `<recordUpdates>` with `<inputReference>$Record</inputReference>` (before-save in-memory writes — free, no DML). Uses cross-object formula refs (`$Record.Order.EffectiveDate`, `$Record.Product2.Rev_Category__c`, `$Record.ProductSellingModel.SellingModelType`) — no explicit lookups.
- Fields it stamps:
  - **Non-perpetual path** (`Non_Perpetual_Set_Dates`): `Billing_Schedule_From_Date__c`, `Billing_Schedule_To_Date__c`, `End_Date_Calculated__c`, `Start_Date_Calculated__c` (From = ServiceDate else Order.EffectiveDate; To = EndDate else From+12mo-1).
  - **Perpetual path** (`Perpetual_Set_Dates`, Product2.Rev_Category__c = RC_41000): same 4 fields all = `Order.EffectiveDate`.
  - **Termed backstop** (`Backstop_Std_Term_Fields`, SellingModelType=TermDefined AND EndDate null OR PricingTermCount null): `EndDate` = calculated To date, `PricingTermCount` = 1 (the SC-3411 backstop).
- Because it's before-save with no SOQL/DML, its CPU cost is modest per call, but at ~455 clones × (initial fire + re-fire from the after-save DML) it is part of the aggregate that blows the 10,000ms budget.

---

## 4. Autolaunched / Order-level Workday line-type flows — status

| ApiName | Object | TriggerType | Status | Notes |
|---|---|---|---|---|
| Fortra_Autolaunched_Set_Workday_Contract_Line_Type | OrderItem (collection) | (autolaunched) | **Draft (inactive)**, V7 | "(Deprecated)" label. Deactivated since 2026-06-08 (SC-3366). |
| Fortra_Order_After_Save_Set_Workday_Contract_Line_Type | **Order** | RecordAfterSave / Update | **Obsolete (inactive)**, V1 | Only flow that has `<subflows><flowName>Fortra_Autolaunched_Set_Workday_Contract_Line_Type</flowName>`. Inactive → no live caller. |

- Grep of all retrieved flow XML for `<subflows>` / `<flowName>` found the Autolaunched subflow referenced **only** by the Obsolete `Order_After_Save` flow. No active flow invokes it. Confirmed.

---

## 5. Other OrderItem-insert automation (triggers / VRs / processes / rollups)

- **Apex triggers on OrderItem:** `SELECT Id, Name, Status FROM ApexTrigger WHERE TableEnumOrId='OrderItem'` → **0 rows**. None.
- **Validation rules on OrderItem:** `SELECT Id, ValidationName, Active FROM ValidationRule WHERE EntityDefinition.QualifiedApiName='OrderItem'` → **0 rows**. None active.
- **Other active OrderItem record-triggered flows:** only the three in section 1 (two insert flows + one delete-only). No after-insert async paths (`HasAsyncAfterCommitPath=false` on both).
- **Clone children:** no active flows/triggers on OrderItemAttribute or Partition__c.
- No rollup-summary recompute flows on OrderItem insert were found.

Conclusion: the per-clone automation surface = exactly the two flows in sections 2–3.

---

## 6. Safety of `Is_Split_Line__c = false` entry condition

`Is_Split_Line__c` is a **Checkbox** on OrderItem (confirmed via FieldDefinition). `Original_Order_Item__c` is a Lookup(Order Product). Both are populated by `PowerOrderSplittingService`:

- `PowerOrderSplittingService.cls:162-163` — each qty-1 **clone** is built in memory with `Is_Split_Line__c = true; Original_Order_Item__c = original.Id;` BEFORE the Phase-4 `insert newItems` (line 214). So at the moment the before-save and after-save flows evaluate, a clone's `Is_Split_Line__c = true`.
- `PowerOrderSplittingService.cls:233-234` — the **original** (slot 0) is updated in Phase 5 with `Is_Split_Line__c = false; Original_Order_Item__c = null;`. So the original is `false`.

Execution order (convert flow connector chain, all CurrentTransaction / one sync request):
`Get_Quote_Details` → `Call_Create_Order_From_Quote` (createOrderFromQuote — **inserts originals; both flows fire and stamp the originals**) → `MapQuoteLineFieldsToOrderItems` → `SplitPowerOrderLines` (**clones the already-stamped originals**) → `Get_Created_Order` → Reprice → Checklist → Activate.

Do clones need the same stamped values? **Yes — and they already get them by copy, not by flow.**
- `createFullClone` (`PowerOrderSplittingService.cls:363-380`) copies **every createable field** from the original. The original was queried with a dynamic ALL-accessible-fields SOQL (`queryOrderItemsToSplit`, lines 334-358), so the queried original already carries the flow-stamped values (`Workday_Contract_Line_Type__c`, `Billing_Schedule_From_Date__c`, `Billing_Schedule_To_Date__c`, `End_Date_Calculated__c`, `Start_Date_Calculated__c`, `EndDate`, `PricingTermCount`) from its own insert. Those values are copied onto every clone.
- Therefore the per-clone flow runs are **redundant** for the stamped fields — the clone would carry identical values whether or not the flows run on it.

Does anything downstream depend on the flows running on clones?
- No. No trigger/VR/rollup/active flow consumes a side effect that only the per-clone flow run produces. The only consumer of `Workday_Contract_Line_Type__c` is Workday integration, which reads the stamped value (present via copy) at order-complete time. Dates are read by billing/activation, also present via copy.
- One nuance: after the entry condition is added, the **original** (slot 0, `Is_Split_Line__c=false`) still runs both flows on its insert AND on its Phase-5 update — so the original stays correctly stamped. Only the (qty-1) clones are skipped. This is exactly the redundant work we want to eliminate.

Edge cases / caveats for the implementer:
- The Phase-5 update of the original flips `Is_Split_Line__c true→false`? No — the original is never `true`; it's set to `false`. So the original's update with `Is_Split_Line__c=false` still passes the `=false` entry filter and re-stamps (harmless, 1 record/line).
- The entry filter must be added to **both** flows. Adding it to only the after-save Workday flow would still leave Set Dates re-firing per clone via the after-save DML — but with the Workday flow skipped on clones, the after-save DML on clones no longer happens, so Set Dates re-fire on clones also stops. Still, the cleanest fix adds the filter to both so Set Dates is skipped on the clone's initial insert too.
- `Is_Split_Line__c=false` as a Checkbox: in Flow entry conditions, evaluate against boolean `false`. (Power originals and all non-split lines are `false` by default, so all normal OrderItems remain covered.)
- This is a flow-only mitigation; it removes the redundant ~455×(before+after+refire) flow executions. Combined with PowerOrderSplittingService already being bulk-safe (fixed SOQL/DML budget, no per-row DML), it directly targets the CPU consumer. It does NOT by itself fix the deeper "1 OrderItem per unit at qty up to 750k" scaling problem (that needs the async/redesign track), but it removes the flow-side amplification for moderate quantities.

---

## Cross-checks vs known state (2026-06-26)

- Set Dates V6 / Set Workday V11 active version numbers + ids: **match, no drift.**
- Autolaunched INACTIVE: confirmed (Draft). Order_After_Save: confirmed Obsolete (Order object, not OrderItem).
- No OrderItem Apex triggers: confirmed.
- PowerOrderSplittingService gate (Solution_Group__c='Power' AND Quantity>1) and per-unit clone + Original_Order_Item__c FK: confirmed in source.
