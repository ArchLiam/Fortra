# BSI Discovery — Power BI Reports, Dataflows & Lineages (Customer Engagement / Services)

**Scope:** `BSI Discovery Info/Reports/` — the legacy Power BI estate that BSI (Business Systems & Innovation) ran for Fortra's **Customer Engagement (CE / Professional Services)** organisation and **Finance**. This documents the report inventory, every dataflow's source systems and queries, the data lineages, and the legacy SQL views feeding the older Services reporting. It is the raw-discovery counterpart to the design KB; it tells you **what reporting must be reproduced on Salesforce RCA + Workday** after the CRM consolidation, and **exactly where the numbers come from today**.

> **Why this matters for the migration:** every dataflow below ultimately reads from **D365/Dynamics (`hsprod.crm.dynamics.com`)**, the **Tripwire Salesforce** org, the **Globalscape Salesforce** org, **SharePoint Excel exports** (ADP payroll, work calendars, Alert Logic onboarding forms), and **Microsoft Customer Voice** (survey org `org5ade7db4.crm.dynamics.com`). When those source CRMs are retired into Salesforce RCA and Workday, these reports break unless their source queries are repointed. The Services *utilisation*, *project hours/backlog*, *billings* and *CSAT/NPS* logic captured here is the functional spec for the replacement reporting.

---

## 1. Report inventory

The discovery package contains **5 Power BI report files (`.pbix`)** plus their backing Power BI **dataflows** (Power Query / `model.json` definitions), **lineage diagrams**, and **legacy T-SQL views**.

| Report (`.pbix`) | Workspace | Purpose | Backing semantic model | Status of file |
|---|---|---|---|---|
| **CE Customer Engagement** | Customer Engagement | Account-level customer-success / engagement 360 (ARR, temperature, risk, cases, surveys, engagements, activities) | `CE Customer Engagement` semantic model | **BINARY — not extractable** (137 MB `.pbix`) |
| **CE Services Delivery** | Customer Engagement | Services project delivery: projects, hours, budget, backlog, risk, opportunity/services value, CSAT | `CE Services Delivery` semantic model | **BINARY — not extractable** (15 MB) |
| **CE Utilisation** | Customer Engagement | Consultant utilisation: logged vs available hours, FTO/leave, capacity by country/manager | `CE Utilisation` semantic model | **BINARY — not extractable** (24 MB) |
| **Services Project Hours** | Customer Engagement | Project-hours fact reporting (revenue, billable, late entry) — fed by **HSWarehouse SQL views**, not the dataflows | (self-contained `.pbix`) | **BINARY — not extractable** (3.3 MB) |
| **Adapted Billings Report** | **Finance Reports** | Finance billings report | (self-contained `.pbix`) | **BINARY — not extractable** (116 MB) — **no dataflows/lineage/SQL supplied; the only Finance artifact in scope and it is opaque** |

> The `.pbix` files are zipped binary (DataModel/Report layout) and were **not** extracted to text. The recoverable design intent lives in the **dataflows** (full Power Query M is in the `.json` definitions) and the **SQL views** below. Visual layout, DAX measures, and the `Adapted Billings` logic are **not recoverable** from this package.

---

## 2. Lineage — how data flows to each report

Power BI lineage (from the three `Lineages/*.png`): **Source dataflows → "Linking" dataflows → Semantic model → Report.** Reproduced from the vision reads of the lineage diagrams.

### 2.1 CE Customer Engagement report lineage
[CE Customer Engagement Report Lineage.png](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Lineages/CE Customer Engagement Report Lineage.png)

Feeds the **`CE Customer Engagement` semantic model → `CE Customer Engagement` report**:
- `Linking_1_D365_Projects`, `Linking_1_D365_Accounts`, `Linking_2_Engagement_D365`, `Linking_1_D365_OLD`, `Linking_2_All_Hours`, `Linking_1_Tripwire`, `Linking_2_CustomerVoice_D365`, `Linking_1_Sharepoint_Utilisation`, `Source_Data_SFDC_Globalscape` (Customer Engagement Premium workspace)
- `D365 Datasets`, `CustomerVoice_ALERTLOGIC`, `D365 Activity`, `Smartsheet_FORTRA`, `Salesforce_GLOBALSCAPE`, `Salesforce_ALERTLOGIC` (Shared Services Dataflows_1/_2 workspaces)
- `SharePoint` (Services Operations workspace)
- The `CE Services Delivery` semantic model also chains into this report's lineage (shared upstream dataflows).

### 2.2 CE Services Delivery report lineage
[CE Services Delivery lineage.png](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Lineages/CE Services Delivery lineage.png)

