# Fortra Discovery Knowledge Base — Master Index

## What this is

This knowledge base is a synthesis of the **"Fortra Discovery Documentation"** business-discovery corpus — the raw requirements artifacts gathered during Fortra's CRM/quoting/billing transformation program (discovery calls, legacy-system field dumps, pricebooks, sample documents, SSRS/Power BI report definitions, UAT screenshots, and contract templates).

- **Source corpus:** 219 files under `Fortra Discovery Documentation/`.
- **How it was built:** every source file was run through a text-extraction pipeline into `Data/discovery-extract/` (see `manifest.tsv` for per-file status, character counts, and notes). Each topic was then synthesized into a standalone document (files `02`–`26` in this folder). This index (`00`) and the executive overview (`01`) were written last, on top of the topic docs and the manifest.
- **Relationship to `FORTRA_KNOWLEDGE_BASE.md`:** that root-level document is the **DESIGN synthesis** — it distills the 31 Confluence design docs describing the *target-state* Salesforce RCA + Workday + MuleSoft architecture (how it is being built). **This Discovery KB is the complementary BUSINESS / AS-IS synthesis** — it captures *what Fortra does today* across legacy systems (D365, Tripwire SF, Globalscape SF CPQ, GP, Zuora, NetSuite) and *what the business is asking for*. Read the design KB for "how the new system works"; read this KB for "what the requirements and legacy reality are." Where the two touch the same defect (e.g. SC-3384 multi-currency, SC-3350 COLA), this KB supplies the as-is grounding.

> **Start here:** [01_OVERVIEW.md](01_OVERVIEW.md) — the cross-cutting executive synthesis ("read this first").

---

## Document catalog

### Sales & Marketing
| # | Doc | Hook |
|---|-----|------|
| 02 | [Lead Flow & Attribution](02_sales-marketing-lead-flow-and-attribution.md) | Fortra's renamed "Inquiry" lead lifecycle, routing/SLA, and the first-touch → multi-touch (linear) attribution shift behind the One Team/One Number Unified Pipeline 2026 vision, enabled by the Mar 2026 SFDC go-live. |
| 03 | [Territory Routing & Inquiry Assignment](03_sales-marketing-territory-routing.md) | Per-product territory match hierarchy, AE/BDR/CAM assignment logic, and the 2,138-row territory master that drives inquiry routing. |
| 04 | [New Account, Sales Inquiry & DUNS / D&B Matching](04_sales-marketing-new-account-duns-flow.md) | Proposed D&B/DUNS-driven dedup and Account-hierarchy logic for two intake paths: automated inbound Sales Inquiry (HubSpot) and the manual New Account Wizard. |

### Channel
| # | Doc | Hook |
|---|-----|------|
| 05 | [Partner Portal, Deal Registration, Types & Access](05_channel-partner-portal-and-deal-registration.md) | Partner portal (PRM=SFDC) requirements, field-by-field Deal Registration mapping, partner-type taxonomy + access matrix, KPI metrics, CAM territories, and channel reporting. |
| 06 | [Partner Onboarding / Offboarding & Management](06_channel-partner-onboarding-management.md) | The 6/17/25 Channel Partner Management call — CAM org model, 5-phase onboarding & 4-stage offboarding checklists, partner-record SF requirements, legacy Alert Logic onboarding plan. |
| 07 | [Partner Discounts Data (D365 → RCA)](07_channel-partner-discounts-data.md) | D365 partner/channel discount lists (Cyber & Tech) reshaped into RCA Partner Discount load files — field map, brand coverage, WIP→UAT→prod transform. |
| 08 | [Brand Guidelines & Partner Content/Collateral](08_channel-brand-and-content-collateral.md) | Fortra brand rules, the Fortra Protect Partner Program (tiers/territories/margins), the cyber portfolio, DLP buyer personas, and a partner content inventory. |

