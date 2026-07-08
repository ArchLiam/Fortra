# Quote Line Auto-Population — Solution Design

**Source:** `Quote_Line_Auto_Population_Solution_Design_(1).txt` — Solution Design Document, "Quote Line Auto-Population", Prepared for Fortra by Coastal, April 6, 2026.

**One-line purpose:** Replaces Salesforce CPQ "Product Rule / Add action" cross-product auto-add (which Revenue Cloud Advanced has no native equivalent for at transaction scope) with a data-driven custom mapping object (`Quote_Line_Companion_Rule__c`) plus two record-triggered Flows that auto-add and auto-remove companion `QuoteLineItem` lines.

**Status note:** This is a DESIGN document. Several mechanisms are explicitly "to be determined during implementation" (notably the Step 9 reprice-flag mechanism). No Apex class names for new code are given — the solution is Flow-based. Target org = `fortradp2`.

---

## 1. Executive Summary

- Fortra CPQ-to-Revenue Cloud migration requires automatically adding **companion products** to quotes when specific **trigger products** are selected.
- In CPQ this used **Product Rules with "Add" actions** that dynamically resolved companion products via **Lookup Queries at quote scope**. Revenue Cloud Advanced (RCA) has **no native equivalent** for standalone cross-product auto-add at the transaction level.
- Solution = hybrid: custom mapping object `Quote_Line_Companion_Rule__c` + record-triggered Flows for auto-population and auto-removal of companion quote line items.
- Supports: **product-specific** rules AND **Product Classification-level** rules; **multiple companions per trigger product**; **configurable quantity modes**.
- Designed to scale to **thousands of products** without per-product configuration rules. Companion relationships are **data records** maintainable by business users via list views, reports, or data loader (no developer needed).

### 1.1 Key Benefits (verbatim)
- **Data-Driven Scalability:** Companion rules are data records, not declarative rules. Add 1,000 mappings via CSV upload without touching configuration.
- **Classification-Level Rules:** A single mapping record for a Product Classification covers all products in that classification automatically.
- **Hybrid Pricing:** Companion lines are pre-priced from PricebookEntry on insert and flagged for full pricing engine processing on next TLE open.
- **Auto-Remove:** When a trigger product is removed from a quote, its companion lines are automatically removed, maintaining data integrity.

---

## 2. Overview / Problem Statement

- Fortra catalog = thousands of products; many have **mandatory companion relationships** (e.g., support SKUs required for software subscriptions, compliance add-ons for regulated products, maintenance contracts paired with hardware).
- CPQ enforced these with Product Rules "Add" actions that: operated at quote scope, dynamically resolved companions via Lookup Queries, fired during the Quote Line Editor (TLE) session.

### 2.1 Why native RCA mechanisms are insufficient (Gap Analysis — verbatim)
| Revenue Cloud Mechanism | Can Auto-Add Lines? | Limitation |
|---|---|---|
| Configuration Rules (BRE) | Yes, within bundle scope only | Cannot add standalone transaction-level lines. Action target is static (one fixed companion per rule). |
| Pricing Prehooks / Posthooks | No | Context API provides `queryTags()` and `updateContextAttributes()` only. No `addNode()` or DML capability. |
| CML Constraint Rules | Yes, within bundle scope only | require/exclude rules operate within a configured bundle's type hierarchy. |
| Record-Triggered Flows | Yes, after TLE save | Lines are added post-save, not during the TLE session. Requires reprice for pricing engine processing. |

### 2.2 Solution Approach (two components)
1. **Custom Mapping Object `Quote_Line_Companion_Rule__c`** — data-driven config: trigger product (or Product Classification), companion product to add, quantity mode.
2. **Record-Triggered Flows (two):**
   - **Auto-populate flow:** fires **asynchronously after QuoteLineItem insert** (AsyncAfterCommit pattern); queries matching companion rules; checks for duplicates; inserts companion QuoteLineItems with pre-priced values.
   - **Auto-remove flow:** fires **before QuoteLineItem delete**; detects if deleted line is a trigger product; removes its companion lines.

