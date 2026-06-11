# Apex — Integration, Platform & Misc

## Overview

This is the catch-all Apex domain for the Fortra org: everything that is **not** core
pricing/order/quote logic. It covers outbound integrations (Workday platform events,
MuleSoft D&B enrichment, DocuSign, Globalscape/InterPayment, Microsoft JWT token), the
**license-key email** subsystem (brand-handler strategy + dependency-injected sender),
Experience-Cloud / Site authentication controllers (mostly Salesforce-generated boilerplate),
RCA migration admin tooling (product creators, context-definition dependency management), a
handful of trigger handlers and Flow invocables, and assorted Flow/utility helpers. Most of
the heavy domain logic lives in the email and RCA sub-domains; the auth controllers are
near-stock and exist only to satisfy Experience Cloud page bindings.

Managed-package classes (`pse__`, `c2g__`, etc.) are out of scope. A few classes here
reference `pse__` objects (PSA) or `RevSignaling` (Revenue Cloud) but are themselves
no-namespace custom code and are documented.

---

### Email — License-Key Email Subsystem

A dependency-injected, brand-aware email engine for sending license keys. `EmailService`
is the entry point; the `IEmailSender` seam swaps a real Messaging sender for a mock in
tests; `BrandEmailHandlerFactory` selects per-silo (Clearswift / PowerTech / Automate)
recipient + template logic.

| Class | Role | Purpose / key methods |
|---|---|---|
| `EmailService` | Service (entry point) | `sendLicenseKeyEmail(...)` (2 overloads) — sends a `License_Key__c` email by template API name. Injects `IEmailSender emailSender` (`@TestVisible`, defaults to `DefaultEmailSender`). |
| `IEmailSender` | Interface | Single `sendEmail(List<SingleEmailMessage>)` — abstracts Messaging API for testability. |
| `IEmailSenderResult` | Interface | `isSuccess()`, `getErrorMessage()` — wraps a send result without stubbing system classes. |
| `DefaultEmailSender` | Implementation | Production sender; calls `Messaging.sendEmail(emails, false)` (allOrNone=false for deliverability-restricted orgs). Returns `RealEmailSenderResult`. |
| `RealEmailSenderResult` | Wrapper | Wraps `Messaging.SendEmailResult`; production `IEmailSenderResult`. |
| `MockEmailSender` | `@isTest` mock | Captures `sentEmails` for assertions; configurable `shouldSucceed`. Used when Email Deliverability = "System email only". |
| `MockEmailSenderResult` | `@isTest` mock | Stub `IEmailSenderResult` for the mock sender. |
| `EmailResult` | Wrapper | Success/failure + user-friendly message DTO returned by `EmailService`. |
| `EmailAttachmentService` | Service | `getAttachmentForLicenseKey(Id)` — finds the license file (checks legacy `Attachment` first, then `ContentDocument`) and builds an `EmailFileAttachment`. |
| `EmailTemplatePlaceholderProcessor` | Utility | `replacePlaceholdersWithInjectedText(...)` — replaces `\|\|Placeholder\|\|` tokens with `Text_Injection__c` custom-metadata values (incl. product instructions); `removeUnreplacedMergeFields(...)`. NOT a merge-field evaluator. |
| `IBrandEmailHandler` | Interface | Per-brand contract: `getRecipient1Email`, `getRecipient2Email`, `getEmailTemplateForLicenseKey(License_Key__c)`. |
| `BaseBrandEmailHandler` | Abstract base | Default shared recipient/template logic; **extend this, not the interface**. Exposes `getDefaultHandler()` returning inner `DefaultBrandEmailHandler`. |
| `BrandEmailHandlerFactory` | Factory | `getHandler(siloName)` — normalizes silo name, caches and returns the brand-specific `IBrandEmailHandler`; falls back to default handler when blank. |

Test classes: `EmailServiceTest`, `EmailAttachmentServiceTest`, `EmailResultTest`,
`EmailTemplatePlaceholderProcessorTest`, `RealEmailSenderResultTest`,
`BaseBrandEmailHandlerTest`, `BrandEmailHandlerFactoryTest`, `testemaildeliverbility`
(empty placeholder class — effectively dead).

### Email — License-Key Generation (LKG) interfaces

Interfaces for the license-key-generation pipeline (concrete builders/mappers/creators live
outside this list, e.g. `LkgProcessor`, `LkgRequestBuilderBase`).

| Class | Role | Purpose |
|---|---|---|
| `ILkgMapper` | Interface | `mapPayloadToKeyData(String payload)` → `LkgRequestBuilderBase.KeyData`. |
| `ILkgRequestBuilder` | Interface | `buildRequest(KeyData)` → `LkgProcessor.LicenseKeyRequest`. |
| `ILkgRecordCreator` | Interface | `createLicenseKeyRecord`, `insertLicenseKeyRecord`, `createAttachment` — persists `License_Key__c` + attachment. |