### Pricing & Products
| # | Doc | Hook |
|---|-----|------|
| 09 | [Product Catalog, Hierarchy & SKUs](09_products-catalog-hierarchy-and-skus.md) | Cyber/Tech/Services/Globalscape SKU catalogs, the Unit→Solution Group→Brand→Family→SKU hierarchy, GP-Item-Class→RCA-Product-Type taxonomy, PhishLabs tiered pricing, and the D365→SFDC SKU migration. |
| 10 | [Pricing Strategy & Approval Matrices](10_pricing-strategy-and-approval-matrix.md) | Cyber pricing-strategy project (6,124 SKUs → 3-tier Good/Better/Best), the Cyber & Tech discount-approval matrices, legacy D365 quoting/billing field catalog, BSI↔Coastal next steps. |
| 11 | [Quoting Rules for D365: Experlogix, Bundles & Hardware](11_quoting-rules-d365-experlogix.md) | Legacy D365/Experlogix CPQ rule grammar, bundle BOMs, required-items, and the hs_hardware object — and how each maps to RCA Product Configuration Rules, bundles, hardware data. |
| 12 | [Globalscape → Salesforce RLM Field Mappings](12_globalscape-rlm-field-mappings.md) | Field-by-field migration triage of the legacy Globalscape SF CPQ (SBQQ__) org onto RCA/RLM, with Workday-required Order fields, the ALE formula, the product taxonomy, M&S ratios. |
| 13 | [Legacy Pricebooks (SharePoint) Inventory](13_legacy-pricebooks-inventory.md) | Inventory of 34 legacy per-brand SharePoint pricebooks (30 password-locked) plus extracted GoAnywhere USD/AUD, Alert Logic, and Tripwire-Japan price/SKU structures. |

### Quotes & Billing
| # | Doc | Hook |
|---|-----|------|
| 14 | [Partner Pricing Models & Billing Scenarios](14_quotes-billing-partner-pricing-models.md) | The two partner pricing models (Guaranteed Margin vs Discount), channel billing flows, hardware grouping, and PowerBranching line-splitting — grounded in the Meridian MSP quote/invoice. |
| 15 | [Export Controls + Operational ARR / Billings Data](15_quotes-billing-export-controls-and-misc.md) | As-is export-control/denied-party screening (a hard quoting/ordering gate), the Outflank ARR model, the Finance Master Billings workbook, and the 4-quote UAT reprice work-list. |
| 16 | [Quote Approval & Deal Desk](16_quote-approval-deal-desk.md) | Legacy Fortra Deal Desk workflow: exception-type catalog, per-LOB reviewer routing, MS-Forms intake, approval teams/proxies, and the >50%/MYCAP/Displaced-ARR escalation rule. |
| 17 | [D365 Terms & Conditions Rules](17_d365-terms-and-conditions-rules.md) | Legacy D365 condition→clause rules that auto-inserted T&C/EULA, tax, license-key, service-terms and signature text onto Quote/Invoice documents, with verbatim language and RCA/DocGen rebuild guidance. |

### Contracts & Legal
| # | Doc | Hook |
|---|-----|------|
| 18 | [Agreements, Schedules & NDAs](18_contracts-and-legal-agreements.md) | The MSA + Solution-Specific-Schedule + Order Form architecture and the brand/SKU-specific contract terms (term, renewal, payment, liability, export, DPA) that drive RCA quoting/billing/renewal logic. |

### Support & Portal
| # | Doc | Hook |
|---|-----|------|
| 19 | [Globalscape Knowledge Base (InstantKB Export)](19_support-portal-kb.md) | Legacy Globalscape InstantKB export: 867 articles (EFT/CuteFTP/DMZ Gateway/Arcus), data model, volume, and mapping to the Fortra Support Portal Solution Category 2.00 / Feature 4.00. |

