# SC-3441 — Complete Solution: make the cancellation line price the negative credit (live)

**Date:** 2026-06-26 · Produced by a 4-agent deep-investigation workflow (attr-writability · total-pipeline gate audit · seq-16 Derived-Products · hydration/re-sync) + adversarial verification. Repro: Cancellation Quote 00734145 / QuoteLineItem `0QLWC000002q2Sn4AI` ("24 X 7 X 365 Monitoring", Qty −1, ListPrice 15000, expected Total −15000).

> **Two corrections to earlier conclusions in this dossier, both verified:**
> 1. **Hydration is ALREADY solved — not the blocker.** `CancelNetUnitPrice__c=15000` is in **8/9 RLM_PRICING_BEGIN and 8/8 RLM_PRICING_END** blocks (verified by proper multi-line block parse of `live_reprice_log/reprice_field_present_0426.txt`). The earlier "0 occurrences in BEGIN/END" was a **grep artifact** (only the BEGIN *marker line* was searched, not the multi-line context dump) compounded by one genuinely-stale pre-population log. **No context Sync / no Salesforce case is needed for hydration.**
> 2. The "Simulator ≠ live engine, escalate" conclusion is **superseded** — the live blocker is a procedure gate, fixable in metadata.

## 1. Executive summary

The cancel-seed group `ListContainer12` (seq 13) correctly seeds `NetUnitPrice` from the hydrated `CancelNetUnitPrice__c`. The live blocker is **downstream**: the only step that turns `NetUnitPrice` into the line total — `QuantityPrice74` (`ListContainer72`, seq 25: `NetUnitPrice × LineItemQuantity → ItemNetTotalPrice`) — is gated `ItemPricingSource NotEquals 'LastTransaction' AND DerivedPricingAttribute IsNotNull AND DerivedPricingAttribute Equals false`. The cancel line carries **null `DerivedPricingAttribute` and null `ItemPricingSource`**, so the gate fails → `QuantityPrice74` is skipped → `ItemNetTotalPrice` stays 0 → the unconditional `Assignment111` (seq 40) copies 0 into `ItemTotalPrice` → Total Price = USD 0.00. **Fix:** inside the existing cancel-seed group, additionally seed the two gate attributes (`DerivedPricingAttribute=false`, `ItemPricingSource`=non-LastTransaction) so `QuantityPrice74` fires, then guard the unconditional MAX-clamp `FormulaBasedPricing3` (seq 36) so it doesn't clamp the now-negative Subtotal back to 0.

## 2. Root cause — the complete chain

- **Total Price** = context tag `ItemTotalPrice` → `QuoteLineItem.TotalPrice`. Written by exactly one step: `Assignment111` (seq 40, unconditional), `ItemNetTotalPrice → ItemTotalPrice`. So the fix must drive `ItemNetTotalPrice = −15000`.
- **Only writer of `ItemNetTotalPrice = NetUnitPrice×qty` on this line:** `QuantityPrice74` (`ListContainer72`, seq 25). (Native `PricingSetting`/`PriceBookEntries`/`DerivedProductsRenewals` map `Subtotal→ItemNetTotalPrice` but write 0; `SubscriptionPricing91` seq 30 writes only `TotalLineAmount`/`InputUnitPrice`.)
- **Gate that fails (the controlling defect):** `QuantityPrice` filter at `ListContainer72`, `conditionLogic = 1 AND 2 AND 3`: (1) `ItemPricingSource NotEquals 'LastTransaction'`, (2) `DerivedPricingAttribute IsNotNull`, (3) `DerivedPricingAttribute Equals false`. Live cancel line has both attrs **null/absent** → criteria 2 & 3 fail → step skipped. The complementary path `FormulaBasedPricing` (`ListContainer75`, seq 26) needs `ItemPricingSource Equals 'LastTransaction'` (also false) → the line falls through **both** total paths.
- **Simulator/live divergence (resolved):** Simulator returns −15000 because it (a) injects `CancelNetUnitPrice__c`, (b) coerces null `DerivedPricingAttribute→false` (gate passes), (c) has no contributors. Live differs on all three.
- **Clobber audit:**
  - seq 16 `DerivedProductsNativePull` — gated **only** `QuoteTypeText__c NotEquals 'Renewal'` (no `ItemIsDerived` guard); a Cancellation **enters** the group and `DerivedProductsRenewals` (DerivedPricing) **executes** but is **inert for this product** (`01tWC00000DD115YAD` has `IsDerived=false` on all 11 PBEs, zero `PriceBookEntryDerivedPrice` rows). Defense-in-depth guard warranted (a future derived-maintenance cancel would hard-error or recompute the net).
  - seq 22 `ListContainer10` `DerivedPricingNetUnitPriceValueReset` — formula `IF(QuoteTypeText='Renewal', NetUnitPrice, 0)`, gated `ItemIsDerived__std Equals true` → does not enter for this line. Defense-in-depth.
  - seq 36 `FormulaBasedPricing3` — **unconditional**, `TotalLineAmount = MAX(ItemNetTotalPrice, TotalLineAmount)`; sole output `TotalLineAmount`. Not the Total-Price cause, **but** once the fix makes `ItemNetTotalPrice=−15000`, `MAX(−15000,0)=0` corrupts the Subtotal — must be guarded.

