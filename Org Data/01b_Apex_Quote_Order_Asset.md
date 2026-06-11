# Apex — Quote / Order / Asset / Renewal Lifecycle

## Overview

This domain covers the Apex behind Fortra's Revenue Cloud (RLM/RCA) commerce lifecycle: **Quote → Order → Asset**, plus the renewal/amend pricing chain and the bulk migration tooling that imports legacy CPQ quotes into Revenue Cloud. The center of gravity is the **Quote-to-Order (Q2O) flow** (`Fortra_Convert_Quote_To_Order` / `Fortra_Assetize_Order`), which is a Salesforce Flow orchestrating a sequence of `@InvocableMethod` Apex actions: reprice the order, split Power lines, map custom fields, activate, then create lifecycle-managed Assets and link them to Contracts. A parallel set of **batch + LWC-controller + service** triples (`*MigrationBatch` / `*MigrationController` / `*MigrationService`, all by Marc DeBrey) drives the one-time legacy data migration. Renewal pricing (the COLA / SC-3350 family) is handled by trigger handlers and queueables that normalize renewal quote type, strip platform carryover lines, and persist maintenance-dollar decomposition for carry-forward.

Most of these classes are **flow-invoked or trigger-invoked**, not directly called by tests/UI, and several are load-bearing for live pricing and Workday integration. See *Patterns & gotchas* at the end.

---

### Quote-to-Order conversion (flow-invoked actions)

These run in sequence inside the Q2O / Assetize flows. Order matters.

| Class | Role | Purpose / key methods |
|---|---|---|
| `OrderRepriceInvocable` | Invocable (`without sharing`) | SC-3308 fix. Reprices an Order in place via `commerceorders.PlaceOrderExecutor` (PricingPreferenceEnum.Force = programmatic "Reprice All") so it reaches **CompletedWithPricing before activation**; first seeds/persists maintenance decomposition via `MaintenanceOrderDecompositionService`. `reprice(List<Request>)` returns Calculation Status / Validation Result / `pricingReady` so the flow can gate `Activate_Order`. |
| `QuoteToOrderFieldMapper` | Invocable service | Bridges the gap left by standard `createOrderFromQuote`, which does **not** copy custom lookups. Maps `QLI.Hardware__c → OI.Hardware__c`, `Hardware_ID__c`, `Partition_Reference__c → OI.Partition_Record__c`. `Source_List_Price__c` mapping is **DISABLED** (use flow + context def). Also persists FORTRA-PRODUCT-018 maintenance Base/Partner$/Discretionary$ for renewal carry-forward. `mapFields(List<MapRequest>)`. |
| `PowerOrderSplittingService` | Invocable service | Splits Power product order lines with qty > 1 into individual qty=1 lines during Q2O, cloning/sharing Hardware + Partition records per the product's **Power Split Type** ("Order Line Only" = hardware shared; "Order Line and Hardware" = hardware cloned). Bulk-safe, fixed SOQL/DML budget. `splitPowerOrderLines(...)`, `processOrder(Id)`. **Note (SC-3210):** also sets `Original_Order_Item__c` on qty-split parents, which downstream Workday line-type logic can misread. |
| `MaintenanceOrderDecompositionService` | Service | FORTRA-PRODUCT-018 Step 5. Persists maintenance dollar decomposition (Base / Partner$ / Discretionary$) onto OrderItem at Q2O so **renewal pricing carries real dollars forward**. Loads order+quote context once (`loadWork`/`OrderMaintenanceWork`), builds patches (`buildPatchesFromWork`, `buildCommercialPatchesFromWork`), seeds derived maintenance lines (`seedFromWork`), and `prepareForReprice` / `persistFromWork` are called by `OrderRepriceInvocable`. `resolveTierRate` / `compute` derive the decomposition. |
| `AssetContractLinkerAction` | Invocable | Creates `AssetContractRelationship` (ACR) records for Assets created from an Order that has a `ContractId`. Called by `Fortra_Assetize_Order` after `createOrUpdateAssetFromOrder`. Enforces ACR prerequisites (Contract has AppUsageAssignment, StartDate required, EndDate ≤ Contract EndDate, no duplicate ACR). `linkAssetsToContract(List<ActionInput>)`. |
| `PopulateAssetLegacyFieldsAction` | Invocable (`without sharing`) | Backfills **legacy** Asset fields (Status, Quantity, Price) that Revenue Cloud's `createOrUpdateAssetFromOrder` leaves null on lifecycle-managed Assets. Reads the `AssetActionSource` records created alongside each Asset. Called from `Fortra_Assetize_Order` right after asset creation. `populateFields(List<FlowInput>)`. |
| `OrderCascadeDeleter` | Invocable | Deletes an Order plus all dependent fulfillment records (FulfillmentOrders, FOLIs, step sources, steps, plan, AUA) inside a savepoint. `cascadeDelete(List<Input>)` → per-order `runOne`. Cleanup/admin utility. |

