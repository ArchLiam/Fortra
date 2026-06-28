# SC-3447 — Hardware/Partition Reality: Is Per-Unit Splitting Ever Meaningful?

**Date:** 2026-06-27
**Org:** FortraUAT (00DWC000006eUFF2A2)
**Mode:** STRICTLY READ-ONLY (SOQL / describe only; no DML, no flow runs)
**Class under review:** `force-app/main/default/classes/PowerOrderSplittingService.cls`
**Repro:** quote `0Q0WC000003AuQb0AK` (Q-00781200), line *Abstract* `01tWC00000DD11GYAT` @ qty 456 (Power / "Order Line Only").

## BOTTOM LINE

Per-unit Hardware/Partition cloning is **vestigial / dead design**, not a real business need.

- The partition-clone branch is a **no-op for 100% of real data**: of 3,816 Power lines with qty>1, **only 4** carry a `Partition_Record__c` — and those 4 are explicitly-named UAT test records. Every real high-qty Power line has `Partition_Record__c = null`, so Phase 6/7 of the service produces nothing for production orders.
- The hardware-clone branch ("Order Line and Hardware") exists for **1 product**, and the only order that ever exercised it is literally named `"UAT Power Split Test - Order Line and Hardware --do not delete!"`.
- Power `Quantity` is a **seat/user count or an "unlimited" sentinel (999,999)**, not a machine count. Partitions are a per-MACHINE (IBM i LPAR) concept bounded by physical hardware (~2.4 partitions/machine), never per-seat. So a 7,500-seat or 999,999-sentinel line could never legitimately spawn 7,500 / 999,999 partitions or OrderItems.
- The per-unit OrderItem clone loop (Phase 1) is the **only** thing that scales 1:1 with Quantity, and it is the CPU-killer — while the partition/hardware cloning it carries is doing nothing of value.

---

## 1. Partition__c

| Metric | Value | Note |
|---|---|---|
| Total `Partition__c` records | **80,615** | |
| Partitions linked to a Hardware | 80,615 (all) | across **33,597 distinct** machines → ~2.4 partitions/machine (per-machine LPAR concept) |
| Partitions with `Partition_ID__c LIKE '%-SPLIT-%'` (service clones) | **4** | all UAT test ("UAT OLO/OLH Partition … (Split n)") |
| Partitions with `Partition_Name__c LIKE '%(Split %'` | 4 | same 4 |
| Distinct partitions referenced by ANY OrderItem (`Partition_Record__c`) | **11** | out of 80,615 — OrderItem→Partition link is essentially unused |
| Distinct partitions referenced by ANY QuoteLineItem (`Partition_Reference__c`) | **1** | |
| Power qty>1 lines with `Partition_Record__c` populated | **4** (the test ones) | the partition-clone loop is a no-op for all 3,812 real qty>1 Power lines |
| `License_Key__c` on the 4 split partitions | **null on all 4** | cloned partitions carry no meaningful licensing data |

**The 4 service-cloned partitions (all created 2026-04-16, all UAT test):**
- `PART-OLO-001-SPLIT-1/2` → "UAT OLO Partition 1 (Split 1/2)", on OrderItems for product **"5250 Integrator"** (order `801WC00000fuLa4YAE`)
- `PART-OLH-001-SPLIT-1/2` → "UAT OLH Partition 1 (Split 1/2)", on OrderItems for product **"UAT Power Split Test - Order Line and Hardware --do not delete!"** (order `801WC00000fuLa5YAE`)

**Downstream usage of cloned partitions:** none beyond the test OrderItem they sit on. `Partition__c` is referenced only by `OrderItem.Partition_Record__c` and `QuoteLineItem.Partition_Reference__c` (no Asset, no License_Key__c lookup, no subscription). Asset has **no** partition field at all (`No such column 'Partition_Record__c'/'Partition__c' on entity 'Asset'`). The 4 cloned partitions are dead-ends.

## 2. Hardware__c

