# 04 — Test remediation + re-review (test-gate dimension)

**Date:** 2026-06-11 (later same day) · **Reviewer:** Liam Jeong · **Scope:** test coverage + green-suite only. Prod deployment/packaging is owned by another team and was explicitly out of scope for this pass; the deploy/packaging/renewal-*functional* blockers in [02_BLOCKERS_AND_DEFECTS.md](02_BLOCKERS_AND_DEFECTS.md) and [03_DEPLOY_MANIFEST_AND_COMPLETION_PLAN.md](03_DEPLOY_MANIFEST_AND_COMPLETION_PLAN.md) are **unchanged**. This pass raised *test coverage*, not feature-readiness.

## Verdict change — test-gate dimension only

| Gate | Original review | After this pass |
|---|---|---|
| Apex test suite green | ❌ 4 failures (Outcome=Failed) | ✅ **0 failures, all green** |
| Maintenance-build classes ≥75%/≥90% | ❌ 5 classes 2–37% | ✅ **all 10 classes ≥90%** |
| Genuine functional bug (partner 15-vs-12) | flagged as a bug (B-3) | ✅ **disproven — not a bug** (see below) |

The **test-gate dimension flips from NO-GO to GREEN.** The overall ticket verdict is still NO-GO for prod because the *functional* and *packaging* blockers (renewal priced E2E once with null carry-forward; `Asset_Action_Source_Entries_Decision_Table_V2` refresh Failed; prod missing fields/classes/context-def/PCR; procedure V1-vs-V13) are untouched by test work — those remain the owner/other-team's path.

## Final coverage scorecard (verified live, FortraUAT)

| Class | Before | After | How | Prod code changed? |
|---|---|---|---|---|
| PartnerPricingService | 33% | **100%** | new `PartnerPricingServiceTest` | none |
| QuoteRenewalTypeHandler | 70% | **100%** | (already) | none |
| RenewalQuoteHeaderHandler | 15% | **100%** | +9 tests | none |
| RenewalAssetQuantityHandler | 36% | **97.9%** | +11 tests | none |
| MaintenanceOrderDecompositionService | 77% (solo) | **97.9%** | +unit tests | **none** |
| PartnerNetPricePosthook | 37% | **95.5%** | +tests + test seam | **seam only** (below) |
| RenewalMaintenancePricingService | 2% | **92%** | new tests + test seam | **seam + dead-code removal** |
| QuoteToOrderFieldMapper | 76% | **92%** | (already) | none |
| OrderRepriceInvocable | 85%＋fail | **91%** | fixed failing test | none |
| RenewalQuoteLineHandler | 90% | **91%** | (already) | none |

Each percentage is from a real test run on FortraUAT (run IDs: 707WC00002y4447, y4NCr, y4kwM, and the earlier per-unit runs). All tests pass. An earlier combined-suite run of all 10 test classes was **183 tests, 100% pass, 0 failures** (org-wide 45% — org-wide is dragged by hundreds of unrelated org classes and is a prod-deploy concern, out of scope here).

> Coverage note: Salesforce per-class coverage can read lower in a large mixed `--tests` run than in a dedicated run (multi-test-context attribution quirk — e.g. MaintenanceOrderDecompositionService showed 51% combined vs 77%/97.9% solo). The authoritative number for each class is its dedicated run, shown above; a real prod `RunLocalTests` deploy computes the proper union.

## The 4 originally-failing tests — all resolved, all were test-side

1. **`testBuildNetPriceUpdate_usesProductTypeFromBulkMapWhenContextBlank` (the "15% vs 12%" finding, original Blocker B-3): NOT a product bug.** Diagnosed live: a **before-save flow in FortraUAT defaults a blank `QuoteLineItem.Fortra_Product_Type__c` to `'Software'` on insert**, so `loadProductTypesForLines` correctly returned the (now-populated) line-level `'Software'`. `PartnerPricingService.resolveProductType` is correct by design (line-level type is authoritative when present). The test's premise (line-level type stays blank) was invalid in this org → the test was fixed to set `Fortra_Product_Type__c='New Maintenance'` explicitly. **No product code changed.** → **B-3 in [02_BLOCKERS_AND_DEFECTS.md](02_BLOCKERS_AND_DEFECTS.md) is RETRACTED.**
2. `enrichPartnerDataFromSourceQuote_fallsBackToLinkedQuote` — seeded a `Quote_Checklist_Item__c` to satisfy the "No checklist items found for Quote" VR.
3. `buildRenewalMaintenanceColaUpdate_correctsStaleLastTransactionNet` — replaced the brittle `fakeIdFor()` (emitted a checksum-invalid Id that `Id.valueOf` rejected) with a valid Id generator; the COLA math was always correct.
4. `OrderRepriceInvocableTest.reprice_seedsQuotePricingBeforeExecutor` — fixed the test-data/isolation setup (INVALID_CROSS_REFERENCE_KEY).

