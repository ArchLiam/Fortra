# Fortra Orders MultiCurrency — Solution Design (KB)

> **Purpose (one line):** Implements **Legal Entity-driven Currency Auto-Selection** for Fortra's Salesforce Revenue Cloud Advanced (RCA) migration, replacing legacy user-location-based currency determination so that an Account's default Legal Entity deterministically drives transaction currency across the entire Quote-to-Order lifecycle.

Source: `Fortra-Orders-MultiCurrency-Solution-Design-Doc.txt` ("Orders MultiCurrency — Solution Design Document, Prepared for Fortra"). This KB is written for an AI coding agent. Values, field types, and formulas are quoted verbatim where the source specifies them. Where the source is vague (e.g., a field is named but its exact API type is not given), that ambiguity is preserved and flagged.

---

## 1. Executive Summary

- Replaces **legacy user-location-based** currency determination with a **Legal Entity-driven** model: the Account's default Legal Entity determines the transaction currency throughout the Quote-to-Order lifecycle.
- Fortra operates across **five currencies: USD, EUR, GBP, AUD, CAD**. Goal = consistent, predictable currency assignment.
- Anchoring currency to Legal Entity (not user geography) eliminates inconsistencies from **traveling sales reps / remote work**, and keeps currency aligned across **Opportunities, Quotes, Orders**.
- Implementation includes: automated Legal Entity auto-selection flows, currency synchronization automation, currency-mismatch warning flows, a **custom-metadata-driven currency conversion framework**, automated pricebook currency update batch processing, and legacy-compatibility components.
- Doc claims: "All components have been deployed and verified in production environments."

### 1.1 Key Features (verbatim mapping)
- **Legal Entity-driven currency auto-selection:** `Account.Default_Legal_Entity__c` drives automatic currency assignment on new Opportunities via `Fortra_Opportunity_Legal_Entity_AutoSelect` flow.
- **Automatic currency synchronization:** `Fortra_Opportunity_Currency_Sync` keeps `Opportunity.CurrencyIsoCode` aligned with the Legal Entity's currency, with a safeguard to **skip updates when Quotes exist**.
- **Currency mismatch detection:** two warning flows — `Warn_Opportunity_Quote_Currency_Mismatch` and `Warn_Quote_Order_Currency_Mismatch`.
- **Custom Metadata-driven conversion framework:** `Currency_Conversion_Formula__mdt` records define conversion rates/formulas for USD, EUR, GBP, AUD, CAD.
- **Automated pricebook currency updates:** `CurrencyConversionService` + `PricebookCurrencyUpdateBatch`.
- **Product creation with multi-currency support:** multiple flow iterations (`Create_New_Product`, `Fortra_Product_Creation_With_Currency`) auto-create pricebook entries across all active currencies.
- **`CurrencyCodeExtractor` invocable class:** parses currency text (e.g., `'AUD - Australian Dollar'`) into 3-letter ISO codes for Flow automation.
- **`Legal_Entity_Currency_Match` validation rule on Quote:** **deployed INACTIVE** for admin review before enforcement.

---

## 2. Business Requirements & Rules

### 2.1 Business Requirements (BR)
| ID | Requirement | Priority |
|----|-------------|----------|
| BR-001 | Automatically assign correct transaction currency when Opportunities are created, based on the customer Account's default Legal Entity | High |
| BR-002 | Support five currencies: USD, EUR, GBP, AUD, CAD | High |
| BR-003 | **Prevent currency changes on Opportunities after Quotes have been created** to avoid data-integrity issues (Salesforce platform limitation) | High |
| BR-004 | Provide admin ability to set a default Legal Entity per Account for consistent currency assignment across all transactions for that customer | High |
| BR-005 | Alert users when currency mismatches are detected between Opportunity/Quote or Quote/Order records | Medium |
| BR-006 | Allow users to override the auto-selected currency **at the Opportunity level before Quote creation** for exceptional cases | Medium |
| BR-007 | Automate multi-currency pricebook entry creation and updates when exchange rates change | Medium |
| BR-008 | Maintain an audit trail of Legal Entity assignment changes on Account records via **field history tracking** | Low |

