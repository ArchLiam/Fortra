# Prompt — Thoroughly validate active Pricing Procedure V21 (smoke-tested on real UAT data)

## Goal
Validate that `Rev_Mgmt_Default_Pricing_Procedure` **Version 21** (currently Active in FortraUAT) prices
correctly across all 104 documented scenarios. **Every scenario must be SMOKE-TESTED against actual data in
FortraUAT** — not statically reasoned. Produce a PASS/FAIL/BLOCKED results matrix with concrete evidence and
a defect list mapped to specific V21 steps. Do **not** fix or deploy a fix — validation only.

## Context
- **Org:** FortraUAT (`-o FortraUAT` / `--target-org FortraUAT`). Revenue Cloud Advanced (RLM) is enabled.
  NOTE: the `uat` alias is a different (5sInfusion) org — always use **FortraUAT**.
- **Procedure:** `Rev_Mgmt_Default_Pricing_Procedure`, active version **V21**. Re-confirm it is still Active
  first (Tooling API: `SELECT VersionNumber, Status FROM ExpressionSetDefinitionVersion WHERE
  ExpressionSetDefinition.DeveloperName='Rev_Mgmt_Default_Pricing_Procedure' ORDER BY VersionNumber DESC`).
- **Step skeleton (122 steps):** `Data/pricing-v21-validation/V21_step_skeleton.md`
- **Scenario catalog (source of truth):** `Data/pricing-v21-validation/V21_SCENARIO_CATALOG.md` and
  `scenario_catalog.json` (104 scenarios; fields: id, category, name, what_it_tests, proc_mechanism,
  expected_behavior, test_setup, defect_provenance, priority).
- **V21 gates on:** ItemPricingSource, SellingModelType, IsContracted, QuoteTypeText__c,
  ItemSalesTransactionAction, Fortra_Product_Type__c, Deal_Type__c, Attribute_Price_Mode__c,
  ItemIsDerived__std, AllowRegionalPricing__c, COLA_Uplift_Percent__c, GSW__c (GSA), proration fields.

## Scope
- **IN:** correctness of V21 outputs — NetUnitPrice, UnitPrice, ItemNetTotalPrice/TotalLineAmount,
  PricingTermCount, COLA uplift, partner/regional/derived/maintenance nets, currency conversion, proration,
  category aggregates/rollups, cancellation credits.
- **OUT:** deploying a fix, editing the procedure/flows/Apex/metadata. If a fix is warranted, **describe** it.

## Distinguishing a real defect from bad seed data (READ FIRST — avoid false defects)
The #1 failure mode of this validation is **mistaking a malformed fixture for a procedure/config defect**:
a wrong seed value makes a CORRECT V21 look broken, and you log a phantom "wrong configuration" finding.
**A mismatch is NOT a defect until you have proven the input data was valid and actually reached the
procedure as intended.** Enforce this:
- **No FAIL may be attributed to V21 or to org configuration until the seed data has passed the preflight
  below AND the procedure's explainability/debug trace confirms the intended branch ran on the intended
  inputs.** If you cannot prove the data was correct, the result is **BLOCKED (data unverified)**, never FAIL.
- Every mismatch must be **root-cause-classified** (see Method step 6) into exactly one of:
  `PROCEDURE-DEFECT` · `ORG-CONFIG-DEFECT` · `TEST-DATA-ARTIFACT` · `EXPECTATION-ERROR`.
  Only the first two are reportable findings. `TEST-DATA-ARTIFACT` → fix the fixture and re-run.
  `EXPECTATION-ERROR` → fix the expected value in the catalog and re-run.
- Use a **positive control**: for each category, first price a KNOWN-GOOD existing record (a real, correctly
  priced UAT quote/order) through V21 and confirm it matches. If the control passes but your fixture fails,
  suspect the fixture first, not the procedure.
- Prefer **cloning a known-good real record** over hand-building inputs — it minimizes seed errors.
- Distinguish a *missing-config-the-scenario-is-meant-to-expose* (a real `ORG-CONFIG-DEFECT`, e.g. a product
  genuinely lacking a required pricing attribute) from a *missing-config-the-fixture-forgot-to-set* (a
  `TEST-DATA-ARTIFACT`). The test is: would a real sales rep building this in the UI have hit the same gap?
  If yes → real defect; if the UI would have populated it for them → fixture artifact.

## Test data — MANDATORY smoke test on real UAT data (per scenario)
Resolve test data via this waterfall, in order:
1. **Find existing UAT data** that matches the scenario's `test_setup` (SOQL on Quote/QuoteLineItem/Order/
   OrderItem/Asset/PricebookEntry). If a suitable record exists, use it.
