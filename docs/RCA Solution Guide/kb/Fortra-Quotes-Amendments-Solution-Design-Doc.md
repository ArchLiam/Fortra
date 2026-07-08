# Fortra Quote Amendments — Solution Design (RCA)

**Source:** `Fortra-Quotes-Amendments-Solution-Design-Doc.txt` — "Quote Amendments Solution Design Document, Fortra Revenue Cloud Implementation, Prepared by Coastal Cloud, April 16, 2026."

**Purpose (one line):** Implements Salesforce Revenue Cloud Advanced (RCA) contract amendments: user clicks the standard **Amend** action on a Contract, a Fortra override flow resolves the asset origin chain and builds a fully-populated Amendment Quote, co-termination logic aligns the amendment Contract end date to the parent, and role/window/discount validation rules gate who can create which amendment types.

---

## 1. Executive Summary

- Amendment process lets users modify existing contracts by creating **amendment Quotes directly from the Contract record**, with full asset context and automated field population.
- Leverages Revenue Cloud's standard **"Amend" action** on the Contract object, **overridden** by a Fortra-specific flow that: resolves the asset origin chain, creates an **Amendment Opportunity**, and populates the amendment Quote with all required reference fields, billing info, and financial tracking fields.
- **Co-termination logic** ensures amendment Contracts automatically align with parent Contract end dates.
- **Role-based validation rules** restrict downsell and cancellation amendments to Customer Operations, and prevent sales users from creating non-upsell amendments during the **120-day renewal window**.
- **Eleven (11) custom fields** on the Quote object track amendment details, financial impact, pro-ration, and audit information.

## 2. Business Goals / Requirements

- Enable contract amendments directly from the Contract record with full asset context.
- Automate amendment Quote creation with proper field population, eliminating manual data entry.
- Enforce co-termination of amendment Contracts to align with parent Contract end dates.
- Restrict downsell and cancellation amendments to Customer Operations roles.
- Prevent sales users from creating non-upsell amendments during the **120-day renewal window**.
- Track financial impact of amendments including ARR changes, credits, pro-ration, and net contract change.

## 3. Solution Overview

- Entry point: Revenue Cloud standard **"Amend" action** on the Contract object.
- That action is **overridden** by `Fortra_Create_Amendment_Quote` flow, which resolves the full asset origin chain to populate the amendment Quote with comprehensive reference data.
- On creation, the amendment Quote is further enriched by `Fortra_RCA_Renewal_Enhancement` flow — a **record-triggered after-save flow** that copies billing addresses, contact information, shipping/billing places, net terms, language preferences, and deal type from the original Quote.
- An **embedded screen flow** (`Fortra_Set_Amendment_Details`) on the Quote record page lets users change the amendment reason from the default **"Upsell"** to other categories (Cross-sell, Downsell, Full Cancellation, billing corrections, etc.).

### 3.1 Data Model — Origin Resolution Chain

The amendment creation flow resolves this relationship chain to populate the Quote:

```
Contract -> Asset -> OrderItem -> Order -> Quote (Original) -> Contract (Source)
```

Linkage of amendment Quote back to origins:
- **`Renewal_Contract__c`** → source Contract (the Contract being amended).
- **`Original_Quote__c`** → the original Quote.
- **`Original_Order_Id__c`** → the original Order.

---

## 4. Component Summary