Feeds the **`CE Services Delivery` semantic model → `CE Services Delivery` report** (and the shared `CE Customer Engagement` model/report). Upstream dataflows: `Linking_2_All_Hours`, `Linking_1_D365_Projects`, `Linking_1_Tripwire`, `CustomerVoice_ALERTLOGIC`, `D365 Activity`, `D365 Datasets`, `Linking_1_Sharepoint_Utilisation`, `Linking_2_CustomerVoice_D365`, `SharePoint`, `Smartsheet_FORTRA`, `Salesforce_GLOBALSCAPE`, `Salesforce_ALERTLOGIC`, `Source_Data_SFDC_Globalscape`.

### 2.3 CE Utilisation report lineage
[CE Utilisation lineage.png](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Lineages/CE Utilisation lineage.png)

The simplest chain. **3 dataflows → `CE Utilisation` semantic model → `CE Utilisation` report**:
- `Linking_2_All_Hours` (Gen2) — all CRM hours, enriched with ADP staffing
- `Source_Data_SharePoint` (Gen2) — ADP payroll, work calendars, leave (note: lineage labels it `Source_Data_SharePoint`; the supplied JSON is named `Source_Data_SharePoint` with dataflowId `a716c567-…`)
- `Linking_1_Sharepoint_Utilisation` (Gen2) — transformed ADP / weekly-hours / FTO

### 2.4 Dataflow dependency graph (from `dataflowId` cross-references in the M)
The "Linking" dataflows are **Gen2** compute layers that read **other dataflows' entities** via `PowerPlatform.Dataflows([])` navigation, keyed by `workspaceId` + `dataflowId`. Key IDs (all in workspace `0aeb26be-09b5-40bf-9441-adff4cd7e85c` = *Customer Engagement Premium* unless noted):

| dataflowId | Dataflow | Role |
|---|---|---|
| `a23db998-a35e-487b-a9b2-78b91617d990` | **D365 source layer** (Shared Services) | Raw D365 entities: `Source_Accounts`, `Source_Brand_Account`, `Source_Opportunity`, `Source_Projects`, `Source_projecthourses`, `Source_systemusers`, `Source_incident`, `Source_Engagement`, `Source_Cross_Team_Requests`, `Source_Temperature_Risk_Audit`, etc. |
| `a1d60fa1-a9bb-4bd2-ac5f-f0279989e982` | Accounts source (D365) | `Accounts`, `Brand Accounts`, `System Products`, `Brand_Team`, `Source_Selling_team` |
| `cf70f665-a62b-4f79-a644-67b08e899da2` | **`Linking_1_D365_Accounts`** | Produces `CS_Accounts`, `CS_Brand_Account`, `CS_Selling_Team`, `CS_System_Products`, `Temp_D365`, `Temp_D365_Activity_Append` |
| `d0538da6-a2ce-4a23-b492-db8661d5cec8` | **`Linking_1_D365_Projects`** | Produces `Transformed_Projects`, `Transformed_Hours`, `Transformed_Opportunity`, `Transformed_CTRs`, `Project_D365_Activity_Append`, `REF_Solution_Group` |
| `9ecdc2fd-33bf-4454-9b77-be11279e72cc` | **`Linking_1_Sharepoint_Utilisation`** | Produces `Transformed_ADP`, `Transformed_ADP_2_with_manager`, `Calendar_Hours`, `Transformed_FTO`, `Transformed_FTO_new` |
| `d03635ea-c14e-45a3-8c28-5411076a5a44` | **`Linking_1_Tripwire`** | Produces `Transformed_Hours`, `Transformed_Projects`, `Transformed_Opportunity` (Tripwire SF source) |
| `37f64040-0586-4eda-93af-5cfc1b2d3dd7` | Globalscape hours | `Transformed_Hours` (Globalscape) consumed by `Linking_2_All_Hours` |
| `f448be34-36cc-4a32-bae4-5b7c294ab912` | **`Linking_2_All_Hours`** | Unions D365 + Tripwire + Globalscape hours → `All_CRM_Hours`, `All_CRM_Hours_with_manager` |
| `a716c567-c73b-47fc-8745-14800f1a06b6` | **`Source_Data_SharePoint`** | SharePoint Excel source layer (ADP, calendars, leave, Alert Logic forms, Solution Structure) |
| `b6a5df5b-2217-4841-a4f7-0a35858837cf` | Tripwire SF source | `Account`, `Opportunity`, `Project`, `Timecard_Header_*` consumed by `Linking_1_Tripwire` |
| `83468185-e260-44ed-86cd-58c959297798` | Customer Voice response merge | `Merge_Response_nps`, `Merge_Response_Pro`, `Merge_Response_Supp` |
| `fc19734a-d73b-438f-8bac-8959da37a636` | Cases dataflow | `Case_D365` |
| `5de8793b-99e1-4c20-8f1c-031c13279c5f` (ws `1b31bc55-…`) | Region Mapping | Country→Region lookup |
| `53f6ed60-dabc-459e-a42a-47b65a7b7105` (ws `db01a80b-…`) | Risk & Issue – Active Projects | Project risk register |

