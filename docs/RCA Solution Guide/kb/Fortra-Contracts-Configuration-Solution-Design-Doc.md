# Fortra Contracts Configuration — Solution Design Doc (RCA)

**Purpose (one line):** Contract lifecycle management framework on the standard Salesforce `Contract` object under Revenue Cloud Advanced (RCA) — 19 custom fields, 2 validation rules, 6 Flows, a Lightning Record Page (Dynamic Forms), a Path Assistant, 7 permission sets, and Calendar-Month-Alignment proration — enhancing (not replacing) standard RCA renewal/amendment behavior with Fortra-specific rules.

> Source: "Contracts Configuration Solution Design Document — Prepared for Fortra". This KB is exhaustive and verbatim where values/formulas/types matter. Field types, formulas, picklist value lists, and thresholds are quoted exactly. Do not invent beyond what is stated here.

---

## 1. Executive Summary

- Establishes full contract lifecycle management for the RCA migration: **19 custom fields, 2 validation rules, 6 Flows, a Lightning Record Page with Dynamic Forms, permission sets for FLS, a Path Assistant, and proration configuration.**
- Enhances standard RCA with Fortra-specific logic:
  - Role-based amendment restrictions (preventing Sales from processing downsells, cancellations, and billing corrections).
  - Automated **120-day** renewal window monitoring.
  - RCA renewal quote enhancement with Legal Entity propagation.
  - Contract succession tracking on order activation.
  - Amendment co-termination with parent contract alignment.
- Integrates with: existing **COLA (Cost of Living Adjustment)** pricing infrastructure for renewal quotes, the **Quote-to-Order** conversion pipeline, and the Revenue Cloud **asset management** framework.
- Proration is configured for **Calendar Month Alignment with no partial period billing** for predictable revenue recognition aligned to standard financial reporting periods.

### 1.1 Key Features (verbatim scope)
- **19 custom fields on Contract** spanning: financial tracking (ARR, Amendment Impact, Credits), lifecycle management (Renewal Status, Amendment Reason, Cancellation details), formula calculations (Days Until Expiry, Within Renewal Window), and relationship tracking (Original Contract, Legal Entity, Partner).
- **Role-based amendment restrictions via 2 validation rules:** Sales users cannot select Downsell, Full Cancellation, or billing-related amendment reasons; within the 120-day renewal window, Sales is further restricted to only Upsell and Cross-sell.
- **Automated renewal pipeline with 4 Flows:** scheduled daily monitor for renewal window entry; RCA renewal quote enhancement (Legal Entity + Contract linking); contract succession tracking on order activation; and a deactivated screen flow from initial prototyping.
- **Amendment co-termination via 2 Flows:** auto-populates amendment contract End Date from parent contract; and detects manual overrides setting `Co_Term_Overridden__c` flag.
- **Contract Record Page** with 4-tab structure (Managed Assets default, Details with Dynamic Forms, Obligations, Related Lists) plus Path Assistant with 9 status values.
- **Calendar Month Alignment proration:** billing periods start on the 1st of each month, no partial period billing.
- **7 permission sets** for granular FLS: `Contract_Create`, `Contract_Read`, `Contract_Edit`, `Contract_Delete`, `Import_Data`, `System_Admin_Full_Object`, `sfdc_a360_sfcrm_data_extract`.

---

## 2. Solution Overview

### 2.1 Process Flow Sequence
1. Contract created in **Draft** status via Revenue Cloud order activation or manual entry, with custom fields for **Legal Entity, Solution Group, Deal Type, and Partner** populated.
2. Contract progresses through status lifecycle **Draft → In Review → Negotiating → Awaiting Signature → Activated**, guided by the Path Assistant with contextual guidance at each stage.
3. When the contract enters the **120-day** renewal window, the `Fortra_Contract_Renewal_Window_Monitor` scheduled flow (**daily at 2:00 AM**) automatically sets `Renewal_Status__c` to **Pending**.
4. Users initiate renewal via the **Managed Assets** tab, triggering standard RCA renewal, which creates a Quote with **QuoteAction Type=Renew**.
5. `Fortra_RCA_Renewal_Enhancement` (record-triggered on Quote) detects the renewal QuoteAction and sets `Quote_Type__c=Renewal`, links `Renewal_Contract__c`, and copies `LegalEntityId` from the source contract.
6. When amendments are processed, Sales users are restricted by validation rules from selecting Downsell, Cancellation, or billing-related reasons (**Customer Ops exempt**). Amendment co-termination flows align amendment contract End Date with the parent.
7. Upon order activation from a renewal quote, `Fortra_Renewal_Contract_Succession` updates the **original** contract `Status` to **Renewed** and `Renewal_Status__c` to **Accepted**.
8. Throughout the lifecycle, financial fields (`Contract_ARR__c`, `Amendment_ARR_Impact__c`, `Credit_Amount__c`) track revenue impact, and the Cancellation Details section conditionally appears when **Status equals Canceled**.

