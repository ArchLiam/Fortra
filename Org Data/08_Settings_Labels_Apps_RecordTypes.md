# 08 — Custom Settings, Labels, Apps & Record Types

**Overview.** This doc covers four small but org-defining configuration areas in the Fortra Salesforce org: custom **Settings** (hierarchy/list config objects), custom **Labels** (translatable/text constants), custom **Applications** (the Lightning apps users actually open), and custom **Record Types** (per-object record variants). The vast majority of the org's settings/labels/record types come from managed packages (`pse__` PSA, `c2g__`/`ffr__`/`fferpcore__` FinancialForce/Certinia accounting, `ffrr__` Rev Mgmt, `omnistudio__`, `salesintelio__`, `LID__`, etc.) and are **out of scope** here — only the no-namespace, locally-authored items are documented below. Net-net there is very little custom config: **2 custom settings, 1 custom label, 12 apps, and a handful of custom-object record types**, which makes each one disproportionately load-bearing.

---

## 1. Custom Settings (no-namespace)

Only two custom settings are locally authored. Everything else under `_customsettings.json` is managed-package config (`c2g__*`, `pse__*`, `ffrr__*`, `fferpcore__*`, `omnistudio__*`, `salesintelio__*`, `LID__*`).

| API Name | Type / Visibility | Purpose | Fields |
|---|---|---|---|
| `In_App_Checklist_Settings__c` | **Hierarchy**, Protected | Holds attributes for the "In App Checklist" onboarding/guidance experience. Hierarchy type → can be defaulted org-wide and overridden per profile/user. | `ProfileKey__c` (Text 255 — keys the checklist to a profile), `Sales_Cloud_In_App_Page__c` (URL — the in-app guidance page to launch) |
| `FFX_Package_Version__c` | **List**, Public | Records package-version info for **FF Accelerate ("FFX")** components — i.e. a manifest of which accelerator suites/versions are installed. Read-only reference data, queried for version gating/diagnostics. | `FFX_Product_Suite_Name__c` (Text 255, required), `FFX_Version_Name__c` (Text 255, required), `FFX_Version__c` (Text 20, **required + unique** — the version key) |

**Notes / non-obvious:**
- `In_App_Checklist_Settings__c` is **Protected** (not visible to subscriber-installed packages) and Hierarchy-typed, so per-profile overrides via `ProfileKey__c` are the intended usage pattern.
- `FFX_Package_Version__c` is **List**-typed with a unique `FFX_Version__c` key — treat it as a small reference table, not per-user config.

---

## 2. Custom Labels (no-namespace)

The retrieved `CustomLabels.labels-meta.xml` contains exactly **one** no-namespace label. (All other labels in the org belong to managed packages and are excluded.)

| Label (fullName) | Value | Purpose / Notes |
|---|---|---|
| `Google_API_Key` | `AIzaSyAbNWzIfmhadmTJxAocZCrZnQI9MoUD_6c` | Google Maps / Google API key consumed by Google-Maps-driven features (and likely the `pse__Google_Maps_Settings__c` PSA mapping UI). **Unprotected** (`protected=false`), `language=en_US`. **Fragile / sensitive:** a live API key stored in plaintext metadata and committed to source — rotate-on-leak risk; do not treat as a secret store. Any feature that geocodes addresses or renders maps depends on this label resolving. |

---

## 3. Custom Applications (12)

All 12 are locally authored Lightning apps (except UAT CLASSIC, which is Classic). They map almost 1:1 to user personas / job functions. `navType=Console` apps give a tabbed-workspace UI; `Standard` apps are single-pane.

### Core sales & revenue apps

| App (label) | API Name | Nav | What it's for |
|---|---|---|---|
| **Fortra Sales** | `Fortra_Sales` | **Console** | Fortra's primary day-to-day Sales app. Broadest tab set (17): Leads, Opportunities, Accounts, Contacts, Action Cadences, Campaigns, Forecasting, plus Fortra-custom objects **Hardware**, **Product Description**, **Quote Checklist Item**, **Regional Pricing**, **Account Temperature History**, **Export License Document**. This is the workspace where the RCA quoting/pricing custom objects surface. |
| **Revenue Cloud** | `Revenue_Cloud` | Standard | The Revenue Cloud / RCA workflow surface: Account → Opportunity → **Quote → Order → Asset → Contract** plus Product2. The end-to-end quote-to-cash navigation used for RLM/Subscription-Mgmt work. |
| **Inside Sales** | `Inside_Sales` | Standard | Lead generation / prospect qualification & nurture (SDR-style). Standard Salesforce "Inside Sales" template. |
| **Sales Operations** | `Sales_Operations` | Standard | Sales-process customization, automation, and data analysis for Sales Ops (12 tabs). |
| **Sales Leader** | `Sales_Leader` | Standard | Manager view — monitor team sales activity and targets. |
| **Success Manager** | `Success_Manager` | Standard | Customer-success / renewals workspace (relationships, renewals, organization). Relevant to the COLA renewal-pricing domain. |

