# Orders Configuration — Solution Design (RCA KB)

**Purpose:** Establish the foundational Salesforce Revenue Cloud Advanced (RCA) infrastructure for Fortra's Quote-to-Order conversion pipeline — Order Type value set, Sales Transaction Type config, Legal Entity propagation, custom OrderItem/Order fields, Field-Level Security across permission sets, Asset-to-Contract relationship automation, and a Fortra Product Type global value set for partner-pricing categorization.

> Source: `Fortra-Orders-Configuration-Solution-Design-Doc.txt`. This is a design document; class/field/flow names below are as named in the design. Verify against live Apex/metadata before refactoring. This solution is **foundational plumbing** — its outputs (Order fields, OrderItem fields, Legal Entity, ACRs) are consumed by downstream solutions (assetization, billing schedules, contract lifecycle, Power line splitting, partner pricing).

---

## 1. Executive Summary

This configuration package must be deployed **before** downstream processes (assetization, billing schedules, contract lifecycle management) can operate. Without it, Quote-to-Order conversion fails or produces incomplete Order records. Deployed across both **fortradp2** (development/sandbox) and **fortrauat** (UAT) environments; verified via automated deployment scripts and **SOQL-based permission verification queries**.

### 1.1 Key Features (verbatim specifics)
- **Order Type standard value set** with six transaction types: **New, Upsell, Renewal, Amendment, Cancellation, Net-New**.
- **Legal Entity propagation flow** — automatically copies `LegalEntityId` from Quote to QuoteLineItem during line-item creation (only when QLI `LegalEntityId` is null), ensuring proper downstream mapping to OrderItem.
- **`AssetContractLinkerAction`** invocable Apex class — creates `AssetContractRelationship` records after Order assetization, linking Assets to their parent Contract with proper RLM `AppUsageAssignment`.
- **Custom OrderItem fields** for subscription date calculations (`Year_After_StartDate__c`, `Two_Years_After_Start_Date__c`), Power product line splitting (`Is_Split_Line__c`, `Original_Order_Item__c`), and Partition tracking (`Partition_Record__c`).
- **Field-Level Security** deployed across three permission sets (`Order_Field_Access`, `Revenue_Cloud_Admin`, `Revenue_Cloud_Base`) granting Read/Edit on six custom Order fields.
- **Fortra Product Type global value set** picklist on QuoteLineItem for partner-pricing margin determination.
- **Sales Transaction Type** configuration integrated with the Quote-to-Order Conversion flow.

---

## 2. Solution Overview

### 2.1 Process Flow Summary (sequence, verbatim)
1. Administrator configures Order Types (New, Upsell, Renewal, Amendment, Cancellation, Net-New) via standard value set deployment — defines the transaction lifecycle categories.
2. **Sales Transaction Type** is configured and referenced by the `Fortra_Quote_to_Order_Conversion` flow to determine Order decomposition behavior during conversion.
3. When a QuoteLineItem is created, the `Fortra_QuoteLineItem_Legal_Entity_Copy` flow automatically copies the parent Quote's `LegalEntityId` to the line item — **only when QLI `LegalEntityId` is null**.
4. During Quote-to-Order conversion, the **Context Definition mapping** transfers `QuoteLineItem.LegalEntityId → OrderItem.LegalEntityId`, along with custom fields like `Fortra_Product_Type__c`.
5. Custom OrderItem fields (`Year_After_StartDate__c`, `Two_Years_After_Start_Date__c`, `Is_Split_Line__c`, `Original_Order_Item__c`, `Partition_Record__c`) support downstream subscription calculations, line splitting, and partition management.
6. After Order activation and assetization, `AssetContractLinkerAction` creates `AssetContractRelationship` records linking newly created Assets to the Order's parent Contract.
7. Field-Level Security permissions deployed to `Order_Field_Access`, `Revenue_Cloud_Admin`, `Revenue_Cloud_Base` — Read/Edit on Order summary fields (`Total_Services__c`, `Quote_Type__c`, `Total_Subscription__c`, `Total_Software__c`, `Deal_Type__c`, `GSW__c`).

