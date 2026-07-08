# Products Hardware — Solution Design (RCA KB)

**Purpose:** Manage Fortra hardware equipment records, associate them to Revenue Cloud quote line items via hardware groups, and drive attribute-based pricing for Power products (mainframe/server software) from hardware characteristics (pGroup, System Type, Users Per Partition, Model).

> Source: `Fortra-Products-Hardware-Solution-Design-Doc.txt`. This is a design document; class/field names below are as named in the design. Verify against live Apex/metadata before refactoring (some names in the doc may differ from deployed code — e.g. doc lists both `HardwareGroupController` and the component set `hardwareGroupManager`).

---

## 1. Executive Summary

Three major components:
1. **Hardware Groups Management LWC** (`hardwareGroupManager`) — modal UI on the Quote page for creating, editing, and assigning hardware groups. Supports Quote Line Group creation, searching existing `Hardware__c` records, inline creation of new hardware, and assigning hardware to groups.
2. **Hardware Attribute Pricing Pre-Hook** (`HardwareAttributePricingPrehook`) — calculates pricing multipliers from hardware attributes during the Revenue Cloud pricing waterfall; reads attributes from context, applies pGroup / user-count / system-type multipliers, writes the calculated hardware price back to context for downstream steps.
3. **Partitions custom object** (`Partitions__c`) — tracks logical partitions (LPARs) within hardware systems; master-detail to `Hardware__c`.

Flow: When quote lines are added to a hardware group, hardware attributes automatically flow to the `QuoteLineItem` via triggers. During pricing, the pre-hook reads those attributes, applies multipliers, and writes the hardware-adjusted price.

### Key Features (verbatim specifics)
- Hardware Groups LWC: three-mode modal (**Create, Edit, Assign**) with inline hardware creation and search.
- Pricing formula: `Hardware_Price = List_Price x pGroup_Multiplier x UserCount_Multiplier x (1 - SystemType_Discount)`.
- Three-tier attribute override priority: (1) `QuoteLineItemAttribute` from Product Configurator, (2) `Hardware__c` defaults from linked hardware, (3) System defaults (**P20, Production, 1**).
- pGroup multiplier tiers: **P05=0.5x through P60=4.0x**.
- User count tier multipliers: **1-10 users=1.0x, 11-50=1.25x, 51-100=1.5x, 101-250=2.0x, 251-500=2.5x, 501+=3.0x**.
- System Type discounts: **Production=0%, Staging=25%, Test=50% off production pricing**.
- `Partitions__c` for LPAR tracking, master-detail to `Hardware__c`.
- Automatic attribute inheritance: quote lines inherit pGroup, Model, System Type, Users Per Partition from linked hardware groups via triggers.
- Hardware product eligibility service filters which products can be assigned to hardware groups.

---

## 2. Business Requirements & Rules

| ID | Requirement | Priority |
|----|-------------|----------|
| BR-001 | Allow sales reps to create hardware groups on Quotes and associate them with hardware equipment records | High |
| BR-002 | Support inline creation of new hardware records when required hardware does not exist | High |
| BR-003 | Auto-calculate Power product prices based on pGroup classification (P05 through P60) with multipliers 0.5x to 4.0x | High |
| BR-004 | Apply user count tier-based multipliers 1.0x (1-10 users) to 3.0x (501+ users) for per-user licensing | High |
| BR-005 | Apply system type discounts: Production = 0% (full price), Staging = 25% discount, Test = 50% discount | High |
| BR-006 | Allow override of hardware attribute defaults via Product Configurator while retaining hardware values as fallback | Medium |
| BR-007 | Track LPARs within hardware systems with partition name, number, and processor count | Medium |
| BR-008 | Display hardware config defaults (pGroup, Server Type, Users Per Partition) in Hardware Group Manager when selecting hardware | Medium |
| BR-009 | Support hardware search/filter by status, category, environment, serial number, and model | Medium |

