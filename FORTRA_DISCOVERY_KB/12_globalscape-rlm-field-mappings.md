# Pricing & Products — Globalscape → Salesforce RLM Field Mappings

> **Scope:** The legacy **Globalscape** Salesforce org (running **Salesforce CPQ / Steelbrick — the `SBQQ__` managed package** plus the **Avalara AVA_SFCPQ tax** package and a half-built, since-cancelled **NetSuite Celigo `netsuite_conn__`** integration) field-by-field inventoried and triaged for migration onto **Salesforce Revenue Cloud Advanced (RCA / RLM)**. Five field-metadata workbooks (`*_RLM_Mapped.xlsx`) cover Contract, Order, CPQ (Quote/QuoteLine/Product2), CPQ-supporting, and standard-object (OpportunityLineItem) fields; one SQL script (`GSPricingExampleScripts.sql`) documents how Globalscape's **finance system** auto-generates License + M&S SKUs and prices.
>
> **What this is:** A **migration field-map / triage inventory**, not a finished target-state design. Each field carries three discovery-owner decision columns — **"Still in Use"** (Yes / No / Maybe / ?), **"Required for Workday"**, **"Should be Visible on Order Detail Page"** — plus **Fortra Notes** and **BSI Notes** (Business Systems & Innovation, the integration build owner). The recurring BSI verdict on the entire `SBQQ__` field set is: *"These are used by Salesforce (Steelbrick CPQ). I assume similar things exist in RCA, but these are only needed if RCA needs them."* In other words, **the CPQ package fields are NOT a committed RLM schema** — they are the legacy source to be re-expressed in native RLM objects.
>
> **Connection to the rest of the program:** Globalscape is one of three legacy CRMs being consolidated (alongside D365/Dynamics and Tripwire SF) onto RCA, with **Workday** as the financial back end and **MuleSoft** as the integration layer. The "Required for Workday" column on Order is the seed of the **Order → Workday** payload that MuleSoft builds (see the design-KB Workday integration notes). Product hierarchy/grouping fields are flagged for replacement by the **new RCA Product Catalog** (Product2 + attributes + ProductComponentGroup), not 1:1 migrated.

---

## 1. Source Workbooks & Sheets

| Workbook (`.xlsx`) | Sheets (rows × cols) | Migration relevance |
|---|---|---|
| **Contract_Field_Metadata** | `Contract` (83r), `ContractLineItem` (18r), `Subscription` (86r) | Contract + CPQ Subscription asset model |
| **Order_Field_Metadata** | `Order` (111r), `OrderItem` (63r), `OrderItemConsumptionSchedule` (13r) | Order → Workday payload basis |
| **CPQ_Field_Metadata** | `Quote` (166r), `QuoteLine` (153r), `Product2` (130r) | Quote/QuoteLine pricing engine + product catalog |
| **CPQ_Supporting_Field_Metadata** | `Favorite`, `FavoriteProduct`, `ImportFormat`, `ImportColumn`, `Localization`, `LookupData` (12r), `SolutionGroup`, `Theme` (233r), `UpgradeSource` | CPQ supporting config; nearly all **"Still in Use = No"** except **LookupData** |
| **Standard_Objects_Field_Metadata** | `OpportunityLineItem` (40r) | Pipeline/forecast (ALE) reporting |
| **GSPricingExampleScripts.sql** | n/a | Legacy finance-system SKU/price generation logic |

**Column schema used across every sheet** (the mapping table format):
`Still in Use` · *(Order only:* `Required for Workday`, `Should be Visible on Order Detail Page`, `Detail Page Screen Section`) · `Fortra Notes` · `BSI Notes` · `API Name` · `Label` · `Type` · `Length` · `Precision` · `Scale` · `Required` · `Unique` · `External ID` · `Default Value` · `Formula` · `Help Text` · `Reference To` · `Relationship Name` · `Picklist Values` · `Createable` · `Updateable` · `Deprecated` · `Custom`

> **Cross-cutting decision:** every field whose BSI/Fortra note reads *"There was a project to move to NetSuite, but was cancelled when Globalscape was acquired by Fortra"* is the `netsuite_conn__*` package. **All such fields are `Still in Use = No` and are out of scope for the RLM migration.** They are enumerated once per object below rather than repeated.

---

## 2. ORDER (`Order` object) — the Workday-bound fields

The Order sheet is the most important for downstream integration because of the **"Required for Workday"** flag. Fortra's standing note: *"This will be standard on all orders, not specific to GS. Should be pulled from quote/opp."* Most standard address/relationship fields are kept; almost all custom GS rollups, the NetSuite set, and CPQ contracting helpers are dropped or "only if RCA needs them."

### 2.1 Order fields KEPT and FLAGGED "Required for Workday = Yes"

