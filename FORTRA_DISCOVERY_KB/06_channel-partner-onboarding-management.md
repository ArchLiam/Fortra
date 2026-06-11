# 06 — Channel: Partner Onboarding / Offboarding & Management (Meeting #60)

> **Source meeting:** #60 Salesforce Channel Partner Management Call — **June 17, 2025**
> **Topic owner area:** Fortra Channel org (Global Channels & Alliances)
> **Discovery purpose:** Capture the partner lifecycle (onboarding/offboarding), the Channel Account Manager (CAM) operating model, partner-record/system requirements for Salesforce RCA, and the legacy partner-onboarding project plan so the SF build team can model partner management correctly.
>
> This is a **discovery** document (raw business inputs). For the synthesized design picture see `FORTRA_KNOWLEDGE_BASE.md`. Connections to the SF RCA / Workday / MuleSoft build are flagged inline under **[SF/Integration note]**.

---

## 1. What this meeting was

A discovery call to onboard the Salesforce/Coastal implementation team to how Fortra's **Channel** organization actually works, so partner management can be modeled in Salesforce Revenue Cloud Advanced. The agenda walked the channel team's existing collateral (a 75-slide CAM enablement deck) plus two operational checklists and a legacy partner-onboarding project plan.

**Key acronym:** **CAM = Channel Account Manager.**

The bulk of the deck is CAM training/playbook material (co-sell, AWS, QBRs). The **directly actionable discovery content** for the SF build is concentrated in:
- The **agenda docx** (org structure, distribution logic, system requirements list).
- The **onboarding checklist** (5-phase lifecycle, responsible roles, CRM touchpoints).
- The **offboarding checklist** (termination workflow, account-transition, system-access teardown).
- The **legacy partner onboarding project plan** (milestone/phase template — Alert Logic era).

---

## 2. Channel organization (2025)

### 2.1 Global leadership / reporting lines
Source: PPTX Slide 1 "Channel Organization 2025".

| Role | Person |
|---|---|
| VP Global Channels & Alliances | **Faraz Siraj** |
| Director, Channel — EMEA | **Jenko Gaviglia** |
| Director, Global Channel Ops | **Heather Honn** |
| Strategic Alliances | Mike Reed |
| Strategic Partners | Nils Hansen |
| Global Program Administrator | **Lidiane Santos** |
| UK Coordinator | Vicki Smith |

**Three geos:** NORAM, EMEA, APAC.

### 2.2 Cyber Defensive Solutions org (from agenda docx)

| Geo | Reporting | CAM coverage |
|---|---|---|
| **Americas** | Reports directly to VP Channel | Regional CAMs (4); Industry/Vertical CAMs (5): FinServ, Public Sector, Strategic Accounts, AWS Alliance (co-sell), Distribution (named partner accounts) |
| **EMEA** | Reports to EMEA Channel Director → VP Channel | Sub-Regional CAMs (3.5) |
| **APAC** | Reports to APAC VP (indirect to VP Channel) | 1 CAM for all Cyber Defensive solution sales |

### 2.3 Named CAMs by territory (Slides 1–3)

**Americas — 4 Pods (Cyber):**
| Pod | CAM |
|---|---|
| Northeast / Canada | OPEN (TBH) — also "CAM NE: John Murdock" listed |
| Southeast | Don Smith |
| Central | Larry Meeusen |
| West | Chris Camaclang |
| MSPs | CJ Donohoe |
| Latin America | Nils Hansen |
| Strategic Accounts (MidEast) | Moe Bux |
| FinServ | Troy Myers |
| PubSec | Skip Chapman |

Americas distribution partners named: **CLIMB, Insight, Cisco, Dell, Lookout**.

**EMEA — Cyber map (CAMs):**
| CAM | Regions (focus in bold) |
|---|---|
| **Melissa O'Leary (MO)** | **UK & Ireland**, **Nordics (w/ Baltic)**, Benelux, Turkey |
| **Jean-Philippe Fourche (JP)** | **France**, DACH, Iberia, French/Portuguese-speaking Africa, Israel |
| **Moe Bux (MB)** | **Middle East**, English-speaking Africa |
| **Jenko Gaviglia (JG)** | **Italy**, Eastern Europe |

### 2.4 Tech-focused (MFT / IBM Power / Automation / Network Monitoring) reporting (Slides 5–6)

| Tech line | Sales Director | NORAM CAM | EMEA CAM |
|---|---|---|---|
| MFT (Managed File Transfer) | Joe Eginger | Tommy Fuller | **James Taylor** |
| IBM Power | Stacy Jensen | (by regional AE) | (by regional AE) |
| Automation | Jon Spencer | — | — |
| Network Monitoring & Cap. Mgmt | Jon Racine | — | — |

**James Taylor's EMEA MFT-focused partner accounts (Slide 6):** Pro2col, Handd, Business Solutions UK, Bluefinch-ESBD France, Bluefinch-ESBD Netherlands, Korper NL, Systematik (Germany), Sysob (Germany), Blackbridge (Italy, via distributor Computer Gross), IDAL OEM (global), E-Director ME (Globalscape only), AL Networks Germany (Globalscape only), ADM Tools Spain (Globalscape only), Emib Hungary (direct for MFT, via Computer 2000 for Cyber).

