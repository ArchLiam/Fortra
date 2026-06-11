# Apex — Hardware, License Keys, Partner Pricing & Operations Checklists

## Overview

This domain covers four loosely related custom (no-namespace) Apex sub-systems layered on top of the Fortra Revenue Cloud / RCA org:

1. **Automate / BPA license-key "points" builders** — a Strategy-pattern family that encodes Fortra Automate & BPA product tiers/options into the cryptic license-key "points string" consumed by the License Key Generator (LKG). Pure business-logic string builders, no DML.
2. **License Key email pipeline** — fired by `LicenseKeyTrigger` (after update) to email generated keys to customers, resolve the right template per brand/product, and push real-time status via Platform Events.
3. **Hardware management** — LWC controllers + an eligibility/pre-config service that drive the hardware-first quoting workflow (Hardware__c records, hardware groups, hardware→QuoteLine linking, hardware-aware pricing attributes).
4. **Partner pricing & checklists** — `SignalingApexProcessor` pricing prehooks (V1 + V2) that apply partner margin/discount models during the RCA pricing procedure, the supporting service layer, plus the Operations Checklist (per-Quote) and Partner Checklist (per-User onboarding) feature areas and the partner-portal self-registration handler.

Most of these were authored by **Marc DeBrey** (late 2025 / early 2026). Several pieces are versioned in place (`PartnerPricingPrehook` vs `…V2`, points-builder "Legacy" variants) — see "Patterns & gotchas".

---

## Automate / BPA License-Key Points Builders

A Strategy + Template-Method family. `AutomatePointsBuilderBase.build(context)` calls the subclass `populatePointsMap()`, then serializes the map into the key string (`<letter><int>` per entry) and appends a version tier (`V<release>` when `isGte11`). The concrete builder per product/tier is selected externally by **`LkgMapperAutomate`** (out of scope — different inventory). "Legacy" variants emit the older key format (extra A/B/C/D flag points, different P/Q/T base values); "Bpa*" variants add E/F/G points for bots / studios / web SMCs.

### Core abstractions

| Class | Role | Purpose / key methods |
|---|---|---|
| `ILkgAutomatePointsBuilder` | Interface | Single contract `String build(AutomatePointsBuilderContext context)`. |
| `AutomatePointsBuilderBase` | Abstract base (Template Method) | Implements `build()`; defines `protected abstract populatePointsMap()`; private `buildPointsString()` serializes `pointsMap` to `<key><value>` and `addVersionTier()` appends `V<release>` when `context.isGte11`. |
| `AutomatePointsBuilderContext` | Wrapper / DTO | Plain bag of inputs: `productCode, tier, release, isGte11`, action counts `TActions/MActions/NActions/PActions`, and `bots/studios/webSmcs`. Drives the per-letter point math. |

### Automate tier builders (current format)

| Class | Role | Purpose / key details |
|---|---|---|
| `AutomateDefaultPointsBuilder` | Concrete builder | Fallback/minimal key — emits only `S1`. |
| `AutomateTierAPointsBuilder` | Concrete builder | Tier A. M/N/P points = base (8 / 204672 / 521983) + action counts; fixed K/L/Q/T. |
| `AutomateTierBPointsBuilder` | Concrete builder | Tier B. All-fixed point set (no action-count add). |
| `AutomateTierCPointsBuilder` | Concrete builder | Tier C. All-fixed; differs from B only in `T` (35 vs 65523). |
| `AutomateTierDPointsBuilder` | Concrete builder | Tier D. Distinct lower-cap point set (K=13858, L=1636, …). |

### Automate tier builders (legacy format)

| Class | Role | Purpose / key details |
|---|---|---|
| `AutomateTierALegacyPointsBuilder` | Concrete builder | Legacy Tier A. Adds `A1` flag, `S2`; M/N/P base 8 / 204672 / **1791** + actions. |
| `AutomateTierBLegacyPointsBuilder` | Concrete builder | Legacy Tier B. Adds `B1` flag; lower P/Q (2047 / 16383). |
| `AutomateTierCLegacyPointsBuilder` | Concrete builder | Legacy Tier C. Minimal — `S1` + `C1` flag only. |

### BPA tier builders

