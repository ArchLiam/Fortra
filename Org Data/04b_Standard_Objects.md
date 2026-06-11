# 04b — Customized Standard / RCA Objects

## Overview

This document covers the **heavily-customized Salesforce standard objects** that form the spine of
Fortra's Revenue Cloud (RCA) implementation. They model the **Quote → Order → Asset → Contract**
lifecycle for a software company that sells perpetual licenses, subscriptions/SaaS, annual maintenance,
hardware appliances, and professional services — through both **direct** and **partner/distributor/reseller**
channels, in **multiple currencies and regions**.

Because the team has been repeatedly burned by hidden customization, the focus here is **what the custom
fields are *for*** and **which ones drive logic**. Recurring cross-object themes you will see everywhere:

- **Pricing & COLA** — RCA pricing procedures (`Rev_Mgmt_Default_Pricing_Procedure`), prehooks, and the COLA
  (Cost-Of-Living-Adjustment) renewal uplift engine write to these fields. `Source_List_Price__c` is the
  load-bearing list-price carrier.
- **Partner / channel** — distributor, reseller, referral partner, partner pricing models and overrides.
- **Workday integration** — outbound sync to Workday Financials via MuleSoft (`*_Sync_Status__c`,
  `Workday_Contract_Line_Type__c`, payload/correlation fields).
- **Legacy migration** — `Legacy_Id__c` / `Legacy_*__c` external keys from the prior system; `GearsetExternalId__c`
  / `ExternalId__c` natural keys used by Gearset data deploys.
- **Billing & dates** — billing frequency, schedule From/To dates, effective/term dates.
- **Regional pricing** — country-multiplier list-price adjustments (Italy etc.).
- **Hardware** — appliance attributes (serial, LPAR, model, hostname, processors) for IBM-i / Power systems.

> **Managed-package fields** (`pse__`, `c2g__`, `ffr__`, `fferpcore__`, `salesintelio__`, `LID__`, etc.)
> are **out of scope** and excluded from the counts below — those belong to PSA/FinancialForce/SalesIntel
> and are not Fortra-custom.

**No-namespace custom-field counts** (the subject of this doc):

| Object | Custom fields | Object | Custom fields |
|---|---|---|---|
| Account | 241* | Order | 124 |
| Opportunity | 165 | QuoteLineItem | 109 |
| Contact | 156* | OrderItem | 97 |
| Quote | 136 | Product2 | 60 |
| Contract | 27 | Asset | 10 |
| PricebookEntry | 4 | ProductSellingModel | 4 |
| QuoteLineGroup | 3 | ContractLineItem | 3 |
| Pricebook2 | 2 | AssetAction | 2 |
| QuoteAction | 0 | ProductSellingModelOption | 0 |
| Entitlement | 0 | OrderAction | 0 |

\* Account/Contact counts include a large block of managed-package finance/PSA fields that are excluded from
the thematic discussion below; the **no-namespace Fortra-owned** subset is far smaller (~70 for Account,
~35 for Contact).

---

## Transaction line: Quote → Order → Asset

### Quote (136 custom fields)

**Role:** The configure-price-quote header. Origin of the whole flow — a Quote is priced by the RLM pricing
procedure, approved, then converted to an Order. Drives **deal type, COLA renewal, discount approvals,
multi-currency, and partner pricing**.

`Quote_Type__c` picklist (**logic driver**): `New | Upsell | Renewal | Amendment | Cancellation | Net-New`.
This is the master switch that branches pricing/renewal/amendment behavior across the whole pipeline
(carried forward to Order as `Quote_Type__c` + `QuoteTypeText__c`).