### 2.2 Solution Components (component → type → responsibility)

| Component | Type | Responsibility |
|---|---|---|
| Contract Custom Fields (19) | Custom Fields | Financial (`Contract_ARR__c`, `Amendment_ARR_Impact__c`, `Credit_Amount__c`, `Early_Termination_Fee__c`), tracking (`Amendment_Count__c`, `Amendment_Reason__c`, `Renewal_Status__c`, `Cancellation_Reason__c`, `Cancellation_Date__c`, `Auto_Renew__c`, `Co_Term_Overridden__c`), formula (`Days_Until_Expiry__c`, `Within_Renewal_Window__c`), relationship (`Original_Contract__c`, `Legal_Entity__c`, `Partner__c`, `Solution_Group__c`, `Deal_Type__c`, `Parent_Contract_End_Date__c`) |
| `Sales_Cannot_Amend_Downsell` | Validation Rule | Prevents Sales users from selecting restricted amendment types (Downsell, Full Cancellation, Withholding Tax, Billing Correction, Partner Change, Currency Change, Billing Entity Change). **Customer Ops and Operations roles are exempt.** |
| `Sales_Renewal_Window_Restriction` | Validation Rule | Within the 120-day renewal window, restricts Sales users to only **Upsell or Cross-sell** amendment reasons. **Customer Ops and Operations roles are exempt.** |
| `Fortra_Contract_Renewal_Window_Monitor` | Scheduled Flow | Runs **daily at 2:00 AM in System Mode.** Queries activated contracts within 120-day renewal window with no `Renewal_Status__c` and sets status to **Pending**. |
| `Fortra_RCA_Renewal_Enhancement` | Record-Triggered Flow (Quote) | After-save on Quote creation when `Quote_Type__c` is null. Uses **0-minute scheduled path** to query QuoteAction, then sets `Quote_Type__c=Renewal`, `Renewal_Contract__c`, and `LegalEntityId` from source contract. |
| `Fortra_Renewal_Contract_Succession` | Record-Triggered Flow (Order) | After-save on Order when `Status=Activated`. Queries related Quote, checks for renewal type, updates original contract `Status` to **Renewed** and `Renewal_Status__c` to **Accepted**. |
| `Contract_Amendment_CoTermination` | Record-Triggered Flow (Contract) | Auto-populates End Date on amendment contracts to co-terminate with the parent contract by looking up `AmendedContractId` and copying the parent `EndDate`. |
| `Contract_Amendment_CoTerm_Override_Detection` | Record-Triggered Flow (Contract) | Detects when an amendment contract End Date is manually changed from the parent contract End Date and sets `Co_Term_Overridden__c` flag accordingly. |
| `Fortra_Renewal_Quote_Creation` | Screen Flow (**Deactivated**) | Original renewal approach replaced by RCA enhancement. **Retained in Draft status for reference.** |
| `Contract_Record_Page` | FlexiPage | 4-tab Lightning Record Page: **Managed Assets (default)**, Details (Dynamic Forms — 7 field sections incl. conditional Cancellation Details), Obligations, Related Lists. Path Assistant in subheader. |
| `Contract_Status_Path` | Path Assistant | Visual status progression with **9 values**: Draft, In Review, Negotiating, Awaiting Signature, Activated, Amended, Renewed, Canceled, Contract Expired. Includes contextual guidance and key fields at each stage. |
| Permission Sets (7) | Permission Sets | FLS config: `Contract_Create`, `Contract_Read`, `Contract_Edit`, `Contract_Delete`, `Import_Data`, `System_Admin_Full_Object`, `sfdc_a360_sfcrm_data_extract`. Multiple deployment iterations for FLS alignment. |