### 2.2 Technical Requirements (TR)
| ID | Requirement | Priority |
|----|-------------|----------|
| TR-001 | Create `Default_Legal_Entity__c` lookup on Account with **SetNull delete constraint**, **FLS visible only to System Administrator**, and **field history tracking enabled** | High |
| TR-002 | `Fortra_Opportunity_Legal_Entity_AutoSelect` = record-triggered **after-save** flow on Opportunity (**CreateAndUpdate**) with condition `Legal_Entity__c IS NULL AND AccountId IS NOT NULL` | High |
| TR-003 | `Fortra_Opportunity_Currency_Sync` = record-triggered **after-save** flow on Opportunity (**Update**) that checks for related Quotes before updating `CurrencyIsoCode` | High |
| TR-004 | `CurrencyCodeExtractor` = invocable Apex supporting **3 input formats**: 3-letter codes, `'AUD - Australian Dollar'`, and `'AUD Australian Dollar'` | Medium |
| TR-005 | Deploy `Currency_Conversion_Formula__mdt` with fields `ISO_Code__c`, `Conversion_Rate__c`, `Conversion_Formula__c`, `Formula_Text__c`, `Is_Active__c` | Medium |
| TR-006 | `PricebookCurrencyUpdateBatch` = Batch Apex with `PricebookUpdateRollbackService` for error recovery | Medium |
| TR-007 | Deploy `Legal_Entity_Currency_Match` validation rule on Quote **INACTIVE**, requiring admin activation after review | Low |
| TR-008 | Maintain backward compatibility with legacy `CurrencySelectionService` (user-location-based) while transitioning | Low |

---

## 3. Data Model

Every custom object/field named in the source, with its type as stated. **NOTE:** the source does not give a strict SF field-type token for every custom field; where it only gives a prose descriptor, that descriptor is quoted and the type is marked inferred.

### 3.1 Account
| Field | Type | Description (verbatim / inferred) |
|-------|------|-----------------------------------|
| `Default_Legal_Entity__c` | **Lookup(LegalEntity)** | Stores default entity for currency auto-selection. **SetNull on delete. FLS: SysAdmin only. History tracked.** |

### 3.2 Opportunity
| Field | Type | Description |
|-------|------|-------------|
| `Legal_Entity__c` | **Lookup(LegalEntity)** | Auto-populated from `Account.Default_Legal_Entity__c` by AutoSelect flow |
| `CurrencyIsoCode` | Standard currency field | Auto-synced with Legal Entity's currency by Currency Sync flow |

### 3.3 Quote
| Field | Type | Description |
|-------|------|-------------|
| `LegalEntityId` | Standard lookup | Copied from Opportunity during Quote creation |
| `CurrencyIsoCode` | Standard currency field | Inherited from Opportunity (standard SF inheritance) |
| `Original_Opportunity_Currency__c` | **Custom text field** | Tracks the original Opportunity currency **at Quote creation time** |

### 3.4 Order
| Field | Type | Description |
|-------|------|-------------|
| `LegalEntityId` | Standard lookup | Propagated from Quote during Quote-to-Order (Q2O) conversion |
| `CurrencyIsoCode` | Standard currency field | Propagated from Quote during conversion |

### 3.5 `Currency_Conversion_Formula__mdt` (Custom Metadata Type)
Configuration for currency conversion rates/formulas for **USD, EUR, GBP, AUD, CAD**.

| Field | Type | Description |
|-------|------|-------------|
| `ISO_Code__c` / `Currency_ISO_Code__c` | Text (3-letter ISO) | 3-letter ISO currency code identifier for the conversion record. **Source lists BOTH names** — treat as an aliasing ambiguity; verify actual API name in org. |
| `Conversion_Rate__c` | Number | Numeric conversion rate **relative to the corporate currency (USD)** |
| `Conversion_Formula__c` / `Formula_Text__c` | Text | Text formula describing the conversion calculation method. **Source lists BOTH names** (TR-005 lists both `Conversion_Formula__c` and `Formula_Text__c` as separate fields; §6.2 pairs them as alternates) — verify. |
| `Is_Active__c` | Checkbox | Whether this currency conversion is currently active |