| Theme | Key fields | Notes |
|---|---|---|
| **COLA / renewal** | `COLA__c`, `Renewal_Contract__c`, `Renewal_Value__c`, `Total_Renewal__c`, `Within_Renewal_Window__c`, `Days_Until_Renewal__c`, `Auto_Renewal__c`, `Original_Contract_ARR__c`, `Credit_Renewal_ARR__c`, `Discount_Renewal_ARR__c`, `LegacyRenewalQuote__c` | SC-3350 territory. COLA uplift is computed per-line (see QLI) and rolled here. `Force_New_Contract__c` controls contract creation on convert. |
| **ARR / revenue rollups** | `ALE__c` (formula = Subtotal), `Annual_Revenue_Base__c`, `Annualized_License_Equivalent_Base__c`, `Total_ARR__c`, `Total_Quote_Line_ARR__c`, `Quote_NARR__c`, `Annual_Contract_Value_ACV__c`, `Total_Contract_Value_TCV__c`, `Net_Contract_Change__c` | **Fragile:** conditional category aggregates leave stale values on empty groups (SC-3345). Note the typo twins `Annuial_Revenue_Base__c` / `Annual_Revenue_Base_old__c`. |
| **Discount / approvals** | `Header_Discount_Type__c`, `Header_Discount_Value__c`, `Header_Distribution_Logic/Type__c`, `Header_Remainder_Amount__c`, `Manual_Discount__c`, `Max_Discount_on_QLIs__c`, `*_Max_Discount__c` (Maintenance/Perpetual/Service/Subscription), `DiscountApprovalStatus__c`, `DiscountApprover__c`, plus many `*_Approval__c` (Renewal ARR, Displaced ARR, MYCAP, Legal Support, Net Terms, Signed/Unsigned Quote, Services, Channel/MSP, Perpetual/Subscription pricing) | Large approval-routing surface; `Approval_Status__c` / `Approval_Justification__c` are the headers. |
| **Partner / channel** | `Distributor__c`, `Reseller__c`, `Referral_Partner__c`, `Billing_Partner__c`, `Partner_Contact__c`, `Partner_Pricing_Model__c`, `Partner_Pricing_Model_Source__c`, `Channel_MSP_Pricing_Discount_Approval__c` | Partner pricing model drives per-line partner discount (see QLI). |
| **Places / addresses** | `Bill_To_Place__c`, `Ship_To_Place__c`, `End_User_Place__c`, `Install_Place__c`, `Service_Place__c`, `Partner_Place__c`, `Regulatory_Place__c`, `Primary_Place__c` | Place lookups (RCA Sales-Transaction model) carried to Order. SC-3298 address mapping. |
| **Pricing totals / category** | `Total_Software__c`, `Total_Subscription__c`, `Total_Services__c`, `TotalDiscount__c`, `Total_Discount_Amount__c`, `Hardware__c`, `GSW__c` | Category subtotals feeding totals rollups. |
| **Amendment** | `Amendment_Reason__c`, `Amendment_Effective_Date__c`, `Amendment_Request_Date__c`, `Amendment_ARR_Impact__c`, `Mark...` | Mid-term contract change path. |
| **Multi-currency** | `Exchange_Rate_To_USD__c`, `Corporate_Currency_Amount__c`, `Original_Opportunity_Currency__c` | |
| **Export / compliance** | `Export_Compliance_Status__c`, `Export_License_Required__c`, `Export_Review_Required__c`, `Disable_Export_Control__c`, `Contains_Offensive_Security__c`, `Compliance_Notes__c` | OffSec/regulatory gating. |
| **AWS Marketplace** | `AWS_Marketplace_Agreement_ID__c`, `AWS_Marketplace_Offer_ID__c` | Marketplace co-sell. |
| **Document / display** | `Show_Hide_Discounts/Free_Products/Product_Number/Signature_Block__c`, `Signed_Quote__c`, `Editable_T_C__c`, `Terms_and_Conditions__c`, `Language__c` | Feed the DocGen Quote PDF pipeline. |
| **Convert / lineage** | `Create_Order_from_Quote__c`, `Original_Order_Id__c`, `Original_Quote__c`, `Migration_Contract_Id__c` | |
| **Legacy / misc** | `Legacy_Id__c`, `Record_Type__c` (text, not RT), `Test_Field__c` | `Test_Field__c` looks like dev cruft. |

**Record types:** none defined as metadata RTs. Type behavior is driven by the **`Quote_Type__c` picklist**,
not RecordType (there is a text `Record_Type__c` field — a legacy artifact).

### QuoteLineItem (109 custom fields)

**Role:** The priced line. This is where the **COLA, hardware, regional, partner, and attribute-based
pricing engines actually write**. Highly logic-heavy — most RCA prehooks read/write QLI fields.

