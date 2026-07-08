# Fortra Quotes — Create New Quote (Solution Design)

**Source doc:** Fortra-Quotes-Create-New-Quote-Solution-Design-Doc.txt (Revised 04/09/26)
**Purpose (one line):** Guided, validated Screen-Flow experience launched from an Opportunity Quick Action that replaces the default Salesforce quote creation with a 7-check pipeline, auto address population from `Places__c`, 30+ Opportunity→Quote field mappings, and auto-navigation to the new Quote.

---

## Executive Summary

- Guided Quote creation runs inside Fortra's Salesforce **Revenue Cloud Advanced (RCA)** org via a **Screen Flow** launched from a **Quick Action** on the Opportunity record page. It replaces the default SF quote-creation mechanism with a validated, multi-step process that enforces data completeness/accuracy **before** creating the Quote.
- Supports **five Quote Types**: **New, Renewal, Amendment, Upsell, Cancellation** — each with type-specific validation.
- Performs **seven sequential validation checks** before the configuration screen: (1) PriceBook, (2) Legal Entity, (3) Bill To Place, (4) Ship To Place, (5) Partner Account, (6) Deal Origin Channel Account, (7) Renewed Contract (only for Renewal/Amendment/Upsell).
- Auto-populates Quote address fields from `Places__c`: retrieves Bill To Place and Ship To Place records after user selection and maps compound address subfields (incl. multi-line street concatenation) to Quote `BillingAddress` / `ShippingAddress`. Uses `StateCode`/`CountryCode` for **State & Country Picklist** compatibility.
- Includes a **before-save derivation flow** `Fortra_Opportunity_Derive_Deal_Origin` on Opportunity that sets `Deal_Origin__c` from `Distributor__c`, `Reseller__c`, `Referral_Partner__c` — deterministic, so no manual entry.
- Maps **over 30 fields** Opportunity→Quote: financials (Total ARR, Total Services, Displaced ARR), partners (Reseller, Distributor, Billing Partner, Referral Partner), operational (Legal Entity, Currency, Approval Status), and up to **8 Place lookups**.
- Error handling: pre-creation validation screens (step-by-step fix instructions) + post-creation DML error screen with **Retry / Return** options.

### Revision 2026-04-08 — FORTRA-QUOTE-004 (important state change)

- `Deal_Origin__c` and `Deal_Type__c` are now **hidden from ALL internal record pages** (Opportunity, Quote, Order, Contract) and classic page layouts.
- New before-save Opportunity flow **`Fortra_Opportunity_Derive_Deal_Origin`** (**API v64.0, Active**) auto-derives `Deal_Origin__c` from `Distributor__c`, `Reseller__c`, `Referral_Partner__c`.
- The prior **`Deal_Origin_Partner_Required` validation rule is REMOVED** — source was out of sync with the org; **it was never actually deployed to fortrauat**. Permanently out of scope.
- **Field-Level Security (FLS) is unchanged / preserved** so all automation continues to read AND write the field: Create New Quote flow, Renewal & Amendment flows, `OrderMigrationBatch`, and the Revenue Cloud pricing procedure.
- **Forward-only approach:** existing null `Deal_Origin__c` records remain null (pricing engine treats null implicitly as **'Fortra Originated'**). The **2,782 existing Quotes** with legacy value **'Reseller - Partner Originated'** are **left untouched**.

---

## Deal Origin Derivation Rules (`Fortra_Opportunity_Derive_Deal_Origin`)

Before-save Opportunity flow. Inspects `Distributor__c`, `Reseller__c`, `Referral_Partner__c` on **every insert** and on **update when those fields change**. Writes `Deal_Origin__c`. **First rule match wins; Distributor takes precedence over Reseller when both are populated.**

