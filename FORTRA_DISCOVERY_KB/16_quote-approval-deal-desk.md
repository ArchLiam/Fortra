# 16 — Quote Approval & Deal Desk (Process / Workflow)

**Scope:** The legacy Fortra **Deal Desk** quote-approval process — the catalog of exception/discount types that route to Deal Desk, the per-exception reviewer roster (who is notified for Cyber vs Tech), the **Approval Exception Form** (the MS Forms intake), the **Quote Approval Teams** persona inventory, and the 2025 Deal Desk Approval Workflow categories. This doc **owns the approval PROCESS / routing**; the actual discount-% / $-cap **threshold matrices** are owned by **[doc 10 — Pricing Strategy & Approval Matrices](10_pricing-strategy-and-approval-matrix.md)** and are only summarized here to avoid duplication.

**Why it matters for RCA:** An RCA Quote approval process (Flow + Approval Process, or a Deal Desk routing/queue model) must reproduce two things: (1) the **threshold rules** — discount % of list by product-line type, plus order-$ size, that decide *whether* Deal Desk is required (doc 10); and (2) the **routing** — *which* reviewer team is notified per exception type (this doc). Today both live outside Salesforce: thresholds in two Excel matrices, routing in a SharePoint list ("Deal Desk Mention Assignments") that feeds an MS-Forms-driven SharePoint tracker.

> **Related design KB:** This is raw discovery (legacy SharePoint/MS-Forms tooling). For the target-state RCA design see `FORTRA_KNOWLEDGE_BASE.md`. For the empirical discounting evidence behind these controls (40–59% average discounting vs the authorized 20% threshold) and the full threshold tables, see doc 10.

---

## 1. How Deal Desk Works Today (legacy tooling)

The current Deal Desk is built on Microsoft 365, **not** Salesforce:

- **Intake:** an **MS Forms** form — the *Approval Exception Form* — submitted by the sales rep.
  - URL: `https://forms.office.com/pages/responsepage.aspx?id=O-KBygk17kWpmD40as8nTewazzzUwHpJjwMmbBZY9yVUQzhYSUxCS1hUUzZJVVU2WVE3OUQyRDFXWCQlQCN0PWcu`
  - Form header instructs: *"Hi, Dawn. When you submit this form, the owner will see your name and email…"* and links the two corporate discount approval matrices (Cyber Sales Approval Matrix, Tech Sales Approval Matrix on the `DealDocs` SharePoint).
  - First and pivotal question: **"Exception Type"** — *"What type of exception are you requesting approval for? If you are requesting multiple exceptions please select 'Multiple'."* (single-select dropdown). This selection drives the routing.
- **Tracker / routing:** a SharePoint site **`FortraOperations-DealDeskTracker`**, list **"Deal Desk Mention Assignments"**. Each row maps an *Exception Type* → the **Cyber team members** to @-mention and the **Tech team members** to @-mention, plus a standing review **Comment** (the instruction shown to reviewers). See §3 for the full table.
- **Approval channel:** per the matrix general notes, *"All approvals should be made via **email**, with the exception of Deal Desk"* — i.e. routine in-threshold approvals are email; out-of-threshold items go through the Deal Desk form/tracker.

This three-part shape (Form intake → routing table → notified reviewers + standing comment) is the workflow an RCA implementation must replicate inside Salesforce.

---

## 2. Deal Desk Exception / Option Types

Two source lists enumerate the exception types, with slightly different groupings.

### 2.1 "Deal Desk Options Used Today" (the MS-Forms dropdown values)

From the embedded image in [Deal Desk Options.docx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Deal Desk Options.docx) (the .docx body is just the title "Deal Desk Options Used Today"; the content is the screenshot of the Exception Type dropdown). These are the selectable **Exception Type** values on the Approval Exception Form, in order:

1. Multiple Exceptions
2. Perpetual License Discount
3. Subscription License Discount
4. Services Discount
5. Multi-Year Contract Annually Paid (MYCAP)
6. Maintenance Discount
7. Hardware Change Fee
8. Subscription Start Date
9. Emailed Acceptance of a Quote (signed or unsigned)
10. Displaced/Swap ARR
11. Net Terms
12. Legal Terms and Non-Standard Documentation
13. Annual Index Increase Change – COLA (not MYCAP)
14. AWS Marketplace Renewal
15. Export Control / Sales Appeal Denial Confirmation
16. Non-Standard License Type
17. Offline Quote

### 2.2 2025 Deal Desk Approval Workflow categories

The matrix workbooks' **"Deal Desk Workflows"** tab groups the items into four workflow buckets (the *Reviewer(s) – Roles* column was left blank in the draft):

| Workflow category | Items |
|---|---|
| **Discount Approval** | Channel MSP Discount; Perpetual License Discount; Subscription License Discount; Services Discount; New Maintenance Discount; **SAARC** |
| **Process Exceptions** | MYCAP; Subscription Start Date; AWS Marketplace Renewal; Displaced ARR (Swap); Email Quote Approval; Offline Quote |
| **Legal Approval** | COLA Change; Legal Non-Standard Form (SaaS); Legal Non-Standard Form (On-Prem); Legal Terms; Non-Standard Net Terms; Non-Standard License Type |
| **Other** | Hardware Change Fee; Other; Export Control – Sales Appeal |

> Drift note: the dropdown list (§2.1) and the workflow buckets (§2.2) are *near* but not *exactly* aligned — the dropdown splits "Legal Terms and Non-Standard Documentation" into one item while the workflow tab splits SaaS vs On-Prem non-standard forms; the dropdown has a single "Emailed Acceptance (signed or unsigned)" while the tracker later split it into signed/unsigned (see §3); "**SAARC**" and "**Channel MSP Discount**" appear only in the workflow buckets, "Net Terms" only in the dropdown. **SAARC is undefined in any source doc** (open question, also flagged in doc 10).

---

## 3. Reviewer Roster per Exception Type — Deal Desk Approvers

Source: [Deal Desk Approvers.xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Deal Desk Approvers.xlsx), sheet `query (43)` — an export of the SharePoint **"Deal Desk Mention Assignments"** list (`sites/FortraOperations-DealDeskTracker`). For each exception type it records the **Cyber team members notified**, the **Tech team members notified**, and the standing **review Comment** shown to those reviewers. (The `;#NN` suffixes are SharePoint user-lookup IDs; people names retained, IDs stripped below for readability.)