---

## 3. EMEA Channel Landscape (Slide 4) — partner structure

- **Strategic Partner (pan-EMEA): Infinigate** (operating as **Starlink** in MEA). Can sell **all Fortra products across all EMEA**. **Sole partner for DP, DREP, IP, MDR in UK, DACH, and France.** For other brands/regions, Fortra can also work with other distributors per regional strategy.
- **Infinigate gaps:** not present in **Italy, Spain, Greece, Israel** — other distributors used there.
- **Diamond VARs (MFT)** — managed by James Taylor; some MFT partners retained directly due to autonomy/performance.
- **Strategy direction:** reduce partner count by reassigning VARs to distributors or terminating relationships — **case-by-case, will take time** (directly relevant to the offboarding process below).

Other key distributors named (with CAM initials): Infinigate Nordics (MO), Starlink/Infinigate MEA (MB), Computer Gross (JG), ALSO (JP), Infinigate FR (JP), Bakotech Ukraine (JG), Bakotech PL (JG), NSS (JG), Detech (MO), Bulwark (MB), EMT ME (MB), Cyberknight ME (MB), Cyberknight N.Afr. (JP), Private Protocol (MB), EMT S.Afr. (MB), IT2 Trust (MO), Handd UK (JT), Pro2col (JT), ESBD-BF (JT), Systematik (JT), Sysob (JT), Computer 2000 (JG), MessageNet (JP), Infinigate DACH (JP), Infinigate UK (MO).

---

## 4. Partner Distribution & Territory Management (Agenda item 2)

Partners are distributed across CAMs three ways for Cyber Defensive Solutions:
1. **Region** — country/region, state/province.
2. **Named Strategic Accounts.**
3. **Industry / Vertical.**

> **Decision / gap captured:** **There is NO territory-assignment automation for CAMs in any system today (WIP — "work in progress").**
> **[SF/Integration note]** This is an explicit greenfield requirement for the SF RCA build: CAM↔partner-account assignment/routing must be designed (likely Salesforce Territory Management or assignment rules). Today it is manual.

**AE & CAM ownership** is governed by the "AE & CAM Responsibilities" co-sell RACI (see §9).

---

## 5. Partner Identification & Acquisition (Agenda item 3)

- Partner evaluation uses a **Partner Application Form** — file: **`Fortra Partner Program Application Form.docx`** (referenced, not in this meeting folder; lives elsewhere in discovery set).
- **Lead process for accounts to become partners** is part of acquisition workflow (connects to the Lead/Sales discovery streams).
- Partner recruitment qualifying questions (Slides 30–32) cover: Sales & Marketing capabilities, Commitment/Expectations, Business & Capabilities, Alignment with Fortra goals, Financial/Operational stability, Competitor/Market landscape. Notable quantitative qualifier: **"How much of your gross revenue is allocated to your cybersecurity business?"**
- Partnership types referenced throughout: **Reseller, Distributor, Referral** (and MSP/MSSP). Tiering: **Authorized, Gold, Diamond, Distributor, MSP/MSSP (incl. "Growth MSP/MSSP")** — see NFR/MDF eligibility in §7.

---

## 6. Onboarding lifecycle — the 5-phase checklist

Source: `channel-partner-onboarding-checklist (Internal).xlsx`, tab **"Onboard Checklist"**.

The checklist is structured as **five phases** — **Engage, Educate, Motivate, Support, Manage** — laid out across timeline **stages**: *Complete Before Executing Partner Agreement → Complete Before Start of Onboard → 30-Day → 60-Day → 90–120 Days → Onboard Complete (Business as Usual)*. Phases may run concurrently/overlap. Each row has: Stage, Phase, Objective, Supporting Activity, Status, **Date to be Completed (MM/YYYY)**, **Internal Lead**, **Partner Lead**, Comments. Header fields per partner: **Channel Partner Name, Tier Level, Date of Signed Agreement.**

> **[SF/Integration note]** This checklist is the de-facto onboarding **business process**. In SF RCA it maps to a partner-onboarding flow/record-type with phase + status tracking, an Internal Lead and Partner Lead field, and a target-date field per task. "Dark grey" rows = cross-business-unit shared responsibility (a routing/notification concern).