| Distributor__c | Reseller__c | Referral_Partner__c | Deal_Origin__c result |
|---|---|---|---|
| populated | — (any) | populated | **Distributor - Channel Originated** |
| populated | — (any) | null | **Distributor - Fortra Originated** |
| null | populated | populated | **Reseller - Channel Originated** |
| null | populated | null | **Reseller - Fortra Originated** |
| null | null | — (any) | **Fortra Originated** |
| populated | populated | — (any) | **Distributor wins (first rule match)** |

Rationale: derivation is deterministic and runs before save, so `Deal_Origin__c` is always consistent with partner fields → no user input needed → field hidden from UI. This replaces the removed validation-rule approach.

---

## Business Requirements

| ID | Requirement | Priority |
|---|---|---|
| BR-001 | Cannot create a Quote from an Opportunity lacking a **PriceBook** (PriceBook determines available products & pricing). | High |
| BR-002 | Cannot create a Quote from an Opportunity lacking a **Legal Entity** (determines billing company & tax jurisdiction). | High |
| BR-003 | **Bill To Place** and **Ship To Place** must be validated on the Opportunity before Quote creation (address data available for billing/shipping). | High |
| BR-004 | **Partner deals** (Reseller or Distributor populated) must have a **Partner Account** assigned before Quote creation. | High |
| BR-005 | **Renewal, Amendment, Upsell** quotes must reference the original Contract (`Renewed_Contract__c`) for pricing, terms calc, and co-termination. | High |
| BR-006 | Quote `BillingAddress` & `ShippingAddress` must auto-populate from selected Bill To / Ship To Place records (eliminate manual entry). | High |
| BR-007 | `Deal_Origin__c` derived automatically from `Distributor__c`/`Reseller__c`/`Referral_Partner__c`. When it resolves to a 'Channel Originated' value, `PartnerAccountId` must be populated consistently — invariant guaranteed by derivation; no standalone VR needed. `Deal_Origin_Partner_Required` VR removed (FORTRA-QUOTE-004). | Medium |
| BR-008 | Flow must support **8 Place lookup fields** (Bill To, Ship To, Service, Install, End User, Regulatory, Partner, Primary) mapped Opportunity→Quote. | Medium |
| BR-009 | Error screens must provide clear, actionable instructions for self-service resolution. | Medium |
| BR-010 | After successful Quote creation, user auto-navigated to new Quote record (no manual search). | Medium |

### Technical Requirements

| ID | Requirement | Priority |
|---|---|---|
| TR-001 | Screen Flow (**API v64.0**), auto-layout canvas, launched via Quick Action on Opportunity, using `recordId` input variable for Opportunity context. | High |
| TR-002 | Map **30+ fields** Opportunity→Quote in `Create_Quote_Record` element, incl. `OpportunityId`, `Pricebook2Id`, `QuoteAccountId`, `ContactId`, `Quote_Type__c`, `CurrencyIsoCode`, `LegalEntityId`, `PartnerAccountId`, `Renewal_Contract__c`, and all 8 Place lookups. | High |
| TR-003 | Retrieve `Places__c` records (`Get_Bill_To_Place_Details`, `Get_Ship_To_Place_Details`) after selection; map `Address__Street__s`, `Address__City__s`, `Address__StateCode__s`, `Address__PostalCode__s`, `Address__CountryCode__s` to Quote `BillingAddress` / `ShippingAddress` compound fields. | High |
| TR-004 | Create formula fields for multi-line street concat (`formulaBillingStreet`, `formulaShippingStreet`) using **`BR()`** for line breaks between `Street_Address_Line_2__c` and `Street_Address_Line_3__c`. | High |
| TR-005 | Use **`StateCode`/`CountryCode`** fields (NOT State/Country text fields) to support State & Country Picklist orgs and prevent **FIELD_INTEGRITY_EXCEPTION**. | High |
| TR-006 | Fault connector on `Create_Quote_Record` → `Quote_Creation_Error` screen showing `$Flow.FaultMessage`, offering **Retry** (loop back to `Configure_New_Quote`) or **Return to Opportunity**. | High |
| TR-007 | `navigateToRecordLWC` using `NavigationMixin` with `@api recordId` property, navigating via `standard__recordPage` with actionName **'view'** on `connectedCallback`. | Medium |
| TR-008 | Use `flowruntime:lookup` component instances for Bill To / Ship To Place with `fieldApiName`, `objectApiName` (**Quote**), and pre-populated `recordId` from Opportunity defaults. | Medium |