### Technical Requirements
| ID | Requirement | Priority |
|----|-------------|----------|
| TR-001 | LWC modal (`hardwareGroupManager`) with three modes: Create, Edit, Assign | High |
| TR-002 | Apex Pre-Hook using `RevSignaling.SignalingApexProcessor` for hardware attribute pricing | High |
| TR-003 | Three-tier attribute override priority: `QuoteLineItemAttribute` > `Hardware__c` defaults > System defaults | High |
| TR-004 | Create `Partitions__c` with master-detail to `Hardware__c` and lookup to Account | Medium |
| TR-005 | Position Hardware Attribute Pricing AFTER List Price lookup and BEFORE Regional/Partner Pricing | High |
| TR-006 | Write pricing audit fields (`Pre_Hardware_Price__c`, `Hardware_Price_Multiplier__c`, `pGroup_Applied__c`, etc.) to context | High |
| TR-007 | All Apex test classes must pass with adequate code coverage for deployment | High |

---

## 3. Data Model

### 3.1 `Hardware__c` (existing custom object — equipment records)
| Field | Type | Notes |
|-------|------|-------|
| `Model_Number__c` | Text | Hardware model identifier |
| `Serial_Number__c` | Text | Hardware serial number |
| `Status__c` | Picklist | Hardware status (Active, Inactive, etc.) |
| `P_Group_List__c` | Picklist | Power pricing group classification (**P05 through P60**) |
| `Server_Type__c` | Picklist | Server type classification |
| `Users_Per_Partition__c` | Number | Number of users per logical partition |
| `Account__c` | Lookup(Account) | Account that owns this hardware |

### 3.2 `Partitions__c` (child of `Hardware__c`)
| Field | Type | Notes |
|-------|------|-------|
| `Hardware__c` | Master-Detail(Hardware__c) | Parent hardware record |
| `Partition_Number__c` | Text | Logical partition identifier |
| `Number_of_Processors__c` | Number | Processor count for this partition |
| `Account__c` | Lookup(Account) | Account associated with this partition |

### 3.3 `QuoteLineGroup` (standard object + custom fields)
| Field | Type | Notes |
|-------|------|-------|
| `Hardware__c` | Lookup(Hardware__c) | Hardware record assigned to this group |
| `Hardware_Notes__c` | Text Area | Notes for Order Management team about hardware |
| `Hardware_Group_Type__c` | Picklist | Type classification for hardware groups |

### 3.4 `QuoteLineItem` — Hardware attribute fields (inherited via trigger)
| Field | Type | Notes |
|-------|------|-------|
| `pGroup__c` | Text | Power pricing group from hardware (P05–P60) |
| `Model__c` | Text | Hardware model identifier from linked hardware |
| `System_Type__c` | Text | System type (Production, Staging, Test) from hardware |
| `Users_Per_Partition__c` | Number | User count per partition from hardware |

### 3.5 `QuoteLineItem` — Hardware pricing audit fields (written by pre-hook)
| Field | Type | Notes |
|-------|------|-------|
| `Pre_Hardware_Price__c` | Currency | Price before hardware attribute adjustment |
| `Hardware_Price_Multiplier__c` | Number | Combined multiplier applied to list price |
| `Hardware_Pricing_Applied__c` | Checkbox | Flag indicating hardware pricing was applied |
| `Hardware_Pricing_Detail__c` | Long Text Area | **JSON audit trail** with pGroup multiplier, user tier multiplier, system type discount |
| `Hardware_Pricing_Source__c` | Text | Source of attribute values: `Configurator`, `Hardware Default`, or `System Default` |
| `pGroup_Applied__c` | Text | Actual pGroup value used in pricing calculation |
| `System_Type_Applied__c` | Text | Actual System Type value used in pricing calculation |
| `Users_Per_Partition_Applied__c` | Number | Actual Users Per Partition value used in pricing calculation |

### 3.6 Field Mappings
Trigger-driven (Hardware → QuoteLineItem):
- `Hardware__c.P_Group_List__c` → `QuoteLineItem.pGroup__c`
- `Hardware__c.Server_Type__c` → `QuoteLineItem.System_Type__c`
- `Hardware__c.Users_Per_Partition__c` → `QuoteLineItem.Users_Per_Partition__c`
- `Hardware__c.Model_Number__c` → `QuoteLineItem.Model__c`

Configurator → Context:
- `QuoteLineItemAttribute (Pgroup)` → `Context: SalesTransactionItemAttribute.Pgroup`
- `QuoteLineItemAttribute (Server_Type)` → `Context: SalesTransactionItemAttribute.Server_Type`
- `QuoteLineItemAttribute (Users)` → `Context: SalesTransactionItemAttribute.Users`

