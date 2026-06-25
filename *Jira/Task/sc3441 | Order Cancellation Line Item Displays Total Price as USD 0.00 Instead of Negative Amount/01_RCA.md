# SC-3441 — RCA Dossier: Order Cancellation Line Total Price shows USD 0.00 instead of the negative amount

**Ticket:** SC-3441 "Order Cancellation Line Item Displays Total Price as USD 0.00 Instead of Negative Amount"
**Reporter:** Joe Romo
**Org:** FortraUAT (sandbox, `00DWC000006eUFF2A2`) — Revenue Cloud Advanced / native RLM, single shared pricing procedure for Quote + Order
**Subject order:** 00095539 / `801WC00000ktJPMYA2` — cancellation of Asset "Arcus Hosting"
**Date:** 2026-06-24
**Status of this dossier:** FINAL. Incorporates three adversarial reviews (mechanism-skeptic, expected-value-skeptic, fix-safety-skeptic). Where a verdict refuted or corrected the synthesis, the conclusion below is the corrected one — **the original synthesis's rank-1 "V16 InputUnitPrice seed regression is THE root cause" is downgraded; the load-bearing defect is the null `NetUnitPrice` *field* on the cancel line, which feeds the `TotalPrice` formula and is not populated by any seed.**

---

## 1. Executive summary

Cancelling an order/asset creates a cancellation line with Quantity −1 and ListPrice 3000, but **Total Price = USD 0.00** instead of **−3000.00**. The proximate cause is that the line-total formula `ItemNetTotalPrice = NetUnitPrice × LineItemQuantity` multiplies a **null `NetUnitPrice` field** by −1 and yields 0, which then copies to `ItemTotalPrice → TotalPrice`. The **root cause** is that on a cancel/reduction line the native RLM price waterfall produces no priced row (`PriceWaterfallIdentifier = null`), so the **`NetUnitPrice` field is never populated** for that line, and the procedure has **no declarative step that seeds the `NetUnitPrice` field from list price or the originating asset's net** — the only declarative writer of the `NetUnitPrice` field anywhere in the active procedure is the COLA-renewal branch (`COLACalculatedPrice__c → NetUnitPrice`), which does not fire here. This is **systemic**: 6/6 cancellation lines that actually ran the procedure are broken; the only "working" negative lines are bulk-migrated rows with a pre-stamped `UnitPrice` that bypassed the procedure entirely. **Recommended fix:** add a tightly-gated step (or prehook) that seeds the **`NetUnitPrice` field** (not `InputUnitPrice`) on cancel/reduction lines from the originating asset's net (`AssetActionSource.NetUnitPrice`, with `ListPrice` as a fallback only when asset net is unavailable and `ListPrice > 0`), placed before the subscription/line-total step and gated to fire only when `NetUnitPrice IsNull AND PriceWaterfallIdentifier IsNull AND LineItemQuantity < 0` — and resolve the **dual-Active V14/V16 anomaly** first so the executing version is deterministic.

---

## 2. Evidence (hard data)

All IDs queried LIVE from FortraUAT. File references are to the live retrieve:
`Data/sc3441/retrieve/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition` (API v66, 92,611 lines).

### 2.1 The broken cancellation line (Order side)

| Field | Value |
|---|---|
| OrderItem | `802WC00000OugI7YAJ` |
| Order | 00095539 / `801WC00000ktJPMYA2` (OriginalActionType `Cancel`, Status `Order Complete`, TotalAmount 0, IsReductionOrder **false**) |
| OrderAction | `8OAWC000002SxiL4AS` (Type `Cancel`, **SourceAssetId `02iWC000008MpX7YAK`** → asset-based cancellation) |
| Product2 | Arcus Hosting `01tWC00000DD11IYAT` |
| Selling model | `0jPWC000000060b2AA` = "Term Based - Annual", `SellingModelType = TermDefined` |
| StartQuantity / EndQuantity / Quantity | 1 / 0 / **−1** |
| PricebookEntryId | `01uWC000005wrrCYAQ` (UnitPrice/list 3000, IsDerived false) |
| ListPrice | **3000** (present) |
| UnitPrice | **NULL** |
| NetUnitPrice | **NULL** |
| TotalPrice / NetTotalPrice / TotalLineAmount | **0 / 0 / 0** |
| PriceWaterfallIdentifier | **NULL** (no native priced row) |
| PricingTermCount | 1 |
| ServiceDate → EndDate | 2026-06-16 → 2027-06-15 (full term — no proration) |
| Asset__c / OriginalOrderItemId / PriceRevisionPolicyId | **all null** |

