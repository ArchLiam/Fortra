# Root Cause Analysis — Order Status-Change / Activation Failure

**Order:** 00095503 (`801WC00000knHDLYA2`)
**Environment:** FortraUAT (`https://fortra--uat.sandbox.my.salesforce.com`, Org `00DWC000006eUFF2A2`)
**Prepared for:** Joe
**Date:** 2026-06-15
**Status of findings:** All facts below were independently re-verified live against FortraUAT via the Salesforce CLI on 2026-06-15. CONFIRMED items are observed facts; HYPOTHESIS items are clearly labelled.

---

## 1. Executive summary

Order 00095503 cannot be moved to **Activated**. The one termed (subscription) line on the order is missing two platform-required fields — **EndDate** and **PricingTermCount** — and Salesforce's Revenue Lifecycle Management (RLM) engine refuses to activate any order whose termed products are not fully dated. **Root cause (one line): the order's termed line `802WC00000OpopoYAB` (ES-CEP-RSL-ACTIDB, "Term Based - Annual") has null EndDate and null PricingTermCount because those fields were never derived during pricing — the null was carried in from the source quote line and the order has never had a successful (complete) price/reprice pass.** A separate flow defect (a missing error handler in the "Update Status" quick action) hides the real platform message behind a generic "unhandled fault," which is why the failure looks mysterious rather than actionable.

---

## 2. What the user sees — two symptoms, two different error messages

There are **two distinct UI paths** to change an Order's status, and they fail differently because they run different code.

| # | Path used | What the user sees | Why |
|---|-----------|--------------------|-----|
| **Symptom 1** | **"Update Status" quick action** on the Order (button → screen flow), pick **Activated** | Generic: *"An unhandled fault has occurred in this flow … Please contact your system administrator."* | The flow element that writes the new status has **no error handler**, so the underlying platform error is swallowed and replaced with a generic message. (CONFIRMED — see §4.) |
| **Symptom 2** | **Order details page → inline-edit Status → Activated → Save** | Real platform error: *"802WC00000OpopoYAB: EndDate is required for Termed order products."* and *"802WC00000OpopoYAB: PricingTermCount is required for Termed order products."* | The inline-edit path hits the platform DML directly, so the native RLM validation message is shown verbatim. |

**Why they differ:** Both paths attempt the same underlying database write (set `Status = Activated`). The details-page Save surfaces the platform's own error text. The quick-action flow routes the write through a flow element that lacks a fault connector, so any error there is reported as the generic "unhandled fault" screen instead of the real message. **The two symptoms are the same failure seen through two different error-reporting layers.**

---

## 3. Root cause — proximate

### 3.1 The blocking condition (CONFIRMED)

Salesforce RLM enforces that **every termed (subscription) order line must have an EndDate and a PricingTermCount before the order can be activated.** Order 00095503 has exactly one termed line, and it is missing both.

**Order-item evidence table** (live query, 2026-06-15):

| OrderItem | Product | Selling-model type | Qty | ServiceDate | EndDate | PricingTermCount | UnitPrice | Blocks activation? |
|-----------|---------|-------------------|-----|-------------|---------|------------------|-----------|--------------------|
| **`802WC00000OpopoYAB`** | ES-CEP-RSL-ACTIDB — Active Defense BEC Threat Intelligence Service | **TermDefined** (Term Based - Annual, `0jPWC000000060b2AA`; PricingTermUnit=Annual, PricingTerm=1) | 1 | 2026-06-15 | **NULL** | **NULL** | 94,000 | **YES — named in the platform error** |
| `802WC00000OpoppYAB` | PIA-PIA-NRPS-PIAP — Powertech Identity & Access Manager (BoKS) | OneTime | 1 | (none) | NULL | 0 | 301.75 | No (OneTime — term fields not required) |
| `802WC00000OpopqYAB` | PIA-PIA-RNM-PIAMBK — …NewMaintenance | OneTime | 0 | 2026-06-15 | NULL | NULL | 0 | No (OneTime, qty 0) |

The two OneTime lines are **not** a problem: null term fields are *normal* on OneTime lines (org-wide, 100% of OneTime order lines have null EndDate). The RLM guardrail only fires on `SellingModelType = TermDefined`, and this order has exactly one such line.

### 3.2 IMPORTANT — there is a SECOND, independent blocker (CONFIRMED)

A read-only, fully-rolled-back probe (savepoint + `Database.update Status='Activated'` with `allOrNone=false`, then guaranteed rollback — **no data was committed; the order is still Draft**) returned **three** errors, not two:

1. **`INVALID_INPUT`** — *"We couldn't activate the order because the prices aren't updated. Click Reprice All and try again."* (carries **no** OrderItem reference — an independent activation-validation gate)
2. `REQUIRED_FIELD_MISSING` — *802WC00000OpopoYAB: EndDate is required for Termed order products.*
3. `REQUIRED_FIELD_MISSING` — *802WC00000OpopoYAB: PricingTermCount is required for Termed order products.*

Error #1 is corroborated by the order's own state (CONFIRMED live):

- `CalculationStatus = CompletedWithPricing`
- `ValidationResult = **TransactionIncomplete**`
- `LastPricedDate = **null**` (the order has **never** been successfully repriced)

This is the documented SC-3308 `ValidationResult = TransactionIncomplete` activation pattern: RLM will not activate an order whose pricing-validation state is incomplete.

**Consequence:** the term-field errors and the reprice/validation gate are **AND-gated** by the platform (all-or-nothing DML). **Fixing only the EndDate/PricingTermCount fields will still fail with error #1.** Both must be resolved. See §6.

### 3.3 What was ruled OUT as the blocker (CONFIRMED)

- **Custom Order Validation Rules** — all 7 active Order VRs either do not apply (the currency-lock VR only fires on `ISCHANGED(CurrencyIsoCode)`, which is not changing) or pass (all 6 Ship/Bill-To account-match rules pass because every Ship/Bill-To Place/Contact/Address resolves to the same Account `001WC00000XiZP4YAN` as `Order.AccountId`). None appeared in the probe.
- **OrderItem Validation Rules** — none exist (tooling query returned 0 rows). The OrderItem-named errors are **native RLM platform checks**, not custom VRs.
- **Field-Level Security / picklist restriction** — for the running admin, `Order.Status` is updateable and "Activated" is an active picklist value. No FLS or value-set block.
- **`OrderValidationTrigger`** (only active Apex trigger on Order) — fires on `before insert` only; does not run on a status **update**.
- **The flow's Ship/Bill-To gate** — passes; all 6 required fields are populated, so the flow reaches the status picker normally and is not itself the blocker.

---

## 4. Why the quick action HIDES the real error (CONFIRMED flow defect)

The "Update Status" quick action (`Order.Order_Complete`) launches screen flow **`Fortra_Order_Submission_Check`**. The **active version is V13** (verified via Tooling API), and the live `Org Data/_src` copy is byte-identical to the deployed V13. (Note: a different, older copy exists under `force-app/main/default/flows/`; it is **not** the active version, but it shares the identical defect described below.)

**Flow routing (verified by parsing the live V13 definition):**

```
Status_Selection (screen) → user picks a value from Order_Status_Picker
   (dynamic choice = ALL Order.Status picklist values, INCLUDING "Activated")
        │
        ▼
Status_Route (decision)
   ├─ default  "Order Complete" → Validate_Order_Submission (Apex) → Set_Order_Status_Order_Complete
   │                                                                   └─ faultConnector → Error_Screen  ✅ shows {!$Flow.FaultMessage}
   └─ rule "NOT_Order_Complete" (any other value, incl. "Activated") → Update_Order_Stage
                                                                        └─ NO faultConnector, NO connector  ❌ (terminal, unhandled)
```

Verified element facts:

- `Update_Order_Stage` is a record-update that assigns `Status = {!Order_Status_Picker}` (the user's picked value — e.g. "Activated"). It has **no `<faultConnector>` and no `<connector>`** (confirmed by parsing the live flow). A DML failure here is **unhandled** → the runtime shows the generic *"An unhandled fault has occurred in this flow."*
- `Set_Order_Status_Order_Complete` (the *other* branch) **has** a `<faultConnector>` to `Error_Screen`, which renders `{!$Flow.FaultMessage}` — i.e. the real platform text.

**So:** picking "Activated" (or any status other than "Order Complete") routes to the one element that cannot report errors. The real RLM message is generated by the platform but discarded by the flow. This is why Symptom 1 is opaque and Symptom 2 is informative — same failure, different error-handling.

> Caveat (HYPOTHESIS, well-supported): the exact symptom-1→Update_Order_Stage mapping is inferred from the verified flow structure + the verified platform errors; a live screen-flow interview was not re-run during this analysis. The structural defect (no fault connector) and the platform errors are both CONFIRMED; the linkage is the only inferred step.

---

## 5. Origin — why the term fields are null

### 5.1 These fields are engine-derived, not user-entered (CONFIRMED)

`EndDate` and `PricingTermCount` are **platform-derived** values stamped by the RLM/RCA pricing engine during a successful price/reprice pass. They are not typed in by a rep. (Repo evidence: `OrderMigrationService.cls` and `QuoteMigrationService.cls` carry the comment *"PricingTermCount is system-managed and set by Revenue Cloud's pricing engine."*) The inputs needed to derive them are all present on the line (StartDate 2026-06-15, PricingTerm 1, PricingTermUnit Annual) — the same inputs that produce an EndDate on every healthy ES-CEP line. **Same inputs, null output ⇒ the derivation step never completed for this line.**

### 5.2 The null carried in from the quote (CONFIRMED)

The source quote line **`0QLWC000003ehSj4AI`** (ES-CEP-RSL-ACTIDB, TermDefined) on quote `0Q0WC0000039Vm10AE` was itself missing the fields (live query): **StartDate 2026-06-15, EndDate = null, PricingTermCount = null, SubscriptionTerm = 1.** Convert-to-order inherited both nulls. So the order line did not lose the data — it never had it.

### 5.3 Scope — this is rare (CONFIRMED)

Org-wide, only **12 of 114,890** termed (TermDefined) order lines have a null EndDate (114,878 are correctly populated) — about **0.01%**. This is not a broad data-quality problem; it is a small, recent cluster.

### 5.4 Likely cause of the missed derivation (HYPOTHESIS — strong circumstantial evidence)

The 12 lines fall into two groups:
- **1 legacy/migrated pair** (order 00000100, created 2025-10-03, never RLM-priced — pre-pipeline data).
- **A recent QA/test cluster** of ~10 lines across 7 Draft orders created 2026-06-12 → 2026-06-15 (00095477, 00095482, 00095493, 00095494, 00095501, 00095502, **00095503**) by several internal users. All share the same selling model "Term Based - Annual." Their parent orders show pricing states of `CompletedWithoutPricing`, `None`, or `CompletedWithPricing`-but-`LastPricedDate=null` — i.e. **the term-derivation step never ran to completion.**

This recent window coincides with the documented heavy churn on the `Rev_Mgmt_Default_Pricing_Procedure` (V9 → V12 → V13) and the recurring UAT reprice "contextDefinitionName" gacks. The most probable cause is a **transient pricing-procedure / context-sync regression that intermittently leaves the term-field derivation un-run.** This is supported by strong correlation but has **not yet been captured in a debug trace** (see §7).

---

## 6. Remediation

### 6.1 Correct values for this line (CONFIRMED against 114,839 production-cohort records)

- **PricingTermCount = `1`.** RLM expresses PricingTermCount in the model's pricing *period*. ES-CEP-RSL-ACTIDB is Annual / PricingTerm 1, so one annual period = **1** (not 12). Decisive: of 114,863 populated Annual termed lines, **114,839 store `1` and ZERO store `12`**. The "months = 12" interpretation does not occur anywhere in the org.
- **EndDate = `2027-06-14`** (one annual term from ServiceDate, inclusive convention = ServiceDate + 1 year − 1 day). Empirically proven against the cohort: ServiceDate 2025-06-15 → EndDate 2026-06-14; ServiceDate 2026-06-01 → 2027-05-31 (both verified live, PTC=1). For this line: 2026-06-15 + 1 year − 1 day = **2027-06-14**. (Use 2027-06-14, not 2027-06-15, to match the 114,839-record org convention.)

### 6.2 Immediate fix — unblock 00095503

> **Requires a fresh explicit UAT data-write authorization from Liam before mutating live data.** DML feasibility is proven (a no-op write to a sibling OrderItem returned Success — OrderItem is not RLM-locked while the order is Draft), but per standing policy "focus on UAT" is not write authorization.

1. **Verify state** (Draft; line `802WC00000OpopoYAB` EndDate/PricingTermCount null) — CONFIRMED.
2. **Get the UAT-DML ack.**
3. **Populate the term fields on the termed line only:**
   ```
   sf data update record --target-org FortraUAT --sobject OrderItem \
     --record-id 802WC00000OpopoYAB \
     --values "EndDate=2027-06-14 PricingTermCount=1"
   ```
   (Leave the two OneTime siblings untouched — the guardrail does not apply to them. The before-save flow "Fortra | OrderItem | Set Dates" will fire but only writes custom billing fields — `Billing_Schedule_From/To_Date__c`, `Start/End_Date_Calculated__c` — **not** the standard EndDate/PricingTermCount, so it will not clobber the fix.)
4. **Re-read** the line to confirm `EndDate=2027-06-14 / PricingTermCount=1` stuck.
5. **Clear the second blocker (error #1):** run **Reprice All** so `ValidationResult` moves off `TransactionIncomplete` and `LastPricedDate` is set. **Verify the reprice completes cleanly** (the morning "contextDefinitionName" gacks were a separate V13 issue) — do not assume it succeeds.
6. **Activate** (details inline-edit Save, or the corrected flow). Both blockers must be clear for activation to succeed.

> **Sequencing note (HYPOTHESIS, untested):** a successful Reprice All *may itself* re-derive EndDate + PricingTermCount from the model (Annual, term 1) and ServiceDate, potentially resolving all three errors in one pass. This was not tested (would need an authorized reprice). The direct field write in step 3 is the **proven** path; the reprice is **required regardless** for error #1.

### 6.3 Systemic / preventive fixes

| Priority | Fix | Where | What it prevents |
|----------|-----|-------|------------------|
| **P0** | **Add a fault connector** on `Update_Order_Stage` → an Error_Screen showing `{!$Flow.FaultMessage}` (mirror the existing handler on `Set_Order_Status_Order_Complete`). | Flow `Fortra_Order_Submission_Check` (V13) | Turns the opaque "unhandled fault" into the actionable real message. Cheapest, highest-leverage fix. |
| **P1** | **Backstop the standard term fields in the before-save flow** "Fortra | OrderItem | Set Dates": when a TermDefined line has blank EndDate/PricingTermCount, default `PricingTermCount = PSM PricingTerm` and `EndDate = ADDMONTHS(StartDate, 12 × PricingTerm) − 1`. It currently writes only custom billing fields — exactly why these standard fields stay null. | OrderItem before-save flow | Self-heals any future null-carryforward order regardless of quote state. |
| **P1** | **Derive at the quote** — before-save / pricing hook on QuoteLineItem that stamps the same standard term fields for TermDefined lines when blank. | Quote pricing | Stops the null from ever reaching the order (true root). |
| **P2** | **Pre-activation guard** (tie to SC-3338): on the activation path, validate (or better, auto-derive) EndDate + PricingTermCount + ServiceDate for every TermDefined line. Today the Apex validator runs only on the "Order Complete" branch, so the "Activated" branch **bypasses validation entirely**. | Flow / OrderSubmissionValidator | Closes the validation-bypass and prevents reps reaching the unguarded path with bad data. |
| **P2** | **Tighten the status picker** so it does not expose every Order.Status value (including "Activated") and route reps around the validated path — or route all statuses through the same validation/derivation pre-step. | Flow status picker | Removes the path that skips validation. |
| **P2** | **Backfill the other 11** broken termed lines (the same cohort) using their own ServiceDate/PSM, so they don't surface this blocker later. | Data | Clears the latent backlog. |

---

## 7. Open questions / what to confirm next

1. **Capture a FINEST / PlaceQuote debug log of a fresh Reprice All on 00095503** to confirm (a) the reprice succeeds and clears `ValidationResult=TransactionIncomplete` / sets `LastPricedDate`, and (b) whether the reprice itself re-derives the term fields — and to pinpoint the engine step (and any contextDefinitionName gack) that skipped the derivation. The May/June correlation with the V9→V12→V13 churn is strong but **not yet captured in a trace.**
2. **Why does the quote report `CompletedWithPricing` while `LastPricedDate` is null** on the affected lines? Is a posthook/flow setting the status optimistically before the line-level term derivation runs, masking a partial failure?
3. **Net-price drift:** on 00095503 the quote line's `NetUnitPrice` was 77,080 but the order line's `NetUnitPrice` is 94,000 (= list). Confirm whether the same skipped/failed order-reprice that lost the term fields also dropped the negotiated discount on conversion. (This is a *separate* concern from the activation blocker but worth flagging to the client.)
4. **Confirm the fix path:** verify a Force-reprice (`OrderRepriceInvocable`) back-fills EndDate/PricingTermCount on these Draft orders when run, vs. requiring the direct data write. (The data write is the proven path; this confirms whether the systemic backstop should be reprice-based or field-derivation-based.)

---

### Verification log (all live against FortraUAT, 2026-06-15)

- Order 00095503 state, 3 OrderItems, and the source quote line term fields — queried and match the facts above (incl. `ValidationResult=TransactionIncomplete`, `LastPricedDate=null`).
- Org-wide counts: 12 null-EndDate TermDefined order lines, 114,878 populated.
- PricingTermCount=1 for Annual = 114,839 records; PricingTermCount=12 = 0 records.
- EndDate +1yr−1day convention: ServiceDate 2025-06-15 → 2026-06-14; 2026-06-01 → 2027-05-31.
- Flow `Fortra_Order_Submission_Check` active version = **V13**; `Update_Order_Stage` has no faultConnector/connector and assigns `Status = {!Order_Status_Picker}`; `Set_Order_Status_Order_Complete` has a faultConnector to an Error_Screen rendering `{!$Flow.FaultMessage}`; `NOT_Order_Complete` rule routes to `Update_Order_Stage`.
