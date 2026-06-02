# Put_Multiple-Element_Revenue_Allocation — Workday Revenue Management API (v46.1)

> **Operation:** `Put_Multiple-Element_Revenue_Allocation`  
> **Purpose (per SC-3143):** Revenue Data (MEA)  
> **Source:** https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Put_Multiple-Element_Revenue_Allocation.html  
> **Schema:** [WSDL](https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Revenue_Management.wsdl) · [XSD](https://community.workday.com/sites/default/files/file-hosting/productionapi/Revenue_Management/v46.1/Revenue_Management.xsd)  
> **API version:** v46.1 (Workday Community public docs)  
> **Extracted:** 2026-06-01 — deterministic parse of the source HTML (fields + nested per-field validation rules; lossless).  
> **Data types documented:** 22 (7 primary, 10 reference, 5 enumeration)

## Data type index

| # | Data type | Category |
|---|---|---|
| 1 | [Put_Multiple-Element_Revenue_Allocation_Request](#put_multiple-element_revenue_allocation_request) | primary |
| 2 | [Put_Multiple-Element_Revenue_Allocation_Response](#put_multiple-element_revenue_allocation_response) | primary |
| 3 | [Customer_ContractObject](#customer_contractobject) | reference |
| 4 | [Customer_ContractObjectID](#customer_contractobjectid) | reference |
| 5 | [MEA_Customer_Contract_Data](#mea_customer_contract_data) | primary |
| 6 | [CurrencyObject](#currencyobject) | reference |
| 7 | [CurrencyObjectID](#currencyobjectid) | reference |
| 8 | [Revenue_Allocation_Calculation_BasisObject](#revenue_allocation_calculation_basisobject) | reference |
| 9 | [Revenue_Allocation_Calculation_BasisObjectID](#revenue_allocation_calculation_basisobjectid) | reference |
| 10 | [MEA_Customer_Contract_Line_Data](#mea_customer_contract_line_data) | primary |
| 11 | [Customer_Contract_LineObject](#customer_contract_lineobject) | reference |
| 12 | [Customer_Contract_LineObjectID](#customer_contract_lineobjectid) | reference |
| 13 | [Revenue_TreatmentObject](#revenue_treatmentobject) | reference |
| 14 | [Revenue_TreatmentObjectID](#revenue_treatmentobjectid) | reference |
| 15 | [Application_Instance_Related_Exceptions_Data](#application_instance_related_exceptions_data) | primary |
| 16 | [Application_Instance_Exceptions_Data](#application_instance_exceptions_data) | primary |
| 17 | [Exception_Data](#exception_data) | primary |
| 18 | [Customer_ContractReferenceEnumeration](#customer_contractreferenceenumeration) | enumeration |
| 19 | [CurrencyReferenceEnumeration](#currencyreferenceenumeration) | enumeration |
| 20 | [Revenue_Allocation_Calculation_BasisReferenceEnumeration](#revenue_allocation_calculation_basisreferenceenumeration) | enumeration |
| 21 | [Customer_Contract_LineReferenceEnumeration](#customer_contract_linereferenceenumeration) | enumeration |
| 22 | [Revenue_TreatmentReferenceEnumeration](#revenue_treatmentreferenceenumeration) | enumeration |

---

## Put_Multiple-Element_Revenue_Allocation_Request

*Element containing Customer Contract reference for update and all Customer Contract data items relevant to Multiple-Element Revenue Allocation.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @version | string | [0..1] | Web Service version |  |
| Customer_Contract_Reference | Customer_ContractObject | [1..1] | Reference to an existing Customer Contract for update only purposes. |  |
| Customer_Contract_Data | MEA_Customer_Contract_Data | [1..1] | Contains customer contract data. | Ensure the total revenue override amount matches the total contract amount. To automatically calculate the total revenue override amount, leave the revenue override amounts empty.<br>To exclude range calculations for revenue allocation, set the No Allocation Threshold field as true.<br>Specify all contract lines for the customer contract. Exclude any cancelled or terminated lines. Ensure that all contract lines are for the same customer contract.<br>Leave the Currency Reference field empty or specify the existing currency for the customer contract.<br>Ensure the total revenue override amount matches the sum of all child contract amounts. To automatically calculate the total revenue override amount, leave the revenue override amounts empty.<br>Specify all child contract lines for the linked customer contract. Exclude any cancelled or terminated lines. Ensure that all contract lines are child lines for the same linked customer contract.<br>Customer contract ID submitted in Customer Contract Reference doesn't match the ID submitted in Customer Contract ID. Leave the Customer Contract ID field empty or specify the same ID for both fields. |

| col1 |
|---|
| To run this web service, specify a customer contract that is not in Approval in Process or Amendment in Process status. |

## Put_Multiple-Element_Revenue_Allocation_Response

*Response element for Put Multiple-Element Revenue Allocation request.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| @version | string | [0..1] | Web Service version |  |
| Customer_Contract_Reference | Customer_ContractObject | [0..1] | Customer Contract Response Reference. |  |
| Exceptions_Response_Data | Application_Instance_Related_Exceptions_Data | [0..*] | Element containing Exceptions Data |  |

## Customer_ContractObject

*Part of: [Put_Multiple-Element_Revenue_Allocation_Request](#put_multiple-element_revenue_allocation_request), [Put_Multiple-Element_Revenue_Allocation_Response](#put_multiple-element_revenue_allocation_response)*

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

## MEA_Customer_Contract_Data

*Part of: [Put_Multiple-Element_Revenue_Allocation_Request](#put_multiple-element_revenue_allocation_request) — Contains customer contract data.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Customer_Contract_ID | string | [0..1] | Customer Contract ID. This is the Customer Contract Unique Identifier. |  |
| Currency_Reference | CurrencyObject | [0..1] | The Reference ID for the currency on the contract. |  |
| No_Allocation_Threshold | boolean | [0..1] | If true, the upper and lower range percentage for a company is set to 0. |  |
| Lower_Range_Percentage | decimal (10, 4) >0 | [0..1] | The lower range percentage for the company as a demical. |  |
| Upper_Range_Percentage | decimal (10, 4) >0 | [0..1] | The upper range percentage for the company as a decimal. |  |
| Allocation_Basis_Reference | Revenue_Allocation_Calculation_BasisObject | [1..1] | The revenue allocation calculation basis. |  |
| Auto-Update_Revenue_Recognition_Schedule | boolean | [0..1] | If true, automatically recalculates the revenue recognition schedule upon submission. |  |
| Customer_Contract_Line_Data | MEA_Customer_Contract_Line_Data | [0..*] | Contains customer contract line data. | Contract line can't be both excluded and fixed.<br>Leave the Revenue Treatment Reference field empty or specify the existing revenue treatment for contract line [contractLineRef] ([contractLine]).<br>[contractLineRef] ([contractLine]) is not the parent contract line for [linkedLineRef] ([linkedLine]). Ensure that all Contract Line Reference values submitted are the parent lines for the Linked Contract Line Reference values submitted.<br>Specify a Linked Contract Line Reference for every line of a linked contract.<br>You can't modify a parent line [plineRef] ([pline]) that is canceled or terminated. If you leave the parent line reference empty, Workday will create a new parent line for an active child contract line. |

| col1 |
|---|
| Ensure the total revenue override amount matches the total contract amount. To automatically calculate the total revenue override amount, leave the revenue override amounts empty.<br>To exclude range calculations for revenue allocation, set the No Allocation Threshold field as true.<br>Specify all contract lines for the customer contract. Exclude any cancelled or terminated lines. Ensure that all contract lines are for the same customer contract.<br>Leave the Currency Reference field empty or specify the existing currency for the customer contract.<br>Ensure the total revenue override amount matches the sum of all child contract amounts. To automatically calculate the total revenue override amount, leave the revenue override amounts empty.<br>Specify all child contract lines for the linked customer contract. Exclude any cancelled or terminated lines. Ensure that all contract lines are child lines for the same linked customer contract.<br>Customer contract ID submitted in Customer Contract Reference doesn't match the ID submitted in Customer Contract ID. Leave the Customer Contract ID field empty or specify the same ID for both fields. |

## CurrencyObject

*Part of: [MEA_Customer_Contract_Data](#mea_customer_contract_data)*

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

## Revenue_Allocation_Calculation_BasisObject

*Part of: [MEA_Customer_Contract_Data](#mea_customer_contract_data)*

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

## MEA_Customer_Contract_Line_Data

*Part of: [MEA_Customer_Contract_Data](#mea_customer_contract_data) — Contains customer contract line data.*

| Parameter name | Type/Value | Cardinality | Description | Validations |
|---|---|---|---|---|
| Contract_Line_Reference | Customer_Contract_LineObject | [0..1] | A reference to an existing receivable contract line. |  |
| Linked_Contract_Line_Reference | Customer_Contract_LineObject | [0..1] | A reference to a receivable contract line of a linked contract's child contract. Not applicable for standard (non-linked) contracts. |  |
| Revenue_Treatment_Reference | Revenue_TreatmentObject | [0..1] | If true, the customer contract line has deferred revenue. |  |
| Exclude_From_Calculation | boolean | [0..1] | If true, excludes the contract line from the revenue allocation calculation. |  |
| Fixed | boolean | [0..1] | If true, sets the revenue override amount to fair value extended amount. |  |
| SSP__FV__Unit_Price | decimal (21, 6) | [0..1] | The fair value unit price. Workday ignores this field in the Put Multiple-Element Revenue Allocation web service operation and automatically calculates the Fair Value Unit Price value based on the Fair Value Extended Amount value. |  |
| SSP__FV__Extended_Amount | decimal (18, 3) | [0..1] | The fair value unit price multiplied by the quantity. |  |
| Revenue_Override_Amount | decimal (26, 6) | [0..1] | The customer contract line revenue override amount. |  |

| col1 |
|---|
| Contract line can't be both excluded and fixed.<br>Leave the Revenue Treatment Reference field empty or specify the existing revenue treatment for contract line [contractLineRef] ([contractLine]).<br>[contractLineRef] ([contractLine]) is not the parent contract line for [linkedLineRef] ([linkedLine]). Ensure that all Contract Line Reference values submitted are the parent lines for the Linked Contract Line Reference values submitted.<br>Specify a Linked Contract Line Reference for every line of a linked contract.<br>You can't modify a parent line [plineRef] ([pline]) that is canceled or terminated. If you leave the parent line reference empty, Workday will create a new parent line for an active child contract line. |

## Customer_Contract_LineObject

*Part of: [MEA_Customer_Contract_Line_Data](#mea_customer_contract_line_data)*

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

## Revenue_TreatmentObject

*Part of: [MEA_Customer_Contract_Line_Data](#mea_customer_contract_line_data)*

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

## Application_Instance_Related_Exceptions_Data

*Part of: [Put_Multiple-Element_Revenue_Allocation_Response](#put_multiple-element_revenue_allocation_response) — Element containing Exceptions Data*

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

## CurrencyReferenceEnumeration

*Part of: [CurrencyObjectID](#currencyobjectid)*

| Base Type |
|---|
| string |

## Revenue_Allocation_Calculation_BasisReferenceEnumeration

*Part of: [Revenue_Allocation_Calculation_BasisObjectID](#revenue_allocation_calculation_basisobjectid)*

| Base Type |
|---|
| string |

## Customer_Contract_LineReferenceEnumeration

*Part of: [Customer_Contract_LineObjectID](#customer_contract_lineobjectid)*

| Base Type |
|---|
| string |

## Revenue_TreatmentReferenceEnumeration

*Part of: [Revenue_TreatmentObjectID](#revenue_treatmentobjectid)*

| Base Type |
|---|
| string |
