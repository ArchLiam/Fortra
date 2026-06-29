# Evidence — Full consumer audit (both model fields)

Source: multi-agent code sweep (`grep -rn` over `classes/`, `flows/`, `lwc/`) + hand verification.
"Breaks if blank" = does production behavior degrade when the model lives in `iSeries_Model__c` and the
consumer reads `Model_Number__c` (null for iSeries)?

## `Model_Number__c` consumers

### Genuine impact (iSeries only)
- **hardwareGroupManager.js:121** — `{ label:'Model', fieldName:'Hardware__r.Model_Number__c' }` (group datatable col) → blank.
- **hardwareGroupManager.js:130** — `{ label:'Model', fieldName:'Model_Number__c' }` (hardware datatable col) → blank.
- **hardwareGroupManager.js:822** — `Model_Number__c: this.selectedGroup.Hardware__r?.Model_Number__c` (edit hydration) → blank.
- **hardwareGroupManager.html:312 / :611** — `<dd>{selectedHardware.Model_Number__c}</dd>` (detail cards) → blank.
- **hardwareManagementModal.html:239-240** — `<template if:true={hw.Model_Number__c}>Model: {hw.Model_Number__c}` → "Model:" line suppressed for iSeries.
- **HardwareGroupController.cls:58** — `Hardware__r.Model_Number__c` in group SELECT (display).
- **HardwareGroupController.cls:103** — `WHERE Model_Number__c LIKE :modelFilter` → **model search misses iSeries rows**.
- **HardwareGroupController.cls:116** — hardware search SELECT (display).
- **HardwareGroupController.cls:204-205** — write `Model_Number__c` only if key present → **dead** (LWC never sends it).
- **HardwareGroupController.cls:395** — unassigned-hardware SELECT (display).
- **HardwareManagementController.cls:209-211** — conditionally add `Model_Number__c` to dynamic SELECT (display).
- **HardwareManagementController.cls:324-325** — `Model_Number__c LIKE :searchPattern` → **free-text search misses iSeries codes**.

### Integration — structurally reads it, no live impact today
- **BSSOrderInfoRestService.cls:104** — `SELECT Hardware_ID__r.Model_Number__c`.
- **BSSOrderInfoRestService.cls:183/198** — `this.model = item.Hardware_ID__r?.Model_Number__c` → outbound BSS `model`.
  - Reads via `Hardware_ID__c` (not `Hardware__c`). Only **2 OrderItems** reach the 46 HW via that lookup, both **Draft** → nothing transmitted. No iSeries fallback exists, so it's a latent gap if iSeries orders ever activate.

### Latent data-fidelity (independent of SC-3468)
- **PowerOrderSplittingService.cls:410** — `SELECT ... Model_Number__c` (no `iSeries_Model__c`).
- **PowerOrderSplittingService.cls:424** — `cloned.Model_Number__c = original.Model_Number__c` → splitting an iSeries HW loses the model on clones. Rare; **separate ticket**.

### Safe — model is not used in logic
- **HardwareAttributePricingPrehook.cls:530/629/674** — price from `P_Group_List__c`+`Server_Type__c`+`Users_Per_Partition__c`; model is **audit-JSON only**. No pricing change.
- **HardwareProductEligibilityService.cls:46** — eligibility from `Number_of_Processors__c`+`Feature_Code__c`+`Product2.Type`; model never read in a rule.
- **HardwareProductSelectorController.cls:42/132** — `this.modelNumber = hardware.Model_Number__c` as header context only; not used in `addProductsToQuote`.

### Not a live consumer
- **flows/Hardware_Selection_Screen.flow:115** — `[PLACEHOLDER]` developer note listing intended columns; the flow doesn't read the field yet.

### False positives — different object/field or test-only
- **LicenseKeyEmailHandler.cls:54**, **LkgRecordCreator{LegacyIbm:8, HalcyonIbm:5, Powertech:8, Robot:8, Sequel:8}**, **LkgRequestBuilder\*** — all reference **`License_Key__c.LPAR_Model_Number__c`** from the inbound LKG JSON, **not** `Hardware__c.Model_Number__c`. No FK to the hardware model. Zero impact.
- **QuoteLineItemTriggerHandlerTest.cls:80**, **OpportunityTriggerHandlerTest.cls:69/80/296** — test fixtures only; the production handlers do not read `Model_Number__c`.
- **FortraDemoDataFactory.cls:410/423** — seed data; sets `Model_Number__c` = full name AND `iSeries_Model__c` = short code on the same record (evidence the two fields are semantically distinct).

## `iSeries_Model__c` consumers

- **hardwareGroupManager.js:737** — `hardwareData.iSeries_Model__c = this.newHardware.iSeriesModel` (the only model write). Client validation (`js:702-704`) requires it for iSeries.
- **HardwareGroupController.cls:170-171** — persist (null-safe).
- **HardwareGroupController.cls:437-438** — build the `iSeriesModel` combobox options from the `iSeries_Model__c` describe.
- **HardwareGroupController.cls:486** — `iSeries_Model__c` as the **controlling field** in `getFeatureCodeOptions`.
- **objects/Hardware__c/fields/iSeries_Feature_Code__c.field-meta.xml:12** — `<controllingField>iSeries_Model__c</controllingField>` (the dependency lock).
- **flows/Fortra_Hardware_Hardware_Creation_Subflow.flow:158** — optional assignment.
- **flows/Fortra_Hardware_Hardware_Management_Orchestrator.flow:221** — `ISeriesModelChoices` dynamic choice set; screen field labeled "iSeries Model" (`:388`).
- **objects/Hardware__c/listViews/All_Hardware.listView:13** — filter `iSeries_Model__c != null`.
- **FortraDemoDataFactory.cls:411/424** — seed literals (`9080-M9S`, `9105-22A`).

None throw on blank `iSeries_Model__c`.
