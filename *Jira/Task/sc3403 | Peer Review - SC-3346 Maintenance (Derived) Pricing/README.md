# Peer Review (SC-3403) — Maintenance (Derived) Pricing (SC-3346): production-readiness assessment

**Build ticket:** **SC-3346** — Maintenance (Derived) Pricing ("Auto-Add First Year Maintenance and Additional Year Renewal Pricing")
**Peer-review ticket:** **SC-3403**
**Parent:** SC-1457 Revenue Cloud: Quote to Order · **Reporter:** Marc DeBrey · **Owner:** Nir Kailash · Sprint 14 · Component: SF RCA · Priority: Blocker
*(SC-3346 is where Leah Guenther's worked-example waterfall lives; it is the parent referenced by the COLA ticket SC-3350.)*

> **Update note (2026-06-11, later):** after this initial NO-GO review, the test classes were brought to ≥90% coverage and green per a follow-up request (prod-deploy items deferred to another team). See **[04_TEST_REMEDIATION_AND_REREVIEW.md](04_TEST_REMEDIATION_AND_REREVIEW.md)** for the updated coverage/test state and the revised verdict on the test-gate dimension.

**Reviewer:** Liam Jeong · **Date:** 2026-06-11 · **Method:** live UAT + Prod org queries, a fresh 76-test Apex run, retrieval of all live sources, and an 8-agent adversarial review workflow (6 dimensions + a devil's-advocate GO case + synthesis). Every claim below is cited to a file:line, query result, or test name. Evidence is in [evidence/](evidence/).

---

## VERDICT: 🔴 NO-GO for production

This build is **not a finishing pass; it is a from-zero packaging effort plus multi-defect remediation.** It fails **every** hard prod-deploy gate, verified live:

| Hard gate | Required | Actual | Source |
|---|---|---|---|
| Apex test suite green | 0 failures | **4 failures (Outcome=Failed)** | testrun.txt:125 |
| Org-wide coverage | ≥ 75% | **43%** | testrun.txt:136 |
| Renewal/partner class coverage | ≥ 75% each | PartnerNetPricePosthook 37%, RenewalMaintenancePricingService **2%**, RenewalQuoteHeaderHandler 15%, RenewalAssetQuantityHandler 36%, PartnerPricingService 33% | testrun.txt:92-107 |
| Code exists in prod-deployable form | yes | **prod has 0 of ~10 new classes, neither trigger, 3/5 QLI fields missing, 0 OrderItem fields** | live FortraProd queries |
| Prod pricing procedure | matches UAT | **Prod V1 vs UAT V13** (12-version gap, couples 5 tickets in one ExpressionSetVersion) | live FortraProd ExpressionSetVersion |
| Renewal E2E works | yes | **priced E2E exactly once** (order 00095475), and even that order persists null carry-forward + UnitPrice=0 | live OrderItem query |
| Build frozen for release | yes | **5+ classes modified the day of review (2026-06-11)**; inventory incomplete | live ApexClass LastModifiedDate |

The owner's own assessment ("new business is essentially done; renewal needs one more pass") **overstates readiness on both halves** when measured against prod gates and live code — see the claim-by-claim refutations below.

---

## What is genuinely solid (do not re-litigate these)

The new-business **design and core logic are coherent and worth preserving** — the devil's-advocate review verified these and they survived scrutiny:

- **Branches are runtime-decoupled** in V13 via `IF(QuoteTypeText__c='Renewal', …)` — a broken renewal formula **cannot** corrupt a new-business quote (V130 lines 1906/1971). The architecture is sound.
- **New-business decomposition math is fully unit-proven** — 33/33 `MaintenanceOrderDecompositionService` tests pass incl. `compute_matchesWorkedExample` (1000→200→140 worked example). (testrun.txt:7-39)
- **Triggers ARE covered** — QuoteTrigger 100%, QuoteLineItemTrigger 92% on the fresh run. (The "0% trigger" reading in the stale `ApexCodeCoverageAggregate` was an artifact of same-day edits; the fresh run is the source of truth.)
- **Selling-model backfill (Step 8) is loaded** — `PIA-PIA-NRPS-PIAP` is priceable in Term-Based-Annual (4,943 TermDefined PSMOs org-wide); `Derived Pricing Entries` decision table is **Completed** (synced 2026-06-11 20:36).
- **Year-2 config rule exists** (14OWC0000022Eyb2AE "Year 2 Maintenance Sku added to … Perpetual") in UAT.

**A new-business-only carve-out is the one defensible partial path** — but it is a *multi-day hardening pass*, not a same-day ship (see "New-business carve-out" below).

---

## BLOCKERS (each independently prevents a prod deploy)

**B-1 · Test suite is red + org-wide coverage 43%.** 4 failures, Outcome=Failed, 43% org-wide vs 75% required. Two failures are **genuine functional bugs** (B-3, B-4); two are test-data/env defects but still leave the suite red. (testrun.txt:125,136 · [01_PROD_READINESS_GATES.md](01_PROD_READINESS_GATES.md))

**B-2 · Production is structurally absent — this is a from-zero bundle, not a promotion.** Live FortraProd: 0 of the new classes, neither QuoteTrigger nor QuoteLineItemTrigger, only 2/5 QLI fields (`Source_List_Price__c`, `Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c` missing), 0 OrderItem maintenance fields, no `SalesTransactionContextExt_v2` context def, **0 ProductConfigurationRules**, 0 selling-model/PBE backfill, 0 `Maintenance_Rate__mdt` rows, no MaintenanceType decision table, no stamp flows. Several items (context def, procedure version, PCR, backfill data) **have no CI/CD path at all**. ([03_DEPLOY_MANIFEST_AND_COMPLETION_PLAN.md](03_DEPLOY_MANIFEST_AND_COMPLETION_PLAN.md))

**B-3 · Real partner-rate bug: derived maintenance lines get Software 15% instead of New/Renewal Maintenance 12%.** `PartnerPricingService.resolveProductType` (bulk overload, **PartnerPricingService.cls:194**) hard-returns `'Software'` on a bulk-map miss instead of falling through to the `Product2.Fortra_Product_Type__c` lookup the single overload does (lines 79-92). `PartnerNetPricePosthook` runs on **new-business AND renewal** derived lines, so this mis-prices partner maintenance quotes in scope today. Proven by failing test `testBuildNetPriceUpdate_usesProductTypeFromBulkMapWhenContextBlank` (Expected 12, Actual 15.00, testrun.txt:68).

**B-4 · Renewal carry-forward is broken — renewal has priced E2E exactly once and didn't persist its decomposition.** Only order **00095475** ever completed renewal pricing ($60.64); its Renewal-Maintenance OrderItem persists `Prior_Partner_Discount__c=null`, `Prior_Discretionary_Discount__c=null`, `UnitPrice=0`. A Year-2→Year-3 renewal would read null priors and mis-price `(71−0−0)×1.0785=76.57`. 13 of the 15 most-recent build-renewal quotes have GrandTotal 0. The in-procedure `DerivedPricingRenewals` formula also has **no null-guard** on its operands and is the same inert-write pattern SC-3350 proved cannot commit net on non-derived `LastTransaction` renewal lines. (live OrderItem query · V130:1971 · SC-3350 09_NETPRICE_SEED_INERT_RCA.md)

**B-5 · The renewal source decision table refresh is FAILED — this is the mechanism behind blocker "B1" (renewing both assets fails before a quote is created).** `Asset_Action_Source_Entries_Decision_Table_V2` (0lDa50000007BJhEAM) is **RefreshStatus=Failed**, `LastSyncDate=null`, reason **"Hash Key Group contains more than 200 rows"** over 430,329 `AssetActionSource` rows — never synced. The renewal path can't resolve sources. (live DecisionTable query)

**B-6 · The Step-5 dollar decomposition fires inconsistently across live orders.** Order 801WC00000kZELqYAO maintenance line: `Base_Price__c=71` / `Prior_Partner_Discount__c=8.52` (correct). Order 801WC00000kYmw8YAC lines: `Base_Price__c=355` (the raw **license** base, not the 71 maintenance base) / partner+discretionary null. Carrying 355 forward as the maintenance base then COLA-growing it would ~5× the renewal price. The "Q2O E2E validated / carry-forward persisting" claim holds only on some orders. (live OrderItem query · MaintenanceOrderDecompositionService.cls:145-154)

---

## MAJORS (must resolve before sign-off; not all independently block deploy)

**M-1 · The design's KEY PRINCIPLE — "no Apex pricing prehook on the maintenance line" — is false as built.** Two `RevSignaling.SignalingApexProcessor` classes write net into the pricing context: `COLAUpliftPrehook.cls:21` and `PartnerNetPricePosthook.cls:22` (writes NetUnitPrice at :264-271, :842-849). Renewal net is computed in **three** places (Flow + V13 formula + Apex posthook), and `DerivedPricingRenewals` reads `COLACalculatedPrice__c` *first* — seeded only by the prehook. Per SC-3350 this is actually *necessary* (a procedure-only seed can't set net on non-derived lines). **The SDD must be reconciled to reality; the deploy manifest cannot be derived from the SDD's component list.** (SDD lines 22,26,160)

**M-2 · Two competing, undocumented new-business formulas in V13.** `ListContainer9` (seq 6) computes `Source_List_Price__c × tier` (V130:1776); `DerivedPricingNewBusiness` (seq 7) computes `Base_Price__c × tier` (V130:1906) and overwrites it — *but only when the MDT attribute filter passes* (V130:1700). The two read different inputs and can produce different prices. The SDD specifies only the single `Source_List_Price__c × tier` formula. **Pick one.**

**M-3 · Reprice `contextDefinitionName` error is a guaranteed prod failure, not intermittent.** Prod lacks `SalesTransactionContextExt_v2` entirely (UAT has it + the base def). `PartnerNetPricePosthook` hard-codes `CONTEXT_DEFINITION_NAME='SalesTransactionContextExt_v2'` (:28,:98). UAT also has **two** active context defs and **four** active discovery procedures — Marc's "two discovery procedures / corruption" instinct is a real anomaly, though the likely root cause per prior RCA is the unsynced context after in-place V-edits. `OrderRepriceInvocable` (PlaceOrderExecutor Force) is the affected Q2O-before-Activate path; its success test fails with INVALID_CROSS_REFERENCE_KEY (testrun.txt:78).

**M-4 · `Source_List_Price__c` Q2O mapping is DISABLED in the one class that ships.** In `QuoteToOrderFieldMapper` the QLI→OrderItem propagation for `Source_List_Price__c` is commented out (header note + lines 115-121) while the other carry-forward fields are mapped (246-253). Tied to the "Unable to fetch tags: [Source_List_Price__c]" order-reprice error. Decide flow-vs-mapper source of truth.

**M-5 · Two of four derived RRM/RNM PBEs lack `PriceBookEntryDerivedPrice` config (SC-3372 regression risk).** Only 2 of 4 IsDerived PBEs have a derived-price row; the OneTime/Standard RRM PBEs have none — the exact pattern that makes native `DerivedPricingDataRetrieval` hard-error "contributing products are missing."

**M-6 · `COLAUpliftPrehook` prod copy is already stale vs UAT** (~3,316 char delta; prod 39,956 vs UAT 43,272) and is live-only in both — the COLA/partner stack must co-deploy, reconciled.

**M-7 · Renewal classes are largely untested** — `RenewalMaintenancePricingService` has **no dedicated test class** (2% incidental), `RenewalQuoteHeaderHandler` 15%, `RenewalAssetQuantityHandler` 36%. These are exactly the classes behind the owner's open items (auto-populate headers; both-assets renewal).

---

## MINORS / corrections

- **Two stamp flows are active** (`Stamp_Maintenance_Pricing_Inputs` v11 + older `Stamp_Source_List_Price` v8) — redundant; they feed the two M-2 formulas. Retire one.
- **`COLA_Source__c` restricted picklist in force-app is missing the live `MyCAP Default` value** — a partial COLA-field deploy would fail validation or strip a value the code relies on (SC-3350-class regression). Re-retrieve from UAT.
- **Correction:** the failing test `buildRenewalMaintenanceColaUpdate_correctsStaleLastTransactionNet` root-causes to a **brittle fake-Id fixture** (`0QL000000000001AAA` fails `Id.valueOf`), not the COLA math (`computeRenewalMaintenanceColaNet`=67.38 passes). The SC-3350 net-commit gap is independently real (B-4), but this specific failure does not demonstrate it. Fix the fake-Id generator.
- **Correction:** the "COLA caps at 9.99" concern is **false** — `COLA_Uplift_Percent__c` is Number(3,2) **Precision 5** (max 999.99) and the formula divides by 100. The real currency risk is **`Base_Price__c` being Number not Currency** (currency-blind, shared with SC-3384) — evaluate before non-USD go-live.
- **Correction:** B2 ("Year-1 product copied not swapped to RRM") **partially fired correctly** on order 00095475 (RRM present, no New-Maintenance line) — but `RenewalQuoteLineHandler` cleanup is an async-Queueable race that no-ops if the Year-2 config rule (needs a license on the cart) hasn't added RRM first. Maintenance-only renewals remain unproven.
- **Stale narrative:** the SDD's "formula sits after Volume Discounts, before Quantity × Price" is wrong for V13 — all derived steps (seq 4-8) run *before* Volume Discounts (seq 21) and Quantity × Price (seq 22).
- Passing tests are skewed to the pure `compute()` helper fed pre-decomposed inputs; **no test drives a real quote through the V13 procedure.** Add at least one procedure-level assertion or a documented manual UAT script.

---

## The new-business carve-out (the only defensible partial GO — and it's CONDITIONAL)

The devil's-advocate review confirmed a new-business-only release is *architecturally* defensible (clean QuoteTypeText__c gate, proven math, covered triggers) but **breaks on packaging + a real defect**:

1. The partner posthook 15%-vs-12% bug (B-3) **runs on new-business lines too** — new-business *code* is wrong today.
2. The pricing procedure ships as **one** `ExpressionSetVersion`; you can't pluck new-business out of V13 — it requires authoring a carved **V14** (which also means deciding what to do with the SC-3393/3372/3359/3384 changes also baked into V13).
3. Prod is missing the fields/triggers/classes, and **both triggers call the renewal handlers unconditionally** — so even a new-business bundle drags the 2–37%-covered renewal classes into the deploy against the 75% gate.

**Minimum credible path:** fix B-3 → raise posthook + bundled-handler coverage to ≥75% → author/validate a gated V14 → deploy fields+triggers+classes+one stamp flow as one bundle → reconcile the SDD principle. That is a **multi-day hardening pass**, not a same-day ship → **CONDITIONAL, not GO.**

---

## Message to post on the ticket

> Nir — I can't sign this off for production. Verified live: org-wide coverage is 43% (need 75%), the test run is red with 4 failures, and **prod has only 2 of the 5 QuoteLineItem fields, none of the new classes, neither trigger, no `SalesTransactionContextExt_v2`, and the active prod pricing procedure is V1 against your V13** — so this is a from-zero bundle deploy, not a finishing pass. One failure is a genuine logic bug, not test noise: `PartnerPricingService.resolveProductType` (bulk overload, line 194) hard-returns `'Software'` on a map-miss instead of resolving the Product2 type, so derived maintenance partner lines get 15% instead of 12% — and that runs on new business too, so "new business essentially done" isn't true at the code level. Renewal is further from done than "one more pass": it has priced end-to-end **exactly once** (order 00095475) and even that order persists null carry-forward with `UnitPrice=0`, and the `Asset_Action_Source_Entries_Decision_Table_V2` refresh is **Failed** live ("Hash Key Group contains more than 200 rows") — that's your both-assets blocker. Net: **NO-GO**. A new-business-only carve-out is defensible (the V13 `QuoteTypeText__c` gate cleanly isolates the branches), but it still needs the partner-rate fix, posthook/handler coverage to 75%, a carved V14, reconciling the SDD's now-false "no Apex prehook" principle, and deploying the missing fields/triggers/classes plus the manual context-def/PCR/backfill items as one bundle. Happy to walk the completion plan with you and Marc.

---

## Document index
- **[01_PROD_READINESS_GATES.md](01_PROD_READINESS_GATES.md)** — gate-by-gate detail: tests, coverage, the 4 failures triaged, test-quality assessment.
- **[02_BLOCKERS_AND_DEFECTS.md](02_BLOCKERS_AND_DEFECTS.md)** — every blocker/major with code citations, mechanism, and the owner-claim each refutes.
- **[03_DEPLOY_MANIFEST_AND_COMPLETION_PLAN.md](03_DEPLOY_MANIFEST_AND_COMPLETION_PLAN.md)** — the full ordered prod manifest (pipeline vs manual/non-CI-CD) and the sequenced completion plan.
- **[evidence/](evidence/)** — `LIVE_STATE_CAPTURE.md`, `TICKET_AND_HANDOFF.md`, `apex_testrun_707WC00002y0PNw.txt`, `per_dimension_findings.txt`, `peer_review_workflow_findings.json`.