### Integrations — Outbound Callouts & Platform Events

| Class | Role | Purpose / endpoint |
|---|---|---|
| `DunAndBradstreetHandler` | Invocable + callout | `@InvocableMethod dunsEnrichment(...)` and `dunsCallout(Account)` — calls D&B via **MuleSoft** (`callout:Mulesoft_DUNS`, `client_id`/`client_secret` credentials) and enriches the Account. |
| `DunAndBradstreetHelper` | Invocable | `@InvocableMethod dunsSearch(List<Account>)` — same MuleSoft callout but returns matches WITHOUT committing enrichment DML; falls through to `searchForAccount` SF match. |
| `DunsResponseWrapper` | Wrapper | DTO for D&B response payload (success `data`/`DunsResult` + failure `statusCode`/`errorMessage`). |
| `AccessTokenGenerator` | Token helper | `generateDunsToken()` — fetches a Microsoft OAuth client-credentials token (`callout:Microsoft_JWT_for_DUNS`, `$Credential` merge fields) for the D&B flow. |
| `DocuSignEnvelopeService` | Service / Invocable / `Callable` | Sends a Fortra quote PDF for e-signature via `callout:DocuSignAPI` named credential. Three entry points: `call(...)` (OmniStudio Remote Action), `@InvocableMethod sendEnvelopeInvocable`, and `sendEnvelope(...)`. `detectPdfPageCount(Blob)` auto-places the signature on the last page. |
| `GsLicensingController` | Aura controller + callout | `@AuraEnabled processOrder(orderId)` — LWC Quick Action on Order; calls Globalscape (`callout:GS_License_Gen_API`) to generate serials/licenses. (`without sharing`.) |
| `BSIInvoicePaymentLinkController` | VF page controller + callout | `goToPaymentLink()` — accepts an invoice id, redirects to an InterPayment credit-card payment page. Settings from custom metadata; deliberately opaque `stockError` for security. (`without sharing`.) |
| `FortraBillingEventItemTriggerHandler` | Trigger handler | `handleAfterInsertOrUpdate(...)` on `pse__Billing_Event_Item__c`; recursion-guarded; publishes `Billing_Event_Item_Released_WD__e` **platform events** to Workday when sync status flips to Pending. |

### Trigger Handlers (non-integration)

| Class | Role | Purpose |
|---|---|---|
| `OpportunityTriggerHandler` | Trigger handler | Manages `Hardware__c` lifecycle from Opportunity stage: Closed Lost → delete `Quoting` hardware (if unreferenced); Order Processing → `Quoting`→`Active`. Path: Opp → Quote → QuoteLineGroup → Hardware__c. |

### RCA Migration — Product Creator Admin Tools