| Class | Role | Purpose / key details |
|---|---|---|
| `BpaTierAPointsBuilder` | Concrete builder | BPA Tier A. `T` = 3635 + `TActions`; adds `E/F/G` = bots / studios / webSmcs. |
| `BpaTierCPointsBuilder` | Concrete builder | BPA Tier C. Same shape as BPA-A but `T` base = 65523. |
| `BpaTierALegacyPointsBuilder` | Concrete builder | Legacy BPA-A. `A1`+`B1` flags, fixed points, plus E/F/G. |
| `BpaTierCLegacyPointsBuilder` | Concrete builder | Legacy BPA-C. `C1`+`D1` flags, fixed points, plus E/F/G. |

> **Note:** The numeric point constants are an external contract with the license-key generator. Treat them as load-bearing magic numbers — do not "clean up" or refactor the values.

---

## License Key Email Pipeline

Triggered by `LicenseKeyTrigger` (after update) → `LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds`. Resolves a per-brand/product email template, sends the key to the account's contacts, writes status back, and publishes a Platform Event so LWCs get live updates.

| Class | Role | Purpose / key methods |
|---|---|---|
| `LicenseKeyEmailHandler` | Service (trigger-invoked) | `ProcessLicenseKeyEmailFromIds(List<Id>)` queries `License_Key__c` + builds emails; `ProcessLicenseKeyEmail(List<License_Key__c>)` returns `Map<Id, EmailResult>`. Core send + status-write logic. |
| `LicenseKeyTemplateResolver` | Resolver / config lookup | Maps Product Code + Key Type → `EmailTemplate` DeveloperName via `LKG_Product__mdt`. `getTemplateName(License_Key__c)`, `hasTemplateConfig(productIdentifier)`. Inner `TemplateConfig` (generic / specific-temporary / permanent / subscription template names). |
| `LicenseKeyNotificationPublisher` | Platform-event publisher | `publishEmailNotifications(List<License_Key__c>)` re-queries status fields and publishes events so any subscribing LWC gets real-time email-status notifications via the streaming API. |
| `LicenseKeyEmailTestDataFactory` | Test data factory (`@isTest`) | Centralized builders for Account / Contacts / Hardware__c / `License_Key__c` (Clearswift, subscription, with-hardware variants) + `EmailTemplate`. Shared across all license-key test classes. |

---

## Hardware Management

LWC server controllers plus an eligibility/pre-config service supporting the hardware-first quoting flow on `Hardware__c`. `HardwarePreConfigInvocable` bridges Hardware__c attribute values into the Revenue Cloud Product Configurator (dynamic defaults) and pricing prehooks.

| Class | Role | Purpose / key methods |
|---|---|---|
| `HardwareGroupController` | LWC controller (`@AuraEnabled`) | Backs the `hardwareGroupManager` LWC. CRUD + assignment for hardware groups: `getQuoteAccountId`, `getExistingGroups`, `searchHardware`, `createHardwareRecord`, `createHardwareGroup`, `updateHardwareGroup`, `assignHardwareToGroup`, `getUnassignedHardware`, `getPicklistOptions`, `getFeatureCodeOptions`. |
| `HardwareManagementController` | LWC controller (`@AuraEnabled`) | Backs the Transaction Line Editor hardware panel. `getAllQuoteLines` / `getSelectedQuoteLines`, `searchHardware`, `linkHardwareToLines`, `flagLinesAsRequiringNewHardware`, `clearHardwareReferences`. Returns `HardwareResult` wrapper (success/message/error/lines). |
| `HardwarePreConfigInvocable` | Invocable + LWC controller | Surfaces Hardware__c attributes as configurator defaults. `@InvocableMethod getHardwareAttributes(List<HardwareAttributeRequest>)` for Flow; `@AuraEnabled` `getHardwareAttributesForLWC`/`ForQuote`, `isProductHardwarePricingApplicable`, `getProductApplicableAttributes`. **Normalizes `P05`→`P5`** (Hardware__c vs AttributeDefinition format mismatch). Pricing precedence per its header: QuoteLineItemAttribute > Hardware__c > System Default. |
| `HardwareProductEligibilityService` | Service | `filterProducts(Id hardwareId)` → `EligibilityResult`: queries active Product2s and filters to those compatible with a hardware record's processors / feature codes. Inner `EligibilityCheck`, `EligibleProduct`, `EligibilityResult`, `EligibilityException`. |
| `HardwareProductSelectorController` | LWC controller (`@AuraEnabled`) | Backs `hardwareProductSelector` LWC. `getEligibleProducts(hardwareId)` (delegates to the eligibility service), `addProductsToQuote(quoteId, productIds, hardwareId)`. Rich `*Wrapper` DTOs for product + hardware context. |

---

## Partner Pricing (Prehooks + Service)

