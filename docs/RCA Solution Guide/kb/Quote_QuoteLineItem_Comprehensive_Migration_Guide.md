# Quote & QuoteLineItem Comprehensive Migration Guide

**Purpose (one line):** Field-by-field spec for migrating `Quote` and `QuoteLineItem` data into Salesforce Revenue Cloud (RLM) for Fortra, covering both **Historical** (completed/archived) and **In-Flight** (active/in-progress) migration scenarios, with a per-field Population Method telling you exactly how each field must be populated (or NOT loaded).

> Source is a **data-migration field-mapping guide**, not a pricing-algorithm design. It contains almost no formulas; its load-bearing content is (a) which fields exist, (b) how each is populated per scenario, (c) which fields must NEVER be loaded, and (d) the ordered migration procedure. Capture faithfully and do not invent field types the source does not state — where the source gives no SF type, the type is inferred and flagged `[inferred]`.

---

## Executive Summary

Migrating `Quote`/`QuoteLineItem` into Revenue Cloud must handle two scenarios with different rules:

- **Historical Migration** — Completed quotes (Won/Lost/Expired) migrated for reporting and historical reference. **Pricing recalculation is OPTIONAL**; records won't progress through workflows.
- **In-Flight Migration** — Active quotes (Draft, Pending Approval, Pending Signature, Ready for Conversion) that must continue their journey. **Must preserve workflow state; pricing recalculation is REQUIRED; user assignments are critical.**

Each field carries a **Population Method** code stating how it is populated. Tier 3 QuoteLineItem fields (Salesforce-Pricing calculated) must **NOT** be loaded — `PlaceQuote` overwrites them.

---

## Population Method Legend (verbatim codes)

| Code | Description |
|------|-------------|
| **DL** | Data Load — Bulk loaded from source system via Data Loader or API |
| **UE** | User Entry — Manually entered by user in Salesforce UI |
| **FA** | Flow Automation — Populated by Salesforce Flow |
| **PH** | Pre-Hook — Populated by Revenue Cloud Apex pricing pre-hook |
| **SP** | Salesforce Pricing — Calculated by PlaceQuote API (do NOT load) |
| **SA** | System Auto — System-generated (auto-number, CreatedDate, etc.) |
| **DR** | Derived — Calculated from other fields via formula or trigger |
| **LR** | Lookup/Reference — Selected from existing records via relationship |

Combined codes (e.g. `DL/UE`, `DL/PH`, `PH/SA`, `SP/DR`) mean the field may be populated either way depending on scenario/state.

---

## Business Requirements / Rules

1. **Two scenarios, different pricing rules.** Historical: pricing recalc optional (SP fields may stay empty). In-Flight: `PlaceQuote` recalc is REQUIRED.
2. **In-Flight must preserve workflow state** — `Status`, `Approval_Status__c`, `OwnerId`, approvers, signature status all carry over so quotes resume their journey.
3. **Revenue Cloud Transaction Management requires an `ApplicationUsageAssignment`** per Quote linking it to RLM (`ApplicationUsageType = RevenueLifecycleManagement`). Without it, the Quote is not managed by Revenue Cloud.
4. **Do NOT load Salesforce-Pricing-calculated (SP) QuoteLineItem fields** (Tier 3) — any loaded values are overwritten by `PlaceQuote`.
5. **Parent lines load before child/bundle lines.** Bundles link via `ParentQuoteLineItemId`.
6. **`Pricebook2Id` on Quote must match the Opportunity's Price Book**; `PricebookEntryId` on each line must match the Quote's Price Book.
7. **`IsPrimary__c`**: only one primary quote per Opportunity.
8. **`CurrencyIsoCode` is required in multi-currency orgs** (Fortra is multi-currency).
9. **Validation rules and triggers are disabled during load and re-enabled after** (Historical: re-enable BEFORE optional PlaceQuote; In-Flight: re-enable BEFORE the REQUIRED PlaceQuote so pre-hooks fire).
10. **COLA / Partner Pricing / Regional pricing are recomputed fresh by pre-hooks on In-Flight** (loaded historical values are for audit only). Historical loads the stored values directly (DL); In-Flight lets the pre-hook (PH) recalc.

