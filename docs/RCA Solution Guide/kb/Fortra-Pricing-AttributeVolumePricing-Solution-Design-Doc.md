# Fortra Pricing — Attribute Volume Pricing (Solution Design)

**Purpose (one line):** A dynamic Apex pre-hook pricing engine in Salesforce Revenue Cloud Advanced (RCA) that sets product price by a six-dimensional match — Product, ProductSellingModel, Attribute Name, Attribute Value, Quantity Lower Bound, Quantity Upper Bound — supporting three price modes, with no-code tier maintenance.

> Source: `Fortra-Pricing-AttributeVolumePricing-Solution-Design-Doc.txt` (Solution Design Document, prepared for Fortra). This KB captures the design spec verbatim where values/formulas/types matter. NOTE: this is a design doc; it names the intended Apex class, custom object, and context attributes but contains NO actual Apex source. Field TYPES below are as stated in §6.2; some are stated ambiguously (e.g. Product_Selling_Model__c "Lookup or Text") and are reproduced exactly.

---

## 1. Executive Summary

- Dynamic pricing engine in RCA determining price by **six-dimensional matching criteria: Product, ProductSellingModel, Attribute Name, Attribute Value, and Quantity Range (Lower and Upper Bound).** (Note: the summary text lists five names but the "Quantity Range" is two bounds → six dimensions total.)
- Lets Fortra vary a product's price by selected attributes (e.g. Feature Options or Support Level) combined with ordered quantity, **without code changes when new pricing rules are added**.
- Implemented as an Apex pre-hook **`AttributeVolumePricingPrehook`**, integrated as **Section 3** within the **`Fortra_Pricing_PreHook`** Procedure Plan Definition, following patterns from Regional Pricing and Partner Pricing.
- Supports **three price modes**:
  - **Unit Price** — sets the base unit price directly.
  - **Calculated** — applies a multiplier to the base price for the total.
  - **Total Price** — sets the total price directly.
- Tier data stored in custom object **`Attribute_Tier_Pricing_Storage__c`** — maintainable by pricing admins via standard Salesforce data management.
- **Governor-limit-safe bulk two-pass pattern:**
  - **Pass 1** — collect Product and PSM IDs from all eligible line items, issue a **single SOQL query** against the tier storage object, build an in-memory composite-key lookup map.
  - **Pass 2** — iterate each line item's attributes dynamically against the map with in-memory quantity range validation.
  - Guarantee: **exactly one SOQL query consumed regardless of the number of line items** on a quote.

### 1.1 Key Features (verbatim intent)
- **Six-Dimensional Pricing Lookup** — Product, ProductSellingModel, Attribute Name, Attribute Value, Quantity Lower Bound, Quantity Upper Bound.
- **Three Price Modes** — Unit Price (direct unit price), Calculated (base price × configurable multiplier), Total Price (direct total).
- **Dynamic Attribute Matching** — iterates ALL product attributes on each line item, checks each against tier storage; new rules for any attribute need no code changes.
- **Bulk Two-Pass Pattern** — Pass 1 collect IDs; single SOQL; composite-key map; Pass 2 O(1) attribute lookups, zero additional queries.
- **No-Code Pricing Administration** — rules stored in `Attribute_Tier_Pricing_Storage__c` records.
- **Pricing Waterfall Visibility** — writes `AttributePricingApplied__c` flag, `AttributePricingExplainer__c` text (attribute name, value, quantity, price), `Attribute_Feature__c`, and `Attribute_Quantity__c` to the pricing context.

---

## 2. Solution Overview

### 2.1 Process Flow (exact sequence)
1. Quote line items created/updated in the **Transaction Line Editor (TLE)**. The pricing procedure triggers the `Fortra_Pricing_PreHook` Procedure Plan Definition, which executes `AttributeVolumePricingPrehook` as **Section 3**.
2. Pre-hook **filters line items by the `Has_Attribute_Adjustment__c` eligibility flag**. Only line items flagged **true** are processed; all others skipped.
3. **Pass 1 (ID Collection):** iterate eligible line items, read **Product** and **ProductSellingModel** context tags to collect unique IDs; also read **LineItemQuantity** from each line item.
4. **Bulk Query:** single SOQL retrieves all `Attribute_Tier_Pricing_Storage__c` records matching collected Product and PSM IDs. Build composite-key map **`ProductId|PSMId|AttrName|AttrValue`** for O(1) lookups.
5. **Pass 2 (Attribute Matching):** for each eligible line item, read all **`SalesTransactionItemAttribute`** tags, iterate each attribute, construct composite key, check the map. On match, validate quantity against `Lower_Bound__c` and `Upper_Bound__c` **in-memory**.
6. **Context Output:** on a tier match, write **`Base_Price__c`**, **`Attribute_Price_Mode__c`**, and (for Calculated mode only) **`AttributeMultiplierPct__c`** to the pricing context via **`updateContextAttributes`**. Also set waterfall visibility attributes.
7. **Downstream Pricing Procedure** applies the calc per `Attribute_Price_Mode__c`:
   - **Unit Price** → assigns `Base_Price__c` to `InputUnitPrice`.
   - **Calculated** → `ItemNetTotalPrice = Base_Price__c × AttributeMultiplierPct__c`.
   - **Total Price** → assigns `Base_Price__c` directly to `ItemNetTotalPrice`.

