# Fortra Approvals (Maintenance / Quote Approvals)

**Purpose (one line):** Flow-driven Quote approval engine on the RCA Quote object that sets boolean "Approval" checkbox fields from Quote-line and Quote-header conditions, routes each triggered approval through a Cyber-vs-Tech approver chain via a megaflow, and finally moves Quote Status to `Approved` or `Rejected`.

> Source: `Fortra Approvals Maintenance.txt` (solution-design / maintenance guide). This document describes org configuration (Setup), the approval checkbox fields, the fields that feed those checkboxes, the ordered set of flows, and the internal structure of the "megaflow" `Fortra | Quote | Approvals`. It does NOT contain object/field API names, field data types, or literal formulas — those are described only in business terms in the source and are reproduced verbatim here as such. Where a fact is not in the source, this KB says so rather than inventing it.

---

## Executive Summary

- Approvals are implemented as **Flows**, not Apex. There is a screen entry flow, a series of per-condition "Approval Criteria" flows, a central megaflow `Fortra | Quote | Approvals`, an `Approval Template` decision flow, a rejection-logging flow, and a final quote-stage update flow.
- Each approval category is represented by a **boolean checkbox field** on the Quote (visible only to System Admins). The "Approval Criteria" flows evaluate conditions and set these checkboxes to True.
- The megaflow triggers **when ANY approval checkbox is checked AND changed to True**. It splits the process into **Cyber vs Tech** (different approvers), runs each triggered "segment", and waits on the Approver's Approve/Reject response on the Approvals tab.
- A **Reject** on any step immediately stops that segment and runs `Fortra | Quote | Check Approval Rejected Checkbox`, which logs the rejection (sets the `Approval Rejected` checkbox).
- At the end, `Approvals: Update Quote Stage` moves Quote Status to **`Approved`** (no rejections) or **`Rejected`** (any rejection).

---

## Setup / Org Configuration (prerequisites)

1. **Organization-Wide Addresses** (Setup → Organization-Wide Addresses): an email used for **no-reply emails and general errors regarding approvals**. It must be **verified** to work.
   - Currently set to `aaron.broom@coastalcloud.us` as a placeholder until `bsi-salesforce-test@fortra.com` (or another preferred email) can be verified.
2. **Process Automation Settings** (Setup → Process Automation Settings): populate the **second box** with the verified email used above (the OWA email).

---

## Business Requirements / Rules

An approval is triggered (its checkbox becomes True) under these exact conditions:

| # | Approval checkbox field | True when… |
|---|---|---|
| 1 | **Perpetual Pricing Discount Approval** | any Quote Lines are **Perpetual** AND discounted |
| 2 | **Subscription Pricing Discount Approval** | any Quote Lines are **Subscription** AND discounted |
| 3 | **Services Discount Approval** | any Quote Lines are **Services** AND discounted |
| 4 | **Maintenance Discount Approval** | any Quote Lines are **New/Renewal Maintenance** AND discounted |
| 5 | **Signed Quote Approval** | `Signed` is selected for the `Signed Quote?` field |
| 6 | **Unsigned Quote Approval** | `Unsigned` is selected for the `Signed Quote?` field |
| 7 | **Credit Renewal Approval** | `Credit Renewal ARR` is True |
| 8 | **Displaced ARR Approval** | `Displaced ARR` is **greater than 0**. *Will eventually be updated to use `Quote Displaced ARR` > 0.* |
| 9 | **Legal Support Approval** | `Request Legal Support` is true |
| 10 | **License Extension Approval** | `Temp License Key Extension` is true |
| 11 | **MYCAP Approval** | `Mycap` is true |
| 12 | **Net Terms Approval** | `Net Terms` picklist is **not `Net 30`** |
| 13 | **Renewal ARR Approval** | `Quote Type` is **Renewal** AND `Discount Renewal ARR` is true |
| 14 | **Renewal Cancellation Approval** | `Quote Type` is **Cancellation** OR `Quote Name` **contains** "cancellation" |
| 15 | **Approval Rejected** (checkbox) | **ANY** of the approvers **Reject ANY** of the approval steps |