### 6.1 Stage: Complete BEFORE executing partner agreement
| Phase | Objective | Activity | Internal Lead |
|---|---|---|---|
| Engage | Sales | Provide Fortra (HelpSystems) Partner Program Overview doc | Partner Manager |
| Engage | Sales | Provide product demo | Partner Manager |
| Engage | Sales | Complete a Proof of Concept (POC) | Partner Mgr & Pre-Sales |
| Engage | Sales process | Identify potential sales conflict points | Partner Manager |
| Engage | Sales process | Send Partner Questionnaire to complete | Partner Manager |
| Engage | Sales process | Identify key target markets, product integration points, synergies | Partner Manager |
| Engage | Sales process | Define training & implementation engagement process | Partner Manager |
| Engage | KPIs | Agree on objectives & benefits of partnership | Partner Manager |
| Engage | Contracts | Gather required internal approvals (MD/GM and/or Global Partner Program) | Partner Manager |
| Engage | Contracts | Send Partner Agreement to partner | Partner Manager |
| Engage | Contracts | Send NDA to partner | Partner Manager |
| Engage | Contracts | **Discuss Schedule A terms: commission / discount rates / incentive programs by solution group** | Partner Manager |
| Engage | Contracts | Define sales, technical pre-sales assistance, pricing process | Partner Manager |
| Engage | Contracts | Identify key partner personnel to be certified (sales, pre-sales, technical, marketing) — *all key contacts must be on Schedule A* | Partner Manager |
| Engage | Contracts | Request final review/approval from Global Partner Program Manager (bundle: Partner Agreement, Schedule A, NDA, Key Partner Contacts, Partner Questionnaire) | Partner Manager |

### 6.2 Stage: Complete BEFORE start of onboard
| Phase | Objective | Activity | Internal Lead |
|---|---|---|---|
| Engage | Contracts | Send executed NDA to partner | Partner Manager |
| Engage | Contracts | Send executed business partner contract to partner | Partner Manager |
| Support | — | Notify **Customer Operations, Partner Marketing & Legal** of new agreement (share the 5-doc bundle) | **Manager, Global Partner Program** |
| Support | — | Save partner agreement & NDA in Contracts Folder | **Legal team** |
| Support | — | **Update CRMs with partner's billing address, product discounts, primary contacts, and partner tier level** | **Customer Operations** |
| Educate | Training & Certs | Provide key partner personnel access to partner portal(s) (Gold, Diamond, Distributor) | Customer Operations |

> **[SF/Integration note]** "Update **CRMs** (plural) with billing address, product discounts, primary contacts, tier level" is the **core partner-record data model** for SF RCA. These four data points (billing address, discount schedule, contacts, tier) are the load-bearing fields. The agenda explicitly assigns this to **Customer Operations** (see §8). Product discounts trace to **Schedule A** commission/discount rates — relevant to RCA pricing/partner pricebooks and to Workday billing.

### 6.3 Stage: 30-Day
| Phase | Objective | Activity | Internal Lead |
|---|---|---|---|
| Motivate | Sales | Schedule intro call w/ channel + local sales/technical | Partner Mgr & Pre-Sales |
| Motivate | Sales | Provide Welcome Kit (show disparate portals via video overviews) | Partner Manager |
| Educate | Technical support process | Define tech support process per product | Partner Manager |
| Educate | Training & Certs | Define solution-focused sales training curriculum & certification | Partner Mgr & Technical Team |
| Educate | Training & Certs | Provide **Fortra Academy** access for sales/pre-sales/technical/marketing contacts | Partner Manager |
| Educate | Training & Certs | Provide partner-portal access for additional personnel | Partner Manager |
| Support | — | Request **NFR (Not For Resale) demo copies** for partner | Partner Mgr & Customer Ops |
| Support | — | Request technical support helpdesk access | Partner Mgr & Customer Ops |
| Support | Marketing | Create new partner folder in **Wrike** | Partner Marketer |
| Support | Marketing | Schedule intro call w/ partner marketing teams | Partner Mgr & Partner Marketer |
| Support | Marketing | Request high-res logo (.eps/.ai), 100-word company description, social media | Partner Marketer |
| Support | Marketing | Receive logo & send to Partner Marketer | Partner Manager |
| Support | Marketing | Provide **partner tier badge** | Partner Marketer |
| Manage | Relationship | Create partnership key-additional-contacts list — **Update in CRM** | Partner Manager |
| Manage | Relationship | Establish weekly/bi-weekly/monthly sales forecast meeting | Partner Manager |
| Manage | Relationship | Establish monthly/quarterly marketing meeting (Qtrly: Gold, Distributor, Growth MSP/MSSP; Monthly: Diamond) | Partner Mgr & Partner Marketer |
| Manage | Relationship | Establish sales **QBR** (for partners required to have annual business plan) | Partner Manager |
| Manage | Relationship | Establish monthly executive check-point meeting | Partner Manager |

**NFR rule (key commercial detail):** Gold, Diamond, Distributor and MSP/MSSP partners receive **free 6–12 month NFRs**. Authorized partners receive NFRs at a **discounted rate**. **Referral partners are NOT eligible** for NFR discounts.

### 6.4 Stage: 60-Day
| Phase | Objective | Activity | Internal Lead |
|---|---|---|---|
| Engage | Billing process | Define billing process per product | Partner Manager |
| Engage | Fulfillment process | Define product fulfillment process per product | Partner Manager |
| Manage | KPIs | Set Sales & Marketing performance-metric goals | Partner Mgr & Partner Marketer |
| Support | Sales | Schedule account-mapping session with partner | Partner Manager |
| Motivate | — | Establish transactional cost-of-sales model | Partner Manager |
| Support | Training & Certs | Hold monthly partner sales-team Q&A calls | Partner Mgr & Pre-Sales |
| Educate | — | Conduct live sales training (*requires online sales cert first*) | Partner Manager |
| Educate | — | Conduct live pre-sales training (*requires online pre-sales cert first*) | Partner Mgr & Pre-Sales |
| Motivate | Success stories | Identify & communicate success stories | Partner Manager |
| Support | Marketing | Create co-branded product datasheets (*MDF-eligible: Gold, Diamond, Distributor, Growth MSP/MSSP; requires sales/pre-sales/marketing certs*) | Partner Marketer |
| Support | Marketing | Provide unique tracking code to partner | Partner Marketer |

