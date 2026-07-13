# LANE 1 — Call Graph + Field Reads/Writes + Guard Analysis

Evidence base: `Data/pricing-refactor-scratch/live-classes/*.cls` (read in full this run, 2026-07-06).
Runtime order per SHARED GROUND TRUTH fact 5 (ProcedurePlanSection.Sequence on `Fortra_Pricing_PreHook`):
seq1 Hardware → seq2 Regional → seq3 Partner(V2) → seq4 AttrVolume → seq6 COLA → seq10 ESD procedure → seq11 PartnerNetPricePosthook → seq12 QLDescription(runs AFTER procedure) → seq13 CancelLineCredit.

Tag convention: `CONFIRMED` = verified in evidence this run. `CORRECTED` = prior claim disproved. `UNVERIFIED` = carried, not checkable read-only.

---

## A) CLASS-LEVEL CALL GRAPH

### Entry method for every RevSignaling hook
All wired hooks implement `RevSignaling.SignalingApexProcessor`; the RCA runtime invokes **`execute(RevSignaling.TransactionRequest request)`** and reads `request.ctxInstanceId`. (grep "implements Rev" confirms 8 wired + 2 dead/disabled.)

### CG-1 — Hardware (seq1) `HardwareAttributePricingPrehook.execute` — CONFIRMED
- `execute` → `processLineItems` (`HardwareAttributePricingPrehook.cls:170`) → `queryConfiguredAttributes`→`parseConfiguredAttributes`, `collectHardwareIds`, `queryHardwareRecords` (SOQL `Hardware__c`, :519), `buildItemUpdates`→`processLineItem`, `submitContextUpdates`.
- **No downstream in-scope class calls.** Self-contained Context-API hook + one `Hardware__c` SOQL.

### CG-2 — Regional (seq2) `RegionalServicesPricingPrehook.execute` — CONFIRMED
- `execute` → `loadRegionalPricingMultipliers` (SOQL `Services_Regional_Pricing__mdt`, :89) → `getShippingCountry`→`parseShippingCountry` → `processLineItems`→`buildItemUpdates`→`buildNodeUpdate`→`calculateAdjustedPrice`, `submitContextUpdates`.
- **No downstream in-scope class calls.** Self-contained + one CMDT SOQL.

### CG-3 — Partner LIVE (seq3) `PartnerPricingPrehookV2.execute` — CONFIRMED / CORRECTED
- `execute` → `queryQuoteHeaderFromContext`, `collectPartnerIds`, `loadPartnerPricingModels`, `getPartnerNames` (SOQL `Account`, :399), `processLineItems`→`processLineItem`.
- **Downstream in-scope: `PartnerPricingServiceV2` ONLY** (`PartnerPricingPrehookV2.cls:384,708,715,720,735,742,760`):
  `getPricingModelCandidates`, `selectBestModelForLine`, `getMarginForProductType`, `calculateDiscountPrice`, `calculateGuaranteedMarginPrice`.
- CORRECTED vs prior docs: the live prehook uses **V2 service** (deal-type aware `Non_Orig_*` fields). The dead V1 twin used the V1 service — see CG-12.

### CG-4 — AttrVolume (seq4) `AttributeVolumePricingPrehook.execute` — CONFIRMED
- `execute` → `processAttributeVolumePricing` → `queryLineItems`, `queryLineItemAttributes`→`groupAttributesByLineItem`, `buildItemNodeUpdates` (bulk SOQL `Attribute_Tier_Pricing_Storage__c`, :211) →`buildTierLookupMap`/`lookupTierFromMap`/`buildNodeUpdate`/`buildResetNodeUpdate`, `submitContextUpdates`.
- **No downstream in-scope class calls.** Self-contained + one bulk CMDT-style SOQL. Two-pass bulk pattern (no SOQL in loop).

