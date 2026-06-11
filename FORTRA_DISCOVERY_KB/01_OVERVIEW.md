# Fortra Discovery — Executive Overview (Read This First)

> The single orientation document for the **business / as-is** side of Fortra's CRM transformation. It connects every topic in this Discovery KB. For the target-state architecture, pair it with the root `FORTRA_KNOWLEDGE_BASE.md` (the Confluence design synthesis). For the master catalog and gaps, see [00_INDEX.md](00_INDEX.md).

---

## 1. The big picture: why this program exists

Fortra grew by acquisition. Today its lead-to-cash runs on a patchwork of legacy systems, brand by brand:

- **CRM / quoting:** Microsoft **Dynamics 365** (the "hs_" schema; with **Experlogix** CPQ + **HubSpot** for marketing) is the main estate, alongside a separate **Tripwire Salesforce** org and a **Globalscape Salesforce CPQ** org (the `SBQQ__` Steelbrick package).
- **Billing / finance:** **Great Plains (GP)** for the D365 core, **Zuora** + a *separate* GP for Tripwire (double-posted), **NetSuite** for Alert Logic, **OrdersX/CyberSource** for Globalscape.
- **Reporting:** a **Power BI** estate over D365, Tripwire SF, Globalscape SF, SharePoint/ADP and Customer Voice; plus shadow Finance workbooks (Outflank ARR, Master Billings) and **Essbase/BOD** feeds.

The program replaces this with **one Salesforce org running RLM/RCA (Revenue Lifecycle / Cloud) for quote-to-order**, **MuleSoft** as the integration layer, and **Workday** as the financial back end (invoicing, credits, AR, treasury). **The target SFDC go-live is March 2026.**

The discovery corpus in this KB is the *requirements and as-is reality* feeding that build. The end-to-end flow it must reproduce:

```
Marketing / HubSpot
   → Inquiry (Lead)  → POI / Unit derivation
   → Territory routing (AE / BDR / CAM)  → Account (D&B/DUNS dedup + hierarchy)
   → Opportunity  → Quote (RLM, configured products, partner pricing)
   → Deal Desk / Approval matrix
   → Order  → MuleSoft  → Workday (Invoice / Credit, AR, treasury)
   → Contracts/DocGen (MSA + Schedule + Order Form, brand-driven T&C)
   → Support portal + Knowledge + Reporting (RCA + Workday native)
```

Every domain below is a stage of that flow.

---

## 2. Lead-to-cash, domain by domain

### 2.1 Marketing & lead flow → "Inquiry"
The org **renames the standard Lead to "Inquiry."** A renamed lifecycle (New → MQL → SAL → Working → Qualified → Closed) carries routing/SLA requirements, closed-reason codes, and a **Working auto-status**. Marketing feeds in via **HubSpot → SFDC auto-sync** with **D&B / 6sense** enrichment and a HubSpot iframe; leads carry a **Product of Interest (POI)** multi-select that should derive the **Unit** (e.g. Brand Protection ⇒ Cyber).

The headline strategy shift is **Unified Pipeline 2026 ("One Team / One Number")**: move from **first-touch to multi-touch (linear / even-distribution) attribution** across a *single* Fortra journey (not per-brand), reframing KPIs as a "revenue factory." Cyber pipeline target: **$175.2M (2025) → ~$246–250M (2026)**, 10% ALE growth, 4× coverage.
→ [02 Lead Flow & Attribution](02_sales-marketing-lead-flow-and-attribution.md) · [22 Campaign / POI UAT](22_bsi-campaign-marketing-product-uat.md)

### 2.2 Territory routing & assignment
Inquiries route through a **per-product territory match hierarchy**: *Named Account > Industry > Country > State+Zip > State*, nested by **Solution Category > Solution Group > Unit**. The driver is a **~2,138-row territory master** (Unit/Solution Group/Solution Category/Industry/State/Country/Zip dimensions) with ZIP-level patches. AE/BDR ownership is gated by a **PCTA ("Assigned to AE")** flag; partner deals route to a **CAM (Channel Account Manager)** via a geo lookup. Account resolution depends on **D&B + Domestic/Global HQ hierarchy**.
→ [03 Territory Routing](03_sales-marketing-territory-routing.md) · [04 New Account / DUNS Flow](04_sales-marketing-new-account-duns-flow.md)