> **Note on Flow count:** Doc calls out "6 Flows" but lists 7 flow assets — the deactivated `Fortra_Renewal_Quote_Creation` screen flow is retained but not active; the operational set is: 1 scheduled + 3 record-triggered renewal/succession + 2 co-termination = 6 active, plus 1 deactivated.

---

## 3. Requirements

### 3.1 Business Requirements
| ID | Requirement | Priority |
|---|---|---|
| BR-001 | Track contract lifecycle through defined statuses (Draft, In Review, Negotiating, Awaiting Signature, Activated, Amended, Renewed, Canceled, Contract Expired) with visual guidance | High |
| BR-002 | Restrict Sales users from processing downsells, cancellations, and billing-related amendments. Only Customer Ops and Operations roles should have full amendment access. | High |
| BR-003 | Within the 120-day renewal window, further restrict Sales users to only Upsell and Cross-sell amendment types while Customer Ops retains full access | High |
| BR-004 | Automatically detect when contracts enter the 120-day renewal window and set Renewal Status to Pending for tracking/reporting | High |
| BR-005 | When RCA creates renewal quotes, automatically set Quote Type to Renewal, link to the source contract, and copy Legal Entity for proper billing alignment | High |
| BR-006 | When a renewal order is activated, automatically update the original contract Status to Renewed and Renewal Status to Accepted | Medium |
| BR-007 | Track financial metrics: Contract ARR, Amendment ARR Impact, Credit Amount, Early Termination Fee at contract level | Medium |
| BR-008 | Auto-populate amendment contract End Date to co-terminate with the parent contract, with detection/flagging of manual overrides | Medium |
| BR-009 | Configure proration for Calendar Month Alignment with no partial period billing | High |
| BR-010 | Display Cancellation Details (date, reason, early termination fee, credit amount) only when contract Status equals Canceled using conditional visibility | Low |

### 3.2 Technical Requirements
| ID | Requirement | Priority |
|---|---|---|
| TR-001 | All automation flows must run in **System Mode Without Sharing** so scheduled flows can update all contracts and record-triggered flows can access related records regardless of user permissions | High |
| TR-002 | Renewal detection must use a **0-minute scheduled path** on Quote creation to allow QuoteAction records to be created before querying them (**QuoteAction cannot be a Flow trigger object**) | High |
| TR-003 | Contract-to-renewal-quote linking must use **Account-based lookup** (Contract WHERE `AccountId` matches AND `Status=Activated`, sorted by `EndDate DESC`) since **no direct Asset-to-Contract relationship exists in RCA** | Medium |
| TR-004 | PathAssistant and Dynamic Forms field sections must be configured **manually** via Setup UI and Lightning App Builder due to Salesforce metadata API limitations | Medium |
| TR-005 | Permission sets must provide granular FLS across 7 profiles/roles (the 7 named sets) | Medium |
| TR-006 | Validation rules must use `$UserRole.Name` with **CONTAINS** function to check for Customer Ops and Operations role exemptions | Medium |

---

## 4. Assumptions
| ID | Assumption |
|---|---|
| A-001 | RCA is enabled with **Contract Lifecycle Management** record type available for the Contract object. |
| A-002 | The **arcFlow** managed package is installed and operational for standard renewal processing through Managed Assets. |
| A-003 | User roles follow a naming convention where Customer Operations roles contain **'Customer Ops'** and Operations roles contain **'Operations'** in the role name. |
| A-004 | `ContractStatus` picklist values cannot be created/modified via Metadata API. New values (**In Review, Amended, Renewed**) must be created manually through Setup UI. |
| A-005 | Dynamic Forms with field-section visibility rules must be configured through Lightning App Builder and cannot be fully deployed via metadata. |
| A-006 | Existing COLA pricing infrastructure (**COLAUpliftHandler trigger, COLA_Uplift_Rules__mdt**) is deployed and operational for automatic uplift on renewal Quote Line Items. |
| A-007 | For accounts with multiple active contracts, the renewal enhancement flow uses the contract with the **latest EndDate**. More precise contract matching may be needed for complex scenarios. |
| A-008 | Proration config (Calendar Month Alignment, no partial periods) is applied **org-wide** and does not vary by product or customer segment. |