| Globalscape API Name | Label | Type | Notes / Workday role |
|---|---|---|---|
| `AccountId` | Account ID | reference→Account | Standard on all orders; pull from quote/opp |
| `Bill_To_Account__c` | Bill To Account | reference→Account | Standard on all Fortra orders |
| `BillToContactId` | Bill To Contact ID | reference→Contact | Standard on all Fortra orders |
| `BillingAddress` / `BillingCity` / `BillingCountry` / `BillingState` / `BillingStreet` / `BillingPostalCode` | Billing address block | address/string | Standard on all Fortra orders |
| `SBQQ__BillingFrequency__c` | Billing Frequency | picklist | `Monthly, Quarterly, Semiannual, Annual, Invoice Plan` |
| `ContractId` | Contract ID | reference→Contract | Standard — link to contract |
| `Contract_Start_Date__c` | Contract Start Date | date | "earliest date from order lines for related MS contract/subscription"; pull from quote |
| `Is_New_Logo__c` | Is New Logo | boolean (formula) | Net-New-Logo tracking; will capture from opp type & pass to Workday. Formula uses `Override_New_Logo__c`, `gsShipDate__c`, `Account.New_Logo_End_Date__c` with a **365-day** new-logo window |
| `Legal_Entity__c` | Legal Entity | picklist | `Fortra, LLC` (default), `Globalscape`, `Barcelona/04 Computing Group` |
| `MSYears__c` | MSYears | double | "Max number of MS years ordered on the order's product lines" — length of term |
| `New_Licenses__c` | New Licenses | currency | Revenue-category rollup (*see "D365 list for Total fields"*) |
| `New_Maintenance__c` | New Maintenance | currency | Revenue-category rollup |
| `New_Pro_Services__c` | New Pro Services | currency | Revenue-category rollup |
| `OpportunityId` | Opportunity ID | reference→Opportunity | Link to opp visible on all Fortra orders |
| `TotalAmount` | Order Amount | currency (Required) | |
| `EndDate` | Order End Date | date | Pulls from quoted contract end date |
| `OrderNumber` | Order Number | string (Required) | |
| `EffectiveDate` | Order Start Date | date (Required) | Pull from quote/opp; matches contract start/end |
| `Type` | Order Type | picklist | `Direct` (default), `Channel`, `Renewal` — "should reflect the opp type" |
| `Partner_Account__c` | Partner Account | reference→Account | "Should be our Bill To Account"; need to identify partner on order |
| `SBQQ__PaymentTerm__c` | Payment Term | picklist | `Net 30` default; values: `Due on receipt, Net 15, Net 30, Net 45, Net 60, Net 90, COD, Hold, 5%15 Net 60` |
| `PoNumber` | PO Number | string | Default for all Fortra orders |
| `Sales_Type__c` | Sales Type | formula(text) | `Net New, Add New, Add-on, Renewal` (from `Opportunity.Sales_Type__c`) |
| `SBQQ__RenewalTerm__c` | Renewal Term | double | Defaults to original contract term |
| `SBQQ__RenewalUpliftRate__c` | Renewal Uplift (%) | percent | Standard on all Fortra orders |
| `ShippingAddress`/`City`/`Country`/`State`/`Street`/`PostalCode` (+ Geocode/Lat/Long) | Shipping block | address | All marked Workday-required |

### 2.2 Order fields KEPT but NOT Workday-required (operational / CPQ helpers)

`ActivatedById`, `ActivatedDate` (audit history), `BillingGeocodeAccuracy/Latitude/Longitude` (out-of-box OK), `Commission_Date__c` + `Default_Commission_Date__c` (commission tracking — **"Need Finance weigh-in on Workday requirements"**, marked `?`), `Description`, `OriginalOrderId` (reduced/cancelled orders), `OrderReferenceNumber`, `PoDate`, `Pricebook2Id`, `QuoteId`, `Sales_Rep__c`, `ShipToContactId`, `Status` (`Draft, Activated`), `StatusCode` (`Draft, Activated, Cancelled, Expired, Superseded`), and the CPQ-contracting helpers (kept "only if RCA needs them"): `SBQQ__Contracted__c`, `SBQQ__ContractingMethod__c` (`By Subscription End Date` default / `Single Contract`), `SBQQ__TaxAmount__c`, `SBQQ__FirstContractedOrder__c`, `SBQQ__OrderBookings__c`, `SBQQ__Quote__c`, `SBQQ__PriceCalcStatus__c`/`Message`, `SBQQ__TotalAmount__c` (with-tax), `IsDR__c` (IsChannelComp — partner deal-registration), `IsReductionOrder` ("ML: Will manage via order status/amendment"), `Reseller_PO__c`.

**`Default_Commission_Date__c` formula** (commission timing rule worth preserving):
`IF(IsReductionOrder, gsShipDate__c, IF(NOT IsRenewal__c, gsShipDate__c, IF(gsShipDate__c > Contract_Start_Date__c, gsShipDate__c, Contract_Start_Date__c)))` → "gsShipDate for Non-Renewals, Contract Start Date for Renewals."

### 2.3 Order fields DROPPED (`Still in Use = No`) — concept may carry, field will not

| Field | Why dropped (note) |
|---|---|
| `Clawback_Repaid_Date__c` | Commission clawback tracking |
| `Account_NameText__c` | Flattened lookup text — use lookup |
| `DoNotInvoicePS__c` | Post-paid PS invoicing — "handled by Certinia and Workday" |
| `IsRenewal__c` | "tracked by order type" (`Type` picklist) |
| `Is_Reversed__c` | "Not needed if reduction/reversed orders tracked out of box with RCA" |
| `Most_Recent_Order__c`, `OrderOne__c`, `Order_Source__c` (`Salesforce, Online, Accounting System`), `Override_New_Logo__c` (`Calculate, New Logo, Not New Logo`), `SingleYearMS__c`, `Total_List_Price__c` | Legacy helpers / category rollups to be redone via catalog hierarchy |
| `gsOrderID__c`, `gsShipDate__c` | "Copied into SF from the Globalscape finance system… probably not needed go-forward, but maybe in interim phases" (`Still in Use = Not Sure`) |
| All `netsuite_conn__*` (Celigo) | Cancelled NetSuite project |

---

## 3. ORDERITEM (`OrderItem`)

### 3.1 Kept order-line fields

Standard: `AvailableQuantity`, `Description` (Line Description), `EndDate`, `ListPrice`, `OrderId`, `OrderItemNumber`, `OriginalOrderItemId`, `PricebookEntryId`, `Product2Id`, `Quantity`, `ServiceDate` (Start Date), `TotalPrice`, `UnitPrice`.

