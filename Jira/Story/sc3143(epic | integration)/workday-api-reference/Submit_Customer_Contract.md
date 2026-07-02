# Submit_Customer_Contract — Workday Revenue Management API (v46.1)

> **Operation:** `Submit_Customer_Contract`  
> **Purpose (per SC-3143):** Contract Data  
> **Source:** https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Submit_Customer_Contract.html  
> **Schema:** [WSDL](https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Revenue_Management.wsdl) · [XSD](https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Revenue_Management.xsd)  
> **API version:** v46.1 (Workday Community public docs)  
> **Extracted:** 2026-06-01 — deterministic parse of the source HTML (fields + nested per-field validation rules; lossless).  
> **Data types documented:** 152 (19 primary, 88 reference, 45 enumeration)

## Data type index

| # | Data type | Category |
|---|---|---|
| 1 | [Submit_Customer_Contract_Request](#submit_customer_contract_request) | primary |
| 2 | [Submit_Customer_Contract_Response](#submit_customer_contract_response) | primary |
| 3 | [Customer_ContractObject](#customer_contractobject) | reference |
| 4 | [Customer_ContractObjectID](#customer_contractobjectid) | reference |
| 5 | [Financials_Business_Process_Parameters](#financials_business_process_parameters) | primary |
| 6 | [Business_Process_Comment_Data](#business_process_comment_data) | primary |
| 7 | [WorkerObject](#workerobject) | reference |
| 8 | [WorkerObjectID](#workerobjectid) | reference |
| 9 | [Customer_Contract_Data](#customer_contract_data) | primary |
| 10 | [CompanyObject](#companyobject) | reference |
| 11 | [CompanyObjectID](#companyobjectid) | reference |
| 12 | [Sales_Item_Fair_Value_Price_ListObject](#sales_item_fair_value_price_listobject) | reference |
| 13 | [Sales_Item_Fair_Value_Price_ListObjectID](#sales_item_fair_value_price_listobjectid) | reference |
| 14 | [CurrencyObject](#currencyobject) | reference |
| 15 | [CurrencyObjectID](#currencyobjectid) | reference |
| 16 | [Address_ReferenceObject](#address_referenceobject) | reference |
| 17 | [Address_ReferenceObjectID](#address_referenceobjectid) | reference |
| 18 | [Bill-From_Address_Data](#bill-from_address_data) | primary |
| 19 | [Address_Information_Data](#address_information_data) | primary |
| 20 | [CountryObject](#countryobject) | reference |
| 21 | [CountryObjectID](#countryobjectid) | reference |
| 22 | [Address_Line_Information_Data](#address_line_information_data) | primary |
| 23 | [Country_CityObject](#country_cityobject) | reference |
| 24 | [Country_CityObjectID](#country_cityobjectid) | reference |
| 25 | [Submunicipality_Information_Data](#submunicipality_information_data) | primary |
| 26 | [Country_RegionObject](#country_regionobject) | reference |
| 27 | [Country_RegionObjectID](#country_regionobjectid) | reference |
| 28 | [Subregion_Information_Data](#subregion_information_data) | primary |
| 29 | [Communication_Method_Usage_Information_Data](#communication_method_usage_information_data) | primary |
| 30 | [Communication_Usage_Type_Data](#communication_usage_type_data) | primary |
| 31 | [Communication_Usage_TypeObject](#communication_usage_typeobject) | reference |
| 32 | [Communication_Usage_TypeObjectID](#communication_usage_typeobjectid) | reference |
| 33 | [Communication_Usage_BehaviorObject](#communication_usage_behaviorobject) | reference |
| 34 | [Communication_Usage_BehaviorObjectID](#communication_usage_behaviorobjectid) | reference |
| 35 | [Communication_Usage_Behavior_TenantedObject](#communication_usage_behavior_tenantedobject) | reference |
| 36 | [Communication_Usage_Behavior_TenantedObjectID](#communication_usage_behavior_tenantedobjectid) | reference |
| 37 | [Ship-From_Address_Data](#ship-from_address_data) | primary |
| 38 | [Billable_EntityObject](#billable_entityobject) | reference |
| 39 | [Billable_EntityObjectID](#billable_entityobjectid) | reference |
| 40 | [CustomerObject](#customerobject) | reference |
| 41 | [CustomerObjectID](#customerobjectid) | reference |
| 42 | [Customer_Contract_TypeObject](#customer_contract_typeobject) | reference |
| 43 | [Customer_Contract_TypeObjectID](#customer_contract_typeobjectid) | reference |
| 44 | [Payment_TermsObject](#payment_termsobject) | reference |
| 45 | [Payment_TermsObjectID](#payment_termsobjectid) | reference |
| 46 | [Payment_TypeObject](#payment_typeobject) | reference |
| 47 | [Payment_TypeObjectID](#payment_typeobjectid) | reference |
| 48 | [Tax_CodeObject](#tax_codeobject) | reference |
| 49 | [Tax_CodeObjectID](#tax_codeobjectid) | reference |
| 50 | [Customer_Contract_AbstractObject](#customer_contract_abstractobject) | reference |
| 51 | [Customer_Contract_AbstractObjectID](#customer_contract_abstractobjectid) | reference |
| 52 | [Customer_Contract_AlternateObject](#customer_contract_alternateobject) | reference |
| 53 | [Customer_Contract_AlternateObjectID](#customer_contract_alternateobjectid) | reference |
| 54 | [Audited_Accounting_WorktagObject](#audited_accounting_worktagobject) | reference |
| 55 | [Audited_Accounting_WorktagObjectID](#audited_accounting_worktagobjectid) | reference |
| 56 | [Contract_Discount_PremiumObject](#contract_discount_premiumobject) | reference |
| 57 | [Contract_Discount_PremiumObjectID](#contract_discount_premiumobjectid) | reference |
| 58 | [Billing_Schedule_TemplateObject](#billing_schedule_templateobject) | reference |
| 59 | [Billing_Schedule_TemplateObjectID](#billing_schedule_templateobjectid) | reference |
| 60 | [Customer_Contract_Line_Data](#customer_contract_line_data) | primary |
| 61 | [Receivable_Contract_Line_AbstractObject](#receivable_contract_line_abstractobject) | reference |
| 62 | [Receivable_Contract_Line_AbstractObjectID](#receivable_contract_line_abstractobjectid) | reference |
| 63 | [Customer_Contract_LineObject](#customer_contract_lineobject) | reference |
| 64 | [Customer_Contract_LineObjectID](#customer_contract_lineobjectid) | reference |
| 65 | [Item_DescriptorObject](#item_descriptorobject) | reference |
| 66 | [Item_DescriptorObjectID](#item_descriptorobjectid) | reference |
| 67 | [Commodity_CodeObject](#commodity_codeobject) | reference |
| 68 | [Commodity_CodeObjectID](#commodity_codeobjectid) | reference |
| 69 | [Accounting_CategoryObject](#accounting_categoryobject) | reference |
| 70 | [Accounting_CategoryObjectID](#accounting_categoryobjectid) | reference |
| 71 | [Contract_Line_TypeObject](#contract_line_typeobject) | reference |
| 72 | [Contract_Line_TypeObjectID](#contract_line_typeobjectid) | reference |
| 73 | [Project_AbstractObject](#project_abstractobject) | reference |
| 74 | [Project_AbstractObjectID](#project_abstractobjectid) | reference |
| 75 | [Project_Plan_PhaseObject](#project_plan_phaseobject) | reference |
| 76 | [Project_Plan_PhaseObjectID](#project_plan_phaseobjectid) | reference |
| 77 | [Project_Plan_TaskObject](#project_plan_taskobject) | reference |
| 78 | [Project_Plan_TaskObjectID](#project_plan_taskobjectid) | reference |
| 79 | [Project_Transaction_SourceObject](#project_transaction_sourceobject) | reference |
| 80 | [Project_Transaction_SourceObjectID](#project_transaction_sourceobjectid) | reference |
| 81 | [Contract_Rate_SheetObject](#contract_rate_sheetobject) | reference |
| 82 | [Contract_Rate_SheetObjectID](#contract_rate_sheetobjectid) | reference |
| 83 | [Usage_Billing_RateObject](#usage_billing_rateobject) | reference |
| 84 | [Usage_Billing_RateObjectID](#usage_billing_rateobjectid) | reference |
| 85 | [Contract_Line_FeeObject](#contract_line_feeobject) | reference |
| 86 | [Contract_Line_FeeObjectID](#contract_line_feeobjectid) | reference |
| 87 | [Unit_of_MeasureObject](#unit_of_measureobject) | reference |
| 88 | [Unit_of_MeasureObjectID](#unit_of_measureobjectid) | reference |
| 89 | [Contract_Discount_Premium_AbstractObject](#contract_discount_premium_abstractobject) | reference |
| 90 | [Contract_Discount_Premium_AbstractObjectID](#contract_discount_premium_abstractobjectid) | reference |
| 91 | [Revenue_Allocation_Calculation_BasisObject](#revenue_allocation_calculation_basisobject) | reference |
| 92 | [Revenue_Allocation_Calculation_BasisObjectID](#revenue_allocation_calculation_basisobjectid) | reference |
| 93 | [Revenue_TreatmentObject](#revenue_treatmentobject) | reference |
| 94 | [Revenue_TreatmentObjectID](#revenue_treatmentobjectid) | reference |
| 95 | [Revenue_Recognition_Schedule_TemplateObject](#revenue_recognition_schedule_templateobject) | reference |
| 96 | [Revenue_Recognition_Schedule_TemplateObjectID](#revenue_recognition_schedule_templateobjectid) | reference |
| 97 | [Tax_ApplicabilityObject](#tax_applicabilityobject) | reference |
| 98 | [Tax_ApplicabilityObjectID](#tax_applicabilityobjectid) | reference |
| 99 | [Document_StatusObject](#document_statusobject) | reference |
| 100 | [Document_StatusObjectID](#document_statusobjectid) | reference |
| 101 | [Financials_Attachment_with_Category__Workday-Owned__Data](#financials_attachment_with_category__workday-owned__data) | primary |
| 102 | [Financials_Attachment_with_Category__Workday-Owned__Detail_Data](#financials_attachment_with_category__workday-owned__detail_data) | primary |
| 103 | [Attachment_Category__Workday_Owned_Object](#attachment_category__workday_owned_object) | reference |
| 104 | [Attachment_Category__Workday_Owned_ObjectID](#attachment_category__workday_owned_objectid) | reference |
| 105 | [Application_Instance_Related_Exceptions_Data](#application_instance_related_exceptions_data) | primary |
| 106 | [Application_Instance_Exceptions_Data](#application_instance_exceptions_data) | primary |
| 107 | [Exception_Data](#exception_data) | primary |
| 108 | [Customer_ContractReferenceEnumeration](#customer_contractreferenceenumeration) | enumeration |
| 109 | [WorkerReferenceEnumeration](#workerreferenceenumeration) | enumeration |
| 110 | [CompanyReferenceEnumeration](#companyreferenceenumeration) | enumeration |
| 111 | [Sales_Item_Fair_Value_Price_ListReferenceEnumeration](#sales_item_fair_value_price_listreferenceenumeration) | enumeration |
| 112 | [CurrencyReferenceEnumeration](#currencyreferenceenumeration) | enumeration |
| 113 | [Address_ReferenceReferenceEnumeration](#address_referencereferenceenumeration) | enumeration |
| 114 | [CountryReferenceEnumeration](#countryreferenceenumeration) | enumeration |
| 115 | [Country_CityReferenceEnumeration](#country_cityreferenceenumeration) | enumeration |
| 116 | [Country_RegionReferenceEnumeration](#country_regionreferenceenumeration) | enumeration |
| 117 | [Communication_Usage_TypeReferenceEnumeration](#communication_usage_typereferenceenumeration) | enumeration |
| 118 | [Communication_Usage_BehaviorReferenceEnumeration](#communication_usage_behaviorreferenceenumeration) | enumeration |
| 119 | [Communication_Usage_Behavior_TenantedReferenceEnumeration](#communication_usage_behavior_tenantedreferenceenumeration) | enumeration |
| 120 | [Billable_EntityReferenceEnumeration](#billable_entityreferenceenumeration) | enumeration |
| 121 | [CustomerReferenceEnumeration](#customerreferenceenumeration) | enumeration |
| 122 | [Customer_Contract_TypeReferenceEnumeration](#customer_contract_typereferenceenumeration) | enumeration |
| 123 | [Payment_TermsReferenceEnumeration](#payment_termsreferenceenumeration) | enumeration |
| 124 | [Payment_TypeReferenceEnumeration](#payment_typereferenceenumeration) | enumeration |
| 125 | [Tax_CodeReferenceEnumeration](#tax_codereferenceenumeration) | enumeration |
| 126 | [Customer_Contract_AbstractReferenceEnumeration](#customer_contract_abstractreferenceenumeration) | enumeration |
| 127 | [Customer_Contract_AlternateReferenceEnumeration](#customer_contract_alternatereferenceenumeration) | enumeration |
| 128 | [Audited_Accounting_WorktagReferenceEnumeration](#audited_accounting_worktagreferenceenumeration) | enumeration |
| 129 | [Contract_Discount_PremiumReferenceEnumeration](#contract_discount_premiumreferenceenumeration) | enumeration |
| 130 | [RichText](#richtext) | enumeration |
| 131 | [Billing_Schedule_TemplateReferenceEnumeration](#billing_schedule_templatereferenceenumeration) | enumeration |
| 132 | [Receivable_Contract_Line_AbstractReferenceEnumeration](#receivable_contract_line_abstractreferenceenumeration) | enumeration |
| 133 | [Customer_Contract_LineReferenceEnumeration](#customer_contract_linereferenceenumeration) | enumeration |
| 134 | [Item_DescriptorReferenceEnumeration](#item_descriptorreferenceenumeration) | enumeration |
| 135 | [Commodity_CodeReferenceEnumeration](#commodity_codereferenceenumeration) | enumeration |
| 136 | [Accounting_CategoryReferenceEnumeration](#accounting_categoryreferenceenumeration) | enumeration |
| 137 | [Contract_Line_TypeReferenceEnumeration](#contract_line_typereferenceenumeration) | enumeration |
| 138 | [Project_AbstractReferenceEnumeration](#project_abstractreferenceenumeration) | enumeration |
| 139 | [Project_Plan_PhaseReferenceEnumeration](#project_plan_phasereferenceenumeration) | enumeration |
| 140 | [Project_Plan_TaskReferenceEnumeration](#project_plan_taskreferenceenumeration) | enumeration |
| 141 | [Project_Transaction_SourceReferenceEnumeration](#project_transaction_sourcereferenceenumeration) | enumeration |
| 142 | [Contract_Rate_SheetReferenceEnumeration](#contract_rate_sheetreferenceenumeration) | enumeration |
| 143 | [Usage_Billing_RateReferenceEnumeration](#usage_billing_ratereferenceenumeration) | enumeration |
| 144 | [Contract_Line_FeeReferenceEnumeration](#contract_line_feereferenceenumeration) | enumeration |
| 145 | [Unit_of_MeasureReferenceEnumeration](#unit_of_measurereferenceenumeration) | enumeration |
| 146 | [Contract_Discount_Premium_AbstractReferenceEnumeration](#contract_discount_premium_abstractreferenceenumeration) | enumeration |
| 147 | [Revenue_Allocation_Calculation_BasisReferenceEnumeration](#revenue_allocation_calculation_basisreferenceenumeration) | enumeration |
| 148 | [Revenue_TreatmentReferenceEnumeration](#revenue_treatmentreferenceenumeration) | enumeration |
| 149 | [Revenue_Recognition_Schedule_TemplateReferenceEnumeration](#revenue_recognition_schedule_templatereferenceenumeration) | enumeration |
| 150 | [Tax_ApplicabilityReferenceEnumeration](#tax_applicabilityreferenceenumeration) | enumeration |
| 151 | [Document_StatusReferenceEnumeration](#document_statusreferenceenumeration) | enumeration |
| 152 | [Attachment_Category__Workday_Owned_ReferenceEnumeration](#attachment_category__workday_owned_referenceenumeration) | enumeration |

---

## Submit_Customer_Contract_Request

*Element containing Customer Contract reference for update and all Customer Contract data items.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @version | string | [0..1] | Web Service version |  |
| @Add_Only | boolean | [0..1] | Add Only Flag. Indicates that the service is an add only, not an update. |  |
| Customer_Contract_Reference | Customer_ContractObject | [0..1] | Reference to an existing Customer Contract for update only purposes. |  |
| Business_Process_Parameters | Financials_Business_Process_Parameters | [0..1] | Business Process Parameters provide the ability to auto-submit to the business process. |  |
| Customer_Contract_Data | Customer_Contract_Data | [1..1] | Customer Contract Data | Please enter at least one Contract line. — Please enter at least one Contract line.<br>Currency entered is not listed as an Accepted Currency by Bill To Customer. — Currency entered is not listed as an Accepted Currency by Bill To Customer.<br>Currency entered is not listed as an Accepted Currency by Sold To Customer. — Currency entered is not listed as an Accepted Currency by Sold To Customer.<br>The Contract Amount and the Contract Line Amount must be equal to Submit Contract. — The Contract Amount and the Contract Line Amount must be equal to Submit Contract.<br>Effective Date is required for Contract. — Effective Date is required for Contract.<br>Only one worktag for each type is allowed for each document line. — Only one worktag for each type is allowed for each document line.<br>If "Related" Contract is entered, the related contract must have the same Company and Sold To Customer as the current contract. — If "Related" Contract is entered, the related contract must have the same Company and Sold To Customer as the current contract.<br>Bill to customer reference is for a customer that can be used as a basic worktag only. — Bill to customer reference is for a customer that can be used as a basic worktag only.<br>Customer reference is for a customer that can be used as a basic worktag only. — Customer reference is for a customer that can be used as a basic worktag only.<br>Can not have any combination of Project, Project Phase or Project Task worktags for the same line. — Can not have any combination of Project, Project Phase or Project Task worktags for the same line.<br>Customer Reference is for a Customer, not for a Sponsor. — Customer Reference is for a Customer, not for a Sponsor.<br>Customer Reference is for a Customer, not for a Sponsor. — Customer Reference is for a Customer, not for a Sponsor.<br>Revenue and billing amounts must be equal for each unique combination of company and balancing worktag. — Revenue and billing amounts must be equal for each unique combination of company and balancing worktag.<br>The sum of the Line Revenue Amount for all contract lines must be equal to zero if the Contract Type is designated as a linked contract on the Maintain Customer Contract Types task. — The sum of the Line Revenue Amount for all contract lines must be equal to zero if the Contract Type is designated as a linked contract on the Maintain Customer Contract Types task.<br>Select a contract that is not already linked. For any contract selected, the contract type must not be designed as a Linked Contract on the Maintain Customer Contract Type task.<br>Enter a Billing Schedule From Date that is earlier than the To Date. — Enter a Billing Schedule From Date that is earlier than the To Date.<br>You must enter a From Date when you use an Installment billing schedule template with Grouped Billing selected.<br>More than 1 contract line contains this Contract Line Number: [line_number]. Enter a unique Contract Line Number on each contract line.<br>Cannot create Alternate Contract if Original Contract is in Draft status.<br>Installment Type Billing Schedule Template is not valid if Original Customer Contract Supplied.<br>Transaction Type Billing Schedule Template is not valid if Original Customer Contract Supplied.<br>Alternate Customer Contract Number must match Original Customer Contract Number if supplied.<br>Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract. — Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract.<br>You cannot submit an Incremental Contract Amendment for a Draft Contract Amendment. Set the Submit Flag to Use Incremental Contract Amendment. — You cannot submit an Incremental Contract Amendment for a Draft Contract Amendment. Set the Submit Flag to Use Incremental Contract Amendment.<br>Enter a Billing Schedule From Date when you use a Transaction Billing Schedule Template with Billing Frequency and Group All Related Contract Lines selected. — Enter a Billing Schedule From Date when you use a Transaction Billing Schedule Template with Billing Frequency and Group All Related Contract Lines selected.<br>You must have a Fixed Amount - Revenue Only line type for bundle sales items: [items].<br>The Sold-To Customer is not valid for the selected company.<br>The Bill-To Customer is not valid for the selected company.<br>You can't specify a third party tax code in the transaction tax code reference. — You can't specify a third party tax code in the transaction tax code reference.<br>To create intercompany supplier invoice for this customer contract, verify that the supplier for company and currency is setup correctly. — To create intercompany supplier invoice for this customer contract, verify that the supplier for company and currency is setup correctly.<br>To create the customer contract, first specify a currency conversion rate between the contract header company currency and the contract header currency. — To create the customer contract, first specify a currency conversion rate between the contract header company currency and the contract header currency.<br>You must enter a To Date when you use an Installment billing schedule template with Grouped Billing and Use To Date selected.<br>Specify either a billing template or an installment/transaction billing schedule template - not both.<br>Specify a billing schedule template where the receivable contract type is Customer Contract and the billing template type is Billing Template.<br>The values in the Allocation Percent column must equal 100. — The values in the Allocation Percent column must equal 100.<br>The existing bill-from address is currently not in use for billing for the Customer Contract header company. You can send an updated bill-from address that has a billing usage for the Customer Contract header company. — The existing bill-from address is currently not in use for billing for the Customer Contract header company. You can send an updated bill-from address that has a billing usage for the Customer Contract header company.<br>The existing ship-from address is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled. — The existing ship-from address is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled.<br>The existing bill-from address is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled. — The existing bill-from address is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled.<br>The existing ship-from address is currently not in use for shipping for the Customer Contract header company. You can send an updated ship-from address that has a shipping usage for the Customer Contract header company. — The existing ship-from address is currently not in use for shipping for the Customer Contract header company. You can send an updated ship-from address that has a shipping usage for the Customer Contract header company.<br>The existing ship-from address at the customer contract line level is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled. — The existing ship-from address at the customer contract line level is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled. |

| col1 |
|---|
| This Customer Contract is Canceled and cannot be resubmitted. — This Customer Contract is Canceled and cannot be resubmitted.<br>The Web Service is set to Add Only; documents cannot be resubmitted. — The Web Service is set to Add Only; documents cannot be resubmitted.<br>This Customer Contract is not in Draft status and is unable to be resubmitted. — This Customer Contract is not in Draft status and is unable to be resubmitted. |

## Submit_Customer_Contract_Response

*Element containing Put Customer Invoice Response Data*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @version | string | [0..1] | Web Service version |  |
| Customer_Contract_Reference | Customer_ContractObject | [0..1] | Customer Contract Reference |  |
| Exceptions_Response_Data | Application_Instance_Related_Exceptions_Data | [0..*] | Element containing Exceptions Data |  |

## Customer_ContractObject

*Part of: [Customer_Contract_Data](#customer_contract_data), [Submit_Customer_Contract_Request](#submit_customer_contract_request), [Submit_Customer_Contract_Response](#submit_customer_contract_response)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Customer_ContractObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Customer_ContractObjectID

*Part of: [Customer_ContractObject](#customer_contractobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Customer_Contract_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Financials_Business_Process_Parameters

*Part of: [Submit_Customer_Contract_Request](#submit_customer_contract_request) — Contains data for business processing*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Auto_Complete | boolean | [0..1] | When set to "true" or "1", the business process is automatically processed. This means that all approvals will be automatically approved in the system, all reviews and to-do's will be automatically by-passed, and all notifications will be automatically suppressed. |  |
| Comment_Data | Business_Process_Comment_Data | [0..1] | Captures the Comment for the Business Process. |  |

## Business_Process_Comment_Data

*Part of: [Financials_Business_Process_Parameters](#financials_business_process_parameters) — Captures a comment for the Business Process.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Comment | string | [0..1] | Free form comment regarding the business process. | This Business Process has been configured to disable comment. Please remove the comment or change the setting in the Business Process Policy or tenant setup. |
| Worker_Reference | WorkerObject | [0..1] | Default the Person making the comment to the processing person if not submitted via the web service. |  |

## WorkerObject

*Part of: [Business_Process_Comment_Data](#business_process_comment_data), [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | WorkerObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## WorkerObjectID

*Part of: [WorkerObject](#workerobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Contingent_Worker_ID, Employee_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Customer_Contract_Data

*Part of: [Submit_Customer_Contract_Request](#submit_customer_contract_request) — Represent a complete Customer Contract Document.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Customer_Contract_ID | string | [0..1] | Customer Contract ID. This is the Customer Contract Unique Identifier. | Invalid ID value. |
| Submit | boolean | [0..1] | Submit for Approval is a boolean flag indicating if the transaction is to be submitted or saved in draft mode. If this flag is set, the transaction will be submitted, otherwise the transaction is saved in draft. |  |
| Locked_in_Workday | boolean | [0..1] | Set to True to disable editing and canceling the invoice inside the Workday application. Invoice can only be updated from the web service. |  |
| Company_Reference | CompanyObject | [1..1] | Company Reference |  |
| Multiple_Element_Revenue_Allocation | boolean | [0..1] | Multi Element Allocation flag to denote that revenue allocation is required | You cannot edit Multi-Element Revenue Allocation Flag during a contract change when schedules exist on the contract. — You cannot edit Multi-Element Revenue Allocation Flag during a contract change when schedules exist on the contract. |
| Revenue_Allocated | boolean | [0..1] | Revenue Allocated flag | Select the Multiple-Element Revenue Allocation flag, or clear the Revenue Allocation flag. |
| No_Allocation_Threshold | boolean | [0..1] | No Allocation Threshold is checked when the Upper and lower range percentage for a company is not set |  |
| Lower_Range_Percentage | decimal (10, 4) >0 | [0..1] | Lower Range Percentage for Company |  |
| Upper_Range_Percentage | decimal (10, 4) >0 | [0..1] | Upper Range Percentage for Company |  |
| Standalone_Selling_Price__FV__List_Reference | Sales_Item_Fair_Value_Price_ListObject | [0..1] | Sales Item Fair Value Price List Reference |  |
| Currency_Reference | CurrencyObject | [0..1] | This is the reference id of currency of the transaction If no currency is specified, Workday will first look to see if the payer/payee has a preferred currency and if not, currency will be populated with the company base currency. If the company base currency is not allowed currency for payer/payee then transaction will not be able to be submitted for approval. | Currency Conversion Rates between currency and company's default currency are not defined. — Currency Conversion Rates between currency and company's default currency are not defined.<br>Currency Conversion Rates between currency and company's default currency are not defined. |
| Bill-From_Address_Reference | Address_ReferenceObject | [0..1] | Bill-From Address Reference for the Bill-From Address on the Customer Contract Header. | To specify the bill-from address for the Customer Contract header company, first specify the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company.<br>Specify a bill-from address that is currently in use for billing for the Customer Contract header company. |
| Bill-From_Address_Data | Bill-From_Address_Data | [0..*] | Address information data for bill-from address on invoice header |  |
| Ship-From_Address_Reference | Address_ReferenceObject | [0..1] | Ship-From Address Reference for the Ship-From Address on the Customer Contract Header. | To specify the Ship-from address for the Customer Contract header company, first specify the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company.<br>Specify a Ship-from address that is currently in use for shipping for the Customer Contract header company. |
| Ship-From_Address_Data | Ship-From_Address_Data | [0..*] | Address information data for ship-from address on invoice header |  |
| Sold_To_Customer_Reference | Billable_EntityObject | [1..1] | Sold To Customer Reference | Company represented by Customer cannot match the transaction Company. |
| Ship_To_Customer_Reference | CustomerObject | [0..1] | This is the Ship To Connection on the contract header that the lines will default from. | Enter a Ship-To Customer that is part of the Customer's Connection Map.<br>You cannot edit Ship-To Customer during a contract change when schedules exist on the contract. — You cannot edit Ship-To Customer during a contract change when schedules exist on the contract. |
| Ship_To_Address_Reference | Address_ReferenceObject | [0..1] | The ship to address reference on the contract header. If this field is blank, it will take the default address from the header ship to customer. | Enter a Ship-To Customer first before entering a Ship-To Address Reference.<br>The Ship-To Address you entered is not valid for this Ship-To Customer.<br>If you did not enter a Ship-To Customer, Workday chose the default for this Sold-To Customer for you, and this Ship-To Address is not valid for that customer. |
| Ship_To_Address_Data | Address_Information_Data | [0..*] | Address information | Postal Code is not a valid address component for certain countries. — Postal Code is not a valid address component for certain countries.<br>Municipality is not a valid address component for certain countries . — Municipality is not a valid address component for certain countries .<br>Region Name must be valid for the specified Country. — Region Name must be valid for the specified Country.<br>Usage Type and Use For combination must be valid for Address. — Usage Type and Use For combination must be valid for Address.<br>Second Address Line is not a valid address component for certain countries. — Second Address Line is not a valid address component for certain countries.<br>Third Address Line is not a valid address component for certain countries. — Third Address Line is not a valid address component for certain countries.<br>Fourth Address Line is not a valid address component for certain countries. — Fourth Address Line is not a valid address component for certain countries.<br>A maximum of four Submunicipalities are allowed in an address. — A maximum of four Submunicipalities are allowed in an address.<br>A maximum of four Subregions are allowed in an address. — A maximum of four Subregions are allowed in an address.<br>A maximum of four Address Lines are allowed in an address. — A maximum of four Address Lines are allowed in an address.<br>Home addresses which are not additionally used as work addresses cannot be marked as public. — Home addresses which are not additionally used as work addresses cannot be marked as public.<br>[postal code] is not a valid postal code for [region] — Postal Code must be valid for the Region.<br>Address Line 1 is not valid for this Country. — Address Line 1 is not valid for this Country.<br>Address Line 2 not Valid for this Country. — Address Line 2 not Valid for this Country.<br>Address Line 3 is not Valid for this Country. — Address Line 3 is not Valid for this Country.<br>Address Line 4 is not Valid for this Country. — Address Line 4 is not Valid for this Country.<br>Address Line 5 is not Valid for this Country. — Address Line 5 is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 7 is not Valid for this Country. — Address Line 7 is not Valid for this Country.<br>Address Line 8 is not Valid for this Country. — Address Line 8 is not Valid for this Country.<br>Address Line 9 is not Valid for this Country. — Address Line 9 is not Valid for this Country.<br>You cannot specify the same usage type more than once for an address. — You cannot specify the same usage type more than once for an address.<br>Address Line 1 - Local is not valid for this Country. — Address Line 1 - Local is not valid for this Country.<br>Municipality - Local is not a valid address component for certain countries . — Municipality - Local is not a valid address component for certain countries .<br>Address Line 2 - Local is not valid for this Country. — Address Line 2 - Local is not valid for this Country.<br>Address Line 3 - Local is not Valid for this Country. — Address Line 3 - Local is not Valid for this Country.<br>Address Line 9 - Local is not Valid for this Country. — Address Line 9 - Local is not Valid for this Country.<br>Address Line 8 - Local is not Valid for this Country. — Address Line 8 - Local is not Valid for this Country.<br>Address Line 7 - Local is not Valid for this Country. — Address Line 7 - Local is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 5 - Local is not Valid for this Country. — Address Line 5 - Local is not Valid for this Country.<br>Address Line 4 - Local is not Valid for this Country. — Address Line 4 - Local is not Valid for this Country.<br>City Subdivision 1 - Local is not a valid address component for certain countries. — City Subdivision 1 - Local is not a valid address component for certain countries.<br>City Subdivision 2 - Local is not a valid address component for certain countries. — City Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 1 - Local is not a valid address component for certain countries. — Region Subdivision 1 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 - Local is not a valid address component for certain countries. — Region Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 is not a valid address component for certain countries. — Region Subdivision 2 is not a valid address component for certain countries.<br>City Subdivision 2 is not a valid address component for certain countries. — City Subdivision 2 is not a valid address component for certain countries.<br>If one local script address field is submitted, all required local script address fields must be submitted. — If one local script address field is submitted, all required local script address fields must be submitted.<br>Address Reference is required when deleting an address — Address Reference is required when deleting an address<br>Usage Data is required unless address is being deleted — Usage Data is required unless address is being deleted<br>Country Reference is required unless address is being deleted — Country Reference is required unless address is being deleted<br>Address deletion is not supported in this web service request — Address deletion is not supported in this web service request<br>If one western script field is submitted, all required western script address fields must be submitted. — If one western script field is submitted, all required western script address fields must be submitted.<br>Use a unique Address Reference ID for each address. [ID] is already used on another address. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>You can only update addresses that belong to this customer.<br>You can't use an existing address for a new customer.<br>You can't use an existing address for a new customer request.<br>You can't use an existing address for a new prospect.<br>You can only update addresses that belong to this customer request.<br>You can only update addresses that belong to this prospect.<br>Enter a postal code in the valid format: [PostalCodeValidationMessage]<br>One or more addresses are missing a Country City reference. This field is required because the City Prompt localization is active for: [countryref].<br>Enter a Country City reference that is valid for: [countryref]. You entered this Country City reference: [countrycityref].<br>Only Address reference belonging to the Customer tied to the Customer Contact can be shared by the Customer Contact<br>International Assignment is only valid for Non-Primary Home Addresses<br>Number of Days cannot be greater than 7. — Number of Days cannot be greater than 7.<br>Number of Days is not allowed for the country specified. — Number of Days is not allowed for the country specified.<br>You must enter a Country City reference instead of a text element because the City Prompt localization is active for: [countryref]. You entered this text element: [cityattrib] [citylocalattrib].<br>You entered this Country City reference: [countrycityref]. To use this Country City reference, you must activate the City Prompt localization for: [countryref].<br>Perform either one of these actions:<br>Activate the City Prompt localization.<br>Enter a municipality instead of a Country City reference.<br>Address "[ID]" is already in use by another address (possibly on another contactable). Please choose a different Address ID. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>Second Submunicipality is not a valid address component for certain countries. — Second Submunicipality is not a valid address component for certain countries.<br>Second Subregion is not a valid address component for certain countries. — Second Subregion is not a valid address component for certain countries.<br>Subregion is not a valid address component for certain countries. — Subregion is not a valid address component for certain countries.<br>Submunicipality is not a valid address component for certain countries. — Submunicipality is not a valid address component for certain countries.<br>Specify the required missing address components for [proposedCountry]: [missingAddressComponents]<br>Specify an Address Reference that isn't already in use by another address. — Specify an Address Reference that isn't already in use by another address.<br>Existing addresses can't be future dated. Select an effective date that is on or before today, or create a new address with a future date.<br>Address [AddressReference] is not accessible to the processing user. — The Address Reference provided is not accessible to the processing user.<br>Ensure that the effective date specified in the Address Information Data matches the effective date specified in the [Add or Edit]:[Dependent Effective Date]. Alternatively, remove the effective date in the Address Information Data and reprocess the request. |
| Customer_Contract_Type_Reference | Customer_Contract_TypeObject | [1..1] | Customer Contract Type Reference | You cannot edit Contract Type during a contract change when schedules exist on the contract. — You cannot edit Contract Type during a contract change when schedules exist on the contract.<br>You can't change the Contract Type to or from a Linked type. |
| Contract_Name | string | [0..1] | Customer Contract Name |  |
| Version | decimal (12, 0) | [0..1] | Customer Contract Version |  |
| Customer_Contract_Number | string | [0..1] | Customer Contract Number |  |
| Contract_Description | string | [0..1] | Customer Contract Description |  |
| Bill_To_Customer_Reference | Billable_EntityObject | [0..1] | Bill to Customer Reference for Customer Contract |  |
| Payment_Terms_Reference | Payment_TermsObject | [0..1] | Payment Terms Reference for Customer Contract |  |
| Payment_Type_Reference | Payment_TypeObject | [0..1] | Payment Type Reference for Customer Contract |  |
| Default_Tax_Code_Reference | Tax_CodeObject | [0..1] | Tax Code Reference for Customer Contract | Enter a Default Tax Code that doesn’t include withholding tax rates. |
| Related_Customer_Contract_Reference | Customer_ContractObject | [0..1] | For information purposes only, a contract "related" to the current contract. Needs to have same company and customer of current contract. | You can't reference a Related Customer Contract that you don't have access to. — You can't reference a Related Customer Contract that you don't have access to. |
| Linked_Customer_Contracts_Reference | Customer_Contract_AbstractObject | [0..*] | Other customer contracts that are linked to this contract. | If the Contract Type is not identified as a Linked Contract on the Maintain Customer Contract Types task, the Linked Contracts field should be empty.<br>You can't reference a Linked Customer Contract that you don't have access to.<br>Select an active contract. The contract status for this Linked or Master Contract is cancelled. |
| Master_Customer_Contract_Reference | Customer_ContractObject | [0..1] | The master customer contract this contract could be linked to. | If the Contract Type is identified as a Linked Contract on the Maintain Customer Contract Types task, the Master Contract field should be empty.<br>Select a Master Contract with a contract type that has been designated as a Linked Contract on the Maintain Customer Contract Type task.<br>Select an active contract. The contract status for this Linked or Master Contract is cancelled.<br>You can't change the Master Customer Contract value. |
| Original_Customer_Contract_Reference | Customer_ContractObject | [0..1] | Original Customer Contract. The Customer Contract used as source for this Alternate Customer Contract. |  |
| Alternate_Customer_Contract_Reference | Customer_Contract_AlternateObject | [0..1] | Alternate Customer Contract. The Alternate Customer Contract associated to this Customer Contract. |  |
| On_Hold | boolean | [0..1] | Customer Contract is On Hold |  |
| Customer_Contract_Effective_Date | date | [0..1] | Customer Contract Effective Date | You cannot edit Effective Date during a contract change when schedules exist on the contract. — You cannot edit Effective Date during a contract change when schedules exist on the contract. |
| Contract_Signed_Date | date | [0..1] | Contract Signed Date |  |
| PO_Number | string | [0..1] | Purchase Order for Customer Contract |  |
| Salesperson_Reference | WorkerObject | [0..1] | Reference to existing Worker that represents the salesperson for this Customer Contract. |  |
| Default_Worktags_Reference | Audited_Accounting_WorktagObject | [0..*] | Customer Contract Default Worktags Reference | [not allowed worktag types on Customer Contract WWS] — The Worktags provided are not valid for this transaction<br>[list of worktag types] not valid for this transaction. — The Worktags provided are not valid for this transaction<br>The [type] is/are not available for use with the company/s: [partitionable] [company]<br>[worktag value] is not permitted as an allowed value for worktag type: [worktag type], because it is inactive.<br>[invalid worktag value message]<br>The intercompany affiliate worktag [worktag] is invalid for header company [header company]. Enter a valid header company and intercompany affiliate worktag combination. |
| Current_Contract_Amount | decimal (18, 3) | [0..1] | Current Contract Amount | You cannot edit Contract Amount during a contract change when schedules exist on the contract. — You cannot edit Contract Amount during a contract change when schedules exist on the contract. |
| Discounts_and_Premiums_Applied_Reference | Contract_Discount_PremiumObject | [0..*] | Customer Contract Discounts And Premiums | Enter an active discount or premium within the contract date range on the header. |
| Contract_Notes | RichText | [0..1] | Customer Contract Notes |  |
| Billing_Notes | RichText | [0..1] | Customer Contract Billing Notes |  |
| Transaction_Billing_Schedule_Template_Reference | Billing_Schedule_TemplateObject | [0..1] | Billing Schedule Template of Type Transaction | You cannot edit Transaction Billing Schedule Template during a contract change when schedules exist on the contract. — You cannot edit Transaction Billing Schedule Template during a contract change when schedules exist on the contract.<br>You cannot change Transaction Billing Schedule Template during Incremental Contract Amendment when schedules exist. |
| Installment_Billing_Schedule_Template_Reference | Billing_Schedule_TemplateObject | [0..1] | Billing Schedule Template of Type Installment. | You cannot edit Installment Billing Schedule Template during a contract change when schedules exist on the contract. — You cannot edit Installment Billing Schedule Template during a contract change when schedules exist on the contract.<br>You cannot change Installment Billing Schedule Template during Incremental Contract Amendment when schedules exist. — You cannot change Installment Billing Schedule Template during Incremental Contract Amendment when schedules exist. |
| Billing_Template_Reference | Billing_Schedule_TemplateObject | [0..1] | The billing template for the contract. |  |
| Billing_Schedule_From_Date | date | [0..1] | Billing Schedule Template From Date. | You cannot edit Billing From date during a contract change when schedules exist on the contract. — You cannot edit Billing From date during a contract change when schedules exist on the contract. |
| Billing_Schedule_To_Date | date | [0..1] | Billing Schedule Template To Date. | You cannot edit Billing To Date during a contract change when schedules exist on the contract. — You cannot edit Billing To Date during a contract change when schedules exist on the contract. |
| Customer_Contract_Line_Replacement_Data | Customer_Contract_Line_Data | [0..*] | Customer Contract Line Data Element | Only one worktag for each type is allowed for each document line. — Only one worktag for each type is allowed for each document line.<br>Please specify an Item or a Spend Category. — Please specify an Item or a Spend Category.<br>If Line is Renewable, a line End Date must be entered. — If Line is Renewable, a line End Date must be entered.<br>To Date must be greater than From Date. — To Date must be greater than From Date.<br>If both First and Last Installments are entered, number of installments must be greater than or equal to 3. — If both First and Last Installments are entered, number of installments must be greater than or equal to 3.<br>If either First or Last Installment is entered, number of installments must be greater than or equal to 2. — If either First or Last Installment is entered, number of installments must be greater than or equal to 2.<br>If either First or Last Installment is entered, number of installments must be greater than or equal to 2. — If either First or Last Installment is entered, number of installments must be greater than or equal to 2.<br>Contract Line Amount is not valid for Prepaid or Revenue Only Contract Lines — Contract Line Amount is not valid for Prepaid or Revenue Only Contract Lines<br>Billable Project is required for a Project Contract Line Type. — Billable Project is required for a Project Contract Line Type.<br>Renewable is invalid for Prepaid or Revenue Only contract lines. — Renewable is invalid for Prepaid or Revenue Only contract lines.<br>New Business is invalid for Prepaid or Revenue Only contract lines. — New Business is invalid for Prepaid or Revenue Only contract lines.<br>Revenue Override Amount must be empty for contract lines that are Billing Only or Variable Amount (Non-Project) — Revenue Override Amount must be empty for contract lines that are Billing Only or Variable Amount (Non-Project)<br>Project Transaction Source cannot be entered for non Project based Customer Contract Lines. — Project Transaction Source cannot be entered for non Project based Customer Contract Lines.<br>Only a Billable Project may be entered. — Only a Billable Project may be entered.<br>Cannot enter Project Worktag on Contract Line with Billable Project entered. — Cannot enter Project Worktag on Contract Line with Billable Project entered.<br>Cannot have an Employee Worktag along with a Contingent Worker Worktag for the same line. — Cannot have an Employee Worktag along with a Contingent Worker Worktag for the same line.<br>Can not use a Sales Item that is a basic worktag only as the sales item for the transaction. — Can not use a Sales Item that is a basic worktag only as the sales item for the transaction.<br>Sales Item is inactive. — Sales Item is inactive.<br>Sales Item Reference does not refer to a valid Sales Item. — Sales Item Reference does not refer to a valid Sales Item.<br>Project reference is for a project that can be used as a basic worktag only. — Project reference is for a project that can be used as a basic worktag only.<br>Can not have any combination of Project, Project Phase or Project Task worktags for the same line. — Can not have any combination of Project, Project Phase or Project Task worktags for the same line.<br>Quantity 2 can only be entered if the primary Quantity is not zero. — Quantity 2 can only be entered if the primary Quantity is not zero.<br>Unit of Measure 2 cannot be provided unless both primary Quantity and Unit of Measure are provided. — Unit of Measure 2 cannot be provided unless both primary Quantity and Unit of Measure are provided.<br>Quantity 2 is required if Unit of Measure 2 is provided. — Quantity 2 is required if Unit of Measure 2 is provided.<br>Contract Line Data contains duplicate Receivable Contract Line Reference ID's. — Contract Line Data contains duplicate Receivable Contract Line Reference ID's.<br>FV Extended Amount cannot be entered for contract line types of: Prepaid or Revenue Only — FV Extended Amount cannot be entered for contract line types of: Prepaid or Revenue Only<br>Contract Line Billing Schedule From Date must be before To Date. — Enter a Billing Schedule From Date that is earlier than the To Date.<br>Revenue override amount is invalid when contract line type is Variable Amount - Non Project because it is the billed amount that determines revenue amount for this type of contract line. — Revenue override amount is invalid when contract line type is Variable Amount - Non Project because it is the billed amount that determines revenue amount for this type of contract line.<br>For sales items that Require Fulfillment, you must enter a Line Type of Fixed Amount, Subscription, or Variable Amount – Non Project. — For sales items that Require Fulfillment, you must enter a Line Type of Fixed Amount, Subscription, or Variable Amount – Non Project.<br>Either Percentage Allocation or Revenue Override Amount can be supplied but not both. — Either Percentage Allocation or Revenue Override Amount can be supplied but not both.<br>You can't enter a value in the Quantity 2 field on a contract line where the sales item requires fulfillment. — You can't enter a value in the Quantity 2 field on a contract line where the sales item requires fulfillment.<br>Sales Item Bundle: [bundle] can't contain child items with different currencies.<br>Sales Item Bundle: [bundle] can't contain child items that are Inactive.<br>The contract lines use conflicting Percent Complete methods. All Revenue Recognition Schedule Templates must use the same Percent Complete method for contract lines containing the same Project ([project]), Transaction Source ([transaction source]), and overlapping dates.<br>The Revenue Recognition Schedule Template using the [pcm] Percent Complete method on this contract line is invalid. A contract line using the same project, transaction source, and overlapping start and end dates and assigned to a Revenue Recogntion Schedule using the [pcm2] Percent Complete Method already exists. All Percent Complete Revenue Recognition Schedule Templates for these contract lines must use the [pcm2] Percent Complete Method.<br>Referenced Original Contract Line: [original line] is not child of Original Contract [original contract]<br>Tax applicability is required when tax code has a value. — Tax applicability is required when tax code has a value.<br>You can't update the Alternate Customer Contract Line because the Original Contract Line Status is either Canceled or Terminated for: [line].<br>Clear the Zero Revenue option for line types that don't allow for revenue override. — Clear the Zero Revenue option for line types that don't allow for revenue override.<br>You can’t select the Zero Revenue option when there is an Override Amount. — You can’t select the Zero Revenue option when there is an Override Amount.<br>You must change the contract rate sheet type to match the project type. — You must change the contract rate sheet type to match the project type.<br>You can only select Billable Transaction Tax when the line type is Project Time and Expense, and the project transaction source is either Expense or Supplier Invoice.<br>You can't select the Billable Transaction Tax on the contract line, when the Only Include Non-Recoverable Tax on Billable Transactions check box isn't selected at the tenant level.<br>Unit Of Measure 2 can only be entered if the Contract Line Type is Fixed Amount or Subscription. — Unit Of Measure 2 can only be entered if the Contract Line Type is Fixed Amount or Subscription.<br>Quantity 2 can only be entered if the Contract Line Type is Fixed Amount or Subscription. — Quantity 2 can only be entered if the Contract Line Type is Fixed Amount or Subscription.<br>Contract Line Billing Schedule From Date must be before To Date. — Enter a Billing Schedule From Date that is earlier than the To Date.<br>When you have the Standard Rate Sheet selected, you can't use a contract rate sheet that contains a Project Billing Rate Sheet, a Time Definition, an Adjustment Percent, or Rate Category Members. Either clear the Standard Rate Sheet or select a different contract rate sheet.<br>You can't add Intercompany line type to this contract.<br>Revenue Category must match the Revenue Category for the Sales Item if that category is active.<br>Revenue Category must match the Revenue Category of the Contract Line.<br>Cannot use inactive Revenue Category<br>The following fields are invalid on a Recurring line on a Grid contract: Number of Installments, Regular Installment Amount, First Installment Amount, and Last Installment Amount. — The following fields are invalid on a Recurring line on a Grid contract: Number of Installments, Regular Installment Amount, First Installment Amount, and Last Installment Amount.<br>You can't specify a third party tax code in the transaction tax code reference. — You can't specify a third party tax code in the transaction tax code reference.<br>Unit Price cannot be entered for contract line types of: Prepaid, and Revenue Only — Unit Price cannot be entered for contract line types of: Prepaid, and Revenue Only<br>You can't enter a Unit of Measure for contract line types of prepaid, revenue only, or project with a nontime project transaction source. — You can't enter a Unit of Measure for contract line types of prepaid, revenue only, or project with a nontime project transaction source.<br>You can not add a contract rate sheet or use a standard rate sheet with daily rates for fixed fee or value-based contact lines.<br>You can only enter one Project Transaction Source for fixed fee or value-based contract lines with a contract rate sheet or standard rate sheet<br>You can't add a contract rate sheet or use a standard rate sheet on the contract line because a contract line with a contract rate sheet or using a standard rate sheet exists with the same project, source, and date combination on this contract:[text]<br>Specify a project for the billable project instead of a project event.<br>Specify a revenue treatment of Deferred for prepaid customer contract lines.<br>You must enable Deferred Revenue for prepaid customer contract lines.<br>Specify a date range less than 100 years for the Billing Schedule From Date and Billing Schedule To Date.<br>Specify a date range less than 100 years for the Customer Contract Line Start Date and Customer Contract Line End Date.<br>Billable Project is not valid for a non-project Contract Line type. — Billable Project is not valid for a non-project Contract Line type.<br>To specify a Phase Reference on a contract line, ensure the contract line has a line type of Project Time and Expense, Fixed Fee Project, or Value-Based Project.<br>To specify a Task Reference on a contract line, ensure the contract line has a line type of Project Time and Expense, Fixed Fee Project, or Value-Based Project.<br>Specify a different combination. The billable project, task, project transaction source, and date combination already exists for another project time and expense line on this contract. [contract]<br>Specify a different combination. The billable project, project transaction source, and date combination already exists for another project time and expense line on this contract. [contract]<br>Specify a different combination. The billable project, phase, project transaction source, and date combination already exists for another project time and expense line on this contract. [contract]<br>When you specify a project plan task on a contract line, you can't specify the task as a worktag.<br>When you specify a project plan phase on a contract line, you can't specify the phase as a worktag.<br>You can't specify a project plan phase or project plan task for a contract line that specifies a daily rate sheet.<br>Enter a Billing Schedule From Date when you use a Transaction Billing Schedule Template with Billing Frequency and Separate Billing Schedule selected. — Enter a Billing Schedule From Date when you use a Transaction Billing Schedule Template with Billing Frequency and Separate Billing Schedule selected.<br>If you select the Number of installments option, Billing Schedule From Date is required. — If you select the Number of installments option, Billing Schedule From Date is required.<br>Specify a billing schedule template where the receivable contract type is Customer Contract and the billing template type is Billing Template.<br>You can’t specify a billing template when the contract line type is Fixed Amount - Revenue Only.<br>Specify a Billing To Date on the contract or contract line. This field is required for all contract line types except Project Time and Expense and Usage when you use a billing template that generates installments with To Date.<br>If you select Use To Date, both Billing Schedule From Date and Billing Schedule To Date are required. — If you select Use To Date, both Billing Schedule From Date and Billing Schedule To Date are required.<br>Specify a Billing From Date on the contract or contract line. This field is required for all contract line types except Project Time and Expense and Usage when you use a billing template.<br>You can't enter a Quantity for contract line types of prepaid, revenue only, or project with a nontime project transaction source. — You can't enter a Quantity for contract line types of prepaid, revenue only, or project with a nontime project transaction source.<br>When the contract line type is Prepaid or Fixed Amount - Revenue Only for nonbundle lines, you must clear the FV Unit Price field. — When the contract line type is Prepaid or Fixed Amount - Revenue Only for nonbundle lines, you must clear the FV Unit Price field.<br>To set the Is Quantity per Bundle Zero field to true, ensure that the bundled customer contract lines have a line type of Fixed Amount - Revenue Only. — To set the Is Quantity per Bundle Zero field to true, ensure that the bundled customer contract lines have a line type of Fixed Amount - Revenue Only.<br>You must enter a Contract Line Amount when the Line Type is Fixed Fee Project, the line isn't canceled, and there isn't a Revenue Override Amount. — You must enter a Contract Line Amount when the Line Type is Fixed Fee Project, the line isn't canceled, and there isn't a Revenue Override Amount.<br>To use a revenue recognition schedule template with Percent Complete on the customer contract line, ensure that the contract line amount is not negative.<br>To specify a revenue recognition template with contract lines of type Project Time and Expense that have multiple project plan phases or project plan tasks, the revenue recognition method must be Transaction.<br>Specify a different combination. The specified combination of billable project, phase, and task conflicts with another fixed-fee line on this contract. [contract]<br>Specify a different combination. The specified combination of billable project and phase conflicts with another fixed-fee line on this contract. [contract]<br>Ensure that the Project Plan Phase or Project Plan Task you specify in the Worktags field is associated with the billable Project specified on the contract line.<br>You can't specify a third party tax code in the withholding tax code reference. Specify a non third party withholding tax code. — You can't specify a third party tax code in the withholding tax code reference. Specify a non third party withholding tax code.<br>Specify a task worktag that corresponds to the phases specified on the contract line.<br>Enter a positive contract line amount. When the revenue recognition schedule uses the Percent Complete recognition method, the fixed-fee contract line amounts must be positive. — Enter a positive contract line amount. When the revenue recognition schedule uses the Percent Complete recognition method, the fixed-fee contract line amounts must be positive.<br>Remove the Billing Only Customer Contract Line Reference that refers to a contract line not present in this request. — Remove the Billing Only Customer Contract Line Reference that refers to a contract line not present in this request.<br>Remove the Bundled Revenue Only Contract Line Reference that refers to a contract line not present in this request. — Remove the Bundled Revenue Only Contract Line Reference that refers to a contract line not present in this request.<br>The Billable Project field doesn't apply to contract lines with the Advanced Usage field set to true. — The Billable Project field doesn't apply to contract lines with the Advanced Usage field set to true.<br>The Advanced Usage field only applies when Subscription Management is enabled. — The Advanced Usage field only applies when Subscription Management is enabled.<br>Specify a value for the Contract Line Start Date field if the Advanced Usage field is set to true. — Specify a value for the Contract Line Start Date field if the Advanced Usage field is set to true.<br>Specify a value for the Sales Item field if the Advanced Usage field is set to true. — Specify a value for the Sales Item field if the Advanced Usage field is set to true.<br>Specify a Usage Billing Rate effective on or before the contract line Start Date if the Advanced Usage field is set to true. — Specify a Usage Billing Rate effective on or before the contract line Start Date if the Advanced Usage field is set to true.<br>Specify a value for the Contract Line End Date field if the Advanced Usage field is set to true. — Specify a value for the Contract Line End Date field if the Advanced Usage field is set to true.<br>The Advanced Usage field only applies to usage-based contract lines. — The Advanced Usage field only applies to usage-based contract lines.<br>You can't set the Advanced Usage field to true for contract lines on alternate contracts. — You can't set the Advanced Usage field to true for contract lines on alternate contracts.<br>A Project Transaction Source of Time, Expense, Supplier Invoice, or Misc. Expense is required for a Project Time and Expense contract line (exactly 1 source). — A Project Transaction Source of Time, Expense, Supplier Invoice, or Misc. Expense is required for a Project Time and Expense contract line (exactly 1 source).<br>For all contract lines with Advanced Usage set to true, ensure that you use only sales items with charge models. — For all contract lines with Advanced Usage set to true, ensure that you use only sales items with charge models.<br>When you use a revenue recognition schedule template with a revenue recognition method other than Transaction or Percent Complete, you need to specify the customer contract line start date.<br>Specify an active tax applicability.<br>Specify contract line start and end dates within the fiscal years defined for the contract line company when using a revenue recognition template with the Spread Even or Number of Days revenue recognition methods. |
| Customer_Contract_Attachment_Data | Financials_Attachment_with_Category__Workday-Owned__Data | [0..1] | A wrapper element that contains data for Financial Attachments | If Delete is set to true in Attachment Data, Replace All must be set to false in Attachment Widget Data. |

| col1 |
|---|
| Please enter at least one Contract line. — Please enter at least one Contract line.<br>Currency entered is not listed as an Accepted Currency by Bill To Customer. — Currency entered is not listed as an Accepted Currency by Bill To Customer.<br>Currency entered is not listed as an Accepted Currency by Sold To Customer. — Currency entered is not listed as an Accepted Currency by Sold To Customer.<br>The Contract Amount and the Contract Line Amount must be equal to Submit Contract. — The Contract Amount and the Contract Line Amount must be equal to Submit Contract.<br>Effective Date is required for Contract. — Effective Date is required for Contract.<br>Only one worktag for each type is allowed for each document line. — Only one worktag for each type is allowed for each document line.<br>If "Related" Contract is entered, the related contract must have the same Company and Sold To Customer as the current contract. — If "Related" Contract is entered, the related contract must have the same Company and Sold To Customer as the current contract.<br>Bill to customer reference is for a customer that can be used as a basic worktag only. — Bill to customer reference is for a customer that can be used as a basic worktag only.<br>Customer reference is for a customer that can be used as a basic worktag only. — Customer reference is for a customer that can be used as a basic worktag only.<br>Can not have any combination of Project, Project Phase or Project Task worktags for the same line. — Can not have any combination of Project, Project Phase or Project Task worktags for the same line.<br>Customer Reference is for a Customer, not for a Sponsor. — Customer Reference is for a Customer, not for a Sponsor.<br>Customer Reference is for a Customer, not for a Sponsor. — Customer Reference is for a Customer, not for a Sponsor.<br>Revenue and billing amounts must be equal for each unique combination of company and balancing worktag. — Revenue and billing amounts must be equal for each unique combination of company and balancing worktag.<br>The sum of the Line Revenue Amount for all contract lines must be equal to zero if the Contract Type is designated as a linked contract on the Maintain Customer Contract Types task. — The sum of the Line Revenue Amount for all contract lines must be equal to zero if the Contract Type is designated as a linked contract on the Maintain Customer Contract Types task.<br>Select a contract that is not already linked. For any contract selected, the contract type must not be designed as a Linked Contract on the Maintain Customer Contract Type task.<br>Enter a Billing Schedule From Date that is earlier than the To Date. — Enter a Billing Schedule From Date that is earlier than the To Date.<br>You must enter a From Date when you use an Installment billing schedule template with Grouped Billing selected.<br>More than 1 contract line contains this Contract Line Number: [line_number]. Enter a unique Contract Line Number on each contract line.<br>Cannot create Alternate Contract if Original Contract is in Draft status.<br>Installment Type Billing Schedule Template is not valid if Original Customer Contract Supplied.<br>Transaction Type Billing Schedule Template is not valid if Original Customer Contract Supplied.<br>Alternate Customer Contract Number must match Original Customer Contract Number if supplied.<br>Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract. — Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract.<br>You cannot submit an Incremental Contract Amendment for a Draft Contract Amendment. Set the Submit Flag to Use Incremental Contract Amendment. — You cannot submit an Incremental Contract Amendment for a Draft Contract Amendment. Set the Submit Flag to Use Incremental Contract Amendment.<br>Enter a Billing Schedule From Date when you use a Transaction Billing Schedule Template with Billing Frequency and Group All Related Contract Lines selected. — Enter a Billing Schedule From Date when you use a Transaction Billing Schedule Template with Billing Frequency and Group All Related Contract Lines selected.<br>You must have a Fixed Amount - Revenue Only line type for bundle sales items: [items].<br>The Sold-To Customer is not valid for the selected company.<br>The Bill-To Customer is not valid for the selected company.<br>You can't specify a third party tax code in the transaction tax code reference. — You can't specify a third party tax code in the transaction tax code reference.<br>To create intercompany supplier invoice for this customer contract, verify that the supplier for company and currency is setup correctly. — To create intercompany supplier invoice for this customer contract, verify that the supplier for company and currency is setup correctly.<br>To create the customer contract, first specify a currency conversion rate between the contract header company currency and the contract header currency. — To create the customer contract, first specify a currency conversion rate between the contract header company currency and the contract header currency.<br>You must enter a To Date when you use an Installment billing schedule template with Grouped Billing and Use To Date selected.<br>Specify either a billing template or an installment/transaction billing schedule template - not both.<br>Specify a billing schedule template where the receivable contract type is Customer Contract and the billing template type is Billing Template.<br>The values in the Allocation Percent column must equal 100. — The values in the Allocation Percent column must equal 100.<br>The existing bill-from address is currently not in use for billing for the Customer Contract header company. You can send an updated bill-from address that has a billing usage for the Customer Contract header company. — The existing bill-from address is currently not in use for billing for the Customer Contract header company. You can send an updated bill-from address that has a billing usage for the Customer Contract header company.<br>The existing ship-from address is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled. — The existing ship-from address is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled.<br>The existing bill-from address is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled. — The existing bill-from address is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled.<br>The existing ship-from address is currently not in use for shipping for the Customer Contract header company. You can send an updated ship-from address that has a shipping usage for the Customer Contract header company. — The existing ship-from address is currently not in use for shipping for the Customer Contract header company. You can send an updated ship-from address that has a shipping usage for the Customer Contract header company.<br>The existing ship-from address at the customer contract line level is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled. — The existing ship-from address at the customer contract line level is not valid because the Enable Bill-From Address and Ship-From Address on Customer Invoice option on the Put Customer Account Options web service for this company is disabled. |

## CompanyObject

*Part of: [Customer_Contract_Data](#customer_contract_data), [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | CompanyObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## CompanyObjectID

*Part of: [CompanyObject](#companyobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Company_Reference_ID, Organization_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Sales_Item_Fair_Value_Price_ListObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Sales_Item_Fair_Value_Price_ListObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Sales_Item_Fair_Value_Price_ListObjectID

*Part of: [Sales_Item_Fair_Value_Price_ListObject](#sales_item_fair_value_price_listobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Abstract_Sales_Item_Price_List_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## CurrencyObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | CurrencyObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## CurrencyObjectID

*Part of: [CurrencyObject](#currencyobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Currency_ID, Currency_Numeric_Code | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Address_ReferenceObject

*Part of: [Address_Information_Data](#address_information_data), [Customer_Contract_Data](#customer_contract_data), [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Address_ReferenceObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Address_ReferenceObjectID

*Part of: [Address_ReferenceObject](#address_referenceobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Address_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Bill-From_Address_Data

*Part of: [Customer_Contract_Data](#customer_contract_data) — Address information data for bill-from address on invoice header*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Bill-From_Address_Data | Address_Information_Data | [0..*] | Address information | Postal Code is not a valid address component for certain countries. — Postal Code is not a valid address component for certain countries.<br>Municipality is not a valid address component for certain countries . — Municipality is not a valid address component for certain countries .<br>Region Name must be valid for the specified Country. — Region Name must be valid for the specified Country.<br>Usage Type and Use For combination must be valid for Address. — Usage Type and Use For combination must be valid for Address.<br>Second Address Line is not a valid address component for certain countries. — Second Address Line is not a valid address component for certain countries.<br>Third Address Line is not a valid address component for certain countries. — Third Address Line is not a valid address component for certain countries.<br>Fourth Address Line is not a valid address component for certain countries. — Fourth Address Line is not a valid address component for certain countries.<br>A maximum of four Submunicipalities are allowed in an address. — A maximum of four Submunicipalities are allowed in an address.<br>A maximum of four Subregions are allowed in an address. — A maximum of four Subregions are allowed in an address.<br>A maximum of four Address Lines are allowed in an address. — A maximum of four Address Lines are allowed in an address.<br>Home addresses which are not additionally used as work addresses cannot be marked as public. — Home addresses which are not additionally used as work addresses cannot be marked as public.<br>[postal code] is not a valid postal code for [region] — Postal Code must be valid for the Region.<br>Address Line 1 is not valid for this Country. — Address Line 1 is not valid for this Country.<br>Address Line 2 not Valid for this Country. — Address Line 2 not Valid for this Country.<br>Address Line 3 is not Valid for this Country. — Address Line 3 is not Valid for this Country.<br>Address Line 4 is not Valid for this Country. — Address Line 4 is not Valid for this Country.<br>Address Line 5 is not Valid for this Country. — Address Line 5 is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 7 is not Valid for this Country. — Address Line 7 is not Valid for this Country.<br>Address Line 8 is not Valid for this Country. — Address Line 8 is not Valid for this Country.<br>Address Line 9 is not Valid for this Country. — Address Line 9 is not Valid for this Country.<br>You cannot specify the same usage type more than once for an address. — You cannot specify the same usage type more than once for an address.<br>Address Line 1 - Local is not valid for this Country. — Address Line 1 - Local is not valid for this Country.<br>Municipality - Local is not a valid address component for certain countries . — Municipality - Local is not a valid address component for certain countries .<br>Address Line 2 - Local is not valid for this Country. — Address Line 2 - Local is not valid for this Country.<br>Address Line 3 - Local is not Valid for this Country. — Address Line 3 - Local is not Valid for this Country.<br>Address Line 9 - Local is not Valid for this Country. — Address Line 9 - Local is not Valid for this Country.<br>Address Line 8 - Local is not Valid for this Country. — Address Line 8 - Local is not Valid for this Country.<br>Address Line 7 - Local is not Valid for this Country. — Address Line 7 - Local is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 5 - Local is not Valid for this Country. — Address Line 5 - Local is not Valid for this Country.<br>Address Line 4 - Local is not Valid for this Country. — Address Line 4 - Local is not Valid for this Country.<br>City Subdivision 1 - Local is not a valid address component for certain countries. — City Subdivision 1 - Local is not a valid address component for certain countries.<br>City Subdivision 2 - Local is not a valid address component for certain countries. — City Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 1 - Local is not a valid address component for certain countries. — Region Subdivision 1 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 - Local is not a valid address component for certain countries. — Region Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 is not a valid address component for certain countries. — Region Subdivision 2 is not a valid address component for certain countries.<br>City Subdivision 2 is not a valid address component for certain countries. — City Subdivision 2 is not a valid address component for certain countries.<br>If one local script address field is submitted, all required local script address fields must be submitted. — If one local script address field is submitted, all required local script address fields must be submitted.<br>Address Reference is required when deleting an address — Address Reference is required when deleting an address<br>Usage Data is required unless address is being deleted — Usage Data is required unless address is being deleted<br>Country Reference is required unless address is being deleted — Country Reference is required unless address is being deleted<br>Address deletion is not supported in this web service request — Address deletion is not supported in this web service request<br>If one western script field is submitted, all required western script address fields must be submitted. — If one western script field is submitted, all required western script address fields must be submitted.<br>Use a unique Address Reference ID for each address. [ID] is already used on another address. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>You can only update addresses that belong to this customer.<br>You can't use an existing address for a new customer.<br>You can't use an existing address for a new customer request.<br>You can't use an existing address for a new prospect.<br>You can only update addresses that belong to this customer request.<br>You can only update addresses that belong to this prospect.<br>Enter a postal code in the valid format: [PostalCodeValidationMessage]<br>One or more addresses are missing a Country City reference. This field is required because the City Prompt localization is active for: [countryref].<br>Enter a Country City reference that is valid for: [countryref]. You entered this Country City reference: [countrycityref].<br>Only Address reference belonging to the Customer tied to the Customer Contact can be shared by the Customer Contact<br>International Assignment is only valid for Non-Primary Home Addresses<br>Number of Days cannot be greater than 7. — Number of Days cannot be greater than 7.<br>Number of Days is not allowed for the country specified. — Number of Days is not allowed for the country specified.<br>You must enter a Country City reference instead of a text element because the City Prompt localization is active for: [countryref]. You entered this text element: [cityattrib] [citylocalattrib].<br>You entered this Country City reference: [countrycityref]. To use this Country City reference, you must activate the City Prompt localization for: [countryref].<br>Perform either one of these actions:<br>Activate the City Prompt localization.<br>Enter a municipality instead of a Country City reference.<br>Address "[ID]" is already in use by another address (possibly on another contactable). Please choose a different Address ID. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>Second Submunicipality is not a valid address component for certain countries. — Second Submunicipality is not a valid address component for certain countries.<br>Second Subregion is not a valid address component for certain countries. — Second Subregion is not a valid address component for certain countries.<br>Subregion is not a valid address component for certain countries. — Subregion is not a valid address component for certain countries.<br>Submunicipality is not a valid address component for certain countries. — Submunicipality is not a valid address component for certain countries.<br>Specify the required missing address components for [proposedCountry]: [missingAddressComponents]<br>Specify an Address Reference that isn't already in use by another address. — Specify an Address Reference that isn't already in use by another address.<br>Existing addresses can't be future dated. Select an effective date that is on or before today, or create a new address with a future date.<br>Address [AddressReference] is not accessible to the processing user. — The Address Reference provided is not accessible to the processing user.<br>Ensure that the effective date specified in the Address Information Data matches the effective date specified in the [Add or Edit]:[Dependent Effective Date]. Alternatively, remove the effective date in the Address Information Data and reprocess the request. |

## Address_Information_Data

*Part of: [Customer_Contract_Data](#customer_contract_data), [Customer_Contract_Line_Data](#customer_contract_line_data), [Bill-From_Address_Data](#bill-from_address_data), [Ship-From_Address_Data](#ship-from_address_data) — Address information*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Formatted_Address | string | [0..1] | Returns the formatted address in the format specified for the country. This data is not used for inbound requests and any data provided in this element will be ignored. |  |
| @Address_Format_Type | string | [0..1] | The format type of the address. |  |
| @Defaulted_Business_Site_Address | boolean | [0..1] | Set to 1 if the address is a defaulted location address. If this value is 1, this address will not be processed for inbound web services. |  |
| @Delete | boolean | [0..1] | Set this flag to true in order to delete the referenced address. If this flag is set, the Reference ID field becomes required, and all other address fields that would otherwise be required will be optional and meaningless. | The referenced address is in use as a primary home address and cannot be deleted. — The referenced address is in use as a primary home address and cannot be deleted. |
| @Do_Not_Replace_All | boolean | [0..1] | This flag controls whether or not existing non-primary address data will be replaced. A value of true means only the referenced address will be updated, or created if it does not exist or no reference was provided. This behavior is used if the flag is set to true for ANY address in the request. |  |
| @Effective_Date | date | [0..1] | Effective date of address. |  |
| Country_Reference | CountryObject | [0..1] | Country for the address. |  |
| Last_Modified | dateTime | [0..1] | The moment when the address was last modified. |  |
| Address_Line_Data | Address_Line_Information_Data | [0..*] | The address line for the address. This typically contains Street name, street number, apartment, suite number. | A value is required on internal element 'Address Line Data'. If you do not want to set a value for a non-required type such as ADDRESS_LINE_2, remove it completely from the web service request. — A value is required on internal element 'Address Line Data'. If you do not want to set a value for a non-required type such as ADDRESS_LINE_2, remove it completely from the web service request.<br>Type is required when you submit an Address Line Data. — Type is required when you submit an Address Line Data.<br>The Type isn't valid. Valid types include: ADDRESS_LINE_1 to ADDRESS_LINE_9, ADDRESS_LINE_1_LOCAL to ADDRESS_LINE_9_LOCAL, CITY, CITY_LOCAL, CITY_SUBDIVISION_1 or CITY_SUBDIVISION_2, CITY_SUBDIVISION_1_LOCAL or CITY_SUBDIVISION_2_LOCAL, POSTAL_CODE, REGION, REGION_SUBDIVISION_1 or REGION_SUBDIVISION_2, REGION_SUBDIVISION_1_LOCAL or REGION_SUBDIVISION_2_LOCAL. — The Type isn't valid. Valid types include: ADDRESS_LINE_1 to ADDRESS_LINE_9, ADDRESS_LINE_1_LOCAL to ADDRESS_LINE_9_LOCAL, CITY, CITY_LOCAL, CITY_SUBDIVISION_1 or CITY_SUBDIVISION_2, CITY_SUBDIVISION_1_LOCAL or CITY_SUBDIVISION_2_LOCAL, POSTAL_CODE, REGION, REGION_SUBDIVISION_1 or REGION_SUBDIVISION_2, REGION_SUBDIVISION_1_LOCAL or REGION_SUBDIVISION_2_LOCAL. |
| Municipality | string | [0..1] | City part of the address. |  |
| Country_City_Reference | Country_CityObject | [0..1] | Country city for the address. |  |
| Submunicipality_Data | Submunicipality_Information_Data | [0..*] | The submunicipality of the address. | Element Content 'Address_Value' is required, on internal element "Submunicipality_Data" — Element Content 'Address_Value' is required, on internal element "Submunicipality_Data" |
| Country_Region_Reference | Country_RegionObject | [0..1] | The region part of the address. Typically this contains the state/province information. |  |
| Country_Region_Descriptor | string | [0..1] | The region part of the address. Typically this contains the state/province information. |  |
| Subregion_Data | Subregion_Information_Data | [0..*] | The subregion part of the address. |  |
| Postal_Code | string | [0..1] | The postal code part of the address. |  |
| Usage_Data | Communication_Method_Usage_Information_Data | [0..*] | Encapsulating element for all Communication Method Usage data. |  |
| Number_of_Days | decimal (1, 0) >0 | [0..1] | Tracks the number of days an employee works from home per week. |  |
| Municipality_Local | string | [0..1] | City in local script part of the address. |  |
| Address_Reference | Address_ReferenceObject | [0..1] | The address Reference ID. |  |
| Address_ID | string | [0..1] | New ID value used in address updates. The ID cannot already be in use by another address. | Address [ID] is not accessible to the processing user. |

| col1 |
|---|
| Postal Code is not a valid address component for certain countries. — Postal Code is not a valid address component for certain countries.<br>Municipality is not a valid address component for certain countries . — Municipality is not a valid address component for certain countries .<br>Region Name must be valid for the specified Country. — Region Name must be valid for the specified Country.<br>Usage Type and Use For combination must be valid for Address. — Usage Type and Use For combination must be valid for Address.<br>Second Address Line is not a valid address component for certain countries. — Second Address Line is not a valid address component for certain countries.<br>Third Address Line is not a valid address component for certain countries. — Third Address Line is not a valid address component for certain countries.<br>Fourth Address Line is not a valid address component for certain countries. — Fourth Address Line is not a valid address component for certain countries.<br>A maximum of four Submunicipalities are allowed in an address. — A maximum of four Submunicipalities are allowed in an address.<br>A maximum of four Subregions are allowed in an address. — A maximum of four Subregions are allowed in an address.<br>A maximum of four Address Lines are allowed in an address. — A maximum of four Address Lines are allowed in an address.<br>Home addresses which are not additionally used as work addresses cannot be marked as public. — Home addresses which are not additionally used as work addresses cannot be marked as public.<br>[postal code] is not a valid postal code for [region] — Postal Code must be valid for the Region.<br>Address Line 1 is not valid for this Country. — Address Line 1 is not valid for this Country.<br>Address Line 2 not Valid for this Country. — Address Line 2 not Valid for this Country.<br>Address Line 3 is not Valid for this Country. — Address Line 3 is not Valid for this Country.<br>Address Line 4 is not Valid for this Country. — Address Line 4 is not Valid for this Country.<br>Address Line 5 is not Valid for this Country. — Address Line 5 is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 7 is not Valid for this Country. — Address Line 7 is not Valid for this Country.<br>Address Line 8 is not Valid for this Country. — Address Line 8 is not Valid for this Country.<br>Address Line 9 is not Valid for this Country. — Address Line 9 is not Valid for this Country.<br>You cannot specify the same usage type more than once for an address. — You cannot specify the same usage type more than once for an address.<br>Address Line 1 - Local is not valid for this Country. — Address Line 1 - Local is not valid for this Country.<br>Municipality - Local is not a valid address component for certain countries . — Municipality - Local is not a valid address component for certain countries .<br>Address Line 2 - Local is not valid for this Country. — Address Line 2 - Local is not valid for this Country.<br>Address Line 3 - Local is not Valid for this Country. — Address Line 3 - Local is not Valid for this Country.<br>Address Line 9 - Local is not Valid for this Country. — Address Line 9 - Local is not Valid for this Country.<br>Address Line 8 - Local is not Valid for this Country. — Address Line 8 - Local is not Valid for this Country.<br>Address Line 7 - Local is not Valid for this Country. — Address Line 7 - Local is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 5 - Local is not Valid for this Country. — Address Line 5 - Local is not Valid for this Country.<br>Address Line 4 - Local is not Valid for this Country. — Address Line 4 - Local is not Valid for this Country.<br>City Subdivision 1 - Local is not a valid address component for certain countries. — City Subdivision 1 - Local is not a valid address component for certain countries.<br>City Subdivision 2 - Local is not a valid address component for certain countries. — City Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 1 - Local is not a valid address component for certain countries. — Region Subdivision 1 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 - Local is not a valid address component for certain countries. — Region Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 is not a valid address component for certain countries. — Region Subdivision 2 is not a valid address component for certain countries.<br>City Subdivision 2 is not a valid address component for certain countries. — City Subdivision 2 is not a valid address component for certain countries.<br>If one local script address field is submitted, all required local script address fields must be submitted. — If one local script address field is submitted, all required local script address fields must be submitted.<br>Address Reference is required when deleting an address — Address Reference is required when deleting an address<br>Usage Data is required unless address is being deleted — Usage Data is required unless address is being deleted<br>Country Reference is required unless address is being deleted — Country Reference is required unless address is being deleted<br>Address deletion is not supported in this web service request — Address deletion is not supported in this web service request<br>If one western script field is submitted, all required western script address fields must be submitted. — If one western script field is submitted, all required western script address fields must be submitted.<br>Use a unique Address Reference ID for each address. [ID] is already used on another address. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>You can only update addresses that belong to this customer.<br>You can't use an existing address for a new customer.<br>You can't use an existing address for a new customer request.<br>You can't use an existing address for a new prospect.<br>You can only update addresses that belong to this customer request.<br>You can only update addresses that belong to this prospect.<br>Enter a postal code in the valid format: [PostalCodeValidationMessage]<br>One or more addresses are missing a Country City reference. This field is required because the City Prompt localization is active for: [countryref].<br>Enter a Country City reference that is valid for: [countryref]. You entered this Country City reference: [countrycityref].<br>Only Address reference belonging to the Customer tied to the Customer Contact can be shared by the Customer Contact<br>International Assignment is only valid for Non-Primary Home Addresses<br>Number of Days cannot be greater than 7. — Number of Days cannot be greater than 7.<br>Number of Days is not allowed for the country specified. — Number of Days is not allowed for the country specified.<br>You must enter a Country City reference instead of a text element because the City Prompt localization is active for: [countryref]. You entered this text element: [cityattrib] [citylocalattrib].<br>You entered this Country City reference: [countrycityref]. To use this Country City reference, you must activate the City Prompt localization for: [countryref].<br>Perform either one of these actions:<br>Activate the City Prompt localization.<br>Enter a municipality instead of a Country City reference.<br>Address "[ID]" is already in use by another address (possibly on another contactable). Please choose a different Address ID. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>Second Submunicipality is not a valid address component for certain countries. — Second Submunicipality is not a valid address component for certain countries.<br>Second Subregion is not a valid address component for certain countries. — Second Subregion is not a valid address component for certain countries.<br>Subregion is not a valid address component for certain countries. — Subregion is not a valid address component for certain countries.<br>Submunicipality is not a valid address component for certain countries. — Submunicipality is not a valid address component for certain countries.<br>Specify the required missing address components for [proposedCountry]: [missingAddressComponents]<br>Specify an Address Reference that isn't already in use by another address. — Specify an Address Reference that isn't already in use by another address.<br>Existing addresses can't be future dated. Select an effective date that is on or before today, or create a new address with a future date.<br>Address [AddressReference] is not accessible to the processing user. — The Address Reference provided is not accessible to the processing user.<br>Ensure that the effective date specified in the Address Information Data matches the effective date specified in the [Add or Edit]:[Dependent Effective Date]. Alternatively, remove the effective date in the Address Information Data and reprocess the request. |

## CountryObject

*Part of: [Address_Information_Data](#address_information_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | CountryObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## CountryObjectID

*Part of: [CountryObject](#countryobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, ISO_3166-1_Alpha-2_Code, ISO_3166-1_Alpha-3_Code, ISO_3166-1_Numeric-3_Code, OPM_Country_Code | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Address_Line_Information_Data

*Part of: [Address_Information_Data](#address_information_data) — The address line for the address. This typically contains Street name, street number, apartment, suite number.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  | A value is required on internal element 'Address Line Data'. If you do not want to set a value for a non-required type such as ADDRESS_LINE_2, remove it completely from the web service request. — A value is required on internal element 'Address Line Data'. If you do not want to set a value for a non-required type such as ADDRESS_LINE_2, remove it completely from the web service request.<br>Type is required when you submit an Address Line Data. — Type is required when you submit an Address Line Data.<br>The Type isn't valid. Valid types include: ADDRESS_LINE_1 to ADDRESS_LINE_9, ADDRESS_LINE_1_LOCAL to ADDRESS_LINE_9_LOCAL, CITY, CITY_LOCAL, CITY_SUBDIVISION_1 or CITY_SUBDIVISION_2, CITY_SUBDIVISION_1_LOCAL or CITY_SUBDIVISION_2_LOCAL, POSTAL_CODE, REGION, REGION_SUBDIVISION_1 or REGION_SUBDIVISION_2, REGION_SUBDIVISION_1_LOCAL or REGION_SUBDIVISION_2_LOCAL. — The Type isn't valid. Valid types include: ADDRESS_LINE_1 to ADDRESS_LINE_9, ADDRESS_LINE_1_LOCAL to ADDRESS_LINE_9_LOCAL, CITY, CITY_LOCAL, CITY_SUBDIVISION_1 or CITY_SUBDIVISION_2, CITY_SUBDIVISION_1_LOCAL or CITY_SUBDIVISION_2_LOCAL, POSTAL_CODE, REGION, REGION_SUBDIVISION_1 or REGION_SUBDIVISION_2, REGION_SUBDIVISION_1_LOCAL or REGION_SUBDIVISION_2_LOCAL. |
| @Descriptor | string | [0..1] | The descriptor is an optional serialized attribute that shows the text Override Label (such as Apartment Number or Building Number) that helps describe the usage of the type (such as ADDRESS_LINE_5 and ADDRESS_LINE_6) for each country. |  |
| @Type | string | [0..1] | Enter the address line type, such as ADDRESS_LINE_1, or ADDRESS_LINE_2. |  |

| col1 |
|---|
| A value is required on internal element 'Address Line Data'. If you do not want to set a value for a non-required type such as ADDRESS_LINE_2, remove it completely from the web service request. — A value is required on internal element 'Address Line Data'. If you do not want to set a value for a non-required type such as ADDRESS_LINE_2, remove it completely from the web service request.<br>Type is required when you submit an Address Line Data. — Type is required when you submit an Address Line Data.<br>The Type isn't valid. Valid types include: ADDRESS_LINE_1 to ADDRESS_LINE_9, ADDRESS_LINE_1_LOCAL to ADDRESS_LINE_9_LOCAL, CITY, CITY_LOCAL, CITY_SUBDIVISION_1 or CITY_SUBDIVISION_2, CITY_SUBDIVISION_1_LOCAL or CITY_SUBDIVISION_2_LOCAL, POSTAL_CODE, REGION, REGION_SUBDIVISION_1 or REGION_SUBDIVISION_2, REGION_SUBDIVISION_1_LOCAL or REGION_SUBDIVISION_2_LOCAL. — The Type isn't valid. Valid types include: ADDRESS_LINE_1 to ADDRESS_LINE_9, ADDRESS_LINE_1_LOCAL to ADDRESS_LINE_9_LOCAL, CITY, CITY_LOCAL, CITY_SUBDIVISION_1 or CITY_SUBDIVISION_2, CITY_SUBDIVISION_1_LOCAL or CITY_SUBDIVISION_2_LOCAL, POSTAL_CODE, REGION, REGION_SUBDIVISION_1 or REGION_SUBDIVISION_2, REGION_SUBDIVISION_1_LOCAL or REGION_SUBDIVISION_2_LOCAL. |

## Country_CityObject

*Part of: [Address_Information_Data](#address_information_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Country_CityObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Country_CityObjectID

*Part of: [Country_CityObject](#country_cityobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Country_Subregion_Code_In_Country, Country_Subregion_Internal_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |
| @parent_id | string | [0..1] | For types that require a parent reference, contains a unique identifier for an instance of a parent object. |  |
| @parent_type | WID, ISO_3166-1_Alpha-2_Code, ISO_3166-1_Alpha-3_Code, ISO_3166-1_Numeric-3_Code, OPM_Country_Code | [0..1] | For types that require a parent reference, the unique identifier type of a parent object. |  |

## Submunicipality_Information_Data

*Part of: [Address_Information_Data](#address_information_data) — The submunicipality of the address.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  | Element Content 'Address_Value' is required, on internal element "Submunicipality_Data" — Element Content 'Address_Value' is required, on internal element "Submunicipality_Data" |
| @Address_Component_Name | string | [0..1] | The descriptor is an optional serialized attribute that shows the text Override Label (such as Municipality or District) that helps describe the usage of the type (such as CITY_SUBDIVISION_1 or CITY_SUBDIVISION_2) for each country. |  |
| @Type | string | [0..1] | The city subdivision part of the address. |  |

| col1 |
|---|
| Element Content 'Address_Value' is required, on internal element "Submunicipality_Data" — Element Content 'Address_Value' is required, on internal element "Submunicipality_Data" |

## Country_RegionObject

*Part of: [Address_Information_Data](#address_information_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Country_RegionObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Country_RegionObjectID

*Part of: [Country_RegionObject](#country_regionobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Country_Region_ID, ISO_3166-2_Code, ISO_3166-2_Country-Region_Code, OPM_Country_Subdivision_Code | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Subregion_Information_Data

*Part of: [Address_Information_Data](#address_information_data) — The subregion part of the address.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @Descriptor | string | [0..1] | The descriptor is an optional serialized attribute that shows the text Override Label (such as Municipality or District) that helps describe the usage of the type (such as REGION_SUBDIVISION_1 or REGION_SUBDIVISION_2) for each country. |  |
| @Type | string | [0..1] | Enter the region subdivision type, such as REGION_SUBDIVISION_1, or REGION_SUBDIVISION_2. |  |

## Communication_Method_Usage_Information_Data

*Part of: [Address_Information_Data](#address_information_data) — Encapsulating element for all Communication Method Usage data.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Public | boolean | [0..1] | Indicates if the address is public. |  |
| Type_Data | Communication_Usage_Type_Data | [1..*] | Reference ID for the communication usage type. |  |
| Use_For_Reference | Communication_Usage_BehaviorObject | [0..*] | Reference ID for communication usage behavior. |  |
| Use_For_Tenanted_Reference | Communication_Usage_Behavior_TenantedObject | [0..*] | Reference ID for communication usage behavior tenanted. |  |
| Comments | string | [0..1] | Description of the address, phone, email, instant messenger, or web address. | Character limit is 2,000. |

## Communication_Usage_Type_Data

*Part of: [Communication_Method_Usage_Information_Data](#communication_method_usage_information_data) — Reference ID for the communication usage type.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Primary | boolean | [0..1] | Indicates if the communication method is primary. |  |
| Type_Reference | Communication_Usage_TypeObject | [1..1] | Reference ID for the communication usage type. |  |

## Communication_Usage_TypeObject

*Part of: [Communication_Usage_Type_Data](#communication_usage_type_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Communication_Usage_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Communication_Usage_TypeObjectID

*Part of: [Communication_Usage_TypeObject](#communication_usage_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Communication_Usage_Type_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Communication_Usage_BehaviorObject

*Part of: [Communication_Method_Usage_Information_Data](#communication_method_usage_information_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Communication_Usage_BehaviorObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Communication_Usage_BehaviorObjectID

*Part of: [Communication_Usage_BehaviorObject](#communication_usage_behaviorobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Communication_Usage_Behavior_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Communication_Usage_Behavior_TenantedObject

*Part of: [Communication_Method_Usage_Information_Data](#communication_method_usage_information_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Communication_Usage_Behavior_TenantedObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Communication_Usage_Behavior_TenantedObjectID

*Part of: [Communication_Usage_Behavior_TenantedObject](#communication_usage_behavior_tenantedobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Communication_Usage_Behavior_Tenanted_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Ship-From_Address_Data

*Part of: [Customer_Contract_Data](#customer_contract_data), [Customer_Contract_Line_Data](#customer_contract_line_data) — Address information data for ship-from address on invoice header*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Ship-From_Address_Data | Address_Information_Data | [0..*] | Address information | Postal Code is not a valid address component for certain countries. — Postal Code is not a valid address component for certain countries.<br>Municipality is not a valid address component for certain countries . — Municipality is not a valid address component for certain countries .<br>Region Name must be valid for the specified Country. — Region Name must be valid for the specified Country.<br>Usage Type and Use For combination must be valid for Address. — Usage Type and Use For combination must be valid for Address.<br>Second Address Line is not a valid address component for certain countries. — Second Address Line is not a valid address component for certain countries.<br>Third Address Line is not a valid address component for certain countries. — Third Address Line is not a valid address component for certain countries.<br>Fourth Address Line is not a valid address component for certain countries. — Fourth Address Line is not a valid address component for certain countries.<br>A maximum of four Submunicipalities are allowed in an address. — A maximum of four Submunicipalities are allowed in an address.<br>A maximum of four Subregions are allowed in an address. — A maximum of four Subregions are allowed in an address.<br>A maximum of four Address Lines are allowed in an address. — A maximum of four Address Lines are allowed in an address.<br>Home addresses which are not additionally used as work addresses cannot be marked as public. — Home addresses which are not additionally used as work addresses cannot be marked as public.<br>[postal code] is not a valid postal code for [region] — Postal Code must be valid for the Region.<br>Address Line 1 is not valid for this Country. — Address Line 1 is not valid for this Country.<br>Address Line 2 not Valid for this Country. — Address Line 2 not Valid for this Country.<br>Address Line 3 is not Valid for this Country. — Address Line 3 is not Valid for this Country.<br>Address Line 4 is not Valid for this Country. — Address Line 4 is not Valid for this Country.<br>Address Line 5 is not Valid for this Country. — Address Line 5 is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 7 is not Valid for this Country. — Address Line 7 is not Valid for this Country.<br>Address Line 8 is not Valid for this Country. — Address Line 8 is not Valid for this Country.<br>Address Line 9 is not Valid for this Country. — Address Line 9 is not Valid for this Country.<br>You cannot specify the same usage type more than once for an address. — You cannot specify the same usage type more than once for an address.<br>Address Line 1 - Local is not valid for this Country. — Address Line 1 - Local is not valid for this Country.<br>Municipality - Local is not a valid address component for certain countries . — Municipality - Local is not a valid address component for certain countries .<br>Address Line 2 - Local is not valid for this Country. — Address Line 2 - Local is not valid for this Country.<br>Address Line 3 - Local is not Valid for this Country. — Address Line 3 - Local is not Valid for this Country.<br>Address Line 9 - Local is not Valid for this Country. — Address Line 9 - Local is not Valid for this Country.<br>Address Line 8 - Local is not Valid for this Country. — Address Line 8 - Local is not Valid for this Country.<br>Address Line 7 - Local is not Valid for this Country. — Address Line 7 - Local is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 5 - Local is not Valid for this Country. — Address Line 5 - Local is not Valid for this Country.<br>Address Line 4 - Local is not Valid for this Country. — Address Line 4 - Local is not Valid for this Country.<br>City Subdivision 1 - Local is not a valid address component for certain countries. — City Subdivision 1 - Local is not a valid address component for certain countries.<br>City Subdivision 2 - Local is not a valid address component for certain countries. — City Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 1 - Local is not a valid address component for certain countries. — Region Subdivision 1 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 - Local is not a valid address component for certain countries. — Region Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 is not a valid address component for certain countries. — Region Subdivision 2 is not a valid address component for certain countries.<br>City Subdivision 2 is not a valid address component for certain countries. — City Subdivision 2 is not a valid address component for certain countries.<br>If one local script address field is submitted, all required local script address fields must be submitted. — If one local script address field is submitted, all required local script address fields must be submitted.<br>Address Reference is required when deleting an address — Address Reference is required when deleting an address<br>Usage Data is required unless address is being deleted — Usage Data is required unless address is being deleted<br>Country Reference is required unless address is being deleted — Country Reference is required unless address is being deleted<br>Address deletion is not supported in this web service request — Address deletion is not supported in this web service request<br>If one western script field is submitted, all required western script address fields must be submitted. — If one western script field is submitted, all required western script address fields must be submitted.<br>Use a unique Address Reference ID for each address. [ID] is already used on another address. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>You can only update addresses that belong to this customer.<br>You can't use an existing address for a new customer.<br>You can't use an existing address for a new customer request.<br>You can't use an existing address for a new prospect.<br>You can only update addresses that belong to this customer request.<br>You can only update addresses that belong to this prospect.<br>Enter a postal code in the valid format: [PostalCodeValidationMessage]<br>One or more addresses are missing a Country City reference. This field is required because the City Prompt localization is active for: [countryref].<br>Enter a Country City reference that is valid for: [countryref]. You entered this Country City reference: [countrycityref].<br>Only Address reference belonging to the Customer tied to the Customer Contact can be shared by the Customer Contact<br>International Assignment is only valid for Non-Primary Home Addresses<br>Number of Days cannot be greater than 7. — Number of Days cannot be greater than 7.<br>Number of Days is not allowed for the country specified. — Number of Days is not allowed for the country specified.<br>You must enter a Country City reference instead of a text element because the City Prompt localization is active for: [countryref]. You entered this text element: [cityattrib] [citylocalattrib].<br>You entered this Country City reference: [countrycityref]. To use this Country City reference, you must activate the City Prompt localization for: [countryref].<br>Perform either one of these actions:<br>Activate the City Prompt localization.<br>Enter a municipality instead of a Country City reference.<br>Address "[ID]" is already in use by another address (possibly on another contactable). Please choose a different Address ID. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>Second Submunicipality is not a valid address component for certain countries. — Second Submunicipality is not a valid address component for certain countries.<br>Second Subregion is not a valid address component for certain countries. — Second Subregion is not a valid address component for certain countries.<br>Subregion is not a valid address component for certain countries. — Subregion is not a valid address component for certain countries.<br>Submunicipality is not a valid address component for certain countries. — Submunicipality is not a valid address component for certain countries.<br>Specify the required missing address components for [proposedCountry]: [missingAddressComponents]<br>Specify an Address Reference that isn't already in use by another address. — Specify an Address Reference that isn't already in use by another address.<br>Existing addresses can't be future dated. Select an effective date that is on or before today, or create a new address with a future date.<br>Address [AddressReference] is not accessible to the processing user. — The Address Reference provided is not accessible to the processing user.<br>Ensure that the effective date specified in the Address Information Data matches the effective date specified in the [Add or Edit]:[Dependent Effective Date]. Alternatively, remove the effective date in the Address Information Data and reprocess the request. |

## Billable_EntityObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Billable_EntityObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Billable_EntityObjectID

*Part of: [Billable_EntityObject](#billable_entityobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Customer_ID, Customer_Reference_ID, Sponsor_ID, Sponsor_Reference_ID, Student_Financial_Account_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## CustomerObject

*Part of: [Customer_Contract_Data](#customer_contract_data), [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | CustomerObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## CustomerObjectID

*Part of: [CustomerObject](#customerobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Customer_ID, Customer_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Customer_Contract_TypeObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Customer_Contract_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Customer_Contract_TypeObjectID

*Part of: [Customer_Contract_TypeObject](#customer_contract_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Contract_Type_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Payment_TermsObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Payment_TermsObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Payment_TermsObjectID

*Part of: [Payment_TermsObject](#payment_termsobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Payment_Terms_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Payment_TypeObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Payment_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Payment_TypeObjectID

*Part of: [Payment_TypeObject](#payment_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Payment_Type_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Tax_CodeObject

*Part of: [Customer_Contract_Data](#customer_contract_data), [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Tax_CodeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Tax_CodeObjectID

*Part of: [Tax_CodeObject](#tax_codeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Tax_Code_ID, Withholding_Tax_Code_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Customer_Contract_AbstractObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Customer_Contract_AbstractObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Customer_Contract_AbstractObjectID

*Part of: [Customer_Contract_AbstractObject](#customer_contract_abstractobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Customer_Contract_Alternate_Reference_ID, Customer_Contract_Amendment_Reference_ID, Customer_Contract_Intercompany_ID, Customer_Contract_Reference_ID, Sales_Order_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Customer_Contract_AlternateObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Customer_Contract_AlternateObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Customer_Contract_AlternateObjectID

*Part of: [Customer_Contract_AlternateObject](#customer_contract_alternateobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Customer_Contract_Alternate_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Audited_Accounting_WorktagObject

*Part of: [Customer_Contract_Data](#customer_contract_data), [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Audited_Accounting_WorktagObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Audited_Accounting_WorktagObjectID

*Part of: [Audited_Accounting_WorktagObject](#audited_accounting_worktagobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Academic_Level_ID, Academic_Period_ID, Academic_Person_ID, Academic_Unit_ID, Ad_hoc_Payee_ID, Allocation_Pool_ID, Alternate_Supplier_Contract_ID, Applicant_ID, Application_Grouping_ID, Appropriation_ID, Asset_Adjustment_Reason_Reference_ID, Asset_Adjustment_Type_Reference_ID, Asset_Impairment_Reason_ID, Bank_Account_ID, Business_Asset_Cost_Adjustment_Reason_ID, Business_Unit_ID, Candidate_ID, Cash_Activity_Category_ID, Catalog_Item_ID, Company_Reference_ID, Compensation_Grade_ID, Contingent_Worker_ID, Contingent_Worker_Type_ID, Corporate_Credit_Card_Account_ID, Cost_Center_Reference_ID, Custom_Organization_Reference_ID, Custom_Worktag_06_ID, Custom_Worktag_07_ID, Custom_Worktag_08_ID, Custom_Worktag_09_ID, Custom_Worktag_1_ID, Custom_Worktag_10_ID, Custom_Worktag_11_ID, Custom_Worktag_12_ID, Custom_Worktag_13_ID, Custom_Worktag_14_ID, Custom_Worktag_15_ID, Custom_Worktag_2_ID, Custom_Worktag_3_ID, Custom_Worktag_4_ID, Custom_Worktag_5_ID, Customer_Category_ID, Customer_Contract_Alternate_Reference_ID, Customer_Contract_Reference_ID, Customer_ID, Customer_Reference_ID, Donor_ID, Employee_ID, Employee_Type_ID, Ethnicity_ID, Expense_Item_ID, External_Committee_Member_ID, External_Sourceable_ID, Financial_Institution_ID, Financial_Institution_Reference_ID, Fringe_Basis_ID, Fund_ID, Funding_Source_Name, Gender_Code, Gift_Reference_ID, Grant_ID, Internal_Service_Provider_ID, Internal_Service_Provider_Reference_ID, Investment_Pool_ID, Investment_Profile_ID, Investor_ID, Job_Category_ID, Job_Level_ID, Job_Profile_ID, Job_Requisition_ID, Loan_ID, Location_ID, Management_Level_ID, Miscellaneous_Payee_ID, Object_Class_ID, Opportunity_Reference_ID, Organization_Reference_ID, Pay_Rate_Type_ID, Petty_Cash_Account_ID, Position_ID, Position_Time_Type_ID, Program_ID, Program_of_Study_ID, Project_ID, Project_Plan_ID, Project_Worker_Role_ID, Proposal_Grant_ID, Prospect_ID, Prospect_Reference_ID, Purchase_Item_ID, Receivable_Writeoff_Reason_ID, Region_Reference_ID, Revenue_Category_ID, Run_Category_ID, Salary_Over_the_Cap_Basis_ID, Salary_Over_The_Cap_Type_ID, Sales_Item_ID, Spend_Category_ID, Sponsor_ID, Sponsor_Reference_ID, Student_Award_Item_ID, Student_Charge_Item_ID, Student_Course_ID, Student_Course_Section_ID, Student_ID, Student_Recruiting_Campaign_ID, Student_Recruiting_Event_ID, Student_Sponsor_Contract_ID, Student_Waiver_Item_ID, Supplier_Category_ID, Supplier_Contract_ID, Supplier_Contract_ID_External, Supplier_ID, Supplier_Reference_ID, Tax_Applicability_ID, Tax_Authority_ID, Tax_Authority_Reference_ID, Tax_Category_ID, Tax_Code_ID, Tax_Rate_ID, Tax_Recoverability_Object_ID, Third_Party_ID, Universal_Identifier_ID, Withholding_Order_Case_ID, Withholding_Tax_Code_ID, Withholding_Tax_Rate_ID, Work_Function_ID, Work_Shift_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |
| @parent_id | string | [0..1] | For types that require a parent reference, contains a unique identifier for an instance of a parent object. |  |
| @parent_type | WID, External_Supplier_Invoice_Source_ID, External_Transaction_Source_ID, Workday_External_Supplier_Invoice_Source_ID, Workday_External_Transaction_Source_ID | [0..1] | For types that require a parent reference, the unique identifier type of a parent object. |  |

## Contract_Discount_PremiumObject

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Contract_Discount_PremiumObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Contract_Discount_PremiumObjectID

*Part of: [Contract_Discount_PremiumObject](#contract_discount_premiumobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Contract_Discount_and_Premium_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Billing_Schedule_TemplateObject

*Part of: [Customer_Contract_Data](#customer_contract_data), [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Billing_Schedule_TemplateObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Billing_Schedule_TemplateObjectID

*Part of: [Billing_Schedule_TemplateObject](#billing_schedule_templateobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Billing_Schedule_Template_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Customer_Contract_Line_Data

*Part of: [Customer_Contract_Data](#customer_contract_data) — Customer Contract Line Data. A Customer Contract may have multiple lines and must have at least 1 line.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Receivable_Contract_Line_Reference | Receivable_Contract_Line_AbstractObject | [0..1] | Reference to an existing Receivable Contract Line for update only purposes. |  |
| Receivable_Contract_Line_Reference_ID | string | [0..1] | The Receivable Contract Line Reference ID. This is the Receivable Contract Line unique identifier. | The contract line or contract line reference ID is not valid for this contract. You can either update an existing contract line on this contract or create a new contract line for this contract.<br>Provide Contract Line Reference, if you select the Contract Change without Amendment flag. |
| Line_Number | decimal (4, 0) >0 | [1..1] | Contract Line Number | You can't modify or remove the contract line number. — You can't modify or remove the contract line number. |
| Line_Company_Reference | CompanyObject | [0..1] | The company for the line for intercompany contracts. If field is left blank, it will default to the same company as the contract header. | Set up an intercompany relationship between [hdr company] and [line company] using the Edit Company Intercompany Profile task.<br>Currency Conversion Rates between currency and the line company's default currency are not defined.<br>Company cannot be modified on this Contract line — Company cannot be modified on this Contract line<br>Currency Conversion Rates between currency and company's default currency are not defined. — Currency Conversion Rates between currency and company's default currency are not defined.<br>Company on the line must be the same as Company on the document for intercompany customers. |
| Bundled_Revenue_Only_Contract_Line_Reference | Customer_Contract_LineObject | [0..*] | Revenue Only Customer Contract Lines that are associated to this Billing only Customer Contract Line. | You can’t reference a Bundled Revenue Only Contract Line which isn't on the contract. |
| Billing_Only_Customer_Contract_Line_Reference | Customer_Contract_LineObject | [0..1] | Billing Only Customer Contract Line parent for this Revenue Only Customer Contract Line. | You can’t reference a Billing Only Contract Line which isn't on the contract. |
| Bundle_Line_Number | decimal (4, 0) >0 | [0..1] | References the Billing Only Customer Contract Line this bundled line belongs to. |  |
| Ship-From_Address_Line_Reference | Address_ReferenceObject | [0..1] | Ship-From Address for Customer Contract Line | To specify the Ship-From Address for the customer contract line company, first set the Enable Bill-From Address and Ship-From Address on Customer Invoice field to true on the Put Customer Account Options web service for this company. — To specify the Ship-From Address for the customer contract line company, first set the Enable Bill-From Address and Ship-From Address on Customer Invoice field to true on the Put Customer Account Options web service for this company.<br>Specify a Ship-From Address that is currently in use for shipping for the customer contract line company. — Specify a Ship-From Address that is currently in use for shipping for the customer contract line company. |
| Ship-From_Address_Line_Data | Ship-From_Address_Data | [0..*] | Address information data for ship-from address on invoice header |  |
| Sales_Item_Reference | Item_DescriptorObject | [0..1] | This is the reference id value of the sales item.<br>If a value is provided for sales item, revenue category will default so it is recommended to provide a value for either sales item or revenue category but not both. | Sales Item is not enterable for this Customer Contract Amendment — Sales Item is not enterable for this Customer Contract Amendment<br>The sales item is not mapped to a purchase item. — The sales item is not mapped to a purchase item.<br>For contract lines containing sales item bundles, the Contract Line Type must be Fixed Amount – Billing Only.<br>You cannot edit Sales Item Reference during a contract change when schedules exist on the contract. — You cannot edit Sales Item Reference during a contract change when schedules exist on the contract. |
| Commodity_Code_Reference | Commodity_CodeObject | [0..*] | Commodity Code for Customer Contract Line | Specify an active commodity code. — Specify an active commodity code.<br>You can select only 1 code for each commodity code type. — You can select only 1 code for each commodity code type.<br>Specify a valid commodity code for the associated sales item. — Specify a valid commodity code for the associated sales item. |
| Revenue_Category_Reference | Accounting_CategoryObject | [0..1] | This is the reference id value of the spend category. A spend category is a classification of items and services that drive the accounting. All expense items are associated with a Spend Category and sales items are associated with a Revenue Category.<br>If a value is provided for sales item, revenue category will default so it is recommended to provide a value for either sales item or revenue category but not both.<br>It is required if sales item is blank. | The revenue category is not mapped to a spend category. — The revenue category is not mapped to a spend category.<br>Revenue Category is not enterable for Customer Contract Amendment — Revenue Category is not enterable for Customer Contract Amendment<br>You cannot edit Revenue Category Reference during a contract change when schedules exist on the contract. — You cannot edit Revenue Category Reference during a contract change when schedules exist on the contract.<br>Revenue Category Reference doesn't refer to a valid Revenue Category. |
| Contract_Line_Type_Reference | Contract_Line_TypeObject | [1..1] | Contract Line Type for Customer Contract Line. | Line Type must be Fixed Amount - Revenue Only if the Contract Type is designated as a linked contract on the Maintain Customer Contract Types task.<br>Include all Revenue Only contract lines.<br>You cannot edit Contract Line Type Reference during a contract change when schedules exist on the contract. — You cannot edit Contract Line Type Reference during a contract change when schedules exist on the contract. |
| Alternate_Customer_Contract_Line_Reference | Customer_Contract_LineObject | [0..1] | Alternate Customer Contract Line. The Alternate Customer Contract Line associated to this Customer Contract Line. | You can't update the alternate customer contract line reference because this line already references: [original line]. |
| Original_Customer_Contract_Line_Reference | Customer_Contract_LineObject | [0..1] | Original Customer Contract Line. The Original Customer Contract Line associated to this Alternate Customer Contract Line. |  |
| Billable_Project_Reference | Project_AbstractObject | [0..1] | Billable Project Reference for Contract Line. Billable Project is required for project contract line types. | Cancel Invoices before you amend the Billable Project on Contract Line. — Cancel Invoices before you amend the Billable Project on Contract Line.<br>Cancel Schedules on the contract line before you amend the Billable Project. — Cancel Schedules on the contract line before you amend the Billable Project.<br>You cannot edit Billable Project Reference during a contract change when schedules exist on the contract. — You cannot edit Billable Project Reference during a contract change when schedules exist on the contract.<br>You can't change or amend the billable project because there are usage-based transactions associated with this customer contract line. To change or amend the billable project, either create a new customer contract or customer contract line. — You can't change or amend the billable project because there are usage-based transactions associated with this customer contract line. To change or amend the billable project, either create a new customer contract or customer contract line.<br>To specify this project in the Billable Project Reference field, ensure that you have access to the project. — To specify this project in the Billable Project Reference field, ensure that you have access to the project. |
| Phase_Reference | Project_Plan_PhaseObject | [0..*] | Project Phase Reference for Contract Line. | Specify a Phase Reference that's associated with the project on the contract line.<br>You can't edit a Phase Reference during a contract change when schedules exist on the contract.<br>To amend the Phase on the contract line, first cancel the associated invoices.<br>To amend the Phase on the contract line, first cancel the associated schedules.<br>To specify a Phase Reference, first specify a project.<br>Specify a top-level Phase Reference on the contract line. |
| Task_Reference | Project_Plan_TaskObject | [0..*] | Project Task Reference for Contract Line. | You can't edit a Task Reference during a contract change when schedules exist on the contract.<br>Specify a Task Reference that's associated with the project and phase on the contract line.<br>To amend the Task on the contract line, first cancel the associated invoices.<br>To specify a Task Reference, first specify a project and phase.<br>To amend the Task on the contract line, first cancel the associated schedules. |
| Project_Transaction_Source_Reference | Project_Transaction_SourceObject | [0..*] | Project Transaction Source Reference. Project Transaction Source of Expense and or Time is required for project contract line types. | Cancel Schedules on the contract line before you amend the Project Transaction Source. — Cancel Schedules on the contract line before you amend the Project Transaction Source.<br>Cancel Invoices on the contract line before you amend the Project Transaction Source. — Cancel Invoices on the contract line before you amend the Project Transaction Source.<br>You cannot edit Project Transaction Source Reference during a contract change when schedules exist on the contract. — You cannot edit Project Transaction Source Reference during a contract change when schedules exist on the contract. |
| Use_Standard_Rate_Sheet | boolean | [0..1] | Customer Contract Line uses Standard Rate Sheet. | Contract Line with a standard rate sheet must have a source that includes Time.<br>You can't change a standard rate sheet flag when billing schedules exist on the contract. — You can't change a standard rate sheet flag when billing schedules exist on the contract.<br>Submit a Project Contract Line Type to use a standard rate sheet. |
| Contract_Rate_Sheet_Reference | Contract_Rate_SheetObject | [0..1] | This is a reference to an already existing Contract Rate Sheet. | You cannot edit Contract Rate Sheet Reference during a contract change when schedules exist on the contract. — You cannot edit Contract Rate Sheet Reference during a contract change when schedules exist on the contract.<br>Specify a customer contract currency that matches the contract rate sheet currency.<br>Ensure the contract rate sheet currency matches the currency on all the customer contracts for the project.<br>The contract rate sheet specifies a project billing rate sheet with company, customer, and worktags that don't match the fields on the customer contract line. The field values must match the contract line's values.<br>Update the contract rate sheet so that it has only 1 rate. Contract rate sheets can't have multiple rates for a role. |
| Usage_Billing_Rate_Reference | Usage_Billing_RateObject | [0..1] | The Line Type for this customer contract line must be Usage Based to add a Usage Billing Rate. | The Line Type for this customer contract line must be Usage Based to add a Usage Billing Rate.<br>You cannot associate a Usage Billing Rate with more than one customer contract. — You cannot associate a Usage Billing Rate with more than one customer contract.<br>You cannot edit Usage Billing Rate Reference during a contract change when schedules exist on the contract. — You cannot edit Usage Billing Rate Reference during a contract change when schedules exist on the contract.<br>Ensure the Minimum Amount on the usage billing rate has a currency precision that's allowed for the customer contract currency. |
| Contract_Line_Fee_Reference | Contract_Line_FeeObject | [0..1] | Contract Line Fee reference. This is a reference to an existing Contract Line Fee. | The Line Type for this customer contract line must be Project Time & Expense to add a Contract Line Fee. — The Line Type for this customer contract line must be Project Time & Expense to add a Contract Line Fee. |
| Customer_Contract_Line_Start_Date | date | [0..1] | Customer Contract Line Start Date |  |
| Customer_Contract_Line_End_Date | date | [0..1] | Customer Contract Line End Date | You cannot edit Customer Contract Line End Date during a contract change when schedules exist on the contract. — You cannot edit Customer Contract Line End Date during a contract change when schedules exist on the contract. |
| Contract_Line_Description | string | [0..1] | Contract Line Description |  |
| Is_Quantity_per_Bundle_Zero | boolean | [0..1] | You can enable this option for bundled customer contract lines that have a line type of Fixed Amount - Revenue Only. When you enable this option, Workday sets the Quantity, List Extended Amount, Fair Value Extended Amount, and Revenue Override Amount fields to zero. |  |
| Quantity | decimal (22, 2) | [0..1] | Quantity for Contract Line | You cannot edit Quantity during a contract change when schedules exist on the contract. — You cannot edit Quantity during a contract change when schedules exist on the contract. |
| Unit_of_Measure_Reference | Unit_of_MeasureObject | [0..1] | Customer Contract Line Unit of Measure |  |
| Quantity_2 | decimal (22, 2) | [0..1] | Second Quantity for Contract Line, corresponding to the secondary Unit of Measure. | You cannot edit Quantity 2 during a contract change when schedules exist on the contract. — You cannot edit Quantity 2 during a contract change when schedules exist on the contract. |
| Unit_of_Measure_2_Reference | Unit_of_MeasureObject | [0..1] | Customer Contract Line secondary Unit of Measure, usually a measure of time. |  |
| Unit_Cost | decimal (26, 6) | [0..1] | Unit Cost for Contract Line. | You cannot edit Unit Price during a contract change when schedules exist on the contract. — You cannot edit Unit Price during a contract change when schedules exist on the contract. |
| Extended_Amount | decimal (18, 3) | [0..1] | Extended Amount for Contract Line. | You cannot edit Extended Amount during a contract change when schedules exist on the contract. — You cannot edit Extended Amount during a contract change when schedules exist on the contract. |
| Discounts_and_Premiums_Applied_Reference | Contract_Discount_Premium_AbstractObject | [0..*] | Discounts And Premiums Applied on Customer Contract Line | Your discounts cannot add up to over 100%.<br>You can only apply Discounts and Premiums to goods and services customer contract lines (except revenue only lines).<br>You can only apply Discounts and Premiums if the List Unit Price is more than zero.<br>Enter an active discount or premium within the contract date range on the line.<br>You can't change the Discounts and Premiums during a contract change when schedules exist on the contract. |
| Discount_Premium_With_Additional_Discount_Reference | Contract_Discount_Premium_AbstractObject | [0..*] | Ad Hoc Discount and Premium applied for a contract line. |  |
| Recalculate_FV_Unit_Price | boolean | [0..1] | Re-Calculate FV Unit Price |  |
| Fair_Value_Unit_Price | decimal (21, 6) | [0..1] | FV Unit Price is the value used to calculate the revenue allocation for Multi-Element arrangement contract. | You cannot edit Fair Value Unit Price during a contract change when schedules exist on the contract. — You cannot edit Fair Value Unit Price during a contract change when schedules exist on the contract. |
| Fair_Value_Extended_Amount | decimal (18, 3) | [0..1] | FV Extended Amount is FV Unit Price multiplied by the Quantity | You cannot edit Fair Value Extended Amount during a contract change when schedules exist on the contract. — You cannot edit Fair Value Extended Amount during a contract change when schedules exist on the contract. |
| List_Unit_Price | decimal (21, 6) | [0..1] | List Unit Price | You cannot edit List Unit Price during a contract change when schedules exist on the contract. — You cannot edit List Unit Price during a contract change when schedules exist on the contract.<br>List Unit Price can be enterable only if Contract Line Type is Fixed Amount or Billing Only or Subscription or Variable Amount Non Project Only. |
| List_Extended_Amount | decimal (18, 3) | [0..1] | List Extended Amount | You cannot edit List Extended Amount during a contract change when schedules exist on the contract. — You cannot edit List Extended Amount during a contract change when schedules exist on the contract.<br>List Extended Amount can be enterable only if Contract Line Type is Fixed Amount or Billing Only or Subscription or Variable Amount Non Project Only. — List Extended Amount can be enterable only if Contract Line Type is Fixed Amount or Billing Only or Subscription or Variable Amount Non Project Only. |
| Exclude_From_Calculation | boolean | [0..1] | This option may be set in order to exclude the contract line from the Revenue allocation calculation |  |
| Lower_Range_Percentage | decimal (10, 4) >0 | [0..1] | Line Level Lower Range Percentage |  |
| Upper_Range_Percentage | decimal (10, 4) >0 | [0..1] | Line Level Upper Range Percentage |  |
| Revenue_Allocation_Calculation_Basis_Reference | Revenue_Allocation_Calculation_BasisObject | [0..1] | Revenue Allocation Calculation Basis |  |
| Range_Low | decimal (26, 6) | [0..1] | Range Low is the lower range value calculated for the Revenue Allocation |  |
| Range_High | decimal (26, 6) | [0..1] | Range High is the Higher range value calculated for the Revenue Allocation |  |
| MidRange | decimal (26, 6) | [0..1] | Mid Range is the median value calculated for the Revenue Allocation |  |
| Relative_Selling_Price_Allocation | decimal (26, 6) | [0..1] | Relative Selling Price Allocation calculated based on Range Low,Range High and Mid Range values |  |
| Renewable | boolean | [0..1] | Customer Contract Line Renewable |  |
| New_Business | boolean | [0..1] | Customer Contract Line New Business |  |
| Deferred_Revenue | boolean | [0..1] | Customer Contract Line Deferred Revenue | You cannot edit Deferred Flag during a contract change when schedules exist on the contract. — You cannot edit Deferred Flag during a contract change when schedules exist on the contract.<br>A Revenue Only customer contract line must have Deferred Revenue checked. — A Revenue Only customer contract line must have Deferred Revenue checked.<br>Cannot enter a value for Revenue Override Amount unless Deferred Revenue is checked — Cannot enter a value for Revenue Override Amount unless Deferred Revenue is checked<br>Select Deferred Revenue to enable Zero Revenue. — Select Deferred Revenue to enable Zero Revenue.<br>Deferred Revenue Flag is not enterable for this Customer Contract Amendment — Deferred Revenue Flag is not enterable for this Customer Contract Amendment<br>Deferred Revenue is required for Billing Only line — Deferred Revenue is required for Billing Only line |
| Revenue_Treatment_Reference | Revenue_TreatmentObject | [0..1] | Revenue Treatment (Invoice, Deferred, or Accrued) on Customer Contract Line. | You can't change the Revenue Treatment for customer contracts with existing billing or revenue activity. — You can't enter Revenue Treatment for this Customer Contract Amendment.<br>You can't enter a value for Revenue Override Amount until you set Revenue Treatment to Accrued or Deferred. — You can't enter a value for Revenue Override Amount until you set Revenue Treatment to Accrued or Deferred.<br>You can't add Revenue Schedule Template for contract lines unless the Revenue Treatment is Deferred or Accrued. — You can't add Revenue Schedule Template for contract lines unless the Revenue Treatment is Deferred or Accrued.<br>Set Revenue Treatment to Accrued or Deferred to enable Zero Revenue. — Set Revenue Treatment to Accrued or Deferred to enable Zero Revenue.<br>Enter a valid Revenue Treatment of Invoice, Deferred, or Accrued. — Enter a valid Revenue Treatment of Invoice, Deferred, or Accrued.<br>Set Revenue Treatment for Billing Only Contract Line to Accrued or Deferred. — Set Revenue Treatment for Billing Only Contract Line to Accrued or Deferred.<br>Set Revenue Treatment for Revenue Only Contract Line to Accrued or Deferred. — Set Revenue Treatment for Revenue Only Contract Line to Accrued or Deferred. |
| Revenue_Recognition_Schedule_Template_Reference | Revenue_Recognition_Schedule_TemplateObject | [0..1] | A reference to a Revenue Recognition Schedule Template. If available, this will default from the Sales Item selected, but it can be overridden. This allows you to automatically generate Revenue Recognition Installments upon approval of the contract. | Revenue Recognition Schedule Template can only be selected if Deferred Revenue is selected. — Revenue Recognition Schedule Template can only be selected if Deferred Revenue is selected.<br>You cannot edit Revenue Recognition Schedule Template Reference during a contract change when schedules exist on the contract. — You cannot edit Revenue Recognition Schedule Template Reference during a contract change when schedules exist on the contract. |
| Billing_Template_Reference | Billing_Schedule_TemplateObject | [0..1] | The billing template for the contract line | You can't specify a billing template on an alternate customer contract.<br>You can’t edit a billing template on a contract line when the line includes a billing schedule. |
| Customer_Contract_Line_Revenue_Override_Amount | decimal (26, 6) | [0..1] | Customer Contract Line Entered Revenue Amount | You cannot edit Revenue Override Amount during a contract change when schedules exist on the contract. — You cannot edit Revenue Override Amount during a contract change when schedules exist on the contract. |
| Zero_Revenue | boolean | [0..1] | Customer Contract Line Zero Revenue Indicator | You can’t select the Zero Revenue option when schedules exist on the contract. — You can’t select the Zero Revenue option when schedules exist on the contract. |
| Allocation_Percentage | decimal (26, 6) | [0..1] | Percentage Allocation for Revenue Line when part of Bundle. |  |
| Default_Worktags_Reference | Audited_Accounting_WorktagObject | [0..*] | Customer Contract Line Default Worktags Reference | Revenue Category worktag is not valid for this transaction.<br>[worktag value] is not permitted as an allowed value for worktag type: [worktag type], because it is inactive.<br>[list of worktag types] not valid for this transaction. — The Worktags provided are not valid for this transaction<br>Select a balancing worktag for Worktags of the following type: [type]<br>[missing required worktag types on Customer Contract WWS]<br>Select the balancing worktag(s) [bw from contract line] that you deleted. You cannot remove the worktag(s) because billing or revenue recognition installments for the contract line are already processed or in process.<br>Revenue Category worktag is not valid for this transaction.<br>list of worktag types not valid for this transaction : [types] — The Worktags provided are not valid for this transaction<br>You cannot edit Worktags on contract Line during a contract change when schedules exist on the contract. — You cannot edit Worktags on contract Line during a contract change when schedules exist on the contract.<br>[invalid worktag value message]<br>Remove the balancing worktag(s) [bw from contract line]. You cannot add the worktag(s) because billing or revenue recognition installments for the contract line are already processed or in process.<br>The intercompany affiliate worktag [worktag] is invalid for header company [header company] and line company [line company]. Enter a valid header company, line company, and intercompany affiliate worktag combination.<br>The [type] is/are not available for use with the company/s: [partitionable] [company]<br>[not allowed worktag types on Customer Contract Line WWS]<br>Required worktag type(s) are missing. — Required worktag type(s) are missing.<br>Ensure you have access to the project, project plan phase, or project plan task to specify it in the Default Worktags Reference field. — Ensure you have access to the project, project plan phase, or project plan task to specify it in the Default Worktags Reference field. |
| Line_Item_Description_Override | string | [0..1] | Customer Contract Line Item Description Override |  |
| Line_Invoice_Memo | string | [0..1] | Memo for the Invoice line. This is free form text. |  |
| Line_Invoice_Memo_Override | string | [0..1] | Customer Contract Line Invoice Memo Override |  |
| Ship_To_Customer_Reference | CustomerObject | [0..*] | The ship to customer for the contract line. This field will default from header if left blank. | Enter a Ship-To Customer that is part of the Customer's Connection Map. — The ship to customer must be a part of the Customer's connection map.<br>You cannot edit Ship To Customer during a contract change when schedules exist on the contract. — You cannot edit Ship To Customer during a contract change when schedules exist on the contract. |
| Ship_To_Address_Reference | Address_ReferenceObject | [0..*] | The ship to address reference for the contract line. If there is a ship to customer on the line and this field is left blank, it will default to the ship to connection's default address. | Enter a Ship-To Customer first before entering a Ship-To Address Reference.<br>The Ship-To Address you entered is not valid for this Ship-To Customer.<br>If you did not enter a Ship-To Customer, Workday chose the default for this Sold-To Customer for you, and this Ship-To Address is not valid for that customer.<br>You cannot edit Ship To Address during a contract change when schedules exist on the contract. — You cannot edit Ship To Address during a contract change when schedules exist on the contract. |
| Ship_To_Address_Data | Address_Information_Data | [0..*] | The exact address specified in the address reference stored on the contract. | Postal Code is not a valid address component for certain countries. — Postal Code is not a valid address component for certain countries.<br>Municipality is not a valid address component for certain countries . — Municipality is not a valid address component for certain countries .<br>Region Name must be valid for the specified Country. — Region Name must be valid for the specified Country.<br>Usage Type and Use For combination must be valid for Address. — Usage Type and Use For combination must be valid for Address.<br>Second Address Line is not a valid address component for certain countries. — Second Address Line is not a valid address component for certain countries.<br>Third Address Line is not a valid address component for certain countries. — Third Address Line is not a valid address component for certain countries.<br>Fourth Address Line is not a valid address component for certain countries. — Fourth Address Line is not a valid address component for certain countries.<br>A maximum of four Submunicipalities are allowed in an address. — A maximum of four Submunicipalities are allowed in an address.<br>A maximum of four Subregions are allowed in an address. — A maximum of four Subregions are allowed in an address.<br>A maximum of four Address Lines are allowed in an address. — A maximum of four Address Lines are allowed in an address.<br>Home addresses which are not additionally used as work addresses cannot be marked as public. — Home addresses which are not additionally used as work addresses cannot be marked as public.<br>[postal code] is not a valid postal code for [region] — Postal Code must be valid for the Region.<br>Address Line 1 is not valid for this Country. — Address Line 1 is not valid for this Country.<br>Address Line 2 not Valid for this Country. — Address Line 2 not Valid for this Country.<br>Address Line 3 is not Valid for this Country. — Address Line 3 is not Valid for this Country.<br>Address Line 4 is not Valid for this Country. — Address Line 4 is not Valid for this Country.<br>Address Line 5 is not Valid for this Country. — Address Line 5 is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 7 is not Valid for this Country. — Address Line 7 is not Valid for this Country.<br>Address Line 8 is not Valid for this Country. — Address Line 8 is not Valid for this Country.<br>Address Line 9 is not Valid for this Country. — Address Line 9 is not Valid for this Country.<br>You cannot specify the same usage type more than once for an address. — You cannot specify the same usage type more than once for an address.<br>Address Line 1 - Local is not valid for this Country. — Address Line 1 - Local is not valid for this Country.<br>Municipality - Local is not a valid address component for certain countries . — Municipality - Local is not a valid address component for certain countries .<br>Address Line 2 - Local is not valid for this Country. — Address Line 2 - Local is not valid for this Country.<br>Address Line 3 - Local is not Valid for this Country. — Address Line 3 - Local is not Valid for this Country.<br>Address Line 9 - Local is not Valid for this Country. — Address Line 9 - Local is not Valid for this Country.<br>Address Line 8 - Local is not Valid for this Country. — Address Line 8 - Local is not Valid for this Country.<br>Address Line 7 - Local is not Valid for this Country. — Address Line 7 - Local is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 5 - Local is not Valid for this Country. — Address Line 5 - Local is not Valid for this Country.<br>Address Line 4 - Local is not Valid for this Country. — Address Line 4 - Local is not Valid for this Country.<br>City Subdivision 1 - Local is not a valid address component for certain countries. — City Subdivision 1 - Local is not a valid address component for certain countries.<br>City Subdivision 2 - Local is not a valid address component for certain countries. — City Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 1 - Local is not a valid address component for certain countries. — Region Subdivision 1 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 - Local is not a valid address component for certain countries. — Region Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 is not a valid address component for certain countries. — Region Subdivision 2 is not a valid address component for certain countries.<br>City Subdivision 2 is not a valid address component for certain countries. — City Subdivision 2 is not a valid address component for certain countries.<br>If one local script address field is submitted, all required local script address fields must be submitted. — If one local script address field is submitted, all required local script address fields must be submitted.<br>Address Reference is required when deleting an address — Address Reference is required when deleting an address<br>Usage Data is required unless address is being deleted — Usage Data is required unless address is being deleted<br>Country Reference is required unless address is being deleted — Country Reference is required unless address is being deleted<br>Address deletion is not supported in this web service request — Address deletion is not supported in this web service request<br>If one western script field is submitted, all required western script address fields must be submitted. — If one western script field is submitted, all required western script address fields must be submitted.<br>Use a unique Address Reference ID for each address. [ID] is already used on another address. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>You can only update addresses that belong to this customer.<br>You can't use an existing address for a new customer.<br>You can't use an existing address for a new customer request.<br>You can't use an existing address for a new prospect.<br>You can only update addresses that belong to this customer request.<br>You can only update addresses that belong to this prospect.<br>Enter a postal code in the valid format: [PostalCodeValidationMessage]<br>One or more addresses are missing a Country City reference. This field is required because the City Prompt localization is active for: [countryref].<br>Enter a Country City reference that is valid for: [countryref]. You entered this Country City reference: [countrycityref].<br>Only Address reference belonging to the Customer tied to the Customer Contact can be shared by the Customer Contact<br>International Assignment is only valid for Non-Primary Home Addresses<br>Number of Days cannot be greater than 7. — Number of Days cannot be greater than 7.<br>Number of Days is not allowed for the country specified. — Number of Days is not allowed for the country specified.<br>You must enter a Country City reference instead of a text element because the City Prompt localization is active for: [countryref]. You entered this text element: [cityattrib] [citylocalattrib].<br>You entered this Country City reference: [countrycityref]. To use this Country City reference, you must activate the City Prompt localization for: [countryref].<br>Perform either one of these actions:<br>Activate the City Prompt localization.<br>Enter a municipality instead of a Country City reference.<br>Address "[ID]" is already in use by another address (possibly on another contactable). Please choose a different Address ID. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>Second Submunicipality is not a valid address component for certain countries. — Second Submunicipality is not a valid address component for certain countries.<br>Second Subregion is not a valid address component for certain countries. — Second Subregion is not a valid address component for certain countries.<br>Subregion is not a valid address component for certain countries. — Subregion is not a valid address component for certain countries.<br>Submunicipality is not a valid address component for certain countries. — Submunicipality is not a valid address component for certain countries.<br>Specify the required missing address components for [proposedCountry]: [missingAddressComponents]<br>Specify an Address Reference that isn't already in use by another address. — Specify an Address Reference that isn't already in use by another address.<br>Existing addresses can't be future dated. Select an effective date that is on or before today, or create a new address with a future date.<br>Address [AddressReference] is not accessible to the processing user. — The Address Reference provided is not accessible to the processing user.<br>Ensure that the effective date specified in the Address Information Data matches the effective date specified in the [Add or Edit]:[Dependent Effective Date]. Alternatively, remove the effective date in the Address Information Data and reprocess the request. |
| Tax_Applicability_Reference | Tax_ApplicabilityObject | [0..1] | This is the reference id value of the tax applicability.<br>If this is blank and there invoice line has a sales item, Workday will default tax applicability from the sales item. If the invoice line has a tax code then tax applicability is required. | You cannot edit Tax Applicability during a contract change when schedules exist on the contract. — You cannot edit Tax Applicability during a contract change when schedules exist on the contract. |
| Tax_Code_Reference | Tax_CodeObject | [0..1] | This is the reference id value of the tax code.<br>If this is blank, Workday will default in the default tax code from the invoice header if there is one. If the invoice line has a tax applicability value, Workday will validate that the invoice line also has a tax code. | You cannot edit Tax Code during a contract change when schedules exist on the contract. — You cannot edit Tax Code during a contract change when schedules exist on the contract.<br>Enter a Tax Code that doesn’t include withholding tax rates. |
| Withholding_Tax_Code_Reference | Tax_CodeObject | [0..1] | Withholding Tax Code for Customer Contract Line | You cannot edit the Withholding Tax Code during a contract change for Fixed Amount – Revenue Only contract line types.<br>Enter a valid code in the Withholding Tax Code field.<br>You cannot edit the Withholding Tax Code during a contract change when schedules exist on the contract. — You cannot edit the Withholding Tax Code during a contract change when schedules exist on the contract. |
| Billable_Transaction_Tax | boolean | [0..1] | When this flag is checked, Recoverable Tax is not billed to the customer. |  |
| Billing_Schedule_From_Date | date | [0..1] | Billing Schedule Template From Date. | You can’t edit a Billing From Date for a contract line that includes a billing schedule and the contract or contract line includes a billing template. — You can’t edit a Billing From Date for a contract line that includes a billing schedule and the contract or contract line includes a billing template.<br>You cannot edit Billing Schedule From Date during a contract change when schedules exist on the contract. — You cannot edit Billing Schedule From Date during a contract change when schedules exist on the contract. |
| Billing_Schedule_To_Date | date | [0..1] | Billing Schedule Template To Date. | You cannot edit Billing Schedule To Date during a contract change when schedules exist on the contract. — You cannot edit Billing Schedule To Date during a contract change when schedules exist on the contract.<br>You can’t edit a Billing To Date for a contract line that includes a billing schedule and the contract or contract line includes a billing template. — You can’t edit a Billing To Date for a contract line that includes a billing schedule and the contract or contract line includes a billing template. |
| Line_Billing_Notes | string | [0..1] | Customer Contract Line Billing Notes |  |
| Revenue_Recognition_Line_Notes | string | [0..1] | Customer Contract Line Revenue Recognition Line Notes |  |
| Document_Status_Reference | Document_StatusObject | [0..1] | Customer Contract Line Status Override | You can't cancel the Contract Line until invoices or revenue recognition finishes processing.<br>You can't cancel the line because this customer contract has recognized deferred revenue.<br>Enter a Contract Line Amount of zero to cancel the contract line.<br>You can't terminate the contract line because either the deferred revenue balance doesn't equal to zero or the sum of the deferred revenue balance in the base currency and the adjustment amounts in the base currency doesn't equal to zero.<br>You can't terminate this contract line because the contract line amount is not equal to the billed to date amount<br>You can't complete the contract line because either the deferred revenue balance doesn't equal to zero or the sum of the deferred revenue balance in the base currency and the adjustment amounts in the base currency doesn't equal to zero.<br>Verify that you want to terminate or complete deferred revenue balances on 1 or more contract lines with a revenue override amount because your deferred revenue could become out of balance.<br>You can't complete this contract line because the contract line amount is not equal to the billed to date amount — You can't complete this contract line because the contract line amount is not equal to the billed to date amount<br>You can't cancel a contract line with a billed amount.<br>You can't complete a contract line that has available revenue recognition installments.<br>Contract Line Override Status is not enterable for Customer Contract. |
| Advanced_Usage | boolean | [0..1] | Advanced Usage is intended for contract lines that need to be processed by Subscription Management. |  |

| col1 |
|---|
| Only one worktag for each type is allowed for each document line. — Only one worktag for each type is allowed for each document line.<br>Please specify an Item or a Spend Category. — Please specify an Item or a Spend Category.<br>If Line is Renewable, a line End Date must be entered. — If Line is Renewable, a line End Date must be entered.<br>To Date must be greater than From Date. — To Date must be greater than From Date.<br>If both First and Last Installments are entered, number of installments must be greater than or equal to 3. — If both First and Last Installments are entered, number of installments must be greater than or equal to 3.<br>If either First or Last Installment is entered, number of installments must be greater than or equal to 2. — If either First or Last Installment is entered, number of installments must be greater than or equal to 2.<br>If either First or Last Installment is entered, number of installments must be greater than or equal to 2. — If either First or Last Installment is entered, number of installments must be greater than or equal to 2.<br>Contract Line Amount is not valid for Prepaid or Revenue Only Contract Lines — Contract Line Amount is not valid for Prepaid or Revenue Only Contract Lines<br>Billable Project is required for a Project Contract Line Type. — Billable Project is required for a Project Contract Line Type.<br>Renewable is invalid for Prepaid or Revenue Only contract lines. — Renewable is invalid for Prepaid or Revenue Only contract lines.<br>New Business is invalid for Prepaid or Revenue Only contract lines. — New Business is invalid for Prepaid or Revenue Only contract lines.<br>Revenue Override Amount must be empty for contract lines that are Billing Only or Variable Amount (Non-Project) — Revenue Override Amount must be empty for contract lines that are Billing Only or Variable Amount (Non-Project)<br>Project Transaction Source cannot be entered for non Project based Customer Contract Lines. — Project Transaction Source cannot be entered for non Project based Customer Contract Lines.<br>Only a Billable Project may be entered. — Only a Billable Project may be entered.<br>Cannot enter Project Worktag on Contract Line with Billable Project entered. — Cannot enter Project Worktag on Contract Line with Billable Project entered.<br>Cannot have an Employee Worktag along with a Contingent Worker Worktag for the same line. — Cannot have an Employee Worktag along with a Contingent Worker Worktag for the same line.<br>Can not use a Sales Item that is a basic worktag only as the sales item for the transaction. — Can not use a Sales Item that is a basic worktag only as the sales item for the transaction.<br>Sales Item is inactive. — Sales Item is inactive.<br>Sales Item Reference does not refer to a valid Sales Item. — Sales Item Reference does not refer to a valid Sales Item.<br>Project reference is for a project that can be used as a basic worktag only. — Project reference is for a project that can be used as a basic worktag only.<br>Can not have any combination of Project, Project Phase or Project Task worktags for the same line. — Can not have any combination of Project, Project Phase or Project Task worktags for the same line.<br>Quantity 2 can only be entered if the primary Quantity is not zero. — Quantity 2 can only be entered if the primary Quantity is not zero.<br>Unit of Measure 2 cannot be provided unless both primary Quantity and Unit of Measure are provided. — Unit of Measure 2 cannot be provided unless both primary Quantity and Unit of Measure are provided.<br>Quantity 2 is required if Unit of Measure 2 is provided. — Quantity 2 is required if Unit of Measure 2 is provided.<br>Contract Line Data contains duplicate Receivable Contract Line Reference ID's. — Contract Line Data contains duplicate Receivable Contract Line Reference ID's.<br>FV Extended Amount cannot be entered for contract line types of: Prepaid or Revenue Only — FV Extended Amount cannot be entered for contract line types of: Prepaid or Revenue Only<br>Contract Line Billing Schedule From Date must be before To Date. — Enter a Billing Schedule From Date that is earlier than the To Date.<br>Revenue override amount is invalid when contract line type is Variable Amount - Non Project because it is the billed amount that determines revenue amount for this type of contract line. — Revenue override amount is invalid when contract line type is Variable Amount - Non Project because it is the billed amount that determines revenue amount for this type of contract line.<br>For sales items that Require Fulfillment, you must enter a Line Type of Fixed Amount, Subscription, or Variable Amount – Non Project. — For sales items that Require Fulfillment, you must enter a Line Type of Fixed Amount, Subscription, or Variable Amount – Non Project.<br>Either Percentage Allocation or Revenue Override Amount can be supplied but not both. — Either Percentage Allocation or Revenue Override Amount can be supplied but not both.<br>You can't enter a value in the Quantity 2 field on a contract line where the sales item requires fulfillment. — You can't enter a value in the Quantity 2 field on a contract line where the sales item requires fulfillment.<br>Sales Item Bundle: [bundle] can't contain child items with different currencies.<br>Sales Item Bundle: [bundle] can't contain child items that are Inactive.<br>The contract lines use conflicting Percent Complete methods. All Revenue Recognition Schedule Templates must use the same Percent Complete method for contract lines containing the same Project ([project]), Transaction Source ([transaction source]), and overlapping dates.<br>The Revenue Recognition Schedule Template using the [pcm] Percent Complete method on this contract line is invalid. A contract line using the same project, transaction source, and overlapping start and end dates and assigned to a Revenue Recogntion Schedule using the [pcm2] Percent Complete Method already exists. All Percent Complete Revenue Recognition Schedule Templates for these contract lines must use the [pcm2] Percent Complete Method.<br>Referenced Original Contract Line: [original line] is not child of Original Contract [original contract]<br>Tax applicability is required when tax code has a value. — Tax applicability is required when tax code has a value.<br>You can't update the Alternate Customer Contract Line because the Original Contract Line Status is either Canceled or Terminated for: [line].<br>Clear the Zero Revenue option for line types that don't allow for revenue override. — Clear the Zero Revenue option for line types that don't allow for revenue override.<br>You can’t select the Zero Revenue option when there is an Override Amount. — You can’t select the Zero Revenue option when there is an Override Amount.<br>You must change the contract rate sheet type to match the project type. — You must change the contract rate sheet type to match the project type.<br>You can only select Billable Transaction Tax when the line type is Project Time and Expense, and the project transaction source is either Expense or Supplier Invoice.<br>You can't select the Billable Transaction Tax on the contract line, when the Only Include Non-Recoverable Tax on Billable Transactions check box isn't selected at the tenant level.<br>Unit Of Measure 2 can only be entered if the Contract Line Type is Fixed Amount or Subscription. — Unit Of Measure 2 can only be entered if the Contract Line Type is Fixed Amount or Subscription.<br>Quantity 2 can only be entered if the Contract Line Type is Fixed Amount or Subscription. — Quantity 2 can only be entered if the Contract Line Type is Fixed Amount or Subscription.<br>Contract Line Billing Schedule From Date must be before To Date. — Enter a Billing Schedule From Date that is earlier than the To Date.<br>When you have the Standard Rate Sheet selected, you can't use a contract rate sheet that contains a Project Billing Rate Sheet, a Time Definition, an Adjustment Percent, or Rate Category Members. Either clear the Standard Rate Sheet or select a different contract rate sheet.<br>You can't add Intercompany line type to this contract.<br>Revenue Category must match the Revenue Category for the Sales Item if that category is active.<br>Revenue Category must match the Revenue Category of the Contract Line.<br>Cannot use inactive Revenue Category<br>The following fields are invalid on a Recurring line on a Grid contract: Number of Installments, Regular Installment Amount, First Installment Amount, and Last Installment Amount. — The following fields are invalid on a Recurring line on a Grid contract: Number of Installments, Regular Installment Amount, First Installment Amount, and Last Installment Amount.<br>You can't specify a third party tax code in the transaction tax code reference. — You can't specify a third party tax code in the transaction tax code reference.<br>Unit Price cannot be entered for contract line types of: Prepaid, and Revenue Only — Unit Price cannot be entered for contract line types of: Prepaid, and Revenue Only<br>You can't enter a Unit of Measure for contract line types of prepaid, revenue only, or project with a nontime project transaction source. — You can't enter a Unit of Measure for contract line types of prepaid, revenue only, or project with a nontime project transaction source.<br>You can not add a contract rate sheet or use a standard rate sheet with daily rates for fixed fee or value-based contact lines.<br>You can only enter one Project Transaction Source for fixed fee or value-based contract lines with a contract rate sheet or standard rate sheet<br>You can't add a contract rate sheet or use a standard rate sheet on the contract line because a contract line with a contract rate sheet or using a standard rate sheet exists with the same project, source, and date combination on this contract:[text]<br>Specify a project for the billable project instead of a project event.<br>Specify a revenue treatment of Deferred for prepaid customer contract lines.<br>You must enable Deferred Revenue for prepaid customer contract lines.<br>Specify a date range less than 100 years for the Billing Schedule From Date and Billing Schedule To Date.<br>Specify a date range less than 100 years for the Customer Contract Line Start Date and Customer Contract Line End Date.<br>Billable Project is not valid for a non-project Contract Line type. — Billable Project is not valid for a non-project Contract Line type.<br>To specify a Phase Reference on a contract line, ensure the contract line has a line type of Project Time and Expense, Fixed Fee Project, or Value-Based Project.<br>To specify a Task Reference on a contract line, ensure the contract line has a line type of Project Time and Expense, Fixed Fee Project, or Value-Based Project.<br>Specify a different combination. The billable project, task, project transaction source, and date combination already exists for another project time and expense line on this contract. [contract]<br>Specify a different combination. The billable project, project transaction source, and date combination already exists for another project time and expense line on this contract. [contract]<br>Specify a different combination. The billable project, phase, project transaction source, and date combination already exists for another project time and expense line on this contract. [contract]<br>When you specify a project plan task on a contract line, you can't specify the task as a worktag.<br>When you specify a project plan phase on a contract line, you can't specify the phase as a worktag.<br>You can't specify a project plan phase or project plan task for a contract line that specifies a daily rate sheet.<br>Enter a Billing Schedule From Date when you use a Transaction Billing Schedule Template with Billing Frequency and Separate Billing Schedule selected. — Enter a Billing Schedule From Date when you use a Transaction Billing Schedule Template with Billing Frequency and Separate Billing Schedule selected.<br>If you select the Number of installments option, Billing Schedule From Date is required. — If you select the Number of installments option, Billing Schedule From Date is required.<br>Specify a billing schedule template where the receivable contract type is Customer Contract and the billing template type is Billing Template.<br>You can’t specify a billing template when the contract line type is Fixed Amount - Revenue Only.<br>Specify a Billing To Date on the contract or contract line. This field is required for all contract line types except Project Time and Expense and Usage when you use a billing template that generates installments with To Date.<br>If you select Use To Date, both Billing Schedule From Date and Billing Schedule To Date are required. — If you select Use To Date, both Billing Schedule From Date and Billing Schedule To Date are required.<br>Specify a Billing From Date on the contract or contract line. This field is required for all contract line types except Project Time and Expense and Usage when you use a billing template.<br>You can't enter a Quantity for contract line types of prepaid, revenue only, or project with a nontime project transaction source. — You can't enter a Quantity for contract line types of prepaid, revenue only, or project with a nontime project transaction source.<br>When the contract line type is Prepaid or Fixed Amount - Revenue Only for nonbundle lines, you must clear the FV Unit Price field. — When the contract line type is Prepaid or Fixed Amount - Revenue Only for nonbundle lines, you must clear the FV Unit Price field.<br>To set the Is Quantity per Bundle Zero field to true, ensure that the bundled customer contract lines have a line type of Fixed Amount - Revenue Only. — To set the Is Quantity per Bundle Zero field to true, ensure that the bundled customer contract lines have a line type of Fixed Amount - Revenue Only.<br>You must enter a Contract Line Amount when the Line Type is Fixed Fee Project, the line isn't canceled, and there isn't a Revenue Override Amount. — You must enter a Contract Line Amount when the Line Type is Fixed Fee Project, the line isn't canceled, and there isn't a Revenue Override Amount.<br>To use a revenue recognition schedule template with Percent Complete on the customer contract line, ensure that the contract line amount is not negative.<br>To specify a revenue recognition template with contract lines of type Project Time and Expense that have multiple project plan phases or project plan tasks, the revenue recognition method must be Transaction.<br>Specify a different combination. The specified combination of billable project, phase, and task conflicts with another fixed-fee line on this contract. [contract]<br>Specify a different combination. The specified combination of billable project and phase conflicts with another fixed-fee line on this contract. [contract]<br>Ensure that the Project Plan Phase or Project Plan Task you specify in the Worktags field is associated with the billable Project specified on the contract line.<br>You can't specify a third party tax code in the withholding tax code reference. Specify a non third party withholding tax code. — You can't specify a third party tax code in the withholding tax code reference. Specify a non third party withholding tax code.<br>Specify a task worktag that corresponds to the phases specified on the contract line.<br>Enter a positive contract line amount. When the revenue recognition schedule uses the Percent Complete recognition method, the fixed-fee contract line amounts must be positive. — Enter a positive contract line amount. When the revenue recognition schedule uses the Percent Complete recognition method, the fixed-fee contract line amounts must be positive.<br>Remove the Billing Only Customer Contract Line Reference that refers to a contract line not present in this request. — Remove the Billing Only Customer Contract Line Reference that refers to a contract line not present in this request.<br>Remove the Bundled Revenue Only Contract Line Reference that refers to a contract line not present in this request. — Remove the Bundled Revenue Only Contract Line Reference that refers to a contract line not present in this request.<br>The Billable Project field doesn't apply to contract lines with the Advanced Usage field set to true. — The Billable Project field doesn't apply to contract lines with the Advanced Usage field set to true.<br>The Advanced Usage field only applies when Subscription Management is enabled. — The Advanced Usage field only applies when Subscription Management is enabled.<br>Specify a value for the Contract Line Start Date field if the Advanced Usage field is set to true. — Specify a value for the Contract Line Start Date field if the Advanced Usage field is set to true.<br>Specify a value for the Sales Item field if the Advanced Usage field is set to true. — Specify a value for the Sales Item field if the Advanced Usage field is set to true.<br>Specify a Usage Billing Rate effective on or before the contract line Start Date if the Advanced Usage field is set to true. — Specify a Usage Billing Rate effective on or before the contract line Start Date if the Advanced Usage field is set to true.<br>Specify a value for the Contract Line End Date field if the Advanced Usage field is set to true. — Specify a value for the Contract Line End Date field if the Advanced Usage field is set to true.<br>The Advanced Usage field only applies to usage-based contract lines. — The Advanced Usage field only applies to usage-based contract lines.<br>You can't set the Advanced Usage field to true for contract lines on alternate contracts. — You can't set the Advanced Usage field to true for contract lines on alternate contracts.<br>A Project Transaction Source of Time, Expense, Supplier Invoice, or Misc. Expense is required for a Project Time and Expense contract line (exactly 1 source). — A Project Transaction Source of Time, Expense, Supplier Invoice, or Misc. Expense is required for a Project Time and Expense contract line (exactly 1 source).<br>For all contract lines with Advanced Usage set to true, ensure that you use only sales items with charge models. — For all contract lines with Advanced Usage set to true, ensure that you use only sales items with charge models.<br>When you use a revenue recognition schedule template with a revenue recognition method other than Transaction or Percent Complete, you need to specify the customer contract line start date.<br>Specify an active tax applicability.<br>Specify contract line start and end dates within the fiscal years defined for the contract line company when using a revenue recognition template with the Spread Even or Number of Days revenue recognition methods. |

## Receivable_Contract_Line_AbstractObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Receivable_Contract_Line_AbstractObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Receivable_Contract_Line_AbstractObjectID

*Part of: [Receivable_Contract_Line_AbstractObject](#receivable_contract_line_abstractobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Receivable_Contract_Line_Reference_ID, Student_Sponsor_Contract_Line_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Customer_Contract_LineObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Customer_Contract_LineObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Customer_Contract_LineObjectID

*Part of: [Customer_Contract_LineObject](#customer_contract_lineobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Receivable_Contract_Line_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Item_DescriptorObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Item_DescriptorObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Item_DescriptorObjectID

*Part of: [Item_DescriptorObject](#item_descriptorobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Catalog_Item_ID, Catalog_Load_Item_ID, Expense_Item_ID, Purchase_Item_ID, Sales_Item_ID, Supplier_Item_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Commodity_CodeObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Commodity_CodeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Commodity_CodeObjectID

*Part of: [Commodity_CodeObject](#commodity_codeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Commodity_Code_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |
| @parent_id | string | [0..1] | For types that require a parent reference, contains a unique identifier for an instance of a parent object. |  |
| @parent_type | WID, Commodity_Code_Type_ID | [0..1] | For types that require a parent reference, the unique identifier type of a parent object. |  |

## Accounting_CategoryObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Accounting_CategoryObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Accounting_CategoryObjectID

*Part of: [Accounting_CategoryObject](#accounting_categoryobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Bank_Account_ID, Customer_Category_ID, Petty_Cash_Account_ID, Receivable_Writeoff_Reason_ID, Revenue_Category_ID, Spend_Category_ID, Supplier_Category_ID, Tax_Category_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Contract_Line_TypeObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Contract_Line_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Contract_Line_TypeObjectID

*Part of: [Contract_Line_TypeObject](#contract_line_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Contract_Line_Type_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Project_AbstractObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Project_AbstractObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Project_AbstractObjectID

*Part of: [Project_AbstractObject](#project_abstractobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Project_ID, Workday_Project_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Project_Plan_PhaseObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Project_Plan_PhaseObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Project_Plan_PhaseObjectID

*Part of: [Project_Plan_PhaseObject](#project_plan_phaseobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Project_Plan_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Project_Plan_TaskObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Project_Plan_TaskObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Project_Plan_TaskObjectID

*Part of: [Project_Plan_TaskObject](#project_plan_taskobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Project_Plan_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Project_Transaction_SourceObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Project_Transaction_SourceObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Project_Transaction_SourceObjectID

*Part of: [Project_Transaction_SourceObject](#project_transaction_sourceobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Project_Transaction_Source_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Contract_Rate_SheetObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Contract_Rate_SheetObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Contract_Rate_SheetObjectID

*Part of: [Contract_Rate_SheetObject](#contract_rate_sheetobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Contract_Rate_Sheet_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Usage_Billing_RateObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Usage_Billing_RateObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Usage_Billing_RateObjectID

*Part of: [Usage_Billing_RateObject](#usage_billing_rateobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Usage_Billing_Rate_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Contract_Line_FeeObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Contract_Line_FeeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Contract_Line_FeeObjectID

*Part of: [Contract_Line_FeeObject](#contract_line_feeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Contract_Line_Fee_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Unit_of_MeasureObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Unit_of_MeasureObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Unit_of_MeasureObjectID

*Part of: [Unit_of_MeasureObject](#unit_of_measureobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, UN_CEFACT_Common_Code_ID, UOM_EDI_Code_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Contract_Discount_Premium_AbstractObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Contract_Discount_Premium_AbstractObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Contract_Discount_Premium_AbstractObjectID

*Part of: [Contract_Discount_Premium_AbstractObject](#contract_discount_premium_abstractobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Contract_Discount_and_Premium_Reference_ID, Contract_Line_Fee_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Revenue_Allocation_Calculation_BasisObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Revenue_Allocation_Calculation_BasisObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Revenue_Allocation_Calculation_BasisObjectID

*Part of: [Revenue_Allocation_Calculation_BasisObject](#revenue_allocation_calculation_basisobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Revenue_Allocation_Calculation_Basis | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Revenue_TreatmentObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Revenue_TreatmentObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Revenue_TreatmentObjectID

*Part of: [Revenue_TreatmentObject](#revenue_treatmentobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Revenue_Treatment_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Revenue_Recognition_Schedule_TemplateObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Revenue_Recognition_Schedule_TemplateObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Revenue_Recognition_Schedule_TemplateObjectID

*Part of: [Revenue_Recognition_Schedule_TemplateObject](#revenue_recognition_schedule_templateobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Revenue_Recognition_Schedule_Template_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Tax_ApplicabilityObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Tax_ApplicabilityObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Tax_ApplicabilityObjectID

*Part of: [Tax_ApplicabilityObject](#tax_applicabilityobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Tax_Applicability_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Document_StatusObject

*Part of: [Customer_Contract_Line_Data](#customer_contract_line_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Document_StatusObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Document_StatusObjectID

*Part of: [Document_StatusObject](#document_statusobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Document_Status_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Financials_Attachment_with_Category__Workday-Owned__Data

*Part of: [Customer_Contract_Data](#customer_contract_data) — A wrapper element that contains data for Financial Attachments*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Replace_All | boolean | [0..1] | Replace All boolean to replace (True) or update (False) Financial Attachment information for a Business Document. |  |
| Attachment_Data | Financials_Attachment_with_Category__Workday-Owned__Detail_Data | [0..*] | Encapsulating element containing all Business Document Attachment data. | If a file name is specified for a Financial Attachment, File Content and Content Type are required.<br>You must specify a valid File ID with reference to the Business Document<br>You must specify a File ID if the Delete flag is set to 'True' |

| col1 |
|---|
| If Delete is set to true in Attachment Data, Replace All must be set to false in Attachment Widget Data. |

## Financials_Attachment_with_Category__Workday-Owned__Detail_Data

*Part of: [Financials_Attachment_with_Category__Workday-Owned__Data](#financials_attachment_with_category__workday-owned__data) — Encapsulating element containing all Business Document Attachment data.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Content_Type | string (80) | [0..1] | Text attribute identifying Content Type of the Attachment. |  |
| @Filename | string (255) | [0..1] | Text attribute identifying Filename of the Attachment. |  |
| @Encoding | string | [0..1] | Text attribute identifying Encoding of the Attachment. |  |
| @Compressed | boolean | [0..1] | Boolean attribute identifying whether the Attachment is compressed. |  |
| @Delete | boolean | [0..1] | Set this flag to True in order to delete Financial Attachment |  |
| File_ID | string | [0..1] | Text attribute identifying a unique ID for Attachment. |  |
| File_Content | base64Binary | [0..1] | File content in binary format. |  |
| Comment | string | [0..1] | Comment |  |
| Attachment_Category_Reference | Attachment_Category__Workday_Owned_Object | [0..1] | A reference to the Attachment Category for the Attachment |  |

| col1 |
|---|
| If a file name is specified for a Financial Attachment, File Content and Content Type are required.<br>You must specify a valid File ID with reference to the Business Document<br>You must specify a File ID if the Delete flag is set to 'True' |

## Attachment_Category__Workday_Owned_Object

*Part of: [Financials_Attachment_with_Category__Workday-Owned__Detail_Data](#financials_attachment_with_category__workday-owned__detail_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Attachment_Category__Workday_Owned_ObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Attachment_Category__Workday_Owned_ObjectID

*Part of: [Attachment_Category__Workday_Owned_Object](#attachment_category__workday_owned_object) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Attachment_Category_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Application_Instance_Related_Exceptions_Data

*Part of: [Submit_Customer_Contract_Response](#submit_customer_contract_response) — Element containing Exceptions Data*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Exceptions_Data | Application_Instance_Exceptions_Data | [0..*] | Exceptions Data |  |

## Application_Instance_Exceptions_Data

*Part of: [Application_Instance_Related_Exceptions_Data](#application_instance_related_exceptions_data) — Element containing application related exceptions data*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Exception_Data | Exception_Data | [0..*] | Exception Data |  |

## Exception_Data

*Part of: [Application_Instance_Exceptions_Data](#application_instance_exceptions_data) — Exception (Errors and Warning) associated with the transaction.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Classification | string | [0..1] | Exception Classification (Error or Warning) |  |
| Message | string | [0..1] | Exception Detail |  |

## Customer_ContractReferenceEnumeration

*Part of: [Customer_ContractObjectID](#customer_contractobjectid)*

| Base Type |
|---|
| string |

## WorkerReferenceEnumeration

*Part of: [WorkerObjectID](#workerobjectid)*

| Base Type |
|---|
| string |

## CompanyReferenceEnumeration

*Part of: [CompanyObjectID](#companyobjectid)*

| Base Type |
|---|
| string |

## Sales_Item_Fair_Value_Price_ListReferenceEnumeration

*Part of: [Sales_Item_Fair_Value_Price_ListObjectID](#sales_item_fair_value_price_listobjectid)*

| Base Type |
|---|
| string |

## CurrencyReferenceEnumeration

*Part of: [CurrencyObjectID](#currencyobjectid)*

| Base Type |
|---|
| string |

## Address_ReferenceReferenceEnumeration

*Part of: [Address_ReferenceObjectID](#address_referenceobjectid)*

| Base Type |
|---|
| string |

## CountryReferenceEnumeration

*Part of: [CountryObjectID](#countryobjectid)*

| Base Type |
|---|
| string |

## Country_CityReferenceEnumeration

*Part of: [Country_CityObjectID](#country_cityobjectid)*

| Base Type |
|---|
| string |

| Base Type |
|---|
| string |

## Country_RegionReferenceEnumeration

*Part of: [Country_RegionObjectID](#country_regionobjectid)*

| Base Type |
|---|
| string |

## Communication_Usage_TypeReferenceEnumeration

*Part of: [Communication_Usage_TypeObjectID](#communication_usage_typeobjectid)*

| Base Type |
|---|
| string |

## Communication_Usage_BehaviorReferenceEnumeration

*Part of: [Communication_Usage_BehaviorObjectID](#communication_usage_behaviorobjectid)*

| Base Type |
|---|
| string |

## Communication_Usage_Behavior_TenantedReferenceEnumeration

*Part of: [Communication_Usage_Behavior_TenantedObjectID](#communication_usage_behavior_tenantedobjectid)*

| Base Type |
|---|
| string |

## Billable_EntityReferenceEnumeration

*Part of: [Billable_EntityObjectID](#billable_entityobjectid)*

| Base Type |
|---|
| string |

## CustomerReferenceEnumeration

*Part of: [CustomerObjectID](#customerobjectid)*

| Base Type |
|---|
| string |

## Customer_Contract_TypeReferenceEnumeration

*Part of: [Customer_Contract_TypeObjectID](#customer_contract_typeobjectid)*

| Base Type |
|---|
| string |

## Payment_TermsReferenceEnumeration

*Part of: [Payment_TermsObjectID](#payment_termsobjectid)*

| Base Type |
|---|
| string |

## Payment_TypeReferenceEnumeration

*Part of: [Payment_TypeObjectID](#payment_typeobjectid)*

| Base Type |
|---|
| string |

## Tax_CodeReferenceEnumeration

*Part of: [Tax_CodeObjectID](#tax_codeobjectid)*

| Base Type |
|---|
| string |

## Customer_Contract_AbstractReferenceEnumeration

*Part of: [Customer_Contract_AbstractObjectID](#customer_contract_abstractobjectid)*

| Base Type |
|---|
| string |

## Customer_Contract_AlternateReferenceEnumeration

*Part of: [Customer_Contract_AlternateObjectID](#customer_contract_alternateobjectid)*

| Base Type |
|---|
| string |

## Audited_Accounting_WorktagReferenceEnumeration

*Part of: [Audited_Accounting_WorktagObjectID](#audited_accounting_worktagobjectid)*

| Base Type |
|---|
| string |

| Base Type |
|---|
| string |

## Contract_Discount_PremiumReferenceEnumeration

*Part of: [Contract_Discount_PremiumObjectID](#contract_discount_premiumobjectid)*

| Base Type |
|---|
| string |

## RichText

*Part of: [Customer_Contract_Data](#customer_contract_data)*

| Base Type |
|---|
| string |

## Billing_Schedule_TemplateReferenceEnumeration

*Part of: [Billing_Schedule_TemplateObjectID](#billing_schedule_templateobjectid)*

| Base Type |
|---|
| string |

## Receivable_Contract_Line_AbstractReferenceEnumeration

*Part of: [Receivable_Contract_Line_AbstractObjectID](#receivable_contract_line_abstractobjectid)*

| Base Type |
|---|
| string |

## Customer_Contract_LineReferenceEnumeration

*Part of: [Customer_Contract_LineObjectID](#customer_contract_lineobjectid)*

| Base Type |
|---|
| string |

## Item_DescriptorReferenceEnumeration

*Part of: [Item_DescriptorObjectID](#item_descriptorobjectid)*

| Base Type |
|---|
| string |

## Commodity_CodeReferenceEnumeration

*Part of: [Commodity_CodeObjectID](#commodity_codeobjectid)*

| Base Type |
|---|
| string |

| Base Type |
|---|
| string |

## Accounting_CategoryReferenceEnumeration

*Part of: [Accounting_CategoryObjectID](#accounting_categoryobjectid)*

| Base Type |
|---|
| string |

## Contract_Line_TypeReferenceEnumeration

*Part of: [Contract_Line_TypeObjectID](#contract_line_typeobjectid)*

| Base Type |
|---|
| string |

## Project_AbstractReferenceEnumeration

*Part of: [Project_AbstractObjectID](#project_abstractobjectid)*

| Base Type |
|---|
| string |

## Project_Plan_PhaseReferenceEnumeration

*Part of: [Project_Plan_PhaseObjectID](#project_plan_phaseobjectid)*

| Base Type |
|---|
| string |

## Project_Plan_TaskReferenceEnumeration

*Part of: [Project_Plan_TaskObjectID](#project_plan_taskobjectid)*

| Base Type |
|---|
| string |

## Project_Transaction_SourceReferenceEnumeration

*Part of: [Project_Transaction_SourceObjectID](#project_transaction_sourceobjectid)*

| Base Type |
|---|
| string |

## Contract_Rate_SheetReferenceEnumeration

*Part of: [Contract_Rate_SheetObjectID](#contract_rate_sheetobjectid)*

| Base Type |
|---|
| string |

## Usage_Billing_RateReferenceEnumeration

*Part of: [Usage_Billing_RateObjectID](#usage_billing_rateobjectid)*

| Base Type |
|---|
| string |

## Contract_Line_FeeReferenceEnumeration

*Part of: [Contract_Line_FeeObjectID](#contract_line_feeobjectid)*

| Base Type |
|---|
| string |

## Unit_of_MeasureReferenceEnumeration

*Part of: [Unit_of_MeasureObjectID](#unit_of_measureobjectid)*

| Base Type |
|---|
| string |

## Contract_Discount_Premium_AbstractReferenceEnumeration

*Part of: [Contract_Discount_Premium_AbstractObjectID](#contract_discount_premium_abstractobjectid)*

| Base Type |
|---|
| string |

## Revenue_Allocation_Calculation_BasisReferenceEnumeration

*Part of: [Revenue_Allocation_Calculation_BasisObjectID](#revenue_allocation_calculation_basisobjectid)*

| Base Type |
|---|
| string |

## Revenue_TreatmentReferenceEnumeration

*Part of: [Revenue_TreatmentObjectID](#revenue_treatmentobjectid)*

| Base Type |
|---|
| string |

## Revenue_Recognition_Schedule_TemplateReferenceEnumeration

*Part of: [Revenue_Recognition_Schedule_TemplateObjectID](#revenue_recognition_schedule_templateobjectid)*

| Base Type |
|---|
| string |

## Tax_ApplicabilityReferenceEnumeration

*Part of: [Tax_ApplicabilityObjectID](#tax_applicabilityobjectid)*

| Base Type |
|---|
| string |

## Document_StatusReferenceEnumeration

*Part of: [Document_StatusObjectID](#document_statusobjectid)*

| Base Type |
|---|
| string |

## Attachment_Category__Workday_Owned_ReferenceEnumeration

*Part of: [Attachment_Category__Workday_Owned_ObjectID](#attachment_category__workday_owned_objectid)*

| Base Type |
|---|
| string |
