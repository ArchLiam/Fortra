# Quotes & Billing — Partner Pricing Models & Billing Scenarios

**Scope:** How Fortra prices and bills deals that involve channel partners on Salesforce Revenue Cloud Advanced (RCA). Covers the two partner pricing models (Guaranteed Margin vs. Discount), the channel billing scenarios (Distributor / Reseller / MSP / Referral, and the MSP-with-MSP-end-users case), hardware-record grouping on quotes, PowerBranching (line splitting) behavior, and the legal/T&C and tax rules that gate the quote and invoice documents. The Meridian quote and invoice examples ground the MSP scenario with real numbers.

**Source dir:** `Fortra Discovery Documentation/Quotes and Billing/` and `Fortra Discovery Documentation/Channel/`

**Related discovery KB docs:** `07_channel-partner-discounts-data.md` (deep dive on the partner discount data list structure and migration template), `06_channel-partner-onboarding-management.md` (partner types/tiers, portal), `10_pricing-strategy-and-approval-matrix.md` (deal-desk approval thresholds). This doc does **not** re-derive the discount-list column model — it reuses it to ground the pricing-model percentages and adds the billing/quoting/splitting behavior.

> **Design-KB connection:** The RCA design synthesis (`FORTRA_KNOWLEDGE_BASE.md`) is the implementation counterpart. Where this doc describes the *business* requirement (e.g. "additional partner margin stacks on the quote"), the RCA pricing procedure / prehooks are where it is realized. Several active-engineering memory notes (SC-3359 partner pricing net-not-applied, SC-3384 multi-currency, SC-3210 line-type, PowerOrderSplitting) are the live implementation of exactly the requirements captured here.

---

## 1. Partner Pricing Models — the two models

Source: [PartnerPricingModels.docx](Fortra Discovery Documentation/Quotes and Billing/PartnerPricingModels.docx), [PartnerPricingModelSummary.docx](Fortra Discovery Documentation/Quotes and Billing/PartnerPricingModelSummary.docx)

Fortra supports **two distinct partner pricing models**. Any single partner account can have **either or both** configured.

| Model | Definition | How additional partners affect price |
|---|---|---|
| **Guaranteed Margin Model** | Each partner involved in the deal has a guaranteed margin, and **all** partner margins are baked into the price of the product. | Additional partner's margin is **stacked on top of** the billing partner's margin. |
| **Discount Model** | **Only the billing partner's** discount is applied to the product. Discounts of any other partners on the deal are **ignored**. | Additional partner's discount is ignored; price uses **only the billing partner's** discount. |

### Product-type percentage dimensions
Both models carry percentages configured per **product type** (the same five categories used by the partner-discount data load — see `07_channel-partner-discounts-data.md`):

1. Software
2. New Maintenance
3. Renewal Maintenance
4. Subscription
5. Professional Service

> Note the discount data list splits each of these five across **two origination columns** — "Channel Originated" and "Fortra Originated" percentage sets (i.e. 10 numeric columns total). The origination set used depends on whether the deal was channel- or Fortra-sourced (see `Deal Origin` picklist below).

### Default-model resolution
- The Partner Manager configures the available model(s) on each **partner account**.
- If **only one** model is enabled → it is automatically the **default**.
- If **both** are enabled → the Partner Manager selects which is the account's default.
- Partner Managers can update/change the configuration at any time.

### Quoting behavior (model selection on a Quote)
1. When a **billing partner** is added to a quote, that partner account's **default** pricing model is automatically set on the quote, and pricing is computed from the percentages configured on that model.
2. If the billing partner supports **both** models, the user may **switch** the model on the quote.
3. When **additional partners** are added, pricing is controlled by **whichever model is currently set on the quote**:
   - **Guaranteed Margin** → additional partner's margin **stacks**.
   - **Discount** → additional partner's discount **ignored** (only billing partner's discount used).

### Worked example matrix
From `PartnerPricingModelSummary.docx` — `List Price` is the catalog price; "Margin"/"Discount" are the configured percentages on the partner account:

| # | Billing Partner | Additional Partner(s) | Model | Pricing Calculation | Note |
|---|---|---|---|---|---|
| 1 | Partner A | None | Discount | `List × A-Discount` | Only billing partner's discount applies |
| 2 | Partner A | Partner B | Discount | `List × A-Discount` | Additional partner's discount **ignored** |
| 3 | Partner A | Partner B | Guaranteed Margin | `List × A-Margin × B-Margin` | Margins **stack** for all partners |
| 4 | Partner A | None | Guaranteed Margin | `List × A-Margin` | Only billing partner's margin applies |
| 5 | Partner B | Partner A | Discount | `List × B-Discount` | Only billing partner's discount applies |
| 6 | Partner B | Partner A | Guaranteed Margin | `List × B-Margin × A-Margin` | Margins **stack** for all partners |

**Key implication for RCA:** the "billing partner" on the quote is the price-driving entity for the Discount model, while Guaranteed Margin is a *multiplicative stack* across every partner on the deal. This is the business rule behind the live `SubscriptionPricing74` / `PartnerDiscount22` waterfall steps and the SC-3359 "partner net not applied on One-Time/Perpetual" defect — see the memory note `project_sc3359_partner_pricing_net_not_applied`.

### Grounding the percentages (from the UAT/prod discount data lists)
Source: [CyberDiscounts_UATSample_041326.xlsx](Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/CyberDiscounts_UATSample_041326.xlsx), [D365 Partner Discounts Data Template (WIP-Lidiane)](Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/Copy of D365 Partner Discounts Data Template-WIP-Lidiane 2026.2.27.xlsx). Each row = one (partner account × model × optional solution scope) combination.

Representative real configured values (Channel-Originated set | Fortra-Originated set, % per product type SW / NewMaint / RenewMaint / Subscription / Service):

| Partner | Type / Tier | Model | Is Default | SW | NewMaint | RenewMaint | Subscription | Service | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Optiv Security | Reseller / Diamond (Direct) | Guaranteed Margin | Y | 20\|12 | 20\|12 | 20\|12 | 20\|12 | 15\|15 | Diamond top-tier reseller margins |
| GuidePoint Security | Reseller / Diamond (Direct) | Guaranteed Margin | Y | 20 | 20 | 20 | 20 | 15 | (Fortra-set mirror = 12/12/12/12/15) |
| BorderLAN | Reseller / Gold (Direct+Indirect) | Guaranteed Margin | Y | 15\|7 | 15\|7 | 15\|7 | 15\|7 | 15\|15 | Gold tier |
| M. Tech Holdings | Distributor | Discount | Y | 40\|5 | 40\|5 | 20\|5 | 40\|5 | 18\|0 | Distributor discount (40% SW) |
| Chillisoft | Distributor | Guaranteed Margin (default) **and** Discount (non-default) | both | GM 10 / Disc 40 | — | RenewMaint 20 (Disc) | Subscription 40 (Disc) | Service 5 (GM) / 15 (Disc) | Same partner carries **both** models; Discount rows further scoped per Solution Group |
| Computer Gross S.P.A. | Distributor | both | Discount=Default | GM 10 / Disc 40 | … | RenewMaint 20 | Subscription 40 | Service 5/15 | Default flips to Discount here |
| Decens OY | MSP (Direct) / MSP tier | Discount | (blank %s in sample) | — | — | — | — | — | Scoped to solution `Human Risk Management` / `Terranova` |
| SharkmanSix LLC | MSP (Direct) / MSP tier | Discount | Y | 0 | 0 | 0 | 25 | 10 | **Subscription-only** discount (25%) — typical MSP shape, scoped to `Vulnerability Management` / `Fortra VM` |
| GOSECURE INC | Reseller / Bronze (Direct) | Discount | Y | 0 | 0 | 0 | 25 | 10 | Bronze reseller, subscription-led |

Observations that matter for pricing config:
- **Distributors trend Discount-model with deep SW discounts (40%)**, and the percentage varies by **Solution Group** (`Offensive Security`, `Brand Protection`/`Phishlabs` rows carry 0% SW / 30% Subscription / 15% Service).
- **Renewal Maintenance is consistently discounted less than New Maintenance** (e.g. 40% new → 20% renewal).
- **MSPs are subscription-centric** (0% on SW/maintenance, 25% on Subscription, 10% on Service).
- A partner can have **multiple rows** with different `Solution Group` / `Solution Category` / `Solution` scopes, plus both a Guaranteed-Margin and a Discount row, with `Is Default` distinguishing the active one.
- Each row carries `Account Name in D365`, `Partner Type`, `Direct/Indirect`, `Tier`, `D365 Account ID`, `D-U-N-S Number`, `Is Active`, `Effective Start Date`. The **D-U-N-S Number** is the natural key used to match the D365 partner account to the SF Account during migration (see `07_…`).

