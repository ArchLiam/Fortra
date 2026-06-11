# 10 — Pricing Strategy & Approval Matrices

**Scope:** Cyber Pricing Strategy project summary (Coastal/BSI engagement), the Cyber & Tech discount-approval matrices (threshold → approver tables across New Sale, Renewals, Legal, Deal Desk), the consolidated Quoting/Billing important-fields catalog (the legacy D365 schema that RCA must map from), and the BSI ↔ Coastal next-steps action list for translating the new pricing model into Salesforce.

**How this connects to the RCA build:**
- The **Cyber Pricing Strategy** is the business rationale for SKU consolidation (6,124 SKUs → tiered Good/Better/Best bundles) that the new RCA Product2 / ProductSellingModel catalog is meant to realize. It is the "why" behind the product-hierarchy and tiered-pricing tickets (e.g. SC-3390 tiered pricing, SC-3384 multi-currency).
- The **Approval Matrices** define the discount-threshold → role rules that an RCA Quote approval process / Deal Desk flow must enforce. The Deal Desk *process* doc (under `Quotes and Billing/Quote Approval/`) owns the workflow; this doc owns the **matrix content** (the actual %s, $ caps, and approver roles).
- The **Quoting/Billing important fields** is the legacy **Dynamics 365 (D365)** field catalog (note the `hs_*` HelpSystems schema prefix). It is the source-side field map that RCA Quote/QuoteLineItem/Order/OrderItem/Asset and Workday billing must be reconciled against during migration.

---

## 1. Cyber Pricing Strategy — Project Summary (as of 5.29.25)

Source: [Cyber_Pricing Strategy_Project Summary as of 5.29.25.pptx](Fortra Discovery Documentation/Pricing and Products/Cyber_Pricing Strategy_Project Summary as of 5.29.25.pptx) (deck dated "21 May 2025 Update"; status slide "5.30.25"). Engagement run with consulting partner **Coastal** (per BSI/Coastal next-steps doc).

### 1.1 Objectives (3 pillars)
1. **Provide Ease of Use** — Unify & streamline the price book to support simplified quoting and cross-product sales.
2. **Support Platform & Portfolio Expansion** — Create a flexible, scalable approach to support the move to a unified platform and the build-out of a structured pricing team and process.
3. **Quick Wins** — Provide both near-term and long-term recommendations as the company implements a Unified CRM and adjusts its Quote-to-Cash process.

Overarching goal: drive comprehensive **full-suite ("full-suite selling motion")** portfolio sales for Account Executives (AEs) on a unified platform, replacing the inconsistent organic+acquisition pricing structures.

### 1.2 Current-State pain points / findings
- **SKU proliferation:** 6,000+ SKUs in the Cyber portfolio; **10% sold < 10 times in 3 years**. Average **44 permutations per SKU/Product**.
- **Discount misalignment:** Many solutions average **above 40% discount**; Digital Guardian (DG) is **nearing 60%**, while the sales matrix only authorizes **20% at the VP/approval level** — a structural mismatch driving high approval burden.
- **UOM chaos:** 13+ units of measure across product lines (target: reduce to **< 5 standardized** units).
- Competitor "freemium" bundling drives high discounts and margin pressure; pricing changes historically focused on new sales, ignoring install base; no impact analysis for pricing revisions.
- Not feasible to provide existing SKUs & price lists to partners.

### 1.3 Recommended Unified Pricing Framework
**Packaging type chosen: Modular** (deck marks "Recommended"), implemented as a 3-tier Good/Better/Best structure:

| Tier | Name |
|---|---|
| Entry | **Essentials** |
| Mid | **Advanced** |
| Top | **Elite** |

Framework rules ("Approved by Chris and Sales Leadership"):
- Shift from à-la-carte features to **bundled products**; eliminate excess SKUs by grouping features into the 3 tiers.
- Features increase with each tier; **Add-Ons** provide modular flexibility (incl. Services).
- **Standardized support, independent of tier**; a **Starter Services Package is required**, optional add-ons available.
- Consolidate volume pricing into a limited number of tiers; use **negotiation** for large deals rather than extra pricing tiers.
- **Monetization model based on:** Tier level + User count + Add-Ons (incl. Services).
- **Deployment-agnostic:** deployment method (On-Prem / SaaS / Hybrid / Managed Service) affects **price but NOT tier structure**.

### 1.4 Current-State business-model landscape problems (Slide 3)
- UOM definitions vary across product lines; bundle definition varies.
- Multiple deployment models — need standard definitions, with **deployment model secondary to selling motion**.
- Need a standard business-model matrix governing packaging/pricing requests.
- UOMs catalogued: Agents, Annual Rev., Apps, Devices, eMail Volume, Topics, Asset Range, Configuration Items, Days (Ea.), Hours (Ea.), GB per Day, Users, IP, Nodes, Pages, Takedowns, Instance. Deployment models: On Prem, SaaS, Hybrid, Managed Service.

### 1.5 Competitor pricing comparison (Slide 7)

