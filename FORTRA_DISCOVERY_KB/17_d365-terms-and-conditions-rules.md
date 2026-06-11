# 17 — D365 Terms & Conditions Rules (Quote & Invoice document text)

> **Scope.** The legacy **Microsoft Dynamics 365 (D365)** rules that auto-inserted **Terms & Conditions (T&C) text blocks** onto generated **Quote** and **Invoice** documents, and that Fortra must re-implement in **Salesforce Revenue Cloud Advanced (RCA)** — almost certainly as **conditional sections in the DocGen / OmniStudio document templates** that render the Quote PDF and the Invoice. Source folder: [`Quotes and Billing/D365 TandC Rules`](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/D365%20TandC%20Rules). Two files only: [QUOTE Terms and Condition Rules.docx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/D365%20TandC%20Rules/QUOTE%20Terms%20and%20Condition%20Rules.docx) and [INVOICE Terms and Condition Rules.docx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/D365%20TandC%20Rules/INVOICE%20Terms%20and%20Condition%20Rules.docx).
>
> **What this is.** Raw discovery input documenting *legacy behavior to preserve*. Each "rule" is a **condition (trigger) → exact clause text** mapping. The clause text below is **verbatim** — it is contract language and must be reproduced exactly, not paraphrased, when rebuilt in Salesforce. This complements the design KB (`FORTRA_KNOWLEDGE_BASE.md`) and the live DocGen Quote-PDF pipeline notes; where this doc lists *what text appears when*, the design/runtime work governs *how the template emits it*.
>
> **Connection to live SF work.** The auto-memory note "DocGen Quote PDF pipeline" establishes that the Quote PDF body is built by **template-bound DataRaptors** (`useTemplateDRExtract=Yes`), not the IntegrationProcedure, and that prehooks (e.g. `QLDescriptionGeneratorPrehook`) shape line text. These T&C blocks are the **static/conditional boilerplate** that must be emitted by the same template engine, gated on the conditions captured here. Re-implementing them is a DocGen template-logic task, not a pricing task.

---

## 1. Document model — two outputs, shared sub-rules

Both legacy documents share the same building-block sections; only the **T&C clause** differs between Quote and Invoice. The sections that recur (License Key, Tax Text, Service Terms) are **identical text** across the two docs but have **different trigger conditions** on the Invoice.

| Section | On QUOTE? | On INVOICE? | Trigger differs between docs? |
|---|---|---|---|
| **T&C clause** (EULA / Master Solutions Agreement / Service Order) | Yes — brand-driven, the bulk of the logic | **None** (Invoice has no top-level T&C clause) | Yes — Invoice intentionally omits it |
| **License Key** text | Yes | Yes | No — same trigger (new maintenance present, not subscription) |
| **Tax Text** | Yes | Yes | **Yes** — Invoice additionally requires *new maintenance* on the quote |
| **Service Terms** | Yes — full multi-clause block | Yes — but **collapsed to a single sentence** | Yes — Invoice shows a one-line pointer, not the full terms |
| **Signature Page** | Yes | No | n/a |

> **Key takeaway for the rebuild:** model these as **reusable conditional template fragments**, each with its own boolean trigger, and assemble the Quote and Invoice documents from the same fragment library. The Quote document is the rich one; the Invoice reuses three fragments with tightened/relaxed triggers and one shortened variant.

---

## 2. QUOTE document rules

Source: [QUOTE Terms and Condition Rules.docx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/D365%20TandC%20Rules/QUOTE%20Terms%20and%20Condition%20Rules.docx).

### 2.1 EULA / T&C clause — brand-driven (the primary rule set)

The T&C clause shown on the quote is selected by **product brand** present on the quote lines. Three behaviors:

1. **Standard EULA text** (two brand groups, below) — auto-applied.
2. **Custom T&C brands** — a defined set of brands that *allow* their own custom T&C starting text (Service-Order style), with per-brand variants.
3. **Legal-entity suppression** — the EULA text is fully hidden for two legal entities regardless of brand.

#### 2.1.1 Legal-entity suppression (overrides brand text)

> **Condition:** *"Eula text does not display when the quote's legal entity is"* one of:
> - **Fortra Argentina S.R.L.**
> - **Fortra Computing Group, S.L.U.**

