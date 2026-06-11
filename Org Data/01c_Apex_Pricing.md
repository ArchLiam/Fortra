# Apex — Pricing

## Overview

This domain holds the custom Apex behind Fortra's Revenue Cloud (RCA) pricing waterfall. It splits into two families: **`RevSignaling.SignalingApexProcessor` hooks** (pre/post-hooks invoked by the pricing procedure `Rev_Mgmt_Default_Pricing_Procedure` / context `SalesTransactionContextExt_v2`) that read and write pricing context tags during a Reprice, and **service / batch / invocable utilities** that feed the catalog (multi-currency PricebookEntries, attribute loading, exchange-rate lookups). Sub-domains covered: COLA renewal uplift, currency/exchange conversion, attribute & hardware volume pricing, regional services pricing, partner net pricing, derived-maintenance source-list pricing, and PricebookEntry maintenance tooling.

Most hooks are **load-bearing and order-sensitive** in the waterfall — sequence matters (e.g. PartnerNetPrice must run *after* the procedure recomputes NetUnitPrice). Several are versioned aggressively (v3, v9, v13.3) and have live counterparts in UAT that drift from this source. Authors are predominantly Marc DeBrey / Coastal Cloud.

---

### COLA (Cost of Living Adjustment) — Renewal Uplift

Applies COLA % to renewal quote lines via a three-tier hierarchy: **Line Override > Contract Override > CMDT default** (`COLA_Uplift_Rules__mdt`, keyed by Solution Category). This is the SC-3350 problem area — see project memory before changing.

| Class | Role | Purpose / key methods |
|---|---|---|
| `COLAUpliftHandler` | Trigger handler (QuoteLineItem) | Legacy/trigger path. `handleBeforeInsert` / `handleBeforeUpdate` apply COLA to `Renew`-type `QuoteAction` lines (queries `SourceAsset.Price`, `Solution_Category__c`). `isManualLineOverride(...)` decides whether a pct is a user override vs a default. |
| `COLAUpliftPrehook` | Prehook (`SignalingApexProcessor`) | **Revenue Cloud replacement** for the handler. `execute()` writes `COLACalculatedPrice__c`, `COLAUpliftPercent__c`, `COLAExplainer__c`, `COLAApplied__c` to context for waterfall visibility. Has recursion guard `isProcessing` and an inner Queueable. |
| `COLAUpliftTest` | Test | Covers `COLAUpliftHandler` three-tier hierarchy; seeds LegalEntity because the before-save flow copies it onto QLIs (insert fails without it). |

### Currency & Exchange Rate

| Class | Role | Purpose / key methods |
|---|---|---|
| `Fortra_CurrencyConversionService` | Service | Core multi-currency engine. `getActiveFormulas()` (cached `Currency_Conversion_Formula__mdt` by ISO), `convertPrice` / `applyFormula` (parses `"* 0.92"`-style formulas), `convertToAllCurrencies`, `getActiveCurrencyCodes`, `convertPriceWithDetails`. Used by the bulk price batch and currency flows. |
| `CurrencyConversionService` *(inner of above)* | — | See `Fortra_CurrencyConversionService`. |
| `CurrencyCodeExtractor` | Invocable | `@InvocableMethod extractCode` parses an ISO code from display strings like `"AUD - Australian Dollar"` / `"EUR European Euro"` / plain `USD`. |
| `CurrencySelectionService` | Service | `determineCurrencyForUser/CurrentUser` (priority: User default → hard-coded country→currency map → USD); `canChangeCurrencyOnOrder(status)`. |
| `DatedConversionRateLookup` | Invocable (category `Pricing`) | `getExchangeRates` queries `DatedConversionRate` (ACM) → USD with `CurrencyType` fallback; USD/blank/null return 1.0. Called from `QuoteLineItemExchangeRateTrigger` to stamp `Exchange_Rate_To_USD__c`. Bulkified with a single max-date SOQL. |
| `CurrencyCodeExtractorTest` / `DatedConversionRateLookupTest` | Test | Unit tests for the two invocables (format parsing; USD=1.0 short-circuits). |

### Attribute & Volume Pricing