---

## Data Model

Objects: standard **`Quote`** and **`QuoteLineItem`**, extended with Fortra custom fields (`__c`), plus the platform **`ApplicationUsageAssignment`** join object. Types below are from Salesforce standard schema where the field is standard; custom-field types are inferred from purpose and flagged `[inferred]` (source does NOT state SF data types).

### Part 1 — `Quote` object fields

#### 1.1 Tier 1: Required Quote fields

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `OpportunityId` | Lookup(Opportunity) | Lookup to parent Opportunity | DL | DL | Required for Quote creation |
| `Name` | Text (standard) | Quote name | DL | DL/UE | Can be auto-generated or user-entered |
| `Pricebook2Id` | Lookup(Pricebook2) | Price Book reference | DL | DL | **Must match Opportunity's Price Book** |
| `Status` | Picklist (standard) | Quote status | DL | DL | Set to appropriate status (Draft, Approved, etc.) |
| `CurrencyIsoCode` | Picklist (standard) | Currency code | DL | DL | **Required in multi-currency orgs** |
| `AccountId` | Lookup(Account) | Account lookup (via Opportunity) | LR | LR | **Inherited from Opportunity** |
| `ContactId` | Lookup(Contact) | Primary contact | DL | DL/UE | Optional but recommended |

#### 1.2 Tier 2: Workflow & Approval fields (CRITICAL for In-Flight)

Control approval routing and workflow progression.

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `OwnerId` | Lookup(User) | Quote owner (sales rep) | DL | DL | **Critical for workflow routing** |
| `Approval_Status__c` | Picklist `[inferred]` | Current approval status | DL | DL | **Must match `Status` for workflow** |
| `Approval_Justification__c` | Text/Long Text `[inferred]` | Justification for approvals | DL | DL/UE | **Required if pending approval** |
| `DiscountApprovalStatus__c` | Picklist `[inferred]` | Discount approval status | DL | DL | **Triggers discount approval workflow** |
| `DiscountApprover__c` | Lookup(User) `[inferred]` | Assigned discount approver | DL | DL/LR | **Must be valid user** |
| `IsPrimary__c` | Checkbox `[inferred]` | Primary quote flag | DL | DL | **Only one per Opportunity** |
| `ExpirationDate` | Date (standard) | Quote expiration date | DL | DL | **Future date for In-Flight** |
| `Signed_Quote__c` | Text/File ref `[inferred]` | Signed quote document | DL | DL/UE | Attachment reference |
| `Signed_Quote_Approval__c` | Picklist `[inferred]` | Signed quote approval status | DL | DL | For pending-signature quotes |
| `User__c` | Lookup(User) `[inferred]` | Assigned user | DL | DL/LR | Secondary owner/assignee |
| `BDR__c` | Lookup(User) `[inferred]` | BDR assignment | DL | DL/LR | For sales compensation |

#### 1.3 Tier 3: Pricing configuration fields (Quote header)

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `Header_Discount_Type__c` | Picklist `[inferred]` | Type of header discount | DL | DL/UE | **Percent or Amount** |
| `Header_Discount_Value__c` | Number/Percent `[inferred]` | Header discount value | DL | DL/UE | **Applies to all lines** |
| `Header_Distribution_Logic__c` | Picklist `[inferred]` | How discount distributes | DL | DL | **Weighted, Equal, etc.** |
| `Manual_Discount__c` | Checkbox `[inferred]` | Manual discount flag | DL | DL/UE | **Overrides calculated** |
| `Net_Terms__c` | Picklist `[inferred]` | Payment terms | DL | DL/UE | **Net 30, Net 60, etc.** |
| `Net_Terms_Approval__c` | Picklist `[inferred]` | Net terms approval status | DL | DL | **Triggers approval if non-standard** |
| `COLA__c` | Checkbox `[inferred]` | COLA adjustment flag | DL | DL/PH | **Triggers COLA pre-hook** |
| `Auto_Renewal__c` | Checkbox `[inferred]` | Auto-renewal enabled | DL | DL/UE | For subscription quotes |
| `Deal_Type__c` | Picklist `[inferred]` | Type of deal | DL | DL/UE | **New, Renewal, Upsell, etc.** |