| Theme | Key fields | Notes |
|---|---|---|
| **COLA pricing (SC-3350)** | `COLAUpliftPercent__c`, `COLA_Uplift_Percent__c`, `COLA_Outyear_Uplift_Percent__c`, `Default_COLA_Uplift_Percent__c`, `COLACalculatedPrice__c`, `Final_Year_COLA_Calculated_Price__c`, `Pre_COLA_Price__c`, `Is_COLA_Overridden__c`, `COLA_Override_Reason__c`, `COLA_Source__c`, `COLA_Solution_Category__c`, `COLA_Applied_Date__c`, `COLA_Modified_By/Date__c`, `COLA_Uplift2__c` | The COLA renewal uplift surface. Override + source/audit trail. **Load-bearing & fragile** (active rework, peer review w/ Nir). |
| **Core pricing** | `Source_List_Price__c`, `Base_Price__c`, `Price_Mode__c`, `Discount_Value__c`, `Discount_Reason__c`, `ALE__c`, `ALE_Base__c`, `Quote_Line_ARR__c`, `QLI_NARR__c`, `QLI_NARR_Calculated__c` | `Source_List_Price__c` is **the** list-price carrier the pricing procedure depends on (its in-place edit caused the contextDefinitionName gack). |
| **Partner pricing (SC-3359)** | `Partner_Adjusted_Price__c`, `Partner_Discount_Percent__c`, `Partner_Pricing_Model_Applied__c`, `Partner_Pricing_Source__c`, `Partner_Margin_Detail__c`, `Partner_Pricing_Warning__c`, `Is_Partner_Price_Overridden__c`, `Pre_Partner_Price__c`, `Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c` | Partner net-price applied by `SubscriptionPricing74` (currently broken for One-Time/Perpetual). |
| **Hardware** | `Hardware__c`, `Hardware_ID__c`, `Hardware_Type__c`, `Hardware_Reference__c`, `Hardware_Notes__c`, `HardwareCalculatedPrice_c__c`, `Hardware_Price_Multiplier__c`, `Hardware_Pricing_Applied__c`, `Hardware_Pricing_Source/Detail__c`, `Hardware_Attributes_Synced__c`, `Pre_Hardware_Price__c`, `Requires_New_Hardware__c`, `Serial_Number__c`, `Model__c`, `Hostname__c`, `LPAR_Number__c`, `LPAR_System_Name__c`, `Partition_Reference__c`, `System_Type__c` (+`_Applied/_Source`) | IBM-i / Power appliance pricing & attributes. |
| **Regional pricing** | `Allow_Regional_Pricing__c`, `Regional_NetUnit_Price__c`, `PrehookRSNetUnitPrice__c`, `RegionalPricingExplainerItem__c` | `RegionalServicesPricingPrehook` writes the country-multiplier list price (NET stays catalog — structural `TotalLineAmount≠NetTotalPrice`). |
| **Attribute-based pricing** | `Has_Attribute_Adjustment__c`, `AttributeMultiplierPct__c`, `Multiplier__c` / `Multiplier2__c`, `Attribute_Price_Mode__c`, `Attribute_Picklist_Value__c`, `Users_Per_Partition__c` (+`_Applied/_Source`/`_del`), `pGroup__c` (+`_Applied/_Source`/`_del`), `Instances__c` | Pricing-group + per-attribute multipliers (e.g., AA SKU adjustments — SC-3360). `_del` fields are deprecated dupes. |
| **Product classification** | `Fortra_Product_Type__c` (picklist below), `Product_Type__c`, `License_Type__c`, `Product_Code__c`, `Product_Name__c`, `CustomProductName__c`, `Legacy_Product_Name/Number__c`, `Unique_Product_Identifier__c` | `Fortra_Product_Type__c`: `Software, Perpetual, New Maintenance, Renewal Maintenance, Subscription, SaaS Subscription, Services, Professional Service, Renewal Services` — drives line-type & Workday mapping. |
| **Dates / term** | `Effective_End_Date__c`, `Year_After_StartDate__c`, `Two_Years_After_Start_Date__c` | Used for COLA out-year pricing windows. |
| **Displaced/cross-sell** | `Displaced_ARR__c`, `Displaced_ARR_Base/Input__c`, `Replaced_Asset__c`, `Swap__c` | Renewal displacement of prior ARR. |
| **Export / GSA / misc** | `Export_Control_Category/Document__c`, `Export_Documentation_Required__c`, `GSA__c`, `Services_Hourly_Rate__c`, `Postpaid_Service__c`, `Currency__c`, `Exchange_Rate_To_USD__c`, `Clone_Parent_LineItemId__c`, `c_CreatedfromEstimate__c` | |

**Record types:** none. Behavior keys off `Fortra_Product_Type__c`.

### QuoteLineGroup (3) & QuoteAction (0)

| Object | Custom fields | Role |
|---|---|---|
| **QuoteLineGroup** | `Hardware__c`, `Hardware_Group_Type__c`, `Hardware_Notes__c` | Line grouping; only hardware-grouping fields added. |
| **QuoteAction** | none | Standard RCA action object, no customization. |

### Order (124 custom fields)

**Role:** The committed transaction created from a Quote. Primary **integration boundary to Workday**
(and legacy/HubSpot/PO sync). Where activation, reprice, and order-completion automations fire.

