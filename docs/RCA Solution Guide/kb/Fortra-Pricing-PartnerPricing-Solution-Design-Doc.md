# Fortra Pricing — Partner Pricing (Solution Design Doc)

**Purpose (one line):** Apply partner-specific pricing adjustments (margins/discounts) during the Revenue Cloud pricing waterfall via an Apex Pre-Hook, supporting two configurable models (Guaranteed Margin additive, Discount single-partner) across five product types.

> Source: `Fortra-Pricing-PartnerPricing-Solution-Design-Doc`. This KB is for an AI coding agent; values, formulas, and field types below are quoted verbatim from the design doc. Where the doc is silent (e.g., rounding mode, exact SOQL, class internals), that is flagged explicitly — do NOT invent.

---

## 1. Executive Summary

When Fortra sells through partners (resellers, distributors, referral partners), each partner receives a margin = the difference between what they pay Fortra and what they charge the end customer. This solution automates partner-adjusted price calculations during quoting.

Two distinct pricing models:
- **Guaranteed Margin model** — all participating partners' margins are **summed and applied additively** (e.g., `15% + 10% = 25%` total margin).
- **Discount model** — only the **billing partner's** discount percentage applies.

The pricing model is configurable per partner. Margin percentages are differentiated across **five product types**: Software, New Maintenance, Renewal Maintenance, Subscription, and Professional Services.

Implementation integrates into the Revenue Cloud pricing waterfall as an **Apex Pre-Hook**, executing **after Regional Services Pricing and before COLA Uplift**. Uses the Revenue Cloud **Context API** for read/write of pricing data, a custom `Partner_Pricing_Model__c` object for partner configs, and a separated service layer for reusable business logic.

