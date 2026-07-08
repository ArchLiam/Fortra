# Fortra Pricing ARR — Solution Design

**Purpose:** Automatically calculate, track, and propagate Annual Recurring Revenue (ARR) across the Salesforce Revenue Cloud Advanced (RCA) quote-to-cash lifecycle (QuoteLineItem → OrderItem → Asset), plus Displaced ARR, Renewal ARR approvals, Amendment ARR impact, and product-hierarchy ARR reporting.

> Source: `Fortra-Pricing-ARR-Solution-Design-Doc.txt` (Pricing ARR Solution Design Document, prepared for Fortra). This KB is for an AI coding agent; values/formulas/field types are quoted verbatim from the source.

---

## Executive Summary

- ARR is calculated automatically **at the QuoteLineItem level** based on `ProductSellingModel` configuration, then propagated through OrderItems and Assets during order activation.
- Supports billing frequencies **Annual, Semi-Annual, Quarterly, Monthly**, all normalized to an **annualized** figure.
- Supports **Displaced ARR** tracking for product swap/upgrade scenarios (existing asset ARR captured, compared to new deal ARR for incremental value).
- **Renewal ARR approval workflows** provide management oversight of discount and credit scenarios that impact recurring revenue.
- **ARR Product Hierarchy Breakdown** enables reporting by Catalog, Category, and Sub-Category.
- Implemented **entirely declaratively** — Record-Triggered Flows, formula fields, roll-up summaries, standard reporting. **No custom Apex is required for ARR calculations.**
- **Context Definition mappings** carry ARR from Quote → Order → Asset.

### Key Features (verbatim intent)
- **Automatic ARR Calculation:** Before-save flow on QuoteLineItem calculates ARR based on `TotalLineAmount`, `PricingTermCount`, and `PricingTermUnit` from the ProductSellingModel; supports Annual, Semi-Annual, Quarterly, Monthly.
- **Quote-to-Asset ARR Propagation:** ARR flows from QuoteLineItem via Context Definition mappings to OrderItem during Q2O conversion, then to Asset via a record-triggered flow traversing the AssetAction/AssetActionSource chain.
- **Displaced ARR Tracking:** Formula field on QuoteLineItem pulls ARR from a linked Replaced Asset, with manual override via the Swap checkbox, rolled up to Quote level.
- **Renewal ARR Approval Workflows:** Dedicated approval criteria flows for Displaced ARR and Discount Renewal ARR scenarios, with justification fields and checkbox-based approval gating.
- **ARR Product Hierarchy Reporting:** Custom report type aggregating ARR by Catalog, Category, Sub-Category using product hierarchy fields on OpportunityLineItem.
- **Amendment ARR Impact:** Currency fields on both Quote and Contract track incremental ARR change from amendments; supports positive (upsell) and negative (downsell) values.

---

## Process Flow (Sequence)

1. **QuoteLineItem created/updated** with a `ProductSellingModel` assigned. Before-save flow queries the ProductSellingModel to determine `SellingModelType` and `PricingTermUnit`.
2. **ARR calculated:** `TotalLineAmount` divided by `PricingTermCount`, multiplied by the annualization factor (**1x Annual, 2x Semi-Annual, 4x Quarterly, 12x Monthly**). One-time products and missing selling models → ARR = **zero**.
3. **Store + roll up:** Calculated `Quote_Line_ARR__c` stored on QuoteLineItem. After-save flow on QuoteLineItem recalculates Quote-level `Total_ARR__c` by summing all line item ARR values. `Total_Displaced_ARR__c` roll-up summary aggregates displaced ARR from all lines.
4. **Q2O conversion:** Context Definition maps `Quote_Line_ARR__c` → `Order_Line_ARR__c` on OrderItem, preserving ARR through the transition.
5. **Activation/assetization:** `Fortra_Asset_Copy_ARR_From_OrderItem` flow fires on Asset create/update, traverses **Asset → AssetAction → AssetActionSource → OrderItem**, and copies `Order_Line_ARR__c` → `Asset.ARR__c`.
6. **Amendments:** `Original_Contract_ARR__c` formula pulls the contract's expected renewal amount; `Amendment_ARR_Impact__c` tracks incremental ARR change on both Quote and Contract.

---

