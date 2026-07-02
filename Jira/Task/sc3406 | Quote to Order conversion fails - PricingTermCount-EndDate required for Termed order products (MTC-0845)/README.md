# SC-3406 — Quote to Order Conversion Error: "PricingTermCount is required for Termed order products"

| Field | Value |
|---|---|
| Ticket | **SC-3406** (Salesforce-Coastal) — origin/customer ref **MTC-0845** |
| Reporter / triage | **Andy Kumar** (sys-admin repro) → assignee **Liam Jeong** (chain: Andy → Marc Debrey → Liam, 2026-06-15 AM) — parent **SC-1991 "MTC Internal Testing"**, Critical, CRM Sprint 14, status To Do |
| Repro quote | `0Q0WC0000038PHF0A2` — "Q-COLA Renewal Test -- do not delete (latest) copy 2 andy-2026-06-12" |
| Account / Currency | AB Test Account / **AUD** |
| Quote status | Accepted, Pricebook `01sWC0000022GHFYA2`, `Quote_Type__c='New'`, `COLA__c=null` |
| Convert flow | `Fortra_Quote_to_Order_Conversion` **V27** (Active) |
| Status | ✅ **TERM-FIELD BUG VERIFIED FIXED in UAT** (live re-convert test 2026-06-15) — convert no longer throws `REQUIRED_FIELD_MISSING`; V6 stamps EndDate/PricingTermCount. ⚠️ **AUD orders then hit a SEPARATE activation blocker** (Revenue Orchestrator: *"Sales Transaction cannot be processed"*; reprice → CompletedWithoutPricing) — **SC-3384 multi-currency family**, not this ticket. Quote-tier durable fix = **SC-3415**. **PROD still fully exposed.** |
| Scope | UAT (FortraUAT) — read-only investigation, no DML, quote NOT converted |

---

## Summary

Clicking **Convert Quote to Order** (Automatic activation) on `0Q0WC0000038PHF0A2` fails with the modal **"Order Creation Failed"**, surfacing the raw platform fault:

> `The flow tried to update these records: 801WC00000kdgubYAA. REQUIRED_FIELD_MISSING: 802WC00000OjUiUYAV:PricingTermCount is required for Termed order products.`

Two-stage: first **"EndDate is required for Termed order products"**, then after EndDate is populated, **"PricingTermCount is required"**.

This is the **customer-facing convert/auto-activate manifestation** of the same defect family as SC-3411 (manual activate) and SC-3415 (quote-tier root). It is NOT a clean duplicate of either — it sits between them. The error is a **native RLM / Subscription Management platform validation** on TermDefined order products at activation; there is **no custom Validation Rule or Apex trigger** on Order/OrderItem enforcing term fields (Tooling: OrderItem = 0 VRs / 0 triggers; Order = 7 VRs, none term-related). The Convert flow merely re-surfaces the platform fault on its error screen.

The symptom is **already masked in UAT** by the SC-3411 V6 backstop (`Fortra_OrderItem_Set_Dates`), which is RecordBeforeSave on OrderItem and stamps `EndDate` + `PricingTermCount=1` on blank TermDefined lines during the convert's OrderItem insert. The **durable cure** (restore quote-tier `PricingTermCount` derivation) remains SC-3415.

AUD currency and the "COLA Renewal" quote name are **incidental, not causal** — SC-3350 (COLA pricing) and SC-3384 (non-USD using USD values) are price-value defects, ruled out (`Quote_Type__c='New'`, `COLA__c=null`).

---

## Failure mechanism

Convert path in `Fortra_Quote_to_Order_Conversion` V27 (Contract branch; a No_Contract twin path is structurally identical):

```
Call_Create_Order_From_Quote   (createOrderFromQuote action, CurrentTransaction)
   -> Assign_Created_Order_Id
   -> MapQuoteLineFieldsToOrderItems   (Apex QuoteToOrderFieldMapper)
   -> SplitPowerOrderLines             (Apex PowerOrderSplittingService)
   -> Decision_Activate_Order_After_Contract.Auto_Activate_Order_Now
   -> Reprice_Order_Before_Activate    (Apex OrderRepriceInvocable, SC-3308)
   -> Decision_Order_Priced            (checks Reprice_Order_Before_Activate.pricingReady == true)
   -> Activate_Order                   (recordUpdate Order.Status = 'Activated')
        faultConnector  -> Screen_Error_Order_Creation_Failed   <-- the screenshot modal
```