### BSI Discovery
| # | Doc | Hook |
|---|-----|------|
| 20 | [D365 SSRS Reports (Quote/Order/Invoice/Credit)](20_bsi-d365-ssrs-reports.md) | The six legacy D365 SSRS report definitions decoded into datasets, field maps, and conditional logic — the as-built requirements for SF DocGen quote PDFs and Workday invoice/credit documents. |
| 21 | [Power BI Reports, Dataflows & Lineages](21_bsi-powerbi-reports-and-dataflows.md) | Legacy Power BI estate (CE/Services + Finance) over D365, Tripwire SF, Globalscape SF, SharePoint/ADP & Customer Voice — field maps, dataflows and SQL views to re-source onto RCA + Workday. |
| 22 | [Campaign / Marketing Product & POI UAT](22_bsi-campaign-marketing-product-uat.md) | UAT walkthrough of the Campaign Marketing Product lookup and the Inquiry POI / Unit-derivation feature, doubling as a bug log (POI field-vs-list mismatch, Unit auto-populate gap, label/layout fixes). |
| 23 | [Sample Quote & Invoice PDFs](23_bsi-sample-quotes-and-invoices.md) | 13 real legacy quote/invoice PDFs grounding RCA DocGen + Workday invoice requirements — partner billing splits, Spain unique invoice numbering, bundle rendering, ELA summarization, large-line-count edge cases. |
| 24 | [Tripwire TE License Management (Interim Phase)](24_bsi-tripwire-te-license.md) | How Tripwire Enterprise on-prem licensing, downloads, and support entitlement are represented in the legacy Tripwire SF org (LAC asset model vs. Issued Product/Configuration/Configured Product self-serve model). |
| 25 | [D365 Entity Junctions & FortraUAT Role Changes](25_bsi-d365-entity-junctions-and-roles.md) | The legacy D365 N:N junction-entity inventory (with RCA keep/drop notes) plus the FortraUAT Salesforce role hierarchy and its Cyber/Tech de-branding consolidation map. |

### Cross-Team
| # | Doc | Hook |
|---|-----|------|
| 26 | [Current (As-Is) Payment & Deposit Process](26_cross-team-payment-deposit-process.md) | As-is cash-application across the fragmented legacy AR stacks (D365/GP, Tripwire/Zuora, Alert Logic/NetSuite, Globalscape/OrdersX) and the bank/card/lockbox flows the RCA→MuleSoft→Workday O2C redesign must replace. |

---

## Source corpus & extraction status

**219 source files** under `Fortra Discovery Documentation/`, extracted to `Data/discovery-extract/` (per-file detail in `Data/discovery-extract/manifest.tsv`).

### Extraction summary
| Status | Count | Meaning |
|--------|------:|---------|
| `ok` | 165 | Text successfully extracted and synthesized |
| `encrypted` | 30 | Password-protected `.xlsx` — header/structure not recoverable without password |
| `skip-binary` | 24 | Binary assets (images, Power BI `.pbix`, video, zip) not run through the text pipeline |
| **Total** | **219** | |

### File types
| Ext | Count | | Ext | Count |
|-----|------:|---|-----|------:|
| xlsx | 79 | | sql | 6 |
| docx | 45 | | rdl | 6 |
| pdf | 33 | | pptx | 6 |
| png | 16 | | pbix | 5 |
| json | 11 | | csv | 3 |
| | | | vsdx | 2 |
| | | | drawio | 2 |
| | | | zip / url / txt / mp4 / jpg | 1 each |

### Source folders
| Folder | Files |
|--------|------:|
| BSI Discovery Info | 64 |
| Pricing and Products | 59 |
| Channel | 34 |
| Contracts and Legal Documents | 24 |
| Quotes and Billing | 17 |
| Sales and Marketing | 15 |
| Support and Portal | 3 |
| Cross Team Meetings | 2 |
| (root) QuotesToReprice.xlsx | 1 |

### KNOWN GAPS (not extractable from the provided artifacts)

These are explicitly enumerated so the gaps are discoverable. Closing them requires the original binaries, a password, or the live system.

**1. The 30 password-locked pricebooks** (`Pricing and Products/Pricebooks From SharePoint/`) — full per-brand catalog migration is **blocked on a password**. Of the 34 SharePoint pricebooks, only the GoAnywhere/MFT, Alert Logic, and Tripwire-Japan DRAFT files were readable. Locked files:
> Agari, AutoMate, Beyond Security (Federal Incl), Business Intelligence, Bytware, CCSS, COS, CTS, Capacity Management, Clearswift, Cobalt Strike, DDI, Doc Mgt RJS, Halcyon, IGA, Intermapper, JAMS MVP, MFT Pricing 2024, Outflank, PhishLabs, Powertech, Robot, SafeStone, Skybot, Tango, Terranova, and the four Tripwire regional books (AMER/LatAm, APAC, EMEA, and KK Japan). See [13_legacy-pricebooks-inventory.md](13_legacy-pricebooks-inventory.md).