## Business Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| BR-001 | Calculate ARR automatically on each Quote Line Item based on the product's selling model and billing frequency | High |
| BR-002 | Propagate ARR from Quote → Order → Asset across the full quote-to-cash lifecycle | High |
| BR-003 | Track Displaced ARR when an existing asset is replaced/upgraded, auto-pulling the existing asset's ARR | High |
| BR-004 | Provide approval workflows for quotes with Displaced ARR and Renewal ARR discounts/credits, with justification requirements | High |
| BR-005 | Display ARR breakdown by product hierarchy (Catalog, Category, Sub-Category) on Opportunities for executive reporting | Medium |
| BR-006 | Track Amendment ARR Impact on both Quotes and Contracts | Medium |
| BR-007 | Support multiple billing frequencies (Annual, Semi-Annual, Quarterly, Monthly) with correct annualization | High |

## Technical Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| TR-001 | Before-save record-triggered flow on QuoteLineItem to calculate ARR **without DML** for performance | High |
| TR-002 | Configure Context Definition field mappings for `Quote_Line_ARR__c` → `Order_Line_ARR__c` during Q2O | High |
| TR-003 | Asset-triggered flow to traverse AssetAction/AssetActionSource to copy ARR from OrderItem to Asset | High |
| TR-004 | Change `Quote_Line_ARR__c` **from formula field to currency field** to support flow-based calc + roll-up aggregation | High |
| TR-005 | Create Product2 hierarchy fields (`Primary_Catalog_Name__c`, `Primary_Category_Name__c`, `Parent_Category_Name__c`), maintained by Product Management | Medium |
| TR-006 | Null safety in all ARR formulas: null `PricingTermCount`, zero `PricingTermCount`, null `TotalLineAmount`, and missing `ProductSellingModel` all → ARR = zero | High |

---

## Data Model (every named field, with TYPE)

### QuoteLineItem
| Field | Type | Description |
|-------|------|-------------|
| `Quote_Line_ARR__c` | **Currency** | Calculated ARR for this line item; computed by the before-save flow. **(Converted from formula → currency — see A-002/TR-004.)** |
| `Displaced_ARR__c` | **Formula** | Displaced ARR from linked Replaced Asset's `ARR__c` or manual `Displaced_ARR_Input__c` value |
| `Replaced_Asset__c` | **Lookup(Asset)** | Asset being replaced/upgraded by this line; used to auto-calc Displaced ARR |
| `Displaced_ARR_Input__c` | (manual entry field; used as fallback) | Manual displaced-ARR entry, used when no `Replaced_Asset__c` and `Swap__c` = true |
| `Swap__c` | **Checkbox** | When true, enables manual `Displaced_ARR_Input__c` fallback for displaced ARR |

### Quote
| Field | Type | Description |
|-------|------|-------------|
| `Total_ARR__c` | **Currency** | Sum of all QuoteLineItem ARR values; updated by after-save flow |
| `Total_Displaced_ARR__c` | **Roll-Up Summary** | Aggregates `Displaced_ARR__c` from all QuoteLineItems |
| `Displaced_ARR__c` | **Currency** | Quote-level displaced ARR value |
| `Displaced_ARR_Approval__c` | **Checkbox** | Set by approval-criteria flow when Displaced ARR > 0 |
| `Displaced_ARR_Justification__c` | **Long Text Area** | Business justification for displaced ARR |
| `Credit_Renewal_ARR__c` | **Checkbox** | Whether this quote involves a credit to renewal ARR |
| `Credit_Renewal_ARR_Justification__c` | **Long Text Area** | Justification for renewal ARR credit |
| `Discount_Renewal_ARR__c` | **Checkbox** | Whether this quote involves a discount on renewal ARR |
| `Discount_Renewal_ARR_Justification__c` | **Long Text Area** | Justification for renewal ARR discount |
| `Discount_Renewal_ARR_Request__c` | **Percent** | Requested renewal ARR discount percentage |
| `Renewal_ARR_Approval__c` | **Checkbox** | Set by approval-criteria flow for renewal ARR discount/credit scenarios |
| `Renewal_ARR_Credit_Amount__c` | **Currency** | Credit amount applied to renewal ARR |
| `Amendment_ARR_Impact__c` | **Currency** | Incremental ARR change from this amendment quote (positive = upsell, negative = downsell) |
| `Original_Contract_ARR__c` | **Formula** | Pulls Expected Renewal Amount from the linked Renewal Contract to show pre-amendment ARR |

### OrderItem
| Field | Type | Description |
|-------|------|-------------|
| `Order_Line_ARR__c` | **Currency** | Populated from `QuoteLineItem.Quote_Line_ARR__c` via Context Definition during Q2O |
| `Displaced_ARR__c` | **Currency** | Displaced ARR on the order line; **divided evenly across split lines when order lines are split** |

