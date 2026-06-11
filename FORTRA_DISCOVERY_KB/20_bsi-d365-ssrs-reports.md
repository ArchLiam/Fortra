# BSI Discovery — D365 SSRS Reports (Quote / Order / Invoice / Credit)

> **Scope:** The six legacy SQL Server Reporting Services (`.rdl`) report definitions that produced Fortra's (formerly **HelpSystems** / **HS**) customer-facing documents out of **Microsoft Dynamics 365 / Dynamics CRM**. These documents — Quote (Detail & Summary), Order Confirmation, Invoice (Detail & Summary), and Credit Summary — are the *as-built reference* for what the corresponding **Salesforce RCA + DocGen** quote/order PDFs and the **Workday invoice/credit** documents must reproduce after CRM consolidation.
>
> **Why this matters for the migration:** These RDLs define the *exact* data fields, layout sections, conditional show/hide logic, brand-specific legal/EULA blocks, multi-currency handling, and translation (localization) mechanics of the legacy documents. They are the requirements source for the Salesforce DocGen templates (Quote PDF) and the Workday-generated Invoice/Credit documents. See the design-side companion `FORTRA_KNOWLEDGE_BASE.md` and the memory notes on the **DocGen Quote PDF pipeline** (template-bound DataRaptors) for the *target* implementation.

---

## 0. How to read these RDL extracts

Each `.txt` is a flattened extraction of an `.rdl` (XML) file. The useful, load-bearing structures are:

| Section | Meaning |
|---|---|
| `[QUERY]` (repeated) | One block per **dataset**. Contains the **FetchXML** query (Dynamics CRM's query language, not T-SQL) against CRM entities. Each block = one data source feeding the report. |
| `[FIELDS]` | The flat list of **report field names** (RDL `<Field>` names) available to the layout, including computed/expression fields. |
| `[TEXT NODES]` | RDL body text: data-source connection strings, parameter bindings, duplicated FetchXML, field `DataType`s, and **RDL expression formulas** (`=IIF(...)`, `=Switch(...)`, `=Lookup(...)`). These reveal the show/hide and branching logic. |

**Data platform note:** Datasets use the `MSCRMFETCH` data-extension (FetchXML), not SQL. "Tables joined" below = CRM entities linked via `<link-entity>`. Connection strings seen across the set:
- `https://hsdev2.crm.dynamics.com` (QuoteDetail, OrderConfirmation, CreditSummary, InvoiceSummary — D365 online dev)
- `https://hsintegration-dev.crm.dynamics.com` (InvoiceDetail — D365 online integration dev)
- `https://crm15uat.helpsystems.com/HSCRM15UAT` (QuoteSummary — on-prem CRM 2015 UAT; the oldest report)

The `hs_` prefix = HelpSystems custom (publisher) entities/attributes; un-prefixed = D365 out-of-the-box (`quote`, `quotedetail`, `invoice`, `invoicedetail`, `product`, `account`, `contact`, `systemuser`, `transactioncurrency`).

---

## 1. Report inventory (at a glance)

| Report | File | Root entity | Doc produced | Key params |
|---|---|---|---|---|
| **Quote Detail** | `hs_po_QuoteDetail.rdl` | `quote` / `quotedetail` | Full itemized customer quote (per-line, with subreport hardware/system detail) | `QuoteID`, `Language`, `BankId`, `CurrencyID`, `CRM_quote` |
| **Quote Summary** | `hs_po_QuoteSummary_CRM.rdl` | `quote` / `quotedetail` | Condensed quote grouped by reporting category (no system subreport) | `QuoteID`, `Language`, `BankId`, `CurrencyID`, `CRM_quote` |
| **Order Confirmation** | `hs_OrderConfirmation_CRM.rdl` | `invoice` (D365 invoice = the order/confirmation) | Order confirmation w/ license keys, export-control docs, hardware keys | `InvoiceID`/`CRM_invoice`, `Language`, `BankId`, `CurrencyID`, `HideWS`, `ShowHideFreeProducts` |
| **Invoice Detail** | `hs_po_InvoiceDetailCRM.rdl` | `invoice` / `invoicedetail` | Full itemized invoice (per-line + system subreport), online-pay link | `InvoiceID`/`CRM_invoice`, `Language`, `BankId`, `CurrencyID`, `HideWS`, `ShowHideFreeProducts` |
| **Invoice Summary** | `hs_po_InvoiceSummary_CRM.rdl` | `invoice` / `invoicedetail` | Condensed invoice grouped by reporting category | `InvoiceID`/`CRM_invoice`, `Language`, `BankId`, `CurrencyID` |
| **Credit Summary** | `hs_po_CreditSummary_CRM.rdl` | `invoice` (filtered `statecode=3` = Canceled/Credit) | Credit memo summary | `InvoiceID`/`CRM_invoice`, `Language`, `BankId`, `CurrencyID`, `HideWS`, `ShowHideFreeProducts` |

> **Architecture insight #1 — Orders & Invoices are the same D365 entity.** In this CRM, the `invoice` entity backs the Order Confirmation, the Invoice (Detail/Summary), *and* the Credit Summary. They differ only by **`statecode` filter** and which datasets/sections are rendered. Credit Summary explicitly filters `invoice.statecode = 3`. This is a strong cue for the SF→Workday model: a single financial object lifecycle, document type driven by status.

---

## 2. Shared dataset patterns (common to all six reports)

These datasets recur across the set and constitute the **document chrome** (header, footer, localization, remittance) that every legacy document carried. Reproduce these in DocGen/Workday templates.

### 2.1 Translation / localization — `hs_translation`
```
entity hs_translation
  attribute hs_value AS VALUE
  attribute hs_key   AS KEY
  filter hs_optionsetid = @Language
```
- Every report is **fully localizable**. Static labels (DATE, ACCOUNTNUMBER, QUOTENUMBER, NETTERMS, EXPIRATIONDATE, DAYS, etc.) are not hard-coded — they are resolved at render time via RDL `=Lookup("KEY", Fields!KEY.Value, Fields!VALUE.Value, "dsTranslation")`.
- `@Language` is an **option-set integer**. Known values seen in expressions: `717710000` = default (English), `717710004` = **French** (`IsLanguage_French` / `=IIF(Fields!Language.Value=717710004,1,0)`).
- **Implication for SF/DocGen:** the new quote/invoice templates need a label-translation table keyed by language, not English-only literals. French is the confirmed second language.

### 2.2 Legal entity, bank & remittance — `hs_hsbankaccounts`
```
entity hs_hsbankaccounts
  attributes: hs_taxlabel, hs_taxidphonewebsite, hs_registeredaddress, hs_currency,
              hs_bankinformationlabel, hs_bankinformation, hs_remitto, hs_remittolabel,
              hs_invoicelabel (invoice/credit/order only)
  filter hs_legalentity = @BankId  [+ hs_language = @Language on QuoteDetail & InvoiceDetail]
  link transactioncurrency (alias Currency): isocurrencycode, currencyname  WHERE transactioncurrencyid = @CurrencyID
```
- The **remit-to / bank wiring instructions / tax label / registered address** printed on the document are selected by **legal entity (`@BankId`) + currency (`@CurrencyID`)**, and (on the newer reports) by language. This is the per-legal-entity, per-currency remittance block.
- **Implication:** the Workday invoice/Salesforce quote PDFs must select remittance + bank + tax-registration text by **Selling Legal Entity × transaction currency × language**. This is a hard requirement, not cosmetic.

### 2.3 Legal-entity GUIDs (decoded from RDL `=IIF(...)` expressions)
The Quote/Invoice Detail reports branch document boilerplate (signature lines, EULAs, cover letter, professional-services terms) on the quote/invoice **`hs_legalentity` GUID**. Decoded mapping:

| Legal entity (report flag) | `hs_legalentity` GUID |
|---|---|
| **Fortra, LLC** (`IsLegalEntity_FortraLLC`) | `DDFB4089-BE25-E511-80C4-005056840EFE` *(also the default when null)* |
| **Fortra Computing Group** (`IsLegalEntity_FortraComputingGroup`) | `D9FB4089-BE25-E511-80C4-005056840EFE` |
| **Fortra International LTD** (`IsLegalEntity_FortraInternationalLTD`) | `D7FB4089-BE25-E511-80C4-005056840EFE` |
| **Fortra International PTY LTD** (`IsLegalEntity_FortraInternationalPTYLTD`) | `0C91C223-8070-E711-80E5-0050569F6BB1` |
| **Barcelona Computing Group** (`IsLegalEntity_BarcelonaComputingGroup`) | `7CDF0C3D-7C70-E711-80E5-0050569F6BB1` |
| **Terranova** (`IsLegalEntity_Terranova`) | `C59741B2-D132-ED11-9DB1-002248214BBB` **and** `CA9741B2-D132-ED11-9DB1-002248214BBB` |

> These GUIDs are CRM-instance-specific and will **not** survive migration as-is, but the **set of legal entities** (6) and their document-conditional behavior are the requirement. "Help/Systems, LLC" + currency = USD is referenced as a special tax-display case (`=iif(Fields!hs_legalentity.Value = "Help/Systems, LLC" And ...USD, FALSE, TRUE)`).

### 2.4 Net-terms & due-date logic (Invoice/Order/Credit)
- `hs_netterms` (integer days). Expression: `=iif(hs_netterms = "0", "Due Upon Reciept", hs_netterms)` (typo "Reciept" is verbatim in source).
- **Due date** = `createdon` (or `hs_updatedinvoicedate` if present) **+ `hs_netterms` days** via `DateAdd("d", hs_nettermsValue, ...)`.
- Quote reports use `hs_nettermsinteger` instead; due upon receipt handled identically.

---

## 3. Product / brand classification — the document grouping engine

All six reports classify each line by **product type** (D365 option-set `hs_producttype`) and **brand** (`hs_productbrand` → `hs_productbrandname`). These two dimensions drive: section grouping, sort order, and which legal/EULA blocks appear.

### 3.1 `hs_producttype` option-set (decoded from `=Switch`/`=IIF` expressions)

| Value | Meaning | Notes / report behavior |
|---|---|---|
| `717710000` | **Hardware Change** | If `hs_hwcproductid` populated → "Change Fee"; License Upgrade Fee maps here too; ReportingGroup sequence **2** |
| `717710001` | **Software** (New Software) | ReportingGroup sequence **1** (prints first) |
| `717710002` | **Services** | ReportingGroup sequence **6**; Linoma+Services drives training/services flags |
| `717710003` | **License Upgrade Fee** | sequence **5** |
| `717710004` | **Subscription** | sequence **3**; `Subscription` flag |
| `717710005` | **Renewal Maintenance** | sequence **4** |
| `717710006` | **Other** | sequence **9** (default) |

The **Summary** reports (Quote & Invoice) build a `ReportingGroup` string + `Sequence` integer per line from these, then group/sort the document body. The `=Switch` mapping for the report grouping label (Quote Summary):
```
HARDWARECHANGE | RENEWALMAINT | NEWSOFTWARE | NEWMAINTENANCE | SUBSCRIPTIONS
```
plus License Upgrade Fee folded into HARDWARECHANGE.

### 3.2 Brand-driven flags (computed RDL fields)
The QuoteDetail/InvoiceDetail/Summary reports compute boolean flags off `hs_productbrandname` to toggle brand-specific blocks. Brands explicitly referenced:

| Computed flag | Triggering brand(s) |
|---|---|
| `HasIM` | InterMapper |
| `HasAM` | AutoMate |
| `HasSB` | Skybot |
| `HasCore` | Core CTS, Core IGA, Core SCS |
| `HasRJS` | RJS |
| `HasLinoma` / `HasLinomaServices` / `HasLinomaTraining` | Linoma (Linoma + Services type; product name starting `"GoAnywhere Training"`) |
| `HasTerranova` | Terranova Security |
| `HasPhishlabs` | Phishlabs *(QuoteDetail only)* |
| `HasFortra` | (Fortra-branded; QuoteDetail / InvoiceDetail / CreditSummary) |
| `ShowCobaltStrikeText` / `ShowCoreEULA` | Cobalt Strike **or** Core CTS **or** Outflank |
| `ShowFortraProfServiceTerms` / `HideFortraProfServiceTerms` | driven by `hs_hidefortrapsterms` ("Yes"/"No") + product type ∈ {Software, Hardware Change, License Upgrade Fee} |

> **Migration note:** these brand families (InterMapper, AutoMate, Skybot, Core CTS/IGA/SCS, RJS, Linoma/GoAnywhere, Terranova, Phishlabs, Cobalt Strike, Outflank) are the legacy HelpSystems acquisitions. The conditional **EULA / professional-services-terms / cover-letter** content per brand is a real document requirement to carry into DocGen.

### 3.3 Product translation — `hs_producttranslation`
- Localized product descriptions/names come from `hs_producttranslation` filtered by `@Language` and `hs_producttranslationtype`:
  - `717710000` = product **description**
  - `717710001` = product **name** (report display name)
- Display-name resolution (QuoteDetail): translated name → `hs_reportproductname` → product `name` (first non-empty).

---

## 4. Per-report detail

### 4.1 Quote Detail — `hs_po_QuoteDetail.rdl`

**Purpose:** the full, line-itemized **customer quote PDF**, including a hardware/system **subreport** (`hs_quotedetailsubreport`) that enumerates physical systems (server type, serial, LPAR, model, processors, host) per quoted item.

**Datasets (7):**
1. `quotedetail` (+ link `quote`, `hs_productbrand`, `product`, `hs_producttranslation` ×2) — line product type/brand/translation, `hs_mycap`, `hs_includeprofessionalserviceterms`, `hs_hidefortrapsterms`.
2. `quote` (+ `account`, `transactioncurrency`, `contact` ×3 [buyer/billto/purchasing-agent], `systemuser` owner) — **header dataset** (see field map below).
3. `hs_translation` — labels.
4. `hs_hsbankaccounts` — remittance/bank (by `@BankId` + `@Language` + `@CurrencyID`).
5. `hs_quotedetailsubreport` (+ `product` → `hs_producttranslation`) — **system/hardware lines**.
6. `quote → quotedetail → hs_translation` — brand-name translation per line.
7. `quotedetail` WHERE `hs_mycap = True` (+ `product.hs_createsystemproduct`) — **myCAP** (capped/contract-term) lines: `hs_billingfrequency`, `hs_contractstartdate`, `hs_contractenddate`, `extendedamount`.

**Quote header field map (dataset 2 → report):**

| Report field | CRM source | Purpose on document |
|---|---|---|
| `quotenumber` | `quote.quotenumber` | Quote number |
| `createdon` / `effectivefrom` / `effectiveto` | `quote` | Quote date / valid-from / expiration |
| `AccountName` (computed) | `a.hs_accountinvoicename` ?? `a.name` | Customer/invoice name |
| `a_accountnumber`, `a_address1_line1`, `a_hs_locationid`, `a_fax` | `account` | Customer account no., address, location, fax |
| `BillToName` (computed) | reseller ?? purchasing-agent ?? invoice-name ?? account name | Bill-to display name (cascade) |
| `billto_*` / `shipto_*` (name, line1-3, city, postalcode) | `quote` | Bill-to / ship-to address blocks |
| `hs_billto_stateprovinceid`, `hs_billto_countryid`, `hs_shipto_*` | `quote` | State/country lookups |
| `hs_buyercontact[name]` + `c_fullname/telephone1/emailaddress1` | `contact` (buyer) | Buyer contact |
| `hs_billtocontact[name]` + `cbilling_*` | `contact` (bill-to) | Bill-to contact |
| `hs_purchasingagentcontact[name]`, `hs_purchasingagentaccount[name]` + `cpurchase_*` | `contact`/account | Purchasing agent / agent account |
| `hs_reseller` / `hs_resellername` | `quote` | Reseller (channel) |
| `owner_fullname/internalemailaddress/address1_telephone1` | `systemuser` | Quote owner (sales rep) |
| `transactioncurrencyid` / `tc_isocurrencycode` | `transactioncurrency` | Document currency |
| `totalamount`, `totaldiscountamount` | `quote` | Totals; discount |
| `NetTerms` (computed from `hs_nettermsinteger`) | `quote` | Payment terms |
| `hs_legalentity`, `hs_legalentityValueNoNull` | `quote` | Selling legal entity (→ legal/EULA blocks) |
| `hs_language` | `quote` | Document language |
| `hs_termsandconditions` | `quote` | T&Cs block |
| `hs_serviceexpirationmonths` | `quote` | Service expiration window |
| `hs_managerapprovalneeded` / `hs_managerapproved` + `statecode` | `quote` | Drives `ShowInvalidQuote` (watermark/blocker) |
| `hs_renewalmaintenancequote` | `quote` | Renewal-maint quote flag (`RenewalQuote`) |

**Show/hide flags (computed):**
- `HideDiscount` = `(totaldiscountamount = 0) OR (hs_showhidediscounts = false)` — suppress discount column.
- `ShowInvalidQuote` = quote not approved / wrong state (renewal quotes always valid; otherwise needs `hs_managerapproved` when `hs_managerapprovalneeded` and statecode ∈ {1,2}).
- `hs_showhidews` (workstation lines), `hs_showhidefreeproducts`, `hs_showhideproductnumber`, `hs_showhidesignaturelines` — column/section toggles stored on the quote.
- `Multiplier`, `HasMyCAP`, `SoftNewMaint`, `Subscription`, `Legal`, `Language` — computed.

**Quote-line / subreport field map (dataset 5 `hs_quotedetailsubreport`):**

| Field | Meaning |
|---|---|
| `hs_productname`, `hs_productsku`, `hs_bundlesku`, `hs_featurecode`, `hs_billcode` | Product identity / billing code |
| `hs_quantity`, `hs_itemamount`, `hs_extendedamount`, `hs_discountamount` | Qty, unit/item amount, extended, line discount |
| `hs_producttype` | Line product type |
| `hs_startdate`, `hs_enddate`, `hs_duration` | Term dates / duration |
| `hs_servertype`, `hs_hardwaretype`, `hs_modelname`, `hs_serialnumber`, `hs_hardwareidnumber`, `hs_systemid`, `hs_hostname` | Hardware/system identity |
| `hs_lparname`, `hs_lparnumber`, `hs_numberofprocessors`, `hs_licensingtype` | IBM-i / LPAR licensing detail |
| `hs_priorsysteminformation` | Prior-system info (upgrades/migrations) |
| `hs_mspenduser` | MSP end-user |
| `hs_salessupportnotes` | Sales/support notes (→ `IncludeSalesNotes`) |
| `hs_reportsequence` | Explicit line sort order |

> The presence of **LPAR / processors / server type / serial / system id** confirms the legacy quote document carried **IBM Power-i hardware-bound licensing detail**. This is the heaviest data requirement for any DocGen reproduction and is largely absent from a vanilla RCA quote line — it lived on a dedicated `hs_quotedetailsubreport` entity.

### 4.2 Quote Summary — `hs_po_QuoteSummary_CRM.rdl`

**Purpose:** condensed quote — same header as Quote Detail, but **no hardware subreport**; lines pulled directly from `quotedetail` and **grouped by reporting category** (`ReportingGroup`/`Sequence`). This is the oldest report (on-prem CRM 2015 UAT endpoint).

**Datasets (5):**
1. `quotedetail` (+ `hs_productbrand`, `product`, `hs_producttranslation`) — line type/brand/translation/flags.
2. `quote` (+ account / currency / contacts / owner) — header (same shape as QuoteDetail header, **minus** `hs_mycap`, `hs_showhidefreeproducts`, `hs_showhidesignaturelines`, `effectivefrom`, `hs_termsandconditions`, `hs_includeprofessionalserviceterms`).
3. `hs_translation` — labels.
4. `hs_hsbankaccounts` — remittance (by `@BankId` + `@CurrencyID`; **no** language filter — older).
5. `quote → quotedetail (link p=product, tc=currency)` — **the line dataset** with the financials:

| Field | Source | Meaning |
|---|---|---|
| `id_productid` / `id_productidname` | `quotedetail` | Line product |
| `id_priceperunit`, `id_quantity` | `quotedetail` | Unit price, qty |
| `id_baseamount`, `id_manualdiscountamount`, `id_extendedamount`, `id_tax` | `quotedetail` | Base, manual discount, extended, tax |
| `id_hs_hardwareid`, `id_hs_hwcproductid`, `id_hs_productformaintenance` | `quotedetail` | Hardware / change-fee / maintenance-of links |
| `p_hs_producttype`, `p_productnumber`, `p_name` | `product` | Type/SKU/name |
| `DisplayAmount`, `FinalAmount`, `ItemAmount` (computed) | — | `priceperunit × quantity`; `baseamount − manualdiscount` |
| `ReportingGroup`, `Sequence`, `TranslationKey` (computed) | — | Grouping label / sort / label-lookup key |
| `ShowHideDiscounts` (int) | `quote.hs_showhidediscounts` | discount column toggle |

> **Architecture insight #2 — two financial conventions coexist.** Quote *Summary* reads native `quotedetail` financial fields (`baseamount`, `manualdiscountamount`, `priceperunit`, `extendedamount`, `tax`). Quote *Detail* and *Invoice Detail* additionally rely on the `hs_quotedetailsubreport` (`hs_itemamount`/`hs_extendedamount`/`hs_discountamount`). The two must reconcile to the same `totalamount`. Watch this when mapping to RLM line pricing fields (NetUnitPrice / TotalLineAmount / NetTotalPrice) — the Summary "ItemAmount = base − manual discount" definition is the cleanest analog.

### 4.3 Order Confirmation — `hs_OrderConfirmation_CRM.rdl`

**Purpose:** the **order confirmation** document. Backed by the D365 `invoice` entity but enriched with **license keys**, **export-control documents**, and **hardware license keys** — i.e., the fulfillment-facing confirmation.

**Datasets (10):**
1. `invoice` (+ account, currency, `contact` ×3 [licensekeycontact / billto / purchasing-agent], `systemuser` owner, `systemuser` AccSpecialist) — header (invoice field map, §4.4).
2. `hs_translation` — labels.
3. `hs_hsbankaccounts` — remittance.
4. `hs_quotedetailsubreport` WHERE `hs_invoiceid = @InvoiceID` — **system/hardware lines** (same field set as §4.1 dataset 5).
5. `hs_applicationsetting` WHERE `hs_key = 'InvoicePaymentURL'` — online-payment base URL (→ `ShowPayOnline`).
6. `invoicedetail` (+ `hs_productbrand`, `product`, `hs_producttranslation`, `invoice`) — line type/brand/translation; `hs_shiptocountryregion`.
7. `hs_exchangerates` (→ EUR) — `hs_rate`, `hs_currencyone`, `hs_currencytwo`, `hs_startdate`/`hs_enddate`, filtered to `transactioncurrency.currencyname = 'euro'` — **EUR-equivalent display** (`ExchFk`/`HasEurope`).
8. `hs_licensekeys` WHERE active (`statecode=0`), linked via `invoicedetail.hs_systemproduct` — **software license keys** (`hs_licensekeynumber`, `hs_licensekeyserialnumber`, `createdon`).
9. `hs_exportcontroldocument` (intersect `hs_invoice_hs_exportcontroldocument`; + `hs_exportcontroldocumenttype`) — **export-control license numbers** (`hs_licensenumber`, type `hs_name`/`hs_reportingdescription`).
10. `hs_licensekeys` linked via `invoicedetail.hs_hardware` — **hardware license keys**.

**Confirmation-specific elements (vs. plain invoice):**
- **License-key contact** (`hs_licensekeycontact`) is a distinct contact role — who receives software keys.
- **Export-control documents** block — regulatory (ECCN-type) license numbers tied to the order.
- **Account Specialist** (`hs_accountspecialist`, alias `AccSpecialist`) printed alongside the Owner.
- `hs_ccigpasscode` (CCIG passcode), `hs_vatnumber`, `hs_spaininvoiceid` (Spain-specific invoice id) — region/regulatory fields.

### 4.4 Invoice Detail — `hs_po_InvoiceDetailCRM.rdl`

**Purpose:** the full itemized **invoice PDF** — the most complex and **newest** report (integration-dev endpoint `https://hsintegration-dev.crm.dynamics.com`, 824 KB source). Carries the most legal-entity branding (incl. Fortra, Terranova, French) and an online-payment-allowed gate.

**Datasets (8):**
1. `invoice` (+ account, currency, `contact` billto/purchasing-agent, `systemuser` owner / AccSpecialist / **createdby**) — header. Note this one adds the **`createdby`** systemuser link (creator's name/phone/email on the doc).
2. `hs_translation` — labels.
3. `hs_hsbankaccounts` — remittance (filtered by `@BankId` **and** `@Language`).
4. `hs_quotedetailsubreport` (+ `product` → `hs_producttranslation` type `717710001`) WHERE `hs_invoiceid = @InvoiceID` — **system/hardware lines** with translated names.
5. `hs_applicationsetting` (`InvoicePaymentURL`).
6. `invoicedetail` (+ `hs_productbrand`, `product` [+ `hs_hidefortrapsterms`] → `hs_producttranslation` type `717710001`, `invoice`) — line type/brand/translation + Fortra prof-services-terms toggle.
7. `hs_exchangerates` (→ EUR) — EUR-equivalent.
8. `hs_invoicepaymentinformation` WHERE `hs_invoice = @InvoiceID` — `hs_portalpaymentallowed` → final **ShowPayOnline** gate (portal-payment allowed flag).

**Invoice header field map (dataset 1 → report) — shared by InvoiceDetail / InvoiceSummary / OrderConfirmation / CreditSummary:**

| Report field | CRM source | Purpose |
|---|---|---|
| `invoicenumber` | `invoice.invoicenumber` | Invoice / document number |
| `hs_spaininvoiceid` | `invoice` | Spain statutory invoice id |
| `createdon` / `hs_updatedinvoicedate` | `invoice` | Invoice date (updated overrides) |
| `duedate` (computed) | `createdon`/`updated` + `hs_netterms` | Payment due date |
| `hs_ponumber` | `invoice` | Customer PO number |
| `hs_netterms` (→ `NetTerms`) | `invoice` | Payment terms (0 = Due Upon Receipt) |
| `hs_paidinfulldate` | `invoice` | Paid-in-full date |
| `AccountName` (computed) | `a.hs_accountinvoicename` ?? `a.name` | Customer/invoice name |
| `a_accountnumber`, `a_address1_line1`, `a_hs_locationid`, `a_fax` | `account` | Customer no./address/location/fax |
| `billto_*` (name, line1-3, city, stateorprovince, postalcode, country) | `invoice` | Bill-to address (free-text on invoice, not lookups) |
| `shipto_*` (line1-3, city, stateorprovince, postalcode, country) | `invoice` | Ship-to address |
| `hs_billtocountryregion`, `hs_shiptocountryregion` | `invoice` | Country/region codes (option-set) |
| `hs_resellerpartner` / `hs_resellerpartnername` | `invoice` | Reseller partner (channel) |
| `hs_purchasingagentaccount` / `hs_purchasingagentcontact` (+ `cpurchase_*`) | invoice/contact | Purchasing agent |
| `hs_billtocontact` (+ `c_fullname/telephone1/emailaddress1`) | contact | Bill-to contact |
| `Owner_*`, `AccSpecialist_*`, `createdby_*` | `systemuser` | Owner / account specialist / creator |
| `transactioncurrencyid` / `tc_isocurrencycode` / `Currency_currencyname` | currency | Document currency |
| `hs_taxrate`, `totaltax` | `invoice` | Tax rate & total tax |
| `hs_vatnumber`, `hs_taxlabel`, `hs_taxidphonewebsite` | invoice / bank | VAT no. & tax labels |
| `totalamountlessfreight` | `invoice` | Subtotal (pre-freight) |
| `totaldiscountamount` | `invoice` | Total discount |
| `totalamount` | `invoice` | Grand total |
| `hs_creditsapplied` | `invoice` | Credits applied |
| `hs_amountpaid` | `invoice` | Amount paid |
| `hs_amountdue` | `invoice` | **Balance due** |
| `hs_ccigpasscode` | `invoice` | CCIG passcode |
| `hs_legalentity` / `hs_legalentityname` | `invoice` | Selling legal entity |
| `hs_invoicereportaddress`, `hs_invoicereportshiptostatescountries` | `invoice` | Address-display toggles |
| `hs_showhidediscounts`, `hs_showhidews`, `hs_showhidefreeproducts`, `hs_showhidecontactonorderform` | `invoice` | Section/column toggles |
| `statecode` | `invoice` | Doc state (drives Credit vs Invoice) |

**Invoice-line field map (`invoicedetail` + `hs_quotedetailsubreport`):** same line/system fields as the quote subreport (§4.1 dataset 5): `hs_productsku`, `hs_bundlesku`, `hs_quantity`, `hs_itemamount`, `hs_extendedamount`, `hs_discountamount`, `hs_startdate`/`hs_enddate`/`hs_duration`, hardware/LPAR/system identity, `hs_billcode`, `hs_salessupportnotes`, `hs_reportsequence`. Plus `invoicedetail` natives: `priceperunit`, `quantity`, `baseamount`, `manualdiscountamount`, `extendedamount`, `tax`, `hs_hardwareid`, `hs_hwcproductid`, `hs_productformaintenance`, `hs_subscriptionrenewal`.

**Invoice show/hide line filters (RDL expressions):**
- `HideWS` param + `hs_billcode = "WS"` → suppress/show **workstation** lines (`FilterType` WS vs Other).
- `ShowHideFreeProducts` param → if "Show" → All; else hide lines where `hs_itemamount = 0` (free items).
- `IncludeSalesNotes` = true when `hs_salessupportnotes` is empty.
- `SoftNewMaint` (computed): `New Software`/`Subscription`/`Services` → "Software Only"; `New Maintenance` → "Maintenance Only"; else "Default" — drives EULA/terms grouping.

### 4.5 Invoice Summary — `hs_po_InvoiceSummary_CRM.rdl`

**Purpose:** condensed invoice — same invoice header (§4.4), lines grouped by `ReportingGroup`/`Sequence`. **No** export-control / license-key datasets, **no** portal-payment-allowed gate. Has the EUR-exchange path **omitted** vs Detail (no `hs_exchangerates`), and uses `hs_purchasingagentcontact` (not account) as the purchasing-agent contact link.

**Datasets (7):** `invoice` header; `hs_translation`; `hs_hsbankaccounts`; `hs_quotedetailsubreport` (systems); `hs_applicationsetting` (pay URL); `invoicedetail` (brand/type/translation); and the **summary line dataset** — `invoice → invoicedetail (p=product, tc=currency)` mirroring Quote Summary dataset 5: `id_priceperunit/quantity/baseamount/manualdiscountamount/extendedamount/tax`, `p_hs_producttype/productnumber/name`, computed `DisplayAmount`, `FinalAmount`, `ItemAmount`, `ReportingGroup`, `Sequence`, `TranslationKey`, `DateToDisplayOnReport`.

### 4.6 Credit Summary — `hs_po_CreditSummary_CRM.rdl`

**Purpose:** the **credit memo** summary. Identical structural shape to Invoice Summary/Order Confirmation header, but the root `invoice` dataset adds **`filter statecode = 3`** — i.e., this report only renders **canceled/credit-state invoices**. Carries the EUR exchange-rate dataset (like Order Confirmation / Invoice Detail).

**Datasets (7):** `invoice` (WHERE `statecode=3`; + account, currency, billto contact, purchasing-agent contact, owner, AccSpecialist); `hs_translation`; `hs_hsbankaccounts`; `hs_quotedetailsubreport` (systems, by `@InvoiceID`); `hs_applicationsetting` (pay URL); `invoicedetail` (brand/type/translation + ship-to country); `hs_exchangerates` (→ EUR).

**Field set** = invoice header + line field maps from §4.4 (the `[FIELDS]` list is the InvoiceSummary set plus `HasFortra`/`HasTerranova`/`HasEurope`). Same totals block: `totalamountlessfreight`, `totaldiscountamount`, `totaltax`, `totalamount`, `hs_creditsapplied`, `hs_amountpaid`, `hs_amountdue`.

> **Architecture insight #3 — credit = a state-filtered invoice, not a separate object.** A credit memo in legacy CRM is just an `invoice` with `statecode=3`, rendered through the same template family. For SF→Workday: confirm whether credits are modeled as negative invoices / credit memos in Workday and ensure the document selector keys on status.

---

## 5. Cross-cutting requirements for the SF RCA / DocGen / Workday target

| Legacy capability (from RDLs) | Target consideration |
|---|---|
| **Localization** via `hs_translation` keyed by `@Language` option-set (English `717710000`, French `717710004`) | DocGen / Workday templates need a label-translation layer + product description/name translation (`hs_producttranslation`). French confirmed. |
| **Per-legal-entity × currency × language remittance/bank/tax block** (`hs_hsbankaccounts`) | Workday invoice + SF quote PDF must select remit-to, bank wiring, registered address, tax label by **Selling Legal Entity (6 entities) × currency × language**. |
| **6 legal entities** with conditional EULA / signature-lines / cover-letter / prof-services-terms | Map legacy GUIDs → SF/Workday legal-entity records; carry conditional legal-block logic into DocGen. |
| **Brand-conditional content** (10+ brands; Cobalt Strike/Core/Outflank EULA, Fortra prof-svc terms, Terranova, Phishlabs) | DocGen template needs brand-driven conditional sections; brand lives on Product2 in RCA. |
| **Product-type grouping & sequence** (7-value option-set → ReportingGroup/Sequence) | Reproduce section grouping/ordering on the RCA quote/order documents. |
| **Hardware / IBM-i LPAR licensing detail** on lines (`hs_quotedetailsubreport`: server type, serial, LPAR, processors, system id, prior-system info) | Heaviest gap — vanilla RCA quote lines don't carry this; needs a system/asset child structure if these documents are reproduced. |
| **Show/hide toggles** (discounts, workstation/WS lines, free $0 products, product number, signature lines, contact-on-order-form) | Carry as quote/order flags + DocGen conditional rendering. |
| **License keys + export-control docs** on Order Confirmation | Fulfillment-side document data; confirm source in target (assets / entitlement / export-control). |
| **Online-pay link** (`InvoicePaymentURL` app-setting + `hs_portalpaymentallowed` gate) | Workday/portal pay-online equivalent. |
| **EUR-equivalent display** via `hs_exchangerates` (non-EUR doc shows EUR conversion) | Multi-currency display requirement — relates directly to memory note **SC-3384 multi-currency pricing** (currency-blind USD lookups). |
| **Financials**: `totalamountlessfreight`, `totaldiscountamount`, `totaltax`, `totalamount`, `hs_creditsapplied`, `hs_amountpaid`, `hs_amountdue`; line `baseamount − manualdiscountamount = ItemAmount` | Map to RLM/Workday totals; the Summary `ItemAmount` definition is the cleanest "net line" analog. |
| **Roles printed**: Owner (rep), Account Specialist, Created By, Buyer / Bill-to / Purchasing-agent / License-key contacts, Reseller partner | Ensure these contact/role relationships exist on SF Quote/Order and flow to Workday. |
| **Regulatory fields**: `hs_vatnumber`, `hs_taxrate`, `hs_taxlabel`, `hs_ccigpasscode`, `hs_spaininvoiceid` (Spain), country/region option-sets | Carry tax/VAT/statutory-id fields to Workday invoicing. |

---

## 6. Open questions / ambiguities

1. **Order vs Invoice object boundary.** Legacy uses the single D365 `invoice` entity for Order Confirmation, Invoice, and Credit. In the SF RCA + Workday target, are these split (Order in SF, Invoice/Credit in Workday)? Which system owns the document generation for each? (DocGen handles SF Quote/Order PDFs per memory; Workday likely owns Invoice/Credit.)
2. **`hs_quotedetailsubreport` provenance.** This entity carries the hardware/LPAR/system detail and is linked by both `hs_quoteid` and `hs_invoiceid`. Is it a denormalized snapshot built by CRM workflow? Its RCA/asset equivalent is undefined here.
3. **Translation coverage.** Only English (`717710000`) and French (`717710004`) are confirmed in expressions. Are other languages in the `hs_translation` table (the FetchXML pulls *all* keys for a given `@Language`)? Need the data, not just the report.
4. **Legal-entity GUID remap.** The 6 GUIDs are CRM-instance-specific. A crosswalk to Workday/SF legal-entity records is required and not in these files.
5. **EUR-only conversion.** The exchange-rate datasets hard-filter to `currencyname = 'euro'`. Is EUR the only secondary display currency, or is this a legacy artifact superseded by RCA multi-currency? (Connects to SC-3384.)
6. **`ShowInvalidQuote` watermark.** QuoteDetail computes an invalid/unapproved-quote indicator from manager-approval + statecode. Confirm the equivalent approval-state gating on RCA quote PDFs.
7. **Field-level financial reconciliation.** Two amount conventions (`quotedetail`/`invoicedetail` natives vs `hs_quotedetailsubreport` `hs_*amount`) must reconcile; the exact rounding/tax handling isn't fully visible in the truncated expression nodes.
8. **`hs_mycap` (myCAP) semantics.** QuoteDetail has a dedicated myCAP dataset (`hs_billingfrequency`, contract start/end, `hs_createsystemproduct`). Definition of myCAP (a capped/committed-spend program?) and its RCA mapping are unclear.

---

## 7. Connections to existing knowledge base

- **DocGen Quote PDF pipeline** (memory `project_docgen_quote_pdf_pipeline.md`): these RDLs are the *legacy* equivalent of the target DocGen Quote PDF (template-bound DataRaptors). The brand/legal/show-hide conditionals here are exactly the kind of logic that lives in the DocGen templates.
- **SC-3384 multi-currency** (memory `project_sc3384_multicurrency_pricing.md`): the EUR-exchange and per-currency remittance logic here is the legacy precedent for currency-aware document rendering — and a reminder that documents must handle non-USD correctly (the legacy reports *did* via `hs_exchangerates` + currency-filtered bank accounts).
- **Workday integration** (SC-3143 family): invoice header fields (`hs_vatnumber`, `hs_taxrate`, `totalamountlessfreight`, `hs_amountdue`, net terms / due date) are the legacy analog of the Workday Contract/Billing field maps.
- **Design KB** (`FORTRA_KNOWLEDGE_BASE.md`): complements the design-side description of quote/order/invoice flows; this doc supplies the *concrete legacy document field inventory*.

---

## Sources

All read in full (the load-bearing `[QUERY]` FetchXML datasets and `[FIELDS]` lists were captured for every report; `[TEXT NODES]` expression/formula logic captured where present):

- [hs_po_QuoteDetail.rdl](Fortra Discovery Documentation/BSI Discovery Info/D365 SSRS reports/hs_po_QuoteDetail.rdl) → `discovery-extract/text/BSI Discovery Info/D365 SSRS reports/hs_po_QuoteDetail.rdl.txt`
- [hs_po_QuoteSummary_CRM.rdl](Fortra Discovery Documentation/BSI Discovery Info/D365 SSRS reports/hs_po_QuoteSummary_CRM.rdl) → `…/hs_po_QuoteSummary_CRM.rdl.txt`
- [hs_OrderConfirmation_CRM.rdl](Fortra Discovery Documentation/BSI Discovery Info/D365 SSRS reports/hs_OrderConfirmation_CRM.rdl) → `…/hs_OrderConfirmation_CRM.rdl.txt`
- [hs_po_InvoiceDetailCRM.rdl](Fortra Discovery Documentation/BSI Discovery Info/D365 SSRS reports/hs_po_InvoiceDetailCRM.rdl) → `…/hs_po_InvoiceDetailCRM.rdl.txt`
- [hs_po_InvoiceSummary_CRM.rdl](Fortra Discovery Documentation/BSI Discovery Info/D365 SSRS reports/hs_po_InvoiceSummary_CRM.rdl) → `…/hs_po_InvoiceSummary_CRM.rdl.txt`
- [hs_po_CreditSummary_CRM.rdl](Fortra Discovery Documentation/BSI Discovery Info/D365 SSRS reports/hs_po_CreditSummary_CRM.rdl) → `…/hs_po_CreditSummary_CRM.rdl.txt`

**Extraction note:** the two largest extracts (`hs_po_QuoteDetail.rdl.txt`, `hs_po_InvoiceDetailCRM.rdl.txt`) contain very long `[TEXT NODES]` tails of repeated field-`DataType` declarations and RDL layout primitives; these were sampled (the meaningful expression logic and all `[QUERY]`/`[FIELDS]` content were read in full). No in-scope file was encrypted, binary, or empty.