### 2.3 Architecture Flow (verbatim sequences)
- **Auto-Populate:** User saves TLE → QuoteLineItem inserted → Record-Triggered Flow (AsyncAfterCommit) → Query `Quote_Line_Companion_Rule__c` for matching rules → Check for existing companion lines (dedup) → Insert companion QuoteLineItems with PricebookEntry pricing → Flag Quote for reprice.
- **Auto-Remove:** User deletes QuoteLineItem → Record-Triggered Flow (Before Delete) → Query `Quote_Line_Companion_Rule__c` to check if deleted line is a trigger → Find companion lines (via `Auto_Populated_By__c` lookup) → Delete companion QuoteLineItems.

---

## 3. Requirements

### 3.1 Functional Requirements (verbatim, all Must Have)
- **FR-001:** When a QuoteLineItem is created whose `Product2` matches a trigger product in an active companion rule, the system shall automatically create companion QuoteLineItem(s) on the same Quote.
- **FR-002:** When a QuoteLineItem is created whose `Product2` belongs to a Product Classification matching an active companion rule, the system shall automatically create companion QuoteLineItem(s) on the same Quote.
- **FR-003:** A single trigger product shall support multiple companion products, each defined as a separate `Quote_Line_Companion_Rule__c` record.
- **FR-004:** Each companion rule shall support configurable quantity modes: **Match Trigger** (companion quantity equals trigger quantity), **Fixed** (specified quantity), or **Ratio** (trigger quantity multiplied by a ratio).
- **FR-005:** Companion QuoteLineItems shall be pre-priced using `UnitPrice` and `ListPrice` from the matching PricebookEntry, and the parent Quote shall be flagged for full reprice on next TLE open.
- **FR-006:** Companion QuoteLineItems shall be linked to their trigger line via a lookup field (`Auto_Populated_By__c`) and flagged as auto-populated (`Is_Auto_Populated__c = true`).
- **FR-007:** When a user attempts to manually delete an auto-populated companion line, the system shall display a warning that the line is required by its trigger product.
- **FR-008:** When a trigger product QuoteLineItem is deleted, the system shall automatically delete all companion QuoteLineItems linked to it.
- **FR-009:** The system shall not create duplicate companion lines. If a companion product already exists on the Quote (whether manually added or auto-populated), the flow shall skip insertion for that companion.

### 3.2 Technical Requirements (verbatim, all Must Have)
- **TR-001:** The auto-populate flow shall use the **AsyncAfterCommit** scheduled path to execute asynchronously after the QuoteLineItem insert transaction commits, following the established **`Fortra_Asset_Populate_Legacy_Fields`** pattern.
- **TR-002:** The auto-remove flow shall use the **Before Delete** trigger type to detect and remove companion lines before the trigger line is deleted.
- **TR-003:** Companion rule lookups shall be **bulkified** to support batch QuoteLineItem creation (e.g., from Quote-to-Order conversion or data migration).
- **TR-004:** The solution shall not interfere with Revenue Cloud pricing engine operations. Companion lines inserted via Flow DML are outside the pricing context and require separate reprice.
- **TR-005:** The custom object and flows shall be deployable via Salesforce CLI (`sf project deploy`) with appropriate `package.xml` metadata.
- **TR-006:** All companion rule records shall support an `Is_Active__c` flag to enable/disable rules without deletion.

---

