# Fortra Contract Renewals — Solution Design (RCA)

**Source:** `Fortra-Contract-Renewals-Solution-Design-Doc.txt` — "Contract Renewals Solution Design Document, Fortra Revenue Cloud Implementation", prepared by Coastal Cloud, April 16, 2026. Rev 1.0 (April 2025, Marc DeBrey).

**Purpose (one line):** Implement Contract Renewals in Fortra's Salesforce Revenue Cloud Advanced (RCA) — scheduled renewal-window detection, standard "Renew" action from Contract Managed Assets, renewal-Quote enrichment, automated COLA (Cost of Living Adjustment) pricing via a 3-tier override hierarchy, MyCAP out-year uplift enforcement, and contract succession on order activation.

---

## 1. Executive Summary

Users renew existing contracts by selecting Assets on the Contract record and initiating a renewal Quote through Revenue Cloud's standard **"Renew"** action. The solution provides:
- A **scheduled flow** that monitors contracts approaching their **120-day renewal window** and marks them `Pending`.
- A **record-triggered flow** that enriches renewal Quotes with original-contract data + billing info.
- **COLA pricing** applied automatically via a **trigger-based handler** (before insert on QuoteLineItem).
- **Contract succession** logic marking the original contract `Renewed` when the renewal order is activated.
- **Role-based validation** preventing sales users from creating non-upsell amendments during the renewal window.

---

## 2. Business Goals / Requirements

- Automate detection of contracts entering the **120-day renewal window**.
- Enable renewals directly from the Contract record with full asset context via standard Revenue Cloud actions.
- Auto-populate renewal Quotes with original contract data, billing addresses, contact information, and financial terms.
- Apply COLA pricing automatically during renewal quote line creation using a **configurable three-tier hierarchy**.
- Track the renewal lifecycle from window detection through contract succession.
- Enforce role-based restrictions during the renewal window period.
- Maintain a complete audit trail linking renewal Quotes back to their source Contracts, Orders, and original Quotes.

---

## 3. Solution Overview + Data Model

**Flow:** A daily scheduled flow identifies contracts entering the 120-day window and marks them `Pending`. When a user runs the standard "Renew" action on the Contract's Managed Assets, Revenue Cloud creates a Quote with `QuoteAction` records of `Type="Renew"`. A record-triggered flow traces the asset origin chain, populates the renewal Quote with reference/billing fields, and creates an Opportunity. COLA pricing is applied via the `COLAUpliftHandler` trigger (3-tier hierarchy). On renewal-order activation, a succession flow marks the original contract `Renewed` and renewal status `Accepted`.

### 3.1 Data Model — relationship chain

Renewal Quote is linked to the source Contract through:

```
Contract → Asset → OrderItem → Order → Quote (Original) → Contract (Source)
```

Renewal Quote links back via:
- `Renewal_Contract__c` → source Contract
- `Original_Quote__c` → original Quote
- `Original_Order_Id__c` → original Order
- The `QuoteAction` record with `Type="Renew"` and `SourceAssetId` links each renewal quote line to its source Asset.

---

## 4. Component Summary

| Component | Type | Responsibility |
|---|---|---|
| `Fortra_Contract_Renewal_Window_Monitor` | Flow (Scheduled) | **Daily at 2:00 AM UTC** — queries activated contracts within 120-day window and sets `Renewal_Status__c = "Pending"` |
| `Fortra_RCA_Renewal_Enhancement` | Flow (Record-Triggered) | **After-save on Quote create** — traces asset origin, sets `Quote_Type__c = "Renewal"`, populates reference fields, copies billing/contact info, creates Opportunity |
| `Fortra_Renewal_Contract_Succession` | Flow (Record-Triggered) | **After-save on Order activation** — marks original Contract `Status = "Renewed"` and `Renewal_Status__c = "Accepted"` |
| `COLAUpliftHandler` | Apex Class | Trigger handler — applies COLA pricing on renewal QLIs using 3-tier hierarchy (Line Override > Contract Override > CMDT Lookup) |
| `COLAUpliftPrehook` | Apex Class (**global**) | Revenue Cloud pricing prehook — runs MyCAP out-year uplift enforcement for multi-year annual renewals |
| `AssetContractQueryHelper` | Apex Class | Helper — queries `AssetContractRelationship` for Contract COLA override lookup |
| `QuoteLineItemTrigger` | Apex Trigger | **Before insert/update on QuoteLineItem** — invokes `COLAUpliftHandler` |
| `COLA_Uplift_Rules__mdt` | Custom Metadata | COLA percentages by Solution Category with effective dates (**21 records**) |
| `MyCAP_Rules__mdt` | Custom Metadata | MyCAP out-year uplift threshold and default (**Global record: 3%**) |
| `COLA_Admin` | Permission Set | FLS for COLA, MyCAP, and renewal-related fields |
| `Sales_Renewal_Window_Restriction` | Validation Rule | Blocks non-Ops users from non-upsell amendments within 120-day renewal window |