Custom kept:
- `Commissionable_Amount__c` (currency) = `(UnitPrice * Quantity) - Royalty_Amount__c` — "accounts for potential royalty amount in commissions."
- `Royalty_Amount__c` — royalty owed for the product on this line.
- `DoNotExpand__c` (boolean) — "Determines if 1 or multiple license keys are generated when quantity > 1. e.g. qty=10: 1 key usable on 10 servers, **or** 10 separate keys."
- `OorderProductMSYears__c` (double, formula) = `IF((YEAR(EndDate)-YEAR(ServiceDate))<1, 1, YEAR(EndDate)-YEAR(ServiceDate))` — contract length in years.
- `Serial_Number__c` (unique) — identifies a specific product instance.
- `gsOrderDetailID__c`, `gsOrderID__c` — "Unique order id from finance system."
- `OrderCategory__c` (picklist) — `Invoice, Order, MIX, ProfSvc, Ghost`.
- Full `SBQQ__*` line set (kept "only if RCA needs them"): includes `SBQQ__ProductSubscriptionType__c` (`Renewable, One-time, Renewable/Evergreen, Evergreen`), `SBQQ__PricingMethod__c` (`List, Cost, Block, Percent Of Total, Custom`), `SBQQ__DimensionType__c`/`SegmentIndex`/`SegmentKey` (MDQ multi-segment), `SBQQ__Subscription__c`, `SBQQ__UpgradedSubscription__c`, `SBQQ__UnproratedNetPrice__c` (full-term net), `SBQQ__BookingsIndicator__c` (`Include`/`Do Not Include`), `SBQQ__OrderProductBookings__c`.

### 3.2 Dropped order-line custom fields (`Still in Use = No`) — *"Should use standard fields, not custom"* / *"flattened product info"*

`Line_Discount__c` (=`IF(ListPrice>0, 1-UnitPrice/ListPrice, 0)`), `Line_Total__c` (=`Quantity*UnitPrice`), `ProductCodeText__c`, `ProductName__c`, `Product_Family__c`, `Product_Support_Type__c`, `Prorated_Price__c`, `Total_List_Price__c` (term-prorated formula), `UnitPriceForceOverride__c`, plus all `netsuite_conn__*`.

### 3.3 OrderItemConsumptionSchedule — **entirely `Still in Use = No`**

All 13 rows are dropped (usage/consumption pricing not used in GS). Notable fields if RLM usage-pricing is revisited: `SBQQ__BillingTermUnit__c` (`Month, Year, Quarter`), `SBQQ__RatingMethod__c` (`Tier`), `SBQQ__Type__c` (`Range, Slab`).

---

## 4. CONTRACT (`Contract`)

### 4.1 Kept Contract fields

**Standard (Yes):** `AccountId`, `ActivatedById`, `ActivatedDate`, full Billing & Shipping address blocks, `ContractNumber`, `ContractTerm` (int), `CustomerSignedDate`/`Id`/`Title`, `Description`, `EndDate` (Contract End Date), `LastApprovedDate`, `SpecialTerms` (textarea 4000 — *"not sure how RCA handles this,"* marked `Yes?`), `StartDate`, `Status` (`In Approval Process, Activated, Draft`), `StatusCode` (`Draft, In Approval Process, Activated, Terminated, Expired, Rejected, Negotiating, Awaiting Signature, Signature Declined, Signed, Canceled, Contract Expired, Contract Terminated`).

**Custom kept (Yes) — renewal/co-term semantics worth preserving:**
| Field | Meaning |
|---|---|
| `Co_termed_Contract__c` (boolean) | "Flags the contract was co-termed to a previously existing contract so the next renewal includes all items from both. **May work differently in RCA.**" |
| `Expected_Ren_Amount__c` (currency) | "Expected amount of next renewal, accounting for any uplift/COLA." |
| `Ren_Opportunity_Owner__c` (formula) | Renewal specialist assigned to renewal opp |
| `Renewal_Status__c` (formula) | Initial `Open` → `Co-termed` / `Renewed` / `Lost` based on renewal opp won/closed state |

**CPQ helpers kept "if RCA needs":** `SBQQ__ActiveContract__c` (formula: activated + (not-evergreen & EndDate≥TODAY OR evergreen)), `SBQQ__Amendment*` set, `SBQQ__MDQRenewalBehavior__c` (`De-segmented`), `SBQQ__Opportunity__c`, `SBQQ__Order__c`, `SBQQ__PreserveBundleStructureUponRenewals__c` (default **True**), `SBQQ__RenewalUpliftRate__c`, `SBQQ__SubscriptionQuantitiesCombined__c`.

### 4.2 Dropped Contract fields (`Still in Use = No`)

`CompanySignedDate`/`Id`, `ContractOne__c`, `Expiring_InMonth__c`, `Last_Invoice_Reversed__c`, `Last_Invoice__c`, `Last_MS_Amount__c` (=`SBQQ__Order__r.New_Maintenance__c + New_SaaSEftCloud__c`), `Last_PO__c`, `Master_Contract_Label__c`, `OwnerExpirationNotice`, `Renewal_Amount__c`, `Renewal_Close_Date__c`, `Renewal_Segment__c`, `Renewal_Type__c` (`Direct, Channel, InHouse, SAM, RAM, INT, SMB, Arcus`), `Single_Year_MSAmount__c`/`_Rollup__c`, `Top_100_Account__c` ("Top 100 Strategic Accounts for Renewal Owner Mark Alvarado"), all `netsuite_conn__*` (including `Bill_To_Tier__c`/`Ship_To_Tier__c` = `End User, Reseller, Distributor`).

### 4.3 ContractLineItem — **entirely `Still in Use = No`** ("Contract Line Items not used")