---

## 2. Channel Billing Scenarios

Source: [Channel/Partner Billing Scenarios.docx](Fortra Discovery Documentation/Channel/Partner Billing Scenarios.docx)

**Meeting purpose:** enumerate every billing scenario where having a partner on the deal changes quoting, invoicing, discounts, or renewals. The variations to support:
- Partner receives the bill instead of the Customer.
- Partner is involved but the **Customer** receives the bill.
- Partner bills from **different legal entities** for different customers.
- Both a **Distributor and a Reseller** are on the deal and each gets a part.

**Most common partnership types:** Distributor, Reseller (VAR), MSP/MSSP. **Least common:** Referral.

### 2.1 Distributor (2-tier distribution)
- **Role:** Distributes Fortra software licenses between Fortra and resellers.
- **Billing flow:** `Fortra → invoices Distributor` → `Distributor → invoices Reseller` → (Reseller → End Customer). **End customer is NOT billed by Fortra.**
- **CRM attribution:**
  - Distributor = **Bill-To Partner**
  - Reseller = **Sell-To / Channel Partner**
  - End Customer = **End User / Customer of Record**

### 2.2 Reseller (Value-Added Reseller, VAR)
- **Role:** Sells licenses directly to the end customer; may add implementation/support.
- **Billing flow:** `Fortra → invoices Reseller` → `Reseller → invoices End Customer`. **No direct Fortra↔end-customer financial transaction.**
- **CRM attribution:**
  - Reseller = **Bill-To AND Sell-To Partner**
  - End Customer = **End User / Customer of Record**
- **Use case:** VAR sells a bundled software+services package to an enterprise, handling billing and support locally.

### 2.3 Managed Service Provider (MSP)
- **Role:** Delivers Fortra software as part of a broader managed service (security monitoring, hosting, IT management).
- **Billing flow:** `Fortra → invoices MSP`. The MSP packages and bills the end customer inside a service bundle. **Fortra typically will NOT know the end customer** and has no engagement/interaction with them.
- **Billing cadences to support (aligns to standard MSSP practice; Fortra is rebuilding its MSSP program for 2026):**
  - **Monthly, Quarterly, Annual**
  - **Usage-based billing**
- **CRM attribution:**
  - MSP = **Customer of Record** (when providing service on behalf of the end customer)
  - End Customer = **Optional / Linked Account** (not directly transacting); in most cases unknown to Fortra
- **Use case:** MSP buys licenses, bundles them into a fully managed endpoint-protection service for SMB clients.

> This is the scenario the **Meridian** examples illustrate — see §5. Meridian IT Ltd is the MSP/billing entity; the end-customer names (Ageas, Cigna, Barrett Steel, etc.) appear only as **descriptive line groupings**, not as billed accounts.

### 2.4 Referral Partner (least common)
- **Role:** Identifies/refers an opportunity; **not** involved in billing or service delivery.
- **Billing flow:** `Fortra → invoices End Customer directly`. Referral partner is paid a **commission % / referral fee**.
- **Commission timing:** paid to the referral partner **45 days after** Fortra receives payment from the end customer.
- **CRM attribution:**
  - Referral Partner = **Influencer / Referral Source** (not in billing hierarchy)
  - End Customer = **Bill-To AND Customer of Record**

### 2.5 Mixed scenarios
**Distributor + Referral Partner:**
`Fortra → Distributor → Reseller → End Customer` for the billing chain; Fortra **separately** pays a referral fee to the Referral Partner (tracked **outside** the billing chain), as a commission % of the sale, **45 days after** Fortra receives payment **from the Distributor**.

**Reseller + Referral Partner:**
`Fortra → Reseller → End Customer`; Fortra pays referral fee (commission %) to the Referral Partner outside the billing chain, **45 days after** payment **from the Reseller**.

### Billing-scenario → attribution summary

