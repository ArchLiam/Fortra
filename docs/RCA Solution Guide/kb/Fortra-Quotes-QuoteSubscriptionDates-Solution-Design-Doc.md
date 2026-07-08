# Quotes Subscription Dates — Solution Design (Fortra RCA)

**Purpose (one line):** Bulk subscription-date management for Quote Line Items inside the Revenue Cloud Advanced (RCA) Transaction Line Editor (TLE) — update Start Date, End Date, and Subscription Term across many quote lines at once, excluding one-time products.

Source: `Fortra-Quotes-QuoteSubscriptionDates-Solution-Design-Doc.txt` (Coastal Cloud SDD for Fortra, RCA migration).

---

## Executive Summary

- Provides **bulk subscription date management** for Quote Line Items within the RCA **Transaction Line Editor (TLE)**.
- Embedded in the **`quoteLineFlexPanel`** Lightning Web Component (LWC) on the **Quote Record Page**.
- Two update modes:
  - **Date Range** — explicit Start + End dates, with **automatic Term calculation**.
  - **Date & Term** — Start date + Term (months), with **automatic End Date calculation**.
- **One-time products are automatically excluded**; only subscription (**Term-Defined**) line items are modified.
- Includes: Apex controller with **partial-success DML**, a **modal-based line selection** component, and integration with **`QuoteRepricingController`** for post-update repricing.
- Multiple **Flow variants** were built during iterative prototyping; the **`BulkUpdateDatesController`** Apex class is the **production-ready** approach (Flow variants Simple/Invocable are prototyping iterations and may be deactivated — see A-007).

### Key Features (verbatim specifics)
- Bulk updates across multiple Quote Line Items; two modes: Date Range and Date & Term.
- Automatic term calc from date range: `CEILING((EndDate - StartDate + 1) / 30)`.
- Automatic end-date calc from term: `ADDMONTHS(StartDate, Term) - 1`.
- Modal-based line selection via **`bulkUpdateDatesModal`** LWC showing only Term-Defined products with hardware group context.
- Partial-success DML — continues updating remaining lines even if individual lines fail, with detailed error reporting.
- Quote header `StartDate` synchronization and `Latest_Effective_End_Date__c` rollup recalculation after bulk updates.
- Integration with `QuoteRepricingController` for post-update repricing with **quote lock polling (10 attempts, 500ms delay)**.
- Embedded within `quoteLineFlexPanel` alongside **Manual Discount** and **Hardware Groups** functionality.

---

## Business Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| BR-001 | Update subscription Start Date, End Date, and Term across multiple Quote Line Items simultaneously from the Quote Record Page | High |
| BR-002 | Support two update modes: Date Range (start + end date, auto-calculated term) and Date & Term (start date + term, auto-calculated end date) | High |
| BR-003 | One-time products (non-subscription) automatically excluded from bulk date updates without user intervention | High |
| BR-004 | Users selectively choose which subscription line items to update (not all lines) | Medium |
| BR-005 | After updating dates, Quote header `StartDate` and Latest Effective End Date automatically synchronized | Medium |
| BR-006 | Prompt users to **Reprice All** after date updates to trigger Revenue Cloud pricing recalculation | High |
| BR-007 | Subscription term constrained to valid range **1 to 120 months** | Low |

## Technical Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| TR-001 | `BulkUpdateDatesController` must use partial-success DML (`Database.update` with `allOrNone=false`) — no all-or-nothing failures | High |
| TR-002 | `getEligibleQuoteLines` must filter on `SellingModelType=TermDefined` (exclude one-time and evergreen) and must be **cacheable** | High |
| TR-003 | Modal LWC must **flatten relationship fields** (`Product2.Name`, `QuoteLineGroup.Name`) for `lightning-datatable` compatibility | Medium |
| TR-004 | Quote lock polling must implement retry logic (**default 10 attempts, 500ms delay**) using `FOR UPDATE` server-side lock checks before repricing | Medium |
| TR-005 | Date calculations must use Salesforce-native Date methods: `daysBetween()` for term calc, `addMonths()`/`addDays()` for end-date calc | Medium |
| TR-006 | TLE subscription columns (`StartDate`, `EndDate`, `SubscriptionTerm`, `SubscriptionTermUnit`, `DoesAutomaticallyRenew`) must be configured on the Quote Record Page FlexiPage | High |