| Component | Type | Responsibility |
|---|---|---|
| `Fortra_Create_Amendment_Quote` | Flow (Override) | Overrides `quotingAI__createAmendmentQuote` — resolves asset chain, creates Opportunity, calls `initiateAmendment`, populates Quote fields |
| `Fortra_RCA_Renewal_Enhancement` | Flow (Record-Triggered) | After-save on Quote **create** — traces asset origin, copies billing/contact info for `Amend`/`Renew`/`No Change` QuoteActions |
| `Contract_Amendment_CoTermination` | Flow (Record-Triggered) | After-save on Contract **create** — sets amendment Contract `EndDate` to parent Contract `EndDate` |
| `Contract_Amendment_CoTerm_Override_Detection` | Flow (Record-Triggered) | After-save on Contract **update** — detects if user changed `EndDate` away from parent Contract |
| `Fortra_Set_Amendment_Details` | Flow (Screen, Embedded) | Embedded on Quote record page — allows users to change `Amendment_Reason__c` from default |
| Quote Amendment Fields (11) | Custom Fields | Track amendment details, financial impact, pro-ration, audit info |
| Contract Co-Term Fields | Custom Fields | `Co_Term_Overridden__c` tracks manual EndDate changes on amendment Contracts |
| Quote-Amendment Quote Layout | Page Layout | Amendment-specific field arrangement (Amendment Details, Contract Info, Financial Impact sections) |
| `Quote_Record_Page` | FlexiPage | Lightning record page with embedded amendment components |
| 5 Validation Rules | Validation Rules | Enforce contract link, amendment reason, role-based restrictions, discount cap |

---

## 5. Custom Fields

### 5.1 Quote Amendment Fields (11 fields on Quote object)

| Field API Name | Type | Label | Description / Formula |
|---|---|---|---|
| `Amendment_Reason__c` | **Picklist (Required)** | Amendment Reason | Categorizes the amendment. Values: **Upsell, Cross-sell, Downsell, Full Cancellation, Withholding Tax, Billing Correction, Partner Change, Currency Change, Billing Entity Change, Other** |
| `Amendment_ARR_Impact__c` | **Currency** | Amendment ARR Impact | Annual recurring revenue change from the amendment (positive or negative) |
| `Amendment_Effective_Date__c` | **Date** | Amendment Effective Date | When the amendment takes effect |
| `Amendment_Request_Date__c` | **Date** | Amendment Request Date | When the amendment was requested |
| `Original_Contract_ARR__c` | **Formula (Currency)** | Original Contract ARR | Pulls `Expected_Ren_Amount__c` from the linked `Renewal_Contract__c` |
| `Days_Until_Renewal__c` | **Formula (Number)** | Days Until Renewal | Calculates days until contract expiration for renewal window enforcement |
| `Within_Renewal_Window__c` | **Formula (Checkbox)** | Within Renewal Window | **TRUE if within 120 days of contract end date**; triggers role-based restrictions |
| `Pro_Ration_Method__c` | **Picklist** | Pro-Ration Method | Options: **Daily, Monthly (default), Full Period, No Pro-ration** |
| `Pro_Rated_Amount__c` | **Currency** | Pro-Rated Amount | Calculated pro-rated charge or credit for the amendment. **Manually entered** (no automated pro-ration calc in this release) |
| `Credit_Amount__c` | **Currency** | Credit Amount | Credit issued for downgrades or cancellations |
| `Net_Contract_Change__c` | **Formula (Currency)** | Net Contract Change | Formula: **`Amendment_ARR_Impact__c` minus `Credit_Amount__c`** |

> Note: `Amendment_Reason__c` appears in both §5.1 (as the required picklist) and §5.2 (as auto-populated by the override flow, default "Upsell"). It is one field.

### 5.2 Quote Reference Fields (Auto-Populated by Automation)

| Field API Name | Type | Populated By | Description |
|---|---|---|---|
| `Quote_Type__c` | **Picklist** | `Fortra_Create_Amendment_Quote` | Set to **"Amendment"** for amendment quotes |
| `Renewal_Contract__c` | **Lookup (Contract)** | `Fortra_Create_Amendment_Quote` | Links to the Contract being amended |
| `Original_Quote__c` | **Lookup (Quote)** | `Fortra_Create_Amendment_Quote` | Links to the original Quote from the Contract |
| `Original_Order_Id__c` | **Lookup (Order)** | `Fortra_Create_Amendment_Quote` | Links to the original Order |
| `Amendment_Reason__c` | **Picklist** | `Fortra_Create_Amendment_Quote` | Defaults to **"Upsell"**; changeable via `Fortra_Set_Amendment_Details` embedded flow |