---

## 5. Custom Fields

### 5.1 Contract Renewal Fields (object: Contract)

| Field API Name | Type | Description |
|---|---|---|
| `Renewal_Status__c` | **Picklist** | Lifecycle status: `Pending, In Progress, Quoted, Accepted, Declined`. Set to `Pending` by scheduled flow; `Accepted` by contract succession flow. |
| `Within_Renewal_Window__c` | **Formula (Checkbox)** | TRUE when contract is within 120 days of EndDate and EndDate is in the future. Formula (verbatim): `AND(NOT(ISBLANK(EndDate)), (EndDate-TODAY())<=120, (EndDate-TODAY())>=0)` |
| `Auto_Renew__c` | **Checkbox** | Auto-renewal eligibility. **Default: TRUE.** |

### 5.2 Quote Renewal Fields (object: Quote)

| Field API Name | Type | Populated By | Description |
|---|---|---|---|
| `Quote_Type__c` | **Picklist** | `Fortra_RCA_Renewal_Enhancement` | Set to `Renewal` when `QuoteAction.Type = "Renew"`. Values: `New, Upsell, Renewal, Amendment, Cancellation`. |
| `Renewal_Contract__c` | **Lookup (Contract)** | `Fortra_RCA_Renewal_Enhancement` | Links renewal Quote to the originating Contract being renewed. |
| `Original_Quote__c` | **Lookup (Quote)** | `Fortra_RCA_Renewal_Enhancement` | Links to the original Quote from the source Contract (audit trail). |
| `Original_Order_Id__c` | **Lookup (Order)** | `Fortra_RCA_Renewal_Enhancement` | Links to the original Order for traceability. |
| `Auto_Renewal__c` | **Checkbox** | Manual | Auto-renewal flag on the renewal Quote. |
| `Renewal_Value__c` | **Currency** | Manual/External | Total renewal value. |
| `Renewal_ARR_Credit_Amount__c` | **Currency** | Manual/External | Credit for renewal ARR adjustments. |
| `Renewal_ARR_Approval__c` | **Picklist** | Manual | Approval status for renewal ARR adjustments. |
| `Renewal_Cancellation_Approval__c` | **Picklist** | Manual | Approval status for renewal cancellations. |

> NOTE: `Auto_Renew__c` (Contract) and `Auto_Renewal__c` (Quote) are **two distinct fields** on two different objects — do not conflate.

### 5.3 QuoteLineItem COLA Fields (10 fields, applied on renewal)

| Field API Name | Type | Description |
|---|---|---|
| `COLA_Uplift_Percent__c` | **Number(5,2)** | Applied COLA percentage — users can override (Tier 1: Line Override) |
| `Default_COLA_Uplift_Percent__c` | **Number(5,2)** | Original COLA % from rules — preserved for comparison and override detection |
| `Pre_COLA_Price__c` | **Currency** | Original Asset price before COLA applied — base for **all** recalculations |
| `COLA_Solution_Category__c` | **Text** | Product Solution Category used for CMDT lookup |
| `COLA_Applied_Date__c` | **DateTime** | Timestamp when COLA was first applied |
| `COLA_Modified_By__c` | **Lookup (User)** | User who last modified the COLA percentage |
| `COLA_Modified_Date__c` | **DateTime** | Timestamp when COLA % was last modified |
| `COLA_Override_Reason__c` | **Text Area** | Business justification for line-level override |
| `Is_COLA_Overridden__c` | **Checkbox** | TRUE if COLA % differs from `Default_COLA_Uplift_Percent__c` |
| `COLA_Source__c` | **Picklist** | Tracks override tier: `CMDT Lookup, Contract Override, Line Override, MyCAP Default` |