### 3.6 Field Mappings (source → target, verbatim)
| Source Field | Target Field (mechanism) |
|--------------|--------------------------|
| `Account.Default_Legal_Entity__c` | `Opportunity.Legal_Entity__c` (via AutoSelect Flow) |
| `LegalEntity.Currency` | `Opportunity.CurrencyIsoCode` (via Currency Sync Flow) |
| `Opportunity.Legal_Entity__c` | `Quote.LegalEntityId` (via Quote Creation) |
| `Opportunity.CurrencyIsoCode` | `Quote.CurrencyIsoCode` (via Standard Inheritance) |
| `Opportunity.CurrencyIsoCode` | `Quote.Original_Opportunity_Currency__c` (at creation time) |
| `Quote.LegalEntityId` | `Order.LegalEntityId` (via Q2O Conversion) |
| `Quote.CurrencyIsoCode` | `Order.CurrencyIsoCode` (via Q2O Conversion) |
| `Currency_Conversion_Formula__mdt` | `PricebookEntry.UnitPrice` (via Batch Processing) |

### 3.7 Currency propagation chain (data-flow architecture)
```
Account.Default_Legal_Entity__c
  -> Opportunity.Legal_Entity__c
  -> Opportunity.CurrencyIsoCode
  -> Quote.LegalEntityId + Quote.CurrencyIsoCode
  -> Order.LegalEntityId + Order.CurrencyIsoCode
```
Each level inherits from the previous; automation ensures consistency (top-down model).

---

## 4. Business Logic (exact rules, conditions, precedence)

### 4.1 Legal Entity Auto-Selection — `Fortra_Opportunity_Legal_Entity_AutoSelect`
- Record-triggered, **after-save**, on Opportunity **create AND update** (CreateAndUpdate).
- **Fires only when:** `Legal_Entity__c IS NULL AND AccountId IS NOT NULL`.
- Effect: copies `Account.Default_Legal_Entity__c` → `Opportunity.Legal_Entity__c`.
- Design intent: sets Legal Entity from Account default on creation but **does NOT overwrite manual selections** on subsequent edits (because condition requires `Legal_Entity__c IS NULL`).

### 4.2 Currency Synchronization — `Fortra_Opportunity_Currency_Sync`
- Record-triggered, **after-save**, on Opportunity **update**.
- Detects when `Legal_Entity__c` changes → updates `CurrencyIsoCode` to match the Legal Entity's currency.
- **CRITICAL SAFEGUARD:** the flow **queries for related Quotes and SKIPS the currency update if ANY Quotes exist.** This respects the SF platform limitation preventing currency change on parent Opportunity after child Quotes are created.

### 4.3 Currency Code Extraction — `CurrencyCodeExtractor` (invocable)
Handles **three input formats**:
1. 3-letter codes — e.g., `'AUD'`
2. Dash-separated — e.g., `'AUD - Australian Dollar'`
3. Space-separated — e.g., `'AUD Australian Dollar'`

**Validation:** confirms the code is **exactly 3 alphabetic characters** before returning the **uppercase** ISO code.

### 4.4 Legacy Currency Selection — `CurrencySelectionService` (superseded, retained)
`CurrencySelectionService.determineCurrencyForUser()` — **3-tier priority cascade**:
1. `User.DefaultCurrencyIsoCode` — if not null.
2. **Country-to-currency mapping for 12+ countries:** `US -> USD`, `Canada -> CAD`, `Australia -> AUD`, and **9 European countries -> EUR**.
3. **`USD` default.**

Also provides `canChangeCurrencyOnOrder()` — **blocks changes** for Order statuses: **Activated, In Fulfillment, Fulfilled, Completed.**

### 4.5 Pricebook Currency Updates
- `PricebookCurrencyUpdateBatch` processes **all active pricebook entries**, applying conversion rates from `Currency_Conversion_Formula__mdt`.
- `PricebookUpdateRollbackService` provides recovery if batch processing fails.
- `ExchangeRateUpdateTrigger` initiates the batch when `CurrencyType` records are modified.
- Conversion rate semantics: `Conversion_Rate__c` is **relative to corporate currency (USD)**.

> **Rounding mode / precise formula:** The source does NOT specify a rounding mode or the literal arithmetic of `PricebookEntry.UnitPrice = f(Conversion_Rate__c, ...)`. `Conversion_Formula__c`/`Formula_Text__c` is described only as "Text formula describing the conversion calculation method." Do NOT invent a formula — inspect the actual metadata records and Apex.

### 4.6 Warning Flows (advisory, NON-blocking)
- `Warn_Opportunity_Quote_Currency_Mismatch` — fires when Opportunity and Quote currencies diverge.
- `Warn_Quote_Order_Currency_Mismatch` — fires when Quote and Order currencies diverge.
- These display **notifications** to the user; they are **advisory rather than blocking**.

