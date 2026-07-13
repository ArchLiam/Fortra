# Pricing defects to fix (logged from the Wave-0 golden-harness run, 2026-07-06)

Not filed as tickets — team will fix directly. Each has exact repro + root cause + fix + acceptance.

---

## DEF-1 · P1 · Partner-discount reprice is DIVERGENT (compounds toward $0)

**Severity:** high — a partner **Discount**-model quote loses its discount % again on **every** reprice.
Repeated repricing drives the line price toward $0. Live, pre-existing (no refactor involved).

**Repro (FortraUAT):**
- Quote `0Q0WC000003IKeT` (S5; Channel-Originated, `Partner_Pricing_Model = Discount`, 18%), line "beSECURE".
- Reprice repeatedly and snapshot `NetUnitPrice`:
  - 1st: `4442.35`  → 2nd: `3642.727`  → 3rd: `2987.04`  … each = ×0.82 (= ×(1 − 18%)).

**Root cause:** `PartnerNetPricePosthook.calculateDeferredPartnerPrice`
- `Data/pricing-refactor-scratch/live-classes/PartnerNetPricePosthook.cls:554`
  ```apex
  Decimal currentPrice = getDecimalFromTag(lineItem, 'NetUnitPrice');   // base = ALREADY-DISCOUNTED net
  ...
  result.adjustedPrice = PartnerPricingService.calculateDiscountPrice(currentPrice, discountPercent); // :574  ×(1−18%)
  ```
