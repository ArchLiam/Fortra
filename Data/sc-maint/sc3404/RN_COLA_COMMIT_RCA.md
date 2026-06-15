# SC-3404 / RN-COLA-COMMIT — Definitive Root Cause Analysis

**Date:** 2026-06-14 · **Org:** FortraUAT · **Active procedure:** Rev_Mgmt_Default_Pricing_Procedure **V14** (sole active, `9QMWC00000023eX4AQ`) · **Method:** read-only SOQL/Tooling + live FINEST logs + procedure XML + Apex retrieve

## Symptom
Renewal-maintenance (derived) lines commit the wrong `NetUnitPrice`: `0`, `54.58`, or `60.64` (=`COLACalc × 0.90`) instead of the correctly-computed COLA net (e.g. 67.38). `COLACalculatedPrice__c` is correct on every line.

## Decisive live evidence (current, V14)
5 live Draft renewal-maintenance lines (`PIA-PIA-RRM-PIAM`, all `ListPrice=0`, all `DerivedPricingAttribute=true`):

| Line | QuoteAction | NetUnitPrice | COLACalc | Outcome |
|---|---|---|---|---|
| 0QLWC000003dEW24AM | **Renew(PIA-PIA-RRM-PIAM)** | **67.38** | 67.38 | ✓ correct |
| 0QLWC000003e2Sn4AI | none | 60.64 (=67.38×0.90) | 67.38 | ✗ |
| 0QLWC000003cy334AA | none | 54.58 (=60.64×0.90) | 60.64 | ✗ |
| 0QLWC000003cN584AE / …ck6X4AQ | none | 0 | 67.38 | ✗ |

**`ListPrice=0` is NOT the discriminator** (both the working and broken lines have it). The discriminator is the linked **`QuoteAction.Type='Renew'`**.

## Root cause chain (definitive)
1. **SKU mismatch at the asset layer.** The renewal quote's maintenance line uses the **Renewal Maintenance SKU `PIA-PIA-RRM-PIAM`**, but customers' installed maintenance asset is the **New Maintenance SKU `PIA-PIA-RNM-PIAMBK`**. Proven by asset inventory: the ONE account that commits 67.38 (`Nir DPP Test 2`) is the ONLY one that also owns a `PIA-PIA-RRM-PIAM` asset; the three failing accounts own only `PIA-PIA-RNM-PIAMBK` (+ perpetual `NRPS-PIAP`).
2. **No QuoteAction → non-writable node.** `initiateRenewal` creates `Renew` QuoteActions only for assets it can renew by matching SKU. With no RRM asset, the RRM line is **auto-added by the Year-2 configurator rule** with **no QuoteAction**. A derived, QuoteAction-less, zero-list line is a **non-writable pricing node**: the RLM engine will not persist a corrected `NetUnitPrice`.
3. **Born-stale, immutable.** The line is **born** at the partner-discounted `60.64` (creation-time ×0.90) and stays there. Today's reprice updated `UnitPrice→67.38` but `NetUnitPrice` stayed `60.64` (FLOW_VALUE_ASSIGNMENT snapshot: `UnitPrice=67.38, NetUnitPrice=60.64, PartnerDiscountPercent=12.0` — the price doesn't even match the current stamp → not a live recompute). **Not reprice-fixable** — this is why lever-c (seeding price fields) couldn't move `NetUnitPrice`.

## Why the ×0.90 (partner double-discount)
The COLA base already nets the prior partner amount (`Base 71 − priorPartner 8.52 = 62.48`, ×1.0785 = 67.38). The creation-time partner step applies another ×0.90 → 60.64. Procedure gates (V14):
- Generic `PartnerDiscount` (file L3426): applies when `DerivedPricingAttribute` IsNull/false.
- `PartnerDiscountDerivedMaintenance` (L3557): applies when `DerivedPricingAttribute=true` AND `QuoteTypeText__c ≠ 'Renewal'`.
A *correct* renewal-maintenance line (`DerivedPricingAttribute=true`, `QuoteTypeText='Renewal'`) is excluded by BOTH — confirming the ×0.90 was applied **at creation time** before those attributes were set, then frozen.

## The intended fix already exists — and why it's insufficient
`RenewalMaintenancePricingService` (SC-3346) is built to write the COLA net for exactly these lines. Candidate query is correct (`Fortra_Product_Type__c='Renewal Maintenance' AND Base_Price__c>0`, QA-less lines included). It has **two** write modes via `updateContextAttributes`:
- **`applyToContext`** — writes `COLACalculatedPrice__c`, `InputUnitPrice`, `SalesTransactionActionType='Renew'`. **Does NOT write `NetUnitPrice`.** ← matches the canary (UnitPrice=67.38 from the InputUnitPrice seed, NetUnitPrice still 60.64).
- **`applyColaNetFinalizeToContext`** (`finalizeAfterPricing==true`) — writes `UnitPrice` + **`NetUnitPrice`** + `NetTotalPrice` + `TotalPrice` + `PartnerUnitPrice` = colaNet directly. This path *would* force 67.38 but the canary proves **it is not the path that runs**.

