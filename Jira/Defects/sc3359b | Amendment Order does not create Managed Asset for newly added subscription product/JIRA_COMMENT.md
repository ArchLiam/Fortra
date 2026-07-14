## ✅ Resolved — Assetization gate fixed & validated in UAT

Amendment orders that reached a terminal status without ever committing `Status = "Activated"` were silently skipping asset creation. Root-caused, fixed, deployed to FortraUAT, and validated end-to-end with live debug logs.

### Root cause
Order **00095740** transitioned `Draft → Provisioned → Order Complete`, **never passing through "Activated."** `Fortra_Assetize_Order` (plus billing + orchestrator submission) trigger only on `Status = Activated`, so none fired → **0 Assets and 0 Billing Schedules for all lines**, not just "ARC for On Prem DLP." AUA was present and no error was raised because the flow never executed. "CCM succeeded / ARC missing" was a UI artifact — CCM was already a Managed Asset from the original order; ARC was the only genuinely-new SKU. Confirmed independently: the amendment had 0 BillingSchedules vs 8 on the original.

### Fix — `Fortra_Assetize_Order` V20 (Active)
- Entry broadened from `Status = Activated` to **`Status = Activated OR Order Complete`** (Provisioned/Superseded excluded by transition semantics).
- New idempotency guard **`OrderAssetizationGuard`** → `createOrUpdateAssetFromOrder` runs exactly once.
- Fault path publishes `Pricing_Exception__e` → `Fortra_Pricing_Exception_Logger` → `Exception_Log__c`.

### Components

| Component | Type | Change |
| --- | --- | --- |
| `Fortra_Assetize_Order` | Flow | Modified → **V20 (Active)** — broadened entry + guard + exception publish |
| `OrderAssetizationGuard` | Apex Class | **New** — bulk-safe idempotency guard (2 SOQL, List in/out) |
| `OrderAssetizationGuardTest` | Apex Class | **New** — 5 methods, all pass |
| `Pricing_Exception__e` / `Fortra_Pricing_Exception_Logger` / `Exception_Log__c` | Event / Flow / Object | Leveraged, not modified |

### Validation results

| Scenario | Flow fires? | Guard | Outcome |
| --- | --- | --- | --- |
| Draft → Activated | Yes (enters set) | false → proceed | 4 Assets + 4 ACRs created ✅ |
| Activated → Order Complete | No (stays in set) | n/a | No duplicates ✅ |
| … → Provisioned → Order Complete | Yes (out-and-back) | true → skip | No duplicates ✅ |

### Testing records (FortraUAT)

| Record | Type | Role / Result | Link |
| --- | --- | --- | --- |
| 00095740 | Order | Defect amendment — skipped Activated → 0 Assets / 0 BillingSchedules (unrecovered) | [Open](https://fortra--uat.sandbox.my.salesforce.com/801WC00000mr9CvYAI) |
| 00095739 | Order | Original (8 Assets); no-duplicate smoke test (OC→Prov→OC) — guard skipped, counts held 300/8/8 | [Open](https://fortra--uat.sandbox.my.salesforce.com/801WC00000mrKRaYAM) |
| 00069476 | Contract | Amendment contract (8 managed assets from original) | [Open](https://fortra--uat.sandbox.my.salesforce.com/800WC00000TYZVhYAP) |
| 00095719 | Order | Live E2E — Draft→Activated: 4 Assets + 4 ACRs; OC in-set: no re-fire; Prov→OC: guard=true skip (no dup) | [Open](https://fortra--uat.sandbox.my.salesforce.com/801WC00000mk8agYAA) |
| 00095683 | Order | Surfaced pre-existing bug — Finalize fault on maint line `PIA-PIA-RNM-PIAMBK` (UnitPrice locked by OrderItemDetail) → silent | [Open](https://fortra--uat.sandbox.my.salesforce.com/801WC00000mQBXSYA4) |

### Assets created by 00095719 (Initial Sale / Generate)

| Product | Link |
| --- | --- |
| BP-ETM-RMS-ADDITH | [Open](https://fortra--uat.sandbox.my.salesforce.com/02iWC000008szoHYAQ) |
| GS-GSE-NRPS-EFT7 | [Open](https://fortra--uat.sandbox.my.salesforce.com/02iWC000008szoIYAQ) |
| GS-GSE-RSS-SINGFA | [Open](https://fortra--uat.sandbox.my.salesforce.com/02iWC000008szoJYAQ) |
| GS-GSE-NRPS-AAMP | [Open](https://fortra--uat.sandbox.my.salesforce.com/02iWC000008szoKYAQ) |

Exception pipeline probe: published `Pricing_Exception__e` → persisted to `Exception_Log__c` in <1s → subscriber confirmed (probe row deleted). Unit tests: `OrderAssetizationGuardTest` 5/5 pass.

### Follow-ups (separate scope)

| # | Item |
| --- | --- |
| 1 | `AssetRateOverrideConsolidationService` ("Finalize Order Commercial Net") faults with `INVALID_FIELD_FOR_INSERT_UPDATE` updating `OrderItem.UnitPrice` on maintenance-decomposed lines (OrderItemDetail locks UnitPrice); `Finalize_Order_Commercial_Net` has no fault connector → silent. Fix: skip UnitPrice-locked lines + add fault connectors. |
| 2 | `Fortra_Order_to_Billing_Schedule` has the identical `Status = Activated`-only gate → skip-Activated orders miss BillingSchedules (revenue impact). Same fix pattern. |
| 3 | Identify what sets the amendment directly to "Provisioned" (upstream root). |
| 4 | Recover order 00095740 (re-fire assetization for its missing Managed Assets). |