| Class | Role | Purpose / key methods |
|---|---|---|
| `AttributeVolumePricingPrehook` (v3.0) | Prehook (`SignalingApexProcessor`) | Attribute + volume tier pricing. Bulk two-pass match of line attributes against `Attribute_Tier_Pricing_Storage__c` by composite key `ProductId\|PSMId\|AttrName\|AttrValue` + volume range. Three price modes — Unit Price → `InputUnitPrice`, Calculated (`Base_Price__c × Attribute_Multiplier_Pct__c`) → `ItemNetTotalPrice`, Total Price → `ItemNetTotalPrice`. Filters by `Has_Attribute_Adjustment__c`; recursion guard `isUpdating`. |
| `HardwareAttributePricingPrehook` (v3.0) | Prehook (`SignalingApexProcessor`) | Power/hardware pricing: `Hardware_Price = ListPrice × pGroup_Mult × UserCount_Mult × (1 − SystemType_Discount)`. Override priority: QLIA (configurator) > `Hardware__c` defaults > system defaults (P20/Production/1). Writes `UnitPrice`, `Pre_Hardware_Price__c`, `Hardware_Price_Multiplier__c`, `*_Applied__c` audit fields. Key lookups `getPGroupMultiplier`, `getUserTierMultiplier`, `getSystemTypeDiscount`. Runs after List Price, before Regional/Partner. |
| `AttributeVolumePricingPrehookTest` / `HardwareAttributePricingPrehookTest` | Test | Verify tier-map/composite-key matching and multiplier math. `execute()` not fully unit-testable (managed `RevSignaling.TransactionRequest` has no public ctor) — integration-tested in-org. |

### Attribute Data Loading (QLIA migration)

| Class | Role | Purpose / key methods |
|---|---|---|
| `AttributeLoadingService` | Service | CSV → `QuoteLineItemAttribute` loader. `buildAttributeMap` (Legacy_Id→attr name/value), `extractAttributeNames`, `buildAttrDefMap`, `buildPicklistValueMap`, `previewLoad` (LWC preview wrapper). Resolves `AttributeDefinitionId` + `AttributePicklistValueId`. |
| `AttributeLoadingBatch` | Batch (`Stateful`) | Idempotent creation of QLIA from the service's parsed map; skips existing rows, stateful counters, email summary. Driven by `Legacy_Id__c`. |
| `AttributeLoadingServiceTest` / `AttributeLoadingBatchTest` | Test | QLIA is a Revenue Cloud "internal sObject" needing `Database.insertImmediate()` — does not persist in test context, so tests assert execution/resolution/audit, not row counts (E2E verified manually). |

### Regional Services Pricing

| Class | Role | Purpose / key methods |
|---|---|---|
| `RegionalServicesPricingPrehook` (v13.3) | Prehook (`SignalingApexProcessor`) | Applies country multipliers from `Services_Regional_Pricing__mdt` to LIST channel. `loadRegionalPricingMultipliers`, `getMultiplierForCountry`, `calculateAdjustedPrice`. Writes adjusted `UnitPrice` + `RegionalNetUnitPrice__c` audit field. **Independent hook** (no cross-hook deps). NET stays catalog → structural `TotalLineAmount ≠ NetTotalPrice` (see Italy 0.64 regional-pricing memory). |
| `RegionalServicesPricingPrehookTest` | Test | Exercises multiplier logic + `@TestVisible` seams (`buildItemUpdates`, `buildNodeUpdate`, `submitContextUpdates`, `parseShippingCountry`). |

### Partner Net Pricing

| Class | Role | Purpose / key methods |
|---|---|---|
| `PartnerNetPricePosthook` (v1.1) | **Posthook** (`SignalingApexProcessor`) | Runs at sequence 10 (**after** the pricing procedure) to apply `PartnerUnitPrice` → `NetUnitPrice`/`NetTotalPrice`/`TotalPrice`/`Subtotal`/`TotalLineAmount`, because V9 recomputes NetUnitPrice from ListPrice for OneTime lines at seq 9 and would overwrite a prehook. Handles derived-maintenance lines (price 0 until the procedure). `buildNetPriceUpdate`, `applyNetPricesToOrder(orderId)`. Models: Guaranteed Margin / Discount. Context `SalesTransactionContextExt_v2`. |
| `PartnerNetPricePosthookTest` | Test | Asserts `buildNetPriceUpdate` propagates partner price into all net/total fields and skips when net already matches. |

### Source List Price (Derived Maintenance) — DISABLED