- **The modal is confirmed** as `Screen_Error_Order_Creation_Failed` (flow lines 2184-2219): red header "Order Creation Failed", "Error Details" + `{!$Flow.FaultMessage}` (carries the raw `REQUIRED_FIELD_MISSING` text), and an `OrderFailed_Instructions` "Common Causes and Resolutions" list ("Prices not updated", "Configuration warnings", "Checklist incomplete", "Other errors") matching the screenshot verbatim.
- **Five fault connectors converge on the same screen** (create, both reprice steps, both activate steps). The native "EndDate is required" / "PricingTermCount is required" validation can fire at multiple platform DML moments (createOrderFromQuote, reprice/PowerOrderSplitting, and Activate_Order), but all route to the **identical user-visible modal** — which is why the screenshot looks the same at each stage.
- **Atomic rollback (CurrentTransaction):** the failed `Activate_Order` DML rolls back the whole interview. The IDs named in the fault — Order `801WC00000kdgubYAA`, `801WC00000khJpkYAE`, OrderItem `802WC00000OjUiUYAV` — **do not persist** (queries return 0 records), consistent with rollback.
- The two products are **non-maintenance** (Active Defense BEC `01tWC00000DD11JYAT` RC_41204 Subscription; Hardware `01tWC00000DD1PZYA1` RC_46000 Other), `Power_Split_Type='Order Line Only'`, Qty 1 — so SC-3411 finding #1 (OrderRepriceInvocable throwing on maintenance-decomposed orders) **does not apply** here. Post-V6 success orders show `Original_Order_Item__c=null` (no decomposition).

---

## Root cause

The order lines are TermDefined with **null PricingTermCount** because the value is **born null on the quote** and faithfully carried through convert.

1. **`QuoteLineItem.PricingTermCount` is platform read-only** — describe: `createable=false, updateable=false, calculated=false`. Only the RLM pricing engine writes it. No Fortra quote-side flow touches it (verified across `Fortra_Quote_Line_Item_Populate_QL_With_Quote_Values`, `Quote_Line_Item_On_Create`, `Fortra_Quote_Reprice` — zero `PricingTermCount`/`EndDate` references). `OrderItem.PricingTermCount` IS writable (`createable=true, updateable=true`), which is the **only** reason a fix can exist at the order tier.
2. **Engine derivation regressed (SC-3415):** TermDefined quote lines created up to 2026-06-11 ~19:16Z have PTC populated; lines created after STOP. Last populated = `0QLWC000003dBZl4AM` @ 2026-06-11T19:16:34Z; first post-churn null = `0QLWC000003dCu14AE` @ 2026-06-11T20:20:35Z — falling inside the **V12→V13 pricing-procedure churn window (~19:07Z)**. ~**938,056** null-PTC TermDefined lines org-wide, **currency-independent** (USD 834,362 / EUR 47,747 / GBP 34,113 / AUD 13,814 / CAD 8,020).
3. **The Convert flow has no mapping bug:** `grep -ic PricingTermCount` in `Fortra_Quote_to_Order_Conversion.flow` = **0**; the 5 `EndDate` references are all read-only datatable/queriedFields metadata. `createOrderFromQuote` carries PTC natively when present; the null on the order is inherited from the null on the quote.
4. **Both lines are null PTC; the Hardware line is also null EndDate** — the rare two-stage cohort. null-PTC **and** null-EndDate = **282 / 938,056 = 0.030%**. The common case (937,774 lines) is null-PTC with EndDate present → the single-stage "PricingTermCount is required" error is the **far more frequent** convert failure shape. The EndDate difference is **product-config-independent** (both products share the identical single PSMO `0jPWC000000060b2AA` "Term Based - Annual"/TermDefined; Hardware `01tWC00000DD1PZYA1` has **no** perpetual/one-time fallback) — it is purely whether a user/contract supplied EndDate at line creation. The service line had a manually-entered `2027-06-01`; the Hardware line (created 06-14) had none.
5. **COLA / multi-currency ruled out:** quote is `Quote_Type__c='New'`, `COLA__c=null`; the "Q-COLA Renewal Test" name is misleading. SC-3350/SC-3384 are price-value bugs that never touch `PricingTermCount`/`EndDate`.

---

## Why it's already addressed

