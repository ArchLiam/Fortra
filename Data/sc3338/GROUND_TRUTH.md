# SC-3338 — Verified Ground Truth (2026-06-12, live FortraUAT)

Ticket: **Quote UI: indicate required fields & enforce required-data validation before Order submission**
Reporter Jomil Bell; callout from Ashley Gabbert ("even an asterisk?") + Wren (no validation stopping submission).
Assignee Liam Jeong. Sprint CRM 14. Components: SF Sales Cloud. Labels: CRM, CRM-Sales-Cloud, LOB-Salesforce-1-UAT, ui, ux.

## What the ticket asks (scope)
1. INVENTORY every field required for a valid Quote→Order across implemented metadata (VRs, required-on-layout, Flow checks, Apex/integration prereqs e.g. `Order_Submit_Validation__mdt`, submission-check flows). ~3–5 hrs metadata review.
2. Do NOT hard-require every field (regression risk across Apex/test/integration/flow).
3. Surface requirements via (a) help text on each required Quote field, and (b) a Flow (Screen) guidance modal listing all required fields, reachable from the Quote. Chosen Flow over LWC for maintainability.
4. Confirm/backfill validation that BLOCKS submission when required data missing — clear, non-restrictive messaging.
5. UX review with Wren before build. No regressions.

### Acceptance Criteria
- Documented inventory of all fields required for a valid Quote→Order, with the metadata enforcing each.
- Each required field has descriptive help text on the Quote layout.
- A Flow-based guidance modal lists all required fields and is reachable from the Quote.
- Submitting/converting a Quote with missing required data is blocked with a clear, user-friendly message (no silent/un-noticeable blockers).
- No regressions in existing Apex/test/integration/flow.

## VERIFIED facts (live UAT, 2026-06-12)

### Enforcement machinery (downstream, on the ORDER — NOT the Quote)
- **`Order_Submit_Validation__mdt`** — 48 records. Full live export: `Data/sc3338/retrieve/Order_Submit_Validation_LIVE.csv`. Each rule = {Object_API_Name__c, Field_API_Name__c, Relationship_Field_API_Name__c, Error_Message__c, Active__c, Field_Label__c, Object_Label__c, Link_Message__c}.
  - `Relationship_Field_API_Name__c` semantics: `Id` = the Order itself; `OrderId` = per-line OrderItem; else a FK ON the Order resolving a related record (`AccountId`, `BillToContactId`, `ShipToContactId`, `Bill_To_Address__c`, `Ship_To_Address__c`).
- **`OrderSubmissionValidator.cls`** (active) — bulk, constant-SOQL validator. Reads active mdt rules, returns blank-field errors with record links. Introduced SC-3366 (2026-06-08) to replace per-field `FieldPopulatedCheck`.
- **`FieldPopulatedCheck.cls`** — DEPRECATED (SC-3366), no longer called by active flow. (Memory SC-3291 "0% coverage" note is stale on this point.)
- **`Fortra_Order_Submission_Check` flow = v13 ACTIVE** (processType=Flow, screen flow, object=Order). Structure: screens [BillShipTo_Validation_Screen, Error_Screen, Status_Selection, Validation_Error_Screen]; decisions [Errors_Exist, ShipTo_BillTo_Account_Contact_Validation, Status_Route]; action calls [c:RefreshPage, c:showToast x2, OrderSubmissionValidator]. It is a screen flow run as an action on the Order to move Status→Order Complete; blocks with a Validation_Error_Screen listing blank required fields.
- This is all UAT-only per prior memory (SC-3291): the mdt/flow/validator machinery is absent from prod. CONFIRM during research. User said do NOT deploy SC-3291 artifacts to prod (2026-06-01).

### ACTIVE required-field rules (Active__c=true) — the canonical "required for Order Complete" set
- Account (via AccountId): `DB_DUNS__c`, `Name`, `Phone`, `Type`
- Contact BillTo (BillToContactId): `FirstName`, `LastName`, `Workday_MobilePhone_Device_Type__c`, `Workday_MobilePhone_Primary__c`, `Workday_MobilePhone_Usage_Type__c`
- Contact ShipTo (ShipToContactId): same five as BillTo
- Order (Id): `Bill_To_Account__c`, `EffectiveDate`, `Ship_To_Account__c`, `Status`, `Workday_Contract_ID__c`, `WorkdayReferenceID__c`
- OrderItem (OrderId): `Billing_Frequency__c`, `Id`, `LineNumber`, `TotalLineTaxAmount`, `Workday_Contract_Line_Type__c`

### INACTIVE rules (Active__c=false) — present but not enforced
- Contact: `Business_Entity_Contact_ID__c`, `MobilePhone`, `Workday_Customer_Id__c`, `Workday_MobilePhone_Country_ISO_Code__c`, `Workday_MobilePhone_International_Phone__c` (both Bill & Ship)
- Order: `Billing_Frequency__c`, `Workday_Contract_Type__c`
- OrderItem: `ProductCode`
- Places (Bill_To_Address__c / Ship_To_Address__c): `Location_Type__c`, `Primary__c`, `Public__c`, `Street_Address_Line_2__c`, `Street_Address_Line_3__c`

### Quote side (the GAP)
- **Quote schema**: only `Name` is hard-required (nillable=false, createable, not defaulted). All else nillable. (237 fields; describe at `Data/sc3338/retrieve/Quote_describe.json`.)
- **Quote-Quote Layout**: 128 layout items, only `Name` Required-on-layout.
- **Quote-Amendment Quote Layout**: 127 items, Required = `Name`, `Amendment_Reason__c`.
- **Help text**: only 36 of 237 Quote fields have inlineHelpText (Place fields, discount/amendment fields mostly). No coverage tied to the Order-submission required set.
- **Quote validation rules** (5, all conditional, none blanket-required-for-submission): Amendment_Requires_Contract, Enforce_Amendment_Sales_Restriction, Enforce_Discount_Cap, Require_Amendment_Reason, Sales_Cannot_Create_Downsell.
- **Order validation rules**: none in force-app (verify live).
- **Order-Order Layout** Required-on-layout: AccountId, EffectiveDate, ContractId, Status.

### Core gap statement
Enforcement exists but it lives on the **Order**, fired late (status→Order Complete via a screen-flow action), surfacing many fields that are auto-populated downstream (Workday_* etc.) rather than user-entered on the Quote. The **Quote** itself gives the rep no visual cue (1 required field, partial help text) and no Quote-time validation. So a rep can build a Quote with missing data and only discover it at Order submission — an "un-noticeable blocker." SC-3338 wants Quote-time visibility (help text + a Flow guidance modal) and confirmed blocking validation, WITHOUT hard-requiring everything.

## Key open questions for research
- Which of the active required fields are USER-ENTERED on the Quote vs AUTO-POPULATED by automation/integration downstream? (Drives which need Quote help text vs which are not a rep concern.)
- How does Quote→Order conversion happen (RLM placeQuote / convert action / flow)? Where exactly could a Quote-time check be inserted?
- Is the Order-submission blocker actually noticeable / does it truly block? Any path to submit without running the screen flow?
- Prod vs UAT parity of the whole machinery.
- Mapping each Order/Contact/Account required field back to its Quote-side source field (e.g. Quote Bill_To_Place__c → Order Bill_To_Account__c).
