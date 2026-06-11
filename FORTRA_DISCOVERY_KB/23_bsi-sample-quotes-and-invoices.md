# BSI Discovery — Sample Quote & Invoice PDFs

**Scope:** `BSI Discovery Info/SamplePDFs` — 13 sample legacy documents (7 quotes `Q-…`, 6 invoices `V0…`) plus `InvoiceQuoteDescriptions.txt` which labels what each pair demonstrates. These are real, anonymized examples of Fortra's **current/legacy quote and invoice output** (generated from the pre-RCA systems — D365/Dynamics + Experlogix CPQ, and legacy SF orgs). They are the ground-truth specification for what Salesforce Revenue Cloud Advanced (RCA) DocGen output and the MuleSoft→Workday invoice pipeline must reproduce.

> **Why this matters for the RCA build:** Every header field, line column, grouping rule, totals block, terms paragraph and edge case shown here is an implicit requirement for the new **DocGen** quote template and the new **billing/invoice** generation. The design KB (`FORTRA_KNOWLEDGE_BASE.md`) covers the *system* design; this doc captures the *document artifact* the system must emit. Where the quote and invoice diverge in layout, the new platform must support both renderings.

---

## 1. Pairing & Scenario Map (read `InvoiceQuoteDescriptions.txt` first)

The label file maps each invoice to its originating quote and names the demonstrated scenario:

| # | Invoice (V0…) | Quote (Q-…) | Scenario demonstrated | Key edge case |
|---|---|---|---|---|
| 1 | [V0000304974](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/V0000304974.pdf) | [Q-0000455841](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/Q-0000455841.pdf) | **New subscription sale with partner** — also a **Spain invoice** | **Unique sequential Spain invoice ID** (`S000006265`) distinct from the global ID; Spanish-language template; FX rate shown |
| 2 | [V0000304602](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/V0000304602.pdf) | [Q-0000456763](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/Q-0000456763.pdf) | **Hourly project services** | Fractional service Qty (94.8 hrs); full Professional-Services terms page; quote line table is empty (pricing on SOW) |
| 3 | [V0000304240](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/V0000304240.pdf) | [Q-0000445897](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/Q-0000445897.pdf) | **Renewal with partner** | Bill-to (reseller NetCon) ≠ Ship-to (end-customer J.D. Geck); EUR currency / EMEA entity |
| 4 | [V0000285819](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/V0000285819.pdf) | [Q-0000429097](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/Q-0000429097.pdf) | **Renewal with a large number of line items** | 47-page quote (~hundreds of LPAR-keyed lines) **collapsed to a single ELA/Strategic-Agreement summary line on the invoice**; invoice references a *different* quote (Q-0000416288) |
| 5 | [V0000274389](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/V0000274389.pdf) | [Q-0000400631](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/Q-0000400631.pdf) | **Renewal with multiple bundles** | Bundle parent line carries price; bundle component lines printed at $0.00; per-hardware/system grouping |
| 6 | [V0000215067](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/V0000215067.pdf) | [Q-0000319668](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/Q-0000319668.pdf) | **Sale with large line count for a partner who buys licenses to later redistribute** | ~150+ identical "Dealertrack Scan Bundle" lines (Qty 1 each, not consolidated); perpetual + subscription sections in one doc |
| 7 | [V0000212838](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/V0000212838.pdf) | [Q-0000319257](../Fortra%20Discovery%20Documentation/BSI%20Discovery%20Info/SamplePDFs/Q-0000319257.pdf) | **New software sale with a large number of line items** | Mixed New Software + New Maintenance + Services/Training; legacy `@helpsystems.com` contact; unpaid invoice (Amount Due, no Amount Paid) |

**Document-number convention:** Quotes are `Q-` + 10 digits (`Q-0000455841`). Invoices/"Global" invoices are `V0` + 9 digits (`V0000304974`). Spain has an additional country-local sequential ID `S` + 9 digits (`S000006265`).

---

## 2. Common Document Structure

### 2.1 Page 1 — Rebrand / Payment cover letter (boilerplate, both quotes & invoices)

Every doc opens with a standardized **HelpSystems→Fortra rebrand + new-banking-details letter** ("Dear Valued Customer… Meet Fortra, the new face of HelpSystems"). This is templated by **legal entity / currency / region**:

| Entity / region | Letter language | Currency | Bank block shown |
|---|---|---|---|
| Fortra, LLC (US, Eden Prairie MN) | English | USD | ACH/Wire (Routing 124001545 / 021000021, Acct 895537857, SWIFT CHASUS33, J.P.Morgan NY) + "Send Checks To: P.O. Box 735324, Chicago IL 60673-5324"; W-9 link `community.fortra.com/forms/W9.pdf` |
| Fortra International Limited (UK/EMEA, Altrincham Cheshire) | English | EUR | Wire only — Correspondent JPMorgan SE / CHASDEFX, Bank J.P. Morgan SE Luxembourg, Acct 6550211305, IBAN LU240670006550211305, SWIFT CHASLULX |
| Fortra Computing Group, S.L.U. (Spain, Barcelona; formerly **Tango/04 Computing Group SL**) | Spanish ("Estimado Cliente") | USD | Wire — Acct 6550211326, IBAN LU390670006550211326, SWIFT CHASLULX, Beneficiary "Fortra International Limited" |

Standard contact addresses on the letter: `collections@fortra.com` (supplier setup / questions), `accountsreceivable@fortra.com` + `FortraLLC.eremit@jpmchase.com` (remittance advices). Tax IDs: US `30-0290533`; UK `Company No 4172068`, `VAT GB770614141`; Spain `CIF B-60341401`, `VAT/Reg Mercantil de Barcelona Tomo 25991 Folio 0216 Hoja 96367`.

> **Implication:** DocGen must select the correct legal-entity letterhead, language, currency, bank block and tax registration based on the selling entity / customer region — this is template branching, not a single template.

### 2.2 Document header band (the structured fields)

Present on the line-item page of every doc. **Quotes and invoices share most fields but differ in a few:**

| Field | Quote label | Invoice label | Notes |
|---|---|---|---|
| Watermark / status | `-DO NOT PAY-` | (none) | Spanish quote uses `-NO PAGAR-` |
| Doc type heading | `QUOTE` / `COTIZACIÓN` | `Invoice` / `Factura` | |
| Date | `Date:` / `Fecha:` | `Date:` / `Fecha:` | Quote = create date; invoice = issue date |
| Account (+ legacy ID) | `Account:` `(00xxxxxx)` | `Account:` `(00xxxxxx)` | The parenthetical is the legacy account number (e.g. `(00073914)`, `(00169647)`) — a candidate external-ID for migration |
| Doc number | `Quote #:` / `ID Cotización:` | `Invoice #:` / `Nro de Global:` | Spain adds `Nro de Factura: S…` |
| Terms | `Net Terms:` / `Cond. De Pago:` | `Net Terms:` / `Cond. De Pago:` | e.g. 30/45/90 Days |
| Expiry / Due | `Expiration Date:` / `Fecha de Vencimiento:` | `Payment Due:` / `Vencimiento del pago:` | Quote=quote expiry; invoice=payment due |
| Shipping Info | **Yes** (Name/Company/Address/Phone/Email) | collapsed to `Ship To:` (state, country only) | |
| Billing Info | **Yes** | **Yes** (full block) | |
| Bank/remit block | (none on line page) | **Yes** (repeats ACH/Wire) | |
| Purchase Order ID | (none) | **Yes** | invoice carries the customer PO ref |
| Currency | `Currency:` / `Moneda:` | same | |
| Sales contact footer | `Contact: <rep> Phone / Email` | same | repeated on every page |

The customer-facing `Account #:` on the Spain invoice can be the **customer's own bank account reference** (e.g. `Banesco Banco Universal C.A. (BAN223232)`), not the Fortra account — region-specific.

### 2.3 Line-item table

Two layout variants exist:

**A — Full layout (most quotes & detailed invoices):** columns `Description | Price | Discount | Amount` (Spanish: `Descripción | Precio | Descuento | Total`). Lines are grouped, with sub-headers inside the Description column:

- **Hardware grouping header** — `Serial #: … Model: … Feature Code: … Processors: … System Type: …` (IBM i context) **or** `Hardware ID: … System Type: …` (software/cloud context). System Type values seen: `Production`, `HA`, `DR`, `Test`, `OnlineProduction`, `OnlineNonProduction`.
- **Transaction-type sub-header** per group: `Subscriptions` / `Suscripciones`, `Subscription Renewal`, `Renewal Maintenance`, `New Software`, `New Maintenance`, `Services`.
- **Line sub-columns** that vary by transaction type:
  - Subscription/renewal: `Product | LPAR | Name | Start Date | End Date` (IBM i) or `Product | Qty | Start Date | End Date` (software).
  - Quote subscription: `Product | LPAR | Name | Qty | Duración` (e.g. `12 months`) — duration instead of dates.
  - Perpetual New Software: `Product | Qty` (no dates).
  - New Maintenance (first-year on perpetual): `Product | Qty | Start Date | End Date`.
  - Services: `Product | Qty` (Qty can be fractional hours, e.g. `94.8`).