### 5.3 Contract Co-Termination Fields

| Field API Name | Type | Object | Description |
|---|---|---|---|
| `Co_Term_Overridden__c` | **Checkbox** | **Contract** | TRUE if user manually changed the amendment Contract `EndDate` to differ from parent Contract `EndDate` |

---

## 6. Process Flow: Amendment Creation

### 6.1 User Journey

1. User navigates to the Contract record page.
2. User selects Assets on the Contract to amend.
3. User clicks the **"Amend"** action (standard Revenue Cloud button).
4. System creates the amendment Quote with all fields auto-populated. **Auto-population of Quote fields can take up to 3 minutes depending on system load.**
5. User reviews the amendment Quote and configures line items in the **Transaction Line Editor (TLE)**.
6. User adjusts Amendment Reason via the embedded `Fortra_Set_Amendment_Details` screen flow (if needed).
7. User submits the amendment for approval and order processing.

### 6.2 Automation Execution Sequence (on "Amend" click)

**Step 1 — `Fortra_Create_Amendment_Quote` (Override Flow).** Overrides standard RCA `quotingAI__createAmendmentQuote`:
- a. Resolves the Asset origin chain: `Asset → OrderItem → Order → Quote → Contract`.
- b. Creates a new **Amendment Opportunity** with **Stage = "Pricing & Approval"** and **`Deal_Origin__c`** from the original Opportunity.
- c. Calls the Revenue Cloud **`initiateAmendment`** action with the resolved **ContractId** and **OpportunityId**.
- d. Sets on the new Quote:
  - `Quote_Type__c = "Amendment"`
  - `Amendment_Reason__c = "Upsell"` (default)
  - `Renewal_Contract__c` = the Contract being amended
  - `Original_Quote__c` = original Quote from the Contract
  - `Original_Order_Id__c` = original Order
  - Billing address fields (**falls back to Account if original Quote lacks them**)
  - `BillToContactId`, `Bill_To_Place__c`, `Ship_To_Place__c`
  - `Net_Terms__c`, `Language__c`, `Deal_Type__c` (preserving **"Fortra Originated"** or **"Channel Originated"**)

**Step 2 — `Fortra_RCA_Renewal_Enhancement` (Record-Triggered Flow).** After-save on Quote creation, fires when a **QuoteAction with Type = "Amend", "Renew", or "No Change"** exists:
- a. Confirms `QuoteAction.Type = "Amend"` for this Quote.
- b. Traces the asset origin to gather additional data from the original transaction.
- c. Copies billing and contact information from the original Quote to the amendment Quote.

**Step 3 — Validation Rules Execute.** The amendment Quote is validated against the 5 active validation rules (see §8).

**Step 4 — User Configuration.** Quote is ready: user adjusts line items in TLE and can modify Amendment Reason via `Fortra_Set_Amendment_Details`.

---

## 7. Contract Co-Termination

When an amendment is converted to an Order and a new amendment Contract is created, co-termination aligns the amendment Contract with the parent Contract's end date.

### 7.1 Automatic Co-Termination — `Contract_Amendment_CoTermination`

Fires as **after-save on Contract creation**:
- **Trigger condition:** `AmendedContractId` **is not null** (identifies this as an amendment Contract).
- **Action:** Sets the amendment Contract's `EndDate` = parent Contract's `EndDate`.
- Sets `Co_Term_Overridden__c = false`.

### 7.2 Override Detection — `Contract_Amendment_CoTerm_Override_Detection`

Fires as **after-save on Contract update**:
- Compares amendment Contract's `EndDate` with parent Contract's `EndDate`.
- If they **differ** → `Co_Term_Overridden__c = true`.
- If they **match** → `Co_Term_Overridden__c = false`.
- Enables reporting on amendments where the co-termination date was manually overridden.