## 3. The solution — ordered steps

All edits are V18 metadata changes (ESDVersion `9QBWC0000000o3F4AQ`, ESD `9QAWC0000003mg14AA`). Active version can't be edited in place → deactivate → deploy (api 67 + `--metadata-dir`; the `rca_diagnostic.cls-meta.xml` orphan blocks source-format ops) → UI-activate, offline window. **Needs a fresh UAT deploy/activate ack.**

### 3a. Hydration — already working; do NOT Sync
Verify only: (1) FINEST reprice shows `CancelNetUnitPrice__c=15000` in RLM_PRICING_BEGIN for the line (it does); (2) profile FLS present (granted to System Administrator on QuoteLineItem + OrderItem). Do **not** click Sync — V23 mapping already delivers the field; a needless resync risks the working context. The deactivate/Sync/reactivate runbook is NOT part of this fix.

### 3b. Cancel seed group edits — the core fix (writability confirmed)
Inside `ListContainer12` (seq 13), under the **same** `CancellationSeed` filter (`CancelNetUnitPrice__c IsNotNull`), add **two** `AssignmentElement` children (do not alter the existing three):
- **`CancelSeedDerivedFalse`** → set `DerivedPricingAttribute = false` (boolean literal). Satisfies gate criteria 2 (`IsNotNull`) and 3 (`Equals false`). Confirmed writable: `DerivedPricingAttribute` = boolean, `fieldType=inputoutput`, `transient=true` (pure in-context, no SObject).
- **`CancelSeedPricingSource`** → set `ItemPricingSource` to a non-`LastTransaction` literal (sentinel `'CancelSeed'`). Makes criterion 1 deterministically true; keeps the line in the `ListContainer72` partition (away from the `ListContainer75` `Equals 'LastTransaction'` sibling). Confirmed writable: `ItemPricingSource` → context attr `PricingSource`, string, `fieldType=inputoutput`.

Build by cloning `CancelSeedNet`'s shape (`section-0-input1` literal → `section-0-output` target via `sectionJsonString2`). `PricingTermCount=1` (FormulaBasedPricing1) and `CancelSeedNet → NetUnitPrice` stay unchanged. Placement: same level as the other assignments, after the filter; runs before `QuantityPrice74` (seq 25) since the group is seq 13.

### 3c. Downstream clobber prevention
Guard field: **`SalesTransactionActionType Equals 'Cancel'`** (enum string, runtime `Cancel` confirmed) or **`LineItemQuantity LessThan 0`**. **Never** use `ItemSalesTransactionAction` for `=Cancel` — it holds the QuoteAction Id (`7ocWC00000jSfhRYAS`), never matches.
1. **seq 36 `FormulaBasedPricing3` (REQUIRED — fixes negative Subtotal):** rewrite to `TotalLineAmount = IF(LineItemQuantity < 0, ItemNetTotalPrice, IF(ItemNetTotalPrice > TotalLineAmount, ItemNetTotalPrice, TotalLineAmount))`. Positive lines keep MAX; negative lines take `ItemNetTotalPrice` directly.
2. **seq 16 `DerivedProductsNativePull` (defense-in-depth):** add `AND SalesTransactionActionType NotEquals 'Cancel'` to `DerivedProductsNonRenewal`.
3. **seq 22 `ListContainer10` `DerivedPricingFilter` (defense-in-depth):** add `AND SalesTransactionActionType NotEquals 'Cancel'`.