#### 1.4 Tier 4: Revenue Cloud configuration (Quote-level)

Revenue Cloud Transaction Management requires an **Application Usage Assignment** per Quote.

| Field / Object | Type | Value | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `ApplicationUsageAssignment.QuoteId` | Lookup(Quote) | Quote record ID | DL | DL | **Links Quote to Revenue Cloud** |
| `ApplicationUsageAssignment.ApplicationUsageType` | Picklist | `RevenueLifecycleManagement` | DL | DL | **Required value (exact string)** |
| `Legal_Entity__c` (on Quote) | Picklist `[inferred]` | Fortra legal entity | DL | DL/UE | **Fortra LLC, Globalscape, etc.** |
| `Ship_To_Place_Country__c` (on Quote) | Picklist/Text `[inferred]` | Ship-to country | DL | DL/UE | **For regional pricing** |

### Part 2 — `QuoteLineItem` fields

#### 2.1 Tier 1: Required QuoteLineItem fields

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `QuoteId` | Lookup(Quote) (standard) | Parent Quote lookup | DL | DL | Required for line creation |
| `Product2Id` | Lookup(Product2) (standard) | Product reference | DL | DL | **Must exist in Product2** |
| `PricebookEntryId` | Lookup(PricebookEntry) (standard) | Price Book Entry reference | DL | DL | **Must match Quote's Price Book** |
| `Quantity` | Number (standard) | Number of units | DL | DL/UE | User may adjust for In-Flight |
| `ServiceDate` | Date (standard) | Service start date | DL | DL/UE | Future date for In-Flight |

#### 2.2 Tier 2: Pricing INPUT fields (marked "Input" in Context Definition)

These are inputs to Salesforce Pricing.

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `UnitPrice` | Currency (standard) | Price per unit | DL | DL/SP | Input or calculated by PlaceQuote |
| `ListPrice` | Currency (standard) | List price from price book | DL | DL/SP | Usually pulled from PricebookEntry |
| `StartDate` | Date (standard) | Service start date | DL | DL/UE | For subscription products |
| `EndDate` | Date (standard) | Service end date | DL | DL/UE | **Calculated or user-entered** |
| `SubscriptionTerm` | Number (standard) | Term length | DL | DL/UE | Number of periods |
| `SubscriptionTermUnit` | Picklist (standard) | Term unit | DL | DL/UE | **Month or Year** |
| `PeriodBoundary` | Picklist (standard) | Billing period boundary | DL | DL | **Start, End, or Custom** |
| `ProductSellingModel` | Picklist/Lookup (standard) | Selling model | DL | DL | **One-Time, Subscription, Usage** |
| `Discount` | Percent (standard) | Line discount percent | DL | DL/UE | User may adjust |
| `Description` | Text (standard) | Line description | DL | DL/UE | Optional text |
| `Allow_Regional_Pricing__c` | Checkbox `[inferred]` | Enable regional pricing | DL | DL/PH | **Triggers regional pre-hook** |

#### 2.3 Tier 3: Calculated by Salesforce Pricing — **DO NOT LOAD**

> **IMPORTANT (verbatim):** Do NOT populate these fields during data load. They are automatically calculated by PlaceQuote API. Any loaded values will be overwritten.

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `NetUnitPrice` | Currency (standard) | Net price per unit | SP | SP | Calculated by PlaceQuote |
| `NetTotalPrice` | Currency (standard) | Net total for line | SP | SP | Calculated by PlaceQuote |
| `TotalLineAmount` | Currency (standard) | Total line amount | SP | SP | **Before tax** |
| `ItemTotalAdjustmentAmount` | Currency (standard) | Total adjustments | SP | SP | **Sum of all adjustments** |
| `ItemTotalAdjustmentDistAmount` | Currency (standard) | Distributed adjustments | SP | SP | **Header discount portion** |
| `TotalPrice` | Currency (standard) | Total price | SP | SP | **Final calculated price** |
| `TotalTaxAmount` | Currency (standard) | Tax amount | SP | SP | If tax enabled |
| `RoundedLineAmount` | Currency (standard) | Rounded amount | SP | SP | **After rounding rules** |
| `ProformaBillingPeriodAmount` | Currency (standard) | Proforma amount | SP | SP | **Per billing period** |
| `PriceWaterFall` | Long Text/JSON (standard) | Price breakdown JSON | SP | SP | **Shows calculation steps** |
| `Subtotal` | Currency (standard) | Line subtotal | SP/DR | SP/DR | **Quantity × UnitPrice** |

