# Channel — Partner Portal, Deal Registration, Partner Types & Access

**Scope:** Top-level `Channel/` discovery artifacts only. Covers the partner portal (PRM) experience requirements, the SFDC partner-portal Deal Registration (DR) form field-by-field mapping, the partner-type taxonomy and access/permission matrix, partner KPI metrics, Channel Account Manager (CAM) territory coverage, the NORAM partner roster, and the channel bookings/DR/dashboard reporting structure.

**Out of this topic's scope** (separate KB docs): the `Channel/Meeting 60/`, `Channel/Partner Discounts Data Lists/`, and `Channel/Content Examples/` subfolders. Partner pricing/discount mechanics live in those docs and in the Partner Pricing Models design doc — cross-referenced below where billing/pricing intersects.

**Relation to design KB:** This is raw business *discovery* input (requirements gathering, legacy D365 artifacts, operational reports). The companion `FORTRA_KNOWLEDGE_BASE.md` synthesizes the Confluence *design* docs. Where this doc names SF objects/fields (e.g., new Opportunity DR fields), those are *requested* additions captured during discovery, not necessarily as-built.

---

## 1. Strategic context

- **Strategic shift to an ~80% channel-based sales model.** The PRM (Partner Relationship Management portal) is being built on Salesforce so the **CRM and PRM are the same system** — eliminating the cross-system sync and "duplicate opps" problems that exist today.
- **Legacy state:** Multiple CRMs (D365/Dynamics, Tripwire SFDC, Globalscape/Alert Logic SFDC) and leads arriving from multiple places. Today only **Strategic Partners** are supported in the existing **Allbound (AL)** portal. Deal registrations flow through **D365 Partner Portal**, **Allbound (Zift)**, and the **Fortra website (HubSpot)** today.
- **Key pain points (today):** lack of account-creation/clean-up control; duplicate partner accounts in CRMs; partner contacts living inside customer accounts; sales creating opps without leads (so a partner's DR lead can't be matched to an open opp); D365 dedupe keys on customer email + product brand, not company name. **Deal protection in Fortra is granted by Product Brand/Solution + registered Company Name.**

Source: [Channel_PartnerPortalRequirements (2).xlsx](Fortra Discovery Documentation/Channel/Channel_PartnerPortalRequirements (2).xlsx)

---

## 2. Partner Portal experience requirements

Each requirement was assessed against SFDC ("Does SFDC meet this?"). All "Need to have" items were answered **Yes** except the duplicate-opp item (needs scenario clarification) and Fortra-Academy auto-provisioning (an IT/internal item, not SFDC).

### Need to have

| Requirement | SFDC answer / note |
|---|---|
| Single tool for all partner types, integrate to all Fortra CRMs | Yes — future end state is one CRM for all brands; all partners access the SFDC PRM |
| Unified interface: register deals, find materials, bi-directional opp sync | Yes — because CRM and PRM are the same, no sync needed |
| Avoid duplication of opps | Yes, SFDC has dedupe; Fortra must explain the specific duplicate scenario. Need efficient way for sales to cross-check registered deals vs open opps |
| Approval workflow | Yes — configurable, simple→complex |
| Customize portal experience **by partner business type** (Reseller, Distributor, MSP, etc.) | Yes — different views/workflows/whole experience per partner type |
| Partner user **role hierarchy** | Yes — multiple partner roles; Fortra defines capabilities (e.g., whether a role can create users) |
| Fortra can **impersonate** a partner account/user | Yes, OOTB (shown in demo) |
| Automated partner **onboarding** (trigger/action engine) | Yes — part of the "Program" feature |
| Distinguish **Fortra Originated** vs **Channel Originated** opps | Yes |
| Partner commercial terms visible in portal (map from D365) | Yes — same system, no mapping needed |
| Partner **business planning** (share/create/track goals) | Yes — "Programs" feature; can also share campaigns, tracked in SFDC |
| Report/export opportunity info | Yes — build, export, share, schedule |
| **Fortra Academy (Docebo)** integration — partner certification tracking back to CRM/PRM | Yes, OOTB via Docebo connector App |
| Track partner certifications at **contact and company** level | Yes (shown in demo) |
| Self-serve marketing — partners **co-brand assets** | Yes, multiple options |
| **Content Management Tool** — bulk edit/analyze portal content | Yes — built-in SFDC CMS; supports MS Office docs + rich web content |
| **MDF** (Marketing Development Funds) request + Fortra approval | Yes (shown in demo) |
| Manage partner communications (newsletters, social) | Yes — email/phone auto or manual; social needs scoping (SMS/Facebook may add cost) |
| Automated email/portal **notifications** on partner/Fortra actions | Yes |

### Nice to have

| Requirement | SFDC answer / note |
|---|---|
| HubSpot integration | Yes |
| **SSO** with Fortra Academy using SFDC creds | Yes (SFDC + Docebo); partners mainly log into SFDC and see classes in the PRM |
| Auto-approve Academy course access on org approval | Not an SFDC item — IT/internal discussion |
| Seamless registration — **whitelist partner email domains** | Yes |
| **AWS Integration / ACE** | Yes — ACE integrated with SFDC; PRM *is* SFDC |
| Partner **prospect pages** (ungated landing pages w/ shareable content) | Fortra users yes; confirm whether partners can author |
| Playbooks & learning tracks in portal | Yes — the "Program" feature |
| **Incentives mgmt — SPIFFs** | Fortra evaluating a SPIFF tool in SFDC. Use case: Fortra rewards a Partner AE (gift card/grill) for hitting SPIFF parameters — e.g., $100 gift card per successful Q4 customer meeting; $500 gift for closing a min $100K PO in Q1 |

Source: [Channel_PartnerPortalRequirements (2).xlsx](Fortra Discovery Documentation/Channel/Channel_PartnerPortalRequirements (2).xlsx)

---

## 3. Partner Type taxonomy

Seven core partner types plus two International use-case rows. **A partner may be multiple types** (e.g., NORAM list shows many "VAR + MSP").