### 3d. Populator for real cancellations
Subject row already has `CancelNetUnitPrice__c=15000`, so §3b–§3c fix it. For all future cancellations, the prehook `CancelLineNetSeedPrehook` resolves each cancel line's asset NET (`OrderAction/QuoteAction.SourceAssetId → AssetActionSource.NetUnitPrice`, Generate/Initial-Sale) and writes `CancelNetUnitPrice__c` via DML-free `updateContextAttributes`. Confirm it's registered/active in Plan `Fortra_Pricing_PreHook`, ordered before the procedure body; add the queryable debug-record sink (own try/catch) for observability.

## 4. Validation plan
- **Simulator (isolate gate/clamp):** Simulate rejects `__c` inputs, so pre-set `NetUnitPrice=15000`. OLD V18 with `DerivedPricingAttribute=null` → `ItemTotalPrice=0`. Edited V18 with `DerivedPricingAttribute=false` + `ItemPricingSource='CancelSeed'` → `QuantityPrice74` runs → `ItemTotalPrice=−15000`, `FormulaBasedPricing3` doesn't clamp.
- **Live FINEST reprice (decisive):** RLM_PRICING_END for the line shows `ItemNetTotalPrice=−15000`, `ItemTotalPrice=−15000`, `TotalLineAmount/ItemSubtotal=−15000`, no "contributing products missing". (Output-only attrs aren't in the dump — judge by dumped outputs + UI Total Price + the §3d debug sink + the price waterfall.)
- **Comparators:** a discounted cancel (net≠list) and a ListPrice-0 cancel must refund asset NET (negative), not list/0; a normal positive line unchanged (seed group skipped via `CancelNetUnitPrice__c IsNull`).

## 5. Risks, blast radius, rollback
Shared Quote+Order procedure. §3b edits live inside the cancel-only `CancellationSeed` filter → fire only on cancel lines. §3c-1 clamp guard is qty<0-gated → positive lines keep MAX. §3c-2/3 only narrow derived gates by excluding Cancel. `ItemPricingSource='CancelSeed'` sentinel is set only in the cancel group; verify no cancel-path step misreads it (the LastTransaction partition needs exact `Equals`). Rollback: keep the pre-edit V18 snapshot; deactivate edited → reactivate prior (never delete a version). Re-pull active-version list before deploy (V16 oscillation observed). UAT-only; prod is different-lineage → separate port + validation.

## 6. Confidence map
| Item | Confidence |
|---|---|
| Total Price = `ItemTotalPrice`, sole writer `Assignment111` (unconditional) | HIGH |
| `QuantityPrice74` gate is the controlling live defect (null `DerivedPricingAttribute`/`ItemPricingSource`) | HIGH |
| Hydration already works; no Sync needed | HIGH |
| §3b two seeds flip the gate (writability confirmed) | HIGH |
| §3c-1 MAX-clamp guard required for correct Subtotal | HIGH (mechanism) |
| seq 16/22 inert for subject line but execute → defense-in-depth | HIGH (inertness) |
| `SalesTransactionActionType='Cancel'` is the correct guard field | HIGH |

**Open questions (resolve on the authorized FINEST run):** (1) confirm `CancelSeedNet` actually lands `NetUnitPrice=15000` at runtime (output-only, not dumped — confirm via `StampBaseFilter` passing + debug sink + waterfall); (2) exact pre-guard Subtotal magnitude (§3c-1 pre-empts); (3) prehook firing on every real cancel path (debug sink makes observable).

## 7. If it still fails: Salesforce-case fallback
If a live FINEST reprice still shows `ItemNetTotalPrice=0` despite both gate attrs seeded **and** `CancelSeedNet` confirmed run, the failure is RLM's opaque seed-propagation (child-group AssignmentElement outputs not visible to a later step) — not metadata-addressable. Then: package the V18 diff + before/after FINEST + debug-sink records + gate definition; open an RLM pricing-procedure case ("seeded context attributes set by an AssignmentElement in an earlier ListGroup aren't visible to a later filter/formula in the same run; Simulator computes correctly, live doesn't"). Interim workaround: have `CancelLineNetSeedPrehook` write **all** gate-enabling attrs (`NetUnitPrice`, `DerivedPricingAttribute=false`, `ItemPricingSource`) directly into context (prehook writes provably land in BEGIN), bypassing the in-procedure seed group; keep §3c guards.