### CG-5 — COLA (seq6) `COLAUpliftPrehook.execute` — CONFIRMED
- `execute` → `isOrderTransaction` (scope guard, skips Order), `getCOLARulesMap` (SOQL `COLA_Uplift_Rules__mdt`, :867), `MyCAP_Rules__mdt.getInstance('Global')`, `processLineItems`, `processMyCAPEligibility`.
- `processLineItems` → SOQL `QuoteLineItem WHERE QuoteAction.Type='Renew'` (:243), `getContractOverrides`→`buildOverrideMap` (dynamic SOQL `AssetContractRelationship`, :914), `buildLineItemUpdates`→`buildItemUpdate`/`buildNetUnitPriceUpdate`, `appendStampedRenewalMaintenanceUpdates` (SOQL `QuoteLineItem` Renewal Maint, :600), `submitContextUpdates`.
- `processMyCAPEligibility` → SOQL `AttributeDefinition`/`AttributePicklistValue`/`QuoteLineItemAttribute`/`QuoteLineItem`/`Quote`, then **`System.enqueueJob(new MyCAPFlagApplier(...))`** (inner `Queueable`, :1308) which does bulk `Database.update` on `Quote.Mycap__c`.
- **Downstream in-scope: `COLAUpliftHandler.isManualLineOverride(...)` (static predicate, `COLAUpliftPrehook.cls:382`)** — the single shared override-detection predicate, deliberately reused so prehook and trigger cannot drift.

### CG-6 — Posthook (seq11) `PartnerNetPricePosthook.execute` — CONFIRMED / CORRECTED (2563 lines, largest)
- `execute` → `applyPartnerNetPrices(ctxInstanceId)` (`:136`).
- `applyPartnerNetPrices` fan-out:
  - `queryLineItems`, `queryQuoteHeaderFromContext`→`parseQuoteHeaderApiResponse`→`enrichPartnerDataFromSourceQuote` (SOQL `Order`→`Quote`, :763).
  - **`PartnerPricingService` (V1 service!)** — `getPricingModels`, `ensureProductTypesLoaded`, `loadProductTypesForTransactionLines`, `resolveProductType`, `getMarginForProductType`, `calculateDiscountPrice`, `calculateGuaranteedMarginPrice` (`:146,159,161,319,545,569,574,581,591,1112,1480,1527,1560,2251`).
  - `loadRenewalColaLines`, `loadNewMaintenanceLines` (SOQL QLI/OrderItem + `Maintenance_Rate__mdt` + `PricebookEntryDerivedPrice` + `QuoteLineItemAttribute`/`OrderItemAttribute`), `resolveNewMaintenancePartnerBandByQuote/ByOrder` (more `Quote`/`Order`/PPM SOQL), `resolveContributorCarryForwardByMaintenanceQuoteLines`.
  - `buildNetPriceUpdate` (7-overload chain) → `buildRenewalColaCommitUpdate`, `buildRenewalMaintenanceColaUpdate`, `calculateDeferredPartnerPrice`, `buildDerivedMaintenanceSequentialDiscountUpdate`, `buildNewMaintenanceUpdate`, `adjustNewBusinessDerivedListLineItem`.
  - **`RenewalMaintenancePricingService.resolveColaLineTotal(...)` (static, `:476,1023,1138`)**.
  - `buildSupplementalDerivedMaintenanceUpdates` (SOQL QLI IN :maintIds), `submitContextUpdates`.
  - **`schedulePostPersistPriceStamp(quoteId)`** → `System.enqueueJob(new QuotePriceStampQueueable(quoteId))` OR, if already async, calls static `stampAttributeListPricesForQuote` inline.
- **Static entry points (called from OUTSIDE the RCA hook path):**
  - `applyNetPricesToOrder(Id orderId)` (`:92`) — rebuilds Order context via `ctx.buildContext`, calls instance `applyPartnerNetPrices`, `ctx.persistContext`. **Called by `OrderRepriceInvocable` (CG-9).**
  - `stampAttributeListPricesForQuote(Id quoteId)` (`:2440`) — post-persist DML stamp on QLIs (`update updates`, bulk). **Called by `QuotePriceStampQueueable.execute` (`QuotePriceStampQueueable.cls:13`) and by `schedulePostPersistPriceStamp` inline.**
  - `applyPostPricingNetPrices` (`@InvocableMethod`, :2419) — flow entry, loops requests → instance `applyPartnerNetPrices`.
- CORRECTED: the LIVE posthook depends on **`PartnerPricingService` (V1)**, while the LIVE prehook (CG-3) depends on **`PartnerPricingServiceV2`**. See finding **CG-15 (partner-service split hazard)**.

