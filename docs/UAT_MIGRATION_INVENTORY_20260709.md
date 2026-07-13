# FortraUAT Migration Inventory — LIVE components

> Every Salesforce metadata component migrated to **FortraUAT** that is **live & active today**, with its
> ticket + reason. Live status **verified against the org 2026-07-09** (ApexClass presence · Flow `IsActive` ·
> DecisionTable `Status` · `FieldDefinition` · `EntityDefinition` · `ValidationRule.Active`). UAT-only — none
> of this is in FortraProd. **Inactive / staged / reverted / deleted components are excluded.**

**🟢 129 live components** — Apex 53 · RCA/Revenue Cloud 16 · OmniStudio 9 · Flows 14 · Custom fields 13 ·
Permission sets/groups 6 · CMDT 3 · Objects/events 2 · LWC/FlexiPage 3 · Validation/access 2 · Config/data 5 · triggers 3.

---

## RCA · Revenue Cloud (ExpressionSet · Decision Tables · Calculation Matrices · Context)

The native Revenue Cloud Advanced pricing engine data model.

| Component | Ticket | Reason |
|---|---|---|
| **ExpressionSet** `Rev_Mgmt_Default_Pricing_Procedure` | SC-3345/3374/3390/3393/3420/3441/3473/3501 · G-01/F-07/I-03/D-17/K-01 | Shared Quote+Order pricing procedure, edited in-place V8→V24 (V23/V24 active) |
| **Decision Table** `Price_Book_Entry_Decision_Table_v2` | waterfall §1 · SC-3384 | Per-currency list-price / Base_Price lookup |
| **Decision Table** `Attribute_Based_Adjustment_Decision_Table` | SC-3360 · SC-3384 | Attribute-based (ABA) price adjustments |
| **Decision Table** `Attribute_Tier_Pricing_Matrix` | SC-3390 · SC-3384 | Attribute volume-tier pricing |
| **Decision Table** `Bundle_Based_Adjustment_Decision_Table` | bundle pricing | Bundle-based price adjustments |
| **Decision Table** `Derived_Pricing_Entries_Decision_Table` | SC-3346 · SC-3372 | Derived-maintenance contributor pricing |
| **Decision Table** `Asset_Action_Source_Entries_Decision_Table_V2` | SC-3346 | Renewal / asset-action pricing source |
| **Decision Table** `Fortra_Regional_Pricing` · `Regional_Pricing` | SC-3374 · regional | Regional multiplier tables |
| **Decision Table** `MaintenanceType` | SC-3346 | Maintenance-tier rate lookup |
| **Decision Table** `Cyber_Partner_Discount_Matrix` · `Tech_Partner_Discount_Matrix` | SC-3359 · partner | Partner discount schedules |
| **Decision Table** `Contract_Pricing_Entries_Decision_Table` | contracted pricing | Contracted-price lookup |
| **Decision Table** `Index_Rate_Decision_Table` | SC-3350 · COLA | COLA index rates |
| **Calculation Matrices** (14) | pricing waterfall | Backing rate data behind the decision tables (Price Book Entries V2, Derived Pricing Entries, MaintenanceType, Attribute Tier Pricing, Cyber/Tech Partner Discount, Fortra Regional Pricing, Attribute/Bundle/Volume Discount, Contract Pricing, Index Rate) |
| **Context Definition** `SalesTransactionContextExt_v2` | SC-3371 · SC-3441 · V16 | Pricing context: Order-node mapping of Prior_*, Cancel, Pre_Partner fields |

## OmniStudio (Integration Procedures · OmniScripts · DataMappers · DocGen)

The quote document-generation / DocuSign stack (SC-3335).

| Component | Ticket | Reason |
|---|---|---|
| **Integration Procedure** `IPFortraGenerateQuoteDoc` (v4) | SC-3335 | Orchestrates quote document generation (extract → transform → render) |
| **Integration Procedure** `SendDocuSignEnvelope` (v1) | SC-3335 · e-sign | Sends the generated quote doc as a DocuSign envelope |
| **OmniScript** `Fortra Quote Generate Document` (v3) | SC-3335 | Quote document-generation OmniScript (UI entry point) |
| **DataMapper** `DMExtractFortraQuote` (Extract) | SC-3335 | Extracts Quote + line data for the DocGen payload |
| **DataMapper** `DMTransformFortraQuote` (Transform) | SC-3335 | Transforms Quote data into the document-template payload |
| **DataMapper** `DMTransformFortraDocTemplate` (Transform) | SC-3335 | Maps template metadata for rendering |
| **DataMapper** `DMTurboExtractQuoteDocGenTemplate` (Turbo Extract) | SC-3335 | Turbo-extract of the DocGen template config |
| **DataMapper** `DMTurboExtractQuoteLineItem` (Turbo Extract) | SC-3335 | Turbo-extract of quote line items for the doc |
| **Document Template** `Fortra Quote Consolidated EN` (v3) | SC-3335 | DocGen consolidated quote PDF template (rendered by the stack above) |

