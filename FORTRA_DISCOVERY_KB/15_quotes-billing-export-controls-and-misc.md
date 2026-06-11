# 15 — Quotes & Billing: Export Controls (Trade Compliance) + Operational ARR / Billings Data

> **Scope.** Raw business-discovery inputs from the **Quotes and Billing** workstream that gate or instrument quoting/ordering but are *not* CPQ rules: (1) **Export-control / trade-compliance** screening (denied-party / sanctions screening, country license requirements) as a discovery-call write-up; (2) the **Outflank ARR** analytics model (how the Outflank Security business unit's recurring revenue & renewals are tracked outside CRM); (3) the **Running Master Billings File** — Finance's monthly billings consolidation/reconciliation workbook (legacy GP/Scooby/CRM billings normalization); (4) the root-level **QuotesToReprice.xlsx** — a 4-quote work-list of UAT quotes flagged for repricing.
>
> **Why this matters for the SF RCA build.** Export controls is a **hard compliance gate** that must be re-implemented in Salesforce (the design KB §8.3 describes the *target* RCA model — this doc is the *as-is* business process and the integration requirements behind it). The ARR and Billings spreadsheets are **shadow systems** — finance/RevOps run revenue, retention, and billings reconciliation in Excel today because the legacy CRMs (D365, Tripwire SF, Globalscape SF) don't produce trustworthy recurring-revenue or normalized-billings data. They document the data model RCA + Workday must replace, and the exact column lists those downstream consumers expect.
>
> Source folder: [`Quotes and Billing`](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing). Complements the design KB (`FORTRA_KNOWLEDGE_BASE.md` §8.3 Export Control Screenings, §8 Quote & Billing objects). **Read alongside** design KB §8.3 for the target-state object/automation design.

---

## 1. Export Controls / Trade Compliance — As-Is Discovery

**Source:** [Export Controls Discovery.docx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/Export%20Controls%20Discovery.docx) — summary of a discovery call with **Emily Bredhold (Legal)** on **2/19/25**.

### 1.1 Flag — this is a compliance requirement for the SF implementation

Export control / trade-compliance screening is a **legal obligation that gates quoting and order placement**, not a nice-to-have. Fortra (a cybersecurity vendor selling offensive-security tooling) must screen customers/contacts against US & EU sanctions and denied-party lists, and for certain products must verify **country-specific export licenses** *before a quote can be generated*. Today this is **highly manual and fragmented across 4 different processes** in two CRMs (Tripwire SF + the "rest of Fortra"). The SF RCA migration is the opportunity to consolidate it. Legal has been asking for a real tool **for the last couple of years**.

### 1.2 The four as-is screening processes

| # | Process | Owner | System / Tool | Trigger / Cadence | Mechanism |
|---|---|---|---|---|---|
| 1 | **Tripwire pre-order / opp screening** | Melissa Loch & team → escalate to Emily Bredhold (Legal) | **Tripwire SFDC**, integrated to vendor **OCR Inc.** (old version of **Visual Compliance**, now Descartes; limited-functionality endpoint) | Salesperson submits a form in SFDC **before an Order is placed**; **re-run when the opportunity hits Stage 7** | SF sends form data to OCR vendor → vendor keyword-scans against SDN / non-SDN / all publicly available US export lists → returns results. New sales only, **not renewals**. |
| 2 | **Tripwire quarterly batch** | Melissa Loch & team | Tripwire SFDC report → vendor portal | **Quarterly** | Report of accounts with **address outside the US** sent to vendor in a specific file format; results returned as a file; Melissa clears, escalates unclearable to Emily. |
| 3 | **Offensive Security export process** (ELM) | **Victoria Mullady (Cops)** → **Export Compliance Committee** (Emily is a member) | Custom code / **ELM** | Per-deal | Because of product nature, screening covers **individuals allowed to use the products** (not just accounts) and has special rules — *can sell to some governments but not their military branches*. ELM checks **ICANN, government lists, automatic Google search**. Victoria does the initial check, escalates concerns to the committee. |
| 4 | **"Rest of Fortra" screening** | **Emily Bredhold (Legal)**; finance file from **Connor Kilmurray** | Manual (Excel + vendor portal) | **Twice a year** (wants quarterly once less labor-intensive) | Emily gets a large account-level file from finance, **deduplicates so only one line per company name** (else billed multiple times by the vendor), reformats/transforms into the vendor template (some cells left blank), uploads, gets results back, resolves many **false positives from keyword search** (Googles to confirm e.g. "company X in country A" vs "company B in Moscow"). True problems → **Customer Ops removes customer access**; harder cases → Kyle → external legal group. |

### 1.3 Key business rules captured

- **Renewals are NOT screened** in the Tripwire pre-order process (process #1) — new sales only. *(Open gap: should RCA screen renewals?)*
- **Offensive Security has individual-level + end-use restrictions** beyond account screening — e.g. allowed to sell to a government but not its military branch. This is the strictest tier and cannot be satisfied by simple account/SDN matching.
- **"Rule UK"** (explicitly named): *Based on product and ship address, **before a quote can be generated**, supporting documentation is needed from the customer.* → This is the quote-gate requirement: certain product + ship-country combinations require an export license/document on file before quoting is allowed. (Maps to the design-KB Export License Document object + quote-approval block — see §1.6.)
- **Dedup requirement:** the screening file must have **one line per company name** or the vendor charges per duplicate line — implies RCA must produce a deduplicated account extract for batch screening.

### 1.4 Process-improvement asks (future-state requirements for RCA)

- Get **at least the Tripwire-style process** rolled out across all of Fortra — a step forward even with manual gaps.
- **Pull the account file directly from the CRM in the format the vendor needs** (eliminate Emily's manual reformat/transform step).
- Make the Tripwire process **less manual** — pick up data automatically and send back automatically (auto round-trip).
- Once automated, **move twice-a-year batch scanning to quarterly**.
- There's interest in **moving export screening earlier — to the Lead level** — but this is a business-process decision Emily isn't in the loop on. *(Open question — confirm with whoever owns lead process; connects to Sales & Marketing lead flow KB.)*
- **Urgency:** Legal has asked for ~2 years; no new regulation has raised priority beyond current.

### 1.5 Vendor / tool evaluation — Visual Compliance by Descartes (BSI investigated 2022)

To get true pricing, the vendor needs answers to scoping questions — these double as a **system-integration inventory** for RCA:

**Pricing drivers (number of integrations + batch size + update volume):**
- Number of systems to integrate to: **Salesforce Classic, Salesforce Lightning, MS Dynamics 365** (named) — *"we'll have **8–9 integrations** → special pricing"*.
- Total existing accounts + contacts (+ anything else to batch-screen).
- Total annual **changes** to existing accounts/contacts.
- Total annual **new** accounts/contacts.
- Number of users doing **on-line screening**; number of users **resolving alerts**.

**Business-process questions (drive RCA config):**
- **What to screen:** Accounts, Contacts.
- **At what points:** *Rule UK* — based on product + ship address, before a quote can be generated, customer supporting documentation is needed.
- **When to re-screen** (cadence).
- **Which team sees/manages alerts; how many users.**
- **What rules / what do you screen for.**

**Tool capabilities noted from demo (target capabilities for RCA):**
- Compliance workflow details + attachments **saved to the audit record**.
- **Nightly re-screen process**: if sanctions are lifted, alerts auto-update and **automatically clear holds**.
- Delivered as a **Managed Package** (new for Dynamics).
- Pricing model: vendor sets up in **Sandbox**, then promotes to **Prod**, keeps sandbox for changes; access to integration team + assigned support rep; pricing based on # integrations, initial batch size, expected CRM update volume.
- **Value-add over raw state lists / current process:** Rules Management, Alerts Workflow, saving documentation+data to audit record, data source = **US and EU lists plus additional account-name matching**, could implement in a week.
- Hosting: **AWS primary East Coast, backup West Coast**.

### 1.6 Connection to the SF RCA / target design

This as-is discovery is the requirements source behind **design KB §8.3 "Export Control Screenings (CSL) — Descartes/OCR API"** and the **Export License Document** object. Key target-state mappings:

| As-is (this doc) | Target RCA design (design KB §8.3) |
|---|---|
| OCR Inc. / Visual Compliance keyword API | **Descartes/OCR API** integration (likely via MuleSoft) |
| Quarterly bulk re-screen of non-US accounts | **Quarterly bulk re-screen** of all active customers incl. global ultimate parents; false positives → Legal (`contracts@fortra.com`); future **nightly auto-clear** |
| "Rule UK" — product + ship-country needs doc before quote | **Export License Document** object: `Status` (Active/Expired/Requested), `Document Type` (End User Undertaking, EU General Export Authorization, Open/Standard Individual Export License, US Export Control License – Offensive Security), `Export Control Category` (Secure Email/ICAP Gateway, Cobalt Strike, Core Impact, Outflank), Start/End Date, License Number, Default/Regional License flags, Document Link |
| Offensive Security committee + access removal | **Quote-level approval flow** blocks activation until Customer Ops Export Approval = Yes (Offensive Security), or until a valid Active (>30 days) doc of correct type exists for Solution-3 + ship-to country (Email Security) |
| Manual expiry tracking | status → Expired when End Date passes; **weekly Monday** email to `cyber.operations@fortra.com` (cc `cyber.renewals@fortra.com`) for licenses expiring in 90 days |
| Country-specific list spreadsheet | "Country specific Export Control List" spreadsheet drives country requirements |

**Glossary (from design KB):** **CSL** = Consolidated Screening List; **ECJU** = UK Export Control Joint Unit; **SDN** = Specially Designated Nationals (OFAC). The vendor "Descartes" absorbed OCR Inc./Visual Compliance.

### 1.7 Referenced documents NOT in this extract (gaps to chase)

- **"Tripwire Export Control OCR Screening Process Summary from Emily Feb192025.docx"** — the detailed process write-up referenced twice; **not present** in the discovery extract tree. Request from BSI.
- Confluence pages (links only, not extracted): **"Export Control - Documentation - Confluence"** and **"D365 Export Screening Process - Customer Operations - Confluence"**.
- The "Country specific Export Control List" spreadsheet (referenced in design KB; not in this folder).

---

## 2. Outflank ARR Model — Recurring-Revenue & Retention Analytics

**Source:** [Outflank ARR Apr25 v1.xlsx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/Outflank%20ARR%20Apr25%20v1.xlsx) — a 27-sheet Excel ARR engine for the **Outflank Security** business unit (product **Outflank Security Tooling / OST**), data through **April 2025 (FY25)**.

### 2.1 What it is / why it exists

Outflank is one of Fortra's offensive-security brands (OST; bundles "OST & Cobalt", "OST, Cobalt Strike & Core Impact"). This workbook is the **shadow ARR/retention model** built off **invoice-level data exported from CRM (D365/Experlogix) plus a "Pre-CRM" manual tail**. It computes Beginning/Ending ARR, New/Expansion/COLA/Contraction/Churn waterfalls, GRR/NRR, logo counts, renewal rates by tier, ARR by product/geo, and a collections/status view. It is the **as-is definition of how Fortra measures recurring revenue** for this unit — directly relevant to what RCA + Workday must produce natively (ARR rollups, renewal tracking, COLA — see memory: COLA renewal pricing SC-3350).

### 2.2 Sheet inventory & purpose

| Sheet | Size | Purpose |
|---|---|---|
| **YoY Summary** | 32×21 | Monthly / Q2-QTD / YTD / TTM ARR waterfall vs prior year with B/(W) $ and % |
| **Updated Summary** / **Original Summary** | 65×41 / 54×41 | Month-over-month and year-over-year ARR bridge (Beginning, New, COLA, Expansion-less-COLA, Gross Expansion, Gross New, Contraction/Downsell, Churn/Lost, Net New, Ending) + GRR/NRR/Growth/ACV + logo counts; May-2022 → Apr-2025 |
| **Detailed Summary** | 322×16 | Top-10 New/Expansion/Contraction/Churn (monthly & YoY) by customer with MRR/ARR; **Top 25 Renewals for 2025**; **ARR by Product**; **ARR by Geo** |
| **Detailed Export** | 448×50 | Pivot source: Customer (Invoice ID) × Country × Channel-vs-Direct × Billable Partner × Product Type × GP Item Class, with monthly `Sum of MM/DD/YYYY` columns Oct-2021 → Apr-2025 |
| **ARR Status** | 32×30 | **Collection status** roll-forward by month (Paid, PO Received, Remittance Received, In Progress, Initiate First Contact, No Response, Plug, Churn Reserve, DO NOT COLLECT, Pending Cancellation, etc.) + Unpaid / Unpaid % |
| **Renewal Summary** | 121×39 | Available-to-Renew / Did-Not-Renew / Renewed-for-Loss / Gross & Net renewal rates, **overall + Tier 1–4**, monthly + quarterly FY24/FY25 |
| **Inputs** | 5×3 | Model params: `Calc Start Month` 2022-05-31, `Most Recent Month` 2025-04-30, `Month of the Year` 4, **`COLA` = 0.062** (6.2%) |
| **Data** | 1015×157 | Line-level invoice fact table + monthly MRR spread Dec-2020 → May-2028 (see §2.4) |
| **Retention / Retention-Forecast / UFR TIV / UFR ARR-ED / UFR ARR-SD / Renewal Report** | up to 5011×429 | Retention cohort matrices & forecast; **UFR = "Up For Renewal"** (TIV / ARR by End-Date & Start-Date); 5,011-row renewal report |
| **Qs** (Data Checks) | 90×19 | QA tie-out: Top-20 Churn/Contraction/Expansion/New (monthly & YoY) with check %s |
| **Pivot** | 122×17 | Per-customer drill (e.g. Royal Bank of Canada) by Experlogix Area / Sale Type |
| **Name Adjustment** | 4×3 | Customer-name normalization map (e.g. `VocaLink` → `Vocalink Ltd.`) |
| **Summary Lookups** | 14×11 | Period-label + QTD/YTD annualization-factor lookup (drives the summary headers) |
| **Lookup** | 53820×24 | Master reference: **FX rates** (euro 1.07, USD 1, GBP 1.27, AUD 0.65), **ISO-3166 country→region/sub-region** table, **customer name consolidation** (Original→Unique→Consolidated), product-name & product-type maps |
| **Pre CRM** | 35×13 | Manual pre-CRM license tail (see §2.5) |

### 2.3 Headline metrics (as of 2025-04-30, $ thousands)

| Metric | Value (Apr-2025) | Prior-Yr (Apr-2024) |
|---|---|---|
| **Ending ARR** | **$6,905.1K** ($6.905M) | $3,286.7K |
| Beginning ARR (FY25 YTD) | $5,580.3K | $2,135.7K |
| YTD New | $1,330.7K | $1,189.3K |
| YTD COLA | $71.0K | $16.7K |
| YTD Expansion (less COLA) | $182.3K | $8.3K |
| YTD Churn | −$219.3K | −$57.3K |
| YTD Contraction | −$39.9K | −$6.0K |
| **Logo count (Ending)** | **375** | 174 |
| GRR (annualized, monthly Apr) | 0.912 | 0.941 |
| NRR (annualized, monthly Apr) | 1.011 | 0.966 |
| ACV (per logo) | ~$18,414 | ~$18,889 |
| YoY Growth | 1.10× (110%) | 3.34× |

- **ARR by Geo (Apr-2025):** US & Canada $4.008M; Europe $2.415M; Asia $0.331M; Oceania $0.069M; Mexico/Central/South America $0.044M; Africa $0.038M; Antarctica $0. Total $6.905M.
- **ARR by Product:** **OST** carries 100% ($6,905,129); the "OST & Cobalt Bundle" and "OST, Cobalt Strike & Core Impact" bundle rows are $0 (bundles not yet billing).
- **Top renewals 2025** (TIV): NCC Group UK $110K (Jan, did not renew → −$110K churn), Bank of Montreal $90K (Oct), European Commission DIGIT $80.5K (Dec), CA Military Department $74.5K (Oct), Ministerie van Financiën $73.2K (Oct), CommonSpirit Health $68.4K (Jul). *TIV = Total Invoice Value.*

### 2.4 `Data` sheet — the invoice fact table (line-item field list)

This is the **as-is recurring-revenue data contract** (RCA + Workday must reproduce these fields/derivations). Key columns:

`Product Brand · Experlogix Area · Product Type · Product Sale Type · Customer Account Number (Invoice) · Created On (Invoice) · Invoice ID · Currency · Extended Amount · Tax · ALE · Exchange Rate · Extended Amount (Base) · Tax (Base) · Annualized License Equivalent (Base) · Product SKU · Ship To Country · Billable Partner · Number of Months · Start Date · End Date · PaidInFullDate · Status · Status Reason · Customer · Product Name · Quantity · Legal Entity · Cancellation Date · Cancellation Reason · Is Term? · Term Subscription · Ship To Country/Region · Ship To State/Province · Referral Partner · RSM · Software Product Master (Existing/Maintenance Product) · Collections Status · Deployment Type · GP Item Class · Country · Region · Channel vs. Direct · Unique Name · Consolidated Name · Inv Yr/Mo/Yr-Mo · Billings (Base) · Extended Amount – USD · Start/End Year/Month/Yr-Mo · Norm Term · Product Filter · MRR · ARR` + **monthly MRR spread columns Dec-2020 → May-2028**.

- **ALE = Annualized License Equivalent** — the normalized recurring metric (also a formula = Subtotal in the live Quote model; see memory "Quote pricing rollups"). MRR = ALE/12-style spread across the term months; ARR = MRR×12.
- **COLA = Cost-Of-Living Adjustment** uplift applied to renewals (model rate 6.2%). Connects to live SC-3350 COLA renewal pricing rework.

### 2.5 `Pre CRM` sheet — manual license tail (pre-CRM contracts)

Hand-keyed licenses predating CRM capture (license start/months/end + ARR in EUR or USD + comment). Notable rows:

| Customer | Start | Months | ARR | Comment |
|---|---|---|---|---|
| ABN Amro | 2022-09-01 | 12 | €42,000 | |
| Bank Of Montreal | 2022-11-01 | 12 | €45,000 | |
| Van lanschot Kempen | 2022-10-01 | **99** | €42,000 | **Auto-renewal** |
| **Wizlynx Switserland** | 2022-12-16 | **24** | €42,000 | "agreed 24 months, possibly small discount given **export approval delay**" |
| Wizlynx Mexico / Singapore | — | — | — | part of main Switzerland contract |
| Secura | 2022-10-22 | 6 | €22,500 | 6-month paid trial; renegotiating |
| Nettitude | 2022-03-15 | 12 | €40,000 | Will terminate at end of current license |
| EY | 2023-01-01 | 12 | $46,622 | "weird number, actually €45k, USD from CRM" (note in Dutch) |

> **Cross-link:** the **Wizlynx "export approval delay"** note directly corroborates §1 — export-license delays materially affect Outflank/offensive-security deal timing and terms.

### 2.6 Connection to RCA / Workday / MuleSoft

- This workbook is the **target for retirement**: RCA (Subscription Mgmt / RLM) + Workday should natively produce ARR/MRR, renewal status, COLA uplift, and collections status without an Excel model. The exact metric definitions (Beginning/Ending ARR bridge, GRR/NRR, ALE, COLA 6.2%, tiered renewal rates) are the **acceptance criteria** for those native rollups.
- The collections-status taxonomy (Paid, PO Received, Promised-to-Pay, In Progress, No Response, DO NOT COLLECT, Pending Cancellation, Churn Reserve) is an **AR/collections requirement** that lands in Workday.
- **Currency:** model uses fixed FX (EUR 1.07, GBP 1.27, AUD 0.65) — relevant to the multi-currency pricing work (memory SC-3384: non-USD pricing currently wrong); a real system needs live/dated rates, and the memory notes rates are corrupted (7/11 at 1.0).

---

## 3. Running Master Billings File (Q2 / Apr'25) — Finance Billings Consolidation

**Source:** [Running Master Billings File Q2 (Apr'25) - Working Version.xlsx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/Running%20Master%20Billings%20File%20Q2%20%28Apr%2725%29%20-%20Working%20Version.xlsx) — a **~70-sheet, 36,654-row** Finance reconciliation workbook that normalizes and consolidates **all Fortra billings** across legacy source systems for FY2025.

### 3.1 What it is / why it exists

This is **Finance's monthly billings master** — the shadow system that pulls billings from three legacy sources (**Scooby, CRM, PreScooby**), normalizes them (entity/country/currency/product-line), applies brand-specific adjustments and rep-location adjustments, computes **ALE** and **displaced ARR**, and feeds **Power BI** and the **board (For BOD)**. It is the **as-is billings data pipeline** that RCA + Workday + MuleSoft must replace. It documents the legacy **GP (Great Plains) transaction-code / load-code taxonomy**, the brand→solution-group mapping, and the rep roster — all reference data the migration must carry.

### 3.2 Source-system taxonomy (`Lists` + `CRM Tables` sheets)

**Billing sources** (`Source` / `Measures`): **Scooby** (Scooby Billings), **CRM** (CRM Billings), **Prescooby** (Pre Scooby Billings). *"Scooby" is Fortra's internal billings data store/warehouse name.*

**CRM "Load Code" → Sale-Type taxonomy** (the GP/CRM transaction classes — maps to RCA line/sale types and Workday revenue categories):

| Load Code | Sale Type | GP Acct Code |
|---|---|---|
| CRM1 | Software | 4100 |
| CRM2 | New Maintenance | 4110 |
| CRM3 | Base Subscription | 4100 |
| CRM3-N | New Subscription | 4100 |
| CRM3-N MSS / CRM3-MSS | New MSS / Base MSS | 4100 |
| CRM4 | License Upgrade Fee | 4135 |
| CRM5 | Renewal Maintenance | 4120 |
| CRM6 | Services | 4130 |
| CRM7 | Other / Term Subscription | 4140 |

**Region / Entity:** Domestic (US, code SB), International (INTL, code OSM). Entity codes incl. AM, AUS, BI, BW, CCSS, CCSS-UK (GBP), DW, FR (EUR), OPS, OSM (GBP), PT, RJS, SA-NL/SA-UK, Linoma, SB, SW (Switzerland/EUR), TNG, UK (GBP), Hal/Hal-UK/Hal-AUS, SKV, etc. Each maps to a default `Scooby Currency` (USD-LC, GBP, EUR, AUD).

**Product Line ↔ CRM Product Line ↔ Brand ↔ Solution Group** crosswalk (`Lists`) — the canonical brand taxonomy. Selected mappings:

| Brand | Solution Group |
|---|---|
| Robot / Skybot | SM / WLA |
| Powertech / PowertechX | Cybersecurity / PowertechX |
| Globalscape / Linoma | Globalscape / MFT |
| Titus / Boldon James | Data Classification |
| SEQUEL / ShowCase | BI |
| **Outflank** | **Outflank** |
| Cobalt Strike | Cobalt Strike |
| Tripwire / Tripwire - FIM | Tripwire |
| Digital Guardian | Digital Guardian |
| Beyond Security (BSEC) | BSEC |
| PhishLabs | PhishLabs |
| Agari / Terranova | Agari / Terranova |
| Alert Logic - MDR / - Legacy | Alert Logic - MDR / - Legacy |
| FoxT | BoKS |
| RJS | Doc Mgmt |
| Vera | Vera |
| JAMS | WLA |

**Discount-reason taxonomy** (`CRM Tables`, `Discount Sequence` 10–99) — legacy discount reasons that may need RCA picklist values, e.g. `Pro-rated Invoice`(10), `Multiple System Discount`(15), `Multiple Product Discount`(16), `Quantity Discount`(15), `Competitor price match`(30), `ELA`(75), `Bad debt write-off`(65), `Created in error`(85), `Bankruptcy`(87), `Sequel User Based pricing`(88), `Distributor Invoice`(90), `Invoice cancelled`(99).

**GP Product Code map** (`CRM Tables`, far-right) — ~110 internal product codes (e.g. `103010L`→`000003010L`, `503190`, `SB03xxx` Skybot codes) for legacy GP→product mapping.

### 3.3 Key reference / transform sheets

| Sheet | Purpose |
|---|---|
| **Normalization Table** | Term-length normalization: 23 mo→N/A, **24→2yr, 30→3, 42→4, 54→5, 66→6, 84→7** (used to annualize multi-year deals) |
| **Code Lookup table** | Sale-type → Load Code → GP acct code (the §3.2 table) |
| **Rep List** (2,575×19) | Sales-rep roster: Rep / Name / Region / Country, Ess Country/Region, Head Name — drives rep-location billings adjustments |
| **CRM S.T.C Mapping** | Sales-Type-Code map (mostly `#N/A` in this copy — likely broken/empty) |
| **PreScooby / CRM Pivot/Load NEW**, **Add-Backs & Deferrals CRM NEW**, **CRM Norm Load NEW** | Source-by-source pivots → normalized loaders |
| **Pivot For Rep Loc Adj**, **Rep Loc Adj Load NEW/OLD**, **Rep Loc Adj Check**, **Swap Adj-Pivot** | Rep-location revenue reallocation |
| **ALE from Pivot**, **Pre-ALE Billings**, **ALE ADJ Loader**, **ALE Pivot**, **GM ALE**, **Reck ALE** | ALE (Annualized License Equivalent) computation & reconciliation |
| **Billings From Essbase** | Tie to **Essbase** (Oracle/Hyperion financial cube) |
| **Brand-specific ADJ sheets** | `IPP ADJ`, `Agari ADJ`, `DG ADJ`(Digital Guardian, 3 variants), `PHISH ADJ`, `BSEC ADJ`, `Forcepoint ADJ`, `DDI ADJ`, `OTHER ADJ` (389 rows) — manual per-brand corrections |
| **YTD** (36,654×96) | The master normalized fact table (see §3.4) |
| **Adjustment for Slim File** (36,664×26) | Slimmed export |
| **By Brand** | Billings by brand pivot (Apr'25 — Grand Total $37.99M source vs $50.06M; see §3.5) |
| **Pivot on PowerBI** / **PowerBI Data** | Feeds the Power BI report (link embedded: `app.powerbi.com/.../bfbe5e89-...`; Run 2025-05-01) |
| **Rec** (7,782 rows) | Reconciliation |
| **For BOD** (9,858 rows) | Board-of-Directors output |
| **TIE OUT LOADER** | Final tie-out |

### 3.4 `YTD` master fact table — column list (the billings data contract)

The normalized billings record (RCA + Workday + MuleSoft must reproduce):

`Source · REGION · Invoice Number · Sales Type Code · Company Name · Company Number · Sales Fiscal Month · Sales Fiscal Year · Product Code · Transaction Code · Sales Home Currency · USD Currency · Exchange Rate Used · TOTALUNITS · Sales Tax · Entity Code · Parent/Child Product Line · Product Description · Sales Type Name · Sales Date · Term Subscription · Month/Year Maintenance To Start/End (orig + adjusted) · Vendor Type · NETNEW · Request Desc · SA · CDR · Sales Rep · Sales Type Type · Memo Number · Vendor Number/Name · Discount Sequence · Discount Reason Text · Accounting Code · Location Number · Ship Department/Address/City/State/Zip/Country/Postal · Channel Partner · Price Policy · BUNDLE · Processor Group · CPU Serial Number · LPARNumber · hs_computernumber · UsersAgentsDevices · Amt in invoice currency · Swap? · Begin/End Date · Months · # of Years Normalized · Sales Rep Region/Name · ALE SW/NM/NS · ALE · Group · Deferred New Maint/Subs · Y1–Y7 USD · Core vs CIA · L2 · Amount · MyCAP · Sum of Displaced ARR Base · ALE less Displaced ARR · Take to ALE Rec`.

Notable derived fields: **ALE** split into **ALE SW / ALE NM / ALE NS** (Software / New Maint / New Subs); **Y1–Y7 USD** (multi-year revenue spread); **Displaced ARR** (renewal cannibalization); **NETNEW** flag; **Core vs CIA**; **MyCAP** (capacity/quota). `hs_computernumber`, `LPARNumber`, `CPU Serial Number` reveal **IBM-i / mainframe license-key fields** carried from the Powertech/Robot heritage.

### 3.5 `By Brand` billings snapshot (Apr'25)

Source-currency billings by brand (selected) — illustrates relative brand scale and that this file reconciles two columns (e.g. period vs YTD) with large variances:

| Brand | Col A | Col B | Variance |
|---|---|---|---|
| MFT | $5.55M | $0.33M | −$5.23M |
| Globalscape | $4.00M | $0.41M | −$3.60M |
| SM | $3.44M | $1.33M | −$2.11M |
| Cybersecurity | $2.40M | $1.69M | −$0.71M |
| Tripwire | $2.96M | $1.06M | −$1.90M |
| Vera | $0.47M | $5.38M | +$4.91M |
| Alert Logic - MDR | $0.45M | $7.68M | +$7.22M |
| IPP | $0.33M | $4.24M | +$3.92M |
| Outflank | $0.45M | $0.20M | −$0.26M |
| **Grand Total** | **$37.99M** | **$50.06M** | **−$36.14M** |

*(The two columns appear to be different measures/periods being reconciled; the −$36M "variance" row is a reconciliation artifact, not a real loss.)*

### 3.6 Connection to RCA / Workday / MuleSoft

- This is the **billings reconciliation that Workday is meant to own** (financial back end). The Source taxonomy (Scooby/CRM/PreScooby) and the GP transaction/load-code map are the **legacy mapping** MuleSoft must translate when sending orders to Workday (cf. memory: Workday line-type / `extendedAmount` mapping tickets SC-3143/3210/3347).
- The **ALE** computation here is the finance-side definition of the same ALE that surfaces on the live Quote (formula = Subtotal). RCA pricing rollups must agree with this.
- The **Sales-Type-Code / discount-reason / brand-solution-group** reference data are migration inputs (picklist values, product hierarchy).
- **Essbase** dependency = a current financial-cube integration point that Workday displaces.

---

## 4. QuotesToReprice.xlsx — UAT Quote Reprice Work-List

**Source:** [QuotesToReprice.xlsx](Fortra%20Discovery%20Documentation/QuotesToReprice.xlsx) (root of discovery set; extracted to `discovery-extract/text/QuotesToReprice.xlsx.txt`).

A single sheet (`Sheet1`, 4 rows × 1 col) — just **four Lightning URLs to UAT Quote records** flagged as needing a reprice. No reason column, no notes.

| # | Quote Id | UAT URL |
|---|---|---|
| 1 | `0Q0WC0000028dHd0AI` | https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000028dHd0AI/view |
| 2 | `0Q0WC0000028dHh0AI` | https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000028dHh0AI/view |
| 3 | `0Q0WC000002AHkn0AG` | https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000002AHkn0AG/view |
| 4 | `0Q0WC000001lsvd0AA` | https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000001lsvd0AA/view |

### 4.1 Interpretation & connection to org repricing issues

- These are **`Quote` (`0Q0…`) records in the `fortra--uat` sandbox** — i.e. a **testing/triage work-list in the active RCA build**, not legacy data. Someone collected four quotes to re-run through the pricing procedure (Reprice All).
- The file gives **no stated reason**. Given the cluster of live RCA repricing defects in this org, the most likely candidates are:
  - **`Rev_Mgmt_Default_Pricing_Procedure` rework / republish churn** — multiple memory entries document quotes/orders that broke after the V9 pricing procedure was re-published (SC-3371 convert gack, SC-3372 contributing-products, SC-3374 regional pricing, and the "Specify the contextDefinitionName…" Reprice-All gack from an in-place edit to the live active procedure). Quotes touched during those windows need re-pricing.
  - **Multi-currency mis-pricing (SC-3384)** — non-USD configured products priced using USD values (currency-blind ABA lookups). Affected quotes must be repriced after the data/config fix.
  - **COLA renewal pricing (SC-3350)** — renewal quotes whose net price was wrong pending the COLA rework.
  - **Partner pricing not applied (SC-3359)** — One-Time/Perpetual partner lines saved net=list; affected quotes need reprice after the SubscriptionPricing74 fix.
- **To action:** open each quote in UAT, check `CurrencyIsoCode`, line products (configured/ABA?), sale type (renewal/partner), and the last reprice timestamp, then map to the relevant ticket. **Do not reprice in UAT without a fresh explicit authorization** (per memory: read-only inspection is fine; any UAT DML — even a reprice — needs a fresh ack).

> **Caveat:** the work-list is undated and unattributed. Treat the four Ids as a triage starting point; confirm intent with whoever produced the file before assuming which defect they map to.

---

## 5. Open Questions & Gaps

1. **Export — renewals:** Tripwire pre-order screening explicitly excludes renewals. Does target-state RCA screen renewals? (Design KB implies quarterly bulk re-screen covers active customers — confirm renewals are caught.)
2. **Export — lead-level screening:** Business interest in moving screening to the Lead level exists but is undecided and Legal isn't in the loop. Owner / decision needed.
3. **Export — missing source doc:** "Tripwire Export Control OCR Screening Process Summary from Emily Feb192025.docx" and the two Confluence pages are referenced but not extracted — request the detailed process write-up.
4. **Export — vendor selection:** Is Descartes/Visual Compliance the chosen tool, and is the integration MuleSoft-mediated? (Design KB names "Descartes/OCR API"; confirm contract & 8–9-integration special pricing.)
5. **ARR/Billings shadow systems — retirement plan:** Are the Outflank ARR model and the Master Billings file slated for replacement by native RCA + Workday reporting, and who owns validating that native ARR/ALE/COLA/collections-status match these workbooks?
6. **ALE definition alignment:** ALE appears in the Outflank model, the Billings file, and on the live Quote (formula = Subtotal). Confirm all three definitions reconcile in RCA.
7. **FX rates:** Both spreadsheets use fixed FX (EUR 1.07/1.07, GBP 1.27, AUD 0.65); memory notes live rates are corrupted (7/11 at 1.0). RCA needs a governed, dated FX source — open.
8. **QuotesToReprice:** undated/unattributed; which defect (3371/3372/3374/3384/3350/3359) drove the four quotes? Confirm before any reprice; reprice needs fresh UAT authorization.
9. **CRM S.T.C Mapping sheet** in the billings file is mostly `#N/A` — is the source mapping broken, or just not populated in this working copy?

---

## Sources

**Used (in scope):**
- [Quotes and Billing/Export Controls Discovery.docx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/Export%20Controls%20Discovery.docx) — extracted `discovery-extract/text/Quotes and Billing/Export Controls Discovery.docx.txt` (71 lines, read in full)
- [Quotes and Billing/Outflank ARR Apr25 v1.xlsx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/Outflank%20ARR%20Apr25%20v1.xlsx) — extracted `…/Outflank ARR Apr25 v1.xlsx.txt` (3,819 lines; all 27 sheet markers reviewed; summary/status/renewal/inputs/data/checks/lookup/pre-CRM sections read in full; very large per-line data matrices sampled at header + representative rows)
- [Quotes and Billing/Running Master Billings File Q2 (Apr'25) - Working Version.xlsx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/Running%20Master%20Billings%20File%20Q2%20%28Apr%2725%29%20-%20Working%20Version.xlsx) — extracted `…/Running Master Billings File Q2 (Apr'25) - Working Version.xlsx.txt` (8,557 lines; all ~70 sheet markers reviewed; reference/taxonomy sheets — CRM Tables, Lists, Normalization Table, Code Lookup, By Brand, YTD/PowerBI headers — read in full; large fact tables sampled at header + representative rows)
- [QuotesToReprice.xlsx](Fortra%20Discovery%20Documentation/QuotesToReprice.xlsx) — extracted `discovery-extract/text/QuotesToReprice.xlsx.txt` (5 lines, read in full)

**Cross-referenced (not re-summarized here):**
- `FORTRA_KNOWLEDGE_BASE.md` §8.3 (Export Control Screenings — Descartes/OCR API; Export License Document object) and §8 Quote/Billing objects — the target-state design this discovery doc complements.

**Referenced but NOT in the extract tree (gaps):**
- "Tripwire Export Control OCR Screening Process Summary from Emily Feb192025.docx" (the detailed process write-up).
- Confluence pages: "Export Control - Documentation" and "D365 Export Screening Process - Customer Operations" (links only).
- "Country specific Export Control List" spreadsheet (named in design KB; not in this folder).

**Not extractable / empty:** none of the four in-scope files were encrypted, binary, or empty — all four extracted to readable text. (Within the Master Billings file, the `CRM S.T.C Mapping` sheet was effectively empty/`#N/A` — noted as Open Question #9, not a file-level extraction failure.)
