# Quotes Manual Discount — Solution Design (KB)

**Purpose:** Quote-level (header) manual discount that is automatically distributed across ALL QuoteLineItems, replacing per-line manual discounting, inside Fortra's Salesforce Revenue Cloud Advanced (RCA) environment.

**Source:** `Fortra-Quotes-QuoteManualDiscount-Solution-Design-Doc` (Solution Design Document, prepared for Fortra).

---

## Executive Summary

A header-level discount capability. Sales users enter one discount value on the Quote header; it is distributed across every QuoteLineItem automatically. Three main components:

1. **`quoteLineFlexPanel`** — Lightning Web Component (LWC). UI embedded in the **Transaction Line Editor (TLE)** on the Quote record page.
2. **`QuoteRepricingController`** — Apex controller. Server-side discount distribution logic.
3. Custom fields on **Quote** storing discount configuration + **`Quote_Manual_Discount_Access`** permission set for FLS.

**Two discount modes:**
- **Percentage** — uniform percentage applied to each line item's `Discount` field.
- **Amount** — total dollar value distributed across lines via **Equal** (divided evenly) or **Proportionate** (weighted by each line's share of the total subtotal) distribution.

**Critical platform fact:** `QuoteLineItem.DiscountAmount` is a **per-unit** field, NOT a per-line field, and Salesforce validates it against `UnitPrice` (not `Subtotal`). The solution divides distributed line-level amounts by the line's `Quantity` to compute the per-unit discount, and caps at `UnitPrice`. This avoids platform validation errors discovered/fixed during UAT.

The FlexPanel also hosts: subscription date management (bulk start/end date via Date Range or Date & Term modes) and a **Hardware Groups** button (launches `hardwareGroupManager`). The `Quote_Manual_Discount_Access` permission set controls field-level access to the discount fields.

### Key Features (verbatim intent)
- Quote-level discount with automatic distribution to all QuoteLineItems.
- Dual modes: Percentage (uniform %) and Amount (total $ distributed).
- Two distribution options for Amount: Equal and Proportionate (weighted by line subtotal share).
- Correct per-unit `DiscountAmount` = line amount ÷ Quantity to satisfy Salesforce validation.
- Quote record lock polling (`isQuoteAvailable` / `waitForQuoteAvailable`) preventing concurrent edit conflicts during repricing.
- Automatic currency conversion when switching Percentage ⇄ Amount based on quote subtotal.
- Visual change indicator prompting user to click Update before navigating away.
- Integrated subscription date management (Date Range + Date & Term modes).
- Hardware Groups button launching `hardwareGroupManager` modal.
- Dedicated `Quote_Manual_Discount_Access` permission set controlling FLS for **5** discount fields.

---

## Business Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| BR-001 | Apply a single discount value at the quote header level that auto-distributes to all quote line items, eliminating per-line manual discounting. | High |
| BR-002 | Support both Percentage discounts (uniform % per line) and Amount discounts (total $ distributed). | High |
| BR-003 | Amount discounts must support two distribution methods: Equal (evenly divided) and Proportionate (weighted by each line's share of total subtotal). | High |
| BR-004 | Per-line discount amounts must NOT exceed the line item's unit price or subtotal (prevent negative pricing / SF validation errors). | High |
| BR-005 | Switching Percentage ⇄ Amount must auto-convert the entered value based on current quote subtotal. | Medium |
| BR-006 | Discount interface must be accessible within the TLE context on the Quote record page. | Medium |
| BR-007 | Access to discount config fields controlled via a dedicated permission set. | Medium |
| BR-008 | Page must auto-refresh after successful discount application to show updated line prices. | Low |
| BR-009 | If automatic repricing fails due to record locking, user must be clearly notified and directed to manual 'Reprice All' in the TLE. | Medium |

## Technical Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| TR-001 | Implement `quoteLineFlexPanel` LWC using `@wire(getRecord)` for reactive Quote binding with fields: `CurrencyIsoCode, StartDate, Latest_Effective_End_Date__c, Header_Discount_Value__c, Manual_Discount__c, Header_Discount_Type__c, Header_Distribution_Logic__c, Header_Distribution_Type__c, Subtotal`. | High |
| TR-002 | `QuoteRepricingController.repriceQuote` uses `Database.update(allOrNone=false)` for partial-failure tolerance; query QuoteLineItems including `Discount, ListPrice, Quantity, UnitPrice, Subtotal`. | High |
| TR-003 | For Amount discounts, divide calculated line-level discount by `Quantity` to get per-unit `DiscountAmount`. Salesforce validates `DiscountAmount` against `UnitPrice`, not `Subtotal`, requiring per-unit conversion. | High |
| TR-004 | Client-side lock polling via async/await + `sleep()` promise: call `isQuoteAvailable` up to **10 times** with **500ms** delays before calling `repriceQuote`. | High |
| TR-005 | Clear opposing field: PERCENTAGE → set `Discount`, clear `DiscountAmount` to null; AMOUNT → set `DiscountAmount`, clear `Discount` to null. Prevents SF validation conflicts. | High |
| TR-006 | Implement `isQuoteAvailable` using `SELECT ... FOR UPDATE` to detect locks; catch exceptions → return false for locked records. | Medium |
| TR-007 | Use `refreshApex` after successful updates; dispatch `CustomEvent('refresh')` then `setTimeout` `window.location.reload()` at **1500ms**. | Medium |
| TR-008 | Discount type picklist values must match case-sensitively between LWC JS (`Percentage`/`Amount`) and SF picklist API values. Case mismatch → radio buttons show no selection. | Medium |

---

## Data Model

### Quote — custom fields (6 deployed)

| Field (API) | Type | Details (verbatim) |
|-------------|------|--------------------|
| `Manual_Discount__c` | **Percent**, precision **5**, scale **2** | Default value **0**. Stores user-entered discount percentage. **History tracking enabled**. |
| `Header_Discount_Value__c` | **Number**, precision **18**, scale **2** | Stores the ACTIVE discount value used in repricing — either a percentage number OR a dollar amount. |
| `Header_Discount_Type__c` | **Restricted Picklist** | Values: **`Amount`, `Percentage`, `Target Amount (Override)`**. Determines how `Header_Discount_Value__c` is interpreted during repricing. (Note: §6.2 Data Model table lists the third value as `Target Amount`; §2.2 spells it `Target Amount (Override)`.) |
| `Header_Distribution_Logic__c` | **Restricted Picklist** | Values: **`Equal`, `Proportionate`**. Controls how Amount discounts are distributed across lines. |
| `Header_Distribution_Type__c` | **Restricted Picklist** | Values: **`ItemNetTotalPrice`, `NetUnitPrice`**. Determines the target field for distribution calc. **Set to `NetUnitPrice` by the LWC** (hardcoded). |
| `Header_Remainder_Amount__c` | **Currency**, precision **18**, scale **2** | Tracks any remainder amount after discount distribution due to rounding. |

> Permission set covers **5** fields (all above EXCEPT `Header_Remainder_Amount__c`). Dependency D-001 requires all **6** deployed.

### QuoteLineItem — standard fields used

| Field | Role |
|-------|------|
| `Discount` | Standard PERCENTAGE discount field. **Set for PERCENTAGE** type; **cleared to null for AMOUNT** type. |
| `DiscountAmount` | Standard **per-unit** currency discount field. **Set for AMOUNT** type (value = `lineDiscount / quantity`); **cleared to null for PERCENTAGE** type. Validated by SF against `UnitPrice`. |
| `UnitPrice` | Standard unit price. Used as the **cap** for per-unit `DiscountAmount`. |
| `Subtotal` | Standard subtotal (= `ListPrice * Quantity`). Used as proportionate distribution weight AND as per-line discount cap. |
| `ListPrice` | Queried (per TR-002); component of Subtotal. |
| `Quantity` | Divisor for per-unit conversion. |

### Field Mappings (§6.2.1)

| Source | Target |
|--------|--------|
| LWC `pendingDiscountValue` | `Quote.Header_Discount_Value__c` AND `Quote.Manual_Discount__c` |
| LWC `discountType` (Percentage/Amount) | `Quote.Header_Discount_Type__c` |
| LWC `distributionLogic` (Equal/Proportionate) | `Quote.Header_Distribution_Logic__c` |
| Hardcoded `'NetUnitPrice'` | `Quote.Header_Distribution_Type__c` |
| `Quote.Header_Discount_Value__c` (PERCENTAGE mode) | `QuoteLineItem.Discount` (uniform across all lines) |
| `Header_Discount_Value__c * (line.Subtotal / totalSubtotal) / line.Quantity` (AMOUNT Proportionate) | `QuoteLineItem.DiscountAmount` (per-unit) |
| `Header_Discount_Value__c / lineCount / line.Quantity` (AMOUNT Equal) | `QuoteLineItem.DiscountAmount` (per-unit) |

---

## Business Logic (§6.3) — exact formulas

- **Percentage Discount:** Each `QuoteLineItem.Discount` = full `Header_Discount_Value__c` percentage value. `DiscountAmount` set to **null**. Applies uniformly regardless of line quantities/amounts.

- **Amount — Proportionate:** `lineDiscount = totalDiscount * (lineSubtotal / totalSubtotal)` where `totalDiscount = Header_Discount_Value__c`. **If `totalSubtotal` is zero → falls back to Equal distribution.**

- **Amount — Equal:** `lineDiscount = totalDiscount / lineCount`.

- **Per-Unit Conversion (CRITICAL):** After computing line-level discount → `perUnitDiscount = lineDiscount / quantity`. **Round to 2 decimal places using HALF_UP.** **Cap at `UnitPrice`** to prevent `DiscountAmount > UnitPrice` validation error.

- **Subtotal Cap:** BEFORE per-unit conversion, cap `lineDiscount` at line `Subtotal` (prevent over-discounting an individual line). Ordering: subtotal cap → divide by quantity → HALF_UP round → UnitPrice cap.

- **Lock Polling:** Client-side async loop calls `isQuoteAvailable` up to **10 times** with **500ms** sleep between attempts. Still locked after all attempts → warn user to use manual **Reprice All**.

- **Type Conversion on Switch:**
  - Percentage → Amount: `newAmount = (percentage / 100) * subtotal`.
  - Amount → Percentage: `newPercentage = (amount / subtotal) * 100`.
  - Both rounded to **2 decimal places**.

- **Mutual Field Clearing:** PERCENTAGE mode: set `Discount`, clear `DiscountAmount` = null. AMOUNT mode: set `DiscountAmount`, clear `Discount` = null. Prevents SF applying conflicting discount calcs.

- **Partial Success Handling:** `Database.update(allOrNone=false)`. Success & failure counts tracked per line item. On failures, result message includes error details + remaining success count. Returned via **`RepricingResult`** wrapper.

- **Input validation (LWC, §2.1 step 3):** `0–100` for Percentage; **non-negative** for Amount.

---

## Components (§2.2)

| Component | Type | Responsibility |
|-----------|------|----------------|
| `quoteLineFlexPanel` | LWC | Main UI in TLE area. Discount type radios (Percentage/Amount), distribution logic radios (Equal/Proportionate, visible for Amount only), discount value input (currency/percent formatting), Update button, subscription date controls, Hardware Groups button. Uses `@wire(getRecord)` reactive binding. Radios are **button-type at 70% zoom** for compact display. Discount section wrapped in a bordered card matching the subscription-dates section pattern; horizontal CSS Flexbox layout. Change indicator appears when pending value ≠ saved value. |
| `QuoteRepricingController` | Apex Class | `with sharing`. Three `@AuraEnabled` methods: **`repriceQuote(quoteId, discountType)`** distributes discounts to line items; **`isQuoteAvailable(quoteId)`** checks lock via `FOR UPDATE`; **`waitForQuoteAvailable(quoteId, maxAttempts, delayMs)`** server-side poll (used as backup). |
| `QuoteRepricingControllerTest` | Apex Test Class | **12 test methods**: percentage repricing, amount repricing, proportionate distribution, equal distribution, no line items, invalid quote ID, quote availability check, lock polling, wrapper class init. Uses `@testSetup` for shared test data. |
| `Quote_Manual_Discount_Access` | Permission Set | Read/edit on **5** Quote fields: `Manual_Discount__c, Header_Discount_Value__c, Header_Discount_Type__c, Header_Distribution_Logic__c, Header_Distribution_Type__c`. Must be assigned to discount users. |

Child components launched from FlexPanel (separately deployed): **`bulkUpdateDatesModal`** (`c-bulk-update-dates-modal`) for batch start/end date updates on selected QLIs; **`hardwareGroupManager`** (`c-hardware-group-manager`) for hardware group creation + line assignment.

---

## Process Flow / Sequence (§2.1)

1. User opens Quote record page → `quoteLineFlexPanel` embedded in TLE. Loads via `@wire(getRecord)`, populates current discount values from Quote.
2. User configures: Discount Type (Percentage/Amount), Distribution Logic (Equal/Proportionate — visible for Amount), enters value. Type switch auto-recalculates value from quote subtotal.
3. User clicks **Update** → validate input (0–100 Percentage; non-negative Amount) → begin 3-step process.
4. **Step 1 — Quote Header Update:** LWC `updateRecord` saves `Header_Discount_Value__c, Manual_Discount__c, Header_Discount_Type__c, Header_Distribution_Logic__c, Header_Distribution_Type__c`.
5. **Step 2 — Lock Polling:** call `isQuoteAvailable` up to **10 times** with **500ms** client delays until Quote available.
6. **Step 3 — Line Item Repricing:** call `repriceQuote`; queries all QuoteLineItems, computes discount per line (Percentage uniform %; Amount+Proportionate `headerDiscount * lineSubtotal/totalSubtotal`; Amount+Equal `headerDiscount / lineCount`), divides Amount discounts by Quantity for per-unit, caps at UnitPrice, `Database.update(allOrNone=false)`.
7. Success → toast confirms discount + item count → page auto-refreshes after **1.5s**. Failure → warning toast advising manual **Reprice All** in TLE.

**Integration points (§6.4):** Lightning Data Service (`@wire(getRecord)` + `updateRecord`); Apex controller (3 `@AuraEnabled` methods via imported functions); TLE (dispatch `CustomEvent('refresh')` + force page reload); Hardware Group Manager modal; Bulk Update Dates modal; Permission Set FLS.

---

## Assumptions / Dependencies / Open Notes

**Assumptions:** A-001 QLI supports both `Discount` (%) and `DiscountAmount` (per-unit $) standard fields in Revenue Cloud. A-002 `DiscountAmount` is per-unit, validated vs `UnitPrice`, NOT per-line total (confirmed during UAT). A-003 Quote record page uses Lightning Record Page with TLE component. A-004 Multi-currency enabled (LWC reads `CurrencyIsoCode`). A-005 `Quote.Subtotal` accessible via `@wire(getRecord)`, = sum of line subtotals before discount. A-006 Record locking during Quote updates (e.g. pricing procedure) may temporarily block QLI updates → polling needed. A-007 `bulkUpdateDatesModal` + `hardwareGroupManager` deployed separately. A-008 Users assigned `Quote_Manual_Discount_Access` by admin.

**Internal Dependencies (all Deployed):** D-001 6 Quote custom fields. D-002 permission set created+assigned. D-003 `bulkUpdateDatesModal` LWC. D-004 `hardwareGroupManager` LWC. D-005 Quote Record Page region for `quoteLineFlexPanel` (in/adjacent to TLE). D-006 `Quote.Latest_Effective_End_Date__c` custom field for subscription date display.

**External Dependencies:** E-001 RCA with TLE enabled (Salesforce Platform Team). E-002 `QuoteLineItem.Discount` + `DiscountAmount` standard fields available (Salesforce Platform). E-003 LWC runtime: `@wire`, `NavigationMixin`, `updateRecord`, `refreshApex`, `ShowToastEvent` (Salesforce Platform).

**Open / discrepancy note:** The third `Header_Discount_Type__c` picklist value is written as `Target Amount (Override)` in §2.2 and `Target Amount` in §6.2 — the source is inconsistent; do NOT normalize without confirming the actual metadata API value.

---

## CODE-GOVERNING RULES (MUST NOT violate)

1. **`DiscountAmount` is PER-UNIT.** For AMOUNT mode, set `QuoteLineItem.DiscountAmount = lineDiscount / Quantity`. Never write the line-total amount directly — Salesforce validates `DiscountAmount` against `UnitPrice` (not `Subtotal`) and will error.
2. **Cap per-unit discount at `UnitPrice`.** After per-unit conversion, `DiscountAmount` must be ≤ `UnitPrice`. Exceeding it triggers a platform validation error.
3. **Cap line discount at `Subtotal` BEFORE per-unit conversion.** Ordering is fixed: subtotal-cap → divide by Quantity → round HALF_UP to 2 decimals → UnitPrice-cap.
4. **Rounding = HALF_UP, 2 decimal places** for per-unit discount and for type-conversion values. Do not change the rounding mode or scale.
5. **Mutual field exclusivity.** PERCENTAGE mode: set `Discount`, set `DiscountAmount = null`. AMOUNT mode: set `DiscountAmount`, set `Discount = null`. Never leave both populated — conflicting SF discount calcs result.
6. **Proportionate zero-subtotal fallback.** If `totalSubtotal == 0`, fall back to Equal distribution (`totalDiscount / lineCount`). Never divide by zero.
7. **Exact distribution formulas.** Proportionate: `lineDiscount = totalDiscount * (lineSubtotal / totalSubtotal)`. Equal: `lineDiscount = totalDiscount / lineCount`. `totalDiscount = Header_Discount_Value__c`.
8. **Type-conversion formulas.** %→$: `newAmount = (percentage / 100) * subtotal`. $→%: `newPercentage = (amount / subtotal) * 100`. Rounded to 2 decimals. Driven by current quote `Subtotal`.
9. **Lock polling constants.** `isQuoteAvailable` polled up to **10 attempts**, **500ms** between attempts, BEFORE calling `repriceQuote`. On timeout, warn user → manual Reprice All (do NOT silently proceed).
10. **`isQuoteAvailable` uses `SELECT ... FOR UPDATE`** and must catch the lock exception to return `false` (not throw) for a locked record.
11. **`repriceQuote` must use `Database.update(allOrNone=false)`** and return success/failure counts + error details in the `RepricingResult` wrapper. Partial success is required behavior, not a bug.
12. **`Header_Distribution_Type__c` is hardcoded to `'NetUnitPrice'`** by the LWC on every header update.
13. **`pendingDiscountValue` writes BOTH** `Header_Discount_Value__c` and `Manual_Discount__c`. Keep them in sync.
14. **Picklist value case sensitivity.** LWC JS strings (`Percentage`, `Amount`, `Equal`, `Proportionate`) must exactly match the Salesforce picklist API values; a case mismatch silently deselects radio buttons.
15. **Input validation ranges.** Percentage: 0–100. Amount: non-negative. Enforce before starting the 3-step update.
16. **`Manual_Discount__c` field spec is fixed:** Percent, precision 5, scale 2, default 0, history tracking ON. Numeric fields `Header_Discount_Value__c` (Number 18,2) and `Header_Remainder_Amount__c` (Currency 18,2) must retain precision/scale.
17. **Controller is `with sharing`.** Preserve sharing enforcement on `QuoteRepricingController`.
18. **Permission set governs exactly 5 fields** (`Manual_Discount__c, Header_Discount_Value__c, Header_Discount_Type__c, Header_Distribution_Logic__c, Header_Distribution_Type__c`). FLS changes to these fields must go through `Quote_Manual_Discount_Access`.
19. **Post-success refresh contract:** `refreshApex` → dispatch `CustomEvent('refresh')` → `setTimeout(window.location.reload, 1500)`. The 1.5s reload refreshes the TLE display.
20. **`@wire(getRecord)` field set** must include all TR-001 fields; removing any (esp. `Subtotal`, `CurrencyIsoCode`, `Latest_Effective_End_Date__c`) breaks type conversion, currency display, or date display.