**2. Power BI `.pbix` binaries (5)** — no DAX measures, model relationships, or visual layout recoverable; only the companion dataflow JSON, SQL views, and lineage PNGs were extractable. Finance/billings reporting is a near-total gap (`Adapted Billings Report.pbix` has no supporting dataflows/SQL). Files: `CE Customer Engagement.pbix`, `CE Services Delivery.pbix`, `CE Utilisation.pbix`, `Services Project Hours.pbix`, `Adapted Billings Report.pbix`. See [21_bsi-powerbi-reports-and-dataflows.md](21_bsi-powerbi-reports-and-dataflows.md).

**3. The Globalscape KB zip (~906 MB / 950 MB)** — `Support and Portal/kb_globalscape_com202508081526.zip` is a full HTML site dump of the legacy InstantKB; not run through the text pipeline. The 867-article structure was recovered from the companion CSV/SQL export instead; the HTML bodies, attachments/images, and the InstantKB Categories/Types/Status/Levels label tables remain in the zip. Available on request. See [19_support-portal-kb.md](19_support-portal-kb.md).

**4. The Payment & Deposit meeting video (146 MB)** — `Cross Team Meetings/…Meeting Recording.mp4`; no transcript/audio extraction available. The companion transcript was synthesized in [26_cross-team-payment-deposit-process.md](26_cross-team-payment-deposit-process.md); video-only content beyond the transcript is unrecovered.

**5. Truncated large spreadsheets** — the text extractor caps at ~400 non-empty rows per sheet. The full row sets for the large product/bundle sheets are **not** in the extract and must be re-pulled from source xlsx or the live system:
> Cyber Products (8,874r), Tech Products (9,441r), Services SKUs D365 (1,224r), Globalscape BSS-22410 (15,129r) — [09](09_products-catalog-hierarchy-and-skus.md); Bundle Items D365 (3,148r) — [11](11_quoting-rules-d365-experlogix.md); PartnerDiscount Cyber-for-Production 'Cyber Data' (589r, header-only), 'Raw 2' (2,394r), 'Data to Load C&T' (589r), 'Tech ALL Columns' (555r) — [07](07_channel-partner-discounts-data.md).

**6. External / non-local references** — the two **Product Pricing Rules Google Docs** (Drive links in `BSI_Coastal 07 14 2025 Next Steps.docx`), the **Approval Exception Form** full question set (only the MS-Forms URL + Q1 extracted), the **MFT Case Study** (goanywhere.com web page), the **Visio territory diagram** (`SF_TerritoryRouting.vsdx`/`.jpg` — node text recovered from companion `.drawio`/`.pdf`), and several missing export-control source docs (Tripwire OCR screening summary + Confluence pages). See [09](09_products-catalog-hierarchy-and-skus.md), [16](16_quote-approval-deal-desk.md), [03](03_sales-marketing-territory-routing.md), [15](15_quotes-billing-export-controls-and-misc.md).

---

## Open questions across the corpus

A consolidated, de-duplicated list of the most material open questions raised across all topic docs. Grouped by theme; each item cites the source doc(s).

### Object model & "Inquiry" semantics
- **Is "Sales Inquiry" the renamed Lead or a distinct custom object?** Org labels Leads as "Inquiry"; the New Account/DUNS flow and Territory Routing both reference a "Sales Inquiry" whose object identity is unconfirmed. ([02], [03], [04])
- **Reconcile the two Inquiry-stage models** (Model A New/Assigned/Working/Pending Resolution/Converted/Closed vs Model B MQL/SAL with sub-statuses) and the KPI label mismatch (Inquiry→SAL vs Lead→MQL). ([02])
- **POI sync direction:** should the Inquiry Product-of-Interest multi-select picklist fan out into child POI records, or should children roll up into the picklist? Automation is broken (field shows 2 values, related list shows 0); the full POI→Unit derivation matrix (beyond Brand Protection ⇒ Cyber) is undefined. ([22], [02])
- **What object backs the "Marketing Products" lookup** (custom object, filtered Product2, or `Marketing_Product__c`)? ([22])

