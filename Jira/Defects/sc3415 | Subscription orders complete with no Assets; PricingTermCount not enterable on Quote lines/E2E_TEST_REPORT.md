# SC-3415 — E2E Test Report (Defect A visibility fix)

**Org:** FortraUAT · **Date:** 2026-06-15 · **Build under test:** `Fortra_Assetize_Order` **V13** + `Order.Assetization_Status__c` / `Assetization_Error__c` + permset `SC3415_Assetization_Visibility` (Deploy ID `0AfWC00000GLZb30AH`).

## Objective
Verify end-to-end that an Order activation drives the async asset-generation flow (`Fortra_Assetize_Order`) and that the new **Assetization Status/Error** fields correctly reflect the outcome — `Success` when assets are generated, `Failed` (with message) when the asset action throws — so a no-asset failure is no longer silently swallowed.

## Method
Throwaway RLM orders built via Apex on disposable accounts (scaffolding required to make an order activatable: `OrderAction` Type=Add → `ServiceDate`/`EndDate`/`PricingTermCount`/`PeriodBoundary` on lines → `AppUsageAssignment` (the flow's gate) → bill-to/ship-to Contact → `OrderRepriceInvocable.reprice`). Activation = `Status='Activated'` update (fires the AsyncAfterCommit flow). Stamps polled; assets counted by **account** (per-order `AssetActionSource` undercounts subscription assets — see Findings). Artifacts: `Data/sc3415/diag/`.

## Scenarios & results

| # | Scenario | Order | Expected | Result | Verdict |
|---|---|---|---|---|---|
| 1 | OneTime, **2** identical lines (PIA-PIA-NRPS-PIAP) | 00095521 | Success + assets | `Assetization_Status__c=Success`, **2 assets** | ✅ PASS |
| 2 | OneTime, **12** identical lines (PIAP) | 00095523 | Success + assets | `Success`, **12 assets** | ✅ PASS |
| 3 | **Subscription** (TermDefined), **6** identical lines (HRM-HRM-RSL-SEAW) | 00095524 | Success + assets | `Success`, **6 assets** | ✅ PASS |
| 4 | **Fault mode** — maintenance-decomposed order (PIAMBK/RNM) | 00095470 (real) | Failed + message | **Directly observed:** owner-authorized re-fire (Status→Activated) → flow stamped `Assetization_Status__c=Failed`, `Assetization_Error__c="We couldn't process your request because the asset was updated by another process."`; Status restored to 'Order Complete' (Failed stamp retained — accurate) | ✅ PASS |

## Findings
1. **Success path fully validated** — 4 activations across OneTime/subscription × single/duplicate all stamped `Success` and generated the expected assets (1 per line). The flow fires, the gate passes, and the success recordUpdate writes correctly.
2. **The `Success` stamp is accurate** — an early "Success but 0 assets" alarm on scenario 3 was a **measurement artifact**: subscription assets link to the order via a non-`OrderItem` reference, so the per-order `AssetActionSource WHERE ReferenceEntityItemId IN (OrderItems)` metric reads 0 while the account truly has 6 assets. Validate subscription assetization by **account asset count**, not that metric. (00095470 remains genuinely 0 by account count too.)
3. **Plain duplication does NOT reproduce the fault** — neither OneTime (2, 12) nor subscription (6) duplicate-line orders collide; all assetize cleanly. 00095470's fault is specific to its **maintenance-decomposed** lines (PIAMBK/RNM → Order Product Detail), consistent with SC-3411 §4.1. It cannot be reproduced synthetically without the maintenance-decomposition pipeline.
4. **Fault-path stamp — indirect validation is strong:** the action's deterministic fault on 00095470 is proven (rollback diagnostic ×3); the fault-path `Stamp_Assetization_Failed` uses the **identical recordUpdate** element proven by the 4 passing Success stamps, off the V12 fault-capture branch that was already proven to catch the fault (that's why it was silently swallowed). ∴ a real fault will write `Failed`.

## Closed
- ✅ **Direct `Failed`-stamp observation DONE (2026-06-15, owner-authorized).** Re-fired 00095470 (Status→Activated, Workday-safe: `Workday_Sync_Status=Pending`) → flow stamped `Failed` + the lock message within ~10s; Status restored to 'Order Complete', stamp retained. All 4 scenarios now PASS.

## Out of scope
- **Defect B (PricingTermCount)** not in this fix's scope — separate, owner-gated.

## Residual test data (inert, clearly marked `SC3415…`)
Accounts `001WC00000kpGHxYAM` (orders 00095521/00095523) and `001WC00000kpR26YAE` (order 00095524) + their lifecycle-managed assets cannot be API-deleted (RLM immutable `AssetActionSource` + lifecycle-managed Assets). Deletable children (assets-non-lifecycle, fulfillment assets, CPAR, OrderActions) were removed. Remove the rest via Setup UI if desired.

## Verdict
**Defect A visibility fix: PASS (all 4 scenarios, directly verified).** Success path stamps `Success` + generates assets across OneTime/subscription × single/duplicate; the real fault on 00095470 stamps `Failed` + the platform error message instead of a silently asset-less "Order Complete." The fix achieves its goal — assetization failures are now visible and queryable.