Two parallel generations of an RCA pricing **before-hook** (`RevSignaling.SignalingApexProcessor`, Summer '25). They apply the Quote's selected Partner Pricing Model — **Guaranteed Margin** (additive: list × (1 − Σ partner margins)) or **Discount** (list × (1 − billing partner discount)). Runs AFTER Regional Pricing, BEFORE COLA; `Pre_Partner_Price__c` snapshots the post-regional price. Requires "Procedure Plan Orchestration for Pricing" enabled.

| Class | Role | Purpose / key details |
|---|---|---|
| `PartnerPricingPrehook` | Pricing prehook (`SignalingApexProcessor`) | **V1.** Per-line partner margin/discount application; static `isProcessing` recursion guard; v2.1 propagates adjusted price to NetUnitPrice/UnitPrice for OneTime lines. Heavily `@TestVisible`-decomposed. |
| `PartnerPricingPrehookV2` | Pricing prehook (`SignalingApexProcessor`) | **V2.** Same contract/header but model selection is **deal-type aware**: reads `Deal_Type__c` (e.g. "Fortra Originated") and picks the best-fitting model per line via `PartnerPricingServiceV2.selectBestModelForLine` rather than a single fixed lookup. |
| `PartnerPricingService` | Service (`without sharing`) | V1 business logic. `getPricingModel`/`getPricingModels` (active model lookup), `resolveProductType` + `loadProductTypesForLines`/`ForTransactionLines`, `getMarginForProductType`, `calculateGuaranteedMarginPrice`, `calculateDiscountPrice`. |
| `PartnerPricingServiceV2` | Service (`without sharing`) | V2 logic with **candidate selection**: `getPricingModelCandidates` (ordered list per partner), `selectBestModelForLine(...)` (resolves Fortra-Originated/default/effective-date precedence), `getMarginForProductType`, `calculateGuaranteedMarginPrice`, `calculateDiscountPrice`. |

---

## Operations & Partner Checklists

Two distinct checklist features. **Operations Checklist** = per-Quote (`Quote_Checklist_Item__c`) gating on the Order-Processing stage. **Partner Checklist** = per-User onboarding (`Partner_Checklist_Item__c`, seeded from `Partner_Checklist_Definition__mdt`).

| Class | Role | Purpose / key methods |
|---|---|---|
| `ChecklistInitializationService` | Service + Invocable | `@InvocableMethod initializeChecklistForQuote(List<InitializeRequest>)` — creates checklist items for syncing Quotes when an Opportunity hits Order Processing. Inner `InitializeRequest`/`InitializeResult`. |
| `InitializeChecklistAction` | Invocable (Quick Action) | `@InvocableMethod initializeFromAction(List<Id> opportunityIds)` — manual "Initialize Operations Checklist" button; thin wrapper delegating to `ChecklistInitializationService`. |
| `ChecklistValidationService` | Service + Invocable | `validateChecklistForQuote(Id)` (trigger use) and `@InvocableMethod validateChecklistComplete(...)` (Flow). Returns `ValidationResult` (isComplete, totals, `incompleteItems`). Used to block progression until checklist done. |
| `OperationsChecklistService` | Service (CRUD) | Data access for `Quote_Checklist_Item__c`: `getChecklistItems(quoteId)`, `updateChecklistItem(itemId, isChecked, notes)`, `updateChecklistItemNotes`. Backs the controller; uses `WITH SECURITY_ENFORCED`. |
| `OperationsChecklistController` | LWC controller (`@AuraEnabled`) | Backs the Operations Checklist LWC. `getChecklistItems` (cacheable, returns `ChecklistData` w/ counts + edit permission), `updateChecklistItem`, `hasCustomPermission`. Gated on custom permission **`Operations_Checklist_Access`** via `FeatureManagement.checkPermission`. |
| `PartnerChecklistController` | LWC controller (`@AuraEnabled`) | Per-User partner onboarding checklist. `getChecklistItems()` (current user; lazily seeds from `Partner_Checklist_Definition__mdt` when empty), `updateChecklistItems(List<...>)` upserts by external id `Duplicate_Identifier__c`. |

---

## Partner Portal Registration

| Class | Role | Purpose / key methods |
|---|---|---|
| `PartnerPortalRegistrationHandler` | `Auth.RegistrationHandler` (global) | SSO/portal self-registration. `createUser(portalId, Auth.UserData)` (first auth, no link) + `updateUser(...)`. Defaults: profile **"Basic Partner User"**, America/Los_Angeles, en_US, UTF-8. Custom `RegHandlerException`. Wired to a partner-community Auth Provider. |

---

## Test Classes

All `@isTest`; each targets its same-named subject. Listed for completeness.

| Test class | Covers |
|---|---|
| `AutomateDefaultPointsBuilderTest` | `AutomateDefaultPointsBuilder` |
| `AutomateTierAPointsBuilderTest`, `AutomateTierALegacyPointsBuilderTest` | Automate Tier A (current / legacy) |
| `AutomateTierBPointsBuilderTest`, `AutomateTierBLegacyPointsBuilderTest` | Automate Tier B (current / legacy) |
| `AutomateTierCPointsBuilderTest`, `AutomateTierCLegacyPointsBuilderTest` | Automate Tier C (current / legacy) |
| `AutomateTierDPointsBuilderTest` | Automate Tier D |
| `BpaTierAPointsBuilderTest`, `BpaTierALegacyPointsBuilderTest` | BPA Tier A (current / legacy) |
| `BpaTierCPointsBuilderTest`, `BpaTierCLegacyPointsBuilderTest` | BPA Tier C (current / legacy) |
| `ChecklistInitializationServiceTest`, `ChecklistValidationServiceTest`, `InitializeChecklistActionTest` | Operations checklist init / validation / quick action |
| `OperationsChecklistServiceTest`, `OperationsChecklistControllerTest` | Operations checklist service + controller |
| `PartnerChecklistControllerTest` | Partner onboarding checklist |
| `HardwareGroupControllerTest`, `HardwareManagementControllerTest`, `HardwarePreConfigInvocableTest`, `HardwareProductEligibilityServiceTest`, `HardwareProductSelectorControllerTest` | Hardware management area |
| `LicenseKeyEmailHandlerTest`, `LicenseKeyNotificationPublisherTest`, `LicenseKeyTemplateResolverTest`, `LicenseKeyTriggerTest` | License-key email pipeline (handler / publisher / resolver / trigger). `LicenseKeyEmailTestDataFactory` is the shared fixture. |
| `PartnerPortalRegistrationHandlerTest` | Portal registration handler |
| `PartnerPricingPrehookTest`, `PartnerPricingPrehookV2Test`, `PartnerPricingServiceTest`, `PartnerPricingServiceV2Test` | Partner pricing prehooks + services (V1 / V2) |

---

## Patterns & gotchas

- **Two live generations everywhere.** `PartnerPricingPrehook`/`Service` (V1) and `…V2` coexist with near-identical headers. V2 adds deal-type-aware *candidate selection* (`selectBestModelForLine`, `Deal_Type__c`). Confirm which generation is wired into the active RCA pricing procedure before editing — partner-pricing net-not-applied is an open issue (see SC-3359 memory; `SubscriptionPricing74` lives in the procedure, not here).
- **Pricing prehooks are `SignalingApexProcessor` before-hooks**, ordered AFTER Regional Pricing / BEFORE COLA. They mutate price fields and rely on a static `isProcessing` recursion guard. Editing pricing-step order or the procedure can silently change behavior. Heavy `@TestVisible` decomposition is intentional for the prehooks.
- **Points-builder constants are an external contract** with the license-key generator. The big integers (e.g. 524287, 204672) and single-letter keys encode product entitlements; "Legacy" vs current is a format generation. Do not refactor values; the dispatcher is `LkgMapperAutomate` (separate inventory).
- **`HardwarePreConfigInvocable` straddles formats:** `Hardware__c.P_Group_List__c` uses `P05`, but `AttributeDefinition` uses `P5` — it normalizes on the way into the configurator. The stated pricing precedence (QuoteLineItemAttribute > Hardware__c > System Default) lives in the prehook, not here.
- **Two unrelated "checklists."** Operations Checklist is **per-Quote** and gated by custom permission `Operations_Checklist_Access`; Partner Checklist is **per-User onboarding**, seeded from `Partner_Checklist_Definition__mdt` and upserted by external id `Duplicate_Identifier__c`. Don't conflate them.
- **License-key emailing is trigger-driven** (`LicenseKeyTrigger` after update → `LicenseKeyEmailHandler`), with template selection externalized to `LKG_Product__mdt` and status surfaced to LWCs via Platform Events (`LicenseKeyNotificationPublisher`). Template config is data, not code.
- **Sharing:** partner-pricing services run `without sharing` (system-context pricing); checklist/hardware controllers run `with sharing`. The portal registration handler is `global` and bound to an Auth Provider — renaming/removing it breaks partner SSO.