### Order validation & submission

| Class | Role | Purpose / key methods |
|---|---|---|
| `OrderValidationTriggerHandler` | Trigger handler | `handleBeforeInsert` blocks Order creation unless the source Quote's Operations Checklist is complete (delegates to `ChecklistValidationService`). Has a static **`bypassValidation`** flag used by migration (legacy quotes lack checklist items). |
| `OrderSubmissionValidator` | Invocable service | **SC-3366 fix.** Bulk, metadata-driven "required field populated" check for the Order submission flow (`Fortra | Order | Submission Check`). Replaces the per-field `FieldPopulatedCheck` SOQL-in-loop that breached the 100-SOQL governor on ~16+ line orders. One invocation returns all blank-required-field errors in **constant SOQL**. Rules live in `Order_Submit_Validation__mdt` (Object/Field/Relationship-Field/Error-Message). `validate(List<ValidationRequest>)`. |

### Renewal / amend pricing (COLA / SC-3350 family)

| Class | Role | Purpose / key methods |
|---|---|---|
| `QuoteRenewalTypeHandler` | Trigger handler | Forces `Quote_Type__c = 'Renewal'` on asset-initiated renewal quotes (`OriginalActionType = 'Renew'`) so Product Configuration Rules (e.g. Year-2 Maintenance AutoAdd, keyed off the `QuoteTypeText__c` formula) evaluate correctly. `applyRenewalQuoteType` / `normalizeRenewalQuoteType`. |
| `RenewalQuoteLineHandler` | Handler | Removes platform-copied carryover lines (Year-1 license + New Maintenance) from renewal quotes once a **Renewal Maintenance** line exists, so Year 2+ quotes bill Renewal Maintenance only (`PIA-PIA-RRM-PIAM`). Guarded so it never strips before the Year-2 config rule runs. `enqueueCarryoverCleanup` (from QLI after insert) defers via queueable; `removeNewMaintenanceCarryover*`. |
| `RenewalQuoteLineCleanupQueueable` | Queueable | Defers the carryover-line delete until **after Place Sales Transaction** completes — synchronous deletes in `after insert` break TLE Configure + Save. Just calls `RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes`. |
| `AssetContractQueryHelper` | Selector (`without sharing`) | Marc DeBrey. Queries `AssetContractRelationship` + Contract for COLA-override fields (`colaOverridePercent`, `colaPersistUntil`, status) for given Asset Ids. Exists because RCA objects aren't reliably reachable via dynamic SOQL with relationship traversal in `with sharing` trigger context. `queryAssetContracts(Set<Id>)` → `AssetContractData` wrappers. |

### Quote editing / cloning / sync / repricing