---

## 5. Dependencies

### 5.1 Internal (all status = Complete)
| ID | Dependency |
|---|---|
| D-001 | COLA pricing infrastructure (COLAUpliftHandler, `COLA_Uplift_Rules__mdt`, `Pre_COLA_Price__c`) for automatic COLA application on renewal Quote Line Items |
| D-002 | Quote-to-Order conversion pipeline (`Fortra_Quote_to_Order_Conversion` flow) for order activation triggering contract succession |
| D-003 | Order activation and assetization pipeline (`Fortra_Assetize_Order` flow) for creating Revenue Cloud managed assets linked to contracts |
| D-004 | Quote object custom fields (`Quote_Type__c`, `Renewal_Contract__c`) must exist for renewal flow to set type and link to source contract |
| D-005 | Contract custom fields deployment (**FORTRA-CONTRACT-003**) must be complete before validation rules and flows can reference them |
| D-006 | Proration config (`StartProrationPeriod=AlignToCalendar`, `AllowPartialProrationPeriods=false`) must be set in Revenue Cloud Settings or Context Definition |

### 5.2 External
| ID | Dependency | Owner |
|---|---|---|
| E-001 | Salesforce RCA managed package incl. arcFlow, QuoteAction object, Managed Assets component, Obligations component | Salesforce |
| E-002 | Contract Status picklist values (In Review, Amended, Renewed) manually created via Setup UI | Fortra System Administrator |
| E-003 | Dynamic Forms configuration on Contract Record Page completed manually via Lightning App Builder | Fortra System Administrator |
| E-004 | Managed Assets column configuration (**FORTRA-CONTRACT-005**) and Contract Action Buttons (**FORTRA-CONTRACT-006**) are separate JIRA items pending implementation | Coastal Cloud |

---

## 6. Technical Design

### 6.1 Architecture (layered)
- **UI Layer:** Contract Record Page (Path Assistant, Dynamic Forms, Revenue Cloud components).
- **Business Logic Layer:** validation rules + Flows.
- **Data Model Layer:** 19 custom fields on Contract.
- **Integration Layer:** RCA managed package + COLA infrastructure.
- **Record Page:** 4-tab FlexiPage — Managed Assets (default, primary workflow), Details (Dynamic Forms, 7 sections w/ conditional visibility), Obligations, Related Lists. Path Assistant in subheader.
- **Renewal automation = three-flow pipeline:** (1) scheduled flow monitors window entry daily; (2) record-triggered flow enhances RCA-created renewal quotes; (3) record-triggered flow on Order activation updates original contract status. Enhances rather than replaces standard RCA renewal.
- **Amendment controls:** two validation rules with role-based exemptions + two co-termination flows. VRs check `$UserRole.Name` with CONTAINS for Customer Ops / Operations exemptions.
- **Proration:** org-level Calendar Month Alignment, no partial periods. Billing periods start on the 1st regardless of subscription start date. New subscriptions starting mid-month are charged the **full month**. Amendments take effect at the **next period boundary**.
- **FLS:** 7 permission sets across multiple deployment iterations.

### 6.2 Data Model — Contract custom fields (EXACT types & formulas)

All fields are on the standard **`Contract`** object.