### Lead/territory routing & attribution
- **Named_Account__c is the top match tier but 0 rows are populated** in the Final UAT List — is named-account data loaded elsewhere or is this tier dead? ([03])
- **CAM is double-sourced** (Final UAT List.CAM vs Sheet4b geo-lookup) — which is authoritative? And the CAM auto-assignment rule (Brand→Country→State) doesn't resolve segment sub-regions (MSP/FinServ/PubSec/Strategic/AWS). ([03], [05], [06])
- **Exact definition/source of "Is PCTA?"** (territory Assigned-to-AE checkbox vs inquiry partner flag vs separate attribute). ([03], [02])
- **Attribution scope & mechanics:** first-touch → multi-touch (linear) achievable OOTB while retaining a full single Fortra journey? Account-contact vs opp-contact scope? Is Data Cloud used? How to replicate D365 campaign-code/UTM tracking URLs and associate dollars before pipeline/ALE exists at opp creation? All 12 Lead Flow Scenario SF outcomes are blank. ([02])
- **BDR→AE handoff point** and whether both AEs and BDRs can convert inquiries / create opps; is Pre-Qual an opp stage for BDR-creates-opp-for-AE? ([02])

### D&B / account hierarchy
- **How is the D&B Service reached** (native SF, managed package, or custom MuleSoft callout to D&B Direct+)? Duplicate handling on "DUNS already exists" (offer existing vs hard-block)? Re-enrichment of an already-matched Account from fresher D&B data is unaddressed. ([04])

### Partner / channel model
- **Reseller→Distributor requirement conflict** (Special-Notes "Optional" vs field-mapping "Required for Resellers"); which account field marks a reseller as indirect and forces distributor selection? ([05], [14])
- **Most target SFDC field API names in the Deal Registration mapping are UNKNOWN** (to be confirmed by BS Team). ([05])
- **What is the SF CAM territory / partner-account assignment model** (manual, assignment rules, or SF Territory Management)? It is WIP with no design today. And the canonical partner Account hierarchy (distributor → VAR → end customer)? ([06], [05])
- **Which legacy CRM becomes the partner system-of-record** post-migration, and how do partner discounts flow into RCA pricing and Workday billing? ([06], [07])
- **Where do partner Tier / Partner Type / Direct-Indirect land in SF** (presumably on the Account)? They're in curated discount sheets but absent from the 22-col RCA load shape. ([07])
- **How NFR / eval licenses are modeled in RCA** ($0/internal SKU or order type) and synced through fulfillment + Workday on onboard/offboard. ([06], [08])
- **Deal Registration approval rules/SLA and channel-conflict detection logic** for the SF DR object. ([05], [06])

### Pricing & SKU model
- **Does RCA collapse separate NEW MAINT vs RENEW MAIN (and Cross/Gov/GSA) SKUs into one Product2 + Subscription lifecycle, or preserve 1:1?** ([09])
- **Multi-currency is a live defect (SC-3384):** non-USD configured pricing uses USD values; PhishLabs tiered, Services, and Attribute-Tier-Pricing data are USD-only; FX rates corrupted (7/11 at 1.0). How are non-USD tiered prices computed? ([09], [13], [15], [24])
- **Per-tier price points in the Cyber strategy decks are placeholders ($XX)**; go-live "X Date" for non-Done SKUs is TBD; the per-brand COLA % rate table lives in an out-of-scope link. ([10])
- **Guaranteed Margin vs straight Discount enforcement** when only percentages are stored — implemented in the pricing procedure? Exact margin-stack math (markup multiplier vs retained-margin) and compounding order in `SubscriptionPricing74`? Which percentage set (Channel- vs Fortra-Originated) does the engine pick and does it key on Deal Origin? ([07], [14])
- **Experlogix Series → RCA ProductConfigurationRule mapping** is not stated; which ClearAll/RF maintenance rules port vs are obsolete under native state mgmt + derived pricing. ([09], [11])
- **Globalscape environment variants** (-NP/-DV/-SB encoding ~50%/33%/50% price ratios) and CPQ `gsUplift_*` renewal-uplift / co-terming — keep as distinct SKUs or model as RCA adjustments? ([09], [12])
- **Default COLA % by brand** and reconciling the renewal-automation matrix with the brand/SKU-aware contract terms (Tripwire ExpertOps does NOT auto-renew; Core/Cobalt/OST use 30-day vs MSA 60-day). Relevant to SC-3350 COLA renewal universe (43, not 1.2M). ([10], [18])