| Class | Role | Purpose / key methods |
|---|---|---|
| `QuoteCloneService` | Service (AuraEnabled) | Clones a Quote with all line items, pricing and relationships; handles RCA syncing via `Opportunity.SyncedQuoteId`. `cloneQuote` (Flow-simple, makes clone primary), `cloneQuoteWithLines(Id, CloneOptions)`, plus sync helpers `syncQuoteToOpportunity[Async]`, `stopSyncingQuote`, `isQuoteSyncing`. Savepoint-wrapped. |
| `QuoteSyncQueueable` | Queueable | Sets `Opportunity.SyncedQuoteId` asynchronously — it **cannot** be set in the same transaction as Quote DML. Constructed with quote Ids or a quote→opportunity map. |
| `QuoteSyncingTriggerHandler` | Trigger handler | `handleAfterUpdate`: when `Quote.IsSyncing` flips false→true, initializes the Operations Checklist on the related Opportunity (`processOpportunities`). `@TestVisible` seam because `IsSyncing` is read-only. |
| `QuoteRepricingController` | Controller (AuraEnabled) | Reprices all quote lines after a header discount change, with record-lock timing checks. `repriceQuote(Id, discountType)` (PERCENTAGE/AMOUNT, proportionate distribution by Subtotal), plus availability helpers `isQuoteAvailable`, `waitForQuoteAvailable`. |
| `QuoteCurrencyChangeService` | Invocable service | Recalculates quote lines when currency changes by rebuilding QLIs (creates new lines before deleting old). **Superseded by the `_Fixed` variant.** `handleCurrencyChange(List<Request>)`. |
| `QuoteCurrencyChangeService_Fixed` | Invocable service | Corrected currency-change action: first updates `Quote.CurrencyIsoCode` (and uses `Pricebook2Id`), then rebuilds lines from product Ids. Use this over the un-suffixed version. `handleCurrencyChange(List<Request>)`. |

### QuoteLineGroup / QuoteLineItem hardware linking (trigger handlers)

| Class | Role | Purpose / key methods |
|---|---|---|
| `QuoteLineGroupTriggerHandler` | Trigger handler | When a group's `Hardware__c` changes, cascades `Hardware_Reference__c` to **all** quote lines in the group (set, change, or clear). `handleHardwareChange(newGroups, oldMap)`. |
| `QuoteLineItemTriggerHandler` | Trigger handler | When a QLI is added to / removed from a hardware group (`QuoteLineGroupId` changes), auto-sets/clears `Hardware__c` from the group. `handleHardwareLinking(newLines, oldMap)`. |

### Migration tooling — Quote (legacy CPQ → Revenue Cloud)

Marc DeBrey, 2026-02. The `Controller` is the LWC entry point; `Service` holds the logic; `Batch` runs it.

| Class | Role | Purpose / key methods |
|---|---|---|
| `QuoteMigrationBatch` | Batch (Stateful, AllowsCallouts) | Populates RCA fields on migrated Quotes/QLIs: computes subscription terms, applies `Migration_Field_Default__mdt` defaults, and **preserves customer-accepted prices** (capture → calculate → restore). Optionally sets Status=Accepted for Q2O readiness; logs to `Migration_Run_Log__c` + emails. |
| `QuoteMigrationController` | Controller (AuraEnabled) | LWC API: `getRecordCounts`, `getFieldGapAnalysis`, `startMigration(filter, prepareForQ2O, batchSize, includeReprice)`, `getBatchStatus`, `getMigrationDefaults`, plus QLIA CSV load (`startAttributeLoad` / `getAttributeLoadStatus`). |
| `QuoteMigrationService` | Service | Analyze/preview/transform helpers: `getRecordCounts`, `getFieldGapAnalysis`, `resolveDefaults`, `calculateQLIFields`, `calculateQuoteFields`, price `capturePriceFields`/`restorePriceFields`, `repriceQuote`, `createPreCheckedChecklistItems`. |

### Migration tooling — Order (Quote → RCA Order + Asset)

Marc DeBrey, 2026-03/04. Implements the **AUA-bypass pipeline** (activate without AppUsageAssignment to skip CalculationStatus checks, then add AUA + create Assets via REST).