### CG-7 — QLDescription (seq12, runs AFTER procedure+posthook) `QLDescriptionGeneratorPrehook.execute` — CONFIRMED
- `execute` → `queryLineItemDataPaths`→`parseLineItemDataPaths`, `isQuoteLineSet` (Quote-only scope guard), `queryConfiguredAttributes`→`parseConfiguredAttributes`, `queryProductNames` (SOQL `QuoteLineItem`→`Product2.Name`, :708), `loadConfig`→`queryActiveConfig` (SOQL `QL_Description_Attribute__mdt`)/`buildResolvedConfig`/`defaultConfig`, `buildContextUpdates`→`buildDescription`/`computeUnitTypeSegment`/`resolveUnitQuantity`, `submitContextUpdates` (writes `SalesTrxnItemDescription`→QLI.Description).
- **No downstream in-scope class calls.** DML forbidden here; context-API writeback only.

### CG-8 — CancelLineCredit (seq13) `CancelLineCreditPosthook.execute` — CONFIRMED
- `execute` → `process(contextId)` → `fetchSalesTransactionItems`→`parseLineNodes`, `resolveAssetNetsForUnseededLines`→`collectUnseededCancelLines`/`resolveScope`/`resolveSourceAssetIds` (SOQL QLI/OrderItem→`*Action.SourceAssetId`)/`resolveAssetNetByCurrency` (SOQL `AssetActionSource`)/`applyAssetNetSource`/`resolveSeedNet`, `buildCreditUpdates`→`buildNodeUpdate`, `submitContextUpdates`.
- **No downstream in-scope class calls.** Self-contained; 2 read-only SOQL max (RLM-DML-lock safe).

### CG-9 — OrderReprice edge `OrderRepriceInvocable.reprice` — CONFIRMED (the SC-3308 Q2O reprice path)
- `reprice` (`@InvocableMethod`) loops `repriceOne(req.orderId)` per Request.
- `repriceOne` (`OrderRepriceInvocable.cls:33`) edges:
  1. `MaintenanceOrderDecompositionService.prepareForReprice(orderId)` (→ `loadWork`→`loadWorkBulk`, `seedFromWork`) `:37`.
  2. `MaintenanceOrderDecompositionService.persistFromWork(work)` `:38,77`.
  3. `OrderCommercialNetService.patchOrderItemCommercialUnitPrices(orderId)` `:40`.
  4. `PartnerNetPricePosthook.applyNetPricesToOrder(orderId)` `:50` (→ posthook static, CG-6).
  5. `commerceorders.PlaceOrderExecutor.execute(... PricingPreferenceEnum.Force ...)` — native RCA reprice.
  6. `resolveQuoteTotal`/`resolveOrderTotal`/`totalsMatch`/`clearOrderValidationResult` (DML `update Order`).

### CG-10 — Assetization edge `OrderCommercialNetService` — CONFIRMED
- `finalizeForAssetization` (`@InvocableMethod`) loops inputs → `finalizeOrderForAssetization` → `patchOrderItemCommercialUnitPrices` (SOQL `OrderItem WHERE OrderId=` + `update patches`). **Does NOT call the posthook** (comment `:6-9`: re-running it at activation can gack/stall assetization). No in-scope downstream calls.

### CG-11 — Async stamp `QuotePriceStampQueueable.execute` — CONFIRMED
- `execute` → `PartnerNetPricePosthook.stampAttributeListPricesForQuote(quoteId)` (static). Cyclic with CG-6 `schedulePostPersistPriceStamp` enqueue.

### CG-12 — DEAD twin `PartnerPricingPrehook` (V1, 1646 lines) — CONFIRMED unwired
- Same `execute` shape; calls **`PartnerPricingService` (V1)**: `getPricingModels`, `ensureProductTypesLoaded`, `loadProductTypesForTransactionLines`, `resolveProductType`, `resolveTotalPartnerPercent`, `buildPartnerMarginDetailJson`, `getMarginForProductType` (`PartnerPricingPrehook.cls:390,455,632,693,777,1146,1152`).
- Per ground-truth fact 6, ProcedurePlanOption `1FYWC0000002W3r4AE` points at V2 (`01pWC000002TL37YAG`), so this class is the **dead partner prehook** in runtime. Deletion candidate (verify no test/flow refs first).

### CG-13 — DISABLED no-ops — CONFIRMED
- `SourceListPricePrehook.execute` returns a static "disabled" response (`SourceListPricePrehook.cls:10-15`). `SourceListPriceResolver.resolve` returns skipReason "disabled" (`:18-22`). No callers of `SourceListPriceResolver` anywhere in live-classes (grep empty). Both are inert.