### Quoting, documents & billing
- **Is tax calculated in Workday or SFDC?** (Avalara `AVA_SFCPQ`/`SBQQ__TaxAmount__c` still needed?) Does RCA compute estimated VAT on quotes or always defer to invoice? ([12], [14], [23])
- **How the legacy single D365 invoice entity splits** into SF Order vs Workday Invoice/Credit, and which system generates each document. ([20], [23])
- **Is the Spain S-number invoice sequence allocated by Workday or RCA**, and does it extend to other EU entities? Does legacy Account (00…) number become a SF external ID? ([23])
- **Hardware/LPAR licensing detail** (`hs_quotedetailsubreport`: server/serial/processors/system-id) — RCA/asset equivalent? Hardware-group renewal-propagation mechanism (clone vs reference)? ([20], [14], [11])
- **Service Terms suppression granularity** (all-or-nothing "Hide PS Terms" vs per-line) and the SF field names/picklists for Legal_Entity, brand-on-line, and transaction Type (New/Renewal/Add-on) driving the T&C/EULA/license-key clause selection. ([17])
- **Whether localized (Spanish) T&C variants are required** for the AR/ES legal entities (docs are English-only); EUR-only secondary display currency vs RCA multi-currency. ([17], [20])

### Deal Desk & approval
- **Deal Desk SLAs existence/values are unsettled** ("need clarity from Matt/Tia"); the Approval Exception Form's per-exception detail questions are not extractable (only Q1); "SAARC" and "MYCAP" appear but are undefined here. ([16], [10])
- **Quote Approval Teams "Type" (Team vs Queue vs Individual)** is blank — SF Public Group/Queue/role assignment undecided; several `?`-flagged roles unconfirmed; cross-LOB (Cyber+Tech) routing unaddressed; filename↔content swap on the two matrix workbooks. ([16], [10])
- **Replicate as native SF Approval Process/Flow+Queues vs keep the external MS-Forms/SharePoint tracker via MuleSoft?** ([16])

### Export controls & legal
- **Does target-state RCA screen renewals and move screening to the Lead level?** Is Descartes/Visual Compliance the selected tool, MuleSoft-mediated? Several export-control source docs are missing. ([15])
- **How End-Use Statement / Chamber-of-Commerce legalization is enforced** for offensive-security SKUs (manual gate vs system flag); where the entity/region attribute (Fortra LLC=Minnesota vs Int'l Ltd=England&Wales vs Computing Group S.L.U.) lives in the data model. ([18], [17])
- **Where Alert Logic Node/log overage and Terranova user-count true-ups are measured and posted back to Workday billing.** ([18])

### Reporting & data lineage
- **Which SF migration stream replaces each D365 org** (hsprod CRM vs org5ade7db4 Customer Voice)? Post-migration source for ADP/utilisation HR data (likely Workday)? Was cases reporting ever migrated off the "OLD" D365 lineage? ([21])
- **Crosswalk from the 6 instance-specific `hs_legalentity` GUIDs** to SF/Workday legal-entity records is undefined; what `hs_mycap` represents and how it maps to RCA. ([20])

### Support, licensing & roles
- **The InstantKB Categories/Types/Status/Levels label tables were not exported** — the ID→name map needed for Feature 4.00 tagging is missing; legacy support URLs needing 301 redirects and the new portal URL scheme are undefined; confirm cases are in Service Cloud (no ticket data to migrate). ([19])
- **Exact org API names/casing for the Tripwire custom objects** (`Issued_Object__c`, `Configuration__C`) and the AssetRollup/ConfiguredProductRollUp trigger logic need source inspection; which of LAC vs Issued-Product is authoritative in interim prod; unmitigated license-replication abuse risk. ([24])
- **North/South AE each have two manager parents** — invalid for a single-parent SF role hierarchy; role label/API names need reconciling; per-junction keep/replace/drop decisions are only advised, not finalized; profile/permission-set assignments absent. ([25])

### Treasury / O2C cutover
- **Kyriba scope vs direct bank→Workday feeds undefined** (defer to Treasury); the Workday lockbox connector is missing from integration scope and must be added to JP Morgan scope; do the <$10k self-pay / >$10k manual card thresholds persist; retirement sequencing of Zuora/NetSuite/OrdersX/CyberSource/separate Tripwire GP relative to Workday cutover. ([26])