All 18 standard CLI fields dropped. GS tracks the asset model via **Subscription** instead (next section).

---

## 5. SUBSCRIPTION (`SBQQ__Subscription__c`) — the CPQ asset/recurring model

GS uses the CPQ Subscription object as its active recurring-revenue asset record (since ContractLineItem is unused). Almost all fields are `Yes` "if RCA needs them." Key ones for the RLM Asset/Subscription mapping:

| Field | Type | Meaning |
|---|---|---|
| `Active__c` | boolean (formula) | `SBQQ__EndDate__c >= TODAY()` |
| `SBQQ__Account__c` | ref→Account | Volume-discount aggregation owner |
| `SBQQ__Contract__c` / `SBQQ__ContractNumber__c` | ref / formula | Governing contract |
| `SBQQ__Product__c` / `ProductName__c` / `ProductId__c` | ref→Product2 / formula | |
| `SBQQ__Quantity__c` (Required) / `SBQQ__RenewalQuantity__c` | double | |
| `SBQQ__StartDate__c` / `SBQQ__EndDate__c` | date (formula) | Fall back to Contract start/end if subscription-specific blank |
| `SBQQ__SubscriptionStartDate__c` / `SubscriptionEndDate__c` | date | |
| `SBQQ__NetPrice__c` / `ListPrice__c` / `RegularPrice__c` / `CustomerPrice__c` / `SpecialPrice__c` / `RenewalPrice__c` | currency | Pricing waterfall snapshot |
| `SBQQ__SubscriptionPricing__c` | picklist | `Fixed Price, Percent Of Total` |
| `SBQQ__SubscriptionType__c` / `ProductSubscriptionType__c` | picklist | `Renewable, One-time, Renewable/Evergreen, Evergreen` |
| `SBQQ__ChargeType__c` | picklist | `One-Time, Recurring, Usage` |
| `SBQQ__BillingFrequency__c` / `BillingType__c` | picklist | `Monthly…Annual, Invoice Plan` / `Advance, Arrears` |
| `SBQQ__PartnerDiscount__c` / `DistributorDiscount__c` / `OptionDiscount__c` / `Discount__c` | percent | Discount waterfall |
| `SBQQ__RenewalUpliftRate__c` / `RenewedDate__c` | percent / date | Renewal uplift compounding |
| `SBQQ__RenewalProductId__c` (formula) | string | Resolves renewal SKU via `SBQQ__Product__r.SBQQ__RenewalProduct__c` chain |
| `SBQQ__Dimension__c` + MDQ Segment* fields | mixed | Multi-segment (MDQ) subscriptions |
| `SerialNumber__c` | string | Identifies specific product instances when >1 owned |

Subscription fields **dropped** (`No`): `Contract_End_Date__c`, `Imported__c`, `Single_Year_MSAmount__c` (annualization formula `NetPrice/(End-Start+1)*365`), `Support_Type__c` (derivable from product), `gsDataOrderDetailId__c`.

---

## 6. QUOTE (`SBQQ__Quote__c`) & QUOTELINE (`SBQQ__QuoteLine__c`)

### 6.1 Quote — Globalscape-specific approval / template / tax fields

The Quote sheet exposes Globalscape's **discount-approval matrix** and **quote-PDF section logic**, both flagged as likely NOT to migrate (Fortra has its own Approval Matrix; PDF sections to be handled in RCA/Certinia).

**Discount approval-threshold fields (`Maybe` — "globalscape specific, probably not needed for the Fortra Approval Matrix"):** `Discount_CuteFTP__c`, `Discount_CuteFTP_M_S__c`, `Discount_EFTArcus__c`, `Discount_EFTLicenses__c`, `Discount_EFTMandS__c`, `Discount_EFT_Kenetix__c`, `Discount_EFT_Tier__c`, `Discount_ProServices__c`, `Discount_WAFS__c` — i.e. **per-product-group maximum discounts** drive approval. Plus `Software_Disc__c` (License Disc %) and `Support_Type__c` (`NoSupport, Basic, Professional, Premier, Expert` — *"rep selects support level and CPQ uses this to know which maintenance SKU to add… should be handled however RCA handles product rules."*).

**Quote-PDF "Has*/Show*" section toggles (`Maybe` — "hide/show sections in quote PDF, mostly SOWs of standard service packages, not sure how to handle in RCA"):** `HasArcusPlat__c`, `HasArcusStd__c`, `HasArcusQuickStart__c`, `HasProfSvc__c`, `HasPShours__c`, `HasQuickStart__c`, `HasRequiredSOW__c`, `HasSubscriptions__c`, `HasTraining__c`, `Has_Accelerator__c`, `Has_Assessment__c`, `Has_Cutover__c`, `Has_EFT_TAM__c`, `Has_Health_Check__c`, `Has_Hourly_TAM__c`, `Has_Migration__c`, `Has_Prepaid_Hours__c`, `Has_Upgrade__c`, `ShowArcusPlatinum__c`, `ShowArcusStandard__c`, `ShowInQuoteDocument__c`, `Show_Quote_Discounts__c`.

**Quote-template selection logic (`Quote_Template_Frla__c` formula, dropped):** chooses one of ~8 hardcoded `QuoteTemplate` IDs (e.g. `a2L1C000003nWcZ`, `a2L1C000000RysB`) keyed on **Direct vs Indirect** (Distributor/Partner present) × Subscriptions/Arcus/Renewal. `DualSignatures__c` / `SingleSignature__c` toggle one vs two PDF signature blocks.

**Avalara tax (kept):** `AVA_SFCPQ__SalesTaxAmount__c`, `Sales_Tax_Amount__c` / `Total_Including_Tax__c` / `Renewal_Total_Including_Tax__c` formulas.