**B — Simplified invoice layout (`Description | Qty | Amount`, no Price/Discount):** used when the invoice need only show net amounts (e.g. redistribution-partner invoice V0000215067, and the ELA summary invoice V0000285819 which is just `Description | Amount`). The **quote** for the same deal still shows full Price/Discount/Amount.

**Discount rendering:** absolute negative figure in parentheses in its own column, e.g. `3,250.00 (1,316.25) 1,933.75`. `(0.00)` printed when no discount. Discount % is *not* printed — only the dollar reduction; the net `Amount = Price − Discount`.

**Inline NOTE annotations** appear within the Description: `NOTE: SOW BMC-ENPT-043024-NO`, `NOTE: PS - FSP & AWS SNS/SMS CC`, `NOTE: Half Day`.

### 2.4 Totals block

| Row | Quote | Invoice |
|---|---|---|
| Subtotal | shows `Subtotal Price (Discount) Amount` | same |
| Tax / IVA / VAT | `Calculation pending` / `Cálculo pendiente` | resolved figure (e.g. `153,099.51`) or `0.00` |
| Total | net total | (Total) |
| Amount Paid | — | shown with **payment date** if paid (e.g. `30-May-2025 Amount Paid 21,330.00`) |
| Amount Due | — | `0.00` if paid, else open balance (e.g. `700,973.06`) |
| Total pagado / Total a pagar | (Spain invoice) | shows paid + remaining |
| Currency / Moneda | yes | yes; Spain also prints `Tipo de Cambio: 0.8828` (FX rate) |

> **Key tax behavior:** Quotes always show **Tax = "Calculation pending"** (tax not computed at quote time); invoices carry the actual tax. The RCA→Workday flow must reproduce: quote = pre-tax estimate, invoice = tax-resolved.

### 2.5 Standard terms & signature elements

- Footer legal line on every quote/invoice: *"This Quote is subject to the terms and conditions set forth in the Fortra Master Solutions Agreement and applicable Solution Specific Schedule(s) located at www.fortra.com/legal."*
- Quotes carry an **expiry banner** on every page: *"This quote, including all related pricing, EXPIRES on <date>."*
- License-key note (perpetual/subscription): *"Temporary license keys are issued upon receipt of order. Permanent license keys are issued upon receipt of payment in full."* (Spanish quotes have the long-form version about claves temporales/permanentes.)
- Quotes for license/subscription deals include a **signature page** (Signature / Print Name / Title / Date) authorizing Fortra to invoice and issue temporary keys.
- Services quotes append a **full Professional-Services Terms page** (see §3.2) and reference `https://static.fortra.com/goanywhere/pdfs/other/ga-professional-services-terms-and-conditions.pdf`.

---

## 3. Scenario Deep-Dives & Edge Cases

### 3.1 New subscription w/ partner + Spain unique invoice ID (V0000304974 / Q-0000455841)
- **Spanish-language template** ("COTIZACIÓN"/"Factura"), entity **Fortra Computing Group, S.L.U. (Barcelona)**, currency **USD** but with FX note `Tipo de Cambio: 0.8828`.
- **The defining edge case:** the invoice carries **two distinct numbers** — global `Nro de Global: V0000304974` and the **Spain-only sequential** `Nro de Factura: S000006265`. Spain legally requires its own gapless invoice sequence, separate from the global numbering. **RCA/Workday must allocate a country-local invoice number for Spanish (and likely other regulated EU) entities in addition to the global ID.**
- Partner billing: Ship-to = end customer **Banesco Banco Universal C.A. (Venezuela)**; Bill-to = partner **Grupo Incisive, C.A.**; product = `Powertech SIEM Agent for IBM i - Subscription` (2 LPAR lines, list 3,250 each, discounts 1,316.25 / 2,112.50). `ID Orden de Compra: Quote signed`.
- Subscription line keys: `LPAR`, `Nombre` (e.g. `C104C43P`), `Fecha de Inicio`/`Fecha de Fin` (1-Jun-25 → 31-May-26).