**Tenant:** `ca81e23b-3509-45ee-a998-3e346acf274d`. Calculated entities land as **Parquet** (Gen2) or **CSV** (Gen1) in Azure blob `wabincusfpcdsa*.blob.core.windows.net`.

---

## 3. Source systems (the migration-critical part)

| Source system | Connection / endpoint | Used by | What it provides | Migration note |
|---|---|---|---|---|
| **D365 / Dynamics (Help Systems prod)** | `https://hsprod.crm.dynamics.com/` (Cds) | `D365 Datasets`, all `Linking_*_D365_*`, `Linking_2_Engagement_D365` | Accounts, Brand Accounts, System Products, Projects, Project Hours, Project Tasks, Opportunities, Sales Orders, Cases (incident), Engagements, Cross-Team Requests, Temperature/Risk Audit, system users, product brands | **Primary legacy CRM being retired into Salesforce RCA.** Every account/opportunity/project/hours field below must be re-sourced from SF objects. |
| **D365 Customer Voice (survey org)** | `https://org5ade7db4.crm.dynamics.com` (Cds) | `CustomerVoice_ALERTLOGIC`, `Linking_2_CustomerVoice_D365` | `msfp_*` survey entities (project/survey/question/invite/response/satisfactionmetric) — NPS, CSAT (Pro Services), Support surveys | Survey platform; CSAT/NPS reporting must be re-sourced post-migration |
| **Tripwire Salesforce** | via dataflow `b6a5df5b-…` (PSA/`pse__*` fields) | `Linking_1_Tripwire` | Tripwire Account/Opportunity/Project + **weekly timecard headers** (Sun–Sat), PSA hours | Legacy SF org being consolidated; PSA hours model differs from D365 |
| **Globalscape Salesforce** | dataflow `37f64040-…` + `Source_Data_SFDC_Globalscape`, `Salesforce_GLOBALSCAPE` | `Linking_2_All_Hours` | Globalscape services hours | Legacy SF org being consolidated |
| **SharePoint (Customer Engagement site)** | `https://helpsystemsllc.sharepoint.com/sites/Teams-CustomerEngagement` (Web/Excel.Workbook) | `Source_Data_SharePoint` | ADP payroll export, Work Calendars (company holidays + weekly hours by country), Time Off reports (2024/2025), **Alert Logic onboarding form outputs**, Solution Structure, Consultant list | Staffing/HR + onboarding data **outside CRM** — likely re-sourced from **Workday HR** (payroll/headcount) post-migration |
| **Alert Logic** | Microsoft Forms outputs in SharePoint `Automation/02 FORM OUTPUT/` | `Source_Data_SharePoint` | Kick-Off, Exposure, Implementation Design, Health, Incident onboarding checklists | Operational onboarding data |
| **ADP** | `Monthly ADP Report.xlsx`, `Time_off_report*.xlsx` (SharePoint) | utilisation chain | Payroll names, job titles, country, hire/term dates, scheduled hours, reports-to hierarchy, leave | **HR data → Workday**; the org-hierarchy "STOP" logic (below) becomes Workday manager hierarchy |
| **Smartsheet (Fortra)** | `Smartsheet_FORTRA` dataflow (Shared Services) | CE reports | (definition not in scope; referenced in lineage only) | Not extracted |

---

## 4. Dataflow-by-dataflow detail

### 4.1 `D365 Datasets` (Gen1, Shared Services Dataflows_2) — the raw D365 query layer
[D365 Datasets.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Shared Services Dataflows_2 Workspace/D365 Datasets.json) · modified 2025-03-28 · all queries read `hsprod.crm.dynamics.com` via `Cds.Entities`.

The canonical field-rename map from D365 logical names to report-friendly names. **This is the single most reusable artifact for the SF migration** — it tells you which D365 field each report column equals.