## Apex Classes — pricing hooks & services

| Component | Ticket | Reason |
|---|---|---|
| `PartnerNetPricePosthook` | SC-3346/3359/3384/3544 · D-11 | Partner + derived-maint net posthook; deal-aware; SC-3544 Sales-Price stamp |
| `PartnerPricingPrehookV2` | SC-3359 · E-04 · D-11 | V2 partner prehook; Non_Orig fallback (V1→V2 flip 07-01) |
| `PartnerPricingService` · `PartnerPricingServiceV2` | D-11 · E-04 | Consolidated V1→V2 delegation; deal-aware getMarginForProductType |
| `COLAUpliftPrehook` · `COLAUpliftHandler` | SC-3384 · D-13 | Reprice-time + save-time COLA; line-override precedence; resolveTier |
| `AmendNetCarryPrehook` | SC-3501 | Carries prior asset net (×qty) onto amend lines (V24) |
| `CancelLineCreditPosthook` | SC-3441 | Negative cancel credit; self-resolves asset NET |
| `HardwareAttributePricingPrehook` | D-14 · Hardware | Hardware price = List×pGroup×userTier×(1−systemType%) |
| `RegionalServicesPricingPrehook` | SC-3374/3393 · regional | Country multiplier on LIST channel; null-mult guard |
| `AttributeVolumePricingPrehook` | SC-3390 · SC-3384 | Attribute/volume tier price; currency-aware tier lookup |
| `QLDescriptionGeneratorPrehook` | SC-3349 | Line description; Number_of_Units fallback |
| `RenewalMaintenancePricingService` | SC-3346 | Computes 3-component renewal-maint net |
| `MaintenanceOrderDecompositionService` | SC-3412 · SC-3346 | Order-side derived-maint net mirror at Q→O convert |
| `RenewalAssetQuantityHandler` | SC-3410 · SC-3412 | Normalizes auto-added New-Maint qty; No Change→Amend |
| `QuoteLineItemCurrencyCorrectionHandler` | SC-3384 (WS-E) | Re-points mis-currencied auto-add PBE to quote currency |
| `AbaCurrencyCorrectionService` | SC-3384 (ABA) | Per-unit USD→currency ABA localization |
| `OrderRepriceInvocable` | SC-3308 | Force-reprice before Activate |
| `OrderSubmissionValidator` | SC-3366 · SC-3291 | Bulk constant-SOQL order-submit validation |
| `QuoteToOrderFieldMapper` | SC-3339 · bill-ship | Q→O header mapping (Bill_To_Account__c=Quote.AccountId) |
| `PowerOrderSplittingService` | SC-3447 | 200-clone cap + partition/hardware gate + ARR apportion |
| `HardwareGroupController` | SC-3423 · SC-3468 | getHardwareById read-after-write; NULLS LAST |
| `RenewalForecastAmount` | SC-3500 | Σ(Asset MRR×12)×(1+COLA) renewal-opp Amount |
| `OrderValidationTriggerHandler` | manual-convert | Auto-activates linked Draft Contract before Order activation |
| `AssetRateOverrideConsolidationService` | D-16 | Bulkified assetize finalize (governor) |
| `AssetArrFromOrderItemHandler` | A-3 | Copies Order_Line_ARR__c→Asset.ARR__c |
| `OrderCommercialNetService` | assetize | Order commercial-net helper |
| `ExceptionLogger` · `PricingHookLogger` · `AppException` · `PricingException` | D-18 | Pricing-hook exception logging (observability) |
| `PricingCharacterizationTest` | refactor Wave-0 | Golden characterization test |

## Apex Classes — Wave-2 refactor calculators (behavior-preserving extractions, 0-delta)