These two entities still get **Tax Text** (§2.4) instead. In RCA, gate the EULA fragment on `Quote.Legal_Entity__c NOT IN ('Fortra Argentina S.R.L.', 'Fortra Computing Group, S.L.U.')`.

#### 2.1.2 Multi-brand behavior

> **Condition:** *"If more than one product brand is on the quote, based on products, and there is different text, both will be shown."*

So the EULA fragment is **not single-select** — it must iterate over the distinct brands on the quote, dedupe the resulting clause text, and concatenate all distinct clauses. RCA implication: the brand→clause mapping must run per distinct brand on the line set, then union the text.

#### 2.1.3 Brand group A — Offensive Security EULA (URL clause)

> **Brands:** Cobalt Strike, Outflank, Core CTS
>
> **Text (verbatim):**
> "This Quote is subject to the terms and conditions set forth in `https://static.fortra.com/infrastructure-protection/pdfs/EULA-Offensive-Security-Solutions.pdf`"
>
> (rendered as an `<a href=...>` link to that PDF)

#### 2.1.4 Brand group B — Fortra Master Solutions Agreement (the default for most brands)

> **Brands:** Core IGA, PowerTech, Robot, Linoma, AutoMate, Beyond Security, Bytware, CCSS, Clearswift, Core SCS, Digital Defense, Fortra Security Services, Halcyon, InterMapper, JAMS, PowertechX, RJS, Safestone, SEQUEL, ShowCase, Skybot, Tango04, TeamQuest, Terranova Security
>
> **Text (verbatim):**
> "This Quote is subject to the terms and conditions set forth in the Fortra Master Solutions Agreement and applicable Solution Specific Schedule(s) located at `www.fortra.com/legal`"
>
> (link target `https://www.fortra.com/legal`)

#### 2.1.5 Custom-T&C brands

> **Brands that allow Custom T&C's:** Agari, PhishLabs, Digital Guardian, Titus, Boldon James, Vera

These brands use **Service-Order-style starting text** with **New Sale** vs **Renewal/Add-on** variants. Note **Boldon James / Titus / Vera / Digital Guardian** in practice fall back to the **Master Solutions Agreement** text (§2.1.7), while **PhishLabs** and **Agari** have the full Service-Order language (§2.1.6).

#### 2.1.6 PhishLabs & Agari — Service Order starting text

PhishLabs and Agari share **identical** text. There are two transaction-type variants.

**New Sale (PhishLabs & Agari) — verbatim:**
> "This Service Order is issued under and subject to the **Governing Terms** (link `https://www.fortra.com/master-solutions-agreement`) which are incorporated herein by reference. Any purchase order terms and conditions issued by Client for the same Services are null and void. The Services ordered above are described in, and subject to the terms in, the separate Service Description documents which are incorporated herein by reference and may be enhanced from time to time by Fortra.
>
> This Service Order will automatically renew for additional, successive one year terms unless either party gives the other party written notice of non-renewal at least **sixty (60) days** prior to the expiration of the then-current term.
>
> **Invoicing:** All Service Fees and Payment are exclusive of any applicable sales, use, excise, or VAT taxes. Client will be invoiced the non-refundable Total First Year Fees upon Client's execution of this Service Order. The Annual Service Fee will increase annually after the initial Service Term unless this Service Order is terminated or not renewed per the above terms.
>
> For a multi-year Service Term, Client will be invoiced the Annual Service Fee annually thereafter."

**Renewal and Add-on Sale (PhishLabs & Agari) — verbatim:**
> "This Service Order is issued under and subject to the **Governing Terms** (link `https://www.fortra.com/master-solutions-agreement`) which are incorporated herein by reference **(unless there is a separately existing services agreement between the parties which is applicable to this Service Order)**. Any purchase order terms and conditions issued by Client for the same Services are null and void. The Services ordered above are described in, and subject to the terms in, the separate Service Description documents which are incorporated herein by reference and may be enhanced from time to time by Fortra.
>
> This Service Order will automatically renew for additional, successive one year terms unless either party gives the other party written notice of non-renewal at least **sixty (60) days** prior to the expiration of the then-current term."