### Delivery / services (PSA) apps

| App (label) | API Name | Nav | What it's for |
|---|---|---|---|
| **Fortra - Consultant** | `Fortra_Consultant` | Standard | Landing app for Fortra Consultants (PSA delivery resources). 6 tabs. |
| **Fortra - Project Management** | `Fortra_Project_Management` | Standard | App for Fortra Project Managers — largest PSA app (13 tabs). |

### Platform / QA / UAT apps

| App (label) | API Name | Nav | What it's for |
|---|---|---|---|
| **Platform Dev/Test** | `Platform_DevTest` | Standard | Minimal landing page for platform developers & testers (just Accounts + Contacts, 2 tabs). |
| **UAT** | `UAT_Lightning` | Standard | UAT test-management (Lightning). Tabs: **Master Test Case**, **Test Cases**, **Test Case Issues**, Reports, Dashboards, Feed. Drives the custom UAT/QA object suite. |
| **UAT Console** | `UAT_Console` | **Console** | Console-mode variant of the UAT test-management app (same Master Test Case / Test Cases / Test Case Issues tabs). |
| **UAT CLASSIC** | `UAT_CLASSIC` | Classic (`uiType` not Lightning) | Salesforce **Classic** version of the UAT app (Test Cases, Test Case Issues, Master Test Case, Reports, Dashboards). Legacy — kept for Classic-only testers; the "(Classic)" record types feed it. |

**Notes:**
- The three UAT apps (`UAT_Lightning`, `UAT_Console`, `UAT_CLASSIC`) are three skins over the **same** custom QA objects (`Master_Test_Case__c`, `Test_Cases__c`, `Test_Case_Issues__c`) — see the matching "(Classic)" record types below.
- `Fortra_Sales` is the only place several Fortra-custom objects (Hardware, Regional Pricing, Export License Document, Quote Checklist Item, Account Temperature History) get first-class tabs.

---

## 4. Record Types (custom objects / no managed namespace)

Filtered to custom (`__c`) objects and standard objects with **no** managed-package namespace. Managed-package record types (`c2g__*`, `ffr__*`, `fferpcore__*`, `ffban__*`, `pse__*`) are excluded.

### UAT / QA test-management objects
Backs the UAT apps above; the "(Classic)" variants pair with the **UAT CLASSIC** app.

| SobjectType | DeveloperName | Record-type label |
|---|---|---|
| `Master_Test_Case__c` | `Master_Test_Case` | Master Test Case |
| `Master_Test_Case__c` | `Master_Test_Case_Classic` | Master Test Case (Classic) |
| `Test_Cases__c` | `Master_Test_Cases` | Master Test Cases |
| `Test_Cases__c` | `Test_Cases` | Test Cases |
| `Test_Cases__c` | `Test_Cases_Classic` | Test Cases (Classic) |
| `Test_Case_Issues__c` | `Test_Case_Issues_Classic` | Test Case Issues |

### Standard objects (no namespace) — custom record types

| SobjectType | DeveloperName | Record-type label | Notes |
|---|---|---|---|
| `Knowledge__kav` | `Internal_Content` | Internal Content | Knowledge article audience split — internal vs partner. |
| `Knowledge__kav` | `Partner_Content` | Partner Content | Partner-community-facing Knowledge. |
| `Contact` | `PSA_Resource` | PSA Resource | Contact representing a billable PSA delivery resource (Certinia PSA pattern). |
| `Contact` | `CRM_Contact` | CRM Contact | Standard CRM contact (non-resource). |
| `Contract` | `ContractLifecycleManagement` | Contract Lifecycle Management | CLM-enabled Contract record type. |
| `Product2` | `Technical_Product` | Technical Product | Product2 variant for technical/hardware products — relevant to RCA catalog (Hardware object + Product2 in Revenue Cloud app). |

**Notes / non-obvious:**
- `Contact.PSA_Resource` vs `CRM_Contact` is the load-bearing split between Certinia-PSA delivery resources and ordinary CRM contacts — automation and PSA assignment keys off it.
- The "(Classic)" record types exist **only** to feed the legacy `UAT_CLASSIC` Classic app; deleting them would break that app's page layouts.
- `Product2.Technical_Product` is the only custom Product2 record type — pricing/RCA logic that branches on product kind should be checked against it.