Notes:
- Checkbox fields #1–#15 are described as "**this section is only visible for System Admins**".
- #8 has a known pending change: replace `Displaced ARR` with `Quote Displaced ARR`.

---

## Data Model (as described in source)

> The source names fields in business terms only; it does NOT give API names or Salesforce field data types. Types below are the **field kinds stated in the source** (e.g. "Picklist", "Checkbox", "input field"). Do not assume anything beyond this.

### Approval checkbox fields (on Quote; System-Admin-visible section)
All 15 listed above are **checkbox (boolean)** fields on the Quote. `Approval Rejected` is also a checkbox.

### Fields that AFFECT the checkbox fields (inputs / drivers)

| # | Field | Kind / role (verbatim from source) |
|---|---|---|
| 1 | **Perpetual Max Discount** | Takes the **highest** discount value of all lines where `Fortra Product Type` is **Perpetual** |
| 2 | **Subscription Max Discount** | Takes the **highest** discount value of all lines where `Fortra Product Type` is **Subscription** |
| 3 | **Service Max Discount** | Takes the **highest** discount value of all lines where `Fortra Product Type` is **Service** |
| 4 | **Maintenance Max Discount** | Takes the **highest** discount value of all lines where `Fortra Product Type` is **New Maintenance** or **Renewal Maintenance** |
| 5 | **Max Discount on QLIs** (marked `*`) | Takes the **highest** discount value of **all** lines |
| 6 | **Signed Quote** | **Picklist** to choose if Quote is `Signed` or `Unsigned` |
| 7 | **Credit Renewal ARR?** | **Checkbox** — notes that Renewal needs to be credited; opens other fields (**Credit Amount** and **Credit Renewal ARR Justification**) |
| 8 | **Renewal ARR Credit Amount** | Input the amount needing to be credited; **used in email** |
| 9 | **Credit Renewal ARR Justification** | Shown to approver (in email) — why Renewal needs to be credited |
| 10 | **Displaced ARR** | Currently an **input field** for the amount of displaced ARR to trigger approval. New work replaces this field but is **not yet added to approvals**. |
| 11 | **Displaced ARR Justification** | Shown to approver (in email) — why there was Displaced ARR |
| 12 | **Request Legal Support?** | **Checkbox** to choose if Legal support is needed; opens another field (**Legal Support Justification**) |
| 13 | **Temp License Key Extension?** | **Checkbox** — whether the license needs an extension |
| 14 | **Mycap** | **Checkbox** — whether the sale is a Mycap sale |
| 15 | **Net Terms** | **Picklist** for the terms of the Quote; **anything other than `Net 30`** triggers approval |
| 16 | **Discount Renewal ARR?** | **Checkbox** — whether renewal ARR needs further discount; opens other fields (**Discount Renewal ARR Request** and **Discount Renewal ARR Justification**) |
| 17 | **Discount Renewal ARR Request** | Input discount amount being requested; **will be in email** |
| 18 | **Discount Renewal ARR Justification** | Shown to approver (in email) — why Renewal ARR needs to be discounted |

**`Fortra Product Type`** is the line-level classifier used to bucket discounts. Values referenced: `Perpetual`, `Subscription`, `Service`, `New Maintenance`, `Renewal Maintenance`.

**`Quote Type`** header value referenced with values: `Renewal`, `Cancellation`.

---

## Business Logic (exact semantics)

- **Max-discount aggregation:** each `* Max Discount` field = the **highest (maximum) discount value** across lines filtered by `Fortra Product Type`. (No rounding mode, tie-break, or formula is given in the source.)
  - Perpetual Max Discount → `Fortra Product Type = Perpetual`
  - Subscription Max Discount → `Fortra Product Type = Subscription`
  - Service Max Discount → `Fortra Product Type = Service`
  - Maintenance Max Discount → `Fortra Product Type ∈ {New Maintenance, Renewal Maintenance}`
  - Max Discount on QLIs → **all** lines (no filter)