**Core CPQ Quote pricing rollups (kept "if RCA needs"):** `SBQQ__ListAmount__c`, `SBQQ__NetAmount__c`, `SBQQ__RegularAmount__c`, `SBQQ__CustomerAmount__c`, `SBQQ__AdditionalDiscountAmount__c`, `SBQQ__AverageCustomerDiscount__c` (`(List−Customer)/List`), `SBQQ__AveragePartnerDiscount__c` (`(Customer−Net)/Customer`), `SBQQ__TotalCustomerDiscountAmount__c`, `SBQQ__TargetCustomerAmount__c`, `SBQQ__CustomerDiscount__c`/`PartnerDiscount__c`/`DistributorDiscount__c`, `SBQQ__Type__c` (`Quote, Renewal, Amendment, Change Order`), `SBQQ__Status__c` (`Draft, In Review, Approved, Denied, Presented, Accepted, Rejected`), `SBQQ__Partner__c`/`Distributor__c`, `SBQQ__GenerateContractedPrice__c` (`Price, Discount Schedule, Do Not Generate`), `SBQQ__PaymentTerms__c`, full Bill-To/Ship-To address mirrors.

**Auto-uplift (renewal) helpers (dropped, `No`):** `gsAutoUplift_Allowed__c`, `gsAutoUplift_Applied__c`, `gsReadyForAutoUplift__c`, `gsPrevQuote_MSQuoteLinesCount__c`, `Custom_Markup__c`, `MSofLicense__c` (M&S % of license cost), `Renewal_Avg_Customer_Discount__c`.

### 6.2 QuoteLine — the pricing waterfall & the ALE formula

QuoteLine is the **largest pricing surface** (153 fields). The full `SBQQ__` pricing waterfall is present and is the canonical reference for re-implementing pricing in RLM. Key waterfall fields:

| Field | Type/Formula | Role in waterfall |
|---|---|---|
| `SBQQ__ListPrice__c` (List Unit Price) | currency | From price book |
| `SBQQ__OriginalPrice__c` | currency | Original price-book unit price |
| `SBQQ__SpecialPrice__c` (+`Type`/`Description`) | currency / `Contracted Price, Renewal, Custom` | Volume/contracted/renewal price |
| `SBQQ__RegularPrice__c` → `SBQQ__RegularTotal__c` | currency | Unit price before additional discount |
| `SBQQ__CustomerPrice__c` (Customer Unit Price) → `SBQQ__CustomerTotal__c` | currency | Net of customer discounts, **before** partner discount |
| `SBQQ__PartnerPrice__c` → `SBQQ__PartnerTotal__c` | currency | After partner discount, before distributor |
| `SBQQ__NetPrice__c` (Net Unit Price) → `SBQQ__NetTotal__c` | currency | Final net |
| `SBQQ__Discount__c` / `AdditionalDiscount__c`/`Amt` | percent/currency | Discretionary discount |
| `SBQQ__VolumeDiscount__c`, `SBQQ__DiscountSchedule__c`/`Tier`/`Type` (`Range, Slab`) | percent/ref | Volume-discount schedule |
| `SBQQ__TermDiscount__c`/`Schedule`/`Tier` | currency/ref | Term-based discount |
| `SBQQ__PartnerDiscount__c` / `DistributorDiscount__c` / `OptionDiscount__c` | percent | Channel discounts |
| `SBQQ__Uplift__c` / `UpliftAmount__c` | percent/currency | Year-over-year compounding uplift (not on Year 1) |
| `SBQQ__TotalDiscountAmount__c` / `TotalDiscountRate__c` | currency/percent (formula) | Aggregate discount (Slab-aware) |
| `SBQQ__PricingMethod__c` | `List, Cost, Block, Percent Of Total, Custom` | |
| `SBQQ__SubscriptionPercent__c` / `SubscriptionBase__c` / `SubscriptionCategory__c` (`Hardware, Software`) | Percent-of-Total config | M&S-as-%-of-license modeling |
| `SBQQ__EffectiveQuantity__c` / `Quantity__c` / `PriorQuantity__c` / `UpgradedQuantity__c` | double (formula) | Amendment/renewal quantity deltas |
| `SBQQ__EffectiveStartDate__c` / `EffectiveEndDate__c` / `EffectiveSubscriptionTerm__c` | date/double (formula) | Cascade line→group→quote dates |
| `SBQQ__ProratedListPrice__c` / `ProratedPrice__c` / `ProrateMultiplier__c` | currency/double | Proration |
| `SBQQ__UnitCost__c` / `Cost__c` / `GrossProfit__c` / `Markup*` | currency | Cost/margin path |

**The ALE (Annual License Equivalent) formula — critical, preserve exactly.** `Quote_Line_ALE__c` (currency) drives forecast/pipeline. It rolls into `OpportunityLineItem.ALE_Amount__c` (=`SBQQ__QuoteLine__r.Quote_Line_ALE__c`):

```
IF( NOT(SBQQ__Product__r.ExcludeFromALECalc__c),
  IF( Id = "a2JPb000001Hvm8", 38250,                         // one hardcoded override line
    IF( SBQQ__Product__r.ProductCode = "GSRECO-X", Quote_Line_Total__c * 0.35,
      CASE( Family__c,
        "Licenses",     Quote_Line_Total__c * 0.35,           // licenses annualized at 35%
        "M&S",          (Quote_Line_Total__c / ActualTerm__c) * 12,
        "Subscriptions",(Quote_Line_Total__c / ActualTerm__c) * 12,
        "ProfSvc",      (Quote_Line_Total__c / ActualTerm__c) * 12,
        0 ))))
```
Supporting: `ActualTerm__c` = months derived from `SBQQ__EffectiveEndDate − EffectiveStartDate` (`ROUND((End−Start)/365*12)`, min 1).

