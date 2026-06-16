# SC-3419 — L2 Evidence: Order 00095470 + Asset-Pipeline State (FortraUAT)

Captured: 2026-06-16 (read-only `sf data query`). Org: FortraUAT. Order Id 801WC00000kYmw8YAC.
Grounds AC5 baseline (00095470 expects 32 Assets after de-dup) and AC1/AC2 context.

---

## 1. Order state (Q1)
```
Id            801WC00000kYmw8YAC
OrderNumber   00095470
Status        Order Complete
StatusCode    Activated
ActivatedDate 2026-06-11T13:27:30.000+0000
Order_Integration_Error_Messages__c   null      <-- AC1 visibility field NOT yet runtime-exercised on this order
Workday_Sync_Status__c                Pending
TotalAmount   4189
```
Reads exactly as the silent-swallow defect: Activated + "Order Complete" with NO surfaced error and (per Q3) zero assets of its own. Field null => V14 fault path has not fired on 00095470 yet (no re-trigger has occurred since the V14 deploy 2026-06-15).

## 5. Contract (Q5)
```
Contract 800WC00000S9jqbYAB (00069266)  Status = Activated
```

---

## 2. 32 OrderItems — line composition (Q2)

Group-by confirms the 4-SKU x10/10/6/6 = 32 profile:

| ProductCode          | Product2Id          | SellingModelType | lineCount | sum(Qty) | ServiceDate | EndDate     | PricingTermCount | IsAssetizable |
|----------------------|---------------------|------------------|-----------|----------|-------------|-------------|------------------|---------------|
| PIA-PIA-NRPS-PIAP    | 01tWC00000DD1btYAD  | OneTime          | 10        | 10       | null        | null        | 0                | true          |
| PIA-PIA-RNM-PIAMBK   | 01tWC00000DD1bsYAD  | OneTime          | 10        | 9*       | null (9)/2026-06-11 (1) | null    | 0/null           | true          |
| HRM-HRM-RSL-SEAW     | 01tWC00000DD1fiYAD  | TermDefined      | 6         | 6        | 2026-06-11  | 2027-06-10  | 1                | true          |
| HRM-HRM-RSL-CLSAAS   | 01tWC00000DD17PYAT  | TermDefined      | 6         | 6        | 2026-06-11  | 2027-06-10  | 1                | true          |
| **TOTAL**            |                     |                  | **32**    |          |             |             |                  | all true      |

\* PIAMBK sum(Qty)=9 not 10: nine lines qty=1, ONE line (802WC00000Og2R2YAJ) qty=0 with ServiceDate=2026-06-11, EndDate=null, PricingTermCount=null. This is the maintenance-decomposition / amendment artifact line (see Q4).

- All 32 lines `IsAssetizable=true` (every line SHOULD assetize → AC2).
- 20 OneTime (PIAP+PIAMBK) + 12 TermDefined (SEAW+CLSAAS). TermDefined lines are future-spanning (Service 2026-06-11 → End 2027-06-10) — the "future-dated lines" of AC2.
- Heavy same-Product2 duplication (10 identical PIAP lines, 10 identical PIAMBK lines, etc.) is the optimistic-lock collision driver: all duplicates of a SKU map (AccountId+Product2Id) onto ONE Asset row.

## 4. Maintenance decomposition evidence (Q4)
- OrderItemDetail rows on this order = **2**, BOTH on the single qty=0 PIAMBK line 802WC00000Og2R2YAJ:
  - qty **+1**, EffectiveFrom 2026-06-11, TotalLineAmount 0
  - qty **-1**, EffectiveFrom 2026-06-15, TotalLineAmount 0   (the -1 / 2026-06-15 matches the SC-3415 FINEST rollback test date)
- This +1/-1 netting on PIAMBK (the RNM "renewal maintenance" SKU) is the decomposition/amendment signature.
- Decomposition/parent FK linkage among the 32 lines: **0 lines** have OriginalOrderItemId, ParentOrderItemId, or Original_Order_Item__c populated (no license→maintenance FK split recorded on these lines).
- PIAMBK qty distribution: {1: 9, 0: 1}.

---

## 3. Asset pipeline for this order / account (Q3)