### 2.3 New Account & D&B/DUNS dedup
Two intake paths: **(A)** automated inbound Sales Inquiry from HubSpot form submissions, and **(B)** a manual **New Account Wizard** (min-required = (Name+Domain+State+Country) OR DUNS). Both run **D&B/DUNS match-or-create** across a three-level hierarchy (entity / Domestic Ultimate / Global Ultimate DUNS).
→ [04 New Account / DUNS Flow](04_sales-marketing-new-account-duns-flow.md)

### 2.4 Channel: partners, onboarding, discounts
Fortra runs the **Fortra Protect Partner Program** (Silver / Gold / Diamond + Distributor + MSP/MSSP + Strategic Alliance/OEM), with **PRM = the SFDC partner portal**, a field-by-field **Deal Registration** form, and a **partner-type access matrix**. VAR margins: **7%/12% Fortra-originated, 15%/20% channel-originated, 15% PS discount**; revenue **territories T1/T2/T3**. **CAMs** own onboarding (5-phase: Engage/Educate/Motivate/Support/Manage across 30-60-90-120 days) and offboarding (4-stage, with cancel-and-rebill of quotes/invoices). Customer Operations creates the partner Account on the Partner Program team's executed-agreement notice. There is **no CAM territory-assignment automation today** (greenfield SF requirement).

Partner **discounts** migrate from a D365 53-column source into a **22-column RCA Partner Discount load** model: `Model_Type__c` = **Guaranteed Margin vs Discount**, scoped Unit→Solution Category→Solution Group, across 34 brands, per product type (Software / New Maint / Renewal Maint / Subscription / Service) × Channel- vs Fortra-Originated. These feed **RLM partner pricing at quote time**.
→ [05 Portal & Deal Reg](05_channel-partner-portal-and-deal-registration.md) · [06 Onboarding/Offboarding](06_channel-partner-onboarding-management.md) · [07 Partner Discounts Data](07_channel-partner-discounts-data.md) · [08 Brand & Collateral](08_channel-brand-and-content-collateral.md)

### 2.5 Quoting & pricing
Quotes are configured in **RLM/RCA**. The legacy quoting logic comes from two engines:
- **D365 + Experlogix CPQ** — a rule grammar (LNK/ERR/ALW/EXC/SLK/REQ/MSG with S:/C:/F:/R: tokens), bundle BOMs, required-items, and an `hs_hardware` object → maps to RCA **ProductConfigurationRule**, bundles, and hardware data.
- **Globalscape Salesforce CPQ** (`SBQQ__`) — a Quote/QuoteLine pricing waterfall, an **ALE CASE formula** (`Quote_Line_ALE__c`), and `LookupData`-driven Product Selection Rules → RCA ProductConfigurationRule. All other CPQ-supporting objects retire; NetSuite/Celigo is out of scope.

**Partner pricing** applies the two models: *Guaranteed Margin* (billing-partner-only) vs *Discount* (stacking), with distinct percentage sets for Channel- vs Fortra-Originated deals, currently realized in `SubscriptionPricing74`. **Hardware Grouping** maps a Hardware record 1:1 to a Quote Line Group; **PowerBranching** splits order lines (Order-Line-Only vs Order-Line-and-Hardware).
→ [09 Catalog & SKUs](09_products-catalog-hierarchy-and-skus.md) · [10 Pricing Strategy & Approval](10_pricing-strategy-and-approval-matrix.md) · [11 D365/Experlogix Rules](11_quoting-rules-d365-experlogix.md) · [12 Globalscape→RLM](12_globalscape-rlm-field-mappings.md) · [13 Legacy Pricebooks](13_legacy-pricebooks-inventory.md) · [14 Partner Pricing Models](14_quotes-billing-partner-pricing-models.md)