## 4. Assumptions (verbatim, with impact-if-invalid)
- **A-001:** Rules based solely on trigger product or its Product Classification. **No** additional conditions on Account/Opportunity/Quote fields in initial release. *(Impact: additional filter fields would need adding to object + Flow.)*
- **A-002:** All companion products have **active PricebookEntry records in the same Pricebook as the parent Quote**; Flow retrieves pricing from PricebookEntry without ambiguity. *(Impact: lines inserted without pricing.)*
- **A-003:** AsyncAfterCommit timing is acceptable — companion lines appear **after** TLE save, not during the TLE session. *(Impact: if in-session auto-add required, redesign as bundles with Configuration Rules BRE/CML.)*
- **A-004:** Product Classification values consistently maintained on Product2. *(Impact: classification-level rules miss products with missing/incorrect classification.)*
- **A-005:** `Quote_Line_Companion_Rule__c` managed by business administrators who understand catalog relationships. *(Impact: incorrect rules → wrong companions.)*
- **A-006:** Companion lines do **not** themselves trigger further companion rules (no cascading/recursive auto-population). *(Impact: recursion would need explicit guard/depth-limit logic.)*
- **A-007:** Existing `QuoteLineItemTrigger` (Apex) does not conflict with new record-triggered Flows; order of execution follows standard Salesforce trigger/flow ordering. *(Impact: trigger conflicts → unexpected behavior / governor issues.)*
- **A-008:** Target org (`fortradp2`) has Revenue Cloud Advanced with Product Catalog Management enabled and necessary Product Classifications defined. *(Impact: classification-level rules untestable until classifications configured.)*

---

## 5. Dependencies

### 5.1 Platform Dependencies
- **Revenue Cloud Advanced (RLM)** — Platform Feature. Required for TLE, pricing engine, Product Classification objects.
- **Product Catalog Management** — Platform Feature. Required for Product Classifications used in classification-level rules.
- **Record-Triggered Flows (AsyncAfterCommit)** — Platform Feature. **Available in API version 56.0+.** Required for async post-save pattern.
- **PricebookEntry** — Standard Object. Companion lines pre-priced from PricebookEntry; all companion products must have active entries in relevant Pricebook.

### 5.2 Existing Fortra Component Dependencies
- **`QuoteLineItemTrigger`** (Apex Trigger) — Existing before insert/update trigger. New Flows must coexist. Standard order of execution: triggers fire before flows.
- **`Fortra_QuoteLineItem_Legal_Entity_Copy`** (Record-Triggered Flow) — Existing after-save Flow on QuoteLineItem Create. New auto-populate flow uses AsyncAfterCommit (separate transaction) → no conflict expected.
- **`Fortra_QuoteLineItem_Calculate_ARR`** (Record-Triggered Flow, **Draft**) — Before-save Flow on QuoteLineItem Create/Update. Will fire for **both** trigger and companion lines. Companion lines must have necessary fields populated for ARR calculation.

---

## 6. Data Model

### 6.1 Custom Object: `Quote_Line_Companion_Rule__c`
Stores mapping between trigger products and required companion products. One record = one trigger-to-companion relationship. A trigger product can have multiple records. Rules at individual product level OR Product Classification level.

**Object Definition:**
| Property | Value |
|---|---|
| API Name | `Quote_Line_Companion_Rule__c` |
| Label | Quote Line Companion Rule |
| Plural Label | Quote Line Companion Rules |
| Name Field | Auto-Number, format `QLCR-{00000}` |
| Description | Defines trigger-to-companion product relationships for automatic quote line population. |

**Field Specifications (8 fields — API name, label, TYPE verbatim):**
| Field API Name | Label | Type | Required | Notes |
|---|---|---|---|---|
| `Trigger_Product__c` | Trigger Product | **Lookup(Product2)** | No* | Specific product that triggers companion auto-population. Either this or `Trigger_Classification__c` must be populated. |
| `Trigger_Classification__c` | Trigger Classification | **Text(255)** | No* | Product Classification **DeveloperName** that triggers auto-population. All products in this classification trigger the rule. |
| `Companion_Product__c` | Companion Product | **Lookup(Product2)** | **Yes** | Product to automatically add when trigger condition met. |
| `Quantity_Mode__c` | Quantity Mode | **Picklist** | **Yes** | Values: **Match Trigger**, **Fixed**, **Ratio**. Determines how companion line quantity is calculated. |
| `Fixed_Quantity__c` | Fixed Quantity | **Number(10,2)** | No | Quantity used when `Quantity_Mode__c = Fixed`. Ignored for other modes. |
| `Quantity_Ratio__c` | Quantity Ratio | **Number(10,4)** | No | Multiplier applied to trigger line quantity when `Quantity_Mode__c = Ratio`. Example: 0.5 means companion qty = trigger qty × 0.5. |
| `Is_Active__c` | Active | **Checkbox** | **Yes** | **Default: true.** When false, rule ignored by auto-populate flow. |
| `Description__c` | Description | **Long Text Area(1000)** | No | Business justification/notes for the companion relationship. |

