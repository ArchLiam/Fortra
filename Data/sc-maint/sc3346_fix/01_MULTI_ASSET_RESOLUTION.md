# SC-3346 MULTI-ASSET — Resolution (2026-06-13/14, FortraUAT)

## Verdict: the prehook-seed fix is DEFINITIVELY DEAD (proven by direct experiment)

MULTI-ASSET = quote **00781053**, license leg `cxzq4` (beSECURE Subscription) prices correctly **4442.35**;
maintenance leg **`cy334`** (PIA RenewalMaintenance, `Fortra_Product_Type__c='Renewal Maintenance'`,
`ItemIsDerived__std=true`) commits **NetUnitPrice = 54.58 = COLA-net 60.64 × 0.90** (stale). Expected = 60.64.

### What was tested
doc 13's "decisive test": in `COLAUpliftPrehook.buildMaintenanceColaItemUpdate` (the branch that already
fires for these lines), seed the derived line as a priced node — `InputUnitPrice = ListPrice = UnitPrice = colaNet`
and `DerivedPricingAttribute = false` — before the procedure runs. Deployed (NoTestRun) and repriced
00781053 via `/services/data/v64.0/connect/rev/sales-transaction/actions/place` (pricingPref Force).

### Result (airtight — FINEST log `logs/seed_v2.log`)
- The seed **fired in the running bytecode**: `SC3346 SEED V2 FIRED: 0QLWC000003cy334AA colaNet=60.64`.
- The engine **ignored every write** for the derived line, across all 16 context snapshots:
  - `ListPrice = 0.0` (seed wrote 60.64) — ignored
  - `InputUnitPrice = 0.0` (seed wrote 60.64) — ignored
  - `DerivedPricingAttribute = true` (seed wrote false) — ignored
  - `NetUnitPrice = 54.58` (committed) — unchanged
- Same outcome on e2Sn4 (00781109): unchanged 60.64.

### Conclusion
The committed price of a **derived** (`ItemIsDerived__std=true`) renewal-maintenance line is owned entirely by
the **native RLM derived-pricing engine**. It ignores prehook AND posthook `updateContextAttributes` writes to
`ListPrice / InputUnitPrice / UnitPrice / NetUnitPrice / DerivedPricingAttribute` for these lines. **No custom
Apex (pre- or post-hook) can fix the committed price.** This proves doc 13's prediction and CLOSES the
prehook-seed hypothesis the team chased for days.

### The committed 54.58 / 60.64 is a frozen stale value (a historical ×0.90), not an active per-reprice discount —
the engine never recomputes these lines (absent from the SalesTransactionActionType/UnitPrice maps), so whatever
was last stored rides through every reprice unchanged.

## The only viable fix paths (both owner-gated, Nir/Marc — NOT a code fix)
1. **Native derived-pricing config** — make the derived element (`PriceBookEntryDerivedPrice`, currently
   Formula=`UnitPrice`/contributor=license) yield the COLA net for renewals. SC-3372 territory (data/config).
2. **Renewal quote generation** — create the renewed maintenance line as a NON-derived priced line
   (RenewalQuoteLineHandler / native renew action), so it prices like the license leg.

## Org-state notes (IMPORTANT)
- `COLAUpliftPrehook` restored to **truly pristine** (removed my seed v2 AND a prior session's leftover 77.77
  throwaway that was in the live class). Verified live: no `77.77`, no `SEED V2`, no DerivedPricingAttribute seed.
- The live `COLAUpliftPrehook` is **invalid/inconsistent**: its source lacks `buildOverrideMap`, but
  `COLAUpliftTest` + `RenewalMaintenancePricingServiceTest` (and ~28 classes per prior memory) reference it →
  those tests can't compile (explains the prehook's 0% coverage). Pre-existing, not introduced here. Deploy with
  `--test-level NoTestRun` (sandbox) to avoid it.
- **Deploying COLAUpliftPrehook desyncs the pricing procedure scale cache** → reprice fails with
  `ScaleCacheServiceException: Ensure that this procedure has at least one active version` even though
  `ExpressionSetVersion` V14 `IsActive=true` in the DB. Recovery = re-publish/re-sync (toggle V14 IsActive
  false→true, or UI Context Def Manager). This is an activation op (owner/user-gated).
- Reprice endpoint that actually runs the engine: `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place`
  body `{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{...Quote PATCH...}}`.
  (`/commerce/quotes/actions/place` only runs header sync, NOT pricing.)