#### 2.4 Tier 4: Fortra COLA fields (QuoteLineItem)

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `COLA_Uplift_Percent__c` | Percent/Number `[inferred]` | COLA percentage applied | DL | PH | **Pre-hook calculates for In-Flight** |
| `Default_COLA_Uplift_Percent__c` | Percent/Number `[inferred]` | Default COLA from Product | DL | PH | **Pulled from Product2** |
| `Pre_COLA_Price__c` | Currency `[inferred]` | Price before COLA | DL | PH | **For audit trail** |
| `COLA_Solution_Category__c` | Picklist/Text `[inferred]` | Solution category for COLA | DL | PH | **Determines COLA rate** |
| `Is_COLA_Overridden__c` | Checkbox `[inferred]` | Manual COLA override flag | DL | DL/UE | **User sets to override** |
| `COLA_Source__c` | Picklist `[inferred]` | Source of COLA rate | DL | PH | **Product, Manual, etc.** |
| `COLA_Applied_Date__c` | Date/DateTime `[inferred]` | When COLA was applied | DL | PH/SA | Timestamp |
| `COLA_Modified_By__c` | Lookup(User) `[inferred]` | Who modified COLA | DL | SA | User lookup |
| `COLA_Modified_Date__c` | DateTime `[inferred]` | When COLA modified | DL | SA | Timestamp |
| `COLA_Override_Reason__c` | Text/Long Text `[inferred]` | Reason for override | DL | DL/UE | **Required if overridden** |
| `Effective_End_Date__c` | Date `[inferred]` | End date for COLA calc | DL | DL/UE | **Used in COLA calculation** |

#### 2.5 Tier 5: Fortra Partner Pricing fields

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `Partner_Adjusted_Price__c` | Currency `[inferred]` | Price after partner discount | DL | PH | Pre-hook calculates |
| `Partner_Discount_Percent__c` | Percent `[inferred]` | Partner discount % | DL | PH | **From Partner pricing rules** |
| `Partner_Pricing_Model_Applied__c` | Picklist `[inferred]` | Which model used | DL | PH | **Tier, Volume, Special** |
| `Pre_Partner_Price__c` | Currency `[inferred]` | Price before partner adj | DL | PH | **For audit trail** |
| `Is_Partner_Price_Overridden__c` | Checkbox `[inferred]` | Manual override flag | DL | DL/UE | **User sets to override** |
| `Partner_Pricing_Source__c` | Picklist `[inferred]` | Source of partner pricing | DL | PH | **Account, Agreement, etc.** |
| `Partner_Margin_Detail__c` | Text/Long Text `[inferred]` | Margin detail text | DL | PH/DR | **Calculated margin info** |
| `Referral_Partner__c` (on **Quote** header) | Lookup(Account) `[inferred]` | Partner lookup | DL | DL/LR | **On Quote header, not line** |

#### 2.6 Tier 6: Fortra Hardware Reference fields (QuoteLineItem)