### 3a. AssetActionSource for the 32 OrderItems  →  **0 rows**
`SELECT COUNT(Id) FROM AssetActionSource WHERE ReferenceEntityItemId IN (<the 32 OrderItems>)` = **0**.
=> NO asset-pipeline records were generated for any of this order's 32 lines. (Confirms silent swallow: assetization never produced a source row.)

### 3b. AssetAction referencing these 32 OrderItems  →  **0**
The recent AssetActions on the 4 SKUs' assets (2026-06-09 / 2026-06-15) have AssetActionSource.ReferenceEntityItemId in {802WC00000OpoppYAB, 802WC00000OZLOnYAP, 802WC00000OZLOrYAP, 802WC00000N0xTYYAZ, ...} — all from OTHER orders. None of 00095470's 32 OrderItems appear.

### 3c. Asset on account 001WC00000XiZP4YAN
- **Account total Asset count = 1994** (large pre-existing asset pool → the collision background).
- Assets for THIS order's 4 SKUs on the account = **5 total** (and SEAW has 0):

| ProductCode          | Product2Id          | acct asset cnt | notable rows (Status / SystemModstamp / Lifecycle)                          |
|----------------------|---------------------|----------------|------------------------------------------------------------------------------|
| PIA-PIA-NRPS-PIAP    | 01tWC00000DD1btYAD  | 2              | Installed/2026-06-09T16:39 (Start 2026-06-05); Installed/2026-06-15T20:32 (Start 2026-06-15) |
| PIA-PIA-RNM-PIAMBK   | 01tWC00000DD1bsYAD  | 1              | Installed/2026-06-15T20:31 (Start 2026-06-05)                                |
| HRM-HRM-RSL-CLSAAS   | 01tWC00000DD17PYAT  | 2              | null status/2026-05-07 (two rows, Lifecycle 2025-08-02 → 2026-08-01)         |
| HRM-HRM-RSL-SEAW     | 01tWC00000DD1fiYAD  | 0              | none                                                                         |

- The PIAP and PIAMBK assets with SystemModstamp 2026-06-15T20:31/20:32 are the SINGLE collision-target rows that all 10 duplicate same-SKU lines write to (AccountId+Product2Id) and collide on SystemModstamp → INVALID_API_INPUT "the asset was updated by another process."
- **00095470 still has 0 of its OWN assets** (0 AssetActionSource referencing its 32 lines; the 5 same-SKU account assets belong to other orders/loads).

---

## 6. AC5 de-dup target — "expect 32 Assets" (Q6)

RLM asset generation is **per-unit (per quantity)**, observable from the account pool: existing assets carry Quantity=1 per row (PIAP/PIAMBK Installed rows are Quantity=1), i.e. one Asset record per unit, not one per multi-quantity line.

If the 4 duplicated SKU sets are collapsed to **4 lines with Quantity 10 / 10 / 6 / 6 (= 32 units)**:
- per-unit assetization → 10 + 10 + 6 + 6 = **32 Assets** expected (AC5 target).
- This both removes the duplicate-line optimistic-lock collision (each unit no longer competes to update one shared Asset SystemModstamp in the same async batch) AND yields the 32-asset count.
- De-dup target lines:
  - PIA-PIA-NRPS-PIAP   (01tWC00000DD1btYAD) Qty 10  — OneTime
  - PIA-PIA-RNM-PIAMBK  (01tWC00000DD1bsYAD) Qty 10  — OneTime  (note: collapses the qty=0 + decomposition artifact)
  - HRM-HRM-RSL-SEAW    (01tWC00000DD1fiYAD) Qty 6   — TermDefined, future-dated (AC2)
  - HRM-HRM-RSL-CLSAAS  (01tWC00000DD17PYAT) Qty 6   — TermDefined, future-dated (AC2)

---

## Raw query references
- Q1 Order: 1 record (above).
- Q2 OrderItems: 32 records; group-by 10/10/6/6 (PIAMBK sumQty 9 due to qty=0 line).
- Q3 AssetActionSource (32 OIs): COUNT=0. Account Asset COUNT=1994. 4-SKU account assets=5 (SEAW=0). AssetActions on 4-SKU assets reference other orders.
- Q4 OrderItemDetail (order): 2 rows, both on PIAMBK 802WC00000Og2R2YAJ (+1 @2026-06-11 / -1 @2026-06-15). Decomposition/parent FKs on 32 lines: 0.
- Q5 Contract 800WC00000S9jqbYAB: Activated.
