export const meta = {
  name: 'fortra-discovery-absorb',
  description: 'Absorb the Fortra Discovery Documentation corpus into a durable markdown knowledge base',
  phases: [
    { title: 'Synthesize', detail: 'one KB doc per topic, scoped to real source dirs' },
    { title: 'IndexOverview', detail: 'master index + cross-cutting executive overview' },
    { title: 'Audit', detail: 'completeness critic: every extracted source covered?' },
  ],
}

const EXTRACT = '/Users/liamjeong/Documents/Code/Fortra/Data/discovery-extract/text'
const SRC = '/Users/liamjeong/Documents/Code/Fortra/Fortra Discovery Documentation'
const EMB = '/Users/liamjeong/Documents/Code/Fortra/Data/discovery-extract/embedded-images'
const OUT = '/Users/liamjeong/Documents/Code/Fortra/FORTRA_DISCOVERY_KB'
const MANIFEST = '/Users/liamjeong/Documents/Code/Fortra/Data/discovery-extract/manifest.tsv'

const TOPIC_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['file', 'title', 'oneLineHook', 'sources', 'keyTopics', 'openQuestions', 'notExtractable'],
  properties: {
    file: { type: 'string', description: 'output filename written, e.g. 02_xxx.md' },
    title: { type: 'string' },
    oneLineHook: { type: 'string', description: 'one-line description for the index' },
    sources: { type: 'array', items: { type: 'string' }, description: 'source filenames actually used' },
    keyTopics: { type: 'array', items: { type: 'string' } },
    openQuestions: { type: 'array', items: { type: 'string' } },
    notExtractable: { type: 'array', items: { type: 'string' }, description: 'files in scope that were encrypted/binary/empty' },
  },
}

const SHARED = `You are absorbing Fortra's Salesforce Revenue Cloud Advanced (RCA) DISCOVERY documentation into a durable, reusable markdown knowledge base for future engineering and analysis work.

CONTEXT: Fortra is consolidating legacy CRMs (D365/Dynamics, Tripwire SF, Globalscape SF) onto Salesforce Revenue Cloud Advanced, with Workday as financial back end and MuleSoft as integration layer; partner Coastal implements; BSI (Business Systems & Innovation) owns integration build. A separate repo file FORTRA_KNOWLEDGE_BASE.md already synthesizes the Confluence DESIGN docs — THIS discovery KB is complementary (raw business discovery inputs: requirements, data lists, legacy artifacts, meeting notes). Do not duplicate the design KB; note connections where relevant.

EXTRACTED TEXT TREE (read these .txt — clean plaintext already extracted from docx/pptx/xlsx/pdf/csv/etc):
  ${EXTRACT}/<same relative path as source>.txt
ORIGINAL FILES (read these directly ONLY for images .png/.jpg and diagram-heavy PDFs, using the Read tool's vision):
  ${SRC}/<relative path>

HOW TO WORK:
1. List your scoped dir(s) with Bash (find/ls). Then Read EVERY extracted .txt in scope IN FULL. Do not skip files.
2. For images and diagram PDFs listed below, Read the ORIGINAL file (vision).
3. Synthesize ONE well-structured markdown knowledge document. Requirements:
   - Capture CONCRETE, reusable detail: exact field/object/API names, SKUs, picklist values, thresholds, discount %s, territory rules, formulas, table column lists, decisions, owners, dates. Use markdown tables for field maps and structured data.
   - Do NOT write generic fluff. A reader should be able to act from your doc without reopening the source.
   - Note open questions, ambiguities, and how each thing connects to the SF RCA / Workday / MuleSoft implementation.
   - Flag any in-scope file that was encrypted, binary, or empty (so the gap is explicit).
   - Use clickable relative markdown links to source files where useful, e.g. [Lead Flow Scenarios.docx](Fortra Discovery Documentation/Sales and Marketing/Lead Flow Scenarios.docx).
4. End the doc with a "## Sources" section listing every source file you used (and any you could not read).
5. Write the doc with the Write tool to: ${OUT}/<FILENAME>
6. Return the structured JSON (file, title, oneLineHook, sources, keyTopics, openQuestions, notExtractable).

Be thorough and exhaustive — quality and completeness matter more than brevity.`

function topicPrompt(t) {
  const scopes = t.scopes.map(s => `  - ${EXTRACT}/${s}`).join('\n')
  const imgs = (t.images && t.images.length)
    ? `\nIMAGES / DIAGRAM PDFs TO READ WITH VISION (original files):\n${t.images.map(i => '  - ' + i).join('\n')}\n`
    : ''
  return `${SHARED}

=========================================================
TOPIC: ${t.title}
OUTPUT FILE: ${t.file}
SCOPED EXTRACTED-TEXT DIRECTORIES (cover EVERY .txt inside, recursively):
${scopes}
${imgs}
FOCUS / BRIEF:
${t.brief}
=========================================================`
}