### 2.2 Solution Components (verbatim table)
| Component | Type | Description |
|-----------|------|-------------|
| **OrderType StandardValueSet** | Standard Value Set | Defines six Order Type picklist values: New, Upsell, Renewal, Amendment, Cancellation, Net-New |
| **`Fortra_QuoteLineItem_Legal_Entity_Copy`** | Record-Triggered Flow | After-create flow on QuoteLineItem that copies `Quote.LegalEntityId` to QLI when null |
| **`Fortra_Quote_to_Order_Conversion`** | Screen Flow | Quote-to-Order conversion flow referencing Sales Transaction Type configuration |
| **`AssetContractLinkerAction`** | Apex Invocable Action | Creates `AssetContractRelationship` records linking Order-derived Assets to the parent Contract |
| **`AssetContractLinkerActionTest`** | Apex Test Class | Test coverage for `AssetContractLinkerAction` invocable method |
| **`Fortra_Product_Type__c` (QLI)** | Custom Picklist Field | Global value set picklist on QuoteLineItem for partner pricing product-type categorization |
| **OrderItem Custom Fields** | Custom Fields (5) | `Year_After_StartDate__c`, `Two_Years_After_Start_Date__c`, `Is_Split_Line__c`, `Original_Order_Item__c`, `Partition_Record__c` |
| **`Order_Field_Access`** | Permission Set | Grants Read/Edit FLS on 6 custom Order fields for standard users |
| **`Revenue_Cloud_Admin`** | Permission Set | Grants Read/Edit FLS on 6 custom Order fields for Revenue Cloud administrators |
| **`Revenue_Cloud_Base`** | Permission Set | Grants Read/Edit FLS on 6 custom Order fields for Revenue Cloud base users |
| **`OrderItem_Field_Access`** | Permission Set | Grants FLS access to custom OrderItem fields including pricing and attribute fields |

---

## 3. Requirements

### 3.1 Business Requirements (verbatim)
| ID | Requirement | Priority |
|----|-------------|----------|
| BR-001 | Support six Order Types (New, Upsell, Renewal, Amendment, Cancellation, Net-New) to categorize transactions throughout the revenue lifecycle | High |
| BR-002 | Automatically propagate Legal Entity from Quote to QuoteLineItem to ensure proper currency and entity assignment on Order Products after conversion | High |
| BR-003 | Create Asset-to-Contract relationships automatically after Order assetization to support Revenue Lifecycle Management | High |
| BR-004 | Track subscription date boundaries on Order Products to support year-based pricing and configuration rules | Medium |
| BR-005 | Support Power product line splitting by tracking original Order Item references and split line indicators | Medium |
| BR-006 | Categorize products by Fortra Product Type on Quote Line Items to determine applicable partner pricing margins | Medium |
| BR-007 | Ensure all Revenue Cloud users have appropriate field-level access to Order summary fields (Total Services, Total Subscription, Total Software, Deal Type, Quote Type, GSW) | High |

### 3.2 Technical Requirements (verbatim)
| ID | Requirement | Priority |
|----|-------------|----------|
| TR-001 | Deploy OrderType standard value set with six values maintaining **`sorted=false`** ordering for UI consistency | High |
| TR-002 | Implement record-triggered flow on QuoteLineItem (after create) with entry condition **`LegalEntityId IS NULL`** to prevent overwriting API-set values | High |
| TR-003 | Build invocable Apex action (`AssetContractLinkerAction`) that traces Asset lineage through **AssetAction and AssetActionSource** to find Order-derived Assets | High |
| TR-004 | Ensure `AssetContractLinkerAction` creates **`AppUsageAssignment` (RevenueLifecycleManagement)** on Contract if not already present before creating ACR records | High |
| TR-005 | Create formula fields (`Year_After_StartDate__c`, `Two_Years_After_Start_Date__c`) on OrderItem using **`EndDate` minus `ServiceDate`** calculations | Medium |
| TR-006 | Deploy Field-Level Security across three permission sets using Metadata API, with **SOQL-based verification** for permission sets that cannot be retrieved via standard metadata retrieval | High |
| TR-007 | Configure `Fortra_Product_Type` global value set picklist on QuoteLineItem with **field history tracking enabled** | Medium |
| TR-008 | Maintain **API version 64.0/65.0** compatibility across all metadata components | Low |

---

## 4. Data Model