## Production-class changes (test-enabling seams — behavior-preserving)

Two classes required a minimal `@TestVisible` injection seam because their uncovered lines are the Salesforce RCA pricing-engine context I/O (`Context.IndustriesContext.queryTags()/buildContext()/updateContextAttributes()/persistContext()`), which **throws outside a live pricing transaction** and cannot run in an Apex unit test. **In production all override fields are null, so every seam takes the real `ctx.*` branch → runtime behavior is byte-for-byte identical to before.** No public/`@InvocableMethod` signatures or logic changed.

### RenewalMaintenancePricingService.cls
- Added 2 `@TestVisible` static override fields (`testQueryTagsResponse`, `testContextIdOverride`).
- Guarded the `queryTags` read, two `updateContextAttributes` writes, and `buildContext`+`persistContext` with `Test.isRunningTest() && override != null` ternaries/guards.
- **Removed dead `private static Decimal getDecimal(Map, String)`** (orig. lines 462-481, ~20 lines) — proven zero callers by whole-codebase grep (the real callers use the differently-named `getDecimalFromTag`).
- Result: 50.4% → **92.0%** (230/250). 20 residual lines = the live-`ctx` false-branches of the seams + provably-dead loop guards.

### PartnerNetPricePosthook.cls
- `@TestVisible` on the existing `isProcessing` re-entrancy flag; 5 new `@TestVisible` static fields (3 response stubs + a captured-payload field).
- Guarded `buildContext`/`persistContext` (order path), both `queryTags` reads (line-items + header), and the `updateContextAttributes` write (captures the payload under test instead of calling the platform).
- No code removed. Result: 69.2% → **95.5%** (492/515). 23 residual lines = live-`ctx` branches + dead defensive guards (left in place to keep the diff pure-seam).

### MaintenanceOrderDecompositionService.cls
- **Zero production changes** — no engine I/O, so no seam. 77% → **97.9%** (228/233) by adding behavioral unit tests. 5 residual lines = 1 dead defensive branch + 4 lines requiring multiple tier-valued `QuoteLineItemAttribute` rows, which are not DML-insertable (`IsCreatable=false`, managed RLM object) and zero exist in the org.

Full seam diffs and per-class residual line analysis: [evidence/seam_workflow_results.json](evidence/seam_workflow_results.json).

## What this does NOT change (still open — other team / owner)
- Renewal priced E2E **exactly once** (order 00095475) with **null carry-forward + UnitPrice=0** — *functional*, not test (Blocker B-4).
- `Asset_Action_Source_Entries_Decision_Table_V2` refresh **Failed** ("Hash Key Group >200 rows") — the "both-assets" blocker (B-5).
- Prod missing 3/5 QLI fields, all new classes, both triggers, `SalesTransactionContextExt_v2`, PCRs, backfill; procedure **V1 vs V13** (Blockers B-2, M-3).
- The SDD "no Apex pricing prehook" principle is still false-as-built (M-1) — and this pass *reinforced* it: the seams are inside the `SignalingApexProcessor` posthook/prehook classes that own renewal/partner net.

## Method
5-unit sequential coverage workflow + 3-unit sequential seam/coverage workflow (one deploy at a time to the single UAT org), each agent self-verifying against live test runs. Staging source dir: `Data/sc-maint/src/classes/`. Evidence: `evidence/apex_testrun_*.txt`, `evidence/seam_workflow_results.json`, `evidence/coverage_workflow_units.json`.