### 4.7 User override rule (BR-006)
Users may override currency **at the Opportunity level, only BEFORE Quote creation.** After a Quote exists, currency is locked (platform limitation, BR-003 / A-004 / E-004).

---

## 5. Components (with responsibility)

| Component | Type | Responsibility |
|-----------|------|----------------|
| `Fortra_Opportunity_Legal_Entity_AutoSelect` | Record-Triggered Flow (after-save, CreateAndUpdate) | Auto-populate `Opportunity.Legal_Entity__c` from `Account.Default_Legal_Entity__c` when null |
| `Fortra_Opportunity_Currency_Sync` | Record-Triggered Flow (after-save, Update) | Sync `CurrencyIsoCode` with Legal Entity currency; **skip when Quotes exist** |
| `Opportunity_Before_Insert` | Record-Triggered Flow (before-insert) | Initial currency setup on Opportunity |
| `Opportunity_After_Update` | Record-Triggered Flow (after-update) | Currency change handling on Opportunity |
| `Warn_Opportunity_Quote_Currency_Mismatch` | Record-Triggered Flow | Detect Opportunity→Quote currency mismatch (advisory) |
| `Warn_Quote_Order_Currency_Mismatch` | Record-Triggered Flow | Detect Quote→Order currency mismatch (advisory) |
| `Legal_Entity_Currency_Match` | Validation Rule (Quote) | Ensure Quote currency matches Legal Entity currency. **Deployed INACTIVE** |
| `Default_Legal_Entity__c` | Custom Field (Account) | Lookup to LegalEntity; default entity for the Account |
| `Original_Opportunity_Currency__c` | Custom Field (Quote) | Tracks original Opportunity currency at Quote creation |
| `CurrencySelectionService` | Apex Class (legacy) | User-location + country mapping currency determination. **SUPERSEDED** |
| `CurrencyCodeExtractor` | Apex Invocable Class | Extract 3-letter ISO codes from text for Flow automation |
| `SetOpportunityCurrencyOnCreate` | Apex Trigger (legacy) | Set currency on Opportunity creation. **SUPERSEDED by flow approach** |
| `Currency_Conversion_Formula__mdt` | Custom Metadata Type | Config for conversion rates/formulas (USD, EUR, GBP, AUD, CAD) |
| `CurrencyConversionService` | Apex Class | Currency conversion calculations using custom-metadata formulas |
| `PricebookCurrencyUpdateBatch` | Apex Batch Class | Update pricebook entries across multiple currencies |
| `PricebookUpdateRollbackService` | Apex Class | Rollback / reverse failed pricebook currency updates |
| `ExchangeRateUpdateTrigger` | Apex Trigger | On `CurrencyType` update → initiate pricebook currency recalculation batch |
| `RefreshPage` | Aura Component | Utility page-refresh after currency-related updates |
| **Product Creation Flows** | Screen Flows (**6**) | Create products with multi-currency pricebook entries |

### 5.1 The six (6) Product Creation Flows (verbatim list)
`Create_New_Product`, `Create_New_Product_v2`, `Fortra_Product_Creation_With_Currency`, `Product_Creation_Multi_Currency`, `Product_With_Currency_Metadata`, `Simple_Product_Creation`.
All consume `Currency_Conversion_Formula__mdt` to calculate prices across currencies.

### 5.2 Architecture layers (from §6.1)
- **Primary Flow Layer (Legal Entity-Driven):** the two core flows (AutoSelect + Currency_Sync).
- **Warning Layer:** the two Warn_* flows (advisory).
- **Legacy Compatibility Layer:** `CurrencySelectionService` + `SetOpportunityCurrencyOnCreate` trigger — superseded but retained for reference.
- **Currency Conversion Framework:** `Currency_Conversion_Formula__mdt` + `CurrencyConversionService` + `PricebookCurrencyUpdateBatch` + `PricebookUpdateRollbackService` + `ExchangeRateUpdateTrigger`.
- **Product Multi-Currency Automation:** the six product-creation flows.
- **Validation Layer:** `Legal_Entity_Currency_Match` (Quote, inactive).

---

## 6. Integration Points & Sequence