> **Note:** the Renewal/Add-on variant **drops the Invoicing paragraph and the multi-year sentence**, and **adds** the "unless there is a separately existing services agreement…" carve-out. This New-Sale-vs-Renewal split is the only place where **transaction type** (not brand) drives the clause; in RCA this maps to the Quote's order-type / `Type` (New vs Renewal vs Add-on).

#### 2.1.7 Boldon James, Titus, Vera, Digital Guardian — Master Solutions Agreement text

> **Condition:** New Sale **and** Renewal (same text for both).
>
> **Text (verbatim):**
> "This Quote is subject to the terms and conditions set forth in the Fortra Master Solutions Agreement and applicable Solution Specific Schedule(s) located at `www.fortra.com/legal`"

(This is the **same string** as brand group B in §2.1.4 — these four "custom-allowed" brands default to the standard MSA clause unless overridden with custom text.)

### 2.2 License Key text

> **Condition:** *"This text is displayed when a quote has new maintenance on it. Not displayed for Subscriptions."*
>
> **Text (verbatim):**
> "Temporary license keys are issued upon receipt of order. Permanent license keys are issued upon receipt of payment in full."

RCA gate: there is a **new maintenance** line (perpetual maintenance), and the quote is **not** a subscription. Ties to the perpetual-license / maintenance line model.

### 2.3 Tax Text (Argentina / Spain entities)

> **Condition:** the **legal entity** of the quote is one of two entities. Each entity has its own text.

| Legal entity | Tax Text (verbatim) |
|---|---|
| **Fortra Argentina S.R.L.** | "The values do not include IVA. Stamp tax and municipal tax are responsibility of the customer." |
| **Fortra Computing Group, S.L.U.** | "The values do not include IVA. We accept withholding income tax only with documentation. Other taxes and withholdings will be paid by the customer." |

These are the **same two entities** for which the EULA is suppressed (§2.1.1) — i.e. for AR/ES entities the document swaps the EULA clause for entity-specific tax language. (`S.R.L.` = Argentina; `S.L.U.` = Spain/Fortra Computing Group.)

### 2.4 Service Terms (full block — Quote only)

> **Condition:** *"This text is displayed if the Quote has a services product and none of those products have 'Hide Fortra Professional Services Terms' set to Yes."*

So the trigger is: **at least one services product on the quote** AND **no services line has `Hide Fortra Professional Services Terms = Yes`** (a product-level flag — a single opted-out services line suppresses the whole block). RCA implication: this is a product attribute (`Hide_Fortra_Professional_Services_Terms__c` or equivalent) checked across all services lines with an ALL/none aggregation.

**Service Terms block (verbatim, all clauses):**