### 2.2 The same defect at the Quote stage (shared procedure)

Cancellation Quote `0Q0WC000003A8PB0A0`, QuoteLineItem `0QLWC000003fKAj4AM`: Quantity −1, ListPrice 3000, UnitPrice NULL, NetUnitPrice NULL, TotalPrice 0, NetTotalPrice 0. Identical pattern, confirming the single shared `Rev_Mgmt_Default_Pricing_Procedure` for Quote + Order.

### 2.3 The smoking-gun intermediate row

OrderItemDetail `14CWC000001KXDl2AO` (the procedure's own waterfall snapshot for the cancel line) carries **UnitPrice = 3000 and NetUnitPrice = 3000**, Quantity −1, yet **TotalLineAmount = 0 and TotalPrice = 0**. So a correct unit price of 3000 was resolved onto the *detail* row, but the line-level `NetUnitPrice` field that the total formula reads stayed null and the total came out 0. (See §3 for why the detail's 3000 and the line's null are different observation points.)

### 2.4 The price source of truth (asset lineage)

```
Asset 02iWC000008MpX7YAK "Arcus Hosting"  Price=3000  PricingSource=NULL
  AssetAction 4nLWC00000333aj2AA (AA-000543593, Type Generate, "Initial Sale")
    AssetActionSource 4nMWC0000046hkj2AA (AAS-000543597)  *** SOURCE OF TRUTH ***
      ListPrice 3000 | UnitPrice 3000 | NetUnitPrice 3000 | TotalPrice 3000
      ReferenceEntityItemId = 802WC00000OtSYxYAN (the ORIGINAL sold OrderItem)
      PricebookEntryId 01uWC000005wrrCYAQ (SAME PBE as the cancel line)
```
There is **no AssetAction of Type Cancel** and **no AssetActionSource** referencing the cancellation OrderItem (`TotalCancellationsAmount` stayed 0). The original sale was undiscounted, so for THIS line net == list == 3000.

### 2.5 Active procedure version (drift-checked, live tooling API)

ExpressionSetDefinition `9QAWC0000003mg14AA`. **Two versions are Active simultaneously** (anomaly):

| Version | Id | Status | startDate | File block (lines) | Closing `<versionNumber>` tag |
|---|---|---|---|---|---|
| V14 | `9QBWC0000000nIT4AY` | **Active** | 2026-06-18 | 69795–75411 | `14` (line 75410) |
| V15 | — | Inactive | — | 75412–80963 | `15` (line 80962) |
| **V16** | `9QBWC0000000niH4AQ` | **Active** | 2026-06-18 | **80964–86874** | **`16` (line 86873)** |
| V17 | — | Inactive | — | 86875–92610 | `17` — label "Rev Mgmt Default Pricing V17 (SC-3441 fix, V15 base)" |

Both Active versions share the same `startDate` with no rank/endDate → RLM resolves to the **highest version number = V16 executes**. (Correction to synthesis: the `<versionNumber>` tag sits at the **end** of each block; line 86873 reads `16`, so the inspected 80964–86874 block IS org version 16. There is **no +1 offset** — the synthesis's "internal versionNumber 15" reasoning was wrong, though it inspected the correct block, so the version conclusion survives.)

### 2.6 Population / base rate (systemic, not data-specific)

| Probe | Count |
|---|---|
| OrderAction Type='Cancel' | 2 |
| OrderItem Quantity < 0 | 2 (both broken, identical pattern) |
| QuoteLineItem Quantity < 0 | 42 |
| → priced **correctly** | 36 — **all created by `Service Data Migration`** (UnitPrice pre-stamped, procedure bypassed) |
| → **broken** (UnitPrice null → TotalPrice 0) | **6 — all created by real users via the UI cancellation flow = 6/6 = 100% broken** |

The 6 broken lines span 4 months (2026-03-20 → 2026-06-16), 5 users, 2 families (Subscription, Services), ListPrice 0 → 15000. Discriminator is **provenance (procedure-run vs migrated)**, NOT product/selling-model/region/Asset/ListPrice/date. `Cancel`, `StartQuantity`, `EndQuantity` each appear **0 times** in the procedure — there is no cancellation/reduction-aware branch.

---

## 3. Root cause (precise mechanism)

### 3.1 Proximate: the total formula faithfully multiplies a null base price

The line total reaches `TotalPrice` via this chain (V16 block):

- `QuantityPrice64` (FormulaBasedPricing, parentStep `ListContainer62`, file line 85391): `ItemNetTotalPrice = NetUnitPrice × LineItemQuantity`. **Reads the field `NetUnitPrice`.** Gate (`ListContainer62`, seq 26): `ItemPricingSource NotEquals 'LastTransaction' AND DerivedPricingAttribute IsNotNull AND DerivedPricingAttribute = false`.
- `Assignment108` (seq 41, file lines 81415/81435): `section-1` copies **`ItemNetTotalPrice → ItemTotalPrice`** (→ `TotalPrice`); `section-0` copies `TotalLineAmount → ItemSubtotal`.

`NetUnitPrice` field is null → `ItemNetTotalPrice = null × −1 = 0` → `ItemTotalPrice = 0` → `TotalPrice = 0`. This is the symptom, not the root.

### 3.2 Root: the `NetUnitPrice` *field* is never populated on the cancel line

The decisive structural fact (verified identically in V14 and V16) is that the procedure runs **two parallel subscription pipelines on different fields**:

| Subscription step | Price input (field) | Total output (field) | Net output (field) | Parent / gate |
|---|---|---|---|---|
| `SubscriptionPricing` (file 85993) | **`NetUnitPrice`** | `ItemNetTotalPrice` | **`NetUnitPrice`** | `EvergreenanytimeprorationfilterLinelevel` |
| `SubscriptionPricing80` (file 86072) | `InputUnitPrice` | `TotalLineAmount` | `InputUnitPrice` | `ListContainer77` |
| `SubscriptionPricing86` (file 86151) | `InputUnitPrice` | `TotalLineAmount` | `InputUnitPrice` | `ListContainer84` (gate `SellingModelType = TermDefined OR Evergreen`) |

The pipeline that feeds **`TotalPrice`** is the `NetUnitPrice`-field pipeline (`SubscriptionPricing` + `QuantityPrice64`, both reading and writing the field `NetUnitPrice`, both producing `ItemNetTotalPrice → ItemTotalPrice → TotalPrice`). The `InputUnitPrice` pipeline (`SubscriptionPricing86`) only feeds `TotalLineAmount → ItemSubtotal`.

**Who populates the `NetUnitPrice` field?** An exhaustive enumeration of every write to the `NetUnitPrice` field in V16 returns exactly:
- Native `PricingSettings` / `SubscriptionPricing` waterfall actions (`SubscriptionNetUnitPrice → NetUnitPrice`, e.g. file 85987) — keyed off `LineItemId` / Contract / IsDerived / effective dates; and
- One declarative write: `COLACalculatedPrice__c → NetUnitPrice` (file 82483, COLA-renewal only — gated off for this line).

For the cancel line the native waterfall **produced no priced row** (`PriceWaterfallIdentifier = null`, vs the normal +1 sale line `802WC00000OtSYxYAN` which has a populated identifier and NetUnitPrice 3000). So the `NetUnitPrice` field is **null**, nothing declarative seeds it (COLA branch skipped), and the total formula yields 0.

**This is the corrected root cause.** It is *not* primarily the V14→V16 seed change, because that seed writes the `InputUnitPrice` field, which feeds only the `ItemSubtotal` pipeline — it never reaches the `NetUnitPrice` field that `TotalPrice` is computed from. (See §8 for how the three adversarial reviews drove this correction.)

### 3.3 The V14→V16 seed change — real, but not load-bearing for `TotalPrice`

At `ListContainer47` / step `Assignment` (seq 2), the InputUnitPrice null-seed was changed between versions:
- **V14** (file line 70181): `ListPrice → InputUnitPrice`, label "Assignment".
- **V16** (file line 81350): `NetUnitPrice → InputUnitPrice`, label "Sync InputUnitPrice from Net", description "Sync discount base from post-attribute NetUnitPrice (Partner/Manual steps use InputUnitPrice)."

The gate is byte-identical in both (`InputUnitPrice IsNull AND ItemPricingSource NotEquals 'LastTransaction' AND DerivedPricingAttribute IsNotNull AND = false`). V16 has **0** `ListPrice → InputUnitPrice/NetUnitPrice` seeds; V14 has exactly 1. The change was **deliberate** (the V16 rework added a whole partner/derived-maintenance block: "Stamp Base_Price and Pre_Partner from Net", "Resolve Partner Discount Percent", "Manual Discount - Derived Maintenance" — the SC-3346/SC-3359/`PartnerNetPricePosthook` area MEMORY flags as fragile/oscillating).

**Why this matters but isn't the cure:** because the seed only ever feeds `InputUnitPrice`, restoring `ListPrice → InputUnitPrice` (the V14 behavior) would repopulate `ItemSubtotal` but would **not** by itself put 3000 into the `NetUnitPrice` field that `TotalPrice` reads. Independent corroboration: the **already-drafted Inactive V17 ("SC-3441 fix, V15 base")** did exactly this — it re-added two `ListPrice → InputUnitPrice` seeds **but added zero new writes to the `NetUnitPrice` field** — and it remains Inactive/unshipped, consistent with that approach not actually fixing `TotalPrice`.

### 3.4 Refuted sub-hypotheses

- **REFUTED — negative-quantity gate starves the seed.** `AllLinesNullSafeFilter` (`LineItemQuantity >= 0`) is parented to `ListContainer11` and governs only the discount-adjustment null-guard (`NullSafeLineAdjustment`), NOT the `ListContainer47` price seed. The seed branch has no quantity-sign criterion and DOES run for the cancel line. (Confirmed; consistent across V14/V16.)
- **REFUTED as the cause of `TotalPrice = 0` — the MAX clamp.** `FormulaBasedPricing3` (`TotalLineAmount = IF(ItemNetTotalPrice > TotalLineAmount, ItemNetTotalPrice, TotalLineAmount)`, file 83426) is a **top-level step (no parentStep), seq 37, `resultIncluded=false`** — it runs unconditionally and would zero a negative `TotalLineAmount`. **But it writes only `TotalLineAmount` (→ `ItemSubtotal`); it does not write `ItemNetTotalPrice` or `ItemTotalPrice`.** Since `TotalPrice` is copied from `ItemNetTotalPrice` (Assignment108 section-1), the clamp **cannot** be the cause of `TotalPrice = 0`. (This refutes the mechanism-skeptic's proposed competing root cause, while confirming the clamp exists and would corrupt `ItemSubtotal`/`Subtotal` for any legitimately-negative line — a separate latent bug worth fixing.) The mechanism-skeptic's structural mapping was also corrected: the no-clamp line total is `QuantityPrice64` under `ListContainer62`; `ListContainer70` is the `ItemPricingSource == 'LastTransaction'` path.

---

## 4. What the correct value should be (and from which source)

**Correct cancellation credit = `NetUnitPrice(asset) × LineItemQuantity`**, where `NetUnitPrice(asset)` is the **original NET the customer paid**, sourced from `AssetActionSource.NetUnitPrice` (= `Asset.Price` = original OrderItem `802WC00000OtSYxYAN` NetUnitPrice). For the subject line that is **3000 × −1 = −3000.00**.

**Settle the list-vs-asset-net question — the value is the asset NET, not list:**
- For THIS line, the original sale was undiscounted, so net == list == 3000; ListPrice and asset-net coincide. The ticket's stated expected value −3000.00 is therefore **correct, but only coincidentally equal to list**.
- Across the org, **net ≠ list is the norm**: of 1,999 AssetActionSource rows with both values, **1,539 (77%) have NetUnitPrice ≠ ListPrice** (concrete discounts: list 250 → net 115.5; list 250 → net 165; list 42 → net 14.7; list 2021.25 → net 1010.625), and **907 rows have ListPrice 0 with a nonzero net actually paid** (list 0 → net 1000 / 3575 / 5000 / 12000). A list-price-based credit would **over-refund every discounted cancellation by the discount amount** and **under-refund (to 0) the ListPrice-0 cancellations**.
- The ticket's own comparator set proves it: two of the six broken lines have **ListPrice = 0** (beSECURE-Cloud-Based, Automate Enterprise). A ListPrice-only fallback credits 0 for those (correct for beSECURE only by luck — its asset genuinely is net 0).

No proration applies (full term, `PricingTermCount = 1`, `ServiceDate → EndDate` spans the whole term).

| Target on cancel line | Should be | Sourced from |
|---|---|---|
| `NetUnitPrice` (field) | 3000 | `AssetActionSource.NetUnitPrice` (AAS-000543597) = `Asset.Price` = orig OrderItem.NetUnitPrice |
| `LineItemQuantity` | −1 | StartQty 1 → EndQty 0 (already correct) |
| `TotalPrice` / `NetTotalPrice` / `TotalLineAmount` | **−3000.00** | `NetUnitPrice × Quantity` = 3000 × −1 |

---

## 5. Why it reproduces / scope

**Systemic, deterministic for procedure-priced cancellations.** Every cancellation/negative-qty line that actually executed the live procedure ended NULL `NetUnitPrice` → `TotalPrice` 0 (6/6 = 100%). The "working" negative lines are bulk-migrated records carrying a pre-stamped `UnitPrice` that bypassed the procedure. The trigger is independent of product, selling model, region flag, Asset link, PriceRevisionPolicy, ListPrice value, and date — it is purely **procedure-run vs migrated provenance**:

1. PBE lookup fills `ListPrice` only (no `NetUnitPrice`/`UnitPrice` write).
2. The native RLM price waterfall returns **no priced row** for the cancel/reduction line (`PriceWaterfallIdentifier = null`) → the **`NetUnitPrice` field stays null**.
3. No declarative step seeds the `NetUnitPrice` field on a non-COLA line; the `InputUnitPrice` seed (V14 list / V16 net) feeds only the `ItemSubtotal` pipeline.
4. `NetUnitPrice × LineItemQuantity = null × −1 = 0` → `ItemNetTotalPrice 0 → ItemTotalPrice 0 → TotalPrice 0`.

Reproduces identically at Quote and Order stages (one shared procedure). Will recur on every future UI cancellation until the `NetUnitPrice` field is seeded on the cancel path.

---

## 6. Fix options (ranked)

> The two skeptics that examined the fix agree the **list-price seed is structurally inadequate** (over-refunds the 77% discounted population, under-refunds the ListPrice-0 cancellations) **and likely ineffective** (it feeds `InputUnitPrice`, not the `NetUnitPrice` field that `TotalPrice` reads). The asset-net seeding path is therefore promoted to the recommended fix. **The previously-"low-risk" ListPrice-COALESCE seed is NOT recommended.**

### ★ RECOMMENDED — Option A: Seed the `NetUnitPrice` field on cancel/reduction lines from the originating asset net

- **What:** Add a step (or a small prehook) that, for cancel/reduction lines, populates the **`NetUnitPrice` field** (the one the total formula reads) from `AssetActionSource.NetUnitPrice` (resolved via `OrderAction.SourceAssetId` → AssetAction → AssetActionSource), with `ListPrice` as a fallback **only** when asset net is unavailable AND `ListPrice > 0`. Then total = `NetUnitPrice × LineItemQuantity`.
- **Where:** New branch in `Rev_Mgmt_Default_Pricing_Procedure` **before** the `SubscriptionPricing` / `QuantityPrice64` line-total step, plus a prehook to resolve the asset link (necessary because `Asset__c` / `OriginalOrderItemId` / `PriceRevisionPolicyId` are all null on the cancel OrderItem, so the procedure has no direct pointer to the asset net at runtime). Deploy per the api-67 + `--metadata-dir` + UI-activation mechanics (`reference_pricing_procedure_deploy_mechanics`).
- **Gate (tight, to avoid blast radius):** fire only when `NetUnitPrice IsNull AND PriceWaterfallIdentifier IsNull AND LineItemQuantity < 0` (or `OrderAction.Type = 'Cancel'` / `SourceAssetId` present). This deliberately avoids the partner-discount base waterfall (`Base_Price__c` / `Pre_Partner_Price__c` / `InputUnitPrice`) entirely, so it cannot perturb partner/COLA/regional pricing.
- **Why this is the correct value:** covers the whole 6/6 broken population including the ListPrice-0 cancellations (which require the asset net, not list). For the subject line it yields the correct −3000.
- **Blast radius / risk:** Medium. Larger surface; needs a prehook + new test coverage (procedure is UAT-only, 0% coverage today). Interacts with the `ItemPricingSource == 'LastTransaction'` line-total path (`ListContainer70`) only if the cancel line ever materializes as LastTransaction — handle both line-total containers.
- **Effort:** High.

### Option B (do FIRST, prerequisite): Resolve the dual-Active V14/V16 anomaly

- **What:** Deactivate the redundant version (V14 or V16) via the UI so exactly one version is Active and behavior is deterministic; confirm via a FINEST pricing log which version executes for a reprice today. Do NOT delete (version delete is platform-blocked per `project_pricing_proc_version_delete_blocked`); keep the `PricingActionParameters` Quote/Order context bindings intact.
- **Where:** ExpressionSetDefinition `9QAWC0000003mg14AA` version activation (UI-only). V14 `9QBWC0000000nIT4AY` and V16 `9QBWC0000000niH4AQ`, identical `startDate` 2026-06-18.
- **Risk:** Low-medium. Removes ambiguity; does not by itself fix the price. **This is a prerequisite to any fix** so you can prove which version executes before/after.
- **Effort:** Low.

### Option C (NOT recommended as the fix): Restore / COALESCE the `InputUnitPrice` seed (the V14 behavior / drafted V17)

- **What:** Change the `ListContainer47` seed to `ListPrice → InputUnitPrice` (V14) or `COALESCE(NetUnitPrice, ListPrice) → InputUnitPrice`.
- **Why rejected:** (1) **Likely ineffective for `TotalPrice`** — the seed feeds `InputUnitPrice`, which routes to `ItemSubtotal`, not the `NetUnitPrice` field the `TotalPrice` formula reads; the already-drafted Inactive **V17** took exactly this approach (two `ListPrice → InputUnitPrice` seeds, zero `NetUnitPrice`-field writes) and remains unshipped. (2) **Unsafe** — flips the partner-discount base waterfall (`IF(Base_Price__c>0,…,IF(Pre_Partner_Price__c>0,…,IF(InputUnitPrice>0,InputUnitPrice,0)))`) from 0 to ListPrice on any partner line whose `NetUnitPrice` is null at seq 13, regressing computed partner discounts (the SC-3359/SC-3346 entanglement). (3) **Wrong value** — list ≠ net for 77% of cancellations; ListPrice-0 cancellations under-refund to 0.
- **Risk:** Medium-to-high (partner-line regression) + unproven efficacy. **Effort:** Low.

### Option D (NOT recommended — also fix separately): Repair the unconditional MAX clamp

- **What:** `FormulaBasedPricing3` (seq 37, unconditional) zeroes any negative `TotalLineAmount` → corrupts `Subtotal`/`ItemSubtotal` for legitimately-negative lines even once the net is seeded. Condition it on `LineItemQuantity >= 0`, or compute `TotalLineAmount = NetUnitPrice × LineItemQuantity` unconditionally on the cancel path.
- **Why separate:** It does **not** cause the ticketed `TotalPrice = 0` (it doesn't write `ItemTotalPrice`), but it WILL produce a wrong `Subtotal` on cancel lines once Option A makes the net non-null. Fold this into Option A's validation.
- **Risk:** Low. **Effort:** Low.

### Option E (NOT recommended — emergency stopgap only): pre-stamp UnitPrice/NetUnitPrice via automation

- A before-save flow/Apex on negative-qty QLI/OrderItem stamps `NetUnitPrice` (mirrors why migrated negative lines price correctly). Masks the defect, fragile, easily reverted by Gearset/refresh, diverges Quote vs Order. Only justified if a procedure deploy window is unavailable. **Risk:** High (mask, not cure). **Effort:** Medium.

**Recommended sequence:** B (deterministic single Active version) → A (asset-net seed on the `NetUnitPrice` field) → D (clamp guard) → validation across comparators.

---

## 7. Risks & open questions / what to verify before any change

1. **Active-version drift.** MEMORY warns the active `ExpressionSetVersion` drifts across days (V9→V12→V13→V14→V16 observed). **Two versions are Active right now** (V14 + V16, same startDate). Re-pull live and re-confirm V16 executes immediately before AND after any change; land the fix on the executing version. Resolve the dual-Active state first (Option B).
2. **Decisive runtime confirmation still pending.** The materialized `ItemPricingSource` on the cancel line was not directly read (`Asset.PricingSource = NULL` strongly implies it is NOT 'LastTransaction', so the `ListContainer62` no-clamp branch runs — consistent with this RCA, but unconfirmed). **Before deploying, run an authorized FINEST pricing-waterfall reprice** and read for the cancel line: (a) materialized `ItemPricingSource`; (b) whether the native waterfall returns a `NetUnitPrice` row or null; (c) which line-total container fires (`ListContainer62 QuantityPrice64` vs `ListContainer70`); (d) the `NetUnitPrice` field value at `QuantityPrice64`. This settles the §3 mechanism definitively.
3. **Detail-vs-line tension to reconcile.** OrderItemDetail `14CWC000001KXDl2AO` shows `NetUnitPrice = 3000` while the parent OrderItem `NetUnitPrice` is null and `TotalPrice = 0`. These are different observation points (an intermediate detail/waterfall snapshot vs the final line). The FINEST log should show whether the native step momentarily held 3000 and the field that the total formula reads never received it. Option A's "seed the field the total reads" is robust to either resolution.
4. **Shared-procedure regression surface.** One procedure serves Quote + Order and all pricing channels (attribute, regional, COLA, partner, derived-maintenance). Gate Option A tightly (`NetUnitPrice IsNull AND PriceWaterfallIdentifier IsNull AND qty<0`) and validate that `NetUnitPrice` / `Base_Price__c` / `Pre_Partner_Price__c` / `InputUnitPrice` are **unchanged** for partner, COLA-renewal, derived-maintenance, regional, and normal positive-qty comparators (e.g. list 250 → net 115.5).
5. **Durability.** PAD/data flags and procedure versions have silently reverted via Gearset/refresh before (NB-DERIVED-TIER, SC-3390). Bake the fix into the republish source and coordinate with the procedure owner (Nir / Marc DeBrey have been iterating this proc). Do not delete inactive versions (platform-blocked); deactivate only.
6. **0% test coverage.** The procedure and its prehooks are UAT-only with no test coverage today; Option A's prehook needs coverage before any prod promotion. Prod cutover is separately blocked (pre-cutover).
7. **The drafted V17 is not a safe shortcut.** Inactive V17 ("SC-3441 fix, V15 base") only re-adds `ListPrice → InputUnitPrice` seeds (Option C) and adds no `NetUnitPrice`-field write — do not activate it expecting it to fix `TotalPrice`.

---

## 8. Adversarial review notes (what the skeptics changed or confirmed)

Three independent adversarial passes each returned **partially-confirmed**. Net effect: the diagnosis direction (V16-area regression suspicion, systemic scope, expected value −3000 for this line) survived, but the **mechanism and the recommended fix were materially corrected**.

**Confirmed by all three (and re-verified here against the file):**
- Dual-Active V14 + V16; V16 highest-numbered → executes (block 80964–86874, closing `<versionNumber>` = 16). The synthesis's "+1 offset / internal versionNumber 15" reasoning is **wrong** (versionNumber tags sit at block end) but the conclusion is right.
- V14 seed `ListPrice → InputUnitPrice` (file 70181) vs V16 `NetUnitPrice → InputUnitPrice` (file 81350); identical gate; V16 has 0 ListPrice-seeds, V14 has 1; the V16 change was **deliberate** (partner/manual discount-base rework).
- Rank-4 (negative-qty gate starves the seed) **refuted** — `LineItemQuantity >= 0` is on `ListContainer11` (discount null-guard), not the seed.
- Expected value −3000.00 for the subject line is **correct** (original sale undiscounted; AAS-000543597 net = list = 3000).

**Mechanism-skeptic — changed the mechanism:** flagged that OrderItemDetail carries `NetUnitPrice = 3000` yet `TotalPrice = 0`, inconsistent with a pure "null propagates" story, and raised an unconditional **MAX clamp** as a competing cause. **Adjudication (verified here):** the clamp (`FormulaBasedPricing3`, seq 37, no parentStep) is real and unconditional, but it writes **only `TotalLineAmount` → `ItemSubtotal`**; `TotalPrice` is copied from `ItemNetTotalPrice` (Assignment108 section-1), so **the clamp is NOT the cause of `TotalPrice = 0`** (it is a separate latent `Subtotal` bug — Option D). The skeptic's claim that the clamp is gated to `ListContainer70`/LastTransaction was also corrected: the clamp is top-level/unconditional; `ListContainer62 QuantityPrice64` is the no-clamp `TotalPrice` path.

**Fix-safety-skeptic — corrected the field routing and overturned the recommended fix (the most consequential correction):** established that the line-total `TotalPrice` reads the **`NetUnitPrice` field**, populated only by the native waterfall (or COLA), while the V14/V16 seed writes the **`InputUnitPrice` field**, which routes only to `ItemSubtotal`. **Verified here:** there are two parallel subscription pipelines — `SubscriptionPricing` reads/writes the `NetUnitPrice` field → `ItemNetTotalPrice` → `TotalPrice`; `SubscriptionPricing80/86` read/write `InputUnitPrice` → `TotalLineAmount` → `ItemSubtotal` (identical in V14 and V16). Therefore **restoring the ListPrice→InputUnitPrice seed (Option C / the drafted V17) would not feed `TotalPrice`** — corroborated by the Inactive V17 having two `ListPrice→InputUnitPrice` seeds and **zero `NetUnitPrice`-field writes**, and remaining unshipped. The skeptic's narrower claim that "SubscriptionPricing reads the NetUnitPrice *field* not InputUnitPrice" is itself imprecise — `SubscriptionPricing86`'s `NetUnitPrice` *parameter* is bound to the `InputUnitPrice` *field* — but its load-bearing conclusion (the seed doesn't reach the field that `TotalPrice` reads) is correct. This drove the promotion of the **asset-net `NetUnitPrice`-field seed (Option A)** to recommended and the demotion of the ListPrice seed.

**Expected-value-skeptic — pinned the value to asset NET, not list:** 77% (1,539/1,999) of AssetActionSource rows have net ≠ list; 907 have ListPrice 0 with nonzero net; two of the six broken comparators have ListPrice 0. A list-based fix over-refunds discounted cancellations and under-refunds ListPrice-0 ones. **Adopted:** §4 now states the correct credit is `AssetActionSource.NetUnitPrice × qty`; the subject line's −3000 is correct only because its original sale was undiscounted. This reinforces Option A (asset net) over any list-price approach.

**Bottom line of the adversarial pass:** the original synthesis's **rank-1 ("V16 InputUnitPrice seed regression is THE root cause")** is **corrected/demoted** — it is a real, deliberate V16 change but is **not load-bearing for `TotalPrice`** because it writes the wrong field. The load-bearing root cause is the **null `NetUnitPrice` field on cancel lines (native waterfall produces no row) with no asset-net/list seeding of that field**, and the correct fix is the **asset-net `NetUnitPrice`-field seed (Option A)**, gated tightly and shipped after the dual-Active anomaly is resolved (Option B) and validated against the discounted/ListPrice-0 comparators.
