# D-16 — Order-side invocable bulkification (SHIPPED 2026-07-07)

Behavior-preserving governor-hardening of the Order-side pricing invocables. Verified via a 17-agent
adversarial workflow (find hot-path loop antipatterns → adversarially verify behavior-preservation).

## Key discovery (corrects the plan's D-16 one-liner)
The plan named `MaintenanceOrderDecompositionService` / `OrderCommercialNetService` / `OrderRepriceInvocable`.
But **Nir Kailash already bulkified the SOQL side in June** (`loadWorkBulk` batches all context in one pass) and
the **reprice hot path is already line-bulk-safe** (prepareForReprice/seedFromWork/persistFromWork/
patchOrderItemCommercialUnitPrices each ≤1 SOQL + 1 bulk DML). So D-16 was mostly-done hardening, not a live fire.

The workflow **refuted the initial thesis on one point**: the flow-wired assetize entry point is
`AssetRateOverrideConsolidationService` (the `Fortra_Assetize_Order` element labeled *Finalize Order Commercial
Net* actually binds `actionName=AssetRateOverrideConsolidationService` — the label is misleading), NOT
`OrderCommercialNetService.finalizeForAssetization` (which is DEAD — flow-wires nothing). Its own sibling
`PopulateAssetLegacyFieldsAction` in the same async flow is already bulkified → the per-order pattern was a
copy-paste omission.

## Shipped (both off every reprice path → gate = atomic test deploy, not reprice)

### Fix A — `AssetRateOverrideConsolidationService` bulkified  ✅ Deploy 0AfWC00000GjMRN0A3 (7/7 tests)
- Added `patchOrderLinesForAssetizationBulk(Set<Id>)`: 1 SOQL (`WHERE OrderId IN :orderIds`) + 1 DML for N orders,
  mirroring `PopulateAssetLegacyFieldsAction`. `prepareOrderForAssetization(Id)` / `patchOrderLinesForAssetization(Id)`
  kept as delegates (signatures preserved). Invocable `prepareForAssetization(List<FlowInput>)` now collects orderIds
  into a Set → one bulk call.
- Behavior preserved: identical SELECT field list kept (the `getPopulatedFieldsAsMap().containsKey('TotalPrice')`
  guard), per-order counts preserved, DML atomicity unchanged (no try/catch either way). Added `OrderId` to the SELECT
  (needed for count attribution; does not affect the TotalPrice presence check).
- Tests added to `AssetRateOverrideConsolidationTest`: `prepareForAssetization_bulkOrdersUseSingleQuery`
  (already-aligned no-DML scenario → `soqlUsed == 1` for 3 orders, flow-noise-immune) +
  `prepareForAssetization_bulkOrdersAllPatched` (3 orders all patched).

### Fix B — `MaintenanceOrderDecompositionService.backfillCarryForwardFieldsBulk` DML-hoist  ✅ Deploy 0AfWC00000GjMuP0AV
- The plan's literal `:734` headline. Hoisted `update patches.values()` out of the `for (orderId : orderIds)` loop:
  accumulate all patches into one `List<OrderItem>`, record per-order counts before merge, single `update` after.
- Behavior-preservation risk = NONE (verified): patches are OrderItem-Id keyed (one OI ⇒ one order ⇒ no collision);
  per-order counts bit-identical; no try/catch/savepoint so all-or-nothing rollback is unchanged.
- Test added: `backfillCarryForwardFieldsBulk_dmlDoesNotScaleWithOrderCount` — distribution-invariance
  (2 orders×1 line vs 1 order×2 lines, same total lines → identical DML budget only if hoisted). Flow-noise-immune.

## Gate evidence
- Fix A: atomic `RunSpecifiedTests --tests AssetRateOverrideConsolidationTest` → **7/7 pass** (5 existing + 2 new).
- Fix B: **deployed `NoTestRun`** because `MaintenanceOrderDecompositionServiceTest` has **2 PRE-EXISTING drift
  failures** (`buildRenewalCarryForwardPatches_computesNetWhenQuoteNetIsZero` / `_persistsQliInputsOnOrderItem` — both
  expect renewal-COLA `60.64`, get `71.00` because the org's QLI-insert automation stamps a price so
  `resolveCommercialUnitPrice` returns non-null; proven to fail on LIVE code with my change rolled back → NOT my
  regression, same class as SC-3346 test-suite drift). Confirmed my change via targeted method run:
  `backfillCarryForwardFieldsBulk_dmlDoesNotScaleWithOrderCount` + `backfillCarryForwardFields_updatesBaseWithoutUnitPrice`
  → **both PASS**. The first (rolled-back) atomic run also showed 40/42 pass — my change broke 0 tests.
- Control: S1 (New USD baseline `0Q0WC000003IIT0`) reprice → `IsSuccess:true`; `diff.py` vs baseline → **GATE PASS 0 delta**.

## NOT done (verified poor risk/reward — leave)
- `OrderCommercialNetService.finalizeForAssetization` (C): dead code, unwired. Low value.
- `OrderRepriceInvocable` 4 redundant Order SELECTs (D) + `repriceOne` per-order loop (E): reprice path, **verified N=1**
  (screen flow, scalar `varCreatedOrderId`), golden-gated, pricing-critical → tiny saving, real regression surface.
- `QuoteToOrderFieldMapper.mapFields` per-order DML (F): convert path, N=1, high fix-risk (per-order failure isolation,
  Order-Product-Detail lock-strip blast radius).

## Follow-up flagged to owner
- `MaintenanceOrderDecompositionServiceTest` has 2 pre-existing environmental failures (renewal-COLA QLI pricing drift).
  Out of D-16 scope; blocks a clean class-level gate for that class until fixed. See SC-3346 test-suite drift.
