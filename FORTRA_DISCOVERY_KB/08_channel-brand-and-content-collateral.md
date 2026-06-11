# 08 — Channel: Brand Guidelines & Partner Content / Collateral

> **Scope & nature:** This is *reference/collateral* material, not transactional Salesforce config. It documents (1) the **Fortra brand guidelines** (logo, color, typography, voice, product-naming rules), (2) the **Fortra Protect Partner Program** structure (tiers, benefits, requirements, margins, territories), (3) the **Fortra cybersecurity portfolio / solution categories**, (4) **buyer personas** (Data Protection), and (5) an **inventory of the partner content examples** (datasheets, guides, decks, videos).
>
> **Why it matters to the RCA project:** Several artifacts here are *source-of-truth* for data that lands in Salesforce/Workday transactional config covered in other discovery docs — most importantly the **VAR tier model, deal-registration margins (7/12/15/20%), revenue territories (T1/T2/T3), and the partner-discount structure**, which feed the channel pricing/partner-discount data lists (see the sibling Channel KB doc on partner discounts & partner-type access). The **product rebrand map** (legacy brand → Fortra solution category → Fortra product) is the canonical naming reference for Product2 / catalog naming in RCA. Brand/voice rules are governance, not config.
>
> Source folder: [Channel/Content Examples](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples) + top-level [fortra-brand-guidelines.pdf](../Fortra%20Discovery%20Documentation/Channel/fortra-brand-guidelines.pdf).

---

## 1. Fortra Brand Guidelines (essentials)

Source: [fortra-brand-guidelines.pdf](../Fortra%20Discovery%20Documentation/Channel/fortra-brand-guidelines.pdf) (v16.2). The companion [Fortra Brand Guidelines.url](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Fortra%20Brand%20Guidelines.url) just points at the public copy: `https://static.fortra.com/assets/brand/fta-brand-guidelines.pdf`.

### 1.1 Voice & copy rules (load-bearing for any Fortra-facing text)
- **"Fortra" is always sentence-case**: capital F, rest lowercase → `Fortra`, never `FORTRA`.
- Website in body copy: `fortra.com` (all lowercase, **no** leading `www.`).
- Website standalone (footers, signage, under logo): `Fortra.com`.
- Mission tagline / north-star message: **"Break the attack chain."**

### 1.2 Logo
- Logo always carries the **®** symbol in all instances. Where "Fortra" is spelled out, the **"a"** takes the place of the triangle (Delta) used in the logomark.
- On dark backgrounds (Fortra Forest, Dusk Forest, other dark): logo must be **Sky Blue**.
- On light backgrounds: use **Fortra Forest**. Acceptable light backgrounds: White, Cream, Sky Blue, Mint Green.
- **Clear space** is measured using the **Delta** mark; the ® is excluded from clear-space requirements.
- **Delta logomark** can stand alone to signify the brand. Carries ® when displayed ≥ **96px** wide/high, **300 DPI** print / **72 PPI** web. Provided at 16/32/64/96/128/256 px sizes.
- **Logo don'ts:** no unapproved colors, no stretch/compress, no degrading effects, no Sky Blue on White, delta must match logo color, don't lock up sub-brands or the Delta logomark with the Fortra logo, don't use black logo when color is available.

### 1.3 Brand colors (exact values)

| Color | Pantone | RGB | CMYK | Hex | Role |
|---|---|---|---|---|---|
| **Sky Blue** | 304 C | 143/229/242 | 38/0/7/0 | `8FE5F2` | **Primary** |
| **Fortra Forest** | 568 C | 0/106/86 | 94/35/68/22 | `006A56` | **Primary** |
| Dusk Forest | 330 C | 0/68/66 | 95/45/65/37 | `004442` | Wide use |
| Fern | 625 C | 77/127/113 | 72/34/57/12 | `4D7F71` | Wide use |
| Lichen | 623 C | 112/165/154 | 42/16/33/0 | `70A59A` | Wide use |
| White | White | 255/255/255 | 0/0/0/0 | `FFFFFF` | Wide use |
| Mint Green | 352 C | 119/236/194 | 43/0/41/0 | `77ECC2` | Accent only |
| Cream | 9043 C | 227/227/227 | 8/7/11/0 | `E3E3E3` | Accent only |
| Gray Taupe | 421 C | 169/169/169 | 32/24/26/0 | `A9A9A9` | Accent only |
| Beige | 9220 C | 235/219/193 | 3/12/16/0 | `EBDBC1` | Accent only |
| Web Button | N/A | 17/113/156 | N/A | `11719C` | Web UI |
| Web Hover | N/A | 0/70/103 | N/A | `004667` | Web UI |

Intent: colors are "nurturing, approachable, organic" to warm a strong/angular logomark.

