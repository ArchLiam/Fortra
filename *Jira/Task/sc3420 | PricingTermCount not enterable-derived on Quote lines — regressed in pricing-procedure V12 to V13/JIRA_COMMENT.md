# SC-3420 — ROOT CAUSE FOUND ✅ · FIX BUILT & VALIDATED (10/10 E2E) ✅ · READY TO SHIP (Marc coordination)

**TL;DR:** PricingTermCount stopped deriving because the pricing procedure's **TermDefined "Proration" step — the one that writes `PricingTermCount` — was deleted in the V11→V12 rework** and is still missing from live V14. I rebuilt it (guarded), validated it against **10 real records with zero regressions**, and reverted. The org is untouched; the fix is ready for a coordinated deploy with the procedure owner.

---

## 🔬 Root cause (proven)

- `Rev_Mgmt_Default_Pricing_Procedure` derives `PricingTermCount` per selling-model with three writer steps. The **TermDefined** writer is a *Proration* element that maps **Proration Multiplier → `PricingTermCount`** (Salesforce's documented design). For a 1-yr annual line that multiplier = 1 → `PTC = 1`.
- That single step was **dropped during the V11→V12 "Maintenance Derived / COLA" rebuild** and is absent from V12, V13, and the live-active **V14**. The OneTime and Evergreen writers survived — which is exactly why **only TermDefined lines** lost PTC.
- `QuoteLineItem.PricingTermCount` is **platform read-only** (createable/updateable = false). Only the RLM engine can write it → **no flow/Apex workaround exists at the quote tier.**

**Hard evidence:** all 718 PTC-populated TermDefined lines were created **≤ 2026‑06‑11 19:16:34** (the rework instant); **zero since.** Meanwhile OneTime lines still persist `PTC=0`, proving the write-back plumbing itself is fine — only the TermDefined step is missing.

> Correction to the title's framing: the breaking change is the **V11→V12** content delta (the active pointer flipped ~17:00Z on 2026‑06‑11), consistent with the "V12→V13" window. It is **not** a context‑definition de‑sync — the context still maps `PricingTermCount` both ways.

---

## 🔗 Why this matters

This null `PricingTermCount` is the **upstream origin** of the whole chain:
- **SC‑3406** — Quote→Order convert fails ("PricingTermCount required for Termed order products")
- **SC‑3411** — Order can't activate (termed line missing PricingTermCount)

Both are currently *masked in UAT* by the order‑tier backstop (`Fortra_OrderItem_Set_Dates`), but **Prod has no backstop and no fix → fully exposed.** SC‑3420 is the durable cure.

---

## 🛠️ The fix

Re-add the TermDefined Proration writer to the active procedure, **guarded** so it only runs on lines it can price:

> **Filter:** `SellingModelType = 'TermDefined' AND StartProrationPeriod IsNotNull AND ItemSubscriptionTerm IsNotNull`
> **Step:** `ProrationTermDefined` → `Proration Multiplier → PricingTermCount`

The guard is essential: an **un‑guarded** writer threw `INVALID_PERIOD_BOUNDARY` on the **124,912** TermDefined lines that have a null PeriodBoundary, failing their reprice/convert. The guard makes those lines skip cleanly instead. (`PeriodBoundary` itself isn't a valid ExpressionSet resource; `StartProrationPeriod` / `ItemSubscriptionTerm` are.)

**Required line config for PTC to derive:** PeriodBoundary set · SubscriptionTerm + Unit · EndDate. (ServiceDate is *not* required — 710/718 historical PTC lines had it null.)

---

## ✅ E2E validation — 10/10 records, 2 rounds, no regressions

| Scenario | Records | Result |
|---|---|---|
| **Fully-configured** (PeriodBoundary + term set) | 5 incl. three **$77,080** lines | **`PricingTermCount` null → 1**, prices preserved |
| **No PeriodBoundary** (the 124K-line cohort) | 3 incl. $766 / $246 | **Reprice succeeds, no error**, PTC null, prices preserved |
| **Term missing** (PeriodBoundary set, term null) | 2 | **Skips cleanly** — no error, no fractional value |

Every record's net price was preserved; well-configured lines derived a clean integer `PTC=1`. Full table in the attached E2E report.

---

## 📦 Status & next step

- **Org is clean** — all testing was read-only or reverted; live V14 = the owner's current version, verified.
- **Ship-ready build** prepared (guarded + term‑guard writer).
- **Decision needed (with Marc, procedure owner):**
  1. Deploy the guarded writer to V14 (note: the procedure is co-owned and edited frequently — rebuild on the current live copy at deploy time).
  2. Decide whether to **backfill `PeriodBoundary` / `SubscriptionTerm`** on the ~124K lines that lack them, so those also derive PTC (otherwise they continue to skip).

**Acceptance criteria status:** AC "newly-priced TermDefined line derives `PricingTermCount=1` on reprice" — **met in validation**; pending production deploy + the backfill decision. Help-text AC already delivered under SC‑3415.