Pre-hook context writes → QuoteLineItem:
- `Context: UnitPrice (pre-hook write)` → `QuoteLineItem.UnitPrice` (hardware-adjusted)
- `Context: Pre_Hardware_Price__c` → `QuoteLineItem.Pre_Hardware_Price__c`
- `Context: Hardware_Pricing_Detail__c` → `QuoteLineItem.Hardware_Pricing_Detail__c`

---

## 4. Business Logic (exact formulas / tables / precedence)

### 4.1 Hardware Pricing Formula
```
Hardware_Price = List_Price x pGroup_Multiplier x UserCount_Multiplier x (1 - SystemType_Discount/100)
```
**Worked example (verbatim):** `$10,000 x 1.5 (P30) x 2.0 (150 users) x (1 - 0.25 Staging) = $22,500`.

> Note the formula uses `SystemType_Discount/100` (discount expressed as a percent). The Key-Features summary writes it as `(1 - SystemType_Discount)` with the discount as a fraction — same result. Use the `/100` form since the discount table is stated in percent (0%, 25%, 50%).

### 4.2 pGroup Multiplier Table
| pGroup | Multiplier |
|--------|-----------|
| P05 | 0.5 |
| P10 | 0.75 |
| P20 | 1.0 (**default/base**) |
| P30 | 1.5 |
| P40 | 2.0 |
| P50 | 3.0 |
| P60 | 4.0 |

Represents hardware processing capacity tiers. Range stated as "P05=0.5x through P60=4.0x".

### 4.3 User Count Tier Multipliers (applied on `Users_Per_Partition` value)
| Users Per Partition | Multiplier |
|---------------------|-----------|
| 1–10 | 1.0x |
| 11–50 | 1.25x |
| 51–100 | 1.5x |
| 101–250 | 2.0x |
| 251–500 | 2.5x |
| 501+ | 3.0x |

### 4.4 System Type Discounts
| System Type | Discount |
|-------------|----------|
| Production | 0% (no discount / full price) |
| Staging | 25% discount |
| Test | 50% discount |

### 4.5 Attribute Override Priority (three-tier)
1. **`QuoteLineItemAttribute` from Product Configurator** — highest priority (explicit user configuration).
2. **`Hardware__c` record values** — defaults/fallback when configurator attributes are not set.
3. **System defaults** — last resort: `pGroup = P20`, `System Type = Production`, `Users = 1`.

The pre-hook records which source won in `Hardware_Pricing_Source__c` (`Configurator` / `Hardware Default` / `System Default`).

### 4.6 Hardware Group Assignment behavior
- When a `QuoteLineItem` is added to a `QuoteLineGroup` that has a `Hardware__c` lookup, `QuoteLineItemTriggerHandler` copies hardware attributes to the line item.
- The LWC **auto-creates Partition records for iSeries hardware types** (see Assumption A-007).

### 4.7 Product Eligibility Filtering
`HardwareProductEligibilityService` determines which products are eligible for hardware group assignment based on **product family and solution category**, ensuring only Power products receive hardware pricing.

### 4.8 Fail-Safe Pricing (edge cases)
- The pre-hook **always returns SUCCESS** — it logs errors without blocking the pricing procedure.
- Lines **without hardware linkage are skipped gracefully**.

---

## 5. Components

| Component | Type | Responsibility |
|-----------|------|----------------|
| `hardwareGroupManager` | Lightning Web Component | Modal on Quote page for creating/editing/assigning hardware groups; hardware search, inline creation, config-defaults display |
| `HardwareGroupController.cls` | Apex Controller | Server-side CRUD for QuoteLineGroups, hardware search, inline hardware creation, attribute queries |
| `HardwareAttributePricingPrehook.cls` | Apex Pre-Hook | RC pricing hook computing hardware attribute-based pricing (pGroup, User Count, System Type multipliers) |
| `HardwarePreConfigInvocable.cls` | Invocable Apex | Pre-configures hardware attributes on QuoteLineItems before product configuration |
| `HardwareProductEligibilityService.cls` | Apex Service | Determines which products are eligible for hardware group assignment (product family + attributes) |
| `HardwareProductSelectorController.cls` | Apex Controller | Hardware product selection and filtering in the hardware management workflow |
| `HardwareManagementController.cls` | Apex Controller | Broader hardware management operations (retrieval and updates) |
| `QuoteLineItemTriggerHandler` | Apex Trigger Handler | Copies hardware attributes from `Hardware__c` to `QuoteLineItem` when a line is added to a hardware group |
| `QuoteLineGroupTriggerHandler` | Apex Trigger Handler | Hardware lifecycle management on the group |
| `Partitions__c` | Custom Object | LPAR child of `Hardware__c` (master-detail) |
| `Hardware__c` | Custom Object | Existing equipment records (model, serial, status, pGroup, server type, users per partition) |

