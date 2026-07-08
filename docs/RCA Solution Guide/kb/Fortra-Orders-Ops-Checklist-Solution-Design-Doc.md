# Orders Ops Checklist — Solution Design (KB)

**Purpose (one line):** A configurable, permission-controlled operations checklist embedded on the Salesforce Quote record page that enforces a hard validation gate blocking Quote-to-Order conversion until all checklist items are verified complete.

**Source doc:** "Orders Ops Checklist — Solution Design Document" (prepared for Fortra). Platform: Salesforce Revenue Cloud Advanced (RCA/CPQ). Deployed to `fortradp2` and `fortrauat`. API Version **62.0+** for all metadata. Reported test coverage **85–95%** across all Apex classes.

---

## 1. Executive Summary

- Embedded checklist system on the Quote record page. Hard validation gate prevents Quote→Order conversion until ALL checklist items are complete.
- **14 total components:** 1 LWC (`operationsChecklistPanel`), 4 Apex service classes, 2 Apex triggers, 1 record-triggered Flow, 1 Custom Metadata Type, 1 Custom Permission + 1 Permission Set. (The component table also names two additional invocable Apex classes — `ChecklistInitializationService` and `InitializeChecklistAction` — plus two handler classes; see Component Inventory. The "14 components" count is the doc's own framing.)
- **37 configurable checklist items** stored in `Operations_Checklist_Config__mdt`. Admins add/remove/reorder via Custom Metadata in Setup — **no code deployment required**.
- Lifecycle: automatic initialization → interactive completion → audit trail tracking → order validation.
- Categories of items include: contract validation, pricing approval, legal terms, payment setup, shipping/billing address verification, compliance checks.

### 1.1 Key Features (verbatim intent)
- Automated initialization via **three trigger paths**: (1) Opportunity StageName change to `'Order Processing'`, (2) Quote `IsSyncing` change, (3) manual stage re-entry — with **duplicate prevention** on re-triggers.
- Interactive LWC panel on Quote record page: real-time progress bar, checkbox controls, notes fields, permission-based read-only/editable modes.
- Hard-stop Order validation: `OrderValidationTrigger` blocks Order creation (**before insert**) when any item is incomplete; error message lists the specific incomplete items.
- 37 items in `Operations_Checklist_Config__mdt`, modifiable through Setup without code changes.
- Complete audit trail: every check/uncheck captures `Checked_By__c` (User lookup) and `Checked_Date__c` (DateTime) at the field level.
- Permission-based access via `Operations_Checklist_Access` Custom Permission + `Operations_Team_Access` Permission Set; non-operations users see read-only view.
- `ChecklistInitializationService` is an `@InvocableMethod` for Flow integration with proper `IsSyncing` detection.
- `ChecklistValidationService` also exposed as `@InvocableMethod` for the Q2O conversion flow's pre-validation chain.

---

## 2. Business Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| BR-001 | Automatically initialize a checklist with 37 configurable validation items when an Opportunity reaches `'Order Processing'` stage OR when a Quote syncs while the Opportunity is already in that stage | High |
| BR-002 | Provide interactive LWC panel on Quote records: display progress, allow authorized users to check/uncheck items, track who completed each item and when | High |
| BR-003 | Block Order creation if ANY checklist items remain incomplete; display clear error listing the specific incomplete items | High |
| BR-004 | Store checklist configuration in Custom Metadata Types so admins can modify items without code deployment | High |
| BR-005 | Enforce permission-based access: only users with `Operations_Checklist_Access` custom permission can modify items; others are read-only | High |
| BR-006 | Support notes on individual checklist items to capture context/explanations | Medium |
| BR-007 | Prevent duplicate checklist item creation when Opportunity stage changes back and forth or initialization fires multiple times | Medium |
| BR-008 | Maintain complete audit trail of all checklist interactions (user identity + timestamp) for compliance reporting | Medium |

### 2.1 Technical Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| TR-001 | Create `Quote_Checklist_Item__c` as **Master-Detail to Quote** with fields: `Item_Name__c` (Text 255), `Is_Checked__c` (Checkbox), `Checked_By__c` (Lookup User), `Checked_Date__c` (DateTime), `Notes__c` (Long Text 32768), `Sort_Order__c` (Number) | High |
| TR-002 | Create `Operations_Checklist_Config__mdt` with fields: `Item_Label__c`, `Sort_Order__c`, `Is_Active__c`, `Icon_Name__c`, `Category__c` for zero-code configuration | High |
| TR-003 | Implement `ChecklistInitializationService` as `@InvocableMethod` with duplicate-prevention logic that checks for existing `Quote_Checklist_Item__c` records before creating new ones | High |
| TR-004 | Build `operationsChecklistPanel` LWC using `@wire` for data fetching, `lightning-progress-bar` for completion display, conditional rendering based on Custom Permission check | High |
| TR-005 | Implement `OrderValidationTrigger` as **before-insert** trigger on Order with handler pattern; use `order.addError()` to block creation with descriptive message | High |
| TR-006 | Handle `Quote.IsSyncing` read-only limitation in tests by providing a `@TestVisible processOpportunities()` method that bypasses the `IsSyncing` check | Medium |
| TR-007 | Enforce FLS using `WITH SECURITY_ENFORCED` in ALL SOQL queries within `OperationsChecklistController` | Medium |
| TR-008 | Achieve minimum 85% test coverage across all Apex classes (initialization, validation, permission checks, edge cases) | Medium |

---

## 3. Data Model

### 3.1 `Quote_Checklist_Item__c` (Custom Object)
Master-Detail to Quote; **cascade delete**; sharing = **Controlled By Parent** (inherits Quote sharing). Stores individual checklist items with check status, user audit, notes, sort order.

| Field | Type (verbatim) | Notes |
|-------|-----------------|-------|
| `Quote__c` | Master-Detail(Quote) | Cascade delete; Controlled By Parent sharing |
| `Item_Name__c` | Text(255) | Display label **copied from config metadata at initialization** (from `Operations_Checklist_Config__mdt.Item_Label__c`) |
| `Is_Checked__c` | Checkbox | Default **false**; set to true when user checks the item |
| `Checked_By__c` | Lookup(User) | Populated with current user ID when checked; **cleared when unchecked** |
| `Checked_Date__c` | DateTime | Populated with current timestamp when checked; **cleared when unchecked** |
| `Notes__c` | Long Text Area(32768) | Optional notes for additional context on each item |
| `Sort_Order__c` | Number(18,0) | Determines display order in the LWC panel |

### 3.2 `Operations_Checklist_Config__mdt` (Custom Metadata Type)
Configuration template = single source of truth. Currently **37 active items**. Defines label, sort order, active flag, icon, category.

| Field | Type (verbatim) | Notes |
|-------|-----------------|-------|
| `Item_Label__c` | Text(255) | Template label used when creating `Quote_Checklist_Item__c` records |
| `Sort_Order__c` | Number(18,0) | Determines creation order and default display sequence |
| `Is_Active__c` | Checkbox | **Only active items are used to create checklist records** |
| `Icon_Name__c` | Text(100) | SLDS icon name for display in the LWC panel (optional) |
| `Category__c` | Text(100) | Grouping category for organizing items (optional) |

**Named example categories** (from doc): Contract Signed, Purchase Order, Customer Credit Check, Pricing Approval, Legal Terms, Discount Authorization, Tax Calculation, "and 30 more operational validation items." Higher-level category groupings mentioned: contract validation, pricing approval, legal terms, payment setup, shipping/billing address verification, compliance checks.

### 3.3 Field Mappings (source → target)

| Source | Target | When |
|--------|--------|------|
| `Operations_Checklist_Config__mdt.Item_Label__c` | `Quote_Checklist_Item__c.Item_Name__c` | at initialization |
| `Operations_Checklist_Config__mdt.Sort_Order__c` | `Quote_Checklist_Item__c.Sort_Order__c` | at initialization |
| `UserInfo.getUserId()` | `Quote_Checklist_Item__c.Checked_By__c` | on check |
| `DateTime.now()` | `Quote_Checklist_Item__c.Checked_Date__c` | on check |
| `Opportunity.Id` | `ChecklistInitializationService.InitializeRequest.opportunityId` | Flow input |
| `Quote_Checklist_Item__c.Is_Checked__c` (all items) | `ChecklistValidationService.ValidationResult.isComplete` | aggregated |

---

## 4. Business Logic (exact rules)

### 4.1 Initialization Logic (`ChecklistInitializationService`)
1. Query Quotes where **`IsSyncing = true`** for the given Opportunity.
2. For each qualifying Quote, check whether `Quote_Checklist_Item__c` records already exist (duplicate prevention).
3. If **none exist**: query all `Operations_Checklist_Config__mdt` where **`Is_Active__c = true`**, sorted by `Sort_Order__c`.
4. Create one `Quote_Checklist_Item__c` per config record with:
   - `Item_Name__c = Item_Label__c`
   - `Sort_Order__c = config Sort_Order__c`
   - all check fields defaulted to **null/false**.
5. **In test context the `IsSyncing` check is bypassed** (field is read-only → use `@TestVisible processOpportunities()`).

### 4.2 Check/Uncheck Logic (`OperationsChecklistService.updateChecklistItem()`)
Accepts `itemId` and `isChecked` boolean.
- When `isChecked = true`: set `Is_Checked__c = true`, `Checked_By__c = UserInfo.getUserId()`, `Checked_Date__c = DateTime.now()`.
- When `isChecked = false`: set `Is_Checked__c = false`, **clear** `Checked_By__c` and `Checked_Date__c`.
- Returns a success/error **message string**.

### 4.3 Validation Logic (`ChecklistValidationService.validateChecklistForQuote()`)
- Query all `Quote_Checklist_Item__c` for the given Quote ID.
- Iterate records, counting checked vs total.
- If any `Is_Checked__c = false`, build a list of incomplete `Item_Name__c` values.
- Return `ValidationResult` with: `isComplete` (boolean), `incompleteItems` (List of String), `errorMessage` (formatted string), `totalItems`, `completedItems`.

### 4.4 Order Blocking Logic (`OrderValidationTriggerHandler.handleBeforeInsert()`)
- Iterate Orders being inserted; collect QuoteIds; call validation service for each.
- If validation fails, call `order.addError()` with message (verbatim):
  `'Cannot convert Quote to Order. The following Operations Checklist items are incomplete: [list of items]'`
- This prevents the DML from completing (hard stop).

### 4.5 LWC Data Binding (`operationsChecklistPanel`)
- Uses `@wire(getChecklistItems, { quoteId: '$recordId' })` for reactive data loading.
- Controller returns `ChecklistData` inner class: `items` list, `totalItems`, `completedItems`, `completionPercentage`, `hasEditPermission`.
- After each check/uncheck or notes update, component calls `refreshApex()` to reload data and update progress bar.

### 4.6 Duplicate Prevention
- Before creating items, initialization service queries for existing `Quote_Checklist_Item__c` on the target Quote.
- If records already exist (**count > 0**), skip creation and return a success message indicating the checklist was already initialized.
- Handles re-triggering when Opportunity stage bounces in/out of `'Order Processing'`.

---

## 5. Components (Inventory + Responsibility)

| Component | Type | Responsibility |
|-----------|------|----------------|
| `Quote_Checklist_Item__c` | Custom Object | Master-Detail to Quote; stores items with check status, user audit, notes, sort order |
| `Operations_Checklist_Config__mdt` | Custom Metadata Type | Config template, 37 active items (label, sort order, active flag, icon, category) |
| `Operations_Checklist_Access` | Custom Permission | Controls write access to items; checked via `FeatureManagement.checkPermission()` |
| `Operations_Team_Access` | Permission Set | Grants Custom Permission + Read/Create/Edit on `Quote_Checklist_Item__c` with full FLS |
| `ChecklistInitializationService` | Apex Invocable Class (`@InvocableMethod`) | Creates `Quote_Checklist_Item__c` records from config metadata; prevents duplicates |
| `OperationsChecklistService` | Apex Service Class | Check/uncheck operations and notes updates with audit field population |
| `OperationsChecklistController` | Apex Controller (`@AuraEnabled`) | LWC gateway. Methods: `getChecklistItems` (cacheable), `updateChecklistItem`, `updateChecklistItemNotes` |
| `ChecklistValidationService` | Apex Service Class | Validates completion; returns `ValidationResult`(isComplete, incompleteItems, errorMessage). Also `@InvocableMethod` |
| `OrderValidationTriggerHandler` | Apex Handler Class | Before-insert handler on Order; calls validation service; blocks creation if incomplete |
| `QuoteSyncingTriggerHandler` | Apex Handler Class | After-update handler on Quote; detects `IsSyncing` changes; triggers initialization via `processOpportunities()` |
| `Initialize_Operations_Checklist` | Record-Triggered Flow | After-update on Opportunity; fires when StageName changes to `'Order Processing'`; runs in **Current Transaction** mode |
| `OrderValidationTrigger` | Apex Trigger | **Before-insert** on Order; delegates to `OrderValidationTriggerHandler` |
| `QuoteSyncingTrigger` | Apex Trigger | **After-update** on Quote; delegates to `QuoteSyncingTriggerHandler` |
| `operationsChecklistPanel` | Lightning Web Component | Interactive UI: progress bar, checkboxes, notes, SLDS styling, permission-based rendering |
| `InitializeChecklistAction` | Apex Invocable Class | Additional invocable action for checklist initialization callable from flows |

### 5.1 Architecture — Four-Layer
1. **Configuration Layer** — `Operations_Checklist_Config__mdt` = single source of truth (zero-code item management).
2. **Automation Layer** — Flow + Apex triggers for initialization and validation.
3. **Service Layer** — 4 Apex classes, separated concerns.
4. **Presentation Layer** — reactive LWC.

### 5.2 Security Model — Three-tier
1. **Object-level:** `Quote_Checklist_Item__c` Master-Detail to Quote → inherits parent sharing (Controlled By Parent).
2. **Permission-level:** `Operations_Team_Access` permission set grants object CRUD + field FLS + `Operations_Checklist_Access` custom permission.
3. **UI-level:** LWC checks `hasEditPermission` from controller; conditionally renders editable vs read-only.

---

## 6. Integration Points & Sequence

**End-to-end sequence:**
1. Admin configures items in `Operations_Checklist_Config__mdt` (`Item_Label__c`, `Sort_Order__c`, `Is_Active__c`, `Icon_Name__c`, `Category__c`).
2. Opportunity `StageName` → `'Order Processing'` fires `Initialize_Operations_Checklist` flow → invokes `ChecklistInitializationService.initializeChecklistForQuote()`.
3. Service queries Opportunity's Quotes where `IsSyncing = true`, gets active config records, creates one `Quote_Checklist_Item__c` per config item on the syncing Quote.
4. **Alt path:** Quote `IsSyncing` changes false→true while Opportunity already in `'Order Processing'` → `QuoteSyncingTrigger` (after-update) → `QuoteSyncingTriggerHandler` → `ChecklistInitializationService.processOpportunities()`.
5. Ops user opens Quote page → `operationsChecklistPanel` LWC loads → `OperationsChecklistController.getChecklistItems()` via `@wire` returns items, completion %, permissions.
6. User checks/unchecks → `OperationsChecklistController.updateChecklistItem()` → `OperationsChecklistService` updates `Is_Checked__c`, `Checked_By__c`, `Checked_Date__c`. Notes via `updateChecklistItemNotes()`.
7. On Quote→Order conversion, `OrderValidationTrigger` (before insert on Order) → `OrderValidationTriggerHandler` → `ChecklistValidationService.validateChecklistForQuote()`.
8. If all `Is_Checked__c = true` → Order proceeds. If any incomplete → `order.addError()` blocks the transaction, listing incomplete items.

**Named integration points:**
- **`Initialize_Operations_Checklist` Flow** — record-triggered after-update on Opportunity; invokes `ChecklistInitializationService` as Apex Action; passes `Opportunity.Id`; runs in `'Current Transaction'` mode.
- **`Fortra_Quote_to_Order_Conversion` Flow** — Q2O conversion flow invokes `ChecklistValidationService` as pre-conversion validation. If `isComplete = false`, flow displays error before attempting `createOrderFromQuote` (user-friendly message before the trigger-level hard stop). (Dependency D-004 also names this `Fortra_Quote_to_Order_Conversion`.)
- **Quote Record Page (Lightning App Builder)** — `operationsChecklistPanel` LWC must be **manually** added; recommended placement = right sidebar or dedicated tab.
- **`QuoteSyncingTrigger` Integration** — after-update on Quote detects `IsSyncing` changes; coordinates with `ChecklistInitializationService`; alternative init path when Quotes sync after Opportunity already reached `'Order Processing'`.
- **Permission Set Assignment** — `Operations_Team_Access` must be assigned via Setup or `sf org assign permset --name Operations_Team_Access`. Without it, users see read-only mode.

---

## 7. Assumptions

| ID | Assumption |
|----|-----------|
| A-001 | RCA (CPQ) enabled with Quote-to-Order configured in target environments |
| A-002 | Opportunity uses `'Order Processing'` as a valid StageName in the org's Sales Process |
| A-003 | Quote syncing (`IsSyncing`) is part of standard Quote-to-Opportunity sync |
| A-004 | The 37 items represent the complete validation set at deployment; can be added/modified post-deploy |
| A-005 | Ops team members will be assigned `Operations_Team_Access` by admin |
| A-006 | Quote record page layout updated to include the LWC (manual step) |
| A-007 | `OrderValidationTrigger` is the PRIMARY enforcement; the Q2O flow's `ChecklistValidationService` invocable is a SECONDARY pre-validation |
| A-008 | `Quote_Checklist_Item__c` sharing is Controlled By Parent (inherits Quote sharing), sufficient for ops team access |

## 8. Dependencies

**Internal (all status = Complete):** D-001 Quote w/ standard `IsSyncing` + Opportunity relationship; D-002 Opportunity `StageName` incl. `'Order Processing'`; D-003 Order object for before-insert trigger; D-004 `Fortra_Quote_to_Order_Conversion` flow invoking `ChecklistValidationService`; D-005 Quote record page Lightning layout; D-006 **API Version 62.0+** for all metadata.

**External:** E-001 Salesforce RCA platform w/ Quote & Order (Owner: Salesforce); E-002 Ops user provisioning w/ permission set (Fortra Admin Team); E-003 Quote page layout config (Fortra Admin Team); E-004 Ongoing maintenance of `Operations_Checklist_Config__mdt` records (Fortra Operations Team).

**Open issues:** None explicitly listed in the source. Implicit risk: dual enforcement (trigger + flow) means the flow validation is only user-experience sugar — the trigger is the true gate (see A-007).

---

## 9. CODE-GOVERNING RULES (MUST NOT violate)

1. **`Quote_Checklist_Item__c` MUST be Master-Detail to Quote**, cascade delete, sharing = Controlled By Parent. Do not convert to Lookup — the security model (A-008) and cascade-delete cleanup depend on Master-Detail.
2. **Field types are fixed:** `Item_Name__c` Text(255), `Is_Checked__c` Checkbox (default false), `Checked_By__c` Lookup(User), `Checked_Date__c` DateTime, `Notes__c` Long Text Area(32768), `Sort_Order__c` Number(18,0). Config MDT: `Item_Label__c` Text(255), `Sort_Order__c` Number(18,0), `Is_Active__c` Checkbox, `Icon_Name__c` Text(100), `Category__c` Text(100).
3. **Initialization MUST only create items from `Operations_Checklist_Config__mdt` where `Is_Active__c = true`**, one `Quote_Checklist_Item__c` per active config record, copying `Item_Label__c → Item_Name__c` and `Sort_Order__c → Sort_Order__c`. Check fields default null/false.
4. **Duplicate prevention is mandatory:** before creating items, query existing `Quote_Checklist_Item__c` on the target Quote; if count > 0, skip creation and return the "already initialized" success message. Must survive repeated stage bounce in/out of `'Order Processing'`.
5. **Initialization targets only Quotes where `IsSyncing = true`** for the Opportunity — except in test context, where the `IsSyncing` check is bypassed via the `@TestVisible processOpportunities()` method (because `IsSyncing` is read-only and cannot be set in tests). Do not remove `@TestVisible processOpportunities()`.
6. **Check action MUST set** `Is_Checked__c = true`, `Checked_By__c = UserInfo.getUserId()`, `Checked_Date__c = DateTime.now()`. **Uncheck action MUST set** `Is_Checked__c = false` AND **clear** both `Checked_By__c` and `Checked_Date__c`. The audit fields must never retain stale values after an uncheck.
7. **`OrderValidationTrigger` MUST be before-insert on Order** and use `order.addError()` to block creation when any item is incomplete. This is the PRIMARY hard-stop gate (A-007). Do not downgrade to after-insert or non-blocking. Error message format: `'Cannot convert Quote to Order. The following Operations Checklist items are incomplete: [list of items]'`.
8. **Validation completeness = ALL items checked.** `ValidationResult.isComplete` is true only when every `Quote_Checklist_Item__c.Is_Checked__c = true`; otherwise `incompleteItems` must list every unchecked `Item_Name__c`. `ValidationResult` must carry `isComplete`, `incompleteItems` (List<String>), `errorMessage`, `totalItems`, `completedItems`.
9. **`ChecklistInitializationService` and `ChecklistValidationService` MUST remain `@InvocableMethod`-exposed** (Flow integration): the former for `Initialize_Operations_Checklist`, the latter for `Fortra_Quote_to_Order_Conversion` pre-validation.
10. **All SOQL in `OperationsChecklistController` MUST use `WITH SECURITY_ENFORCED`** (TR-007).
11. **Write access gated by `Operations_Checklist_Access` custom permission**, checked via `FeatureManagement.checkPermission()`. LWC must render read-only when `hasEditPermission` is false. Do not bypass the permission check for edits.
12. **`OperationsChecklistController` public/`@AuraEnabled` surface:** `getChecklistItems` (cacheable), `updateChecklistItem`, `updateChecklistItemNotes`. LWC binds via `@wire(getChecklistItems, { quoteId: '$recordId' })` and calls `refreshApex()` after each mutation. `getChecklistItems` returns `ChecklistData` { items, totalItems, completedItems, completionPercentage, hasEditPermission }.
13. **All metadata components MUST target API Version 62.0+** (D-006).
14. **Configurability is a hard requirement (BR-004):** the checklist item set must remain driven entirely by `Operations_Checklist_Config__mdt` — never hardcode the 37 items in Apex or the LWC.
15. **Maintain ≥85% Apex test coverage** across all classes, covering initialization, validation, permission checks, and edge cases (TR-008).