**\* Validation Rule (verbatim):** At least one of `Trigger_Product__c` or `Trigger_Classification__c` must be populated. **If both are populated, `Trigger_Product__c` takes precedence** (product-specific rules override classification-level rules).

### 6.2 Custom Fields added to `QuoteLineItem` (3 fields — verbatim)
| Field API Name | Label | Type | Default | Purpose |
|---|---|---|---|---|
| `Is_Auto_Populated__c` | Auto-Populated | **Checkbox** | **false** | Set true on companion lines inserted by auto-populate flow. Identifies auto-populated lines in UI AND prevents recursive triggering (used in Flow entry condition). |
| `Auto_Populated_By__c` | Auto-Populated By | **Lookup(QuoteLineItem)** (self-lookup) | **null** | Points to the trigger QuoteLineItem that caused this companion line. Used by auto-remove flow to find/delete companions when trigger removed. |
| `Companion_Rule__c` | Companion Rule | **Lookup(`Quote_Line_Companion_Rule__c`)** | **null** | References the companion rule that caused this line. Traceability/audit. |

---

## 7. Business Logic / Flows

### 7.1 Flow 1: `Fortra_QLI_Auto_Populate_Companions`

**Configuration (verbatim):**
| Property | Value |
|---|---|
| Flow Type | Record-Triggered Flow |
| Object | QuoteLineItem |
| Trigger | A record is created |
| Trigger Type | **RecordAfterSave** |
| Scheduled Path | **AsyncAfterCommit** (runs in a separate transaction after the initial DML commits) |
| Entry Condition | **`Is_Auto_Populated__c = false`** (prevents recursive triggering when companion lines are themselves inserted) |

**Flow Logic (step by step, verbatim):**
1. **Get Trigger Product Details:** Retrieve the `Product2` record for the triggering QuoteLineItem, including the Product Classification field. Needed to match both product-specific and classification-level rules.
2. **Query Matching Companion Rules:** Query `Quote_Line_Companion_Rule__c` `WHERE (Trigger_Product__c = :product2Id OR Trigger_Classification__c = :productClassification) AND Is_Active__c = true`.
3. **Decision — Rules Found?** If no matching rules, flow terminates.
4. **Get Existing Quote Lines:** Query all QuoteLineItems on the same Quote (`QuoteId = :triggerQLI.QuoteId`) to check for existing companion products (prevents duplicate insertion).
5. **Loop Through Rules:** For each matching rule, check if `Companion_Product__c` already exists on the quote. If not, proceed to create.
6. **Get PricebookEntry:** For each new companion product, query PricebookEntry `WHERE Product2Id = :companionProductId AND Pricebook2Id = :quote.Pricebook2Id AND IsActive = true`. Provides ListPrice for pre-pricing.
7. **Calculate Quantity** (per `Quantity_Mode__c`):
   - **Match Trigger:** quantity = trigger QLI quantity.
   - **Fixed:** quantity = `Fixed_Quantity__c`.
   - **Ratio:** quantity = trigger QLI quantity × `Quantity_Ratio__c`.
8. **Create Companion QuoteLineItem** — field mappings (verbatim):
   | Companion QLI Field | Value Source |
   |---|---|
   | `QuoteId` | Trigger QLI's `QuoteId` |
   | `Product2Id` | Companion Rule's `Companion_Product__c` |
   | `PricebookEntryId` | Looked-up `PricebookEntry.Id` |
   | `Quantity` | Calculated per `Quantity_Mode__c` |
   | `UnitPrice` | **`PricebookEntry.UnitPrice`** |
   | `ListPrice` | **`PricebookEntry.UnitPrice`** (note: ListPrice ALSO sourced from PricebookEntry.UnitPrice, not a separate list field) |
   | `ServiceDate` | Trigger QLI's `ServiceDate` |
   | `Is_Auto_Populated__c` | **true** |
   | `Auto_Populated_By__c` | Trigger QLI's `Id` |
   | `Companion_Rule__c` | Companion Rule's `Id` |