---

## Data Model (objects / fields with types)

### Opportunity (custom fields)
- **`Deal_Origin__c`** — Picklist. **Hidden from UI** (FORTRA-QUOTE-004); system-derived by before-save flow `Fortra_Opportunity_Derive_Deal_Origin`. FLS preserved. Mapped to `Quote.Deal_Type__c`.
- **`Referral_Partner__c`** — **Lookup to Account**. Referral partner tracking; copied to Quote on creation. **SetNull on delete.**
- **`Bill_To_Place__c`** — Lookup to `Places__c` (billing address source); validated required before Quote creation.
- **`Ship_To_Place__c`** — Lookup to `Places__c` (shipping address source); validated required before Quote creation.
- **`Legal_Entity__c`** — **Lookup to LegalEntity** (billing company); validated required before Quote creation.
- **`Reseller__c`**, **`Distributor__c`** — partner lookups (drive partner-deal / deal-origin logic).
- **`Renewed_Contract__c`** — lookup to original Contract; validated for Renewal/Amendment/Upsell.
- **`AWS_Marketplace_Agreement_ID__c`**, **`AWS_Marketplace__c`**, **`Displaced_ARR__c`**, **`Total_ARR__c`**, **`Total_Services__c`**, **`Approval_Status__c`**, **`Legacy_Id__c`** — mapped to Quote (see Field Mappings).
- Standard `Type` field customized via **`OpportunityType` StandardValueSet** = New, Renewal, Amendment, Upsell, Cancellation (default Quote Type source).

### Places__c (custom object)
- **`Address__c`** — compound Address field with standard subfields. Subfields referenced: `Address__Street__s` (line 1), `Address__City__s`, `Address__StateCode__s`, `Address__PostalCode__s`, `Address__CountryCode__s`.
- **`Street_Address_Line_2__c`** — custom text (2nd street line).
- **`Street_Address_Line_3__c`** — custom text (3rd street line).

### Quote (custom + standard fields)
- **`Quote_Type__c`** — Picklist: **New, Renewal, Amendment, Upsell, Cancellation** (RCA feature).
- **`Amendment_Reason__c`** — Picklist, **10 values**; populated during flow only when Quote Type = Amendment.
- **`Deal_Type__c`** — receives `Opportunity.Deal_Origin__c`. **Hidden from UI** (FORTRA-QUOTE-004); FLS preserved.
- Place lookups: **`Bill_To_Place__c`, `Ship_To_Place__c`, `Service_Place__c`, `Install_Place__c`, `End_User_Place__c`, `Regulatory_Place__c`, `Partner_Place__c`, `Primary_Place__c`** (8 total).
- **`Renewal_Contract__c`** — receives `Opportunity.Renewed_Contract__c` (NOTE the source/target name mismatch: Opportunity uses `Renewed_`, Quote uses `Renewal_`).
- **`Billing_Partner__c`**, **`Referral_Partner__c`**, **`Total_ARR__c`**, **`Total_Services__c`**, **`Displaced_ARR__c`**, **`Reseller__c`**, **`Distributor__c`**, **`Approval_Status__c`**, **`Legacy_Id__c`**, **`AWS_Marketplace_Offer_ID__c`**, **`AWS_Marketplace_Agreement_ID__c`**, **`LegalEntityId`**, **`QuoteAccountId`**, **`PartnerAccountId`**.

---

## Field Mappings (Opportunity → Quote) — exact

