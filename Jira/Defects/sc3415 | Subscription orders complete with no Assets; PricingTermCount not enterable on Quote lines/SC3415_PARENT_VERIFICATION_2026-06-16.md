# SC-3415 (parent) — comprehensive verification, 2026-06-16

**Question:** is the parent SC-3415 *completely* fixed and resolved, now that both children are done — **SC-3419** (Defect A: no Assets / async silent swallow) and **SC-3420** (Defect B: "End Date and PricingTermCount required" / PTC not enterable)?

**Verdict: ✅ YES — all four acceptance criteria verified live in FortraUAT today.** One transparency caveat on the *mechanism* of the PTC fix (§ Caveat).

---

## Acceptance criteria — live results

| # | Acceptance criterion | Verdict | Evidence (2026-06-16, live) |
|---|---|---|---|
| **AC1** | A TermDefined order **completes/activates without** the "End Date and PricingTermCount required" error **and without the rep typing PricingTermCount** | ✅ **MET** | Built a normal TermDefined order (**00095543**) with PTC **left null** on all 3 lines → the active `Fortra_OrderItem_Set_Dates` (RecordBeforeSave) backstop **auto-filled PTC=1** on every line (incl. the future-dated one) → order **Activated with no error**. |
| **AC2** | Activation generates Assets for **every** subscription line on a normally-built order (Quantity, not duplicate lines), **including future-dated lines** | ✅ **MET** | 00095543 → **3 Assets** (CLSAAS qty 2, SEAW qty 2, **future-dated SEAW qty 1, LifecycleStart 2026-08-15**), all `Installed`. Corroborated by SC-3419: order 00095537 (32 lines → 32 Assets) and the 8-order 1:1 sweep incl. future-dated `BESECB`. |
| **AC3** | A failed async asset run is **surfaced** on the Order (`Order_Integration_Error_Messages__c = "Assetization failed: …"`) instead of a silent asset-less "Order Complete" | ✅ **MET** | `Fortra_Assetize_Order` **V14** live (SC-3419). 00095543 error field = `null` (clean success). Surfacing/clear/no-clobber runtime-proven in SC-3419's `RUNTIME_TEST_RESULTS.md`. |
| **AC4** | In-UI help text on PricingTermCount / SubscriptionTerm directs reps to set **Subscription Term** | ✅ **MET** | `QuoteLineItem.PricingTermCount` inlineHelpText: *"System-derived from the subscription term — you can't type this… The order still activates if this is blank."* `SubscriptionTerm`: *"Sets the contract length… edit Subscription Term, not Pricing Term Count."* |

## The decisive E2E (order 00095543, fresh account `001WC00000ktREtYAM`)

Built the **normal rep path** — TermDefined products, Quantity (not duplicate lines), a **future-dated** line, and **PricingTermCount deliberately left null** (the rep can't type it):

```
SC3415V_AFTERINSERT SEAW   svc=2026-06-16 end=2027-06-15 PTC=1.00 subterm=1   ← backstop filled PTC
SC3415V_AFTERINSERT CLSAAS svc=2026-06-16 end=2027-06-15 PTC=1.00 subterm=1   ← backstop filled PTC
SC3415V_AFTERINSERT SEAW   svc=2026-08-15 end=2027-08-14 PTC=1.00 subterm=1   ← future-dated, backstop filled PTC
SC3415V_ACTIVATED ok - no required-field error
→ 3 Assets (Installed), incl. the future-dated SEAW (LifecycleStart 2026-08-15); error field null
```

One run exercises **AC1 (activate w/o error, w/o typing PTC) + AC2 (assets for every line incl. future-dated) + AC3 (no silent failure)**.

## How the two defects were resolved

- **Defect A (SC-3419):** asset generation ran in an async flow whose fault was silently swallowed; underlying throw = an optimistic-lock collision when duplicate same-product *maintenance* lines contend on a pre-existing matching Asset. **Fix = `Fortra_Assetize_Order` V14** surfaces the fault on the Order (never silent); normal/Quantity builds assetize cleanly (proven: 32 assets on a clean account, 3 assets here incl. future-dated).
- **Defect B (SC-3420):** `QuoteLineItem.PricingTermCount` is **platform read-only / system-derived** — not a bug to "make enterable." Resolved by (1) **help text** pointing reps to `SubscriptionTerm`, and (2) the **order-tier backstop** `Fortra_OrderItem_Set_Dates` deriving PTC so the order activates without the native "required" error and without the rep typing it.

## ⚠️ Caveat (transparency)

Quote-tier **auto-derivation of PricingTermCount was NOT restored** — new TermDefined *quote* lines today still show `PricingTermCount = null` (06-16 sample: 26 null vs 1 populated; the V12→V13 procedure regression persists). This is **handled by design**, not by restoring derivation: the field is genuinely read-only/system-derived, the help text says blank is fine, and the order-tier backstop fills it before activation. **So the only residual is cosmetic** — if anyone expects the *quote line* to display a populated PTC, it won't. It does not block activation, assetization, or German's renewal/COLA testing. (If a populated quote-tier PTC is ever required, that's the owner-gated pricing-procedure re-publish + context re-sync noted in the SC-3415 README §3 — a separate, optional enhancement.)

## Bottom line

**SC-3415 meets all four acceptance criteria and its stated goal — German Wren can now build a normal subscription order, activate it without the "required" error and without typing PricingTermCount, and get Assets for every line (including future-dated) to run renewal/COLA E2E.** Both children (SC-3419, SC-3420) are resolved; the parent can be closed (with the cosmetic quote-tier-PTC caveat noted).

## Test residuals (inert, marked)
Verification order **00095543** + account `001WC00000ktREtYAM` (+ 3 assets) — RLM-immutable, leave or remove via Setup UI. 00095470 (original) untouched. Other SC-3419 test records: 00095536, 00095537, the two AC4 throwaways.
