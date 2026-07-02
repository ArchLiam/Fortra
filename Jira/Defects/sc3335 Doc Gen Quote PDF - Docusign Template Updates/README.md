# SC-3335 — Doc Gen Quote PDF / DocuSign Template Updates

## Details
- **Type:** Task
- **Status:** ✅ **Resolved 2026-06-04** — all 5 defects fixed & verified in UAT (see Resolution below)
- **Assignee:** Liam Jeong · **Reporter:** Jomil Bell
- **Parent:** None
- **Due date:** 2026-06-05
- **Priority:** 🔴 **Blocker**
- **Sprint:** CRM Sprint 14 · **Component:** SF RCA
- **Labels:** CRM-Revenue-Cloud, LOB-Salesforce-1-UAT
- **Source ticket:** [SC-3335](https://helpsystems.atlassian.net/browse/SC-3335)
- **Related impl:** [SC-845 / SC-3298 — Quote Document Generation + DocuSign](../../sc3143%28epic%20%7C%20integration%29/sc3298/README.md)

## ✅ Resolution (2026-06-04) — verified in FortraUAT
All five reported defects are resolved and **confirmed by regenerating the PDF** on two A/B test quotes:
**00780817** (`Show_Hide_Discounts=Hide`, `Net_Terms=Net_15`) and **00780823** (`Show`, blank Net Terms).

| # | Defect | Resolution | Where |
|---|--------|------------|-------|
| **1** | Net Terms showed raw value | Picklist **API→label map** (`Net_15`→"Net 15", `Net_0`→"Immediate", …; blank→"Due Upon Receipt") | `DMTransformFortraQuote` netTerms formula — **deployed** |
| **2** | "Signature line / how captured?" | **Works as designed** — signing happens via DocuSign at the *Send for Signature* step; this was a how-to gap, not a defect. | [`HOWTO_send_for_signature.md`](./HOWTO_send_for_signature.md) — no code change |
| **3** | Discount shown when set to Hide | Discount header + value cells gated with `{{#IF_showDiscounts}}` | template **v3** (`.docx`) — **uploaded/Active** |
| **4** | Product Start/End dates missing | Added `lineItems:startDate` formula + a gated `Term: {{startDate}} - {{endDate}}` line | `DMTransformFortraQuote` + template **v3** — **deployed** |
| **5** | Product name / blank Description | `description → productName` fallback (`Product2.Name`) | `DMTransformFortraQuote` — **deployed** |

**Key corrections to the initial analysis** (found during live verification — kept for honesty):
- **#1 was *not* a template bug** — the header already binds `{{netTerms}}`; the raw `Net_15` was the *payload* emitting the picklist API value. Fix moved to the DataRaptor.
- **#5 prehook was *not* deleted** — `QLDescriptionGeneratorPrehook` **exists and is Active** in UAT (created 2026-04-27, untouched). The blank Description is because that prehook only writes for lines *with configured attributes*; the `productName` fallback fixes the PDF regardless. (If full attribute-rich descriptions are wanted back for configured products, that's a separate prehook-registration check — see `RESOLUTION_GUIDE.md` Step 4.)
- **Source drift** confirmed: the `force-app` DataRaptor was stale vs. live (missing an existing `hwLineItems:description` mapping). `force-app/.../DMTransformFortraQuote_1.rpt-meta.xml` has now been **synced to the deployed version** so future deploys won't regress the org.

**Out of scope (left as-is per decision):** the per-line **Discount _amount_** prints the quote-wide total (`1240.00`) instead of each line's own (240 / 1000) — `lineItems:discountAmt` sourcing issue. Real bug, **not one of the 5 reported**; not logged as a separate ticket per request.

**Deployed artifacts:** `DMTransformFortraQuote` (live, synced to `force-app`) · DocumentTemplate "Fortra Quote Consolidated EN" **v3 Active** · template source archived at `Data/sc3335/template/Fortra_Quote_Consolidated_EN_v5.docx`. Step-by-step record in [`Data/sc3335/RESOLUTION_GUIDE.md`](../../../Data/sc3335/RESOLUTION_GUIDE.md).

---

## TL;DR _(initial hypothesis — superseded by the Resolution above; kept for investigation history)_
The **Generate Document → Quote PDF** (the DocGen/OmniScript flow built in SC-845) renders an
incorrect quote document. Reporter (Jomil Bell, via Marc's demo + German Wren) flagged **5 defects**
on the generated "**-DO NOT PAY- QUOTE**" PDF, plus a likely shared root cause: the **Quote Line
`Line Item Description` field is now blank** ("description on quote lines is not being created
anymore… was working, stopped in the last week or so").

**Deep research is complete and source-verified** (see [`Data/sc3335/DocGen_Pipeline_Analysis.md`](../../../Data/sc3335/DocGen_Pipeline_Analysis.md)). The defects split cleanly across three layers:
- **3 are in the binary `.docx` template** (not in repo — must be downloaded): Net Terms label (#1), Discount column visibility (#3), and the DocuSign signature region (#2). The merge **payload is already correct** for Net Terms and the discount gate; the template just doesn't bind/honor them.
- **1 is an in-repo DataRaptor bug** (#4): `DMTransformFortraQuote_1` never builds `lineItems:startDate` — line-item end date has a formula, **start date is a dead self-passthrough**.
- **1 is an upstream automation regression** (#5 + the comment): the RLM pricing prehook **`QLDescriptionGeneratorPrehook`** — which writes `QuoteLineItem.Description` *led by the Product Name* — is **absent from deployed classes** (present only in `Data/apexguru-review/corpus/`). Its removal blanks both the Description column and the "product name."

---

## The 5 flagged defects (from the annotated PDF)

On the sample PDF (Quote **#00780817**, Account "AB Test Account", dated 3-Jun-26), the reporter
marked these in red:

| # | Defect | Where it should come from |
|---|--------|---------------------------|
| 1 | **Net Terms should pull in from the record** — currently shows a static "Due Upon Receipt" | Quote / Account net-terms field, not hardcoded in the template |
| 2 | **Signature line missing** — "How will the signature be captured?" | DocuSign signature anchor / recipient tab in the template + envelope |
| 3 | **Discount shows when it was set to be hidden** — the `(1240.00)` Discount column renders even though "hide discount" was selected | a hide-discount toggle (Quote/Group field) the template/payload ignores |
| 4 | **Start / End date of product not showing** | OrderItem/QuoteLine Start & End (term) dates into the line-item payload |
| 5 | **Product name not displaying** — the Description column is blank | product name / line description into the table rows |

### The rendered PDF (transcribed)
```
FORTRA                         -DO NOT PAY-                    Fortra, LLC.
                                  QUOTE                        11095 Viking Drive, Suite 100
                                                               Eden Prairie, MN 55344, United States
                                                               Tax ID: 30-0290533
                                                               Phone: +1 952-933-0609 · www.fortra.com

Date: 3-Jun-26 | Account: AB Test Account | Quote #: 00780817 | [Net Terms: Due Upon Receipt]  ← #1

Shipping Info                              Billing Info
  Name:    Billing Test Place               Name:    AB Test Place
  Company: AB Test Account                   Company: AB Test Account
  Address: 123456 Main street,               Address: 57 Henry Street,
           chicago, IL 55555                          Lindenow, 3865
  Phone:                                     Phone:
  Email:                                     Email:   abc@xyz.com

  Description          Qty    Price     Discount      Amount
  [blank] ← #5,#4       1    2400.00   (1240.00) ← #3  2160.00
  [blank] ← #5,#4       1   10000.00   (1240.00) ← #3  9000.00
  Subtotal                              (1240.00)     12400.00
  Tax                                              Calculation Pending
  Total                                               11160.00
                                                  Currency: USD

  ← #2  (no signature line)

Subscription terms below include:
  Subscription licenses are provided on an annual basis. Subscription fees are invoiced upon
  order execution and are non-refundable. Access to subscription products is contingent on
  timely payment of renewal invoices. Subscription terms and pricing are subject to change
  upon renewal with advance written notice.

  This Quote is subject to the terms and conditions set forth in the Fortra Master Solutions
  Agreement and applicable Solution Specific Schedule(s) located at www.fortra.com/legal
```
> Source images: `image-202606…334.png` (PDF, 01:44 PM) and `image-202606…212.png` (Slack thread, 01:52 PM) — attached to the ticket.

---

## Related root cause — blank `Line Item Description` (German Wren, 2026-06-03 2:47 PM)
> *"Jomil this could be related to the description being blank. Yesterday we discussed how the
> description on quote lines is not being created anymore. This was working, but stopped sometime
> in the last week or so, not exactly sure when. I brought it up yesterday but it may be related to
> the quote pdf issue from Marc's demo."*

On Quote **Q-Coastal Demo - New Business-2026-06-03**, Quote Line **04265865**
(Product = *Automate Professional*, Custom Product Name = *Automate Professional*), the
**`Line Item Description`** field is **blank**. Defects **#4** (dates) and **#5** (product name /
blank Description column) on the PDF are almost certainly downstream of this: the template's
**Description** column merges from the quote line's description, which **was being auto-populated by
an automation that recently stopped firing.** So the fix has two fronts:
1. **Template/payload** — render product name + term dates + respect the hide-discount flag + pull Net Terms from the record + add a DocuSign signature anchor.
2. **Upstream automation** — find why `Line Item Description` stopped being written on quote lines (flow/Apex regression "in the last week or so") and restore it.

---

## DocGen implementation in this org (component map)
This Quote PDF is produced by the OmniStudio/DocGen stack built in **SC-845 / SC-3298**. Full
post-deploy + access details: [sc3298 README](../../sc3143%28epic%20%7C%20integration%29/sc3298/README.md).
Components present in this repo:

| Layer | Component | Path |
|---|---|---|
| OmniScript (UI modal) | `DocumentGeneration_Quote_English_3` | `force-app/main/default/omniScripts/` |
| Integration Procedure (build doc) | `Quote_GenerateDoc_English_4` | `force-app/main/default/omniIntegrationProcedures/` |
| Integration Procedure (send) | `Quote_SendDocuSignEnvelope_Procedure_1` | `force-app/main/default/omniIntegrationProcedures/` |
| DataRaptor Extract | `DMExtractFortraQuote_1` (1430 ln) | `force-app/main/default/omniDataTransforms/` |
| DataRaptor Transform (payload) | `DMTransformFortraQuote_1` (1952 ln) | `force-app/main/default/omniDataTransforms/` |
| DataRaptor Transform (template) | `DMTransformFortraDocTemplate_1` | `force-app/main/default/omniDataTransforms/` |
| DataRaptor Turbo Extract (template lookup) | `DMTurboExtractQuoteDocGenTemplate_1` | `force-app/main/default/omniDataTransforms/` |
| DataRaptor Turbo Extract (line type) | `DMTurboExtractQuoteLineItem_1` | `force-app/main/default/omniDataTransforms/` |
| Apex (DocuSign envelope) | `DocuSignEnvelopeService` (+ Test) | `force-app/main/default/classes/` |
| LWC (wrapper) | `docGenOmniScriotWrapperLWC` | `force-app/main/default/lwc/` |
| LWC (quote summary card) | `fortraQuoteOsCard` | `force-app/main/default/lwc/` |
| `.docx` template | **Fortra Quote Consolidated EN** (uploaded to `DocumentTemplate`, **not in source**) | Setup → Document Generation |
| Access | group `DocGen_Template_Users`, PSL `DocuSign_API_Access` | groups / permissionsets |

> ⚠️ The actual merge-field rendering (Net Terms label, Discount column, Description column,
> dates, signature block) lives in the **binary `.docx`** template, which is **not in the repo** —
> it must be downloaded from the org's Document Templates. The DataRaptors decide **what data is
> available** to merge; the `.docx` decides **what is shown**.

---

## Verified root cause per defect
Full evidence (file:line) and the end-to-end pipeline data-flow are in
[`Data/sc3335/DocGen_Pipeline_Analysis.md`](../../../Data/sc3335/DocGen_Pipeline_Analysis.md). Summary:

| # | Defect | Owning layer | Verified finding | Fix |
|---|--------|-------------|------------------|-----|
| 1 | Net Terms static | **`.docx` template** | Payload is correct & dynamic — `Net_Terms__c → netTermsRaw → netTerms` (formula at `DMTransformFortraQuote_1:1693`). The cell renders a typed literal, not the `{{netTerms}}` token. | Rebind the Net Terms cell to `{{netTerms}}`; re-version the template. |
| 2 | No signature line | **Apex + `.docx` + wiring** | `DocuSignEnvelopeService` places tabs at **absolute x/y** (`360,680` — `cls:293-313`), no anchor strings; `pageCount` never reaches Apex (falls back to `MIN_FORTRA_PAGES=2`). `Quote.Show_Hide_Signature_Block__c` **exists but is never extracted.** | Switch to `anchorString` tabs + reserve a signature block w/ anchor tokens in the `.docx`. Interim: wire `pageCount` from the merge LWC into the send payload. |
| 3 | Discount shows when hidden | **`.docx` template** | Gate exists & works in payload — `Show_Hide_Discounts__c → IF_showDiscounts` (`:1191`); per-row `discountDisplay` honors Hide. But the **column header + cells aren't wrapped** in the conditional, and raw `discountAmt`/`discountPct` are emitted unconditionally. | Wrap the Discount column in an `IF_showDiscounts` region; harden the doc-level/raw discount fields in `DMTransformFortraQuote_1` as defense-in-depth. |
| 4 | Product Start/End dates missing | **In-repo DataRaptor bug** | `lineItems:endDate` has a full reformat formula (`:299-301`); both hw dates too. **`lineItems:startDate` is only a self-referential passthrough (`:1335`)** — `startDateRaw` is never consumed → start date always blank. | Add a formula cloning endDate's (input `lineItems:startDateRaw` → `lineItems:startDate`); drop the dead passthrough. Highest-certainty code fix. |
| 5 | Product name not displaying / Description blank | **Upstream automation** (+ template) | Plumbing is correct (`QLI.Description → lineItems:description`, `:518-532`); the **source field is blank.** `QLDescriptionGeneratorPrehook` (writes `QuoteLineItem.Description` led by Product Name) is in `Data/apexguru-review/corpus/` but **absent from deployed classes & the 2026-06-02 UAT retrieve.** | Restore/re-register the prehook **last** in the RLM Quote pricing chain + reprice; add a `description ?? productName` fallback in `DMTransformFortraQuote_1:1589` as a safety net. |

> **Why #5 ≡ the regression:** German Wren's "description stopped being created" and the PDF's "product name not displaying" are the **same** root cause — the prehook prepends Product Name as segment 0 of `QuoteLineItem.Description`, and the Description column merges that field. No removal = blank field = blank column.

## Fix plan (ordered for the Jun-5 blocker)
**P0 (today, read-only — no deploy ack needed):**
1. Retrieve the live `DocumentTemplate` **Fortra Quote Consolidated EN** from FortraUAT and unzip the `.docx` — unblocks #1, #3, #2's anchor path, and the residual of #4/#5. Also confirms which DataRaptor versions are actually active (all are `active=false` in source).
2. Retrieve the live **RLM Quote pricing-prehook chain registration** + confirm whether `QLDescriptionGeneratorPrehook` was deregistered vs. deleted vs. failing silently (root of #5/regression — *not* captured in `force-app`).

**P1 (self-contained code fixes, queue deploy pending ack per [UAT-deploy policy](../../../)):**
3. #4 — add the `lineItems:startDate` formula in `DMTransformFortraQuote_1`.
4. #5/regression — redeploy + re-register `QLDescriptionGeneratorPrehook` (recoverable from `corpus/`), reprice; add the `description` fallback as belt-and-suspenders.

**P2 — `.docx` edits (batch once template is retrieved):** #1 Net Terms rebind, #3 Discount column conditional.
**P3 — DocuSign signature (#2):** anchor-string tabs + reserved signature block (most involved; ship the interim `pageCount` wiring fix first if Jun-5 is tight).

> ⚠️ **Do not deploy without re-confirming live active versions** of `DMExtractFortraQuote` / `DMTransformFortraQuote` and the deployed `DocuSignEnvelopeService` against a fresh UAT retrieve — source may be stale ([Fortra source drift](../../../)).

## Artifacts (`Data/sc3335/`)
| File | What it is |
|---|---|
| `DocGen_Pipeline_Analysis.md` | **Main deliverable** — end-to-end pipeline data-flow, component reference, per-defect root-cause table, "needs live verification" list, prioritized fix plan. Source-verified. |
| `research_component_map.json` | Raw structured map of each DocGen component (8 agents) |
| `research_defect_traces.json` | Raw per-defect traces (6 agents) |
| `research_ip_generate_map.json` | Map of the `Quote_GenerateDoc` IP |

---
_Written 2026-06-03 from the SC-3335 ticket (description PDF + comments); root-cause analysis from
the `sc3335-docgen-research` multi-agent workflow, **independently source-verified** the same day.
Component/field/version names are point-in-time — verify against a fresh FortraUAT retrieve before
changing anything._