### 6.5 Stage: 90–120 Days
| Phase | Objective | Activity | Internal Lead |
|---|---|---|---|
| Support | Marketing | Provide client-ready collateral per product (*requires certs*) | Partner Mgr & Partner Marketer |
| Support | Marketing | Develop joint marketing / demand-gen plan (*requires certs*) | Partner Marketer |
| Educate | Training & Certs | Schedule/conduct live technical engineer training (*requires online tech cert first*) | Partner Mgr & Technical Team |

### 6.6 Stage: Onboard Complete — Business as Usual
| Phase | Objective | Activity | Internal Lead |
|---|---|---|---|
| Support | Marketing | Schedule demand-gen activity (lunch & learn, webinar, co-sponsor event) | Partner Marketer |
| Support | Marketing | Annual partner/user conference participation (*final list approved by Global Partner Program MD*) | Partner Marketer |
| Manage | KPIs | Conduct client, partner & internal satisfaction surveys | Partner Mgr & Partner Marketer |

---

## 7. Tier-gated benefits matrix (derived from onboarding checklist notes)

> **[SF/Integration note]** Tier is a partner-record attribute that gates entitlements. Modeling tier (Authorized / Gold / Diamond / Distributor / MSP-MSSP incl. Growth / Referral) is a discrete data requirement that drives several downstream behaviors:

| Benefit | Eligible tiers |
|---|---|
| Partner portal access (onboarding) | Gold, Diamond, Distributor |
| **Free 6–12 month NFR demo licenses** | Gold, Diamond, Distributor, MSP/MSSP |
| NFR at discounted rate | Authorized |
| NFR — **not eligible** | Referral |
| **MDF (Marketing Development Funds)** | Gold, Diamond, Distributor, Growth MSP/MSSP |
| Monthly marketing meeting cadence | Diamond |
| Quarterly marketing meeting cadence | Gold, Distributor, Growth MSP/MSSP |
| QBR + annual business plan required | (partners flagged as requiring annual business plan) |

---

## 8. Onboarding role responsibilities (Agenda item 4) — who owns what

From the agenda docx, two distinct organizations split onboarding:

**Partner Program team:**
- Notifies Customer Ops of a **new executed agreement** and includes **commercial details**.

**Customer Operations team:**
- Responsible for **onboarding the partner into CRM systems** (Account creation & updates).

> **[SF/Integration note]** This is the hand-off that the SF build must support: Partner Program → (executed agreement + commercial terms) → Customer Operations → (Partner Account created/updated in CRM). This sequencing is the trigger for partner-account provisioning in Salesforce. Today it's a manual notification ("notifies"), a candidate for automation/flow.

Internal roles named across the checklists: **Partner Manager / Channel Account Manager (CAM)**, **Manager Global Partner Program**, **Customer Operations**, **Legal team**, **Pre-Sales**, **Technical Team**, **Partner Marketer**, **Channel Program Administrator**, **Channel Program Director**, **Regional Sales VP**, **Channel VP**.

---

## 9. CAM ↔ AE co-sell RACI (Slides 27–28)

Activities marked Owner vs Assists between **CAM** and **AE**. This is the operating split the SF build's opportunity/deal-registration ownership rules should reflect.

| Activity | Owner | Notes |
|---|---|---|
| Plan by Region & Brand | CAM/AE jointly | Sales & Channel leadership work together |
| Partner Recruiting & Onboarding | CAM | |
| Partner Enablement | CAM | |
| Negotiation, partner discounts, T&C | CAM | Targets/KPIs agreed w/ sales leaders |
| Agreements, Schedule A | CAM | |
| Business Plan | CAM | Agreed w/ partner & sales |
| Account Mapping | CAM/AE | |
| Marketing Plan | CAM | Agreed w/ marketing & sales |
| Event Participation | CAM/AE | |
| Joint visits to Customers | AE (CAM assists if needed) | |
| Joint visits to Partners | CAM (AE assists if needed) | |
| Sales Qualification/Discovery | AE | Customer opps qualification |
| Allocate SE resources (Demo/POC) | AE | |
| Manage/respond to Customer RFPs | AE | |
| Budgeting & Quotations | AE | CAM assists when needed |
| Deal Discounts Justification/Approval | AE | CAM assists when needed |
| Opp Forecasting in CRMs | AE | CAM may assist |
| Pipeline meetings with partner | CAM | Organized by CAM for all brands; AEs participate by agreement |
| Order Booking | AE | |
| Project Assistance/Escalations | AE | Escalations by/for customer |
| Partner PS Training/Cert Quotes | CAM | Training/certification quotations |
| Escalations by Partner (Mgmt/Support) | CAM | |
| Escalations by Customer (Mgmt/Support) | AE | |
| **Channel Conflicts** | CAM | Opps requested by multiple partners |
| **MDF Requests (Marketing)** | CAM | Marketing budget request / events |
| **DR Approval (Deal Registration)** | CAM | CAM manages DR process; AE assists when needed |
| Letter Requests (MAF, etc.) | CAM | Manufacturer's Authorization Form / Letters |
| Partner Payment escalations | CAM | Outstanding partner payments (escalated from Finance) |