### 2.6 Approval & Deal Desk
A discount-approval **threshold→approver matrix** governs quoting: New/Upsell — **AE 25%/15%, MD/Director 35%/20%, GM-EVP/CRO 50%, >50% = Deal Desk (CFO/CEO)**; Renewals — Director 10%/$30K, EVP/VP 20%/$100K, CEO-CFO >20%; Legal — LoL 3×/$500K, 5×/$2M. **Deal Desk triggers:** **>50% discount, MYCAP, Displaced ARR/Swap, non-standard legal/terms.** The legacy intake is an **MS-Forms exception form** with a 17-value exception dropdown and per-LOB (Cyber vs Tech) reviewer routing; approved proxies are defined (e.g. CFO → Vicky McCartney).
→ [16 Quote Approval & Deal Desk](16_quote-approval-deal-desk.md) · [10 Approval Matrices](10_pricing-strategy-and-approval-matrix.md)

### 2.7 Export-control gate
Before a quote/order can complete, deals pass **export-control / denied-party screening** (SDN/CSL/OFAC + country export licenses) — a hard compliance gate. Today this is **four separate as-is processes** (Tripwire pre-order, Tripwire quarterly, Offensive Security/ELM, Rest-of-Fortra twice-yearly). **Visual Compliance by Descartes** is under evaluation as the consolidated tool; offensive-security SKUs additionally require an **End-Use Statement** and Chamber-of-Commerce legalization.
→ [15 Export Controls + ARR/Billings](15_quotes-billing-export-controls-and-misc.md) · [18 Contracts & Legal](18_contracts-and-legal-agreements.md)

### 2.8 Order → MuleSoft → Workday (billing)
The Order is the RLM handoff to finance. **MuleSoft** builds the **Order→Workday payload** (carrying only `Order_Id`; Mule reads live data and upserts by Order Id). Workday issues **Invoices and Credits** (legacy D365 modeled all three — Order/Invoice/Credit — as one entity differentiated by `statecode`). The corpus grounds this in **13 real legacy quote/invoice PDFs** (partner Bill-to ≠ Ship-to splits, **Spain country-local sequential invoice IDs**, bundle parent-priced/components-$0 rendering, ELA 47-page-quote-into-1-invoice-line summarization, multi-entity/multi-currency/multi-language branching).
→ [20 D365 SSRS Reports](20_bsi-d365-ssrs-reports.md) · [23 Sample Quotes/Invoices](23_bsi-sample-quotes-and-invoices.md) · [26 Payment & Deposit](26_cross-team-payment-deposit-process.md)

### 2.9 Contracts & document generation
Customer paper is an **MSA + Solution-Specific-Schedule + Order Form** architecture (precedence: **Schedule > MSA > Order Form**, DPA/SCCs override). Legacy D365 auto-inserted T&C/EULA/tax/license-key/service-terms/signature text via **condition→clause rules** (brand-driven EULA/MSA selection across 3 brand groups; legal-entity rules for Fortra Argentina S.R.L. and Fortra Computing Group S.L.U.; License-Key text on new maintenance; a 15-clause Service Terms block gated on services + a Hide-PS-Terms flag). The rebuild target is **conditional DocGen template fragments driven by template-bound DataRaptor extract fields** + a brand→clause Custom Metadata map.
→ [17 D365 T&C Rules](17_d365-terms-and-conditions-rules.md) · [18 Contracts & Legal](18_contracts-and-legal-agreements.md)

