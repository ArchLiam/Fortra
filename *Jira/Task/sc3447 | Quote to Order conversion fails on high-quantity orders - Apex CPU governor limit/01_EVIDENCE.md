# SC-3447 — Evidence & Data

All evidence gathered read-only from live FortraUAT on 2026-06-18.

## Repro

- **Quote:** `0Q0WC000003AuQb0AK` (Q-00781200, "Q-Cypress Test Opportunity - 3prod-2026-06-18"), Status = Accepted, CalculationStatus = CompletedWithPricing, GrandTotal 1,990,187.
- **Action:** Convert Quote to Order (Automatic activation chosen).
- **Result:** fails every attempt; no Order persists (full rollback).

### Quote lines
| Product | Product2Id | Solution Group | Qty | Splits? |
|---|---|---|---|---|
| Abstract | 01tWC00000DD11GYAT | **Power** | 456 | ✅ 455 clones |
| Accelerated | 01tWC00000DD11HYAT | Managed File Transfer | 3,425 | ❌ |
| Powertech IAM (BoKS) – NewMaintenance | 01tWC00000DD1bsYAD | — | 1 | ❌ (qty 1) |
| Powertech IAM (BoKS) | 01tWC00000DD1btYAD | — | 1 | ❌ (qty 1) |

## The error (FINEST log)

Main convert log: **`07LWC00000PCXmd2AH`** — 19.5 MB, 88,541 lines, duration 46,801 ms.

```
line 86274 | EXCEPTION_THROWN | System.LimitException: Apex CPU time limit exceeded
            | error.cause   = FLOW_INTERVIEW_LIMIT_EXCEEDED
            | error.type    = FLOW_INTERVIEW_LIMIT_EXCEEDED
            | error.message = Apex CPU time limit exceeded
            | error.errorId = 1545545860-178253
```

Last cumulative checkpoint before the throw: `Maximum CPU time: 8277 / 10000 *** CLOSE TO LIMIT`,
then the loop pushes past 10,000 ms.

- **Org entitlements ruled out:** all 72 org named-limits healthy, none > 90% used, none RLM-specific.
  The "feature limit" modal text is just Salesforce's generic rendering of `LIMIT_EXCEEDED`.

## What consumed the CPU (one synchronous transaction)

| Metric | Value |
|---|---|
| Distinct OrderItem (`802…`) clones touched before death | **401** |
| Distinct flow interview GUIDs | **1,293** |
| DML rows | 480 / 10,000 |
| DML statements | 19 / 150 |
| SOQL queries | 19 / 100 |
| CPU | **> 10,000 / 10,000 (breach)** |

### Flow interviews fired per clone (the multiplier)
| Flow | Interviews | Status |
|---|---|---|
| `Fortra \| OrderItem \| Set Dates` (V6) | 409 | active |
| `(Deprecated) Autolaunched \| Set Workday Contract Line Type` | 408 | **redundant duplicate** |
| `Fortra \| OrderItem \| Set Workday Contract Line Type` (V11) | 209 | active |
| Order-level flows (sync status, platform event, payment terms, …) | ~67 | — |
| **Total** | **~1,293** | |

The deprecated Autolaunched line-type subflow is ~⅓ of all interviews — the **same** dead duplicate
flagged in SC-3366.

## The splitting algorithm (`PowerOrderSplittingService.cls`, retrieved)

Class doc:
> Service class for splitting Power order lines during Quote-to-Order conversion. When a Power product
> order line has quantity > 1, this service splits it into individual lines (qty=1 each) and handles
> associated Hardware and Partition records.
> Split types — "Order Line Only": lines split, Hardware SHARED, Partitions CLONED · "Order Line and
> Hardware": lines split, Hardware CLONED, Partitions CLONED.

The gate (`queryOrderItemsToSplit`, ~line 349):
```apex
String solGroup = SOLUTION_GROUP_POWER;        // = 'Power' (hardcoded constant)
... FROM OrderItem
    WHERE OrderId IN :orderIds
      AND Product2.Solution_Group__c = :solGroup
      AND Quantity > 1
```

The clone loop (~line 156):
```apex
// Create (qty - 1) clones. The original counts as slot 0; clones are slots 1..qty-1.
for (Integer i = 1; i < qty; i++) {
    OrderItem splitItem = createFullClone(original);   // copies ~150 createable fields
    splitItem.Quantity = 1;
    splitItem.Is_Split_Line__c = true;
    splitItem.Original_Order_Item__c = original.Id;
    newItems.add(splitItem);
}
// + cloneHardwareRecord() per clone when split type = "Order Line and Hardware"
// + clonePartitionRecord() per clone
```

DML structure (`processOrders`): `insert newHardwareRecords` → `insert newItems` → `update
originalsToUpdate` → `insert newPartitions` → `update itemsToUpdatePartition` → clear
`Order.ValidationResult`. Wrapped in a savepoint; on any exception `Database.rollback(sp)`.

**Cost drivers:** (1) clone count = `Σ(qty − 1)` over Power lines; (2) `createFullClone` rebuilds a
~150-field describe map and copies every field per clone; (3) three per-record flows re-run on every
clone; (4) all of it on the **synchronous** convert request (10,000 ms ceiling).

## Ruled out
- Org/license entitlement limit (entitlements healthy).
- The previously-resolved convert defect (different mechanism).
- High quantity *alone* — non-Power high-qty lines (Accelerated 3,425; Endpoint DLP 750,000) do not split.