1. "Services will be invoiced upon order execution. Services payment is required upfront within Net Terms. Pre-paid services are not dependent on delivery or completion. Services expire **12 months** from the date of purchase. All fees are nonrefundable."
2. "For onsite services, consultant(s) expenses are invoiced following the visit. Customer is responsible for any costs associated with changes in travel arrangements made at the customer's request."
3. "**Completion Criteria:** Services will end when one of the following first occurs: 1) We complete the project, or 2) We complete the number of hours, or Services expire, or 3) Either of us terminates the project stated with written notice to the other party."
4. "If further assistance is required for services outside of these terms, Fortra will provide another contract for said services."
5. "Scheduled remote working sessions must be scheduled in continuous blocks of time with a minimum of **1-hour blocks** for on-demand service requests and **2-hour blocks** for implementation and migration services."
6. "The Services shall be performed in accordance with a mutually agreeable schedule. Fortra shall perform the Services during Fortra's normal business hours **8:30am and 5:00pm Monday through Friday** at the location of the consultant, excluding holidays, unless otherwise agreed in writing."
7. "If, during the engagement, by mutual agreement the description of the Services and/or the cost estimate changes, a written change order must be prepared and signed by you and Fortra."
8. "If the Services include Fortra installing or updating software on Customers systems, Customer acknowledges that Fortra will not be responsible for any damage to, or disruption of Customers systems or other software. The cumulative liability of Fortra for all claims relating to or from Services will not exceed the total fees paid to Fortra by you."
9. "Any modifications to Fortra products and/or any custom software developed by Fortra for (the "Customized Code") are delivered on an "AS IS" basis without warranty or representation of any kind. Customized Code is not supported by Fortra and is not subject to any maintenance or support plan covering the underlying Fortra products."
10. "The deliverables are delivered to you on an "AS IS" basis without warranty or representation of any kind. Fortra hereby disclaims all representations and warranties, express or implied, oral, or written, in fact, arising by operation of law or otherwise, except as expressly stated in this quote and designated as representations or warranties, including without limitation all warranties of merchantability or fitness for a particular purpose."
11. "The entire right, title, and interest in and to the Work and the Other Intellectual Property, including without limitation, all copyrights, patent rights, trade secrets and all other worldwide intellectual property rights therein, shall be and remain with Fortra. Any Services work created or developed by Fortra for this engagement are licensed to Customer as part of the underlying Fortra software and are subject to the terms and conditions of the existing license between Fortra and you."
12. "We do our best to accommodate schedule changes, however we require a minimum of **2 business days'** notice for scheduled remote working sessions that are less than 8 hours, **5 business days'** notice for full-day engagements and **10 business days'** notice for changes to scheduled onsite visits. If a cancellation is made within these windows or in the event of a no-show, we reserve the right to charge for the scheduled session/visit."
13. "Services may be terminated by you or Fortra with **thirty (30) days** written notice if the other party breaches the Services terms unless the breaching party cures the breach within the thirty-day period. Fortra may stop work and terminate Services immediately upon written notice if you fail to make any payment when due to Fortra."
14. "Customer will not solicit or offer employment to any Fortra employee who performs Services under this engagement during the term of this engagement and for a period of **six (6) months** thereafter. If Customer employs or engages as a consultant an individual who has been assigned by Fortra as a resource for a Services engagement, then Customer shall pay to Fortra a fee of **$150,000**, as liquidated damages and not as a penalty."
15. "The Quote is subject to the terms and conditions of any previously existing written agreement between the parties."

### 2.5 Signature Page

> **Condition:** *"This text will display unless 'Show/Hide Signature Lines?' field on the quote is set to Hide."* (default = show; suppressed only when the field = Hide.)
>
> **Text (verbatim):**
> "By signing below, I confirm acceptance of the attached quote from Fortra. This authorizes Fortra to send an invoice for the software and services listed on the attached quote, as well as provide temporary license keys for the quoted software.
>
> For perpetual licenses I understand that permanent keys will be provided upon receipt of payment for the invoice and delivery to Fortra of any hardware information necessary to create permanent keys. For subscriptions I understand that keys for the term of the subscription will be provided upon receipt of payment for the invoice and delivery to Fortra of any hardware information necessary to create those keys."

RCA gate: `Quote.Show_Hide_Signature_Lines__c != 'Hide'` (a per-quote field).

---

## 3. INVOICE document rules

Source: [INVOICE Terms and Condition Rules.docx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/D365%20TandC%20Rules/INVOICE%20Terms%20and%20Condition%20Rules.docx).

The Invoice is a **subset** of the Quote document. Differences are explicit and small.

| Section | Invoice rule |
|---|---|
| **T&C clause** | **None.** The Invoice carries **no** top-level EULA / Master-Solutions clause. (The brand-driven block from §2.1 is Quote-only.) |
| **License Key** | **Same as Quote** (§2.2). Condition: quote has new maintenance; not displayed for Subscriptions. Text: "Temporary license keys are issued upon receipt of order. Permanent license keys are issued upon receipt of payment in full." |
| **Tax Text** | **Tighter trigger than Quote.** Condition: quote has **new maintenance** AND legal entity is Fortra Argentina S.R.L. **or** Fortra Computing Group, S.L.U. (Quote only requires the legal entity; Invoice **also** requires new maintenance.) Same per-entity text as §2.3. |
| **Service Terms** | **Same trigger** as Quote (services product present AND no line has `Hide Fortra Professional Services Terms = Yes`), but **collapsed to one sentence** instead of the 15-clause block: "This Invoice is subject to the terms and conditions set forth in the Fortra Master Solutions Agreement and applicable Solution Specific Schedule(s) located at www.fortra.com/legal" |
| **Signature Page** | **Not present** on the Invoice. |

### 3.1 Quote vs Invoice trigger deltas (precise)