### 4.1 `Order` (standard object + custom fields)
| Field | Type | Notes / Verbatim Description |
|-------|------|------------------------------|
| `Type` | Standard picklist | Configured with **New, Upsell, Renewal, Amendment, Cancellation, Net-New** values |
| `Total_Services__c` | Custom currency | Total services amount on the Order |
| `Quote_Type__c` | Custom field | Stores the originating Quote type classification |
| `Total_Subscription__c` | Custom currency | Total subscription amount on the Order |
| `Total_Software__c` | Custom currency | Total software amount on the Order |
| `Deal_Type__c` | Custom field | Categorizes the deal type for reporting and analytics |
| `GSW__c` | Custom field | GSW (**Global Software Waterfall**) tracking |

> These six custom Order fields (`Total_Services__c`, `Quote_Type__c`, `Total_Subscription__c`, `Total_Software__c`, `Deal_Type__c`, `GSW__c`) are the FLS targets across the three permission sets.

### 4.2 `OrderItem` (standard object + custom fields — the 5 deployed)
| Field | Type | Notes / Verbatim Description |
|-------|------|------------------------------|
| `Year_After_StartDate__c` | Formula (Checkbox) | **true if `EndDate` minus `ServiceDate` is 365 days or less (first year)** |
| `Two_Years_After_Start_Date__c` | Formula (Checkbox) | true if subscription is within two years of start date |
| `Is_Split_Line__c` | Checkbox (default false) | Indicates this line was created by Power product line splitting |
| `Original_Order_Item__c` | Lookup(OrderItem) | References the original line before splitting; **`SetNull` on delete** |
| `Partition_Record__c` | Lookup(`Partition__c`) | For Power product partition configuration tracking |

### 4.3 `QuoteLineItem` (standard object + fields used)
| Field | Type | Notes / Verbatim Description |
|-------|------|------------------------------|
| `LegalEntityId` | Standard lookup | Populated by flow from parent `Quote.LegalEntityId` |
| `Fortra_Product_Type__c` | Global value set picklist | Product-type categorization (partner pricing); **field history tracking enabled** (TR-007) |

### 4.4 `AssetContractRelationship` (ACR — junction object)
| Field | Type | Notes / Verbatim Description |
|-------|------|------------------------------|
| `AssetId` / `ContractId` | (junction keys) | Created by `AssetContractLinkerAction` linking Assets to Contracts |
| `StartDate` | Date | Set from `Contract.StartDate` |
| `EndDate` | Date | Set from `Contract.EndDate` |

### 4.5 Field Mappings (verbatim source→target)
| Source Field | Target Field |
|--------------|--------------|
| `Quote.LegalEntityId` | `QuoteLineItem.LegalEntityId` (via **Flow**) |
| `QuoteLineItem.LegalEntityId` | `OrderItem.LegalEntityId` (via **Context Definition**) |
| `QuoteLineItem.Fortra_Product_Type__c` | `OrderItem.Fortra_Product_Type__c` (via **Context Definition**) |
| `Order.ContractId` | `AssetContractRelationship.ContractId` (via `AssetContractLinkerAction`) |
| `OrderItem` (via AssetActionSource) | `AssetContractRelationship.AssetId` (via `AssetContractLinkerAction`) |
| `Contract.StartDate` | `AssetContractRelationship.StartDate` |
| `Contract.EndDate` | `AssetContractRelationship.EndDate` |

---

## 5. Business Logic (exact rules, formulas, edge cases)

### 5.1 Legal Entity Copy Flow (`Fortra_QuoteLineItem_Legal_Entity_Copy`)
- Record-triggered **after-create** flow on QuoteLineItem.
- **Entry condition: `LegalEntityId IS NULL`** — prevents overwriting programmatically/API-set values.
- Retrieves the parent Quote via **`$Record.QuoteId`**, checks if the Quote has a `LegalEntityId`, and copies it to the QuoteLineItem **only if present**.
- **Supports bulk creation** of multiple QLIs.
- Must run **before** the Context Definition mapping executes during conversion (it populates `LegalEntityId` on the QLI so the QLI→OrderItem mapping has a value to carry).