### AssetActionSource
| Field | Type | Description |
|-------|------|-------------|
| `Order_Line_ARR__c` | **Currency** | Intermediate field receiving ARR from OrderItem during activation; used in the asset ARR copy chain |

### Asset
| Field | Type | Description |
|-------|------|-------------|
| `ARR__c` | **Currency** | Final ARR value, copied from `OrderItem.Order_Line_ARR__c` via the Asset Copy ARR flow |

### Contract
| Field | Type | Description |
|-------|------|-------------|
| `Contract_ARR__c` | **Currency** | Total ARR for this contract |
| `Amendment_ARR_Impact__c` | **Currency** | Net ARR change from contract amendments |
| `Expected_Ren_Amount__c` | (referenced) | Source for `Quote.Original_Contract_ARR__c` (via `Renewal_Contract__r` formula) |

### Product2 (hierarchy fields, manually maintained by Product Management)
| Field | Type | Description |
|-------|------|-------------|
| `Primary_Category_Name__c` | **Text** | Primary product category name for ARR hierarchy reporting |
| `Primary_Catalog_Name__c` | **Text** | Primary product catalog name for ARR hierarchy reporting |
| `Parent_Category_Name__c` | **Text** | Parent category name when product is in a sub-category |
| `Product_Selling_Model_Type__c` | **Text** | Product's selling model type (**OneTime, TermDefined, or Evergreen**) for ARR calculation eligibility |

### Standard/platform fields consumed
- `ProductSellingModel.SellingModelType` — values **OneTime, TermDefined, Evergreen**
- `ProductSellingModel.PricingTermUnit` — values **Annual, Semi-Annual, Quarterly, Months** (note: source uses "Months"/"Monthly" interchangeably)
- `QuoteLineItem.TotalLineAmount`, `QuoteLineItem.PricingTermCount`, `QuoteLineItem.ProductSellingModelId`
- `AssetActionSource.ReferenceEntityItemId` — points to source OrderItem

### Field Mapping Chain (verbatim)
| Source Field | Target Field |
|--------------|--------------|
| `QuoteLineItem.Quote_Line_ARR__c` | `OrderItem.Order_Line_ARR__c` |
| `OrderItem.Order_Line_ARR__c` | `AssetActionSource.Order_Line_ARR__c` |
| `OrderItem.Order_Line_ARR__c` | `Asset.ARR__c` |
| `Asset.ARR__c` | `QuoteLineItem.Displaced_ARR__c` (via `Replaced_Asset__c` lookup) |
| `Contract.Expected_Ren_Amount__c` | `Quote.Original_Contract_ARR__c` (via `Renewal_Contract__r` formula) |

---

## Business Logic (exact formulas + edge cases)

**ARR calculation by `PricingTermUnit`** (annualization factor applied to `TotalLineAmount / PricingTermCount`):

- **Annual (1x):** `TotalLineAmount / PricingTermCount`
  - Example: 3-year annual subscription of $36,000 → `36000 / 3 = $12,000`.
- **Semi-Annual (2x):** `(TotalLineAmount / PricingTermCount) * 2`
- **Quarterly (4x):** `(TotalLineAmount / PricingTermCount) * 4`
- **Monthly (12x):** `(TotalLineAmount / PricingTermCount) * 12`

**Null / zero safety (TR-006, A-001):**
- `PricingTermCount` null **or zero** → ARR = **0** (prevents division-by-zero).
- `TotalLineAmount` null → ARR = **0**.
- Missing `ProductSellingModel` → ARR = **0**.
- `SellingModelType` = **OneTime** → ARR = **0**. (Only `TermDefined` / `Evergreen` generate ARR.)

**Displaced ARR logic (`QuoteLineItem.Displaced_ARR__c` formula):**
1. If `Replaced_Asset__c` set → pull `Asset.ARR__c`.
2. Else if `Swap__c` = true → use manual `Displaced_ARR_Input__c`.
3. Else → **0**.

**Displaced ARR approval trigger:** When `Quote.Displaced_ARR__c > 0`, the approval-criteria flow sets `Displaced_ARR_Approval__c` = true and displays a submission confirmation screen.

**Asset ARR copy conditions (idempotency guard):** The flow updates `Asset.ARR__c` **only when** the source `OrderItem.Order_Line_ARR__c` is **not null AND differs from** the current `Asset.ARR__c` — preventing unnecessary DML.

