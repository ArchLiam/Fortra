# SC-3345 — V9 Fix Plan (Wren's bug)

> Build V9 on top of active **V8**. Design + adversarially verified (workflow `wf_6c0a29a4-4ba`, 4 scenarios).
> Source of truth: `Data/sc3345/verify_v8b/V8.xml`.

## TL;DR
- **2 fixes are unambiguously safe → ship now** (Services phantom, discount-amount sign).
- **The headline −11,271% Discount % + ALE = $46 are HELD** — the naive fix regresses real discounts; the correct fix needs one business decision + an empirical check.

---

## SHIP NOW (safe, no sign-off, zero regression to real discounts)

### Fix 1 — Phantom $500 Services (stale category totals)
- **Cause:** `ServicesAggregatePrice`/`SoftwareAggregatePrice`/`SubscriptionAggregatePrice` are gated `SUM(ItemNetTotalPrice)`. Empty group → step never fires → with "Initialize resources" OFF + no reset, the prior run's $500 persists.
- **Edit:** add **three unconditional `AssignmentElement` reset steps** writing `0` to `Total_Services__c` / `Total_Software__c` / `Total_Subscription__c`, sequenced **before** `ListContainer8` / `Copy1ofListContainer8` / `Copy1ofCopy1ofListContainer8`. The gated SUM overwrites with the real total when the group is non-empty.
- **Why not the global "Initialize resources" toggle:** its blast radius (zero-inits *every* output var, every quote) isn't auditable from the metadata. Scoped resets are file-verifiable and equivalent for these fields.

### Fix 2 — Negative `Total_Discount_Amount__c` (−$5,185)
- **Cause:** `TotalDiscountAmount` = `LineDiscountBuffer__c * NegativeNumber(−1)`, where `LineDiscountBuffer__c = SUM(ItemTotalAdjustmentAmount) = +$5,185` (a markup). ×−1 → −$5,185.
- **Edit:** change the `TotalDiscountAmount` formula from
  `LineDiscountBuffer__c * NegativeNumber` → **`MIN ( LineDiscountBuffer__c , 0 ) * NegativeNumber`**
  (or `IF ( LineDiscountBuffer__c < 0 , LineDiscountBuffer__c , 0 ) * NegativeNumber` if MIN unsupported).
- **Verified:** markup → 0; **real discount (negative buffer) → unchanged, byte-identical to V8**; no-adjustment → 0.

---

## HELD — needs business decision + empirical check (the headline symptom)

### Fix 3 — −11,271.739% Discount % and ALE = $46
- **Critical finding:** the −11,271% is **platform-derived**, NOT written by the procedure. The procedure's `DiscountPercent` step is **dead** — it divides by `ListPriceBuffer__c`, which is a **dangling reference** (never written), so the IF guard is always false and it writes `Discount__std = 0`. The visible number is the RLM platform's own `(1 − TotalPrice/Subtotal) = 1 − 5231/46`, exploding because **Subtotal = list base ($46)** ≪ **TotalPrice = net ($5,231)**.
- **Regression trap (FORBIDDEN):** repointing Subtotal to `SUM(ItemNetTotalPrice)` makes Subtotal == TotalPrice on *every* quote → **hides genuine discounts** on net<list quotes.
- **Only no-regression variant:** add a per-line `EffectiveListAmount = MAX(TotalLineAmount, ItemNetTotalPrice)` and base Subtotal on it.
  - markup line (net>list): effective list = net → Subtotal lifts to net → **Discount % = 0**, and **ALE (= Subtotal) self-corrects to net** ✓
  - discounted line (net<list): MAX keeps the higher list → **real discount preserved** ✓
  - net==list: unchanged ✓
- **Pre-reqs before this can ship:**
  1. **Business decision:** a markup (net>list) should display **0% discount** (Subtotal lifted to net) — confirm this is the intent.
  2. **Empirical check:** confirm on a test reprice that raising the procedure's Subtotal actually suppresses the platform % (evidence supports it: repriced maintenance quotes show Subtotal==Total → Discount=0).
  3. **Preserve filters:** `AggregatePrice` (Subtotal) carries 3 `DerivedPricingAttribute` where-conditions; the MAX rewrite **must keep them**.

### Fix 4 — ALE formula
- `ALE__c` / `Annualized_License_Equivalent_Base__c` are formula fields **= Subtotal**; no procedure change. They **auto-correct** once Fix 3 lifts Subtotal. (Latent gap: ALE has **no term annualization** — flag separately.)

---

## Adversarial regression verdict (4 scenarios)
| Scenario | Fixes 1+2 (ship) | + Fix 3 (MAX) |
|---|---|---|
| SC-3345 markup | Services 0 ✅, DiscAmt 0 ✅; %/ALE still wrong ⚠️ (needs Fix 3) | fully fixed |
| **real-discount (net<list)** | **PASS** ✅ (discount preserved) | **PASS** ✅ |
| normal (net==list) | **PASS** ✅ | **PASS** ✅ |
| mixed Services/Software/Subscription | reset safe ✅; *pre-existing*: category totals don't reconcile to GrandTotal (derived lines) | separate decision |

## Build path
UI **Save As V8 → V9** (not metadata deploy). Add the 3 reset steps; edit the `TotalDiscountAmount` formula; (if approved) add `EffectiveListAmount` MAX + repoint Subtotal preserving the 3 conditions. Save. **Activate = live pricing change → explicit go-ahead + regression reprice (markup, real-discount, normal) required.**