---

## 8. Validation Rules (5)

| Rule Name | Condition | Error Message |
|---|---|---|
| `Amendment_Requires_Contract` | `Quote_Type__c = "Amendment"` AND `Renewal_Contract__c` is blank | Amendment quotes must be linked to the original Contract being amended. |
| `Require_Amendment_Reason` | `Quote_Type__c = "Amendment"` AND `Amendment_Reason__c` is blank | Amendment Reason is required for all amendment quotes. |
| `Sales_Cannot_Create_Downsell` | Amendment with **Downsell or Full Cancellation** reason AND user **NOT** in "Customer Ops" or "Operations" role | Downsell and Cancellation amendments can only be created by Customer Operations. |
| `Enforce_Amendment_Sales_Restriction` | Amendment within 120 days of renewal (`Within_Renewal_Window__c = TRUE`) with **non-Upsell/Cross-sell** reason AND user **NOT** in Ops roles | Sales users cannot create downsell or cancellation amendments during the renewal window. |
| `Enforce_Discount_Cap` | Discount exceeds **30%** without Deal Desk or CFO approval | Discount exceeds the 30% cap. Requires Deal Desk or CFO approval. |

---

## 9. Page Layout — Quote-Amendment Quote Layout (3 sections)

**9.1 Amendment Details Section:** Quote Type (read-only, "Amendment"); Source Contract (`Renewal_Contract__c`, link); Original Contract ARR (read-only formula); User (Quote owner); Amendment Reason (required); Request Date; Effective Date; Within Renewal Window (read-only formula).

**9.2 Related Contract Information Section:** Days Until Renewal (read-only formula).

**9.3 Financial Impact Section:** Amendment ARR Impact; Net Contract Change (read-only formula, ARR Impact minus Credits); Pro-Rated Amount; Pro-Ration Method (Daily / Monthly / Full Period / No Pro-ration); Credit Amount.

---

## 10. Dependencies and Assumptions

**10.1 Dependencies:**
- Revenue Cloud standard **"Amend" action** available on the Contract record page.
- **QuoteAction** object populated with **Type = "Amend"** and **SourceAssetId** during amendment initiation.
- Contract has related Assets with a complete **OrderItem → Order → Quote** chain for origin resolution.
- User roles **"Customer Ops"** and **"Operations"** exist in the org for validation rule enforcement.
- `Renewal_Contract__c` lookup field exists on Quote object.
- `Original_Quote__c` and `Original_Order_Id__c` lookup fields exist on Quote object.

**10.2 Assumptions:**
- `Amendment_Reason__c` defaults to **"Upsell"** and is changeable via the embedded screen flow.
- Co-termination is automatic; users can override by editing the amendment Contract `EndDate`.
- `Pro_Rated_Amount__c` is **manually entered** (no automated pro-ration calculation in this release).
- Financial impact fields (ARR Impact, Credit Amount, Net Contract Change) are **populated manually or calculated by external processes**.
- `Deal_Type__c` on the amendment Quote **preserves** the original deal type ("Fortra Originated" or "Channel Originated").

## 11. Revision History

| Version | Date | Author | Description |
|---|---|---|---|
| 1.0 | January 2025 | Marc DeBrey | Initial Amendment Quote solution design with fields, validation rules, page layout |
| 2.0 | April 2025 | Marc DeBrey | Major revision: Contract-initiated amendment flow (`Fortra_Create_Amendment_Quote` override), RCA Renewal Enhancement automation, co-termination flows, embedded amendment details screen, updated process flow documentation |

---

## CODE-GOVERNING RULES (do not violate when refactoring)