| Metric | Value | Note |
|---|---|---|
| Total `Hardware__c` records | **79,042** | real, heavily-used entity (machines) |
| Distinct hardware referenced by ANY OrderItem (`Hardware__c`) | **10,921** | original/shared machine refs, broadly used |
| Hardware with `Serial_Number__c LIKE '%-SPLIT-%'` | **12** | all UAT test data |
| — of those, actually produced by the service (`serial + '-SPLIT-' + index`) | **2** | `SN-UAT-OLH-059786-SPLIT-1/2` (2026-04-16) |
| — the other 10 (`SN-UAT-SPLIT-001`) | seed/test rows | NOT the service's `…-SPLIT-<index>` pattern; pre-seeded test data |
| Power qty>1 lines with `Hardware__c` populated | 2,871 | but this is the **original/shared** machine; multiple lines share the same Hardware Id (one machine, many seat-lines) |
| Split lines (`Is_Split_Line__c=true`) with `Hardware__c` | 18 | all in test orders |
| License_Keys on the 2 service-cloned hardware | **0** | |
| Assets on the 2 service-cloned hardware | **0** | dead-ends, no downstream consumption |

**"Order Line and Hardware" path is effectively dead:** only **1** of 3,406 Power products is split-type "Order Line and Hardware" (per prior verification). The only order that exercised the hardware-clone branch is `801WC00000fuLa5YAE`, whose product is named **"UAT Power Split Test - Order Line and Hardware --do not delete!"**. The 2 cloned hardware records it produced have zero License_Keys and zero Assets. The path has never been used by a real customer order.

## 3. OrderItem field describe (service/flow dependencies)

All fields the service and record-triggered flows write **exist with correct types and are settable in Apex** (createable=true, updateable=true, calculated=false), EXCEPT a few read-only/calculated ones the service does not touch:

| Field | Type | Createable | Updateable | Calculated | Notes |
|---|---|---|---|---|---|
| `Is_Split_Line__c` | boolean | yes | yes | no | settable ✓ |
| `Original_Order_Item__c` | reference→OrderItem | yes | yes | no | qty-split FK ✓ |
| `Partition_Record__c` | reference→Partition__c | yes | yes | no | settable ✓ (but null on all real data) |
| `Hardware__c` | reference→Hardware__c | yes | yes | no | settable ✓ |
| `Manual_Discount__c` | currency | yes | yes | no | settable ✓ |
| `Displaced_ARR__c` | currency | yes | yes | no | settable ✓ |
| `Workday_Contract_Line_Type__c` | picklist | yes | yes | no | settable ✓ (stamp on clones if flows suppressed) |
| `PricingTermCount` | double (18,2) | yes | yes | no | **settable on OrderItem** ✓ (contrast SC-3415/3420 where it was read-only in flow context) |
| `Quantity` | double | yes | yes | no | settable ✓ |
| Billing dates: `Billing_Schedule_From_Date__c`, `Billing_Schedule_To_Date__c` | date | yes | yes | no | settable ✓ |
| `EndDate`, `ServiceDate` (Start), `End_Date_Calculated__c`, `Start_Date_Calculated__c` | date | yes | yes | no | settable ✓ |
| `SubscriptionTerm`, `Is_Term__c` | int/bool | yes | yes | no | settable ✓ |

**Read-only / calculated (cannot be set in Apex) — service does not touch these:**
- `Billing_Frequency__c` (string, calculated, read-only) — distinct from settable `BillingFrequency2` (picklist).
- `Two_Years_After_Start_Date__c`, `Year_After_StartDate__c` (boolean, calculated).
- System: `CreatedDate`, `LastModifiedDate`, `EndDateTime`, `ServiceDateTime` (read-only).

Implication for the fix: if record-triggered flows are suppressed on clones (P1 of the fix roadmap), the Apex clone path **can** stamp every derived field (line-type, billing/term dates, PTC) directly — none of them are blocked by being calculated/read-only.

## 4. Business inference — is per-unit tracking ever needed?