const TOPICS = [
  {
    file: '02_sales-marketing-lead-flow-and-attribution.md',
    title: 'Sales & Marketing — Lead Flow & Attribution',
    scopes: ['Sales and Marketing'],
    note: 'exclude the Territory Routing and New Account Flow Updates subfolders (covered separately)',
    images: [],
    brief: `Cover the TOP-LEVEL files in "Sales and Marketing/" only (Lead Flow Scenarios.docx, Attribution Requirements and Questions Oct 2025.docx, Attribution Questions from Marketing (1).docx, Lead Flow Requirements from Mktg - LoB.docx, For nov 18 mtg_SFDC Lead Flow_questions.pptx, Unified Pipeline 2026.pptx). Do NOT cover the "Territory Routing/" or "New Account Flow Updates/" subfolders — they are separate topics. Capture: the lead lifecycle/flow stages and routing logic, lead source & attribution model requirements (first-touch/multi-touch, campaign attribution, Products of Interest), open marketing questions, the Unified Pipeline 2026 vision, and Line-of-Business (LoB) specific lead requirements.`,
  },
  {
    file: '03_sales-marketing-territory-routing.md',
    title: 'Sales & Marketing — Territory Routing',
    scopes: ['Sales and Marketing/Territory Routing'],
    images: [
      `${SRC}/Sales and Marketing/Territory Routing/Territory Assignment - Updated.pdf`,
      `${SRC}/Sales and Marketing/Territory Routing/Archive/SF_TerritoryRouting.jpg`,
    ],
    brief: `Territory assignment/routing design. Read Territory Assignment Process.docx, the Territory Assignment - Updated.pdf (a routing diagram — read with vision), FortraTerritories2026_18_02.xlsx (the territory definitions — capture the dimensions/columns and how territories are defined: geo, segment, product, named accounts), and the Archive SF_TerritoryRouting diagram (jpg/vsdx/drawio). Capture the exact routing rules, ownership assignment logic, region breakdown, and how this maps to Salesforce Territory Management / assignment rules.`,
  },
  {
    file: '04_sales-marketing-new-account-duns-flow.md',
    title: 'Sales & Marketing — New Account & DUNS Flow',
    scopes: ['Sales and Marketing/New Account Flow Updates'],
    images: [
      `${SRC}/Sales and Marketing/New Account Flow Updates/SalesInquiryDUNSProposedChanges.pdf`,
    ],
    brief: `The proposed new-account / Sales Inquiry / DUNS-matching flow changes. Read the SalesInquiryDUNSProposedChanges.pdf diagram with vision (primary source), plus the .drawio/.vsdx extracted text. Capture: the as-is vs proposed flow, DUNS/D&B dedup & account-matching logic, decision points, what changes, and the Salesforce objects/automation involved (Inquiry, Lead, Account).`,
  },
  {
    file: '05_channel-partner-portal-and-deal-registration.md',
    title: 'Channel — Partner Portal, Deal Registration, Partner Types & Access',
    scopes: ['Channel'],
    note: 'top-level Channel files only; exclude Meeting 60, Partner Discounts Data Lists, Content Examples subfolders',
    images: [],
    brief: `Cover the TOP-LEVEL "Channel/" files ONLY (NOT the Meeting 60, Partner Discounts Data Lists, or Content Examples subfolders — those are separate topics). Files: Channel_PartnerPortalRequirements (2).xlsx, Field Mapping for SFDC Partner Portal Deal Registration Form (copy).xlsx, Access by Partner Type.xlsx, Partner Types_Salesforce Requirements_8.27.2025.xlsx, Partner KPI Metrics.docx, Partner Billing Scenarios.docx, NORAM Partner list.xlsx, Cyber CAM Territories by Region(June 2025).csv, Channel Bookings & DR Report 2025.xlsx, Channel Dashboard - Apr '25.xlsx. Capture: partner portal experience requirements, the deal-registration form field mapping (field-by-field table), partner type taxonomy and the access/permission matrix by partner type, partner KPI metrics, CAM territory coverage, and the channel reporting/dashboard structure. For Partner Billing Scenarios.docx give a concise summary and cross-reference the Partner Pricing Models doc.`,
  },
  {
    file: '06_channel-partner-onboarding-management.md',
    title: 'Channel — Partner Onboarding / Offboarding & Management (Meeting #60)',
    scopes: ['Channel/Meeting 60'],
    images: [],
    brief: `The 6/17/25 Channel Partner Management Salesforce call. Read the meeting docx + pptx + the onboarding & offboarding checklists (xlsx) + Plan-Main_PARTNER.xlsx. Capture: the partner lifecycle (onboarding and offboarding steps as checklists), decisions and action items from the call, the SF requirements discussed for partner management, and the project plan/milestones.`,
  },
  {
    file: '07_channel-partner-discounts-data.md',
    title: 'Channel — Partner Discounts Data',
    scopes: ['Channel/Partner Discounts Data Lists'],
    images: [],
    brief: `Partner discount data lists migrated from D365 to Salesforce (Cyber & Tech). Read all xlsx incl. Archive. Capture: the discount data MODEL (columns/fields: brand, partner, product/SKU scope, discount %, tier, effective dating, currency), how partner discounts are structured, the difference between the WIP template and the production/UAT load files, and how this feeds RLM partner pricing. Note row counts and brand coverage.`,
  },
  {
    file: '08_channel-brand-and-content-collateral.md',
    title: 'Channel — Brand Guidelines & Partner Content/Collateral',
    scopes: ['Channel/Content Examples'],
    images: [
      `${SRC}/Channel/fortra-brand-guidelines.pdf`,
      `${SRC}/Channel/Content Examples/partner-program-overview-brochure (1).pdf`,
      `${SRC}/Channel/Content Examples/fta-corp-cybersecurity-portfolio-ds.pdf`,
      `${SRC}/Channel/Content Examples/Fortra Data Protection Personas Guide.pdf`,
    ],
    brief: `Also cover Channel/fortra-brand-guidelines.pdf (top-level). This is marketing/brand collateral and partner-program content examples. Read the PDFs (vision OK for the brand guide; the .txt extracts are fine for the datasheets). Capture: Fortra brand guidelines essentials (logo/color/voice rules at a high level), the Fortra Protect Partner Program structure (tiers, benefits, requirements), the cybersecurity portfolio/product line overview, buyer personas, and an inventory of the content examples (with what each is). Keep this concise — it is reference/collateral, not transactional config.`,
  },
  {
    file: '09_products-catalog-hierarchy-and-skus.md',
    title: 'Pricing & Products — Product Catalog, Hierarchy & SKUs',
    scopes: ['Pricing and Products/Product Hierarchy'],
    extraFiles: [
      'Pricing and Products/Cyber Products.xlsx',
      'Pricing and Products/Tech Products.xlsx',
      'Pricing and Products/ServicesProductDescriptions.xlsx',
      'Pricing and Products/Tech_GlobalscapeSKUsfromSalesforce_BSS-22410-2025-06-04-10-45-55.xlsx',
      'Pricing and Products/D365 SKU Tiered Pricing.xlsx',
    ],
    images: [],
    brief: `Cover these EXTRACTED files specifically (read each .txt):
  - Pricing and Products/Cyber Products.xlsx
  - Pricing and Products/Tech Products.xlsx
  - Pricing and Products/ServicesProductDescriptions.xlsx
  - Pricing and Products/Tech_GlobalscapeSKUsfromSalesforce_BSS-22410-2025-06-04-10-45-55.xlsx
  - Pricing and Products/D365 SKU Tiered Pricing.xlsx
  - everything under Pricing and Products/Product Hierarchy/ (Services SKUs D365.xlsx)
Capture: the product catalog structure for Cyber vs Tech vs Services, the product hierarchy levels (Unit/Solution Group/Solution Category/Solution/Feature/SKU and their aliases), SKU naming/coding conventions, the Globalscape SKU set, services product descriptions, and how D365 tiered-pricing SKUs map over. Tables of representative SKUs + their attributes. Do NOT cover the Approval Matrix, Quoting Rules, Globalscape Fields, or Pricebooks subfolders (separate topics).`,
  },
  {
    file: '10_pricing-strategy-and-approval-matrix.md',
    title: 'Pricing & Products — Pricing Strategy & Approval Matrices',
    scopes: ['Pricing and Products/Approval Matrix'],
    extraFiles: [
      'Pricing and Products/Cyber_Pricing Strategy_Project Summary as of 5.29.25.pptx',
      'Pricing and Products/QuotingBillingImportantFields.xlsx',
      'Pricing and Products/BSI_Coastal 07 14 2025 Next Steps.docx',
    ],
    images: [],
    brief: `Cover: Pricing and Products/Cyber_Pricing Strategy_Project Summary as of 5.29.25.pptx, QuotingBillingImportantFields.xlsx, BSI_Coastal 07 14 2025 Next Steps.docx, and everything under Pricing and Products/Approval Matrix/ (Cyber & Tech Sales Approval Matrix 2024 Draft xlsx). Capture: the Cyber pricing strategy project summary (goals, decisions, status), the discount-approval matrix (who approves what discount threshold — give the threshold→approver tables for both Cyber and Tech), the important quoting/billing fields list, and the BSI/Coastal next-steps action items. Note the Approval Matrix also appears under Quotes and Billing/Quote Approval/ — focus here on the matrix CONTENT; the Deal Desk process doc owns the approval workflow.`,
  },
  {
    file: '11_quoting-rules-d365-experlogix.md',
    title: 'Pricing & Products — Quoting Rules for D365 (Experlogix, Bundles, Hardware)',
    scopes: ['Pricing and Products/Quoting Rules for D365'],
    images: [],
    brief: `Legacy D365 quoting/configuration rules to be re-implemented in Salesforce RCA product rules. Read ExperlogixRules 2.xlsx (+ Previous version/ExperlogixRules.xlsx), Bundle Items D365.xlsx, HardwareOptionSets.xlsx/.csv, RequiredItemsSetUpInD365.xlsx, Fortra Hardware Object Metadata.xlsx, Pricing Notes.docx. Capture: the Experlogix configuration rule logic (constraints, option sets, required/included items, bundle compositions), hardware option sets and metadata, and pricing notes — and how these translate to RCA Product Configuration Rules / bundles / product components. Give concrete rule examples and the hardware object field metadata.`,
  },
  {
    file: '12_globalscape-rlm-field-mappings.md',
    title: 'Pricing & Products — Globalscape ↔ RLM Field Mappings',
    scopes: ['Pricing and Products/Globalscape Product & Pricing Fields'],
    images: [],
    brief: `Globalscape product/pricing data mapped to Salesforce RLM (Revenue Lifecycle Management) objects. Read the *_RLM_Mapped.xlsx files (Contract, CPQ, CPQ_Supporting, Standard_Objects, Order field metadata) and GSPricingExampleScripts.sql. Capture: the field-by-field mapping tables (source Globalscape field → target RLM object.field, data type, notes) for Contract, Order, CPQ, and Standard objects, and what the example SQL pricing scripts compute. This is a critical migration field-map — preserve the mappings in tables.`,
  },
  {
    file: '13_legacy-pricebooks-inventory.md',
    title: 'Pricing & Products — Legacy Pricebooks (SharePoint) Inventory',
    scopes: ['Pricing and Products/Pricebooks From SharePoint'],
    images: [],
    brief: `An inventory of legacy per-brand pricebooks exported from SharePoint. IMPORTANT: ~30 of these .xlsx are PASSWORD-PROTECTED/encrypted and could not be extracted (their .txt says "[ENCRYPTED]"). Only a few PDFs are readable: GoAnywhere Pricing Sheet USD-2025.pdf, GoAnywhere Pricing Sheet AUD-2025.pdf, and Alert Logic global-price-list. Produce: (1) a complete INVENTORY TABLE of all pricebook files (brand, year/revision, format, locked/readable status) so the team knows what exists and what needs a password; (2) for the readable GoAnywhere & Alert Logic price lists, capture the product/price structure (tiers, editions, currency). Clearly flag the encrypted ones as a data gap requiring the password.`,
  },
  {
    file: '14_quotes-billing-partner-pricing-models.md',
    title: 'Quotes & Billing — Partner Pricing Models & Billing Scenarios',
    scopes: [],
    extraFiles: [
      'Quotes and Billing/PartnerPricingModels.docx',
      'Quotes and Billing/PartnerPricingModelSummary.docx',
      'Quotes and Billing/HardwareGrouping.docx',
      'Quotes and Billing/PowerBranchingSalesforce.docx',
      'Channel/Partner Billing Scenarios.docx',
    ],
    images: [
      `${SRC}/Quotes and Billing/Meridian Quote Example - MSP with MSP End Users.pdf`,
      `${SRC}/Quotes and Billing/Meridian Invoice Example - MSP with MSP End Users.pdf`,
    ],
    brief: `Read these specific extracted files: Quotes and Billing/PartnerPricingModels.docx, PartnerPricingModelSummary.docx, HardwareGrouping.docx, PowerBranchingSalesforce.docx, and Channel/Partner Billing Scenarios.docx. Also read the two Meridian PDF examples (Quote and Invoice, MSP-with-MSP-end-users — read the .txt extracts; consult original PDF if layout unclear). Capture: every partner pricing model (e.g., MSRP-discount, cost-plus, MSP/MSSP, distributor 2-tier, reseller) with how price flows and who-pays-what; the billing scenarios (esp. MSP with MSP end users, partner-of-record billing); hardware grouping logic; and PowerBranching (PowerOrderSplitting) line-splitting behavior in Salesforce. Use the Meridian examples to ground the MSP scenario with concrete numbers.`,
  },
  {
    file: '15_quotes-billing-export-controls-and-misc.md',
    title: 'Quotes & Billing — Export Controls & Operational Data',
    scopes: [],
    extraFiles: [
      'Quotes and Billing/Export Controls Discovery.docx',
      'Quotes and Billing/Outflank ARR Apr25 v1.xlsx',
      'Quotes and Billing/Running Master Billings File Q2 (Apr\'25) - Working Version.xlsx',
      'QuotesToReprice.xlsx',
    ],
    images: [],
    brief: `Read: Quotes and Billing/Export Controls Discovery.docx, Outflank ARR Apr25 v1.xlsx, Running Master Billings File Q2 (Apr'25) - Working Version.xlsx, and the root-level QuotesToReprice.xlsx (at ${EXTRACT}/../.. NO — it is at ${EXTRACT}/QuotesToReprice.xlsx? Actually it is at the discovery root, extracted to ${EXTRACT}/QuotesToReprice.xlsx.txt — verify with find). Capture: export-control / trade-compliance requirements (ECCN, denied-party screening, country restrictions, license requirements) and how they gate quoting/ordering; the Outflank ARR structure; the master billings file columns and what it tracks; and the QuotesToReprice list (which quotes need repricing and why — connect to the repricing issues in the org). Flag export controls as a compliance requirement for the SF implementation.`,
  },
  {
    file: '16_quote-approval-deal-desk.md',
    title: 'Quotes & Billing — Quote Approval & Deal Desk',
    scopes: ['Quotes and Billing/Quote Approval'],
    images: [
      `${EMB}/DealDeskOptions/image1.png`,
    ],
    brief: `The quote approval workflow and Deal Desk. Read all files under Quotes and Billing/Quote Approval/ (Deal Desk Options.docx — its content is in an embedded image, READ ${EMB}/DealDeskOptions/image1.png with vision; Deal Desk Approvers.xlsx; Approval Exception Form.xlsx; Quote Approval Teams.xlsx; Tech Sales Approval Matrix 2024_Draft.xlsx; Sales Approval Matrix 2024_Draft.xlsx). Capture: the Deal Desk options/process flow (from the image), the approver roster and approval teams, the exception-request form fields, and the approval-matrix thresholds. This doc OWNS the approval PROCESS/workflow; cross-reference doc 10 for the matrix thresholds to avoid duplication (summarize, don't fully re-table if identical).`,
  },
  {
    file: '17_d365-terms-and-conditions-rules.md',
    title: 'Quotes & Billing — D365 Terms & Conditions Rules',
    scopes: ['Quotes and Billing/D365 TandC Rules'],
    images: [],
    brief: `Legacy D365 rules that auto-applied Terms & Conditions text to Quotes and Invoices. Read QUOTE Terms and Condition Rules.docx and INVOICE Terms and Condition Rules.docx. Capture: each rule (the condition/trigger → the T&C clause/text applied), grouped by quote vs invoice, and note how these should be re-implemented in Salesforce (e.g., as conditional terms on quote/order documents, DocGen template logic). Preserve the actual rule conditions.`,
  },
  {
    file: '18_contracts-and-legal-agreements.md',
    title: 'Contracts & Legal — Agreements, Schedules & NDAs',
    scopes: ['Contracts and Legal Documents'],
    images: [],
    brief: `The legal agreement templates underpinning Fortra deals. Read all docx. Capture: (1) an INVENTORY TABLE of every agreement (name, type — MSA/EULA/Eval/NDA/DPA/Solution Schedule, brand/scope, date/version); (2) the master agreement architecture — how the Master Solutions Agreement (MSA) relates to Solution-Specific Schedules (per brand: Core/Cobalt/OST, Digital Defense/Beyond Security, Agari/Phishlabs/Clearswift, Terranova, Alert Logic, Tripwire/DG schedules) and Cloud/Managed/Professional Services schedules; (3) key recurring terms relevant to quoting/billing/contracts in Salesforce (term length, renewal, auto-renew, payment terms, data processing/DPA obligations, eval period, export/end-use statements). Summarize each schedule's purpose. Do NOT reproduce full legal text — extract the structure and the operationally-relevant terms.`,
  },
  {
    file: '19_support-portal-kb.md',
    title: 'Support & Portal — Globalscape Knowledge Base',
    scopes: ['Support and Portal'],
    images: [],
    brief: `The Globalscape support knowledge base export. Read Fortra GlobalScape InstantKB_Articles.csv and Globalscape KB Article.xlsx (the 906MB kb_globalscape_com....zip is a full HTML KB dump — NOT extracted, note it as available-on-request). Capture: the KB article data model (columns: id, title, category/product, body, dates, status), article volume, product/category breakdown, and how this KB maps to the Fortra Support Portal (Solution Category / Feature levels). Give representative article examples.`,
  },
  {
    file: '20_bsi-d365-ssrs-reports.md',
    title: 'BSI Discovery — D365 SSRS Reports (Quote/Order/Invoice/Credit)',
    scopes: ['BSI Discovery Info/D365 SSRS reports'],
    images: [],
    brief: `Legacy D365 SSRS (.rdl) report definitions for customer-facing documents. Read all 6 .rdl extracts (QuoteDetail, QuoteSummary, OrderConfirmation, InvoiceSummary, InvoiceDetail, CreditSummary). The extracts contain [QUERY] SQL CommandText and [FIELDS] lists. Capture: for each report — its purpose, the data source query (summarize the SQL/tables joined), and the field/column layout. This documents what the legacy quote/order/invoice/credit DOCUMENTS contained, which informs the Salesforce DocGen / Workday invoice template requirements. Preserve field lists in tables.`,
  },
  {
    file: '21_bsi-powerbi-reports-and-dataflows.md',
    title: 'BSI Discovery — Power BI Reports, Dataflows & Lineages',
    scopes: ['BSI Discovery Info/Reports'],
    images: [
      `${SRC}/BSI Discovery Info/Reports/Customer Engagement Reports/Lineages/CE Customer Engagement Report Lineage.png`,
      `${SRC}/BSI Discovery Info/Reports/Customer Engagement Reports/Lineages/CE Services Delivery lineage.png`,
      `${SRC}/BSI Discovery Info/Reports/Customer Engagement Reports/Lineages/CE Utilisation lineage.png`,
    ],
    brief: `Power BI reporting for Customer Engagement (Services) and Finance. The .pbix files are BINARY (not extracted) — note them. Read the Dataflows .json (these are Power Query / dataflow definitions — capture the source systems: D365, SharePoint, Tripwire, CustomerVoice, Alert Logic, and the entities/queries), the Lineages .png (READ with vision — they show data-source→dataflow→dataset→report lineage), and Notes on Services Project Hours.docx. Capture: the report inventory (CE Utilisation, CE Customer Engagement, CE Services Delivery, Services Project Hours, Adapted Billings), each report's data sources and lineage, and how Services/utilisation and billings reporting is structured. This informs Salesforce/Workday reporting migration.`,
  },
  {
    file: '22_bsi-campaign-marketing-product-uat.md',
    title: 'BSI Discovery — Campaign / Marketing Product UAT',
    scopes: ['BSI Discovery Info/UATScreenshots'],
    images: [
      `${SRC}/BSI Discovery Info/UATScreenshots/Marketing Product Field on Campaign.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Marketing Product Field on Campaign Creation Pop Up.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Marketing Product to Product of Interest.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Products of Interest New Button.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Products of Interest New Button 2.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Products of Interest Field and List Not Matching.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Unit Field Populating Based on POI Field.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Related Tab on Campaign Object.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Related Opportunities on Campaign Object.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Related Tab on Inquiry Object.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Activity Section on Campaign Object.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/Planning Section on Campaign Object.png`,
      `${SRC}/BSI Discovery Info/UATScreenshots/View All Campaign Members Link.png`,
    ],
    brief: `These are UAT screenshots (all .png — READ EACH with vision; there is no text extract). They document the Campaign object's Marketing Product / Products of Interest (POI) feature in Salesforce UAT. Capture: how Marketing Product is set on a Campaign (field + creation pop-up), how it links to Products of Interest on the Inquiry/Lead, the POI "New" button behavior, the Unit field auto-populating from POI, the Campaign related tabs (Opportunities, Inquiry) and Activity/Planning sections, the "View All Campaign Members" link, and the noted BUG "Products of Interest Field and List Not Matching." Reconstruct the feature design and list the UAT observations/issues from the screenshots.`,
  },
  {
    file: '23_bsi-sample-quotes-and-invoices.md',
    title: 'BSI Discovery — Sample Quote & Invoice PDFs',
    scopes: ['BSI Discovery Info/SamplePDFs'],
    images: [],
    brief: `13 sample quote (Q-...) and invoice (V0...) PDFs plus InvoiceQuoteDescriptions.txt which labels each. Read InvoiceQuoteDescriptions.txt FIRST (it explains what each PDF demonstrates), then read each PDF's .txt extract. Capture: a table mapping each invoice↔quote pair to the SCENARIO it demonstrates (new subscription with partner, Spain invoice sequencing, hourly services, renewal with partner, large line-item counts, multiple bundles, license-redistribution partner, etc.), and the COMMON document STRUCTURE/fields of a Fortra quote and invoice (header fields, line columns, totals, terms). These ground the DocGen/Workday document requirements. Note the Spain unique-invoice-ID and multi-bundle/large-line-count edge cases.`,
  },
  {
    file: '24_bsi-tripwire-te-license.md',
    title: 'BSI Discovery — Tripwire TE License Management (Interim Phase)',
    scopes: ['BSI Discovery Info/TripwireInterimPhaseWork'],
    images: [],
    brief: `Tripwire interim-phase work on TE (Tripwire Enterprise) License management and support/maintenance. Read the 3 PDFs (.txt extracts): Tripwire Salesforce Required Fields for Support-Download Maintenance, TE License — LAC Research Notes, TE License — User Configurable TE License Management. Capture: the Salesforce fields required for Tripwire support/download/maintenance entitlement, the LAC (License/Asset) research findings, the user-configurable TE license management design, and how Tripwire licensing/entitlements are represented in Salesforce during the interim phase before full RCA.`,
  },
  {
    file: '25_bsi-d365-entity-junctions-and-roles.md',
    title: 'BSI Discovery — D365 Entity Junctions & UAT Role Changes',
    scopes: [],
    extraFiles: [
      'BSI Discovery Info/D365EntityJunctions.xlsx',
      'BSI Discovery Info/FortraUATRoleChanges.xlsx',
    ],
    brief: `Read BSI Discovery Info/D365EntityJunctions.xlsx and BSI Discovery Info/FortraUATRoleChanges.xlsx (top-level of BSI Discovery Info — find them). Capture: (1) the D365 entity junction/relationship map (which entities relate via junction tables — N:N relationships — and how they map to Salesforce objects/junctions); (2) the FortraUAT role changes (security role / profile / permission-set changes for UAT — who gets what access). These inform data-model migration and the UAT security model. Preserve the junction relationships and role-change rows in tables.`,
  },
  {
    file: '26_cross-team-payment-deposit-process.md',
    title: 'Cross-Team — Current Payment & Deposit Process',
    scopes: ['Cross Team Meetings'],
    images: [],
    brief: `The current (as-is) payment & deposit process, from a cross-team meeting. Read Current Payment Deposit Process.docx. (A meeting-recording .mp4 exists but has no transcript — note it.) Capture: the end-to-end as-is flow for customer payments and deposits (who/what systems handle receipt, deposit, application to invoices, reconciliation), pain points, and implications for the Salesforce→Workday order-to-cash design.`,
  },
]

