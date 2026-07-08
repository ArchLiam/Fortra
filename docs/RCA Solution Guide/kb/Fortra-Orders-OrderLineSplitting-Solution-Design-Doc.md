# Power Order Line Splitting — Solution Design (Fortra RCA)

**Purpose (one line):** During Quote-to-Order (Q2O) conversion, automatically decompose Power-product OrderItems with `Quantity > 1` into one OrderItem per unit (Quantity=1 each), conditionally clone/share Hardware and always clone Partition records, so Revenue Cloud creates one Asset per unit on Order activation.

- **Source doc:** Power Order Line Splitting Solution Design Document, Client: Fortra, Consultant: Coastal Cloud, Version 1.0, Date April 14, 2026.
- **Nature:** Custom automation inside Fortra's Salesforce Revenue Cloud Advanced (RCA / Revenue Lifecycle Management) implementation. Entirely in-org; no external system integration.

---

## 1. Executive Summary

The solution automatically decomposes Power product order lines with quantity greater than one into individual order lines of quantity one, and conditionally clones or shares the associated Hardware and Partition records based on each product's Power Split Type configuration.

Key design decision: **The design preserves the original OrderItem (updating it in place) and inserts `(quantity - 1)` clones**, which avoids invalidating the Revenue Cloud activation gate and produces one Asset per unit after Order activation.

### 1.1 Key Features (verbatim)
- Automatic order line decomposition for any OrderItem whose `Product2.Solution_Group__c` equals `'Power'` and `Quantity` is greater than one.
- Two configurable split behaviors driven by `Product2.Power_Split_Type__c`:
  - **`Order Line Only`** — hardware shared across splits.
  - **`Order Line and Hardware`** — hardware cloned per split.
- Partition records are **always** cloned per split, inheriting from the original with a unique `'(Split N)'` suffix on `Partition_Name__c`.
- Original OrderItem is **kept and updated in place** (`Quantity=1`) rather than deleted, preserving referential integrity and avoiding `Order.ValidationResult` side effects.
- `Order.ValidationResult` is captured before processing and restored to its pre-DML value, preventing the misleading Revenue Cloud `'prices aren't updated'` activation error.
- Per-line distribution of `Manual_Discount__c` and `Displaced_ARR__c` across the original and cloned OrderItems.
- Invocable entry point (`splitPowerOrderLines`) enables direct integration with the `Fortra_Quote_to_Order_Conversion` flow.
- Dedicated `Power_Order_Splitting` permission set grants the CRUD and FLS needed by the service account running Q2O.

---

## 2. Business Requirements (§3.1) — verbatim IDs, text, priority

| ID | Requirement | Priority |
|----|-------------|----------|
| BR-001 | Each unit of a Power product sold must become its own Order line so Revenue Cloud creates one Asset per unit after activation | High |
| BR-002 | Manual discount and displaced ARR entered on the Quote line must be preserved by distributing evenly across every split line | High |
| BR-003 | The split operation must run automatically during Q2O with no additional user action after the Quote is accepted | High |
| BR-004 | Split behavior must be configurable per product so different Power SKUs can share or clone their hardware based on business need | High |
| BR-005 | Each split line must reference its source Quote Line and original Order line for audit and reporting | Medium |
| BR-006 | Partition records must be cloned per split so each unit has its own provisioning record even when hardware is shared | High |
| BR-007 | Failure of the splitting operation must not leave the Order in a partially-split state; the entire operation rolls back on error | High |
| BR-008 | Non-Power products and Power products with Quantity = 1 must be ignored by the splitting service | Medium |

## 2b. Technical Requirements (§3.2) — verbatim

| ID | Requirement | Priority |
|----|-------------|----------|
| TR-001 | Splitting must be implemented as an Apex InvocableMethod so Flow can orchestrate it inside the Q2O transaction | High |
| TR-002 | The service must use dynamic SOQL covering all accessible OrderItem fields so every attribute of the original line is carried to the clones | High |
| TR-003 | The service must not cause `Order.ValidationResult` to change from its pre-DML value; any side-effect flip must be reverted before exit | **Critical** |
| TR-004 | The original OrderItem must be kept and updated in place rather than deleted, to avoid invalidating Revenue Cloud pricing calculation state | **Critical** |
| TR-005 | All DML must be bulkified; per-request governor limits must not be exceeded up to the platform cap of approximately 150 OrderItems | High |
| TR-006 | The service must use a `Database` savepoint and `Database.rollback` so partial failures do not leak inserted clones or cloned hardware | High |
| TR-007 | A dedicated permission set (`Power_Order_Splitting`) must grant `Partition__c` CRUD plus OrderItem custom field Edit so system users running the Q2O flow have the required FLS | High |
| TR-008 | Apex test coverage for `PowerOrderSplittingService` must be at least **90% line coverage** | High |