### 5.2 `AssetContractLinkerAction` (invocable)
- Invocable method called by the `Fortra_Assetize_Order` flow **after** the standard `createOrUpdateAssetFromOrder` action completes; the flow passes the **Order ID** to the action.
- **Traces Asset lineage** through the chain: **`Order > OrderItem > AssetActionSource > AssetAction > Asset`** to discover Order-derived Assets.
- **Ensures the Contract has an RLM `AppUsageAssignment`** (RevenueLifecycleManagement) **before** creating ACRs — creates it if not already present.
- **Idempotent:** skips Assets that already have an ACR to the same Contract.
- Sets ACR **`StartDate` from `Contract.StartDate`** and **`EndDate` from `Contract.EndDate`**.
- **Orders without a Contract (`ContractId` not populated) are silently skipped** (A-004).

### 5.3 Subscription Date Formulas
- `Year_After_StartDate__c` evaluates **`EndDate` minus `ServiceDate` <= 365** to determine first-year subscriptions (formula checkbox → true).
- `Two_Years_After_Start_Date__c` uses **similar logic for two-year boundaries** (within two years of start date).
- These formulas support **configuration rules and pricing logic** downstream.

### 5.4 Line Splitting Support
- `Is_Split_Line__c` — checkbox, **default false**; marks OrderItems created from Power product splitting.
- `Original_Order_Item__c` — lookup(OrderItem), **`SetNull` on delete**; references the parent line before split.
- Together they enable tracking/reporting on split order lines and are consumed by `PowerOrderSplittingService`.

### 5.5 Permission Set Strategy (three-tier)
- Three-tier permission model grants Order field access at **base, admin, and field-specific levels** (`Revenue_Cloud_Base`, `Revenue_Cloud_Admin`, `Order_Field_Access`).
- `Revenue_Cloud_Admin` and `Revenue_Cloud_Base` are part of **Permission Set Groups** requiring **manual FLS configuration through the Salesforce UI** due to Metadata API retrieval limitations (A-005, E-003).

---

## 6. Components (Apex / flows / metadata + responsibility)

| Component | Type | Responsibility |
|-----------|------|----------------|
| `AssetContractLinkerAction` | Apex Invocable Action | Traces Order→Asset lineage, ensures Contract `AppUsageAssignment`, creates idempotent ACRs with Contract-derived Start/End dates |
| `AssetContractLinkerActionTest` | Apex Test Class | Coverage for the invocable method |
| `Fortra_QuoteLineItem_Legal_Entity_Copy` | Record-Triggered Flow (after-create, QLI) | Copies `Quote.LegalEntityId → QLI.LegalEntityId` when QLI `LegalEntityId` is null; bulk-safe |
| `Fortra_Quote_to_Order_Conversion` | Screen Flow | Q2O conversion; references Sales Transaction Type to determine Order decomposition |
| `OrderType` | Standard Value Set | Six Order Type picklist values; `sorted=false` |
| `Fortra_Product_Type__c` | Custom Picklist Field (QLI) | Global-value-set-backed; partner-pricing categorization; field history tracking on |
| OrderItem custom fields (×5) | Custom Fields | Subscription-date formulas, split-line tracking, partition lookup |
| `Order_Field_Access` / `Revenue_Cloud_Admin` / `Revenue_Cloud_Base` | Permission Sets | FLS Read/Edit on 6 custom Order fields |
| `OrderItem_Field_Access` | Permission Set | FLS on custom OrderItem fields (pricing + attribute) |

### 6.1 Deployment Package Architecture (seven modular packages)
Each package is independently deployable with its own `sfdx-project.json` and `package.xml` manifest (enables targeted deploys/rollbacks):
1. **`acr-automation-deploy`** — `AssetContractLinkerAction` Apex class + test class. Follows the Order-to-Asset lineage chain (`Order > OrderItem > AssetActionSource > AssetAction > Asset`) and creates ACRs with Contract-derived start/end dates.
2. **`context-def-fields-deploy`** — Permission-set metadata + **Python-based build scripts** generating FLS configs. Includes `Order_Field_Access`, `Revenue_Cloud_Admin`, `Revenue_Cloud_Base` with **SOQL-based verification queries**.
3. **`field-gvs-deploy`** — `Fortra_Product_Type__c` picklist field on QuoteLineItem, referencing the `Fortra_Product_Type` global value set.
4. **`order-type-deploy`** — `OrderType` standard value set (six transaction types) as a StandardValueSet metadata component.
5. **`order-type-flow-deploy`** — `Fortra_Quote_to_Order_Conversion` flow referencing Sales Transaction Type.
6. **`orderitem-fields-deploy`** — five custom OrderItem fields + an `OrderItem_Field_Access` permission set.
7. **`sales-transaction-type-deploy`** — Sales Transaction Type configuration + related flow/field metadata for Q2O.