### 6.1 Process sequence (end-to-end)
1. Admin configures `Account.Default_Legal_Entity__c` — establishes standard Legal Entity (and currency) for the customer.
2. Opportunity created → `Fortra_Opportunity_Legal_Entity_AutoSelect` sets `Opportunity.Legal_Entity__c` from `Account.Default_Legal_Entity__c` (only when `Legal_Entity__c IS NULL AND AccountId IS NOT NULL`).
3. `Fortra_Opportunity_Currency_Sync` detects Legal Entity change → syncs `CurrencyIsoCode` to Legal Entity currency, **but skips if related Quotes exist**.
4. Users may override currency at Opportunity level **before** Quote creation.
5. Quote created → Quote creation flow copies `LegalEntityId` from Opportunity to Quote; `CurrencyIsoCode` follows via standard SF inheritance; `Original_Opportunity_Currency__c` captured at creation time.
6. Q2O conversion → both `LegalEntityId` and `CurrencyIsoCode` propagate to Order.
7. Currency mismatches → Warn_* flows display notifications.
8. Product/pricebook management → `Currency_Conversion_Formula__mdt` drives automated pricebook entry creation/updates across supported currencies.

### 6.2 Integration surfaces (§6.4)
- **Salesforce Multi-Currency Framework:** `CurrencyType` records, `CurrencyIsoCode` standard fields, native parent→child currency inheritance.
- **LegalEntity Standard Object** (available with Revenue Cloud): stores entity-to-currency mappings; prerequisite for auto-selection flows.
- **Revenue Cloud Quote-to-Order Pipeline:** multi-currency config sits **upstream** of Q2O; currency must be set on Opportunity before Quote creation (platform blocks changes after Quotes exist).
- **Product & Pricebook Management:** conversion framework integrates with `Pricebook`/`PricebookEntry`; `ExchangeRateUpdateTrigger` gives real-time sync on rate change.
- **Downstream Order & Billing:** Orders inherit currency from Quotes; downstream billing schedules must respect inherited currency. `Fortra_Order_to_Billing_Schedule` flow **depends on correct currency propagation** through the entire pipeline.

---

## 7. Assumptions

| ID | Assumption |
|----|-----------|
| A-001 | SF Multi-Currency feature enabled with USD, EUR, GBP, AUD, CAD activated |
| A-002 | Legal Entity records exist and are configured with associated currencies |
| A-003 | `Account.Default_Legal_Entity__c` populated by admins or data migration **before** auto-selection flows are activated |
| A-004 | SF platform limitation (no currency change after Quote creation) accepted as **design constraint, not a defect** |
| A-005 | Legacy `CurrencySelectionService` + `SetOpportunityCurrencyOnCreate` trigger will be **deactivated once Legal Entity approach fully validated in production** |
| A-006 | Exchange rates in SF `CurrencyType` maintained by Fortra finance team, kept current |
| A-007 | `Legal_Entity_Currency_Match` VR activated by admin **after UAT confirms no edge cases** |
| A-008 | Product pricebook entries **pre-created** for all active currencies during initial product setup, NOT generated on-demand during quoting |

---

## 8. Dependencies

### 8.1 Internal (all status = Complete)
| ID | Dependency |
|----|-----------|
| D-001 | LegalEntity standard object with proper currency configuration |
| D-002 | Account page layout updated to include `Default_Legal_Entity__c` |
| D-003 | Quote creation flow copies `LegalEntityId` from Opportunity to Quote |
| D-004 | Q2O conversion propagates `CurrencyIsoCode` and `LegalEntityId` |
| D-005 | RCA Pricebook configuration with multi-currency entries |
| D-006 | Orders Configuration solution for Sales Transaction Type and Order Type setup |

### 8.2 External
| ID | Dependency | Owner |
|----|-----------|-------|
| E-001 | Multi-Currency feature enablement + currency activation | Fortra Admin Team |
| E-002 | Exchange rate maintenance in `CurrencyType` records | Fortra Finance Team |
| E-003 | Legal Entity config with proper currency assignments | Fortra Admin Team |
| E-004 | SF platform behavior: currency cannot change on Opportunity after Quotes exist | Salesforce |

---

## 9. Open Issues / Ambiguities (do not resolve by guessing)
- **`Legal_Entity_Currency_Match` VR is deployed INACTIVE** — must not be assumed enforcing. Activation is gated on admin/UAT (A-007, TR-007).
- **MDT field-name aliasing:** `ISO_Code__c` vs `Currency_ISO_Code__c`, and `Conversion_Formula__c` vs `Formula_Text__c`. The source is internally inconsistent (TR-005 lists all as distinct; §6.2 pairs them as alternates). Verify the real API names against the org before referencing.
- **No rounding mode / explicit conversion arithmetic** is specified. Inspect `CurrencyConversionService` / `Currency_Conversion_Formula__mdt` records.
- **Legacy components (`CurrencySelectionService`, `SetOpportunityCurrencyOnCreate`) are superseded but still present.** Per A-005 they remain until Legal Entity approach is validated; do not treat as dead code without confirming deactivation.