**Conclusion:** the `NetUnitPrice`-writing finalize path is either not invoked on the reprice flow for these lines, or its direct `NetUnitPrice` context write no-ops on the QA-less node.

## Fix levers
- **(A) Creation-path QuoteAction (proven).** Make the renewal-maintenance line born linked to a `Renew` QuoteAction (renew the `RNM` asset into the `RRM` line, or have the renewal handler create the action). Structurally correct, matches the working case; larger flow change.
- **(B) Make the finalize NetUnitPrice write land (likely smaller).** Ensure `applyColaNetFinalizeToContext` (the NetUnitPrice-writing mode) runs in the reprice flow AFTER main pricing persist. If the platform refuses the `NetUnitPrice` context write on a QA-less node, fall back to (A).
- **(C) Lever-c (seed price fields) — REFUTED** for NetUnitPrice; seeding `InputUnitPrice` only fixes `UnitPrice`.

## CONFIRMED proximate cause — the fix-service is UNWIRED
Four independent read-only checks prove `RenewalMaintenancePricingService` is **never invoked**:
- `MetadataComponentDependency` WHERE RefMetadataComponentName='RenewalMaintenancePricingService' → **0 rows**.
- `OrderRepriceInvocable` (the only referenced reprice class) does **not** call it.
- The renewal handlers (QuoteRenewalTypeHandler / RenewalQuoteLineHandler / RenewalAssetQuantityHandler) do **not** call it.
- No active Quote/pricing Flow references it.

So the SC-3346 service built specifically to write the COLA net onto renewal-maintenance lines is **dead code**. The `UnitPrice=67.38` seen on the canary comes from the procedure's COLA formula, not the service; the corrected `NetUnitPrice` is **never written** → the line keeps the procedure's born-stale partner-discounted `60.64`.

## Fix (refined)
**Wire `RenewalMaintenancePricingService` into the post-pricing flow** so its `finalizeAfterPricing` path (`applyColaNetFinalizeToContext`, which writes `NetUnitPrice`=colaNet directly) runs after main-pricing persist on renewal-maintenance lines. Open verification: confirm the `NetUnitPrice` context write **lands** on a QA-less node; if the platform refuses it, fall back to Lever A (creation-path `Renew` QuoteAction).

## Verification requires a state change (NOT read-only)
Invoking the finalize path calls `persistContext` → re-prices/persists the canary (writes `NetUnitPrice` on the Draft test quote). This is reversible and on a non-protected test canary, but it is a UAT write and needs explicit owner ack before running.

## Experiment run (owner-authorized 2026-06-14) — GACKED at buildContext
Ran `RenewalMaintenancePricingService.finalizeRenewalMaintenanceAfterPricing('0Q0WC0000038aXd0AI')` (Draft canary). Result: **`System.UnexpectedException: Salesforce System Error 1648396304-208856`** at **line 157 = `ctx.buildContext({contextDefinitionName:'SalesTransactionContextExt_v2', sourceRecordId:quoteId})`**.
- `CONTEXT_DEFINITION_NAME='SalesTransactionContextExt_v2'` is valid (exists live) → the gack is a **context-definition-sync failure**, same family as [[project_reprice_contextdef_error]] (procedure republished V9→V14 without the context staying in sync), not a wrong name.
- So the service's **standalone `buildContext` fallback is broken**; and the "does the NetUnitPrice write land?" question can't be answered by a bare call — it needs a **live `contextInstanceId`** from a real pricing transaction (which the *wired* `finalizeAfterPricing` path supplies, bypassing `buildContext`).

## Refined fix plan
1. **Wire `RenewalMaintenancePricingService` into the post-pricing flow**, calling the invocable with `{contextInstanceId: <live ctx>, finalizeAfterPricing: true}` so it runs `applyColaNetFinalizeToContext` (writes `NetUnitPrice`=colaNet directly) and **never hits the gacking `buildContext`**.
2. **Verify** via a real reprice that NetUnitPrice 60.64→67.38 on a QA-less canary.
3. If the write still doesn't land on the QA-less node → fall back to **Lever A** (born-link a `Renew` QuoteAction at creation).
4. Separately, the broken `buildContext` fallback should be removed or guarded (it gacks), and the `SalesTransactionContextExt_v2` sync re-verified after any procedure republish.
