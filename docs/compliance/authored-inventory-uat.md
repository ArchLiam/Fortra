# Apex & Flow Created by Me — FortraUAT

Authoritative "created by me" inventory, sourced from the FortraUAT **Tooling API** by `CreatedById`.

- **Org:** FortraUAT (`liam.jeong.c@fortra.com.uat`)
- **User:** Liam Jeong — `005WC00000MgTN2YAN`

## Summary

| Type | Count | Notes |
|---|---|---|
| Apex classes | **80** | 41 implementation + 39 test; all 80 present in the repo |
| Apex triggers | **1** | `AssetArrFromOrderItemTrigger` (Asset) |
| Flows | **15 distinct** | 27 versions total — 6 active (mine), 19 obsolete, 2 draft |

> **Scope note.** Git attributes 521 classes to author "DevLiam," but only **80** carry your org `CreatedById`. The remaining repo classes were created in the org under other accounts (deploy/service users, other consultants) and committed to git under DevLiam. For "created by me," this 80 / 1 / 15 set is the accurate scope — it is the pricing / maintenance / partner / currency refactor domain.

## Apex classes — implementation (41)

AbaCurrencyCorrectionService, AmendNetCarryPrehook, AppException, AssetArrFromOrderItemHandler, AttributeVolumeCalculator, COLAUpliftCalculator, CancelLineCreditCalculator, CancelLineCreditPosthook, ContextTagReader, ContextUpdateNavigator, ContributorPricingCalculator, DerivedMaintenanceClassifier, DerivedMaintenancePayloadBuilder, DocuSignEnvelopeService, ExceptionLogger, FortraDemoDataFactory, HardwarePricingCalculator, ListPriceStampCalculator, NewBusinessMaintenanceNets, NewMaintenanceBandCalculator, NewMaintenanceInputResolver, NewMaintenanceNetCalculator, OrderRepriceInvocable, OrderSubmissionValidator, PartnerMarginDispatcher, PartnerNetResolutionCalculator, PartnerParticipationResolver, PartnerPricingGate, PartnerPricingPayloadBuilder, PricingException, PricingHookLogger, PsmoOrphanScanner, QLDescriptionCalculator, QuoteLineItemCurrencyCorrectionHandler, RegionalPricingCalculator, RenewalColaPayloadBuilder, RenewalMaintenanceColaCalculator, RenewalMaintenanceFlip, RenewalMaintenanceProvisioner, RenewalQuoteActionStamp, SequentialDiscountCalculator

## Apex classes — test (39)

AbaCurrencyCorrectionServiceTest, AmendNetCarryPrehookTest, AssetArrFromOrderItemHandlerTest, AttributeVolumeCalculatorTest, COLAUpliftCalculatorTest, COLAUpliftPrehookCovTest, CancelLineCreditCalculatorTest, CancelLineCreditPosthookTest, ContextTagReaderTest, ContextUpdateNavigatorTest, ContributorPricingCalculatorTest, DerivedMaintenanceClassifierTest, DerivedMaintenancePayloadBuilderTest, DocuSignEnvelopeServiceTest, ExceptionLoggerTest, HardwarePricingCalculatorTest, ListPriceStampCalculatorTest, NewMaintenanceBandCalculatorTest, NewMaintenanceInputResolverTest, NewMaintenanceNetCalculatorTest, OrderRepriceInvocableTest, OrderSubmissionValidatorTest, PartnerMarginDispatcherTest, PartnerNetPriceCurrencyCorrectionTest, PartnerNetResolutionCalculatorTest, PartnerParticipationResolverTest, PartnerPricingGateTest, PartnerPricingPayloadBuilderTest, PricingCharacterizationTest, PricingHookLoggerTest, QLDescriptionCalculatorTest, QuoteLineItemCurrencyCorrectionTest, RegionalPricingCalculatorTest, RenewalColaPayloadBuilderTest, RenewalMaintenanceColaCalculatorTest, RenewalMaintenanceFlipTest, RenewalMaintenanceProvisionerTest, RenewalQuoteActionStampTest, SequentialDiscountCalculatorTest

## Apex triggers (1)

- `AssetArrFromOrderItemTrigger` — on Asset (v62, Active)

## Flows (15 distinct)

Active version created by me:

| Flow | Type | Active version |
|---|---|---|
| Fortra Quote Reprice | AutoLaunched | ACTIVE v29 (api 62) |
| Fortra Quote Required Fields Check | Screen | ACTIVE v1 (api 62) |
| Fortra \| Exception Log Purge | AutoLaunched | ACTIVE v1 (api 64) |
| Fortra \| OrderItem \| Set Dates | AutoLaunched | ACTIVE v6 (api 67) |
| Fortra \| Pricing \| Exception Logger | AutoLaunched | ACTIVE v1 (api 64) |
| Fortra \| Screen Flow - Inquiry Conversion | Screen | ACTIVE v15 (api 65) |

Authored by me but current active version is superseded/obsolete (active version now owned by another account, or my version is obsolete):

| Flow | Type |
|---|---|
| Fortra - Assetize Order | AutoLaunched |
| Fortra Order Reprice | AutoLaunched |
| Fortra Quote to Order Conversion | Screen |
| Fortra \| Create Renewal Quote | AutoLaunched |
| Fortra \| Order \| Submission Check | Screen |
| Fortra \| OrderItem \| Set Workday Contract Line Type | AutoLaunched |
| Fortra \| Stamp Sales Price | AutoLaunched |
| (Deprecated) Fortra \| Asset \| After Insert/Update - Copy ARR From OrderItem | AutoLaunched |
| (Deprecated) Fortra \| Autolaunched \| Set Workday Contract Line Type | AutoLaunched |