| Scenario | Who Fortra invoices (Bill-To) | Sell-To / Channel | Customer of Record | Notes |
|---|---|---|---|---|
| Distributor (2-tier) | Distributor | Reseller | End Customer | Distributor invoices Reseller; Reseller invoices End Customer |
| Reseller (VAR) | Reseller | Reseller | End Customer | Reseller is both Bill-To and Sell-To |
| MSP | MSP | MSP | MSP (end customer often unknown) | Monthly/Quarterly/Annual/Usage cadence |
| Referral | End Customer | — | End Customer | Referral fee paid 45 days post-payment |
| Distributor + Referral | Distributor | Reseller | End Customer | Referral fee 45 days post Distributor payment |
| Reseller + Referral | Reseller | Reseller | End Customer | Referral fee 45 days post Reseller payment |

> **RCA / Workday connection:** "Bill-To Partner" maps to the order/quote `Bill_To_Account__c`; the memory note `project_quote_order_billship_carryover` documents that defaulting `Bill_To_Account__c = Quote.AccountId` is **wrong for ~36% of deals** precisely because partner-billing scenarios (Distributor/Reseller/MSP) put the **partner**, not the end-customer Account, as the billing entity — the fix is place-derived billing. The "different legal entities for different customers" requirement is why the quote/invoice T&C engine keys on **legal entity** (§4).

---

## 3. Partner attribution fields (Deal Registration → SF data model)

Source: [Field Mapping for SFDC Partner Portal Deal Registration Form (copy).xlsx](Fortra Discovery Documentation/Channel/Field Mapping for SFDC Partner Portal Deal Registration Form (copy).xlsx). These are the fields that carry partner roles from the portal into the SF Opportunity/Quote, which then drive the billing model.

| Field (DR form) | SF / D365 field | Type | Rule |
|---|---|---|---|
| Reseller Company Name | `Reseller` (lookup) | Lookup | **Required for Distributor partners only** — lookup limited to resellers associated to the Distributor's account |
| Distributor Company Name | `Distributor` (lookup) | Lookup | **Required for Reseller partners only** — lookup limited to distributors associated to the Reseller's account |
| (system) Selling Partner | `Selling Partner` | Lookup + flag | Added to **Associated Partners** grid; `Selling Partner = Yes` |
| (system) Billable Partner | `Billable Partner` | Picklist flag | In Associated Partners grid; set `Yes` — this is the **Bill-To / billing partner** designation |
| Deal Origin | `Deal Origin` | Picklist | `Channel Originated` / `Fortra Originated` — selects which discount percentage set applies |
| Partner Deal Status | `Partner Deal Status` | Picklist | `Registered`, `Approved`, `Rejected`, `Closed` |
| Channel Account Manager | `Channel Account Manager` | Lookup | Auto-populated by **CAM Territory Rules** (`Product Brand → Country → State/Province`) |
| Lead Source | `Lead Source` | Picklist | `Partner Deal Registration` (set value, locked) |

The **Associated Partners grid** with `Selling Partner` / `Billable Partner` flags is the mechanism that ties multiple partners to one deal and identifies which one is the **billing partner** (drives the §1 model and the §2 billing flow). The Distributor↔Reseller conditional lookups encode the 2-tier relationship.

> Open question carried from the mapping: *"What field within the Partner's account will determine which resellers must select a distributor within the DR form?"* — i.e. how the system decides a reseller is indirect/distributor-fed.

---

## 4. Quote & Invoice T&C / Tax / License engine (legal-entity-driven)

Source: [QUOTE Terms and Condition Rules.docx](Fortra Discovery Documentation/Quotes and Billing/D365 TandC Rules/QUOTE Terms and Condition Rules.docx), [INVOICE Terms and Condition Rules.docx](Fortra Discovery Documentation/Quotes and Billing/D365 TandC Rules/INVOICE Terms and Condition Rules.docx)

These rules govern which legal text renders on the generated **Quote** and **Invoice** documents (the DocGen output). They are conditional on **legal entity**, **product brand**, and **product flags** — directly relevant to the multi-legal-entity partner billing requirement in §2.