**Order-line split behavior:** `OrderItem.Displaced_ARR__c` is **divided evenly across split lines** when order lines are split.

> Rounding mode: **not specified** in the source document.

---

## Components

| Component | Type | Responsibility |
|-----------|------|----------------|
| `Fortra_QuoteLineItem_Calculate_ARR` | **Record-Triggered Flow (Before Save)** | Triggers on QuoteLineItem create/update when `ProductSellingModelId` is not null. Queries ProductSellingModel for `SellingModelType` + `PricingTermUnit`, applies annualization formula → `Quote_Line_ARR__c`. OneTime/missing model → 0. **No DML (before-save).** |
| `Fortra_Quote_Line_Item_Calculate_Total_ARR` | **Record-Triggered Flow (After Save)** | On QuoteLineItem save: queries all line items for parent Quote, loops computing ARR by selling-model type, updates `Quote.Total_ARR__c` with the aggregate. |
| `Fortra_Asset_Copy_ARR_From_OrderItem` | **Record-Triggered Flow (After Save)** | On Asset create/update: traverses Asset → AssetAction → AssetActionSource, uses `ReferenceEntityItemId` to find source OrderItem, copies `Order_Line_ARR__c` → `Asset.ARR__c`. **Runs in System Mode Without Sharing** for cross-object access. |
| `Fortra_Quote_Displaced_ARR_Approval_Criteria` | **Screen Flow** | Checks if Quote Displaced ARR > 0; sets `Displaced_ARR_Approval__c` for approval routing. |
| `Fortra_Quote_Discount_Renewal_ARR_Approval_Criteria` | **Screen Flow** | Evaluates renewal ARR discount/credit scenarios; sets `Renewal_ARR_Approval__c` for approval routing. |
| `Fortra_Opportunity_Line_Item_Calculate_Total_ARR` | **Record-Triggered Flow** | Calculates Total ARR on Opportunity from OpportunityLineItem values using product selling model type. |
| `Fortra ARR Report Type` | **Custom Report Type** | "Opportunities with Products" report type incl. Catalog, Category, Sub-Category hierarchy fields for ARR analysis. |
| Context Definition Mapping | **Configuration** | Maps `QuoteLineItem.Quote_Line_ARR__c` → `OrderItem.Order_Line_ARR__c` during Q2O conversion. |

---

## Integration Points & Sequence

- **Context Definition (Q2O):** `Quote_Line_ARR__c` → `Order_Line_ARR__c` through the RCA Context Definition during `Fortra_Quote_to_Order_Conversion` flow execution.
- **Assetization Chain:** The `createOrUpdateAssetFromOrder` standard action creates AssetAction + AssetActionSource records. `Fortra_Asset_Copy_ARR_From_OrderItem` locates the source OrderItem via `AssetActionSource.ReferenceEntityItemId`.
- **Product Selling Model:** ARR calc queries the standard `ProductSellingModel` object at runtime for `SellingModelType` (OneTime, TermDefined, Evergreen) and `PricingTermUnit` (Annual, Semi-Annual, Quarterly, Months).
- **Revenue Lifecycle Management (RLC/RLM):** Assets created through the RLC-managed order activation pipeline automatically have the AssetAction/AssetActionSource chain the ARR copy flow depends on.

---

## Assumptions

| ID | Assumption |
|----|-----------|
| A-001 | All recurring-revenue products have a ProductSellingModel with `SellingModelType` = TermDefined or Evergreen. No model / OneTime → ARR = 0. |
| A-002 | `Quote_Line_ARR__c` has been converted **from formula field to currency field** to allow flow-based calc + roll-up usage. |
| A-003 | Context Definition mappings (`Quote_Line_ARR__c` → `Order_Line_ARR__c`) are configured in **both DP2 and UAT** environments. |
| A-004 | Product2 hierarchy fields (`Primary_Catalog_Name__c`, `Primary_Category_Name__c`, `Parent_Category_Name__c`, `Product_Selling_Model_Type__c`) are **manually maintained by Fortra Product Management**. |
| A-005 | Assetization creates AssetAction/AssetActionSource with `ReferenceEntityItemId` pointing to source OrderItem, enabling ARR-copy traversal. |
| A-006 | Displaced ARR uses `ARR__c` on the replaced Asset. If no `Replaced_Asset__c`, `Swap__c` + `Displaced_ARR_Input__c` are the fallback. |

## Dependencies