| Source Field | Target Field |
|---|---|
| Opportunity.Id | Quote.OpportunityId |
| Opportunity.Pricebook2Id | Quote.Pricebook2Id |
| Opportunity.AccountId | Quote.QuoteAccountId |
| Opportunity.CurrencyIsoCode | Quote.CurrencyIsoCode |
| Opportunity.Legal_Entity__c | Quote.LegalEntityId |
| Opportunity.PartnerAccountId | **Quote.PartnerAccountId / Quote.Billing_Partner__c** (mapped to both) |
| Opportunity.Renewed_Contract__c | Quote.Renewal_Contract__c |
| Opportunity.OwnerId | Quote.OwnerId |
| Opportunity.Description | Quote.Description |
| Opportunity.Displaced_ARR__c | Quote.Displaced_ARR__c |
| Opportunity.Reseller__c | Quote.Reseller__c |
| Opportunity.Distributor__c | Quote.Distributor__c |
| Opportunity.Referral_Partner__c | Quote.Referral_Partner__c |
| Opportunity.Total_ARR__c | Quote.Total_ARR__c |
| Opportunity.Total_Services__c | Quote.Total_Services__c |
| **Opportunity.Deal_Origin__c** | **Quote.Deal_Type__c** |
| Opportunity.AWS_Marketplace__c | Quote.AWS_Marketplace_Offer_ID__c |
| Opportunity.AWS_Marketplace_Agreement_ID__c | Quote.AWS_Marketplace_Agreement_ID__c |
| Opportunity.Approval_Status__c | Quote.Approval_Status__c |
| Opportunity.Legacy_Id__c | Quote.Legacy_Id__c |
| Places__c.Address__Street__s (+ Line2 + Line3) | Quote.BillingStreet (concatenated with `BR()`) |
| Places__c.Address__City__s (Bill To) | Quote.BillingCity |
| Places__c.Address__StateCode__s (Bill To) | Quote.BillingStateCode |
| Places__c.Address__PostalCode__s (Bill To) | Quote.BillingPostalCode |
| Places__c.Address__CountryCode__s (Bill To) | Quote.BillingCountryCode |
| Places__c.Address__Street__s (+ Line2 + Line3) | Quote.ShippingStreet (concatenated with `BR()`) |
| Places__c.Address__City__s (Ship To) | Quote.ShippingCity |
| Places__c.Address__StateCode__s (Ship To) | Quote.ShippingStateCode |
| Places__c.Address__PostalCode__s (Ship To) | Quote.ShippingPostalCode |
| Places__c.Address__CountryCode__s (Ship To) | Quote.ShippingCountryCode |
| User Selection (Flow Screen) | Quote.Bill_To_Place__c / Ship_To_Place__c / Service_Place__c / Install_Place__c / End_User_Place__c / Regulatory_Place__c / Partner_Place__c / Primary_Place__c |

---

## Business Logic (exact rules, formulas, order)

### Data retrieval (pre-validation)
- `Get_Opportunity_Details` — retrieves full Opportunity.
- `Get_Existing_Quotes` — queries existing Quotes on the Opportunity to determine primary-quote status.

### Validation chain (7 checks, execute in this order; each has a dedicated error screen)
1. **Check_PriceBook** — validates `Opportunity.Pricebook2Id` is **not null**. All Quote Types require a PriceBook for catalog access.
2. **Check_Legal_Entity** — validates `Opportunity.Legal_Entity__c` is **not null** (billing company & tax jurisdiction).
3. **Check_Bill_To_Place** — validates `Opportunity.Bill_To_Place__c` is **not null** (billing address population).
4. **Check_Ship_To_Place** — validates `Opportunity.Ship_To_Place__c` is **not null** (shipping address population).
5. **Check_Partner_Account** — when `Reseller__c` OR `Distributor__c` populated (`formulaIsPartnerDeal = TRUE`), validates `PartnerAccountId` is **not null**.
6. **Check_Deal_Origin_Partner** — when `Deal_Origin__c` is a **'Channel Originated'** value, validates `Opportunity.PartnerAccountId` is populated AND `Distributor__c` or `Reseller__c` set consistently. **Defensive safety net only** (FORTRA-QUOTE-004): should never fire now that the before-save derivation guarantees consistency.
7. **Check_Renewed_Contract** — when `selectedQuoteType IN (Renewal, Amendment, Upsell)` per `formulaContractRequired`, validates `Renewed_Contract__c` is **not null**.