// ---------- Phase 1: synthesize topics in parallel ----------
phase('Synthesize')
log(`Synthesizing ${TOPICS.length} discovery KB documents from the extracted corpus...`)

const results = await parallel(
  TOPICS.map(t => () =>
    agent(topicPrompt(t), {
      label: t.file.replace(/\.md$/, ''),
      phase: 'Synthesize',
      agentType: 'general-purpose',
      schema: TOPIC_SCHEMA,
    }).then(r => r ? { ...r, _topic: t.file } : null)
  )
)

const ok = results.filter(Boolean)
log(`Synthesized ${ok.length}/${TOPICS.length} topic docs.`)

// ---------- Phase 2: index + cross-cutting overview ----------
phase('IndexOverview')

const indexInput = ok.map(r =>
  `- FILE: ${r.file}\n  TITLE: ${r.title}\n  HOOK: ${r.oneLineHook}\n  TOPICS: ${(r.keyTopics || []).join('; ')}\n  OPEN_Q: ${(r.openQuestions || []).join('; ')}\n  NOT_EXTRACTABLE: ${(r.notExtractable || []).join('; ')}`
).join('\n\n')

const indexResult = await agent(
  `You are finalizing the Fortra Discovery Documentation knowledge base. ${TOPICS.length} topic documents have been written to ${OUT}/ (filenames 02..26). Here is the metadata returned by each topic agent:

${indexInput}

You also have:
- The extraction manifest at ${MANIFEST} (status/chars/ext/relpath/note for all 219 source files — read it with Bash to know exactly what exists, what was extracted, what is encrypted/binary).
- The actual written docs in ${OUT}/ (Read any you need to write accurate summaries).
- The existing repo KB ${'/Users/liamjeong/Documents/Code/Fortra/FORTRA_KNOWLEDGE_BASE.md'} (the Confluence DESIGN synthesis) — this discovery KB complements it.

DO TWO THINGS:

1) Write ${OUT}/00_INDEX.md — a master index:
   - Short intro: what this KB is (synthesis of the "Fortra Discovery Documentation" business-discovery corpus, 219 source files), how it was built (text extracted to Data/discovery-extract/, then synthesized), and its relationship to FORTRA_KNOWLEDGE_BASE.md.
   - A table of all docs grouped by category (Sales & Marketing, Channel, Pricing & Products, Quotes & Billing, Contracts & Legal, Support, BSI Discovery, Cross-Team) with clickable links [title](file.md) and the one-line hook.
   - A "Source corpus & extraction status" section: counts by file type, the extraction summary (165 extracted / 30 encrypted / 24 binary), and an explicit list of the KNOWN GAPS (the 30 encrypted pricebooks needing a password; the binary .pbix/.mp4; the 906MB KB zip) so the gaps are discoverable.
   - A consolidated "Open questions across the corpus" list (dedup the per-topic open questions).

2) Write ${OUT}/01_OVERVIEW.md — a cross-cutting executive synthesis (the "read this first" doc):
   - The big picture connecting ALL topics: the D365/Tripwire/Globalscape → Salesforce RCA + Workday + MuleSoft program, told through the discovery lens.
   - Per-domain synthesis (lead-to-cash: marketing/lead flow → territory routing → quoting → approval/deal desk → pricing & partner discounts → order → billing/Workday → contracts → support/reporting), pulling the most important concrete facts from the topic docs.
   - The product hierarchy & SKU model, partner/channel model, pricing & approval model, billing/document model, and reporting model — each in a tight section with the key facts.
   - The most important open questions and data gaps that block the SF implementation.
   Make it genuinely useful as the single orientation document for someone new to the Fortra discovery context. Use clickable links to the detailed topic docs.

Return a short plain-text confirmation of both files written, with their absolute paths and a one-line description of each.`,
  { label: 'index+overview', phase: 'IndexOverview', agentType: 'general-purpose' }
)

