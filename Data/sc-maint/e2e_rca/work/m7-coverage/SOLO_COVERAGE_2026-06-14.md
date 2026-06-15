# M7-COVERAGE re-test — SOLO per-class coverage (2026-06-14, live FortraUAT)

Active procedure: Rev_Mgmt_Default_Pricing_Procedure V14 (ExpressionSetDefinitionVersion 9QBWC0000000nIT4AY = VersionNumber 14, Status Active).

Each test run SOLO: `sf apex run test -o FortraUAT -n <Test> --code-coverage --synchronous`.
Org admin-operation lock recurred repeatedly (concurrent build edits today); cleared via retry loop.

| Class | SOLO % | >=75? | Test class | Tests |
|---|---|---|---|---|
| QuoteRenewalTypeHandler | 100% | PASS | QuoteRenewalTypeHandlerTest | 5/5 |
| RenewalQuoteHeaderHandler | 100% | PASS | RenewalQuoteHeaderHandlerTest | 20/20 |
| RenewalAssetQuantityHandler | 98% | PASS | RenewalAssetQuantityHandlerTest | 24/24 |
| RenewalQuoteLineHandler | 93% | PASS | RenewalQuoteLineHandlerTest | 8/8 |
| RenewalMaintenancePricingService | 92% | PASS | RenewalMaintenancePricingServiceTest | 50/50 |
| OrderRepriceInvocable | 91% | PASS | OrderRepriceInvocableTest | 10/10 |
| MaintenanceOrderDecompositionService | 84% | PASS | MaintenanceOrderDecompositionServiceTest | 40/40 |
| PartnerPricingService | 83% | PASS | PartnerPricingServiceTest | 28/28 |
| PartnerNetPricePosthook | 77% | PASS | PartnerNetPricePosthookTest | 47/47 |
| QuoteToOrderFieldMapper | 77% | PASS | QuoteToOrderFieldMapperTest | 9/9 |
| **COLAUpliftHandler** | **39%** | **FAIL** | COLAUpliftTest (WONT COMPILE) | incidental only |
| **COLAUpliftPrehook** | **0%** | **FAIL** | COLAUpliftTest (WONT COMPILE) | compile error |

Result: 10/12 pass >=75%, 2/12 fail.

## Root cause of the 2 failures
COLAUpliftTest is the SOLE test class for both COLAUpliftHandler (30 refs) and COLAUpliftPrehook (52 refs).
It does not compile:

```
COLAUpliftTest line 1813, column 70: Method does not exist or incorrect signature:
void buildOverrideMap(List<SObject>) from the type COLAUpliftPrehook
```

- COLAUpliftPrehook (ApexClass) IsValid handled, but the TEST references a removed method.
- Live COLAUpliftPrehook body (LastModified 2026-06-14T04:20:15Z, this session) contains ZERO occurrences of `buildOverrideMap` (verified via Tooling Body pull). The override map is now built inline in `getContractOverrides(Set<Id>)` returning `Map<Id, ContractOverride>`.
- COLAUpliftTest LastModified 2026-06-11T01:30:54Z — NOT re-synced after today's prehook edit.
- COLAUpliftTest IsValid=false in ApexClass; SOLO run returns Tests Ran=0, Outcome=Failed.
- COLAUpliftHandler 39% is incidental coverage from trigger-path execution in OTHER tests; its own assertions never run.

This is a build-hygiene regression (test/code signature drift), UAT-fixable: sync the test stub call at L1813 to the current prehook API. Same defect was flagged in the prior STAMP-FLOW verdict notes; it is now BLOCKING two classes' SOLO coverage.
