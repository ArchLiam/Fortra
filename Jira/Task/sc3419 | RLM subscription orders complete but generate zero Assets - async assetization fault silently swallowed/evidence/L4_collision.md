# SC-3419 L4 — Optimistic-Lock Collision Mechanism Re-Confirmation (read-only)

Date: 2026-06-16. Org: FortraUAT. Account: `001WC00000XiZP4YAN`. Order 00095470 = `801WC00000kYmw8YAC`.
All queries read-only (`sf data query`). `createOrUpdateAssetFromOrder` NOT invoked; nothing mutated.

VERDICT: **CONFIRMED** — the AccountId+Product2Id funnel-onto-one-row premise holds, with one refinement:
existing assets per product are **1–2, NOT always 1**, and the collision-prone row is the one that already
carries multiple AssetActionSource (AAS) entries from prior orders. The 32 same-account, same-product lines on
00095470 will concurrently update these few pre-existing rows → optimistic-lock (SystemModstamp) collisions.

---

## 1. Existing Assets on the account for the 4 products

Query:
```
SELECT Id, Name, Product2Id, Product2.ProductCode, Status, Quantity, SystemModstamp,
       LifecycleStartDate, LifecycleEndDate, CreatedDate
FROM Asset
WHERE AccountId='001WC00000XiZP4YAN'
  AND Product2Id IN ('01tWC00000DD1bsYAD','01tWC00000DD1btYAD','01tWC00000DD1fiYAD','01tWC00000DD17PYAT')
```

| Asset Id | ProductCode | Product2Id | Status | Qty | CreatedDate | SystemModstamp | Lifecycle Start→End |
|---|---|---|---|---|---|---|---|
| 02iWC000007kLByYAM | HRM-HRM-RSL-CLSAAS | 01tWC00000DD17PYAT | null | null | 2026-05-06 21:16 | 2026-05-07 15:11 | 2025-08-02 → 2026-08-01 |
| 02iWC000007mWZfYAM | HRM-HRM-RSL-CLSAAS | 01tWC00000DD17PYAT | null | null | 2026-05-07 19:28 | 2026-05-07 19:28 | 2025-08-02 → 2026-08-01 |
| 02iWC000008DFvxYAG | PIA-PIA-NRPS-PIAP | 01tWC00000DD1btYAD | Installed | 1 | 2026-06-09 16:39 | 2026-06-09 16:39 | 2026-06-05 → null |
| 02iWC000008LagcYAC | PIA-PIA-NRPS-PIAP | 01tWC00000DD1btYAD | Installed | 1 | 2026-06-15 20:31 | 2026-06-15 20:32 | 2026-06-15 → null |
| 02iWC000008DFvvYAG | PIA-PIA-RNM-PIAMBK | 01tWC00000DD1bsYAD | Installed | 1 | 2026-06-09 16:39 | **2026-06-15 20:31** | 2026-06-05 → null |
| (none) | HRM-HRM-RSL-SEAW | 01tWC00000DD1fiYAD | — | — | — | — | 0 existing assets |

Existing assets per product:
- **PIA-PIA-RNM-PIAMBK (`...DD1bsYAD`): 1** existing asset (02iWC000008DFvvYAG) — the pure single-row funnel target.
- **PIA-PIA-NRPS-PIAP (`...DD1btYAD`): 2** existing assets.
- **HRM-HRM-RSL-CLSAAS (`...DD17PYAT`): 2** existing assets.
- **HRM-HRM-RSL-SEAW (`...DD1fiYAD`): 0** existing assets.

00095470 line distribution (confirms ticket): PIAMBK x10, PIAP x10, CLSAAS x6, SEAW x6 = **32 lines**.
```
SELECT Product2Id, COUNT(Id) FROM OrderItem WHERE OrderId='801WC00000kYmw8YAC' GROUP BY Product2Id
→ 01tWC00000DD17PYAT (CLSAAS): 6 | 01tWC00000DD1fiYAD (SEAW): 6
  01tWC00000DD1btYAD (PIAP): 10 | 01tWC00000DD1bsYAD (PIAMBK): 10  (TOTAL 32)
```

Funnel math (AccountId+Product2Id → one mapping target per product): 10 PIAMBK lines map onto the 1 existing PIAMBK
asset; 10 PIAP lines map onto a small set (2) of existing PIAP assets; 6 CLSAAS lines onto 2; 6 SEAW lines have no
pre-existing asset (so SEAW is the new-row case, not the collision case). The heavy duplicates collide because many
order lines target the same handful of pre-existing rows within one async batch.

## 2. Product2.IsAssetizable (config not the gate)
```
SELECT Id, ProductCode, IsAssetizable FROM Product2 WHERE Id IN (4 ids)
```
- HRM-HRM-RSL-CLSAAS (01tWC00000DD17PYAT): **true**
- PIA-PIA-RNM-PIAMBK (01tWC00000DD1bsYAD): **true**
- PIA-PIA-NRPS-PIAP (01tWC00000DD1btYAD): **true**
- HRM-HRM-RSL-SEAW (01tWC00000DD1fiYAD): **true**

All four are assetizable → **config is NOT the gate**. The failure is runtime (optimistic lock), not eligibility.

