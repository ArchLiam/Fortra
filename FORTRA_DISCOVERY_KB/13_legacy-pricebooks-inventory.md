# 13 — Legacy Pricebooks (SharePoint) Inventory

**Scope:** A complete inventory of the legacy, per-brand pricebooks exported from SharePoint into `Pricing and Products/Pricebooks From SharePoint/`. These are the **raw source price lists** for the dozens of brands Fortra acquired (Tripwire, GoAnywhere, Alert Logic, Powertech, Robot, Clearswift, Beyond Security, Digital Defense/DDI, Agari, PhishLabs, Cobalt Strike, Terranova, etc.). They are the underlying catalog the **Cyber Pricing Strategy** consolidation (6,000+ SKUs → tiered Good/Better/Best bundles; see **doc 10 — Pricing Strategy & Approval Matrices**) is meant to rationalize, and the price/SKU/UOM data that must seed the new RCA `Product2` / `ProductSellingModel` / `PricebookEntry` catalog during the D365 / Tripwire-SF / Globalscape-SF → Salesforce RCA migration.

**Critical data gap (read first):** **30 of the 33 spreadsheet/PDF files are password-protected / encrypted** and could **not** be text-extracted (their `.txt` contains only `[ENCRYPTED / PASSWORD-PROTECTED WORKBOOK] ... Content cannot be extracted without the password.`). Only **4 files are readable**: 2 GoAnywhere PDFs (USD, AUD), the Alert Logic global price-list PDF, and — contrary to the original brief — **one un-locked XLSX**: `Copy of KK Pricing ALL_Effective 1.1.2025 - DRAFT 2.xlsx` (the Tripwire Japan / TWKK pricebook). Obtaining the workbook password(s) from the Fortra pricing/finance team is a prerequisite to extracting the remaining ~30 brands' SKU-level catalogs for migration.

**How this connects to the RCA / Workday / MuleSoft build:**
- These pricebooks are the **source of truth for legacy SKUs, list prices, quantity-tier breaks, currency, and UOM** that RCA's catalog (`Product2.ProductCode`, `PricebookEntry.UnitPrice`, `ProductSellingModel`, `PriceAdjustmentSchedule`/`PriceAdjustmentTier`) must be loaded from / reconciled against.
- The **quantity-tier and discount structures** seen here (GoAnywhere agent/user tiers, Tripwire node tiers, Alert Logic node tiers) are exactly the **tiered / attribute-based pricing** mechanics that surface in RCA pricing tickets (e.g. SC-3390 tiered pricing double-click, SC-3384 multi-currency, attribute-volume pricing).
- The **multi-currency** dimension (USD, AUD, EUR, JPY) is the legacy basis for the RCA multi-currency pricing problem (SC-3384: non-USD configured pricing erroneously using USD values). The GoAnywhere AUD/USD/EUR sheets and the JPY TWKK sheet are concrete legacy multi-currency catalogs.
- **Subscription vs Perpetual** modeling is explicit in these sheets (GoAnywhere: "Subscription" vs "Perpetual (Requires GM Approval to sell)"; Tripwire JA: separate `-031`/`-033` subscription SKUs). This maps to RCA `ProductSellingModel` (one-time/perpetual vs term-defined subscription).

---

## 1. Complete Inventory Table

Path root: `Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/`
Extracted-text root: `Data/discovery-extract/text/Pricing and Products/Pricebooks From SharePoint/<file>.txt`

Status legend: **READABLE** = text fully extracted; **ENCRYPTED** = password-protected, extraction blocked (data gap).