> **[SF/Integration note]** **Deal Registration (DR)** is CAM-owned and is one of the explicit partner-record requirements (§11). "Channel Conflicts" (opps requested by multiple partners) implies conflict-detection logic on opportunities/deal regs.

---

## 10. Performance Tracking & Metrics (Agenda item 5)

Key partner performance metrics named (agenda + Slides 42–43). Program benefits/requirements reference the **Partner Program Overview brochure**: `https://static.fortra.com/hs/partner/pdfs/partner-program-overview-brochure.pdf`.

**Two revenue metrics + certifications** (agenda):
- **Revenue achievement (2 metrics)**, **Certifications achieved**.

**CAM KPI / Partner Performance KPIs (Slides 42–43):**
- Plan Achievement; Sales Quota Achievement (% of quota on annual sales revenue)
- **Lead Conversion Rate — measured by source: Channel-Originated (CO) vs Fortra-Originated (FO)**
- Partner Win Rate; Average Deal Size & Time to Close; Pipeline Value; **YoY Growth**
- **Volume of Approved Deal Registrations** (partner-originated, approved by Fortra)
- **MDF results / ROI** (lead conversion, SQL volume)
- Deal Registration; Partner Bookings; # of Transactions
- Renewal & Retention Rates (subscription renewals, license retention, CLTV)
- Partner Engagement (sales activity, training, certifications)
- Marketing ROI (partner-originated SQLs, lead conversion)

> **[SF/Integration note]** **CO vs FO lead source** is a foundational attribution dimension that recurs across Fortra's Sales/Marketing discovery — partner performance reporting depends on it being captured at the lead/opportunity level. Renewal/retention KPIs connect to the RCA subscription model and Workday billing data.

---

## 11. System Requirements for partner records (Agenda item 6) — **PRIMARY SF/RCA REQUIREMENTS**

The agenda's explicit "what needs to be visible on partner records" list — this is the closest thing in the meeting to a direct SF requirement set:

- **All benefits & requirements in the program guide** (the brochure above).
- **Deal registrations** — **Approved, Denied, and In-Progress** states.
- **CAM Owner** (partner-record ownership field).
- **Volume of partner meetings scheduled.**
- **Approved partner affiliates.**
- Fields to track **Agreement terms & status.**
- **Solutions authorized to sell** (per-partner authorization list).
- **Required activity logging and tracking.**
- **Assignment and routing considerations** (ties back to the no-territory-automation gap in §4).
- **Partner offboarding processes** (see §12).

> **[SF/Integration note]** Consolidated partner-record field requirements emerging from this meeting (for the SF RCA data model):
> | Requirement | Field/concept |
> |---|---|
> | Partner tier | Tier Level picklist (Authorized/Gold/Diamond/Distributor/MSP-MSSP/Referral) |
> | Ownership | CAM Owner |
> | Commercials | Billing address, product **discounts** (from Schedule A), commission rates |
> | Contacts | Primary contacts + key-additional-contacts (incl. partner sellers as SFDC contacts) |
> | Authorization | Solutions authorized to sell; approved partner affiliates |
> | Agreement | Agreement terms & **status** (e.g. active / in-progress / terminated), signed date |
> | Deal Registration | DR status = Approved / Denied / In-Progress; conflict detection |
> | Activity | Meeting volume, activity logging, QBR cadence |
> | Routing | Territory/assignment automation (NEW — none today) |

---

## 12. Offboarding lifecycle — the termination checklist

Source: `channel-partner-offboarding-checklist (Internal) (1).xlsx`, tab **"Offboard Checklist"**.

**Approval gate:** The **CAM must obtain approval for partner termination from the Channel Program Director.** Header fields: **Partner Company Name, Tier Level (VARs only), Date.** Columns: Stage, Objective, Supporting Activity, **Deadline Date**, Status, **Internal Lead**, Comments.

Structured in **4 stages**:

### Stage 1 — Submit Partner Termination Request to Channel Program Team
| Objective | Activity | Internal Lead |
|---|---|---|
| Contact Information | Partner name; address; Executive Contact name; Executive Contact email | CAM |
| Contracts to Terminate | Provide copy of contract(s) to terminate | CAM & Contracts |
| Contracts to Terminate | Indicate which contract(s) retained (if any) | CAM & Contracts |
| Reason for Termination | Provide reason / reference clause from partner Agreement | CAM |
| **Internal Approvals** | **Obtain approval from Regional Sales VP & Channel VP** | CAM |
| Proposed Account Transition Plan | List of on-support customers + proposed new managing partner | CAM & Customer Ops |
| Proposed Account Transition Plan | List of open opportunities + proposed new managing partner | CAM |
| Proposed Account Transition Plan | List of open leads + proposed new managing partner | CAM |
| Proposed Account Transition Plan | List of open quotes | Customer Ops |
| Proposed Account Transition Plan | List of open invoices (incl. invoices with PO) | Customer Ops |