If any validation fails → dedicated error screen (red title, explanation, numbered fix steps). Screens use **`allowFinish:true`**; user clicks Finish → Salesforce built-in behavior returns user to the launching Opportunity record.

### Configuration screens
- **`Configure_New_Quote`** screen: Quote Type dropdown (**defaults to Opportunity.Type**), Start Date, conditional **Amendment Reason** (visible only when Quote Type = Amendment), Contact lookup, Bill To Place lookup (**required**), Ship To Place lookup (**required**).
- **`Place_Selection`** screen: optional Place lookups — Service Place, Install Place, End User Place, Regulatory Place, Partner Place, Primary Place. (Two-screen wizard: Screen 1 = required Bill/Ship; Screen 2 = optional 6 places.)

### Place detail retrieval (after config, not during validation — avoids unnecessary queries)
- `Get_Bill_To_Place_Details`, `Get_Ship_To_Place_Details` — retrieve full `Places__c` records.

### Formulas / derived values (exact)
- **Quote Name Formula:** `Q-[OpportunityName]-[TODAY]`
- **Expiration Date Formula:** `TODAY() + 30` (30-day default expiration).
- **IsPrimary Logic:** if existing quotes exist on the Opportunity → new quote is **not** primary.
- **Address Concatenation:** `formulaBillingStreet` and `formulaShippingStreet` concatenate `Address__Street__s` with optional Line 2 (`Street_Address_Line_2__c`) and Line 3 (`Street_Address_Line_3__c`) using **`BR()`** line breaks, **skipping blank lines**.

### Record creation & error recovery
- `Create_Quote_Record` — single DML creating the Quote with 30+ mappings incl. address fields.
- **DML fault:** on `Create_Quote_Record` fault → `Quote_Creation_Error` screen displays **`$Flow.FaultMessage`**. User selects **Retry** (loops back to `Configure_New_Quote`) or **Return** (ends flow).
- On success → `navigateToRecordLWC` navigates user to new Quote.

---

## Components

| Component | Type | Responsibility |
|---|---|---|
| **`Fortra_Opportunity_Create_New_Quote_From_Opportunity_Flow`** | Screen Flow (**API v64.0, Active**) | Primary orchestration: 7 validations, 2 config screens, field mapping, error handling. Sequential pipeline. |
| **`Opportunity.Create_New_Quote`** | Quick Action (Flow-type) on Opportunity | Entry point; launches the Create New Quote screen flow from the Opportunity record page. |
| **`navigateToRecordLWC`** | Lightning Web Component | **Headless** LWC using `NavigationMixin`; empty template; navigates to new Quote on `connectedCallback` via `standard__recordPage` actionName `'view'`; `@api recordId`. |
| **`Opportunity_Record_Page_Two_Column`** | FlexiPage | Custom two-column Opportunity Lightning Record Page; includes Create New Quote Quick Action in page action bar / highlights panel. |
| **`Deal_Origin__c`** | Custom Field (Picklist) on Opportunity | Hidden from UI; system-derived by `Fortra_Opportunity_Derive_Deal_Origin`; FLS preserved for automation. |
| **`Referral_Partner__c`** | Custom Field (Lookup to Account) on Opportunity | Referral partner; copied to Quote; SetNull on delete. |
| **`Fortra_Opportunity_Derive_Deal_Origin`** | Before-save Opportunity Flow (**API v64.0, Active**) | Derives `Deal_Origin__c` from Distributor/Reseller/Referral Partner on insert and on change. |
| **`Deal_Origin_Partner_Required`** | Validation Rule | **REMOVED** (FORTRA-QUOTE-004). Never deployed to fortrauat. Permanently out of scope. |
| **`OpportunityType`** | StandardValueSet | Opportunity Type picklist: New, Renewal, Amendment, Upsell, Cancellation. Default Quote Type source. |
| **`Fortra_Order_Sync_Address_From_Place`** | Flow | Companion flow syncing address fields from `Places__c` to Order records (extends the Quote address-mapping pattern). |