| Field API Name | Type | Purpose | Historical | In-Flight | Notes |
|---|---|---|---|---|---|
| `Hardware_Reference__c` | Lookup(Hardware__c) `[inferred]` | Hardware lookup | DL | DL/LR | **Link to `Hardware__c`** |
| `Hardware__c` | Text `[inferred]` | Hardware text reference | DL | DL/UE | **Alternative text field** |
| `Hardware_ID__c` | Text (External ID) `[inferred]` | Hardware identifier | DL | DL/UE | **External ID** |
| `IsProductOfInterest__c` | Checkbox `[inferred]` | Product of interest flag | DL | DL/FA | **Flow sets from selection** |
| `Partition__c` | Text `[inferred]` | Partition identifier | DL | DL/UE | For mainframe products |
| `Hostname__c` | Text `[inferred]` | Server hostname | DL | DL/UE | User enters |
| `Model__c` | Text/Picklist `[inferred]` | Hardware model | DL | DL/UE | Model designation |
| `System_Type__c` | Picklist `[inferred]` | System type | DL | DL/UE | Classification |
| `LPAR_Number__c` | Number/Text `[inferred]` | LPAR number | DL | DL/UE | Partition number |
| `LPAR_System_Name__c` | Text `[inferred]` | LPAR system name | DL | DL/UE | Partition name |

---

## Business Logic (formulas, derivations, ordering)

The source contains **no explicit arithmetic formulas, rounding modes, or tier-precedence tables** other than:

- **`Subtotal` = Quantity × UnitPrice** (Tier 3, method `SP/DR`).
- **`RoundedLineAmount`** = `TotalLineAmount` "After rounding rules" — rounding mode is NOT specified in this document (governed elsewhere by the pricing procedure).
- **COLA rate is determined by `COLA_Solution_Category__c`**; source of the rate recorded in `COLA_Source__c` (Product, Manual, etc.); default rate `Default_COLA_Uplift_Percent__c` is **pulled from Product2**. Pre-hook computes `COLA_Uplift_Percent__c` and stamps `Pre_COLA_Price__c` (before) for audit. Override path: `Is_COLA_Overridden__c` = true requires `COLA_Override_Reason__c`.
- **Partner pricing model** recorded in `Partner_Pricing_Model_Applied__c` (**Tier, Volume, Special**); source in `Partner_Pricing_Source__c` (**Account, Agreement, etc.**); pre-hook stamps `Partner_Adjusted_Price__c`, `Partner_Discount_Percent__c`, and `Pre_Partner_Price__c` (before) for audit. Override path: `Is_Partner_Price_Overridden__c`.
- **Header discount**: `Header_Discount_Type__c` (Percent or Amount), `Header_Discount_Value__c`, distributed per `Header_Distribution_Logic__c` (**Weighted, Equal, etc.**); the distributed portion lands in line field `ItemTotalAdjustmentDistAmount` (header discount portion). `Manual_Discount__c` overrides calculated.

**Key edge/ordering rules baked into the data:** Historical COLA/Partner/Regional fields are **loaded as-is (DL)** and NOT recalculated; In-Flight fields for the same are **recalculated fresh by pre-hooks (PH)** — so a migrated in-flight quote's stored historical COLA/partner values will be overwritten on the first `PlaceQuote`.

---

## Components (responsibilities)

The guide references these executable components (by function; concrete Apex class names are in the broader Fortra codebase, not this doc):

- **`PlaceQuote` API** (`ConnectApi.SalesTransactionProcessing.placeQuote`) — Triggers (1) Salesforce Pricing calc of all Tier-3 fields, (2) Apex pre-hooks (COLA, Partner Pricing, Regional Pricing), (3) all pricing adjustments and the price waterfall.
- **COLA pre-hook (PH)** — computes Tier-4 COLA fields on In-Flight quotes.
- **Partner Pricing pre-hook (PH)** — computes Tier-5 partner fields on In-Flight quotes.
- **Regional Pricing pre-hook (PH)** — fires when `Allow_Regional_Pricing__c` = true (uses Quote `Ship_To_Place_Country__c`).
- **Flow automation (FA)** — sets `IsProductOfInterest__c` from selection; notifies users of migrated in-flight quotes (procedure step 11); may update `Status`.
- **`ApplicationUsageAssignment`** platform object — join that places the Quote under Revenue Lifecycle Management.

### PlaceQuote API call (verbatim Apex from source)