| Class | Role | Purpose / key methods |
|---|---|---|
| `OrderMigrationBatch` | Batch (Stateful, AllowsCallouts) | Creates RCA Orders from migrated Quotes with direct/pre-set pricing (bypasses headless pricing): resolve/create Contract → create Draft Order (no AUA) → OrderAction + map QLIs → activate via DML → add AUA → create Assets via `createOrUpdateAssetFromOrder` REST → optionally activate Contract. Supports pricebook override + auto-create-missing-PBE. |
| `OrderMigrationCleanupBatch` | Batch (Stateful) | Deletes migration-created records in dependency-safe order: ACRs → Assets → AUAs(Order) → OrderItems → OrderActions → Orders (re-Draft if Activated) → AUAs(Contract) → Contracts (`Migration_Created__c=true`). Identifies orders by `Migration_Run_Log__c` OrderNumbers or by re-running the filter. |
| `OrderMigrationController` | Controller (AuraEnabled) | LWC API: `startMigration`, `getBatchStatus`, `abortMigration`, `getSoqlPreviewResults`, cleanup (`startCleanup` / `…ByFilter` / `…All`), run-log history (`getRecentRunLogs`, `getHistoryRows`, `backfillRunLogTimes`), and saved filters / pricebook presets CRUD. |
| `OrderMigrationService` | Service | Heavy lifting: SOQL-mode detection + `injectSafetyGuards` (guards raw user SOQL), `executeSoqlPreview`, counts/gap analysis, `resolveDefaults`, `calculateOrderItemFields`, `applyOrderDefaults`/`applyQuoteDefaults`, `resolveOrCreateContract`, `invokeCreateAssetsFromOrder` (REST), `createAssetContractRelationships`, PBE remap (`buildPbeRemapForScope`), and `analyzeCoverage`. |
| `AssetMigrationQueueClearHandler` | Trigger handler | Defense-in-depth on Asset `after insert`: when a migration-created Asset lands, traces Asset → ACR → migration Contract → Activated Order → Quote and clears `In_Rerun_Queue__c` on `Migration_Run_Detail__c`. Bounded SOQL; defensively wrapped so failures log without breaking Asset creation. |

### Integration / REST & generic flow utilities

| Class | Role | Purpose / key methods |
|---|---|---|
| `BSSOrderInfoRestService` | REST endpoint (`global without sharing`) | Keith Irwin, BSS-28212/28998. `@RestResource(/OrderInfo/*)` `@HttpGet` — caller passes `order/{OrderNumber}`, returns discount/billing/hardware info for the order + items as JSON (V4: VAT Number, Item Id + DiscountAmount, nulls not blanks). Consumed by the BSS billing system. |
| `ConvertCSVToStringCollection` | Invocable utility | Flow helper: `csvString.split(',')` → `List<String>`. |
| `ConvertStringCollectionToCSV` | Invocable utility | Flow helper: `String.join(collection, ',')` → CSV string. |
| `ConvertToStringCollection` | Invocable utility | Flow helper: split an arbitrary string on a caller-supplied delimiter → `List<String>`. |

### Test classes

Standard `@IsTest` units, one per production class above. All present and named `<Class>Test`:
`AssetContractLinkerActionTest`, `AssetContractQueryHelperTest`, `AssetMigrationQueueClearHandlerTest`, `BSSOrderInfoRestServiceTest`, `ConvertCSVToStringCollectionTest`, `MaintenanceOrderDecompositionServiceTest`, `OrderCascadeDeleterTest`, `OrderMigrationBatchTest`, `OrderMigrationControllerTest`, `OrderMigrationServiceTest`, `OrderRepriceInvocableTest`, `OrderSubmissionValidatorTest`, `OrderValidationTriggerHandlerTest`, `PopulateAssetLegacyFieldsActionTest`, `PowerOrderSplittingServiceTest`, `QuoteCloneServiceTest`, `QuoteCurrencyChangeServiceTest`, `QuoteCurrencyChangeService_FixedTest`, `QuoteLineGroupTriggerHandlerTest`, `QuoteLineItemTriggerHandlerTest`, `QuoteMigrationBatchTest`, `QuoteMigrationControllerTest`, `QuoteMigrationServiceTest`, `QuoteRenewalTypeHandlerTest`, `QuoteRepricingControllerTest`, `QuoteSyncingTriggerHandlerTest`, `QuoteToOrderFieldMapperTest`, `RenewalQuoteLineCleanupQueueableTest`, `RenewalQuoteLineHandlerTest`.