---

## 7. Integration Points & Sequence

- **`Fortra_Assetize_Order` Flow:** invokes `AssetContractLinkerAction` **after** the standard `createOrUpdateAssetFromOrder` action; passes the Order ID.
- **Context Definition (`FortraSalesTransactionContext`):** defines QLI→OrderItem field mappings (incl. `LegalEntityId`, `Fortra_Product_Type__c`) consumed by the Q2O conversion. The Legal Entity Copy flow ensures `LegalEntityId` is on the QLI **before** this mapping runs.
- **Revenue Lifecycle Management (RLM):** `AssetContractLinkerAction` creates `AppUsageAssignment` records to enable RLM on Contracts, and creates ACRs required for downstream contract lifecycle ops (**amendments, renewals, cancellations**).
- **Power Order Line Splitting Service (`PowerOrderSplittingService`):** consumes `Is_Split_Line__c` and `Original_Order_Item__c` on OrderItem when splitting multi-quantity Power product lines into individual **quantity-1** lines.

---

## 8. Assumptions / Dependencies / Open Issues

### 8.1 Assumptions (verbatim)
- **A-001** RCA is enabled and properly licensed in all target environments.
- **A-002** The `FortraSalesTransactionContext` Context Definition is already configured with QLI→OrderItem field mappings including `LegalEntityId`.
- **A-003** The `Fortra_Assetize_Order` flow exists and calls `AssetContractLinkerAction` **after** the `createOrUpdateAssetFromOrder` standard action.
- **A-004** Orders will have a `ContractId` populated when `AssetContractLinkerAction` is invoked; **Orders without a Contract are silently skipped**.
- **A-005** Permission Set Groups (`Revenue_Cloud_Admin`, `Revenue_Cloud_Base`) require **manual FLS configuration through the Salesforce UI** due to metadata API retrieval limitations.
- **A-006** The `Partition__c` custom object exists and is available for the `Partition_Record__c` lookup on OrderItem.
- **A-007** The `Fortra_Product_Type` global value set is already defined in the org with the appropriate picklist values.
- **A-008** Users accessing Order records will be assigned at least one of the three permission sets (`Order_Field_Access`, `Revenue_Cloud_Admin`, or `Revenue_Cloud_Base`).

### 8.2 Internal Dependencies (all status **Complete**)
- **D-001** `FortraSalesTransactionContext` Context Definition with QLI→OrderItem field mappings.
- **D-002** `Fortra_Assetize_Order` flow for post-activation asset creation.
- **D-003** `Fortra_Quote_to_Order_Conversion` flow using Sales Transaction Type.
- **D-004** `Partition__c` custom object for Power product partition tracking.
- **D-005** `Fortra_Product_Type` global value set for product categorization.
- **D-006** Quote-to-Order conversion process requiring Legal Entity on OrderItem.
- **D-007** Power Order Line Splitting service requiring `Is_Split_Line__c` and `Original_Order_Item__c` fields.

### 8.3 External Dependencies
- **E-001** RCA platform with RLM capabilities — *Owner: Salesforce*.
- **E-002** `LegalEntity` standard object and related configuration — *Owner: Fortra Admin Team*.
- **E-003** Permission Set Group config for `Revenue_Cloud_Admin` and `Revenue_Cloud_Base` (manual FLS steps) — *Owner: Fortra Admin Team*.

### 8.4 Open Issues / Ambiguities for an implementer
- **Two API versions in play** (64.0 / 65.0) — TR-008 requires compatibility across both; pin new metadata accordingly.
- `Two_Years_After_Start_Date__c` formula is described as "similar logic" for two-year boundaries but the exact day threshold (e.g. 730) is **not stated verbatim** in the source — verify the deployed formula before altering.
- `Quote_Type__c`, `Deal_Type__c`, `GSW__c` field data **types** are not specified in the source ("Custom field") — verify actual types before editing.