| Theme | Key fields | Notes |
|---|---|---|
| **Workday sync** | `Workday_ID__c`, `WorkdayReferenceID__c`, `Workday_Contract_ID__c`, `Workday_Contract_Type__c`, `Workday_Overall_Status__c`, `Workday_Sync_Status/Message/Payload/Correlation_Id__c`, `Payment_Term_Workday_Reference_ID__c` | **Load-bearing integration.** Payload field is a *log* — Mule reads live data on re-submit. Re-send via `Order_Completed_WD__e` platform event. |
| **Other sync channels** | `HS_Sync_*` / `Hubspot_Overall_Status__c` (HubSpot), `Legacy_Sync_*` / `Legacy_Overall_Status__c`, `PO_Sync_*` / `PO_URL__c`, `gsOrderID__c`, `gsShipDate__c`, `Order_Integration_Error_Messages__c`, `Order_and_Related_Field_Status__c` | Parallel `*_Sync_Status/Message/Payload/Correlation_Id__c` quartet pattern repeated per channel. |
| **Renewal / type** | `IsRenewal__c`, `Quote_Type__c` (+`QuoteTypeText__c`), `Renewal_Maintenance_Quote__c`, `Cross_Sale_Type__c`, `Deal_Type__c`, `Deal_Origin__c`, `MSYears__c`, `SingleYearMS__c` | Mirrors Quote_Type picklist. |
| **Pricing / totals** | `ALE__c`, `Order_NARR__c`, `Order_NARR_Calculated__c`, `Total_List_Price__c`, `Total_Software/Subscription/Services__c`, `Total_Discount_Amount__c`, `Order_Displaced_ARR__c`, `Legacy_Discount__c`, `Skip_Price_Calculation__c`, `Currency_Locked__c` | `Skip_Price_Calculation__c` gates reprice; relevant to the convert-to-order activation race (SC-3308). |
| **Billing** | `Billing_Frequency__c`, `Billing_Day_of_Month__c`, `Auto_Invoice_Date__c` (via line dates), `Net_Terms__c`/`Net_Terms_Approval__c`, `Disable_Tax__c`, `DoNotInvoicePS__c`, `Payment_Portal__c`, `VAT_Number__c` | |
| **Partner / channel** | `Partner_Account__c`, `DistributorReseller__c`, `Reseller_Partner__c`, `Reseller_PO__c`, `Referral_Partner__c`, `Purchasing_Agent_Account/Contact__c`, `IsDR__c` (deal reg) | |
| **Places / addresses** | `Bill_To_Place__c`, `Ship_To_Place__c`, `Bill_To_Account__c`, `Ship_To_Account__c`, `Bill_To_Address__c`, `Ship_To_Address__c`, `Account_Billing_Account__c` (-ish), `POC_Invoice_Contact_On_Billing_Account__c` | `Bill_To_Account__c` carryover (Quote→Order) is wrong for ~36% partner-billing cases (memo). |
| **People / roles** | `Sales_Rep__c`, `RSM__c` (+`RSM_2..5__c`), `Account_Specialist__c`, `Renewals_Specialist__c`, `Customer_Success_Manager__c`, `Solutions_Engineer__c`, `Enterprise_Representative__c`, `Cross_Sale_User__c`, `HARP_Contact__c`, `License_Key_Contact__c` (+`Secondary_`), `Invoice_Contact__c` (+`_2`) | |
| **Lineage** | `Source_Quote_Id__c`, `Source_Order_Id__c`, `Source_Opportunity_Id__c`, `Source_Campaign__c`, `Source_Quote_Currency__c`, `OrderOne__c`, `Is_Reversed__c` | |
| **Fulfillment** | `Date_Fulfilled__c`, `Requested_Delivery_Date__c`, `Line_Items_Complete__c`, `IsNotificationSent__c`, `Contract_Start_Date__c`, `Maintenance_Date__c`, `Commission_Date__c`, `Clawback_Repaid_Date__c` | |
| **Revenue category counts** | `New_Licenses__c`, `New_Maintenance__c`, `New_Pro_Services__c`, `New_SaaSEftCloud__c` | |
| **Export / AWS / misc** | `Disable_Export_Control__c`, `AWS_Marketplace_*`, `Share_With_AWS__c`, `MyCap__c`, `GSW__c`, `Legacy_Id__c` | |

**Record types:** none. Type via `Quote_Type__c`.

### OrderItem (97 custom fields)

**Role:** The order line — the **per-line Workday contract-line mapping** lives here, plus the post-convert
copies of QLI pricing/hardware fields and the order-line splitting (LIC vs MAINT, quantity splits).

