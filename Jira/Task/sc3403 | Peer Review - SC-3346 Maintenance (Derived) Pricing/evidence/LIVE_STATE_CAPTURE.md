# Maintenance (Derived) Pricing — LIVE UAT State Capture
Captured 2026-06-11 (FortraUAT = liam.jeong.c@fortra.com.uat, default org). All facts below are from live org queries, not from screenshots/docs.

## Ticket identity
- Title: **Maintenance (Derived) Pricing** ("Auto-Add First Year Maintenance and Additional Year Renewal Pricing")
- Parent: **SC-1457** Revenue Cloud: Quote to Order. Reporter: Marc Debrey. Assignee/owner: **Nir Kailash**. Sprint 14. Component: SF RCA. Priority: Blocker.
- No SC number visible on the ticket card in provided screenshots; no dossier folder existed before this review.
- SDD: `*Jira Related Data/sc3347/docs_txt/Fortra-Maintenance-Derived-Pricing-Solution-Design.txt` (v1.0, 2026-06-06, Coastal).

## Apex classes — existence + last-modified (Tooling API)
| Class | LengthNoComments | LastModified (UTC) | In force-app? |
|---|---|---|---|
| MaintenanceOrderDecompositionService (+Test) | 13844 / 34162 | 2026-06-09 23:14 | NO |
| OrderRepriceInvocable (+Test) | 5170 / 4607 | 2026-06-09 23:23 | NO |
| QuoteRenewalTypeHandler (+Test) | 730 / 2232 | 2026-06-10 00:05 | NO |
| QuoteToOrderFieldMapper (+Test) | 8976 / 13376 | 2026-06-10 01:16 | **YES** (only one) |
| **PartnerNetPricePosthook (+Test)** | 34818 / 22705 | **2026-06-11 21:25 / 21:23** (TODAY) | NO |
| **RenewalQuoteLineHandler (+Test)** | 6284 / 10526 | **2026-06-11 19:47 / 19:42** (TODAY) | NO |
| RenewalQuoteHeaderHandler (+Test) [undocumented] | 9930 / 9594 | **2026-06-11 18:31** (TODAY) | NO |
| RenewalAssetQuantityHandler (+Test) [undocumented] | 5807 / 9310 | **2026-06-11 21:09** (TODAY) | NO |
| COLAUpliftPrehook [shared w/ SC-3350] | 43272 | **2026-06-11 14:13** (TODAY) | NO |
| COLAUpliftHandler [shared w/ SC-3350] | 13066 | 2026-06-10 16:29 | (live-only per SC-3350) |
| QuoteLineItemTriggerHandler | 1905 | 2026-04-16 | (pre-existing) |

**Five maintenance/renewal/partner classes were modified TODAY (2026-06-11), several within hours of this review** — the build is actively churning, NOT frozen for release. Nir's June-10 "Quick Update" component list is already stale and INCOMPLETE (omits RenewalQuoteHeaderHandler, RenewalAssetQuantityHandler, COLAUpliftHandler/Prehook which the triggers call).

## Triggers (both ACTIVE)
- `QuoteTrigger` (Quote, before ins/upd): calls `QuoteRenewalTypeHandler.applyRenewalQuoteType` + `RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders`.
- `QuoteLineItemTrigger` (QLI, before ins/upd + after ins): after-insert → `RenewalAssetQuantityHandler.enqueueQuantityNormalization` + `RenewalQuoteLineHandler.enqueueCarryoverCleanup`; before → `QuoteLineItemTriggerHandler.handleHardwareLinking`, `COLAUpliftHandler.handleBeforeInsert/Update`.
- Renewal handling is split across **Queueable (enqueue...) async handlers** — relevant to Nir's blocker "renewing both assets at once fails."

## STALE coverage aggregate (ApexCodeCoverageAggregate — invalidated by today's edits)
| Class | Covered | Uncovered | % | Note |
|---|---|---|---|---|
| MaintenanceOrderDecompositionService | 34 | 199 | 14.6% | |
| RenewalQuoteLineHandler | 0 | 101 | 0% | modified today → stale |
| QuoteRenewalTypeHandler | 7 | 3 | 70% | |
| PartnerNetPricePosthook | 0 | 504 | 0% | modified today → stale |
| OrderRepriceInvocable | 0 | 74 | 0% | |
| QuoteToOrderFieldMapper | 91 | 28 | 76.5% | |
| QuoteTrigger | 0 | 3 | 0% | trigger w/ 0% = HARD prod blocker |
| QuoteLineItemTrigger | 0 | 12 | 0% | trigger w/ 0% = HARD prod blocker |
| RenewalQuoteHeaderHandler | 0 | 130 | 0% | |
| RenewalAssetQuantityHandler | 0 | 95 | 0% | |
| COLAUpliftPrehook | 0 | 575 | 0% | modified today → stale |
| COLAUpliftHandler | 169 | 14 | 92% | |
NOTE: the aggregate shows 0% for any class modified after the last test run; TRUE coverage requires a fresh test run (in progress). See TESTRUN_RESULT.md.