### CG-14 — Standalone (NOT in the wired pricing call graph) — CONFIRMED
Grep shows NO wired-hook caller for these; they are flow/trigger/queueable entry points:
- Currency: `Fortra_CurrencyConversionService`, `CurrencySelectionService`, `QuoteCurrencyChangeService`(+`_Fixed`), `CurrencyCodeExtractor` (`@Invocable`), `DatedConversionRateLookup` (`@Invocable`) — **zero callers among live pricing classes** (grep empty). Flow-only.
- `RenewalMaintenanceFlip` (`@Invocable`), `RenewalMaintenanceAutoAddHandler`, `QuoteMigrationService` — no wired-hook callers.
- `RenewalAssetQuantityHandler.processQuotes` → `System.enqueueJob(new RenewalAssetQuantityQueueable(quoteIds))` → `RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes` (self-cyclic async; `RenewalAssetQuantityQueueable.cls:14`).
- `RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices` (`@Invocable`) is flow-called; only its static `resolveColaLineTotal` is reached from the posthook (CG-6).

---

## KEY CROSS-CLASS FINDINGS

### CG-15 — Partner-service SPLIT: live prehook uses V2, live posthook uses V1 — CONFIRMED (HIGH)
The two live partner surfaces call **different service classes with different margin logic**:
- Prehook `PartnerPricingPrehookV2` → `PartnerPricingServiceV2.getMarginForProductType(model, productType, dealType)` which branches on `dealType == 'Fortra Originated'` to `Non_Orig_*_Pct__c` fields (`PartnerPricingServiceV2.cls:114-155`).
- Posthook `PartnerNetPricePosthook` → `PartnerPricingService.getMarginForProductType(model, productType)` — **NO deal-type arg, NO `Non_Orig_*` support** (`PartnerPricingService.cls:253-278`); also its `getPricingModels` SELECT does not even query the `Non_Orig_*` columns (`:50-61`).
Consequence: for a Fortra-Originated deal whose derived-maintenance/deferred partner line is priced by the **posthook** (deferred path), the partner % uses the ORIGINATED band, not the Non-Orig band the prehook would have used for a normally-priced line. Silent per-line inconsistency on the same quote. This is the single biggest structural drift in the partner subsystem and a prime refactor target (collapse to one service).

### CG-16 — `resolveColaLineTotal` is the shared quote-total contract — CONFIRMED
`RenewalMaintenancePricingService.resolveColaLineTotal(qli, net)` (`:322`) is the single source for "flat net when Quantity<=0 (Platform No-Change), else net*qty". Reused by the posthook 3× (CG-6). Keep static; do not inline.

---

## B) PER-HOOK FIELD READS / WRITES (exact API names, file:line)

Legend: context READS are `queryTags` tag names; context WRITES are `updateContextAttributes` attributeName values that hydrate onto the QLI/OrderItem node. SOQL reads noted separately.

### Hardware (CG-1)
- Context READS: `Hardware_Id__c`, `ProductId`, `ListPrice`, `UnitPrice` (`:555,556,640,641`); attr tags `Pgroup`/`Server_Type`/`Users` via `SalesTransactionItemAttribute` (:43-45).
- SOQL READS `Hardware__c`: `P_Group_List__c, Server_Type__c, Users_Per_Partition__c, Model_Number__c` (`:524-533`).
- Context WRITES (`:699-773`): `UnitPrice`, `Pre_Hardware_Price__c`, `Hardware_Price_Multiplier__c`, `Hardware_Pricing_Applied__c`, `Hardware_Pricing_Source__c`, `pGroup_Applied__c`, `System_Type_Applied__c`, `Users_Per_Partition_Applied__c`, `Hardware_Pricing_Detail__c` (JSON), `HardwareCalculatedPrice__c`, `HardwarePricingExplainer__c`.

### Regional (CG-2)
- Context READS: `ShipToPlace_Country__c`→`ShippingCountry` (`:162,168`); per-line `ListPrice`,`UnitPrice`,`ProductId` (`:241,242,245`).
- SOQL READS CMDT `Services_Regional_Pricing__mdt`: `Country__c, Country_Code__c, Multiplier__c` (`:89`).
- Context WRITES (`:286-328`): `UnitPrice`, **`RegionalNetUnitPrice__c`** (OrderItem-only staging per fact 11), `PrehookRSNetUnitPrice__c`, `RegionalPricingExplainer__c`, `RegionalPricingApplied__c`, `Pre_Regional_Price__c`, `Regional_Multiplier__c`.