1. **Origin chain is fixed:** amendment population MUST resolve `Asset → OrderItem → Order → Quote → Contract` (equivalently `Contract → Asset → OrderItem → Order → Quote(Original) → Contract(Source)`). Do not shortcut or reorder — downstream reference fields depend on the full chain.
2. **`Fortra_Create_Amendment_Quote` overrides `quotingAI__createAmendmentQuote`** and MUST call the Revenue Cloud **`initiateAmendment`** action with the resolved **ContractId + OpportunityId**. Do not bypass `initiateAmendment`.
3. The override flow MUST create an **Amendment Opportunity** with **Stage = "Pricing & Approval"** and copy **`Deal_Origin__c`** from the original Opportunity before calling `initiateAmendment`.
4. On the new Quote the override MUST set: `Quote_Type__c = "Amendment"`, `Amendment_Reason__c = "Upsell"` (default), `Renewal_Contract__c` = amended Contract, `Original_Quote__c` = original Quote, `Original_Order_Id__c` = original Order.
5. **Billing address fallback:** billing address fields MUST fall back to the Account when the original Quote lacks them. Preserve `BillToContactId`, `Bill_To_Place__c`, `Ship_To_Place__c`, `Net_Terms__c`, `Language__c`, and `Deal_Type__c` (retain "Fortra Originated" / "Channel Originated").
6. **`Net_Contract_Change__c` formula is exactly `Amendment_ARR_Impact__c − Credit_Amount__c`.** Do not change operands or operator.
7. **`Original_Contract_ARR__c` pulls `Expected_Ren_Amount__c` from the linked `Renewal_Contract__c`.** Keep this source field/relationship.
8. **`Within_Renewal_Window__c` is TRUE within 120 days of contract end date.** The 120-day threshold is load-bearing for `Enforce_Amendment_Sales_Restriction`; do not alter the constant.
9. **`Days_Until_Renewal__c`** computes days until contract expiration; it underpins renewal-window enforcement — keep it a formula on the Quote.
10. **`Amendment_Reason__c` is a REQUIRED picklist** with exactly these values: Upsell, Cross-sell, Downsell, Full Cancellation, Withholding Tax, Billing Correction, Partner Change, Currency Change, Billing Entity Change, Other. Default = "Upsell".
11. **`Pro_Ration_Method__c` picklist** = Daily, Monthly (default), Full Period, No Pro-ration.
12. **`Fortra_RCA_Renewal_Enhancement`** is after-save on Quote **create**, gated on a **QuoteAction Type ∈ {"Amend","Renew","No Change"}**, and MUST confirm `QuoteAction.Type = "Amend"` for the current Quote before copying billing/contact info. Preserve the gate.
13. **Co-termination trigger condition** in `Contract_Amendment_CoTermination` is **`AmendedContractId` is not null** — that is the sole identifier of an amendment Contract. On create it MUST set amendment `EndDate = parent EndDate` and `Co_Term_Overridden__c = false`.
14. **`Contract_Amendment_CoTerm_Override_Detection`** (after-save on Contract update) MUST set `Co_Term_Overridden__c = true` when amendment `EndDate ≠ parent EndDate`, and `false` when they match. This drives override reporting — keep bidirectional.
15. **All 5 validation rules must remain enforced** with their exact conditions: contract-link required, reason required, Sales cannot create Downsell/Full Cancellation (only "Customer Ops"/"Operations" roles), no non-Upsell/Cross-sell amendments in the 120-day window for non-Ops users, and **30% discount cap** requiring Deal Desk or CFO approval. Role names "Customer Ops" and "Operations" are the exact allowed roles.
16. **`Pro_Rated_Amount__c` and financial impact fields are manual/external** in this release — do NOT assume or wire an automated pro-ration/ARR calculation without an explicit spec change.
17. **`Quote_Type__c = "Amendment"`** is the discriminator that activates all amendment validation rules and layout; do not repurpose the value.
18. Auto-population is **asynchronous and can take up to 3 minutes** — do not assume synchronous availability of populated Quote fields immediately after "Amend".