### Architecture notes
- **Declarative-first**: Screen Flow + Quick Action + LWC. Flow is central orchestrator (retrieval, validation, interaction, creation, navigation).
- **Sequential pipeline:** Data Retrieval (Opp + existing Quotes) → Validation Chain (7 checks) → User Configuration (2 screens) → Place Detail Retrieval (2 Get Records) → Record Creation (1 DML) → Success/Error → Navigation.
- **Address mapping is two-stage:** (1) retrieve full `Places__c` after selection (not during validation); (2) formula fields concat multi-line street with `BR()`, map all components to Quote compound `BillingAddress`/`ShippingAddress` using StateCode/CountryCode.
- **Error handling separated:** pre-creation errors = terminating validation screens (`allowFinish:true`, returns to launching record); post-creation errors = DML fault connector with Retry/Return.

---

## Integration Points & Sequence

1. User clicks **'Create New Quote'** Quick Action on Opportunity → launches `Fortra_Opportunity_Create_New_Quote_From_Opportunity_Flow`.
2. Flow: `Get_Opportunity_Details` + `Get_Existing_Quotes` (primary determination).
3. 7 sequential validations (order above). Any fail → dedicated error screen → Finish → back to Opportunity.
4. `Configure_New_Quote` screen (Quote Type default = Opp Type, Start Date, conditional Amendment Reason, Contact, required Bill/Ship Place).
5. `Place_Selection` screen (6 optional places).
6. `Get_Bill_To_Place_Details` + `Get_Ship_To_Place_Details`.
7. `Create_Quote_Record` (30+ mappings + address). On fault → `Quote_Creation_Error` (Retry/Return). On success → `navigateToRecordLWC` → new Quote.
- **Downstream automation reading/writing `Deal_Origin__c` (FLS preserved):** Create New Quote flow, Renewal & Amendment flows, `OrderMigrationBatch`, Revenue Cloud pricing procedure.

---

## Assumptions

- **A-001** Opportunity has custom lookups: `Bill_To_Place__c`, `Ship_To_Place__c`, `Legal_Entity__c`, `Renewed_Contract__c`, `Reseller__c`, `Distributor__c`, `AWS_Marketplace_Agreement_ID__c`.
- **A-002** Quote has custom lookups: `Bill_To_Place__c`, `Ship_To_Place__c`, `Service_Place__c`, `Install_Place__c`, `End_User_Place__c`, `Regulatory_Place__c`, `Partner_Place__c`, `Primary_Place__c`, `Renewal_Contract__c`, `Billing_Partner__c`, `Referral_Partner__c`.
- **A-003** `Places__c` has compound `Address__c` (standard subfields) + custom `Street_Address_Line_2__c`, `Street_Address_Line_3__c` text fields.
- **A-004** State & Country Picklists enabled → must use `StateCode`/`CountryCode` (not text).
- **A-005** `Opportunity.Type` customized via `OpportunityType` SVS: New, Renewal, Amendment, Upsell, Cancellation.
- **A-006** Multi-currency enabled; `CurrencyIsoCode` inherited Opportunity→Quote.
- **A-007** Quick Action deployed to Opportunity Lightning Record Page action bar.
- **A-008** Revenue Cloud Advanced enabled; supports `Quote_Type__c` and related RCA quote features.

## Dependencies