**LWC modal pattern:** three-mode (Create/Edit/Assign) with step-by-step navigation, hardware search with multiple filter criteria, inline hardware creation via `@AuraEnabled` controller methods.

---

## 6. Integration Points & Sequence

### 6.1 Process Flow (sequence)
1. Sales rep opens a Quote → clicks **Hardware Groups** button → launches `hardwareGroupManager` LWC modal.
2. User creates a hardware group: enters name, optionally assigns hardware (search existing or create new inline), saves the Quote Line Group.
3. User adds Power products via **Browse Catalogs**, selecting the hardware group to associate products with hardware.
4. `QuoteLineItemTriggerHandler` auto-populates `pGroup__c`, `Model__c`, `System_Type__c`, `Users_Per_Partition__c` on the `QuoteLineItem` from the linked `Hardware__c`.
5. (Optional) User overrides hardware attribute values in the Product Configurator (`QuoteLineItemAttribute`) for specific lines.
6. On pricing, `HardwareAttributePricingPrehook` reads hardware attributes from context with priority **Configurator overrides > Hardware defaults > System defaults**.
7. Pre-hook computes `List_Price x pGroup_Multiplier x UserCount_Multiplier x (1 - SystemType_Discount)` and writes results to context.
8. Pricing continues: **List Price → Hardware Attribute Pricing → Regional Services Pricing → Partner Pricing → COLA Uplift → Final Price**.

### 6.2 Revenue Cloud Context API
- `HardwareAttributePricingPrehook` uses `Context.IndustriesContext.queryTags()` to read `SalesTransactionItem` data (prices and attributes) and `SalesTransactionItemAttribute` (configurator overrides).
- Uses `updateContextAttributes()` to write hardware pricing results back to context.
- Pre-hook implemented via `RevSignaling.SignalingApexProcessor` (TR-002).

### 6.3 Procedure Plan Definition
`HardwareAttributePricingPrehook` registered as a **Pre-Hook** in the Fortra pricing Procedure Plan Definition — positioned **after List Price lookup and before Regional Services Pricing** (D-004, TR-005).

### 6.4 Product Configurator Integration
Hardware attributes (`Pgroup`, `Server_Type`, `Users`) exposed as configurable attributes in the RC Product Configurator via `AttributeDefinition` records (D-006), allowing user overrides.

### 6.5 QuoteLineGroup / Trigger Framework
- Hardware groups leverage standard `QuoteLineGroup` with custom fields (`Hardware__c`, `Hardware_Notes__c`, `Hardware_Group_Type__c`).
- `QuoteLineItemTriggerHandler` + `QuoteLineGroupTriggerHandler` provide automatic attribute propagation and hardware lifecycle management.

---

## 7. Assumptions / Dependencies / Open Issues

### Assumptions
- **A-001** `Hardware__c` already exists with `Model_Number__c`, `Serial_Number__c`, `Status__c`, `P_Group_List__c`, `Server_Type__c`, `Users_Per_Partition__c`.
- **A-002** `QuoteLineGroup` supports custom fields for `Hardware__c` lookup and `Hardware_Notes__c`.
- **A-003** Pricing multiplier tables (pGroup, User Tier, System Type) are **static** — no custom metadata/custom settings config required.
- **A-004** Power products identifiable by product family or solution category for filtering hardware-eligible products.
- **A-005** `QuoteLineItemTriggerHandler` copies hardware attributes from `Hardware__c` to `QuoteLineItem` when a line is added to a hardware group.
- **A-006** Product Configurator (`SalesTransactionItemAttribute`) is the primary mechanism for user-initiated attribute overrides.
- **A-007** iSeries hardware types require **automatic partition creation** when hardware is assigned to a group.

### Internal Dependencies (all status Complete)
- **D-001** `Hardware__c` with `P_Group_List__c`, `Server_Type__c`, `Users_Per_Partition__c`.
- **D-002** `QuoteLineItem` hardware attribute + pricing audit fields deployed.
- **D-003** Context Definition includes hardware attribute + pricing output fields with proper entity mappings.
- **D-004** Procedure Plan Definition registers `HardwareAttributePricingPrehook` before Regional Pricing.
- **D-005** `QuoteLineItemTriggerHandler` + `QuoteLineGroupTriggerHandler` deployed.
- **D-006** `AttributeDefinition` records for `Pgroup`, `Server_Type`, `Users` exist.

