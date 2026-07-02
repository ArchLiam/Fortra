# Submit_Billing_Schedule — Workday Revenue Management API (v46.1)

> **Operation:** `Submit_Billing_Schedule`  
> **Purpose (per SC-3143):** Billing Schedule Data  
> **Source:** https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Submit_Billing_Schedule.html  
> **Schema:** [WSDL](https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Revenue_Management.wsdl) · [XSD](https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Revenue_Management.xsd)  
> **API version:** v46.1 (Workday Community public docs)  
> **Extracted:** 2026-06-01 — deterministic parse of the source HTML (fields + nested per-field validation rules; lossless).  
> **Data types documented:** 148 (22 primary, 84 reference, 42 enumeration)

## Data type index

| # | Data type | Category |
|---|---|---|
| 1 | [Submit_Billing_Schedule_Request](#submit_billing_schedule_request) | primary |
| 2 | [Submit_Billing_Schedule_Response](#submit_billing_schedule_response) | primary |
| 3 | [Billing_ScheduleObject](#billing_scheduleobject) | reference |
| 4 | [Billing_ScheduleObjectID](#billing_scheduleobjectid) | reference |
| 5 | [Financials_Business_Process_Parameters](#financials_business_process_parameters) | primary |
| 6 | [Business_Process_Comment_Data](#business_process_comment_data) | primary |
| 7 | [WorkerObject](#workerobject) | reference |
| 8 | [WorkerObjectID](#workerobjectid) | reference |
| 9 | [Billing_Schedule_Data](#billing_schedule_data) | primary |
| 10 | [Billing_TypeObject](#billing_typeobject) | reference |
| 11 | [Billing_TypeObjectID](#billing_typeobjectid) | reference |
| 12 | [Letter_of_Credit_Draw_IDObject](#letter_of_credit_draw_idobject) | reference |
| 13 | [Letter_of_Credit_Draw_IDObjectID](#letter_of_credit_draw_idobjectid) | reference |
| 14 | [Document_StatusObject](#document_statusobject) | reference |
| 15 | [Document_StatusObjectID](#document_statusobjectid) | reference |
| 16 | [CurrencyObject](#currencyobject) | reference |
| 17 | [CurrencyObjectID](#currencyobjectid) | reference |
| 18 | [CompanyObject](#companyobject) | reference |
| 19 | [CompanyObjectID](#companyobjectid) | reference |
| 20 | [Billable_EntityObject](#billable_entityobject) | reference |
| 21 | [Billable_EntityObjectID](#billable_entityobjectid) | reference |
| 22 | [Address_ReferenceObject](#address_referenceobject) | reference |
| 23 | [Address_ReferenceObjectID](#address_referenceobjectid) | reference |
| 24 | [Address_Information_Data](#address_information_data) | primary |
| 25 | [CountryObject](#countryobject) | reference |
| 26 | [CountryObjectID](#countryobjectid) | reference |
| 27 | [Address_Line_Information_Data](#address_line_information_data) | primary |
| 28 | [Country_CityObject](#country_cityobject) | reference |
| 29 | [Country_CityObjectID](#country_cityobjectid) | reference |
| 30 | [Submunicipality_Information_Data](#submunicipality_information_data) | primary |
| 31 | [Country_RegionObject](#country_regionobject) | reference |
| 32 | [Country_RegionObjectID](#country_regionobjectid) | reference |
| 33 | [Subregion_Information_Data](#subregion_information_data) | primary |
| 34 | [Communication_Method_Usage_Information_Data](#communication_method_usage_information_data) | primary |
| 35 | [Communication_Usage_Type_Data](#communication_usage_type_data) | primary |
| 36 | [Communication_Usage_TypeObject](#communication_usage_typeobject) | reference |
| 37 | [Communication_Usage_TypeObjectID](#communication_usage_typeobjectid) | reference |
| 38 | [Communication_Usage_BehaviorObject](#communication_usage_behaviorobject) | reference |
| 39 | [Communication_Usage_BehaviorObjectID](#communication_usage_behaviorobjectid) | reference |
| 40 | [Communication_Usage_Behavior_TenantedObject](#communication_usage_behavior_tenantedobject) | reference |
| 41 | [Communication_Usage_Behavior_TenantedObjectID](#communication_usage_behavior_tenantedobjectid) | reference |
| 42 | [Business_Entity_ContactObject](#business_entity_contactobject) | reference |
| 43 | [Business_Entity_ContactObjectID](#business_entity_contactobjectid) | reference |
| 44 | [Schedule_Distribution_MethodObject](#schedule_distribution_methodobject) | reference |
| 45 | [Schedule_Distribution_MethodObjectID](#schedule_distribution_methodobjectid) | reference |
| 46 | [Frequency_BehaviorObject](#frequency_behaviorobject) | reference |
| 47 | [Frequency_BehaviorObjectID](#frequency_behaviorobjectid) | reference |
| 48 | [Billing_PeriodObject](#billing_periodobject) | reference |
| 49 | [Billing_PeriodObjectID](#billing_periodobjectid) | reference |
| 50 | [Proration_MethodObject](#proration_methodobject) | reference |
| 51 | [Proration_MethodObjectID](#proration_methodobjectid) | reference |
| 52 | [Day_of_the_WeekObject](#day_of_the_weekobject) | reference |
| 53 | [Day_of_the_WeekObjectID](#day_of_the_weekobjectid) | reference |
| 54 | [Schedule_TypeObject](#schedule_typeobject) | reference |
| 55 | [Schedule_TypeObjectID](#schedule_typeobjectid) | reference |
| 56 | [Milestone_AbstractObject](#milestone_abstractobject) | reference |
| 57 | [Milestone_AbstractObjectID](#milestone_abstractobjectid) | reference |
| 58 | [Billable_Transaction_Attachment_TypeObject](#billable_transaction_attachment_typeobject) | reference |
| 59 | [Billable_Transaction_Attachment_TypeObjectID](#billable_transaction_attachment_typeobjectid) | reference |
| 60 | [Project_Invoice_Summary_DefinitionObject](#project_invoice_summary_definitionobject) | reference |
| 61 | [Project_Invoice_Summary_DefinitionObjectID](#project_invoice_summary_definitionobjectid) | reference |
| 62 | [Billing_CycleObject](#billing_cycleobject) | reference |
| 63 | [Billing_CycleObjectID](#billing_cycleobjectid) | reference |
| 64 | [Payment_TermsObject](#payment_termsobject) | reference |
| 65 | [Payment_TermsObjectID](#payment_termsobjectid) | reference |
| 66 | [Payment_TypeObject](#payment_typeobject) | reference |
| 67 | [Payment_TypeObjectID](#payment_typeobjectid) | reference |
| 68 | [Invoice_TypeObject](#invoice_typeobject) | reference |
| 69 | [Invoice_TypeObjectID](#invoice_typeobjectid) | reference |
| 70 | [Customer_Invoice_TypeObject](#customer_invoice_typeobject) | reference |
| 71 | [Customer_Invoice_TypeObjectID](#customer_invoice_typeobjectid) | reference |
| 72 | [Document_Delivery_TypeObject](#document_delivery_typeobject) | reference |
| 73 | [Document_Delivery_TypeObjectID](#document_delivery_typeobjectid) | reference |
| 74 | [Interest_and_Late_Fee_Override_WWS_Data](#interest_and_late_fee_override_wws_data) | primary |
| 75 | [Interest_Rate_RuleObject](#interest_rate_ruleobject) | reference |
| 76 | [Interest_Rate_RuleObjectID](#interest_rate_ruleobjectid) | reference |
| 77 | [Late_Fee_RuleObject](#late_fee_ruleobject) | reference |
| 78 | [Late_Fee_RuleObjectID](#late_fee_ruleobjectid) | reference |
| 79 | [Receivable_Contract_Line_AbstractObject](#receivable_contract_line_abstractobject) | reference |
| 80 | [Receivable_Contract_Line_AbstractObjectID](#receivable_contract_line_abstractobjectid) | reference |
| 81 | [Billing_Installment_Data](#billing_installment_data) | primary |
| 82 | [Billing_InstallmentObject](#billing_installmentobject) | reference |
| 83 | [Billing_InstallmentObjectID](#billing_installmentobjectid) | reference |
| 84 | [Billing_Installment_Line_Data](#billing_installment_line_data) | primary |
| 85 | [Unit_of_MeasureObject](#unit_of_measureobject) | reference |
| 86 | [Unit_of_MeasureObjectID](#unit_of_measureobjectid) | reference |
| 87 | [Tax_ApplicabilityObject](#tax_applicabilityobject) | reference |
| 88 | [Tax_ApplicabilityObjectID](#tax_applicabilityobjectid) | reference |
| 89 | [Tax_CodeObject](#tax_codeobject) | reference |
| 90 | [Tax_CodeObjectID](#tax_codeobjectid) | reference |
| 91 | [Audited_Accounting_WorktagObject](#audited_accounting_worktagobject) | reference |
| 92 | [Audited_Accounting_WorktagObjectID](#audited_accounting_worktagobjectid) | reference |
| 93 | [Customer_Contract_Schedule_Installment_Schedule_Data](#customer_contract_schedule_installment_schedule_data) | primary |
| 94 | [Customer_Installment_ItemObject](#customer_installment_itemobject) | reference |
| 95 | [Customer_Installment_ItemObjectID](#customer_installment_itemobjectid) | reference |
| 96 | [Retention_Terms_Data](#retention_terms_data) | primary |
| 97 | [Prepaid_Installment_and_Mapping_Data](#prepaid_installment_and_mapping_data) | primary |
| 98 | [Prepaid_Installment_and_MappingObject](#prepaid_installment_and_mappingobject) | reference |
| 99 | [Prepaid_Installment_and_MappingObjectID](#prepaid_installment_and_mappingobjectid) | reference |
| 100 | [Prepaid_Mapping_Data](#prepaid_mapping_data) | primary |
| 101 | [Prepaid_MappingObject](#prepaid_mappingobject) | reference |
| 102 | [Prepaid_MappingObjectID](#prepaid_mappingobjectid) | reference |
| 103 | [Prepaid_Installment_Data](#prepaid_installment_data) | primary |
| 104 | [Application_Instance_Related_Exceptions_Data](#application_instance_related_exceptions_data) | primary |
| 105 | [Application_Instance_Exceptions_Data](#application_instance_exceptions_data) | primary |
| 106 | [Exception_Data](#exception_data) | primary |
| 107 | [Billing_ScheduleReferenceEnumeration](#billing_schedulereferenceenumeration) | enumeration |
| 108 | [WorkerReferenceEnumeration](#workerreferenceenumeration) | enumeration |
| 109 | [Billing_TypeReferenceEnumeration](#billing_typereferenceenumeration) | enumeration |
| 110 | [Letter_of_Credit_Draw_IDReferenceEnumeration](#letter_of_credit_draw_idreferenceenumeration) | enumeration |
| 111 | [Document_StatusReferenceEnumeration](#document_statusreferenceenumeration) | enumeration |
| 112 | [CurrencyReferenceEnumeration](#currencyreferenceenumeration) | enumeration |
| 113 | [CompanyReferenceEnumeration](#companyreferenceenumeration) | enumeration |
| 114 | [Billable_EntityReferenceEnumeration](#billable_entityreferenceenumeration) | enumeration |
| 115 | [Address_ReferenceReferenceEnumeration](#address_referencereferenceenumeration) | enumeration |
| 116 | [CountryReferenceEnumeration](#countryreferenceenumeration) | enumeration |
| 117 | [Country_CityReferenceEnumeration](#country_cityreferenceenumeration) | enumeration |
| 118 | [Country_RegionReferenceEnumeration](#country_regionreferenceenumeration) | enumeration |
| 119 | [Communication_Usage_TypeReferenceEnumeration](#communication_usage_typereferenceenumeration) | enumeration |
| 120 | [Communication_Usage_BehaviorReferenceEnumeration](#communication_usage_behaviorreferenceenumeration) | enumeration |
| 121 | [Communication_Usage_Behavior_TenantedReferenceEnumeration](#communication_usage_behavior_tenantedreferenceenumeration) | enumeration |
| 122 | [Business_Entity_ContactReferenceEnumeration](#business_entity_contactreferenceenumeration) | enumeration |
| 123 | [Schedule_Distribution_MethodReferenceEnumeration](#schedule_distribution_methodreferenceenumeration) | enumeration |
| 124 | [Frequency_BehaviorReferenceEnumeration](#frequency_behaviorreferenceenumeration) | enumeration |
| 125 | [Billing_PeriodReferenceEnumeration](#billing_periodreferenceenumeration) | enumeration |
| 126 | [Proration_MethodReferenceEnumeration](#proration_methodreferenceenumeration) | enumeration |
| 127 | [Day_of_the_WeekReferenceEnumeration](#day_of_the_weekreferenceenumeration) | enumeration |
| 128 | [Schedule_TypeReferenceEnumeration](#schedule_typereferenceenumeration) | enumeration |
| 129 | [Milestone_AbstractReferenceEnumeration](#milestone_abstractreferenceenumeration) | enumeration |
| 130 | [Billable_Transaction_Attachment_TypeReferenceEnumeration](#billable_transaction_attachment_typereferenceenumeration) | enumeration |
| 131 | [Project_Invoice_Summary_DefinitionReferenceEnumeration](#project_invoice_summary_definitionreferenceenumeration) | enumeration |
| 132 | [Billing_CycleReferenceEnumeration](#billing_cyclereferenceenumeration) | enumeration |
| 133 | [Payment_TermsReferenceEnumeration](#payment_termsreferenceenumeration) | enumeration |
| 134 | [Payment_TypeReferenceEnumeration](#payment_typereferenceenumeration) | enumeration |
| 135 | [Invoice_TypeReferenceEnumeration](#invoice_typereferenceenumeration) | enumeration |
| 136 | [Customer_Invoice_TypeReferenceEnumeration](#customer_invoice_typereferenceenumeration) | enumeration |
| 137 | [Document_Delivery_TypeReferenceEnumeration](#document_delivery_typereferenceenumeration) | enumeration |
| 138 | [Interest_Rate_RuleReferenceEnumeration](#interest_rate_rulereferenceenumeration) | enumeration |
| 139 | [Late_Fee_RuleReferenceEnumeration](#late_fee_rulereferenceenumeration) | enumeration |
| 140 | [Receivable_Contract_Line_AbstractReferenceEnumeration](#receivable_contract_line_abstractreferenceenumeration) | enumeration |
| 141 | [Billing_InstallmentReferenceEnumeration](#billing_installmentreferenceenumeration) | enumeration |
| 142 | [Unit_of_MeasureReferenceEnumeration](#unit_of_measurereferenceenumeration) | enumeration |
| 143 | [Tax_ApplicabilityReferenceEnumeration](#tax_applicabilityreferenceenumeration) | enumeration |
| 144 | [Tax_CodeReferenceEnumeration](#tax_codereferenceenumeration) | enumeration |
| 145 | [Audited_Accounting_WorktagReferenceEnumeration](#audited_accounting_worktagreferenceenumeration) | enumeration |
| 146 | [Customer_Installment_ItemReferenceEnumeration](#customer_installment_itemreferenceenumeration) | enumeration |
| 147 | [Prepaid_Installment_and_MappingReferenceEnumeration](#prepaid_installment_and_mappingreferenceenumeration) | enumeration |
| 148 | [Prepaid_MappingReferenceEnumeration](#prepaid_mappingreferenceenumeration) | enumeration |

---

## Submit_Billing_Schedule_Request

*Element containing Billing Schedule reference for update and all Billing Schedule data items*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @version | string | [0..1] | Web Service version |  |
| @Add_Only | boolean | [0..1] | Add Only Flag. Indicates that the service is an add only, not an update. |  |
| Billing_Schedule_Reference | Billing_ScheduleObject | [0..1] | Reference to an existing Billing Schedule for update only purposes. | Cannot update a Canceled schedule. |
| Business_Processing_Parameters | Financials_Business_Process_Parameters | [0..1] | Business Process Parameters provide the ability to auto-submit to the business process. |  |
| Billing_Schedule_Data | Billing_Schedule_Data | [1..1] | Billing Schedule Data | Please include all existing contract lines when adding a contract line to the schedule. — Contract Lines may be added to the schedule, but cannot be removed.<br>Please set the Method to Custom if you are adding or updating installments. — Cannot add or update an installment if the schedule Method is not Custom.<br>Cannot add or update installments and also request to Generate Installments.<br>Start Date must be before End Date.<br>Billing Frequency is required unless Billing Method is Custom.<br>Schedule Start Date can't be changed with completed installments.<br>Schedule Number of Installments can't be less than the number of Installments already completed or in progress.<br>Frequency Behavior can't be changed with already completed Installments.<br>End Date can't be before the date of completed installments or installments in progress.<br>There must be at least 1 installment to submit the Billing Schedule.<br>The line's currency does not match schedule's currency.<br>You can't create a billing schedule when a change request is in process for the contract.<br>An installment billing schedule with a cost reimbursable award line must have a Prepaid schedule type.<br>Award billing schedules with prepaid schedule types can only have cost-reimbursable award lines.<br>When billing method is not Custom, then From Date and either Number of Installments or To Date are required.<br>You can't select Day of the Month with the Weekly frequency.<br>You must enter a From Date when you select a Billing Frequency.<br>Enter Prepaid Billing as the Schedule Type in order to add a Billing Limit.<br>Enter a billing limit that doesn't exceed the [billing limit label] on the award header.<br>You can only use Automatically Regenerate Installments and Automatically Submit Schedule via Contract Amendment flags for Spread Even billing schedule type.<br>Billing Schedules with Award Lines don't support Automatically Regenerate Installments or Automatically Submit Schedule via Contract Amendment flags.<br>You can’t use intercompany contract lines with this billing schedule web service.<br>Include Tax on Prepaid isn’t valid for Award Lines.<br>You can't change the Include Tax on Prepaid for Billing Schedule with noncanceled Invoices.<br>Include Tax on Prepaid is valid only if you select a prepaid schedule type.<br>You can only add the [Award Task Reference ID] on award contract lines.<br>You cannot assign [Award Task Reference ID] as a milestone as it is associated with another award line that does not belong to this billing schedule. Change the Receivable Contract Line ID or add the associated award line to this billing schedule.<br>You can't use the award task as a billing milestone when the billing type is a Transaction. To use the award task as a billing milestone, change the [Billing Type ID] to an Installment.<br>To add the [Award Task Reference ID] as a milestone, enable the billing milestone field.<br>To enable Automatically Submit Schedule via Contract Amendment, you must also enable Automatically Regenerate Installments.<br>Prepaid mapping with the same customer contract lines and dates already exists for [prepaid line]. Either select different customer contract lines or change the dates for the existing customer contract lines.<br>You can only select prepaid mappings and prepaid installments when the schedule type is enabled for Consolidated Billing.<br>You can only select customer contract lines with the same billing type on the billing schedule. — You can only select customer contract lines with the same billing type on the billing schedule.<br>One and only one option may be chosen from: Use From Date, Use To Date, Day of Month, or Day of Week.<br>You can’t set Billed in Arrears as True when the schedule type is enabled for Consolidated Billing.<br>You can only specify Custom or Spread Even as billing method when the schedule type is enabled for Consolidated Billing.<br>If Billing Type is Transaction and Billing Frequency is selected, one and only one option may be chosen for: Use From Date, Use To Date, Day of Month, Day of Week.<br>Billed in Arrears cannot be selected unless the Billing Type is Transaction.<br>You can't specify a Day of Month when the billing frequency is Calendar Week or Weekly when the schedule type has consolidated billing enabled.<br>A From Date must be entered when the Invoice Date Option is Use From Date.<br>You can only specify a Day of Week when the billing frequency is Weekly or Calendar Weekly when the schedule type has consolidated billing enabled.<br>You can only specify more than 1 billing type when the schedule type has consolidated billing enabled.<br>You can only select Day of Week with Transaction Billing Type.<br>You can’t specify a Use To Date when the schedule type is enabled for Consolidated Billing.<br>Schedule Type must be active and enabled for Billing.<br>You can only specify a Billing Period when the schedule type has consolidated billing enabled and the billing method specified is spread even.<br>If Invoice Uses To Date is entered, To Date must be entered.<br>You can’t specify these billing frequencies unless the schedule type has consolidated billing enabled: Calendar Month, Calendar Quarter, Calendar Week, Calendar Year.<br>You can only specify a Recurring Invoice Day when the schedule type is enabled for Consolidated Billing.<br>You can’t add award lines when the schedule type is enabled for Consolidated Billing.<br>Enter a number between 1 and 31 for Recurring Invoice Day.<br>Select Transaction type Billing Method when Billing Type is Transaction.<br>You can’t specify milestones when the schedule type is enabled for Consolidated Billing.<br>You can only specify installment recurrence when the schedule type has consolidated billing enabled, the billing method is Spread Even, and the frequency is Calendar Month, Calendar Week, Monthly, or Weekly.<br>You must include frequency and date parameters when you select the Recurring - Fixed Term contract line type.<br>You can’t specify retention terms when the schedule type has consolidated billing enabled.<br>You can only select Day of Week with Weekly frequency.<br>If Billing method is Custom, one and only one option may be chosen for: Use From Date, Use To Date, Use Number of Days before Start Date. If Billing Method is not Custom, one and only one option must be chosen for: Use From Date, Use To Date, Use Number of Days before Start Date.<br>Enter a number between 1 and 31 for Day of Month.<br>To create the billing schedule, specify contract lines with the same Company and Bill-To Customer as the header.<br>To enable prorated billing, specify 1 of these billing frequencies: Calendar Month, Calendar Quarter, or Calendar Week.<br>You can only specify proration when the schedule type has consolidated billing enabled.<br>To enable prorated billing, specify Spread Even for the Schedule Distribution Method.<br>Specify different installment criteria. The total number of installments must be less than [max].<br>To submit the billing schedule with a project transaction summarization definition, specify Transaction as the Billing Type. You can't have a project transaction summarization definition on an installment billing schedule.<br>Leave the From Date and To Date fields blank when you specify Transaction as the billing type.<br>To create the billing schedule, specify contract lines with the same Company and Bill-To Customer as the header.<br>You can only specify Invoice Prepaid Installments with Other Transaction Types when the schedule type is enabled for consolidated billing.<br>To submit this invoice delivery type override to the billing schedule, make sure that the billing schedule is for a customer contract.<br>To change Invoice Prepaid Installments with Other Transaction Types, first invoice the prepaid installments on the proposal and approve them on the customer invoice.<br>Leave the Billing Limit field blank when you specify a Summary Reimbursable schedule type.<br>Specify a Summary Reimbursable schedule type and only summary reimbursable award lines for a summary reimbursable billing schedule.<br>Leave the Retention Terms Data fields blank when you specify a Summary Reimbursable schedule type.<br>Leave the Milestone field blank when you specify a Summary Reimbursable schedule type.<br>Leave the Schedule On Hold field blank when you specify a Summary Reimbursable schedule type.<br>You can't specify a Summary Reimbursable schedule type on this web service version. Specify a schedule type that's not Summary Reimbursable or use web service version v39.0 or higher.<br>You can only select customer contract lines with the same billing type on the billing schedule. — You can only select customer contract lines with the same billing type on the billing schedule.<br>Specify draw IDs only on award lines for awards that contain a letter of credit. — Specify draw IDs only on award lines for awards that contain a letter of credit.<br>There's a Record Letter of Credit Draw Down Event business process for this award currently in progress. Wait for the process to complete before changing the Draw ID. — There's a Record Letter of Credit Draw Down Event business process for this award currently in progress. Wait for the process to complete before changing the Draw ID.<br>This statutory invoice type isn't valid for the specified company. Specify a statutory invoice type for the customer contract that's Active, that matches the country for the company, and that has a Statutory Invoice Type Usage of Customer Invoices. Workday doesn't support statutory invoice types on award contracts.<br>These prepaid installments have a status of Complete, In Progress, Credited or Canceled, and can't be deleted: [Installments]<br>This frequency is not valid for an award billing schedule: [frequency]<br>To specify this project plan task in the Milestone Reference field, ensure that you have access to the project.<br>For Transaction schedules, you can’t specify the Number of Installments.<br>Specify either the To Date or the Number of Installments but not both.<br>Enter a date range less than 100 years for the Billing From Date and Billing To Date. — Enter a date range less than 100 years for the Billing From Date and Billing To Date.<br>Specify a valid proration method. You can't specify a proration method value of 30 Day Month or By Calendar Month for weekly or calendar week billing frequencies.<br>You can only specify a proration method when the Billing Method value is Spread Even and the Schedule Type value is Consolidated Billing.<br>Specify only 1 proration method at a time. |

| col1 |
|---|
| Add Only is true, but the Billing Schedule already exists. |

## Submit_Billing_Schedule_Response

*Element containing Submit Billing Schedule Response Data*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @version | string | [0..1] | Web Service version |  |
| Billing_Schedule_Reference | Billing_ScheduleObject | [0..1] | Reference to an existing Billing Schedule. |  |
| Exceptions_Response_Data | Application_Instance_Related_Exceptions_Data | [0..*] | Application Instance Related Exceptions Response Data. |  |

## Billing_ScheduleObject

*Part of: [Submit_Billing_Schedule_Request](#submit_billing_schedule_request), [Submit_Billing_Schedule_Response](#submit_billing_schedule_response)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Billing_ScheduleObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Billing_ScheduleObjectID

*Part of: [Billing_ScheduleObject](#billing_scheduleobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Billing_Schedule_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Financials_Business_Process_Parameters

*Part of: [Submit_Billing_Schedule_Request](#submit_billing_schedule_request) — Contains data for business processing*

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

*Part of: [Business_Process_Comment_Data](#business_process_comment_data)*

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

## Billing_Schedule_Data

*Part of: [Submit_Billing_Schedule_Request](#submit_billing_schedule_request) — Element containing Billing Schedule data*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Billing_Schedule_Reference_ID | string | [0..1] | Billing Schedule Reference ID. This is the unique Billing Schedule identifier. | Invalid ID value. |
| Generate_Installments | boolean | [0..1] | Generate Installments flag. The service will generate billing installments if this is true. You cannot generate installments if using a Custom schedule distribution method. | You cannot generate installments if using a Custom schedule. |
| Submit | boolean | [0..1] | Submit flag. The service will attempt to submit the schedule if this is on. |  |
| Billing_Type_Reference | Billing_TypeObject | [0..*] | Reference element representing the Billing Type. |  |
| Letter_of_Credit_Draw_ID_Reference | Letter_of_Credit_Draw_IDObject | [0..1] | Reference element representing the Letter of Credit Draw ID. |  |
| Schedule_Status_Reference | Document_StatusObject | [0..*] | Reference element representing the schedule status. |  |
| Currency_Reference | CurrencyObject | [1..1] | Reference element representing the schedule currency. | Cannot change the Currency of an existing Billing Schedule. — Cannot change the Currency of an existing Billing Schedule.<br>Currency Conversion Rates between currency and company's default currency are not defined. — Currency Conversion Rates between currency and company's default currency are not defined.<br>Currency entered is not listed as an Accepted Currency by Customer. — Currency entered is not listed as an Accepted Currency by Customer. |
| Company_Reference | CompanyObject | [1..1] | Reference element representing the schedule company. | If any line is linked to the schedule, the company may not be changed. |
| Bill-To_Customer_Reference | Billable_EntityObject | [1..1] | Reference element representing the Bill To Customer. | If any contract line is linked to the schedule, the customer may not be changed. |
| Bill_To_Address_Reference | Address_ReferenceObject | [0..1] | Bill to address for the billing schedule header. | Enter a valid Bill-To Address for this customer. |
| Bill_To_Address_Data | Address_Information_Data | [0..*] | Address information | Postal Code is not a valid address component for certain countries. — Postal Code is not a valid address component for certain countries.<br>Municipality is not a valid address component for certain countries . — Municipality is not a valid address component for certain countries .<br>Region Name must be valid for the specified Country. — Region Name must be valid for the specified Country.<br>Usage Type and Use For combination must be valid for Address. — Usage Type and Use For combination must be valid for Address.<br>Second Address Line is not a valid address component for certain countries. — Second Address Line is not a valid address component for certain countries.<br>Third Address Line is not a valid address component for certain countries. — Third Address Line is not a valid address component for certain countries.<br>Fourth Address Line is not a valid address component for certain countries. — Fourth Address Line is not a valid address component for certain countries.<br>A maximum of four Submunicipalities are allowed in an address. — A maximum of four Submunicipalities are allowed in an address.<br>A maximum of four Subregions are allowed in an address. — A maximum of four Subregions are allowed in an address.<br>A maximum of four Address Lines are allowed in an address. — A maximum of four Address Lines are allowed in an address.<br>Home addresses which are not additionally used as work addresses cannot be marked as public. — Home addresses which are not additionally used as work addresses cannot be marked as public.<br>[postal code] is not a valid postal code for [region] — Postal Code must be valid for the Region.<br>Address Line 1 is not valid for this Country. — Address Line 1 is not valid for this Country.<br>Address Line 2 not Valid for this Country. — Address Line 2 not Valid for this Country.<br>Address Line 3 is not Valid for this Country. — Address Line 3 is not Valid for this Country.<br>Address Line 4 is not Valid for this Country. — Address Line 4 is not Valid for this Country.<br>Address Line 5 is not Valid for this Country. — Address Line 5 is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 7 is not Valid for this Country. — Address Line 7 is not Valid for this Country.<br>Address Line 8 is not Valid for this Country. — Address Line 8 is not Valid for this Country.<br>Address Line 9 is not Valid for this Country. — Address Line 9 is not Valid for this Country.<br>You cannot specify the same usage type more than once for an address. — You cannot specify the same usage type more than once for an address.<br>Address Line 1 - Local is not valid for this Country. — Address Line 1 - Local is not valid for this Country.<br>Municipality - Local is not a valid address component for certain countries . — Municipality - Local is not a valid address component for certain countries .<br>Address Line 2 - Local is not valid for this Country. — Address Line 2 - Local is not valid for this Country.<br>Address Line 3 - Local is not Valid for this Country. — Address Line 3 - Local is not Valid for this Country.<br>Address Line 9 - Local is not Valid for this Country. — Address Line 9 - Local is not Valid for this Country.<br>Address Line 8 - Local is not Valid for this Country. — Address Line 8 - Local is not Valid for this Country.<br>Address Line 7 - Local is not Valid for this Country. — Address Line 7 - Local is not Valid for this Country.<br>Address Line 6 is not Valid for this Country. — Address Line 6 is not Valid for this Country.<br>Address Line 5 - Local is not Valid for this Country. — Address Line 5 - Local is not Valid for this Country.<br>Address Line 4 - Local is not Valid for this Country. — Address Line 4 - Local is not Valid for this Country.<br>City Subdivision 1 - Local is not a valid address component for certain countries. — City Subdivision 1 - Local is not a valid address component for certain countries.<br>City Subdivision 2 - Local is not a valid address component for certain countries. — City Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 1 - Local is not a valid address component for certain countries. — Region Subdivision 1 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 - Local is not a valid address component for certain countries. — Region Subdivision 2 - Local is not a valid address component for certain countries.<br>Region Subdivision 2 is not a valid address component for certain countries. — Region Subdivision 2 is not a valid address component for certain countries.<br>City Subdivision 2 is not a valid address component for certain countries. — City Subdivision 2 is not a valid address component for certain countries.<br>If one local script address field is submitted, all required local script address fields must be submitted. — If one local script address field is submitted, all required local script address fields must be submitted.<br>Address Reference is required when deleting an address — Address Reference is required when deleting an address<br>Usage Data is required unless address is being deleted — Usage Data is required unless address is being deleted<br>Country Reference is required unless address is being deleted — Country Reference is required unless address is being deleted<br>Address deletion is not supported in this web service request — Address deletion is not supported in this web service request<br>If one western script field is submitted, all required western script address fields must be submitted. — If one western script field is submitted, all required western script address fields must be submitted.<br>Use a unique Address Reference ID for each address. [ID] is already used on another address. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>You can only update addresses that belong to this customer.<br>You can't use an existing address for a new customer.<br>You can't use an existing address for a new customer request.<br>You can't use an existing address for a new prospect.<br>You can only update addresses that belong to this customer request.<br>You can only update addresses that belong to this prospect.<br>Enter a postal code in the valid format: [PostalCodeValidationMessage]<br>One or more addresses are missing a Country City reference. This field is required because the City Prompt localization is active for: [countryref].<br>Enter a Country City reference that is valid for: [countryref]. You entered this Country City reference: [countrycityref].<br>Only Address reference belonging to the Customer tied to the Customer Contact can be shared by the Customer Contact<br>International Assignment is only valid for Non-Primary Home Addresses<br>Number of Days cannot be greater than 7. — Number of Days cannot be greater than 7.<br>Number of Days is not allowed for the country specified. — Number of Days is not allowed for the country specified.<br>You must enter a Country City reference instead of a text element because the City Prompt localization is active for: [countryref]. You entered this text element: [cityattrib] [citylocalattrib].<br>You entered this Country City reference: [countrycityref]. To use this Country City reference, you must activate the City Prompt localization for: [countryref].<br>Perform either one of these actions:<br>Activate the City Prompt localization.<br>Enter a municipality instead of a Country City reference.<br>Address "[ID]" is already in use by another address (possibly on another contactable). Please choose a different Address ID. — The Address ID field is for updating the value of the Address Reference. It cannot be the same as another existing address.<br>Second Submunicipality is not a valid address component for certain countries. — Second Submunicipality is not a valid address component for certain countries.<br>Second Subregion is not a valid address component for certain countries. — Second Subregion is not a valid address component for certain countries.<br>Subregion is not a valid address component for certain countries. — Subregion is not a valid address component for certain countries.<br>Submunicipality is not a valid address component for certain countries. — Submunicipality is not a valid address component for certain countries.<br>Specify the required missing address components for [proposedCountry]: [missingAddressComponents]<br>Specify an Address Reference that isn't already in use by another address. — Specify an Address Reference that isn't already in use by another address.<br>Existing addresses can't be future dated. Select an effective date that is on or before today, or create a new address with a future date.<br>Address [AddressReference] is not accessible to the processing user. — The Address Reference provided is not accessible to the processing user.<br>Ensure that the effective date specified in the Address Information Data matches the effective date specified in the [Add or Edit]:[Dependent Effective Date]. Alternatively, remove the effective date in the Address Information Data and reprocess the request. |
| Populate_with_Default_Bill_To_Contacts | boolean | [0..1] | When Populate with Default Bill-To Contacts is set to true, it will populate Bill To Contact with the Default Values. |  |
| Bill-To_Contact_Reference | Business_Entity_ContactObject | [0..*] | Bill-To Contact for the billing schedule header. |  |
| Billing_Method_Reference | Schedule_Distribution_MethodObject | [0..1] | Reference element representing the Billing Method. | Billing Method is required<br>Billing Method must be Defined Installment, Spread Evenly, or Custom. |
| Frequency_Reference | Frequency_BehaviorObject | [0..1] | Reference element representing the schedule Billing Frequency. |  |
| Installment_Recurrence | decimal (2, 0) >0 | [0..1] | Installment Recurrence |  |
| Billing_Period_Reference | Billing_PeriodObject | [0..1] | Reference element representing the Billing Period. |  |
| From_Date | date | [0..1] | From date. The system generates installments based on this value. |  |
| To_Date | date | [0..1] | To date. The system generates installments based on this value. |  |
| Number_of_Installments | decimal (12, 0) >0 | [0..1] | Number of installments. The system generates installments based on this value. |  |
| Prorate_First_and_Last_Installment | boolean | [0..1] | If true, the first and last billing installments are prorated based on the number of days in those installments. |  |
| Proration_Method_Reference | Proration_MethodObject | [0..1] | Determines how installments are prorated for partial periods. Options: 30 Day Month, Monthly Plus Daily, By Calendar Month, Actual Calendar Days, Fixed Year 365 Days. |  |
| Billed_in_Arrears | boolean | [0..1] | Billed in Arrears flag. The system consolidates invoices based on this value. |  |
| Use_From_Date | boolean | [0..1] | Use From Date flag. The system generates installments based on this value. |  |
| Use_To_Date | boolean | [0..1] | Use To Date flag. The system generates installments based on this value. |  |
| Day_of_Month | decimal (12, 0) >0 | [0..1] | Day of Month. The system generates installments based on this value. |  |
| Day_of_Week_Reference | Day_of_the_WeekObject | [0..1] | Day of Week. The system generates installments based on this value. |  |
| Automatically_Regenerate_Installments | boolean | [0..1] | Automatically Regenerate Installments flag. Use this flag to automatically regenerate installments when Customer Contract Amendments are completed. |  |
| Automatically_Submit_Schedule_via_Contract_Amendment | boolean | [0..1] | Automatically Submit Schedule via Contract Amendment flag. Use this flag to automatically submit the Billing Schedule on Customer Contract Amendment completion after installments are automatically regenerated. |  |
| Schedule_Type_Reference | Schedule_TypeObject | [0..1] | Reference element representing the Schedule Type. | You can only change the schedule type from 1 consolidated billing schedule to another consolidated billing schedule. |
| Schedule_Description | string | [0..1] | Schedule Description. |  |
| Milestone_Reference | Milestone_AbstractObject | [0..*] | Reference element representing milestones linked to this schedule. Schedule processing is contingent upon these milestones being met. | At Least One Milestone has an Invalid Customer or Sponsor |
| Schedule_On_Hold | boolean | [0..1] | Schedule On Hold flag. |  |
| Auto-Submit_Invoices_for_Approval | boolean | [0..1] | Auto-Submit Invoices for Approval flag. |  |
| Review_Not_Required_to_Bill | boolean | [0..1] | Review Not Required to Bill. |  |
| Include_Attachments_on_Invoice_Reference | Billable_Transaction_Attachment_TypeObject | [0..*] | This field enables you to select attachment types of expense report and supplier invoice on the billing schedule. | You can’t include attachments on invoices for award contract billing schedules.<br>To include attachments on invoices for installment billing schedules, specify a schedule type of Prepaid Billing. |
| Enable_Consumption_of_Prepaid_Balance | boolean | [0..1] | A boolean flag indicating whether the prepaid balance is currently applied to transactions for this schedule. |  |
| Do_Not_Bill_Over_Installment_Total | boolean | [0..1] | True if the billing schedule doesn't enable you to bill over the installment total for prepaid balances. | You can only select Do Not Bill Over Installment Total when you enable the consumption of prepaid balances. |
| Project_Invoice_Summary_Definition_Reference | Project_Invoice_Summary_DefinitionObject | [0..1] | Project Invoice Summary Definition Reference. |  |
| Billing_Cycle_Reference | Billing_CycleObject | [0..1] | Reference element representing the schedule Billing Cycle. |  |
| Billing_Limit | decimal (26, 6) >0 | [0..1] | Billing Limit on the Billing Schedule. |  |
| Payment_Terms_Reference | Payment_TermsObject | [1..1] | Reference element representing a unique instance of Payment Terms. |  |
| Payment_Type_Reference | Payment_TypeObject | [0..1] | Reference element representing a unique instance of Payment Type. |  |
| PO_Number | string | [0..1] | PO Number. |  |
| Statutory_Invoice_Type_Reference | Invoice_TypeObject | [0..1] | Workday uses statutory invoice types for mandatory government reporting. |  |
| Invoice_Type_Reference | Customer_Invoice_TypeObject | [0..1] | Reference element representing a unique instance of Invoice Type. |  |
| Invoice_Memo | string | [0..1] | Invoice memo. |  |
| Recurring_Invoice_Day | decimal (2, 0) >0 | [0..1] | Recurring Invoice Day |  |
| Invoice_Delivery_Type_Default_Reference | Document_Delivery_TypeObject | [0..*] | The reference ID for the Invoice Delivery Type Default. This field is read-only. |  |
| Invoice_Delivery_Type_Override_Reference | Document_Delivery_TypeObject | [0..*] | The Delivery Type override you want to specify for the given billing schedule. | Specify only 1 document delivery type for each delivery method.<br>You're specifying a document delivery type that's either inactive or isn't associated with the document type of Customer Invoice for this customer. Specify an active Delivery Type and ensure that it's associated with the document type of Customer Invoice on the Maintain Document Delivery Types task. |
| Interest_and_Late_Fee_Rules_Override_Data | Interest_and_Late_Fee_Override_WWS_Data | [0..*] | Contains data for Interest and Late Fee Rule Override including Interest Rule, Late Fee Rule, and Exempt data.<br>When you perform the submit or import operation, make sure that the Interest and Late Fee Rule you're trying to override is active. | Interest and Late Fees Override cannot be the same as Default. If you want to use the Default rules, leave Override empty.<br>You must select an active rule.<br>To submit an Interest and Late Fee Rule, enable the Interest and Late Fee option in your tenant.<br>You can't select Interest Rule: [Interest rule] with Late Fee Rule: [Late Fee Rule] because they use different calculation options. Select rules that have the same Calculation Option.<br>You can't enter a Late Fee Rule or Interest Rule when the Exempt flag is set to true.<br>To submit this operation for applying interest and late fee rule to the billing schedule, make sure that the billing schedule is either for a customer contract or intercompany customer contract.<br>You can’t edit the interest and late fee fields on invoices originating from Sponsor or Student Contract. |
| Contract_Line_Reference | Receivable_Contract_Line_AbstractObject | [0..*] | Reference element representing instances Contract Lines linked to this schedule. | Select prepaid lines with a revenue treatment of Deferred when the schedule type is enabled for Consolidated Billing. — Select prepaid lines with a revenue treatment of Deferred when the schedule type is enabled for Consolidated Billing. |
| Billing_Installment_Data | Billing_Installment_Data | [0..*] | Billing Installment Data | You can't create or update installments to a Closed status for a Prepaid schedule type.<br>You need to enter Billing Installment Payment Terms for the Override Invoice Header marked Yes.<br>You cannot assign [Award Task Reference ID] as a milestone as it is associated with another award line that does not belong to this billing schedule. Change the Receivable Contract Line ID or add the associated award line to this billing schedule.<br>To add the [Award Task Reference ID] as a milestone, enable the billing milestone field.<br>Billing Installment Line Data is required.<br>Start Date must be before End Date.<br>You can't update an installment with a status of Canceled, Completed, Credited, or In Progress. |
| Billing_Schedule_Installment_Schedule_Data | Customer_Contract_Schedule_Installment_Schedule_Data | [0..*] | This element contains data to be used with the Defined Installment or 'RECURRING' schedule distribution method. For each contract line included in the schedule, you can specify a Regular, First, and Last Installment amount that will be used when generating installments to determine how to allocate amounts across each installment. |  |
| Retention_Terms_Data | Retention_Terms_Data | [0..1] | This element contains Percent to Retain, Estimated Retention Release Date, Third Party Retention flag, Retention Memo and Contract Lines for Retention Reference | Please add only valid contract lines for retention to the schedule based on the Company, Customer and Contract Line. — Please add only valid contract lines for retention to the schedule based on the Company, Customer and Contract Line.<br>Please include any contract lines currently associated with a retention balance in the Retention Terms Data. — Please include any contract lines currently associated with a retention balance in the Retention Terms Data. |
| Include_Tax_on_Prepaid | boolean | [0..1] | If true, the Billing Schedule will Include Tax on Prepaid. |  |
| Invoice_Prepaid_Installments_with_Other_Transaction_Types | boolean | [0..1] | If true, Workday includes prepaid installments on the same invoices as other transaction types. |  |
| Prepaid_Installment_and_Mapping_Data | Prepaid_Installment_and_Mapping_Data | [0..*] | Prepaid Installment and Mapping Data Element | Specify a negative installment amount that's less than or equal to the prepaid balance for lines with consumption.<br>You can't delete a prepaid mapping if the customer contract lines already have prepaid consumption. |

| col1 |
|---|
| Please include all existing contract lines when adding a contract line to the schedule. — Contract Lines may be added to the schedule, but cannot be removed.<br>Please set the Method to Custom if you are adding or updating installments. — Cannot add or update an installment if the schedule Method is not Custom.<br>Cannot add or update installments and also request to Generate Installments.<br>Start Date must be before End Date.<br>Billing Frequency is required unless Billing Method is Custom.<br>Schedule Start Date can't be changed with completed installments.<br>Schedule Number of Installments can't be less than the number of Installments already completed or in progress.<br>Frequency Behavior can't be changed with already completed Installments.<br>End Date can't be before the date of completed installments or installments in progress.<br>There must be at least 1 installment to submit the Billing Schedule.<br>The line's currency does not match schedule's currency.<br>You can't create a billing schedule when a change request is in process for the contract.<br>An installment billing schedule with a cost reimbursable award line must have a Prepaid schedule type.<br>Award billing schedules with prepaid schedule types can only have cost-reimbursable award lines.<br>When billing method is not Custom, then From Date and either Number of Installments or To Date are required.<br>You can't select Day of the Month with the Weekly frequency.<br>You must enter a From Date when you select a Billing Frequency.<br>Enter Prepaid Billing as the Schedule Type in order to add a Billing Limit.<br>Enter a billing limit that doesn't exceed the [billing limit label] on the award header.<br>You can only use Automatically Regenerate Installments and Automatically Submit Schedule via Contract Amendment flags for Spread Even billing schedule type.<br>Billing Schedules with Award Lines don't support Automatically Regenerate Installments or Automatically Submit Schedule via Contract Amendment flags.<br>You can’t use intercompany contract lines with this billing schedule web service.<br>Include Tax on Prepaid isn’t valid for Award Lines.<br>You can't change the Include Tax on Prepaid for Billing Schedule with noncanceled Invoices.<br>Include Tax on Prepaid is valid only if you select a prepaid schedule type.<br>You can only add the [Award Task Reference ID] on award contract lines.<br>You cannot assign [Award Task Reference ID] as a milestone as it is associated with another award line that does not belong to this billing schedule. Change the Receivable Contract Line ID or add the associated award line to this billing schedule.<br>You can't use the award task as a billing milestone when the billing type is a Transaction. To use the award task as a billing milestone, change the [Billing Type ID] to an Installment.<br>To add the [Award Task Reference ID] as a milestone, enable the billing milestone field.<br>To enable Automatically Submit Schedule via Contract Amendment, you must also enable Automatically Regenerate Installments.<br>Prepaid mapping with the same customer contract lines and dates already exists for [prepaid line]. Either select different customer contract lines or change the dates for the existing customer contract lines.<br>You can only select prepaid mappings and prepaid installments when the schedule type is enabled for Consolidated Billing.<br>You can only select customer contract lines with the same billing type on the billing schedule. — You can only select customer contract lines with the same billing type on the billing schedule.<br>One and only one option may be chosen from: Use From Date, Use To Date, Day of Month, or Day of Week.<br>You can’t set Billed in Arrears as True when the schedule type is enabled for Consolidated Billing.<br>You can only specify Custom or Spread Even as billing method when the schedule type is enabled for Consolidated Billing.<br>If Billing Type is Transaction and Billing Frequency is selected, one and only one option may be chosen for: Use From Date, Use To Date, Day of Month, Day of Week.<br>Billed in Arrears cannot be selected unless the Billing Type is Transaction.<br>You can't specify a Day of Month when the billing frequency is Calendar Week or Weekly when the schedule type has consolidated billing enabled.<br>A From Date must be entered when the Invoice Date Option is Use From Date.<br>You can only specify a Day of Week when the billing frequency is Weekly or Calendar Weekly when the schedule type has consolidated billing enabled.<br>You can only specify more than 1 billing type when the schedule type has consolidated billing enabled.<br>You can only select Day of Week with Transaction Billing Type.<br>You can’t specify a Use To Date when the schedule type is enabled for Consolidated Billing.<br>Schedule Type must be active and enabled for Billing.<br>You can only specify a Billing Period when the schedule type has consolidated billing enabled and the billing method specified is spread even.<br>If Invoice Uses To Date is entered, To Date must be entered.<br>You can’t specify these billing frequencies unless the schedule type has consolidated billing enabled: Calendar Month, Calendar Quarter, Calendar Week, Calendar Year.<br>You can only specify a Recurring Invoice Day when the schedule type is enabled for Consolidated Billing.<br>You can’t add award lines when the schedule type is enabled for Consolidated Billing.<br>Enter a number between 1 and 31 for Recurring Invoice Day.<br>Select Transaction type Billing Method when Billing Type is Transaction.<br>You can’t specify milestones when the schedule type is enabled for Consolidated Billing.<br>You can only specify installment recurrence when the schedule type has consolidated billing enabled, the billing method is Spread Even, and the frequency is Calendar Month, Calendar Week, Monthly, or Weekly.<br>You must include frequency and date parameters when you select the Recurring - Fixed Term contract line type.<br>You can’t specify retention terms when the schedule type has consolidated billing enabled.<br>You can only select Day of Week with Weekly frequency.<br>If Billing method is Custom, one and only one option may be chosen for: Use From Date, Use To Date, Use Number of Days before Start Date. If Billing Method is not Custom, one and only one option must be chosen for: Use From Date, Use To Date, Use Number of Days before Start Date.<br>Enter a number between 1 and 31 for Day of Month.<br>To create the billing schedule, specify contract lines with the same Company and Bill-To Customer as the header.<br>To enable prorated billing, specify 1 of these billing frequencies: Calendar Month, Calendar Quarter, or Calendar Week.<br>You can only specify proration when the schedule type has consolidated billing enabled.<br>To enable prorated billing, specify Spread Even for the Schedule Distribution Method.<br>Specify different installment criteria. The total number of installments must be less than [max].<br>To submit the billing schedule with a project transaction summarization definition, specify Transaction as the Billing Type. You can't have a project transaction summarization definition on an installment billing schedule.<br>Leave the From Date and To Date fields blank when you specify Transaction as the billing type.<br>To create the billing schedule, specify contract lines with the same Company and Bill-To Customer as the header.<br>You can only specify Invoice Prepaid Installments with Other Transaction Types when the schedule type is enabled for consolidated billing.<br>To submit this invoice delivery type override to the billing schedule, make sure that the billing schedule is for a customer contract.<br>To change Invoice Prepaid Installments with Other Transaction Types, first invoice the prepaid installments on the proposal and approve them on the customer invoice.<br>Leave the Billing Limit field blank when you specify a Summary Reimbursable schedule type.<br>Specify a Summary Reimbursable schedule type and only summary reimbursable award lines for a summary reimbursable billing schedule.<br>Leave the Retention Terms Data fields blank when you specify a Summary Reimbursable schedule type.<br>Leave the Milestone field blank when you specify a Summary Reimbursable schedule type.<br>Leave the Schedule On Hold field blank when you specify a Summary Reimbursable schedule type.<br>You can't specify a Summary Reimbursable schedule type on this web service version. Specify a schedule type that's not Summary Reimbursable or use web service version v39.0 or higher.<br>You can only select customer contract lines with the same billing type on the billing schedule. — You can only select customer contract lines with the same billing type on the billing schedule.<br>Specify draw IDs only on award lines for awards that contain a letter of credit. — Specify draw IDs only on award lines for awards that contain a letter of credit.<br>There's a Record Letter of Credit Draw Down Event business process for this award currently in progress. Wait for the process to complete before changing the Draw ID. — There's a Record Letter of Credit Draw Down Event business process for this award currently in progress. Wait for the process to complete before changing the Draw ID.<br>This statutory invoice type isn't valid for the specified company. Specify a statutory invoice type for the customer contract that's Active, that matches the country for the company, and that has a Statutory Invoice Type Usage of Customer Invoices. Workday doesn't support statutory invoice types on award contracts.<br>These prepaid installments have a status of Complete, In Progress, Credited or Canceled, and can't be deleted: [Installments]<br>This frequency is not valid for an award billing schedule: [frequency]<br>To specify this project plan task in the Milestone Reference field, ensure that you have access to the project.<br>For Transaction schedules, you can’t specify the Number of Installments.<br>Specify either the To Date or the Number of Installments but not both.<br>Enter a date range less than 100 years for the Billing From Date and Billing To Date. — Enter a date range less than 100 years for the Billing From Date and Billing To Date.<br>Specify a valid proration method. You can't specify a proration method value of 30 Day Month or By Calendar Month for weekly or calendar week billing frequencies.<br>You can only specify a proration method when the Billing Method value is Spread Even and the Schedule Type value is Consolidated Billing.<br>Specify only 1 proration method at a time. |

## Billing_TypeObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Billing_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Billing_TypeObjectID

*Part of: [Billing_TypeObject](#billing_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Billing_Type_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Letter_of_Credit_Draw_IDObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Letter_of_Credit_Draw_IDObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Letter_of_Credit_Draw_IDObjectID

*Part of: [Letter_of_Credit_Draw_IDObject](#letter_of_credit_draw_idobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Letter_of_Credit_Draw_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Document_StatusObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data), [Billing_Installment_Data](#billing_installment_data), [Prepaid_Installment_Data](#prepaid_installment_data)*

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

## CurrencyObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

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

## CompanyObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

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

## Billable_EntityObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

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

## Address_ReferenceObject

*Part of: [Address_Information_Data](#address_information_data), [Billing_Schedule_Data](#billing_schedule_data)*

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

## Address_Information_Data

*Part of: [Billing_Schedule_Data](#billing_schedule_data) — Address information*

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

## Business_Entity_ContactObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Business_Entity_ContactObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Business_Entity_ContactObjectID

*Part of: [Business_Entity_ContactObject](#business_entity_contactobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Business_Entity_Contact_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Schedule_Distribution_MethodObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Schedule_Distribution_MethodObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Schedule_Distribution_MethodObjectID

*Part of: [Schedule_Distribution_MethodObject](#schedule_distribution_methodobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Schedule_Distribution_Method_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Frequency_BehaviorObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Frequency_BehaviorObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Frequency_BehaviorObjectID

*Part of: [Frequency_BehaviorObject](#frequency_behaviorobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Frequency_Behavior_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Billing_PeriodObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Billing_PeriodObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Billing_PeriodObjectID

*Part of: [Billing_PeriodObject](#billing_periodobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Billing_Period_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Proration_MethodObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Proration_MethodObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Proration_MethodObjectID

*Part of: [Proration_MethodObject](#proration_methodobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Proration_Method_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Day_of_the_WeekObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Day_of_the_WeekObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Day_of_the_WeekObjectID

*Part of: [Day_of_the_WeekObject](#day_of_the_weekobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Day_of_the_Week_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Schedule_TypeObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Schedule_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Schedule_TypeObjectID

*Part of: [Schedule_TypeObject](#schedule_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Schedule_Category_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Milestone_AbstractObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data), [Billing_Installment_Data](#billing_installment_data), [Prepaid_Installment_Data](#prepaid_installment_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Milestone_AbstractObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Milestone_AbstractObjectID

*Part of: [Milestone_AbstractObject](#milestone_abstractobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Award_Task_Reference_ID, Billing_Installment_Reference_ID, Customer_Date_Milestone_ID, Project_Plan_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Billable_Transaction_Attachment_TypeObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Billable_Transaction_Attachment_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Billable_Transaction_Attachment_TypeObjectID

*Part of: [Billable_Transaction_Attachment_TypeObject](#billable_transaction_attachment_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Billable_Transaction_Attachment_Type_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Project_Invoice_Summary_DefinitionObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Project_Invoice_Summary_DefinitionObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Project_Invoice_Summary_DefinitionObjectID

*Part of: [Project_Invoice_Summary_DefinitionObject](#project_invoice_summary_definitionobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, PROJECT_INVOICE_SUMMARY_DEFINITION_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Billing_CycleObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Billing_CycleObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Billing_CycleObjectID

*Part of: [Billing_CycleObject](#billing_cycleobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Billing_Cycle_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Payment_TermsObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data), [Billing_Installment_Data](#billing_installment_data)*

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

*Part of: [Billing_Schedule_Data](#billing_schedule_data), [Billing_Installment_Data](#billing_installment_data)*

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

## Invoice_TypeObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Invoice_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Invoice_TypeObjectID

*Part of: [Invoice_TypeObject](#invoice_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Invoice_Type_ID, Spend_Data_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Customer_Invoice_TypeObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data), [Billing_Installment_Data](#billing_installment_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Customer_Invoice_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Customer_Invoice_TypeObjectID

*Part of: [Customer_Invoice_TypeObject](#customer_invoice_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Customer_Invoice_Type_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Document_Delivery_TypeObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Document_Delivery_TypeObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Document_Delivery_TypeObjectID

*Part of: [Document_Delivery_TypeObject](#document_delivery_typeobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Document_Delivery_Type_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Interest_and_Late_Fee_Override_WWS_Data

*Part of: [Billing_Schedule_Data](#billing_schedule_data) — Contains data for Interest and Late Fee Rule Override including Interest Rule, Late Fee Rule, and Exempt data.
When you perform the submit or import operation, make sure that the Interest and Late Fee Rule you're trying to override is active.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Interest_Rule_Reference | Interest_Rate_RuleObject | [0..1] | Interest Rule Reference references a specific Interest Rule that you can use for calculating the interest amount and apply it to past due customer invoices. |  |
| Late_Fee_Rule_Reference | Late_Fee_RuleObject | [0..1] | Late Fee Rule Reference references a specific Late Fee Rule that you can use for calculating the late fee amount and apply it to past due customer invoices. |  |
| Exempt | boolean | [0..1] | A flag when set to true, excludes the interest and late fee charges. |  |

| col1 |
|---|
| Interest and Late Fees Override cannot be the same as Default. If you want to use the Default rules, leave Override empty.<br>You must select an active rule.<br>To submit an Interest and Late Fee Rule, enable the Interest and Late Fee option in your tenant.<br>You can't select Interest Rule: [Interest rule] with Late Fee Rule: [Late Fee Rule] because they use different calculation options. Select rules that have the same Calculation Option.<br>You can't enter a Late Fee Rule or Interest Rule when the Exempt flag is set to true.<br>To submit this operation for applying interest and late fee rule to the billing schedule, make sure that the billing schedule is either for a customer contract or intercompany customer contract.<br>You can’t edit the interest and late fee fields on invoices originating from Sponsor or Student Contract. |

## Interest_Rate_RuleObject

*Part of: [Interest_and_Late_Fee_Override_WWS_Data](#interest_and_late_fee_override_wws_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Interest_Rate_RuleObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Interest_Rate_RuleObjectID

*Part of: [Interest_Rate_RuleObject](#interest_rate_ruleobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Interest_and_Late_Fee_Rule_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Late_Fee_RuleObject

*Part of: [Interest_and_Late_Fee_Override_WWS_Data](#interest_and_late_fee_override_wws_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Late_Fee_RuleObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Late_Fee_RuleObjectID

*Part of: [Late_Fee_RuleObject](#late_fee_ruleobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Interest_and_Late_Fee_Rule_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Receivable_Contract_Line_AbstractObject

*Part of: [Billing_Schedule_Data](#billing_schedule_data), [Billing_Installment_Line_Data](#billing_installment_line_data), [Retention_Terms_Data](#retention_terms_data), [Prepaid_Installment_and_Mapping_Data](#prepaid_installment_and_mapping_data), [Prepaid_Mapping_Data](#prepaid_mapping_data)*

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

## Billing_Installment_Data

*Part of: [Billing_Schedule_Data](#billing_schedule_data) — Element containing Billing Schedule Installment Data*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Billing_Installment_Reference_ID | string | [0..1] | The Billing Installment Reference ID. This is the Billing Installment unique identifier. |  |
| Billing_Installment_Reference | Billing_InstallmentObject | [0..1] | Reference to an existing Billing Installment for update purposes only. |  |
| Delete_Installment | boolean | [0..1] | Flag to indicate to delete the installment. When the flag is set to True, Workday deletes the installment and associated installment lines. | You can't delete a new billing installment that you've added to the billing schedule. Either set the Delete Installment flag to False or remove the row.<br>You can't delete a billing installment from a different billing schedule. Set the Delete Installment flag to False, remove the row, or update the billing schedule for the billing installment.<br>To delete a prepaid billing installment, use the Prepaid Installment and Mapping Data element.<br>You can only delete a billing installment that has a billing method of Custom. Set the Delete Installment flag to False, remove the row, or use a billing method of Custom.<br>You can't delete a billing installment with a status of Canceled, Complete, Credited or In Progress. Either set the Delete Installment flag to False or remove the row. |
| Status_Reference | Document_StatusObject | [0..*] | Installment status |  |
| Installment_Date | date | [0..1] | Invoice date |  |
| Due_Date | date | [0..1] | Installment Due date. Due Date is read-only and the system derives it based on Payment Terms. |  |
| From_Date | date | [0..1] | Installment From date |  |
| To_Date | date | [0..1] | Installment To date |  |
| On_Hold | boolean | [0..1] | Installment On Hold flag |  |
| Total_Amount | decimal (26, 6) | [0..1] | Installment Amount |  |
| Milestone_Reference | Milestone_AbstractObject | [0..*] | Reference element representing a unique instance of Milestone | To specify this project plan task in the Milestone Reference field, ensure that you have access to the project. |
| Override_Invoice_Header | boolean | [0..1] | Override Invoice Header flag. This must be Yes if you supply installment values for Payment Terms or Type, PO Number, Invoice Type, or Invoice Memo. | Cannot provide invoice overrides unless Installment Invoice Override is ON. |
| Payment_Terms_Reference | Payment_TermsObject | [0..1] | Reference element representing a unique instance of Payment Terms. This should only be supplied to override the same value on the installment's schedule and must be used in conjunction with Override Invoice Header. |  |
| Payment_Type_Reference | Payment_TypeObject | [0..1] | Reference element representing a unique instance of Payment Type. This should only be supplied to override the same value on the installment's schedule and must be used in conjunction with Override Invoice Header. |  |
| PO_Number | string | [0..1] | PO Number. This should only be supplied to override the same value on the installment's schedule and must be used in conjunction with Override Invoice Header. |  |
| Invoice_Type_Reference | Customer_Invoice_TypeObject | [0..1] | Reference element representing a unique instance of Invoice Type. This should only be supplied to override the same value on the installment's schedule and must be used in conjunction with Override Invoice Header. |  |
| Invoice_Memo | string | [0..1] | Invoice Memo. This should only be supplied to override the same value on the installment's schedule and must be used in conjunction with Override Invoice Header. |  |
| Billing_Installment_Line_Data | Billing_Installment_Line_Data | [0..*] | Billing Installment Line Data | Please associate a valid contract line to the installment line. — Installment lines must refer to a contract line which is already linked to the schedule.<br>The Award Line is invalid. The award line associated with the installment must be the one with smallest line number associated with the billing schedule. |

| col1 |
|---|
| You can't create or update installments to a Closed status for a Prepaid schedule type.<br>You need to enter Billing Installment Payment Terms for the Override Invoice Header marked Yes.<br>You cannot assign [Award Task Reference ID] as a milestone as it is associated with another award line that does not belong to this billing schedule. Change the Receivable Contract Line ID or add the associated award line to this billing schedule.<br>To add the [Award Task Reference ID] as a milestone, enable the billing milestone field.<br>Billing Installment Line Data is required.<br>Start Date must be before End Date.<br>You can't update an installment with a status of Canceled, Completed, Credited, or In Progress. |

## Billing_InstallmentObject

*Part of: [Billing_Installment_Data](#billing_installment_data), [Prepaid_Installment_Data](#prepaid_installment_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Billing_InstallmentObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Billing_InstallmentObjectID

*Part of: [Billing_InstallmentObject](#billing_installmentobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Billing_Installment_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Billing_Installment_Line_Data

*Part of: [Billing_Installment_Data](#billing_installment_data) — Element containing Billing Schedule Installment Line data*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Order | string | [0..1] | Line order |  |
| Overrride_Line | boolean | [0..1] | Override Line flag. Use this to specify values on the installment line instead of using values derived from either the installment, the schedule, or the contract line. This must be on to specify overrides. | Cannot provide invoice line overrides unless Installment Override is ON. |
| Contract_Line_Reference | Receivable_Contract_Line_AbstractObject | [1..1] | Reference element representing a unique instance of a contract line linked to this installment line. | You must associate prepaid customer contract line types with installments using the Prepaid Installment and Mapping Data element when the schedule type has consolidated billing enabled. |
| Line_Item_Description | string | [0..1] | Line Item description |  |
| Quantity | decimal (22, 2) | [0..1] | Quantity. If you supply this value as an override, you must also enable the Override Line flag. |  |
| Unit_of_Measure_Reference | Unit_of_MeasureObject | [0..1] | Unit of measure. If you supply this value as an override, you must also enable the Override Line flag. |  |
| Quantity_2 | decimal (22, 2) | [0..1] | Quantity 2. If you supply this value as an override, you must also enable the Override Line flag. |  |
| Unit_of_Measure_2_Reference | Unit_of_MeasureObject | [0..1] | Unit of Measure 2. If you supply this value as an override, you must also enable the Override Line flag. |  |
| Unit_Cost | decimal (26, 6) | [0..1] | Unit Price. If you supply this value as an override, you must also enable the Override Line flag. |  |
| Amount | decimal (26, 6) | [0..1] | Amount. If you supply this value as an override, you must also enable the Override Line flag. |  |
| From_Date | date | [0..1] | From Date. If you supply this value as an override, you must also enable the Override Line flag. |  |
| To_Date | date | [0..1] | To Date. If you supply this value as an override, you must also enable the Override Line flag. |  |
| Tax_Applicability_Reference | Tax_ApplicabilityObject | [0..*] | Reference element representing a unique instance of Tax Applicability. |  |
| Tax_Code_Reference | Tax_CodeObject | [0..*] | Reference element representing a unique instance of Tax Code. |  |
| Deferred_Revenue | boolean | [0..1] | Deferred Revenue flag. |  |
| Memo | string | [0..1] | Memo. If you supply this value as an override, you must also enable the Override Line flag. |  |
| Worktags_Reference | Audited_Accounting_WorktagObject | [0..*] | Reference element representing instances of Worktag. If you supply this value as an override, you must also enable the Override Line flag. | Only one worktag of each type is allowed<br>You can't use customer contracts as worktags on billing schedules.<br>[invalid worktag value message]<br>[wtt value required]: [wtt]<br>Select a balancing worktag for Worktags of the following type: [type]<br>The intercompany affiliate worktag [worktag] is invalid for header company [header company] and line company [line company]. Enter a valid header company, line company, and intercompany affiliate worktag combination.<br>The [type] is/are not available for use with the company/s: [partitionable] [company] |
| Closed_Installment_Base_Currency_Amount | decimal (18, 3) | [0..1] | The closed installment line amount in the base currency of the contract line company. Specify the closed installment line amount when the base currency on the contract line company differs from the currency on the billing schedule. | You can only specify a Closed Installment Base Currency Amount for closed installments.<br>Specify a decimal precision for the Closed Installment Base Currency Amount that's accurate for [currency]. The Closed Installment Base Currency Amount of [amount] exceeds the decimal precision of [precision].<br>You can only specify a Closed Installment Base Currency Amount when the base currency on the contract line company differs from the currency on the billing schedule. |

| col1 |
|---|
| Please associate a valid contract line to the installment line. — Installment lines must refer to a contract line which is already linked to the schedule.<br>The Award Line is invalid. The award line associated with the installment must be the one with smallest line number associated with the billing schedule. |

## Unit_of_MeasureObject

*Part of: [Billing_Installment_Line_Data](#billing_installment_line_data)*

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

## Tax_ApplicabilityObject

*Part of: [Billing_Installment_Line_Data](#billing_installment_line_data)*

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

## Tax_CodeObject

*Part of: [Billing_Installment_Line_Data](#billing_installment_line_data)*

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

## Audited_Accounting_WorktagObject

*Part of: [Billing_Installment_Line_Data](#billing_installment_line_data)*

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

## Customer_Contract_Schedule_Installment_Schedule_Data

*Part of: [Billing_Schedule_Data](#billing_schedule_data) — This element contains data to be used with the Defined Installment or 'RECURRING' schedule distribution method. For each contract line included in the schedule, you can specify a Regular, First, and Last Installment amount that will be used when generating installments to determine how to allocate amounts across each installment.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Line_Reference | Customer_Installment_ItemObject | [1..1] | A reference to the contract line this schedule information is for. | You can only update Installment Schedule Data for Contract Lines that are included in this Schedule. |
| Regular_Installment_Amount | decimal (26, 6) | [0..1] | The amount to distribute across regular installments. |  |
| First_Installment_Amount | decimal (26, 6) | [0..1] | The amount to use for the first installment, to support proration. |  |
| Last_Installment_Amount | decimal (26, 6) | [0..1] | The amount to use for the last installment, to support proration. |  |

## Customer_Installment_ItemObject

*Part of: [Customer_Contract_Schedule_Installment_Schedule_Data](#customer_contract_schedule_installment_schedule_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Customer_Installment_ItemObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Customer_Installment_ItemObjectID

*Part of: [Customer_Installment_ItemObject](#customer_installment_itemobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Customer_Invoice_Line_Reference_ID, Receivable_Contract_Line_Reference_ID, Student_Sponsor_Contract_Line_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Retention_Terms_Data

*Part of: [Billing_Schedule_Data](#billing_schedule_data) — Element that contains retention data*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Percent_to_Retain | decimal (12, 6) >0 | [0..1] | The retention percent defined for the billing schedule. |  |
| Estimated_Retention_Release_Date | date | [0..1] | The estimated retention release date. |  |
| Third_Party_Retention | boolean | [0..1] | Returns true if the contract has 3rd party retention checked. |  |
| Retention_Memo | string | [0..1] | The memo field for the billing schedule retention terms. |  |
| Contract_Lines_for_Retention_Reference | Receivable_Contract_Line_AbstractObject | [0..*] | Contract lines that include retention. |  |

| col1 |
|---|
| Please add only valid contract lines for retention to the schedule based on the Company, Customer and Contract Line. — Please add only valid contract lines for retention to the schedule based on the Company, Customer and Contract Line.<br>Please include any contract lines currently associated with a retention balance in the Retention Terms Data. — Please include any contract lines currently associated with a retention balance in the Retention Terms Data. |

## Prepaid_Installment_and_Mapping_Data

*Part of: [Billing_Schedule_Data](#billing_schedule_data) — Contains data for prepaid mappings and prepaid installments*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Prepaid_Installment_and_Mapping_ID | string | [0..1] | Prepaid Installment and Mapping ID |  |
| Prepaid_Installment_and_Mapping_Reference | Prepaid_Installment_and_MappingObject | [0..1] | Prepaid Installment and Mapping Reference |  |
| Prepaid_Customer_Contract_Line_Reference | Receivable_Contract_Line_AbstractObject | [1..1] | Prepaid Customer Contract Line Reference | Select a customer contract line with a line type of Prepaid for the prepaid mapping.<br>Select a prepaid line from the billing schedule for the prepaid mapping.<br>You can't change the prepaid line of a prepaid mapping if it's associated with prepaid installments that are Complete, In Progress, Credited or Canceled. |
| Prepaid_Mapping_Data | Prepaid_Mapping_Data | [0..*] | Contains data for prepaid mapping |  |
| Prepaid_Installment_Data | Prepaid_Installment_Data | [0..*] | Contains data for prepaid installments |  |

| col1 |
|---|
| Specify a negative installment amount that's less than or equal to the prepaid balance for lines with consumption.<br>You can't delete a prepaid mapping if the customer contract lines already have prepaid consumption. |

## Prepaid_Installment_and_MappingObject

*Part of: [Prepaid_Installment_and_Mapping_Data](#prepaid_installment_and_mapping_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Prepaid_Installment_and_MappingObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Prepaid_Installment_and_MappingObjectID

*Part of: [Prepaid_Installment_and_MappingObject](#prepaid_installment_and_mappingobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Prepaid_Installment_and_Mapping_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Prepaid_Mapping_Data

*Part of: [Prepaid_Installment_and_Mapping_Data](#prepaid_installment_and_mapping_data) — Contains data for prepaid mapping*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Prepaid_Mapping_ID | string | [0..1] | Prepaid Mapping ID |  |
| Prepaid_Mapping_Reference | Prepaid_MappingObject | [0..1] | Prepaid Mapping Reference |  |
| Prepaid_Mapping_Customer_Contract_Line_Reference | Receivable_Contract_Line_AbstractObject | [1..*] | Prepaid Mapping Customer Contract Line Reference | Select a customer contract line from the billing schedule for the prepaid mapping. — Select a customer contract line from the billing schedule for the prepaid mapping.<br>You can't delete customer contract lines from the prepaid mapping if there's already prepaid consumption. — You can't delete customer contract lines from the prepaid mapping if there's already prepaid consumption.<br>Select a customer contract line that doesn't have a line type of Prepaid or Revenue Only for the prepaid mapping. — Select a customer contract line that doesn't have a line type of Prepaid or Revenue Only for the prepaid mapping.<br>Ensure that the mapped contract lines have the same billable project as the prepaid contract line. — Ensure that the mapped contract lines have the same billable project as the prepaid contract line. |
| Prepaid_Mapping_From_Date | date | [0..1] | Prepaid Mapping From Date |  |
| Prepaid_Mapping_To_Date | date | [0..1] | Prepaid Mapping To Date | To Date must be greater than From Date. — To Date must be greater than From Date. |

## Prepaid_MappingObject

*Part of: [Prepaid_Mapping_Data](#prepaid_mapping_data)*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @Descriptor | string | [0..1] | Display information used to describe an instance of an object. This 'optional' information is for outbound descriptive purposes only and is not processed on inbound Workday Web Services requests. |  |
| ID | Prepaid_MappingObjectID | [0..*] | Contains a unique identifier for an instance of an object. |  |

## Prepaid_MappingObjectID

*Part of: [Prepaid_MappingObject](#prepaid_mappingobject) — Contains a unique identifier for an instance of an object.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| #text | string |  |  |  |
| @type | WID, Prepaid_Mapping_Reference_ID | [1..1] | The unique identifier type. Each "ID" for an instance of an object contains a type and a value. A single instance of an object can have multiple "ID" but only a single "ID" per "type". Some "types" require a reference to a parent instance. |  |

## Prepaid_Installment_Data

*Part of: [Prepaid_Installment_and_Mapping_Data](#prepaid_installment_and_mapping_data) — Contains data for prepaid installments*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Prepaid_Installment_ID | string | [0..1] | Prepaid Installment ID |  |
| Prepaid_Installment_Reference | Billing_InstallmentObject | [0..1] | Prepaid Installment Reference |  |
| Prepaid_Installment_Status_Reference | Document_StatusObject | [0..1] | Prepaid Installment Status | You can't create prepaid installments in a Closed status when the schedule type is enabled for Consolidated Billing.<br>You can't update the prepaid installment status.<br>You can't update an installment with a status of Canceled, Completed, Credited, or In Progress. |
| On_Hold | boolean | [0..1] | Installment On Hold flag for prepaid installment | You can't change the On Hold field if the prepaid installment is Complete, In Progress, Credited or Canceled. |
| Prepaid_Installment_Date | date | [1..1] | Prepaid Installment Date | You can't change the installment date if the prepaid installment is Complete, In Progress, Credited or Cancel |
| Prepaid_Installment_Amount | decimal (26, 6) | [1..1] | Prepaid installment amount | You can't enter a negative installment amount when there's no prepaid consumption. Enter a positive number for the installment amount.<br>You can't change the installment amount if the prepaid installment is Complete, In Progress, Credited or Canceled |
| Line_Item_Description | string | [0..1] | Line Item Description for Prepaid Installment. | To change the line item description, ensure the prepaid installment has a status of Available or Pending Milestone. |
| Memo | string | [0..1] | Memo for Prepaid Installment. | To change the memo, ensure the prepaid installment has a status of Available or Pending Milestone. |
| Milestone_Reference | Milestone_AbstractObject | [0..*] | Milestone reference for prepaid installment. | To specify this project plan task in the Milestone Reference field, ensure that you have access to the project. — Validation to ensure that Milestones are properly secured for the submitting user.<br>One or more milestones have an invalid Customer or Sponsor.<br>To change the milestones, ensure the prepaid installment has a status of Available or Pending Milestone. |

## Application_Instance_Related_Exceptions_Data

*Part of: [Submit_Billing_Schedule_Response](#submit_billing_schedule_response) — Element containing Exceptions Data*

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

## Billing_ScheduleReferenceEnumeration

*Part of: [Billing_ScheduleObjectID](#billing_scheduleobjectid)*

| Base Type |
|---|
| string |

## WorkerReferenceEnumeration

*Part of: [WorkerObjectID](#workerobjectid)*

| Base Type |
|---|
| string |

## Billing_TypeReferenceEnumeration

*Part of: [Billing_TypeObjectID](#billing_typeobjectid)*

| Base Type |
|---|
| string |

## Letter_of_Credit_Draw_IDReferenceEnumeration

*Part of: [Letter_of_Credit_Draw_IDObjectID](#letter_of_credit_draw_idobjectid)*

| Base Type |
|---|
| string |

## Document_StatusReferenceEnumeration

*Part of: [Document_StatusObjectID](#document_statusobjectid)*

| Base Type |
|---|
| string |

## CurrencyReferenceEnumeration

*Part of: [CurrencyObjectID](#currencyobjectid)*

| Base Type |
|---|
| string |

## CompanyReferenceEnumeration

*Part of: [CompanyObjectID](#companyobjectid)*

| Base Type |
|---|
| string |

## Billable_EntityReferenceEnumeration

*Part of: [Billable_EntityObjectID](#billable_entityobjectid)*

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

## Business_Entity_ContactReferenceEnumeration

*Part of: [Business_Entity_ContactObjectID](#business_entity_contactobjectid)*

| Base Type |
|---|
| string |

## Schedule_Distribution_MethodReferenceEnumeration

*Part of: [Schedule_Distribution_MethodObjectID](#schedule_distribution_methodobjectid)*

| Base Type |
|---|
| string |

## Frequency_BehaviorReferenceEnumeration

*Part of: [Frequency_BehaviorObjectID](#frequency_behaviorobjectid)*

| Base Type |
|---|
| string |

## Billing_PeriodReferenceEnumeration

*Part of: [Billing_PeriodObjectID](#billing_periodobjectid)*

| Base Type |
|---|
| string |

## Proration_MethodReferenceEnumeration

*Part of: [Proration_MethodObjectID](#proration_methodobjectid)*

| Base Type |
|---|
| string |

## Day_of_the_WeekReferenceEnumeration

*Part of: [Day_of_the_WeekObjectID](#day_of_the_weekobjectid)*

| Base Type |
|---|
| string |

## Schedule_TypeReferenceEnumeration

*Part of: [Schedule_TypeObjectID](#schedule_typeobjectid)*

| Base Type |
|---|
| string |

## Milestone_AbstractReferenceEnumeration

*Part of: [Milestone_AbstractObjectID](#milestone_abstractobjectid)*

| Base Type |
|---|
| string |

## Billable_Transaction_Attachment_TypeReferenceEnumeration

*Part of: [Billable_Transaction_Attachment_TypeObjectID](#billable_transaction_attachment_typeobjectid)*

| Base Type |
|---|
| string |

## Project_Invoice_Summary_DefinitionReferenceEnumeration

*Part of: [Project_Invoice_Summary_DefinitionObjectID](#project_invoice_summary_definitionobjectid)*

| Base Type |
|---|
| string |

## Billing_CycleReferenceEnumeration

*Part of: [Billing_CycleObjectID](#billing_cycleobjectid)*

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

## Invoice_TypeReferenceEnumeration

*Part of: [Invoice_TypeObjectID](#invoice_typeobjectid)*

| Base Type |
|---|
| string |

## Customer_Invoice_TypeReferenceEnumeration

*Part of: [Customer_Invoice_TypeObjectID](#customer_invoice_typeobjectid)*

| Base Type |
|---|
| string |

## Document_Delivery_TypeReferenceEnumeration

*Part of: [Document_Delivery_TypeObjectID](#document_delivery_typeobjectid)*

| Base Type |
|---|
| string |

## Interest_Rate_RuleReferenceEnumeration

*Part of: [Interest_Rate_RuleObjectID](#interest_rate_ruleobjectid)*

| Base Type |
|---|
| string |

## Late_Fee_RuleReferenceEnumeration

*Part of: [Late_Fee_RuleObjectID](#late_fee_ruleobjectid)*

| Base Type |
|---|
| string |

## Receivable_Contract_Line_AbstractReferenceEnumeration

*Part of: [Receivable_Contract_Line_AbstractObjectID](#receivable_contract_line_abstractobjectid)*

| Base Type |
|---|
| string |

## Billing_InstallmentReferenceEnumeration

*Part of: [Billing_InstallmentObjectID](#billing_installmentobjectid)*

| Base Type |
|---|
| string |

## Unit_of_MeasureReferenceEnumeration

*Part of: [Unit_of_MeasureObjectID](#unit_of_measureobjectid)*

| Base Type |
|---|
| string |

## Tax_ApplicabilityReferenceEnumeration

*Part of: [Tax_ApplicabilityObjectID](#tax_applicabilityobjectid)*

| Base Type |
|---|
| string |

## Tax_CodeReferenceEnumeration

*Part of: [Tax_CodeObjectID](#tax_codeobjectid)*

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

## Customer_Installment_ItemReferenceEnumeration

*Part of: [Customer_Installment_ItemObjectID](#customer_installment_itemobjectid)*

| Base Type |
|---|
| string |

## Prepaid_Installment_and_MappingReferenceEnumeration

*Part of: [Prepaid_Installment_and_MappingObjectID](#prepaid_installment_and_mappingobjectid)*

| Base Type |
|---|
| string |

## Prepaid_MappingReferenceEnumeration

*Part of: [Prepaid_MappingObjectID](#prepaid_mappingobjectid)*

| Base Type |
|---|
| string |