### Partner V2 (CG-3)
- Context READS header: `Billing_Partner__c`, `Partner_Pricing_Model__c`, `Deal_Type__c`, `Reseller__c`, `Distributor__c`, `Referral_Partner__c` (`:326-331`). Per-line: **`RegionalNetUnitPrice__c` first, then `UnitPrice`, then `ListPrice`** (`resolveBasePrice`, :653-660,963), `Fortra_Product_Type__c`, `Unit__c`, `Solution_Group__c`, `Solution_Category__c` (`:605-608`).
- SOQL READS `Account.Name` (:399); `Partner_Pricing_Model__c` (all `*_Percent__c`+`Non_Orig_*` via service, `PartnerPricingServiceV2.cls:26-32`).
- Context WRITES (`:784-847`): `Pre_Partner_Price__c`, `Partner_Adjusted_Price__c`, `Partner_Pricing_Model_Applied__c`, `Partner_Pricing_Source__c`, `Partner_Margin_Detail__c` (JSON), `PartnerUnitPrice`, `PartnerDiscountPercent`, and when `totalPercent>0` also `NetUnitPrice`+`UnitPrice` (`:833-842`), `Partner_Pricing_Warning__c`=null.
- `clearPartnerPricingFields` nulls 9 fields on every line when no partner config (`:1095-1104`).

### AttrVolume (CG-4)
- Context READS: `Has_Attribute_Adjustment__c` (eligibility, :182), `Product`, `ProductSellingModel` (:187,188), `ListPrice` (reset, :529), attr `Attribute_Volume`/`Attribute`/`AttributeKeyName`/`AttributeValue`.
- SOQL READS `Attribute_Tier_Pricing_Storage__c`: `Product__c, Product_Selling_Model__c, Attribute_Name__c, Attribute_Value__c, Lower_Bound__c, Upper_Bound__c, Tier_Value__c, Multiplier__c, Price_Mode__c` (`:212-218`).
- Context WRITES (`:468-543`): `Base_Price__c`, `Attribute_Price_Mode__c`, and (Calculated mode only) `Attribute_Multiplier_Pct__c`. Reset path writes `Base_Price__c`=ListPrice + `Attribute_Price_Mode__c`='Unit Price'.

### COLA (CG-5)
- Context READS: `COLA_Uplift_Percent__c`, `PricingTermCount`, `PricingTermUnit`, `ItemSubscriptionTerm`, `SalesTransactionActionType`, `Default_COLA_Uplift_Percent__c`, `UnitPrice`, `COLA_Solution_Category__c`, `IsCOLAOverridden__c` (`:377,404,406,407,1121,1140-1157`).
- SOQL READS: `QuoteLineItem` (QuoteAction.Type='Renew' + SourceAsset.Price/Product2.Solution_Category__c, `:243`; renewal-maint `Base_Price__c,Prior_Partner_Discount__c,Prior_Discretionary_Discount__c,PartnerDiscountPercent,Discount,COLA_Uplift_Percent__c`, `:600`); `AssetContractRelationship`→`Contract.COLA_Override_Percent__c/Persist_Until__c/Status`; CMDT `COLA_Uplift_Rules__mdt`, `MyCAP_Rules__mdt`; `AttributeDefinition`/`AttributePicklistValue`/`QuoteLineItemAttribute` (prepaid).
- Context WRITES (`:767-796,1032-1039,1146-1153,1450-1461`): `COLACalculatedPrice__c`, `Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Applied_Date__c`, `COLA_Solution_Category__c`; isolated batch writes `NetUnitPrice` (SC-3350 seed, `:494`); maint batch also `PartnerDiscountPercent`, `Discount`.
- DML (async): `MyCAPFlagApplier` writes `Quote.Mycap__c` (`:1393`).
- NOTE (silent-write hazard, documented in-code): `COLAUpliftPercent__c`/`COLA_Uplift_Percent__c` and `COLAApplied__c`/`COLAExplainer__c` **cannot** be written here — "poison the entire updateContextAttributes batch" (`:772-775,1446-1447`). `COLA_Uplift_Percent__c` is instead synced by the `COLAUpliftHandler` trigger. This is a load-bearing exclusion — any refactor that re-adds them silently drops the whole batch.