- **Tax Text:** Quote = `legal entity ∈ {AR, ES}`. Invoice = `has new maintenance AND legal entity ∈ {AR, ES}`. The Invoice adds the maintenance predicate.
- **Service Terms:** same boolean trigger on both, but the **rendered text differs** (full block on Quote, single MSA pointer sentence on Invoice).
- **T&C / Signature:** Quote-only; Invoice omits both.

---

## 4. Consolidated trigger → condition reference

All conditions in one table for the rebuild. "Field" names below are **inferred Salesforce names** for the discovery fields — verify against the actual Quote object before wiring.

| Doc | Section | Condition (verbatim intent) | Inferred SF predicate |
|---|---|---|---|
| Quote | EULA suppression | Legal entity is AR S.R.L. or ES S.L.U. → hide EULA | `Legal_Entity__c IN {AR, ES}` |
| Quote | EULA multi-brand | >1 brand with differing text → show all distinct clauses | iterate distinct `Product.Brand__c` on lines, union text |
| Quote | EULA group A | Brand ∈ {Cobalt Strike, Outflank, Core CTS} | brand membership |
| Quote | EULA group B | Brand ∈ 24-brand MSA list (§2.1.4) | brand membership |
| Quote | Custom T&C — PhishLabs/Agari | brand ∈ {PhishLabs, Agari} AND New-Sale vs Renewal/Add-on | brand + `Type` (New/Renewal/Add-on) |
| Quote | Custom T&C — BJ/Titus/Vera/DG | brand ∈ {Boldon James, Titus, Vera, Digital Guardian} (any type) | brand membership (→ MSA text) |
| Both | License Key | has **new maintenance** line AND not a subscription | new-maintenance line exists AND not subscription quote |
| Quote | Tax Text | legal entity ∈ {AR, ES} | `Legal_Entity__c IN {AR, ES}` |
| Invoice | Tax Text | **new maintenance** AND legal entity ∈ {AR, ES} | maintenance line AND `Legal_Entity__c IN {AR, ES}` |
| Both | Service Terms | ≥1 services product AND no services line has Hide-PS-Terms = Yes | `ANY(Line.IsService)` AND `NONE(Line.Hide_Fortra_Professional_Services_Terms__c = true)` |
| Quote | Signature Page | `Show/Hide Signature Lines? != Hide` | `Show_Hide_Signature_Lines__c != 'Hide'` |

---

## 5. Salesforce RCA re-implementation guidance

**Where this lands.** These are **document-presentation** rules, not pricing or configuration rules. The natural home is the **DocGen / OmniStudio document template** that renders the Quote PDF (and the Invoice) — see the auto-memory "DocGen Quote PDF pipeline" note: the Quote PDF body is assembled by **template-bound DataRaptors** (`useTemplateDRExtract=Yes`), so each T&C fragment becomes a **conditional template block** driven by an extract field.

Recommended build pattern:

1. **Fragment library.** Author each clause (EULA group A, EULA group B, PhishLabs/Agari New-Sale, PhishLabs/Agari Renewal, MSA-default, License Key, Tax-AR, Tax-ES, Service Terms full, Service Terms short, Signature) as a **reusable conditional section** in the template (or as `Conditional Terms` / clause records if using a clause-library product). **Store the verbatim text once**; the contract language must be byte-exact.
2. **Driver fields on the Quote.** Surface or compute: distinct **brands** on the lines, **legal entity**, **transaction type** (New / Renewal / Add-on), **has-new-maintenance**, **is-subscription**, **has-services** + **all-services-hide-PS-terms flag**, **Show/Hide Signature Lines**. Several of these are line-aggregations and should be computed in the **template-bound DataRaptor extract** (or a rollup), not hand-set.
3. **Brand→clause data table.** Encode the brand membership (§2.1.3–2.1.7) as a **mapping table / Custom Metadata** (`Brand → T&C clause key`), not as hard-coded template `if` chains — the 24-brand MSA list and the 6 custom-T&C brands change over time, and a data table keeps the template stable. This mirrors how the rest of the RCA migration prefers Custom Metadata over Apex/flow hard-coding.
4. **Multi-brand union.** The template must loop distinct brands and **dedupe identical clauses** (since group B and the four "custom" fallbacks all emit the same MSA string — they should collapse to one).
5. **Legal-entity swap.** For AR/ES entities, **suppress EULA, emit Tax Text instead** — these are linked behaviors on the same two entities.
6. **New vs Renewal text variant** is the only transaction-type-driven clause (PhishLabs/Agari): gate on the Quote `Type`.
7. **Invoice = same fragment library, three fragments only** (License Key, Tax Text with the extra maintenance predicate, Service Terms short variant), no EULA, no Signature.