> `OrderRepriceInvocableTest` is explicitly thin: `commerceorders.PlaceOrderExecutor` can't fully run in a unit-test context, so the test only exercises the try/catch + result shape. The real behavior is validated by an Anonymous Apex script in `Data/sc3308/` against live order 00095321.
>
> No matching test class is listed for `OrderMigrationCleanupBatch` or `QuoteSyncQueueable` in the inventory (coverage likely comes from the controller/service tests).

---

## Patterns & gotchas

- **Q2O is a Flow pipeline of invocables; sequence is load-bearing.** The order is roughly: `createOrderFromQuote` → `QuoteToOrderFieldMapper` → `PowerOrderSplittingService` → `OrderRepriceInvocable` → `Activate_Order` → `createOrUpdateAssetFromOrder` → `PopulateAssetLegacyFieldsAction` → `AssetContractLinkerAction`. Reprice must precede activation (SC-3308) or activation fails `INVALID_INPUT` (CompletedWithoutPricing).
- **RLM blocks direct Quote/Order DML at the platform tier.** Pricing must go through `PlaceOrderExecutor` (RCA), and Opportunity `SyncedQuoteId` can't be set in the same transaction as Quote DML — hence `QuoteSyncQueueable` and the queueable-deferred renewal cleanup.
- **Migration deliberately bypasses headless pricing/AUA.** `OrderMigrationBatch` pre-sets pricing and activates without AppUsageAssignment to dodge `CalculationStatus` gates; `OrderValidationTriggerHandler.bypassValidation` is the matching escape hatch for missing checklist items. These bypasses are intentional and should not be "fixed."
- **`without sharing` is used on purpose** in `AssetContractQueryHelper`, `OrderRepriceInvocable`, and `PopulateAssetLegacyFieldsAction` — RCA junction objects (ACR, AssetActionSource) and the pricing engine don't behave under sharing/dynamic-SOQL traversal in trigger context.
- **Duplicated/superseded classes:** `QuoteCurrencyChangeService` is superseded by `QuoteCurrencyChangeService_Fixed` (use `_Fixed`). The Quote and Order migration trios are near-mirror copies of each other.
- **`PowerOrderSplittingService` sets `Original_Order_Item__c` on qty-split parents** — this is the field downstream Workday line-type logic (`Fortra_OrderItem_Set_Workday_Contract_Line_Type`) reverse-looks-up, which is why pure quantity splits get mis-stamped as BILLING ONLY (SC-3210). Cross-reference before touching either.
- **Governor-limit history:** `OrderSubmissionValidator` exists specifically to replace a per-field-per-line SOQL pattern that hit `Too many SOQL queries:101` (SC-3366). Keep validation metadata-driven; do not reintroduce per-field SOQL.
- **Renewal carryover deletes must be deferred** (`RenewalQuoteLineCleanupQueueable`) — deleting carryover lines synchronously in `after insert` breaks TLE Configure + Save, and deleting before the Year-2 config rule runs strips the platform asset copy.
- **`MaintenanceOrderDecompositionService` is the renewal carry-forward backbone** (FORTRA-PRODUCT-018 / COLA SC-3350): it stamps real maintenance dollars onto OrderItem at Q2O so renewal pricing has dollars to carry. Both `OrderRepriceInvocable` and `QuoteToOrderFieldMapper` depend on it.