9. **Flag Quote for Reprice:** After inserting all companion lines, update parent Quote to indicate reprice needed, so pricing engine processes companion lines on next TLE open. **The specific reprice flag mechanism will be determined during implementation based on the org's pricing configuration.** (OPEN / TBD.)

### 7.2 Flow 2: `Fortra_QLI_Auto_Remove_Companions`

**Configuration (verbatim):**
| Property | Value |
|---|---|
| Flow Type | Record-Triggered Flow |
| Object | QuoteLineItem |
| Trigger | A record is deleted |
| Trigger Type | **RecordBeforeDelete** |

**Flow Logic (step by step, verbatim):**
1. **Decision — Is this an auto-populated line being deleted?** Check `Is_Auto_Populated__c = true`. If yes → companion line being deleted directly (warn user). If no → check if it's a trigger product.
2. **Query Companion Lines:** Query QuoteLineItems `WHERE Auto_Populated_By__c = :deletedQLI.Id`.
3. **Decision — Companion Lines Found?** If exist, delete them. If none, flow terminates (deleted line was not a trigger).
4. **Delete Companion Lines:** Delete all QuoteLineItems found in Step 2 (cascades companion removal when trigger removed).

### 7.3 Pricing Strategy (hybrid, two-stage)
| Stage | Action | Details |
|---|---|---|
| **On Insert (Immediate)** | Pre-price from PricebookEntry | `UnitPrice` and `ListPrice` set from PricebookEntry record → reasonable default price visible immediately. Subscription term fields (`ServiceDate`, `EndDate`, `SubscriptionTerm`) copied from trigger QLI where applicable. |
| **On Next TLE Open (Deferred)** | Full pricing engine processing | Quote flagged for reprice. On next TLE open, RCA pricing engine processes companion lines through full pricing waterfall (**prehooks, Expression Set, posthooks**), applying regional pricing, partner discounts, COLA uplift, and other pricing logic. |

### 7.4 Rule Precedence and Conflict Resolution (verbatim)
When both a product-specific rule AND a classification-level rule match for the same trigger product AND specify the same companion product, the **product-specific rule takes precedence**. Evaluation order:
1. Product-specific rules (`Trigger_Product__c` populated) evaluated **first**.
2. Classification-level rules (`Trigger_Classification__c` populated) evaluated **second**.
3. If a companion product is already covered by a product-specific rule, the classification-level rule for the same companion is **skipped** (deduplication).

### 7.5 Recursion Prevention (two mechanisms)
1. **Entry Condition Filter:** Flow entry condition checks `Is_Auto_Populated__c = false`. Companion lines inserted with `Is_Auto_Populated__c = true` → do not satisfy entry condition → flow does not fire for them.
2. **Design Constraint (A-006):** Companion products assumed NOT to themselves be trigger products. Cascading would require explicit depth-limiting logic.

---

## 8. User Experience

### 8.1 Companion Line Visibility
Auto-populated lines distinguished via `Is_Auto_Populated__c` checkbox — addable to QuoteLineItem list view, related list, report layouts. `Auto_Populated_By__c` lookup links to trigger line for traceability.

### 8.2 Locked-with-Warning Behavior (FR-007)
When user attempts to delete an auto-populated line (`Is_Auto_Populated__c = true`) directly (not by removing trigger), a validation displays a warning. **Does NOT hard-block deletion** — displays a confirmation message that the line is required by the trigger product. Two implementation options:
- **Option A — Validation Rule:** VR on QuoteLineItem firing on delete when `Is_Auto_Populated__c = true` and delete not initiated by auto-remove flow. **CAVEAT (verbatim):** Standard Salesforce validation rules do NOT fire on delete → requires Apex trigger-based approach OR a Before Delete flow with custom error message.
- **Option B — Before Delete Flow with Custom Error:** The auto-remove flow (`Fortra_QLI_Auto_Remove_Companions`) checks if deleted line is auto-populated AND has an active trigger line still on the quote. If so, adds a fault element with descriptive error → blocks deletion with warning, while still permitting deletion when the trigger line itself is being removed (auto-remove flow handles cleanup in that case).