| Exception Type | Cyber team notified | Tech team notified | Standing review comment / rule | Created |
|---|---|---|---|---|
| **Perpetual License Discount** | Tia Cameron Barisoff; Chris Hand; Matt Swan | Tim Woodfield; Geoff Fischer; John Racine; Brian Pick; Carl Taylor; Michael Nicholas | **Review required by GM/CRO and Finance.** | 2024-04-24 |
| **Subscription License Discount** | Tia Cameron Barisoff; Chris Hand; Matt Swan | Tim Woodfield; Tia Cameron Barisoff; Geoff Fischer; John Racine; Brian Pick; Carl Taylor; Michael Nicholas | **Review required by GM/CRO and Finance when discount is 50% or greater.** | 2024-04-24 |
| **Services Discount** | Jaymie Cater; Renee Ritter | Tim Woodfield; Tia Cameron Barisoff; Cassie Tusler | **Approval required for discounts above 20%, otherwise FYI.** | 2024-04-24 |
| **Maintenance Discount** | Jaymie Cater; Renee Ritter | Tim Woodfield; Tia Cameron Barisoff | Review the maintenance discount and provide comments. | 2024-04-24 |
| **Hardware Change Fee** | Chris Hand; Tia Cameron Barisoff | Tim Woodfield; Tia Cameron Barisoff | Review the hardware change fee. | 2024-04-24 |
| **Subscription Start Date** | Mandy Lopez; Jaymie Cater; Renee Ritter; Dale Watkins | Tim Woodfield; Tia Cameron Barisoff; Cassie Tusler; Carl Taylor; Dale Watkins | **Review/commentary required for rev-rec impact from Finance; FYI for Customer Ops.** | 2024-04-24 |
| **Emailed Acceptance of a Quote (signed or unsigned)** | Chris Hand; Tia Cameron Barisoff | Tim Woodfield; Tia Cameron Barisoff | Review the email acceptance. **If the rep can get the customer to sign via DocuSign, that is preferred.** | 2024-04-24 |
| **Displaced/Swap ARR** | Mandy Lopez; Jaymie Cater; Renee Ritter; Matt Swan | Tim Woodfield; Tia Cameron Barisoff; Mandy Lopez; Cassie Tusler; Jaymie Cater; Renee Ritter; Carl Taylor | **Customer Ops — review for eligibility. Finance — validate the Displaced ARR calculation.** | 2024-04-24 |
| **Net Terms** | Dale Watkins; Kevin Pereira | Tim Woodfield; Geoff Fischer; John Racine; Brian Pick; Cassie Tusler; Dale Watkins; Michael Nicholas | Comment on existing net terms, open/aged AR, payment history for existing customers/partners. **For new customers/partners, perform a credit check for orders above $50k.** | 2024-04-24 |
| **Legal Terms and Non-Standard Documentation** | Ryan Atlas; Kyle Hofmann; Sarah Sederstrom; Joseph Belton | Ryan Atlas; Kyle Hofmann; Sarah Sederstrom; Joseph Belton | **Legal — comment on this request to use non-standard documentation.** (Same Legal team for both LOBs.) | 2024-04-24 |
| **Annual Index Increase Change – COLA (not MYCAP)** | Jaymie Cater; Renee Ritter; Dale Watkins | Tim Woodfield; Tia Cameron Barisoff; Dale Watkins | **Comment on the rev-rec impact of this COLA negotiation.** | 2024-04-24 |
| **AWS Marketplace Renewal** | Tia Cameron Barisoff; Mandy Lopez | Tim Woodfield; Cassie Tusler; Tia Cameron Barisoff | Review this AWS marketplace renewal. | 2024-04-24 |
| **Export Control / Sales Appeal Denial Confirmation** | Vicky McCartney; Tia Cameron Barisoff | Vicky McCartney; Tia Cameron Barisoff | Review this sales appeal denial. | 2024-05-22 |
| **Multiple Exceptions** | *(none listed)* | *(none listed)* | *(blank — routing resolved by the individual exception types selected)* | 2024-05-23 |
| **Other** | Vicky McCartney; Tia Cameron Barisoff | Vicky McCartney; Tia Cameron Barisoff | Review the Exception Type. **If ALE credit is being requested, Matt Swan should be remarked.** | 2024-05-23 |
| **Non-Standard License Type** | Mandy Lopez; Dale Watkins | Cassie Tusler | Comment on the historical payment history. | 2024-05-30 |
| **Multi-Year Contract Annually Paid (MYCAP)** | Tia Cameron Barisoff | Tim Woodfield; Tia Cameron Barisoff | **Review for eligibility to re-submit the quote to the customer.** | 2024-06-18 |
| **Offline Quote** | Vicky McCartney; Tia Cameron Barisoff | Vicky McCartney; Tia Cameron Barisoff | Review the Exception Type. **If ALE credit is being requested, Matt Swan should be remarked.** | 2025-06-27 |
| **Emailed Acceptance of a Quote (Signed)** | Tia Cameron Barisoff; Chris Hand | Tia Cameron Barisoff; Tim Woodfield | Review this email acceptance of a quote (signed). | 2025-09-03 |
| **Emailed Acceptance of a Quote (Unsigned)** | Tia Cameron Barisoff; Dale Watkins | Tia Cameron Barisoff; Dale Watkins | **Validate rev-rec exposure & plan to mitigate; track future signed quote/PO/customer payment within 7 to 14 days.** | 2025-09-03 |