### 2.10 Support, licensing & reporting
- **Support portal / Knowledge:** the legacy **Globalscape InstantKB** export = **867 articles** (EFT 661 / CuteFTP 106 / WAFS 35 / DMZ Gateway 12 / Arcus 11), mapping to **Fortra Support Portal Solution Category 2.00 / Feature 4.00**. → [19](19_support-portal-kb.md)
- **Licensing (interim):** **Tripwire TE** on-prem licensing runs in the legacy Tripwire SF org — an **LAC (License Authorization Code)** asset model and an **Issued Product / Configuration / Configured Product** self-serve model, with a stateless `/generate2` X.509 cert endpoint. → [24](24_bsi-tripwire-te-license.md)
- **Reporting:** a Power BI estate (CE Customer Engagement / Services Delivery / Utilisation / Project Hours + Adapted Billings) over multiple CRMs + SharePoint/ADP + Customer Voice, plus the **Outflank ARR model** and **Master Billings** workbook — all to be re-sourced onto **RCA + Workday native** reporting. Legacy **D365 N:N junction entities** and the **FortraUAT role hierarchy** (with Cyber/Tech de-branding consolidation) define the migrated data/security model. → [21](21_bsi-powerbi-reports-and-dataflows.md) · [25](25_bsi-d365-entity-junctions-and-roles.md)

### 2.11 Cash application / treasury
As-is cash-application is fragmented per brand: credit-card (D365 portal → **Stripe** → ACH payout → GP; <$10k self-pay, >$10k manual phone-keyed by Collections), **JP Morgan lockbox** (USD only, CAD written off after FX hold), ACH/wire (12 JPM accounts, ~95% lack invoice info → manual matching), plus Tripwire/Zuora, Alert Logic/NetSuite, Globalscape/OrdersX/CyberSource. Future state: **direct bank feeds + the Workday lockbox connector into Workday**, with **Kyriba replacing Trovata** at treasury.
→ [26 Payment & Deposit Process](26_cross-team-payment-deposit-process.md)

---

## 3. The product hierarchy & SKU model

**Hierarchy:** `Unit (CIA = Cyber / CORE = Tech) → Solution Group → Brand → Product Family → Software Product Family (F4 codes) → SKU`. A **GP Item Class → RCA Product Type** taxonomy (NEW MAINT / RENEW MAIN / SERVICES / SERV SUP / SERV RECUR / SUBS SAAS / CHANGE FEE / OTHER …) classifies every line.

- **Cyber (CIA):** Solution Groups = Infrastructure Protection, Automation, Data Protection, MFT, Email Security. **GoAnywhere MFT = ~2,697 SKUs.**
- **Tech (CORE):** IBM-i heritage (Powertech / Robot / Halcyon / Sequel), HADR50 hardware lineage, **Access Assurance Suite = ~712 SKUs.** Cross/Gov/GSA variants exist.
- **Globalscape EFT** SKU grammar: `GS + product + edition + M&S-term (SX/PX 1–3) + tier (T1–T3) + env (-N/-NP/-DV/-SB)`; was on Salesforce CPQ.
- **PhishLabs tiered pricing** (D365): Financial(assets) / Non-Financial(revenue) / User basis = Base Price + basis × Multiplier + 10% Setup Fee → maps to RCA **CalculationMatrix**. (USD-only — the substrate of the SC-3384 multi-currency defect.)
- **Services:** revised Good/Better/Best taxonomy (Power / GoAnywhere / RPA / Offensive Security / Human Risk Management).
- **Legacy→Fortra rebrand:** PhishLabs/Digital Guardian/Tripwire/Agari/Clearswift/Terranova etc. sunset into solution categories (e.g. Terranova → Human Risk Management, Fortra VM → Vulnerability Management, Phishlabs → Brand Protection). Marc owns the D365→SFDC SKU mapping (brands Done: Terranova/Agari/PhishLabs/Cloud DP/Offensive Security/Power/GoAnywhere/RPA).

> **Caveat:** full SKU universes (Cyber 8,874r / Tech 9,441r / Services 1,224r / Globalscape 15,129r / Bundles 3,148r) are **truncated at ~400 rows** in the extract — re-pull from source for migration. See [09](09_products-catalog-hierarchy-and-skus.md), [11](11_quoting-rules-d365-experlogix.md).

---

## 4. Partner / channel model