**SC-3411 V6 `Fortra_OrderItem_Set_Dates`** (`301WC00000knsJNYAY`, V6, **Active**, LastModified **2026-06-15T19:04:19Z** — AFTER the 2026-06-12 report; V5 obsolete 06-10):

- RecordBeforeSave on **OrderItem**, trigger **Create AND Update**.
- Decision `Is_Termed_Blank`: `SellingModelType=TermDefined AND (EndDate IsNull OR PricingTermCount IsNull)` → `Backstop_Std_Term_Fields` sets `EndDate = Calculated_To_Date` (= EndDate if present, else `ADDMONTHS(ServiceDate || Order.EffectiveDate, 12) - 1`) and `PricingTermCount = Std_PricingTermCount` (= PTC if present, else **1**).
- Because `createOrderFromQuote` runs `CurrentTransaction`, the before-save fires on the **insert** — so the rows are valid before `Activate_Order`. `createOrderFromQuote` also defaults `OrderItem.ServiceDate` to `Order.EffectiveDate`, giving the fallback a non-null base even for the all-null Hardware scenario.

**Empirical proof (re-verified live, read-only):**

| Order | Created | Status | TermDefined line | PTC | EndDate | ServiceDate |
|---|---|---|---|---|---|---|
| 00095507 | 17:35Z (pre-V6) | **Draft** | ES-CEP-RSL-ACTIDB | **null** | 2027-06-14 | 2026-06-15 |
| 00095507 | 17:35Z (pre-V6) | **Draft** | VM-APS-RSL-BESTSU | **null** | 2027-06-14 | 2026-06-15 |
| 00095511 | 21:52Z (post-V6) | **Order Complete** | GS-EFA-RSSH-ARCUS | **1** | 2027-06-14 | 2026-06-15 |
| 00095513 | 22:07Z (post-V6) | **Order Complete** | GS-GSE-RSS-AAMYS | **1** | 2027-06-14 | 2026-06-15 |

- **DECISIVE:** source quote lines `0QLWC000003erlR4AQ` (GS-EFA-RSSH-ARCUS) and `0QLWC000003erru4AA` (GS-GSE-RSS-AAMYS) each had **PTC=null + EndDate=null + ServiceDate=null on the QUOTE** (re-verified) — the **exact** Hardware-line scenario of this ticket. After post-V6 convert their order items came out **PTC=1, EndDate=2027-06-14, ServiceDate=2026-06-15** and the orders reached Order Complete.
- Pre-V6 order 00095507 sits in Draft with **null PTC** on its TermDefined lines (EndDate already populated) — confirming the **second-stage** state and that the EndDate fix alone is insufficient.
- Orders 00095509-13 (all post-19:04Z) reached **Order Complete** with every TermDefined OrderItem at PTC populated + non-null EndDate.

The Convert flow itself was **not** changed for SC-3411 (V27 last modified before V6) — SC-3406 is incidentally resolved by the OrderItem before-save flow, not by any convert-path-specific fix.

---

## Verification — live UAT re-convert/activate test (2026-06-15)

Run after V6 was live. **DML authorized by the assignee.** Result: **the SC-3406 term-field error is gone; AUD orders surface a separate, pre-existing activation blocker.**

| # | Order | Cur | Step | Result |
|---|---|---|---|---|
| 1 | **00095514** (repro `0Q0WC0000038PHF0A2`) | AUD | UI **convert** (by assignee, 23:13Z) | ✅ **convert succeeded** — no "Order Creation Failed". V6 stamped both lines: ACTIDB PTC=1/End 2027-06-01, **Hardware PTC=1/End 2027-06-13 (V6-computed)**; ValidationResult=null |
| 2 | 00095514 | AUD | Apex **activate** (Status='Activated') | ❌ **NOT the term-field error** → `CANNOT_EXECUTE_FLOW_TRIGGER` "Order Submission to Revenue Orchestrator … **Sales Transaction cannot be processed at this time**" |
| 3 | 00095514 | AUD | **reprice** (`OrderRepriceInvocable`) then activate | reprice `success=true, pricingReady=true, calc=`**`CompletedWithoutPricing`**; activate ❌ same orchestrator error |
| 4 | **00095497** (`0Q0WC0000038qXZ0AY`) | AUD | reprice (pre-V6 order, null PTC) | ✅ **V6 self-healed on reprice**: ACTIDB PtC null→**1**, End 2027-06-14 (proves SC-3411 "self-heal on next save/reprice") |
| 5 | fresh USD quote `0Q0WC0000039DkH0AU` | USD | standard `createOrderFromQuote` | blocked at a **quote-pricing gate** (`"prices aren't updated, Reprice All"`) — separate quote-state condition, not run further |