### 3.1 Routing observations (for RCA design)

- **Cyber vs Tech reviewers differ per exception** — the routing is a function of *(Exception Type × LOB)*. RCA must carry the LOB (Cyber/Tech) on the Quote/Account and pick the reviewer set accordingly.
- **Recurring reviewer personas** (map to Quote Approval Teams in §4):
  - **Sales Exec Ops:** *Tia Cameron Barisoff* (appears on nearly every row, both LOBs).
  - **Sales ELT:** *Chris Hand* (Cyber), *Tim Woodfield* (Tech).
  - **Finance / rev-rec:** *Jaymie Cater, Renee Ritter, Dale Watkins, Cassie Tusler, Mandy Lopez, Carl Taylor*.
  - **Legal:** *Ryan Atlas, Kyle Hofmann, Sarah Sederstrom, Joseph Belton* (identical for Cyber & Tech).
  - **Export Control / appeals:** *Vicky McCartney*.
  - **ALE credit watcher:** *Matt Swan* — to be added whenever ALE credit is requested ("Other" / "Offline Quote").
- **Embedded conditional thresholds inside the routing comments** (these are *triggers*, distinct from the doc-10 approver caps):
  - Subscription License Discount: GM/CRO + Finance only when **discount ≥ 50%**.
  - Services Discount: approval only when **> 20%** (else FYI only).
  - Net Terms: **credit check required for new customers/partners on orders > $50k**.
  - Emailed Acceptance (Unsigned): rev-rec exposure must be validated and a signed quote / PO / payment tracked within **7–14 days**.
- **Process evolution:** the single "Emailed Acceptance (signed or unsigned)" item (2024-04) was later split into separate **Signed** and **Unsigned** rows (2025-09), with tighter rev-rec handling on Unsigned. "Offline Quote" was added 2025-06. This shows the exception taxonomy is still actively evolving.

---

## 4. Quote Approval Teams (persona inventory)

Source: [Quote Approval Teams.xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Quote Approval Teams.xlsx). A discovery worksheet listing the **approval team / role personas** that the RCA approval process must model. The middle column "Type (Team, Queue, Individual People)" was **left blank** in the draft (open decision: which become SF Public Groups vs Queues vs role-based assignees). The "?" marks are the author's own uncertainty flags.

### 4.1 Approval Teams listed (split Cyber / Tech)

| Approval Team (role) | Cyber | Tech | LOB Persona |
|---|---|---|---|
| Account Executives (AEs) | AEs – Cyber | AEs – Tech | Account Executive |
| Channel Account Managers (CAMs) | CAMs (Channel Account Manager) – Cyber | CAMs – Tech | |
| Managing Director | Managing Director – Cyber **?** | Managing Director – Tech | |
| Sales Director | Sales Director – Cyber **?** | Sales Director – Tech | |
| General Manager | GM – Cyber **?** | GM – Tech | |
| VP Renewals | VP Renewals – Cyber | VP Renewals – Tech | |
| EVP | EVP – Cyber **?** | EVP – Tech | |
| CCO | CCO – Cyber | *(n/a — Tech uses CRO/CEO chain)* | |
| CRO | CRO | | |
| CFO | CFO | | |
| CEO / President | CEO / President | | |
| VP FP&A | VP FP&A | | |
| CRO Direct Reports | CRO Direct Reports | | |

*Note in source:* "Some roles have Proxy." Personas were identified via the **Change Management – Persona Creation Matrix** (link in source).

### 4.2 Example persona holders (from the Change-Management persona mapping in the same sheet)