- **Tiers:** Silver / Gold / Diamond (+ Distributor, MSP/MSSP, Strategic Alliance/OEM), revenue territories **T1/T2/T3** with Gold/Diamond thresholds.
- **Partner types:** Distributor / VAR / MSP / SI / Referral / Tech Alliance / Purchasing Agent (+ International), each with an access/permission matrix and DR-field variations.
- **Pricing models:** **Guaranteed Margin** (the billing partner alone earns the margin) vs **Discount** (discounts stack). Per-product-type %s for Channel- vs Fortra-Originated deals.
- **Billing attribution:** Bill-To / Sell-To / Customer-of-Record with a Selling/Billable-Partner grid; Distributor 2-tier, Reseller VAR, MSP cadences, Referral 45-day commission.
- **CAM coverage:** ~20 sub-regions, CAM-by-territory, US/Canada state-level, plus segment sub-regions (MSP/FinServ/PubSec/AWS).
- **KPIs:** ALE is internal-only; Total Amount Invoiced / ARR are partner-facing. Channel-Originated (CO) vs Fortra-Originated (FO) attribution.

→ [05](05_channel-partner-portal-and-deal-registration.md), [06](06_channel-partner-onboarding-management.md), [07](07_channel-partner-discounts-data.md), [14](14_quotes-billing-partner-pricing-models.md)

---

## 5. Pricing & approval model

- **Strategy:** consolidate the **6,124-SKU** Cyber catalog into a **3-tier Good/Better/Best** (Essentials/Advanced/Elite) deployment-agnostic, user+tier+add-on monetization model.
- **Discount-approval matrix** (2024 Draft, approved 250310, rev 4/11/25):

| Scenario | AE | MD/Director | GM-EVP / CRO | Above |
|----------|----|-------------|--------------|-------|
| New Sale | 25% | 35% | 50% | >50% → Deal Desk |
| Upsell | 15% | 20% | 50% | >50% → Deal Desk |
| Renewals | — | Director 10% / $30K | EVP-VP 20% / $100K | CEO-CFO >20% |
| Legal (LoL) | — | 3× / $500K | 5× / $2M | — |

- **Deal Desk triggers:** **>50% discount · MYCAP · Displaced ARR / Swap · non-standard legal/terms.**
- **COLA:** a default per-brand COLA % drives renewals (rate table lives out of scope; SC-3350 work scopes the COLA renewal universe at **43 records, not 1.2M**).
- **Multi-currency is broken (SC-3384):** non-USD configured pricing falls back to USD values because the tiered/Services/Attribute-Tier-Pricing data is USD-only and FX rates are corrupted (7/11 at 1.0). The legacy pricebooks are themselves multi-currency (USD/EUR/AUD/JPY), so this is both a data and a config problem.

→ [10](10_pricing-strategy-and-approval-matrix.md), [16](16_quote-approval-deal-desk.md), [13](13_legacy-pricebooks-inventory.md)

---

## 6. Billing / document model

- **One legacy entity → split target:** D365 modeled Order = Invoice = Credit as a single entity differentiated by `statecode` (Credit = 3). Target splits this into the **SF Order** (RCA) vs **Workday Invoice/Credit** — which system renders which document is an open question.
- **Document generation:** brand-conditional EULA/legal/cover-letter blocks; **6 legal entities** (decoded `hs_legalentity` GUIDs) × currency × language remittance/bank/tax blocks; localization via `hs_translation` (English/French) + `hs_producttranslation`; **EUR-equivalent** secondary display via `hs_exchangerates`.
- **Quote vs Invoice deltas:** Invoice has no EULA/Signature, a tighter Tax trigger, collapsed one-line Service Terms; tax is "Calculation pending" on quotes, resolved on invoices.
- **Edge cases grounded in real PDFs:** Spain sequential invoice IDs (`S000006265`), bundle parent-priced/$0-components, ELA summarization, hardware/LPAR line grouping, redistribution-partner large identical-line counts, discount shown as absolute $ (not %).

→ [17](17_d365-terms-and-conditions-rules.md), [20](20_bsi-d365-ssrs-reports.md), [23](23_bsi-sample-quotes-and-invoices.md)

---