---

## 9. CODE-GOVERNING RULES (do not violate)

1. **Order Type values are fixed at six:** New, Upsell, Renewal, Amendment, Cancellation, Net-New. Deploy the `OrderType` StandardValueSet with **`sorted=false`** to preserve UI ordering (TR-001). Do not add/remove/reorder without changing BR-001.
2. **Legal Entity Copy entry condition is `LegalEntityId IS NULL`** (TR-002) — the flow MUST NOT overwrite an already-populated (API/programmatically-set) QLI `LegalEntityId`. It reads the parent via `$Record.QuoteId` and copies only when the Quote has a value.
3. **Legal Entity Copy runs after-create on QLI and must be bulk-safe** and must complete **before** the Context Definition QLI→OrderItem mapping runs (so `LegalEntityId` carries to OrderItem).
4. **`AssetContractLinkerAction` lineage chain is exact:** `Order > OrderItem > AssetActionSource > AssetAction > Asset`. Do not shortcut/alter the traversal used to find Order-derived Assets (TR-003).
5. **Idempotency is required:** skip any Asset that already has an ACR to the same Contract — never create duplicate ACRs.
6. **`AppUsageAssignment` (RLM) must exist on the Contract before ACR creation** — create it if absent (TR-004). ACR creation depends on RLM being enabled on the Contract.
7. **ACR dates are Contract-derived:** `AssetContractRelationship.StartDate = Contract.StartDate`, `AssetContractRelationship.EndDate = Contract.EndDate`. Do not source these from Order/Asset.
8. **Orders without a `ContractId` are silently skipped** (A-004) — no error, no ACR. Preserve this guard.
9. **`AssetContractLinkerAction` is invoked by `Fortra_Assetize_Order` AFTER `createOrUpdateAssetFromOrder`**, receiving the Order ID. Do not move it before assetization (the Assets it links must already exist).
10. **`Year_After_StartDate__c` formula is exact:** true when **`EndDate` − `ServiceDate` <= 365** days (first-year). Keep it a formula checkbox on OrderItem (TR-005); do not convert to a stored/writable field.
11. **`Is_Split_Line__c` default is false; `Original_Order_Item__c` is a lookup with `SetNull` on delete.** `PowerOrderSplittingService` depends on both fields — do not rename/repurpose (D-007).
12. **`Partition_Record__c` is a lookup to `Partition__c`** (existing object, A-006/D-004). Preserve the lookup target.
13. **FLS targets are exactly the six Order fields:** `Total_Services__c`, `Quote_Type__c`, `Total_Subscription__c`, `Total_Software__c`, `Deal_Type__c`, `GSW__c` — Read/Edit across `Order_Field_Access`, `Revenue_Cloud_Admin`, `Revenue_Cloud_Base` (BR-007).
14. **PSG FLS is manual/UI-only:** `Revenue_Cloud_Admin` and `Revenue_Cloud_Base` belong to Permission Set Groups whose FLS **cannot** be reliably set/retrieved via Metadata API — use the SOQL-based verification path (TR-006, A-005). Do not assume a metadata deploy alone applied their FLS.
15. **`Fortra_Product_Type__c` is a global-value-set picklist on QuoteLineItem with field history tracking enabled** (TR-007) and maps to `OrderItem.Fortra_Product_Type__c` via Context Definition — it feeds partner-pricing margin determination (BR-006). Do not detach it from the `Fortra_Product_Type` global value set.
16. **Field mappings are load-bearing (Section 4.5):** `Quote.LegalEntityId → QLI.LegalEntityId` (Flow); `QLI.LegalEntityId → OrderItem.LegalEntityId` and `QLI.Fortra_Product_Type__c → OrderItem.Fortra_Product_Type__c` (Context Definition). Preserve each hop.
17. **Maintain API version 64.0/65.0 compatibility** across all metadata components (TR-008).
18. **Deployment stays modular:** seven independently-deployable packages, each with its own `sfdx-project.json` + `package.xml`. Preserve package boundaries for targeted deploy/rollback.