- **Discount approval triggers** (checkboxes 1–4) fire when there exist lines of that product type that are **discounted**. (The `* Max Discount` fields are the aggregation inputs described as "fields affecting the checkbox fields".)
- **Net Terms:** trigger iff `Net Terms != Net 30` (any non-`Net 30` value).
- **Signed vs Unsigned:** mutually exclusive picklist `Signed Quote?`; `Signed` → checkbox #5, `Unsigned` → checkbox #6.
- **Displaced ARR:** trigger iff `Displaced ARR > 0` (strictly greater than zero). Planned migration to `Quote Displaced ARR > 0`.
- **Renewal ARR:** requires BOTH `Quote Type = Renewal` AND `Discount Renewal ARR = true`.
- **Renewal Cancellation:** `Quote Type = Cancellation` OR `Quote Name` contains the substring "cancellation".
- **Rejection is terminal per segment:** a `Reject` immediately stops the current segment and logs via the rejected-checkbox flow.
- **Final status resolution:** `Approved` iff NO approver rejected; `Rejected` iff ANY approver rejected.

Edge cases / dependent-field reveals:
- `Credit Renewal ARR?` checkbox reveals `Credit Amount` + `Credit Renewal ARR Justification`.
- `Request Legal Support?` checkbox reveals `Legal Support Justification`.
- `Discount Renewal ARR?` checkbox reveals `Discount Renewal ARR Request` + `Discount Renewal ARR Justification`.

---

## Components (Flows) — ordered "Order of Flows"

> Rule stated in source: *Any flow with "Approval Criteria" in its name contains the conditions to trigger the approval checkbox and the approval flow.* Several steps are **Cyber-OR-Tech pairs** (only one path runs depending on Cyber vs Tech).

1. **Main Approvals Flow - Screen** — screen entry flow.
2. **Perpetual License Discounts - Approval Criteria** OR **Fortra | Quote | Tech Perpetual License Discounts - Approval Criteria**
3. **Fortra | Quote | Cyber Subscription Pricing Discounts - Approval Criteria** OR **Fortra | Quote | Tech Subscription Pricing Discounts - Approval Criteria**
4. **Fortra | Quote | Cyber Services Discounts - Approval Criteria** OR **Fortra | Quote | Tech Services Discounts - Approval Criteria**
5. **Cyber Maintenance Discounts - Approval Criteria** OR **Fortra | Quote | Tech Maintenance Discounts - Approval Criteria**
6. **Fortra | Quote | Unsigned Quote - Approval Criteria**
7. **Fortra | Quote | Signed Quote - Approval Criteria**
8. **Fortra | Quote | Displaced ARR - Approval Criteria**
9. **Fortra | Quote | Legal Support - Approval Criteria**
10. **Fortra | Quote | License Key Extension - Approval Criteria**
11. **Fortra | Quote | Discount Renewal ARR - Approval Criteria**
12. **Fortra | Quote | Renewal Recognition - Approval Criteria**
13. **Fortra | Quote | Renewal Cancellation - Approval Criteria**
14. **Fortra | Quote | MYCAP Sale - Approval Criteria**
15. **Fortra | Quote | Net Terms - Approval Criteria**
16. **Fortra | Quote | Approvals** — the **megaflow** (detailed below).
17. **Approval Template - Decision** — prompts/waits for Approver `Approve`/`Reject`.
18. **Fortra | Quote | Check Approval Rejected Checkbox** — logs rejections, sets the `Approval Rejected` checkbox.
19. **Approvals: Update Quote Stage** (a.k.a. `Update Quote Stage`) — final Quote-Status setter.