---

## Data Model

Note: the SDD does not give Apex field API types for most fields; where the doc states a semantic type (currency, percent, rollup), it is recorded verbatim below. Standard RCA fields (`StartDate`, `EndDate`, `SubscriptionTerm`, etc.) are platform-defined.

### Quote object
| Field | Type / semantics (as stated) | Description |
|-------|------------------------------|-------------|
| `StartDate` | Standard (Date) | Quote-level start date synchronized with bulk date updates. |
| `Latest_Effective_End_Date__c` | **Custom rollup** field | Stores `MAX(EndDate)` across all QuoteLineItems; recalculated after each bulk update (computed via SOQL `MAX(EndDate)`, not a native rollup summary). |
| `Total_Subscription__c` | **Currency** field | Subscription total across all line items. |
| `Subscription_Max_Discount__c` | **Percent** (max allowed discount) | Maximum allowed discount percentage for subscriptions. |

### QuoteLineItem object
| Field | Type / semantics (as stated) | Description |
|-------|------------------------------|-------------|
| `StartDate` | Standard (Date) | Line-level subscription start date updated by bulk operations. |
| `EndDate` | Standard (Date) | Line-level subscription end date; user-specified (Date Range) or calculated (Date & Term). |
| `SubscriptionTerm` | Standard (Number, months) | Term in months; user-specified (Date & Term) or calculated (Date Range). Used to identify subscription vs one-time. |
| `SubscriptionTermUnit` | Standard | Unit for subscription term (typically **Months**). Displayed in TLE column. |
| `DoesAutomaticallyRenew` | Standard (Boolean) | Auto-renewal flag for subscription lines. Displayed in TLE column. |
| `SellingModelType` | Standard, auto-populated from `ProductSellingModel` | Values: **`TermDefined`**, **`OneTime`**, **`Evergreen`**. Used to filter eligible lines. |

### Field Mappings (source → target, verbatim)
| Source | Target |
|--------|--------|
| User Input: Start Date | `Quote.StartDate` |
| User Input: Start Date | `QuoteLineItem.StartDate` |
| User Input: End Date (Date Range mode) | `QuoteLineItem.EndDate` |
| Calculated: `ADDMONTHS(StartDate, Term) - 1` (Date & Term mode) | `QuoteLineItem.EndDate` |
| User Input: Term (Date & Term mode) | `QuoteLineItem.SubscriptionTerm` |
| Calculated: `CEILING((EndDate - StartDate + 1) / 30)` (Date Range mode) | `QuoteLineItem.SubscriptionTerm` |
| Aggregated: `MAX(QuoteLineItem.EndDate)` | `Quote.Latest_Effective_End_Date__c` |

---

## Business Logic (exact formulas, rounding, defaults, edge cases)

- **Update Mode Selection:** User chooses **Date Range** (explicit start + end dates) or **Date & Term** (start date + term in months). UI dynamically shows/hides the End Date or Term field per selected mode.
- **Date Calculation — Date Range Mode:** Subscription term auto-calculated as
  `CEILING((EndDate - StartDate + 1) / 30.0)` — **rounds UP to the nearest whole month**.
  - Note the `/ 30.0` (float division) in the business-logic section vs `/ 30` in the field-mapping table — implementation must use float division (`30.0`) so CEILING rounds up correctly.
  - The `+ 1` makes the range **inclusive** of both endpoints.
- **Date Calculation — Date & Term Mode:** End date auto-calculated as
  `ADDMONTHS(StartDate, Term) - 1 day` — produces the **last day of the final subscription month**.