### 3.2 Hourly project services (V0000304602 / Q-0000456763)
- Account **BMC Software, Inc. (00116639)**, USD, **Net 30** invoice but the **quote was Net 90** with a 12-month expiration window — terms can change between quote and invoice.
- Single services line `Security Consulting Services (Hourly)`, **Qty 94.8** (fractional hours), Price 22,396.50, Discount 1,066.50, Amount 21,330.00. `NOTE: SOW BMC-ENPT-043024-NO`. PO `PO#5011092952`.
- The **quote line table is empty** (Subtotal `(0.00)`, Total blank) — services pricing lives in the SOW; the quote exists mainly to bind the **Professional-Services Terms** (full multi-paragraph page): services invoiced upfront on order execution, pre-paid, expire 12 months from purchase, nonrefundable; remote sessions in ≥1hr (on-demand) / ≥2hr (impl/migration) blocks; business hours 8:30–17:00 M–F; change-order requirement; AS-IS warranty disclaimers; IP stays with Fortra; cancellation notice windows (2/5/10 business days); 30-day termination; **$150,000 no-poach liquidated-damages clause**.

### 3.3 Renewal with partner (V0000304240 / Q-0000445897)
- **EMEA entity Fortra International Limited**, **EUR**. Account **J.D. Geck GmbH (00169647)** (end customer = Ship-to, Germany) but **Bill-to = partner NetCon IT-Security GmbH** — classic reseller split. Partner VAT `DE 262 893 002`. PO `ORD-2025-445897`.
- 4 Clearswift SECURE Email Gateway subscription lines (Sandbox, Avira AV add-on, Sophos AV, Structural Sanitization), each Qty 1, 1-Jun-25→31-May-26, flat ~20% discount; Subtotal 8,964 → 7,172 EUR.
- Quote sub-header `Subscription Renewal`; invoice sub-header `Subscriptions`. The invoice was already paid (Amount Paid 7,172, Due 0.00).

### 3.4 Renewal with large line-item count → ELA summarization (V0000285819 / Q-0000429097)
- **Most important structural edge case.** Account **Sysco Corporation (00073914)**, USD, **Net 45**.
- The **quote Q-0000429097 is 47 pages** of itemized IBM i renewal-maintenance lines, grouped by hardware Serial#/Model/Feature/Processors, each line keyed by `Product | LPAR | Name | Start | End`. Hundreds of Powertech / Robot product lines; **many secondary-license / NETWORK Node lines priced at 0.00** (covered under primary). Quote subtotal **2,014,023.02 list → (157,074.99) discount → 1,856,948.03 net**.
- The **invoice V0000285819 collapses the entire thing into ONE summary line:** *"Year 1 of Strategic Agreement Per Quote Q-0000416288 / ELA Renewal Maintenance / Flexible License Change Fee / Maintenance Dates: 12/1/2024 – 11/30/2025"* = 1,856,948.03, **Tax 153,099.51, Total 2,010,047.54**.
- **Two anomalies to flag:**
  1. The invoice references **Q-0000416288**, not the sample quote Q-0000429097 — confirming an ELA/Strategic-Agreement deal involves multiple quote versions; the billed quote ≠ the sample quote provided.
  2. **The invoice is taxed; the multi-page quotes are not.** This is the only sample where Tax ≠ 0 (US sales tax on a maintenance ELA).
- **RCA implication:** the platform must support **invoice-level summarization** of a many-line order into a single strategic-agreement bill line, while the order/quote retains full itemization — i.e. invoice grouping/rollup is a first-class requirement, not 1:1 line mapping.