| D365 entity (`EntitySetName`) | Output entity | Key column renames (D365 → report) |
|---|---|---|
| `accounts` | **Accounts** | `accountnumber`→Account Number, `hs_accountarr_base`→Total Current ARR, `hs_accountarratrisk_base`→Account ARR at Risk, `hs_accountarrrisk_display`→Account ARR Risk, `hs_accounttemperature_display`→Account Temperature, `customertypecode_display`→Relationship Type, `hs_companysize_display`→Company Size, `hs_industry_display`→Industry, `hs_professionalservicessatisfactionscore`→CSAT Score, `hs_surveylastsent`→Survey Last Sent, `hs_vatnumber`→Account VAT Number, `hs_shiptocontinent_display`→**Account Region** (derived; see §6). Filters out `statuscode_display = Inactive`. |
| `hs_brandaccounts` | **Brand_Account** | `hs_arr_base`→Brand ARR, `hs_arratrisk_base`→Brand ARR at Risk, `hs_brandarrrisk2_display`→Brand ARR Risk, `hs_temperature_display`→Brand Temperature, `hs_customertypecode_display`→Brand Relationship Type, `hs_temperaturereason_display`→Brand Temperature Reason. Inactive filtered. |
| `hs_systemproductses` | **System_Products** | `hs_annualrecurringrevenue_base`→Annual Recurring Revenue, `hs_billingcode_display`→Billing Code, `hs_contractstartdate/enddate`→Contract Start/End Date, `hs_maintenancestartdate/enddate`→Maintenance Start/End Date, `hs_atrisk_maintenance_display`→At Risk Maintenance, `hs_systemproductname`→Product |
| `hs_projectses` | **hs_projects** | `hs_projectname`→Project Name, `hs_projectnumber`→Project Number (prefixed **`PN-`**), `hs_budgetamount_calc_base`→Budget Amount, `hs_budgethours_decimal`→Budget Hours, `hs_projecthourlyrate_base`→Project Hourly Rate, `hs_billableproject`→Billable Project Flag, `hs_projecttype_display`→Project Type, `hs_billedhours_rollup`→Actual Hours, `hs_billablehours_rollup`→Total Billable Time, `hs_basic_value_achieved`→Basic Value Achieved. Adds `System="D365"`. Filters out Abandoned/Cancelled/Lost/Inactive and pre-2023 closed projects. |
| `hs_projecttaskses` | **hs_projecttaskses** | `hs_projecttaskname`→Project Task Name. Active tasks only. |
| `hs_projecthourses` | **hs_projecthourses** | `hs_numberofhours`→Hours Logged, `hs_billablehours`→Billable Hours Flag, `hs_dateservicesperformed`→Date Services Performed (≥ 2022-12-29), `hs_forecastedhours`→Forecasted Hours Flag, `hs_serviceactivitytype_display`→Service Activity Type, `subject`→Hours Description, `hs_acenonbillabletype_display`→Non Billable Type. Adds `System="D365"`. |
| `opportunities` | **Opportunity** | `estimatedvalue_base`, `hs_totalservices_base`/`hs_estservicesrevenue_base`→**Services Value USD**, `hs_confidencepercentage_display`→Opportunity Probability, `hs_salesstages_display`→Opportunity Stage (Won override), `Opportunity Number="N/A-D365"`. Status in Accepted/Delivered/In Progress/Won; excludes Pre-Qualified. |
| `salesorders` | **salesorders** | `hs_totalservices_base`→Total Services USD, `totallineitemamount_base`→Total Order USD, `hs_ponumber`→PO Number, `hs_primaryproductbrand`→Primary Product Brand, `hs_rsm`→RSM. Excludes Canceled. |
| `hs_projectses` (2nd) | **hs_projects_AL_OTY_Lookup** | Extracts `OTY-####` opportunity number from project name; maps to `PN-####`. Alert-Logic OTY↔project cross-ref. |

### 4.2 `Linking_1_D365_Accounts` (Gen2) — Customer-success account model
[Linking_1_D365_Accounts.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_1_D365_Accounts.json) · modified 2024-12-24 · Parquet.

Builds the account/brand-account dimension consumed by the CE report. Output (loadEnabled) entities: **`CS_Accounts`** (distinct by Account Number), **`CS_Brand_Account`** (combine brand + non-brand accounts, joined to selling team: Assigned ISR, CSM, Renewal Owner, Service Delivery, Strategic AE, TAM, Enterprise AE, Data Manager Specialist), **`CS_Selling_Team`**, **`CS_System_Products`**, **`Temp_D365`**, **`Temp_D365_Activity_Append`**.

Key business logic:
- Composite lookup keys built throughout: **`AccId_Prod_Lookup` = `hs_account` + Product Brand**, **`BrandAccId_Prod_Lookup` = `hs_brandaccountid` + Product Brand**, **`AccId_Brand_Lookup`**. These are the join keys that stitch account ↔ brand ↔ product-brand ↔ activity. *Any SF reporting rebuild needs an equivalent composite key, since one account can have ARR split across multiple product brands.*
- **Temperature/Sentiment scoring** (`Temp_D365_Activity_Append`): maps temperature text to a numeric `Sentiment`: Low→4, Medium→5, High→6, Green→7, Yellow→8, Red→9, "Notified Lost"→10, else 0. Activity Subject derived from Risk Level / Temperature / Temperature Reason.
- Filters accounts to `Total Current ARR <> null and <> 0`.

> **`Linking_1_D365_OLD`** (Gen1, [Linking_1_D365_OLD.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_1_D365_OLD.json), described in-file as *"move all accounts off to accounts. Create cases only flow."*) is the **superseded predecessor** of `Linking_1_D365_Accounts`. It additionally builds **`Case_D365`** from D365 `incident`/`incidentresolution` (the cases pipeline), with case counts: Cases Created this Quarter, Count of Open Cases, Count of Feature Requests, Count of Escalated Cases. Resolution-date floor 2023-01-01. Still referenced in the CE Customer Engagement lineage, so cases reporting still routes through it.