**QuoteLine custom fields kept (Yes):** `Is_Renewal__c`/`Quote_Type_Renewal__c` (`= Quote.Type='Renewal'`), `ProductCategory__c`/`Product_SubCategory__c` (reporting rollup — *"need to summarize ALE by product rollup levels"*), `Quote_Line_Total__c`, `Serial_Number__c`, `Single_License__c` ("single license regardless of quantity").

**QuoteLine custom fields dropped (No) — uplift LWC helpers:** `ActualTerm__c`, `Contract_End_Date__c`, `Discounted_Unit_Price__c`, `ProductSKU__c`, `ProductToReview__c`, `Quote_Expiration_Date__c`, `Renewal_List_Total__c`/`_Flow__c`/`Renewal_Not_Same__c`, `Sort_Order__c`, `Uplifted_List_Price__c`, and the entire `gsUplift_*` set (`gsUplift_Amount__c`, `_Applied__c`/`By`/`Date`, `_Autouplift_Error__c`, `_Pricing_Base__c` (`Previous Quote, Pricebook Entry`), `_Rate__c`, `_Start__c` (`Year 1, Year 2`)) — *"custom Lightning component for applying uplift when co-terming/upgrading; should be handled by RCA."*

---

## 7. PRODUCT2 (`Product2`) — the catalog to be re-modeled in RCA

Most product-hierarchy/grouping fields carry the note *"Used for product hierarchy/grouping. Should be replaced by new product catalog"* or *"probably replaced by attributes in RCA."* They are kept (`Yes`) only as the migration source.

### 7.1 Product classification picklists (the legacy taxonomy — map to RCA catalog/attributes)

| Field | Picklist values |
|---|---|
| `Family` (Product Family) | `Licenses, M&S, MIX, ProfSvc, Other, Arcus, Subscriptions` |
| `Product_Category__c` | `EFT Continuum, EFT Enterprise, EFT Express, DMZ Gateway, Arcus, Professional Services, CuteFTP, Cloud Services, CUCM, EFT SMB, Kenetix, Mail Express, Other, scConnect, SecureDrive, TappIn, WAFS` |
| `Product_Model__c` | `EFT Enterprise, EFT SMB, EFT Bundles, EFT Arcus, SecureDrive, scConnect, Mail Express, Standalone, Cloud Services, CUCM, CuteFTP, WAFS, Professional Services, Success 360, TAM, EFT Express, Expert TAM, EFT Enterprise Subscription, EFT Express Subscription, DO NOT USE - Arcus (Legacy), EFT Continuum, EFT Continuum Subscription` |
| `ProductGroup__c` | `EFT SMB, EFT Enterprise, CuteFTP, Cisco UCM, Workspaces, Mail Express, PS Tools, EFT Custom Solution, SMB Workspaces, TAM, SecureDrive, Accelerate Module, Professional Services, WAFS, Advanced Workflow Engine (AWE), Web Transfer Client (WTC), Auditing & Reporting Module (ARM), Advanced Auth, MIX, scConnect, SMB Web Transfer Client (WTC), Kenetix, Arcus, Secure ad hoc Transfer (SAT), AS2 Data Transfer, Cloud Connector Module (CCM), Enterprise Actions, FM Module, Transfer Actions, FTPS Server, DMZ Gateway, HTTP/S Module, OpenPGP Encryption, Compliance Module, Secure Forms, SFTP Module, Schedule Module, EFT Continuum, Remote Agent Module (RAM)` |
| `SubCategory__c` | `EFT Continuum Servers, M&S EFT Continuum, EFT Bundles, EFT Enterprise Bundles, EFT Enterprise Servers, EFT Modules, EFT SMB Bundles, EFT SMB Servers, CuteFTP, Hosted EFT, …, M&S * (many), Mail Express, MIX, Professional Services, Secure Drive, WAFS, Workspaces (WSM), PSTools, Enterprise/SMB Upgrades, Implementation, Staff Augmentation, Kenetix, Arcus (Standard/Platinum/Add-on/Basic/Custom/Premium), Upgrades, Public Training, Assessments, Quickstarts, Cutovers, HealthChecks & Assessments, Migrations, T&M Custom Projects, Training, Consulting, Hours, Accelerators, Prepaid Hours, Hourly TAM, PS EFT TAM` |
| `Support_Type__c` | `Standard, Platinum, NoSupport, Basic, Professional, Premier, Expert` |
| `Instance__c` | `Active, Standby, Dev, Non-Prod` (environment type → "replaced by attributes in RCA") |
| `Product_Status__c` | `In Use, Retired, Inactive` ("Retired" = renewals/support only) |
| `PS_Type__c` | `Onsite, Remote` |

### 7.2 Product2 custom business fields kept

- `ItemControlNumber__c` — *"Used by license-key server to know what kind of license key to generate."*
- `License_Quantity__c` — *"Similar to Usage in D365; number of 'seats'. Quantity may be 1, but if license qty=10 they get 10 seats per quantity."*
- `ProductNumber__c` (unique double) — *"Unique product id generated by financial system. This would be a **Workday product Id** in the new system."* (key Workday cross-reference)
- `Royalty_Dollar__c` / `Royalty_Pcnt__c` — *"some GS products are licensed and a portion is paid as royalty."*
- `IsSubscription__c`, `IsRenewalProduct__c`, `IsSupport__c`, `Is_PS_Subscription__c`, `ExcludeFromALECalc__c` (the ALE-exclusion flag referenced by the QuoteLine ALE formula), `AVA_SFCPQ__TaxCode__c`/`SBQQ__TaxCode__c`.
- Full `SBQQ__*` product-config surface (`Renewal`/`Upgrade` chains, `ChargeType`, `BillingFrequency`/`Type`, `SubscriptionPercent`/`Category`/`Target`, `BlockPricingField`, `ConfiguredCodePattern`/`DescriptionPattern`, etc.) kept "if RCA needs."