| Field API Name | Type (verbatim) | Notes / verbatim formula |
|---|---|---|
| `Contract_ARR__c` | **Currency(18,2)** | Annual Recurring Revenue for the contract |
| `Amendment_ARR_Impact__c` | **Currency(18,2)** | ARR change from the most recent amendment |
| `Credit_Amount__c` | **Currency(18,2)** | Credit issued on cancellation |
| `Early_Termination_Fee__c` | **Currency(18,2)** | Fee charged for early contract cancellation |
| `Amendment_Count__c` | **Number(18,0)** | Count of amendments processed on this contract |
| `Amendment_Reason__c` | **Picklist** | Values: **Upsell, Cross-sell, Downsell, Full Cancellation, Withholding Tax, Billing Correction, Partner Change, Currency Change, Billing Entity Change, Other** |
| `Renewal_Status__c` | **Picklist** | Values: **Pending, In Progress, Quoted, Accepted, Declined** |
| `Cancellation_Reason__c` | **Picklist** | Values: **Customer Request, Non-Payment, Contract Breach, Business Closure, Competitive Loss, Other** |
| `Cancellation_Date__c` | **Date** | Date the contract was cancelled |
| `Auto_Renew__c` | **Checkbox (default TRUE)** | Indicates if contract should auto-renew |
| `Co_Term_Overridden__c` | **Checkbox** | Flag set when amendment End Date is manually changed from the parent contract End Date |
| `Days_Until_Expiry__c` | **Formula (Number)** | `EndDate - TODAY()` — Days remaining until contract ends |
| `Within_Renewal_Window__c` | **Formula (Checkbox)** | **TRUE when `EndDate` is not blank, `EndDate >= TODAY()`, and `(EndDate - TODAY()) <= 120`** |
| `Original_Contract__c` | **Lookup(Contract)** | Links renewal or amendment contract to the parent/original contract |
| `Legal_Entity__c` | **Lookup(LegalEntity)** | Legal entity associated with the contract for billing |
| `Partner__c` | **Lookup(Account)** | Partner account associated with the contract |
| `Solution_Group__c` | **Text(255)** | Solution group/category for the contract |
| `Deal_Type__c` | **Picklist** | Values: **Distributor - Partner Originated, Distributor - Fortra Originated, Reseller - Partner Originated, Reseller - Fortra Originated, Fortra Originated** |
| `Parent_Contract_End_Date__c` | **Date** | End date of the parent contract, used for co-termination tracking |

> Standard fields referenced by logic (not custom): `Status` (ContractStatus picklist), `EndDate`, `AccountId`, `AmendedContractId`, `LegalEntityId` (on Quote).

### 6.2.1 Field Mappings (source → target, and the mechanism)
| Source | Target | Via |
|---|---|---|
| `Contract.Legal_Entity__c` | `Quote.LegalEntityId` | `Fortra_RCA_Renewal_Enhancement` flow |
| `Contract.Id` | `Quote.Renewal_Contract__c` | `Fortra_RCA_Renewal_Enhancement` flow |
| Literal `'Renewal'` | `Quote.Quote_Type__c` | `Fortra_RCA_Renewal_Enhancement` flow |
| Literal `'Renewed'` | `Contract.Status` | `Fortra_Renewal_Contract_Succession` flow |
| Literal `'Accepted'` | `Contract.Renewal_Status__c` | `Fortra_Renewal_Contract_Succession` flow |
| Literal `'Pending'` | `Contract.Renewal_Status__c` | `Fortra_Contract_Renewal_Window_Monitor` flow |
| Parent `Contract.EndDate` | Amendment `Contract.EndDate` | `Contract_Amendment_CoTermination` flow |
| Proration Config `AlignToCalendar` | `StartProrationPeriod` | Revenue Cloud Settings |

### 6.3 Business Logic (exact conditions)

**VR — `Sales_Cannot_Amend_Downsell`:** Fires when `Amendment_Reason__c` is NOT blank **AND** is one of the restricted values (**Downsell, Full Cancellation, Withholding Tax, Billing Correction, Partner Change, Currency Change, Billing Entity Change**) **AND** the user role does NOT contain `'Customer Ops'` or `'Operations'`.

**VR — `Sales_Renewal_Window_Restriction`:** Fires when `Within_Renewal_Window__c` is TRUE **AND** `Amendment_Reason__c` is NOT blank **AND** is NOT `Upsell` or `Cross-sell` **AND** the user role does NOT contain `'Customer Ops'` or `'Operations'`.

**Renewal Window Monitor:** Runs daily at 2:00 AM. Query: contracts `WHERE Status=Activated AND Within_Renewal_Window__c=TRUE AND Renewal_Status__c IS NULL`. Sets `Renewal_Status__c = Pending` in **bulk**.