LWC-backed admin tooling built for the Revenue Cloud (RCA) catalog migration ("Coastal —
Fortra RCA Migration"). Two flavors: bulk **commercial** product creation from CSV/Excel,
and **technical** (fulfillment) product creation with decomposition rules.

| Class | Role | Purpose / key methods |
|---|---|---|
| `RCAProductCreationController` | Aura/LWC controller | `parseCSVFile`/`parseExcelFile`, `validateProducts`, `createProducts`, `getReferenceData`, `getCSVTemplate`, `getDefaultColumnMappings`. Drives the bulk product-import LWC. |
| `RCAProductCreationService` | Service | Bulk-creates `Product2` + `ProductSellingModelOption`, `ProductCategoryProduct`, `ProductComponentGroup`, `ProductRelatedComponent`, `PricebookEntry`. Caches selling models/categories/pricebooks. |
| `RCATechnicalProductController` | Aura/LWC controller | `searchCommercialProducts`, `getProductsByIds`, `validateRequests`, `createTechnicalProducts`, `getSuggestedTechnicalProduct`/`getBulkSuggestedTechnicalProducts`. |
| `RCATechnicalProductService` | Service | Creates technical `Product2` + `ProductFulfillmentDecompRule`, sets commercial product `DecompositionScope = 'OrderLineItem'`; copies PSMO/PBE/category. **Atomic** — full rollback via `Database.Savepoint` if any related record fails. |
| `RCACatalogTreeController` | Aura/LWC controller | `getProductCatalogs()` etc. — navigates `ProductCatalog`/`ProductCategory` hierarchies for tree UI; returns `CatalogWrapper`s. |

### RCA — Context Definition Dependency Management

Tooling to safely deactivate/reactivate Revenue Cloud `ContextDefinition`s by walking the
ExpressionSet dependency tree (load-bearing during pricing-procedure rework — see the
pricing context memos). Backs an LWC.

| Class | Role | Purpose / key methods |
|---|---|---|
| `ContextDefinitionManager` | Service (LWC backend) | `getContextDefinitions`, `getDependencyTree`, `deactivateAllDependencies`/`reactivateDependencies` (+ per-version and rule-library-version variants). Deactivates all `ExpressionSetVersion`s before deactivating a Context Definition, then reactivates in order. Note: `ProductConfigurationRule.Status` is NOT DML-updateable (Metadata API/UI only). |
| `ContextDefinitionFieldValidator` | Validator | Checks whether key RCA fields (e.g. `ExpressionSetVersion.IsActive`) are createable/updateable via DML; returns `FieldValidationResult`. Run via Anonymous Apex or the dependency flow. |
| `ContextDependencyWrapper` | Wrapper | DTOs for the dependency tree (`ContextDefinitionNode`, `ExpressionSetNode`, `ConfigurationRuleNode`, `OperationResult`, `ContextDefinitionSummary`, etc.). |

### Pricing Prehook (SignalingApexProcessor) in this bucket

| Class | Role | Purpose |
|---|---|---|
| `QLDescriptionGeneratorPrehook` | Pricing prehook (`RevSignaling.SignalingApexProcessor`) | `execute(TransactionRequest)` — auto-generates `QuoteLineItem.Description` by joining up to ~10 hardcoded config attributes with ` \| `. **Must run LAST** in the prehook chain (SC-3349). Source of the SC-3335 description regression and the `Number_of_Units` device-count fix. |
| `PricingPrehookTestFixtures` | `@isTest` fixture | Shared builders (Account, `Hardware__c`, etc.) for the pricing-prehook test suite. Author: Marc DeBrey. |

### Bulk / Batch Tools

| Class | Role | Purpose |
|---|---|---|
| `BulkUpdateAccountTeamsController` | Invocable + Aura | `@InvocableMethod invokeBulkUpdateAccountTeams` — routes <100 accounts inline vs. ≥100 to batch; `getAccountsWithTeamMemberCount` for the LWC. |
| `BulkUpdateAccountTeamsBatch` | Batchable (Stateful) | Re-applies the Account-Team flow per scope; stashes `allResults` in `Cache.Org` keyed by job id for the UI to poll. |
| `BulkUpdateDatesController` | Aura controller | `getEligibleQuoteLines(quoteId)` + bulk date update for **Term-Defined** QLIs only. Two modes: DATE_RANGE (calc term) and DATE_AND_TERM (calc end date). Author: Marc DeBrey. |
| `FlexPanelBulkUpdateController` | `@RemoteAction`/Aura controller | `bulkUpdateDatesRemote(ids, startDate, updateMode, term, endDate)` — VF + LWC bulk date update (FlexPanel variant). |
| `PortalUserManagementHelper` | Invocable + Aura admin | `@InvocableMethod giveFortraAcademyAccess` (`@future` to avoid mixed DML); `getUsers`/`searchUsers`/`activateUsers`/`deactivateUsers`/`modifyUsersProfile` for a portal-user admin LWC. |

### Site / Community Authentication Controllers (mostly stock)

Salesforce-generated Experience Cloud / Site controllers. Near-boilerplate; document by
existence. Bound to VF pages / Aura login components.

| Class | Role | Purpose |
|---|---|---|
| `ChangePasswordController` | VF controller | `Site.changePassword(...)`. |
| `ForgotPasswordController` | VF controller | `Site.forgotPassword(username)`. |
| `MyProfilePageController` | VF controller | Edits portal user profile; blocks GUEST users. |
| `CommunitiesLandingController` | VF controller | `Network.communitiesLanding()` start-page routing. |
| `CommunitiesLoginController` | VF controller | `Network.forwardToAuthPage(...)`. |
| `CommunitiesSelfRegController` | VF controller | Self-registration (`registerUser`), sets experience id. |
| `CommunitiesSelfRegConfirmController` | VF controller | Empty confirm-page shell. |
| `MicrobatchSelfRegController` | VF controller | Microbatch self-register variant. |
| `SiteLoginController` | VF controller | `Site.login(...)` (global). |
| `SiteRegisterController` | VF controller | Creates portal user. **Hardcoded `PORTAL_ACCOUNT_ID = '001x000xxx35tPN'`** placeholder — looks unconfigured/dead. |
| `LightningForgotPasswordController` | Aura controller | `forgotPassword(username, checkEmailUrl)`. |
| `LightningLoginFormController` | Aura controller | `login(...)`, `getIsUsernamePasswordEnabled()`. |
| `LightningSelfRegisterController` | Aura controller | Self-register with password validation. |
| `AutoHeadlessUserDiscHandler1754336372522` | Auth handler | Auto-generated `Auth.HeadlessUserDiscoveryHandler`; resolves user by verified email/SMS for headless (passwordless) login. Name is a generated timestamp — do not rename. |

### Flow / Utility Helpers (Invocables & misc)

| Class | Role | Purpose |
|---|---|---|
| `TerritoryFlowHelper` | Invocable | `@InvocableMethod getProductAssignments` — matches marketing products to `Sales_Territory__c` by priority (Solution Category → Group → Unit, then geo); routes unmatched to `Unassociated_Inquiries_Queue`. |
| `FindRecordsInCollection` | Invocable (global) | `@InvocableMethod` "Find Records in Collection [USF Collection Processor]" — filters an in-memory SObject collection by field/value in Flow. |
| `MultiSelectPicklistParser` | Invocable | Splits a semicolon-delimited multi-select picklist string into a loopable text collection for Flow. |
| `TextParse` | Invocable | Splits semicolon text into a collection; also extracts currency codes + conversion rates. |
| `FieldPopulatedCheck` | Invocable | **⚠️ DEPRECATED (SC-3366)** — superseded by `OrderSubmissionValidator`; per-field populated check that caused the order-submission SOQL-in-loop governor blowup. No longer called by the active flow; do NOT use in new work. |
| `DisplayAndFilterKnowledgeController` | Aura controller | `getKnowledgeArticles()` — dynamically queries all accessible `Knowledge__kav` fields where `PublishStatus = 'Online'`. |
| `Q2OConversionFaultHandler` | Invocable fault handler | Single-fault handler for the Convert-Quote-to-Order flow's fault path. **Intentionally NOT bulkified** (one Request/call); classifies governor-limit vs. misleading/real legal-entity errors and cleans up a Draft order. |
| `PsmoOrphanScanner` | Batchable (Stateful) | One-off migration scanner: finds `PricebookEntry` rows whose `(Product2, ProductSellingModel)` pair has no matching `ProductSellingModelOption` (orphans). Diagnostic only. |
| `FortraDemoDataFactory` | Data factory (Execute Anonymous) | `run()`/`cleanup()` — generates demo quotes/data for the 4 Fortra document templates. **Sandbox-only**; idempotent; verify picklist values before running. |

---

## Patterns & gotchas

- **Dependency injection via `@TestVisible` seam:** the email subsystem swaps
  `IEmailSender`/`IEmailSenderResult` for mocks (`MockEmailSender`) so tests pass in orgs
  with Email Deliverability locked to "System email only". `Messaging.sendEmail(..., false)`
  (allOrNone=false) is used deliberately for the same reason. Follow this pattern for any new
  email code.
- **Strategy + Factory for brands:** extend `BaseBrandEmailHandler`, never implement
  `IBrandEmailHandler` directly; `BrandEmailHandlerFactory.getHandler(silo)` is cached and
  case/space-insensitive.
- **Integration credentials are externalized:** D&B/DUNS, DocuSign, Globalscape, InterPayment
  all use Named Credentials / External Credentials (`callout:...`, `$Credential.*` merge
  fields). No secrets in code. D&B routes through **MuleSoft**, not direct.
- **Workday is event-driven:** `FortraBillingEventItemTriggerHandler` publishes
  `Billing_Event_Item_Released_WD__e` platform events (mirrors the broader
  `Order_Completed_WD__e` re-submit pattern); the handler is recursion-guarded.
- **`QLDescriptionGeneratorPrehook` is order-sensitive** — it must execute LAST in the
  pricing-prehook chain or descriptions regress (SC-3335/SC-3349). It is a
  `RevSignaling.SignalingApexProcessor`, not a normal class.
- **`FieldPopulatedCheck` is deprecated** (SC-3366) — left in place only for old flow
  versions; the duplicate per-field SOQL caused `Too many SOQL queries:101`. Use
  `OrderSubmissionValidator`.
- **RCA technical-product creation is atomic** (`RCATechnicalProductService` uses a savepoint
  rollback); RCA Context-Definition tooling is **load-bearing** during pricing-procedure
  rework — it deactivates/reactivates ExpressionSet versions in order, and knows
  `ProductConfigurationRule.Status` cannot be set via DML.
- **Near-stock auth controllers:** the Communities/Site/Lightning login classes are
  Salesforce-generated; treat as boilerplate. `SiteRegisterController` has a hardcoded
  placeholder `PORTAL_ACCOUNT_ID` and is likely inert.
- **Naming oddities:** `AutoHeadlessUserDiscHandler1754336372522` has a generated timestamp
  name (do not rename — it's referenced by Auth config); `testemaildeliverbility` is an empty
  shell; `Claude Code` appears as author on several Flow-helper classes.
