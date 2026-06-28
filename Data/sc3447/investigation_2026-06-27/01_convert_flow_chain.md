# SC-3447 — Convert Flow Chain Verification (read-only, 2026-06-27)

Org: FortraUAT (00DWC000006eUFF2A2). Investigator: Liam (read-only).
Scope: VERIFY THE CONVERT FLOW CHAIN of `Fortra_Quote_to_Order_Conversion` — full ordered action
sequence, transaction models, ordering (split before reprice/activate), async boundaries, and how
`PowerOrderSplittingService` is invoked + whether its result is checked.

---

## 1. Active version — NO DRIFT since 2026-06-26

`Flow` (Tooling) version history for `Fortra_Quote_to_Order_Conversion`:

| Version | Status | LastModifiedDate | LastModifiedBy | Flow Id |
|---|---|---|---|---|
| **27** | **Active** | 2026-06-09T23:23:30Z | Nir Kailash | **301WC00000kSRnZYAW** |
| 26 | Obsolete | 2026-06-09T05:55:28Z | Liam Jeong | 301WC00000kONJsYAO |
| 25 | Obsolete | 2026-06-09T05:48:31Z | Liam Jeong | 301WC00000kO7kFYAS |
| ... (24 down to 1, all Obsolete) | | | | |

The active version is **still V27 = `301WC00000kSRnZYAW`**, identical to the 2026-06-26 known state.
The convert flow itself has NOT changed since 2026-06-09 (despite heavy daily org churn elsewhere).
`apiVersion` = 62.0, `processType` = Flow (screen flow), `status` = Active.

NOTE: `FlowDefinitionView` sObject is "not supported" via this CLI/API — used `Flow` (Tooling) +
metadata retrieve instead. Retrieved metadata to
`Data/sc3447/investigation_2026-06-27/retrieve/unpackaged/flows/Fortra_Quote_to_Order_Conversion.flow`.

---

## 2. Full ordered action sequence (entry → activate)

Start element → `Get_Quote_Details` (recordLookup). The validation gauntlet (decisions/lookups, all
sync) runs first: IsSyncing → existing-order check → PricingStatus(CompletedWithPricing) → QuoteStatus
(Accepted) → BillToContact → Bill To Place → Billing Street → Ship To Place → **Validate_Checklist_Complete**.

The **Apex/DML action chain** (the part that consumes the single-request 10,000 ms CPU budget):

| # | Element | Type | actionName | flowTransactionModel | faultConnector? | Result read? |
|---|---|---|---|---|---|---|
| 1 | Validate_Checklist_Complete | apex | **ChecklistValidationService** | **CurrentTransaction** | no | yes (`isComplete` → decision) |
| 2 | Call_Create_Order_From_Quote | createOrderFromQuote | **createOrderFromQuote** | **CurrentTransaction** | yes → Screen_Error_Order_Creation_Failed | yes (`orderId` → varCreatedOrderId) |
| 3 | MapQuoteLineFieldsToOrderItems | apex | **QuoteToOrderFieldMapper** | **CurrentTransaction** | **NO** | no |
| 4 | SplitPowerOrderLines | apex | **PowerOrderSplittingService** | **CurrentTransaction** | **NO** | **NO** |
| 5 | Reprice_Order_Before_Activate (+ _No_Contract twin) | apex | **OrderRepriceInvocable** | **CurrentTransaction** | yes → Screen_Error_Order_Creation_Failed | yes (`pricingReady` → decision) |
| 6 | Activate_Order (+ _No_Contract twin) | recordUpdates | (sync Order.Status='Activated') | (record update — implicit current txn) | yes → Screen_Error_Order_Creation_Failed | n/a |

Connector trace of the hot path (auto-layout canvas):
`...Validate_Checklist_Complete → Decision → ... → Call_Create_Order_From_Quote → Assign_Created_Order_Id
→ MapQuoteLineFieldsToOrderItems → **SplitPowerOrderLines** → Get_Created_Order → Decision_Create_Contract_Record
→ (contract path) ... → Decision_Activate_Order_After_Contract → **Reprice_Order_Before_Activate**
→ Decision_Order_Priced → **Activate_Order**`.
The no-contract branch mirrors this: `Decision_Activate_Order_No_Contract → Reprice_Order_Before_Activate_No_Contract
→ Decision_Order_Priced_No_Contract → Activate_Order_No_Contract`.

**ALL FIVE Apex actions are present and ALL are `flowTransactionModel=CurrentTransaction`.** Confirmed
exactly 6 `<flowTransactionModel>` tags in the file, all `CurrentTransaction` (lines 16, 38, 63, 88, 110, 131).
The two `OrderRepriceInvocable` calls (contract / no-contract) share the same actionName, hence 5
distinct actionNames across 6 actionCall elements.

---

## 3. Ordering & async boundary