### Stage 2 — Deliver Notice to Partner & Customer Operations
| Objective | Activity | Internal Lead |
|---|---|---|
| Communication | Provide Termination letter | Contracts Team & Program Team |
| Communication | Deliver Termination letter | Contracts Team or CAM |
| Communication | Communicate transition plan to terminated partner | CAM |
| Communication | Communicate transition plan to new managing partner | CAM |
| Communication | Provide effective termination date to Customer Ops | Channel Program Administrator |
| Communication | **Include termination note on partner's account** (Date of Termination, products retained, products kept) | Customer Operations |

### Stage 3 — Transition Accounts to New Managing Partner
| Objective | Activity | Internal Lead |
|---|---|---|
| Account Transition | (If applicable) Update customer account **nicknames** to new managing partner's name | Customer Ops |
| Account Transition | **Cancel and reissue open quotes** to new managing partner after **x days** from termination-letter date | Customer Ops |
| Account Transition | **Cancel and rebill open invoices** to new managing partner after **x days** | Customer Ops |
| Account Transition | Clean up open leads after X days | CAM |
| Account Transition | Clean up open opportunities after X days | CAM |

### Stage 4 — Update System Access (teardown)
| Objective | Activity | Internal Lead |
|---|---|---|
| Disable Partner Access | Disable partner-portal access once termination in effect | Partner Program team |
| Disable Partner Access | Contact Customer Ops to **cancel NFR Licenses** | Partner Program team |
| Disable Partner Access | Update partner permissions in the **Partner Entitlements Spreadsheet**; email **Training@fortra.com** to notify of access changes | Partner Program team |

> **[SF/Integration note]** Offboarding requires SF to support: (a) a termination-request record with multi-level approval (Channel Program Director → Regional Sales VP → Channel VP); (b) **bulk re-assignment** of customers, opportunities, leads, quotes, and invoices to a new managing partner — directly touches RCA quotes/orders and Workday invoices ("cancel and rebill"); (c) a **termination note + termination date + products-retained** on the partner account; (d) entitlement teardown (portal, NFR licenses, the manual "Partner Entitlements Spreadsheet"). The "**x days**" delay before re-issuing quotes/invoices is an unresolved parameter (see Open Questions). Note offboarding still relies on a **manual Partner Entitlements Spreadsheet** and an email to Training@fortra.com — automation candidates.
>
> **Agenda doc bug:** The agenda's "Partner offboarding processes" line erroneously links to the **onboarding** checklist file name (`channel-partner-onboarding-checklist (Internal).xlsx`), but the offboarding checklist is a separate file.

---

## 13. Legacy Partner Onboarding Project Plan (Plan-Main_PARTNER.xlsx)

Source: `Plan-Main_PARTNER.xlsx`, sheet **"Plan-Main_PARTNER" (128 rows × 26 cols)**. This is an **Alert Logic-era** (pre-Fortra-consolidation) partner onboarding project-plan **template** — a generic Smartsheet-style plan with placeholder values (`PM Name`, `Partner Name`, `TPM Name`) and example **2022 dates**. Everything is "Not Started"/0% complete and shows RAG = Red (because the template baseline dates are in the past). It is a **template**, not a live plan — but it documents the milestone/phase structure Fortra used for **strategic/MSSP partner onboarding** (note heavy Alert Logic MDR/MSSP framing).

**Columns:** Project Manager, Account, Weeknum, Effort (hrs) for Reports, Completed Effort, Remaining Effort, % Complete, Elapsed Days, RAG_temp, RAG, Overdue, Progress, Flag/Flag2/Flag3, Task Name, Assigned To, Customer Facing?, Start Date, Effort (hrs), Duration, Target Date, % Complete, Status, Predecessors, Comments/Next Steps.

### 13.1 Phase / milestone structure
| Phase | Span (template dates) | Content |
|---|---|---|
| **Onboarding Checkpoints** (milestones) | — | Sales Enablement Complete; Partner RACI Issued; Sandbox Environment Provided; ALSE Training Complete; Advanced Operational Training Complete; Ready for Business-as-Usual Phase Start; Partner Operational Enablement Complete |
| **Phase 0 — Discovery & Qualification & Sales Enablement** | ~46d | Introductory Sessions (Leadership/Stakeholders, Product/Offer Mgmt/Alliance, Sales Leadership, Engineering, Operations, Marketing); Partner Resource Center access; Deal Flow Process; Define Business Approach; Responsibility Matrix (RACI); Deal Scoping Process |
| **Phase 1 — Alert Logic Solution Implementation** | ~33d (726.5 hrs) | Sandbox Environment; **ALSE (Alert Logic Solutions Expert)** = 100-level operational training; Advanced Technical Training (200-level); **Implementation "Put into Practice"** (300-level — 5 customer implementation projects, AL leads then partner leads/shadows) |
| **Phase 2 — Alert Logic Solution Operational Integration** | ~21d | Set up Data Connections (ticketing connectors, Alert Logic APIs); Set up Incident Notifications (escalation prefs, console alerts/reports); Advanced Technical Training modules (Incident Response, Log Search, Content Tuning, FIM, Advanced Notifications Mgmt) |
| **Phase 3 — Moving to Business as Usual** | (no dates) | Implementation Ongoing Delivery Mgmt (Smartsheet project logs, PDR issue template, Implementation PM intro, weekly Delivery Review, Partner Delivery Report); Operations Ongoing Delivery Mgmt (Security Analyst/CTE intro, weekly Operational Status, Customer Support/Health/Entitlement & Usage Mgmt) |