| Partner Type | Role in ecosystem | Primary sales behavior | SF account-structure implication |
|---|---|---|---|
| **Distributor** (Value-Added Distributor / VAD) | Sells to resellers (not end customers); manages pricing & inventory | Aggregates demand, registers deals, manages fulfillment, supports resellers | Parent account with child reseller accounts (multi-tier hierarchy) |
| **Reseller** (Value-Added Reseller / VAR) | Sells directly to end customers | Registers & owns deals/quotes/opps, closes sales | Partner account w/ full opp+quote+lead access; can link to a Distributor account |
| **MSP / MSSP** (Managed [Security] Service Provider) | Ongoing services (monitoring, support, renewals) around the product | Manages renewals, upsells, service delivery; may co-sell | Partner account w/ linked customer records, subscriptions, service data |
| **Systems Integrator (SI/GSI)** | Implements/configures/customizes as part of a larger project | Co-sells, submits referrals, manages delivery projects, technical validation | Partner account w/ implementation/project tracking + referral submission |
| **Referral Partner** | Identifies & refers prospects | Submits leads only; commission on closed deals | Simplified partner account w/ lead/referral submission + payout tracking |
| **Technology Alliance** | Strategic co-marketing/integration/co-sell (e.g., AWS) | Co-develops/co-markets, influences deals, joint campaigns | Strategic partner account w/ joint-solution + influence tracking + campaign linkage |
| **Purchasing Agent** | Represents customer in procurement; does not influence product use | Places orders / manages contract execution for the customer | Linked to customer account; limited opp access; tracks PO + contract status |

International use cases:

| Partner Type | Role | Behavior | Account-structure implication |
|---|---|---|---|
| **Distributor (International)** | Sells to resellers, not end users | Registers deals, manages customer opps + pricing + inventory, reseller support | Full opp/quote/lead access; parent w/ child resellers (multi-tier) |
| **Reseller (Indirect only)** | Sells to end customers but **works through Distributors only** | Manages opps & receives quotes via Distributor | Partner account linked to a Distributor account |

Source: [Partner Types_Salesforce Requirements_8.27.2025.xlsx](Fortra Discovery Documentation/Channel/Partner Types_Salesforce Requirements_8.27.2025.xlsx) (sheet *Partner Roles*)

---

## 4. Access / permission matrix by partner type

### 4.1 Portal functionality by partner type (release-1 view)

Goal of this matrix: identify where portal functionality should differ by type. **Initial release expectation: not many differences.**

| Partner Type | Training (Docebo) | Content | Deal Reg | MDF Requests | Partner Admin Tasks | Dashboards/Metrics |
|---|---|---|---|---|---|---|
| Distributor | Yes | Yes | Yes | Yes | Yes | Yes |
| Reseller | Yes | Yes | Yes | Yes | Yes | Yes |
| MSP | Yes | Yes | Yes | **No** | Yes | Yes |
| System Integrator | Yes | Yes | Yes | **No** | Yes | Yes |
| Referral Partner | Yes | Yes | Yes | **No** | Yes | Yes |
| Technology Alliance | Yes | Yes | Yes | Yes | Yes | Yes |
| **Purchasing Agent** | **No** | **No** | **No** | **No** | **No** | **No** (no access at all) |
| Distributor-International | Yes | Yes | Yes | Yes | Yes | Yes |
| Reseller (Indirect only) | Yes | Yes | Yes | **No** | Yes | Yes |

Source: [Access by Partner Type.xlsx](Fortra Discovery Documentation/Channel/Access by Partner Type.xlsx) (sheet *Sheet1*)

### 4.2 Deal-Reg form field variations by partner type

The DR form must show/hide the Reseller/Distributor company fields by type (Heather Honn to review):

| Partner Type | DR form field behavior |
|---|---|
| Distributor | **Reseller Company Name is Required** |
| Reseller | Distributor Company is **Optional** |
| MSP | Reseller + Distributor Company Name **both Optional** |
| System Integrator | Reseller + Distributor Company Name **both Optional** |
| Referral Partner | **Hide** Reseller and Distributor Company Name |
| Technology Alliance | Reseller + Distributor Company Name **both Optional** |
| Purchasing Agent | n/a |
| Distributor-International | **Reseller Company Name is Required** |
| Reseller (Indirect only) | **Distributor Company Name is Required** |

> Note conflict between this table and §5: in §5 the field-mapping says *Reseller Company Name* is "Required for Distributor partners only" and *Distributor Company Name* is "Required for Reseller partners only." The Special-Notes table above treats the Reseller's Distributor field as *Optional*. Open question — confirm whether resellers (direct) must select a distributor.

### 4.3 Detailed capability matrix (granular access semantics)

From the *Partner Requirements* sheet — values are richer than Yes/No (Full / Limited / No Access / Required / Optional / Need Option / view-influence-only / etc.):

| Requirement | Distributor | Reseller | MSP | Systems Integrator | Referral Partner | Technology Alliance | Purchasing Agent |
|---|---|---|---|---|---|---|---|
| Partner Account & Contact Setup | Required | Required | Required | Required | Required | Required | Required |
| **Partner Portal Access** | Full | Full | Full | Full | **Limited** | **Limited** | **No Access** |
| **Deal Registration** | Required | Required | Optional | For Co-sell | N/A | N/A | N/A |
| Opportunity Management | View/Support-only **or** Full (need option) | Full Access | Service-Only | View/Influence Only | N/A | Influenced Only | N/A |
| Lead Submission Form | N/A | N/A | N/A | N/A | **Required** | N/A | N/A |
| Lead Distribution / Routing | Need Option | Need Option | Need Option | N/A | N/A | N/A | N/A |
| Lead/Opportunity Attribution | Required | Required | Required | Required | Required | Required | N/A |
| Pricing Access | Required | Need Option (Direct & Indirect) | Yes | Limited | N/A | Optional | N/A |
| Multi-Tier Partner Mapping | Required | Need Option (Direct & Indirect) | N/A | N/A | N/A | N/A | N/A |
| Support Case Management | Per contract | Per contract | Required | N/A | N/A | N/A | N/A |
| Certification Tracking | Required | Required | Required | Per contract | N/A | Per contract | N/A |
| Attribution/Influencer Tagging | N/A | N/A | N/A | Required | Required | Required | N/A |
| Training / Sales Enablement | Required | Required | Required | Required | Limited | Required | N/A |
| Commission Payments from Fortra | N/A | N/A | N/A | If Referral Involved | Required | N/A | N/A |

Source: [Partner Types_Salesforce Requirements_8.27.2025.xlsx](Fortra Discovery Documentation/Channel/Partner Types_Salesforce Requirements_8.27.2025.xlsx) (sheets *Partner Requirements*, and *Special Notes* in Access by Partner Type)

---

## 5. Deal Registration form — field-by-field mapping (SFDC Partner Portal)