### 2.2 Solution Components
| Component | Type | Responsibility |
|---|---|---|
| `AttributeVolumePricingPrehook` | Apex Class (Pre-Hook) | Main pricing pre-hook implementing `RevSignaling.SignalingApexProcessor` with bulk two-pass pattern for attribute + volume-based pricing |
| `AttributeVolumePricingPrehookTest` | Apex Test Class | Unit tests covering tier lookup logic, three price modes, null handling, edge cases using `@TestVisible` methods |
| `Attribute_Tier_Pricing_Storage__c` | Custom Object | Pricing tier storage: Product, PSM, Attribute Name/Value, Quantity Range, Tier Value, Price Mode, Multiplier |
| `Fortra_Pricing_PreHook` | Procedure Plan Definition | Parent plan: Regional Pricing (Section 1), Partner Pricing (Section 2), Attribute Volume Pricing (Section 3), Price Procedure (Section 4) |
| Pricing Procedure Elements | Pricing Procedure Configuration | Three **List Operation** elements applying Unit Price, Calculated, and Total Price mode calculations |
| Context Definition Attributes | Configuration | OUTPUT attributes on `SalesTransactionItem`: `Base_Price__c`, `Attribute_Price_Mode__c`, `AttributeMultiplierPct__c`, `AttributePricingApplied__c`, `AttributePricingExplainer__c`, `Attribute_Feature__c`, `Attribute_Quantity__c` |

---

## 3. Requirements

### 3.1 Business Requirements
| ID | Requirement | Priority |
|---|---|---|
| BR-001 | Enable three pricing modes (Unit Price, Calculated, Total Price) for various product pricing strategies | High |
| BR-002 | Enable multi-dimensional pricing by Product, ProductSellingModel, any attribute name/value, and quantity tiers | High |
| BR-003 | Automate lookup of correct pricing values to eliminate manual calc errors and **reduce pricing-related support tickets by 50%** | High |
| BR-004 | Enable reps to generate accurately priced quotes without manual intervention, **reducing quote creation time by 30%** | High |
| BR-005 | Allow pricing admins to update pricing matrices **without code changes** via standard SF data management | High |
| BR-006 | Provide transparent pricing waterfall visibility: which attribute triggered pricing, incl. name, value, quantity, price | Medium |

### 3.2 Technical Requirements
| ID | Requirement | Priority |
|---|---|---|
| TR-001 | **Single bulk SOQL query** regardless of eligible line item count; composite-key map for O(1) lookups | High |
| TR-002 | **Dynamic attribute iteration** — match ANY product attribute against tier storage, no hardcoded attribute names | High |
| TR-003 | Integrate as **Section 3** of `Fortra_Pricing_PreHook`, following Regional and Partner Pricing | High |
| TR-004 | **Recursion prevention** using a static flag for re-entrant pricing procedure calls | High |
| TR-005 | Handle **non-updatable context state errors during delete** — catch exception, return SUCCESS | Medium |
| TR-006 | Write waterfall visibility attributes (`AttributePricingApplied__c`, `AttributePricingExplainer__c`, `Attribute_Feature__c`, `Attribute_Quantity__c`) | Medium |
| TR-007 | Validate quantity range **in-memory** after the bulk query using `Lower_Bound__c` / `Upper_Bound__c` (avoid extra SOQL) | High |

---