2. **If none exists, create it with the most appropriate provided fixture script** (run with
   `sf apex run --target-org FortraUAT -f <path>`, then grep the debug log for the ERROR-level marker):
   - `scripts/apex/setupColaUatTestData.compact.apex` — partner/"Discount" **New** quote (COLA/DPP, partner +
     billing-partner set) on "Fortra, LLC - Test". Use for: F-02/F-03/F-04 renewal+COLA, E-02/E-04 partner,
     J-04 COLA net, G partner-currency, H discounts.
   - `scripts/apex/setupCancelQuoteTestData.compact.apex` — convert-ready **Cancellation Quote** (Qty −1,
     `CancelNetUnitPrice__c` seeded). Use for: K-01/K-08 cancel credit, K-10 null-safe, F-12, A-02 (quote tier).
   - `scripts/apex/setupCancelOrderTestData.compact.apex` — **Cancellation Order** (Qty −1, asset-net stamped).
     Use for: K-01 order-tier cancel credit, order-side carry-forward.
   - `scripts/apex/setupPowerConvertQuoteTestData.compact.apex` — high-qty **Power convert quote**. Use for:
     C-01 hardware decomposition, B-07 tiered-on-convert, F-07/F-08 convert, K-03 governor, K-05 reprice order.
3. **If none of those scripts fits the scenario, WRITE A NEW fixture script and execute it.** Match the house
   style of the four above (see conventions below). Save new scripts under `scripts/apex/` named
   `setup<Scenario>TestData.compact.apex`.
4. After data exists, **run pricing** (Pricing Simulation / Get Pricing API headlessly where possible; else
   the documented UI reprice/convert flow) and **query the resulting field values** to assert actual vs
   expected. A scenario is only PASS when real records show the expected numbers.

### New-script conventions (copy from the four reference scripts)
- Target **FortraUAT**; first line comment states what it builds + which scenario id(s).
- `Savepoint sp = Database.setSavepoint();` wrap; on any exception `Database.rollback(sp)` then re-`throw`
  (non-zero CLI exit, no orphan records).
- `Database.DMLOptions` with `DuplicateRuleHeader.AllowSave = true; RunAsCurrentUser = true;` on every insert.
- Reuse standing records, do not mutate them beyond required-field backfill:
  Account "Fortra, LLC - Test" `001WC00000XiZP4YAN`; Opportunities `006WC00000RPVp3YAH` /
  `006WC00000OE0NKYA1`. Clone known-good Contact/Place templates so required + custom fields are populated.
- Honor convert preconditions when the scenario converts: StartDate, BillToContact, Bill/Ship Place +
  Billing/Shipping **address text**, Account Type/DB_DUNS__c. Pick PBEs with `Pricebook2.IsActive=true`
  (the live book is "Fortra Price Book"; "Standard Price Book" is inactive).
- Uniquify created records with a per-run `TAG` (datetime) **plus a random suffix** so parallel agents don't
  collide; only write unique fields (DB_DUNS__c) when blank.
- Emit one ERROR-level marker line per script with the scenario id + clickable record URLs (for evidence).
- Put any generated data/evidence under `Data/pricing-v21-validation/` (fixtures index, logs, screenshots).

## Method — per scenario, P0 first → P1 → P2
1. **Trace the branch** from `proc_mechanism` in the V21 skeleton; confirm the gating condition routes it.
2. **Get real data** via the Test-data waterfall above (find → named script → new script).
3. **Preflight the seed data (MANDATORY GATE before pricing).** Prove the fixture is internally valid and
   actually matches the scenario's `test_setup`. Do NOT proceed to assert outputs until every check passes;
   if any fails, fix the fixture and repeat. Verify at minimum:
   - Product has the **expected Fortra_Product_Type__c, ProductSellingModel/SellingModelType**, and any
     **pricing attributes** the branch needs (e.g. derived/maintenance attribute, Attribute_Price_Mode__c).
   - **PricebookEntry** is active, parent **Pricebook2.IsActive=true**, matching **CurrencyIsoCode**, and a
     **non-zero, correct list price** (a $0 PBE silently yields $0 — a data error, not a pricing bug).
   - For renewal/cancel/derived scenarios, the **source Asset/AssetActionSource has the expected positive NET**
     (the cancel scripts warn: no positive Generate net ⇒ nothing to stamp ⇒ TotalPrice 0 = data error).
   - **Scenario-required fields are set**: partner fields (PartnerAccountId, Partner_Pricing_Model__c,
     PartnerDiscountPercent) for partner cases; currency for FX cases; Deal_Type__c/GSW__c for deal cases;
     term/proration fields for subscription cases; QuoteAction/OrderAction Type for renew/cancel/amend.
   - The quote/order is in a **priceable state** (synced where required; CalculationStatus reaches
     `CompletedWithPricing`, not error) — a calc error is a setup problem to resolve, not a FAIL of V21.
   Record the preflight result; a scenario that can't reach a valid preflight is **BLOCKED (data unverified)**.