**Conclusions:**
- **SC-3406 term-field bug = FIXED.** The convert no longer throws `REQUIRED_FIELD_MISSING: …Termed order products`. V6 stamps the fields at convert (new orders) and self-heals older lines on reprice. Proven on the **actual AUD repro quote**.
- **AUD activation is blocked by a DIFFERENT, persistent, currency-specific defect** — the Revenue Orchestrator rejects the sales transaction and the AUD reprice yields `CompletedWithoutPricing` (pricing not applying). Population proof: **AUD = 355 Activated (all a 2026-05-08 bulk load by Marc DeBrey, Created==Activated), 4 Draft, 0 Order Complete *ever*; USD completes routinely** (00095509–13 → Order Complete 06-15). Zero AUD completions across all history rules out a transient org-wide outage → this is the **SC-3384 multi-currency** family, **not SC-3406**.
- Order **00095514 left in Draft** (repriced, term fields stamped, ValidationResult=null) pending the AUD orchestrator fix.

---

## Resolution & verification steps

1. **Confirm the symptom in UAT (owner-authorized):** re-run the actual **Convert Quote to Order** on `0Q0WC0000038PHF0A2` and confirm it reaches Order Complete with `PricingTermCount=1` and non-null `EndDate` on both lines. *I did NOT convert the quote (read-only mandate).* This is the only step that closes the AUD currency gap (see residual risks).
2. **Durable cure = SC-3415:** restore RLM `PricingTermCount` derivation at the quote tier (regressed in the 2026-06-11 V12→V13 pricing-procedure churn). V6 masks the symptom; it does not restore quote-tier derivation. ~938K null-PTC TermDefined lines remain.
3. **PROD rollout (gating for closing SC-3406 in production):** FortraProd contains **ZERO versions** of both `Fortra_OrderItem_Set_Dates` and `Fortra_Order_Submission_Check` (Tooling query = 0 records each). Prod has neither the backstop nor the error-surfacing fix and is **fully exposed**. The SC-3411 V6 + V14 prod rollout (already on SC-3411's roadmap) must precede production closure.

---

## Residual risks

- **AUD / COLA convert+reprice path is empirically UNPROVEN post-V6 (uncertain).** Every decisive post-V6 success is **USD**. No AUD order has ever reached "Order Complete" (355 AUD = Activated, 3 Draft, 0 Complete); the only recent AUD orders are stuck in Draft. V6 itself is **currency-agnostic** (pure date/term math, no currency logic) and active AUD PricebookEntries exist for both products (Active Defense AUD 142880; Hardware AUD 0), so the **term-field blocker is fixed for AUD too**. BUT a **separate** SC-3384 multi-currency mis-pricing could trip `Decision_Order_Priced` (`pricingReady=false`) or a reprice fault and surface the **same generic "Order Creation Failed" modal from a DIFFERENT root cause** than the one V6 fixes. Only an authorized AUD re-convert closes this gap.
- **"Order Complete" is downstream of the convert flow** (the flow sets Status='Activated'; "Order Complete" is a Workday/orchestration status). It is stronger-than-needed evidence for the convert blocker — but Workday/COLA/multi-currency mis-pricing risks (e.g. extendedAmount / $0-hardware) live entirely **past** the V6 fix.
- **Durability (UAT-only):** V6 is UAT-only and not yet in prod; a Gearset/refresh could silently revert it. Any future change that reorders or suppresses the OrderItem RecordBeforeSave (e.g. a bulk/convert context that skips before-save) would re-expose SC-3406 even in UAT.
- **Rare-cohort vs common-cohort:** the 282-row null-PTC + null-EndDate cohort (the two-stage error) is small but live; the 937,774-row null-PTC + EndDate-present cohort means the single-stage "PricingTermCount is required" error (no EndDate prelude) is the more frequent convert failure shape.
- **A second active OrderItem flow** (`Fortra_OrderItem_Set_Workday_Contract_Line_Type` V11) exists but is **RecordAfterSave** and writes only `Workday_Contract_Line_Type__c` — no clobber of PTC/EndDate.

---

## Reconcile with SC-3411 / SC-3415

| Aspect | SC-3411 | SC-3415 | **SC-3406 (this ticket)** |
|---|---|---|---|
| Symptom | Cannot **manually activate** an already-created order — termed line missing EndDate/PricingTermCount; Update Status masks real error | Subscription orders complete with **no Assets**; PricingTermCount **not enterable** on Quote lines | **Convert Quote to Order (auto-activate)** fails "Order Creation Failed": EndDate then PricingTermCount required |
| Trigger path | Manual Activate (e.g. order 00095503) | Quote-tier read-only field; clean activate but 0 Assets (e.g. 00095470) | `Fortra_Quote_to_Order_Conversion` V27 → createOrderFromQuote → reprice → Activate_Order → fault → modal |
| Proximate mechanism | TermDefined order line with null EndDate/PTC blocks activation | RLM PTC derivation regressed; PTC platform read-only on QLI | **Same as SC-3411** (null EndDate/PTC on TermDefined order lines) |
| True root | (shares SC-3415 root) | **Quote-tier PTC derivation stopped** in V12→V13 churn (2026-06-11 ~19:07Z) | **= SC-3415** quote-tier root |
| Fix delivered | **V6** `Fortra_OrderItem_Set_Dates` + V14 `Fortra_Order_Submission_Check` (Order-tier backstop), UAT 2026-06-15T19:04Z | RCA only (durable quote-tier cure) | **None new** — incidentally resolved by SC-3411 V6 |
| Disposition link | SC-3406 **is resolved by** SC-3411 V6 | SC-3406 **is caused by** SC-3415 | UAT-RESOLVED (symptom), durable cure tracked under SC-3415 |

---

## Evidence

**Quote / lines (re-verified live):**
- Quote `0Q0WC0000038PHF0A2` — Accepted, AUD, Pricebook `01sWC0000022GHFYA2`, `Quote_Type__c='New'`, `COLA__c=null`.
- `0QLWC000003dbE54AI` ES-CEP-RSL-ACTIDB — PTC=null, Start=2026-06-12, End=2027-06-01, Service=null, TermDefined.
- `0QLWC000003eFD74AM` ES-SEG-NROR-HARDWA (`01tWC00000DD1PZYA1`) — PTC=null, Start=2026-06-14, End=null, Service=null, TermDefined. Single PSMO `0iOWC0000000R4h2AE` "Term Based - Annual"/TermDefined (no perpetual/one-time).
- Decisive source lines `0QLWC000003erlR4AQ` / `0QLWC000003erru4AA` — both PTC=null + End=null + Service=null on the quote.

**Orders / order items (re-verified live):** 00095507 Draft (pre-V6, PTC=null on TermDefined lines); 00095509-13 Order Complete (post-V6); 00095511 ARCUS PTC=1/End=2027-06-14/Service=2026-06-15; 00095513 AAMYS PTC=1/End=2027-06-14/Service=2026-06-15.

**Rolled-back IDs (do not persist):** Order `801WC00000kdgubYAA`, `801WC00000khJpkYAE`; OrderItem `802WC00000OjUiUYAV` — 0 records.

**Flows:** `Fortra_Quote_to_Order_Conversion` V27 Active; `Fortra_OrderItem_Set_Dates` `301WC00000knsJNYAY` V6 Active, LastModified 2026-06-15T19:04:19Z (V5 obsolete 2026-06-10); `Fortra_Order_Submission_Check` V14 (same window). FortraProd: 0 versions of `Fortra_OrderItem_Set_Dates` and `Fortra_Order_Submission_Check`.

**Field describes:** `QuoteLineItem.PricingTermCount` createable=false/updateable=false; `OrderItem.PricingTermCount` createable=true/updateable=true. OrderItem: 0 VRs / 0 Apex triggers; Order: 7 VRs (Lock_Currency_At_Order_Activation + 6 Bill/Ship-To match), none term-related.

**Local artifacts:**
- `evidence/live_facts.md` — query snapshot.
- `evidence/flows/Fortra_Quote_to_Order_Conversion.flow`, `evidence/flows/Fortra_OrderItem_Set_Dates.flow`.

**Related dossiers:** `sc3411 | Cannot activate Order ...`, `sc3415 | Subscription orders complete with no Assets ...` (same `*Jira/Task/` directory).

---
*RCA by Liam Jeong, 2026-06-15. Adversarially verified (4 independent live-org streams) against FortraUAT. Read-only — the repro quote was not converted.*