### Posthook (CG-6)
- Context READS per line: `NetUnitPrice`, `PartnerUnitPrice`, `PartnerDiscountPercent`, `Partner_Pricing_Source__c`, `RegionalNetUnitPrice__c`, `UnitPrice`, `ListPrice`, `Quantity`, `Fortra_Product_Type__c`, `Base_Price__c`, `Pre_Partner_Price__c`, `Partner_Discount_Percent__c`, `ItemDiscountPercentage`, `Discount` (`:355-357,380,392,554,614,619-623,2177,2181,2186,2190,2273-2281`); header `Billing_Partner__c`/`Partner_Pricing_Model__c`/`Reseller__c`/`Distributor__c`/`Referral_Partner__c` (`:734-738`).
- SOQL READS: `QuoteLineItem`/`OrderItem` (many), `Quote` (`QuoteTypeText__c`,`Billing_Partner__c`,`Partner_Pricing_Model__c`), `Order`(`Quote.*`), `PricebookEntryDerivedPrice`, `Maintenance_Rate__mdt`, `QuoteLineItemAttribute`/`OrderItemAttribute` (`Maintenance Type Defn`), `Partner_Pricing_Model__c` (via V1 service).
- Context WRITES per update: `NetUnitPrice`, `NetTotalPrice`, `TotalPrice`, `Subtotal`, `TotalLineAmount`, `PartnerUnitPrice`, `UnitPrice`, `InputUnitPrice`, `ListPrice`, `Base_Price__c`, `COLACalculatedPrice__c`, `PartnerDiscountPercent`, `Discount`, `Pre_Partner_Price__c`, `Partner_Adjusted_Price__c`, `Partner_Pricing_Model_Applied__c`, `Partner_Pricing_Source__c` (`:395-425,1031-1052,1146-1167,2127-2164,2382-2399`).
- DML (static `stampAttributeListPricesForQuote`): writes `QuoteLineItem.Source_List_Price__c`, `PartnerUnitPrice`, `Partner_Pricing_Source__c` (`:2500,2512,2518`).

### QLDescription (CG-7)
- Context READS: `SalesTransactionItemAttribute` (all attr name/value), dataPaths. SOQL READS `QuoteLineItem.Product2.Name` (`:708`); CMDT `QL_Description_Attribute__mdt`.
- Context WRITES: **`SalesTrxnItemDescription`** only (→ QLI.Description, `:793`).

### CancelLineCredit (CG-8)
- Context READS: `LineItemQuantity` (`TAG_QUANTITY`, :74), `CancelNetUnitPrice__c` (:77, dual-object staging per fact 11), `STICurrencyIsoCode` (:96), `ListPrice` (:99).
- SOQL READS: `OrderItem.OrderAction.SourceAssetId` / `QuoteLineItem.QuoteAction.SourceAssetId` (:459,469); `AssetActionSource` `NetUnitPrice,CurrencyIsoCode,AssetAction.AssetId/Type` (:502).
- Context WRITES: `NetUnitPrice`, `NetTotalPrice`, `TotalPrice`, `Subtotal`, `TotalLineAmount` (`:305-311`) — QLI FIELD API names (Item* internal tags do NOT persist, documented `:27-36`).

---

## C) GUARD ANALYSIS (§4f)

Static recursion guards + reset behavior (verified `isProcessing = / finally` line-pairs):

| Hook | Guard var | set | finally-reset | Stuck-true risk |
|---|---|---|---|---|
| AttributeVolumePricingPrehook | `isUpdating` | :72 | :78 | **None** — reset in finally; set is first stmt in try |
| COLAUpliftPrehook | `isProcessing` | :51 | :107 | None |
| CancelLineCreditPosthook | `isProcessing` | :127 | :173 | None |
| PartnerPricingPrehook (dead V1) | `isProcessing` | :89 | :208 | None (dead) |
| PartnerPricingPrehookV2 | `isProcessing` | :102 | :192 | None |
| PartnerNetPricePosthook | `isProcessing` | :65 | :82 | None |
| QLDescriptionGeneratorPrehook | `isProcessing` | :288 | :347 | None |