This is the authoritative DR-form spec. Source columns: form field name; whether included in the SFDC "Fortra – Field Level Excel" [Opportunity tab]; the **D365 source field + Dynamics API**; type; notes; and four behavior flags (In DR Form? / Required? / Visible in Portal? / Read-Only in Portal? / In current D365 portal DR form?). **APIs are still to be confirmed by the BS Team** (most SFDC API names marked UNKNOWN).

### 5.1 Customer-facing fields (partner enters)

| Form field | D365 field (Dynamics API) | Type | In DR form / Required | Portal: Visible / Read-only | Notes |
|---|---|---|---|---|---|
| Customer Company Name | Company Name (`companyname`) | Text | Yes / Yes | Yes / Yes | |
| Customer Website URL | Website | Text | Yes / Yes | Yes / — | |
| Customer Contact First Name | First Name (`firstname`) | Text | Yes / Yes | Yes / Yes | |
| Customer Contact Last Name | Last Name (`lastname`) | Text | Yes / Yes | Yes / Yes | |
| Customer Contact Job Title | Job Title | Picklist | Yes / Yes | Yes / Yes | |
| Customer Contact Email | Email (`emailaddress1`) | Text | Yes / Yes | Yes / Yes | |
| Customer Contact Phone | Business Phone | Text | Yes / Yes | Yes / Yes | |
| Address 1 | DETAILS-Address-Street Line 1 | Text | Yes / No | Yes / Yes | |
| Address 2 | DETAILS-Address-Street Line 2 | Text | Yes / No | Yes / Yes | |
| City | DETAILS-Address-City | Text | Yes / No | Yes / Yes | |
| Country | Country/Region | Picklist | Yes / Yes | Yes / Yes | |
| State/Province | State/Province | Picklist | Yes / Yes | Yes / Yes | **Required for US, Canada, Germany, United Kingdom** |
| Zip/Postal Code | ZIP/Postal Code + DETAILS-Address-Zip | Text | Yes / No | Yes / Yes | (D365 form: required when Country = UK) |
| **Reseller Company Name** | Reseller (NEW) | Look Up | Yes / Yes | Yes / Yes | **Required for Distributor partners only** — lookup of resellers tied to the distributor's SFDC account |
| **Distributor Company Name** | Distributor (NEW) | Look Up | Yes / Yes | Yes / Yes | **Required for Reseller partners only** — lookup of distributors tied to the reseller's account. *Open Q: which field on partner's account determines if a reseller must pick a distributor?* |
| Product Brand | Product Brand | Picklist | Yes / Yes | **No (Visible=False)** / Yes | |
| Bundle of Interest | (UNKNOWN) | — | Yes / No | No / No | "is this products of interest?" |
| Is this an existing customer of your company? | Existing Customer of Partner? | Picklist (Yes/No) | Yes / Yes | Yes / Yes | |
| Sales Activities (multi-select) | Sales Activities (NEW) | Picklist multi | Yes / Yes | Yes / Yes | Values: *Initialized discussions with customer; Customer has shown interest in solution; Conducted Demo; Agreed on solution to business problem* |
| Project Timeline | Project Timeline | Picklist | Yes / Yes | Yes / Yes | *0-3 / 3-6 / 6-12 / 12+ months / Unknown* (Unknown is new) |
| Budget Allocated? | Budget Allocated? | Picklist | Yes / Yes | Yes / Yes | *Yes / No / Unsure* |
| Customer opportunity is part of an RFP? | RFP (NEW) | Checkbox | Yes / No | Yes / Yes | |
| Who will be responsible for implementing the solution? | (NEW) | Checkbox | Yes / Yes | Yes / Yes | *We (registering partner) will implement; A 3rd-party implementation partner; Customer handles internally; Not yet determined* |
| Additional Notes | Partner Deal Registration Notes (NEW) | Text | Yes / No | Yes / Yes | |
| MDF Funding Code | Partner MDF Activity ID (NEW) | Look Up | Yes / No | Yes / Yes | |
| Campaign Type | Source Campaign Activity | Lookup | Yes / No | Yes / Yes | Links source campaign activities to partner account |
| Fortra Partner Marketing Involvement? | (NEW) | Picklist (Yes/No/Unsure) | Yes / Yes | Yes / Yes | |

### 5.2 System-set / back-office fields (not on the form; "set value")

| D365 field | Type | Set value / behavior | In DR form / Portal |
|---|---|---|---|
| Partner Contact (`hs_partnercontact`) | Look Up | Mapped from registering partner's contact record | not on form / visible |
| Owner | — | Fortra AE (set value) | not on form / read-only |
| Status | single select | Open (set value) | not on form |
| Lead Type | dropdown | Inbound (set value) | not on form |
| Topic | Free form | Selling Partner's Account Name | not on form |
| Status Code | — | New (set value; "Duplicate" if duplicate lead found) | not on form |
| **Lead Source** | Picklist | **Partner Deal Registration** (set value, locked) | visible / read-only |
| **Partner Deal Status** | Picklist | **Registered / Approved / Rejected / Closed** | visible / read-only |
| **Deal Origin** | Picklist | **Channel Originated / Fortra Originated** | visible / read-only |
| **Channel Account Manager** | Look Up | Auto-populated by **CAM Territory Rules: Product Brand → Country → State/Province** | visible / read-only |
| Territory | Picklist | Set by Country/Region | not on form |
| Sales Stage | Picklist | — | visible |

Source: [Field Mapping for SFDC Partner Portal Deal Registration Form (copy).xlsx](Fortra Discovery Documentation/Channel/Field Mapping for SFDC Partner Portal Deal Registration Form (copy).xlsx) (sheet *SFDC Partner Portal DR Form*)

### 5.3 Legacy comparison sheets in the same workbook

- **D365 Partner Portal DR Form** — the current-state Dynamics portal form. Key differences vs the SFDC target: the partner is added to an "Associated Partners Grid" via **Selling Partner** + **Billable Partner** lookups (both "set value = Yes"); Owner = "Partner Sales"; Lead Source = "Partner"; `Partner Recruitment`=No, `Partner Deal Registration`=Yes, `Partner Lead Status Reason`=In Progress; **Source Campaign Activity** = "[Product Brand] - Partner Deal Registration" (one SCA per brand). Distributor/Reseller info is captured as free-text "Description (new line)" today (no lookups).
- **Partner Owned DR_website form** and **Copy - Partner Owned Deal Reg** — the **Fortra website** DR form → Dynamics Lead. Adds Partner Information block (Partner Company Name `hs_partneraccount`, Partner Contact `hs_partnercontact`), Industry, `Job Title 2` (`hs_jobtitle2`), Use case/pain points (→ description?), Solution Group dropdown (TBD), Products (TBD — no Lead field). Many fields "no field within Lead form" today. The "Copy" sheet adds an explicit **HubSpot** column.