- **Eligibility Filtering:** Only QuoteLineItems with `SellingModelType = 'TermDefined'` are eligible. `OneTime` and `Evergreen` are excluded **at query time** in `getEligibleQuoteLines`.
- **Partial-Success Processing:** Controller uses `Database.update(itemsToUpdate, false)` — individual line failures do NOT roll back the batch. Failed lines reported with specific error messages in the `BulkUpdateResult` wrapper.
- **Quote Header Synchronization:** After updating line items → `Quote.StartDate` = user-specified start date; `Quote.Latest_Effective_End_Date__c` recalculated by querying `MAX(EndDate)` from all QuoteLineItems on the quote.
- **Input Validation (LWC, before opening modal):**
  - Start Date **always required**.
  - End Date **required in Date Range mode**.
  - Term **required and between 1–120** in Date & Term mode.
- **Post-Update Repricing:** After date changes the page reloads; users must click **Reprice All** in the TLE. `QuoteRepricingController` provides programmatic repricing with lock polling as an alternative pathway.
- **Native Date-method mandate (TR-005):** implementation uses `Date.daysBetween()` for term calc and `Date.addMonths()`/`Date.addDays()` for end-date calc (Apex-native equivalents of the CEILING/ADDMONTHS formulas above).

---

## Components

| Component | Type | Responsibility |
|-----------|------|----------------|
| `quoteLineFlexPanel` | LWC | Parent FlexPanel on Quote Record Page. Provides subscription date inputs, update-mode selector, and Apply button. Also hosts **Manual Discount** and **Hardware Groups** sections. Receives `recordId` via `@api`; uses `@wire(getRecord)` for quote-level fields (`StartDate`, `Latest_Effective_End_Date__c`). |
| `bulkUpdateDatesModal` | LWC (child) | Modal for line-level selection. Receives date params from parent via `@api`. On init queries eligible Term-Defined lines, renders them in a `lightning-datatable` with hardware group context (`QuoteLineGroup.Name`). Handles Confirm and displays update results (success/partial/failure). |
| `BulkUpdateDatesController` | Apex Controller | **Production-ready** server-side controller. `getEligibleQuoteLines` (cacheable, filters `SellingModelType=TermDefined`) and `updateQuoteLineDates` (partial-success DML with `BulkUpdateResult` wrapper). Two-phase: update Quote header `StartDate`, then partial-success DML on selected QLIs; then recalc `Latest_Effective_End_Date__c` via `MAX(EndDate)`. |
| `BulkUpdateDatesControllerTest` | Apex Test Class | **8 test methods**: Date Range mode, Date & Term mode, quote header updates, partial selection, empty selection, null input, and wrapper class validation. |
| `QuoteRepricingController` | Apex Controller (shared) | Repricing operations: `repriceQuote()`, `isQuoteAvailable()`, `waitForQuoteAvailable()` — with `FOR UPDATE` lock checking. |
| `Quote_Line_Bulk_Date_Update_Complete` | Screen Flow | Self-contained Flow doing ALL date update logic without external Apex. Validates quote status, calculates dates, loops through lines, updates via Flow DML. |
| `TLE_Bulk_Update_Dates_Action` | AutoLaunched Flow | Headless Flow for TLE integration calling `TLEBulkUpdateDates` Apex action. **Currently uses hardcoded start date and term values for testing.** |

Prototyping Flow variants mentioned: **standard, complete, invocable, simple, TLE action** (iterative). `BulkUpdateDatesController` (Apex) is production; other variants may be deactivated (A-007).

---

## Integration Points & Sequence

