# 09 — Pricing & Products: Product Catalog, Hierarchy & SKUs

> **Scope:** the raw product-catalog discovery exports that feed the Salesforce Revenue Cloud Advanced (RCA) Product2 / Pricebook build. Covers the **Cyber**, **Tech**, **Services**, and **Globalscape** SKU sets, the multi-level **product hierarchy** (Unit → Solution Group → Brand → Product Family → Software Product Family / SKU), the **GP Item Class** taxonomy that maps to RCA Product Type, **D365 tiered (asset/revenue/user-based) pricing**, and the legacy-to-revised SKU migration approach.
>
> **Complement, not duplicate:** the Confluence DESIGN synthesis lives in `FORTRA_KNOWLEDGE_BASE.md`. This doc is the **discovery input layer** — the actual catalog data lists Coastal/BSI must translate into RCA Product2, ProductCategory, ProductClassification, AttributeBasedAdjustment, and CalculationMatrix rows. Where a column maps cleanly to an RCA construct, that is flagged.
>
> **Out of scope here** (separate topic docs): Approval Matrix, Quoting Rules for D365, Globalscape Product & Pricing Fields, Pricebooks From SharePoint, `QuotingBillingImportantFields.xlsx`, and the `Cyber_Pricing Strategy ...pptx` deck.

---

## 1. The Three (Four) Catalog Sources & How They Relate

Fortra is consolidating three legacy CRMs onto Salesforce RCA. The catalog data arrives in distinct shapes per source system:

| Catalog file | Source system | Shape / key columns | Row scale (sheet) | What it is |
|---|---|---|---|---|
| `Cyber Products.xlsx` | D365 (Dynamics) | `Product SKU`, full hierarchy columns | Products sheet **8,874r × 23c** (extract shows ~401 distinct rows) | Cyber-side D365 product master + a Product Families pivot (704r) |
| `Tech Products.xlsx` | D365 (Dynamics) | identical 23-col layout to Cyber | Products sheet **9,441r × 23c** (~401 shown) | Tech-side (IBM i / infrastructure) D365 product master + Product Families pivot (788r) |
| `ServicesProductDescriptions.xlsx` | D365 + Salesforce CPQ | D365 sheet keyed by `productnumber`; Globalscape sheet keyed by SF `Id` | D365 **364r × 6c**, Globalscape **14r × 3c** | Long-form product **descriptions** (EN/ES) used for quote/document body text |
| `Tech_GlobalscapeSKUsfromSalesforce_BSS-22410...xlsx` | Globalscape Salesforce org | `Product Code`, `Product Family`, `SubCategory`, `List Price`, `Active`, `IsRenewalProduct` | **15,129r × 18c** (extract truncated at 400 rows) | Globalscape SF product export (report **BSS-22410**, generated 2025-06-04 by Jillian Jones) |
| `D365 SKU Tiered Pricing.xlsx` | D365 (PhishLabs) | `Sku`, `Tier Name`, `Min/Max Qty`, `Type`, `Base Price`, `Price Model`, `Multiplier` | PhishLabs sheet **268r × 10c** | PhishLabs asset/revenue/user-tiered pricing tables + formula |
| `Product Hierarchy/Services SKUs D365.xlsx` | D365 (Dynamics export) | `Product SKU`, `Product Brand`, `Solution Category`, `Product Type`, `GP Item Class`, `Status`, `List Price`, `Currency` | Products sheet **1,224r × 17c** (extract truncated at 400) + a `hiddenSheet` with picklist values | The **services** subset of the D365 product master, with full metadata + picklist legend |

> **Important extract caveat:** the `.xlsx → .txt` extraction caps at ~400 non-empty rows per sheet. The Cyber/Tech Products sheets self-report 8,874 / 9,441 rows but only ~401 were extracted; `Services SKUs D365` and `Globalscape` are likewise truncated ("`... [truncated at 400 non-empty rows; sheet has N rows]`"). **All counts below for the truncated sheets are based on the visible sample, not the full catalog.** Re-pull from the source `.xlsx` (or the live D365/SF) before treating any count as the universe.

---

## 2. The Product Hierarchy — Levels & Aliases

The **brief's canonical hierarchy** is: **Unit → Solution Group → Solution Category → Solution → Feature → SKU**. The discovery files express this with slightly different column names per source. Reconcile as follows:

| Canonical level | Cyber/Tech Products column | Services SKUs D365 column | Globalscape SF column | Notes |
|---|---|---|---|---|
| **Unit** | `Family Unit (Software Product Family) (Product)` | — | — | Top business unit. Cyber = **`CIA`**; Tech = **`CORE`**. (CIA = Cyber/Infrastructure/…, CORE = the IBM-i / systems-management heritage.) |
| **Solution Group** | `Solution Group Family (Software Product Family) (Product)` | (see Solution Category) | — | e.g. Infrastructure Protection, Automation, Data Protection |
| **Solution Category** | (rolled into Solution Group on Cyber/Tech) | `Solution Category` | `Product Family` | The Services D365 export and Globalscape use a flatter category column |
| **Brand / Solution** | `Product Brand Family (Software Product Family) (Product)` | `Product Brand` | (implicit in name/SubCategory) | e.g. Powertech, Robot, Digital Defense, GoAnywhere MFT |
| **Feature / Product Family** | `Product Family (Software Product Family) (Product)` → `Software Product Family` | — | `SubCategory` | the named feature group, e.g. "Automate Maintenance", "Core CTS Hardware" |
| **SKU** | `Product SKU` (+ `Product SKU (Software Product Family) (Product)` = the family's representative SKU, prefixed `F4...`) | `Product SKU` | `Product Code` | the orderable item |

### 2.1 Full column list — Cyber Products.xlsx / Tech Products.xlsx (23 columns, identical layout)

```
Product SKU | Name | Software Product Master | GP Item Class | Tax Code | Price |
Legacy Product? | Bundle? | Unit Label | Is Tiered Pricing | Experlogix Series |
Family Unit (Software Product Family) (Product) |
Solution Group Family (Software Product Family) (Product) |
Product Brand Family (Software Product Family) (Product) |
Product Family (Software Product Family) (Product) |
Software Product Family |
Product SKU (Software Product Family) (Product) |
In Bundles | Required With Items | Approval Discount Fraction |
Hardware | Regional Discounts | Term Length Discounts
```

Key column semantics:
- **`Software Product Master`** — the parent "model" the SKU belongs to (e.g. `DG NDLP Appliance 1500`). Often blank for maintenance/fee SKUs.
- **`Software Product Family`** (col 16) is the human-readable family; **`Product SKU (Software Product Family)`** (col 17) is its `F4...` code (e.g. `F4AUTOMMAINT`, `F4CTSHARDWARE`, `F4GOAMAINT`). This `F4`-prefixed code is the **family-level grouping key** and is the natural candidate for an RCA **ProductCategory / ProductClassification**.
- **`Approval Discount Fraction`** — uniformly **`0.25`** across nearly all rows (the standard max discount before approval). Ties to the Approval Matrix topic.
- **`Experlogix Series`** — the legacy D365 CPQ (Experlogix) configurator rule-set the SKU belonged to. Distinct values are pipe-combined sets of: `New Software`, `New Software No Rules`, `Subscriptions`, `Subscriptions No Rules`, `Professional Services`. These are **legacy configurator bindings** that RCA's ProductConfigurationRule / ProductRelationship will replace.
- **`Is Tiered Pricing`** — present (value `No`) on ~100 of the visible Cyber rows; blank otherwise. Real tiered pricing lives in the separate `D365 SKU Tiered Pricing.xlsx` and the Globalscape T1–T3 SKUs.
- **`Hardware`** — tags the hardware/appliance lineage: Cyber values `None`, `GoAnywhere`, `JAMS`, `Skybot`, `HADR50`, `BS`; Tech is dominated by **`HADR50`** (High Availability/Disaster Recovery 50% lineage) and `0`.
- **`Regional Discounts`** — `Yes` on ~101/401 visible Cyber rows (eligible for region multipliers; connects to the SC-3374 / regional-pricing mechanism documented elsewhere).
- **`Term Length Discounts`** — uniformly `No` in the visible sample.

### 2.2 GP Item Class → RCA Product Type (the load-bearing taxonomy)

`GP Item Class` is the **Great Plains (ERP) item class** and is the single most important field for RCA modeling because the `hiddenSheet` in `Services SKUs D365.xlsx` gives the **authoritative GP-class → Product-Type picklist mapping**:

**`hiddenSheet` Product Type picklist (D365):**
`Software | Subscription | New Maintenance | Renewal Maintenance | Services | Renewal Services | License Upgrade Fee | Other | Saas Subscription | (Not in use) Managed Security Services`

**`hiddenSheet` full GP Item Class value list:**
`CHANGE FEE | NEW MAINT | OTHER | RENEW MAIN | SERVICES | SOFTWARE | SUBS SAAS HOST | SUBS MSS | SUBS SAAS | SUBS SPLIT | SUBSCRIPT | UNISYS SUBS MAINT | UNISYS SW | MSPBULK | SERV EXP | SERV SUP | SERV RECUR`

**`hiddenSheet` Status picklist:** `Active | Retired | Draft | Under Revision`
**`hiddenSheet` Product Structure picklist:** `Product | Product Family | Product Bundle`
**`hiddenSheet` Legacy Product? picklist:** `No | Yes`

GP Item Class distribution (visible sample):

| GP Item Class | Cyber (of 401) | Tech (of 401) | Services SKUs (of ~400) | Meaning |
|---|---|---|---|---|
| `SERV RECUR` | 148 | 57 | 69 | Recurring services (monthly/annual analyst, resident engineer, TAM) |
| `SERV SUP` | 61 | 106 | 77 | Services - support / setup (QuickStart, setup fees) |
| `SERVICES` | — | 20 | 253 | Generic professional services (training, exams, hourly) |
| `OTHER` | 71 | 32 | — | Hardware, appliances, misc one-time |
| `NEW MAINT` | 48 | 49 | — | New maintenance |
| `RENEW MAIN` | 50 | 85 | — | Renewal maintenance |
| `SERV EXP` | 16 | 31 | — | Services - expenses (travel, billed-as-incurred) |
| `CHANGE FEE` | 5 | 19 | — | License upgrade / hardware-change fees ($0 most) |

> **RCA mapping note:** `NEW MAINT` vs `RENEW MAIN` is the new-vs-renewal split that RCA models via Subscription Management / Asset lifecycle, not via separate Product2 records ideally — but the legacy catalog carries **separate SKUs** for new and renew (e.g. `LN01900`/`LN01901` new vs `LN01902`/`LN01903` renew). The migration must decide whether to collapse these. Tax Codes (e.g. `SC100221` for NEW MAINT, `SC100122` for RENEW MAIN, `OT010100` for SERV EXP, `PC070200` for CTS hardware, `SC070321` for services) are GP tax codes that map to RCA TaxTreatment / Avalara codes.

---

## 3. Cyber Catalog (CIA Unit)

**Unit = `CIA`** for all Cyber products.

### 3.1 Solution Groups (visible distribution)

| Solution Group | Count (of 401) | Representative brands |
|---|---|---|
| Infrastructure Protection | 179 | Digital Defense, Core CTS, Cobalt Strike, Beyond Security, Core Impact, Frontline |
| Automation | 82 | Automate, Workload Automation (JAMS/Skybot) |
| Data Protection | 53 | Digital Guardian DLP, Data Classification (Titus/Boldon James) |
| Managed File Transfer | 41 | GoAnywhere, FileCatalyst |
| Email Security | 35 | Clearswift, Agari, MIMEsweeper |
| Security Awareness Training | 7 | Terranova |
| Other / Non-Specific | 4 | Fortra Maintenance, change fees |

### 3.2 Product Brand Families (visible distribution)

Digital Defense (106), Core CTS (66), Automate (50), Managed File Transfer / GoAnywhere (41), Workload Automation (32), Data Classification (29), Digital Guardian DLP (23), Clearswift (23), Agari (12), Cobalt Strike (5), Terranova (4), PhishLabs (3), Fortra (2), Beyond Security (2), Secure Collaboration (1).

### 3.3 Product Families (from the `Product Families` pivot, 704 rows)

The pivot is two-level: a **Product Family** header row with its `Count of Product`, then indented **member sub-families**. Notable families and the scale of SKUs inside them:

| Product Family | SKU count | Key sub-families / notes |
|---|---|---|
| **GoAnywhere MFT** | **2,697** | The single largest family — hundreds of platform/connector/agent SKUs (AS2/AS3/AS4 send-receive per platform & trading-partner count, Cloud Connectors Standard/Premium for AWS/Azure/Box/Dropbox/Jira/ServiceNow/etc., EDI X12 & EDIFACT, Gateways, Advanced Workflows/Reporting, Business Activity Monitor). Platform variants: IBM i / Linux / Windows / AIX-UNIX-HP-UX-Solaris. |
| Access/Endpoint DLP families | 95 | Clearswift Endpoint DLP (Data At Rest / In Use), ARC, TADP, Threat Aware |
| Data Classification Suite | 112 | DCS Essentials / Advanced / Plus / Cloud, DCS for Windows/OWA/SharePoint, Titus Accelerator, Fortra Mail for iOS |
| Cybersecurity Training | 91 | Security Awareness Training (75), Terranova Services (16) |
| Automate (RPA) | 179 | Automate BPA, Enterprise Agents, Plus, Ultimate, Starter Pack, Intelligent Capture (AIC) |
| Digital Defense Services | 87 | Analyst (Recurring), TEAM Services, Phishing/Internet Fraud Prevention, Wireless Pen Test |
| Core CTS Hardware | 54 | `CTS Hardware` appliances (Gen4 MC/Sensor, MicroSensor, Expansion Interfaces, Virtual MicroSensor) |
| Event Manager | 84 | Powertech Event Manager |
| FileCatalyst | 52 | Central, Direct, Workflow, Concurrent Connections, Reverse Proxy |
| Cloud Email Protection | 10 | Agari Phishing Defense, DREP Email Security Bundle |
| beSECURE / beSOURCE / beSTORM | 101 / 19 / 27 | Beyond Security scanning/fuzzing |

### 3.4 Representative Cyber SKUs

| SKU | Name | GP Class | Price (USD) | Brand | Family / `F4` code |
|---|---|---|---|---|---|
| `DG09016` | DG NDLP Appliance 1500 - Maintenance | NEW MAINT | 14,900 | Digital Guardian DLP | F4DGNDLPAPPLIANCE1500174 |
| `DC00900` | Titus Maintenance - New Maintenance | NEW MAINT | 16.5 | Data Classification | F4FORTRADCSSUITE232 |
| `LN08014` | GoAnywhere Premium Support+ | NEW MAINT | 10,000 | Managed File Transfer | F4GOASUPPORTPLUS |
| `CB00500` | Cobalt Strike Level 101 | OTHER | 600 | Cobalt Strike | F4COBALTSTRIKESERVICES |
| `CT03017` | MC Purchase (Gen4) | OTHER | 17,000 | Core CTS | F4CTSHARDWARE |
| `DD00570` | Senior Analyst (per hour) 1-8 Hrs - Recurring | SERV RECUR | 500 | Digital Defense | F4DDANALYSTRECURRING |
| `AM02000` | Maintenance Plus, AutoMate Professional (per License) | NEW MAINT | 300 | Automate | F4MAINTADDONSAUTOMPR |
| `HC00000` | Hardware Change Fee | CHANGE FEE | 0 | Fortra | F4TRAMAINT |

> Maintenance SKUs frequently carry a **fractional Price** (e.g. `LN01900` = `0.2`, `LN01901` = `0.24`, `DG07000` = `3.3`) — these are **percentage-of-license multipliers** (20% / 24% maint rate), not dollar amounts. The migration must distinguish "Price as %" maintenance SKUs from "Price as $" SKUs; the GP Class (`NEW MAINT`/`RENEW MAIN` with sub-1 price) is the signal.

---

## 4. Tech Catalog (CORE Unit)

**Unit = `CORE`** for all Tech products. This is the IBM i / systems-management / infrastructure heritage (Powertech, Robot, Halcyon, Sequel, etc.).

### 4.1 Solution Groups (visible distribution)

| Solution Group | Count (of 401) |
|---|---|
| Systems Management | 117 |
| Cybersecurity | 113 |
| Identity & Access Management | 41 |
| Capacity Management | 41 |
| Business Intelligence | 38 |
| Network Monitoring | 27 |
| Document Management | 22 |

### 4.2 Product Brand Families (visible distribution)

Powertech (85), Robot (48), Capacity Management/TeamQuest (41), Core IGA (32), Tango/Tango04 (29), InterMapper (27), Sequel (22), Doc Management (22), Halcyon (18), ShowCase (16), Fortra Security Services (15), Safestone (13), CCSS (12), Bytware (10), BoKS (9).

### 4.3 Tech-specific characteristics
- **`Hardware` column** is dominated by **`HADR50`** (214/401) — the High-Availability/Disaster-Recovery 50% pricing lineage characteristic of IBM-i products — and `0` (112) / `None` (73).
- **Tax codes** mirror Cyber (`SC100221` new maint, `SC100122` renew maint, `DC010500` change fee).
- Heavy use of **`- Cross`** SKU variants (e.g. `HC11900` Halcyon New Standard Maint - Cross) and **`- Gov` / `- GSA (via Partner)`** variants for government channels.

### 4.4 Product Families (from the `Product Families` pivot, 788 rows)

Two-level pivot, same shape as Cyber. Notable:

| Product Family | SKU count | Notes |
|---|---|---|
| **Access Assurance Suite** | **712** | Core IGA's massive family: Standard Core Connectors In-Product (124) & Standard Delivery (210), Non-Standard Core Connectors (323), Core Provisioning, Core Password, RoleCourier, SecureReset |
| Customer Suite | 40 | Per-customer bespoke suites (CGI, Costco, EVRY, Gannett, IFDS, Mizuno, NYK, Paragon) |
| Robot family group | ~600 (across Robot Monitor 54, Network 72, Schedule 48, Schedule Enterprise 60, Save/Space/Replay/Reports/Transform/Trapper/UPS 48 each, LPAR 24) | The Robot systems-mgmt suite — heavily licensed per-feature |
| DetectIT (modules) | ~450 | Compliance Center, Menu & App Program, Network Traffic Controller, Powerful User Passport, Risk & Compliance Monitor, Security Audit & Detection, User Profile Manager — 48 SKUs each |
| DeliverNow | 32 | Doc-management delivery (Fax, Email, FTP, HTML, SharePoint, iForms, Lotus Notes) |
| Advanced Job Scheduler / Audit Journal Manager / Authority Swapper / AnyDate / Disk Space Manager | 48 each | Classic IBM-i utilities |

### 4.5 Representative Tech SKUs

| SKU | Name | GP Class | Price | Brand | Solution Group |
|---|---|---|---|---|---|
| `IM05850` | Maintenance Plus L1 (1-200 Devices) | NEW MAINT | 250 | InterMapper | Network Monitoring |
| `BI01900` | SEQUEL New Standard Maintenance | NEW MAINT | 0 | Sequel | Business Intelligence |
| `PT01900` | PowerTech New Standard Maintenance | NEW MAINT | 0 | Powertech | Cybersecurity |
| `RB01900` | Robot New Standard Maintenance | NEW MAINT | 0 | Robot | Systems Management |
| `TQ01900` | TeamQuest New Std Maintenance | NEW MAINT | 0 | Capacity Management | Capacity Management |
| `IG01900` | IGA - New Standard Maintenance | NEW MAINT | 0 | Core IGA | Identity & Access Management |

> SKU prefix → brand convention (Tech): `IM`=InterMapper, `BI`=Business Intelligence (Sequel/ShowCase), `PT`/`PT1x`=Powertech (`PT1x` = "Cross"), `RB`=Robot, `SS`=Safestone, `TG`/`TN`=Tango (`TN`=IBM i, `TG`/`TN11`=Cross), `BW`=Bytware, `CC`=CCSS, `HC`/`HC11`=Halcyon, `TQ`/`TQG`=TeamQuest (`TQG`=GSA), `FT`=BoKS, `IG`=Core IGA, `MP`=MPG/Robot, `RJ`=RJS/Doc Mgmt. The numeric block encodes lifecycle: `xx1900`/`1901` = New Standard/Premium, `xx1902`/`1903` = Renew Standard/Premium, `xx2101` = License Upgrade Fee.

---

## 5. Services Catalog (`Services SKUs D365.xlsx`)

This is the **D365 services subset** with richer metadata than the Cyber/Tech masters: it carries `Product Brand`, `Solution Category`, `Product Type`, `Status`, `Product Structure`, `List Price` + `List Price (Base)`, and `Currency`.

### 5.1 Solution Categories (visible sample of ~400)

| Solution Category | Count | Solution Categories here use the NEW "Good/Better/Best" brand naming |
|---|---|---|
| Data Protection | 113 | Boldon James, Digital Guardian, Titus, Vera |
| GoAnywhere | 64 | Linoma (GoAnywhere) services |
| Hybrid | 53 | — |
| Robotic Process Automation | 44 | AutoMate (note: many **Retired**) |
| Power | 43 | Powertech/Robot/CCSS/Bytware/Halcyon services |
| Email Security | 43 | Clearswift, Agari |
| Offensive Security | 17 | Core CTS, Outflank |
| Human Risk Management | 14 | Terranova Security |
| Brand Protection | 6 | PhishLabs |
| Cloud Data Protection | 2 | DG SASE |

### 5.2 Product Brands (visible sample)

Linoma (64), AutoMate (44), Digital Guardian (39), Titus (36), Core IGA (35), Fortra Security Services (26), Boldon James (25), Agari (22), Clearswift (21), TeamQuest (17), Terranova Security (14), Core CTS (14), Vera (13), PhishLabs (6), CCSS (6), Bytware (6), Halcyon (5), Outflank (3), Cloud Data Protection (2), Core SCS (1).

### 5.3 Product Type & Status
- **Product Type**: `Services` (338) vs `Subscription` (61) — Subscription = recurring services such as TAM, Expert Service, Resident Engineer, Phishing/Spearphishing Simulations.
- **Status**: `Active` (338) vs `Retired` (61). **All 61 Retired rows in the visible sample are legacy AutoMate services** (e.g. `AM01905`–`AM01999`, marked `Product Structure` = `Product`, Description `NO LONGER USED`, `Legacy Product? = Yes`). These should **not** migrate as active Product2.
- **Currency**: `US Dollar` throughout the visible sample (relevant to the SC-3384 multi-currency issue documented elsewhere — the services catalog is USD-only at source).

### 5.4 Representative Services SKUs (with prices)

| SKU | Name | Brand | Type | GP Class | List Price (USD) |
|---|---|---|---|---|---|
| `DC00614` | DC - Boldon James - Enterprise - On Prem Setup | Boldon James | Services | SERV SUP | 148,000 |
| `DC00610` | DC - Boldon James - Business - On Prem Setup - DAC | Boldon James | Services | SERV SUP | 48,000 |
| `DG06014` | DG Setup - High | Digital Guardian | Services | SERV SUP | 125,000 |
| `DG06026` | Technical Account Manager - Dedicated | Digital Guardian | Subscription | SERV RECUR | 180,000 |
| `DG06061` | DG Expert Service Enterprise | Digital Guardian | Subscription | SERV RECUR | 70,000 |
| `DC00647` | DP - 12 Calendar Month Resident | Boldon James | Services | SERV RECUR | 360,000 |
| `DG06079` | SASE Integration Service Fee | Cloud Data Protection | Services | SERV SUP | 4,125 |
| `DG06024` | Professional Services Hourly Rate | Digital Guardian | Services | SERVICES | 250 |

### 5.5 Long-form descriptions (`ServicesProductDescriptions.xlsx`)

A **translation / description table**, NOT a price list. Two sheets:

**D365 sheet (364r × 6c):** columns `hs_producttranslationid | productid | Name | productnumber | Language | Content`. Each service SKU (`productnumber`) appears in **English (187)** and **Spanish (176)** rows. `Content` holds the full marketing/scope-of-services prose (used to populate quote line descriptions and SOW text). 187 distinct SKUs; prefix distribution: PT(90), LN(87), AM(52), JM(43), RB(24), FC(24), MP(12), PL(10), TN(8), RJ(6), CS(5), IM(2).

**Globalscape sheet (14r × 3c):** columns `Id | Name | SBQQ__RawMarkup__c`. Holds **13 Salesforce-CPQ (SBQQ__) HTML markup blocks** for Globalscape Professional Services: *PS Assessments, PS Cutovers, PS Healthcheck, PS Quickstart, PS Migration, PS Training, PS Upgrade, PS Terms, PS PrePaid Hours, PS Accelerators, PS Hourly TAM, PS EFT TAM Content, PS Arcus Quick Start.* The `SBQQ__RawMarkup__c` field name confirms Globalscape's legacy quoting ran on **Salesforce CPQ (Steelbrick)** — RCA replaces this, so the markup must be migrated into RCA's document/description mechanism (DataRaptor-driven Quote PDF body — see the DocGen Quote PDF pipeline memory).

> **RCA connection:** these EN/ES description bodies are exactly the content the template-bound DataRaptors inject into the Quote/Order PDF. Spanish coverage (~94% of EN) means localized quoting is a live requirement.

---

## 6. Globalscape SKU Set (`Tech_GlobalscapeSKUsfromSalesforce...xlsx`, report BSS-22410)

Export of the **Globalscape Salesforce org** product catalog (15,129 rows; only first 400 extracted). Columns: `Price Book Name | Product Family | SubCategory | Product Name | Product Code | Product Description | Product Model | Pricing Method | List Price | Term Discount Level | Term Discount Schedule | Default Quantity | Option Selection Method | Active | IsRenewalProduct`.

- **Pricing Method** = `List` throughout; **Option Selection Method** = `Click`; **Default Quantity** = `1`.
- Price Book seen in sample = **`Renewals Price Book`**; `Product Family` = **`Licenses`**.
- The catalog is **EFT (Enhanced File Transfer)**-centric (Globalscape's flagship MFT product).

### 6.1 Globalscape SKU naming convention (`Product Code`)

The modern Globalscape codes follow a structured grammar; the legacy ones are bare integers:

```
GS  EFT  -  EN  -  SX2  -  T1  -  NP
│   │       │     │       │      └─ Environment suffix
│   │       │     │       └─ Tier (T1 / T2 / T3)
│   │       │     └─ M&S term & support level (see below)
│   │       └─ Edition (EN=Enterprise, S=SMB)
│   └─ Product line (EFT)
└─ GS = Globalscape product prefix (modern); HS = bundle/host; SVC = service
```

| Token | Meaning |
|---|---|
| **Environment suffix** | `-N` = New/Production, `-NP` = Non-Prod, `-DV` = Dev, `-SB` = Standby |
| **Edition** | `S` = SMB, `EN`/`ENT` = Enterprise |
| **Tier** | `T1` / `T2` / `T3` (size tiers, ascending price) |
| **M&S term/support** | `SX1`/`SX2`/`SX3` = Standard M&S 1/2/3-year; `PX1`/`PX2`/`PX3` = 24×7 Premium M&S 1/2/3-year |
| **Upgrade markers** | `EFTU` (upgrade), `EFTUG` (upgrade from SMB), `BBF`/`BBS`/`BBH` = Buyback Full / SFTP / HTTPS |
| Legacy codes | bare integers (`593`, `766`, `1106`) or `EFT5+PGP+ARM-N` style — pre-SKU-standardization |

### 6.2 Representative Globalscape SKUs

| Product Code | Product Name | List Price (USD) | Active |
|---|---|---|---|
| `GSEFT-N-ENT` / `EFT-N-ENT` | EFT 7 / EFT 8 Enterprise | 27,354 | True |
| `GSEFT-N-S-T1` | EFT SMB Tier 1 | 1,307.20 | False |
| `GSEFT-N-E-T1` | EFT Enterprise Tier 1 | 24,716.66 | True |
| `GSEFT-EN-SX1-T1` | EFT Enterprise w/ 1-Yr M&S Tier 1 | 29,995 | True |
| `GSEFT-EN-PX3-T3` | EFT Enterprise w/ 3-Yr 24×7 M&S Tier 3 | 139,995 | False |
| `GSEFT-N-SSH` | EFT SFTP (SSH2) Module | 895 | True |
| `GSEFT-N-AS2` | EFT AS2 Module | 9,598.80 | True |
| `GSEFT-N-AWE` | EFT Advanced Workflow Engine Module | 8,394 | True |
| `GSDMZ-N-S` | DMZ Gateway 3 - Single Site | 6,594 | True |
| `HSEFT-N-CNM` | EFT 8 Continuum | 0 | True |

> Environment pricing pattern: `-NP` (Non-Prod) ≈ 50% of production list; `-DV` (Dev) ≈ 33% of production list. Standby (`-SB`) ≈ 50%. These ratios are encoded per-SKU as distinct Product Codes rather than as RCA price adjustments — a candidate for consolidation into RCA AttributeBasedAdjustment in the new model.

### 6.3 Globalscape SubCategory taxonomy (Sheet1, 7-col legend)

The export's `Sheet1` lists the SubCategory / classification vocabulary:
**SubCategories:** CuteFTP, EFT Bundles, EFT Continuum Servers, EFT Enterprise Bundles, EFT Enterprise Servers, EFT Express Bundles, EFT Express Servers, EFT Modules, EFT SMB Bundles, EFT SMB Servers, Enterprise Upgrades, Express Upgrades, Hours, M&S Mail Express Production, Mail Express, Mail Express Production, MIX, Professional Services, PSTools, SCC_ACT, Secure Drive, SMB Upgrades, WAFS, Web Transfer Client (WTC), Workspaces (WSM).
**Product-type tags:** Licenses, M&S, MIX, Other, ProfSvc, Subscriptions.

---

## 7. D365 Tiered (Attribute-Based) Pricing — `D365 SKU Tiered Pricing.xlsx`

A **PhishLabs-only** sheet (`PhishLabs`, 268r × 10c) defining tiered pricing where the unit basis is the **customer's asset value, annual revenue, or user/employee/incident count** — not quantity. Columns: `Sku | ProductID | Name | Tier Name | Min Qty | Max Qty | Type | Base Price | Price Model | Multiplier`.

- **`Type`** = `Financial` (price by **Assets**) | `Non-Financial` (price by **Revenue**) | `NULL` (price by **Users / Employees / Incidents**).
- **`Price Model`** = `Total Price` (flat tier price, multiplier 0) | `Calculated` (Base + basis×multiplier).
- **`Min Qty`/`Max Qty`** = the lower/upper bound of the tier on the chosen basis (e.g. assets `$10B–$50B` = `10000000000`–`49999999999`).

### 7.1 The pricing formula (verbatim from the sheet footer)

> **Financial & Non-Financial Institutions:** Indicate the company's total annual assets/revenue → multiply that total by the tier's `Multiplier` → add to `Base Price` = line-item total. **Example:** Domain Protection @ $51B assets × 0.0000001 = $5,100; $13,500 Base + $5,100 = **$18,600**. **Setup Fee = 10% of all line items** ($18,600 × 0.10 = $1,860).
>
> **User/Employee-based (NULL Type):** Indicate number of Users/Employees → multiply by `Multiplier` → add to `Base Price`. **Example:** Suspicious Email Analysis @ 18,500 users × 5.5 = $101,750; $33,050 Base + $101,750 = **$134,750**. Setup Fee = 10%.

### 7.2 PhishLabs product/SKU lines in the sheet

`PL0146` Counterfeit Intelligence · `PL0144` Credential Baiting · `PL0100`/`PL0145` Credential Theft (+ Intelligence) · `PL0109` Crimeware · `PL0125` Dark Web Brand Monitoring · `PL0149` Dark Web Compromised Credential Monitoring · `PL0102` Domain Protection · `PL0128` Email Threat Indicators · `PL0107` Mobile · `PL0129` MSOAR · `PL0104`/`PL0106` Open Web (+ Add'l Languages) · `PL0111`/`PL0113` Social Media - Cyber (+ Add'l Languages) · `PL0117` Social Media - Executive · `PL0119`/`PL0121` Social Media - Physical (+ Add'l Languages) · `PL0122`/`PL0124` Social Media - Reputational (+ Add'l Languages) · `PL0114`/`PL0116` Social Media - Source Code (+ Add'l Languages) · `PL0127` Suspicious Email Analysis · `PL0147` Suspicious Email Intelligence · `PL0143` Volvo - Suspicious Email Analysis (a **customer-specific** override SKU).

> **RCA mapping note:** this is precisely the pattern RCA models with **CalculationMatrix / AttributeBasedAdjustment** keyed on an order-attribute (annual revenue / assets / user count). The `Min/Max Qty` bands become matrix rows; `Base Price` + `Multiplier` become the formula. The asset/revenue tiers (`Less than $5B` … `Over $250B`) and the per-Type multiplier (Financial vs Non-Financial use **different multipliers for the same tier** — e.g. Crimeware $10B–$50B Financial multiplier `1e-07` vs Non-Financial `5e-07`) mean the matrix needs **Type** as a second key dimension. The 10% Setup Fee is a derived order-level line. This is directly relevant to the SC-3384 multi-currency findings (USD-only tiered data) and the "Tiered Pricing Product Requires Update Price Twice" SC-3390 ticket.

---

## 8. Legacy → Revised SKU Migration (`BSI_Coastal 07 14 2025 Next Steps.docx`)

Context for how this catalog data flows into RCA (BSI internal call 2025-07-14, follow-up with **Marc** 7/15):

- A **new pricing model** ("**Good Better Best**") is being introduced for some lines; **Data Protection** and **Human Risk Protection (Terranova)** were already done at this date.
- Process: **Map current (legacy D365) SKUs → new SKU SFDC format = "Revised SKUs."** Marc owns processing old SKUs into an old→revised SKU mapping; Fortra (Jordan, Mandy, Cassie, Michalea, Sales Ops) confirms.
- **Owners of SKU splitting:** Jordan, Mandy, Cassie (full list targeted EOD 7/15).
- **Brands "Done"** (ready to load, per spreadsheet column T): **Terranova, Agari, PhishLabs, Cloud DP, Offensive Security, Power, GoAnywhere, RPA.**
- Brand-name normalization table (Google-Sheet column T → Brand List): Cloud Data Protection→Cloud DP; Go Anywhere→GoAnywhere; Human Risk Management→Teranova; Offensive Security→Offensive Security; Power→Power; Robotic Process Automation→RPA. *(These are exactly the `Solution Category` values seen in `Services SKUs D365.xlsx`, confirming that file reflects the new revised taxonomy.)*
- Build loop: Marc's spreadsheet (last 3 tabs) → BSI translates to upload → Fortra reviews in-system (working session) → revise & repeat. Two Google Docs hold the Product Pricing Rules (links in the source doc; not retrievable here).

> **Implication:** the **`Services SKUs D365.xlsx`** file (with `Solution Category` = Power / GoAnywhere / RPA / Offensive Security / Human Risk Management) is the **post-revision** taxonomy, whereas **`Cyber Products.xlsx` / `Tech Products.xlsx`** (with `Solution Group Family` = Infrastructure Protection / Automation / Systems Management) reflect the **legacy D365** grouping. The two taxonomies coexist in the discovery set and must be reconciled during the RCA ProductCategory build.

---

## 9. Open Questions / Ambiguities

1. **Truncated extracts.** Cyber (8,874), Tech (9,441), Services (1,224), Globalscape (15,129) sheets were each cut to ~400 rows by the text extractor. The full SKU universe — and therefore any total count — must be re-pulled from the source `.xlsx` or live system. Counts in this doc are sample-based.
2. **New-vs-Renew SKU collapse.** Legacy carries separate SKUs for `NEW MAINT` vs `RENEW MAIN` (and `- Cross` / `- Gov` / `- GSA` channel variants). Does RCA collapse these into one Product2 + Subscription lifecycle, or preserve 1:1? The BSI doc implies a remap but doesn't state the rule.
3. **Maintenance "Price as %" vs "Price as $".** Many maint SKUs have sub-1 prices (0.2, 0.24, 3.3) that are percentage rates, not dollars. The migration needs an explicit flag; none exists in the columns (must be inferred from GP Class + price magnitude).
4. **Globalscape environment-variant SKUs** (`-NP`/`-DV`/`-SB`) encode price ratios (~50%/33%/50%) as distinct Product Codes. Keep as separate Product2 or model as RCA price adjustments? Unresolved.
5. **Globalscape was on Salesforce CPQ** (`SBQQ__RawMarkup__c`). The CPQ→RCA description-markup migration path is not specified in scope.
6. **PhishLabs tiered pricing currency.** The tiered sheet is implicitly USD; combined with the USD-only Services catalog this is the data substrate behind the SC-3384 non-USD-uses-USD-values defect. How are non-USD PhishLabs tiers priced? Not in these files.
7. **`Volvo - Suspicious Email Analysis` (PL0143)** is a customer-specific override SKU embedded in the standard tiered sheet. Are there other per-customer SKUs (the Tech "Customer Suite" — CGI/Costco/EVRY/Gannett/IFDS/Mizuno/NYK/Paragon) that need special RCA handling?
8. **`Experlogix Series`** (legacy D365 configurator rule-sets) → RCA ProductConfigurationRule mapping is unstated; this is the configuration-rule migration that SC-3137 / PCR work touches.
9. The two **Product Pricing Rules Google Docs** referenced in the BSI doc could not be retrieved (external links).

---

## Sources

Files read in full (extracted text under `Data/discovery-extract/text/Pricing and Products/`):

- [Cyber Products.xlsx](Fortra Discovery Documentation/Pricing and Products/Cyber Products.xlsx) — Products (8,874r×23c, ~401 extracted) + Product Families pivot (704r×2c)
- [Tech Products.xlsx](Fortra Discovery Documentation/Pricing and Products/Tech Products.xlsx) — Products (9,441r×23c, ~401 extracted) + Product Families pivot (788r×2c)
- [ServicesProductDescriptions.xlsx](Fortra Discovery Documentation/Pricing and Products/ServicesProductDescriptions.xlsx) — D365 EN/ES descriptions (364r×6c) + Globalscape SBQQ markup (14r×3c)
- [Tech_GlobalscapeSKUsfromSalesforce_BSS-22410-2025-06-04-10-45-55.xlsx](Fortra Discovery Documentation/Pricing and Products/Tech_GlobalscapeSKUsfromSalesforce_BSS-22410-2025-06-04-10-45-55.xlsx) — Globalscape SF export (15,129r×18c, 400 extracted) + Sheet1 SubCategory legend
- [D365 SKU Tiered Pricing.xlsx](Fortra Discovery Documentation/Pricing and Products/D365 SKU Tiered Pricing.xlsx) — PhishLabs tiered pricing (268r×10c, fully read)
- [Product Hierarchy/Services SKUs D365.xlsx](Fortra Discovery Documentation/Pricing and Products/Product Hierarchy/Services SKUs D365.xlsx) — Products with GP Class (1,224r×17c, 400 extracted) + hiddenSheet picklist legend (6r×17c)
- [BSI_Coastal 07 14 2025 Next Steps.docx](Fortra Discovery Documentation/Pricing and Products/BSI_Coastal 07 14 2025 Next Steps.docx) — migration context (legacy→revised SKU mapping, Good/Better/Best, brand readiness)

Explicitly **out of scope** (separate topic docs): `Cyber_Pricing Strategy_Project Summary as of 5.29.25.pptx`, `QuotingBillingImportantFields.xlsx`, and the subfolders `Approval Matrix/`, `Quoting Rules for D365/`, `Globalscape Product & Pricing Fields/`, `Pricebooks From SharePoint/`.

**Not extractable / gaps:** the two Product Pricing Rules Google Docs (external links in the BSI doc); full row sets for all five large sheets (extractor truncated at ~400 rows each). No in-scope file was encrypted, binary, or empty.