| Vendor | Pricing Strategy | Freemium entry (days) | Tiers | UOM | Licensing | Support tiers |
|---|---|---|---|---|---|---|
| MSFT (Defender) | Tiered/Modular + Add-On | 90 | 9 | User/Device/Consumption | Annual sub | 2 |
| CrowdStrike | Tiered/Modular + Add-On | 30 | 2 volume plans/tier | Device | Monthly at premium | 5 |
| Proofpoint | A La Carte/Tiered + Add-On | 15 | 4 | User/Consumption (limited) | Annual sub | 4 |
| Forcepoint | A La Carte, Customized | NA | 5 | User/Others | Annual sub | 3 |
| **Fortra (Future State)** | **Tiered/Modular + Add-On** | — | **3** | **User/Device/Each/TBD** | **Annual sub** | **1 (move to 3 as support model advances)** |

### 1.6 Project scope status (Slide 9, "Status Update 5.30.25")

Columns = Current State Validation % / Proposed Packaging % / Pricing & Install Review %.

| Priority | Solution Area | Brand Family | Curr-State Validation | Proposed Packaging | Pricing/Install Review |
|---|---|---|---|---|---|
| 1 | Data Protection | DSPM | 100% | 100% | 75% |
| 1 | Data Protection | Data Classification | 100% | 100% | 75% |
| 2 | DREP | Human Risk Mgmt (SAT) | 100% | 95% | 75% |
| 2 | DREP | eMail Security (Agari, Clearswift) | 90% | 40% | 25% |
| 2 | DREP | DRP (PhishLabs) | 100% | 25% | 25% |
| 3 | — | File Integrity Monitoring | 100% | 50% | 0% |
| 4 | — | Vulnerability Management | 100% | 50% | 0% |
| 5 | — | Offensive Security | 50% | 0% | 0% |
| N/A | Services | — | 100% | 75% | NA |

### 1.7 Next-Steps milestones (Slide 10)
- **Finalize "DSPM" proposal** — align on new pricing framework (Mtg 5/27), validate with critical teams incl. Channel, identify & map SKU consolidation changes. *Target: May 30, 2025.*
- **Align BSI** — work with BSI team to identify needed changes (complete); evaluate time/effort (in progress). *Target: May 30, 2025.*
- **Continue progress** through Prioritized Opportunity Areas: Proposal = DCS & SAT; Current State = DRP, Email, FIM. *Target: June 15, 2025.*

### 1.8 Proposed pricing models per brand (placeholders `$XX` in deck — values TBD)

**DSPM Proposed Pricing Model 2025 — OPTION B** (Slide 12): 3 tiers by coverage —
- **Essentials (DLP)** = Endpoint; **Advanced (DLP)** = Endpoint + Network; **Elite (DSPM)** = Endpoint + Network + Cloud; all priced `$XX/User`.
- Shared bundle contents (all tiers): Endpoint Agent (Win/Mac/Linux), Web Inspection Proxy, File Labeling, Control Policies, Investigation Module, Content Inspection, Analytics & Reporting Cloud (ARC) + APIs (SaaS); Retention (SaaS): 60 days live + 1 yr archive.
- Network DLP (Advanced+): Network Discovery, Web & Email Discovery. Cloud DLP (Elite): Realtime-inline controls, Cloud Sharing Controls, Continuous Risk-Based Access, Advanced DLP (API+Inline), Unlimited Apps.
- **Add-ons:** Live Data Retention 30-day increments (max 120 days) **$4.75 per User/annually**; Archive Data Retention 1-yr increment (max 3 yrs) **$5.75 per User/annually**; Digital Risk Management `$/xx`.
- Services = "Quick Start" required for new deployments. Discussion point: Network DLP as a standalone at a premium price.

**DCS (Data Classification Suite) Proposed Pricing Model 2025** (Slides 13–14): 3 tiers — Essentials (On-Prem/SaaS), Advanced (On-Prem/SaaS), Elite (SaaS, *hosting fees embedded into user price*). All priced `$xx/user per annum`. Key recommendations:
- DCS Outlook/Office (OWA) version released late-May creates opportunity to streamline packaging. DCS "Plus" renamed **DCS Advanced**.
- Clean up / eliminate **100+ SKUs** currently in CRM (legacy / EOL / EOS / embedded in bundles — likely system setup & translation issues).
- Embed SaaS infrastructure cost into per-user SaaS price; provide incremental Cloud/Hosting only at Elite; embed Data-at-Rest at Advanced+Elite; SDK into core bundle.
- Add-ons: **Cloud Policy Manager Desktop & M365** ($xx Essentials / $xx Advanced / Included Elite); **Fortra Mail for iOS** ($XX/user across tiers).
- No near-term change to Classifier pricing; Classifier→DCS migration path is a future roadmap item, outside current pricing work.

**SAT (Security Awareness Training) Proposed Pricing Model 2025 — OPTION A** (Slides 15–16): 3 tiers — Essentials (cap **1,000 users**), Advanced, Elite. `$X/User`. Recommendations:
- Cut SAT volume tiers from **16 to 5 max (3 best)**.
- Collapse Essentials + "Click & Launch" + "Click & Launch All Star" into one SMB/low-mid entry point.
- Differentiate by **language access**: Essentials = 3 languages, Advanced/Elite = 31; Role-Based Privacy & Compliance courses = 25 / 50 / 300 per tier.
- Communication & Reinforcement Tools (Newsletter, Comics, Infographics) = Complete Library all tiers.
- **Managed Service**: agnostic of product tier (propose by org maturity/need), but limit availability to Advanced & Elite. **MS Starter Pack flat rate $1,000**, required Year 1 of MS offering. Awareness Campaigns add-on `$X/each` (min 4); Phishing Campaigns add-on `$X/each` (min 4); Post Quiz `$X/each`; SAT Hourly Services `$X/hour`. Security Advisory Services: Basic/Standard/Advanced.
- *Speaker note:* Digital Guardian subscriptions/renewals = ~90% of revenue with ~65% discounts, aligning with market re-alignment.