### Internal (all **Deployed**)
- **D-001** `Quote_Type__c` picklist on Quote (values match Opp Type: New/Renewal/Amendment/Upsell/Cancellation).
- **D-002** `Places__c` object with Address compound field + `Street_Address_Line_2__c` + `Street_Address_Line_3__c`.
- **D-003** Opportunity custom fields: `Bill_To_Place__c`, `Ship_To_Place__c`, `Legal_Entity__c`, `Renewed_Contract__c`, `Reseller__c`, `Distributor__c`, `AWS_Marketplace_Agreement_ID__c`, `Deal_Origin__c`, `Referral_Partner__c`.
- **D-004** Quote custom fields: `Bill_To_Place__c`, `Ship_To_Place__c`, `Service_Place__c`, `Install_Place__c`, `End_User_Place__c`, `Regulatory_Place__c`, `Partner_Place__c`, `Primary_Place__c`, `Renewal_Contract__c`, `Billing_Partner__c`, `Referral_Partner__c`, `Total_ARR__c`, `Total_Services__c`.
- **D-005** Amendment Quote fields (`Amendment_Reason__c`, etc.) for Amendment support.
- **D-006** `Opportunity_Record_Page_Two_Column` includes the `Create_New_Quote` Quick Action in highlights panel.

### External
- **E-001** Salesforce Revenue Cloud Advanced platform (Quote object + RCA fields) — owner: Salesforce Platform Team.
- **E-002** State & Country Picklists enabled — owner: Salesforce Admin.
- **E-003** LWC runtime supports `NavigationMixin` for `navigateToRecordLWC` — owner: Salesforce Platform.

## Open Issues / Notes
- **Legacy data left untouched:** 2,782 existing Quotes with `Deal_Origin__c = 'Reseller - Partner Originated'` are NOT migrated. Null records stay null (pricing engine treats null as 'Fortra Originated' implicitly). Forward-only.
- **Check_Deal_Origin_Partner is dead-code-by-design** under normal operation (defensive only) — retained but should never fire post-derivation.
- **Name mismatch:** Opportunity `Renewed_Contract__c` → Quote `Renewal_Contract__c` (intentional per mappings; do not "fix" to match).

---

## CODE-GOVERNING RULES (must NOT violate when refactoring)

1. **Screen Flow API version = 64.0** for `Fortra_Opportunity_Create_New_Quote_From_Opportunity_Flow` (doc §TR-001 states v64.0; §2.2 component table states 64.0 active). Keep flow **Active**. Before-save flow `Fortra_Opportunity_Derive_Deal_Origin` is **API v64.0, Active**.
2. **Seven validations must run in this exact order BEFORE the config screen:** (1) Check_PriceBook → (2) Check_Legal_Entity → (3) Check_Bill_To_Place → (4) Check_Ship_To_Place → (5) Check_Partner_Account → (6) Check_Deal_Origin_Partner → (7) Check_Renewed_Contract.
3. **Validation predicates (exact):**
   - Check_PriceBook: `Opportunity.Pricebook2Id != null`.
   - Check_Legal_Entity: `Opportunity.Legal_Entity__c != null`.
   - Check_Bill_To_Place: `Opportunity.Bill_To_Place__c != null`.
   - Check_Ship_To_Place: `Opportunity.Ship_To_Place__c != null`.
   - Check_Partner_Account: IF `Reseller__c` OR `Distributor__c` populated (`formulaIsPartnerDeal = TRUE`) THEN `PartnerAccountId != null`.
   - Check_Deal_Origin_Partner: IF `Deal_Origin__c` is 'Channel Originated' THEN `PartnerAccountId` populated AND (`Distributor__c` or `Reseller__c` set). Retain as defensive net; do not delete.
   - Check_Renewed_Contract: IF `selectedQuoteType IN (Renewal, Amendment, Upsell)` (`formulaContractRequired`) THEN `Renewed_Contract__c != null`.