---

## 3. Data Model (every object/field with TYPE)

The solution touches **four objects**: OrderItem (standard, extended), Product2 (standard, 2 driver fields), Hardware__c (custom), Partition__c (custom). Plus `Order.ValidationResult` (standard writable picklist).

### 3.1 OrderItem custom fields (D-001)
| Field | Type | Role |
|-------|------|------|
| `Is_Split_Line__c` | Checkbox | Marks an OrderItem as a clone produced by splitting; **false** for the kept original |
| `Original_Order_Item__c` | Lookup | On clones, references the original OrderItem whose quantity was split; **null on the original** (null after processing) |
| `Partition_Record__c` | Lookup | Links the OrderItem to the `Partition__c` that represents the provisioned unit |
| `Hardware__c` | Lookup | Links the OrderItem to the `Hardware__c` record; shared or cloned based on Power Split Type |
| `Manual_Discount__c` | Currency | Per-line manual discount; divided by the original quantity across splits |
| `Displaced_ARR__c` | Currency | Per-line displaced ARR; divided by the original quantity across splits |

### 3.2 Product2 driver fields (D-002)
| Field | Type | Role |
|-------|------|------|
| `Solution_Group__c` | (classifier) | Product qualifies for splitting only when value = `'Power'` |
| `Power_Split_Type__c` | Picklist | Values: `'Order Line Only'`, `'Order Line and Hardware'`. Drives whether hardware is shared or cloned. **Blank defaults to `'Order Line Only'`** |

### 3.3 Partition__c custom object (D-003)
Child of `Hardware__c` **via master-detail**; one record per provisioned unit. Cloned per split with unique `(Split N)` naming. Fields:
`Hardware__c` (master-detail), `Partition_ID__c`, `Partition_Name__c`, `Partition_Number__c`, `Number_of_Processors__c`, `License_Key__c`, `Status__c`, `Activation_Date__c`, `Expiration_Date__c`, `Notes__c`.

### 3.4 Hardware__c custom object (D-004)
Top-level hardware record. Cloned **only** when split type is `'Order Line and Hardware'`. Fields:
`Account__c`, `Primary_Contact__c`, `Parent_Hardware__c`, `Location__c`, `Serial_Number__c`, `Model_Number__c`, `Manufacturer__c`, `Hardware_Type__c`.

### 3.5 Order standard field
`Order.ValidationResult` — a **writable picklist** on the standard Order object that the platform uses as the true activation gate. The service captures and restores it. (Delete+reinsert of OrderItems flips it to `'TransactionIncomplete'`.)

---

## 4. Field Mappings (§6.2.1) — exact source→target

| Source Field | Target Field / Rule |
|--------------|---------------------|
| `QuoteLineItem.Product2Id` | `OrderItem.Product2Id` (preserved on original and clones) |
| `OrderItem.Quantity` (original, pre-split) | `OrderItem.Quantity = 1` on original **+** `(quantity - 1)` clones each at `Quantity = 1` |
| `OrderItem.Manual_Discount__c` (original value) | `OrderItem.Manual_Discount__c` on original and each clone = **original / quantity** |
| `OrderItem.Displaced_ARR__c` (original value) | `OrderItem.Displaced_ARR__c` on original and each clone = **original / quantity** |
| `OrderItem.Hardware__c` (original) | On clones = **same reference** when split type is `'Order Line Only'`; **cloned Hardware Id** when `'Order Line and Hardware'` |
| `OrderItem.Partition_Record__c` (original) | On clones = **newly cloned `Partition__c` Id (always cloned regardless of split type)** |
| `OrderItem.Id` (original) | `OrderItem.Original_Order_Item__c` on each clone (null on the original after processing) |
| `Partition__c.Partition_Name__c` (original) | On clone = original value + `' (Split N)'` |
| `Partition__c.Partition_ID__c` (original) | On clone = original value + `'-SPLIT-N'` |
| `Hardware__c.Serial_Number__c` (original) | On clone = original value + `'-SPLIT-N'` (**only** when split type is `'Order Line and Hardware'`) |
| `Order.ValidationResult` (pre-DML value) | (post-DML) = same pre-DML value, **restored at end of processing when pre-value was null AND `linesCreated > 0`** |