**CG-17 — Guards are structurally SOUND but INCONSISTENT — CONFIRMED.**
- Every guarded hook sets the flag as the FIRST statement inside `try` and resets in `finally`, so a mid-execute exception can never leave it stuck-true (and a static resets between transactions regardless). The §4f "stuck-true silent no-op on re-entry" hazard is **NOT present** in any of the 7 guarded hooks.
- **HOWEVER, CG-1 `HardwareAttributePricingPrehook` and CG-2 `RegionalServicesPricingPrehook` have NO recursion guard at all** (grep "private static Boolean" returns none for either). They rely entirely on the Context API not re-entering. If any of their `updateContextAttributes` writes (both write `UnitPrice`) ever re-triggers the pricing engine, they can recurse unbounded — the opposite failure mode from the guarded hooks. This asymmetry (7 guarded / 2 unguarded, all in the same waterfall) is the real §4f fragility: normalize to one pattern.

---

## D) GOVERNOR / BULKIFICATION

### CG-18 — PowerOrderSplittingService: per-unit fan-out now GUARDED (SC-3447 mitigated) — CONFIRMED
- `splitPowerOrderLines` (`@InvocableMethod`) is fully bulk-safe across all orders in one call: `loadWorkBulk`-style batched SOQL, each phase DMLs once (`:218-341`). **No SOQL/DML in any loop.**
- Per-unit design remains (1 clone OrderItem per unit, slots 1..qty-1) BUT is now capped: `MAX_SYNC_CLONES = 200` (`:28`); Σ(qty-1) > 200 fails fast with a catchable message (`:133-148`) instead of a governor crash. The qualifying SOQL also now excludes seat/site-license lines with no Partition/Hardware (`:389-396`). SC-3447 root cause is addressed in live code — downgrade from P0 to "design-review the per-unit model" (Workday/RLM accept qty=N natively).

### CG-19 — OrderCommercialNetService.finalizeForAssetization — SOQL+DML in invocable loop — CONFIRMED (MEDIUM)
`finalizeForAssetization` (`@InvocableMethod`, :99-108) loops each `FlowInput` → `finalizeOrderForAssetization` → `patchOrderItemCommercialUnitPrices` which does one `OrderItem` SOQL + one `update` **per order** (`:32,54`). One order per flow call is fine; a flow that batches N orders into one invocable call issues N SOQL + N DML. Bulkify by collecting orderIds and one query/update.

### CG-20 — MaintenanceOrderDecompositionService.backfillCarryForwardFieldsBulk — DML in loop — CONFIRMED (MEDIUM)
`loadWorkBulk` is correctly batched, BUT `backfillCarryForwardFieldsBulk` then loops per `orderId` doing `update patches.values()` **inside the loop** (`:724-736`). For N orders that is up to N DML statements (150-statement governor). The `@InvocableMethod` `backfillCarryForwardInvocable` collects orderIds first (good) but hands them to this per-order-DML loop. Accumulate all patches across orders and issue one `update`.

### CG-21 — OrderRepriceInvocable — heavy per-request fan-out — CONFIRMED (MEDIUM)
`reprice` (`@InvocableMethod`) loops `repriceOne` per Request; each `repriceOne` runs the full CG-9 chain (multiple SOQL + DML + a `PlaceOrderExecutor.execute` Force reprice, `:64`). Downstream services are bulk *within* an order but nothing is batched *across* Requests. A flow passing >1 order per invocation multiplies SOQL/DML and PlaceOrder calls — keep this invocable one-order-per-call, or redesign for cross-request batching.

### CG-22 — Invocables that loop per request with SOQL inside — CONFIRMED (LOW, typically 1 request)
- `RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices` (:103) loops requests → each does `queryRenewalMaintenanceCandidates` SOQL + context I/O.
- `PartnerNetPricePosthook.applyPostPricingNetPrices` (:2419) loops requests → each `applyPartnerNetPrices` runs the full CG-6 SOQL set.
Both are governor-safe at the observed 1-request cardinality but are un-bulkified across requests.

No un-bulkified `@InvocableMethod` doing SOQL-in-loop over records was found in the wired hooks themselves (all hooks use two-pass bulk patterns). The governor exposure is concentrated in the Order-side invocables above (CG-19/20/21).

---

## E) SILENT-FAILURE MODES

### CG-23 — AttributeVolume reset-to-list on no-match (SC-3390 family) — CONFIRMED
`buildItemNodeUpdates` Pass-2: on `volume == null` (`:282`) OR no tier match (`tierResult == null`, `:294`) it emits `buildResetNodeUpdate` = writes `Base_Price__c`=ListPrice + mode 'Unit Price' (`:518-548`) and increments `skippedCount` — a **silent reset to list price** with only a `System.debug`. No warning field, no user surface. This is the SC-3390 "stale-context / silent reset" surface: a legitimately-configured line whose volume tag hasn't hydrated yet (2nd-click timing) silently reverts to list. Any refactor must preserve the SC-3390 `IsPriceImpacting=true` PAD fix upstream; the reset here masks the symptom.

