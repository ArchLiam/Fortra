# QuoteLineItem Trigger Merge — Handoff / Cross-Tab Coordination (2026-07-10)

**Author:** Liam Jeong · **Context:** SC-3346 work stream (pricing engine)
**Purpose:** Another tab/session is also working SC-3346. This documents exactly what I changed on the
**QuoteLineItem trigger surface**, why, and how to avoid conflicts.

---

## TL;DR
- **What:** Merged the **two** Apex triggers on `QuoteLineItem` into **one** compliant trigger (apex-compliance §2.1: "exactly one trigger per object").
- **Status:** ✅ **Deployed + smoke-verified in FortraUAT** (deploy `0AfWC00000GoIF30AN`), and **committed to `uat`**.
- **Behavior:** **Preserved exactly** — this is a structural/compliance refactor, not a functional change. Validated by 79 tests + a real-data smoke run.
- **⚠️ For the other tab:** Do **NOT** add a second trigger to `QuoteLineItem` and do **NOT** reactivate `QuoteLineItemExchangeRateTrigger`. Add any new QLI event logic to `QuoteLineItemTriggerHandler` (details below).

---

## Why
`QuoteLineItem` had **two** active triggers, which apex-compliance §2.1 prohibits (non-deterministic order):
- `QuoteLineItemTrigger` (maintenance/COLA/hardware/currency hub) — older.
- `QuoteLineItemExchangeRateTrigger` — added 2026-07-01 during the multicurrency push as a *second* trigger (the "just add another trigger" shortcut), with **all its logic inline** in the trigger body (§2.2 violation) and **no test class**.

## What changed (exact file list — avoid editing these in the other tab, or rebase onto this commit)

| File | Change |
|---|---|
| `triggers/QuoteLineItemTrigger.trigger` | **Rewritten** → logic-less `switch on Trigger.operationType` router only |
| `classes/QuoteLineItemTriggerHandler.cls` | **Rewritten** → per-event methods (`beforeInsert/beforeUpdate/afterInsert/afterUpdate`), recursion guard, §9 telemetry; header fixed |
| `classes/QuoteLineItemExchangeRateService.cls` | **NEW** → FX logic extracted verbatim from the old trigger (`without sharing`) |
| `classes/QuoteLineItemExchangeRateServiceTest.cls` | **NEW** |
| `classes/QuoteLineItemTriggerException.cls` | **NEW** → typed §9 exception (`extends AppException`) |
| `classes/QuoteLineItemTriggerHandlerTest.cls` | **Modified** → compliant header + failure-path test |
| `triggers/QuoteLineItemExchangeRateTrigger.trigger-meta.xml` | `Active` → **`Inactive`** (repo-sync; already deactivated in org) |

(+ the three new `*.cls-meta.xml`.) The `QuoteLineItemExchangeRateTrigger.trigger` body is **left in place** (deactivated, reversible) — do not delete.

## New execution model (READ THIS before touching QLI automation)

`QuoteLineItemTrigger` now does nothing but route:
```apex
switch on Trigger.operationType {
    when BEFORE_INSERT { handler.beforeInsert(Trigger.new); }
    when BEFORE_UPDATE { handler.beforeUpdate(Trigger.new, Trigger.oldMap); }
    when AFTER_INSERT  { handler.afterInsert(Trigger.newMap); }
    when AFTER_UPDATE  { handler.afterUpdate(Trigger.newMap, Trigger.oldMap); }
}
```

Ordered pipeline inside `QuoteLineItemTriggerHandler` (unchanged behavior):

| Event | Ordered calls |
|---|---|
| **beforeInsert** | `QuoteLineItemCurrencyCorrectionHandler.correctPricebookEntryCurrency` → `QuoteLineItemExchangeRateService.stampRatesOnLines` → hardware link → `RenewalQuoteActionStamp.synthesizeRenewQuoteActions` → `COLAUpliftHandler.handleBeforeInsert` |
| **beforeUpdate** | `stampRatesOnLines` → hardware link → `COLAUpliftHandler.handleBeforeUpdate` |
| **afterInsert** | `QuoteLineItemExchangeRateService.propagateRatesToOpportunities` → `RenewalMaintenanceAutoAddHandler.enqueueIfNeeded` → `RenewalAssetQuantityHandler.enqueueQuantityNormalization` |
| **afterUpdate** | `propagateRatesToOpportunities` only |

**Load-bearing orderings preserved:** currency-correction before native validation; `RenewalQuoteActionStamp` before COLA (born-net). `enqueueIfNeeded` runs on **insert only** (a naive union would have woken a dead `||isUpdate` branch on after-update — deliberately avoided).

## How to extend QLI automation now (so we don't re-introduce a 2nd trigger)
- **Add before/after logic** → add a call inside the matching `QuoteLineItemTriggerHandler` event method, delegating to a `*Service`/handler. Do **not** create a new trigger.
- The sub-handlers it calls (`COLAUpliftHandler`, `RenewalMaintenanceAutoAddHandler`, `RenewalAssetQuantityHandler`, `QuoteLineItemCurrencyCorrectionHandler`, `RenewalQuoteActionStamp`) are called with **unchanged public signatures** — you may edit their internals freely; if you change a signature, update the handler call site.
- The FX rate lives in `QuoteLineItemExchangeRateService` — do not re-add FX logic to the trigger.

## Interaction with the other tab's SC-3346 work
- **Fix #2b (per-product `Maintenance Type Defn` default):** if implemented as an **after-save flow** (e.g. extending `Quote_Line_Item_On_Create`, which creates QLIAs), that is a **flow** on QLI, separate from this Apex trigger → low conflict. Just be aware the Apex trigger fires FX/hardware/currency/COLA on the same insert (they don't touch the tier attribute).
- **`NewMaintenanceDedupeService` / dedupe:** independent of this merge.
- **Pricing procedure (V24) / posthooks (`PartnerNetPricePosthook`) / canvas:** untouched here.
- **Merge/rebase note:** if the other tab has local edits to `QuoteLineItemTrigger.trigger` or `QuoteLineItemTriggerHandler.cls`, they **will conflict** — rebase onto commit `<this commit>` and re-apply into the new per-event structure.

## Verification evidence
- **Validate (check-only):** 79 tests, 0 failures. Coverage: Trigger 100%, Handler 89%, Service 97%.
- **Smoke (real UAT catalog data, savepoint→rollback, zero residue):** FX-stamp USD (bulk 20) ✅, hardware link grouped/ungrouped ✅, before-update re-link ✅, FX propagation to synced Opp ✅, FX-stamp EUR = 0.92 (matches lookup) ✅.
- **Org state:** `QuoteLineItemTrigger` **Active**, `QuoteLineItemExchangeRateTrigger` **Inactive**.

## Notes discovered along the way (useful for anyone on SC-3346 / pricing)
- `QuoteLineItem.CurrencyIsoCode` is **not writeable** and is **not populated at before-insert** for raw Apex inserts (only reconciled post-insert). FX rate stamps default (USD 1.0) at before-insert and refreshes on the first before-update. Real RLM insert path populates currency correctly (57,291 EUR lines carry 0.92).
- `Opportunity.Exchange_Rate_To_USD__c` is **independently stamped by `OpportunityTriggerHandler`** on insert/update (not only by QLI propagation) — the rate exists at 5 grains (QLI · Quote · Order · OrderItem · Opportunity), feeding downstream (Workday/BI).