### Process Flow (verbatim sequence)
1. User navigates to Quote Record Page; `quoteLineFlexPanel` LWC renders in the Subscription Dates section.
2. User selects update mode (Date Range or Date & Term) and enters Start Date, End Date or Term.
3. User clicks **Apply** → validates inputs (required fields; valid term range 1–120 months) → opens `bulkUpdateDatesModal`.
4. Modal loads eligible (Term-Defined) quote lines via `BulkUpdateDatesController.getEligibleQuoteLines` → selectable datatable.
5. User selects specific lines → clicks **Confirm** → modal calls `BulkUpdateDatesController.updateQuoteLineDates`.
6. Controller calculates derived values (term from dates OR end date from term), updates Quote header `StartDate`, performs **partial-success DML** on selected QLIs.
7. Controller recalculates `Latest_Effective_End_Date__c` = `MAX(EndDate)` across all quote lines.
8. Modal shows summary (success/partial/failure + error details) → prompts user to click **Reprice All** in the TLE.

### Integration surfaces
- **RCA Transaction Line Editor (TLE):** subscription columns (`StartDate`, `EndDate`, `SubscriptionTerm`, `SubscriptionTermUnit`, `DoesAutomaticallyRenew`) configured via FlexiPage. Must be repriced after bulk updates.
- **`QuoteRepricingController` integration:** `quoteLineFlexPanel` uses it for programmatic repricing after discount AND date operations; polls availability via `isQuoteAvailable()` with `FOR UPDATE` lock check.
- **Revenue Cloud Pricing Engine:** On Reprice All (manual in TLE or programmatic), RC recalculates all line pricing from updated dates/terms.
- **QuoteLineGroup association:** modal displays hardware group context (`QuoteLineGroup.Name`) per line.
- **Quote Record Page FlexiPage:** hosts `quoteLineFlexPanel`; passes `recordId` via `@api`; uses `@wire(getRecord)`.

---

## Assumptions

| ID | Assumption |
|----|-----------|
| A-001 | RCA enabled with TLE configured for Quote management. |
| A-002 | `ProductSellingModel` records exist and are associated with products so `SellingModelType` auto-populates on QLIs (TermDefined, OneTime, Evergreen). |
| A-003 | `quoteLineFlexPanel` LWC is placed on the Quote Record Page FlexiPage and has access to `recordId`. |
| A-004 | Users manually click **Reprice All** in TLE after bulk updates. Automatic repricing via API available through `QuoteRepricingController` but **requires the quote to be unlocked**. |
| A-005 | Page may reload after repricing (RC platform behavior). Users should save unsaved work before triggering reprice. |
| A-006 | **Quote must be in Draft status** for line-item date updates. Accepted or ordered quotes cannot have line items modified. |
| A-007 | `BulkUpdateDatesController` is the production-ready Apex approach. Other Flow variants (Simple, Invocable) were prototyping iterations and may be deactivated. |

## Dependencies

### Internal (all status: Complete)
- **D-001:** `QuoteRepricingController` Apex class deployed for post-update repricing + availability polling.
- **D-002:** Quote Record Page FlexiPage includes `quoteLineFlexPanel` LWC + TLE subscription column config.
- **D-003:** TLE column config per **FORTRA-QUOTE-005** exposes `StartDate`, `EndDate`, `SubscriptionTerm`, `SubscriptionTermUnit`, `DoesAutomaticallyRenew`.
- **D-004:** `ProductSellingModel` records configured for all products (enables `SellingModelType` filtering).
- **D-005:** Quote custom fields (`Latest_Effective_End_Date__c`, `Total_Subscription__c`, `Subscription_Max_Discount__c`) exist on Quote.

### External
- **E-001 (Salesforce):** RCA managed package installed + configured with TLE support.
- **E-002 (Fortra / Coastal Cloud):** Amendment cotermination feature (**FORTRA-CONTRACT-008**) may require alignment of subscription dates with existing asset dates for amendment quotes.

## Open Issues / Watch-outs
- `TLE_Bulk_Update_Dates_Action` AutoLaunched Flow **uses hardcoded start date and term values for testing** — not production-ready as-is.
- Amendment cotermination (E-002 / FORTRA-CONTRACT-008) date alignment is an open cross-feature dependency, not implemented in this SDD.
- `Latest_Effective_End_Date__c` is recomputed imperatively via SOQL `MAX(EndDate)` after each bulk update — it is NOT a native rollup, so any code path that changes QLI EndDate outside this controller must also recompute it or the value goes stale.