## 4. Assumptions
| ID | Assumption |
|---|---|
| A-001 | Eligible products have `Has_Attribute_Adjustment__c` = true on the QuoteLineItem, available via the `SalesTransactionItem` context tag |
| A-002 | `Attribute_Tier_Pricing_Storage__c` is populated before the pre-hook runs. **Quantity ranges within the same Product/PSM/Attribute combination do NOT overlap** |
| A-003 | Product attributes are configured on eligible products and accessible via the `SalesTransactionItemAttribute` context tag during pricing |
| A-004 | Context Definition includes OUTPUT attributes for all seven fields with proper hydration mappings |
| A-005 | Pricing Procedure has three List Operation elements (one per price mode) consuming the pre-hook's context attributes |
| A-006 | `Fortra_Pricing_PreHook` is configured with `AttributeVolumePricingPrehook` as Section 3, after Partner Pricing and before the main Price Procedure |
| A-007 | `RevSignaling.TransactionRequest` **cannot be mocked** in unit tests. Testing relies on `@TestVisible` annotations + integration testing for end-to-end validation |

---

## 5. Dependencies

### 5.1 Internal
| ID | Dependency | Status |
|---|---|---|
| D-001 | Regional Pricing Prehook (Section 1) and Partner Pricing Prehook (Section 2) deployed and functioning in the Plan Definition | Complete |
| D-002 | Context Definition with OUTPUT attributes configured with hydration mappings | Complete |
| D-003 | `Attribute_Tier_Pricing_Storage__c` deployed with all fields: `Product__c`, `Product_Selling_Model__c`, `Attribute_Name__c`, `Attribute_Value__c`, `Lower_Bound__c`, `Upper_Bound__c`, `Tier_Value__c`, `Price_Mode__c`, `Multiplier__c` | Complete |
| D-004 | `Has_Attribute_Adjustment__c` checkbox exists on QuoteLineItem and is mapped through the Context Definition | Complete |
| D-005 | Pricing Procedure config with three List Operation elements for Unit Price, Calculated, Total Price | Complete |

### 5.2 External
| ID | Dependency | Owner |
|---|---|---|
| E-001 | Populate/maintain `Attribute_Tier_Pricing_Storage__c` with correct tier data | Fortra Pricing Team |
| E-002 | Configure product attributes on eligible products; set `Has_Attribute_Adjustment__c` flags | Fortra Product Management |

---

## 6. Technical Design

### 6.1 Architecture Overview
- **Pre-Hook Integration:** `AttributeVolumePricingPrehook implements RevSignaling.SignalingApexProcessor`; executes as **Section 3** of `Fortra_Pricing_PreHook`, after Regional Pricing (Section 1) and Partner Pricing (Section 2), before the main Price Procedure (Section 4).
- **Two-Pass Bulk Pattern:** Pass 1 collects Product + PSM IDs into Sets, then one SOQL against `Attribute_Tier_Pricing_Storage__c` using `IN` clauses; build composite-key map `ProductId|PSMId|AttrName|AttrValue`. Pass 2 iterates each eligible line item's attributes against the map with in-memory quantity range validation.
- **Recursion Prevention:** a **static Boolean flag `isUpdating`** prevents re-entrant execution when the pricing procedure fires recursively. Flag set in a **try/finally block** to guarantee cleanup.
- **Dynamic Attribute Iteration:** reads all `SalesTransactionItemAttribute` tags per line item and dynamically checks each against the composite-key map — no hardcoded attribute names.
- **Context Attribute Updates:** matched values written to `SalesTransactionItem` context via `updateContextAttributes` with the correct data path. **Only attributes that have hydration mappings in the Context Definition are included in the update batch — to prevent silent batch failures.**
- **Error Resilience:** handles missing attributes, missing quantities, missing Product/PSM tags, no matching tiers, and non-updatable context state (during delete) **gracefully — logs a message and returns SUCCESS to avoid blocking the pricing pipeline.**

### 6.2 Data Model

#### `Attribute_Tier_Pricing_Storage__c` (Custom Object — pricing tier source)
| Field | Type | Description |
|---|---|---|
| `Product__c` | Lookup(Product2) | Which product this tier applies to |
| `Product_Selling_Model__c` | **Lookup OR Text** (stated ambiguously in source) | Identifies the ProductSellingModel this tier applies to |
| `Attribute_Name__c` | Text | API name of the product attribute (e.g. `Feature_Options`, `Support_Level`) |
| `Attribute_Value__c` | Text | Attribute value to match (e.g. `Platinum`, `Premium`) |
| `Lower_Bound__c` | Number | Minimum quantity for this tier (**inclusive**) |
| `Upper_Bound__c` | Number | Maximum quantity for this tier (**inclusive**) |
| `Tier_Value__c` | Number | Base price amount for this tier |
| `Price_Mode__c` | Picklist: `Unit Price` \| `Calculated` \| `Total Price` | Determines how the tier value is applied |
| `Multiplier__c` | Number | Multiplier value — **required when `Price_Mode__c` = Calculated**, optional otherwise |