**RCA Renewal Enhancement:** Triggered after Quote creation when `Quote_Type__c` is null. Uses **0-minute scheduled path** to allow QuoteAction creation. Queries QuoteAction `WHERE Type=Renew`; if found, queries active Contract for same Account (sorted by `EndDate DESC`) and sets `Quote_Type__c`, `Renewal_Contract__c`, `LegalEntityId`.

**Contract Succession:** Triggered on Order after-save when `Status=Activated`. Queries related Quote; if `Quote_Type__c=Renewal` AND `Renewal_Contract__c` is not null, updates original Contract to `Status=Renewed` and `Renewal_Status__c=Accepted`.

**Amendment Co-Termination:** Triggered on Contract create/update when `AmendedContractId` is populated. Looks up parent contract `EndDate` and sets amendment contract `EndDate` to match. Companion flow detects manual End Date changes and sets `Co_Term_Overridden__c` flag.

**Renewal Status State Machine:**
`(blank) → Pending` (scheduled flow) `→ In Progress` (user action) `→ Quoted` (quote creation) `→ Accepted` (order activation) **or** `→ Declined` (user action).

**Proration Logic (Calendar Month Alignment):**
- All billing periods start on the **1st**.
- New subscriptions starting **mid-month charge full month**.
- Amendments effective at **next period boundary**.
- Cancellations **run to period end with no refund for unused days**.

### 6.4 Integration Points
- **RCA Managed Package:** standard renewal via arcFlow; QuoteAction object detects renewal quotes; Managed Assets component on Record Page for asset mgmt + renewal initiation; Obligations component for obligations tracking.
- **COLA Pricing Infrastructure:** `COLAUpliftHandler` Apex trigger applies COLA to renewal QuoteLineItems using a **three-tier hierarchy**: (1) **Line Override**, (2) **Contract Override** via `COLA_Override_Percent__c`, (3) **CMDT Lookup** via `COLA_Uplift_Rules__mdt` by Solution Category.
- **Quote-to-Order Pipeline:** Order activation triggers `Fortra_Renewal_Contract_Succession`, depending on Q2O flow (`Fortra_Quote_to_Order_Conversion`) and assetization (`Fortra_Assetize_Order`).
- **Revenue Cloud Pricing Engine:** proration parameters (`StartProrationPeriod`, `AllowPartialProrationPeriods`, `ProrationPeriod`) consumed by the pricing procedure's proration element to calculate `ProrationMultiplier` for `PricingTermCount`.
- **Manual Setup Configuration:** PathAssistant requires manual config (PicklistMasterId metadata limitation); Dynamic Forms field sections via Lightning App Builder; Contract Status picklist values created manually via Setup UI.

---

## CODE-GOVERNING RULES (do NOT violate when refactoring)