### 1.9 Product / Brand Heatmap (Slide 20) — complexity baseline

Period basis FY22–Q1'25. Total **6,124 SKUs**, avg **44 products/SKU ratio**, **501 (8%)** products with <10 transactions in last 2-3 yrs.

| Sub-Segment | Product Family | Brand | SKU Count | Product/SKU Ratio | # <10 txns | % | Avg Discount |
|---|---|---|---|---|---|---|---|
| Email & Data | Digital Risk & Email Protection | Agari | 53 | 13 | 5 | 9% | 64% |
| | | Clearswift | 2,971 | 186 | 92 | 3% | 40% |
| | | PhishLabs | 51 | 2 | 2 | 4% | 39% |
| | | Terranova | 140 | 35 | 5 | 4% | 34% |
| Data Protection | Data Classification | (DCS) | 225 | 56 | 48 | 21% | 55% |
| | | Digital Guardian | 198 | 28 | 66 | 33% | 62% |
| | | Vera | 38 | 19 | 10 | 26% | 50% |
| Vuln Mgmt | | Beyond Security | 213 | 30 | 9 | 4% | 53% |
| | | Digital Defense | 975 | 61 | 57 | 6% | 45% |
| File Integrity Monitoring | | Tripwire | 937 | 25 | 187 | 20% | — |
| Offensive Security | Offensive Security | Cobalt Strike | 10 | 10 | 2 | 20% | 46% |
| | | Core CTS | 302 | 27 | 15 | 5% | 24% |
| | | Outflank | 11 | 4 | 3 | 27% | 22% |
| **Total** | | | **6,124** | **44** | **501** | **8%** | |