### CG-24 — Null-unsafe/guarded Decimal compares (SC-3393 / E-04) — CONFIRMED
- AttrVolume tier range check is null-GUARDED correctly: `lower = Lower_Bound__c != null ? ... : 0` and `upper == null || volume <= upper` (`:418-421`) — safe.
- Posthook comparisons are consistently guarded with `!= null && > 0` before every `<`/`==` (e.g. `resolveCommercialUnitPrice` :481, `shouldSkipProcedureOwnedPartner` :445-467, `adjustNewBusinessDerivedListLineItem` :2062). No unguarded `>0` on a possibly-null line found in the posthook this run — the SC-3393 `RegionalNetReconcileGate` un-null-guarded `>0` lived in the ESD/procedure (out of Lane-1 Apex scope), not these classes. **CORRECTED expectation: the SC-3393 defect is NOT in these Apex bodies; it is a procedure-step guard.** Flag to the ESD lane.

### CG-25 — Swallow-and-continue everywhere (by design, but audit-blind) — CONFIRMED
Every hook's `execute` returns `TransactionStatus.SUCCESS` even on exception (Hardware :176, Regional :70, PartnerV2 :190, AttrVolume :77-82, COLA :104, Posthook :80, QLDescription :344, Cancel :170). `submitContextUpdates` in all hooks swallows "not in updatable state". This is deliberate (never block pricing) but means a partial-failure (e.g. one line's write poisoned by a bad attribute) is invisible except in debug logs. `COLAUpliftPrehook.queryConfiguredAttributes`, `getShippingCountry`, `queryLineItemAttributes` all swallow to empty and degrade to list/default pricing. Recommend a structured warning surface (a `*_Warning__c` field is already written by PartnerV2 but nulled; unused elsewhere) so silent degrade is observable.

### CG-26 — COLA batch-poison exclusions are load-bearing — CONFIRMED
As noted in §B COLA: writing `COLA_Uplift_Percent__c`/`COLAUpliftPercent__c`, `COLAApplied__c`, or `COLAExplainer__c` into an `updateContextAttributes` batch silently drops the ENTIRE batch (documented `:762-775,1446-1447`). The SC-3350 `NetUnitPrice` seed is deliberately isolated into its own batch (`pendingNetUnitPriceUpdates`, :287-290) for the same reason. These are fragile, hydration-mapping-dependent invariants — a refactor that merges batches or adds an unmapped attribute reintroduces a whole-batch silent no-op.

---

## SUMMARY OF NUMBERED FINDINGS
- CG-1..CG-8: entry method + downstream edges per wired hook/posthook.
- CG-9: OrderReprice → Decomposition + CommercialNet + Posthook.applyNetPricesToOrder + PlaceOrderExecutor.
- CG-10/11: Assetization service (no posthook call) / QuotePriceStampQueueable → posthook static.
- CG-12/13/14: dead V1 prehook (V1 service), disabled SourceListPrice*, standalone currency/renewal classes (not wired).
- **CG-15 (HIGH): partner-service split — live prehook=V2(deal-type aware), live posthook=V1(no Non_Orig) → per-line inconsistency on Fortra-Originated deferred lines.**
- CG-16: resolveColaLineTotal shared contract.
- **CG-17 (HIGH): Hardware + Regional prehooks have NO recursion guard while 7 peers do — inverse §4f fragility.**
- CG-18: PowerSplit SC-3447 mitigated (MAX_SYNC_CLONES=200, bulk).
- CG-19/20/21 (MEDIUM): SOQL/DML-in-loop in OrderCommercialNet invocable, Decomposition backfill bulk, OrderReprice per-request fan-out.
- CG-22 (LOW): renewal-maint + post-pricing invocables un-bulkified across requests.
- CG-23 (SC-3390): AttrVolume silent reset-to-list on volume-null/no-tier.
- CG-24 (CORRECTED): SC-3393 null-`>0` defect is in the ESD procedure, NOT these Apex bodies.
- CG-25/26: pervasive swallow-to-SUCCESS + load-bearing COLA batch-poison exclusions.