### 1.4 Typography

| Context | Primary | Secondary / notes |
|---|---|---|
| **Logo & tagline** | **Styrene A Bold** | Logo only — do NOT re-create logo with the font; use approved files. License not needed if only used for logo/tagline. |
| **All media incl. web** | **Poppins** (Google font) | Bold (primary); Regular, Medium, Black (secondary). Chosen for fast load + international accessibility. From `fonts.google.com/specimen/Poppins`. |
| **Non-Latin** (Japanese, Arabic, Hebrew) | **Noto** ("typeface for the world", Google) | Use sans-serif version; use same Noto for Latin text in the same piece (don't mix with Poppins). |
| **PowerPoint / Word (M365)** | **Calibri Bold** | **Consolas** as callout/small/monospace font. |

### 1.5 Photography
- **Black & white only**; strong, serious, sophisticated, documentary/editorial, optimistic, natural light.
- Focus on **people** (companies/people being helped) over technology or surroundings; show diversity in age, ability, race, gender; show collaboration/community.
- **Don'ts:** nothing too dark/ominous/scary; nothing studio/fake/staged.

### 1.6 Brand messaging boilerplate (canonical strings)
- **"About Us" heading:** `BREAK THE ATTACK CHAIN`.
- **Boilerplate / "About Fortra":** "Fortra provides advanced offensive and defensive security solutions that deliver comprehensive protection across the cyber kill chain. With complete visibility across the attack chain, access to threat intelligence spanning the globe, and flexible solution delivery, Fortra customers can anticipate criminal behavior and strengthen their defenses in real time. Break the chain at fortra.com."
- **Legal line:** "Copyright © Fortra, LLC and its group of companies. Fortra®, the Fortra® logos, and other identified marks are proprietary trademarks of Fortra, LLC."

### 1.7 Product / solution naming rules (canonical for catalog naming)
- **Solution categories are NOT proper nouns** (lowercase): "Fortra's brand protection solutions…" ✓ vs. "Fortra Brand Protection offers…" only when naming the *product*.
- **Products** are preceded by **"Fortra"** (non-possessive) on first reference: `Fortra DMARC Protection` ✓, not `Fortra's DMARC Protection`.
- Acronyms spelled out on first reference unless market-known (DLP, XDR OK to abbreviate). Pattern: `Fortra File Integrity Monitoring` (1st) → `Fortra FIM` (2nd).
- Industry-term products lowercase when not naming the Fortra product: "data classification should be…" vs. "Fortra Data Classification offers…".
- **Legacy reference rule:** acceptable as "Fortra DLP (previously known as Digital Guardian)" ✓ — never "Fortra DLP (Digital Guardian)".

### 1.8 Legacy → Fortra product rebrand map (sunset 2025)

> **Highly reusable** for RCA catalog / Product2 naming and for reconciling legacy CRM (D365/Dynamics, Tripwire SF, Globalscape SF) SKUs to Fortra products. These nine legacy brand names are **being sunset in 2025**: Agari, Alert Logic, Beyond Security, Clearswift, Digital Defense, Digital Guardian, PhishLabs, Terranova Security, Tripwire.

| Previous product line | New solution category | New Fortra product offering |
|---|---|---|
| PhishLabs | Brand Protection | **Fortra External Threat Monitoring** |
| PhishLabs | Brand Protection | **Fortra Takedown Services** |
| Lookout | Data Protection | **Fortra CASB** |
| Titus, Boldon James | Data Protection | **Fortra Data Classification** |
| Digital Guardian | Data Protection | **Fortra DLP** |
| Lookout + multiple Fortra | Data Protection | **Fortra DSPM** |
| Lookout | Data Protection | **Fortra SWG** (Secure Web Gateway) |
| Lookout | Data Protection | **Fortra ZTNA** (Zero Trust Network Access) |
| Agari | Email Security | **Fortra Cloud Email Protection** |
| Agari | Email Security | **Fortra DMARC Protection** |
| Clearswift | Email Security | **Fortra Secure Email Gateway** |
| Terranova Security | Email Security | **Fortra Human Risk Management** |
| PhishLabs | Email Security | **Fortra Suspicious Email Analysis** |
| Tripwire | Integrity & Compliance Monitoring | **Fortra File and Integrity Monitoring** (FIM) |
| Tripwire | Integrity & Compliance Monitoring | **Fortra Secure Configuration Management** |
| Cobalt Strike | Offensive Security | **Cobalt Strike** |
| Core Security | Offensive Security | **Core Impact** |
| Outflank Security Tooling (OST) | Offensive Security | **Outflank Security Tooling** |
| Beyond Security | Vulnerability Management | **Fortra Application Security Testing** |
| Beyond Security, Digital Defense, Tripwire, Alert Logic | Vulnerability Management | **Fortra Vulnerability Management** |
| Alert Logic | XDR | **Fortra XDR** |

> Note the partner-program overview brochure (§3) lists slightly different "formerly" labels for some products (e.g. "Fortra Vulnerability Management (formerly Beyond Security, Digital Defense, and Tripwire IP360)"; "Fortra Managed WAF and XDR (formerly Alert Logic)"). The brand-guidelines table above is the more granular/authoritative mapping.

---

## 2. Fortra Protect Partner Program — structure

Primary sources: [Fortra-Protect-Partner-Program-Overview (1).pptx](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Fortra-Protect-Partner-Program-Overview%20(1).pptx) (internal deck, 31 slides) and [partner-program-overview-brochure (1).pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/partner-program-overview-brochure%20(1).pdf) (external brochure). Fortra positions itself as a **"channel-first organization"** with **25,000+ customers**.

### 2.1 Program options (partner types)
1. **Value-Added Reseller (VAR) Program** — three tiers: **Silver → Gold → Diamond**.
2. **Distributor Program** — resell & support to *their* resellers; advanced technical/sales/marketing support; train their resellers.
3. **MSP / MSSP Program** — provide Fortra solutions inside their service offering; tiered pricing on select products, dedicated channel manager, free certs, NFR licenses. Two packages: **Starter** (no upfront revenue commitment) and **Growth** (advanced marketing support + upfront revenue commitment).
4. **Strategic Alliance / OEM Program.**
5. **Referral partners** — exempted from certification requirements (mentioned in brochure).

VAR tier character (brochure): **Silver** = entry-level (online sales/tech certs + standard enablement); **Gold** = mid-level (adds marketing certs, free NFR, dedicated CAM, increased marketing); **Diamond** = top tier (advanced sales/product training + advanced sales/marketing support). **Silver is "By Invite Only"** per the tier-advancement slide.

### 2.2 Revenue territories (T1/T2/T3)

| Territory | Countries / regions |
|---|---|
| **Territory 1 (T1)** | United States, United Kingdom, Ireland, Middle East |
| **Territory 2 (T2)** | Canada, Nordics, Benelux, DACH, South Europe |
| **Territory 3 (T3)** | Rest of World |

Region groupings (from deck speaker notes):
- **UK&I:** United Kingdom & Ireland.
- **Middle East:** Bahrain, Egypt, Iraq, Jordan, Kuwait, Lebanon, Libya, Oman, Palestine, Qatar, Saudi Arabia, Syria, UAE.
- **Nordics:** Akrotiri, Dehkelia, Denmark, Faroe Islands, Finland, Gibraltar, Greenland, Guernsey, Iceland, Jersey, Norway, Svalbard, Sweden.
- **Benelux:** Belgium, Luxembourg, Netherlands.
- **DACH:** Austria, Germany, Liechtenstein, Switzerland.
- **South Europe:** Andorra, France, Italy, Malta, Monaco, Portugal, San Marino, Spain, Vatican.

### 2.3 Revenue requirements (two ways to maintain status; vary by territory)

| Requirement | Silver | Gold | Diamond |
|---|---|---|---|
| **Min. Incremental Revenue thru Partner Deal Registration** | N/A | T1 $250,000 / T2 $125,000 / T3 $75,000 | T1 $500,000 / T2 $250,000 / T3 $125,000 |
| **Min. Annual Reoccurring Revenue** | N/A | T1 $1,000,000 / T2 $500,000 / T3 $250,000 | T1 $2,000,000 / T2 $1,000,000 / T3 $500,000 |

A partner satisfies the revenue bar by **either** incremental deal-registration revenue **or** annual recurring revenue.

### 2.4 VAR deal margins (guaranteed margins) — *feeds partner-discount config*

| Margin type | Silver | Gold | Diamond | Distributor |
|---|---|---|---|---|
| **Guaranteed Margin — Fortra-Originated Deals** | Through Distributor | **7%** | **12%** | Through Distributor |
| **Guaranteed Margin — Channel-Originated Deals (Deal Registration)** | Through Distributor | **15%** | **20%** | Through Distributor |
| **Discount — Fortra Professional Services** | Through Distributor | **15%** | **15%** | Through Distributor |

**Margin caveats (Table 1 footnotes, deck slide 24):**
- Margins do **not** apply to: 3rd-party software, existing sales, **perpetual software sales**, certain public-sector deals, certain Fortra Professional Services.
- Fortra may **withhold program benefits** if the deal requires **non-standard pricing (NSP)** to the customer.
- Fortra reserves the right to **evaluate any deal above $200K**.
- Rationale for guaranteed margin: predictable profitability, simplified business planning, competitive advantage, reduced financial risk/reliable forecasting.

### 2.5 Program requirements — certifications & training (by tier)

| Requirement | VAR Silver | VAR Gold | VAR Diamond | Distributor | MSP/MSSP |
|---|---|---|---|---|---|
| Fortra Partner Agreement | • (thru Distributor) | • | • | • | • |
| Annual Business Plan | — | • | • | • | • |
| Basic Sales Training | • | • | • | • | • |
| **Certified Sales Trainer** | 1 | 3 | 4 | 6 | 2 |
| **Certified Pre-Sales Contact** | 1 | 2 | 3 | 4 | 2 |
| **Certified Marketer** | — | 1 | 1 | 1 | — |
| Provide Level 1 Support | Upon Approval | Upon Approval | Upon Approval | Upon Approval | • |

> Brochure phrasing of the certification stack: Silver **1 Sales + 1 Pre-Sales**; Gold **3 Sales + 2 Pre-Sales + 1 Marketer**; Diamond **4 Sales + 3 Pre-Sales + 1 Marketer**; Distributor **6 Sales + 4 Pre-Sales + 1 Marketer**. (Internal deck's "Certified Sales Trainer" counts of 1/3/4/6 align to the Sales numbers.)

**Tier advancement** (VAR, within a rolling **12-month** period):
- **Silver:** By invite only.
- **Gold:** achieve territory revenue plan; **1 Sales + 1 Pre-Sales** certified; **2 co-branded campaigns**.
- **Diamond:** achieve territory revenue plan; **3 Sales, 2 Pre-Sales, 1 Marketer** + (Diamond row) **4 Sales, 3 Pre-Sales, 1 Marketer**; marketing = **4 co-branded campaigns + 2 events + annual plan**.
- **Maintaining status:** evaluated **annually** at the program review cycle; falling below threshold can drop a tier next evaluation. Mid-year promotions possible (CAM approval). Evaluation factors: sales volume & pipeline growth, lead quality & conversion, CSAT scores/feedback, training & marketing participation.

### 2.6 Benefits matrix — Sales / Marketing (internal deck, slide 14)

| Sales Support & Incentives | Silver | Gold | Diamond |
|---|---|---|---|
| Incumbency Protection | • | • | • |
| Competitive Partner Discounts | • | • | • |
| New-Business Deal Registration | Through Distributor | • | • |
| Participation in Incentive (SPIFF) Programs | Through Distributor | • | • |
| Evaluation Licenses (Upon Approval) | • | • | • |
| Channel Account Manager Access | Through Distributor | • | • |
| Business Planning | — | — | • |

| Marketing | Silver | Gold | Diamond |
|---|---|---|---|
| Promotional Use of Partner Logo | • | • | • |
| Partnership-Level Badge | • | • | • |
| Access to Campaign Solution Kits | • | • | • |
| Partner Communications | • | • | • |
| Access to Sales Enablement Materials | • | • | • |
| Access to Partner Portal | — | • | • |
| Marketing Development Funds (MDF) | Through Distributor | • | • |
| Joint Marketing Planning with Fortra | — | • | • |
| Dedicated Partner Marketer | — | Through Distributor | • |
| Case Study Collaboration | — | — | • |
| Invitation to Partner Conferences/Events | — | — | • |

**Partner benefits per the external brochure (slightly different framing):** NFR licenses = **Basic** for Gold, **Enhanced** for Diamond & Distributor (Silver: through distributor); Dedicated Channel Manager for Gold/Diamond/Distributor; Free Sales Overview courses for all; Sales/Pre-Sales/Marketing cert courses "Upon Approval."

### 2.7 MSP/MSSP-specific benefits (deck slide 31)
Discounts from product lists; License renewal through partner; Dedicated CAM; Free Sales & Marketing certification; Free Pre-Sales certification; **Not-for-Resale (NFR) licenses**; Enhanced Partnership-Level Badge; Marketing Team Onboard; Joint Marketing Plan; **Quarterly** MDF eligibility. Requirements: Fortra Partner Agreement, Annual Business Plan, Basic Sales Training, **2** Certified Sales Trainers, **2** Certified Pre-Sales Contacts, Level 1 Support.

### 2.8 Enablement model (Fortra Academy + shadowing)
- **Fortra Academy** = online learning platform (`training.fortra.com/learn/`). Register with **corporate email**; auto-granted courses your org is entitled to sell; activation email; escalate to CAM for access issues.
  - **Level 1** = solution-group courses (position value of each solution group).
  - **Level 2** = individual-solution courses.
  - Marketing/Sales/SE courses are **free**; **technical courses for Service Delivery & Support are chargeable**.
- **Certification course types:** Solution Group Sales; Solution Sales; Pre-Sales "How To Demo"; Pre-Sales Technical; Pre-Sales Proof-of-Value. Quality assessment conducted by the Fortra team.
- **Three-stage SE enablement:** 01 Enablement (initial knowledge transfer) → 02 Opportunities (Fortra supports demos/PoVs; expect **100% Fortra coverage on first 3 opportunities**; partner SE **must shadow** all activities) → 03 Deployments (first projects; partner includes a % of project scope delivered by Fortra Professional Services; partner shadows all PS engagements).
- **Enablement resource list:** Fortra Website, Partner Portal, Fortra Academy, Sales Overlays, SE & Services Shadowing, Sales & Marketing Collateral. Collateral types: Datasheets, Reports & Guides, Customer Stories, Webinars & Videos, Ideal Customer Profiles, Solution & Persona Guides.

> **RCA/Workday connection:** None of the enablement content is transactional config. The *load-bearing* program data for SF is in §2.2–2.6 (tiers, territories, revenue thresholds, margins) and maps to the partner-discount data lists and partner-type access requirements documented in the sibling Channel discovery doc. Partner tier + territory likely drive Account/partner records and partner-discount selection in RCA pricing.

---

## 3. Fortra cybersecurity portfolio / solution overview

Sources: [fta-corp-cybersecurity-portfolio-ds.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/fta-corp-cybersecurity-portfolio-ds.pdf) (corporate portfolio datasheet) and the partner-program brochure.

### 3.1 The "Break the Attack Chain" framing
Fortra's entire portfolio is positioned against the **cyber kill chain** stages: **Recon → Weaponize → Deliver → Exploit → Install → Command & Control (C2) → Achieve Objectives.** Differentiator vs. ~thousands of point-solution vendors (claimed 99% cover one link): Fortra covers the **entire** chain.

**3 reasons to choose Fortra:** (1) complete attack-chain coverage; (2) offensive *and* defensive security; (3) shared threat intel & analytics (nearly **400** globally recognized threat experts; bi-directional intel exchange with law enforcement/ISACs). Differentiators on the corporate datasheet: Complete Visibility (unified cloud-native platform with agent; exclusive AI models; real-time IOCs), Flexible Delivery (interoperable modules; product and/or managed-service models; **progressive discounting for superusers**), Open Intelligence.

### 3.2 Eligible-to-sell solutions (brochure)
**Defensive:** Fortra Vulnerability Management (formerly Beyond Security, Digital Defense, Tripwire IP360); Fortra File Integrity Monitoring (Tripwire); Fortra DLP (Digital Guardian); Fortra CASB (Lookout); Fortra DSPM; Fortra Data Classification (Titus, Boldon James); Fortra Brand Protection (PhishLabs); Fortra Cloud Email Protection (Agari); Fortra DMARC Protection (Agari); Fortra Secure Email Gateway (Clearswift); Fortra Human Risk Management (Terranova); Fortra Managed WAF and XDR (Alert Logic).
**Offensive:** Core Impact Pen Testing Software; Cobalt Strike Red Team Tools; Outflank Security Tooling.

### 3.3 Attack-chain → solution mapping (internal deck slide 8 + brochure)

| Kill-chain stage | Fortra solutions positioned there |
|---|---|
| **Recon** | Vulnerability Management, Application Security Testing, Pen Testing Services, Core Impact, Cobalt Strike & Outflank Red Team Tools, Security Configuration Management |
| **Weaponize / Deliver** | Brand Protection, Email Security, Managed WAF, Secure Web Gateway, Zero Trust Network Access |
| **Exploit / Install / C2** | File Integrity Monitoring, Managed XDR |
| **Achieve Objectives** | CASB, Data Classification, DLP, DSPM, Human Risk Management |

> The brochure also lists **Strategic technology partners** (IBM, Microsoft, SAP, Oracle, Cisco, VMware) and industry memberships (ISACA, PCI). Recognition: G2, Frost & Sullivan 2024 named Email Security and XDR as market leaders; threat-intel partnerships with Interpol, FBI.

---

## 4. Buyer personas — Data Protection (Internal Only)

Source: [Fortra Data Protection Personas Guide.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Fortra%20Data%20Protection%20Personas%20Guide.pdf). Marked **Internal Only**. Split into **Decision Makers** and **Influencers**, each with Goals/Responsibilities, Discovery Questions, and "Highlight Fortra's Solutions" angles.

**Decision Makers:** CISO (Chief Information Security Officer), CCO (Chief Compliance Officer), CPO (Chief Privacy Officer), Business (Unit) Owner (e.g. VP of HR).
**Influencers:** Security Director, Security Analyst, Security Operations Analyst.

| Persona | Goals / responsibilities (abridged) | Fortra value angles to highlight |
|---|---|---|
| **CISO** (DM) | Demonstrate value of security program, maximize investments; minimize risk/impact of data breaches/loss; balance efficacy vs. budget | Minimize breach/compliance risk; deliver value while maximizing investment; balance effectiveness vs. cost; security-as-enabler |
| **CCO** (DM) | Ensure legal/regulatory compliance; develop policy, train, monitor; investigate violations; interact with regulators | Minimize breach/compliance risk; flexible policies for multiple compliance needs; depth of visibility/analysis; security-as-enabler |
| **CPO** (DM) | Oversee privacy policies/practices; compliance with local→international law; mitigate corporate risk | Minimize breach/compliance risk; flexible compliance policies; depth of visibility/analysis; security-as-enabler |
| **Business Unit Owner / VP HR** (DM) | Aligned to BU responsibilities; owns units handling regulated data (PII) or high-value IP | Minimize breach/compliance risk; remove barriers to new projects/processes |
| **Security Director** (Inf) | Tool & policy implementation; partner on SOC SOPs; gather input, recommend solutions | Ease of implementation; ease of policy management; integration with wider SOC platforms |
| **Security Analyst** (Inf) | Provide policies from privacy/compliance; tune policy; guide SOC actions; strong ops partner | Strength of privacy/compliance controls; granularity of policy; depth of reporting/analysis |
| **Security Operations Analyst** (Inf) | Build/configure/deploy per Director; write policy code; maintain environment & agents health | Ease of implementation; ease of policy management; ease of agent management |

Recurring discovery questions across personas: data identification/reporting across the org, enforcing DLP across all egress points without hurting productivity, proving compliance & violation reporting to executives, avoiding alert fatigue, agent/endpoint deployment effort.

> **RCA connection:** Persona guide is pure sales-enablement (ICP targeting), no SF config impact.

---

## 5. Content examples inventory

Source index: [content examples-links.docx](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/content%20examples-links.docx) lists external links; the linked PDFs were downloaded into [Content Examples/Files from links in the word doc/](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc).

### 5.1 The links index (`content examples-links.docx`)
| Category | Asset | URL |
|---|---|---|
| Datasheet | Cobalt Strike Datasheet | `static.fortra.com/cobalt-strike/pdfs/datasheets/cbs-cobalt-strike-datasheet-refresh-ds-081821.pdf` |
| Datasheet | Brand Protection Solution Brief | `static.fortra.com/corporate/pdfs/solution-briefs/fta-brand-protection-sb.pdf` |
| Guide | The Ultimate Guide to Data Protection | `static.fortra.com/digital-guardian/pdfs/guides/fta-dg-data-protection-bora-gd.pdf` |
| Guide | The Ultimate Vulnerability Management Buyer's Guide | `static.fortra.com/digital-defense/pdfs/guide/dd-vulnerability-management-buyers-gd.pdf` |
| Customer Story | Vulnerability Management Case Study | `static.fortra.com/digital-defense/pdfs/case-study/dd-large-financial-institution-cs.pdf` |
| Customer Story | MFT Case Study (Alliant Credit Union) | `goanywhere.com/resources/case-studies/alliant-credit-union` (web only — not downloaded) |
| Video | Fortra Data Protection Overview Video | `linoma.wistia.com/medias/e9oct0mhsh` (video — not extractable) |
| Video | Fortra "Break the Chain" Video | `static.fortra.com/assets/brand/break-the-chain/break-the-chain.mp4` (video — not extractable) |

### 5.2 What each downloaded asset is

| File | Type | Doc code | One-line description |
|---|---|---|---|
| [fta-corp-cybersecurity-portfolio-ds.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/fta-corp-cybersecurity-portfolio-ds.pdf) | Corporate datasheet | fta-corp-ds-0625-r11-sv | Portfolio overview: "We Break the Attack Chain," 3 reasons to choose Fortra, Cyber Defense Platform, threat-research team. |
| [partner-program-overview-brochure (1).pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/partner-program-overview-brochure%20(1).pdf) | Partner program brochure (external) | fta-cp-gd-0625-r3-sv | External Fortra Protect Partner Program overview: tiers, eligible solutions, territories, revenue reqs, benefits, MDF. |
| [Fortra-Protect-Partner-Program-Overview (1).pptx](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Fortra-Protect-Partner-Program-Overview%20(1).pptx) | Partner program deck (internal, 31 slides) | — | Internal sales deck w/ speaker notes: program tiers, margins (Table 1), enablement methodology, MSP/MSSP, Academy. |
| [Fortra Data Protection Personas Guide.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Fortra%20Data%20Protection%20Personas%20Guide.pdf) | Persona guide (Internal Only) | — | DLP buyer personas (decision makers + influencers) with discovery questions & value angles. |
| [brand-protection-sales-deck.pptx](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/brand-protection-sales-deck.pptx) | Product sales deck (39 slides) | — | Brand Protection (DRP) sales deck — see §5.3. |
| [cbs-cobalt-strike-datasheet-refresh-ds-081821.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/cbs-cobalt-strike-datasheet-refresh-ds-081821.pdf) | Product datasheet | fta-cbs-ds-1124-r4-db | Cobalt Strike adversary-simulation/red-team datasheet (Beacon, Malleable C2, Arsenal/Community Kits, BOFs, system reqs). |
| [fta-brand-protection-sb.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/fta-brand-protection-sb.pdf) | Solution brief | fta-al-sb-0625-r3-vm | Brand Protection solution brief: collection→curation→mitigation, services, recommended coverage per service. |
| [dd-vulnerability-management-buyers-gd.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/dd-vulnerability-management-buyers-gd.pdf) | Buyer's guide | fta-dd-gd-0425-r2-vm | VM buyer's guide: on-prem vs. SaaS, features to look for, Fortra VM features (Security GPA, Peer Insight, Network Map, Connect API, <1% false positives). |
| [dd-large-financial-institution-cs.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/dd-large-financial-institution-cs.pdf) | Customer case study | fta-dd-cs-0924-r1-db | Digital Defense / Fortra VM Pro at a $5B Northern-California bank (~90 branches); compliance PCI DSS/FFIEC/GLBA; VM Pro + PSA, Social Test, pen testing. |
| [fta-dg-data-protection-bora-gd.pdf](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/fta-dg-data-protection-bora-gd.pdf) | Ultimate guide | fta-dg-gd-0923-r2-an | "Ultimate Guide to Data Protection": data protection vs. security vs. privacy, regulatory timeline (1789→GDPR 2018), 3 pillars (DLP, Classification, Sharing), Digital Guardian solutions. |

### 5.3 Brand Protection sales deck — key facts (`brand-protection-sales-deck.pptx`, 39 slides)
- Positioning proof points: **2 of 3** most valuable global brands; **4 of 5** largest US financial institutions; **364,000+** takedowns in last 12 months; **150+** credit unions/community banks; FS-ISAC advisory board.
- **Operating model = Collection → Curation → Mitigation.**
  - **Collection:** Web (open/dark/deep, app stores), Social media, **300+ data feeds**, client feeds; parsing/crawling/anti-evasion/pivoting. Phishing-collection scale: **15M URLs, 250,000 domain registrations, 1M SSL cert registrations** processed daily across 300+ partner feeds.
  - **Curation:** relevancy algorithms → automated analysis → expert handling.
  - **Mitigation:** automated **Killswitches**, **Takedown APIs**, browser-blocking, DMCA, strategic relationships; **99% success rate**; **15+ years** global takedown network; **>50%** of credential-theft incidents leverage direct integrations.
- **12 Brand Protection services:** Domain Monitoring, Customer Phishing Protection, Social Media Protection, Counterfeit Protection, Mobile App Protection, Open Web Monitoring, Executive Protection, Source Code Monitoring, Intelligence Assessments, Dark Web Monitoring, Threat Engagement & Disruption, Threat Intelligence Feeds.
- **Domain scoring** = low/med/high across 5 signals: WhoIs, content, A-record, MX record, SSL cert.
- **Customer Phishing Protection + DMARC bundle** (Fortra DMARC Protection + Fortra Brand Protection): DMARC failure → intel auto-fed to Brand Protection → auto-mitigation. Case study (Jan 1–Apr 28, 2022): **40,733** URLs from DMARC failures → **106** unique phish detected/mitigated + **17** sending IPs taken down.
- **Mobile App Protection:** 500+ app stores. **Anti-evasion** techniques: user-agent blocking/filtering, file-attachment lures (parse Office/PDF, follow URLs), non-browser detection (headless browser + JS), IP-range/GEO-IP blocking, per-visitor directory generators.

> **RCA connection:** All §5 items are marketing collateral / sales enablement and have no direct SF/Workday config impact. They are relevant only insofar as they (a) confirm canonical product names (cross-check the §1.8 rebrand map) and (b) would live in a future **Partner Portal** content library (the partner portal is referenced repeatedly as a benefit gated by tier — see §2.6).

---

## 6. Open questions / ambiguities
1. **Where does partner-program data land in RCA?** The tier/territory/margin model (§2.2–2.6) is clearly source-of-truth for partner discounts and partner-type access, but the mapping to specific Salesforce objects/fields (Account tier field, partner-discount records, deal-registration object) is documented in *other* Channel discovery files, not here. Cross-reference the partner-discount data lists and partner-type/access requirements docs.
2. **Margin exclusions vs. RCA pricing:** the explicit exclusions (perpetual software, 3rd-party, existing sales, certain public sector, certain PS) and the **NSP / >$200K deal-evaluation** rules imply pricing-rule logic — does RCA model these as excluded product families or as manual approval gates? Not answered by collateral.
3. **NFR licenses (Basic vs. Enhanced)** are a benefit tier — is there a corresponding $0/internal SKU or order type in RCA for NFR/eval licenses? Unknown from these sources.
4. **Brochure vs. internal deck discrepancies** in product "formerly" labels and certification counts (see notes in §1.8 and §2.5). Treat the brand-guidelines rebrand table (§1.8) and the deck's numeric cert table as authoritative; flag for confirmation with the channel team.
5. **External vs. internal copy:** the personas guide and parts of the deck are marked **Internal Only**; confirm none of this is surfaced in the customer/partner-facing portal content set.
6. **Document version currency:** datasheets carry codes dated 0625 (Jun 2025), brand guide is **v16.2**; verify these are the latest before reusing externally.

---

## 7. Connections to the Design KB and other discovery docs
- This doc is the *brand/collateral* slice. The **partner pricing/discount mechanics, partner-type access matrices, deal-registration field mapping, and CAM territories** live in the broader Channel discovery set (Partner Discounts Data Lists, `Partner Types_Salesforce Requirements`, `Field Mapping for SFDC Partner Portal Deal Registration Form`, `Cyber CAM Territories by Region`) — out of scope here but directly downstream of §2.
- The product **rebrand map (§1.8)** is the naming authority that the RCA Product2 catalog and the legacy-CRM (D365 / Tripwire SF / Globalscape SF) consolidation should reconcile against.
- Brand voice/color/typography rules (§1) are governance for any generated DocGen / quote-PDF / customer-facing output produced by the RCA implementation.

---

## Sources

**In-scope — read in full (extracted text):**
- [Channel/Content Examples/content examples-links.docx.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/content%20examples-links.docx)
- [Channel/Content Examples/Fortra Brand Guidelines.url.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Fortra%20Brand%20Guidelines.url)
- [Channel/Content Examples/Fortra-Protect-Partner-Program-Overview (1).pptx.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Fortra-Protect-Partner-Program-Overview%20(1).pptx)
- [Channel/Content Examples/partner-program-overview-brochure (1).pdf.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/partner-program-overview-brochure%20(1).pdf)
- [Channel/Content Examples/fta-corp-cybersecurity-portfolio-ds.pdf.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/fta-corp-cybersecurity-portfolio-ds.pdf)
- [Channel/Content Examples/Fortra Data Protection Personas Guide.pdf.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Fortra%20Data%20Protection%20Personas%20Guide.pdf)
- [Channel/Content Examples/brand-protection-sales-deck.pptx.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/brand-protection-sales-deck.pptx)
- [Channel/Content Examples/Files from links in the word doc/cbs-cobalt-strike-datasheet-refresh-ds-081821.pdf.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/cbs-cobalt-strike-datasheet-refresh-ds-081821.pdf)
- [Channel/Content Examples/Files from links in the word doc/fta-brand-protection-sb.pdf.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/fta-brand-protection-sb.pdf)
- [Channel/Content Examples/Files from links in the word doc/dd-vulnerability-management-buyers-gd.pdf.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/dd-vulnerability-management-buyers-gd.pdf)
- [Channel/Content Examples/Files from links in the word doc/dd-large-financial-institution-cs.pdf.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/dd-large-financial-institution-cs.pdf)
- [Channel/Content Examples/Files from links in the word doc/fta-dg-data-protection-bora-gd.pdf.txt](../Fortra%20Discovery%20Documentation/Channel/Content%20Examples/Files%20from%20links%20in%20the%20word%20doc/fta-dg-data-protection-bora-gd.pdf)

**Top-level (in brief, per FOCUS):**
- [Channel/fortra-brand-guidelines.pdf.txt](../Fortra%20Discovery%20Documentation/Channel/fortra-brand-guidelines.pdf) (v16.2) — clean text extract captured all load-bearing content (hex/Pantone/RGB/CMYK color values, typefaces, voice rules, full product-rebrand table). Vision read of the original PDF not required for the data captured here.

**Not extractable / external (linked but not local files):**
- MFT Case Study — Alliant Credit Union (`goanywhere.com`, web page only, not in folder).
- Fortra Data Protection Overview Video (`linoma.wistia.com/medias/e9oct0mhsh`) — video.
- Fortra "Break the Chain" Video (`static.fortra.com/assets/brand/break-the-chain/break-the-chain.mp4`) — video.