---

## 6. Renewal Status Lifecycle (`Contract.Renewal_Status__c`)

| Status | Trigger | Description |
|---|---|---|
| **(blank)** | Initial state | Contract active but not yet within the renewal window. |
| **Pending** | Scheduled flow (daily) | Contract has entered the 120-day window. `Fortra_Contract_Renewal_Window_Monitor` sets this automatically. |
| **In Progress** | Manual | User has begun the renewal process (manually updated by sales). |
| **Quoted** | Manual/Automatic | A renewal Quote has been created and sent to the customer. |
| **Accepted** | Contract succession flow | Renewal Order activated. `Fortra_Renewal_Contract_Succession` sets this and updates Contract `Status = "Renewed"`. |
| **Declined** | Manual | Customer declined the renewal. Set by sales or Customer Operations. |

> Transitions after `Pending` are **manual** until Order activation triggers `Accepted`.

---

## 7. Process Flow: Renewal Creation

### 7.1 User Journey
1. Contracts entering the 120-day window are auto-identified by the daily scheduled flow → marked `Pending`.
2. User navigates to Contract record page, views Managed Assets.
3. User selects Asset(s) to renew.
4. User clicks the standard Revenue Cloud **"Renew"** action.
5. Revenue Cloud creates a renewal Quote with `QuoteAction` records (`Type="Renew"`, `SourceAssetId` linked to each selected Asset).
6. `Fortra_RCA_Renewal_Enhancement` fires — traces asset origin, populates all reference/billing fields.
7. COLA pricing applied to each renewal QLI via `COLAUpliftHandler` (3-tier hierarchy).
8. User reviews Quote, adjusts COLA %, sends to customer.
9. Customer accepts; Order created and activated.
10. `Fortra_Renewal_Contract_Succession` fires — original Contract marked `Renewed`.

### 7.2 Automation Execution Sequence

**Phase 1 — Revenue Cloud Platform**
- Creates a new Quote record.
- Creates `QuoteAction` records with `Type="Renew"` and `SourceAssetId` for each selected Asset.
- Creates `QuoteLineItem` records linked to the QuoteAction.

**Phase 2 — `Fortra_RCA_Renewal_Enhancement` (Record-Triggered Flow, after-save)**
Fires on Quote creation **when `Quote_Type__c IS NULL`** (platform-generated Quote needing enrichment):
- a. Queries `QuoteAction` records for this Quote where `Type IN ("Renew", "Amend", "No Change")`.
- b. If renewal detected: sets `Quote_Type__c = "Renewal"`.
- c. Traces Asset origin chain: `Asset → OrderItem (matched by Product2Id + Account) → Order → original Quote → source Contract`.
- d. Creates a new Renewal **Opportunity** with `Stage = "Pricing & Approval"` and `Deal_Origin__c` copied from the original Opportunity.
- e. Sets `OpportunityId` on the Quote.
- f. Populates reference fields: `Renewal_Contract__c`, `Original_Quote__c`, `Original_Order_Id__c`.
- g. Copies from original Quote: `BillingAddress, LegalEntityId, BillToContactId, Bill_To_Place__c, Ship_To_Place__c, Net_Terms__c, Language__c, Deal_Type__c`.

**Phase 3 — `COLAUpliftHandler` (Apex trigger, Before Insert on QuoteLineItem)**
- a. Confirms `QuoteAction.Type = "Renew"` for each QLI.
- b. Retrieves `Asset.Price` as the Pre-COLA base price.
- c. Looks up `Product2.Solution_Category__c`.
- d. Checks for Contract-level COLA override via `AssetContractRelationship` (Tier 2).
- e. Falls back to `COLA_Uplift_Rules__mdt` by Solution Category (Tier 3).
- f. Calculates: `UnitPrice = Pre_COLA_Price × (1 + COLA%/100)`.
- g. Populates all COLA audit fields.