### 7.3 Product2 dropped: `DisplayUrl`, `ExternalId`, `Record__c`, `NotAutoInvoiced__c`, `Requires_Custom_SOW__c`, all schedule installment fields, all `netsuite_conn__*` (incl. `NetSuite_Item_Type__c` = `Inventory Item, …, Service Sale`).

---

## 8. CPQ-SUPPORTING OBJECTS — almost all retired except LookupData

| Sheet | Decision | Note |
|---|---|---|
| **LookupData** (`SBQQ__LookupData__c`) | **`Yes` — KEEP** | *"The majority of Product Rules in Globalscape use the LookupData table to add/remove products."* Drives CPQ Product Selection Rules — the **product-rule logic** that must be re-expressed as RCA **ProductConfigurationRule / ProductComponentGroup**. Key fields: `OptionalSKU__c`→Product2, `Product_Code__c`, `SBQQ__Type__c` (`Add, Remove, Enable, Disable, Enable & Add, Disable & Remove, Show, Hide, Show & Add, Hide & Remove, Default Filter, Optional Filter`), `SBQQ__Required__c`, `SBQQ__Product__c`, `Support_Type__c`. |
| Favorite / FavoriteProduct | `No` | CPQ "favorites" shopping carts |
| ImportFormat / ImportColumn | `No` | CPQ line-import config (`SBQQ__FieldName__c`: `Discount (%), Discount (Amt), Partner Discount, Product Code, Quantity, List Price`) |
| Localization | `No` | CPQ translation strings |
| SolutionGroup | `No` | CPQ quote grouping |
| **Theme** (233 fields) | `No` | Pure CPQ configurator CSS/styling — entirely cosmetic, **no migration value** |
| UpgradeSource | `No` | `SBQQ__UpgradeConversionRate__c` ("5:1" ratios) |

---

## 9. OPPORTUNITYLINEITEM (`Standard_Objects` workbook)

Pipeline/forecast object. **`ALE_Amount__c`** (=`SBQQ__QuoteLine__r.Quote_Line_ALE__c`) is the kept field that carries the ALE pipeline currency up from the quote (see §6.2). Reporting rollups kept: `ProductCategory__c`, `ProductSubCategory__c` (=`PricebookEntry.Product2.SubCategory__c`), `Product_Family__c`, `ProductCode__c`, `SBQQ__QuoteLine__c`, `SBQQ__SubscriptionType__c`, `Serial_Number__c` (*"populated on Renewal opps to map each product back to the originally-purchased license; if a customer downsizes, identifies which license key should stop working"*). Dropped: `ALE__c` (the non-formula twin, *"added because of a formula-field limitation"*), schedule flags, all `netsuite_conn__*`.

---

## 10. GSPricingExampleScripts.sql — legacy finance-system SKU & price generation