- **Split runs BEFORE reprice and activate, in the SAME transaction.** `SplitPowerOrderLines` (#4)
  connects to `Get_Created_Order`, which routes (via Decision_Create_Contract_Record and the activate
  decisions) into `Reprice_Order_Before_Activate` (#5) and then `Activate_Order` (#6). Split → reprice →
  activate is strictly sequential within one synchronous interview.
- **NO async boundary anywhere in the convert chain.** Grep for `Asynchronous`, `scheduledPath`,
  `Async`, `ScheduledActionsBuilder`, `platformEvent`/`PlatformEvent`, `Batchable`, `@future`,
  `Queueable` returned ZERO hits. The only `runInMode` in the file is `DefaultMode` (line 1353 — a
  recordUpdate/recordCreate element default, NOT a system/async context). No "Run Asynchronously" path,
  no scheduled path, no platform-event publish. Everything executes in the one synchronous screen-flow
  request → one 10,000 ms CPU budget. This is consistent with the dead-txn snapshot
  (CPU >10,000 is the limit that throws; SOQL 19/100, DML 480/10000 rows are well under).

This is the structural root cause confirmation for SC-3447: a single synchronous transaction does
order-create + field-map + per-unit split (one OrderItem + cloned Partition per unit, for-loop
`i=1..qty`) + reprice + activate, and each cloned OrderItem additionally fires two record-triggered
flows (see §5). At qty 456 (repro) and especially at the client's stated ceiling of 750,000, CPU is
exhausted long before any governor on SOQL/DML rows, and the whole interview rolls back
(FLOW_INTERVIEW_LIMIT_EXCEEDED → Apex CPU time limit exceeded).

---

## 4. PowerOrderSplittingService invocation & result handling

- **Input mapping:** single input param `orderId` ← `varCreatedOrderId` (the Id returned by
  `createOrderFromQuote`, assigned via `Assign_Created_Order_Id` from
  `Call_Create_Order_From_Quote.orderId`). So the split operates on the NEWLY CREATED order. Correct order.
- **storeOutputAutomatically=true**, so the `SplitResult` (success / linesCreated / hardwareCloned /
  partitionsCloned / errorMessage) IS stored — BUT:
  - **The output is NEVER read.** Grep for `SplitPowerOrderLines.` (any output reference) = 0 hits. No
    decision examines `success` or `errorMessage`.
  - **There is NO `faultConnector` on SplitPowerOrderLines** (and none on MapQuoteLineFieldsToOrderItems
    either). If the Apex throws an unhandled exception, the flow faults with the generic unhandled-fault
    behavior; if the class instead returns `success=false`/`errorMessage` (its own try/catch path), the
    flow IGNORES it and proceeds to reprice/activate as if nothing happened.
  - **Net: a split failure is effectively swallowed** at the flow layer — either it bubbles as a generic
    fault (no friendly screen, full rollback) or, worse, a soft failure is silently ignored and the order
    proceeds mis-split. The user gets no split-specific diagnostic. (For the CPU-limit case the whole txn
    rolls back regardless, so the user sees the platform LimitException, not a flow screen.)

### Live class confirmation (memory: repo source can be stale — verified)
- Live `ApexClass PowerOrderSplittingService` (01pWC000001xm1eYAA): ApiVersion 62,
  LengthWithoutComments 16635, LastModified 2026-06-09 by Liam Jeong. **Retrieved live body diffs from
  `force-app/main/default/classes/PowerOrderSplittingService.cls` only by a trailing newline —
  functionally IDENTICAL.** Class unchanged since 2026-06-09.
- Confirmed structure: `@InvocableMethod splitPowerOrderLines(List<SplitRequest>)` →
  `List<SplitResult>`; gate selects items where Product2.Solution_Group__c='Power' AND Quantity>1; then
  per item `for (Integer i = 1; i < qty; i++)` createFullClone → qty=1 OrderItem (+ cloned Partition,
  + Hardware for the HW split-type), setting `Original_Order_Item__c = original.Id` on each clone; Phase 5
  resets the original to Quantity=1 and `Original_Order_Item__c = null`. No OrderItem Apex triggers.

---

## 5. Per-clone amplification (re-verified, supports CPU RCA)

Record-triggered OrderItem flows that fire for every cloned line:

| Flow | Active Version | TriggerType | LastModified |
|---|---|---|---|
| Fortra_OrderItem_Set_Dates | **V6** (301WC00000knsJN…) | RecordBeforeSave | 2026-06-15 (Liam) |
| Fortra_OrderItem_Set_Workday_Contract_Line_Type | **V11** | RecordAfterSave | 2026-06-10 (Ben Kozlowski) |
| Fortra_Autolaunched_Set_Workday_Contract_Line_Type | — | (no Active version) | INACTIVE (SC-3366) |

V6/V11 match the 2026-06-26 known state. The after-save line-type flow does a Get_Product SOQL + a
recordUpdate on $Record (re-entrant re-fire of Set_Dates) per clone — so each of the (qty-1) inserted
OrderItems multiplies the synchronous CPU cost. Autolaunched dup subflow still inactive (confirmed: no
Active version returned).

---

## Drift summary vs 2026-06-26 known state
- Convert flow active version: **V27 / 301WC00000kSRnZYAW — NO DRIFT.**
- PowerOrderSplittingService: live == local (newline only) — **NO DRIFT.**
- Per-clone flows: Set_Dates V6, line-type V11, Autolaunched inactive — **NO DRIFT.**
- **ONE drift:** the documented repro quote **0Q0WC000003AuQb0AK (Q-00781200) NO LONGER EXISTS** in the
  org (0 rows by Id, by name, and 0 QLIs). A fresh high-qty Power quote must be built to reproduce.
  Does not affect the flow-chain verification.