---

## 9. CPQ → Revenue Cloud Feature Comparison (Appendix A, verbatim)
| CPQ Capability | Revenue Cloud Native | Gap? | This Solution |
|---|---|---|---|
| Product Rule 'Add' action within bundle | Configuration Rule (BRE Requirement/Inclusion) | No gap | Not needed — use native Configuration Rules |
| Product Rule 'Add' action across quote (standalone) | No native equivalent | **GAP** | `Quote_Line_Companion_Rule__c` + auto-populate Flow |
| Product Rule with Lookup Query (dynamic target) | No equivalent — Configuration Rule actions have static targets | **GAP** | Data-driven mapping object (unlimited rules via data) |
| Product Rule 'Remove/Hide' action | Configuration Rule (BRE Exclusion) | No gap | Not needed — use native Configuration Rules |
| Product Rule scope by Product Family/custom field | `RuleSubType = ProductClassification` (classification only) | Partial gap | `Trigger_Classification__c` field on companion rules |
| Quote-level validation (companion required) | No native cross-product validation at transaction level | **GAP** | Locked-with-warning pattern on companion lines |

---

## 10. Future Enhancements (Appendix B — OUT OF SCOPE for initial release)
- **Conditional Rules** (Medium): add filter fields (Account Region, Order Type, etc.) for context-dependent logic.
- **Cascading Companions** (High): allow companions to trigger further rules, with depth-limiting.
- **Quantity Sync on Update** (Medium): when trigger QLI quantity updated, auto-update companion qty per rule mode. *(Note: initial release does NOT sync quantity on update — only on insert.)*
- **Companion Rule UI** (Medium): custom LWC on Quote page showing active rules and satisfied/missing status.
- **OrderItem Support** (Low): extend Flows to OrderItem for direct Order creation scenarios. *(Initial release is QuoteLineItem only.)*

---

## 11. Deployment Components (Appendix C — target org `fortradp2`)
- `Quote_Line_Companion_Rule__c` — CustomObject (auto-number name field).
- `Quote_Line_Companion_Rule__c` fields (8) — CustomField (all per §6.1.2).
- `QuoteLineItem.Is_Auto_Populated__c` — CustomField (Checkbox).
- `QuoteLineItem.Auto_Populated_By__c` — CustomField (Self-lookup).
- `QuoteLineItem.Companion_Rule__c` — CustomField (Lookup to `Quote_Line_Companion_Rule__c`).
- `Fortra_QLI_Auto_Populate_Companions` — Flow (After Save, AsyncAfterCommit).
- `Fortra_QLI_Auto_Remove_Companions` — Flow (Before Delete).
- `Quote_Line_Companion_Rule__c` (FLS) — PermissionSet / Profile — field-level security for the custom object and new QLI fields.

---

## CODE-GOVERNING RULES (an engineer refactoring MUST NOT violate)