- The deferred path fires on reprice (`needsDeferredPartnerPricing`, :541 — the prehook didn't re-stamp `PartnerUnitPrice`),
  and discounts off the **live `NetUnitPrice`**, which already holds the previous reprice's discount → compounding.
- The idempotency guard at `:600` (`adjustedPrice == currentPrice → null`) can't catch it (`currentPrice × 0.82 ≠ currentPrice`).
- The **correct** base pattern already exists in the same class at `:2273–2285`: `Base_Price__c` → `Pre_Partner_Price__c`.

**Fix:** resolve the discount base as `Base_Price__c` → `Pre_Partner_Price__c` → `NetUnitPrice` (fallback), so the
discount always applies to the **stable pre-partner base**. Same for the Guaranteed-Margin branch (:591) which shares
`currentPrice`. (Secondary: investigate why `PartnerUnitPrice` isn't re-stamped on reprice, forcing the deferred path.)

**STATUS: FIXED — deployed to UAT 2026-07-07 (Deploy 0AfWC00000GiXlR0AV), class only.**
Change: `:554` now bases the discount off `Pre_Partner_Price__c` (stable) with `NetUnitPrice` fallback. Verified via managed
reprice (Flow Invocable REST `Fortra_Quote_Reprice`):
- S5 (`0Q0WC000003IKeT`): compounding STOPPED — stable across 3 reprices (was ×0.82 each before). ✅
- No collateral regression: S3/S6 `0 delta` vs baseline; S7 `0 delta` vs its settled value (its 1-delta is DEF-2, not this fix). ✅
- Mechanism confirmed: `resolveCommercialUnitPrice` (`:481`) = lower(procedureNet, partnerNet). With the fix, partnerNet is a
  stable `Pre_Partner × (1−disc)` instead of the drifting net.

**Acceptance met:** reprice-idempotency achieved. `PricingCharacterizationTest` already pins the unit-level margin math.

---

## DEF-1b · P1 · DATA REMEDIATION — partner-Discount lines already under-priced by the old bug
The compounding ran in prod-like data before the fix. Existing lines are stuck at over-discounted floors (the lower-rule at
`:481` locks the low net; the fix stops *future* compounding but cannot heal *past* pollution — a reprice keeps the low floor).

**Scope (UAT, partner Discount, last 180d, 2026-07-07):** 90 lines → **39 over-discounted across 24 quotes** (upper estimate;
some may carry legit extra discounts). Ratios 0.91 → **0.0** (e.g. `0Q0WC000003A8qb` net $0.39 vs correct $2562.50; S5 $2987 vs $4442; S7 line2 $62 vs $312).

**Remediation options (owner decision):**
1. For affected lines, reset `NetUnitPrice` to the derived/list base (so a post-fix reprice settles at the correct `Pre_Partner × (1−disc)`), then reprice. Requires the managed reset (net is engine-controlled).
2. Re-create/re-add the affected lines (fresh lines price correctly on 1st reprice under the fix).

**Scope: UAT only** (prod explicitly out of scope per owner). These are UAT test quotes — pre-existing test-data damage,
does NOT block the refactor. Cleanup is optional (nice-to-have to make the golden-harness anchors reflect correct values).

**Related (INV-5, D-11):** the deferred path calls the **V1** `PartnerPricingService.getMarginForProductType` (2-arg, `:569`)
while the prehook uses V2 — the partner-service split. Folds into the Wave-3 service unification.

---

## DEF-2 · P3 · Sales Price (`UnitPrice`) stale on 1st reprice — converges at 2nd (DISPLAY-only, low impact)
Investigated 2026-07-07 via managed reprice.
- Mechanism: before-save flow **`Stamp_Sales_Price`** (RecordBeforeSave, QuoteLineItem) sets
  `UnitPrice = IF(ISBLANK(Base_Price__c), Pre_Partner_Price__c, Base_Price__c)`. Settled value = Base_Price = correct
  (S7 line1 UnitPrice 355, Net 312.4 = 355×0.88 correct).
- Non-idempotency (`71 → 355`): the flow's `UnitPrice` write doesn't stick on the 1st reprice — either `Base_Price__c` isn't
  final at the before-save moment, or a later `UnitPrice` writer (pricing hooks / posthook context writes) clobbers it; the 2nd
  reprice re-stamps from the settled `Base_Price__c`. This is the **multi-writer `UnitPrice` ordering** issue (Marc DeBrey Sales-Price thread).
- **Impact: LOW** — display field only; **converges to the correct value**; net/NetTotal/ARR/Workday unaffected. Not a divergence.
- **Fix is NOT a one-liner** — needs `Stamp_Sales_Price` ordered reliably last (or the transient pricing `UnitPrice` write stopped).
  Pinpointing the exact clobbering writer needs a controlled reproduction (perturb the line → reprice once → capture the transient),
  which settled S7 can't show as-is. Deferred as a Marc-thread item unless prioritized.

## DEF-3 · CLOSED — NOT A BUG (attr-tier is idempotent; S11 was mislabeled)
Investigated 2026-07-07 via managed reprice.
- **S11 (`0Q0WC000003FcrF`) is NOT an attribute-tier scenario** — both lines have `Has_Attribute_Adjustment__c=false`,
  so `AttributeVolumePricingPrehook` skips them. It is a **EUR multi-currency** line: `NetUnitPrice 1471.995 = Base_Price 1575 (USD) × 0.9346`
  (hardcoded USD→EUR FX), EUR `ListPrice 2943.99` ignored. It **converges** (stable across r0–r3) — the earlier drift was slow currency settling, not divergence.
- **Real attr-tier quote** (`0Q0WC000003GMu5`, `Has_Attribute_Adjustment=true` lines) is **idempotent** — stable across r0–r3.
  Consistent with SC-3390 already fixed (IsPriceImpacting on the tiered PADs). *(Steady-state tested; the edit→reprice trigger not re-exercised, but SC-3390's fix is documented.)*
- **Residual (not a quick fix):** S11's `USD-base × hardcoded 0.9346 FX` is the **SC-3384 / INV-24 multi-currency cluster** — a known
  larger architectural concern (currency-blind lookups over USD data; config-as-code FX). It converges, so it is not acute. Out of quick-fix scope.
- **Action:** re-bind S11 in the harness to a real attr-tier quote (or relabel S11 as a currency scenario). No code fix for DEF-3.

## DEF-4 · E-04 partner margin 0% on null Non_Orig — RESOLVED (Wave 3b-i, owner decision = catalog)
Fixed 2026-07-07. `PartnerPricingServiceV2.getMarginForProductType` now falls back to the standard "catalog"
percent when a Fortra-Originated deal's `Non_Orig_*` is null (via `effectivePct`, short-circuited so the deal-blind
path never touches Non_Orig). Deployed; 40 tests; live-proven (null Non_Orig + std 20 → 20, was 0); existing
Fortra-Originated deals 0-delta (their Non_Orig is populated so the fallback doesn't fire). `PricingCharacterizationTest`
updated to pin the new behavior.

## D-11-residual · Partner deal-blind POSTHOOK (3b-ii) — LOGGED, deferred (owner accepted stop 2026-07-07)
After Wave 3a (single margin impl) + 3b-i (E-04 catalog fix), the ONLY remaining partner inconsistency is a data-path
difference, not code duplication: `PartnerNetPricePosthook` prices Fortra-Originated *derived-maintenance* lines
**deal-blind** (calls V1 2-arg → V2 with dealType=null → standard %), while the prehook is deal-aware. Making the
posthook deal-aware ("3b-ii") requires: (1) load `Deal_Type__c` in the posthook, (2) thread it through
`calculateDeferredPartnerPrice`, (3) call `V2.getMarginForProductType(model, type, dealType)`, (4) add `Non_Orig_*`
to `PartnerPricingService.getPricingModels` SOQL. Highest-risk change (2563-line posthook + shared SOQL, behavioral for
Fortra-Originated); narrow footprint. **Recommendation: decompose the posthook (Wave-2 style) first, then revisit.**

_(S3 SC-3346 qty0→$0 is tracked in KNOWN_FAILING.md as a frozen baseline, not a to-fix here.)_