| Class | Role | Purpose / key methods |
|---|---|---|
| `SourceListPricePrehook` | Prehook (`SignalingApexProcessor`) — **DISABLED** | Body commented out; `execute()` returns SUCCESS no-op. Maintenance `Source_List_Price__c` is instead handled by the `Stamp_Source_List_Price` flow + context definition. Do not deploy enabled logic without re-enabling intent. |
| `SourceListPriceResolver` | Service — **DISABLED** | `resolve(maintenancePbeId, pricebook2Id, currencyIsoCode)` short-circuits with `skipReason='disabled'`. Intended to resolve source-license list price for derived maintenance PBEs via `PriceBookEntryDerivedPrice`. |
| `SourceListPricePrehookTest` / `SourceListPriceResolverTest` | Test | Prehook test body fully commented out (disabled). Resolver test still seeds license+maintenance PBE + `PriceBookEntryDerivedPrice` and exercises `resolve` (returns skip). |

### Bulk Price / PricebookEntry Tooling

| Class | Role | Purpose / key methods |
|---|---|---|
| `Fortra_BulkPriceUpdateBatch` (Stateful) | Batch | Bulk multi-currency PBE create/update by Solution Category. Finds USD price in Standard PB, converts via `Fortra_CurrencyConversionService`, writes PBEs across pricebooks × currencies × selling models. PBE key = Product + Pricebook + Currency + SellingModel; Standard PBEs committed before Custom (separate DML). Batch size 50; email summary in `finish()`. |
| `Fortra_BulkPriceUpdateInvocable` | Invocable | Screen-Flow → batch bridge (`Fortra_Bulk_Price_Update_Flow`). Validates categories, counts products, starts batch (default size 50), returns job id + count. |
| `UpdatePricebookEntriesInvocable` | Invocable | Flow helper (`Fortra_Product_Update_Currency_Prices_SubFlow`) to update existing PBEs with parallel currency/price lists; **auto-creates Standard PBE** when missing so Custom PBEs can be created. Works around Flow's inputReference + inputAssignments limitation. |
| `PricebookEntryCascadeDeleter` | Invocable | `cascadeDelete` deletes a PBE and all dependents (OpportunityLineItem, AssetActionSource, AssetAction, Asset + children) inside a savepoint; returns success/message/assetsDeleted. Destructive cleanup tool. |
| `Fortra_BulkPriceUpdateBatchTest` | Test | Covers the batch, invocable, and `Fortra_CurrencyConversionService` (formula parse + PBE create/update + email). |

---

## Patterns & gotchas

- **SignalingApexProcessor hooks are the spine.** `COLAUpliftPrehook`, `AttributeVolumePricingPrehook`, `HardwareAttributePricingPrehook`, `RegionalServicesPricingPrehook`, `PartnerNetPricePosthook`, `SourceListPricePrehook` all implement `RevSignaling.SignalingApexProcessor.execute(...)` and are wired into the pricing procedure. They mutate **context tags**, not sObjects directly.
- **Waterfall order is load-bearing.** Hardware runs after List Price / before Regional+Partner; **PartnerNetPrice is a POST-hook (seq 10)** specifically so V9's seq-9 NetUnitPrice recompute can't clobber it. Resequencing silently regresses net pricing.
- **Recursion guards everywhere.** Static `isProcessing` / `isUpdating` flags short-circuit re-entrant pricing calls — keep them.
- **`execute()` is not unit-testable.** `RevSignaling.TransactionRequest`/`TransactionResponse` are managed with no public constructor, so tests target `@TestVisible` seams and helper math; full validation is in-org integration (Reprice). Expect lower coverage on `execute()`.
- **QLIA is an "internal sObject"** — requires `Database.insertImmediate()` and does not persist in Apex test context; attribute-load tests can't assert QLIA counts.
- **DISABLED but present:** `SourceListPrice*` classes are intentionally inert no-ops (flow + context definition own that logic). Don't assume they run.
- **Currency conversion is formula-string driven** (`Currency_Conversion_Formula__mdt`, e.g. `"* 0.92"`), CMDT-cached per transaction; country→currency fallback in `CurrencySelectionService` is a **hard-coded map** (EU-centric) — new countries need code edits.
- **COLA is the active SC-3350 hot spot.** Both the trigger `COLAUpliftHandler` and the `COLAUpliftPrehook` exist; live UAT versions drift from this source — consult the COLA renewal-pricing memory/README before editing.
- **Versioned source drifts from UAT.** Hooks carry version tags (v3.0, v9, v13.3) and live ACTIVE org versions frequently differ from `_src`. Re-retrieve from FortraUAT before scoping any change.
- **`PricebookEntryCascadeDeleter` is destructive** (deletes Assets and their action history) — invocable, savepoint-wrapped, but no soft-undo beyond rollback-on-exception.