### 13.2 Deal-flow tasks relevant to the SF/RCA build (Phase 0)
These appear under "Deal Flow Process" / "Define Business Approach" and are directly SF-relevant:
- **Define Partner SKU** (Strategic Partner Director)
- **Create Partner Pricebook** (Strategic Partner Director)
- Review/tailor web order form
- Partner Managed Services Agreement finalized
- Determine **Account hierarchy structure** + log the decision (SPD/TPM)
- **Add Partner Sellers as contacts in SFDC** (SPD/TPM)

> **[SF/Integration note]** "Define Partner SKU", "Create Partner **Pricebook**", "Account hierarchy structure", and "Add Partner Sellers as contacts in SFDC" are the legacy-plan analogues of RCA constructs: partner-specific **PricebookEntries / price books**, partner SKUs (products), partner **Account hierarchy** (distributor → VAR → customer), and partner-seller **Contacts**. The plan confirms partner onboarding historically required custom pricebooks and SKUs per partner.

### 13.3 Notable plan annotations
- Roles in the plan: **Strategic Partner Director (SPD)**, **Technical Partner Manager (TPM)**, **Alert Logic Project Manager**, **Implementation Engineer (IE)**, **Partner Marketing**, **CSM**, **Partner Delivery Manager**, **OnePoint Admin**, **Chris Camaclang** (named on operational alignment tasks).
- **Cancelled items:** the entire "Secure Document Share" (OneDrive folder) block; "Operational/Process Integration" block (Managed Services Offerings — "being defined by Red River"; Ticketing Integration — "Currently using AutoTask, moving to ServiceNow"); a billing-trigger decision-log task.
- The implementation block (rows ~80–93) has **`#INVALID DATA TYPE`** weeknum and **`#REF`** predecessor errors (broken formula references in the template) — data-quality artifact, not meaningful content.
- **Comment (Row 74, Julia Cox, 03/11/21):** "Need a slide pack and SOP for this — deep dive into project methodology, plan, agenda for each session — KO, deployment, SO, tuning. Gateway criteria."

---

## 14. Decisions & action items captured

| # | Item | Type | Owner / Note |
|---|---|---|---|
| 1 | **No CAM territory-assignment automation exists today; it's WIP** | Gap/Decision | SF build must design assignment/routing |
| 2 | Partner Program team → notify Customer Ops of executed agreement + commercial details; Customer Ops creates/updates partner Account in CRM | Process ownership | Partner Program / Customer Ops |
| 3 | Partner-record must show DR states (Approved/Denied/In-Progress), CAM Owner, agreement terms & status, solutions authorized to sell, approved affiliates, meeting volume | SF requirement | Channel |
| 4 | EMEA strategy: reduce partner count by reassigning VARs to distributors or terminating — case-by-case (drives offboarding volume) | Strategy | EMEA Channel |
| 5 | Termination requires Channel Program Director approval, then Regional Sales VP + Channel VP | Process | CAM |
| 6 | Onboarding/offboarding currently tracked in **Excel checklists**; entitlements in a **manual Partner Entitlements Spreadsheet** | Current state | Automation candidates for SF |
| 7 | Tier gates NFR licenses, MDF, portal access, meeting cadence (see §7) | Business rule | Channel Program |
| 8 | Legacy onboarding plan used per-partner **SKUs + Pricebooks** and SFDC partner-seller contacts | Legacy precedent | Informs RCA partner pricing |

> No formal numbered action-item list was recorded in the meeting docx itself — these are synthesized from the agenda + checklists + plan. The meeting was primarily knowledge-transfer/discovery, not a decision-making session.

---

## 15. External references cited in the materials
- **Partner Program Overview brochure:** `https://static.fortra.com/hs/partner/pdfs/partner-program-overview-brochure.pdf`
- **SharePoint Channel Hub** (source of the onboarding checklist): `https://helpsystemsllc.sharepoint.com/sites/sales/SitePages/channel-hub.aspx`
- **Fortra Academy** (partner training/cert): `https://training.fortra.com/learn`
- **Deal Registration Terms & Conditions:** `https://www.fortra.com/about/channel-program/deal-registration-terms-conditions`
- **D365 Lead Source & Attribution Guidelines** (referenced — confirms current CRM is **D365/Dynamics**, the system being migrated off)
- Referenced-but-not-in-folder docs: **`Fortra Partner Program Application Form.docx`**, **Fortra (HelpSystems) Partner Agreement, Schedule A, NDA, Partner Questionnaire**.

