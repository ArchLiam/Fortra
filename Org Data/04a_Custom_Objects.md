# Custom Objects (`__c`)

## Overview

This document covers the **39 no-namespace custom objects** (`__c`) in the Fortra Salesforce org. They cluster into a handful of business domains: **pricing & discounting** (the Revenue Cloud / RCA layer's bespoke pricing tables), **partner channel** management, **licensing & hardware** asset tracking, **Workday integration** payment/invoice records, **places/addressing**, **marketing & territory** routing, **migration tooling** (Order/Quote migration audit), and a **manual UAT test-management** suite. Many of these objects are reference/decision-table data feeding pricing prehooks and pricing procedures, so their *data* is as load-bearing as their schema. Managed-package objects (`pse__`, `c2g__`, `ffr__`, and standard objects) are out of scope.

Conventions in the tables below: **MD** = Master-Detail, **FK** = Lookup. `→Target` names the referenced object. `(formula)` marks formula fields; `(roll-up)` marks roll-up summary fields. `REQ` marks required fields. Sharing model is noted per object (`ControlledByParent` = inherits from the MD parent).

---

## Pricing & Discounting

These objects are custom inputs to the RCA pricing engine (prehooks + the `Rev_Mgmt_Default_Pricing_Procedure` and its decision tables). Their row data drives runtime pricing — treat them as configuration, not transactional data.

### `Attribute_Tier_Pricing_Storage__c` — Attribute & volume tier pricing
**Purpose:** Stores products that participate in attribute-based and volume-based (tier) discounting; read by attribute/tier pricing logic. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Product__c` | FK | →Product2 |
| `Product_Selling_Model__c` | FK | →ProductSellingModel |
| `Price_Adjustment_Schedule__c` | FK | →PriceAdjustmentSchedule |
| `Attribute_Name__c` / `Attribute_Value__c` | Text | Attribute the tier keys on |
| `Tier_Type__c` / `Tier_Value__c` | Text/Number | Tier identity |
| `Lower_Bound__c` / `Upper_Bound__c` | Number | Volume band |
| `Multiplier__c` | Number | Price factor |
| `Price_Mode__c` | Picklist | Total Price / Unit Price / Calculated |
| `Feature__c` | Picklist | Ultimate / Platinum / Self Managed / Financial / Non-Financial |
| `Effective_From__c` | Date | |

### `Regional_Pricing__c` — Regional pricing reference (full)
**Purpose:** Country/region multipliers for regional pricing. Sharing: ReadWrite.

| Field | Type | Notes |
|---|---|---|
| `Country__c` | Text | REQ |
| `Region__c` | Text | REQ |
| `Subregion__c` | Text | |
| `Services_Regional_Multiplier__c` | Number | REQ — the multiplier |
| `Adjustment_Type__c` | Text | |
| `Tier_Value__c` | Number | (formula) |

### `Regional_Pricing_Entry__c` — Regional pricing for Decision Tables
**Purpose:** Per the object description, mirrors `Services_Regional_Pricing__mdt` data but in an SObject format consumable by **Business Rules Engine Decision Tables** in the pricing procedure. (Custom metadata can't be queried by a Decision Table, hence this shadow object.) Used by the Regional Pricing decision table to apply country-specific adjustments. Sharing: ReadWrite. **Non-obvious:** keep this in sync with the `__mdt`; divergence silently mis-prices.

| Field | Type | Notes |
|---|---|---|
| `Country__c` | Text | REQ |
| `Country_Code__c` | Text | |
| `Multiplier__c` | Number | REQ |
| `Is_Active__c` | Checkbox | |
| `Start_Date__c` / `End_Date__c` | Date | Effectivity |

### `Price_Update_Log__c` — Currency price-update audit
**Purpose:** Audit log of pricebook-entry price updates driven by exchange-rate / currency-conversion processes. Captures before/after price and retry state. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Product__c` | FK | →Product2 |
| `Price_Book__c` | FK | →Pricebook2 |
| `Currency_Code__c` | Text | REQ |
| `Old_Price__c` / `New_Price__c` | Currency | New is REQ |
| `Exchange_Rate_Used__c` | Number | REQ |
| `Update_Status__c` / `Update_Type__c` | Picklist | |
| `Retry_Count__c` | Number | Retry bookkeeping |
| `Error_Message__c` | LongText | |
| `Updated_Date__c` | DateTime | REQ |

---

## Partner Channel & Partner Pricing

Partner channel routing plus partner-specific discount/margin models. The pricing models feed partner pricing prehooks (see `SubscriptionPricing74` / partner-discount logic referenced in project memory).

### `Partner_Pricing_Model__c` — Partner Guaranteed-Margin / Discount model
**Purpose:** Per-Account partner pricing config supporting **Guaranteed Margin** and **Discount** model types, with separate percentages for software / subscription / maintenance / services and originating-vs-non-originating splits. Sharing: ReadWrite. Load-bearing for partner net-price calculation.

| Field | Type | Notes / →Target |
|---|---|---|
| `Account__c` | FK | →Account (partner) — REQ |
| `Model_Type__c` | Picklist | REQ — Guaranteed Margin / Discount |
| `Is_Active__c` / `Is_Default__c` | Checkbox | |
| `Effective_Start_Date__c` / `Effective_End_Date__c` | Date | |
| `Software_Percent__c` / `Subscription_Percent__c` / `Services_Percent__c` | Percent | Originating splits |
| `New_Maintenance_Percent__c` / `Renewal_Maintenance_Percent__c` | Percent | |
| `Non_Orig_Software_Pct__c` / `Non_Orig_Subscription_Pct__c` / `Non_Orig_Services_Pct__c` / `Non_Orig_New_Maint_Pct__c` / `Non_Orig_Ren_Maint_Pct__c` | Percent | Non-originating splits |
| `Solution_Category__c` / `Solution_Group__c` / `Unit__c` | Text | |
| `Legacy_Id_c__c` | Text | Migration key (note the doubled `_c`) |

### `Partner_Discount_Matrix__c` — Partner discount lookup matrix
**Purpose:** Discount-percentage matrix keyed by brand, product type, and partner role / deal origin. Sharing: ReadWrite.

| Field | Type | Notes |
|---|---|---|
| `Matrix_Type__c` | Picklist | REQ |
| `Partner_Role_Deal_Origin__c` | Picklist | REQ |
| `Brand__c` / `Product_Type__c` | Picklist | |
| `Solution_Group__c` / `Unit__c` | Text | |
| `Discount_Percentage__c` | Percent | The discount |
| `Active__c` | Checkbox | |

### `Preferred_Partners__c` — Preferred partner per customer/opp
**Purpose:** Associates a customer account / opportunity with a preferred **partner** account. Sharing: ControlledByParent (parent = `Partner_Account__c`).

| Field | Type | Notes / →Target |
|---|---|---|
| `Partner_Account__c` | MD | →Account (partner, parent) |
| `Customer_Account__c` | FK | →Account |
| `Opportunity__c` | FK | →Opportunity |
| `Partner_Type__c` | Picklist | |

### `Opportunity_Partners__c` — Partners on an opportunity
**Purpose:** Junction of partners participating on an Opportunity, flagging billing vs selling partner. Sharing: ControlledByParent (parent = Opportunity).

| Field | Type | Notes / →Target |
|---|---|---|
| `Opportunity__c` | MD | →Opportunity (parent) |
| `Partner_Account__c` | FK | →Account |
| `Partner_Account_Name__c` | Text | (formula) |
| `Partner_Type__c` | Picklist | |
| `Billing_Partner__c` / `Selling_Partner__c` | Checkbox | Role flags |
| `Legacy_Id__c` | Text | Migration key |

### `Partner_Checklist_Item__c` — Partner onboarding checklist item
**Purpose:** Per-user partner onboarding/portal checklist items (definitions live in `Partner_Checklist_Definition__mdt`). Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `User__c` | FK | →User |
| `Checklist_Item__c` | Text | REQ |
| `Metadata_Developer_Name__c` | Text | Links to `__mdt` definition |
| `Duplicate_Identifier__c` | Text | REQ — dedupe key |
| `Completed__c` | Checkbox | |
| `Completion_Date__c` | DateTime | |
| `Sort_Order__c` | Number | |
| `URL__c` | Url | |

---

## Licensing, Hardware & Assets

Tracks customer license keys, the hardware they run on, and partition configs. Load-bearing for the License-Key generation/email pipeline.

### `License_Key__c` — Generated customer license key
**Purpose:** A license key generated for a customer's product instance, with full key-generation request/response payload, email-delivery state, and IBM-i / LPAR hardware identifiers. Sharing: ControlledByParent (parent = Account). Drives the license-key file creation and email-send flow (see `Create_License_Key_File__c`, `Send_Email__c`, `License_Key_Email_Event__e` platform event).

| Field | Type | Notes / →Target |
|---|---|---|
| `Account__c` | MD | →Account (parent) |
| `Hardware__c` | FK | →Hardware__c |
| `Contact_1__c` / `Contact_2__c` | FK | →Contact (recipients) |
| `License_Key__c` | Text | The key value |
| `License_Key_Serial_Number__c` / `License_Key_Product_Name__c` | Text | |
| `Key_Type__c` / `Email_Status__c` | Picklist | |
| `Create_License_Key_File__c` / `Send_Email__c` | Checkbox | Pipeline triggers |
| `Request_Parameters__c` / `Response_Message__c` / `Email_Error_Details__c` | Text/LongText | Integration payload/errors |
| `Last_Email_Sent_Date__c` | DateTime | |
| `Start_Date__c` / `End_Date__c` | Date | `Legacy_End_Date__c` (formula) |
| `LPAR_*` (Number/Model/Serial/System/Feature_Code), `LPAR_Number_Concatenate__c` (formula) | Text | iSeries partition identity |
| `Features__c` / `Add_Ons__c` / `Points__c` / `Instances__c` / `Number_of_Users__c` / `Number_of_Processors__c` | mixed | License entitlement detail |
| `Legacy_Id__c` | Text | Migration key |

### `License_Key_Asset__c` — License-key ↔ Asset junction
**Purpose:** Junction linking a `License_Key__c` to an `Asset`. Sharing: ControlledByParent (parent = License_Key__c).

| Field | Type | Notes / →Target |
|---|---|---|
| `License_Key__c` | MD | →License_Key__c (parent) |
| `Asset__c` | FK | →Asset — REQ |
| `Asset_Type__c` | Picklist | |

### `Hardware__c` — Customer hardware / infrastructure
**Purpose:** Large catalog/inventory object for customer hardware (servers, storage, appliances, IBM iSeries / OS2200 / MCP systems). Tracks specs, location, warranty, support, virtualization/clustering, and many platform-specific model/feature-code picklists (hundreds of values for `iSeries_Feature_Code__c`, `Mcp_System_Type__c`, etc.). Self-referencing (parent/replacement hardware). Sharing: ReadWrite. **Note:** very wide object; `Vendor_del__c` appears deprecated (mirror of `Vendor__c`).

| Field | Type | Notes / →Target |
|---|---|---|
| `Account__c` | FK | →Account — REQ |
| `Parent_Hardware__c` | FK | →Hardware__c (self) |
| `Replacement_Hardware__c` | FK | →Hardware__c (self) |
| `Product__c` | FK | →Product2 |
| `Primary_Asset__c` | FK | →Asset |
| `Primary_Contact__c` | FK | →Contact |
| `Primary_Order__c` / `Primary_Quote__c` | FK | →Order / →Quote |
| `Opportunity__c` | FK | →Opportunity |
| `Location__c` | FK | →Location |
| `Support_Contract__c` | FK | →Contract |
| `Service_Contract__c` | FK | →ServiceContract |
| `Price_Book__c` | FK | →Pricebook2 |
| `Installed_By__c` / `Last_Modified_By_User__c` / `Status_Changed_By__c` | FK | →User |
| `License_Key__c` | EncryptedText | |
| `Hardware_Category__c` / `Hardware_Platform__c` / `Server_Type__c` / `Server_Location_Type__c` | Picklist | Classification |
| `Host_Operating_System__c` / `Operating_System__c` | Picklist/Text | OS |
| `iSeries_Model__c` / `iSeries_Feature_Code__c` / `Mcp_System_Type__c` / `Os2200_System_Type__c` / `Group_Number_List__c` / `P_Group_List__c` | Picklist | Platform-specific (very large value sets) |
| specs: `CPU_Cores__c`, `GPU_Cores__c`, `Memory_GB__c`, `Storage_TB__c`, `Number_of_Processors__c`, `Power_Consumption_Watts__c`, `Rack_Units__c`, `Port_Count__c` | Number | |
| `Status__c` / `Compliance_Status__c` / `Warranty_Status__c` / `Support_Tier__c` / `Criticality__c` | Picklist | Lifecycle/compliance |
| `Is_Virtual__c` / `Is_Clustered__c` / `Is_Customer_Owned__c` / `Requires_Maintenance__c` / `Auto_Created_Group__c` | Checkbox | |
| `Serial_Number__c` / `Model_Number__c` / `Manufacturer__c` / `Vendor__c` / `Vendor_del__c` | mixed | `Vendor_del__c` deprecated |
| `Legacy_Id__c` | Text | Migration key |

### `Partition__c` — Hardware partition / LPAR
**Purpose:** Child of `Hardware__c` for managing software partitions, license keys, and activation details. Sharing: ControlledByParent (parent = Hardware__c).

| Field | Type | Notes / →Target |
|---|---|---|
| `Hardware__c` | MD | →Hardware__c (parent) |
| `Partition_Name__c` / `Partition_Number__c` / `Partition_ID__c` | Text | Identity |
| `License_Key__c` | EncryptedText | |
| `Number_of_Processors__c` | Number | |
| `Status__c` | Picklist | |
| `Activation_Date__c` / `Expiration_Date__c` | Date | |
| `Legacy_Id__c` | Text | Migration key |

---

## Workday Integration (Payments & Invoices)

Salesforce-side mirrors of Workday financial records, kept in sync via the MuleSoft/Workday integration. Both carry a standard `Workday_Sync_*` field set (status / correlation id / message / payload) — the integration-callout audit pattern seen across the org.

### `Workday_Invoice__c` — Workday invoice mirror
**Purpose:** SF representation of a Workday invoice tied to an Order; surfaces payment status and a hosted payment URL. Sharing: ControlledByParent (parent = Order). Note misspelled `Wordday_Sync_Status__c`.

| Field | Type | Notes / →Target |
|---|---|---|
| `Order__c` | MD | →Order (parent) |
| `Order_Id__c` | Text | Workday correlation |
| `OwnerId__c` | FK | →User |
| `Workday_ID__c` | Text | External id |
| `Amount_Due__c` | Currency | |
| `Exchange_Rate_To_USD__c` | Number | (formula) |
| `Invoice_Date__c` | Date | |
| `Customer_PO_Number__c` | Text | |
| `Payment_Status__c` | Text | |
| `Payment_Url__c` | Url | |
| `Workday_Invoice_URL__c` | Text | (formula) |
| `Wordday_Sync_Status__c` *(sic)*, `Workday_Sync_CorrelationId__c`, `Workday_Sync_Message__c`, `Workday_Sync_Payload__c` | Text/LongText | Integration audit |

### `WorkdayPayment__c` — Workday payment (child of invoice)
**Purpose:** Payment applied against a `Workday_Invoice__c`. Label is "Payment". Sharing: ControlledByParent (parent = Workday_Invoice__c).

| Field | Type | Notes / →Target |
|---|---|---|
| `Invoice_ID__c` | MD | →Workday_Invoice__c (parent) |
| `OwnerId__c` | FK | →User |
| `Workday_ID__c` | Text | External id |
| `Amount_Paid__c` | Number | |
| `Payment_Date__c` | Date | |
| `Payment_Status__c` | Text | |
| `Workday_Sync_Status__c` / `Workday_Sync_CorrelationId__c` / `Workday_Sync_Message__c` / `Workday_Sync_Payload__c` | Text/LongText | Integration audit |

---

## Places & Addressing

### `Places__c` — Account place / address with geocoding
**Purpose:** Account-scoped address ("Place") record carrying a structured Address, geocoding state, time zone, region, and external ids for Workday/Avalara. Central to the Quote→Order Bill/Ship carryover and tax/region derivation work (SC-3298). Sharing: ReadWrite. **Load-bearing & non-obvious:** geocoding is async (see `Geocoding_Request__e` event, `Geocoding_Status__c`, `Geocoding_Attempts__c`); `Composite_Address_Key__c` is the natural/dedupe key.

| Field | Type | Notes / →Target |
|---|---|---|
| `Account__c` | FK | →Account — REQ |
| `Place_Contact__c` | FK | →Contact |
| `Quote__c` | FK | →Quote |
| `Address__c` | Address | Compound address |
| `Street_Address_Line_2__c` / `Street_Address_Line_3__c` | Text | Extra lines |
| `Formatted_Address__c` / `Composite_Address_Key__c` | Text | Dedupe / display |
| `Location_Coordinates__c` (+`_Latitude__c`/`_Longitude__c`) | Location/Number | Geocode result |
| `Geocoding_Status__c` / `Geocoding_Error__c` / `Geocoding_Attempts__c` / `Geocoding_Timestamp__c` | mixed | Async geocode state |
| `Location_Type__c` / `Usage_Type__c` / `Fortra_Region__c` / `Time_Zone__c` / `Public__c` | Picklist | Classification |
| `Primary__c` / `Active__c` | Checkbox | |
| `Effective_Start_Date__c` / `Effective_End_Date__c` / `Current_Date__c` (formula) / `isExpired__c` (formula) | Date/Checkbox | Effectivity |
| `Avalara_ID__c` / `Workday_ID__c` / `Place_ID__c` / `Legacy_ID__c` / `Legacy_Source__c` | Text | External ids |
| `Contact_Name__c` / `Contact_Email__c` / `Contact_Phone__c` / `Place_Contact_Phone__c` | Text | (all formula, off Place_Contact) |

---

## Marketing, Products of Interest & Territory Routing

Marketing taxonomy plus the territory-based lead/opportunity routing chain: `Marketing_Product__c` → `Product_of_Interest__c` / `Product_Assignment__c` → `Sales_Territory__c`.

### `Marketing_Product__c` — Marketing product / solution taxonomy
**Purpose:** Marketing-facing product catalog node (solution category/group/vertical, unit). Anchors products-of-interest and assignments. Sharing: ReadWrite.

| Field | Type | Notes |
|---|---|---|
| `Active__c` | Checkbox | |
| `Solution_Category__c` / `Solution_Group__c` / `Vertical__c` / `Unit__c` | Picklist | Taxonomy |
| `Hierarchy_Level__c` | Text | (formula) |
| `Unique_Formula__c` | Text | (formula) dedupe key |
| `Description__c` | LongText | |
| `Product_of_Interest_Name__c` | Text | |

### `Product_of_Interest__c` — Product interest on Lead/Opportunity
**Purpose:** Captures a `Marketing_Product__c` of interest tied to a sales inquiry (Lead) or Opportunity, with territory routing for notification. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Marketing_Product__c` | FK | →Marketing_Product__c — REQ |
| `Sales_Inquiry__c` | FK | →Lead |
| `Opportunity__c` | FK | →Opportunity |
| `Sales_Territory__c` / `CAM_Territory__c` / `Notification_Territory__c` | FK | →Sales_Territory__c (routing) |
| `Notification_User__c` | FK | →User |
| `Part_of_Original_Request__c` | Checkbox | |
| `Product_Name__c` / `Product_Unit__c` / `Marketing_Product_Text__c` / `Sales_Inquiry_Name_Formula__c` | Text | (all formula) |
| `Legacy_Id__c` | Text | Migration key |

### `Product_Assignment__c` — Territory assignment (config)
**Purpose:** Maps a `Marketing_Product__c` to a `Sales_Territory__c` for territory assignment. **Per object description: "used for Territory Assignment, but no records are created"** — config-only / dormant. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Marketing_Product__c` | FK | →Marketing_Product__c |
| `Sales_Territory__c` | FK | →Sales_Territory__c |
| `Index__c` | Number | |
| `OwnerId_Text__c` | Text | |

### `Sales_Territory__c` — Sales territory definition
**Purpose:** Territory definition with the assigned sales roles (AE, BDR, ISR, CAM, Partner BDR), geographic/industry criteria, and solution scoping; self-referencing for hierarchy. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Parent_Sales_Territory__c` | FK | →Sales_Territory__c (self / hierarchy) |
| `Account_Executive__c` / `BDR__c` / `ISR__c` / `CAM__c` / `Partner_BDR__c` | FK | →User (roles) |
| `Named_Account__c` | FK | →Account |
| `Country__c` / `State__c` / `Industry__c` / `Solution_Category__c` / `Solution_Group__c` / `Unit__c` | Picklist | Match criteria |
| `Zip_Code__c` | Text | |
| `Unique_Value__c` | Text | Dedupe key |

### `Marketing_Fund_Request__c` — Partner MDF request
**Purpose:** Partner Marketing Development Fund (MDF) request: event details, funding, approval workflow, expected pipeline. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Partner_Account__c` | FK | →Account |
| `Contact__c` | FK | →Contact |
| `Opportunity__c` | FK | →Opportunity |
| `Approval_Status__c` / `Status__c` | Picklist | Approval state |
| `Funding_Amount__c` / `Total_Cost_of_Event__c` / `Other_Tech_Partners_MDF_Contribution__c` / `Estimated_Pipeline_Revenue_from_Event__c` | Currency | |
| `Activity_Start_Date__c` / `Activity_End_Date__c` | Date | |
| `Marketing_Activity_Type__c` / `Fortra_Solution_Focus__c` / `Industry_Focus__c` / `Primary_Objective_Goal_of_the_Activity__c` | Picklist | |
| `MFR_Code__c` | Text | Request code |
| `ZzMarketing_Activity_Description__c` | LongText | "Zz" prefix → likely deprecated/legacy field |

---

## Competitors

### `Competitor__c` — Competitor master
**Purpose:** Master list of competitors. Minimal — name + legacy id; referenced by `Opportunity_Competitor__c`. Sharing: ReadWrite.

| Field | Type | Notes |
|---|---|---|
| `Legacy_Id__c` | Text | Migration key (only custom field) |

### `Opportunity_Competitor__c` — Competitor on opportunity
**Purpose:** Junction linking a `Competitor__c` to an Opportunity, flagging the deal winner. Sharing: ControlledByParent. **Note:** has **two master-detail** parents (Competitor and Opportunity) — a classic SF junction object.

| Field | Type | Notes / →Target |
|---|---|---|
| `Competitor__c` | MD | →Competitor__c (parent 1) |
| `Opportunity__c` | MD | →Opportunity (parent 2) |
| `Deal_Winner__c` | Checkbox | |
| `Legacy_Id__c` | Text | Migration key |

---

## Account & Contact Relationships

### `Acct2Acct__c` — Account-to-account relationship (DUNS)
**Purpose:** Relationship between two accounts (primary/secondary) with DUNS numbers and effectivity dates — e.g. corporate hierarchy / D&B linkage. Sharing: ReadWrite. Two lookups to Account (note distinct relationship names `Acct2Acct` / `Acct2Acct1`).

| Field | Type | Notes / →Target |
|---|---|---|
| `Primary_Account__c` | FK | →Account |
| `Secondary_Account__c` | FK | →Account |
| `Primary_DUNS__c` / `Secondary_DUNS__c` | Number | D&B ids |
| `Start_Date__c` / `End_Date__c` | Date | |

### `Contact_Product_Account_Relationship__c` — Contact ↔ product ↔ account role
**Purpose:** Three-way relationship: which Contact has which role for which `Marketing_Product__c` at which Account (e.g. economic buyer / technical buyer per product). Sharing: ReadWrite. Several formula fields denormalize contact/account/product display values.

| Field | Type | Notes / →Target |
|---|---|---|
| `Contact__c` | FK | →Contact — REQ |
| `Account__c` | FK | →Account — REQ |
| `Marketing_Product__c` | FK | →Marketing_Product__c |
| `Role__c` | Picklist | Business User / Decision Maker / Economic Buyer / Technical Buyer / … |
| `Is_Active__c` | Checkbox | |
| `Relationship_Start_Date__c` / `Relationship_End_Date__c` | Date | |
| `UniqueIdentifier__c` | Text | Dedupe key |
| `Account_Text__c` / `Contact_Email__c` / `Contact_Phone__c` / `Contact_s_Primary_Account__c` / `Marketing_Product_Text__c` | Text | (all formula) |
| `Legacy_Id__c` | Text | Migration key |

### `Domain__c` — Email domain for account
**Purpose:** Email domain(s) belonging to an Account, with a portal-access approval flag. Sharing: ControlledByParent (parent = Account).

| Field | Type | Notes / →Target |
|---|---|---|
| `Account__c` | MD | →Account (parent) |
| `Domain__c` | Text | REQ — the domain |
| `Approved_for_Portal_Access__c` | Checkbox | |

### `Export_License_Document__c` — Export-control license documents
**Purpose:** Per the (long) object description: stores legally-required **Export Control Joint Unit (ECJU)** export-license documents at the account level, required before processing sales/renewals of Offensive Security and Email Security products (Secure ICAP Gateway, Secure Email Gateway, Cobalt Strike, Core Impact, Outflank). Sharing: ReadWrite. **Load-bearing compliance object** — gates order processing for affected products/countries.

| Field | Type | Notes / →Target |
|---|---|---|
| `Account__c` | FK | →Account |
| `Document_Type__c` | Picklist | REQ — EUU / EU GEA / Open or Standard Individual Export License / US Export Control License |
| `Export_Control_Category__c` | MultiselectPicklist | Secure Email Gateway / Secure ICAP Gateway / Cobalt Strike / Core Impact / Outflank |
| `Status__c` | Picklist | REQ — Requested / Active / Expired |
| `License_Number__c` | Text | |
| `Document_Link__c` | Url | Document storage link |
| `Default_Open_License__c` / `Regional_License__c` | Checkbox | |
| `Start_Date__c` / `End_Date__c` | Date | Validity |

### `Account_Temperature_History__c` — Account temperature change log
**Purpose:** Audit history of an Account's "temperature" (Red/Yellow/Green) changes, optionally scoped to a `Product_of_Interest__c`. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Account__c` | FK | →Account |
| `Product_of_Interest__c` | FK | →Product_of_Interest__c |
| `Old_Value__c` / `New_Value__c` / `Prior_Temperature__c` / `New_Temperature__c` | Picklist | Red/Yellow/Green |
| `Field_Name__c` / `Note__c` / `Reason_for_Change__c` | Text/TextArea | |
| `Legacy_Id__c` | Text | Migration key |

---

## Quote & Product Support

### `Quote_Checklist_Item__c` — Quote checklist item
**Purpose:** Per-Quote checklist items (deal-desk / review gating). Sharing: ControlledByParent (parent = Quote).

| Field | Type | Notes / →Target |
|---|---|---|
| `Quote__c` | MD | →Quote (parent) |
| `Item_Name__c` | Text | REQ |
| `Is_Checked__c` | Checkbox | |
| `Checked_By__c` | FK | →User |
| `Checked_Date__c` | DateTime | |
| `Sort_Order__c` | Number | |
| `Notes__c` | LongText | |

### `ProductDescription__c` — Localized product descriptions
**Purpose:** Localized (per-language) HTML descriptions for a Product2 — used in document/quote PDF generation. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Product__c` | FK | →Product2 |
| `Language__c` | Picklist | Locale |
| `Content__c` | Html | Description body |
| `Full_Name__c` / `Product_Number__c` | Text | |

---

## In-App Checklist Settings

### `In_App_Checklist_Settings__c` — In-app checklist hierarchy custom setting
**Purpose:** **Custom Setting** (not a standard custom object) holding attributes for the In-App (Sales Cloud) onboarding checklist. Per description: "contains all attributes used in In App Checklist". No standard sharing model (custom settings).

| Field | Type | Notes |
|---|---|---|
| `ProfileKey__c` | Text | Keyed by profile |
| `Sales_Cloud_In_App_Page__c` | Url | Target in-app page |

---

## Migration Tooling (Order / Quote Migration)

A purpose-built audit + preset suite behind the **Order Migration Tool** (the team's bespoke Quote→Order data migration utility). `Migration_Run_Log__c` (parent) → `Migration_Run_Detail__c` (per-row failures); plus two saved-preset objects.

### `Migration_Run_Log__c` — Migration batch run audit
**Purpose:** Audit trail header for a Quote/Order migration batch run: counts of quotes/QLIs/orders processed, succeeded, skipped, and PBE auto-creation. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Target_Pricebook__c` | FK | →Pricebook2 |
| `Batch_Job_Id__c` | Text | Apex batch id |
| `Status__c` | Picklist | Run state |
| `Run_Date__c` / `Start_Time__c` / `End_Time__c` | DateTime | |
| `Quotes_Processed__c` / `Quotes_Succeeded__c` / `Quotes_Skipped_No_Coverage__c` | Number | Quote tallies |
| `QLIs_Processed__c` / `QLIs_Succeeded__c` / `QLIs_Skipped__c` | Number | Line-item tallies |
| `Orders_Processed__c` / `Orders_Succeeded__c` | Number | Order tallies |
| `PST_Succeeded__c` / `PST_Failed__c` | Number | Place-Sales-Transaction tallies |
| `PBEs_Auto_Created__c` | Number | |
| `Filter_Used__c` | Text | |
| `Errors__c` | LongText | |

### `Migration_Run_Detail__c` — Per-row migration failure/skip
**Purpose:** Per-row failure/skip event for a migration run; drives the categorized report and per-category re-run buttons in the Order Migration Tool. Child of `Migration_Run_Log__c`. Sharing: ControlledByParent.

| Field | Type | Notes / →Target |
|---|---|---|
| `Run_Log__c` | MD | →Migration_Run_Log__c (parent) |
| `Quote__c` / `Quote_Line_Item__c` | FK | →Quote / →QuoteLineItem |
| `Order__c` / `Order_Item__c` | FK | →Order / →OrderItem |
| `Queued_By__c` | FK | →User |
| `Category__c` | Picklist | REQ — failure category |
| `Severity__c` | Picklist | REQ |
| `Cleanup_Required__c` / `In_Rerun_Queue__c` | Checkbox | Re-run queue flags |
| `Queued_Date__c` | DateTime | |
| `Quote_Number__c` / `Reason__c` | Text | |

### `Migration_Saved_Filter__c` — Saved migration filter preset
**Purpose:** Team-shared saved SOQL / quote-number / legacy-id filter presets for the Order Migration Tool. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Filter_Mode__c` | Picklist | REQ — SOQL / quote# / legacy-id |
| `Filter_Value__c` | LongText | The filter |
| `Description__c` | Text | |
| `Last_Used_By__c` | FK | →User |
| `Last_Used_Date__c` | DateTime | |

### `Migration_Saved_Pricebook_Preset__c` — Saved pricebook preset
**Purpose:** Team-shared saved pricebook + auto-create-PBE presets for the Order Migration Tool. Sharing: ReadWrite.

| Field | Type | Notes / →Target |
|---|---|---|
| `Pricebook__c` | FK | →Pricebook2 |
| `Auto_Create_Missing_PBEs__c` | Checkbox | |
| `Description__c` | Text | |
| `Last_Used_By__c` | FK | →User |
| `Last_Used_Date__c` | DateTime | |

### `FFX_Package_Version__c` — FF Accelerate package version
**Purpose:** Package-version metadata for **FF Accelerate (FFX)** components — tooling/version tracking, not transactional. Sharing: not set in meta (likely custom setting / minimal object). Migration-tooling-adjacent.

| Field | Type | Notes |
|---|---|---|
| `FFX_Product_Suite_Name__c` | Text | REQ |
| `FFX_Version_Name__c` | Text | REQ |
| `FFX_Version__c` | Text | REQ |

---

## UAT / Manual Test Management

A bespoke manual test-case management suite used for UAT (separate from Apex unit tests). Hierarchy: `Master_Test_Case__c` (parent template) → `Test_Cases__c` (instances) → `Test_Case_Issues__c` (defects logged against a case). Multiple record types support a "Classic" vs current UI variant.

### `Master_Test_Case__c` — Master test case template
**Purpose:** Template/grouping for a test scenario (requirement, steps, expected result), with roll-up counts of child test-case outcomes. Sharing: ReadWrite. **Record types:** `Master_Test_Case`, `Master_Test_Case_Classic`.

| Field | Type | Notes / →Target |
|---|---|---|
| `TCI_Assigned_to__c` | FK | →User |
| `MTC_Status__c` / `Environment__c` / `Session__c` / `Organization_Group__c` | Picklist | |
| `Steps_to_Test__c` / `Expected_Result__c` | Html | |
| `Requirement_ID__c` / `Requirement_Description__c` / `User_Story__c` / `Title__c` | mixed | |
| `Completion_Percentage__c` / `Remaining_Test_Cases__c` / `Status__c` | formula | Derived progress |
| `of_Passed_/Failed_/In_Progress_/Defer_/Ready_For_Retest_/Valid_Test_Cases__c` | Roll-up | Child outcome counts |
| `Sort_Order__c` | Number | |
| `TaskRay_Group_Project_Phase__c` | LongText | TaskRay PM linkage |

### `Test_Cases__c` — Individual test case
**Purpose:** Executable test-case instance with pass/fail, environment/session, production re-test tracking, and self/issue links. Child of `Master_Test_Case__c`. Sharing: ControlledByParent. **Record types:** `Master_Test_Cases`, `Test_Cases`, `Test_Cases_Classic`. Self-referencing (`Test_Cases__c`) and links to `Test_Case_Issues__c`.

| Field | Type | Notes / →Target |
|---|---|---|
| `Master_Test_Case__c` | MD | →Master_Test_Case__c (parent) |
| `Tester__c` / `Production_Tester__c` | FK | →User |
| `Test_Cases__c` | FK | →Test_Cases__c (self) |
| `Test_Case_Issues__c` | FK | →Test_Case_Issues__c |
| `Pass_Fail__c` / `Status__c` / `Production_Status__c` / `Dispositon__c` *(sic)* / `Severity__c` / `Test_Case_Type__c` | Picklist | Outcome/state |
| `Environment__c` / `Session__c` / `Organization_Group__c` | Picklist | |
| `Steps_to_Test__c` / `Expected_Result__c` / `Latest_Actual_Results__c` / `Production_Actual_Results__c` | LongText | |
| `Test_Case_Identifier__c` / `Test_Case_Number__c` / `Task_ID__c` / `Task_Group__c` | Text | |
| `Default_Resolver__c` / `Running_User_Tester__c` / `Sort_Order_Formula__c` / `Test_Case_Identifier_Formula__c` / `Test_Case_Record_ID__c` / `Test_Category_Classic__c` | formula | |
| `Feedback_Enhancement_Submitted__c` / `Production_Test__c` | Checkbox | |

### `Test_Case_Issues__c` — Defect / issue against a test case
**Purpose:** Defect logged during testing, linked to both a `Test_Cases__c` and `Master_Test_Case__c`; tracks disposition, severity, go-live-blocker status, and resolution. Sharing: ControlledByParent. **Record type:** `Test_Case_Issues_Classic`. Self-referencing for duplicates.

| Field | Type | Notes / →Target |
|---|---|---|
| `Test_Case__c` | MD | →Test_Cases__c (parent) |
| `Master_Test_Case__c` | MD | →Master_Test_Case__c (parent) |
| `Duplicate_Of__c` | FK | →Test_Case_Issues__c (self) |
| `Resolution_Assigned_To__c` | FK | →User |
| `Issue_Status__c` / `Disposition__c` / `Severity__c` / `Workstream__c` | Picklist | |
| `Go_Live_Blocker__c` / `Production_Issue__c` / `Feedback_Enhancement_Request__c` | Checkbox | |
| `Actual_Results__c` / `Expected_Result__c` / `Resolution__c` / `Notes__c` | LongText | |
| `Steps_to_Reproduce__c` | Html | |
| `Business_Area__c` / `Category__c` / `Organization__c` / `Organization_Group__c` / `Tester__c` | Text | (all formula) |
| `Subject__c` / `Test_Record_URL__c` | Text/LongText | |
| `Date_Closed__c` / `Ready_for_Test_Addressed__c` | Date | |

---

## Quick Reference: Object → Domain

| Object | Domain | Sharing | Parent (MD) |
|---|---|---|---|
| `Attribute_Tier_Pricing_Storage__c` | Pricing | ReadWrite | — |
| `Regional_Pricing__c` | Pricing | ReadWrite | — |
| `Regional_Pricing_Entry__c` | Pricing (Decision Table) | ReadWrite | — |
| `Price_Update_Log__c` | Pricing audit | ReadWrite | — |
| `Partner_Pricing_Model__c` | Partner pricing | ReadWrite | — |
| `Partner_Discount_Matrix__c` | Partner pricing | ReadWrite | — |
| `Preferred_Partners__c` | Partner channel | ControlledByParent | Account |
| `Opportunity_Partners__c` | Partner channel | ControlledByParent | Opportunity |
| `Partner_Checklist_Item__c` | Partner onboarding | ReadWrite | — |
| `License_Key__c` | Licensing | ControlledByParent | Account |
| `License_Key_Asset__c` | Licensing | ControlledByParent | License_Key__c |
| `Hardware__c` | Hardware | ReadWrite | — |
| `Partition__c` | Hardware | ControlledByParent | Hardware__c |
| `Workday_Invoice__c` | Workday | ControlledByParent | Order |
| `WorkdayPayment__c` | Workday | ControlledByParent | Workday_Invoice__c |
| `Places__c` | Places/Address | ReadWrite | — |
| `Marketing_Product__c` | Marketing | ReadWrite | — |
| `Product_of_Interest__c` | Marketing/routing | ReadWrite | — |
| `Product_Assignment__c` | Territory (dormant) | ReadWrite | — |
| `Sales_Territory__c` | Territory | ReadWrite | — |
| `Marketing_Fund_Request__c` | Marketing (MDF) | ReadWrite | — |
| `Competitor__c` | Competitors | ReadWrite | — |
| `Opportunity_Competitor__c` | Competitors | ControlledByParent | Competitor__c + Opportunity |
| `Acct2Acct__c` | Account relations | ReadWrite | — |
| `Contact_Product_Account_Relationship__c` | Contact relations | ReadWrite | — |
| `Domain__c` | Account/Domain | ControlledByParent | Account |
| `Export_License_Document__c` | Compliance | ReadWrite | — |
| `Account_Temperature_History__c` | Account history | ReadWrite | — |
| `Quote_Checklist_Item__c` | Quote support | ControlledByParent | Quote |
| `ProductDescription__c` | Product support | ReadWrite | — |
| `In_App_Checklist_Settings__c` | UI setting | (custom setting) | — |
| `Migration_Run_Log__c` | Migration tooling | ReadWrite | — |
| `Migration_Run_Detail__c` | Migration tooling | ControlledByParent | Migration_Run_Log__c |
| `Migration_Saved_Filter__c` | Migration tooling | ReadWrite | — |
| `Migration_Saved_Pricebook_Preset__c` | Migration tooling | ReadWrite | — |
| `FFX_Package_Version__c` | Tooling/versioning | (n/a) | — |
| `Master_Test_Case__c` | UAT testing | ReadWrite | — |
| `Test_Cases__c` | UAT testing | ControlledByParent | Master_Test_Case__c |
| `Test_Case_Issues__c` | UAT testing | ControlledByParent | Test_Cases__c + Master_Test_Case__c |