| Theme | Key fields | Notes |
|---|---|---|
| **Workday line mapping** | `Workday_Contract_Line_Type__c` (`USAGE BASED | PREPAID | FIXED AMOUNT BILLING ONLY | FIXED AMOUNT`), `Workday_Revenue_Category__c`, `Workday_Contract_Line_Reference_ID__c`, `Workday_Sync_Status/Message/Payload/Correlation_Id__c` | **Load-bearing & fragile.** `Workday_Contract_Line_Type__c` is stamped by `Fortra_OrderItem_Set_Workday_Contract_Line_Type` (V8 correct; V9/V10 caused SC-3347/SC-3368/SC-3210 Workday failures). |
| **Line splitting** | `Is_Split_Line__c`, `Original_Order_Item__c`, `Is_Term__c`, `DoNotExpand__c`, `Sequence_Number__c`, `Version_Number__c`, `Prior_Group_Number__c` | `Original_Order_Item__c` is the subsplit-detection FK — **also set on pure quantity splits** (the SC-3210 mis-stamp trap). |
| **Pricing** | `Source_List_Price__c`, `Base_Price__c`, `Price_Mode__c`, `Price_Overriden__c`, `Override_Discount_Amount/Percentage__c`, `Manual_Discount__c`, `NetTotalPrice_Calculated__c`, `Order_Line_ARR__c`, `Order_Line_NARR_Calculated__c`, `Displaced_ARR__c`, `Order_Is_Price_Locked__c`, `Skip_Price_Calculation__c` | |
| **COLA / regional / attribute** | `COLA_Uplift_Percent__c`, `COLACalculatedPrice__c`, `AllowRegionalPricing__c`, `RegionalNetUnitPrice__c`, `Attribute_Multiplier_Pct__c`, `Attribute_Price_Mode__c`, `Has_Attribute_Adjustment__c`, `Uplift_Percent__c` | Copied/recomputed from QLI. |
| **Billing & dates** | `Billing_Frequency__c`, `Billing_Schedule_From_Date__c`, `Billing_Schedule_To_Date__c`, `Start/End_Date_Calculated__c`, `Year_After_StartDate__c`, `Two_Years_After_Start_Date__c`, `Requested_Delivery_Date__c`, `Freight_Terms__c` | From/To date derivation = `Fortra_OrderItem_Set_Dates` v4 (SC-3297). |
| **Revenue allocation (MEA)** | `LIC_Fair_Value_Amount__c`, `MAINT_Fair_Value_Amount__c`, `Multiple_Element_Rev_Alloc_Value__c`, `Royalty_Amount__c`, `Tax_Code__c` | Multiple-element revenue arrangement (SC-3134/Workday). |
| **Hardware** | `Hardware__c`, `Hardware_ID__c`, `Model__c`, `Serial_Number__c`, `Hostname__c`, `LPAR_Number/System_Name__c`, `Number_of_Processors__c`, `System_Type__c`, `Partition__c`/`Partition_Record__c`, `Units__c`, `Feature_Code__c` (+`Prior_*`) | Plus `Prior_*` snapshot fields for amendment diffs. |
| **Asset / fulfillment** | `Asset__c`, `Entitlement__c`, `Quantity_Shipped__c`, `Quantity_Back_Ordered__c`, `Product_Sale_Type__c`, `Fortra_Product_Type__c`, `Product_type__c` | `Asset__c` links the line to the Asset it creates/amends. |
| **Partner / discount** | `Partner_Discount_Type__c`, `Prior_Partner_Discount__c`, `RSM_Discount_Percent__c`, `Server_Type_Discount_Percent__c`, `Maintenance_Discount_Percent__c`, `MSP_End_User__c`, `Quote_Line_Discount_Reason__c` | |
| **Legacy / GS** | `Legacy_Id__c`, `Legacy_Source__c`, `LegacyQuoteLineDiscount__c`, `Migration_Change__c`, `gsOrderID__c`, `gsOrderDetailID__c` | |

**Record types:** none.

### Asset (10) & AssetAction (2)

**Role:** The post-sale entitlement record. An Order line creates/amends an Asset (`OrderItem.Asset__c`),
which then becomes the basis for **renewal** (the COLA renewal engine reprices off Assets — `Asset.PricingSource`).

| Object | Fields | Notes |
|---|---|---|
| **Asset** | `ARR__c`, `Allow_Regional_Pricing__c`, `Extended__c`, `Extension_Date__c`, `Hardware__c`, `Product_Release_Code__c`, `Product_Version__c`, `Type_of_Processor__c`, `iASP_name__c`, `Legacy_Id__c` | Hardware version/processor attributes + ARR for renewal valuation. SC-3350 renewal universe ≈ 43 assets. |
| **AssetAction** | `Order_Line_ARR__c`, `Legacy_Id__c` | Tracks ARR change per asset action. |

**Record types:** none.

---

## Catalog & pricing objects

### Product2 (60 custom fields)

**Role:** The product catalog entry. Classifies products (software/perpetual/subscription/service/hardware),
controls **pricing eligibility** (regional, attribute), and carries **Workday/finance mapping** + legacy keys.