> Naming note: the two maintenance-discount criteria flows are `Cyber Maintenance Discounts - Approval Criteria` and `Fortra | Quote | Tech Maintenance Discounts - Approval Criteria`; the Perpetual pair is `Perpetual License Discounts - Approval Criteria` and `Fortra | Quote | Tech Perpetual License Discounts - Approval Criteria` (the Cyber variant lacks the `Fortra | Quote |` prefix in the source).

---

## Megaflow internal structure — `Fortra | Quote | Approvals`

1. **Start node**
   - Contains the trigger conditions.
   - Trigger: **If ANY of the approval checkboxes (in the Approval section on the Quote layout) are checked AND changed to True**, the flow triggers. (i.e., record-triggered on change-to-True of any approval checkbox.)
2. **Cyber or Tech**
   - Distinguishes a **Cyber** vs **Tech** approval process because **there are different approvers for each**.
3. **Approval Segments** (one per approval category)
   - The **first decision node** in each segment determines if that specific checkbox was triggered (and identifies which approval this segment handles).
   - If triggered: go to the **first stage**, **send the email**, then run the **`Approval Template`** flow which prompts and waits for the Approver to choose **Approve** or **Reject** on the **Approvals tab** on the Quote object.
     - **Approve** → proceed to the **next approver node** (if applicable) until either an approver Rejects or there are no more approvals for that segment.
     - **Reject** → the segment **immediately stops** and runs **`Check Approval Rejected Checkbox`**.
       - That flow exists **only to log ANY rejected approvals** so it knows to check the respective checkbox and move the quote status to `Rejected` at the end.
4. **End node**
   - Runs the flow **`Update Quote Stage`**, which checks if the **`Approval Rejected Checkbox`** on the Quote is True (set earlier if any approver Rejected).
   - Then sets Quote Status to **`Approved`** if no approver Rejected, or **`Rejected`** if any approver Rejected.

**Approver chaining:** within a segment approvals are sequential — each `Approve` advances to the next approver node until the chain ends or someone Rejects.

---

## Integration Points & Sequence

- **Email:** approval-request emails are sent from the segment's first stage; sender/error email is the verified **Organization-Wide Address** configured in Process Automation Settings.
- **Email content sources:** justification/amount fields are surfaced in emails to approvers — `Renewal ARR Credit Amount`, `Credit Renewal ARR Justification`, `Displaced ARR Justification`, `Discount Renewal ARR Request`, `Discount Renewal ARR Justification`.
- **Approver interaction surface:** the **Approvals tab on the Quote object** (Approve/Reject).
- **Sequence:** Screen entry → per-condition Approval-Criteria flows set checkboxes → megaflow triggers on checkbox-change-to-True → Cyber/Tech split → per-segment email + `Approval Template` wait → on Reject run `Check Approval Rejected Checkbox` → `Update Quote Stage` sets final status.

---

## Assumptions / Dependencies / Open Issues

- **OWA email not final:** placeholder `aaron.broom@coastalcloud.us`; must verify `bsi-salesforce-test@fortra.com` (or preferred) and set it in Process Automation Settings.
- **Displaced ARR migration pending:** approval #8 currently keys off `Displaced ARR > 0`; intended future change is `Quote Displaced ARR > 0`. New work replacing the `Displaced ARR` input field is done but **not yet wired into approvals**.
- **System-Admin visibility:** the approval checkbox section is only visible to System Admins.
- **Cyber/Tech duality:** every discount-category criteria flow exists in a Cyber and a Tech variant with distinct approver chains.
- **No API names / types / literal formulas** are provided in the source; do not fabricate them. Retrieve live Quote metadata (fields + flows) to confirm before editing.

---

## CODE-GOVERNING RULES (must not violate)

An engineer refactoring this implementation MUST preserve each of the following exactly:

1. **Approvals stay Flow-based.** The engine is Flows (screen flow + per-condition "Approval Criteria" flows + megaflow `Fortra | Quote | Approvals` + `Approval Template` + `Check Approval Rejected Checkbox` + `Update Quote Stage`). Do not silently re-platform to Apex/Approval Processes without matching every behavior below.
2. **Megaflow trigger:** `Fortra | Quote | Approvals` fires **when ANY approval checkbox is checked AND changed to True** — trigger on change-to-True, not on every save.
3. **Checkbox trigger conditions are exact** — do not alter:
   - Perpetual Pricing Discount = any Perpetual line discounted.
   - Subscription Pricing Discount = any Subscription line discounted.
   - Services Discount = any Services line discounted.
   - Maintenance Discount = any **New Maintenance OR Renewal Maintenance** line discounted.
   - Signed Quote = `Signed Quote? = Signed`; Unsigned Quote = `Signed Quote? = Unsigned`.
   - Credit Renewal = `Credit Renewal ARR = True`.
   - Displaced ARR = `Displaced ARR > 0` (strictly greater than 0).
   - Legal Support = `Request Legal Support = true`.
   - License Extension = `Temp License Key Extension = true`.
   - MYCAP = `Mycap = true`.
   - Net Terms = `Net Terms != Net 30` (any value other than `Net 30`).
   - Renewal ARR = `Quote Type = Renewal` **AND** `Discount Renewal ARR = true` (both required).
   - Renewal Cancellation = `Quote Type = Cancellation` **OR** `Quote Name` contains "cancellation".
4. **Max-discount fields = MAXIMUM (highest) discount**, bucketed by `Fortra Product Type`:
   - Perpetual Max → Perpetual; Subscription Max → Subscription; Service Max → Service; Maintenance Max → {New Maintenance, Renewal Maintenance}; Max Discount on QLIs → all lines. Do not change from "highest" to average/sum, and keep the exact type filters.
5. **Cyber vs Tech split is mandatory:** approver routing differs by Cyber vs Tech; keep both variants of each discount-category criteria flow and their distinct approver chains.
6. **Reject is terminal per segment:** any `Reject` immediately stops that segment and runs `Check Approval Rejected Checkbox` to set the `Approval Rejected` checkbox. Do not continue the segment after a Reject.
7. **Approve advances sequentially:** each `Approve` moves to the next approver node until the chain ends or someone Rejects (multi-approver chains per segment).
8. **Final status resolution:** `Update Quote Stage` sets Quote Status = `Approved` iff NO approver rejected, `Rejected` iff ANY approver rejected — driven by the `Approval Rejected` checkbox.
9. **`Approval Rejected` semantics:** True iff ANY approver Rejects ANY step; it is the single source of truth read by `Update Quote Stage`.
10. **Approver decisions occur on the Approvals tab of the Quote** via `Approval Template` (prompt + wait). Preserve the wait-for-response semantics.
11. **Emails require a verified OWA** configured in Process Automation Settings (second box); the no-reply/error email must be a verified Organization-Wide Address.
12. **Email-surfaced fields:** keep `Renewal ARR Credit Amount`, `Credit Renewal ARR Justification`, `Displaced ARR Justification`, `Discount Renewal ARR Request`, and `Discount Renewal ARR Justification` available to approval emails.
13. **Dependent-field reveals:** `Credit Renewal ARR?` → (Credit Amount + Credit Renewal ARR Justification); `Request Legal Support?` → Legal Support Justification; `Discount Renewal ARR?` → (Discount Renewal ARR Request + Discount Renewal ARR Justification).
14. **Displaced ARR field is mid-migration:** #8 currently uses `Displaced ARR`; a future switch to `Quote Displaced ARR > 0` is planned — do not assume it is done, and do not delete `Displaced ARR` from the approval path until approvals are re-pointed.
15. **Approval checkbox section visibility = System Admins only.** Do not broaden FLS/page-layout visibility as a side effect of refactoring.