### 5.4 Dropdown / picklist value sets (the *Dropdown Values* sheet)

This sheet is the **master picklist dictionary** with Value Name + API Value for many fields. Notable, reusable detail for SF config:

- **Partner Lead Status Reason** (`hs_partnerleadstatusreason`): In Progress `717710000`, Approved `717710001`, Disqualified `717710002`.
- **Status:** Active / Pending / Inactive.
- **Job Title** (`hs_...`): Procurement, Systems Administration, Security Director, Security Consultant, Security Administration, Sales/Marketing, Programmer/Developer, Other IT Staff, Network Administration, IT Management, Finance, Database Administration, Consultant, C-Level, Business User, Auditor, Other, Accounts Payable (each with `7177100xx` codes).
- **Project Timeline:** 0-3 months `717710001`, 3-6 `717710002`, 6-12 `717710003`, 12+ `717710004`.
- **Budget Allocated:** Yes `717710000`, No `717710001`, Unsure `717710002`.
- **Allbound Partner Portal Access** (`hs_allboundpartnerportalaccess`): None `717710000` … (Y/N flag).
- **Company Size** (`hs_companysize`): 0-250 / 250-499 / 500-999 / 1,000-4,999 / 5,000-9,999 / 10,000+ (codes `717710001`–`717710006`).
- **Country / State-Province / Time Zone:** full ISO-style country lists with D365 option codes (`717710xxx`); State/Province (`hs_stateprovince_picklist`) covers US states, Canadian provinces, UK counties, German states (Länder).
- **Sales Stages** (`hs_salesstages`): Pre-Qualified `717710000`, Sales Qualified `717710001`, Evaluating `717710002`, Pricing & Approval `717710003`, Closing `717710004`.
- **Product Brand** (`hs_productbrands`, entity `hs_productbrandid`): master brand entity with **D365 GUIDs**, **Production GUIDs**, and a **"Shared with Allbound?"** flag. Each value is tagged **SF** (in Salesforce) or **D | mapped / D | missing / D | ??** (Dynamics mapping status). Brand/solution hierarchy seen here (Solution Group – Product):
  - **Data Protection** — Digital Guardian, Data Classification (Boldon James/Titus), Vera
  - **Managed File Transfer (MFT)** — GoAnywhere; **Secure File Transfer (SFT)** — Globalscape; File Catalyst; Outflank
  - **Managed Services** — Alert Logic, Alert Logic-MDR, -XDR, -WAF, -Legacy
  - **Infrastructure Protection** — Core Security, Cobalt Strike, Outflank, Digital Defense, Beyond Security
  - **Automation** — Automate, JAMS
  - **Digital Risk & Email Protection (DREP)** — PhishLabs, Clearswift, Agari, Terranova
  - **File Integrity Monitoring (FIM)** — Tripwire
  - **Hybrid & Power** — Systems Management, PowertechX, Cybersecurity, Business Intelligence, IGA, BoKS, Document Management, Capacity Management
- **Industry / Solution Group (`Products_of_Interest`) / company_size** value lists are also enumerated.

> These option-set codes (`717710xxx`) are **D365 numeric option values**, useful as the migration source-of-truth when mapping to SF picklist API names. The GUIDs are D365 record IDs for brand entities.

---

## 6. New Salesforce fields requested (Opportunity / Account / Contact)

From *Fields to Add* / *Opp-Fields to Add* / *Account-Fields to Add* / *Contact-Fields to Add* in the Partner Types workbook. Note `ACE Connector — Wren has a list of fields`.

### 6.1 Opportunity — Deal Registration category

| Field | Type | Behavior | Portal Read-Only? |
|---|---|---|---|
| **Deal Registration ID** | Text (read-only) | Record ID for internal+external tracking; **prefix "D"**. Maps from portal | Yes |
| Partner Portal Deal Registration? | Picklist (Yes/No) | | Yes |
| **Partner Deal Status** | Picklist | Registered / Approved / Rejected / Closed | Yes |
| Deal Registration – Date Approved | Date | Read-only; maps to date `Partner Deal Status` → Approved | Yes |
| **Deal Registration – Expiration Date** | Date | **Default = 120 days after Date Approved** | Yes |
| Number of Deal Registration Extensions | Number | Default `0`, read-only; +1 each time Expiration Date is changed by Fortra | Yes |
| Deal Registration Notes | Text | Entered by partner; read-only for Fortra sales | No |
| Sales Activities Completed by Partner | Multiselect | Partner-entered at registration (values TBD; see §5.1) | — |
| **Deal Origin** | Picklist | Channel Originated / Fortra Originated | Yes |
| Partner Involvement Start Date | Date | For partner-registered deals, defaults to DR-approved date | No |

### 6.2 Opportunity — Partner Marketing / Involvement

| Field | Type | Notes |
|---|---|---|
| MDF Request ID | Picklist/Lookup | Associated to MDF request form in portal; editable by sales & marketing; partner sees approved MDF requests for their account |
| Partner Marketing Involvement? | Picklist (Yes/No) | |
| Preferred Partner(s) of Customer | Lookup (Partner Accounts), Multi-Select | |
| Primary Partner? | Picklist (Yes/No) | |
| Partner Influencers | Lookup (Partner Accounts), Multi-Select | **Restricted to Alliance + System Integrator types** |
| Partner Contribution | Picklist | "Partner Adding Value" / "Partner Pass Through" |
| Partner Contribution Notes | Text | |

### 6.3 Opportunity — AWS / ACE Connector

| Field | Type | Notes |
|---|---|---|
| Customer AWS Account Number(s) | Lookup | Tied to AWS account numbers on Customer/Logo account; can add new on opp + roll to parent |
| Does Customer Use AWS Marketplace? | Picklist read-only (Yes/No) | Maps from Customer Account |
| **AWS Marketplace Engagement Score** | Picklist read-only | Empty/Low/Medium/High — from **ACE CRM API guide**, not editable by Fortra |
| **AWS Sales Stage** | Text read-only | From ACE CRM API guide, not editable by Fortra |

### 6.4 Account (Partner / Customer / Logo)