### 4.1 Quote EULA / T&C text (by brand)
- **No EULA text displayed** when the quote's legal entity is **Fortra Argentina S.R.L.** or **Fortra Computing Group, S.L.U.**
- If **multiple product brands** are on the quote with different text, **both** texts are shown.
- **Offensive Security EULA** (brands **Cobalt Strike, Outflank, Core CTS**): links to `https://static.fortra.com/infrastructure-protection/pdfs/EULA-Offensive-Security-Solutions.pdf`.
- **Master Solutions Agreement** (default; brands: Core IGA, PowerTech, Robot, Linoma, AutoMate, Beyond Security, Bytware, CCSS, Clearswift, Core SCS, Digital Defense, Fortra Security Services, Halcyon, InterMapper, JAMS, PowertechX, RJS, Safestone, SEQUEL, ShowCase, Skybot, Tango04, TeamQuest, Terranova Security): "subject to the terms and conditions set forth in the Fortra Master Solutions Agreement … located at www.fortra.com/legal".
- **Brands allowing Custom T&Cs:** Agari, PhishLabs, Digital Guardian, Titus, Boldon James, Vera.
  - **PhishLabs / Agari** carry distinct **Service Order** text for New Sale vs. Renewal/Add-on (auto-renew, 60-day non-renewal notice, "non-refundable Total First Year Fees" invoicing).
  - **Boldon James / Titus / Vera / Digital Guardian**: New Sale and Renewal both use the standard MSA text.

### 4.2 License Key text
- Displayed when a quote/invoice has **new maintenance** (perpetual). **Not** displayed for Subscriptions.
- Text: *"Temporary license keys are issued upon receipt of order. Permanent license keys are issued upon receipt of payment in full."*

### 4.3 Tax text (legal-entity-driven)
Displayed when legal entity is **Fortra Argentina S.R.L.** or **Fortra Computing Group, S.L.U.** (on the invoice, only when there is new maintenance):
- **Argentina:** "The values do not include IVA. Stamp tax and municipal tax are responsibility of the customer."
- **Computing Group (Spain):** "The values do not include IVA. We accept withholding income tax only with documentation. Other taxes and withholdings will be paid by the customer."

### 4.4 Service Terms
- Displayed if the quote has a **services product** and none of those products have **`Hide Fortra Professional Services Terms = Yes`**.
- Key terms: services invoiced upon order execution, payment upfront within Net Terms, **prepaid services not dependent on delivery/completion**, services **expire 12 months** from purchase, all fees nonrefundable; onsite consultant expenses invoiced after the visit; completion criteria; minimum scheduling blocks (1-hour on-demand, 2-hour implementation/migration); cancellation notice windows (2 / 5 / 10 business days); non-solicitation with **$150,000** liquidated-damages clause.

### 4.5 Signature page
- Displays unless **`Show/Hide Signature Lines? = Hide`** on the quote.
- Confirms acceptance, authorizes Fortra to invoice, and covers temporary vs. permanent license-key issuance for perpetual vs. subscription.

### 4.6 Invoice-specific
- **Invoice T&Cs: None** (no MSA/EULA block on invoice). License-key, tax, and service-terms text follow the same conditional rules as the quote; the service-terms block on the invoice is the short MSA-reference line.

> **DocGen connection:** This conditional text logic is realized in the Quote PDF DataRaptor/template pipeline (memory note `project_docgen_quote_pdf_pipeline`). The Argentina/Spain "no EULA / IVA" carve-outs and the multi-brand "show both" rule are the discovery requirements behind that template logic.

---

## 5. Meridian Example — MSP with MSP End Users (concrete numbers)

Source: [Meridian Quote Example - MSP with MSP End Users.pdf](Fortra Discovery Documentation/Quotes and Billing/Meridian Quote Example - MSP with MSP End Users.pdf), [Meridian Invoice Example - MSP with MSP End Users.pdf](Fortra Discovery Documentation/Quotes and Billing/Meridian Invoice Example - MSP with MSP End Users.pdf)

This is the canonical **MSP-with-MSP-end-users** worked example. **Meridian IT Ltd** is the MSP and the **sole billed entity**; the end customers (Ageas, Ashford, Barrett Steel, Bernard Matthews, Black Hawk, Cigna, Compact Collections, Dewhirst/Castlecrafts, Edrington, LBBW, TWG, William Hill, etc.) appear **only as descriptive line-group headers**, not as billed accounts — exactly the §2.3 MSP attribution ("Fortra will not know / does not bill the end customer").

### Header facts