| # | File | Brand / Product Line | Year / Revision | Format | Status |
|---|---|---|---|---|---|
| 1 | Agari Pricing 2024 - revised 6.21.2024.xlsx | Agari (email security / DMARC) | 2024, rev 6.21.2024 | xlsx | **ENCRYPTED** |
| 2 | Alert Logic_ global-price-list-ds-r1-am.pdf | Alert Logic (MDR / managed detection) | Effective 4/25/2023 (doc id `al-ds-1124-r1-am`) | pdf | **READABLE** |
| 3 | AutoMate Pricing 2024.xlsx | AutoMate (Fortra RPA) | 2024 | xlsx | **ENCRYPTED** |
| 4 | Beyond Security Pricing _revised Oct 2022 (Federal Incl).xlsx | Beyond Security (incl. Federal) | rev Oct 2022 | xlsx | **ENCRYPTED** |
| 5 | Business Intelligence 2024 - revised 7.8.24.xlsx | Business Intelligence (Sequel / Webdocs?) | 2024, rev 7.8.24 | xlsx | **ENCRYPTED** |
| 6 | Bytware 2024 - revised 07.23.24 - locked.xlsx | Bytware (IBM i AV / StandGuard) | 2024, rev 07.23.24 ("locked") | xlsx | **ENCRYPTED** |
| 7 | CCSS Pricing 2024 - revised 7.23.24 - locked.xlsx | CCSS (IBM i monitoring) | 2024, rev 7.23.24 ("locked") | xlsx | **ENCRYPTED** |
| 8 | COS Pricing 2022.xlsx | COS / Core Security? | 2022 | xlsx | **ENCRYPTED** |
| 9 | CTS 2023 - revised 03.27.23.xlsx | CTS | 2023, rev 03.27.23 | xlsx | **ENCRYPTED** |
| 10 | Capacity Management 2023 - revised 03.27.23.xlsx | Capacity Management (Robot/Performance Navigator?) | 2023, rev 03.27.23 | xlsx | **ENCRYPTED** |
| 11 | Clearswift Pricing 2024 - revised 2.1.24.xlsx | Clearswift (email/data security, ICAP) | 2024, rev 2.1.24 | xlsx | **ENCRYPTED** |
| 12 | Cobalt Strike Pricing_May 2024.xlsx | Cobalt Strike (offensive security) | May 2024 | xlsx | **ENCRYPTED** |
| 13 | Copy of KK Pricing ALL_Effective 1.1.2025 - DRAFT 2.xlsx | **Tripwire Japan (TWKK)** — TE, FIM, Policy Manager, IP360, VnE, Device Profiler | Effective 1.1.2025, DRAFT 2 | xlsx | **READABLE** |
| 14 | DDI Pricing 2024_July_Updated VM.xlsx | Digital Defense Inc. (DDI / Frontline VM) | 2024 July, "Updated VM" | xlsx | **ENCRYPTED** |
| 15 | Doc Mgt RJS 2024_24April.xlsx | RJS Document Management (Webdocs) | 2024, 24 April | xlsx | **ENCRYPTED** |
| 16 | GoAnywhere Pricing Sheet - AUD - 2025.pdf | GoAnywhere MFT / FileCatalyst / Clearswift ICAP | 2025 (Revised Dec 2024) | pdf | **READABLE** |
| 17 | GoAnywhere Pricing Sheet - USD - 2025.pdf | GoAnywhere MFT / FileCatalyst / Clearswift ICAP | 2025 (Revised Dec 2024) | pdf | **READABLE** |
| 18 | Halcyon 2024 - revised 07.19.24 - locked.xlsx | Halcyon (IBM i HA / DR) | 2024, rev 07.19.24 ("locked") | xlsx | **ENCRYPTED** |
| 19 | IGA 2023 - revised 03.27.23.xlsx | IGA (Identity Governance & Administration / Core Security) | 2023, rev 03.27.23 | xlsx | **ENCRYPTED** |
| 20 | Intermapper 2023 - revised 03.27.23.xlsx | Intermapper (network monitoring) | 2023, rev 03.27.23 | xlsx | **ENCRYPTED** |
| 21 | JAMS MVP Pricing 2023 - Updated 06.20.xlsx | JAMS (job scheduling, Fortra MVP) | 2023, updated 06.20 | xlsx | **ENCRYPTED** |
| 22 | MFT Pricing 2024 - revised 4-3-24.xlsx | MFT (likely GoAnywhere MFT, separate from PDF) | 2024, rev 4-3-24 | xlsx | **ENCRYPTED** |
| 23 | Outflank 11.30.22_OST&Cobalt Bundles added.xlsx | Outflank (OST) + Cobalt Strike bundles | 11.30.22 | xlsx | **ENCRYPTED** |
| 24 | PhishLabs Pricing - revised Jan 2024.xlsx | PhishLabs (digital risk protection) | rev Jan 2024 | xlsx | **ENCRYPTED** |
| 25 | Powertech 2024 - revised 7.12.24.xlsx | Powertech (IBM i security) | 2024, rev 7.12.24 | xlsx | **ENCRYPTED** |
| 26 | Robot Pricing 2024 - revised 7.19.24 .xlsx | Robot (IBM i automation/monitoring) | 2024, rev 7.19.24 | xlsx | **ENCRYPTED** |
| 27 | SafeStone  2024 - revised 7.12.24.xlsx | SafeStone (IBM i access control) | 2024, rev 7.12.24 | xlsx | **ENCRYPTED** |
| 28 | Skybot Pricing 2023 - revised 3.27.23.xlsx | Skybot (job scheduling) | 2023, rev 3.27.23 | xlsx | **ENCRYPTED** |
| 29 | Tango 2023 - revised 07.21.23.xlsx | Tango (Tango/04 — IBM i monitoring) | 2023, rev 07.21.23 | xlsx | **ENCRYPTED** |
| 30 | Terranova Pricing 2024_Sept 2024.xlsx | Terranova Security (security awareness training) | 2024, Sept 2024 | xlsx | **ENCRYPTED** |
| 31 | Tripwire AMER  LatAm Pricing - Effective 4.1.2024.xlsx | Tripwire — AMER / LatAm region | Effective 4.1.2024 | xlsx | **ENCRYPTED** |
| 32 | Tripwire APAC Pricing - Effective 4.1.2024.xlsx | Tripwire — APAC region | Effective 4.1.2024 | xlsx | **ENCRYPTED** |
| 33 | Tripwire EMEA Pricing - Effective 4.1.2024.xlsx | Tripwire — EMEA region | Effective 4.1.2024 | xlsx | **ENCRYPTED** |
| 34 | Tripwire_ KK Pricing ALL_Effective 4.1.2024.xlsx | Tripwire Japan (TWKK) — prior locked version of file #13 | Effective 4.1.2024 | xlsx | **ENCRYPTED** |