**SKU proliferation illustrated (Slide 21 — Clearswift SECURE Email Gateway):** a single product blows up to **807 SKUs** via `1 (product) + 12 (add-ons) + 19 (Services)` across these axes: (1) Antivirus engine option (Avira/Kaspersky/Sophos/No-AV), (2) Subscription vs Perpetual, (3) Managed vs Self-Managed across 7 pricing tiers, (4) First vs Additional instance, (5) Add-ons by tier, (6) Bundle options (unclear what's included), (7) 19 Services SKU types.

### 1.10 Discount analysis (Slide 23) — links to the approval-matrix mismatch
Period FY22–Q1'25, based on current list price, excludes 0-qty / transaction-price > price-book / Tripwire. Discount averages **40% / 43% / 45% / 59%** across families, with renewal-VP / CRO approval caps noted as the control points. This is the empirical evidence behind the matrix gap (sales discounting routinely exceeds the authorized 20%/VP threshold).

### 1.11 Engagement plan (Slide 19)
Two ~6-week phases (Mid-April → End of May): **(1) Research & Current-State Assessment** (SKU & discounting assessment, quote-to-cash process review) and **(2) Strategy Definition & Recommendations** (SKU consolidation/sunsetting, revised discounting model & UOMs, operational recommendations). Output = current-state analysis + preliminary exec guidance (create new vs consolidate existing price list) + a **12+ month roadmap** for SKU consolidation, quote-to-cash enhancements, and system updates (aligned with broader Q2C project). Phase 3 = execute & transition day-to-day ops to Fortra.

---

## 2. Discount Approval Matrices (2024 Draft, "Approved 250310", latest revision 4/11/25)

Two near-identical workbooks differ **only in role labels** — the *Cyber* matrix uses CRO-org titles, the *Tech* matrix uses GM/EVP/MD titles. Both carry identical thresholds, the same Deal Desk workflow, the same Legal matrix, and the same approved proxy list. **Focus here is matrix content; the Deal Desk process/workflow is owned by the Quotes and Billing / Quote Approval Deal Desk doc.** This matrix also appears under `Quotes and Billing/Quote Approval/`.

Sources: [Cyber Sales Approval Matrix 2024_Draft.xlsx](Fortra Discovery Documentation/Pricing and Products/Approval Matrix/Cyber Sales Approval Matrix 2024_Draft.xlsx), [Tech Sales Approval Matrix 2024_Draft (1).xlsx](Fortra Discovery Documentation/Pricing and Products/Approval Matrix/Tech Sales Approval Matrix 2024_Draft  (1).xlsx). Each workbook has 6 tabs: New Sale_Upsell, Legal, Renewals, Deal Desk Workflows, Useful links, Approved Proxy.

### 2.1 New Sale & Upsell Threshold Matrix — discount % → approver

The key columns are **Perpetual License**, **New Subscription**, **Channel/MSP**, **Services**, **New Maintenance**, plus quote-acceptance and order-size limits. Below 50%, AE/Director-level approvals apply; **anything above 50% requires Deal Desk (CRO/CFO/CEO).**

**CYBER matrix** (roles: AEs/CAMs → CRO's direct reports → Deal Desk):

| Approver Role | Perpetual License | New Subscription | Channel/MSP | Services | New Maintenance | Order-size / quote authority |
|---|---|---|---|---|---|---|
| **AEs / CAMs** | ≤25% of list | ≤15% of list | ≤15% of list | ≤15% of list | n/a | Email-accept (unsigned) orders **< $15k** (preapproved template + attached quote) |
| **CRO's direct reports** | ≤35% of list | ≤20% of list | ≤20% of list | ≤20% of list | n/a | Orders **< $25k** |
| — DEAL DESK REQUIRED (CRO, CFO, CEO) — | | | | | | |
| **CCO** | n/a | n/a | n/a | **≤100%** | ≤50% | — |
| **CRO** | ≤50% of list | ≤50% of list | ≤50% of list | n/a | n/a | Orders **$100k or less** |
| **CFO or CEO** | **>50% of list** | **>50%** | **>50%** | ≤100% (in lieu of CCO) | **>50% of existing amount** | Orders **> $100k**; any threshold needs CFO approval w/ rev-rec vetting in DD |

**TECH matrix** (roles: AEs/CAMs → Managing Directors or Sales Directors → GM/EVP Sales → CFO/CEO). Thresholds identical to Cyber, differing in the approver title at the >50% tier and the inclusion of Services discount for EVP:

| Approver Role | Perpetual License | New Subscription | Channel/MSP | Services | New Maintenance | Order-size / quote authority |
|---|---|---|---|---|---|---|
| **AEs / CAMs** | ≤25% | ≤15% | ≤15% | ≤15% | n/a | Orders **< $15k** |
| **Managing Directors / Sales Directors** | ≤35% | ≤20% | ≤20% | ≤20% | n/a | Orders **< $25k** |
| — DEAL DESK REQUIRED (EVP Sales, CFO, CEO) — | | | | | | |
| **GM or EVP Sales** | ≤50% | ≤50% | ≤50% | **≤50%** | n/a | Orders **$100k or less** |
| **CFO or CEO** | **>50%** | **>50%** | **>50%** | ≤100% (in lieu of CCO) | **>50% of existing** | Orders **> $100k** |

> Tech revision note (4/11/25): "Updated EVP to have up to 50% Services discount on new deals."

**General notes (apply to both):**
- All approvals via **email**, except Deal Desk.
- CFO/CEO approval needed for **all maintenance starting >30 days from invoice date**.
- CFO/CEO **and Legal** approval for any modification/addition to standard license or services agreement.
- CFO/CEO approval for all quotes prepared **outside a standard CRM** (Excel/Word).
- CRO's direct reports (Cyber) / MDs or Sales Directors (Tech) can approve **free / highly-discounted software to reconcile customer issues up to $3,500** without CFO approval.
- CRO (Cyber) / GM or EVP (Tech) approval for all **new MSP price lists** and add/change/delete to existing price lists.
- **Credit guidelines:** CEO/CFO approval for exceptions to license-key SOP (term key vs full key); partners must vet creditworthiness and inform Fortra of moderate/high-risk accounts at sale; **any service/support engagement or 3rd-party product sale >$10K must be prepaid or approved by CFO/CEO.**

**MYCAP (Multiyear Annually Paid) — Deal Desk required for all MYCAP sales.** Eligibility: (1) 2-year minimum contract, (2) 3% COLA on out-years preferred, (3) MYCAP quote template, (4) Deal Desk approval. (See "Standard Discounts for Multiyear.")

**Displaced ARR (Product Swap) — Deal Desk required for all sales producing displaced ARR** (existing ARR swapped for new ARR). Standard scenarios: (1) Upgrade, (2) Downgrade, (3) Acquisition (Repurchase), (4) Subscription→Perpetual, (5) Reinstatement, (6) Bundle Swap, (7) True-up / OARR, (8) Subscription Replacement vs Renewal.

### 2.2 Legal Approval Matrix

| Approver Role | Payment Net Terms | Limitation of Liability (non-standard) | Enterprise License Agreements (SLSA/ULA/Site) | Annual Increase Adj./Cap | Use of Client's Form | Contract-team turnaround |
|---|---|---|---|---|---|---|
| **Sales Team** | Standard net-30 only | n/a | Standard Fortra terms only | N/A | Must use Fortra Form | 3 business days |
| **Contracts Team** | — | 3× fees received in prior 12-mo **or $500K** | Partner Contracts & Schedule A reviewed by Partner Program owner (incl. sales-created bundles / "unlimited" offers) | **≥ Default COLA % (by brand)** | n/a | Non-standard paper up to **4 weeks** |
| — DEAL DESK REQUIRED (CFO, CEO, CLO) — | | | | | | |
| **AGC / GC / CLO** | Standard net-30 only | 5× fees in prior 12-mo **or $2M** | May grandfather old agreements per Legal Contract Playbook; all others reviewed/approved by CEO/CFO before customer presentation | **≥ Default COLA %** | May use customer form for on-prem >$50K; may approve client's form for partner deals w/ Partner Program approval | |
| **CFO or CEO (Deal Desk)** | All non-standard terms | **Above $2M** | All must be reviewed/approved by CEO/CFO before customer presentation | **< Default COLA %** | May approve client's form for Non-SaaS <$50K, any renewal, or any SaaS deal (on Legal's guidance) | |

*Cyber note:* Contracts Team LoL row reads "Contracts Team — 3X the fees… or $500K". *Note:* CFO/CEO + Legal approval needed for any modification/addition to standard license or services agreement, and must provide approval to Legal Contracts Team for markup of non-standard paper.

### 2.3 Renewals Approval Matrix

**CYBER** (note: per 4/11/25 Steering Committee, **Sr. Mgr and Director were removed from any discount level on renewals**):

| Approver Role | Discounting Existing ARR (COLA, etc.) | Sub→Perpetual switch | Renewal Cancellations | Temporary License Extensions |
|---|---|---|---|---|
| ~~Sr. Manager / Director / MD-Strategic Verticals~~ (removed 4/11/25) | Up to 10% or List COLA, **not to exceed $30K** | N/A | $100k and below | Up to 45 days |
| **VP, Renewals** | Up to 20%, **not to exceed $100K** | N/A | $100k+ (notify CCO/CFO/CEO) | Any |
| **CCO / CEO / CFO** | All discounts **>20% or >$100K** | Deal Desk required | $250k+ | NA |

**TECH** (same thresholds, roles = Director / EVP / CEO-CFO):

| Approver Role | Discounting Existing ARR | Sub→Perpetual | Renewal Cancellations | Temp License Ext. |
|---|---|---|---|---|
| **Director** | Up to 10% or List COLA, ≤$30K | N/A | $100k and below | Up to 45 days |
| **EVP** | Up to 20%, ≤$100K | N/A | $100k+ (notify CCO/CFO/CEO) | Any |
| **CEO / CFO** | >20% or >$100K | Deal Desk required | $250k+ | NA |

**Additional renewal commercial guidelines (both):**
1. Existing licenses cannot be cancelled & resold as ALE — exceptions require Displaced ARR + Deal Desk approval.
2. Customers who lapse and renew **within 12 months** are counted as a renewal.
3. To recognize ALE credit at renewal, **ALE is calculated after renewal + COLA**.
4. All customer requests for future budget pricing must come via the Renewals Team / AMs (Cyber) or Renewals/AEs (Tech).
5. **COLA does not count toward ALE.**
6. Swapping direct↔partner (or vice versa) cannot impact ARR.

### 2.4 Deal Desk Approval Workflow (categories of items requiring Deal Desk)
Identical in both workbooks. The matrix lists the *items*; the routing/SLA logic lives in the Deal Desk process doc.

| Group | Items |
|---|---|
| **Discount Approval** | Channel MSP Discount, Perpetual License Discount, Subscription License Discount, Services Discount, New Maintenance Discount, SAARC |
| **Process Exceptions** | MYCAP, Subscription Start Date, AWS Marketplace Renewal, Displaced ARR (Swap), Email Quote Approval, Offline Quote |
| **Legal Approval** | COLA Change, Legal Non-Standard Form (SaaS), Legal Non-Standard Form (On-Prem), Legal Terms, Non-Standard Net Terms, Non-Standard License Type |
| **Other** | Hardware Change Fee, Other, Export Control — Sales Appeal |

### 2.5 Useful Links & Approved Proxies (both workbooks)
- **Useful links** referenced: Deal Desk Submission Form, Deal Desk SLAs (annotated "Vicky — need clarity from Matt/Tia if we are even going to have them?"), Legal SharePoint site, Deal Desk Tracker, AWS Private Offer Request Form, **List/Default COLA Rate by Brand**, Swap/Displaced ALE Guidelines, Standard Discounts for Multiyear, Displaced ARR Guidelines.
- **Approved Proxy:**

| Role | Name | Proxy |
|---|---|---|
| CFO | Justin Ritchie | Vicky McCartney |
| President | Matt Reck | Tia Barisoff or Chris Hand |

### 2.6 RCA implementation implications of the matrix
- Approval thresholds key off **discount % of list** by **product line type** (Perpetual License / Subscription / Channel-MSP / Services / Maintenance) and on **order $ size**. An RCA Quote approval process must read line-type + discount% + total, and a Deal-Desk-routed approval is mandatory at **>50% discount** or for any MYCAP / Displaced-ARR / non-standard legal scenario.
- The "$3,500 reconciliation" and ">$10K prepay" carve-outs are special-case approval rules to encode.
- **COLA-by-brand** is a configurable rate table (the matrix repeatedly references "Default COLA % by brand"); this ties to the renewal COLA pricing work tracked in SC-3350.

---

## 3. Quoting & Billing Important Fields (legacy D365 / HelpSystems schema)

Source: [QuotingBillingImportantFields.xlsx](Fortra Discovery Documentation/Pricing and Products/QuotingBillingImportantFields.xlsx). This is the **legacy Microsoft Dynamics 365 (D365)** field catalog — the `hs_*` prefix = HelpSystems custom schema. It is the source-of-truth field list to map onto the RCA/Salesforce Quote→Order→Asset model and the Workday billing back end. Pricing/quoting was driven by **Experlogix** CPQ in the legacy world (many fields are flagged "Sent Back from Experlogix"), the analogue of RCA's native configurator.

**Sheets & sizes:** Quote (236 fields), Quote Lines (176), Order (198), Order Lines (159), Invoice (295), Invoice Lines (158), System Product (191), Entitlement (90), Product (176). Full field-by-field tables are in the source; below are the **load-bearing pricing/discount/migration fields** an engineer will actually need.

### 3.1 Discount & pricing fields (the matrix-enforcement fields)
These are the fields the Approval Matrix thresholds operate on, present across Quote/Quote-Line/Order/Invoice lines:

| Schema name | Label | Meaning / use |
|---|---|---|
| `hs_rsmdiscount` / `hs_rsmdiscountpercent` | RSM Discount / % | AE (Regional Sales Mgr) discount — the line-level discount the New-Sale matrix gates |
| `hs_partnerdiscount` / `hs_partnerdiscountpercent` / `hs_partnerdiscounttype` | Partner Discount / % / Type | Channel/MSP partner discount |
| `hs_partnerpricingdiscountamount` / `…percentage` (Quote) | Partner Pricing Discount | Quote-header partner pricing discount |
| `hs_additionalpartnerdiscount` (Quote) | Additional Partner Discount | — |
| `hs_partnerrenewaldiscountpercentage` | Partner renewal discount % | Renewal-specific partner discount |
| `hs_maintenancediscountpercent` | Maintenance Discount % | "New Maintenance" matrix column |
| `hs_servertypediscount` / `…percent` | Server Type Discount | — |
| `hs_overridediscountamount` / `hs_overridepercentage` / `hs_overridediscountpercentage` | Override Discount | Manual discount override |
| `manualdiscountamount` ("Flat Discount") / `volumediscountamount` | Manual / Volume Discount | OOB D365 line discounts |
| `hs_discountpercentage` (line) / `discountpercentage` (header) | Discount (%) | — |
| `hs_discountreason` / `hs_rsmdiscountreason` / `hs_seller…` | Discount Reason | Reason text for discount |
| `hs_salesrulebroken` (Quote Line) | Sales Rule Broken? | **"Used to flag approval"** — the trigger that an approval is required |
| `hs_managerapprovalneeded` / `hs_managerapproved` / `hs_managerapprovalreason` / `hs_managerrejectionreason` / `hs_approvedby` / `hs_approvedon` (Quote) | Manager Approval set | Quote-level approval workflow fields |
| `priceperunit` / `price` (List Price on Product) | Price Per Unit / List Price | Basis for "% of list" thresholds |
| `extendedamount` / `baseamount` / `totalamount` | Extended/Base/Total | Order-size thresholds ($15k/$25k/$100k) |

### 3.2 Revenue-classification rollups (Quote/Order/Invoice headers)
Used for ALE/ARR reporting and the matrix's "new software/subscription/maintenance" distinctions:

| Schema | Label |
|---|---|
| `hs_annualizedlicenseequivalent` (+`_base`) | **ALE** — annualized amount of new software, subscriptions, and new maintenance sales |
| `hs_quotelineale` (+`_base`) | Quote Line ALE |
| `hs_displacedarr` (+`_base`) | **Displaced ARR** (line + header) — drives the Displaced-ARR/Swap Deal Desk rule |
| `hs_totalsoftware`, `hs_totalsubscriptions`, `hs_totalmaintenance`, `hs_totalrenewalmaintenance`, `hs_totalservices` (+`_base`) | Revenue category totals |
| `hs_totalsoftwareplusmaintenance` ("SW++") | Software + Maintenance |
| `hs_annualrecurringrevenue` (System Product, +`_base`) | ARR — annual amount before increases/COLA |
| `hs_contracttotalvalue` (System Product, +`_base`) | Total contract value (full term) |

### 3.3 COLA / renewal-pricing fields (System Product — connects to SC-3350)
The System Product entity is the legacy **asset/subscription** record that renewals price off. These map to RCA `Asset` / subscription pricing:

| Schema | Label / note |
|---|---|
| `hs_listcolapercentage` | List COLA % — *copied from product brand, COLA default* |
| `hs_colapercentagetoapply` | COLA % to apply — *0 if Override COLA, else Increase % if set, else List COLA %* |
| `hs_increasepercentage` / `hs_overrideincreasepercentage` | Increase % / override (used in place of COLA) |
| `hs_bypasscola` | Bypass COLA? — COLA not applied to renewal |
| `hs_overrideprice` (+`_base`) | Override Price — base price for the renewal |
| `hs_maintenanceanniversary` / `hs_nextmaintenancerenewaldate` / `hs_maintenanceenddate` | Maintenance dates driving renewal timing |
| `hs_primarypartnerdiscount` / `hs_secondarypartnerdiscount` | Partner discounts applied at renewal |
| `hs_renewalgroup` | Forces split of a renewal when grouping (after account/currency/legal-entity grouping) |
| `hs_billingcode` / `hs_bibillcode` | Billing codes — `hs_bibillcode` "WS" (with software) generally means product is free; used in renewal price calc |
| `hs_excludefromarr` | Exclude from ARR rollup |

### 3.4 Multi-currency fields (connects to SC-3384)
Nearly every money field has a `_base` companion (value in base currency) plus `transactioncurrencyid`, `exchangerate`, `hs_historicalexchangerate`. This dual-currency structure is what the RCA multi-currency pricing work (SC-3384 — non-USD lookups landing on USD values) must preserve and correctly populate.

### 3.5 Tiered & SKU-structure fields (Product entity — connects to SC-3390 tiered pricing)

| Schema | Label / note |
|---|---|
| `hs_istieredpricing` | Is Tiered Pricing |
| `hs_skutierminimum` / `hs_skutiermaximum` / `hs_skutierpricemodel` | SKU tier bounds & price model |
| `hs_tiercode` / `hs_tierlevelquantityparameter` / `hs_tiermultiplierquantityparameter` | Tier code & quantity parameters |
| `hs_pricingtier` (System Product) | Pricing Tier on the asset |
| `hs_bundle` / `hs_bundletype` / `hs_bundlecodesku` / `hs_bundlelinesind365` | Bundle flags & type |
| `hs_branchingtype` | Branching type (volume branching) |
| `hs_isuserbased` | Is User Based (captures Experlogix "Is User Based" column) |
| `hs_legacyproduct` / `hs_legacyproductnumber` | Legacy product flag/number — key for old→revised SKU mapping |
| `hs_maxtermallowed` / `hs_mintermrequired` / `hs_istermlocked` | Term limits (months) for quoting |
| `hs_deploymenttype` | Deployment Type (On-Prem/SaaS/etc.) — note framework keeps deployment price-affecting but tier-independent |
| `hs_standardrenewalmaintenancesku` / `hs_premiumrenewalmaintenancesku` | Renewal maintenance SKUs |
| `productnumber` ("Product SKU") / `price` ("List Price") | Core SKU + list price |

### 3.6 Experlogix CPQ integration fields (legacy configurator)
`exp_linenumber`, `exp_nestedlinenumber`, `exp_recordid`, `hs_experlogixlineid`, `hs_experlogixbundleparentlineid`, `hs_experlogixmaintenanceparentid`, `hs_experlogixconfigurationname`, `hs_experlogixarea`, `hs_experlogixcalculationinfo`, plus Product-side `hs_experlogixcategory/categorykey/displayname/name/series/tableid/productmastername/sequencenumber/optseqno`. The Quote-line "Sent Back from Experlogix" flag marks fields the configurator owns (price, discounts, hardware specs, bundle structure). In RCA, native configuration/pricing replaces Experlogix — these are the behaviors to re-implement.

### 3.7 Other notable fields
- Export control: `hs_exportcontrolcategory`, `hs_exportcontroldocument`, `hs_exportdocumentationrequired`, `hs_disableexportcontrol`, `hs_subjecttoexportcontrol` — connects to "Export Control — Sales Appeal" Deal Desk item.
- MYCAP: `hs_mycap` (line/system product), `hs_includemycapterms` (Quote).
- Tax: `hs_taxcode`, `hs_taxstatus`, `hs_taxdetails`, `hs_disabletax`, `hs_taxexempt`, `hs_taxexemptionnumber` — maps to RCA/Workday tax engine.
- AWS Marketplace: `hs_awsmarketplaceagreementid`, `hs_awsofferid`, `hs_sharewithaws` — ties to "AWS Marketplace Renewal" Deal Desk item & AWS Private Offer.
- Brand "Has X" flags on Invoice (`hs_hasclearswift`, `hs_hasdigitaldefense`, `hs_hascobaltstrike`, `hs_hasoutflank`, etc.) — per-invoice brand presence, useful for migration brand mapping.

---

## 4. BSI ↔ Coastal Next Steps (7/14/2025)

Source: [BSI_Coastal 07 14 2025 Next Steps.docx](Fortra Discovery Documentation/Pricing and Products/BSI_Coastal 07 14 2025 Next Steps.docx). Action items from the BSI internal call (7/14/2025) to translate the new pricing model into Salesforce. (**BSI** = Business Systems & Innovation, owns integration build; **Marc** = pricing lead with the master spreadsheet; Coastal = implementation partner.)

### 4.1 Plan / sequence
1. **New Pricing Model availability (Good/Better/Best):** Data Protection and Human Risk Protection (Terranova) are **Done**. Other new SKUs: whatever else is available by an agreed "X Date" can make go-live — **date TBD (action: agree on date).**
2. **BSI Internal Call 7/14/2025** → **Call with Marc on 7/15** (assumption: work from Marc's master spreadsheet).
3. **Build → Translate to upload → Fortra reviews upload in the system (working session) → Revise and repeat** based on feedback.
4. **Marc's spreadsheet — fill out last 3 tabs.**

### 4.2 Focus on current SKUs → "Revised SKUs"
- **Map current SKUs to new SKU SFDC format**, to be known as **"Revised SKUs."**
- **Plan to solve:** Jordan, Mandy, Cassie splitting SKUs; **full list to be completed by EOD 7/15.**
- **Brands "Done"** (per spreadsheet Column T): **Terranova, Agari, PhishLabs, Cloud DP, Offensive Security, Power, GoAnywhere, RPA.**
- Column T solution-name → brand-list mapping:

| Solution Name (Column T) | Brand List |
|---|---|
| Cloud Data Protection | Cloud DP |
| Go Anywhere | GoAnywhere |
| Human Risk Management | Teranova |
| Offensive Security | Offensive Security |
| Power | Power |
| Robotic Process Automation | RPA |

- **Marc** to: review column T to see what else is needed; **process old SKU → create old-to-revised SKU mapping**; then **Fortra to confirm** (BSI, Jordan, Mandy, Cassie, Michaela, Sales Ops); revise as necessary.

### 4.3 Product Pricing Rules
- **Marc to share his list.** Three referenced Google Docs (two URLs duplicated):
  - `https://docs.google.com/document/d/1JQZnOirsLEyOc9azG5ikn9wJOUORjGzRFJkguzx3Mo4/edit`
  - `https://docs.google.com/document/d/15rZJrGSW9gTbtfAYpVxFYj3Ibl26jck-YJAzgtTtnY4/edit` (listed twice)
- **Leah / Wren to review;** revise as necessary → schedule a half-hour touch base for Wed or Thurs.
- **Marc to create the sheet for D365** (i.e., the source-side mapping in the legacy system).

> This document is the operational bridge between the Cyber Pricing Strategy (§1) and the RCA build: the "Revised SKUs" are the consolidated tiered products that the strategy designed, now being staged for upload into Salesforce/RCA Product2.

---

## 5. Open Questions & Ambiguities
1. **Proposed price points are placeholders.** DSPM/DCS/SAT decks show `$XX`/`$X` per-user prices — actual per-tier dollar amounts were not finalized in this material (only the DSPM add-ons $4.75 / $5.75 per-user and the SAT MS Starter $1,000 flat rate are concrete).
2. **Go-live "X Date"** for non-Done new SKUs is explicitly TBD ("Agree on Date").
3. **Default COLA % by brand** is referenced repeatedly (matrix + System Product `hs_listcolapercentage`) but the actual per-brand rates live in a separate "List/Default COLA Rate by Brand" link not in scope — needed to implement renewal pricing (SC-3350).
4. **Deal Desk SLAs uncertain** — annotated "need clarity from Matt/Tia if we are even going to have them?"
5. **Tripwire avg discount blank** in the heatmap; Tripwile is also excluded from the Slide-23 discount analysis — discount baseline for FIM is a data gap.
6. **Matrix is a 2024 Draft** ("Approved 250310", revised 4/11/25) — confirm it is the version to encode in RCA, and that Cyber's CCO/CRO roles vs Tech's CCO reference (Services ≤100% "in lieu of CCO") are reconciled (the Tech matrix references CCO in a note but has no CCO row).
7. **Experlogix → RCA configurator parity:** the legacy fields flagged "Sent Back from Experlogix" define behaviors (auto-pricing, bundle parenting, hardware specs) that RCA native config must replicate; mapping not specified here.
8. **SAARC** appears as a Deal Desk discount item but is undefined in these documents.

---

## 6. Connections to the RCA / Workday / MuleSoft Implementation & Related Tickets
- **SC-3390 (Tiered pricing requires Update Price twice):** the tiered-pricing fields in §3.5 (`hs_istieredpricing`, `hs_skutier*`) are the legacy precedent for the RCA tiered-pricing behavior under repair.
- **SC-3384 (Non-USD quotes use USD values):** the dual `_base`/`transactioncurrencyid`/`exchangerate` field structure (§3.4) is the multi-currency model the RCA pricing lookups must honor.
- **SC-3350 (COLA renewal pricing):** the renewal/COLA System-Product fields (§3.3) and the matrix renewal rules (§2.3) plus "Default COLA by brand" are the business spec behind the COLA renewal work.
- **Approval workflow vs content:** this doc = matrix content; the **Quotes and Billing / Quote Approval Deal Desk** doc = the workflow/routing. An RCA approval process must combine both.
- **BSI owns the upload of "Revised SKUs"** (§4) into Salesforce/RCA Product2; this is upstream of the product-hierarchy and pricebook migration. The companion design KB (`FORTRA_KNOWLEDGE_BASE.md`) covers the RCA platform design; this discovery KB captures the business inputs (strategy, matrix, field map, action list).

---

## Sources
- [Cyber_Pricing Strategy_Project Summary as of 5.29.25.pptx](Fortra Discovery Documentation/Pricing and Products/Cyber_Pricing Strategy_Project Summary as of 5.29.25.pptx) — extracted text read in full (23 slides incl. speaker notes).
- [Approval Matrix/Cyber Sales Approval Matrix 2024_Draft.xlsx](Fortra Discovery Documentation/Pricing and Products/Approval Matrix/Cyber Sales Approval Matrix 2024_Draft.xlsx) — extracted text read in full (6 sheets).
- [Approval Matrix/Tech Sales Approval Matrix 2024_Draft  (1).xlsx](Fortra Discovery Documentation/Pricing and Products/Approval Matrix/Tech Sales Approval Matrix 2024_Draft  (1).xlsx) — extracted text read in full (6 sheets).
- [QuotingBillingImportantFields.xlsx](Fortra Discovery Documentation/Pricing and Products/QuotingBillingImportantFields.xlsx) — extracted text read in full (9 sheets: Quote, Quote Lines, Order, Order Lines, Invoice, Invoice Lines, System Product, Entitlement, Product).
- [BSI_Coastal 07 14 2025 Next Steps.docx](Fortra Discovery Documentation/Pricing and Products/BSI_Coastal 07 14 2025 Next Steps.docx) — extracted text read in full.

No in-scope file was encrypted, binary, or empty. No images or diagram-heavy PDFs were in scope (the Cyber pptx is diagram-rich but its table content and speaker notes were fully captured in the extracted text).