```apex
ConnectApi.PlaceQuoteInputRepresentation input = new ConnectApi.PlaceQuoteInputRepresentation();
input.quoteId = 'YOUR_QUOTE_ID';
input.pricingPref = ConnectApi.PricingPreferenceEnum.System;
ConnectApi.PlaceQuoteOutputRepresentation output = ConnectApi.SalesTransactionProcessing.placeQuote(input);
// This triggers:
// 1. Salesforce Pricing calculation (Tier 3 fields)
// 2. Apex Pre-Hooks (COLA, Partner Pricing, Regional Pricing)
// 3. All pricing adjustments and waterfall
```

`input.pricingPref = ConnectApi.PricingPreferenceEnum.System` — pricing preference must be **System** to run full Salesforce Pricing + pre-hooks.

---

## Integration Points & Sequence

### 3.1 Historical Migration Procedure (ordered)

1. Disable validation rules and triggers temporarily — *Manual*
2. Load Quotes with `Status = 'Closed Won'` or historical status — *Data Load*
3. Create `ApplicationUsageAssignment` records — *Data Load*
4. Load QuoteLineItems (**parent lines first**) — *Data Load*
5. Load QuoteLineItems (**child/bundle lines**) — *Data Load*
6. **(Optional)** Call `PlaceQuote` API to populate calculated fields — *Salesforce Pricing*
7. Re-enable validation rules and triggers — *Manual*
8. Verify data integrity with reports — *Manual/Automation*

### 3.2 In-Flight Migration Procedure (ordered)

1. Disable validation rules and triggers temporarily — *Manual*
2. Load Quotes with `Status = 'Draft'` (**initial state**) — *Data Load*
3. Create `ApplicationUsageAssignment` records — *Data Load*
4. Load QuoteLineItems (**parent lines first**) — *Data Load*
5. Load QuoteLineItems (**child/bundle lines**) — *Data Load*
6. Re-enable validation rules and triggers — *Manual* (re-enabled BEFORE PlaceQuote so pre-hooks/VRs fire)
7. Call `PlaceQuote` API to calculate pricing (**REQUIRED**) — *Salesforce Pricing*
8. Pre-hooks execute (COLA, Partner Pricing, Regional) — *Apex Pre-Hook*
9. Update `Quote.Status` to actual status (Pending Approval, etc.) — *Data Load/Flow*
10. Verify workflow assignments (`OwnerId`, Approvers) — *Manual Verification*
11. Notify users of migrated in-flight quotes — *Flow/Email*
12. Users validate and continue quote processing — *User Entry*

> **Ordering contrast:** Historical loads in FINAL status (Closed Won) and PlaceQuote is optional/last-before-reenable. In-Flight loads in **Draft first**, re-enables VRs/triggers, runs PlaceQuote (required), then **flips Status to the true in-flight status** (step 9) — this two-step status prevents VRs/approval workflows from mis-firing during load.

### 3.3 In-Flight Status Mapping

| Source Status | Target Status | Workflow State | Next Action |
|---|---|---|---|
| Draft (being edited) | Draft | No approval pending | User continues editing |
| Submitted for Approval | Pending Approval | Approval in progress | Approver receives notification |
| Approved | Approved | Ready for customer | Generate quote document |
| Sent to Customer | Pending Signature | Awaiting signature | Customer signs |
| Signed | Accepted | Ready for conversion | Convert to Order |

### Appendix: Population Method Summary by Scenario

| Field Category | Historical | In-Flight | Notes |
|---|---|---|---|
| Tier 1: Required | Data Load | Data Load | Always required |
| Tier 2: Workflow | Data Load | Data Load + Verify | Critical for In-Flight routing |
| Tier 3: Calculated | Optional (SP) | Required (SP) | PlaceQuote API |
| Tier 4: COLA | Data Load | Pre-Hook | Pre-hook calculates fresh |
| Tier 5: Partner Pricing | Data Load | Pre-Hook | Pre-hook calculates fresh |
| Tier 6: Hardware | Data Load | Data Load + User | User may need to verify |
| Transaction Management | Data Load | Data Load | `ParentQuoteLineItemId` for bundles |

---

## Assumptions / Dependencies / Open Issues