## 7. Reporting model

- **Legacy Power BI** over D365 (`hsprod` CRM), Tripwire SF, Globalscape SF, SharePoint/ADP, and Customer Voice (`org5ade7db4`) — CE Customer Engagement, Services Delivery, Utilisation, Project Hours, Adapted Billings. Recoverable assets: dataflow JSON, `HSWarehouse` SQL views (ServicesProjectHours/Backlog/Pipeline/PRX/User), lineage PNGs, and a D365-logical-name→report-column field-rename map. **The `.pbix` model internals (DAX, relationships) are not recoverable**, and Finance/billings reporting is a near-total gap.
- **Shadow finance workbooks:** the **Outflank ARR** model (Ending ARR $6.9M, GRR/NRR, ALE, COLA 6.2%) and the **Master Billings** reconciliation (Scooby/CRM/PreScooby sources, GP load-codes, discount-reason taxonomy, ALE/displaced-ARR derivations, Essbase/PowerBI/BOD feeds) — both to be retired once RCA+Workday produce native ARR/ALE/COLA/collections.
- **Migrated data/security model:** the D365 N:N junction inventory (keep/replace/drop dispositions) and the FortraUAT role hierarchy (Cyber/Tech de-branding consolidation) define what carries into SF.

→ [21](21_bsi-powerbi-reports-and-dataflows.md), [15](15_quotes-billing-export-controls-and-misc.md), [25](25_bsi-d365-entity-junctions-and-roles.md)

---

## 8. The questions & gaps that block the SF build

The full, de-duplicated open-question list is in [00_INDEX.md](00_INDEX.md#open-questions-across-the-corpus). The ones most likely to **block** the implementation:

1. **"Sales Inquiry" object identity** — renamed Lead vs distinct custom object? This is foundational for lead flow, territory routing, and DUNS intake. ([02], [03], [04])
2. **Two competing Inquiry-stage models** and the broken **POI → child-record / Unit-derivation** automation must be reconciled before lead routing and marketing attribution can be built. ([02], [22])
3. **Deal Registration target field API names are mostly UNKNOWN**, and there is **no CAM territory-assignment design** — the channel build can't proceed without both. ([05], [06])
4. **NEW MAINT vs RENEW MAIN (and Cross/Gov/GSA) SKU collapse** decision drives the entire Product2 + Subscription model. ([09])
5. **Multi-currency (SC-3384)** — USD-only tiered/Services/ABA data + corrupted FX rates must be fixed as both data and config; the locked multi-currency pricebooks are needed. ([09], [13])
6. **Guaranteed-Margin vs Discount enforcement math** and which percentage set the engine selects — the partner-pricing engine behavior (`SubscriptionPricing74`) is unconfirmed. ([14], [07])
7. **Tax ownership (Workday vs SFDC)** and the **Order↔Invoice↔Credit split** — determines where document generation and tax logic live. ([12], [20], [23])
8. **Deal Desk realization** (native SF Approval Process/Flow+Queues vs external MS-Forms via MuleSoft) and unsettled SLAs/`?`-flagged roles. ([16])
9. **The Workday lockbox connector is missing from integration scope** and treasury (Kyriba) cutover sequencing is undefined. ([26])

### Hard data gaps (need a password, the original binary, or the live system)
- **30 password-locked per-brand pricebooks** — blocks full catalog migration. ([13])
- **5 Power BI `.pbix` binaries** — no DAX/model recoverable; Finance reporting near-total gap. ([21])
- **~906 MB Globalscape KB zip** — HTML bodies/images + InstantKB label tables unrecovered. ([19])
- **Large spreadsheets truncated at ~400 rows** (SKU/bundle/discount universes). ([09], [11], [07])
- **External Google Docs (Product Pricing Rules), the live MS-Forms approval form, and missing export-control source docs.** ([09], [16], [15])
- **146 MB payment-process meeting video** — content beyond the transcript unrecovered. ([26])

---

*Next: browse the [full document catalog](00_INDEX.md#document-catalog) for any domain in depth.*
