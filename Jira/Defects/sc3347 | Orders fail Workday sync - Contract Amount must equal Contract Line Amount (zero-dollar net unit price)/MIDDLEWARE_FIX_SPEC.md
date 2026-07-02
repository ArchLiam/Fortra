# SC-3347 — Middleware fix spec (Workday `Submit_Customer_Contract` line-amount mapping)

**For:** the **MuleSoft** integration team that owns the `Order_Completed_WD__e` → Workday `Submit_Customer_Contract` builder (Connected App *"Mulesoft Integration"*, API user `svc.mulesoft@fortra.com.uat`; owner contact **keith.irwin@fortra.com**; SC-3143 epic assignee **Andy Kumar**). The payload mapping lives in the MuleSoft flow, **not** in Salesforce.
**Problem:** the per-line `extendedAmount` is sourced from the **gross/list** order-line amount, while the header and `unitCost` are **net**. Any line where **net < list** (a discount or a $0 write-down) makes `SUM(extendedAmount) ≠ header` → Workday rejects with *"Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract."*

## Current (buggy) mapping — observed from the logged payload on Order 00095355

| Payload field | Sourced from (Salesforce) | Base | Example (00095355 L2) |
|---|---|---|---|
| `currentContractAmount` (header) | `Order.TotalAmount` | **net** | 3150 |
| line `unitCost` | `OrderItem.NetUnitPrice` | **net** | **0** |
| line `extendedAmount` | `OrderItem.TotalLineAmount` | **list/gross** ← bug | **3150** |
| line `quantity` | `OrderItem.Quantity` | — | 1 |

Result: `SUM(extendedAmount) = 3150 + 3150 = 6300 ≠ header 3150`; and L2 `unitCost×qty = 0 ≠ extendedAmount = 3150`.

> Note: across older orders the same field has been buggy in a *different* way (payloads on 00004792/00004800 sent `extendedAmount = 0` on every line). So the fix is to **pin the invariant**, not just swap one field.

## Required mapping (fix)

Source the line amount from the **net** line total so it is consistent with `unitCost` and the header:

```
line.unitCost        = OrderItem.NetUnitPrice
line.quantity        = OrderItem.Quantity
line.extendedAmount  = OrderItem.NetTotalPrice        # == NetUnitPrice * Quantity  (NOT TotalLineAmount)
header.currentContractAmount = Order.TotalAmount      # already net (== SUM(NetTotalPrice)); unchanged
```

**Invariant that must hold for every submission:**
```
extendedAmount  == round(unitCost * quantity, 2)        # per line
SUM(extendedAmount across lines) == currentContractAmount   # header == sum of lines
```

`OrderItem.NetTotalPrice` already equals `NetUnitPrice × Quantity` in Salesforce (verified), so using it satisfies both the per-line and the header equality in one change.

## Worked check — what the fixed 00095355 payload should look like

| line | unitCost (NetUnitPrice) | qty | extendedAmount (NetTotalPrice) | consistent? |
|---|---|---|---|---|
| 1 | 3150 | 1 | 3150 | ✓ |
| 2 | 0 | 1 | **0** (was 3150) | ✓ |

`SUM(extendedAmount) = 3150 + 0 = 3150 == header 3150` ✓ → Workday accepts.

## Test orders (FortraUAT)

| Order | Condition | Expected after fix |
|---|---|---|
| **00095355** | one $0-net line (extreme) | `extendedAmount` L2 = 0; header == sum; **Success** |
| **00095353** | $0 lines **and** a real 10% discount line (Monitoring) | every `extendedAmount` = net; **Success** |
| A healthy order (e.g. **00095354**) | all net = list | no change; still **Success** (regression check) |

## Validation after deploy (read-only, Salesforce side)

1. Re-publish `Order_Completed_WD__e` (`Order_Id__c = <id>`) for each test order to resubmit against live data.
2. Confirm `Order.Workday_Sync_Status__c = Success`.
3. Re-pull `Workday_Sync_Payload__c` and assert the invariant (`SUM(extendedAmount) == currentContractAmount`, no line with `unitCost×qty ≠ extendedAmount`).
4. Sweep the 13 Pending net<list orders (see `evidence/payloads.md`) and confirm they now submit cleanly.

## Open dependency (separate from this mapping fix)

- **Order 00095354 "Internal Error"** is a *different* failure (healthy lines; payload logged as a bare Contact Id). It needs the **middleware error log** for correlation id `ad1783c0-61cf-11f1-b9c9-96583158e4d0` to root-cause. Not fixed by this mapping change.