`HardwarePricingCalculator` · `RegionalPricingCalculator` · `AttributeVolumeCalculator` · `CancelLineCreditCalculator` ·
`RenewalMaintenanceColaCalculator` · `ContributorPricingCalculator` · `DerivedMaintenanceClassifier` ·
`NewMaintenanceBandCalculator` · `NewMaintenanceInputResolver` · `PartnerNetResolutionCalculator` · `ContextTagReader` ·
`ListPriceStampCalculator` · `ContextUpdateNavigator` · `PartnerPricingGate` · `NewMaintenanceNetCalculator` ·
`SequentialDiscountCalculator` · `DerivedMaintenancePayloadBuilder` · `RenewalColaPayloadBuilder` ·
`PartnerPricingPayloadBuilder` · `PartnerParticipationResolver` · `PartnerMarginDispatcher` · `QLDescriptionCalculator`
— **all 🟢 LIVE** (ticket = pricing-refactor).

## Apex Triggers

| Component | Ticket | Reason |
|---|---|---|
| `QuoteLineItemTrigger` | SC-3441 · SC-3384 | Cancel-seed + currency-correction before COLA |
| `OrderValidationTrigger` | manual-convert | before insert/update — contract auto-activate |
| `AssetArrFromOrderItemTrigger` | A-3 | Fires ARR copy handler |

## Flows

| Component | Ticket | Reason |
|---|---|---|
| `Fortra_Quote_Reprice` | SC-3544 · SC-3346 | Passes QuoteId for Sales-Price stamp; wires renewal-maint service |
| `Fortra_Quote_to_Order_Conversion` | SC-3308/3447/3338 | Convert wizard: reprice gate + Power-split cap + bill/ship mapper |
| `Fortra_OrderItem_Set_Dates` | SC-3297 · SC-3411 | Billing From/To + null EndDate/PTC backstop (V6) |
| `Fortra_Order_Submission_Check` | SC-3291/3366/3411 | Order-submit validation screen (V14) |
| `Fortra_OrderItem_Set_Workday_Contract_Line_Type` | SC-3347/3368/3210 | Workday contract-line-type stamping |
| `Fortra_Create_Renewal_Quote` | SC-3346 | Renewal generation (+ Flip + Reprice subflows) |
| `Fortra_Quote_Required_Fields_Check` | SC-3338 | Required-fields review screen + quick action |
| `Fortra_Pricing_Exception_Logger` | D-18 | Subscriber flow → Exception_Log__c |
| `Fortra_Exception_Log_Purge` | D-18 | 90-day retention scheduled flow |
| `Fortra_Contract_Create_Renewal_Opportunity` | SC-3500 | +15min renewal-opp Amount path |
| `Fortra_Assetize_Order` | SC-3415 · SC-3419 | V14 assetization fault-visibility hardening |
| `Fortra_AssetAction_Stamp_Line_Description` | SC-3513 | AssetAction-Create Asset.Description stamp |
| `Stamp_Source_List_Price` | SC-3346 · SC-3372 | Stamps Source_List_Price__c from PBEDP contributor |
| `Stamp_Maintenance_Pricing_Inputs` | SC-3346 · SC-3372 | Stamps maintenance pricing inputs |

## Custom Fields

| Component | Ticket | Reason |
|---|---|---|
| `QuoteLineItem.CancelNetUnitPrice__c` | SC-3441 | Cancel-credit seed |
| `QuoteLineItem.Source_List_Price__c` | SC-3346 · SC-3372 | Derived-maint base for tier formula |
| `QuoteLineItem.Prior_Partner_Discount__c` · `Prior_Discretionary_Discount__c` | SC-3346 | Renewal 3-component carry-forward inputs |
| `QuoteLineItem.Final_Year_COLA_Calculated_Price__c` · `COLA_Outyear_Uplift_Percent__c` · `COLA_Solution_Category__c` | SC-3346 | COLA staging |
| `QuoteLineItem.Is_COLA_Overridden__c` | D-13 | Restored to SDD Formula(Checkbox) |
| `QuoteLineItem.ABA_Raw_Net__c` · `OrderItem.ABA_Raw_Net__c` | SC-3384 (ABA) | ABA provenance marker |
| `OrderItem.Pre_Partner_Price__c` · `Partner_Pricing_Source__c` | V16 · SC-3384 | Order-side partner fields (fixed Order reprice) |
| `OrderItem.CancelNetUnitPrice__c` | SC-3441 | Order-side cancel mirror |
| `OrderItem` COLA/maint set (`Base_Price__c`, `COLACalculatedPrice__c`, `COLA_Uplift_Percent__c`, `Source_List_Price__c`, `Prior_*_Discount__c`, `Fortra_Product_Type__c`, `Maintenance_Discount_Percent__c`) | SC-3346 | Order-side derived-maint / COLA staging |
| `Order.Quote_Type__c` · `QuoteTypeText__c` | SC-3346 | Order branch-gate fields |
| `Order.Maintenance_Date__c` · `New_Maintenance__c` · `Renewal_Maintenance_Quote__c` | SC-3346 | Maintenance order fields |
| `Hardware__c.Model_Number__c` · `iSeries_Model__c` | SC-3468 | Dual-write model number (+44-row backfill) |
| `Lead.Close_Reason__c` (dependent→independent) | SC-3171 | Reason selectable at Working |

