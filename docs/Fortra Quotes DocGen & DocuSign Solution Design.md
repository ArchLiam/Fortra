# Quote Document Generation & DocuSign Signature
## Solution Design Document
**Prepared for Fortra**

---

> **Document status:** 🟡 DRAFT - for review
> **Solution area:** Quote-to-Cash · Quoting · Document Generation & e-Signature
> **Platform:** Salesforce Revenue Cloud Advanced (RCA) + OmniStudio (Document Generation) + DocuSign
> **Environments:** fortradp2 (dev/sandbox), fortrauat (UAT)
>
> *This is a Markdown working draft for review. On approval it will be converted to a Word document following the Coastal SDD template (`Fortra Quotes DocGen & DocuSign Solution Design Doc.docx`).*

---

## Document Version History

| Version | Date | Updated By | Comments |
|---|---|---|---|
| 1.0 | Jul 24, 2026 | Liam Jeong (Coastal) | Initial draft - for review. |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Solution Overview](#2-solution-overview)
3. [Requirements](#3-requirements)
4. [Assumptions](#4-assumptions)
5. [Dependencies](#5-dependencies)
6. [Technical Design](#6-technical-design)

---

## 1. Executive Summary

The Quote Document Generation & DocuSign Signature solution lets a Fortra sales user generate a
branded, print-ready PDF quote directly from a Salesforce Quote record and route it to the customer
for electronic signature - without leaving the Quote page. It is built on Salesforce **OmniStudio
Document Generation (DocGen)** for the client-side Word-to-PDF merge and a custom **DocuSign** REST
integration for envelope creation and signature-tab placement.

A single guided OmniScript wizard (**"Fortra Quote Generate Document"**) drives the whole flow:
it assembles the quote dataset, resolves the correct Word template, renders the PDF in the browser,
lets the rep confirm the recipient and preview the document, and then fires a DocuSign envelope with
sign-here / date / name tabs on the last page. All quote content (header, addresses, sales rep,
software/services line items, hardware groups, totals, net terms, and conditional discount columns)
is produced by a pair of template-bound OmniStudio DataRaptors, so the rendered layout is fully
data-driven and controlled by document display toggles on the Quote.

The solution closes the "quote paper" gap in Fortra's Revenue Cloud quoting process: prior to it,
there was no standardized, branded, single-click quote document or an integrated signature path.
It was deployed to both **fortradp2** and **fortrauat**, with the DocuSign callout secured through a
Salesforce External Credential and the merge template shared to authorized users through a dedicated
public group.

### 1.1 Key Features

- **One-click quote PDF generation** from the Quote record via a launcher LWC and an
  OmniStudio Document Generation OmniScript (`DocumentGeneration_Quote_English_3`).
- **Client-side Word-to-PDF merge** using the managed `omnistudio__clmOsDocxGenerateDocument`
  component against the binary `.docx` template **"Fortra Quote Consolidated EN"**.
- **Data-driven layout** built entirely by template-bound DataRaptors
  (`DMExtractFortraQuote` → `DMTransformFortraQuote`), invoked because the OmniScript pins
  `useTemplateDRExtract = Yes`.
- **Consolidated content model** covering quote header, bill-to / ship-to address blocks, sales rep
  block, software & services line items, hardware line items grouped by hardware, formatted dates,
  currency, net-terms labels, and totals.
- **Document display controls on the Quote** - Show/Hide Discounts, Show/Hide Signature Block,
  Show/Hide Free Products, Show/Hide Product Number, and Net Terms - that govern what prints.
- **Guided recipient / review / confirm experience** using a branded custom step card
  (`fortraQuoteOsCard`), including an inline same-origin **PDF preview** before sending.
- **Integrated DocuSign e-signature** via a custom Apex service (`DocuSignEnvelopeService`) that
  POSTs a signature envelope through a Salesforce External Credential and places signature, date,
  and name tabs on the last page.
- **Resilient page-count handling** - explicit page count → PDF auto-detection → 2-page minimum
  fallback - so signature tabs never land on page 1.
- **Never-throw telemetry** - DocuSign failures are logged to `Exception_Log__c` (via a
  `Fortra_Exception__e` platform event) without blocking the user.
- **Secured integration** - DocuSign API access is granted through an External Credential principal
  in a dedicated permission set; the merge template file is shared to the `DocGen Template Users`
  public group.

---

## 2. Solution Overview

### 2.1 Process Flow Summary

The solution follows this end-to-end sequence:

1. **Launch.** From a Quote record page or a screen quick action, the launcher LWC
   `docGenOmniScriotWrapperLWC` boots the managed OmniStudio runtime for the
   `DocumentGeneration / Quote / English` OmniScript, passing the Quote Id as prefill
   (`ContextId`, `ObjectId`, and `QuoteId` are all set to the record Id).

2. **Retrieve quote information.** The OmniScript calls Integration Procedure **`Quote_GenerateDoc`**,
   passing `contextId = <Quote Id>`. This IP resolves the document title, the signer defaults, and
   **which** Word template to merge - it does **not** build the document body. It returns
   `documentTitle`, `selectedTemplate`, `signerName`, `signerEmail`, and `emailSubject` under the
   `IPResult` node.

3. **Prepare generation options.** Set-Values steps stage the document title and template Id and set
   the DocGen generation options: `docGenerationMechanism = ClientSide`, `pdfGenerationSource =
   ClientSide`, output format `pdf`, and - critically - **`useTemplateDRExtract = Yes`**.

4. **Generate the document.** The managed merge component `omnistudio__clmOsDocxGenerateDocument`
   merges the binary `.docx` template client-side. Because `useTemplateDRExtract = Yes`, the merge
   JSON is built at merge time by the DataRaptors **bound inside the `DocumentTemplate` record** -
   `DMExtractFortraQuote` (Extract) → `DMTransformFortraQuote` (Transform) - not by the OmniScript or
   the IP. The step outputs the PDF's ContentVersion Id as `pdfGenContentVersionId`.

5. **Confirm recipient.** The rep reviews the pre-populated signer name, signer email, and email
   subject (defaulted from the quote's bill-to details) on a branded card.

6. **Review & preview.** The rep previews the generated PDF inline (same-origin rendition iframe) and
   confirms send.

7. **Send for signature.** The OmniScript calls Integration Procedure **`Quote_SendDocuSignEnvelope`**
   with only the send payload (`contentVersionId`, `signerEmail`, `signerName`, `emailSubject`). That
   IP invokes Apex **`DocuSignEnvelopeService.sendEnvelope`**, which reads the PDF, resolves the last
   page, builds the envelope JSON with signature/date/name tabs, and POSTs it to DocuSign through the
   `DocuSignAPI` callout.

8. **Confirm sent.** The DocuSign response (`envelopeId`, `status`, `statusDateTime`, `pageCount`) is
   surfaced on a confirmation card. Any failure is logged to `Exception_Log__c` and returned as a
   graceful error result.

```
 Quote record  (Record page / Screen Quick Action)
   | recordId
   v
 docGenOmniScriotWrapperLWC  -->  OmniStudio managed runtime (DocumentGeneration/Quote)
   | prefill { ContextId, ObjectId, QuoteId } = recordId
   v
 OmniScript "Fortra Quote Generate Document"  (DocumentGeneration_Quote_English_3)
   0  Configuration            isDebug = false
   1  Retrieve Quote Info -->  IP Quote_GenerateDoc   [Stage A: template + signer/title]
   2  PrepareDocPayload          |- DMExtractFortraQuote        (signer / title fields)
   3  BuildTemplatePayload       |- DMTurboExtractQuoteLineItem (dominant type - unused)
   4  GenerationOptions          |- template = 'Fortra Quote Consolidated EN' (static)
        useTemplateDRExtract=Yes |- DMTurboExtractQuoteDocGenTemplate (template lookup)
        docGenMech=ClientSide     |- DMTransformFortraDocTemplate -> selectedTemplate
                                  \- Return: title, selectedTemplate, signer*, subject
   v
   5  GenerateDocument  --  managed LWC omnistudio__clmOsDocxGenerateDocument
        merges .docx "Fortra Quote Consolidated EN"   [Stage B: built at merge time]
          |                                       |- DMExtractFortraQuote  -> raw JSON
          |                                       \- DMTransformFortraQuote -> tokens
          |  <-- PDF rendered -> pdfGenContentVersionId
   v
   6  RecipientDetails  signer name / email / subject   (fortraQuoteOsCard step1)
   7  ReviewAndSend     PDF preview + confirm            (fortraQuoteOsCard step2)
   8  SendDocuSign  -->  IP Quote_SendDocuSignEnvelope  -->  DocuSignEnvelopeService (Apex)
        payload { contentVersionId, signerEmail, signerName, emailSubject }
        sendOnlyExtraPayload=true  -->  POST callout:DocuSignAPI (signHere/date/name tabs)
   v
   9  ConfirmSent       envelopeId / status / pageCount   (fortraQuoteOsCard confirm)
```

> **Key architectural point:** the PDF **body content does not come from the IP or the OmniScript**.
> It is produced by the template-bound `DMExtractFortraQuote → DMTransformFortraQuote` DataRaptor
> pair, which run only because the OmniScript sets `useTemplateDRExtract = Yes`. The `.docx` template
> itself owns the visual layout and token bindings and is stored as a binary `DocumentTemplate`
> record (not in source control).

### 2.2 Solution Components

| Component | Type | Description |
|---|---|---|
| **docGenOmniScriotWrapperLWC** | Lightning Web Component (host) | Thin launcher that boots the managed OmniStudio runtime for the DocumentGeneration/Quote OmniScript. Exposed as a Record Action (screen quick action) and on the Record Page; passes the Quote Id as prefill under three keys. |
| **Fortra Quote Generate Document** (`DocumentGeneration_Quote_English_3`) | OmniScript (DocumentGeneration / Quote / English, v3) | The guided wizard: retrieves data, resolves template, renders the PDF client-side, collects recipient details, previews, and sends for signature. 10 top-level steps. |
| **Quote_GenerateDoc** (`Quote_GenerateDoc_English_4`) | Integration Procedure (v4) | Stage A - resolves `documentTitle`, `selectedTemplate`, and signer defaults. Does **not** build the document body. |
| **Quote_SendDocuSignEnvelope** (`Quote_SendDocuSignEnvelope_Procedure_1`) | Integration Procedure (v1) | Invokes `DocuSignEnvelopeService.sendEnvelope` (Remote Action) and returns the envelope result. |
| **DMExtractFortraQuote** | DataRaptor Extract | Master data source. Queries Quote, line items (software/services), hardware line items, hardware groups, sales rep (User), Account, and bill-to / ship-to Places into raw JSON. Bound to the template as its Extract DataRaptor. |
| **DMTransformFortraQuote** | DataRaptor Transform | Builds the token-ready merge JSON for the `.docx` (dates, currency, net-terms labels, address blocks, discount display, line-item / hardware-group arrays, section gates). Bound to the template as its Mapper DataRaptor. |
| **DMTurboExtractQuoteDocGenTemplate** | DataRaptor Turbo Extract | Looks up the `DocumentTemplate` by name (`IsActive`, `Status = Active`) and returns its config, including the bound Mapper/Extract DataRaptor names. |
| **DMTransformFortraDocTemplate** | DataRaptor Transform | Reshapes the `DocumentTemplate` row into the `selectedTemplate{}` structure the OmniScript feeds to the merge component. |
| **DMTurboExtractQuoteLineItem** | DataRaptor Turbo Extract | Reads the first line item's product type for legacy "dominant type" logic. *(Currently vestigial - see §6.5.)* |
| **omnistudio__clmOsDocxGenerateDocument** | Managed LWC (OmniStudio) | Performs the client-side Word-to-PDF merge and outputs the PDF `ContentVersion` Id. |
| **fortraQuoteOsCard** | Lightning Web Component | Branded, multi-variant OmniScript step card (recipient / review / confirmation) with an inline same-origin PDF preview. Replaces managed Text Blocks to preserve styled HTML. |
| **DocuSignEnvelopeService** | Apex Class (`Callable` + `@InvocableMethod`) | Builds and POSTs the DocuSign envelope; resolves page count; places signature/date/name tabs; parses the response. |
| **DocuSignEnvelopeException** | Apex Class | Typed marker exception (extends `AppException`) so DocuSign failures are classified by type in `Exception_Log__c`. |
| **ExceptionLogger** | Apex Class | Never-throw telemetry publisher; emits a `Fortra_Exception__e` platform event persisted to `Exception_Log__c`. |
| **DocuSignEnvelopeServiceTest** | Apex Test Class | Mock-based coverage (>90%) of success, error, page-count, `Callable`, and invocable paths. |
| **DocuSign API Access** | Permission Set | Grants the DocuSign External Credential principal access required for the callout. |
| **DocGen Template Users** | Public Group | Share target for the merge template `.docx` file (via `ContentDocumentLink`). |
| **Quote document-control fields** | Custom Fields (Quote) | `Net_Terms__c`, `Show_Hide_Discounts__c`, `Show_Hide_Signature_Block__c`, `Show_Hide_Free_Products__c`, `Show_Hide_Product_Number__c`. Govern what prints on the document. |
| **Fortra Quote Consolidated EN** | DocumentTemplate (binary `.docx`) | The merge surface. Owns visual layout, token bindings, and column visibility. Stored as a `DocumentTemplate` record + `ContentDocument` (not in source control). |

---

## 3. Requirements

### 3.1 Business Requirements

| ID | Requirement | Priority |
|---|---|---|
| **BR-001** | Generate a branded, print-ready PDF quote document directly from a Salesforce Quote record in a single, guided action. | High |
| **BR-002** | Send the generated quote to the customer for electronic signature via DocuSign without leaving Salesforce. | High |
| **BR-003** | Present quote content in a consolidated layout: header, bill-to / ship-to, sales rep, software & services lines, hardware (grouped), net terms, and totals. | High |
| **BR-004** | Let the sales user control what appears on the document - discounts, signature block, free products, and product numbers - via Quote-level toggles. | Medium |
| **BR-005** | Default the signature recipient and email subject from quote data so the rep does not re-key them, while still allowing edits before sending. | Medium |
| **BR-006** | Let the rep preview the exact PDF before it is sent for signature. | Medium |
| **BR-007** | Place signature, date, and name tabs on the document so the customer can complete signing in DocuSign. | High |
| **BR-008** | Fail gracefully and record document/e-signature errors for support, without blocking or confusing the user. | Medium |

### 3.2 Technical Requirements

| ID | Requirement | Priority |
|---|---|---|
| **TR-001** | Implement the flow as an OmniStudio Document Generation OmniScript (`type = DocumentGeneration`, `subType = Quote`, `language = English`) launched from a Quote record via a wrapper LWC. | High |
| **TR-002** | Build the merge JSON via template-bound DataRaptors (Extract → Transform) invoked through `useTemplateDRExtract = Yes`, keeping document data assembly out of the OmniScript and IP. | High |
| **TR-003** | Render the PDF client-side (`docGenerationMechanism = ClientSide`) using the managed `omnistudio__clmOsDocxGenerateDocument` component against the `.docx` template. | High |
| **TR-004** | Resolve the target `DocumentTemplate` at run time by name and pass the selected template Id to the merge component. | Medium |
| **TR-005** | Build the DocuSign envelope in Apex and POST it through a Salesforce External Credential / Named Credential (`DocuSignAPI`) rather than storing secrets in code. | High |
| **TR-006** | Resolve the signature page as: explicit page count → PDF auto-detection → a 2-page minimum fallback, so tabs never land on page 1. | Medium |
| **TR-007** | Guard the synchronous DocuSign send against oversized documents (reject PDFs > 4 MB) to stay within Apex heap/callout limits. | Medium |
| **TR-008** | Expose the Apex send routine through the `Callable` interface (for the OmniStudio Remote Action) and `@InvocableMethod` (for Flow), sharing one core method. | Medium |
| **TR-009** | Log DocuSign failures to `Exception_Log__c` via a never-throw platform-event logger so instrumentation cannot turn a graceful degrade into a hard failure. | Medium |
| **TR-010** | Secure the merge template file by sharing it to the `DocGen Template Users` public group via `ContentDocumentLink`, and grant DocuSign API access via a dedicated permission set. | High |
| **TR-011** | Provide an inline, same-origin PDF preview in the review step using the Files rendition endpoint (`Content-Disposition: inline`). | Low |

---

## 4. Assumptions

| ID | Assumption |
|---|---|
| **A-001** | Salesforce **Revenue Cloud Advanced** and **OmniStudio Document Generation (DocGen)** are enabled and licensed in all target environments. |
| **A-002** | Users running DocGen hold the required permission set licenses - **OmniStudio** and **DocGen Designer** - plus read access to Quote, QuoteLineItem, QuoteLineGroup, `Places__c`, and `Hardware__c`. |
| **A-003** | The binary `.docx` template **"Fortra Quote Consolidated EN"** exists as an active `DocumentTemplate` record, with `DMExtractFortraQuote` bound as its Extract DataRaptor and `DMTransformFortraQuote` as its Mapper. |
| **A-004** | The merge template `ContentDocument` is shared to the **DocGen Template Users** public group, and each DocGen user is a member of that group (or covered by role-hierarchy bosses). A missing `ContentDocumentLink` is the first thing to check for a "List has no rows" DocGen error. |
| **A-005** | A DocuSign account is provisioned and the **`DocuSignAPI`** Named Credential / **DocuSign External Credential** (`DocuSign-DocuSignPrincipal`) are configured in the org with valid endpoint, account Id, integration key, and auth secrets. *(This is external configuration, not source-controlled.)* |
| **A-006** | The Quote has a populated **Bill-To Place** (`Bill_To_Place__c`) with a contact email and account/company name - these default the DocuSign signer email and signer name. |
| **A-007** | The active runtime versions of the OmniScript, both Integration Procedures, and all five DataRaptors match the deployed metadata. *(All five DataRaptors are `active = false` in source; the org must carry an active version.)* |
| **A-008** | Generated quote PDFs are within the **4 MB** synchronous DocuSign send limit. |
| **A-009** | The signer is the **billing company** for the quote. `signerName` defaults to the bill-to company name (not an individual contact name). See §6.5. |
| **A-010** | The `Exception_Log__c` object and a subscriber for the `Fortra_Exception__e` platform event (published *immediately*) are deployed, so failure telemetry is durably persisted. |

---

## 5. Dependencies

### 5.1 Internal Dependencies

| ID | Dependency | Status |
|---|---|---|
| **D-001** | OmniScript `DocumentGeneration_Quote_English_3` deployed and active. | Complete |
| **D-002** | Integration Procedure `Quote_GenerateDoc_English_4` deployed and active. | Complete |
| **D-003** | Integration Procedure `Quote_SendDocuSignEnvelope_Procedure_1` deployed and active. | Complete |
| **D-004** | DataRaptors `DMExtractFortraQuote`, `DMTransformFortraQuote`, `DMTurboExtractQuoteDocGenTemplate`, `DMTransformFortraDocTemplate`, `DMTurboExtractQuoteLineItem` deployed. | Complete |
| **D-005** | Apex `DocuSignEnvelopeService`, `DocuSignEnvelopeException`, `ExceptionLogger` (+ `DocuSignEnvelopeServiceTest`) deployed. | Complete |
| **D-006** | LWCs `docGenOmniScriotWrapperLWC` and `fortraQuoteOsCard` deployed and exposed. | Complete |
| **D-007** | Quote document-control fields (`Net_Terms__c`, `Show_Hide_Discounts__c`, `Show_Hide_Signature_Block__c`, `Show_Hide_Free_Products__c`, `Show_Hide_Product_Number__c`) deployed. | Complete |
| **D-008** | `DocumentTemplate` "Fortra Quote Consolidated EN" (binary `.docx`) uploaded, active, and bound to `DMExtractFortraQuote` / `DMTransformFortraQuote`. | Complete |
| **D-009** | `Places__c` (bill-to / ship-to), `Hardware__c`, and `QuoteLineGroup` data model present, supplying address and hardware detail to the extract. | Complete |
| **D-010** | `Exception_Log__c` object + `Fortra_Exception__e` platform event and its persistence subscriber deployed. | Complete |

### 5.2 External Dependencies

| ID | Dependency | Owner |
|---|---|---|
| **E-001** | Salesforce **OmniStudio Document Generation** platform capability (client-side `.docx` merge) and licensing. | Salesforce |
| **E-002** | **DocuSign** account, eSignature REST API (v2.1), integration key, and authentication. | Fortra / DocuSign Admin |
| **E-003** | `DocuSignAPI` **Named Credential** + **External Credential** (`DocuSign-DocuSignPrincipal`) with endpoint, account Id, and auth secrets. *(Org configuration - not in source control.)* | Fortra Admin Team |
| **E-004** | Permission set licenses **OmniStudio** and **DocGen Designer** assigned to DocGen users. | Fortra Admin Team |
| **E-005** | `ContentDocumentLink` sharing the template `.docx` file to the **DocGen Template Users** public group, and group membership for each DocGen user. | Fortra Admin Team |

---

## 6. Technical Design

### 6.1 Architecture Overview

**Two-stage payload model.** The solution deliberately separates *what template to merge* from *what
data to merge*:

- **Stage A - template & metadata (IP path).** The OmniScript calls IP **`Quote_GenerateDoc`**, which
  resolves the document title, signer defaults, and the `DocumentTemplate` to use. It does **not**
  build the product/pricing body.
- **Stage B - document body (template-bound DataRaptor path).** Because the OmniScript pins
  `useTemplateDRExtract = Yes`, the merge JSON is built **at merge time** by the DataRaptors bound
  *inside* the `DocumentTemplate` record - `DMExtractFortraQuote` (Extract) → `DMTransformFortraQuote`
  (Transform). Neither is referenced by the OmniScript or IP; they run only because the template names
  them as its Extract / Mapper DataRaptors.

**Client-side rendering.** The Word-to-PDF merge runs in the browser via the managed
`omnistudio__clmOsDocxGenerateDocument` component (`docGenerationMechanism = ClientSide`,
`pdfGenerationSource = ClientSide`, output `pdf`). The rendered PDF is stored as a `ContentVersion`,
whose Id (`pdfGenContentVersionId`) is the load-bearing hand-off token between generation and signing.

**OmniScript orchestration.** `DocumentGeneration_Quote_English_3` has 10 top-level steps:

| # | Step | Type | Purpose |
|---|---|---|---|
| 0 | Configuration | Set Values | Sets `isDebug = false` (gates debug blocks). |
| 1 | Retrieve Quote Information | IP Action | Calls `Quote_GenerateDoc` (`extraPayload.contextId = %ContextId%`); result → `IPResult`. |
| 2 | PrepareDocPayload | Set Values | `DocumentTitle = %IPResult:documentTitle%`. |
| 3 | BuildTemplatePayload | Set Values | `templateForLWC:Id = %IPResult:selectedTemplate:Id%`. |
| 4 | GenerationOptions | Set Values | DocGen options: `useTemplateDRExtract = Yes`, `docGenerationMechanism = ClientSide`, format `pdf`. |
| 5 | GenerateDocument | Step (+ managed LWC) | Client-side merge; outputs `pdfGenContentVersionId`. |
| 6 | RecipientDetails | Step | Signer name / email / subject inputs (defaulted from `IPResult`); branded card (`step1`). |
| 7 | ReviewAndSend | Step | PDF preview + confirm; branded card (`step2`). |
| 8 | SendDocuSignEnvelopeAction | IP Action | Calls `Quote_SendDocuSignEnvelope`; `sendOnlyExtraPayload = true`. |
| 9 | ConfirmSent | Step | Shows `envelopeId` / `status` / `pageCount`; branded card (`confirmation`). |

**DocuSign integration.** IP `Quote_SendDocuSignEnvelope` has two elements: a **Remote Action** that
invokes `DocuSignEnvelopeService.sendEnvelope` via the `Callable` interface (5 inputs:
`contentVersionId`, `signerEmail`, `signerName`, `emailSubject`, `pageCount`), and a **Response
Action** that forwards the Apex result. The Apex service reads the PDF `ContentVersion`, resolves the
last page, builds the envelope JSON with sign-here / date / name tabs, and POSTs it to
`callout:DocuSignAPI/v2.1/accounts/{accountId}/envelopes`.

**Security & sharing.** DocuSign API access is granted through the **External Credential principal**
`DocuSign-DocuSignPrincipal` in the `DocuSign API Access` permission set - no secrets in code. The
merge template file is shared to the **DocGen Template Users** public group so authorized users can
read the underlying `.docx`.

**Telemetry.** `DocuSignEnvelopeService` catches failures and calls `ExceptionLogger.log(...)`, which
publishes a `Fortra_Exception__e` platform event (never throwing) that a subscriber persists into
`Exception_Log__c`. The typed `DocuSignEnvelopeException` classifies these entries by exception type.

### 6.2 Data Model

The solution primarily **consumes** existing Quote, QuoteLineItem, and related data and adds a small
set of **document-control fields** on the Quote. It does not introduce new custom objects.

| Object | Field | Type | Description |
|---|---|---|---|
| Quote | `Net_Terms__c` | Picklist (restricted) | Payment net terms. Active values **Net 30** (default), Net 45, Net 60, Net 90, Net 120 (`Immediate` inactive). Rendered as a friendly label on the document. |
| Quote | `Show_Hide_Discounts__c` | Picklist (Show / Hide; default **Show**) | Controls whether discount columns/values print. |
| Quote | `Show_Hide_Signature_Block__c` | Picklist (Show / Hide; **no default**) | Intended to control the signature block on the document. *(See §6.5 - not currently wired into the payload.)* |
| Quote | `Show_Hide_Free_Products__c` | Picklist (Show / Hide; default **Show**) | Controls whether zero-price ("free") products print. |
| Quote | `Show_Hide_Product_Number__c` | Picklist (Show / Hide; default **Show**) | Controls whether the product number prints. |
| Quote | `Language__c` | Picklist | Document language (drives EN vs. localized template intent). |
| Quote | `Quote_Type__c` | Picklist | Quote type; also gates the hardware section (`quoteType = 'Renewal'`). |
| Quote | `Header_Discount_Type__c` | Picklist | Header-level discount type; drives per-line discount display formatting. |
| Quote | `Email` | Email (standard) | Recipient/contact email context for the quote. |
| Quote | `Bill_To_Place__c` / `Ship_To_Place__c` | Lookup (`Places__c`) | Source of the bill-to / ship-to address blocks (and the DocuSign signer defaults). |
| QuoteLineItem | `Description`, `Product_Name__c`, `Fortra_Product_Type__c` | Text / Picklist | Line description, display name, and product type for the line-item rows. |
| QuoteLineItem | `StartDate` / `EndDate`, `ServiceDate` / `Effective_End_Date__c` | Date | Subscription/service term dates (software/services vs. hardware). |
| QuoteLineItem | `Discount` / `DiscountAmount`, `UnitPrice`, `Quantity`, `TotalPrice`, `SortOrder` | Percent / Currency / Number | Line pricing and ordering. |
| QuoteLineItem | `Hardware_ID__c`, `Serial_Number__c`, `Hardware_Notes__c`, `LPAR_Number__c`, `LPAR_System_Name__c` | Text | Hardware line detail. |
| QuoteLineGroup | `Name`, `SortOrder`, `Hardware__c` | Text / Number / Lookup | Groups hardware lines and links to the hardware asset record. |
| Hardware__c | `iSeries_Feature_Code__c`, `Server_Type__c`, `iSeries_Model__c`, `Number_of_Processors__c` | Text / Number | Hardware detail (feature code, system type, model, processors). |
| Places__c | `Address__*` (street/city/state/postal/country), `Street_Address_Line_2/3__c`, `Account__r.Name`, `Contact_Email__c`, `Place_Contact_Phone__c` | Address / Text | Bill-to / ship-to address block content and signer email. |
| User | `Name`, `Email`, `Phone` | Text | Sales rep block (from `Quote.OwnerId`). |
| Account | `Name`, `AccountNumber` | Text | Account name/number in the header and document title. |
| DocumentTemplate | `Name`, `IsActive`, `Status`, `MapperOmniDataTransformName`, `ExtractOmniDataTransformName`, `TokenMappingType`, `DocumentGenerationMechanism` | (standard) | Template lookup + its bound Mapper/Extract DataRaptors and merge config. |
| ContentVersion | (generated PDF) | File | The rendered quote PDF; its Id is passed to DocuSign as `contentVersionId`. |
| Fortra_Exception__e / Exception_Log__c | telemetry fields | Platform Event / Custom Object | Durable failure log for DocuSign/DocGen send errors (see §6.3). |

### 6.2.1 Field Mappings

| Source | Target | Via |
|---|---|---|
| Quote Id (`recordId`) | OmniScript prefill `ContextId` / `ObjectId` / `QuoteId` | `docGenOmniScriotWrapperLWC.prefillData` |
| `%ContextId%` | `Quote_GenerateDoc.extraPayload.contextId` | OmniScript IP Action (step 1) |
| `Account.Name` + `' - '` + `Quote.QuoteNumber` | `documentTitle` (and `emailSubject`) | IP `BuildDocInputParams` (Set Values) |
| Literal `'Fortra Quote Consolidated EN'` | `DMTurboExtractQuoteDocGenTemplate.templateName` | IP `BuildDocInputParams` (hardcoded) |
| `DocumentTemplate` row (Id, Name, Type, VersionNumber, DocumentGenerationMechanism) | `selectedTemplate{Id, Name, TemplateType, VersionNumber, DocumentGenerationMechanism, Select=true}` | `DMTransformFortraDocTemplate` |
| `Places__c (Bill_To_Place__c).Contact_Email__c` | `signerEmail` | IP `Quote_GenerateDoc` ReturnPayload (`billTo:email`) |
| `Places__c (Bill_To_Place__c).Account__r.Name` | `signerName` | IP `Quote_GenerateDoc` ReturnPayload (`billTo:company`) |
| `%IPResult:selectedTemplate:Id%` | `templateForLWC:Id` → merge component | OmniScript `BuildTemplatePayload` (step 3) |
| Quote / QLI / Places / User / Account fields | Raw quote JSON (`lineItems[]`, `hwLineItems[]`, `billTo{}`, `shipTo{}`, `salesRep{}`, header) | `DMExtractFortraQuote` (Extract) |
| Raw quote JSON | Merge tokens (`netTerms`, `IF_showDiscounts`, `lineItems[]`, `hardwareGroups[]`, address blocks, dates, money) | `DMTransformFortraQuote` (Transform) |
| Merge tokens | Rendered PDF (`ContentVersion`) → `pdfGenContentVersionId` | `omnistudio__clmOsDocxGenerateDocument` (client-side merge) |
| `%pdfGenContentVersionId%` | `Quote_SendDocuSignEnvelope.extraPayload.contentVersionId` | OmniScript IP Action (step 8, `sendOnlyExtraPayload=true`) |
| `%signerEmail%` / `%signerName%` / `%emailSubject%` | `DocuSignEnvelopeService.sendEnvelope` inputs | IP Remote Action (`CallDocuSignService`) |
| DocuSign response (`envelopeId`, `status`, `statusDateTime`, `pageCount`) | ConfirmSent card | OmniScript step 9 (`fortraQuoteOsCard` confirmation) |
| Caught exception (`getTypeName` / `getMessage` / stack) | `Fortra_Exception__e` → `Exception_Log__c` | `ExceptionLogger.log()` → subscriber |

### 6.3 Business Logic

- **Template selection.** The IP builds `templateName = 'Fortra Quote Consolidated EN'` and resolves
  the matching active `DocumentTemplate` (`IsActive = true`, `Status = Active`), reshaping it into
  `selectedTemplate{}` (with `Select = true`) for the merge component. *(Selection is effectively
  static today - see §6.5.)*

- **Signer & title defaults.** `documentTitle` = `Account.Name - QuoteNumber`; `emailSubject` reuses
  the title (the OmniScript wraps it as `"[SIGNATURE REQUIRED] Fortra Quote | <title>"`);
  `signerEmail` = bill-to contact email; `signerName` = bill-to company name. All are editable by the
  rep on the RecipientDetails step before sending.

- **Merge-JSON assembly (`DMTransformFortraQuote`).** The Transform converts the raw extract into the
  token model bound to the `.docx` (`targetOutputFileName = "Fortra Quote Consolidated EN(Version 2)"`):
  - **Net terms label.** Maps API values to friendly labels (`Net_0` → *Immediate*, `Net_30` →
    *Net 30*, …), blank → *Due Upon Receipt*, with a raw passthrough fallback.
  - **Discount display.** `IF_showDiscounts = (Show_Hide_Discounts__c = 'Show')`. Per-line and
    per-hardware discount strings are suppressed when Hide; the header total discount renders in
    accounting-negative parentheses, e.g. `(450.00)`.
  - **Dates.** Header and line/hardware dates are reformatted from ISO `YYYY-MM-DD` to `D-Mon-YY`
    (`ISBLANK`-guarded so a missing date yields an empty string).
  - **Product name / description.** `productName` = custom name, falling back to `Product2.Name`;
    line `description` falls back to `productName` when blank.
  - **Address blocks.** Bill-to / ship-to blocks are concatenated from the `Places__c` components,
    including state only for US/CA and appending optional address lines only when present.
  - **Money.** Subtotal, tax, and total are rounded; the `.docx` applies thousands separators. Tax
    renders the literal *Calculation Pending* when no tax is computed.
  - **Section gates.** Boolean tokens gate document sections: `IF_showDiscounts`, `IF_showHardware`,
    `IF_isNewSoftware`, `IF_isSubscription`, `IF_isServices`, `IF_isRenewalMaintenance`, and a
    per-hardware-row `IF_isFirstInGroup` for group headers.
  - **`nullInputsIncludedInOutput = false`.** Genuinely-null inputs are dropped from the JSON (they
    do not appear as empty tokens); formulas emit `''` explicitly where a blank cell is required.

- **DocuSign send (`DocuSignEnvelopeService.sendEnvelope`).**
  1. Read the PDF `ContentVersion`; **reject if > 4 MB** (synchronous send limit).
  2. **Resolve the last page:** explicit `pageCount` if positive → else auto-detect by scanning the
     PDF for `/Type /Page` markers → else fall back to `MIN_FORTRA_PAGES = 2` (never page 1).
  3. Build the envelope JSON: one document (base64 PDF), one signer, and **sign-here / date-signed /
     full-name tabs** positioned on the last page.
  4. POST to `callout:DocuSignAPI/v2.1/accounts/{accountId}/envelopes`; on HTTP 201 return
     `{ success, envelopeId, status, statusDateTime, pageCount }`, otherwise a failure result with
     the DocuSign error body.

- **Entry points.** The service is exposed three ways sharing one core method: the **`Callable`**
  interface (OmniStudio Remote Action), an **`@InvocableMethod`** (Flow / Screen Flow), and the static
  `sendEnvelope(...)`. The `Callable` path also tolerates unresolved OmniStudio tokens (a literal
  `'%pageCount%'` is treated as null → auto-detect).

- **Error handling.** Failures are caught, logged via `ExceptionLogger.log(...)` (never-throw platform
  event → `Exception_Log__c`), and returned as `{ success: false, errorMessage }` so the OmniScript
  can present a graceful message rather than a stack trace. The typed `DocuSignEnvelopeException`
  classifies these entries by exception type.

### 6.4 Integration Points

- **DocuSign eSignature REST API (v2.1).** `DocuSignEnvelopeService` creates and sends envelopes via
  the `DocuSignAPI` callout, authenticated by the `DocuSign-DocuSignPrincipal` External Credential
  principal (granted in the `DocuSign API Access` permission set). Endpoint:
  `callout:DocuSignAPI/v2.1/accounts/{accountId}/envelopes`. The account Id, endpoint, and secrets are
  external org configuration, not source-controlled.

- **OmniStudio Document Generation.** The managed `omnistudio__clmOsDocxGenerateDocument` component
  performs the client-side `.docx` → PDF merge. The document layout and token bindings live in the
  binary `DocumentTemplate` record, bound to `DMExtractFortraQuote` (Extract) and
  `DMTransformFortraQuote` (Mapper).

- **Salesforce Files (Content).** The generated PDF is a `ContentVersion`; the review step previews it
  inline via the same-origin rendition endpoint
  (`/sfc/servlet.shepherd/version/renditionDownload?rendition=ORIGINAL_PDF&versionId=<id>`), chosen
  because it returns `Content-Disposition: inline`. The merge template file is shared through the
  `DocGen Template Users` public group.

- **Platform events / telemetry.** DocuSign/DocGen failures flow through `Fortra_Exception__e`
  (published immediately) into `Exception_Log__c` for support triage.

### 6.5 Known Behaviors & Design Notes

The following are accurate observations of the current implementation, captured so reviewers can
confirm intended behavior (mirroring the candid design-note style used in Fortra's other SDDs). None
block the primary flow; several are candidates for cleanup or a follow-up story.

- **Template selection is effectively static.** `Quote_GenerateDoc` always sets
  `templateName = 'Fortra Quote Consolidated EN'`. The "dominant product type" computation
  (`DMTurboExtractQuoteLineItem` + a `dominantProductType` Set-Values step) and the `InitFlags`
  booleans are computed but not used to pick a template - they are fossils of an earlier
  dynamic-selection design. `DMTurboExtractQuoteLineItem` duplicates a `LIMIT 1` product-type probe
  already embedded in `DMExtractFortraQuote`.

- **Signer name defaults to the company, not a person.** `signerName` resolves to the bill-to
  **company** name (`billTo:company`). If a named individual signer is expected, this should be
  sourced from a contact instead (the rep can still edit it before sending).

- **Hardware section is gated by quote type, not hardware presence.** In `DMTransformFortraQuote`,
  `IF_showHardware = (quoteType = 'Renewal')` - the same expression as `IF_isRenewalMaintenance`. A
  non-renewal quote that legitimately has hardware lines would have its hardware section suppressed
  (and a renewal with no hardware would still show the header). Confirm the intended rule.

- **`Show_Hide_Signature_Block__c` is not wired into the payload.** The field exists on the Quote, but
  `DMExtractFortraQuote` does not extract it and `DMTransformFortraQuote` emits no signature/section
  token for it. The DocuSign signature *tabs* are placed by the Apex service using **absolute
  coordinates** on the last page (x≈360; y≈680/730/755 for sign/date/name), independent of any
  in-document signature block. If the signature block must be toggled or anchored to a reserved region
  in the `.docx`, that is a follow-up (extract the field + template/anchor changes).

- **PDF page auto-detection under-counts compressed PDFs.** `detectPdfPageCount` scans for
  `/Type /Page` markers, which live inside compressed streams in heavily-compressed PDFs; the
  `MIN_FORTRA_PAGES = 2` fallback covers this so tabs still land off page 1. Passing an explicit
  `pageCount` from the merge step would make placement exact.

- **`pageCount` is not currently supplied by the OmniScript.** The send IP maps `pageCount = %pageCount%`;
  the OmniScript's step-8 payload sends only `contentVersionId`, `signerEmail`, `signerName`, and
  `emailSubject`, so `pageCount` arrives unresolved and the service auto-detects (then falls back to 2).

- **DataRaptors are `active = false` in source.** All five DataRaptors carry `active = false` in the
  repository metadata; the org must hold an active version. Re-verify active versions against a fresh
  UAT retrieve before any deploy. *(Related: OmniStudio package upgrades can require re-activating
  OmniScripts/FlexCards - a separate operational concern for DocGen availability.)*

- **`DocuSign API Access` permission set carries unrelated field grants.** Alongside the DocuSign
  External Credential principal access, the permission set includes two `OrderItem` field permissions
  (`COLA_Uplift_Percent__c`, `Multiple_Element_Rev_Alloc_Value__c`) that appear to be unrelated drift
  and could be split out.

- **The `.docx` template is the visual source of truth and is not in source control.** Column
  visibility, cell bindings, and the signature area (if any) are authored in the binary template. Any
  change to what renders (e.g. binding a token to a cell, wrapping a column in a conditional region)
  is a template edit, retrieved/downloaded from Setup → Document Generation.

---

*End of draft - Quote Document Generation & DocuSign Signature Solution Design.*
