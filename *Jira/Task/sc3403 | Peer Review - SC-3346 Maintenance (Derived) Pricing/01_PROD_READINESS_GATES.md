# 01 — Production-readiness gates (test + coverage detail)

Source of truth: fresh Apex run **707WC00002y0PNw** on FortraUAT (`liam.jeong.c@fortra.com.uat`), 76 tests, full evidence in [evidence/apex_testrun_707WC00002y0PNw.txt](evidence/apex_testrun_707WC00002y0PNw.txt). This run is authoritative; the `ApexCodeCoverageAggregate` snapshot taken earlier showed several classes at 0% because they were modified the same day (coverage is invalidated until the next run) — do not use it.

## Gate summary
| Gate | Requirement | Result |
|---|---|---|
| Outcome | all pass | **Failed** (4/76 fail, 95% pass) |
| Org-wide coverage | ≥ 75% | **43%** |
| Every deploy-set class | ≥ 75% line | **5 classes below** (see below) |
| Every trigger | > 0% | ✅ QuoteTrigger 100%, QuoteLineItemTrigger 92% |

## The 4 failing tests — triaged
| # | Test | Failure | Category | Root cause |
|---|---|---|---|---|
| 1 | `PartnerNetPricePosthookTest.testBuildNetPriceUpdate_usesProductTypeFromBulkMapWhenContextBlank` | Expected 12, Actual 15.00 | **GENUINE BUG** | `PartnerPricingService.cls:194` bulk overload hard-returns `'Software'` on a map-miss → 15% software rate applied to a 12% New-Maintenance line. Runs on new-business + renewal derived lines. → Blocker B-3 |
| 2 | `PartnerNetPricePosthookTest.buildRenewalMaintenanceColaUpdate_correctsStaleLastTransactionNet` | "Same value: null" | **brittle test fixture** | `fakeIdFor` produces `0QL000000000001AAA`; `Id.valueOf` throws → `getLineItemRecordId` returns null (PartnerNetPricePosthook.cls:709-712, 812-814). The COLA math itself is correct (`computeRenewalMaintenanceColaNet`=67.38 passes). Fix the fake-Id generator. **Not** proof of the SC-3350 gap (that's evidenced separately by order 00095475). |
| 3 | `PartnerNetPricePosthookTest.enrichPartnerDataFromSourceQuote_fallsBackToLinkedQuote` | FIELD_CUSTOM_VALIDATION "No checklist items found for Quote" | test-data/env | Test inserts a Quote without seeding `Quote_Checklist_Item__c`; a VR fires. Seed the checklist item (other tests in the suite do). |
| 4 | `OrderRepriceInvocableTest.reprice_seedsQuotePricingBeforeExecutor` | INVALID_CROSS_REFERENCE_KEY / "don't have the required access" | test-data/env | Privileged DML / cross-ref setup in the running user's context; the successful-reprice path therefore has **no passing E2E coverage**. OrderRepriceInvocable's credited 85% comes from graceful-failure tests only. |

Categories 3 and 4 are harness defects, but they still set Outcome=Failed → the suite cannot be deployed regardless.

## Coverage by class (fresh run)
**Clears 75%:** QuoteRenewalTypeHandler 100%, QuoteTrigger 100%, OrderValidationTrigger 100%, QuoteSyncingTrigger 100%, QuoteLineItemTrigger 92%, QuoteToOrderFieldMapper 92%, COLAUpliftHandler 92%, RenewalQuoteLineHandler 90%, OrderRepriceInvocable 85%, OpportunityTrigger 71%→(trigger>0 ok), MaintenanceOrderDecompositionService 76%.

**BELOW 75% (block the gate):**
| Class | % | Note |
|---|---|---|
| **RenewalMaintenancePricingService** | **2%** | NO dedicated test class exists — the renewal pricing core is essentially unverified |
| **RenewalQuoteHeaderHandler** | 15% | owner open item "auto-populate renewal headers" |
| **PartnerPricingService** | 33% | the class holding the B-3 bug |
| **RenewalAssetQuantityHandler** | 36% | the "both-assets renewal" path (B1) |
| **PartnerNetPricePosthook** | 37% | the partner/renewal net engine |
| `COLAUpliftPrehook` | absent from table = **0% in this run** | 575-line load-bearing prehook (shared with SC-3350); modified today; not exercised by this run |

Org-wide **43%**.

## Test-quality note (even the green tests under-prove the path)
The bulk of passing assertions exercise `MaintenanceOrderDecompositionService.compute` — a **pure arithmetic helper fed pre-decomposed inputs** (e.g. `compute_matchesWorkedExample` passes `1000,140,180,140` and re-derives `200/20/40`). It inverts inputs through the same formula; it does **not** run the V13 procedure. `RenewalQuoteLineHandlerTest` is genuinely behavioral (inserts QLIs, asserts trigger-driven deletion), but **no test in the suite drives a real reprice through the live pricing procedure**. So the green 95% does not validate the actual prod pricing path; new-business "468×0.20=$93.60" validation is manual/UAT-screenshot only.

## Remaining test work (quantified, multi-day)
1. New `RenewalMaintenancePricingServiceTest` (0→75%+).
2. Behavioral coverage for `COLAUpliftPrehook` (0%), `RenewalQuoteHeaderHandler` (15→75%), `RenewalAssetQuantityHandler` (36→75%), `PartnerNetPricePosthook` (37→75%), `PartnerPricingService` (33→75%).
3. Fix the 2 genuine functional failures (B-3 partner rate; the COLA-net path generally — and persist carry-forward per B-4).
4. Repair the 2 test-data/env failures (checklist seed; privileged DML/runAs).
5. Add ≥1 procedure-driven end-to-end pricing assertion.
6. **Freeze the class set first** — 5 classes were modified 2026-06-11; coverage/results are a moving target until the build stops churning.