### External Dependencies
- **E-001** Revenue Cloud User + Pricing Permission Set Licenses assigned (Salesforce Admin).
- **E-002** Hardware equipment data maintained by Fortra Operations.
- **E-003** Pricing multiplier tables approved by Fortra Power Team Sales.

### Open Issues / Ambiguities for an implementer
- Formula uses `SystemType_Discount/100` (percent) in §6.3 but `(1 - SystemType_Discount)` (fraction) in the summary — **treat the table values as percentages** (0/25/50) and divide by 100.
- Doc names both `HardwareGroupController.cls` and the `hardwareGroupManager` LWC component set; live code may consolidate controllers — verify actual class names before editing.

---

## 8. CODE-GOVERNING RULES (do not violate)

1. **Pricing formula is exact:** `Hardware_Price = List_Price × pGroup_Multiplier × UserCount_Multiplier × (1 − SystemType_Discount/100)`. Discounts are percentages (Production 0, Staging 25, Test 50). Verified example: `$10,000 × 1.5 × 2.0 × (1 − 0.25) = $22,500`.
2. **pGroup multipliers are fixed:** P05=0.5, P10=0.75, P20=1.0 (base/default), P30=1.5, P40=2.0, P50=3.0, P60=4.0. Do not add/reorder tiers without Fortra Power Team Sales approval (E-003).
3. **User-count tiers are fixed and inclusive-banded on `Users_Per_Partition`:** 1–10=1.0, 11–50=1.25, 51–100=1.5, 101–250=2.0, 251–500=2.5, 501+=3.0.
4. **System-Type discounts are fixed:** Production=0%, Staging=25%, Test=50%.
5. **Three-tier override priority MUST be honored in order:** (1) `QuoteLineItemAttribute` (Configurator) → (2) `Hardware__c` record defaults → (3) System defaults `P20 / Production / 1 user`. Record which won in `Hardware_Pricing_Source__c` (`Configurator` | `Hardware Default` | `System Default`).
6. **Fail-safe:** `HardwareAttributePricingPrehook` MUST always return SUCCESS — log errors, never block the pricing procedure. Lines with no hardware linkage MUST be skipped gracefully (not errored).
7. **Waterfall position is load-bearing:** Hardware Attribute Pricing runs AFTER List Price lookup and BEFORE Regional Services Pricing (order: List Price → Hardware → Regional → Partner → COLA → Final). Do not move it.
8. **Context API contract:** read via `Context.IndustriesContext.queryTags()` (`SalesTransactionItem` + `SalesTransactionItemAttribute`); write via `updateContextAttributes()`. Pre-hook must write `UnitPrice`, `Pre_Hardware_Price__c`, and `Hardware_Pricing_Detail__c` back to context.
9. **Audit fields must be populated for traceability (TR-006):** `Pre_Hardware_Price__c`, `Hardware_Price_Multiplier__c` (combined multiplier), `Hardware_Pricing_Applied__c`, `Hardware_Pricing_Detail__c` (JSON of pGroup mult + user tier mult + system type discount), `Hardware_Pricing_Source__c`, `pGroup_Applied__c`, `System_Type_Applied__c`, `Users_Per_Partition_Applied__c`.
10. **Attribute inheritance mappings are exact (trigger):** `P_Group_List__c → pGroup__c`, `Server_Type__c → System_Type__c`, `Users_Per_Partition__c → Users_Per_Partition__c`, `Model_Number__c → Model__c`. Inheritance is trigger-driven on add-to-group; do not require manual entry.
11. **`Partitions__c` is master-detail to `Hardware__c`** (with Account lookup). iSeries hardware types auto-create Partition records on group assignment (A-007) — preserve this behavior.
12. **Only Power products get hardware pricing:** eligibility gated by `HardwareProductEligibilityService` on product family / solution category. Do not apply hardware multipliers to ineligible products.
13. **Multiplier tables are static (A-003):** no custom metadata / custom settings — but any table change still needs Power Team approval (E-003).
14. **P20 / Production / 1 user is the canonical system-default triple** — do not change the fallback constants.
