# Runtime Test Results — Fortra_Assetize_Order V20

**Org:** FortraUAT · **Date:** 2026-07-14 · **Method:** live status transitions + FINEST debug logs (DebugLevel `SC3359_Assetize`, ApexCode+Workflow FINEST) on the running + Automated Process users.

`createOrUpdateAssetFromOrder` is **asynchronous** (returns an `AsyncOperationTracker`); Assets land a few seconds after the flow completes, so all asset counts were read *after* the tracker reached `Completed`.

---

## Test 1 — Unit tests
`OrderAssetizationGuardTest`: **5/5 pass** (bulk 25-event mapping, empty/null safety, trigger/route). Deploy check-only Succeeded, 0 component errors.

## Test 2 — No-duplicate smoke test (already-assetized order re-fired)
**Order 00095739** (`801WC00000mrKRaYAM`) — 8 existing assets. Transitioned `Order Complete → Provisioned → Order Complete` (out-and-back, which *does* re-fire the flow).

| Metric | Baseline | After re-fire |
|---|---|---|
| Account assets | 300 | **300** ✅ |
| AssetActionSource (order) | 8 | **8** ✅ |
| AssetActions (8 assets) | 8 | **8** ✅ |
| Order error field | null | **null** ✅ |

Guard short-circuited the re-fire → **zero duplicates**.

## Test 3 — End-to-end assetization + duplicate paths (fresh order)
**Order 00095719** (`801WC00000mk8agYAA`) · Contract `800WC00000TTJGHYA5` · Draft, 4 items, AUA, not yet assetized.

| Transition | Time | Flow fires? | Guard | Result |
|---|---|---|---|---|
| Draft → Activated | 19:53:04 | **Yes** (enters set) | `alreadyAssetized=false` → proceed | Finalize OK → `createOrUpdateAssetFromOrder` (async `16PWC0000069HSn`, Completed) → **4 Assets + 4 ACRs** |
| Activated → Order Complete | 20:22:15 | **No** (stays in set) | n/a | No re-fire, counts held 4/4 |
| Order Complete → Provisioned → Order Complete | 20:26:13–21 | **Yes** (out-and-back) | `alreadyAssetized=true` → skip | Finalize / createOrUpdateAssetFromOrder **not reached**; counts held 4/4 |

**Assets created (Initial Sale/Generate):**
`02iWC000008szoHYAQ` BP-ETM-RMS-ADDITH · `02iWC000008szoIYAQ` GS-GSE-NRPS-EFT7 · `02iWC000008szoJYAQ` GS-GSE-RSS-SINGFA · `02iWC000008szoKYAQ` GS-GSE-NRPS-AAMP.
**AssetContractRelationships on the contract:** 4.

Debug logs: `07LWC00000QL2362AD` (assetize success), `07LWC00000QKw2d2AD` (guard-skip re-fire). See `evidence/debug_logs_flow_execution.md`.

## Test 4 — Exception pipeline probe
Published a `Pricing_Exception__e` (`Source=PIPELINE_TEST_SC3359`) → `Fortra_Pricing_Exception_Logger` persisted an `Exception_Log__c` row (RecordType `Pricing_Exception`) in **<1s**. Probe row `aGwWC000001mKjp0AE` deleted. Confirms the fault-path telemetry lands.

---

## Incidental finding — pre-existing silent failure (Follow-up #1)
**Order 00095683** (`801WC00000mQBXSYA4`) · Draft → Activated. Debug log `07LWC00000QKwNU2A1`:

```
guard → alreadyAssetized=false → proceed          (V20 correct)
Finalize_Order_Commercial_Net → FAULT
  System.DmlException: INVALID_FIELD_FOR_INSERT_UPDATE
  "You can't edit the Unit Price because the Order Product has related
   Order Product Detail records. : [UnitPrice]"   (OrderItem 0000568065 / PIA-PIA-RNM-PIAMBK)
→ flow ends (Finalize has NO fault connector) → 0 assets, no error stamped, no telemetry
```

`AssetRateOverrideConsolidationService` blindly updates `OrderItem.UnitPrice`, which is locked once the line has `OrderItemDetail` records (maintenance-decomposed lines). This is **not** a V20 regression — it's a separate pre-existing bug that any maintenance-line order needing a price patch hits. Tracked as Follow-up #1.