1. **Auto-populate flow MUST run on `RecordAfterSave` create with the `AsyncAfterCommit` scheduled path** (separate transaction after insert commit), following the `Fortra_Asset_Populate_Legacy_Fields` pattern. Requires API version 56.0+. (TR-001, §6.3.1)
2. **Auto-populate flow entry condition MUST be `Is_Auto_Populated__c = false`.** This is a primary recursion guard — companion lines are inserted with `Is_Auto_Populated__c = true` and must not re-fire the flow. (§6.3.1, §6.8)
3. **Companion lines MUST be inserted with `Is_Auto_Populated__c = true`, `Auto_Populated_By__c = <trigger QLI Id>`, and `Companion_Rule__c = <rule Id>`.** These three stamps drive recursion prevention, auto-removal, and audit traceability respectively. (FR-006, §6.2, Step 8)
4. **Rule query MUST filter `Is_Active__c = true`** and match `(Trigger_Product__c = :product2Id OR Trigger_Classification__c = :productClassification)`. Inactive rules must never fire. (TR-006, Step 2)
5. **Deduplication is mandatory: MUST NOT create a companion line if that companion product already exists on the Quote** (manually added or auto-populated). Check existing QuoteLineItems on the same `QuoteId` before insert. (FR-009, Step 4/5)
6. **Quantity computation MUST follow `Quantity_Mode__c` exactly:** `Match Trigger` → trigger QLI quantity; `Fixed` → `Fixed_Quantity__c`; `Ratio` → trigger QLI quantity × `Quantity_Ratio__c`. Picklist values are exactly `Match Trigger`, `Fixed`, `Ratio`. (FR-004, Step 7)
7. **Companion pricing MUST source both `UnitPrice` AND `ListPrice` from `PricebookEntry.UnitPrice`** of the matching entry (`Product2Id = companion`, `Pricebook2Id = quote.Pricebook2Id`, `IsActive = true`). Note both QLI fields map to `PricebookEntry.UnitPrice`. (FR-005, Step 6/8)
8. **After inserting companion lines, the Quote MUST be flagged for reprice** so the pricing engine reprocesses them on next TLE open. Companion lines are inserted outside the pricing context via Flow DML and MUST NOT be assumed final-priced. The exact reprice-flag mechanism is org-config-dependent and TBD at implementation. (FR-005, TR-004, Step 9, §6.5)
9. **`ServiceDate` (and where applicable `EndDate`, `SubscriptionTerm`) MUST be copied from the trigger QLI** to the companion line. (Step 8, §6.5)
10. **Auto-remove flow MUST run on `RecordBeforeDelete`** and delete all QuoteLineItems `WHERE Auto_Populated_By__c = :deletedQLI.Id`. Deleting a trigger MUST cascade-delete its companions. (TR-002, FR-008, §6.4)
11. **Field type/precision constraints MUST be preserved:** `Trigger_Classification__c` = Text(255) holding the Product Classification **DeveloperName**; `Fixed_Quantity__c` = Number(10,2); `Quantity_Ratio__c` = Number(10,4); `Description__c` = Long Text Area(1000); `Is_Active__c` = Checkbox default true. (§6.1.2)
12. **Object validation rule MUST enforce: at least one of `Trigger_Product__c` or `Trigger_Classification__c` populated; if both, `Trigger_Product__c` takes precedence.** (§6.1.2 note)
13. **Rule precedence MUST be: product-specific rules evaluated first, classification-level second; a classification rule for a companion already covered by a product-specific rule MUST be skipped (dedup).** (§6.7)
14. **All rule lookups MUST be bulkified** to handle batch QuoteLineItem creation (Quote-to-Order conversion, data migration). No per-record SOQL/DML inside loops. (TR-003)
15. **The solution MUST NOT interfere with the RCA pricing engine or the pricing context** — companion insertion happens via Flow DML outside pricing; do not attempt to price within the pricing waterfall. (TR-004)
16. **Recursion assumption (A-006): companion products are assumed NOT to be trigger products themselves. There is NO cascading/depth-limiting logic in the initial release** — do not add companion products that are also triggers without introducing explicit depth-limiting guards. (A-006, §6.8)
17. **Initial scope is QuoteLineItem only** — do not silently extend to OrderItem; that is a future enhancement. Quantity is NOT synced on trigger-quantity update in the initial release (insert-time only). (Appendix B)
18. **Locked-with-warning MUST NOT hard-block deletion.** Standard VRs do not fire on delete, so use a Before Delete flow (or Apex) custom-error approach that still permits deletion when the trigger line itself is being removed (auto-remove path). (FR-007, §6.6.2)
19. **New Flows MUST coexist with the existing `QuoteLineItemTrigger` Apex** (triggers fire before flows) and with existing Flows `Fortra_QuoteLineItem_Legal_Entity_Copy` and draft `Fortra_QuoteLineItem_Calculate_ARR`. Companion lines MUST carry the fields those flows need (e.g., ARR-calculation fields). (A-007, §5.2)
20. **Deploy via Salesforce CLI (`sf project deploy`) with `package.xml`**, including FLS (PermissionSet/Profile) for the new object and QLI fields to `fortradp2`. (TR-005, Appendix C)