- **Assumes** Fortra is a **multi-currency** org (`CurrencyIsoCode` required).
- **Depends on** `Product2` records existing before line load (`Product2Id`, `PricebookEntryId` must resolve); `Default_COLA_Uplift_Percent__c` and default COLA are sourced from `Product2`.
- **Depends on** valid `User` records for `OwnerId`, `DiscountApprover__c`, `User__c`, `BDR__c`, `COLA_Modified_By__c`.
- **Depends on** `Hardware__c` object existing for `Hardware_Reference__c` lookup.
- **Depends on** RLM being enabled + `ApplicationUsageAssignment` support (`ApplicationUsageType = RevenueLifecycleManagement`).
- **Open/unspecified in this doc:** exact SF field data types for all `__c` fields (inferred here); rounding mode for `RoundedLineAmount`; concrete pricing formulas/tier-precedence (owned by the pricing procedure, not this migration guide); concrete Apex pre-hook class names; how bundles resolve `ParentQuoteLineItemId` ordering beyond "parent first".
- **`Referral_Partner__c` lives on the Quote header** even though it is listed under the QuoteLineItem Tier-5 section — do not create it on QuoteLineItem.

---

## CODE-GOVERNING RULES (must NOT violate)

1. **NEVER load Tier-3 SP fields on QuoteLineItem.** Do not populate `NetUnitPrice`, `NetTotalPrice`, `TotalLineAmount`, `ItemTotalAdjustmentAmount`, `ItemTotalAdjustmentDistAmount`, `TotalPrice`, `TotalTaxAmount`, `RoundedLineAmount`, `ProformaBillingPeriodAmount`, `PriceWaterFall`, `Subtotal` during data load — `PlaceQuote` overwrites any loaded values.
2. **In-Flight migration MUST call `PlaceQuote`** (`ConnectApi.SalesTransactionProcessing.placeQuote`) after load; for Historical it is optional. Use `input.pricingPref = ConnectApi.PricingPreferenceEnum.System`.
3. **Every migrated Quote MUST have an `ApplicationUsageAssignment`** with `ApplicationUsageType = 'RevenueLifecycleManagement'` (exact string) linked via `QuoteId`, or it is not under Revenue Cloud management.
4. **Load order: parent QuoteLineItems before child/bundle QuoteLineItems.** Bundles reference `ParentQuoteLineItemId`.
5. **In-Flight load status sequence:** load Quotes as `Status = 'Draft'` first, run PlaceQuote, THEN set the real status (step 9). Do NOT load in-flight quotes directly in their true in-flight status.
6. **Disable VRs/triggers before load; re-enable before the pricing/PlaceQuote step** (Historical step 7 after optional PlaceQuote at step 6; In-Flight step 6 re-enable BEFORE required PlaceQuote at step 7) — so pre-hooks and validation execute against priced data.
7. **`Pricebook2Id` on Quote must equal the Opportunity's Price Book; `PricebookEntryId` on each line must belong to the Quote's Price Book.** Mismatches are invalid.
8. **Only one `IsPrimary__c = true` Quote per Opportunity.**
9. **`CurrencyIsoCode` is required** on Quote (multi-currency org).
10. **Do NOT overwrite Historical COLA/Partner/Regional loaded values with pre-hook logic** — Historical uses stored DL values (audit); pre-hook (PH) recompute applies to In-Flight only. Conversely, expect In-Flight pre-hooks to overwrite any loaded COLA/Partner values.
11. **`Approval_Status__c` must match `Status`** for workflow consistency; approver lookups (`DiscountApprover__c`, etc.) must reference valid Users.
12. **Regional pricing pre-hook is gated by `Allow_Regional_Pricing__c`** and uses Quote `Ship_To_Place_Country__c`; do not trigger regional adjustments when the flag is false.
13. **`COLA_Override_Reason__c` is REQUIRED when `Is_COLA_Overridden__c` = true.**
14. **`Referral_Partner__c` is a Quote-header field, not a QuoteLineItem field** — do not relocate it to the line object.
15. **Audit-trail "before" fields (`Pre_COLA_Price__c`, `Pre_Partner_Price__c`) must be preserved** as the pre-adjustment snapshot; do not repurpose them as live prices.