### 3.5 Renewal with multiple bundles (V0000274389 / Q-0000400631)
- Account **KPMG LLP (00227619)**, USD, Net 30. 6-page invoice. Demonstrates **bundle (product-component-group) rendering**:
  - **Bundle parent line** carries the price (e.g. `GoAnywhere Premium Bundle with Threat Protection - Subscription` 68,466.42 → (36,971.86) → 31,494.56; `GoAnywhere Premium Bundle - Subscription` 32,411.60 → 19,446.96; `SECURE ICAP Gateway Essential Security Package…` 16,289.78 → 9,773.90).
  - **Component lines print at 0.00 / `(0.00)`** (Advanced Workflows, SFTP Server, FTP Client & Server, FTPS Server, Secure Folders, Secure Forms, AS2 Send/Receive, Secure Mail 30 Users, GoDrive 30 Users, Cloud Connector x2, ICAP per-instance + Structural Sanitization).
  - **Naming divergence quote vs invoice:** the **quote** concatenates the full path (`GoAnywhere Premium Bundle with Threat Protection - Subscription - GoAnywhere SFTP Server - Subscription`), while the **invoice** abbreviates components with a leading `- ` (` - GoAnywhere SFTP Server - Subscription`). DocGen must reproduce both conventions.
  - Lines re-grouped per `Hardware ID / System Type` (e.g. `GAG PROD B / OnlineProduction`, `Clearswift / Production`, `ZIJU-ZISA-MDFK-NYAG / OnlineProduction`).
  - Add-ons outside the bundle billed normally (`GoAnywhere Additional Security Domains` Qty 3, 2,669.31 → 1,227.87). Subtotal 260,329.03 → (127,426.31) → 108,029.66.

### 3.6 Partner buys licenses to redistribute (V0000215067 / Q-0000319668)
- Account **Dealertrack Technologies, Inc / Cox Automotive (00213245)**, USD, Net 45. **12-page quote, 8-page invoice.**
- Defining edge case: **~150+ identical `Dealertrack Scan Bundle` lines, each Qty 1, NOT consolidated** — the partner orders many discrete single-unit licenses to redistribute to dealers, so each must remain a separate line (each gets its own key).
- **Two sections in one doc:** `New Software` (perpetual, no dates, list 1,629.00 / disc (407.25) / net 1,221.75 each) **and** `Subscriptions` (Qty 1, 12 months / dates, 357.00 each, no discount). Quote Subtotal 158,880.00 → (32,580.00) → **126,300.00**.
- The **invoice uses the simplified `Description | Qty | Amount` layout** (no Price/Discount), showing only net (1,221.75 perpetual / 357.00 subscription). Same total 126,300.00, paid in full.
- **RCA implication:** must support high line counts of identical SKUs without auto-rolling-up quantity, and an invoice template that suppresses list/discount columns.

### 3.7 New software sale, large line count, mixed types (V0000212838 / Q-0000319257)
- Account **BOK, NA (00117171)**, USD, Net 30. **14-page invoice / 11-page quote.** Oldest sample — sales contact still on **`@helpsystems.com`** and a `+1 (402) 979-8901` number (pre-Fortra rebrand artifact in data).
- Mixes **three transaction sub-types interleaved per hardware group:** `New Software` (perpetual licenses), `New Maintenance` (first-year maintenance, dated 1-Jan-23→31-Dec-23, at 0.00 discount), and a **Services/Training** block:
  - `GoAnywhere MFT Premium QuickStart Services` 13,195; `GoAnywhere MFT Fundamentals Course` 1,500; `…Administrator Associate Course` 4,500; `…Automation Associate Course` 3,000; `GoAnywhere Services Hourly (Pre-Paid)` Qty 52 = 13,000 `NOTE: PS - FSP & AWS SNS/SMS CC`; `GoAnywhere Services Professional Services (Pre-Paid)` Qty 240 = 60,000 `NOTE: Half Day`.
- Example perpetual lines: `GoAnywhere Core Server Bundle with Gateway - Perpetual` 14,700 → (8,011.50) → 6,688.50; `SECURE ICAP Gateway Elite Security Package … (Sophos AV) - Perpetual - Non-Production - 1 Users` 9,568 → 8,706.88; `GoAnywhere Secure Mail Unlimited Users - Perpetual` 31,500 → (17,167.50) → 14,332.50.
- Invoice **Subtotal 917,475.20 → (216,502.14) → 700,973.06**; **unpaid** — shows `Amount Due 700,973.06` with **no Amount Paid line** (the only open-balance sample). PO field = `PER SIGNED QUOTE Q-0000319257`.
- Extra terms: *"Professional service hours expire 1 year after purchase"* + GoAnywhere PS terms URL.

---

## 4. Cross-Cutting Requirements Derived From These Samples (for RCA / DocGen / Workday)