### 1.1 Key Features (verbatim)
- **Guaranteed Margin Model (ADDITIVE):** Sums all partner margins (Billing Partner + Reseller + Distributor + Referral) and applies using formula: `List Price x (1 - SUM of all margins%)`
- **Discount Model:** Applies only the Billing Partner's discount using formula: `List Price x (1 - Billing Partner's Discount%)`
- Five product-type-specific margin percentages: Software, New Maintenance, Renewal Maintenance, Subscription, and Professional Services
- Effective dating with optional start/end dates for pricing model validity periods
- JSON audit trail (`Partner_Margin_Detail__c`) capturing each partner's name, role, and margin contribution
- Warning system that alerts users when partners lack the required pricing model configuration
- Automatic clearing of stale partner pricing fields when partner pricing no longer applies
- Standard Revenue Cloud field integration (`PartnerUnitPrice`, `PartnerDiscountPercent`) for Transaction Line Editor display

---

## 2. Solution Overview

### 2.1 Process Flow (exact sequence)
1. Revenue Cloud triggers the pricing procedure when a quote is saved or repriced.
2. `PartnerPricingPrehook.execute()` is called as a Pre-Hook in the pricing waterfall.
3. The Pre-Hook reads Quote header fields from the SalesTransaction context tag: `Billing_Partner__c`, `Reseller__c`, `Distributor__c`, `Referral_Partner__c`, `Partner_Pricing_Model__c`.
4. `Partner_Pricing_Model__c` records are queried via SOQL to load margin percentages for each participating partner, filtered by active status and effective dating.
5. For each QuoteLineItem: the current price is captured as `Pre_Partner_Price__c`; the product type determines which margin percentage to use; the adjusted price is calculated based on the selected model (Guaranteed Margin or Discount).
6. Results are written back to the context via `updateContextAttributes`: `Partner_Adjusted_Price__c`, `PartnerUnitPrice`, `PartnerDiscountPercent`, `Partner_Margin_Detail__c` (JSON audit trail), and other audit fields.
7. Pricing continues to the next step in the waterfall (COLA Uplift).

### 2.2 Solution Components (table verbatim)

| Component | Type | Description |
|---|---|---|
| `PartnerPricingPrehook.cls` | Apex Pre-Hook | Revenue Cloud pricing hook implementing `RevSignaling.SignalingApexProcessor` that reads context, calculates partner pricing, and writes results back |
| `PartnerPricingService.cls` | Apex Service Class | Centralized business logic for pricing calculations, model lookups, validation, and reusable methods across triggers, flows, and LWC |
| `Partner_Pricing_Model__c` | Custom Object | Stores partner-specific pricing configurations with Master-Detail to Account, supporting two model types with five product-type margins each |
| Quote Partner Fields | Custom Fields | Five fields on Quote object for partner selection (`Billing_Partner__c`, `Distributor__c`, `Reseller__c`, `Referral_Partner__c`) and model configuration |
| QuoteLineItem Partner Fields | Custom Fields | Eight fields on QuoteLineItem for calculated results, audit trail, and override tracking |
| `Partner_Pricing_Admin` | Permission Set | Full CRUD access to `Partner_Pricing_Model__c`, edit Quote partner fields, read QuoteLineItem pricing fields |
| `Partner_Pricing_User` | Permission Set | Read-only access to `Partner_Pricing_Model__c`, edit Quote partner selection, read-only QuoteLineItem pricing fields |
| Context Definition Mapping | Configuration | **18 context attributes** mapped in `SalesTransactionContextExt`: 5 Quote header inputs, 3 line item inputs, 10 line item outputs |

---

## 3. Requirements

### 3.1 Business Requirements
| ID | Requirement | Priority |
|---|---|---|
| BR-001 | Support two pricing models: Guaranteed Margin (additive multi-partner) and Discount (single billing partner) | High |
| BR-002 | Apply different margin percentages for five product types: Software, New Maintenance, Renewal Maintenance, Subscription, and Professional Services | High |
| BR-003 | Enable partner managers to configure one or both pricing models per partner with a selectable default | High |
| BR-004 | Auto-set the partner's default pricing model on the Quote when a billing partner is added | Medium |
| BR-005 | Allow users to switch between available pricing models if the partner has both configured | Medium |
| BR-006 | Support optional effective start/end dates for pricing model validity periods | Medium |
| BR-007 | Display warning messages on quote lines when partners lack the required pricing model configuration | Medium |
| BR-008 | Maintain a JSON audit trail showing each partner's name, role, and margin contribution per line item | High |

### 3.2 Technical Requirements
| ID | Requirement | Priority |
|---|---|---|
| TR-001 | Implement Apex Pre-Hook using `RevSignaling.SignalingApexProcessor` interface for Revenue Cloud pricing integration | High |
| TR-002 | Use Revenue Cloud Context API (`queryTags`, `updateContextAttributes`) for reading and writing pricing data without direct DML | High |
| TR-003 | Position Partner Pricing in pricing waterfall AFTER Regional Services Pricing and BEFORE COLA Uplift | High |
| TR-004 | Return SUCCESS even on errors to avoid blocking the pricing procedure (fail-safe operation) | High |
| TR-005 | Write to both standard Revenue Cloud fields (`PartnerUnitPrice`, `PartnerDiscountPercent`) and custom audit fields for TLE compatibility | High |
| TR-006 | Clear stale partner pricing fields on all line items when partner pricing no longer applies (no billing partner or model) | Medium |
| TR-007 | All Apex test classes must pass with **85%+ code coverage** | High |

---

## 4. Assumptions
| ID | Assumption |
|---|---|
| A-001 | Revenue Cloud Procedure Plan Orchestration for Pricing is enabled in Revenue Settings |
| A-002 | The `SalesTransactionContextExt` Context Definition is configured with all required partner pricing field mappings (18 context attributes) |
| A-003 | Partner accounts have `Partner_Pricing_Model__c` records pre-configured before quotes are created |
| A-004 | The pricing formula uses **additive** margin stacking for Guaranteed Margin (`15% + 10% = 25%`), **not multiplicative** (not 23.5%) |
| A-005 | The `Billing_Partner__c` field drives which partner's Discount model is used; additional partners (Reseller, Distributor, Referral) only participate in Guaranteed Margin |
| A-006 | Only one active pricing model per type per partner is supported (e.g., one active Guaranteed Margin record per Account) |
| A-007 | Quote Partner fields (`Billing_Partner__c`, `Reseller__c`, `Distributor__c`, `Referral_Partner__c`) are populated before pricing is triggered |

---

## 5. Dependencies

### 5.1 Internal
| ID | Dependency | Status |
|---|---|---|
| D-001 | Regional Services Pricing Pre-Hook must execute **before** Partner Pricing in the pricing waterfall | Complete |
| D-002 | Context Definition must include all 18 partner pricing attributes with `fieldType=inputoutput` and `transient=false` | Complete |
| D-003 | Procedure Plan Definition must register `PartnerPricingPrehook` after `RegionalServicesPricingPrehook` | Complete |
| D-004 | Quote page layout must include `Billing_Partner__c`, `Partner_Pricing_Model__c`, and other partner fields | Complete |
| D-005 | `Fortra_Product_Type__c` field must be populated on QuoteLineItem records for product-type-specific margin selection | Complete |

### 5.2 External
| ID | Dependency | Owner |
|---|---|---|
| E-001 | Revenue Cloud User, Business Rules Engine Designer, and Business Rules Engine Runtime Permission Set Licenses must be assigned | Salesforce Admin |
| E-002 | Partner account data and margin percentages must be provided by Fortra business stakeholders | Fortra Sales Operations |

---

## 6. Technical Design

### 6.1 Architecture Overview
- **Separation of Concerns:** Data layer (`Partner_Pricing_Model__c`), business logic layer (`PartnerPricingService.cls`), and integration layer (`PartnerPricingPrehook.cls`) are cleanly separated.
- **Context API Integration:** Pre-hook uses Revenue Cloud Context API (`queryTags` for read, `updateContextAttributes` for write) — **no direct DML** operations, for compatibility with the pricing orchestration framework.
- **Pricing Waterfall Position:** Partner Pricing executes as **Step 4** in the waterfall:
  `List Price -> Volume/Tier Discounts -> Regional Services Pricing -> Partner Pricing -> COLA Uplift -> Final Price`
- **Dual Field Strategy:** Writes BOTH standard RC fields (`PartnerUnitPrice`, `PartnerDiscountPercent`) AND custom audit fields (`Partner_Adjusted_Price__c`, `Partner_Margin_Detail__c`) — TLE display compatibility alongside independent audit trail.
- **Fail-Safe Operation:** The pre-hook **always returns SUCCESS status, even on errors**, to prevent blocking the pricing procedure. Errors are logged and surfaced via response messages rather than exceptions.
- **Recursion Prevention:** A **static Boolean flag** prevents re-entrant execution if the pricing engine calls the hook multiple times in a single transaction.

### 6.2 Data Model

#### `Partner_Pricing_Model__c` (Custom Object) — fields with TYPE verbatim
| Field | Type / Detail |
|---|---|
| `Account__c` | **Master-Detail to Account** identifying the partner |
| `Model_Type__c` | **Picklist**: `Guaranteed Margin` or `Discount` |
| `Is_Active__c` | **Checkbox** — indicates if model is currently active (**default: true**) |
| `Is_Default__c` | **Checkbox** — marks the default model when partner has both types |
| `Software_Percent__c` | **Percent(5,2)** — Margin/discount for **Software and Perpetual** products |
| `New_Maintenance_Percent__c` | **Percent(5,2)** — Margin/discount for **New Maintenance** products |
| `Renewal_Maintenance_Percent__c` | **Percent(5,2)** — Margin/discount for **Renewal Maintenance** products |
| `Subscription_Percent__c` | **Percent(5,2)** — Margin/discount for **Subscription and SaaS** products |
| `Services_Percent__c` | **Percent(5,2)** — Margin/discount for **Services and Professional Service** products |
| `Effective_Start_Date__c` | **Date** — Optional validity start date (**null means no start limit**) |
| `Effective_End_Date__c` | **Date** — Optional validity end date (**null means no end limit**) |

#### `Quote` (partner fields) — verbatim
| Field | Type / Detail |
|---|---|
| `Billing_Partner__c` | **Lookup(Account)** — Primary partner driving pricing, filtered to partner accounts |
| `Partner_Pricing_Model__c` | **Picklist** — Selected model: `Guaranteed Margin` or `Discount` |
| `Reseller__c` | **Lookup(Account)** — Reseller partner, participates in **Guaranteed Margin only** |
| `Distributor__c` | **Lookup(Account)** — Distributor partner, participates in **Guaranteed Margin only** |
| `Referral_Partner__c` | **Lookup(Account)** — Referral partner, participates in **Guaranteed Margin only** |

> Note: `Quote.Partner_Pricing_Model__c` is a **Picklist** (Guaranteed Margin / Discount) — NOT a lookup to the `Partner_Pricing_Model__c` object. Same API name, different meaning; do not conflate.

#### `QuoteLineItem` (partner fields, 8 declared) — verbatim
| Field | Type / Detail |
|---|---|
| `Pre_Partner_Price__c` | **Currency(18,2)** — Price before partner adjustment (**after Regional Pricing**) |
| `Partner_Adjusted_Price__c` | **Currency(18,2)** — Final price after partner margin applied |
| `Partner_Discount_Percent__c` | **Percent(5,2)** — Total partner margin/discount percentage applied |
| `Partner_Pricing_Model_Applied__c` | **Text(50)** — Which model was applied: `Guaranteed Margin` or `Discount` |
| `Partner_Pricing_Source__c` | **Picklist** — How price was determined: `System Calculated` or `Line Override` |
| `Is_Partner_Price_Overridden__c` | **Checkbox** — Flag indicating user manually overrode the partner pricing |
| `Partner_Margin_Detail__c` | **Long Text Area** — JSON breakdown of each partner's name, role, and margin percentage |
| `Partner_Pricing_Warning__c` | **Text** — Warning message displayed when partners lack the required pricing model |

> Also referenced but standard: `QuoteLineItem.UnitPrice`, `QuoteLineItem.ListPrice`, `QuoteLineItem.Fortra_Product_Type__c` (input side), and standard `QuoteLineItem.PartnerUnitPrice`, `QuoteLineItem.PartnerDiscountPercent` (output side).

### 6.2.1 Field Mappings (Source -> Target, verbatim)
| Source Field | Target Field |
|---|---|
| `Quote.Billing_Partner__c` | Context: `SalesTransaction.Billing_Partner__c` |
| `Quote.Partner_Pricing_Model__c` | Context: `SalesTransaction.Partner_Pricing_Model__c` |
| `Quote.Reseller__c` | Context: `SalesTransaction.Reseller__c` |
| `Quote.Distributor__c` | Context: `SalesTransaction.Distributor__c` |
| `Quote.Referral_Partner__c` | Context: `SalesTransaction.Referral_Partner__c` |
| `QuoteLineItem.UnitPrice` | Context: `SalesTransactionItem.UnitPrice` |
| `QuoteLineItem.ListPrice` | Context: `SalesTransactionItem.ListPrice` |
| `QuoteLineItem.Fortra_Product_Type__c` | Context: `SalesTransactionItem.Fortra_Product_Type__c` |
| Context: `PartnerUnitPrice` | `QuoteLineItem.PartnerUnitPrice` (standard) |
| Context: `PartnerDiscountPercent` | `QuoteLineItem.PartnerDiscountPercent` (standard) |
| Context: `Partner_Adjusted_Price__c` | `QuoteLineItem.Partner_Adjusted_Price__c` |
| Context: `Partner_Margin_Detail__c` | `QuoteLineItem.Partner_Margin_Detail__c` |

> Context attribute total = **18** (5 Quote header inputs, 3 line item inputs, 10 line item outputs). All mapped `fieldType=inputoutput`, `transient=false`.

### 6.3 Business Logic (exact formulas & rules)

- **Discount Model Formula:** `Partner Price = List Price x (1 - Billing Partner's Discount%)`. Only the Billing Partner participates. Example: `$1,000 x (1 - 20%) = $800`.
- **Guaranteed Margin Model Formula (ADDITIVE):** `Partner Price = List Price x (1 - SUM of all partner margins%)`. All partners participate (Billing + Reseller + Distributor + Referral). Example: Billing `15%` + Reseller `10%` = `25%` total, `$1,000 x (1 - 0.25) = $750`. **Additive, NOT multiplicative** (25%, not 23.5%).
- **Product Type Mapping** (`Fortra_Product_Type__c` value -> margin field):
  - `Software` / `Perpetual` -> `Software_Percent__c`
  - `New Maintenance` -> `New_Maintenance_Percent__c`
  - `Renewal Maintenance` -> `Renewal_Maintenance_Percent__c`
  - `Subscription` / `SaaS Subscription` -> `Subscription_Percent__c`
  - `Services` / `Professional Service` / `Renewal Services` -> `Services_Percent__c`
- **Effective Date Validation:** Only pricing models with `Is_Active__c = true` **AND** within the effective date range (or null dates) are considered. `PartnerPricingService` handles date-filtered SOQL queries.
- **Price Source Priority:** The pre-hook reads `UnitPrice` from context **first** (reflecting any prior adjustments from Regional Pricing); **falls back to `ListPrice` if `UnitPrice` is null or zero**.
- **Stale Value Clearing:** When partner pricing should not apply (no billing partner, no model, no valid partner IDs), **all 9 partner pricing output fields are explicitly set to null on all line items** to prevent stale values from a previous reprice.
- **Missing Model Warning:** When a partner is configured on the Quote but lacks the required pricing model type, a warning message is written to `Partner_Pricing_Warning__c` on each line item identifying which partner(s) need configuration.

> The formula literally uses **List Price** in the multiplication, but the price-source rule says the pre-hook reads `UnitPrice` first (post-Regional) and falls back to `ListPrice`. Interpretation per doc: the multiplicand is the current effective price captured as `Pre_Partner_Price__c`. Preserve the fallback semantics exactly (UnitPrice unless null/zero -> ListPrice).

> **Rounding mode / decimal scale of the computed price: NOT specified in the source.** Currency fields are `Currency(18,2)` and percents are `Percent(5,2)`. Do not assume a rounding mode; preserve whatever the existing implementation does.

### 6.4 Integration Points
- **Revenue Cloud Context API:** Uses `Context.IndustriesContext.queryTags()` to read `SalesTransaction` (Quote header) and `SalesTransactionItem` (line items), and `updateContextAttributes()` to write pricing results back to the context.
- **Procedure Plan Definition:** Registered as a Pre-Hook step in the Fortra pricing Procedure Plan Definition, positioned **after Regional Services Pricing and before COLA Uplift**.
- **`SalesTransactionContextExt` Context Definition:** All 18 partner pricing attributes mapped with `fieldType=inputoutput` and `transient=false` (hydration from database + persistence on save).
- **Transaction Line Editor (TLE):** Standard fields `PartnerUnitPrice` and `PartnerDiscountPercent` display partner pricing results in the RC Transaction Line Editor **without custom column configuration**.

---

## Open Issues / Ambiguities (flagged, not invented)
- **Rounding mode & scale** of the adjusted price: unspecified in the doc.
- **"9 partner pricing output fields"** for stale-clearing: the doc names 8 custom QLI fields + 2 standard (PartnerUnitPrice/PartnerDiscountPercent). Exact set of 9 cleared fields is not enumerated verbatim — verify against live `PartnerPricingPrehook.cls`.
- **Negative / >100% total margin** behavior (e.g., summed margins exceeding 100%) not addressed.
- **Tie-break** when a partner has both models but no `Is_Default__c` set: doc says one default selectable; runtime default-selection logic not detailed.
- Repo note: local Apex may be stale vs. FortraUAT; the live `PartnerPricingService` was previously flipped to a V2 (`PartnerPricingServiceV2`) partially — the design doc describes the V1 service. Retrieve live before editing.

---

## CODE-GOVERNING RULES (an engineer refactoring MUST NOT violate)

1. **Two models, exact formulas.**
   - Discount: `Partner Price = List Price x (1 - Billing Partner's Discount%)` — ONLY the Billing Partner participates.
   - Guaranteed Margin: `Partner Price = List Price x (1 - SUM of all partner margins%)` — Billing + Reseller + Distributor + Referral all participate.
2. **Guaranteed Margin is ADDITIVE, never multiplicative.** `15% + 10%` MUST equal `25%` total (result `$750` on `$1000`), NOT compounded `23.5%`. (A-004)
3. **Billing_Partner drives Discount model.** Reseller/Distributor/Referral participate in **Guaranteed Margin ONLY** — they must never contribute to the Discount calculation. (A-005)
4. **Five product-type margin fields, fixed mapping.** `Fortra_Product_Type__c` selects the margin field exactly: Software/Perpetual->`Software_Percent__c`; New Maintenance->`New_Maintenance_Percent__c`; Renewal Maintenance->`Renewal_Maintenance_Percent__c`; Subscription/SaaS Subscription->`Subscription_Percent__c`; Services/Professional Service/Renewal Services->`Services_Percent__c`. (BR-002, §6.3)
5. **Waterfall position is fixed:** Partner Pricing runs as **Step 4 — AFTER Regional Services Pricing, BEFORE COLA Uplift.** Do not reorder. (TR-003, D-001, D-003)
6. **No direct DML in the hook.** Read via `queryTags()`/Context API; write via `updateContextAttributes()` only. (TR-002, §6.1)
7. **Fail-safe: always return SUCCESS**, even on errors — never throw/block the pricing procedure. Log + surface via response messages. (TR-004)
8. **Recursion guard required:** a **static Boolean flag** must prevent re-entrant execution within one transaction. (§6.1)
9. **Dual-field write is mandatory:** write BOTH standard (`PartnerUnitPrice`, `PartnerDiscountPercent`) AND custom audit fields (`Partner_Adjusted_Price__c`, `Partner_Margin_Detail__c`, etc.). TLE relies on the standard fields; audit relies on custom. (TR-005, §6.1)
10. **Price-source priority:** use context `UnitPrice` first (post-Regional); fall back to `ListPrice` ONLY when `UnitPrice` is null or zero. Capture the pre-adjustment value into `Pre_Partner_Price__c`. (§6.3)
11. **Effective-dating + active filter:** only consider `Partner_Pricing_Model__c` where `Is_Active__c = true` AND (effective date range matches OR dates are null). Null start = no start limit; null end = no end limit. (BR-006, §6.3)
12. **One active model per type per partner** is the supported cardinality — logic may assume a single active Guaranteed Margin (and single active Discount) record per Account. (A-006)
13. **Stale-value clearing:** when partner pricing does NOT apply (no billing partner / no model / no valid partner IDs), explicitly set ALL partner pricing output fields to null on ALL line items — never leave prior-reprice values. (TR-006, §6.3)
14. **Missing-model warning:** when a configured partner lacks its required pricing model, write an identifying message to `Partner_Pricing_Warning__c` on each line item. Do not silently skip. (BR-007, §6.3)
15. **JSON audit trail:** `Partner_Margin_Detail__c` must contain each participating partner's name, role, and margin percentage per line item. (BR-008)
16. **Interface & context contract:** hook implements `RevSignaling.SignalingApexProcessor`; reads `SalesTransaction` (header) + `SalesTransactionItem` (lines); the 18 context attributes must remain `fieldType=inputoutput`, `transient=false`. (TR-001, D-002)
17. **Field types are contractual:** margin/percent fields = `Percent(5,2)`; price fields (`Pre_Partner_Price__c`, `Partner_Adjusted_Price__c`) = `Currency(18,2)`; `Partner_Pricing_Model_Applied__c` = `Text(50)`. Do not silently widen/narrow.
18. **`Quote.Partner_Pricing_Model__c` is a Picklist** (Guaranteed Margin/Discount), not an object reference. Preserve that.
19. **Business logic lives in `PartnerPricingService`, not the hook.** Keep calculations/lookups/validation in the reusable service layer (callable from triggers/flows/LWC); the hook is integration glue. (§6.1)
20. **Test coverage: 85%+ and all Apex tests passing** is a hard requirement. (TR-007)