#### `SalesTransactionItem` (Context) — OUTPUT attributes
| Field | Type | Description |
|---|---|---|
| `Base_Price__c` | OUTPUT | Receives `Tier_Value__c` from the matched tier |
| `Attribute_Price_Mode__c` | OUTPUT | Receives `Price_Mode__c` (`Unit Price` / `Calculated` / `Total Price`) |
| `AttributeMultiplierPct__c` | OUTPUT | Receives `Multiplier__c` — **only written for Calculated mode** |
| `AttributePricingApplied__c` | OUTPUT Boolean | Set **true** when attribute-based pricing is successfully applied |
| `AttributePricingExplainer__c` | OUTPUT Text | Human-readable explanation, e.g. `Attr: Feature_Options=Platinum, Qty: 250, Base: $950.00 x 0.95` |
| `Attribute_Feature__c` | OUTPUT Text | Matched attribute in format `AttributeName: AttributeValue` |
| `Attribute_Quantity__c` | OUTPUT Number | Quantity used for tier lookup |

#### `QuoteLineItem`
| Field | Type | Description |
|---|---|---|
| `Has_Attribute_Adjustment__c` | Checkbox | Flags a line item as eligible for attribute-based pricing processing |

### 6.2.1 Field Mappings (Source → Target)
| Source | Target |
|---|---|
| `Attribute_Tier_Pricing_Storage__c.Tier_Value__c` | `SalesTransactionItem.Base_Price__c` (Context) |
| `Attribute_Tier_Pricing_Storage__c.Price_Mode__c` | `SalesTransactionItem.Attribute_Price_Mode__c` (Context) |
| `Attribute_Tier_Pricing_Storage__c.Multiplier__c` | `SalesTransactionItem.AttributeMultiplierPct__c` (Context) |
| `SalesTransactionItem.Base_Price__c` (Unit Price Mode) | `InputUnitPrice` (Pricing Procedure) |
| `Base_Price__c * AttributeMultiplierPct__c` (Calculated Mode) | `ItemNetTotalPrice` (Pricing Procedure) |
| `SalesTransactionItem.Base_Price__c` (Total Price Mode) | `ItemNetTotalPrice` (Pricing Procedure) |

### 6.3 Business Logic (exact rules)
- **Eligibility Filter:** only process line items where `Has_Attribute_Adjustment__c` = true. All others skipped without error.
- **Composite Key Construction:** keys built as **`ProductId|PSMId|AttrName|AttrValue`** (pipe-delimited concatenation) for direct map lookup without nested iteration.
- **Quantity Range Validation:** after a composite-key match, check line item quantity against tier's `Lower_Bound__c` and `Upper_Bound__c` in-memory. **Both bounds are inclusive.**
- **Unit Price Mode:** when `Attribute_Price_Mode__c` = `Unit Price` → pricing procedure assigns `Base_Price__c` directly to `InputUnitPrice` (per-unit price).
- **Calculated Mode:** when `Attribute_Price_Mode__c` = `Calculated` **AND `AttributeMultiplierPct__c` is not null** → `ItemNetTotalPrice = Base_Price__c × AttributeMultiplierPct__c`.
- **Total Price Mode:** when `Attribute_Price_Mode__c` = `Total Price` → assign `Base_Price__c` directly to `ItemNetTotalPrice` (fixed total **regardless of quantity**).
- **No-Match Behavior:** if no matching tier for a line item's attributes+quantity → **skip the line item entirely. No context attributes written, allowing standard pricing to apply as fallback.**
- **Delete Operation Handling:** when a line item is being deleted, context may not be updatable → **catch and return SUCCESS** so the delete completes without blocking.

### 6.4 Integration Points
- **Procedure Plan Definition:** pre-hook runs as **Section 3** of `Fortra_Pricing_PreHook`, invoked by RCA pricing orchestration during **quote save, reprice, and product addition** events.
- **Context Definition:** pre-hook **reads** from `SalesTransactionItem` (Product, ProductSellingModel, LineItemQuantity, HasAttributePricing) and `SalesTransactionItemAttribute` (all product attributes); **writes** to seven OUTPUT context attributes.
- **`Attribute_Tier_Pricing_Storage__c`:** pricing tier data source, queried with a single bulk SOQL using `IN` clauses on `Product__c` and `Product_Selling_Model__c`.
- **Pricing Procedure:** three downstream **List Operation** elements consume the context attributes, applying the calc per `Attribute_Price_Mode__c`.
- **`updateContextAttributes` API:** used to write pricing outputs. **Only attributes with hydration mappings in the Context Definition are included, to prevent silent batch failures.**

---

