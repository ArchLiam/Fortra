# SC-3350 — RCA: NetUnitPrice = $0 on non-derived renewal lines

**Method:** static trace of the active V10 pricing procedure (52,499 lines) + COLA prehook, ~90% confidence
(residual is runtime-only, confirmable by a waterfall/debug trace). **Read-only.**

## Root cause (one sentence)

In the renewal (`ItemPricingSource = 'LastTransaction'`) pricing branch, COLA **Path A**
(`COLAUpliftonRenewal10`) writes the COLA price only to **`InputUnitPrice`**, and the *only* step that seeds
**`NetUnitPrice := InputUnitPrice`** — `QuantityPrice49` (plus the discount computers `AttributeBasedPrice` /
`PartnerDiscount13` in `ListContainer35`) — is gated **`ItemPricingSource NotEquals 'LastTransaction'`**, so a
non-derived renewal line never gets `NetUnitPrice` initialized; it stays at the engine default **0**, which
`SubscriptionPricing` (gated only on `SellingModelType='TermDefined'`) then reads as input and faithfully
writes back as 0.

## Why the list side is right but the net side is 0

| Side | Driven by | Our line | Status |
|---|---|---|---|
| List: UnitPrice / Subtotal / TotalLineAmount | `InputUnitPrice` ← `COLACalculatedPrice__c` (Path A `COLAUpliftonRenewal10`, L1465/1493) | 4697.946 / 929.25 | ✅ correct |
| Net: NetUnitPrice / NetTotalPrice / TotalPrice / GrandTotal | needs a `InputUnitPrice → NetUnitPrice` seed | never seeded → 0 → propagated 0 | ❌ $0 |

The seed step `QuantityPrice49` (L3473, container `ListContainer47`, filter L3422) and the discount-based
NetUnitPrice computers (`ListContainer35`, filter `ListOperation36` L2299) all carry
`ItemPricingSource NotEquals 'LastTransaction'`. The renewal branch `ListContainer55`
(filter `ListOperation56` L2377, `ItemPricingSource Equals 'LastTransaction'`) contains a `FormulaBasedPricing`
step that **reads** `NetUnitPrice * LineItemQuantity` (L1837) but never **seeds** NetUnitPrice.

## This is NOT a COLA bug — it's a procedure gap COLA exposed

Any **non-derived renewal line** priced from LastTransaction hits this: there is no `NetUnitPrice` seed in the
renewal branch. The procedure assumes renewals are **derived** (Path B / MDT maintenance, which gets
NetUnitPrice from `DerivedPricingRenewals`); the COLA-on-a-plain-product case (non-derived + renewal) falls
through the gap. This is the **$0-net family** (SC-3345 / SC-3347 territory), surfaced by COLA.

## Fix (preferred → least risk)

1. **Procedure (preferred):** add a scoped `AssignmentElement` `InputUnitPrice → NetUnitPrice` inside the
   renewal container `ListContainer55`, gated `ItemPricingSource Equals 'LastTransaction'` **AND**
   `DerivedPricingAttribute = false`, sequenced **before** the `SubscriptionPricing` group (seq ~22). This is
   the missing symmetric counterpart of `QuantityPrice49` for the LastTransaction side. Restricting to
   non-derived guarantees no collision with Path B (`DerivedPricingRenewals`, L48653). → new version **V11**.
2. *(smaller but riskier)* relax the `QuantityPrice` filter to also allow the renewal case — risks clobbering
   Path-B derived renewals; not recommended.
3. *(Apex)* have `COLAUpliftPrehook.buildItemUpdate` also write `NetUnitPrice` — risky: class comments
   (L545-548) warn some context attributes "poison the batch" without a verified hydration mapping.

## Important ownership / coordination note

This edits the **shared, active `Rev_Mgmt_Default_Pricing_Procedure`** (Marc DeBrey's domain). Per prior
incidents, in-place edits to the live procedure without re-syncing context have caused gacks. **Coordinate
with Marc** before publishing V11; build + validate on quote `0Q0WC000003671t0AA` first.

## Confirm cheaply before editing

`ItemPricingSource` / `DerivedPricingAttribute` are runtime context attributes (not stored fields), so SOQL
can't confirm. Confirm via the **pricing waterfall / Explainability panel** (or a Reprice-All debug log) on the
two lines — expect: `COLAUpliftonRenewal10` set InputUnitPrice; `QuantityPrice49` / `AttributeBasedPrice` /
`PartnerDiscount13` **skipped**; `SubscriptionPricing` ran with NetUnitPrice input = 0.