| Field | Quote | Invoice |
|---|---|---|
| Account | Meridian IT Ltd (`00020229`) | Meridian IT Ltd (`00020229`) |
| Document # | **Q-0000463877** | **V0000312114** |
| Date | 6-Jul-25 | 2-Aug-25 |
| Net Terms | 30 Days | 30 Days |
| Expiration / Due | Expires 6-Oct-25 | Payment Due 1-Sep-25 |
| Legal entity | **Fortra International Limited** (Co. No. 4172068, VAT GB770614141), UK | same |
| Currency | **GBP** | **GBP** |
| Ship-To / Bill-To | MITL Accounts Payable, Forward House, 17 High Street, Henley-In-Arden, B95 5AA, UK | same; Ship To: United Kingdom; Customer VAT `GB578185005` |
| Contact | Toni Scott, Fortra, +44 (0) 1733 234 995 x8391 | same |

### Totals (this is the key MSP grounding)

| Line | Quote | Invoice |
|---|---|---|
| **Subtotal** | **£33,873.75** | **£33,873.75** |
| **VAT** | "Calculation pending" (not computed on quote) | **20.00% = £6,774.75** |
| **Total / Amount Due** | **£33,873.75** | **£40,648.50** |

**Takeaways for the MSP model:**
- The **quote omits VAT** ("Calculation pending") and shows the **ex-VAT subtotal as the Total**; the **invoice adds 20% UK VAT** to reach Amount Due. RCA/DocGen must defer tax to invoice time and apply destination VAT (UK 20%).
- All ~150 lines roll up to **one bill** to the MSP. Pricing is per-line catalog (no partner discount visibly applied on this particular renewal doc — these are list subscription renewals), consistent with the MSP attribution where Fortra bills the MSP directly.
- Document type label drives layout: **"QUOTE" / "-DO NOT PAY-"** vs. **"Invoice"** with full wire/payment details.

### Line structure — grouping, hardware, partitions, tiered pricing
Each end-customer block is a header (`<Customer> - <PO#> - exp <date>`) followed by a **hardware identifier** and its lines. Two hardware-identification styles appear, which maps directly to §6 (Hardware Grouping):
- **IBM i / LPAR-based:** `Serial #: 7886850  Model: 42A  Feature Code: EP1F  Processors: 5  System Type: Production`, then lines keyed by **LPAR** number + **Name** (e.g. LPAR 3 / `S44D0219`), Primary vs Secondary Subscription, Start/End dates, Amount.
- **Hardware-ID-based:** `Hardware ID: ac90bab030  System Type: HA`, lines keyed by **Qty**.

**Concrete tiered-pricing example (Powertech MFA, Barrett Steel PO 201479):** the same product family bills as multiple tier lines on one hardware record — this is the line shape the configured tiered/attribute-based pricing must reproduce:

| Product | Qty | Amount (GBP) |
|---|---|---|
| Powertech Multi-Factor Authentication – Per OS Instance – Subscription | 1 | 450.00 (HW `ac90bab030`) / 900.00 (HW `86d002c12d`) |
| Powertech MFA – First 25 Identities – Subscription | 1 | 2,250.00 / 4,500.00 |
| Powertech MFA – Each Additional Identity – Subscription | 25 | 300.00 / 600.00 |

- **Primary vs Secondary Subscription** is a recurring distinction (Secondary lines are typically priced at ~half the Primary, e.g. Lvl2 Systems Operations Suite Primary 630.00 vs Secondary 315.00), tied to HA/DR LPARs on the same hardware.
- A **£0.00** line appears (NSS – SNMP Trap Receiver – Subscription, LPAR 14 `RG01`) — included/bundled component; relevant to the `$0-net` line handling discussed in active engineering (SC-3345/SC-3347).
- Date model: subscription renewals run **1-Oct-25 → 31-Dec-25** (a short co-term quarter) for most lines, with some annual lines `1-Oct-25 → 30-Sep-26` — i.e. **co-termination** to a common end date, a renewal-quoting requirement.

> **RCA connection:** the per-hardware, per-LPAR, primary/secondary line layout is exactly what §6 (Hardware Grouping) and §7 (PowerBranching) are designed to produce/maintain across renewals. The MSP billing-once-for-many-end-users pattern is why renewal quotes must propagate hardware/group records (§6) so the next renewal reproduces the same grouping.

---

## 6. Hardware Grouping (Hardware records ↔ Quote Line Groups)