## 7. CODE-GOVERNING RULES (an engineer refactoring this MUST NOT violate)

1. **Single-SOQL guarantee (TR-001):** exactly ONE SOQL query against `Attribute_Tier_Pricing_Storage__c` per invocation, regardless of line item count. Collect all Product + PSM IDs in Pass 1, query once with `IN` clauses, then do all matching in-memory in Pass 2. Do NOT query per-line-item or per-attribute.
2. **Composite key format is fixed:** `ProductId|PSMId|AttrName|AttrValue` — pipe-delimited, in that exact order. Any change to key construction must be mirrored on both the map-build side and the lookup side.
3. **Quantity bounds are BOTH inclusive:** match requires `Lower_Bound__c <= qty <= Upper_Bound__c`. Do not make either bound exclusive.
4. **Quantity validation is in-memory only (TR-007):** never issue extra SOQL to validate the quantity range.
5. **Eligibility gate:** only process line items with `Has_Attribute_Adjustment__c` = true; skip all others silently (no error).
6. **Three price modes and their exact math (do not alter):**
   - `Unit Price` → `Base_Price__c` → `InputUnitPrice`.
   - `Calculated` → `ItemNetTotalPrice = Base_Price__c × AttributeMultiplierPct__c` (only when `AttributeMultiplierPct__c` is not null).
   - `Total Price` → `Base_Price__c` → `ItemNetTotalPrice` (fixed, quantity-independent).
7. **`AttributeMultiplierPct__c` is written ONLY for Calculated mode.** Do not populate it for Unit Price or Total Price.
8. **Multiplier requirement:** `Multiplier__c` is required when `Price_Mode__c` = `Calculated`; guard the null case (Calculated calc only runs when multiplier is not null).
9. **Dynamic attribute iteration (TR-002):** iterate ALL `SalesTransactionItemAttribute` tags; never hardcode attribute names. New attribute pricing rules must require zero code changes.
10. **No-match = no writes:** on no tier match, write NOTHING to context and skip the line item so standard/fallback pricing applies. Do not write defaults or zero out prices.
11. **Recursion prevention:** use the static Boolean flag `isUpdating`, set/reset inside a **try/finally** so it always clears even on exception. Do not remove this guard.
12. **Delete-state resilience (TR-005):** catch the non-updatable-context exception during delete operations and **return SUCCESS** — never throw/block the delete or the pricing pipeline.
13. **Return SUCCESS on all handled error conditions:** missing attributes, missing quantities, missing Product/PSM tags, no matching tiers, non-updatable context — log and return SUCCESS; never block pricing.
14. **`updateContextAttributes` batch hygiene:** include ONLY attributes that have hydration mappings in the Context Definition; including unmapped attributes causes silent batch failures.
15. **Ordering invariant:** the pre-hook MUST run as Section 3 of `Fortra_Pricing_PreHook` — after Regional (Section 1) and Partner (Section 2), before the main Price Procedure (Section 4). Do not reorder.
16. **No-overlap assumption (A-002):** logic assumes quantity ranges within the same Product/PSM/Attribute combination never overlap; the code picks a single tier on match and does not resolve overlaps. If overlaps become possible, this assumption (and code) must be revisited.
17. **Interface contract:** class implements `RevSignaling.SignalingApexProcessor`. `RevSignaling.TransactionRequest` is not mockable (A-007) — preserve `@TestVisible` seams for unit testing; rely on integration tests for end-to-end.
18. **Explainer/waterfall fields (TR-006):** on a successful apply, set `AttributePricingApplied__c` = true, plus `AttributePricingExplainer__c`, `Attribute_Feature__c` (`AttributeName: AttributeValue`), and `Attribute_Quantity__c`. Explainer example format: `Attr: Feature_Options=Platinum, Qty: 250, Base: $950.00 x 0.95`.

---

## 8. Notes / Open Items
- Rounding mode: **NOT specified** in the source document. The Calculated formula (`Base_Price__c × AttributeMultiplierPct__c`) gives no rounding rule — do not assume one; confirm before implementing.
- `Product_Selling_Model__c` type is stated as **"Lookup or Text field"** (unresolved in the design doc). Confirm the actual field type against the deployed org before writing SOQL / comparisons.
- The multiplier field is named `AttributeMultiplierPct__c` ("Pct") but is used as a plain multiplier (e.g. `x 0.95`), not a percentage divided by 100. Treat it as a raw multiplier per the example.
- This document is a **design spec only** — no Apex source is included. Verify the live implementation (`AttributeVolumePricingPrehook`) against these rules before refactoring; org source may differ/drift (see repo memory on Fortra source drift).
