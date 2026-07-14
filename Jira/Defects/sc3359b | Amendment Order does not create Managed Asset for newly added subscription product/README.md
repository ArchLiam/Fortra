# Amendment Order does not create Managed Asset for newly added subscription product

> ⚠️ **Ticket number:** filed as `sc3359b` because `sc3359` is already the **Partner-Pricing** defect (*"adjusted price calculated but final net price not applied"*). This is a **different** issue. Rename this folder to the correct Jira key.

**Org:** FortraUAT (`00DWC000006eUFF2A2`) · **Status:** ✅ Fixed & validated in UAT (no production change) · **Date:** 2026-07-14

---

## Reported

Processing an amendment quote against an activated contract added two subscription products. One (existing SKU) appeared as a Managed Asset; the second, a **new SKU (`ARC for On Prem DLP`, `DP-DLP-RSL-ARCO`)**, was added to the Order and the Order completed, but was **not added to the Contract as a Managed Asset**. No errors.

- Order **00095740** (`801WC00000mr9CvYAI`) · Contract **00069476** (`800WC00000TYZVhYAP`) · Account `001WC00000WiR9YYAV`

---

## Root cause

The amendment order transitioned **`Draft → Provisioned → Order Complete`, never passing through `Status = "Activated"`.**

Every fulfillment automation is a record-triggered flow gated **only** on `Status = Activated`:
`Fortra_Assetize_Order` (assets), `Fortra_Order_to_Billing_Schedule` (billing), `Order_Submission_to_Revenue_Orchestrator`.

Because "Activated" was skipped, **none fired → 0 Assets and 0 Billing Schedules for ALL 8 lines** (not just ARC). `AppUsageAssignment` was present and no error was raised because the flow never executed.

**The ticket framing was a UI artifact:** the "existing SKU" (CCM) was already a Managed Asset from the *original* order 00095739; ARC was simply the only genuinely-new SKU, hence the only visibly-absent one. Confirmed independently — the amendment produced **0 BillingSchedules vs 8** on the original.

### Evidence
| | Original 00095739 (hit Activated) | Amendment 00095740 (skipped Activated) |
|---|---|---|
| Status path | Draft → **Activated** → Provisioned → Order Complete | Draft → Provisioned → Order Complete |
| Assets | 8 | **0** |
| Billing Schedules | 8 | **0** |

Ruled out: AUA gate (both have AUA); shared OrderAction (normal — original had 8 lines on 1 Add action and assetized); systemic-to-amendments (a healthy amendment `801WC00000mksBUYAY` hit Activated and assetized). Only 2 of 70 recent orders skipped Activated.

---

## Fix — `Fortra_Assetize_Order` V20 (Active)

1. **Entry broadened** from `Status = Activated` to **`Status = Activated OR Order Complete`** (`filterLogic 1 OR 2`). Transition semantics still exclude `Provisioned`/`Superseded`.
2. **Idempotency guard** — new bulk-safe Apex `OrderAssetizationGuard` wired as action `Check Order Already Assetized` → decision `Is Order Already Assetized?`, so `createOrUpdateAssetFromOrder` runs **exactly once**.
3. **Durable exception logging** on the fault path — publish `Pricing_Exception__e` → `Fortra_Pricing_Exception_Logger` → `Exception_Log__c` (flow-compliance §3.4).

Conforms to `docs/compliance/flow-compliance.md` (Auto-Layout, API 67, versioned description, naming, no hardcoded Ids, bulk-safe Apex, fault path) and `docs/compliance/apex-compliance.md` (headers, bulk, sharing, tests).

**Why the guard is Apex not Flow:** the async path batches orders → Flow-native Gets would sum against governor limits (200×2 = 400 SOQL); an invocable does **2 SOQL total**. Also `AssetActionSource.ReferenceEntityItemId` is polymorphic (un-filterable in Flow), and the guard needs `without sharing` to avoid a false-negative re-assetize.

### Two-layer duplicate prevention
- `Activated → Order Complete` (stays in the meeting-set) → flow **doesn't re-fire** (entry transition semantics).
- `… → Provisioned → Order Complete` (out-and-back) → flow **fires**, guard returns `alreadyAssetized=true` → **skips**.

---

## Components

| Component | Type | Change |
|---|---|---|
| `Fortra_Assetize_Order` | Flow | Modified → **V20 (Active)** — broadened entry + guard + exception publish |
| `OrderAssetizationGuard` | Apex Class | **New** — bulk-safe idempotency guard (2 SOQL, List in/out) |
| `OrderAssetizationGuardTest` | Apex Class | **New** — 5 methods, all pass |
| `Pricing_Exception__e` / `Fortra_Pricing_Exception_Logger` / `Exception_Log__c` | Event / Flow / Object | Leveraged, not modified |

See `evidence/` for the deployed flow XML + Apex + debug-log excerpts. Deploy ref `0AfWC00000Gr0Wv0AJ` (guard + entry) then flow-only V20.

---

## Validation

See `RUNTIME_TEST_RESULTS.md` for full detail. Summary:

| Scenario (order 00095719) | Flow fires? | Guard | Outcome |
|---|---|---|---|
| Draft → Activated | Yes | false → proceed | **4 Assets + 4 ACRs** ✅ |
| Activated → Order Complete | No (in-set) | n/a | No duplicates ✅ |
| … → Provisioned → Order Complete | Yes | true → skip | No duplicates ✅ |

Unit tests `OrderAssetizationGuardTest` 5/5. Exception pipeline probe persisted to `Exception_Log__c` in <1s (probe deleted).

---

## Follow-ups (separate scope)

1. **`AssetRateOverrideConsolidationService`** ("Finalize Order Commercial Net") faults with `INVALID_FIELD_FOR_INSERT_UPDATE` updating `OrderItem.UnitPrice` on maintenance-decomposed lines (`OrderItemDetail` locks UnitPrice); `Finalize_Order_Commercial_Net` has **no fault connector** → silent no-assetization. Surfaced on order 00095683 (`PIA-PIA-RNM-PIAMBK`). Fix: skip UnitPrice-locked lines + add fault connectors to the exception-log path.
2. **`Fortra_Order_to_Billing_Schedule`** has the identical `Status = Activated`-only gate → skip-Activated orders miss BillingSchedules (revenue impact). Same broaden-entry + guard pattern (guard keyed on `BillingSchedule`).
3. **Upstream root** — identify what sets the amendment directly to `Provisioned` (native orchestration / manual). V20 makes the pipeline resilient regardless.
4. **Recover order 00095740** — re-fire assetization for its missing Managed Assets.

---

## Related
`Jira/Defects/sc3419 …` and `sc3415 …` (prior silent-swallow assetization defects — same flow, different failure mode). SDD: `docs/RCA Solution Guide/kb/Revenue_Cloud_Order_to_Asset_Lifecycle.md`.