**Phase 4 — User Configuration**
- Review/adjust COLA % per line (Tier 1: Line Override); add/remove products; send for approval.

**Phase 5 — `Fortra_Renewal_Contract_Succession` (Record-Triggered Flow)**
Fires when the renewal Order is activated:
- a. Queries related Quote via `Order.QuoteId`.
- b. Checks `Quote.Quote_Type__c = "Renewal"` **AND** `Quote.Renewal_Contract__c` is not null.
- c. Updates the original Contract: `Status = "Renewed"`, `Renewal_Status__c = "Accepted"`.

---

## 8. COLA Pricing Integration

### 8.1 Three-Tier Override Hierarchy

| Priority | Tier | Source | `COLA_Source__c` value |
|---|---|---|---|
| **1 (Highest)** | Line Override | User manually edits `COLA_Uplift_Percent__c` on the QLI | `Line Override` |
| **2** | Contract Override | `Contract.COLA_Override_Percent__c` (via `AssetContractRelationship`) with a valid persist-until date | `Contract Override` |
| **3 (Default)** | CMDT Lookup | `COLA_Uplift_Rules__mdt` matched by `Product2.Solution_Category__c` with effective-date validation | `CMDT Lookup` |

Additional `COLA_Source__c` value `MyCAP Default` is set by MyCAP enforcement (§8.3).

### 8.2 COLA Calculation (per renewal QLI)
1. Base Price = `Asset.Price` (stored as `Pre_COLA_Price__c`).
2. COLA % determined by hierarchy (stored as `COLA_Uplift_Percent__c`).
3. **`UnitPrice = Pre_COLA_Price__c × (1 + COLA_Uplift_Percent__c / 100)`** (verbatim formula).
4. `Default_COLA_Uplift_Percent__c` preserves the original % for override detection.

### 8.3 MyCAP Out-Year Uplift Enforcement
For **multi-year annually-billed** renewal deals, the MyCAP enhancement (running via `COLAUpliftPrehook` during the pricing waterfall) enforces a standard **3% COLA floor**:
- **Qualifying lines:** multi-year (`PricingTermCount > 1` with **Annual** unit) **AND** not prepaid (`PS_Service_Type != "Prepaid"`).
- **Default COLA: 3.00%** (configurable via `MyCAP_Rules__mdt.Global`).
- If any qualifying line falls below the 3% minimum threshold: `Quote.Mycap__c` is set to `true`, triggering Deal Desk approval via the existing `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered` flow.
- **Fully prepaid and single-year lines are exempt** from MyCAP enforcement.

### 8.4 Contract Override Persist Logic (`COLA_Override_Persist_Until__c`)

| `COLA_Override_Persist_Until__c` | Behavior |
|---|---|
| **NULL** | Override valid for all future renewals (no expiration). |
| **Future date (≥ today)** | Override valid; used for this renewal. |
| **Past date (< today)** | Override expired; system falls back to CMDT lookup. |

---

## 9. Renewal Window Monitoring

### 9.1 Scheduled Flow `Fortra_Contract_Renewal_Window_Monitor`
Runs **daily at 2:00 AM UTC**:
- Queries all Contracts where `Status = "Activated"` **AND** `Within_Renewal_Window__c = TRUE` **AND** `Renewal_Status__c IS NULL`.
- For each match: sets `Renewal_Status__c = "Pending"`.
- Bulk-updates all matched Contracts in a **single DML operation**.

### 9.2 Renewal Window Formula (`Within_Renewal_Window__c` on Contract)
```
AND(NOT(ISBLANK(EndDate)), (EndDate - TODAY()) <= 120, (EndDate - TODAY()) >= 0)
```
Returns TRUE when the contract is between **0 and 120 days** from its end date.

---

## 10. Validation Rules

| Rule | Object | Condition | Error Message |
|---|---|---|---|
| `Sales_Renewal_Window_Restriction` | Contract | `Within_Renewal_Window__c = TRUE` AND non-Upsell/Cross-sell amendment AND user NOT in `"Customer Ops"` or `"Operations"` role | "This contract is within 120 days of renewal. During this window, Sales users can only process Upsell or Cross-sell amendments." |