| Theme | Key fields | Notes |
|---|---|---|
| **Classification** | `Fortra_Product_Type__c`, `ProductType__c`, `Product_Selling_Model_Type__c`, `License_Type__c`, `Final_SKU_Name_License_Type__c`, `Solution__c`, `Solution_Category__c`, `Solution_Group__c`, `Practice__c` | |
| **Pricing flags** | `Allow_Regional_Pricing__c`, `Has_Attribute_Pricing__c`, `Is_Recurring_Service__c`, `Is_Subsplit_Product__c`, `Power_Split_Type__c` | `Is_Subsplit_Product__c` / `Power_Split_Type__c` drive LIC/MAINT order-line splitting. |
| **Hardware** | `Hardware_ID__c`, `CPW_Max/Min__c`, `Processor_Min__c`, `Excluded_Feature_Codes__c`, `Required_Feature_Codes__c` | CPW = IBM Power capacity ratings. |
| **Workday / finance** | `Workday_Sales_Item_ID__c`, `Finance_Business_Unit__c`, `Rev_Category__c`/`Rev_Category_Name__c`, `Rev_Schedule__c`, `Revenue_Recognition_Schedule_Template__c`, `Revenue_Treatment__c` | (Plus `c2g__`/`fferpcore__` finance fields — out of scope.) |
| **Catalog naming** | `Custom_Product_Name__c`, `Product_Descriptions__c`, `Primary_Catalog_Name__c`, `Primary/Parent_Category_Name__c`, `Product_Lifecycle_Stage__c`, `Unit__c` | |
| **Migration / keys** | `Legacy_Id__c` (`Legacy_ProductId__c`), `Legacy_Brand_Name__c`, `Legacy_Product_Number__c`, `External_ID__c`, `ExternalId__c`, `GearsetExternalId__c` | **Gearset natural keys** — used to avoid Id-match FK stripping on data deploys. |

**Record types:** `Technical_Product` (1 RT).

### Pricebook2 (2), PricebookEntry (4)

| Object | Fields | Notes |
|---|---|---|
| **Pricebook2** | `ExternalId__c`, `GearsetExternalId__c` | Migration natural keys only. |
| **PricebookEntry** | `ExternalId__c`, `GearsetExternalId__c`, `Last_Auto_Update__c`, `Lock_Price__c` | `Lock_Price__c` prevents auto-repricing of the PBE; `Last_Auto_Update__c` audit. (Derived-pricing PBE config is a separate hot spot — SC-3372.) |

### ProductSellingModel (4), ProductSellingModelOption (0)

| Object | Fields | Notes |
|---|---|---|
| **ProductSellingModel** | `Code__c`, `External_ID__c`, `ExternalId__c`, `GearsetExternalId__c` | Selling-model code + migration keys. RCA term/subscription model. |
| **ProductSellingModelOption** | none | **No custom fields** but operationally fragile: cannot be deleted while an active PBE references the (Product, SellingModel) pair (PSMO↔PBE interlock). |

---

## Contract & service objects

### Contract (27 custom fields)

**Role:** The renewal anchor. Holds contract-level ARR, renewal window/status, COLA override, and
amendment metadata. The COLA renewal engine and amendment flow read these.

| Theme | Key fields | Notes |
|---|---|---|
| **COLA override** | `COLA_Override_Percent__c`, `COLA_Override_Persist_Until__c` | Contract-level COLA override (vs per-line on QLI). |
| **Renewal** | `Auto_Renew__c`, `Renewal_Status__c`, `Renewal_Type__c`, `Within_Renewal_Window__c`, `Days_Until_Expiry__c`, `Expiring_InMonth__c`, `Expected_Ren_Amount__c`, `Co_Term_Overridden__c`, `Original_Contract__c`, `Parent_Contract_End_Date__c` | |
| **ARR / value** | `Contract_ARR__c`, `Single_Year_MSAmount_Rollup__c`, `Credit_Amount__c`, `Early_Termination_Fee__c` | |
| **Amendment** | `Amendment_Count__c`, `Amendment_Reason__c`, `Amendment_ARR_Impact__c` | |
| **Cancellation** | `Cancellation_Date__c`, `Cancellation_Reason__c` | |
| **Other** | `Deal_Type__c`, `Legal_Entity__c`, `Partner__c`, `Solution_Group__c`, `Migration_Created__c`, `Legacy_Id__c` | |

**Record types:** `ContractLifecycleManagement` (1 RT).

### ContractLineItem (3), Entitlement (0)

| Object | Fields | Notes |
|---|---|---|
| **ContractLineItem** | `Asset__c`, `Hardware_Id__c`, `Serial_Number__c` | Links contract line to asset/hardware. |
| **Entitlement** | none | Standard, no Fortra customization. |

---

## Account & Contact (CRM master data)

### Account (~70 Fortra-custom of 241 total)

**Role:** Customer / partner master. Drives **partner classification, channel, customer status, and
finance/billing defaults**. (The bulk of the 241 fields are managed-package finance/PSA fields — excluded.)