---

## 16. Open questions & ambiguities
1. **Territory/assignment automation** — agenda says "WIP"; no design exists. What is the assignment model in SF (manual ownership, assignment rules, SF Territory Management)? Who owns it?
2. **"x days" / "X days"** delay before cancel-and-reissue quotes and cancel-and-rebill invoices in offboarding is unspecified — needs a concrete SLA. This directly affects RCA quote/order and Workday invoice handling.
3. The agenda's two revenue metrics ("Revenue achievement (2 metrics)") are not named — which two? (Bookings vs ARR? CO vs FO?)
4. **CRMs (plural)** referenced in the checklist — confirms multiple legacy CRMs (D365, Tripwire SF, Globalscape SF). Which becomes the system of record for partner records post-migration, and how do partner discounts flow to RCA pricing and Workday billing?
5. **Partner Entitlements Spreadsheet** and **Wrike** (marketing folders) and **email-to-Training@fortra.com** are manual/external — are these in scope to replace/integrate, or remain out-of-band?
6. Legacy plan is Alert Logic/MSSP-specific (ALSE, PDR, sandbox, implementation projects). How much of this implementation-heavy onboarding applies to non-MSSP resellers/distributors vs. the lighter checklist process?
7. **Deal Registration approval & channel-conflict** logic is CAM-owned but no rules/SLA captured — needs definition for the SF DR object.
8. Partner **Account hierarchy** (distributor → VAR → end customer) is referenced in the legacy plan but the canonical hierarchy model for SF RCA was not decided here.
9. **NFR license** lifecycle (provisioning at onboard, cancellation at offboard) — how represented in RCA (zero-dollar subscription? asset?) and synced to fulfillment/Workday?

---

## 17. Connections to the broader Fortra SF RCA / Workday / MuleSoft program
- **Partner discounts / Schedule A → RCA pricing:** partner discount rates and per-partner pricebooks/SKUs (legacy plan §13.2) are the channel input to the RCA pricing procedures documented elsewhere in the design KB (partner/distributor pricing channels, regional pricing).
- **CO vs FO lead source** is the same attribution dimension that recurs in the Sales/Marketing and Lead Flow discovery streams — partner KPIs depend on it.
- **Offboarding cancel-and-rebill invoices** touches **Workday** (financial back end) and the order/invoice round-trip; bulk re-assignment of quotes/orders touches **RCA Quote/Order** objects (note the org-wide RLM Quote-DML constraints documented in engineering memory).
- **AWS Marketplace co-sell** (MPPO/CPPO, ACE/APN) is a large part of the deck and is its own integration surface (ACE↔CRM API integration is noted as "integrated with Alert Logic's Salesforce instance today; being developed for D365") — captured here for completeness but is a separate workstream from core partner onboarding.

---

## Sources

All files under `Fortra Discovery Documentation/Channel/Meeting 60/` (extracted plaintext read in full from the parallel `discovery-extract/text/` tree):

- [#60 Salesforce Channel Partner Management Call 6.17.25.docx](../Fortra%20Discovery%20Documentation/Channel/Meeting%2060/%2360%20Salesforce%20Channel%20Partner%20Management%20Call%206.17.25.docx) — meeting agenda (org structure, distribution logic, identification/onboarding/metrics/system-requirements agenda items)
- [Channel Partner Management - Salesforce Call 6.17.25.pptx](../Fortra%20Discovery%20Documentation/Channel/Meeting%2060/Channel%20Partner%20Management%20-%20Salesforce%20Call%206.17.25.pptx) — 75-slide CAM enablement deck (org charts, co-sell RACI, KPIs, AWS co-sell/marketplace playbook)
- [channel-partner-onboarding-checklist (Internal).xlsx](../Fortra%20Discovery%20Documentation/Channel/Meeting%2060/channel-partner-onboarding-checklist%20(Internal).xlsx) — 5-phase onboarding checklist with roles, dates, tier-gated benefits
- [channel-partner-offboarding-checklist (Internal) (1).xlsx](../Fortra%20Discovery%20Documentation/Channel/Meeting%2060/channel-partner-offboarding-checklist%20(Internal)%20(1).xlsx) — 4-stage termination/offboarding checklist
- [Plan-Main_PARTNER.xlsx](../Fortra%20Discovery%20Documentation/Channel/Meeting%2060/Plan-Main_PARTNER.xlsx) — legacy (Alert Logic-era) partner-onboarding project-plan template (Phases 0–3, milestones, deal-flow tasks)

**Files that could not be read / extraction gaps:** None — all five in-scope files extracted cleanly to plaintext and were read in full. No images or diagram-only PDFs were present in this folder. (The PPTX includes org-chart/diagram slides whose visual layout is partially flattened in the text extract, e.g. dotted reporting lines on Slide 1; the textual labels were captured but precise reporting-line arrows are not reconstructable from the extract.)