| Persona / User Group | Cyber example | Tech example | Department |
|---|---|---|---|
| Sales ELT | Chris Hand | Tim Woodfield | Executive |
| Sales Executive Ops | Tia Cameron Barisoff | Tia Cameron Barisoff | Sales |
| Sales Leadership (Sales User) | Arnold Harden | Joe Eginger | Sales |
| Solution Engineers | Joshua Selvidge | Heath Kath | Sales |
| Account Executive / Account Manager (Sales User) | Harlan Blumenthal | Emma Campbell | Sales |
| Strategic Account Manager (Sales User) | Shanna Gordon | *(—)* | Sales |

These confirm the §3 routing personas: *Chris Hand = Cyber Sales ELT*, *Tim Woodfield = Tech Sales ELT*, *Tia Cameron Barisoff = Sales Exec Ops (both LOBs)*.

### 4.3 Approved Proxies (from the matrix "Approved Proxy" tab — relevant to who can sign approvals)

| Role | Primary | Approved Proxy |
|---|---|---|
| CFO | Justin Ritchie | Vicky McCartney |
| President | Matt Reck | Tia Barisoff **or** Chris Hand |

> RCA implication: an approval step assigned to CFO/President must allow these named proxies to act — i.e. delegate/alternate approvers, not a single user.

---

## 5. Approval Exception Form (intake fields)

Source: [Approval Exception Form.xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Approval Exception Form.xlsx). The workbook itself contains **only the MS Forms URL** (one cell) plus an **embedded screenshot** of the live form's top section. The screenshot captures only the form **header and Question 1**; the remaining questions are not in any extracted artifact.

Captured from the form:

- **Header links:** "Corporate Discount Approval Matrices (links below):" with **Cyber Sales Approval Matrix** and **Tech Sales Approval Matrix** linking to `helpsystemsllc.sharepoint.com/sites/sales/DealDocs/...` (the same two workbooks summarized in doc 10).
- **Greeting:** "Hi, Dawn. When you submit this form, the owner will see your name and email." (`* Required`)
- **Section title:** "Exception Request"
- **Q1 — Exception Type** *(required, single-select dropdown, "Select your answer")*: *"What type of exception are you requesting approval for? If you are requesting multiple exceptions please select 'Multiple'."* → the dropdown values are the §2.1 list (including the "Multiple Exceptions" branch).

> **Gap / not extractable:** the remaining form questions (the per-exception detail fields — e.g. discount %, amounts, quote ID, justification, customer, attachments) are **not present** in the .xlsx (it is a thin wrapper around the live MS Form). The actual field set must be obtained from the live form (URL above) or rebuilt during RCA design. This is the most significant content gap in this topic.

---

## 6. Approval Thresholds — Summary & Cross-Reference (owned by doc 10)

The two matrix workbooks ([Sales Approval Matrix 2024_Draft.xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Sales Approval Matrix 2024_Draft.xlsx) = the **Tech/GM-EVP** variant, and [Tech Sales Approval Matrix 2024_Draft .xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Tech Sales Approval Matrix 2024_Draft .xlsx) = the **Cyber/CRO** variant) also live under `Quotes and Billing/Quote Approval/`. They are the **same content** copied here as those in `Pricing and Products/Approval Matrix/` that **[doc 10](10_pricing-strategy-and-approval-matrix.md)** fully tables. To avoid duplication, only the process-relevant summary is given here — see doc 10 §2 for the complete threshold→approver tables.

> **Naming caution (file vs content):** in *this* folder the file named `Sales Approval Matrix…` carries the **Tech (GM/EVP/MD/Sales Director)** role labels, while the file named `Tech Sales Approval Matrix…` carries the **Cyber (CRO / CRO-direct-reports / CCO)** role labels — i.e. the filenames are effectively swapped relative to their contents. Both are the 2024 draft, "**Approved 250310**", latest revision **4/11/25**. Each has 6 tabs: New Sale_Upsell, Legal, Renewals, Deal Desk Workflows, Useful links, Approved Proxy.

### 6.1 The escalation rule that gates Deal Desk

The single most important process rule the threshold matrices encode:

- **Below ~50% discount:** approvals are **email-based**, handled at AE/CAM → (MD/Sales Director or CRO-direct-reports) → (GM/EVP or CRO) tiers, by product-line type.
- **At / above 50% of list, OR any MYCAP, Displaced ARR, or non-standard Legal scenario:** **Deal Desk approval is mandatory** (CCO/CRO/CFO/CEO/CLO as applicable). This is the line that decides whether the §1 Form/Tracker flow is invoked at all.

Authorized tiers (abbreviated — full %s and $ caps in doc 10 §2.1–2.3):

| Tier | Perp Lic | New Subs | Channel/MSP | Services | New Maint | Order-$ acceptance limit |
|---|---|---|---|---|---|---|
| AEs / CAMs | ≤25% | ≤15% | ≤15% | ≤15% | — | unsigned email accept < $15k |
| CRO-direct-reports *(Cyber)* / MD or Sales Director *(Tech)* | ≤35% | ≤20% | ≤20% | ≤20% | — | < $25k |
| CRO *(Cyber)* / GM or EVP Sales *(Tech)* — **DEAL DESK** | ≤50% | ≤50% | ≤50% | (EVP ≤50% per 4/11/25) | — | ≤ $100k |
| CFO / CEO / VP FP&A — **DEAL DESK** | >50% | >50% | >50% | ≤100% (in lieu of CCO) | >50% | > $100k |
| CCO *(Cyber)* — **DEAL DESK** | — | — | — | ≤100% | ≤50% | — |

VP FP&A may approve >50% where the **discount value is < $30k**; >$30k discounts at >50% go to CFO/CEO. CRO-direct-reports (Cyber) / MDs or Sales Directors (Tech) may approve **free/highly-discounted software up to $3,500** to reconcile customer issues without CFO approval.

**Renewals (doc 10 §2.3):** Sr Mgr/Director removed 4/11/25; **VP Renewals** ≤20% / ≤$100k; **CCO/CEO/CFO** for >20% or >$100K. Subscription→Perpetual switch always = Deal Desk. **Legal (doc 10 §2.2):** non-standard net terms, LoL above $2M, sub-default-COLA, and customer-form use escalate to **CFO/CEO/CLO Deal Desk**.

---

## 7. Open Questions & Ambiguities

1. **Approval Exception Form field set is missing** — only Q1 (Exception Type) was captured; the per-exception detail questions are not in any extracted artifact. Must be retrieved from the live MS Form or rebuilt for RCA. (§5)
2. **"Type" of each Quote Approval Team is undecided** — Team vs Queue vs Individual is blank in the source. RCA must decide Public Group / Queue / role-hierarchy assignment per team. (§4.1)
3. **"?" roles** (Managing Director, Sales Director, GM, EVP — Cyber side; CCO presence on Tech) are author-flagged as uncertain — confirm which exist per LOB before modeling approvers.
4. **SAARC** appears as a Discount-Approval workflow item but is **defined nowhere** (also flagged in doc 10). Confirm meaning/threshold.
5. **Dropdown vs workflow-bucket drift** — the §2.1 form options and §2.2 workflow categories are not 1:1 (signed/unsigned split, SaaS/On-Prem split, Channel-MSP & SAARC only in buckets, Net Terms only in dropdown). Reconcile to a single canonical exception taxonomy for RCA. (§2)
6. **Filename↔content swap** on the two matrix workbooks in this folder (Tech labels in the "Sales" file, Cyber labels in the "Tech" file) — verify which is authoritative before mapping role labels.
7. **Deal Desk SLAs** annotated "*Vicky — need clarity from Matt/Tia if we are even going to have them?*" — SLA existence/values are unsettled. (Useful-links tab)
8. **Multi-LOB routing** — for a Quote spanning Cyber + Tech, which reviewer set applies? The tracker keys routing on a single LOB column; cross-LOB quotes are unaddressed.
9. **Legacy tooling vs RCA target** — the entire flow (MS Forms + SharePoint "Mention Assignments" list + DealDeskTracker) is Microsoft-side. Decision needed: replicate as a native SF Approval Process / Flow + Queues, or keep an external tracker integrated via MuleSoft.