4. **Deal Origin derivation is authoritative and first-match, Distributor-wins-over-Reseller.** Exact outputs: Distributor+Referral→`Distributor - Channel Originated`; Distributor+noReferral→`Distributor - Fortra Originated`; Reseller+Referral→`Reseller - Channel Originated`; Reseller+noReferral→`Reseller - Fortra Originated`; neither→`Fortra Originated`. Runs on insert AND on change of `Distributor__c`/`Reseller__c`/`Referral_Partner__c`. Must remain **before-save**.
5. **Do NOT re-introduce the `Deal_Origin_Partner_Required` validation rule** — it was removed (FORTRA-QUOTE-004) and never deployed to fortrauat. Permanently out of scope.
6. **`Deal_Origin__c` and `Deal_Type__c` stay hidden from ALL record pages** (Opportunity, Quote, Order, Contract) and classic layouts, but **FLS MUST remain enabled** so automation can read AND write them (Create New Quote flow, Renewal/Amendment flows, `OrderMigrationBatch`, Revenue Cloud pricing procedure). Do not remove FLS to "clean up" the hidden fields.
7. **Forward-only data policy:** never mass-update the 2,782 legacy `'Reseller - Partner Originated'` Quotes; never backfill null `Deal_Origin__c` (null == implicit 'Fortra Originated' to the pricing engine).
8. **Address mapping MUST use `StateCode`/`CountryCode`** (never State/Country text) to avoid **FIELD_INTEGRITY_EXCEPTION** in State & Country Picklist orgs.
9. **Street concatenation uses `BR()` line breaks** across `Address__Street__s` + `Street_Address_Line_2__c` + `Street_Address_Line_3__c`, **skipping blank lines** (`formulaBillingStreet`, `formulaShippingStreet`).
10. **Places retrieval is deferred:** query full `Places__c` records (`Get_Bill_To_Place_Details`, `Get_Ship_To_Place_Details`) only AFTER user selection, NOT during validation (avoid unnecessary SOQL).
11. **Exact field-mapping fidelity** (do not "correct" apparent mismatches): `Opportunity.Deal_Origin__c → Quote.Deal_Type__c`; `Opportunity.Renewed_Contract__c → Quote.Renewal_Contract__c`; `Opportunity.PartnerAccountId → BOTH Quote.PartnerAccountId AND Quote.Billing_Partner__c`; `Opportunity.AWS_Marketplace__c → Quote.AWS_Marketplace_Offer_ID__c`; `Opportunity.AccountId → Quote.QuoteAccountId`; `Opportunity.Legal_Entity__c → Quote.LegalEntityId`.
12. **Quote Name formula = `Q-[OpportunityName]-[TODAY]`**; **Expiration Date = `TODAY() + 30`** (30-day). Do not change these defaults.
13. **IsPrimary rule:** new quote is primary ONLY if no existing Quotes on the Opportunity.
14. **`Amendment_Reason__c` (10 picklist values) is shown/populated ONLY when Quote Type = Amendment.**
15. **DML fault handling required:** `Create_Quote_Record` must have a fault connector to `Quote_Creation_Error` displaying `$Flow.FaultMessage`, offering **Retry** (loop to `Configure_New_Quote`) and **Return to Opportunity**.
16. **Pre-creation validation screens use `allowFinish:true`** and rely on Salesforce built-in return-to-launching-record behavior (single exit path back to the Opportunity).
17. **`navigateToRecordLWC` is headless** (empty template): navigate on `connectedCallback` via `NavigationMixin` → `standard__recordPage`, actionName **`'view'`**, using `@api recordId`. Do not add rendered UI.
18. **8 Place lookups** (Bill To, Ship To, Service, Install, End User, Regulatory, Partner, Primary) must all be mapped Opportunity→Quote; Bill To & Ship To are **required** on the config screen, the other 6 optional on `Place_Selection`.
19. **Bill/Ship lookup screen components** use `flowruntime:lookup` with `objectApiName = Quote`, correct `fieldApiName`, and pre-populated `recordId` from Opportunity defaults.
20. **Quote Type default = `Opportunity.Type`**, sourced from the `OpportunityType` StandardValueSet (New, Renewal, Amendment, Upsell, Cancellation).
21. **Companion pattern:** `Fortra_Order_Sync_Address_From_Place` mirrors this address-from-`Places__c` mapping onto Order; keep the two consistent when changing address-concat logic.