---

## 11. Page Layout (renewal Quotes use standard Quote layout)

**11.1 Renewal Information:** Quote Type (read-only, "Renewal"); Source Contract (`Renewal_Contract__c`); Original Quote (`Original_Quote__c`); Auto Renewal flag; Renewal Value.

**11.2 COLA Information:** COLA Uplift % (**editable**); Default COLA Uplift % (read-only); Pre-COLA Price (read-only); COLA Source (read-only); COLA Solution Category (read-only); COLA Applied Date / Modified By / Modified Date (read-only); Is COLA Overridden (read-only); COLA Override Reason (**editable**).

---

## 12. Technical Notes

**12.1 QuoteAction Trigger Limitation:** Salesforce Flow **cannot trigger directly on `QuoteAction` object creation**. `Fortra_RCA_Renewal_Enhancement` works around this by triggering on **Quote** creation with a **0-minute scheduled path**, allowing the `QuoteAction` records to be created by Revenue Cloud before the flow executes its logic.

**12.2 Asset Origin Tracing:** No direct Asset-to-Contract relationship exists in Revenue Cloud. The system traces back through the Order/Quote chain using **Product2Id + Account matching**. For accounts with multiple active contracts, the system selects the contract with the **latest EndDate**.

**12.3 Currency Handling:** Renewal Quote inherits its currency from the Revenue Cloud platform. `Fortra_RCA_Renewal_Enhancement` creates an Opportunity matching the Quote's currency, with a workaround for orgs where Opportunity currency defaults differ from the intended Quote currency.

---

## 13. Dependencies and Assumptions

**13.1 Dependencies**
- Revenue Cloud standard "Renew" action available on Contract Managed Assets.
- `QuoteAction` object populated with `Type = "Renew"` and `SourceAssetId` during renewal initiation.
- Assets have a complete `OrderItem → Order → Quote` chain for origin resolution.
- `COLA_Uplift_Rules__mdt` has active records for all relevant Solution Categories (**21 records**).
- User roles `"Customer Ops"` and `"Operations"` exist for validation-rule enforcement.
- `COLAUpliftPrehook` is registered in the Revenue Cloud pricing procedure for MyCAP enforcement.

**13.2 Assumptions**
- Each product has **exactly one** Solution Category assignment for COLA lookup.
- `Asset.Price` reflects the current annual subscription price used as the Pre-COLA base.
- COLA rates are maintained by administrators via Custom Metadata Type records.
- The 120-day renewal window is a **fixed business rule**; changes require formula modification.
- Contract succession (`Status = "Renewed"`) is triggered **only by Order activation**, not by Quote acceptance.
- `Renewal_Status__c` transitions after `Pending` are manual until Order activation triggers `Accepted`.

---

## 14. CODE-GOVERNING RULES (do NOT violate when refactoring)