---

## 8. Connections to the RCA / Workday / MuleSoft Implementation

- **Approval workflow vs content split:** *this doc* = the **routing/process** (exception types → notified reviewer teams → standing comments → the intake form); **[doc 10](10_pricing-strategy-and-approval-matrix.md)** = the **matrix content** (the %s, $ caps, role caps). An RCA approval design must combine both: read line-type + discount-% + order-total + LOB on the Quote, decide email-vs-Deal-Desk via the doc-10 thresholds, then route to the correct §3 reviewer team.
- **Fields the rules key off** are the legacy D365/HelpSystems Quote/Line fields catalogued in doc 10 §3 — notably list price (`priceperunit`/`price`), extended/total amount (order-$ thresholds), `hs_displacedarr` (Displaced-ARR rule), `hs_mycap`/`hs_includemycapterms` (MYCAP), export-control fields (Export Control – Sales Appeal item), and AWS Marketplace fields (`hs_awsofferid` etc., AWS Marketplace Renewal item). RCA must surface equivalents on the RCA Quote / QuoteLine.
- **DocuSign preference:** the Emailed-Acceptance routing rule explicitly prefers **DocuSign-signed quotes** — relevant to the RCA quote-signature integration.
- **Rev-rec / Finance gating** (Subscription Start Date, COLA, Unsigned-email-acceptance) ties into Workday revenue recognition; the "track signed quote/PO/payment within 7–14 days" rule is a finance-controls requirement that should be reflected in the Quote→Order→Workday handoff.
- **Proxy approvers** (CFO→Vicky McCartney; President→Tia Barisoff/Chris Hand) require delegated-approver support in the SF Approval Process.
- **COLA / MYCAP overlap with active tickets:** the COLA-change and MYCAP exception items connect to the SC-3350 COLA renewal-pricing rework and the multi-year MYCAP pricing handled in RCA pricing procedures.

---

## Sources

- [Quotes and Billing/Quote Approval/Deal Desk Options.docx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Deal Desk Options.docx) — extracted text was title-only ("Deal Desk Options Used Today"); **content read from the embedded image** `discovery-extract/embedded-images/DealDeskOptions/image1.png` (vision) = the Exception-Type dropdown list (§2.1).
- [Quotes and Billing/Quote Approval/Deal Desk Approvers.xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Deal Desk Approvers.xlsx) — extracted text read in full (sheet `query (43)`, 21 rows = the SharePoint "Deal Desk Mention Assignments" export) → §3.
- [Quotes and Billing/Quote Approval/Quote Approval Teams.xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Quote Approval Teams.xlsx) — extracted text read in full (Sheet1, 41 rows) → §4.
- [Quotes and Billing/Quote Approval/Approval Exception Form.xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Approval Exception Form.xlsx) — extracted text = MS Forms URL only; **embedded form screenshot** (`xl/media/image1.png`, 1637×857) read via vision → §5. Remaining form questions NOT extractable (thin wrapper around the live form).
- [Quotes and Billing/Quote Approval/Sales Approval Matrix 2024_Draft.xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Sales Approval Matrix 2024_Draft.xlsx) — extracted text read in full (6 sheets; carries **Tech/GM-EVP** role labels) → §2.2, §6.
- [Quotes and Billing/Quote Approval/Tech Sales Approval Matrix 2024_Draft .xlsx](Fortra Discovery Documentation/Quotes and Billing/Quote Approval/Tech Sales Approval Matrix 2024_Draft .xlsx) — extracted text read in full (6 sheets; carries **Cyber/CRO** role labels) → §2.2, §6, §4.3.
- Cross-reference: **[doc 10 — Pricing Strategy & Approval Matrices](10_pricing-strategy-and-approval-matrix.md)** (owns the full threshold tables and the legacy Quote/Billing field catalog).