1. **Renewal window threshold is exactly 120 days.** `Within_Renewal_Window__c` formula MUST remain: TRUE when `EndDate` is not blank AND `EndDate >= TODAY()` AND `(EndDate - TODAY()) <= 120`. The monitor, the VR, and this formula must all use the same 120-day boundary.
2. **`Days_Until_Expiry__c` formula is `EndDate - TODAY()`** (Formula/Number). Do not change return type or add rounding.
3. **Role exemption is name-substring based via `$UserRole.Name` CONTAINS `'Customer Ops'` and `'Operations'`.** Both validation rules MUST exempt roles whose name contains these substrings. Renaming roles away from this convention silently breaks exemptions (A-003).
4. **`Sales_Cannot_Amend_Downsell` restricted set is exactly:** Downsell, Full Cancellation, Withholding Tax, Billing Correction, Partner Change, Currency Change, Billing Entity Change. It fires only when `Amendment_Reason__c` is non-blank and in this set and the user is non-exempt.
5. **`Sales_Renewal_Window_Restriction` allows only `Upsell` and `Cross-sell`** for non-exempt Sales users when `Within_Renewal_Window__c=TRUE`. Any other non-blank reason fires the rule.
6. **QuoteAction cannot be a Flow trigger object.** Renewal detection MUST run on Quote creation via a **0-minute scheduled path** so QuoteAction rows exist before being queried. Do not convert to an immediate/before-save path.
7. **Renewal detection keys off `QuoteAction WHERE Type=Renew`.** The literal RCA action Type is `Renew` (note: the *Quote* field value written is `Renewal`). Keep these distinct.
8. **Contract→renewal-quote linking is Account-based** (`Contract WHERE AccountId matches AND Status=Activated ORDER BY EndDate DESC`, take latest EndDate) because there is **no direct Asset-to-Contract relationship in RCA** (TR-003, A-007). Do not assume an Asset FK.
9. **`Fortra_RCA_Renewal_Enhancement` only acts when `Quote_Type__c` is null** (guard against re-processing). It sets `Quote_Type__c='Renewal'`, `Renewal_Contract__c=Contract.Id`, and `Quote.LegalEntityId=Contract.Legal_Entity__c`.
10. **Contract Succession fires on Order after-save when `Status=Activated`**, only when the related Quote has `Quote_Type__c=Renewal` AND `Renewal_Contract__c` not null; it writes original `Contract.Status='Renewed'` and `Renewal_Status__c='Accepted'`.
11. **All automation flows run in System Mode Without Sharing** (TR-001). Do not switch to user-mode/with-sharing.
12. **Scheduled monitor runs daily at 2:00 AM**, bulk-updates matching contracts to `Renewal_Status__c='Pending'`, and MUST only touch contracts with `Renewal_Status__c IS NULL` (idempotency guard — do not overwrite In Progress/Quoted/Accepted/Declined).
13. **Renewal Status state machine ordering:** `(blank) → Pending → In Progress → Quoted → Accepted|Declined`. Only the scheduled flow sets Pending; only order activation sets Accepted. Do not add transitions that skip the null-guard.
14. **Co-termination is driven by `AmendedContractId`.** `Contract_Amendment_CoTermination` copies parent `EndDate` onto the amendment; `Contract_Amendment_CoTerm_Override_Detection` sets `Co_Term_Overridden__c` when the amendment End Date differs from parent. These two flows must not fight each other (override detection must not re-trigger auto-population).
15. **`Auto_Renew__c` defaults to TRUE.** Preserve the default when refactoring field metadata.
16. **All four currency fields are Currency(18,2); `Amendment_Count__c` is Number(18,0).** Do not change scale/precision.
17. **Proration is org-wide, no per-product/segment variation (A-008):** `StartProrationPeriod=AlignToCalendar` and `AllowPartialProrationPeriods=false`. Billing periods start on the 1st; mid-month starts charge full month; amendments effective at next period boundary; cancellations run to period end with **no refund for unused days**. Do not introduce partial-period billing.
18. **COLA three-tier precedence (highest→lowest): Line Override → Contract Override (`COLA_Override_Percent__c`) → CMDT (`COLA_Uplift_Rules__mdt` by Solution Category).** Any refactor of COLA application must preserve this precedence order.
19. **ContractStatus picklist values (In Review, Amended, Renewed) are NOT deployable via Metadata API** (A-004, E-002) — they are created manually in Setup UI. Do not assume metadata deploy will create them; code/flows must tolerate their manual existence.
20. **PathAssistant + Dynamic Forms field sections are manual (Setup UI / Lightning App Builder), not metadata-deployable** (TR-004, A-005). Cancellation Details section is conditionally visible only when `Status='Canceled'` (BR-010) — preserve that visibility rule.
21. **The 9 Contract status path values are:** Draft, In Review, Negotiating, Awaiting Signature, Activated, Amended, Renewed, Canceled, Contract Expired. (Note spelling: **Canceled** one-l; **Contract Expired**.)
22. **Field mapping literal-vs-copy semantics:** `Quote.Quote_Type__c` is literal `'Renewal'`; `Contract.Status` succession literal is `'Renewed'`; `Contract.Renewal_Status__c` is literal `'Accepted'` (succession) or `'Pending'` (monitor). `LegalEntityId` and `Renewal_Contract__c` are copied references, not literals.
23. **Dependencies D-004/D-005 are prerequisites:** Quote fields (`Quote_Type__c`, `Renewal_Contract__c`) and Contract custom fields (FORTRA-CONTRACT-003) must exist before flows/VRs reference them. Do not reorder deploys ahead of these.