**Internal (all status = Complete):**
- D-001: ProductSellingModel config with correct `SellingModelType` + `PricingTermUnit` for all subscription products.
- D-002: Context Definition field mapping `Quote_Line_ARR__c` → `Order_Line_ARR__c` in Q2O flow.
- D-003: Assetization flow `Fortra_Assetize_Order` creating Assets with proper AssetAction/AssetActionSource chain.
- D-004: Q2O conversion flow `Fortra_Quote_to_Order_Conversion` that triggers Context Definition mappings.
- D-005: Contract object config with `Contract_ARR__c` and `Amendment_ARR_Impact__c` fields.

**External:**
- E-001: Fortra Product Management — maintains product hierarchy fields on Product2.
- E-002: Fortra Sales Operations — defines approval thresholds for Displaced ARR and Renewal ARR discount scenarios.

**Open issues:** None explicitly enumerated. Rounding mode unspecified. "Monthly" vs `PricingTermUnit` value "Months" naming inconsistency in source.

---

## CODE-GOVERNING RULES (do not violate when refactoring)

1. **ARR annualization factors are fixed by `PricingTermUnit`:** Annual = 1x, Semi-Annual = 2x, Quarterly = 4x, Monthly/Months = 12x. Base expression is always `TotalLineAmount / PricingTermCount`, then multiplied by the factor. Do not alter these multipliers.
2. **ARR = 0 for all of:** `SellingModelType` = OneTime; missing/null ProductSellingModel; null `TotalLineAmount`; null OR zero `PricingTermCount`. Never divide when `PricingTermCount` is null/0 (division-by-zero guard is mandatory — TR-006, A-001).
3. **`Quote_Line_ARR__c` MUST remain a Currency field, not a formula** (TR-004, A-002). Roll-up summaries and flow writes depend on this. Do not revert it to a formula field.
4. **ARR line calc MUST stay on a before-save flow with no DML** (TR-001) — `Fortra_QuoteLineItem_Calculate_ARR`, triggered on create/update only when `ProductSellingModelId` is not null.
5. **ARR propagation chain is mapping-only, no custom Apex:** `QuoteLineItem.Quote_Line_ARR__c` → (Context Def) `OrderItem.Order_Line_ARR__c` → `AssetActionSource.Order_Line_ARR__c` / `Asset.ARR__c`. Preserve every hop; the entire ARR feature is declarative-only.
6. **Asset ARR copy traverses exactly Asset → AssetAction → AssetActionSource → OrderItem**, resolving the OrderItem via `AssetActionSource.ReferenceEntityItemId`, copying `OrderItem.Order_Line_ARR__c` → `Asset.ARR__c`. The copy flow **runs in System Mode Without Sharing**.
7. **Asset ARR copy idempotency guard:** update `Asset.ARR__c` **only when** source `Order_Line_ARR__c` is not null AND differs from current `Asset.ARR__c`. Do not remove this guard (prevents unnecessary DML).
8. **Displaced ARR precedence is strict:** (1) `Replaced_Asset__c` → `Asset.ARR__c`; else (2) `Swap__c` true → `Displaced_ARR_Input__c`; else (3) 0. Preserve this order.
9. **Displaced ARR approval gating:** `Quote.Displaced_ARR__c > 0` ⇒ set `Displaced_ARR_Approval__c` = true (and show confirmation screen). Renewal ARR discount/credit scenarios set `Renewal_ARR_Approval__c`. Do not change the checkbox names or the trigger condition.
10. **`OrderItem.Displaced_ARR__c` is divided EVENLY across split lines** when order lines split. Preserve even distribution on any order-splitting refactor.
11. **`Amendment_ARR_Impact__c` (Quote and Contract) is signed:** positive = upsell, negative = downsell. Do not clamp to non-negative.
12. **`Original_Contract_ARR__c` is a formula** pulling `Contract.Expected_Ren_Amount__c` via `Renewal_Contract__r`. Keep it a formula sourced from the renewal contract.
13. **Product2 hierarchy fields are human-maintained** (`Primary_Catalog_Name__c`, `Primary_Category_Name__c`, `Parent_Category_Name__c`, `Product_Selling_Model_Type__c`). Do not auto-overwrite them in code; ARR hierarchy reporting reads them as-is.
14. **`Product_Selling_Model_Type__c` allowed values are exactly OneTime, TermDefined, Evergreen** — mirror ProductSellingModel `SellingModelType`.
15. **Context Definition mappings must exist in BOTH DP2 and UAT** (A-003). Any new ARR mapping must be deployed to both environments.