Source: [HardwareGrouping.docx](Fortra Discovery Documentation/Quotes and Billing/HardwareGrouping.docx)

**Goal:** let teams connect a **hardware record** to a **set of products** at once (not one product at a time) by **linking the hardware record to a Quote Line Group**.

**Proposed solution:**
1. Creating a new **Hardware record** also creates a **Quote Line Group of the same name**, and links them together.
2. A **"New Hardware" button** on the line-editor form prompts for hardware info; on save it creates **(a)** the Hardware record, **(b)** the corresponding Quote Line Group, and **(c)** the link between them.
3. Sales/Customer Ops then add one or more products to that group, associating them with the linked hardware record. The Hardware/Group is visible in the line editor and lines can be added/removed.
4. The UI needs a way to **edit** the hardware record linked to the group (edit button or clickable link to the hardware record page).
5. This must **not replace** the normal "New Group" button/process — teams that don't need hardware records can still create standard quote line groups.
6. **Hardware records/groups must propagate into subsequent renewal quotes.**

**Why it matters (ties to §5):** the Meridian doc shows many hardware records (by Serial#/LPAR or Hardware ID), each carrying a set of subscription lines. Grouping by hardware is what produces those per-hardware blocks, and the renewal-propagation requirement is what keeps the next year's renewal quote structured identically.

> **RCA connection:** Quote Line Group is a native RCA construct; the Hardware record is a Fortra custom object. The 1:1 Hardware↔Group link + auto-create-on-new + renewal propagation is the discovery requirement behind that custom build. Connects to PowerBranching (§7), which decides whether the hardware record is cloned or shared when a line splits.

---

## 7. PowerBranching (Order Line Splitting) in Salesforce

Source: [PowerBranchingSalesforce.docx](Fortra Discovery Documentation/Quotes and Billing/PowerBranchingSalesforce.docx)

Two **order-line branching models** are required. The model is **defined at the SKU level**, and a given SKU is **always treated the same way** every time it appears on an order. Both models trigger **when an order line quantity > 1** (splitting `qty = N` into N lines of `qty = 1`).

### Common to both branch types
- Order lines are **cloned when quantity > 1** (one line of qty N → N lines of qty 1).
- **Manual discount amount** is divided **evenly** across all cloned lines.
- **Displaced ARR** is divided **evenly** across all cloned lines.
- **Partitions are always cloned** — each cloned order line gets its **own** cloned partition.

### Branch Type A — "Order Line Only"
- **Hardware is NOT cloned** — all cloned order lines link to the **one original** hardware record.
- Each cloned line's partition is linked to that **one** original hardware record.
- **Example (qty = 4):** 1 order line + 1 partition + 1 hardware (4 records) → **4 order lines + 4 partitions + 1 hardware (9 records)**.

### Branch Type B — "Order Line and Hardware"
- **Hardware IS cloned** — each cloned order line gets its **own** cloned hardware record.
- Each cloned line's partition is linked to **its own** hardware record.
- **Example (qty = 3):** 1 order line + 1 partition + 1 hardware (3 records) → **3 order lines + 3 partitions + 3 hardware (9 records)**.

### Branch-type comparison

| Aspect | Order Line Only | Order Line and Hardware |
|---|---|---|
| Trigger | qty > 1 | qty > 1 |
| Order lines cloned | Yes (N lines, qty 1 each) | Yes (N lines, qty 1 each) |
| Manual discount | Split evenly | Split evenly |
| Displaced ARR | Split evenly | Split evenly |
| Partitions | Cloned, one each | Cloned, one each |
| **Hardware** | **Shared** (1 original) | **Cloned** (one per line) |
| Record count (qty N from 1+1+1) | N + N + 1 | N + N + N |

> **RCA / Workday connection:** This is implemented as the **PowerOrderSplitting / PowerOrderSplittingService** (memory `project_sc3210_workday_linetype`). Critically, that service sets the child's `Original_Order_Item__c` FK on **pure quantity splits too**, which is the root cause of the SC-3210/SC-3368 Workday line-type mis-stamping — the line-type flow must distinguish a true LIC/MAINT subsplit (different Product2) from a quantity split (same Product2). The "divide manual discount / displaced ARR evenly" rule is the source-of-truth business requirement that the splitting service must preserve.

---

## 8. Open Questions / Ambiguities

1. **Margin-stack math semantics (Guaranteed Margin):** `List × A-Margin × B-Margin` — is each "margin" applied as a *markup multiplier* (e.g. ×(1+m)) or as a *retained-margin discount* off list? The discount-list percentages (e.g. 20, 10) and the SC-3359 net-vs-list defect suggest the net-to-partner is `List × (1 − Σ margins)` in practice; confirm the exact compounding order against the live `SubscriptionPricing74` waterfall.
2. **Origination set selection:** the discount lists carry two percentage sets (Channel Originated vs Fortra Originated). Which set the pricing engine uses presumably keys on `Deal Origin`, but the partner-pricing-model docs don't state this explicitly.
3. **Multi-currency:** the partner-discount lists and pricing models are all expressed as percentages, but SC-3384 shows non-USD configured pricing was using USD values. Whether partner margins/discounts are currency-blind (percent-only, so safe) or interact with the USD-only ABA/attribute-tier data needs confirmation.
4. **Reseller→Distributor determination:** carried-over open question from the DR mapping — what account-level field determines that a reseller must select a distributor (i.e. is "indirect").
5. **MSP usage-based billing:** "Usage-based billing" is listed as a required MSP cadence but no metering/rating mechanism is described. How usage is captured and rated for MSP bills is undefined in discovery.
6. **MSP end-user visibility:** Meridian shows end-customer names as line-group descriptions only. Whether those end-customer names need to be structured data (e.g. linked Accounts for reporting) or remain free-text headers is open (§2.3 says end customer is "Optional/Linked Account").
7. **VAT on quote:** the quote shows VAT "Calculation pending." Whether RCA computes and shows estimated VAT on quotes or always defers to invoice (as Meridian does) should be confirmed for the DocGen template.
8. **Hardware-group renewal propagation mechanics:** the requirement says hardware/groups "must be propagated into subsequent renewal quotes," but the propagation mechanism (clone vs reference, and interaction with PowerBranching branch type) is not specified.

---

## Sources

**Primary (Quotes and Billing):**
- `Fortra Discovery Documentation/Quotes and Billing/PartnerPricingModels.docx`
- `Fortra Discovery Documentation/Quotes and Billing/PartnerPricingModelSummary.docx`
- `Fortra Discovery Documentation/Quotes and Billing/HardwareGrouping.docx`
- `Fortra Discovery Documentation/Quotes and Billing/PowerBranchingSalesforce.docx`
- `Fortra Discovery Documentation/Quotes and Billing/Meridian Quote Example - MSP with MSP End Users.pdf` (read via extracted text)
- `Fortra Discovery Documentation/Quotes and Billing/Meridian Invoice Example - MSP with MSP End Users.pdf` (read via extracted text)
- `Fortra Discovery Documentation/Quotes and Billing/D365 TandC Rules/QUOTE Terms and Condition Rules.docx`
- `Fortra Discovery Documentation/Quotes and Billing/D365 TandC Rules/INVOICE Terms and Condition Rules.docx`

**Primary (Channel — billing/attribution):**
- `Fortra Discovery Documentation/Channel/Partner Billing Scenarios.docx`
- `Fortra Discovery Documentation/Channel/Field Mapping for SFDC Partner Portal Deal Registration Form (copy).xlsx`

**Supporting (to ground pricing-model percentages):**
- `Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/CyberDiscounts_UATSample_041326.xlsx`
- `Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/Copy of D365 Partner Discounts Data Template-WIP-Lidiane 2026.2.27.xlsx`

**Cross-references (other discovery KB docs, not re-derived here):**
- `07_channel-partner-discounts-data.md` — partner-discount data-list column model and migration template
- `06_channel-partner-onboarding-management.md` — partner types/tiers and portal
- `10_pricing-strategy-and-approval-matrix.md` — deal-desk approval thresholds
- `FORTRA_KNOWLEDGE_BASE.md` (repo root) — RCA/Workday/MuleSoft design synthesis

**Not used / out of scope for this doc (present in the same dirs):** Export Controls Discovery.docx, Outflank ARR Apr25, and Running Master Billings File — these are **fully covered in [15_quotes-billing-export-controls-and-misc.md](15_quotes-billing-export-controls-and-misc.md)**, not dropped; Quote Approval/* (covered by `10_…` and `16_…`); broader Channel content (covered by `06`/`07`/`08`).
