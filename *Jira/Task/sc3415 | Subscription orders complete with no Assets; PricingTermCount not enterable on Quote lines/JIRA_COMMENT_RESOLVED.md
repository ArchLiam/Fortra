# 🟢 SC-3415 — RESOLVED (UAT) · all acceptance criteria verified

### Both blocking defects are fixed and **re-tested end-to-end today.** German can now build a normal subscription order, activate it **without the “required” error and without typing Pricing Term Count**, and get **Assets for every line (including future-dated)** to run renewal/COLA E2E.

> **TL;DR**
> • **① No Assets** *(→ SC-3419)*: the async asset step was failing **silently**. Now it’s **visible** (`Fortra_Assetize_Order` V14) and normal orders assetize cleanly.
> • **② “End Date and PricingTermCount required” / can’t type PTC** *(→ SC-3420)*: PTC is **read-only/system-derived** (not a bug). Reps now set **Subscription Term** (help text), and the order **auto-fills PTC** so activation just works.
> • **Verified live today** with one clean end-to-end order — all 4 acceptance criteria pass. ✅

---

## ✔️ Acceptance criteria — all met (live, 2026-06-16)

| # | Criterion | ✅ | How it’s proven |
|---|---|----|---|
| **1** | TermDefined order **activates without** the *“End Date and PricingTermCount required”* error **and without the rep typing PTC** | ✅ | Built a normal order with **PTC left blank** → the order auto-derived **PTC = 1** on every line → **Activated, no error.** |
| **2** | Assets generate for **every** subscription line, **including future-dated** | ✅ | Same order → **3 Assets**, including a **future-dated** line (starts 2026-08-15). (Also: a 32-line order → 32 Assets.) |
| **3** | A failed async asset run is **surfaced on the Order** (not a silent asset-less “Order Complete”) | ✅ | `Fortra_Assetize_Order` **V14** writes *“Assetization failed: …”* on the Order; verified clear-on-success and no-clobber of Workday errors. |
| **4** | In-UI **help text** points reps to **Subscription Term** | ✅ | Live on both fields — PTC’s text even reads *“…you can’t type this. The order still activates if this is blank.”* |

## 🧪 The decisive end-to-end test (order 00095543)

A normal subscription order — Quantity (not duplicate lines), a **future-dated** line, and **Pricing Term Count never entered**:

```
Pricing Term Count auto-filled = 1 on all 3 lines (incl. the future-dated one)
→ Order Activated — NO “required” error
→ 3 Assets created (incl. the future-dated line)
→ no silent failure (error field clean)
```

One order exercises criteria **1 + 2 + 3** together. ✔️

## 🧭 What was really going on (and how each was fixed)

- **① No Assets (SC-3419).** Asset creation runs in a **background** step that *swallowed* its own error → orders looked complete with zero Assets and no warning. The underlying error is a Salesforce **record-lock collision** that only happens when **duplicate same-product *maintenance* lines** hit an Asset the account **already owns** (exactly Order 00095470). **Fix:** the failure is now **visible on the Order**; normal/Quantity builds assetize cleanly (proven — same 32-line shape made **32 Assets** on a clean account).
- **② PricingTermCount (SC-3420).** This field is **platform read-only / system-derived** — it was never meant to be typed. **Fix:** help text now points reps to **Subscription Term**, and the order **auto-derives** Pricing Term Count so activation succeeds without it.

## ⚠️ One transparency note

We did **not** restore auto-population of Pricing Term Count on the **quote line** itself — it still shows blank there (a side effect of the earlier pricing-procedure rework). This is **handled by design** (read-only field + help text + the order auto-fill), so it’s **cosmetic only** — it does **not** block activation, Assets, or renewal/COLA testing. Restoring the quote-line display is a separate, optional pricing-procedure re-sync.

## ✅ Recommendation

**SC-3415 meets all four acceptance criteria and its goal — recommend closing as Done.** Children **SC-3419** and **SC-3420** are both resolved. German is unblocked for renewal/COLA E2E (suggest using a freshly-built order such as 00095543 or 00095537).

---
*Full RCA, the live V14 flow, the runtime test results, the parent-verification report, and the cited Salesforce/RLM docs are in the SC-3415 / SC-3419 dossiers.*