1. **Multi-entity / multi-currency / multi-language templates.** Fortra LLC (US/USD/English), Fortra International Ltd (EMEA/EUR/English), Fortra Computing Group S.L.U. (Spain/USD/Spanish). Each drives letterhead, bank block, tax registration, language and FX display.
2. **Country-local invoice numbering (Spain `S…`)** in addition to global `V…` — gapless legal sequence per regulated entity. Must be supported alongside the global ID in Workday/MuleSoft.
3. **Partner / reseller billing split** — Bill-to (reseller) ≠ Ship-to (end customer) appears in 4 of 7 deals; partner VAT/tax IDs on the document.
4. **Hardware/System grouping** — line items grouped under `Serial#/Model/Feature/Processors/System Type` (IBM i) or `Hardware ID / System Type`; IBM i lines additionally keyed by `LPAR` + `Name`.
5. **Transaction-type sections** — `New Software`, `New Maintenance`, `Subscriptions`, `Subscription Renewal`, `Renewal Maintenance`, `Services` — each with its own column set (dates vs. duration vs. none).
6. **Bundle rendering** — parent priced, components at $0.00; quote uses full concatenated names, invoice uses abbreviated `- component` names.
7. **Invoice-level summarization** of large ELA/Strategic-Agreement orders into a single bill line (Sysco) — invoice line count ≠ order line count.
8. **No quantity auto-consolidation** for redistribution partners (Dealertrack) — preserve discrete Qty-1 lines.
9. **Discount shown as absolute $, never %**; net Amount = Price − Discount.
10. **Tax = "Calculation pending" on quotes**, resolved on invoices; most invoices show 0.00 (services/intl), US ELA shows real sales tax.
11. **Payment status on invoice** — Amount Paid + date when paid; Amount Due when open.
12. **Boilerplate terms** — MSA reference, quote expiry banner, license-key note, signature page, PS terms page, $150K no-poach clause.

---

## 5. Open Questions / Ambiguities

- **Invoice↔quote linkage isn't always 1:1.** Sysco invoice V0000285819 cites quote **Q-0000416288** (not provided), while the sample quote is Q-0000429097 — confirms ELA deals span multiple quote versions. Need the mapping rule the new platform will use (order→invoice, not quote→invoice).
- **Spain `S…` sequence allocation** — is it Workday-assigned or RCA-assigned? Does it apply to other EU entities (Italy/Germany) or only Spain? Not stated here.
- **Discount % source** — documents print only the dollar discount; the underlying % (and whether it's partner-tier vs. line-level) must come from the pricing config (see `07_channel-partner-discounts-data.md`, `10_pricing-strategy-and-approval-matrix.md`).
- **Why some bundles print components at 0.00 vs blank** (V0000274389 shows both `(0.00)` and truly blank amount columns) — likely an extraction artifact, but DocGen needs a definitive "print 0.00 for components" rule.
- **Legacy `@helpsystems.com` contact data** still present (V0000212838) — migration must normalize contact/rep email domains.
- **The "Account (00…) " number** — confirm whether this legacy account number becomes a Salesforce external ID for account matching during migration.
- These are **legacy-system outputs** (D365/Experlogix + old SF). Need confirmation of which exact fields map to RCA Quote/Order/Asset objects and which are DocGen-derived vs. stored — cross-reference the design KB's DocGen/Workday sections.

---

## Sources

All under `Fortra Discovery Documentation/BSI Discovery Info/SamplePDFs/` (read from the extracted `…/Data/discovery-extract/text/…` `.txt` mirrors):

- `InvoiceQuoteDescriptions.txt` — scenario label/index file (read first)
- `V0000304974.pdf` ↔ `Q-0000455841.pdf` — new subscription w/ partner; **Spain unique invoice ID** S000006265
- `V0000304602.pdf` ↔ `Q-0000456763.pdf` — hourly project services (+ full PS terms page)
- `V0000304240.pdf` ↔ `Q-0000445897.pdf` — renewal w/ partner (EUR / EMEA entity)
- `V0000285819.pdf` ↔ `Q-0000429097.pdf` — large-line renewal collapsed to ELA summary (47-page quote; quote read in parts due to 265KB size)
- `V0000274389.pdf` ↔ `Q-0000400631.pdf` — renewal w/ multiple bundles
- `V0000215067.pdf` ↔ `Q-0000319668.pdf` — redistribution partner, ~150+ identical lines
- `V0000212838.pdf` ↔ `Q-0000319257.pdf` — new software sale, mixed software/maintenance/services

**Not extractable / gaps:** None — all 14 files (13 PDFs + the descriptions file) extracted to readable plaintext. No encrypted, binary, or empty files in scope. (Note: page 1 of some invoice extracts begins mid-cover-letter, an extraction artifact, not a content gap.)