- **AWS Account Number(s)** — multi-valued text, always a 12-digit number, can be multiple; rolls up; future state extends to Microsoft Azure.
- **Is AWS Partner? / Is DSOR Partner? / Is CPPO Partner?** — Yes/No picklists (Partner accounts).
- **AWS Marketplace Type** — None / Direct / Channel / Distributor.
- **Preferred Selling Vehicles / Verticals** — multi-select, rolls from Partner accounts to Logo account.
- **Does Customer Use AWS Marketplace?** — read-only on customer account.
- **MDF Request ID** — lookup to MDF requests (on partner account).
- Existing **Job Title** drop-down to be extended with partner roles: Solutions Engineer, Implementation Consultant, Vendor Management, Channel Sales Director, Business Development Manager, Strategic Alliances Manager, Partner Marketing Manager, Territory Sales Manager, Technical Support, Product Manager, Account Manager.

### 6.5 Contact

- **Required to Complete Partner Certifications** (Yes/No), **Number of Partner Certifications Completed** (number).
- **Partner Certification Types** — multi-select on contact: *Sales, Service Delivery, Solution Engineering, Marketing*. Captured 3 ways: (1) at registration on portal, (2) editable later on portal, (3) editable on CRM Contact. **No automation/rules** — view & report only.
- **Partner Contact Type** drop-down: Partner Alliance / Marketing / AWS Lead / Sales Lead / SE Lead / Account Exec / SE Contact Type.
- AWS contact info maps to **ACE Opportunity Account Team** with role names.
- **Data owners/stewards** (Contact fields working session): *Tanya Hague & Nick Scott* (Logo & Customer), *Heather Honn* (Partner accounts); Data Steward: *Nick Scott & Greg Schweitzer* (Logo & Customer), *Heather Honn* (Partner).

Source: [Partner Types_Salesforce Requirements_8.27.2025.xlsx](Fortra Discovery Documentation/Channel/Partner Types_Salesforce Requirements_8.27.2025.xlsx)

---

## 7. Partner KPI metrics

ALE = "Annual License Equivalent"-style internal metric. **Key rule: ALE is internal-only — NOT shown to partners and NOT a visible revenue metric in the portal.** Partner-facing revenue metrics are **Total Amount Invoiced** and **ARR**.

### Lead / Opportunity / Pipeline reports

| Metric | Definition (D365 logic) |
|---|---|
| Approved Deal Registrations | Lead `Partner lead status reason = approved`; lead qualified & converted to opp. *Recommend a timeline filter; default most-recent on top.* |
| Rejected Deal Registrations | Lead `Partner lead status reason = disqualified`; lead closed as lost |
| Approved/Rejected DR Volume (by creation date) | Same as above, bucketed by lead creation date |
| Closed-won deals count & value | Opp closed-won (quote ordered & invoiced); Value = **Total Amount Invoiced** |
| Total DR pipeline value | `status reason = approved`, converted to opp, opp active |
| Average closed-won cycle time | Opp creation date → closed-won date |
| # deals registered this quarter | count |

### Invoice reports

- Metrics by partner — *for Distributor deals also track the indirect reseller buying through distribution (not currently trackable in D365).*
- **Incremental Revenue Closed-Won Through Partner Deal Registration (Channel-Originated):** opps with new license sales (**ALE > 1**), initially deal-registered by partner, lead→opp converted, closed-won. D365 keys: `Lead Source = Partner` (named "partner deal registration"); `Partner lead status reason = approved`; `Source Campaign Activity` begins with "Partner Portal Deal Registration"; `Deal Origin = Channel-Originated`.
- ALE by partner / brand / region / country, YoY comparison.
- Invoice Volume (by invoice date): count where partner = **billable partner**; includes paid or in-progress (excludes cancelled/rebilled).
- Closed deals by origin (Fortra vs Channel): Volume + ALE + Total Amount; invoice posted; ALE > 1.

### MDF form reports

- MDF requests approved & declined — **not tracked in D365 today; net-new in SFDC**. Flow: partner contact submits MDF form → Fortra partner marketing notified → approve/decline.

### On-Hold

- (Finance) **Annual Recurring Revenue**, **Gross Retention %**, **Billings**.
- (BSI/Coastal to confirm Phase 1 Docebo↔SFDC integration) **Completed Partner Certifications**.

Source: [Partner KPI Metrics.docx](Fortra Discovery Documentation/Channel/Partner KPI Metrics.docx)

---

## 8. Partner billing scenarios (summary)

Meeting brief: review any billing scenario where a partner on the deal influences quoting / invoicing / discounts / renewals. The variations to support: (a) partner is the billing entity, (b) partner involved but customer is billed, (c) partner bills from different legal entities for different customers, (d) both a Distributor and a Reseller take part of the deal.

| Partner type | Billing model | CRM attribution |
|---|---|---|
| **Distributor** | Fortra invoices distributor → distributor invoices reseller → end customer not billed by Fortra | Distributor = **Bill-To Partner**; Reseller = Sell-To/Channel; End Customer = Customer of Record |
| **Reseller (VAR)** | Fortra invoices reseller → reseller invoices end customer; no Fortra↔customer transaction | Reseller = **Bill-To and Sell-To**; End Customer = Customer of Record |
| **MSP** | Fortra invoices MSP; **MSP packages & bills end customer** as a service bundle. Support **Monthly / Quarterly / Annual + usage-based** cadences. Fortra typically will **not know the end customer**. | MSP = **Customer of Record** (when servicing on behalf of end customer); End Customer = Optional/Linked |
| **Referral Partner** | Fortra invoices the end customer directly; referral partner paid a commission % / fee, **45 days after Fortra receives customer payment** | Referral Partner = Influencer/Referral Source (not in billing hierarchy); End Customer = Bill-To + Customer of Record |

Combination scenarios:
- **1.2 Distributor + Referral Partner:** Fortra→Distributor→Reseller→End Customer; referral fee (commission %) paid 45 days after Fortra is paid by the **Distributor**.
- **1.3 Reseller + Referral Partner:** Fortra→Reseller→End Customer; referral fee paid 45 days after Fortra is paid by the **Reseller**.

**MSSP note:** *Fortra is rebuilding its MSSP Program for 2026* — the MSP billing cadences above align to standard MSSP business practice.

**Cross-reference:** the *quoting/discount/renewal* mechanics for these billing models (partner price tiers, distributor margins, channel discount schedules) live in the **Partner Pricing Models** design doc and in the `Channel/Partner Discounts Data Lists/` subfolder (separate KB topics). The billing-entity ↔ Workday invoicing wiring (Bill-To vs Sell-To, multi-legal-entity) is the integration concern owned by BSI/Coastal — see the design KB.