// ---------- Phase 3: completeness audit ----------
phase('Audit')

const audit = await agent(
  `You are the completeness critic for the Fortra Discovery KB just written to ${OUT}/ (files 00_INDEX.md, 01_OVERVIEW.md, 02..26 topic docs).

Your job: find COVERAGE GAPS — extracted source material that did NOT make it into any KB doc, or topic docs that are thin relative to their sources.

METHOD:
1. Read the manifest ${MANIFEST} with Bash. Build the set of source files with status 'ok' (successfully extracted text). These MUST each be represented in some KB doc. (Files with status 'encrypted'/'skip-binary' are known gaps — do NOT flag those as missing, but DO confirm the index lists them as gaps.)
2. List ${OUT}/ and grep the written docs' "## Sources" sections to see which source files are cited.
3. For each top-level source category, sanity-check that a corresponding KB doc exists and substantively covers it (spot-check 3-4 docs by reading them and comparing to their extracted .txt sources for major omissions — e.g., a whole spreadsheet sheet or document section ignored).
4. Also verify 00_INDEX.md and 01_OVERVIEW.md exist and are non-trivial.

Return a structured report:
{
  "filesWritten": <count of .md in OUT>,
  "extractedSourcesTotal": <count of status=ok files>,
  "uncoveredSources": [ "relpath", ... ],   // ok-status files not cited/covered anywhere
  "thinDocs": [ {"file":"..","why":".."} ], // docs missing major source content
  "indexGapsListed": true/false,            // does 00_INDEX list the encrypted/binary gaps?
  "verdict": "complete" | "minor-gaps" | "major-gaps",
  "recommendedFixes": [ "..." ]
}`,
  {
    label: 'completeness-audit',
    phase: 'Audit',
    agentType: 'general-purpose',
    schema: {
      type: 'object',
      additionalProperties: true,
      required: ['filesWritten', 'uncoveredSources', 'verdict', 'recommendedFixes'],
      properties: {
        filesWritten: { type: 'number' },
        extractedSourcesTotal: { type: 'number' },
        uncoveredSources: { type: 'array', items: { type: 'string' } },
        thinDocs: { type: 'array', items: { type: 'object', additionalProperties: true } },
        indexGapsListed: { type: 'boolean' },
        verdict: { type: 'string' },
        recommendedFixes: { type: 'array', items: { type: 'string' } },
      },
    },
  }
)

return {
  topicsRequested: TOPICS.length,
  topicsWritten: ok.length,
  failedTopics: TOPICS.filter(t => !ok.find(r => r._topic === t.file)).map(t => t.file),
  indexOverview: indexResult,
  audit,
}