**Cross-references in this KB:**
- Doc **11** (`11_quoting-rules-d365-experlogix.md`) — the *other* legacy D365 rule export (Experlogix configuration/bundle rules); that one is pricing/config, this one is document text. Both are "rebuild in RCA" discovery inputs from the same source CRM.
- Doc **10** (`10_pricing-strategy-and-approval-matrix.md`) — pricing/approval context for quotes.
- `FORTRA_KNOWLEDGE_BASE.md` (design KB) — target RCA Quote/Order/DocGen model.

---

## 6. Open questions & ambiguities

- **`Hide Fortra Professional Services Terms` aggregation semantics.** The wording is "**none** of those products have it set to Yes." Read literally, a single services line flagged Yes suppresses the **entire** Service Terms block (all-or-nothing), not just that line. Confirm this is intended (vs. per-line suppression) before building the rollup.
- **`Legal_Entity__c` field & picklist.** The docs name two legal entities by their legal-entity strings ("Fortra Argentina S.R.L.", "Fortra Computing Group, S.L.U."). Confirm the actual Quote field name and that the picklist values match exactly, and whether other Fortra legal entities exist with no special text.
- **Brand field source.** Brand is described as "based on products." Confirm where brand lives on the SF product/line model (`Product2.Brand__c`? a product family? a custom field) so the per-brand iteration can be built.
- **PhishLabs "Starting Text" vs "Custom T&C" overlap.** PhishLabs appears both in the "allow custom T&C" list and with the full Service-Order text. Confirm whether the Service-Order text is the *default* custom text or whether reps can override per quote.
- **Transaction-type detection for PhishLabs/Agari.** "New Sale" vs "Renewal and Add-on Sale" must map to a specific Quote/Order `Type` value set; confirm the RCA picklist (and how Add-on is distinguished from New).
- **"New maintenance" definition.** Both License Key and the Invoice Tax Text gate on "new maintenance on it … not for Subscriptions." Confirm how a new-maintenance (perpetual maintenance) line is identified in RCA (selling model? product type? line type) vs a subscription.
- **EULA PDF link currency.** The Offensive Security EULA points at a static `static.fortra.com` PDF; confirm the URL is still live and whether the rebuild should hard-code the link or pull it from a clause/config record.
- **Currency/locale of contract text.** The AR/ES entities reference IVA but the clauses are in English; SC-3384 (multi-currency) work shows non-USD/locale handling is fragile. Confirm whether localized (Spanish) T&C variants are needed for AR/ES quotes, since the discovery docs only provide English.
- **Invoice generation owner.** It is unclear whether the SF Invoice document is produced by DocGen or by Workday (the financial back end). If invoices are rendered downstream of Workday, these Invoice rules may need to live in the integration/Workday template rather than SF DocGen — confirm the invoice-rendering system.

---

## Sources

- [QUOTE Terms and Condition Rules.docx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/D365%20TandC%20Rules/QUOTE%20Terms%20and%20Condition%20Rules.docx) — via extracted text `Data/discovery-extract/text/Quotes and Billing/D365 TandC Rules/QUOTE Terms and Condition Rules.docx.txt`. Read in full. The complete Quote document rule set (EULA/brand, License Key, Tax, Service Terms, Signature).
- [INVOICE Terms and Condition Rules.docx](Fortra%20Discovery%20Documentation/Quotes%20and%20Billing/D365%20TandC%20Rules/INVOICE%20Terms%20and%20Condition%20Rules.docx) — via extracted text `Data/discovery-extract/text/Quotes and Billing/D365 TandC Rules/INVOICE Terms and Condition Rules.docx.txt`. Read in full. The Invoice document rule subset (no T&C clause; License Key, tightened Tax, short Service Terms).

No files in scope were encrypted, binary, or empty. Both source files are plaintext-clean (no diagrams or images requiring vision read).