1. **COLA formula is exactly** `UnitPrice = Pre_COLA_Price__c × (1 + COLA_Uplift_Percent__c / 100)`. The COLA % is a whole-number percent (divide by 100), NOT a fractional multiplier. `Pre_COLA_Price__c` = `Asset.Price` and is the base for ALL recalculations.
2. **Three-tier override precedence is fixed:** `Line Override (1, highest) > Contract Override (2) > CMDT Lookup (3, default)`. Line Override = user edit of `COLA_Uplift_Percent__c`; Contract Override = `Contract.COLA_Override_Percent__c` via `AssetContractRelationship`; CMDT = `COLA_Uplift_Rules__mdt` by `Product2.Solution_Category__c`. `COLA_Source__c` MUST record which tier won (`Line Override` / `Contract Override` / `CMDT Lookup` / `MyCAP Default`).
3. **Contract Override validity is date-gated by `COLA_Override_Persist_Until__c`:** NULL = valid forever; future/≥today = valid; past/<today = expired → fall back to CMDT lookup. Do not apply an expired contract override.
4. **`Default_COLA_Uplift_Percent__c` must be preserved as the original rule %** for override detection. `Is_COLA_Overridden__c` = TRUE iff `COLA_Uplift_Percent__c` differs from `Default_COLA_Uplift_Percent__c`. Do not overwrite `Default_COLA_Uplift_Percent__c` with the applied value.
5. **`Number(5,2)`** is the exact type/precision for `COLA_Uplift_Percent__c` and `Default_COLA_Uplift_Percent__c`. `Pre_COLA_Price__c` is Currency.
6. **Renewal window formula is exactly** `AND(NOT(ISBLANK(EndDate)), (EndDate - TODAY()) <= 120, (EndDate - TODAY()) >= 0)` — 0-to-120-day window (both bounds inclusive), EndDate must be non-blank and in the future/today. The 120-day value is a fixed business rule; changing it requires editing this formula.
7. **Scheduled monitor query filter is exactly** `Status = "Activated" AND Within_Renewal_Window__c = TRUE AND Renewal_Status__c IS NULL`, sets `Renewal_Status__c = "Pending"`, runs **daily at 2:00 AM UTC**, and MUST bulk-update in a **single DML** operation.
8. **`Quote_Type__c = "Renewal"` is set ONLY when a `QuoteAction.Type = "Renew"` exists.** The enrichment flow fires only when `Quote_Type__c IS NULL` (guard against re-processing). QuoteAction query matches `Type IN ("Renew", "Amend", "No Change")`.
9. **The enrichment flow MUST trigger on Quote (not QuoteAction) with a 0-minute scheduled path** — Flow cannot trigger on QuoteAction creation, and the delay ensures QuoteActions exist before logic runs. Do not "simplify" this to a direct QuoteAction trigger.
10. **Asset origin tracing uses Product2Id + Account matching** (no direct Asset→Contract FK). When multiple active contracts match, select the one with the **latest EndDate**. Chain: `Asset → OrderItem → Order → Quote → Contract`.
11. **Contract succession fires ONLY on Order activation** (Phase 5), never on Quote acceptance. Its guard is `Quote.Quote_Type__c = "Renewal"` AND `Quote.Renewal_Contract__c` is not null; then set original Contract `Status = "Renewed"` and `Renewal_Status__c = "Accepted"`.
12. **MyCAP enforcement runs in `COLAUpliftPrehook` during the pricing waterfall** (NOT in `COLAUpliftHandler`). Qualifying lines: `PricingTermCount > 1` with Annual unit AND `PS_Service_Type != "Prepaid"`. Floor = **3.00%** (from `MyCAP_Rules__mdt.Global`). Below-floor qualifying line → set `Quote.Mycap__c = true` to trigger `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered`. Fully prepaid and single-year lines are exempt.
13. **COLA is applied Before Insert on QuoteLineItem** via `QuoteLineItemTrigger` → `COLAUpliftHandler`, and each QLI is confirmed to belong to a `QuoteAction.Type = "Renew"` before COLA is applied.
14. **`COLAUpliftPrehook` must remain `global`** (Revenue Cloud pricing prehook contract) and registered in the pricing procedure.
15. **`Auto_Renew__c` (Contract, default TRUE) and `Auto_Renewal__c` (Quote) are distinct fields on distinct objects** — keep them separate.
16. **Validation `Sales_Renewal_Window_Restriction`** must permit only Upsell/Cross-sell amendments for non-`Customer Ops`/`Operations` users while `Within_Renewal_Window__c = TRUE`. Do not weaken role or amendment-type checks.
17. **Renewal Opportunity** created by enrichment uses `Stage = "Pricing & Approval"` and copies `Deal_Origin__c` from the original Opportunity; Quote's `OpportunityId` is set to it; Opportunity currency must match the Quote currency.
18. **Billing/reference copy set from original Quote is exactly:** `BillingAddress, LegalEntityId, BillToContactId, Bill_To_Place__c, Ship_To_Place__c, Net_Terms__c, Language__c, Deal_Type__c` plus reference fields `Renewal_Contract__c, Original_Quote__c, Original_Order_Id__c`.

---

## Open Issues / Notes
- No open issues enumerated in the source. Revision history has a single entry: **v1.0, April 2025, Marc DeBrey** (initial design). Document dated April 16, 2026 by Coastal Cloud.
- Source is a solution-design spec; field types/formulas above are as documented, not verified against live org metadata. Verify against `force-app`/retrieved metadata before implementation.