**Totals:** 34 files = **31 xlsx + 3 PDF**. Readable: **4** (3 PDF + 1 xlsx). Encrypted/blocked: **30** (all xlsx). Note the wording in the original task brief ("only PDFs are readable; ~30 xlsx encrypted") is essentially correct in count but **understates one item**: the 2025 TWKK draft xlsx (#13) is un-locked and fully readable, whereas its 4.1.2024 sibling (#34) is locked.

### 1.1 Observations on the inventory

- **Regional Tripwire split:** Tripwire is broken out by region — AMER/LatAm, APAC, EMEA, and Japan (KK) — all "Effective 4.1.2024" except the readable Japan draft which is "Effective 1.1.2025." This regional fragmentation is the legacy basis for RCA **regional pricing** mechanics (cf. `Services_Regional_Pricing__mdt`, Italy/region multipliers in the design KB).
- **Brand ↔ Practice mapping:** The brands map to Fortra "Practices" / product families (IBM i: Powertech, Robot, Bytware, CCSS, Halcyon, SafeStone, Skybot, Tango, Capacity Mgmt; Offensive: Cobalt Strike, Outflank; Threat/MDR: Alert Logic, DDI/Frontline, Beyond Security; Email/DLP: Clearswift, Agari, PhishLabs, Terranova; MFT: GoAnywhere/MFT/FileCatalyst; Integrity: Tripwire; Automation: AutoMate, JAMS).
- **"locked" in filename** (Bytware, CCSS, Halcyon) explicitly signals workbook protection — consistent with the encrypted-extraction result.
- Several files have **duplicated/overlapping scope** (e.g. `MFT Pricing 2024` xlsx vs the GoAnywhere PDFs; `Copy of KK …2025 DRAFT 2` vs `Tripwire_ KK …4.1.2024`). De-duplication will be needed before loading to RCA.

---

## 2. GoAnywhere 2025 Price Sheet — Structure (READABLE)

Two currency variants, both **Revised December 2024**, effective 2025:
- [GoAnywhere Pricing Sheet - USD - 2025.pdf](Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/GoAnywhere Pricing Sheet - USD - 2025.pdf) — header notes "**EUR for Europe, USD for the United States and other countries**" (i.e. the same numeric sheet is used for both USD and EUR markets).
- [GoAnywhere Pricing Sheet - AUD - 2025.pdf](Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/GoAnywhere Pricing Sheet - AUD - 2025.pdf) — Australian Dollars.

### 2.1 Two price columns per item: Subscription vs Perpetual

Every product/module line carries **two prices**:
- **Subscription** (the default — see Notes: *"All new license quotes must be presented as a subscription license"*).
- **Perpetual (Requires GM Approval to sell)** — perpetual requires General Manager sign-off with justification.

This is the legacy expression of the RCA `ProductSellingModel` choice (term-defined subscription vs one-time/perpetual) and the GM-approval gate is a candidate Quote approval rule.

### 2.2 MFT Bundles (with discount % baked into the bundle)

| Bundle | Discount | USD Subscription | USD Perpetual | AUD Subscription | AUD Perpetual |
|---|---|---|---|---|---|
| Starter Bundle | 15% | 17,064 | 35,679 | 23,890 | 49,950 |
| Starter + Gateway (incl. Load Balancer) | 15% | 20,337 | 42,521 | 28,472 | 59,530 |
| Starter + Gateway & Threat Protection* | 15% | 26,410 | 53,420 | 37,888 | 76,450 |
| Core Server Bundle | 10% | 6,683 | 13,973 | 9,357 | 19,562 |
| Core Server + Gateway | 10% | 10,148 | 21,218 | 14,208 | 29,705 |
| Core Server + Gateway & Threat Protection* | 10% | 16,692 | 32,998 | 24,334 | 47,951 |
| Collaboration Bundle | 18% | 7,607 | 15,905 | 10,650 | 22,266 |
| Collaboration + Gateway | 18% | 10,764 | 22,506 | 15,070 | 31,508 |
| Collaboration + Gateway & Threat Protection* | 18% | 17,196 | 34,207 | 24,958 | 49,496 |
| PeSIT Express Bundle | 10% | 17,078 | 35,708 | 23,910 | 49,991 |
| PeSIT Express + Gateway | 10% | 20,543 | 42,953 | 28,761 | 60,134 |
| PeSIT Starter Bundle | 20% | 30,800 | 64,400 | 43,120 | 90,160 |
| PeSIT Starter + Gateway | 20% | 33,830 | 70,840 | 47,362 | 99,176 |
| Premium Bundle | 15% | 43,158 | 76,702 | 60,421 | 107,382 |
| Premium + Threat Protection | 15% | 44,001 | 84,203 | 62,584 | 119,545 |
| Enterprise Bundle | 28% | 121,141 | 253,293 | 169,598 | 354,610 |
| PeSIT Premium Bundle | 15% | 51,558 | 107,718 | 72,182 | 150,805 |

`*Threat Protection includes Clearswift ICAP Gateway with AV and structural sanitization.`

Bundle contents are enumerated under each (e.g. Enterprise Bundle = Advanced Workflows, SFTP/FTPS Server, Secure Folders, Gateway, Secure Forms, Security Domains (10), GoDrive (Unlimited), Secure Mail (Unlimited), FileCatalyst Acceleration Module, Cloud Connectors, 500 Standard Agents, 5 Advanced Agents, Clearswift Advanced Bundle, BAM Enterprise w/ SSP).

### 2.3 À-la-carte modules (USD Subscription / Perpetual)

| Module | Sub | Perp |
|---|---|---|
| Advanced Workflow (incl. Adv. Reporting) | 12,650 | 26,450 |
| Workflows Basic (5 partners) | 5,000 | 10,455 |
| Workflows Restricted (PGP or SFTP Client) | 6,875 | 14,375 |
| Workflows Express (10 partners) | 9,350 | 19,550 |
| SFTP Server | 1,925 | 4,025 |
| FTPS Server | 1,925 | 4,025 |
| Secure Folders (HTTPS) | 3,575 | 7,475 |
| Gateway (incl. Load Balancer) | 3,850 | 8,050 |
| Load Balancer (existing licenses only) | N/A | 1,208 |
| Secure Forms | 4,015 | 8,395 |
| Additional Security Domain | 1,925 | 4,025 |
| Cloud Connector – Standard | 1,650 | 3,450 |
| Cloud Connector – Premium | 2,475 | 5,175 |
| Standard Cloud Connector 3 Pack | 3,850 | 8,050 |
| Advanced Reporting | 1,760 | 3,680 |
| PeSIT Client | 3,575 | 7,475 |
| PeSIT Server (5 / 10 / 20 / Unlimited Trading Partners) | 3,575 / 6,600 / 11,000 / 20,350 | 7,475 / 13,800 / 23,000 / 42,550 |
| BAM Enterprise | 6,875 | 12,500 |
| BAM SSP | 3,575 | 6,500 |

(Cloud Connector targets: Salesforce, Dynamics 365, Atlassian Jira, Zendesk, Veeva CRM, SharePoint Online.)

### 2.4 Tier-based licensing (USD; tier-upgrade rules apply)

**Agents** (licensed by tier — to add agents you upgrade to the next tier):

| License Count | Sub | Perp |
|---|---|---|
| 1 Standard Agent (incl. w/ Advanced Workflows) | No Charge | No Charge |
| 5 / 10 / 25 / 50 / 100 Std Agents | 1,899 / 3,304 / 6,607 / 12,388 / 14,865 | 3,970 / 6,907 / 13,814 / 25,901 / 31,081 |
| 250 / 500 / 750 / 1000 Std Agents | 17,343 / 20,646 / 24,775 / 28,904 | 36,262 / 43,169 / 51,802 / 60,436 |
| 2000 / 3000 / 4000 / 5000 Std Agents | 33,033 / 37,163 / 41,292 / 45,421 | 69,069 / 77,703 / 86,336 / 94,970 |
| > 5,000 Agents | Custom Pricing | Custom Pricing |
| Advanced Agents (incl. SFTP, SCP, FTPS, execute SSH, Web Services REST/SOAP) | 4,130 | 8,634 |

> Note: an additional MFT node is required for every 1000 Agents licensed.

**GoDrive** and **Secure Mail** (both: 5-user starter pack = No Charge; tiered to 30/100/250/500/1,000/2,000/3,500/5,000 users; > 5,000 = Custom):

| License Count | GoDrive Sub | GoDrive Perp | Secure Mail Sub | Secure Mail Perp |
|---|---|---|---|---|
| 30 users | 2,852 | 5,962 | 2,852 | 5,962 |
| 100 users | 4,275 | 8,938 | 4,275 | 8,938 |
| 250 users | 6,650 | 13,905 | 6,650 | 13,905 |
| 500 users | 9,022 | 18,862 | 9,022 | 18,862 |
| 1,000 users | 11,397 | 23,829 | 11,397 | 23,829 |
| 2,000 users | 14,248 | 29,790 | 14,248 | 29,790 |
| 3,500 users | 18,994 | 39,715 | 18,994 | 39,715 |
| 5,000 users | 23,745 | 49,648 | 23,745 | 49,648 |

**AS2/AS3/AS4** (USD, by trading-partner tier): 1 partner 2,640/5,520; up to 5 = 4,290/8,970; up to 10 = 7,700/16,100; Unlimited = 13,200/27,600. AS2/3/4 are licensed separately; bundles include a single 5-partner license that cannot be split across the 3 types.

### 2.5 Clearswift ICAP Gateway for MFT (USD Sub / Perp)

| Package | Sub | Perp |
|---|---|---|
| ICAP Gateway including AV | 5,720 | 10,400 |
| Essential (ICAP + AV + structural sanitization) | 7,336 | 13,338 |
| Advanced (+ document sanitization) | 8,752 | 15,912 |
| Elite (+ data redaction + OCR) | 10,697 | 19,488 |
| Optional: Additional AV (Avira or Sophos) | 1,040 | N/A |
| Optional: OCR (incl. with Elite) | 1,645 | 2,990 |

### 2.6 MFTaaS / ICAPaaS Hosting Fees (annual recurring)

USD example — **Region 1 (U.S., Canada, APAC, Europe, Middle East)** vs **Region 2 (Latin America)**:

| MFTaaS Tier | EFS Storage | Bandwidth | Region 1 / yr | Region 2 / yr |
|---|---|---|---|---|
| Tier 1 (Single Node MFT) | 50 GB | 250 GB | 5,550 | 6,550 |
| Tier 2 (Clustered MFT) | 500 GB | 500 GB | 14,000 | 17,500 |
| Tier 3 (Clustered MFT) | 1 TB | 1 TB | 20,800 | 27,300 |
| Add'l 500 GB Bandwidth | — | — | 750 | 750 |
| Add'l 500 GB Storage | — | — | 2,600 | 2,600 |

| ICAPaaS Tier | Region 1 / yr | Region 2 / yr |
|---|---|---|
| Tier 1 (Single Node ICAP) | 4,000 | 4,800 |
| Tier 2 (Clustered ICAP) | 6,000 | 7,200 |
| Tier 3 (Clustered ICAP) | 11,000 | 13,200 |

### 2.7 FileCatalyst, Advanced Workflows editions, Services

- **FileCatalyst** lines (Workflow, Direct 100Mbps→10Gbps servers, Add-ons, Central w/ Map View 5→200 nodes, Short-Term Pricing) all carry Sub/Perp columns. FileCatalyst Direct servers include 10 concurrent connections; Workflow single-server is unlimited users.
- **Advanced Workflows editions** form a Good/Better/Best feature matrix: **Restricted / Basic / Express / Advanced Workflows**, differentiated mainly by partner count (Restricted Unlimited but feature-limited; Basic = 5 partners; Express = 10; Advanced = Unlimited + Advanced Reporting) and SFTP/SCP/FTPS + OpenPGP availability. This is a textbook **attribute/edition-based** configuration that RCA `ProductConfigurationRule` / attribute-based pricing must reproduce.
- **Training & Professional Services** priced (USD): Fundamentals Cert 2,250; Automation Associate 3,500; Admin Associate 4,750; Expert 9,000; e-Learning variants; QuickStart Services 3,000–22,000; Expert Services (managed hours) Basic 12,000 / Standard 24,000 / Enterprise 55,000; consulting hourly T&M 275, pre-paid 250, after-hours emergency 375.

### 2.8 Reusable GoAnywhere pricing **rules** (Notes — directly relevant to RCA approval/pricing logic)

- New customers must purchase **≥ 5k in annual recurring** software/fees; existing customers expected to be increased up to 5k.
- All new quotes must be **subscription**; perpetual requires **GM approval** with justification.
- **Virtualized/partitioned systems:** each VM/partition needs a separate license.
- **Non-Production** (Dev/Test/Passive Backup) instances: **license fee = 50% of list price; maintenance = 20% of that net price.** *(This 50%-of-list Non-Production rule is the legacy analog of the RCA Non-Production net-price defect family — cf. SC-3360 missing AttributeBasedAdjustment on the AA Non-Production SKU in the design/Apex KB.)*
- First license for a new customer must be **Production** (cannot be Non-Production).
- **Maintenance** = initially **20% of List or Net Price**; thereafter may increase per Finance.
- Clustering (active-active): no built-in node discounts; adding a module to a cluster requires the module license for every node.
- Service/training rates: training & config 275/hr (credits expire 90 days); service hours expire 12 months; onsite 2,500/day (expire 12 months); emergency phone (after-hours) 375/hr.

---

## 3. Alert Logic Global Price List — Structure (READABLE)

Source: [Alert Logic_ global-price-list-ds-r1-am.pdf](Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/Alert Logic_ global-price-list-ds-r1-am.pdf). **Effective 4/25/2023.** Datasheet id `al-ds-1124-r1-am`. Currency **USD**. Pricing model: **Monthly Recurring Fees (MRF)**, sold in **tier bundles by node count**; standard pricing = 1-year term with annual payments.

### 3.1 MDR Essentials — Asset & Vulnerability Visibility with Endpoint Detection (by Max Nodes)

| Max Nodes | Set-up Fee | Recurring Monthly Price |
|---|---|---|
| 25 | None | (base) |
| 50 | None | $150 |
| 100 | None | $225 |
| 150 | None | $350 |
| 250 | None | $450 |
| 251+ | None | $550 |
| (per-node over) | — | $2.20 |

### 3.2 MDR Professional (by Max Nodes)

Includes 100 MB/Day/Node of log data analysis & storage; 1-year log retention.

| Max Nodes | Set-up Fee | Recurring Monthly Price |
|---|---|---|
| 25 | (see below) | — |
| 50 | — | $2,400 |
| 100 | — | $4,000 |
| 150 | — | $6,000 |
| 250 | — | $7,500 |
| 500 | $3,000 | $9,000 |
| 750 | — | $11,500 |
| 1000 | — | $13,900 |
| (cap) | — | $16,000 |
| PRICE/node over 1000 | — | $7.00 |

> For > 1,000 nodes: price = 1,000-node cost + per-node price, priced in **250-node bundles**.

### 3.3 MDR Enterprise

Professional + designated security expert (continuous threat hunting, proactive tuning, weekly review): **Set-up Fee None; Recurring Monthly $4,500.**

### 3.4 Fortra Managed WAF / Web Security Manager (WSM) Premier (MRF, USD)

| Managed WAF License(s) | Recurring Monthly |
|---|---|
| First WAF License | $450 |
| Additional WAF Licenses | $250 |
| Each Website Security Profile License | $400 |

| WSM Premier Product | Set-Up Fee | Recurring Monthly |
|---|---|---|
| Web Security Manager Premier — 1st Deployment (incl. 5 Websites) | $5,400 | $4,320 |
| WSM Premier — Additional Deployment (incl. 5 Websites) | $4,100 | $3,250 |
| Additional 5 Websites for a WSM Premier Deployment | $750 | $625 |

### 3.5 MDR Professional Add-Ons

**Incremental log data analysis storage** (per day per account; for data exceeding 100MB/day/host):

| Incremental Data | Set-Up Fee | Recurring Monthly |
|---|---|---|
| 1 GB | None | $500 |
| 5 GB | None | $1,000 |
| 10 GB | None | $1,400 |
| 25 GB | None | $2,000 |
| 50 GB | None | $3,000 |

**Additional log retention** (priced as % of Professional price):

| Total Retention Period | Recurring Monthly |
|---|---|
| 2 Years | 5% of Professional Price |
| 3 Years | 10% |
| 4 Years | 15% |
| 5 Years | 20% |
| 6 Years | 25% |
| 7 Years | 30% |

### 3.6 MDR Threat Manager Professional (by node/Mbps tiers)

Tiered recurring monthly (Set-Up Fee None all tiers): $610, $990, $1,350, $1,520, $2,410, $2,930, $4,145, $5,640, $7,520, $8,930, $11,280, $13,380, $16,000 (ascending node tiers).

High-throughput tier (Max Nodes / Max Mbps):

| Max Nodes | Max Mbps | Recurring Monthly |
|---|---|---|
| 1,250 | 5,000 | $7,500 |
| 2,000 | 7,500 | $10,000 |
| 3,000 | 10,000 | $12,000 |
| 7,000 | 20,000 | $20,500 |
| > 7,000 | > 20,000 | Custom Pricing |

**RCA relevance:** Alert Logic is a pure **monthly-recurring, node-tiered, set-up-fee + usage-overage** model — i.e. a recurring `ProductSellingModel` with **attribute-/quantity-based tiered pricing** plus **one-time set-up fees** and **percentage-of-base add-ons** (retention %). The "MDR Threat Manager Professional quote may be a single or multiple SKUs" note implies legacy multi-SKU bundling that maps to RCA bundle/component products.

---

## 4. Tripwire Japan (TWKK) Pricebook — Structure (READABLE — only un-locked XLSX)

Source: [Copy of KK Pricing ALL_Effective 1.1.2025 - DRAFT 2.xlsx](Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/Copy of KK Pricing ALL_Effective 1.1.2025 - DRAFT 2.xlsx). **Effective 1.1.2025, DRAFT 2.** Currency **JPY (¥)**. Bilingual Japanese/English. This is the only price spreadsheet that extracted — its 4.1.2024 sibling (`Tripwire_ KK Pricing ALL_Effective 4.1.2024.xlsx`, #34) is encrypted.

### 4.1 Workbook structure (11 sheets)

| Sheet | Rows × Cols | Content |
|---|---|---|
| Tripwire Enterprise | 181 × 9 | TE perpetual: Console + node/agent SKUs (File Systems, Desktops, Network Devices, VMware ESX, POS Servers, POS End Point, Directory Services, Databases, MS Exchange, MS IIS) |
| FIM | 156 × 9 | File Integrity Manager perpetual SKUs (same node taxonomy) |
| Policy Manager | 156 × 9 | Tripwire Policy Manager perpetual SKUs |
| TE Subscription JA | 122 × 11 | TE subscription SKUs (`-031` license / `-033` renewal) |
| FIM Subscription JA | 106 × 9 | FIM subscription SKUs |
| PM Subscription JA | 105 × 9 | Policy Manager subscription SKUs |
| IP360 | 174 × 250 | IP360 vuln-mgmt + VnE Manager + Device Profiler (license, support, subscription, appliance) |
| PS | 2 × 7 | Professional Services |
| Training | 10 × 7 | Training / e-Learning SKUs |
| NOTE_TE | 30 × 6 | Japanese pricing rules / notes (TE/FIM/PM) |
| NOTE_IP360 | 23 × 6 | Japanese pricing rules / notes (IP360) |

### 4.2 Column model (the discount-tier ladder)

Most sheets share columns:
`製品番号 SKU | 数量 Qty | 製品名 Description | 定価 TWKK List Price (External – Distributor list price) | 50% Discount from List (Distributor Buy Price) | 55% Discount from List | 60% Discount from List | 65% of Distributor Buy Price (target based upon 2013 results) | Yen Transfer Price`

- **IP360** sheet uses a different ladder: **40% / 45% / 50% / 60% discount from list**, plus **65% of Distributor Buy Price** and **Yen Transfer Price** (9 columns logically, despite 250 stored columns).
- **PS / Training** sheets use a shorter ladder: List → **20% Discount** → 65% of Distributor Buy → Yen Transfer Price.

This **distributor list → tiered buy-price → transfer price** model is the legacy partner/distributor pricing structure (cf. **doc 06 — Channel Partner Onboarding** and the partner-discount RCA work, e.g. SC-3359 partner pricing net not applied).

### 4.3 SKU scheme (load-bearing for migration)

SKUs are `NNNNNN-SS-JA` where the **suffix encodes the line type** (the `-JA` denotes Japan):

| Suffix | Meaning |
|---|---|
| `-00` | Perpetual License |
| `-01` | Basic Support (first-year maintenance) |
| `-03` | Basic Support Renewal |
| `-031` | Subscription License (first term) |
| `-033` | Subscription License – Renewal Term |
| `-061` | Annual License / Appliance Subscription (IP360 / VnE / Device Profiler) |
| `-063` | Annual License / Appliance Subscription – Renewal Term |
| `-90` | Services / Training (PS, Training sheets) |

Example console SKUs: `172000-00-JA` TE Console License ¥1,712,368; `172000-031-JA` TE Console **Subscription** License ¥1,213,800; `172000-033-JA` Subscription Renewal ¥1,170,450.

### 4.4 Quantity-tier breaks (per-node volume pricing)

Node products price by **Qty band**. Standard TE/FIM/PM bands: **1-100 / 101-250 / 251-500 / 501-1000 / 1001+**. IP360 uses finer bands: **1-250 / 251-500 / 501-1000 / 1001-2500 / 2501-5000 / 5001-10000 / 10001-25000 / 25001+**. Device Profiler Express variants use **1-5 / 6-10 / 11-25 / 26-50 / 51-100 / 101-250 / 251-500 / 500+**. Per the notes, the qty unit price applies to the per-order quantity for the end user.

Example (TE for File Systems, perpetual `172110-00-JA`, JPY List → 50% buy → … → Yen Transfer):
1-100: 220,528 → 110,264 → 99,238 → 88,211 → 71,672 → **¥72,000**; 1001+: 78,624 → 39,312 → … → 25,553 → **¥26,000**.

Appliance/capacity-limited SKUs encode the IP cap in the description, e.g. `500226-00-JA` VnE Manager Ev Limited – *Limited to 10,000 IPs*; `500232-00-JA` Ev Express – *Limited to 2,500 IPs*; `502370-061` *100 IPs*, `502371` *50 IPs*, `502372` *10 IPs*; Device Profiler Express-25 / Express-50 limited to 25 / 50 IPs.

### 4.5 Tripwire JA pricing **rules** (NOTE_TE / NOTE_IP360 — translated highlights)

- Per-quantity unit prices apply to the **per-order** quantity delivered to the end user.
- Support/maintenance renewals should be done **by the existing maintenance end date**; bundle maintenance must now be renewed per-product (enabling per-product continue/add/move/delete).
- **Monthly maintenance** = annual ÷ 12; rounded per unit price (round half-up for maintenance, **round down (truncate)** for fractional totals).
- **Redundancy / HA:** clustering supports **cold-standby only → requires 2 licenses**; install on an FT server needs only 1 license (consult sales beforehand).
- **TE/FS (1-16 CPU):** one license = software on one server with one OS and ≤16 CPUs; multiple OSes on one machine require a license per OS.
- Prices **exclude consumption tax**.
- Maintenance renewals are **annual** (penalty-rate renewals annual only; no monthly).
- **Maintenance reinstatement (lapsed) fee** applies to the whole renewal period; **max reinstatement fee = 25%.**
- **Maximum purchasable maintenance/subscription term (incl. remaining period) = 5 years**; subscriptions also capped at 5 years (escalate > 5-year deals before booking).
- License purchase **requires concurrent first-year Basic Support**; use **Basic Renewal Support** SKU at renewal.
- **Support rename:** "Enterprise Support" → **"Basic Support"** (IP360 note).
- **TFS (Tripwire for Servers?) is end-of-sale** — **maintenance renewal only.**
- New-purchase maintenance **starts the month after order**; orders placed **on/after the 15th** start the **month-after-next** (e.g. order 1/15 → maintenance starts Feb; order 1/16 → starts Mar).
- Distributor split-price columns were removed from each sheet (list-only display); distributor rates still apply per each distribution contract.
- The "65% of Distributor Buy Price" column is annotated **"target based upon 2013 results"** — i.e. a legacy internal margin target, not a customer price.

**RCA relevance:** the JA pricebook is a concrete, multi-band, multi-line-type (license/support/renewal/subscription/appliance) JPY catalog — directly exercising RCA **multi-currency** (JPY rendering issues are flagged in SC-3384), **subscription term caps (5-yr)**, **maintenance-as-% rollups**, **reinstatement fees**, **bundle-to-per-product maintenance**, and **quantity-tier (volume) pricing**. The `-00/-01/-03/-031/-033/-061/-063` SKU-suffix convention is a candidate mapping for RCA line-type / selling-model classification during migration.

---

## 5. Open Questions / Action Items

1. **PASSWORD GAP (blocker):** 30 of 34 files are password-protected and cannot be extracted. **Action:** obtain the workbook password(s) from the Fortra pricing/finance/RevOps owners (likely a single shared password given the consistent "locked" pattern), then re-run extraction so the per-brand SKU/price/UOM catalogs (Powertech, Robot, Clearswift, Beyond Security, DDI, Agari, PhishLabs, Cobalt Strike, Terranova, AutoMate, JAMS, and the regional Tripwire AMER/APAC/EMEA sheets) can seed/reconcile the RCA catalog. Until then, these brands' SKU-level legacy pricing is **unknown** from this source set.
2. **Currency coverage / FX:** GoAnywhere ships USD(=EUR), AUD; TWKK is JPY; Alert Logic is USD-only. The other (encrypted) brands' currency coverage is unknown. How does this reconcile with RCA's currency model and the SC-3384 multi-currency defect (non-USD using USD values)? Are there per-brand EUR/GBP/CAD sheets hidden inside the locked workbooks?
3. **De-duplication:** `MFT Pricing 2024 - revised 4-3-24.xlsx` (encrypted) vs the GoAnywhere PDFs; `Copy of KK …2025 DRAFT 2` (readable) vs `Tripwire_ KK …4.1.2024` (encrypted) — which is authoritative for migration? The 2025 KK draft supersedes the 4.1.2024 one but is marked **DRAFT 2** (not final).
4. **"DRAFT 2" status:** the only readable spreadsheet is explicitly a draft — confirm it is the version of record for any TWKK data load.
5. **Effective-date skew:** Tripwire regional sheets are "Effective 4.1.2024"; KK is "Effective 1.1.2025"; GoAnywhere "Revised Dec 2024 / 2025"; Alert Logic "4/25/2023." Pick a consistent as-of date for the migration snapshot.
6. **Bundle composition:** GoAnywhere bundle line-items are listed but **without per-component prices** (the bundle carries one discounted price). RCA bundle modeling (component products + bundle-level discount) will need the component-level allocation, which is not in these PDFs.
7. **SKU↔Product2 mapping:** the TWKK `-00/-01/-03/-031/-033/-061/-063` suffix taxonomy and GoAnywhere "Subscription vs Perpetual (GM approval)" columns must be reconciled with RCA `ProductSellingModel` and the consolidated SKU strategy in **doc 10**. No explicit legacy-SKU → new-tier crosswalk is present in these raw files.

---

## Sources

**Readable (text fully extracted / vision-confirmed):**
- [GoAnywhere Pricing Sheet - USD - 2025.pdf](Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/GoAnywhere Pricing Sheet - USD - 2025.pdf)
- [GoAnywhere Pricing Sheet - AUD - 2025.pdf](Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/GoAnywhere Pricing Sheet - AUD - 2025.pdf)
- [Alert Logic_ global-price-list-ds-r1-am.pdf](Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/Alert Logic_ global-price-list-ds-r1-am.pdf)
- [Copy of KK Pricing ALL_Effective 1.1.2025 - DRAFT 2.xlsx](Fortra Discovery Documentation/Pricing and Products/Pricebooks From SharePoint/Copy of KK Pricing ALL_Effective 1.1.2025 - DRAFT 2.xlsx)

**Encrypted / password-protected — could NOT be extracted (data gap; password required):**
- Agari Pricing 2024 - revised 6.21.2024.xlsx
- AutoMate Pricing 2024.xlsx
- Beyond Security Pricing _revised Oct 2022 (Federal Incl).xlsx
- Business Intelligence 2024 - revised 7.8.24.xlsx
- Bytware 2024 - revised 07.23.24 - locked.xlsx
- CCSS Pricing 2024 - revised 7.23.24 - locked.xlsx
- COS Pricing 2022.xlsx
- CTS 2023 - revised 03.27.23.xlsx
- Capacity Management 2023 - revised 03.27.23.xlsx
- Clearswift Pricing 2024 - revised 2.1.24.xlsx
- Cobalt Strike Pricing_May 2024.xlsx
- DDI Pricing 2024_July_Updated VM.xlsx
- Doc Mgt RJS 2024_24April.xlsx
- Halcyon 2024 - revised 07.19.24 - locked.xlsx
- IGA 2023 - revised 03.27.23.xlsx
- Intermapper 2023 - revised 03.27.23.xlsx
- JAMS MVP Pricing 2023 - Updated 06.20.xlsx
- MFT Pricing 2024 - revised 4-3-24.xlsx
- Outflank 11.30.22_OST&Cobalt Bundles added.xlsx
- PhishLabs Pricing - revised Jan 2024.xlsx
- Powertech 2024 - revised 7.12.24.xlsx
- Robot Pricing 2024 - revised 7.19.24 .xlsx
- SafeStone  2024 - revised 7.12.24.xlsx
- Skybot Pricing 2023 - revised 3.27.23.xlsx
- Tango 2023 - revised 07.21.23.xlsx
- Terranova Pricing 2024_Sept 2024.xlsx
- Tripwire AMER  LatAm Pricing - Effective 4.1.2024.xlsx
- Tripwire APAC Pricing - Effective 4.1.2024.xlsx
- Tripwire EMEA Pricing - Effective 4.1.2024.xlsx
- Tripwire_ KK Pricing ALL_Effective 4.1.2024.xlsx

**Related KB docs:** doc 10 (Pricing Strategy & Approval Matrices — the SKU-consolidation "why" and discount-approval thresholds), doc 06 (Channel Partner Onboarding — distributor/partner pricing context).