### Evidence it is NOT a real need (dominant)
1. **Partition clone loop is a no-op for all real data.** 3,812 of 3,816 real qty>1 Power lines have `Partition_Record__c = null`. The 4 that don't are UAT tests. So splitting never creates partitions for production orders.
2. **Top 30 highest-qty Power lines are ALL qty=999,999 ("unlimited" sentinel)** on "Powertech Password Self Help for IBM i", split-type "Order Line Only", **every one with `Partition_Record__c = null`**, all on a single order (`801WC00000hJpqmYAC`). Several share the same Hardware Id (one machine, many unlimited-seat lines). Splitting 999,999 into 999,999 OrderItems is both impossible (10k DML-row cap) and semantically absurd.
3. **Realistic high-qty lines are clearly seat counts:** 99,999 (Insite Analytics), 9,999 (Sequel Repository), 9,900 (Powertech MFA), 7,500 / 5,800 / 5,080 / 4,875 (Password Self Help / Safestone PSH "Users"). Product names ("…Self Help **Users**", "…Multi-Factor Authentication") and the QLI field `Users_Per_Partition__c` confirm Quantity = user/seat count.
4. **Partitions are per-MACHINE, not per-seat.** 80,615 partitions / 33,597 machines ≈ 2.4 partitions/machine. There is no data anywhere of thousands of partitions for one license line. A 7,500-seat line maps to a handful of LPARs, not 7,500 records.
5. **The only "real-looking" splits are tiny per-machine counts.** The most recent `Is_Split_Line__c=true` rows (June 22-24, "Powertech Authority Broker for IBM i") are 2-6 clones per order with null Partition_Record__c — consistent with a per-machine (not per-seat) split, the legitimate small-N use case.
6. **Cloned hardware/partitions have no downstream consumers** (no Assets, no License_Keys, not on QLI). Even when the clone path ran (test data), nothing consumed the output.

### Evidence it MIGHT be needed (weak / bounded)
1. Hardware is a real, broadly-used entity (10,921 distinct on OrderItems; 79,042 total; referenced by Asset, License_Key, Partition, QLI). Per-machine tracking is legitimate — but that is bounded by the number of physical machines (small N), not by seat quantity.
2. A genuine "one line per physical machine" scenario exists (the June Authority Broker splits @ 2-6) — but that quantity is the machine count, which is small, and even there partitions are null.
3. License keys exist (664) and hang off Hardware — so per-machine licensing is real; but again machine-scoped, not seat-scoped, and never produced by the seat-quantity split loop.

### Conclusion
For a 7,500-seat license or a 999,999 "unlimited" sentinel, there is **no evidence** the org needs 7,500 / 999,999 Partition or OrderItem records. The count is purely a **license/seat quantity that belongs on ONE line** (or, at most, one line per physical machine — a small count, never the seat count). The per-unit OrderItem split that scales with Quantity is the CPU/DML hazard, and the Hardware/Partition cloning it carries adds zero value for the real data set. The real fix (P3) — confirm Quantity semantics with the business, restrict any split to genuine per-machine cases, and aggregate/keep-on-one-line the seat counts — is supported by the data.

---

## Query provenance (all read-only, FortraUAT, 2026-06-27)

- `SELECT COUNT() FROM Partition__c` → 80,615
- `SELECT COUNT() FROM Hardware__c` → 79,042
- `SELECT COUNT() FROM Partition__c WHERE Partition_ID__c LIKE '%-SPLIT-%'` → 4
- `SELECT COUNT() FROM Hardware__c WHERE Serial_Number__c LIKE '%-SPLIT-%'` → 12 (only 2 are service `…-SPLIT-<idx>` output)
- `SELECT COUNT() FROM OrderItem WHERE Is_Split_Line__c=true` → 66; with Partition_Record__c → 4; with Hardware__c → 18
- `SELECT COUNT_DISTINCT(Partition_Record__c) FROM OrderItem WHERE Partition_Record__c!=null` → 11
- `SELECT COUNT_DISTINCT(Hardware__c) FROM OrderItem WHERE Hardware__c!=null` → 10,921
- Power qty>1 lines: 3,816; qty>50: 553; qty>=1000: 192; qty=999999: 134
- Power qty>1 with Partition_Record__c: 4; with Hardware__c: 2,871
- Partition_Record__c populated OrderItems all point to test orders `801WC00000fuLa4YAE` / `801WC00000fuLa5YAE` (products "5250 Integrator", "UAT Power Split Test - Order Line and Hardware --do not delete!")
- License_Keys/Assets on the 2 service-cloned hardware → 0 / 0
- `Partition__c` child relationships: only OrderItem.Partition_Record__c + QuoteLineItem.Partition_Reference__c (no Asset)
- Describe JSONs cached in scratchpad: `orderitem_describe.json`, `partition_describe.json`, `hardware_describe.json`