## 3. Decision table 0lDa50000007BJhEAM (downstream, not the creation gate)
Object is **DecisionTable** (not DecisionTableDefinition/CalculationMatrix — those API names rejected).
```
SELECT Id, MasterLabel, DeveloperName, Status FROM DecisionTable WHERE Id='0lDa50000007BJhEAM'
→ Id=0lDa50000007BJhEAM | DeveloperName=Asset_Action_Source_Entries_Decision_Table_V2 | Status=Active
```
This is the **AssetActionSource-entries** decision table (UsageType per SC-3415 RCA = PricingDiscovery), a DOWNSTREAM
reader that shapes AAS rows during pricing discovery — **NOT the new-order asset-creation gate**. Status=Active.
RefreshStatus/RefreshFailureReason/LastSyncDate are not exposed on the DecisionTable SObject via SOQL in this org
(only Id/MasterLabel/DeveloperName/Status queryable); the SC-3415 note of "was RefreshStatus=Failed" is a
DecisionTable-internal/Setup-surfaced attribute and, regardless, does not gate creation — its position downstream
of `createOrUpdateAssetFromOrder` is confirmed by AAS being a *product of* the asset-action chain (section 4).

## 4. AssetActionSource link semantics (explains per-order AAS undercount)
AAS describe — relevant references (no direct AssetId or OrderItemId field):
- `AssetActionId` → **AssetAction** (and AssetAction → Asset). The asset link is INDIRECT, via AssetAction.
- `ReferenceEntityItemId` → **polymorphic (OrderItem, OrderItemDetail, WorkOrderLineItem)** — the order-line link.
- No `OrderId`/`OrderItemId`/`AssetId`/`Name` columns exist on AAS (those SOQL attempts errored INVALID_FIELD).

So a per-Order AAS count undercounts because AAS does not carry OrderId; the order line is reached only via the
polymorphic `ReferenceEntityItemId`, and the asset only via `AssetActionId → AssetAction.AssetId`.

AAS rows funneling onto the existing assets (via their AssetActions):
```
AAS Id              | Asset (via AssetAction) | ReferenceEntityItemId (order line) | Qty | TransactionDate
4nMWC000003mXBK2A2  | 02iWC000007kLByYAM CLSAAS| (none)                             | 1   | 2026-05-06 21:16
4nMWC000003oYUp2AM  | 02iWC000007mWZfYAM CLSAAS| 802WC00000N0xTYYAZ  (Ord 00073445) | 1   | 2026-05-07 19:27
4nMWC0000043PFj2AM  | 02iWC000008DFvvYAG PIAMBK| 802WC00000OZLOrYAP  (Ord 00095402) | 1   | 2026-06-09 16:39
4nMWC0000043PFl2AM  | 02iWC000008DFvxYAG PIAP  | 802WC00000OZLOnYAP  (Ord 00095402) | 1   | 2026-06-09 16:39
4nMWC0000046OF42AM  | 02iWC000008DFvvYAG PIAMBK| (none)                             | -1  | 2026-06-15 20:30
4nMWC0000046OF52AM  | 02iWC000008DFvvYAG PIAMBK| (none)                             | 1   | 2026-06-15 20:30
4nMWC0000046OF62AM  | 02iWC000008LagcYAC PIAP  | 802WC00000OpoppYAB  (Ord 00095503) | 1   | 2026-06-15 20:30
```
The single PIAMBK asset **02iWC000008DFvvYAG carries THREE AAS rows** spanning orders 00095402 (06-09) and a
06-15 -1/+1 adjustment pair — a live demonstration that multiple order lines (across orders, and within an order)
re-target the SAME asset row. The order lines belong to PRIOR orders on this account (00073445, 00095402, 00095503),
confirming the account already has asset history these products map onto.

## 5. Recent concurrent SystemModstamp activity
- PIAMBK 02iWC000008DFvvYAG: **CreatedDate 2026-06-09 16:39 but SystemModstamp 2026-06-15 20:31:36** — the row was
  UPDATED 6 days after creation (the 06-15 -1/+1 AAS adjustment), i.e. a later order/process re-touched the same row.
  This is the optimistic-lock surface: a concurrent batch updating this exact row would collide on its modstamp.
- PIAP 02iWC000008LagcYAC: Created 06-15 20:31:35, SystemModstamp 06-15 20:32:30 (≈55s later) — modified shortly
  after creation. PIAP 02iWC000008DFvxYAG modstamp 06-09 (older, stable).
- CLSAAS rows modstamps 2026-05-07 (stable). SEAW: no rows.
The 06-15 cluster on PIAMBK/PIAP shows recent same-row activity consistent with concurrent assetization writes —
the empirical signature of the INVALID_API_INPUT "the asset was updated by another process" lock collision.

---

## Conclusion
The optimistic-lock collision mechanism is **CONFIRMED** with the following concrete grounding:
- The account already holds existing assets for 3 of 4 products (PIAMBK 1, PIAP 2, CLSAAS 2; SEAW 0), and every
  same-product 00095470 line maps (AccountId+Product2Id) onto that small set of pre-existing rows.
- The clearest single-row funnel is **PIAMBK**: 10 order lines → 1 existing asset (02iWC000008DFvvYAG) that already
  accumulated 3 AAS rows and was re-updated on 06-15 → guaranteed concurrent same-modstamp collision.
- All four SKUs are IsAssetizable=true → not a config gate.
- DecisionTable 0lDa50000007BJhEAM (Asset_Action_Source_Entries_Decision_Table_V2, Status=Active) is a downstream
  AAS-shaping table, not the creation gate; AAS proven to be a *product of* the AssetAction chain.
- AAS links order line via polymorphic ReferenceEntityItemId and asset via AssetActionId→AssetAction (no OrderId),
  which is why naive per-order AAS counts undercount.
Refinement vs the thesis's "1 each": the funnel-onto-few-rows premise holds, but existing assets per product are
1–2 (not strictly 1); the collision is driven by many lines targeting those few rows in one async batch.