4. **Run pricing** and capture the actual output fields **AND the procedure explainability / debug trace**
   (which steps fired, on what inputs) so data-vs-logic can be told apart.
5. **Compare** actual vs `expected_behavior`; record **PASS / FAIL / BLOCKED** with the real numbers + an
   evidence pointer (record URL, query output, explainability trace, log marker, screenshot under `.../evidence/`).
6. **Root-cause triage on any mismatch (before recording FAIL).** Using the trace + preflight evidence,
   classify the cause as exactly one of `PROCEDURE-DEFECT` / `ORG-CONFIG-DEFECT` / `TEST-DATA-ARTIFACT` /
   `EXPECTATION-ERROR`:
   - If the trace shows the branch never ran, or ran on wrong inputs → the data/route is wrong, not V21.
   - If inputs were correct and the branch produced the wrong number → `PROCEDURE-DEFECT` (or
     `ORG-CONFIG-DEFECT` if the wrong number traces to a missing/incorrect config a real user would also hit).
   - `TEST-DATA-ARTIFACT`/`EXPECTATION-ERROR` → correct the fixture/expectation and **re-run** before
     recording the final result. Only `PROCEDURE-DEFECT`/`ORG-CONFIG-DEFECT` become defect findings.
   - For a genuine defect, name the responsible step/condition and check `defect_provenance` to flag a
     **regression** of an already-fixed ticket.

## Execution / parallelism — USE THE MAXIMUM NUMBER OF AGENTS
- Fan out with the **maximum number of parallel agents** available (Workflow `parallel`/`pipeline`, capped by
  the platform concurrency). Default to **one agent per scenario**, batched by category so all 11 categories
  progress concurrently; do not validate scenarios serially.
- Each agent owns its scenario end-to-end: find/create data → run pricing → assert → write its result row.
- **Avoid org collisions:** each agent creates its own uniquely-tagged fixture; serialize only writes that
  touch the same unique-constrained record. Re-running a scenario must be idempotent.
- A final synthesis agent merges all rows into the results file and computes the coverage summary.

## Constraints
- **Retrieve live before trusting local source** — local copies drift.
- **No deploys, no version activate/deactivate, no edits to the procedure/flows/Apex.** Validation only.
  (Creating *test data* via the fixture scripts is allowed and expected.)
- Respect the order-reprice-**before**-Activate ordering. If a DML is blocked by the RLM platform lock at
  runtime, fall back to UI creation and document it — but the provided scripts are proven to insert Draft
  Quotes/Orders in this org.
- If a scenario genuinely cannot be smoke-tested (no data, no buildable fixture), mark **BLOCKED** with the
  exact blocker — never fabricate a PASS or downgrade to a static check.
- **Never report a `PROCEDURE-DEFECT` or `ORG-CONFIG-DEFECT` until the seed data has passed preflight and the
  explainability trace confirms the intended branch ran on valid inputs.** Unproven data ⇒ BLOCKED, not FAIL.
  When in doubt, suspect the fixture before the procedure.
- Every one of the 104 scenarios gets a row. No silent skips.
- Known durability risks to watch: version churn dropping logic deltas (K-07), oscillating derived-tier
  formula (J-02), quote-vs-order context-version parity (K-15).

## Output — write `Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md`
1. **Results matrix:** `| id | category | priority | data source (existing / script / new-script) | preflight
   (pass/fail) | expected | actual | result (PASS/FAIL/BLOCKED) | root-cause class | evidence (record URL /
   trace / log) |`. The `root-cause class` is one of PROCEDURE-DEFECT / ORG-CONFIG-DEFECT / TEST-DATA-ARTIFACT
   / EXPECTATION-ERROR / N-A(pass).
2. **Defects found (only PROCEDURE-DEFECT / ORG-CONFIG-DEFECT):** scenario id, responsible V21 step, observed
   vs expected, the explainability evidence that the input was valid, regression?(ticket), proposed fix
   (not applied).
2b. **Data/expectation corrections:** scenarios where a TEST-DATA-ARTIFACT or EXPECTATION-ERROR was found and
   fixed, with the corrected fixture/expected value and the re-run result.
3. **Coverage summary** by category (pass/fail/blocked counts) + overall **P0 pass rate**.
4. **Fixtures created:** list of new scripts written + records created (for cleanup).
5. **Durability/risk callouts** as follow-ups.

**Test ALL 104 scenarios to completion.** Priority (P0 → P1 → P2) sets the ORDER of coverage only — a
failure at any priority NEVER stops or short-circuits the run. Do not halt for triage; record each result
and keep going until every scenario has a row. Thoroughness over early exit.