### 4.3 `Linking_1_D365_Projects` (Gen2) — Services projects + hours + opportunity
[Linking_1_D365_Projects.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_1_D365_Projects.json) · modified 2025-01-23 · Parquet. The core **Services Delivery** model.

Output (loadEnabled): **`Transformed_Projects`**, **`Transformed_Hours`**, **`Transformed_Opportunity`**, **`Transformed_CTRs`**, **`Project_D365_Activity_Append`**, **`REF_Solution_Group`**.

- **`Transformed_Projects`** (~75 columns) joins projects to product brand, account, project owner/manager/consultant/services-coordinator (pivot of project team), parent project, child-project count, escalated open risks, and the full **opportunity** (close date, probability, stage, **Services Value USD**, region, brand product/solution/group). Adds `Count-Projects_Open` / `Count-Projects_Closed` from Project Status text.
- **`Transformed_Hours`** joins project hours → product brand → resource → account → project task → project, classifying internal (non-billable) hours into a **General Administration Category** (Internal Meetings / Administration / Individual Development / After Hours Travel / Other) by parsing the hours description. Hard-coded internal project/task GUIDs filter "Temp_hours_internal".
- **`REF_Solution_Group`** maps product brand → Solution → Group via the SharePoint `Solution Structure` table, plus a hard-coded `Manual-add_products` row.
- **`Project_D365_Activity_Append`** unions project milestone activities: **Project Kick Off** (start date), **Basic Value Achieved (TTBV)**, **Project Complete** (Closed-Completed / Closed-Expired / Closed-NSR Admin Only).

### 4.4 `Linking_1_Tripwire` (Gen2) — Tripwire PSA hours/projects/opportunities
[Linking_1_Tripwire.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_1_Tripwire.json) · modified 2025-01-06.

Sources Tripwire SF PSA: `Account`, `Opportunity`, `Project` (+ `Project_PublicTraining`), and **7 daily timecard headers** (`Timecard_Header_Sunday … Saturday`). Output: **`Transformed_Hours`** (Tripwire), **`Transformed_Opportunity`**, **`Transformed_Projects`** (`pse__*` PSA fields, e.g. `pse__Project__c`, `pse__Time_Credited__c`, `pse__Opportunity__c`).

Notable logic: a huge **Project Name → Project Task Name** remap normalising legacy Tripwire engagement names ("ExpertOps: Operational Support", "Field Development", "Pre-Sales", "TW@TW", etc.) into standardized **2023/2024/2025 Customer-Engagement task buckets** (Customer Pre-Sale Support, Onboarding, Operational, Renewal, Success Support, Channel Partner Engagement, Product & Release Support, Continuous Improvement, Education Services Content, General Internal). Billable filter = `Billable Hours Flag = true OR pse__Time_Credited__c = true`; excludes Bench/Holiday/PTO/Sick/Vacation/Travel project names.

### 4.5 `Linking_2_All_Hours` (Gen2) — unified cross-CRM hours fact
[Linking_2_All_Hours.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_2_All_Hours.json) · modified 2025-01-06.

**This is the unified Services-hours fact table** consumed by Utilisation and Services Delivery. Unions `Transformed_Hours` from **D365 + Tripwire + Globalscape** (`Append_Hours`), then joins to ADP staffing.
- **`All_CRM_Hours`** — append + `Transformed_ADP` (Job Title, Dept, Business Unit, Worked In Country, Consultant flag, Services Delivery, Reports To Name/Manager, Weekly Hours, PM Group, Hire/Termination Date) + computed **`Daily Hours` = Weekly Hours / 5**.
- **`All_CRM_Hours_with_manager`** — same but uses `Transformed_ADP_2_with_manager` (adds **Reports To Dept Lead**).
- ~50 columns including `Billable Hours Flag`, `Forecasted Hours Flag`, `Project Hourly Rate`, `Service Activity Type`, `System` (D365/Tripwire/Globalscape).

### 4.6 `Source_Data_SharePoint` (Gen2) — HR / calendars / Alert Logic forms
[Source_Data_SharePoint.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Source_Data_SharePoint.json) · modified 2025-04-01.

Reads Excel workbooks from `https://helpsystemsllc.sharepoint.com/sites/Teams-CustomerEngagement/Shared Documents/...`:

| Output entity | Source workbook | Content |
|---|---|---|
| `Monthly ADP Report` | `…/Power BI Central Export Reports/Monthly ADP Report.xlsx` | Payroll name, job title, dept, business unit, **Worked In Country**, hire/position-start/**termination date**, reports-to, scheduled hours. Builds **`STOP` / `STOP-Manager` / `STOP-Lead`** flags = hard-coded named leaders that terminate the manager-hierarchy walk (e.g. Brenda Wurst, Stephen Mason, Mark Bell, Kristi Schulte, Andrew Gittins…). |
| `ADP_Consultant List` | `…/ADP_Consultant List.xlsx` | Per-person **Consultant** + **Services Delivery** flags |
| `Work Calendars_Weekly Hours` | `…/Work Calendars_Company Holidays.xlsx` (row 1) | Standard weekly hours by country code (UK, USA, ARG, AUS, CAN, FRA, IND, SPA, ARM, SAU, SIN, MEX, POR, COL, GER, AND, PHI) |
| `Work Calendars_Company Holidays` | same workbook (rows 2+) | Public-holiday hours by date per country |
| `Time Off Report` / `_2024` / `_2025` | `Time_off_report*.xlsx` | Leave; Days→Hours conversion (×8); `System="ADP"`, `Service Activity Type="FTO"` |
| `Kickoff_Checklist`, `Exposure_Checklist`, `Implementation Design`, `Health_Checklist`, `Incident_Checklist` | `…/Automation/02 FORM OUTPUT/ALERTLOGIC_*.xlsx` | **Alert Logic customer onboarding** Microsoft Forms output (filtered to `Project Number` starting `PN-`). Implementation Design captures deep environment data: OS, firewalls, EDR/AntiVirus, auth apps, WAFs, node entitlement/usage, etc. |
| `Solution Structure` | `…/Solution Structure.xlsx` | Brand → Solution → Group mapping |

### 4.7 `Linking_1_Sharepoint_Utilisation` (Gen2) — utilisation calc engine
[Linking_1_Sharepoint_Utilisation.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_1_Sharepoint_Utilisation.json) · modified 2025-01-08.

Turns ADP + calendar data into capacity. Output: **`Transformed_ADP`**, **`Transformed_ADP_2_with_manager`** (adds Reports To Dept Lead), **`Calendar_Hours`** (per-resource daily available hours from Start→End date), **`Transformed_FTO`** / **`Transformed_FTO_new`** (leave hours), `Transformed_Weekly_Hours`.
- Country-code → full-country normalisation (UK→UNITED KINGDOM, USA→UNITED STATES, +15 more).
- **`Daily Hours` = Weekly Hours / 5**; default fill **40 hrs/week** when missing.
- Hierarchy walk uses the `STOP*` flags to attribute each person to a **`Reports To Manager`** / **`Reports To Dept Lead`** and a **`PM Group`** (`1. PMO` / `2. CEOps` / `3. Services (Other)`) via a hard-coded name list (PMO and CEOps members enumerated inline — Georgina Palmer-Stevens, Andrew Gittins, Kristi Schulte, etc.).

### 4.8 `Linking_2_Engagement_D365` (Gen1) — CSM engagements & cross-team requests
[Linking_2_Engagement_D365.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_2_Engagement_D365.json) · modified 2024-12-10.

Sources D365 `Source_Engagement`, `Source_Engagement_Task`, `Source_Cross_Team_Requests`. Output: **`ENG_D365`**, **`ENG_Append_Activity`**, **`ENG_D365_Counts`** (grouped by `BrandAccId_Prod_Lookup`, Activity Category, Status, Start Month — Count of distinct Activity Ids + sum of `hs_completedpoints`). Engagement type → Activity Category; joins to CSM and brand account.

### 4.9 `Linking_2_CustomerVoice_D365` (Gen1) — survey / CSAT / NPS
[Linking_2_CustomerVoice_D365.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_2_CustomerVoice_D365.json) · modified 2025-01-08 · partitions refreshed 2025-06-10.

Three survey streams merged from Customer Voice response data + D365 reference objects (Contacts→Accounts for NPS, Projects for Pro Services, Cases for Support):

| Stream | Output entities | Sentiment scoring |
|---|---|---|
| **NPS** | `CV_NPS`, `Update_CV_nps`, `Filter_CV_NPS_Comments` | `msfp_sentiment`: Negative→3, Neutral→2, Positive→1. Question: *"How likely are you to recommend Fortra to a friend or colleague?"* |
| **Pro Services CSAT** | `CV_Pro_Services`, `Update_CV_Pro`, `Filter_CV_Pro_Comments` | *"Please rate your satisfaction…"* 1–10: ≥9→1, ≥7→2, <7→3. Adds ROI question. Joined to Project Number. |
| **Support** | `CV_Support`, `Update_CV_supp`, `Filter_CV_Supp_Comments` | Product + Case satisfaction → 1/2/3; emits Satisfied/Dissatisfied % flags for Product and Case |

Plus unioned `CV_Append_Activity` and `CV_All_Comments`. CustomerVoice org = `org5ade7db4.crm.dynamics.com`.

### 4.10 `CustomerVoice_ALERTLOGIC` (Gen1, Shared Services) — raw survey extract
[CustomerVoice_ ALERTLOGIC.json](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Shared Services Dataflows_2 Workspace/CustomerVoice_ ALERTLOGIC.json) · modified 2024-02-05. Raw `msfp_*` entities (`msfp_project`, `msfp_survey`, `msfp_question`, `msfp_surveyinvites`, `msfp_surveyresponse`, `msfp_questionresponses`, `msfp_satisfactionmetric`) filtered to a specific Alert Logic survey (`msfp_surveyid = ae3243a2-cd42-ea11-a812-000d3a8c9285`).

---

## 5. Legacy Services SQL views (HSWarehouse) — feed `Services Project Hours.pbix`
[Services Project Hours - Supporting Views/](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Services Project Hours - Supporting Views/). Per [Notes on Services Project Hours.docx](Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Services Project Hours - Supporting Views/Notes on Services Project Hours.docx): **`CRMPROD`** is a replica of the D365 production CRM in the data-warehouse environment (also available as `hsprodcrm` on server `dc-staging-dw.public.63649b2f8fb6.database.windows.net,3342`); **`HSWarehouse`** hosts scheduled ETL transformations + a spaced-out `StringMap` view + annual team targets. These are **the fact views** behind the Services Project Hours report.

| View (`HSWarehouse.dbo`) | Grain / fact | Notable logic |
|---|---|---|
| **`ServicesProjectHours`** | One row per `hs_projecthours`; the project-hours revenue fact | `Hours = hs_numberofhours`; **Hourly Rate** = native rate × monthly exchange rate to USD (`hs_exchangerates`, EOMONTH of service date, USD); **Revenue = Hours × Hourly Rate**; carries Native Hourly Rate & Native Currency Type; **`Billable?` = Yes** only if `hs_billablehours=1 AND hs_billableproject=1`; **`LateEntry`** flag when created month > service month; uses **billed date in favour of service-performed date** where present; excludes forecasts; rolling ~5-fiscal-year window. Joins account country, project task, project manager, RSM, consultant dim. |
| **`ServicesProjectBacklog`** | One row per open project (`statecode=0`); remaining-revenue backlog | **Remaining Hours** = `hs_BudgetHours_Decimal − hs_BillableHours_Rollup`; **RemainingAmount** = (hourly rate / exchange rate) × remaining hours; **Project Age** bucket `<3 / 3-6 / 6+ Months` from created date; pulls first-invoice legal entity + exchange rate. |
| **`ServicesPipeline`** | Opportunities + pre-sales/SOW projects (services pipeline) | UNION of opportunities (services value, with a **$15,000 default** for a specific brand `655E48CC-…` when services total is 0) and `hs_projects` in `statuscode IN (717710006=SOW, 717710004=Pre-Sales)` with `hs_billableproject=1`, de-duped against opportunities. |
| **`ServicesPRXProjects`** | Projects whose name contains `prx` | Revenue = `hs_BudgetHours_Decimal × hs_projecthourlyrate_base` |
| **`User`** | `dim_SystemUser` dimension | ID, fullname, isdisabled, **RSM Region**, **Manager Name** |

These views read D365 status/picklist codes via `stringmap` joins (langid 1033). Migration replacements must reproduce: USD currency conversion via monthly exchange-rate table, the billable AND-condition, late-entry detection, backlog = budget − billable rollup, and the SOW/Pre-Sales statuscode semantics.

---

## 6. Reusable derivation rules (carry forward to SF/Workday reporting)

- **Account Region** is derived from D365 `hs_shiptocontinent_display`: Africa/Europe/Middle East→**EMEA**; Asia/Oceania→**APAC**; Caribbean/South America→**LATAM**; North America→**NORAM**; Unknown→blank. (Note the typo branch `"Afria"→EMEA` left in the M.)
- **Daily Hours = Weekly Hours / 5**; default weekly hours **40** when ADP value missing.
- **Project Number** is presented as **`PN-` + D365 number**; **Opportunity Number** for Alert Logic is `OTY-####` parsed from project name.
- **Sentiment / Temperature numeric scale** (CE): see §4.2 (Low=4…Red=9, Notified Lost=10).
- **Survey sentiment scales** differ by survey type: NPS 1/2/3 (Pos/Neu/Neg), CSAT 1–10 banded 9+/7+/<7, Support combined Product+Case.
- **Composite join keys** (`AccId_Prod_Lookup`, `BrandAccId_Prod_Lookup`, `AccId_Brand_Lookup`) are mandatory because ARR/temperature/activity are tracked **per account × product-brand**, not per account. A flat SF account model will need an equivalent brand/product-line breakdown to reproduce these reports.
- **Hours unioned across 3 source CRMs** (D365, Tripwire, Globalscape) with a `System` discriminator — post-consolidation this becomes a single Salesforce source, but the historical union must be preserved for trend reporting.

---

## 7. Connections to the SF RCA / Workday / MuleSoft build

- The **D365 field-rename map (§4.1)** is the practical crosswalk for re-sourcing CE/Services reporting onto Salesforce objects once D365, Tripwire SF and Globalscape SF are consolidated into RCA. ARR, temperature, risk, project, hours, opportunity-services-value fields all need SF equivalents.
- **ADP / Work Calendars / Time Off** (utilisation capacity) are HR data that, post-migration, most naturally re-source from **Workday HR** (headcount, manager hierarchy, country, hire/term, scheduled hours) rather than SharePoint Excel dumps. The hard-coded `STOP*`/`PM Group` name lists should become real Workday org hierarchy.
- **Services Project Hours / Backlog / Pipeline** revenue logic (USD conversion via monthly FX, billable AND-rule, backlog = budget − billable rollup) is finance-adjacent and overlaps the Workday billing model — relevant to the broader SC-3143 Workday-integration epic. The **`Adapted Billings Report`** is the explicit Finance report here but is opaque (binary, no supporting artifacts).
- **MuleSoft** is not referenced in any of these dataflows — this estate predates the RCA/Workday integration layer and is pure Power BI over the legacy CRMs/SharePoint/Customer Voice. It is migration *input* (reporting requirements to preserve), not part of the target architecture.
- Complementary to the design KB (`FORTRA_KNOWLEDGE_BASE.md`): that synthesizes the *target* design; this captures the *current-state* analytics that must survive the cutover.

---

## 8. Gaps / open questions / not-extractable

- **All 5 `.pbix` files are binary and not extracted** → no DAX measures, no visual layout, no relationships recoverable: `CE Customer Engagement.pbix`, `CE Services Delivery.pbix`, `CE Utilisation.pbix`, `Services Project Hours.pbix`, `Adapted Billings Report.pbix`.
- **Finance reporting is a near-total gap.** The only Finance artifact is `Adapted Billings Report.pbix` (binary, 116 MB). No dataflows, lineage, SQL views, or field maps were supplied for Finance/billings. The billings logic and its sources are **unknown** from this package.
- Several dataflows appear in the lineage diagrams but their **definitions are not in scope**: `D365 Activity`, `Smartsheet_FORTRA`, `Salesforce_GLOBALSCAPE`, `Salesforce_ALERTLOGIC`, `Source_Data_SFDC_Globalscape`, `SharePoint` (Services Operations), and the Globalscape hours dataflow `37f64040-…`. Their field maps are inferable only indirectly.
- Two distinct D365 orgs are referenced: **`hsprod.crm.dynamics.com`** (main CRM) and **`org5ade7db4.crm.dynamics.com`** (Customer Voice). The OLD dataflow also references `hsprod`. Confirm which org each SF migration stream replaces.
- `Linking_1_D365_OLD` vs `Linking_1_D365_Accounts`: the OLD one is described as superseded but **still feeds the live CE lineage** (cases). Confirm whether cases reporting was ever migrated off it.
- Refresh cadence/orchestration of the dataflows is not documented beyond `modifiedTime` and last partition refresh timestamps (latest seen 2025-06-10).

---

## Sources

**Extracted text (read in full):**
- `BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Customer Engagement Premium Workspace/Linking_1_D365_Accounts.json.txt`
- `…/Linking_1_D365_OLD.json.txt`
- `…/Linking_1_D365_Projects.json.txt`
- `…/Linking_1_Sharepoint_Utilisation.json.txt`
- `…/Linking_1_Tripwire.json.txt`
- `…/Linking_2_All_Hours.json.txt`
- `…/Linking_2_CustomerVoice_D365.json.txt`
- `…/Linking_2_Engagement_D365.json.txt`
- `…/Source_Data_SharePoint.json.txt`
- `BSI Discovery Info/Reports/Customer Engagement Reports/Dataflows/Shared Services Dataflows_2 Workspace/CustomerVoice_ ALERTLOGIC.json.txt`
- `…/Shared Services Dataflows_2 Workspace/D365 Datasets.json.txt`
- `BSI Discovery Info/Reports/Customer Engagement Reports/Services Project Hours - Supporting Views/Notes on Services Project Hours.docx.txt`
- `…/Services Project Hours - Supporting Views/ServicesProjectHours.sql.txt`
- `…/ServiceProjectBacklog.sql.txt`
- `…/ServicesPRXProjects.sql.txt`
- `…/ServicesPipeline.sql.txt`
- `…/User.sql.txt`

**Images read with vision (original files):**
- `Fortra Discovery Documentation/BSI Discovery Info/Reports/Customer Engagement Reports/Lineages/CE Customer Engagement Report Lineage.png`
- `…/Lineages/CE Services Delivery lineage.png`
- `…/Lineages/CE Utilisation lineage.png`

**In scope but NOT extractable (binary `.pbix`):**
- `…/Customer Engagement Reports/CE Customer Engagement.pbix`
- `…/Customer Engagement Reports/CE Services Delivery.pbix`
- `…/Customer Engagement Reports/CE Utilisation.pbix`
- `…/Customer Engagement Reports/Services Project Hours.pbix`
- `…/Finance Reports/Adapted Billings Report.pbix`