---

## 10. CODE-GOVERNING RULES (must NOT be violated by any refactor)

1. **Auto-select fire condition is exactly `Legal_Entity__c IS NULL AND AccountId IS NOT NULL`.** `Fortra_Opportunity_Legal_Entity_AutoSelect` runs after-save on Opportunity create AND update, but must NEVER overwrite a non-null `Legal_Entity__c` (the `IS NULL` guard is what protects manual selections).
2. **Currency Sync must SKIP the `CurrencyIsoCode` update whenever ANY related Quote exists.** `Fortra_Opportunity_Currency_Sync` (after-save, Opportunity update) must query for related Quotes first. This is a hard platform limitation (BR-003 / A-004 / E-004), not a preference — removing this guard causes DML failures / data integrity issues.
3. **Currency may only be overridden at the Opportunity level BEFORE Quote creation.** No path may attempt to change Opportunity currency after a child Quote exists.
4. **Currency propagation direction is strictly top-down and inherited, never re-derived downstream:** `Account.Default_Legal_Entity__c → Opportunity.Legal_Entity__c → Opportunity.CurrencyIsoCode → Quote(LegalEntityId + CurrencyIsoCode) → Order(LegalEntityId + CurrencyIsoCode)`. Quote inherits `CurrencyIsoCode` via standard SF inheritance; Q2O conversion must propagate BOTH `LegalEntityId` and `CurrencyIsoCode`.
5. **`Quote.Original_Opportunity_Currency__c` is captured AT Quote creation time** and represents the original Opportunity currency snapshot — do not repurpose it as a live/current value.
6. **`CurrencyCodeExtractor` must accept all three input formats** (`'AUD'`, `'AUD - Australian Dollar'`, `'AUD Australian Dollar'`), must validate the code is **exactly 3 alphabetic characters**, and must return the **uppercase** ISO code.
7. **`CurrencySelectionService.determineCurrencyForUser()` precedence is fixed:** (1) `User.DefaultCurrencyIsoCode` if not null, then (2) country→currency map (US→USD, Canada→CAD, Australia→AUD, 9 European countries→EUR), then (3) `USD` default. Do not reorder tiers.
8. **`CurrencySelectionService.canChangeCurrencyOnOrder()` must block changes for Order statuses: Activated, In Fulfillment, Fulfilled, Completed.** Do not narrow this set.
9. **Only the five currencies USD, EUR, GBP, AUD, CAD are supported.** Do not silently support others; `Currency_Conversion_Formula__mdt` is the source of truth and its `Conversion_Rate__c` is relative to corporate currency **USD**.
10. **`Currency_Conversion_Formula__mdt` records must be the driver of pricebook conversion** via `PricebookCurrencyUpdateBatch`; conversion rates/formulas must not be hardcoded in Apex. `PricebookUpdateRollbackService` must remain wired for batch failure recovery.
11. **`ExchangeRateUpdateTrigger` fires on `CurrencyType` updates to initiate the pricebook recalculation batch** — keep this trigger→batch linkage intact.
12. **`Legal_Entity_Currency_Match` (Quote VR) must remain INACTIVE until an admin activates it post-UAT** (TR-007 / A-007). Do not auto-activate it in a deployment.
13. **`Account.Default_Legal_Entity__c` field attributes are load-bearing:** Lookup(LegalEntity), **SetNull on delete**, **FLS restricted to System Administrator**, **field history tracking enabled** (TR-001 / BR-008). Preserve all four on any redeploy.
14. **Warning flows are advisory/non-blocking.** `Warn_Opportunity_Quote_Currency_Mismatch` and `Warn_Quote_Order_Currency_Mismatch` must notify, never block/roll back the transaction.
15. **Downstream billing depends on currency propagation:** `Fortra_Order_to_Billing_Schedule` relies on correct currency reaching the Order — any change to propagation must preserve the currency reaching billing schedules.
16. **Pricebook entries are pre-created for all active currencies at product setup, not on-demand during quoting** (A-008). Do not move currency PBE generation into the quoting path.