Source: [Partner Billing Scenarios.docx](Fortra Discovery Documentation/Channel/Partner Billing Scenarios.docx)

---

## 9. Channel Account Manager (CAM) territory coverage

The CAM is auto-assigned on the DR/opp by **territory rules: Product Brand → Country → State/Province**. The June 2025 Cyber CAM territory map defines **Continent/Subcontinent → Sub Region → CAM → Country → State/Province**. There are **20 numbered sub-regions** (the numbering is the canonical sub-region key, e.g. "01. UKI & Nordics" … "20. AWS Alliance"). US and Canada are assigned at the **state/province** level.

### CAM → sub-region assignments

| Sub Region | Channel Account Manager | Coverage notes |
|---|---|---|
| 01. UKI & Nordics | **Melissa O'Leary** | UK & Ireland, Nordics (Denmark, Finland, Iceland, Norway, Sweden), Channel Islands, Akrotiri/Dehkelia, Gibraltar, Greenland |
| 02. Benelux | **Melissa O'Leary** | Belgium, Luxembourg, Netherlands |
| 03. DACH | **Jean-Philippe Fourche** | Austria, Germany, Liechtenstein, Switzerland |
| 04. South Europe | **Jean-Philippe Fourche** (Andorra, France, Monaco, Portugal, Spain); **Jenko Gaviglia** (Italy, Malta, San Marino, Vatican) | split |
| 05. Eastern Europe | **Jenko Gaviglia** (most of E. Europe + Caucasus + Central Asia); **Jean-Philippe Fourche** (Israel); **Melissa O'Leary** (Turkey); **N/A** (Belarus) | mixed |
| 06. Middle East | **Moe Bux** | Afghanistan, Bahrain, Iran, Iraq, Jordan, Kuwait, Lebanon, Oman, Pakistan, Palestine, Qatar, Saudi Arabia, Syria, UAE, Uzbekistan, Yemen |
| 07. Africa (ENG) | **Moe Bux** | English-speaking Africa |
| 08. Africa (FRA) | **Jean-Philippe Fourche** | French-speaking Africa (Algeria, Benin, Cameroon, Cote d'Ivoire, Morocco, Senegal, Tunisia, etc.) |
| 09. Asia | **KoK Chan** | China, India, Japan, S. Korea, SE Asia, etc. |
| 10. Oceania | **KoK Chan** | Australia, NZ, Pacific Islands |
| 11. LATAM | **Nils Hansen** | South America, Caribbean, Mexico & Central America (Puerto Rico → Don Smith) |
| 12. US West | **Don Smith** & **Larry Meeusen** | by state (incl. N. California → Don Smith; S. California → Larry Meeusen) |
| 13. US Central | **Larry Meeusen** & **Don Smith** | by state |
| 14. US Southeast | **Don Smith** | FL, GA, KY, MS, NC, SC, TN |
| 15. US Northeast | **John Murdock** | NE US states **+ all of Canada** (incl. provinces + Saint Pierre and Miquelon) |
| 16. US MSPs | **CJ Donahoe** | United States (MSP segment) |
| 17. US FinServ | **Troy Myers** | United States (Financial Services vertical) |
| 18. US PubSec / CAN PubSec | **Skip Chapman** | US Public Sector + Canada Public Sector |
| 19. US Strategic Partners (Cisco, Climb, Dell, Insight) | **Nils Hansen** | named strategic accounts |
| 20. AWS Alliance | **Mike Reed** | United States (AWS) |

> Implementation note: the US is partitioned by **state** between Don Smith / Larry Meeusen / John Murdock for the geographic sub-regions, **and overlaid** by segment sub-regions (MSPs=16, FinServ=17, PubSec=18, Strategic=19, AWS=20) with dedicated CAMs. So the CAM-assignment rule needs **vertical/segment + brand** dimensions in addition to geography. The DR-form rule as stated (Brand→Country→State) does not by itself disambiguate MSP/FinServ/PubSec/AWS — open question on how segment is resolved.

Source: [Cyber CAM Territories by Region(June 2025).csv](Fortra Discovery Documentation/Channel/Cyber CAM Territories by Region(June 2025).csv)

---

## 10. NORAM partner roster

74-row roster of North America partners with **Partner Name / Partner Manager / Partner Type / Brands** (plus an unused "New Structure" column). Useful as a migration seed list and to validate multi-type behavior.

- **Partner Managers:** the vast majority are **Tommy Fuller**; a few under **Stacy Jensen** (MedHost, Island Pacific, SurePoint) and **Mike Long** (Vormittag Associates, Harris Data, Control Systems Software, SPSS Italia).
- **Type codes used (legacy):** `Distributor`, `VAR`, `REF` (Referral), `MSP`, and combinations like `VAR + MSP`, `MSP + VAR`. Confirms **partners are commonly multiple types** (e.g., Huber & Associates = VAR+MSP; Service Express, MAPSYS, Meridian IT, Mid-Range, Sirius/CDW, Kyndryl = VAR+MSP).
- **Brands** field uses brand shorthand: Robot, Powertech, BI, Linoma, Halcyon, CCSS, PerfNav, Sequel, Showcase, DocM, "Robot HA", and `ALL`.
- Examples: Arrow = Distributor (Robot); CMA Technology = REF (ALL); Insight Direct USA / Guide Technologies / Abacus-Fresche / ERP Suites / Clear Technologies = MSP (Halcyon); IBM = MSP (Powertech).
- A few rows have a Partner Manager but blank Type/Brands (DPS Inc., Optiv, Tectrade/CSI) — data gaps.

Source: [NORAM Partner list.xlsx](Fortra Discovery Documentation/Channel/NORAM Partner list.xlsx)

---

## 11. Channel reporting & dashboard structure

Two operational workbooks define the channel reporting model that the SFDC PRM dashboards/reports must reproduce.

### 11.1 Channel Bookings & DR Report 2025

A weekly-cadence working report (many dated snapshot sheets: `Bookings Summary_*`, `DR Summary_*` for Mar–May 2025) consolidating **bookings** and **deal registrations** across the three legacy systems.

**Core bookings line schema (`BOOKINGS APR 1-28`, raw export):**
`Brand · Solution Group · Customer · AE · Secondary Rep · Deal Status · Bookings ($) · Date · Link · Partner · Invoice Number · Partner? (Yes/No) · Lead Source · Deal Origin · opportunityid · Country · Vertical · Region`
(The richer `REVExportMASTER` adds `REVMonth · Total Amount · Primary SE · Secondary SE · REVRegion`.)

- **Deal Status** values: Active / Closed Won / Paid.
- **Lead Source** values seen: Partner, Partner Marketing, Marketing Email, Sales-Outbound, Sales-Inbound, Website, Buyer Intent, HelpSell, Unmapped, (blank).
- **Deal Origin:** Channel Originated / Fortra Originated / Unknown.
- **Region:** APAC / EMEA / Americas (AMER).
- Links resolve to **D365 (`hsprod.crm.dynamics.com`)**, **Tripwire SFDC (`tripwire.my.salesforce.com`)**, and Allbound — confirming the multi-system consolidation problem the PRM solves.

**DR Summary structure** (e.g., `DR Summary_May 23`): "Partner Deal Registrations (Approved), ALE > $1, Cyber (All) excludes AWSM." Pivots **Approved DR count by Region × Month**, then broken out **by system source**: `[D365]`, `[Tripwire SFDC]` (FIM only), `[AL SFDC]` (XDR only). YTD example: 809 approved Cyber DRs (EMEA 387 / Americas 278 / APAC 144), of which D365 = 671, Tripwire = 100, Allbound = 38.

**REV BOOKINGS SUMMARY MASTER** — the executive channel pivots:
- *Channel ALE Bookings: Totals by Deal Origin × Region (Cyber)* — e.g., 2025 YTD $10.08M total; Channel Originated 31% / Fortra Originated 69%.
- *Invoice count* and *% volume* by Deal Origin × Region; *Average Deal Size* by origin (Channel ≈ $9.8K vs Fortra ≈ $19.7K).
- *Billings: Channel vs Direct Splits (Cyber)* — ≈ 49% channel / 51% direct ($50.3M / $52.0M YTD), monthly MoM % splits.
- Per-region monthly invoice-count and ALE-total breakouts (Americas / EMEA / APAC).

**Source-system export tabs** (the consolidation feeders): `DR_D365 Lead Export`, `DR_Hubspot Website Form Export`, `DR_ALPortal Zift Leads`, `DR_TW Mar SFDC Opp Export`, `BOOK PowerBI Export`, `BOOK_AL (Kirk G)`, `REVBOOK_Export`, `Website Export`, etc. — i.e., bookings/DR data is hand-stitched from **D365 + HubSpot website + Allbound(Zift) + Tripwire SFDC + Alert Logic SFDC + PowerBI**.

**Analyst process notes (`DR Notes HH`)** — current manual DR workflow:
- *Tripwire (TW): partners don't typically submit DRs in the portal.*
- Portal DR comes through as a **Lead** → **Melissa approves** → sends to the **Rep for final approval** → if approved, converted to / applied to an existing opp.
- Adding customer licenses is **coded as a "teaming reg," not a deal registration**.
- Approvers by system: HubSpot report = **Mayling**; TW SFDC = **Melissa L & Travis**; AL SFDC = **Chris & CJ**.

Source: [Channel Bookings & DR Report 2025.xlsx](Fortra Discovery Documentation/Channel/Channel Bookings & DR Report 2025.xlsx)

### 11.2 Channel Dashboard – Apr '25 (Internal Use Only)

The reporting/data model behind channel exec dashboards. Sheets group into **presentation pivots**, **data tables**, and **reference lists**:

- **Billings dashboards** (`Billings Dashboard Org`, `Billings - Cyber`, `Billings Dashboard`): Channel vs Direct billings split by quarter/year with **YoY % growth**; *Channel Billings by Brand* (Agari, RPA, BSEC, Data Classification, …). USD in thousands. Note: *excludes Alert Logic billings.*
- **ALE dashboards** (`ALE Dashboard Org`, `ALE Dashboard`, `ALE vs Plan`): ALE actuals vs plan.
- **By-partner / by-brand pivots:** `Billings by Partner`, `ALE by Partner`, `Billings by Partner & Brand`, `Number of INV by Brand`, `ALE by Partner & Brand`, `Number of New Subs by Brand`.
- **Geographic pivots:** `Sub Region Pivot - ALE`, `International ALE`.
- **Data backbone:** `Master Billings` (~506K rows × 22 cols) is the raw fact table.
- **Reference/list sheets** (the dimension model — directly reusable as SF picklist/region config):
  - `Control` — maps **Product → Group (Master Billings) → Brand → 2022 Solution Group → 2023 Solution Group**, plus the **Cancellation/Discount Reason** value set (*Downgrade, MFF Cancellation, Canceled, Bankruptcy/Economic, Renewal Cancellation*). This is the canonical brand→solution-group rollup (e.g., Tripwire: FIM→Core; Globalscape: SFT→Core; Robot/Halcyon/CCSS: SM→Core; AutoMate: RPA→Automation; PhishLabs/Agari/Clearswift: Email/DRP→Digital Risk and Email Protection).
  - `Partner List` (~4,515 rows) — **partner-name normalization** map: *Original Channel Partner → Revised Channel Partner* (e.g., "Accenture Australia Pty Ltd" → "Accenture"; blanks/`#N/A`/`None`/`0` → "Direct") plus a **Partner Exclusions** list (DELL, Fujitsu, KPMG, Kyndryl, NTT, Westcon, SoftwareONE, etc.). Critical for the duplicate-partner-account cleanup the PRM is meant to fix.
  - `Partner Region`, `Region List` (18 reporting countries), `Sub Region List` (country → Sales Region (EMEA/AMER/APAC) → Geographic area, e.g., "Africa - English"), `Misc List`, `Partner Cleanup`.

Source: [Channel Dashboard - Apr '25 (For Internal Use Only).xlsx](Fortra Discovery Documentation/Channel/Channel Dashboard - Apr '25 (For Internal Use Only).xlsx)

---

## 12. How this connects to the SF RCA / Workday / MuleSoft build

- **PRM = SFDC.** The whole consolidation thesis is that CRM and PRM are one Salesforce org, removing D365↔portal sync, the duplicate-opp/duplicate-account problems, and the manual multi-system DR stitching documented in §11.
- **Deal Registration → Lead → Opportunity.** Portal DR creates a Lead (`Lead Source = Partner Deal Registration`, locked), routed for approval, then converted to/applied to an Opportunity. The new Opportunity DR fields (§6.1) — Deal Registration ID ("D"-prefixed), Partner Deal Status, Expiration Date (Approved + 120 days), Extensions counter — implement "deal protection by Brand/Solution + Company Name."
- **CAM auto-assignment** (§9) becomes Salesforce territory/assignment logic keyed on Brand → Country → State/Province (with an unresolved segment/vertical dimension for MSP/FinServ/PubSec/AWS sub-regions).
- **Workday (financials):** the billing scenarios (§8) define Bill-To vs Sell-To partner and Customer-of-Record, which drive invoice routing in Workday — including MSP cadences (Monthly/Quarterly/Annual + usage-based) and the multi-tier Distributor→Reseller chains. Referral commissions (paid 45 days after Fortra is paid) are tracked **outside** the billing chain.
- **MuleSoft / connectors:** Docebo (Fortra Academy) connector for certification sync; **ACE / AWS** connector (Wren owns the field list) feeding AWS Account Numbers, Marketplace Engagement Score, AWS Sales Stage (read-only from ACE); HubSpot integration; legacy migration feeds from D365/Tripwire SFDC/Alert Logic SFDC/Allbound(Zift).
- **Migration source-of-truth:** the D365 option-set codes (`717710xxx`), Product Brand GUIDs, and the `Control`/`Partner List` normalization tables (§11.2) are reusable mapping inputs for SF picklist + account dedupe.

---

## 13. Open questions / ambiguities

1. **Reseller's Distributor field requirement conflict** — §4.2 (Special Notes) says a Reseller's Distributor field is *Optional*; §5.1 (field mapping) says Distributor Company Name is *Required for Reseller partners only*. Also: *which field on the partner's account decides whether a (direct) reseller must select a distributor?*
2. **Segment-based CAM assignment** — the stated rule (Brand→Country→State) doesn't resolve the overlaid segment sub-regions (16 US MSPs, 17 FinServ, 18 PubSec, 19 Strategic, 20 AWS). How is segment/vertical determined for CAM routing?
3. **SFDC API names** — most target SFDC field APIs in the DR mapping are marked **UNKNOWN / "to be confirmed by BS Team."**
4. **Duplicate-opp scenario** — SFDC team asked Fortra to document the exact duplicate-opp scenario before designing dedupe.
5. **Partner-authored prospect pages** — confirm whether partners (not just Fortra users) can create ungated landing pages.
6. **Docebo↔SFDC in Phase 1** — Completed Partner Certifications KPI and Academy SSO/auto-provisioning are on-hold pending BSI/Coastal Phase-1 confirmation; Academy auto-access provisioning is an IT/internal (non-SFDC) item.
7. **Finance metrics on hold** — ARR, Gross Retention %, Billings KPIs pending Finance.
8. **Distributor→indirect-reseller tracking** — currently impossible in D365; a stated requirement for SFDC (track the indirect reseller buying through distribution).
9. **SPIFF tool** — Fortra is still *evaluating* an SFDC SPIFF tool; not yet a committed requirement.
10. **MSSP program** — being rebuilt for 2026; MSP billing cadence requirements may evolve.
11. **NORAM roster data gaps** — DPS Inc., Optiv, Tectrade have no Partner Type/Brands.

---

## Sources

| File | Used | Notes |
|---|---|---|
| [Channel_PartnerPortalRequirements (2).xlsx](Fortra Discovery Documentation/Channel/Channel_PartnerPortalRequirements (2).xlsx) | Yes | Portal experience requirements (Need/Nice to have), strategic context |
| [Field Mapping for SFDC Partner Portal Deal Registration Form (copy).xlsx](Fortra Discovery Documentation/Channel/Field Mapping for SFDC Partner Portal Deal Registration Form (copy).xlsx) | Yes | DR form field-by-field mapping; D365 + website forms; dropdown/picklist value dictionary |
| [Access by Partner Type.xlsx](Fortra Discovery Documentation/Channel/Access by Partner Type.xlsx) | Yes | Portal functionality matrix + DR field variations + certification notes |
| [Partner Types_Salesforce Requirements_8.27.2025.xlsx](Fortra Discovery Documentation/Channel/Partner Types_Salesforce Requirements_8.27.2025.xlsx) | Yes | Partner taxonomy, capability matrix, new Opp/Account/Contact fields, ACE/AWS fields |
| [Partner KPI Metrics.docx](Fortra Discovery Documentation/Channel/Partner KPI Metrics.docx) | Yes | KPI definitions (D365 logic), ALE internal-only rule, MDF + on-hold metrics |
| [Partner Billing Scenarios.docx](Fortra Discovery Documentation/Channel/Partner Billing Scenarios.docx) | Yes | Distributor/Reseller/MSP/Referral billing models + combination scenarios |
| [Cyber CAM Territories by Region(June 2025).csv](Fortra Discovery Documentation/Channel/Cyber CAM Territories by Region(June 2025).csv) | Yes | 20 sub-regions, CAM-by-territory, US/Canada state-level coverage |
| [NORAM Partner list.xlsx](Fortra Discovery Documentation/Channel/NORAM Partner list.xlsx) | Yes | 74 NORAM partners (manager/type/brands) |
| [Channel Bookings & DR Report 2025.xlsx](Fortra Discovery Documentation/Channel/Channel Bookings & DR Report 2025.xlsx) | Yes (structure; raw rows not exhaustively read — 980KB) | Bookings/DR consolidation schema, summary pivots, source-system feeders, analyst process notes |
| [Channel Dashboard - Apr '25 (For Internal Use Only).xlsx](Fortra Discovery Documentation/Channel/Channel Dashboard - Apr '25 (For Internal Use Only).xlsx) | Yes (structure + reference sheets; raw fact rows not exhaustively read) | Billings/ALE dashboard model, Control brand→solution map, Partner List normalization + exclusions, region dimension |
| [fortra-brand-guidelines.pdf](Fortra Discovery Documentation/Channel/fortra-brand-guidelines.pdf) | No | Present at top-level but **out of scope** — marketing brand collateral (Voice & Tone, Logo, Colors, Typography); not in brief's file list, no partner/portal/DR content |

*No in-scope files were encrypted, binary, or empty. The two large workbooks (Bookings report ~980KB; Dashboard ~5,450 lines) were read structurally — all sheet schemas, headers, summary pivots, and reference/dimension tables were captured; per-row transactional data (individual invoices, ~506K Master Billings rows) was sampled, not transcribed, as it is operational data rather than reusable design detail.*