This T-SQL (against the **Globalscape finance application's `Products` table**, NOT Salesforce) documents the **automated SKU-fanout and M&S pricing rules** that generated the legacy catalog. It is the authoritative source for **how license price relates to maintenance price** and **how SKU codes are constructed** — essential when rebuilding the RCA catalog and Workday product mapping.

### 10.1 Three product-construction patterns

1. **Standard License + Maintenance (2 separate SKUs)** — e.g. Advanced Authentication Modes ($2,500), Audit & Reporting ($2,200), AS2 Client/Server ($11,000), Advanced Workflow Engine ($7,000), Cloud Connector Actions ($2,000), Enterprise Actions ($2,200), Folder Monitor ($2,200). Each license generates **3 product rows**: License + M&S [PRO] + M&S [PRE], **each again duplicated as `[Non-Prod]` (standby) at 50% price**.
2. **Continuum Bundles + Maintenance (2 separate SKUs)** — Enterprise Bundle ($142,800), Premium ($52,500), Starter ($26,250), Collaboration ($10,500), Core Server ($9,450), FTPS Server ($4,200), SFTP Server ($4,200).
3. **Subscription Continuum Bundles (1 SKU, maintenance built into price)** — same bundles, GL/Avalara code `SW054000`, `IsSubscription=1`, "-Y" (Yearly) suffix.

### 10.2 Maintenance pricing rules (the load-bearing ratios)

| Derived SKU | Price formula | SKU suffix pattern |
|---|---|---|
| License (perpetual) | `UnitPrice` (full) | `{SKU1}-N-{SKU2}` (standard) / `{SKU1}-B-{SKU2}` (bundle) |
| **M&S [PRO]** | `UnitPrice × 0.20` (**20% of license**) | `{SKU1}-RX-{SKU2}` |
| **M&S [PRE]** (Premier) | `UnitPrice × 0.30` (**30% of license**) | `{SKU1}-MX-{SKU2}` |
| **Non-Prod / Standby** (any) | base price `× 0.50`, then M&S ratios applied on the halved price | append `-NP` |
| **Subscription License (Yearly)** | `UnitPrice` | `{SKU1}-B-{SKU2}-Y` |
| **Subscription M&S [PRE]** | `(UnitPrice / 1.2) × 0.1` | `{SKU1}-MX-{SKU2}-Y` |

`InvoiceSummaryGroup` values: `Licenses`, `M&S`, `Subscriptions`. The `Products` table columns set per insert: `ProductName, UnitPrice, GLID, LicQty, ActiveFlg, flgSupportAgreement, MntAlloc, CrmProductNum, productgroup (='HSEFT'), avalara_tax_code, InvoiceSummaryGroup, ItemControlNumber, IsSubscription, active_sb_dev, ModifiedBy, CreatedBy, CreatedDate`. The commented sample tuples also encode `ProductCategoryLic/MS` and `ProductSubCategoryLic/MS` integer codes (e.g. Standard License/M&S = `16,16,2,11`; Bundles = `16,16,4,12`).

> **Migration significance:** these ratios (M&S = 20% PRO / 30% PRE of license; Non-Prod = 50%; subscription M&S = `list/1.2 × 0.1`) are the **business pricing rules** that must be reproduced as RCA price adjustments / attribute-based pricing, and they explain the legacy 2-SKU (license + separate M&S) vs 1-SKU (subscription with built-in maintenance) split that RLM must accommodate.

---

## 11. Cross-Migration Themes & Open Questions

**Decisions / patterns captured:**
- **CPQ → RLM is a re-model, not a lift-and-shift.** The entire `SBQQ__` field set is conditional ("only if RCA needs them"); RLM's native objects replace them.
- **Workday seam = the Order "Required for Workday" column** plus `Product2.ProductNumber__c` ("would be a Workday product Id"). This is the concrete field list MuleSoft will map into the Order→Workday payload.
- **Product taxonomy** (`Family`/`Product_Category__c`/`Product_Model__c`/`ProductGroup__c`/`SubCategory__c`) → RCA Product Catalog + attributes; legacy picklists are the migration source mapping table.
- **Product Selection Rules live in `LookupData`** → must become RCA ProductConfigurationRule / ProductComponentGroup.
- **ALE** is the pipeline currency; preserve the `Quote_Line_ALE__c` CASE formula (Licenses 35%; M&S/Subs/ProfSvc annualized over `ActualTerm`).
- **M&S pricing ratios** (20%/30%/50%; subscription `/1.2×0.1`) from the SQL are the catalog pricing rules.
- **NetSuite/Celigo (`netsuite_conn__*`) is fully out of scope** — project cancelled at Fortra acquisition.
- **Avalara tax** stays (or is replaced by Workday tax — see open questions).

**Open questions / ambiguities (from the notes):**
- **Tax:** Order notes ask whether *"tax is calculated in Workday vs SFDC"* and whether Avalara `AVA_SFCPQ` / `SBQQ__TaxAmount__c` are still needed — unresolved.
- **Commission timing:** `Commission_Date__c` / `Default_Commission_Date__c` flagged `?` pending **Finance weigh-in on Workday requirements**.
- **Co-terming & renewal uplift:** `Co_termed_Contract__c` *"may work differently in RCA"*; the entire `gsUplift_*` custom LWC uplift mechanism is expected to be replaced by native RCA renewal pricing — **how** is undefined.
- **Quote PDF SOW sections & dual-signature logic** (`Has_*`, `Show_*`, `DualSignatures__c`, hardcoded `Quote_Template_Frla__c` template IDs): *"not sure how this can be handled in RCA"* — possibly Certinia/DocGen.
- **Discount-approval matrix:** GS per-product-group max-discount fields are *"probably not needed for the Fortra Approval Matrix"* — the Fortra approval model supersedes them, but the GS thresholds are not yet mapped across.
- **Consumption/usage pricing** (`OrderItemConsumptionSchedule`) is unused at GS; if RLM usage billing is wanted it would be net-new.
- **License-key generation** (`ItemControlNumber__c`, `DoNotExpand__c`, `Single_License__c`, `Serial_Number__c`) ties to an external license-key server — its integration is referenced but not specified here.
- **`Legal_Entity__c`** includes `Barcelona/04 Computing Group` alongside Fortra LLC / Globalscape — multi-entity Workday mapping implication.

> **Relation to the design KB:** This discovery field-map predates and feeds the Confluence design docs synthesized in `FORTRA_KNOWLEDGE_BASE.md`. Treat target-state object names (RCA Product Catalog, ProductConfigurationRule, native pricing procedures) as the design KB's domain; this document is the **legacy-source inventory and triage** the design builds on. Field/object names here are *Globalscape legacy* unless noted as RCA targets.

---

## Sources

All under `Fortra Discovery Documentation/Pricing and Products/Globalscape Product & Pricing Fields/` (read via extracted `.txt`):

- [Contract_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx](Fortra Discovery Documentation/Pricing and Products/Globalscape Product & Pricing Fields/Contract_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx) — Contract (83r), ContractLineItem (18r), Subscription (86r)
- [Order_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx](Fortra Discovery Documentation/Pricing and Products/Globalscape Product & Pricing Fields/Order_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx) — Order (111r), OrderItem (63r), OrderItemConsumptionSchedule (13r)
- [CPQ_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx](Fortra Discovery Documentation/Pricing and Products/Globalscape Product & Pricing Fields/CPQ_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx) — Quote (166r), QuoteLine (153r), Product2 (130r)
- [CPQ_Supporting_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx](Fortra Discovery Documentation/Pricing and Products/Globalscape Product & Pricing Fields/CPQ_Supporting_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx) — Favorite, FavoriteProduct, ImportFormat, ImportColumn, Localization, LookupData (12r), SolutionGroup, Theme (233r), UpgradeSource
- [Standard_Objects_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx](Fortra Discovery Documentation/Pricing and Products/Globalscape Product & Pricing Fields/Standard_Objects_Field_Metadata_Fortra_Globalscape_RLM_Mapped.xlsx) — OpportunityLineItem (40r)
- [GSPricingExampleScripts.sql](Fortra Discovery Documentation/Pricing and Products/Globalscape Product & Pricing Fields/GSPricingExampleScripts.sql) — legacy finance-system SKU/price generation T-SQL

**Not extractable / empty / encrypted:** none — all six source files read in full.