---

## 5. Business Logic (§6.3) — exact rules

Rules refined through production testing in **fortrauat**:

1. **Eligibility filter:** only OrderItems where `Product2.Solution_Group__c = 'Power'` AND `Quantity > 1` are eligible; all others are **silently skipped**.
2. **Default split type:** when `Power_Split_Type__c` is blank, default to `'Order Line Only'` (missing config degrades safely to shared-hardware behavior).
3. **Original kept, updated in place — NOT deleted.** Deleting and reinserting OrderItems flips `Order.ValidationResult` to `'TransactionIncomplete'` (the platform's real activation gate, despite the misleading `'prices aren't updated'` error surfaced), which blocks Order activation.
4. **Conditional ValidationResult restore:** capture `Order.ValidationResult` at entry; only if that pre-value was **null** AND **at least one line was created**, restore it to null at exit so Q2O can activate. If the Order arrived with a pre-existing validation issue set by another process, the service must **not** mask it.
5. **Full-field clone via schema map:** use `Schema.SObjectType.OrderItem.fields.getMap()` to build a full-field clone, ensuring every createable field is carried from original to clones without listing them statically (resilient to future OrderItem field additions).
6. **Single savepoint / rollback:** entire operation runs inside a single `Database` savepoint; any exception in any phase triggers `Database.rollback` and returns `success=false` with the error message, preventing partial state.
7. **Financial distribution:** `Manual_Discount__c` and `Displaced_ARR__c` are distributed as **original / quantity** across the kept original and the new clones so the total preserved across the split equals the original Quote line value.

> NOTE on division semantics: The doc states discount/ARR = `original / quantity` on **every** line (original + all `quantity-1` clones), and describes the result as "the total matches what the rep quoted" / "total preserved... equals the original Quote line value." No explicit rounding mode is specified in the source. Division is by the **original** (pre-split) quantity.

---

## 6. Components (§2.3) — Apex / Flow / fields / permset

| Component | Type | Responsibility |
|-----------|------|----------------|
| `PowerOrderSplittingService` | Apex Class | Service class containing invocable `splitPowerOrderLines` and the `processOrder` orchestration (**8 phases**). `with sharing`. |
| `PowerOrderSplittingServiceTest` | Apex Test Class | **Eight test methods** covering single/multi-line, both split types, shared vs cloned hardware, partition cloning, and non-Power product skip behavior |
| `Fortra_Quote_to_Order_Conversion` | Screen Flow | Q2O flow that calls `SplitPowerOrderLines` after `createOrderFromQuote` and before `Activate_Order` |
| `OrderItem.Is_Split_Line__c` | Custom Field (Checkbox) | see Data Model |
| `OrderItem.Original_Order_Item__c` | Custom Field (Lookup) | see Data Model |
| `OrderItem.Partition_Record__c` | Custom Field (Lookup) | see Data Model |
| `OrderItem.Hardware__c` | Custom Field (Lookup) | see Data Model |
| `OrderItem.Manual_Discount__c` | Custom Field (Currency) | see Data Model |
| `OrderItem.Displaced_ARR__c` | Custom Field (Currency) | see Data Model |
| `Product2.Power_Split_Type__c` | Custom Field (Picklist) | Values: `'Order Line Only'`, `'Order Line and Hardware'` |
| `Partition__c` | Custom Object | Child of `Hardware__c`; one per unit; cloned per split with unique `(Split N)` naming |
| `Hardware__c` | Custom Object | Top-level hardware; cloned only when split type is `'Order Line and Hardware'` |
| `Power_Order_Splitting` | Permission Set | Grants `Partition__c` CRUD, `Hardware__c` CRU, OrderItem custom-field Edit to service-account users running Q2O |

### 6.1 Architecture (§6.1)
- Single **`with sharing`** Apex class exposed to Flow via `@InvocableMethod splitPowerOrderLines`.
- Runs in a single transaction protected by a `Database` savepoint.
- Hardware and Partition queries bulkified through a `Set<Id>` then a `Map<Id, SObject>` lookup.
- Returns a `SplitResult` type reporting: `success`, `linesCreated`, `hardwareCloned`, `partitionsCloned`, `errorMessage`.

### 6.2 `processOrder` — the 8 phases (verbatim order)
1. Query qualifying OrderItems using dynamic SOQL over **every accessible field**.
2. Insert cloned Hardware records **when the split type requires** (`'Order Line and Hardware'`).
3. Assign cloned Hardware Ids to in-memory clone OrderItems.
4. Insert clone OrderItems.
5. Update the original OrderItems in place with `Quantity=1` and distributed `Manual_Discount` / `Displaced_ARR`.
6. Insert cloned Partition records.
7. Update clone OrderItems with their cloned `Partition_Record__c` references.
8. Restore `Order.ValidationResult` to its pre-DML value so Revenue Cloud's activation gate is cleared.

---

## 7. Technical Process Flow / Integration & Sequence (§2.2, §6.4)

Sequence:
1. Q2O flow creates Order and OrderItems from source Quote via standard **`createOrderFromQuote`**.
2. Flow invokes `PowerOrderSplittingService.splitPowerOrderLines` with the new Order Id (Apex action named **'Split Power Order Lines'**), immediately after `createOrderFromQuote`.
3. Service queries qualifying OrderItems (`Solution_Group__c = 'Power'` AND `Quantity > 1`) using dynamic SOQL over every accessible field.
4. Service captures `Order.ValidationResult` **before** touching any OrderItems.
5. For each qualifying OrderItem, build `(quantity - 1)` in-memory clones with `Is_Split_Line__c = true` and `Original_Order_Item__c` = original.
6. If split type = `'Order Line and Hardware'`: insert cloned `Hardware__c` records, assign to clones; otherwise share the original `Hardware__c`.
7. Insert clone OrderItems; then update originals in place (`Quantity=1`, `Manual_Discount` and `Displaced_ARR` divided by original quantity, `Is_Split_Line=false`).
8. Clone `Partition__c` records (one per clone slot) with `Partition_Name__c` appended `'(Split N)'`, linked to the appropriate Hardware.
9. Assign cloned partitions to the clone OrderItems via `Partition_Record__c`.
10. Restore `Order.ValidationResult` to null if it was null at entry and any lines were created — clears the activation gate.
11. Q2O flow proceeds to activate the Order; Revenue Cloud standard platform creates **one Asset per OrderItem** on activation.

**Return handling:** invocable returns `List<SplitResult>`; the flow consumes the **first element**. If `success` is false, the flow branches to the fault screen with the `errorMessage`.

**Downstream implicit integration:** On activation, platform creates one `AssetAction` and one Asset per OrderItem; the `Fortra_Asset_Populate_Legacy_Fields` record-triggered flow (**AsyncAfterCommit on Asset insert**) populates legacy fields on each new Asset. No external system integration — entire solution operates inside the Salesforce org.

---

## 8. Assumptions (§4) & Dependencies (§5)

**Assumptions:**
- A-001: Revenue Cloud (RLM) enabled; Order configured for Asset-based ordering.
- A-002: `Solution_Group__c` and `Power_Split_Type__c` populated on every Power product; **missing `Power_Split_Type__c` defaults to `'Order Line Only'`**.
- A-003: `Hardware__c` and `Partition__c` exist with the structure used by `HardwareGroupController` (`Partition__c` is child of `Hardware__c` via master-detail).
- A-004: User/service account running Q2O has `Power_Order_Splitting` permission set.
- A-005: Source Quote lines already carry valid Hardware and Partition references produced by the Hardware Groups workflow.
- A-006: Total OrderItems after splitting ≤ approximately **150** per Order (within per-transaction DML row limits).
- A-007: Q2O flow sets Order to Activated **only after** `SplitPowerOrderLines` returns `success = true`.
- A-008: Pricing already present on source OrderItems (from `createOrderFromQuote`); the service does **not** recalculate prices.

**Internal Dependencies (D-001…D-007):** all **Complete** — OrderItem 6 fields (D-001), Product2 2 fields (D-002), Partition__c object+fields (D-003), Hardware__c object+fields (D-004), Q2O flow modified to invoke SplitPowerOrderLines (D-005), permission set deployed+assigned (D-006), Hardware Groups config `HardwareGroupController` produces Hardware+Partition carried into Order (D-007).

**External Dependencies:** E-001 Salesforce RLM consumes OrderItems to create Assets on activation (Owner: Salesforce). E-002 standard `createOrderFromQuote` produces initial OrderItems (Owner: Salesforce).

**Open issues:** none explicitly listed. No rounding mode specified for the `original / quantity` division.

---

## 9. CODE-GOVERNING RULES (do NOT violate when refactoring)

1. **Never delete-and-reinsert OrderItems.** The original OrderItem MUST be kept and updated in place (`Quantity=1`). Deleting/reinserting flips `Order.ValidationResult` to `'TransactionIncomplete'`, which blocks activation. (TR-004 Critical; §6.3 rule 3.)
2. **`Order.ValidationResult` must equal its pre-DML value on exit.** Capture it at entry (before any OrderItem DML). Any side-effect flip MUST be reverted before returning. (TR-003 Critical.)
3. **Conditional restore only.** Restore `Order.ValidationResult` to null **only if** the pre-DML value was null **AND** `linesCreated > 0`. If it arrived non-null (pre-existing validation issue set elsewhere), do NOT mask/clear it. (§6.3 rule 4; §6.2.1 last row.)
4. **Eligibility gate is exact:** process an OrderItem only when `Product2.Solution_Group__c == 'Power'` AND `Quantity > 1`. All others silently skipped — non-Power and Power-with-Quantity=1 must be ignored. (BR-008; §6.3 rule 1.)
5. **Clone count = `(quantity - 1)`.** Insert exactly `quantity - 1` clones, each `Quantity = 1`; original updated to `Quantity = 1`. Net = `quantity` lines each Quantity 1. (§6.2.1.)
6. **Blank `Power_Split_Type__c` defaults to `'Order Line Only'`** (shared hardware). Do not error on blank. (A-002; §6.3 rule 2.)
7. **Hardware sharing vs cloning by split type:** `'Order Line Only'` → clones share the original `Hardware__c` Id. `'Order Line and Hardware'` → insert a cloned `Hardware__c` per split and assign its Id; clone's `Serial_Number__c` = original + `'-SPLIT-N'`. (Key Features; §6.2.1.)
8. **Partitions ALWAYS cloned** per split regardless of split type. Clone `Partition_Name__c` = original + `' (Split N)'`; clone `Partition_ID__c` = original + `'-SPLIT-N'`; link to the appropriate Hardware; assign to clone via `Partition_Record__c`. (BR-006; §6.2.1.)
9. **Financial distribution = `original / quantity`** applied to `Manual_Discount__c` AND `Displaced_ARR__c` on the kept original and every clone, dividing by the **original (pre-split)** quantity, so the summed total equals the original Quote line value. (BR-002; §6.2.1; §6.3 rule 7.)
10. **Clone marking / lineage:** clones set `Is_Split_Line__c = true` and `Original_Order_Item__c` = original OrderItem Id; the original ends with `Is_Split_Line__c = false` and `Original_Order_Item__c = null`. (§2.2; §6.2.1.)
11. **Full-field clone via schema map:** carry every createable field using `Schema.SObjectType.OrderItem.fields.getMap()` / dynamic SOQL over all accessible fields — do NOT hardcode a static field list. Must remain resilient to future OrderItem field additions. (TR-002; §6.3 rule 5.)
12. **Single savepoint + rollback:** wrap the whole operation in one `Database` savepoint; on any exception in any phase, `Database.rollback` and return `success=false` with `errorMessage`. No partial state may leak (clones or cloned hardware). (BR-007, TR-006; §6.3 rule 6.)
13. **Preserve the 8-phase order** in `processOrder`: (1) query, (2) insert cloned Hardware, (3) assign Hardware Ids to clones, (4) insert clone OrderItems, (5) update originals in place, (6) insert cloned Partitions, (7) update clones with `Partition_Record__c`, (8) restore `Order.ValidationResult`. (§6.1.)
14. **Bulkification required:** all DML bulkified; Hardware/Partition lookups via `Set<Id>` → `Map<Id, SObject>`; must not exceed governor limits up to ~150 OrderItems/Order. (TR-005, A-006.)
15. **Invocable contract:** entry point is `@InvocableMethod splitPowerOrderLines` returning `List<SplitResult>` with fields `success`, `linesCreated`, `hardwareCloned`, `partitionsCloned`, `errorMessage`; Flow consumes the first element. Keep this shape so `Fortra_Quote_to_Order_Conversion` can branch on `success`. (TR-001; §6.4.)
16. **Do not recalculate pricing.** Pricing already exists on source OrderItems from `createOrderFromQuote`; the service must not reprice. (A-008.)
17. **Class remains `with sharing`;** required FLS/CRUD is provided by the `Power_Order_Splitting` permission set (`Partition__c` CRUD, `Hardware__c` CRU, OrderItem custom-field Edit). (§6.1, TR-007.)
18. **Maintain ≥ 90% Apex line coverage** for `PowerOrderSplittingService`. (TR-008.)