| Theme | Key Fortra fields | Notes |
|---|---|---|
| **Partner / channel** | `Partner__c`, `is_Enrolled_Partner__c`, `Direct_or_Indirect_Partner__c`, `Partner_Tier__c`, `Partner_Business_Model__c`, `Partner_Program_Contract_*__c` (ARR/CO Rev/Start/End/Renewal dates), `Enrolled_Partner_Program_Name__c`, `Strategic_Partner__c`, `Channel_Territory__c`, `Primary_Channel_Account_Manager__c`, `Primary_Partner_Marketer__c`, `Partnership_Unit__c` | |
| **Customer status** | `Account_Customer_Status__c`, `Customer_SF_Status__c`, `Account_Partner_Status__c`, `Customer__c`, `Customer_Since__c`, `Customer_Group__c`, `Lifecycle_Stage__c`, `Account_Temperature__c`, `Total_Current_ARR__c`, `Account_ARR_At_Risk__c`/`Account_ARR_Risk__c` | |
| **Solution interest** | `Defensive_Security__c`, `Offensive_Security__c`, `Managed_File_Transfer__c`, `RPA_Plus__c`, `Power__c` | Product-line flags. |
| **Finance / billing** | `Default_Legal_Entity__c`, `Net_Terms__c`, `PO_Required__c`, `Customer_Credit_Hold__c`, `Hold_Invoices__c`, `Hold_Collection_Letters__c`, `VAT_Number__c`, `Invoice_Delivery_Default__c`, `Dunning_Delivery_Type__c`, `Statement_Delivery_Type__c` | |
| **Integration / sync** | `Workday_ID__c`, `Workday_Customer_Id__c`, `Workday_Sync_*`, `HS_Sync_*`, `Legacy_Sync_*`, `GS_CustomerID__c`, `AWS_Customer_Id__c`, `AWS_Marketplace_Seller_Id__c`, `Fortra_IDP_ID__c`, `External_ID__c`, `Legacy_Id__c`, `Account_ID_18__c` | Same per-channel sync quartet pattern. |
| **D&B enrichment** | `DB_*__c` (~30 fields: DUNS, revenue, employees, family tree, etc.) | Dun & Bradstreet firmographic enrichment. |
| **Automation** | `Disable_Automation__c`, `Processing_Status__c`, `Account_Team_Processing_Status__c` | `Disable_Automation__c` is a circuit-breaker. |

**Record types:** none defined in source.

### Contact (~35 Fortra-custom of 156 total)

**Role:** Person master. Mostly **integration sync + billing contact** customization; the remainder are
`pse__` PSA resource fields (out of scope).

| Theme | Key Fortra fields | Notes |
|---|---|---|
| **Workday integration** | `Workday_ID__c`, `Workday_Contact_Id__c`, `Workday_Sync_*`, `Workday_Phone_*__c` / `Workday_MobilePhone_*__c` (country ISO, device type, usage, primary/public flags) | Detailed phone metadata required by Workday. |
| **Other sync** | `HS_Sync_*`, `Hubspot_Contact_Id__c`, `Legacy_Sync_*`, `Legacy_Id__c`, `Business_Entity_Contact_ID__c`, `Contact_ID_18__c`, `Unified_Individual_Id__c` | |
| **Billing role** | `Default_Bill_To_Contact__c`, `Primary_Bill_To_Contact__c` | |
| **Status / prefs** | `Status_Code__c` / `Status_Code_Name__c`, `Preferred_Language__c`, `Time_Zone__c`, `GDPR_Contact_via_Email/Phone__c`, `Fortra_Academy_Access__c`, `Disable_Automation__c`, `Duplicate_Record__c` | |

**Record types:** `CRM_Contact`, `PSA_Resource` (2 RTs — separates CRM contacts from PSA delivery resources).

---

## Opportunity (165 custom fields)

**Role:** Pre-quote sales pipeline. Heavy on **deal registration (partner), forecasting, MEDDPICC-style
qualification, AWS co-sell, and trial/POC tracking**. Feeds Quote (`Quote_Count__c`, places, partner refs).