---

## CODE-GOVERNING RULES (must not violate)

1. **Partial-success DML only.** `updateQuoteLineDates` MUST call `Database.update(itemsToUpdate, false)` (`allOrNone=false`). Never use all-or-nothing DML — a single bad line must not roll back the batch. Failed lines must be reported with per-line error messages via the `BulkUpdateResult` wrapper. (TR-001)
2. **Eligibility filter is `SellingModelType = 'TermDefined'` at query time.** `getEligibleQuoteLines` MUST exclude `OneTime` and `Evergreen` in the SOQL WHERE clause (not client-side), and MUST remain `@AuraEnabled(cacheable=true)`. One-time products are never updated. (BR-003, TR-002)
3. **Term-from-dates formula (Date Range mode):** `CEILING((EndDate - StartDate + 1) / 30.0)`. Use float division by `30.0` and round UP. The `+ 1` makes the range inclusive. In Apex use `Date.daysBetween()` and math ceiling. Do not change the divisor, the `+1`, or the rounding direction. (Business Logic, TR-005)
4. **End-date-from-term formula (Date & Term mode):** `ADDMONTHS(StartDate, Term) - 1` day → last day of the final subscription month. In Apex use `Date.addMonths()` then `Date.addDays(-1)`. Do not drop the `-1`. (Business Logic, TR-005)
5. **Term range constraint: 1–120 months.** LWC MUST validate Term is required and between 1 and 120 in Date & Term mode before opening the modal. (BR-007)
6. **Input validation gate:** Start Date always required; End Date required in Date Range mode; Term required (1–120) in Date & Term mode — all validated BEFORE opening `bulkUpdateDatesModal`. (Business Logic)
7. **Quote header two-phase sync:** After line updates, set `Quote.StartDate` = user-specified start date AND recompute `Quote.Latest_Effective_End_Date__c` = `MAX(EndDate)` across ALL QuoteLineItems on the quote (SOQL aggregate, not native rollup). Both must run every bulk update. (BR-005, Business Logic)
8. **Draft-only precondition:** Date updates apply only when the Quote is in Draft status; Accepted/ordered quotes must not have line items modified. (A-006)
9. **Datatable field flattening:** The modal MUST flatten relationship fields (`Product2.Name`, `QuoteLineGroup.Name`) into scalar columns for `lightning-datatable` compatibility. (TR-003)
10. **Reprice is a separate, post-update step:** Do not auto-reprice inline. Prompt the user to click **Reprice All**; programmatic repricing via `QuoteRepricingController` requires the quote to be unlocked. (BR-006, A-004)
11. **Quote lock polling parameters:** Programmatic repricing MUST poll quote availability using `FOR UPDATE` server-side lock checks with retry — **default 10 attempts, 500ms delay**. Use `isQuoteAvailable()` / `waitForQuoteAvailable()`. (TR-004)
12. **TLE column set is fixed:** `StartDate`, `EndDate`, `SubscriptionTerm`, `SubscriptionTermUnit`, `DoesAutomaticallyRenew` must remain configured on the Quote Record Page FlexiPage / TLE (per FORTRA-QUOTE-005). (TR-006, D-003)
13. **`BulkUpdateDatesController` (Apex) is the production path**, not the Flow variants. Business logic changes belong in the Apex controller; the self-contained `Quote_Line_Bulk_Date_Update_Complete` Flow is an alternative, and `TLE_Bulk_Update_Dates_Action` still has hardcoded test values — do not treat it as production without removing hardcoding. (A-007, Open Issues)
14. **Test coverage baseline:** `BulkUpdateDatesControllerTest` covers 8 scenarios (Date Range, Date & Term, quote header updates, partial selection, empty selection, null input, wrapper validation). Refactors must keep these paths covered.