## Objects · Platform Events · CMDT · LWC/FlexiPage

| Component | Ticket | Reason |
|---|---|---|
| `Pricing_Exception__e` (Platform Event) | D-18 | Pricing-hook degrade telemetry |
| `Exception_Log__c` (Custom Object, 9 fields) | D-18 | Durable exception store |
| `Order_Submit_Validation__mdt` (type + ~48 records) | SC-3291 | Config-driven order-submit validation |
| `Hardware_Attribute_Pricing__mdt` (type + ~16 records) | D-14 | Hardware pricing tables → admin-editable MDT |
| `COLA_Uplift_Rules__mdt` (records: BoKS consolidation 22→21) | SC-3346 | Consolidated BoKS COLA row |
| `hardwareGroupManager` (LWC) | SC-3468 · SC-3423 | Model-number display; getHardwareById |
| `Hardware_Record_Page` (FlexiPage) | SC-3468 | Model Number → iSeries dependent dropdown |
| `Quote_Record_Page` (FlexiPage) | SC-3338 | Required-field help text + action buttons |

## Permission Sets · Public Groups (DocGen / DocuSign access model — SC-3335)

| Component | Ticket | Reason |
|---|---|---|
| **Permission Set** `DocuSign_API_Access` (custom · 6 assigned) | SC-3335 · DocuSign | DocuSign API integration access |
| **Permission Set** `DocGenUser` (11 assigned) | SC-3335 · DocGen | DocGen runtime user access |
| **Permission Set** `DocGenDesigner` (12 assigned) | SC-3335 · DocGen | DocGen template designer access |
| **Permission Set** `DocumentBuilderUser` (13 assigned) | SC-3335 | Document Builder access |
| **Permission Set Licenses** `DocGenDesignerPsl` · `DocumentBuilderUserPsl` · `OmniStudioDesigner` | SC-3335 | License enablement for the DocGen / OmniStudio stack |
| **Public Group** `DocGen_Template_Users` (2 members) | SC-3335 · DocGen | Sharing group for DocGen templates — `ContentDocumentLink` share; load-bearing DocGen access model |

## Validation / Access · Config / Data

| Component | Ticket | Reason |
|---|---|---|
| `Lead.Prevent_Close_Reason_When_Not_Closed` (VR) | SC-3171 | Fixed OR-tautology; reason editable at Working/Closed |
| FLS updates (14 sets): `Pre_Partner_Price__c` / `Partner_Pricing_Source__c` / `CancelNetUnitPrice__c` | V16 · SC-3441 | Mirror QLI FLS to OrderItem |
| `ProcedurePlanOption 1FYWC0000002W3r4AE` → PPV2 | E-04 · D-11 | Re-pointed partner prehook V1→V2 |
| `ProductAttributeDefinition.IsPriceImpacting` (26 tiered PADs) | SC-3390 | Fix tiered click-twice |
| MTD PAD backfill (91 FEAT_ONLY products) | A-07 · SC-3346 | Add Maintenance-Type PAD for tier lookup |
| Order Bill/Ship header backfill (17,241 orders) | SC-3339 | Fill blank Bill/Ship Account/Address/Contact |
| PBEDP contributor config `182WC000000HEPxYAO` | SC-3372 | Cleared derived-price hard-error |

---
*Live status verified against FortraUAT 2026-07-09 via SOQL + Tooling API (ApexClass/ApexTrigger/FlowDefinitionView/
DecisionTable/FieldDefinition/EntityDefinition/ValidationRule). UAT-only — none deployed to FortraProd. Interactive
version: Artifact `76785399`.*