| Theme | Key fields | Notes |
|---|---|---|
| **Deal registration (partner)** | `Deal_Registration_ID__c`, `Deal_Registration_Date_Approved__c`, `Deal_Registration_Expiration_Date__c`, `Number_of_Deal_Registration_Extensions__c`, `Deal_Registration_Notes/Submitter__c`, `Partner_Deal_Status__c`, `Partner_Portal_Deal_Registration__c`, `User_Registered_Deal__c`, `Existing_Customer_of_Partner__c`, `Bypass_Partner_Validation__c`, `No_Territory_Found__c` | Large partner-deal-reg surface. |
| **Partner / channel** | `Distributor__c`/`Distributor_Text__c`, `Reseller__c`/`Reseller_Text__c`, `Referral_Partner__c`, `Channel_Account_Manager__c`, `Partner_Account_Name__c`, `Number_of_Distributors/Resellers__c`, `Partner_MDF_Activity_ID__c`, `Fortra_Partner_Marketing_Involvement__c` | |
| **Qualification (MEDDPICC)** | `Champion_Identified__c`, `Economic_Buyer_Identified__c`, `Pains_and_Challenges__c`, `Negative_Consequences__c`, `Positive_Business_Outcomes__c`, `Value_Drivers__c`, `Required_Capabilities__c`, `Technical_Win_Confirmed__c`, `Demo/Discovery/Technical_Closure_Complete__c` | |
| **Forecasting / ARR** | `Total_ARR__c`, `Opportunity_NARR__c`/`_Calculated__c`, `Displaced_ARR__c` (+`_old`), `ALE_Amount_View__c`, `Expected_Renewal_Amount/Date__c`, `Renewed_Contract__c`, `Renewal_Risk__c` (+reasons/explanation), `Forecast_Notes__c`, `ARR_Last_Updated__c`, `Conversion_Rate__c`/`Dynamic_Conversion_Rate__c` | Renewal-risk reasoning block. |
| **AWS co-sell** | `AWS_Marketplace__c`, `AWS_Marketplace_Agreement/Offer_ID__c`, `AWS_Account_Manager_*`, `AWS_PSM_*`, `AWS_Sales_Stage__c`, `AWS_Score__c`, `AWS_Account_Number__c` | |
| **Trial / POC** | `Proactive_Trial__c`, `Trial_Start/End_Date__c`, `Trial_Status/Manager/Notes__c`, `Trial_Date_Confirmed__c`, `POC_Needed/Complete__c` | |
| **Type / lifecycle** | `Sale_Type__c`, `Cross_Sale_Type__c`, `Cross_Sell_User__c`, `Deal_Origin__c`, `Upsell_Opportunity__c`, `Subscription_Term__c`, `Closed_Lost_Reason/Sub_Reason/Detail__c`, `Re_Opened_Date__c`, `Inquiry/Lead/SQL_Created_Date__c`, `Deal_Cycle_Time_Days__c` | |
| **Places / legal** | `Bill_To_Place__c`, `Ship_To_Place__c`, `Legal_Entity__c`, `LE_Change_In_Progress__c`, `Legal_Review_Started/Completed__c`, `Territory__c` | |
| **Products** | `Product_of_Interest__c`/`Products_of_Interest__c`, `Incumbent_Competitor__c`(+renewal date), `Is_Branded__c` | |
| **Integration / automation** | `HS_Sync_*`, `HS_Deal_Id__c`, `Legacy_Id__c`, `Disable_Automation__c`, `Run_Assignment__c`, `RecordTypeId__c` (text mirror), `Execute_Auto_Project_Creation_Process__c`, `Project_Creation_Processed__c` | |

**Record types:** none defined in source (logic via `Sale_Type__c` / text `RecordTypeId__c`).

---

## Cross-cutting patterns & gotchas

- **Per-channel sync quartet:** `<Channel>_Sync_Status__c / _Message__c / _Payload__c / _Correlation_Id__c`
  (+ `Overall_Status__c`) repeats for **Workday, HubSpot, Legacy, PO** on Order/Account/Contact/Opportunity.
  `Payload` fields are **logs of the last send, not the source of truth** — integrations read live data.
- **`Source_List_Price__c`** (QLI & OrderItem) is the list-price field the RCA pricing procedure binds to;
  in-place edits without re-syncing the context definition cause the "contextDefinitionName" reprice gack.
- **`Workday_Contract_Line_Type__c`** (OrderItem) + **`Original_Order_Item__c`** subsplit detection are the
  most failure-prone pair in the system (SC-3347 / 3368 / 3210). `Original_Order_Item__c` is set on
  *quantity* splits too, which is the recurring mis-stamp trap.
- **No business RecordTypes on the transaction objects** (Quote/Order/QLI/OrderItem) — type behavior is
  driven by **picklists** (`Quote_Type__c`, `Fortra_Product_Type__c`). Only Product2, Contact, and Contract
  carry real RTs.
- **Migration keys** `Legacy_Id__c` (legacy system) and `GearsetExternalId__c` / `ExternalId__c` (Gearset
  natural-key matching) appear on nearly every object — set per-object natural-key matching on deploys or
  FKs get silently nulled.
- **Deprecated / cruft to ignore:** QLI `Users_Per_Partition_del__c`, `pGroup_del__c`; Quote `Test_Field__c`,
  `Annuial_Revenue_Base__c` (typo), `Annual_Revenue_Base_old__c`; Opportunity `Displaced_ARR_old__c`.