## Custom fields (all EXIST + DataType)
QuoteLineItem: Source_List_Price__c Currency(16,2); Base_Price__c **Number(16,2)**; Prior_Partner_Discount__c Currency(16,2); Prior_Discretionary_Discount__c Currency(16,2); COLA_Uplift_Percent__c **Number(3,2) → max 9.99**; COLA_Solution_Category__c Text(100). (Source_Base_Price__c NOT created — design "or reuse Base_Price__c" → reused Base_Price__c.)
OrderItem: Source_List_Price__c Currency(16,2); Base_Price__c Number(16,2); Prior_Partner_Discount__c Currency(16,2); Prior_Discretionary_Discount__c Currency(16,2).
- FLAG: COLA_Uplift_Percent__c Number(3,2) caps at 9.99 (cannot store ≥10% COLA). Base_Price__c is Number not Currency (currency-blind — cf. SC-3384 multi-currency).

## Flows (active versions)
- `Stamp_Maintenance_Pricing_Inputs` — ACTIVE v11 (the new unified stamp flow, 796 lines).
- `Stamp_Source_List_Price` — ACTIVE v8 (the OLDER new-business-only stamp flow, 358 lines). **BOTH active simultaneously** → potential double-stamp / redundancy. Design intended one flow.
- `Fortra_Quote_to_Order_Conversion` — ACTIVE v27.
- `Fortra_Quote_Reprice` — ACTIVE v27 (the ticket screenshot notes "attempted change, reverted in org").

## Pricing / discovery procedures (ACTIVE ExpressionSetVersions)
| ExpressionSet | Active Ver | IsActive |
|---|---|---|
| Rev_Mgmt_Default_Pricing_Procedure | **V13** | true |
| Product_Discovery_Pricing_Procedure | 1 | true |
| Salesforce_Default_Pricing_Discovery_Procedure | 1 | true |
| Salesforce_Default_Pricing_Discovery_Procedure_v2 | 1 | true |
| Salesforce_Pricing_Discovery_Procedure | 1 | true |
- **Active pricing procedure is now V13** (SC-3393 bump; prior memory "active=V12" is STALE).
## Data dependencies (independently verified live)
- **Selling-model backfill (Step 8) IS loaded** for the validated source: `PIA-PIA-NRPS-PIAP` has BOTH `One Time` (OneTime) and `Term Based - Annual` (TermDefined) ProductSellingModelOptions. Org has 4,943 TermDefined PSMOs.
- **Decision tables exist**: `Derived Pricing Entries` + `Asset Action Source Entries V2` (both CalculationMatrix / DecisionTable). Manual refresh after data changes is required (Test #1).
- **Year-2 config rule exists**: 14OWC0000022Eyb2AE = "Year 2 Maintenance Sku added to Powertech Identity_Access Manager Perpetual" (ProductConfigurationRule — no standard migration path → prod-deploy risk).

## Production gap (FortraProd = liam.jeong.c@fortra.com, queried live)
- QLI fields present in PROD: only **Base_Price__c, COLA_Uplift_Percent__c**. MISSING in prod: **Source_List_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c** (3 of 5).
- New Apex classes present in PROD: **ZERO** (MaintenanceOrderDecompositionService, RenewalQuoteLineHandler, PartnerNetPricePosthook, OrderRepriceInvocable all absent; only QuoteToOrderFieldMapper exists but is the OLD version).

## FRESH TEST RUN (2026-06-11, run 707WC00002y0PNw) — see logs/testrun.txt
- 76 tests, **4 FAILED (95% pass)**, **Org-Wide Coverage 43%**.
- FAILURES: (1) `PartnerNetPricePosthookTest.buildRenewalMaintenanceColaUpdate_correctsStaleLastTransactionNet` → "Same value: null" (renewal COLA net correction returns NULL — SC-3350 $0-net family); (2) `testBuildNetPriceUpdate_usesProductTypeFromBulkMapWhenContextBlank` → Expected 12 (New Maint) Actual 15 (Software) — partner rate picks WRONG tier; (3) `enrichPartnerDataFromSourceQuote_fallsBackToLinkedQuote` → DML "No checklist items found"; (4) `OrderRepriceInvocableTest.reprice_seedsQuotePricingBeforeExecutor` → INVALID_CROSS_REFERENCE_KEY.
- Real per-class coverage: QuoteRenewalTypeHandler 100%, QuoteTrigger 100%, QuoteLineItemTrigger 92%, QuoteToOrderFieldMapper 92%, COLAUpliftHandler 92%, RenewalQuoteLineHandler 90%, OrderRepriceInvocable 85%, MaintenanceOrderDecompositionService 76% | **BELOW 75%: PartnerNetPricePosthook 37%, PartnerPricingService 33%, RenewalAssetQuantityHandler 36%, RenewalQuoteHeaderHandler 15%, RenewalMaintenancePricingService 2%** (RenewalMaintenancePricingService is ANOTHER undocumented class).

- **FOUR discovery procedures are simultaneously active.** Marc DeBrey (2026-06-09): "two pricing discovery procedures activated, and there should only be one … some kind of corruption" — his instinct is literally corroborated (multiple active discovery procedures). Whether this is the cause of the reprice `contextDefinitionName` error or a red herring is for analysis (prior RCA `project_reprice_contextdef_error` attributed the error to an in-place V-edit without re-syncing context `SalesTransactionContextExt_v2`).
