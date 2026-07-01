# V21 Fix — PORTION 1 of 3: V21 PROCEDURE

**Your defects (7):** K-01 [P0], F-12 [P1], G-01 [P0], F-09 [P1], G-02 [P0], I-03 [P1], E-04 [P1]

**Your surface:** In-place edits to the active V21 ExpressionSet (pricing procedure) metadata, batched into ONE deactivate -> deploy -> reactivate cycle. PLUS E-04 also needs a small data backfill (Non_Orig_* on 30 Partner_Pricing_Model rows).

**Boundary:** You are the ONLY work-stream permitted to edit the V21 procedure. The other two tabs touch Apex / data records only and will NOT touch the proc.

## Mission

You are fixing a specific portion of the defects found in the **2026-06-30 validation of FortraUAT Pricing Procedure V21** (`Rev_Mgmt_Default_Pricing_Procedure`). Implement the fixes for the defects listed below, verify each on real data, and stop. This is one of **three parallel work-streams**; stay strictly within your portion's artifacts so the three tabs never collide.

## Environment (do not deviate)

- **Org = `FortraUAT`** only — every command uses `-o FortraUAT` / `--target-org FortraUAT`. The `uat` alias is a DIFFERENT (5sInfusion) org; never use it.
- **Active procedure:** `Rev_Mgmt_Default_Pricing_Procedure` **Version 21**, ACTIVE.
  - design `ExpressionSetDefinition` `9QAWC0000003mg14AA`
  - active version `ExpressionSetDefinitionVersion` **`9QBWC0000000oWH4AY`** (VersionNumber 21)
  - runtime `ExpressionSetVersion` `9QMWC00000025LN4AY`
  - pricing context `SalesTransactionContextExt_v2` (v23) / `OrderEntitiesMapping`
- **REST reprice API version = v67.0.**
- Standing test records: Account "Fortra, LLC - Test" `001WC00000XiZP4YAN`; live price book = **"Fortra Price Book"** (`01sWC0000022GHFYA2`, IsActive=true). "Standard Price Book" is INACTIVE — never use it.

## Hard rules (these have bitten us before)

1. **Validation context only became fix context just now — confirm before you change anything.** Retrieve LIVE before trusting local source; repo copies drift. Re-measure the defect on the live org first so you have a before/after.
2. **In-place V21 ONLY — never create a new version (no V22).** All procedure changes go into the existing ESDV `9QBWC0000000oWH4AY`.
3. **RLM canvas re-save CLOBBERS metadata deploys.** After any proc metadata deploy: FULLY CLOSE every open Pricing-Procedure canvas tab, open a FRESH tab, and **Activate from Setup -> Pricing Procedures -> Versions list** (a status flip), NEVER from inside a pre-deploy canvas editor. Re-retrieve the metadata IMMEDIATELY after activation to confirm it did not revert, before repricing.
4. **AdvancedListFilter criteria are referenced by POSITION 1..N, not sequenceNumber.** If you add/remove a criterion, renumber survivors contiguously and update `conditionLogic` to match (e.g. `1 AND 2 AND 3 AND 4 AND 5`). A dangling reference => runtime "Invalid criteria reference".
5. **Proc deploy mechanics:** retrieve/deploy with **api version 67** and `--metadata-dir` (MDAPI source format); the orphan `rca_diagnostic.cls-meta.xml` blocks source-format ops, so use MDAPI. Sequence: **deactivate V21 -> deploy -> reactivate from Versions list -> re-retrieve to confirm -> reprice to verify.**
6. **Order reprice BEFORE Activate** (never activate an order before its order-level reprice).
7. **This is a UAT fix exercise. Do NOT deploy anything to production.** Each fix is UAT-only until separately authorized.
8. **`ValidationResult` string fields are not usable in pricing formulas** ("unsupported field type") — if a fix needs a flag, use a numeric/boolean field or an AssignmentElement, not a formula on a string.

## What the validation found (so you trust the targets)

104 catalog scenarios were smoke-tested on real FortraUAT data via a 4-stage adversarial pipeline (executor -> verifier -> skeptical data-artifact audit -> tie-breaker). Outcome: **69 PASS / 13 FAIL / 22 BLOCKED**. Each defect below is a *confirmed* FAIL whose seed data passed preflight and whose intended V21 branch provably ran on valid inputs. Full evidence + per-scenario rows:
- Report: `Data/pricing-v21-validation/V21_VALIDATION_RESULTS.{html,md}` (exec-summary-first; defect cards).
- Per-defect rows: `Data/pricing-v21-validation/rows_run3/<id>.json` (live numbers + record IDs). Audit/tie-break detail: `audit_run3/`, `tiebreak_run3/`. Artifact pin for your defects: `fix_portions/<id>.json`.

**Already-excluded false positives — do NOT re-chase these:** D-09 (stale frozen FX field, not a live miscalc), I-02 (malformed off-by-one EndDate), J-05 (line on an Amend QuoteAction by design), K-02 & K-10 (catalog expected-value errors). **Out of scope for Fortra:** evergreen-catalog and contracted-pricing scenarios (no evergreen catalog, contracted pricing unsupported) — ignore any "blocked" items in those areas.

## Headless reprice + verify recipe (use for every verification)

```bash
# 1) body file (Quote example; use "Order" for orders). Force-reprice the record through live V21:
cat > /tmp/body.json <<'JSON'
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},
 "graph":{"graphId":"1","records":[{"referenceId":"ref1",
   "record":{"attributes":{"type":"Quote","method":"PATCH","id":"<RECORD_ID>"}}}]}}
JSON
# 2) place action (success = isSuccess:true, errorResponse:[]):
sf api request rest "/services/data/v67.0/connect/rev/sales-transaction/actions/place"   --method POST -o FortraUAT --body "$(cat /tmp/body.json)"
# 3) read the result fields:
sf data query -o FortraUAT -q "SELECT Id,Quantity,UnitPrice,NetUnitPrice,ListPrice,NetTotalPrice,TotalLineAmount,TotalPrice,PricingTermCount,Source_List_Price__c,Pre_Partner_Price__c,Base_Price__c,COLACalculatedPrice__c FROM QuoteLineItem WHERE QuoteId='<q>'"
```
A calc ERROR after your change is a regression to fix, not a pass. After fixing, also re-reprice **one or two known-good PASS controls** in the same area to confirm you did not regress them.


---

## Your defects — fix specs

> K-01 and F-12 are the SAME fix (null-safe the StampBaseFilter). Patch ALL 6 StampBaseFilter instances in one pass: 3 are already patched (lines ~85548/97288/103199), 3 are not (lines ~109595/116513/123420 for the amend/convert path; the cancellation-path instances ~109632/116550/123457). Change `conditionLogic` `(1 OR 2) AND 3 AND 4 AND 5` -> `(1 OR 2) AND 3 AND 4 AND (5 OR 6)` and add criterion 6 = `NetUnitPrice IsNull` to each unpatched instance.

### K-01 — Cancellation reprice hard-aborts on null net — no credit produced  ·  P0 · PROCEDURE-DEFECT · ticket SC-3441

**Exact artifact(s) to edit:**
  - **proc-step** — StampBaseFilter (sequenceNumber=1 inside StampContributorBasePreDiscount) — cancellation-path instances at expressionSetDefinition lines ~109632, ~116550, ~123457 in V21 design 9QBWC0000000oWH4AY; conditionLogic '(1 OR 2) AND 3 AND 4 AND 5' with criterion #5 = 'NetUnitPrice GreaterThan 0'; runtime ESV 9QMWC00000025LN4AY (VersionNumber 21). NOTE: 3 other instances (lines ~85590/97330/103241) were partially patched 2026-06-30T05:56 but the runtime was never recompiled — all 6 instances require verification and the runtime must be recompiled via full deactivate+deploy+reactivate.

**Deploy mechanism:** In-place edit to V21 ExpressionSetDefinition 9QBWC0000000oWH4AY (no new version). Edit expressionSetDefinition-meta.xml: for each of the 3 cancellation-path StampBaseFilter instances (lines ~109632, ~116550, ~123457) change conditionLogic from '(1 OR 2) AND 3 AND 4 AND 5' to '(1 OR 2) AND 3 AND 4 AND (5 OR 6)' and add criterion #6 'NetUnitPrice IsNull'. Confirm all 3 already-patched instances (lines ~85590/97330/103241) are also null-safe. Deploy: deactivate V21, deploy via sf project deploy start --metadata-dir with api 67, then reactivate from the Versions list (NOT the canvas save) to recompile the runtime. Reactivating from Versions is mandatory — the 2026-06-30T05:56 in-place edit did NOT recompile the runtime (ESV still executes the pre-fix frozen compile, so reprice still errors).

**Expected behavior:** NetUnitPrice = asset net (e.g. 3000); TotalPrice = net × −1 = −3000; header rolls up the negative credit.

**Observed (live, this validation):** Reprice ERRORS at StampBaseFilter#1 (SF-Pricing-00006 / SF-BRE-00004); cancel QLI (CancelNetUnitPrice__c=15000) stays NetUnitPrice=null, TotalPrice=0, CalculationStatus=PriceCalculationFailed. Reproduced on 3 records incl. a fresh one.

**Responsible step / root cause:** StampBaseFilter (in StampContributorBasePreDiscount): criterion #5 ‘NetUnitPrice GreaterThan 0’ has no IsNull guard; condition logic ‘(1 OR 2) AND 3 AND 4 AND 5’ cannot evaluate GreaterThan on a null net → SF-BRE-00004 aborts the entire reprice.

**Fix to implement (NOT yet applied):** Add an IsNull guard to criterion #5 (e.g. ‘(1 OR 2) AND 3 AND 4 AND (5 OR NetUnitPrice IsNull)’), or exclude cancel lines via QuoteTypeText__c before the filter.

**Implementation detail (from artifact pin):** The V21 StampBaseFilter step (seq=1 inside StampContributorBasePreDiscount) contains criterion #5 'NetUnitPrice GreaterThan 0' under condition logic '(1 OR 2) AND 3 AND 4 AND 5'. The SF rules engine cannot evaluate GreaterThan on a null operand, so it aborts with SF-BRE-00004 for any fresh cancel line where NetUnitPrice=null, preventing CancelLineCreditPosthook from ever seeding the credit from CancelNetUnitPrice__c. Fix: in V21 design 9QBWC0000000oWH4AY, add an IsNull guard for NetUnitPrice as a new criterion #6 and update the condition logic to '(1 OR 2) AND 3 AND 4 AND (5 OR 6)' in all 3 cancellation-path StampBaseFilter instances (expressionSetDefinition lines ~109632, ~116550, ~123457). The 3 previously-patched instances (lines ~85590/97330/103241) should be verified as already null-safe. After deploying, reactivate V21 from the Versions list (not canvas) to recompile the runtime. Verify by force-repricing cancel quote 0Q0WC000003FoMA0A0 (QLI 0QLWC000003kySU4AY, CancelNetUnitPrice__c=15000, Qty=-1) and confirming isSuccess=true, NetUnitPrice=15000, TotalPrice=-15000, CalculationStatus=CompletedWithPricing. NOT APPLIED.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FoMA0A0/view

---

> Fixed together with K-01 (same StampBaseFilter null-safety). After null-safing the filter, also confirm the amend(qty<0) line produces a prorated negative delta (route through TermDefined proration so PTC multiplies the negative net); if it still nets full/zero, that proration routing is a follow-on within the same step family.

### F-12 — Mid-term amend-remove aborts — no prorated negative delta  ·  P1 · PROCEDURE-DEFECT · ticket SC-3441

**Exact artifact(s) to edit:**
  - **proc-step** — StampBaseFilter inside StampContributorBasePreDiscount — 3 unpatched instances at expressionSetDefinition-meta.xml lines ~109595, ~116513, ~123420 (V21 ESDV 9QBWC0000000oWH4AY). Each instance: conditionLogic '(1 OR 2) AND 3 AND 4 AND 5', criterion 5 = NetUnitPrice GreaterThan 0. Change conditionLogic to '(1 OR 2) AND 3 AND 4 AND (5 OR 6)' and add criterion 6 (NetUnitPrice IsNull), matching the already-patched instances at lines ~85548, ~97288, ~103199.

**Deploy mechanism:** in-place V21 proc deploy (MDAPI --metadata-dir, api 67, target -o FortraUAT) + reactivate from Versions list (deactivate current active V21, deploy, reactivate). No new version — edit ESDV 9QBWC0000000oWH4AY in place only.

**Expected behavior:** Credit = removed qty × net × remaining-term fraction (e.g. remove 50 of 100 at 6/12 months → −(50 × net × 0.5)).

**Observed (live, this validation):** Force-reprice isSuccess=false, SF-BRE-00004 at StampBaseFilter#1; QLI Qty=−50000, NetUnitPrice=null, TotalPrice=0, PricingTermCount=null. No proration delta.

**Responsible step / root cause:** Same null-unsafe StampBaseFilter as K-01; 3 of 6 instances (block lines ~109632 / 116550 / 123457) still carry ‘(1 OR 2) AND 3 AND 4 AND 5’ with criterion 5 = NetUnitPrice > 0; the amend/cancel path hits an unpatched one and aborts before the seed step runs.

**Fix to implement (NOT yet applied):** Null-safe all remaining StampBaseFilter instances (add a NetUnitPrice IsNull criterion + matching condition logic), and route Amend(qty<0) lines through TermDefined proration so PTC multiplies the negative net.

**Implementation detail (from artifact pin):** In the live V21 expressionSetDefinition-meta.xml (Rev_Mgmt_Default_Pricing_Procedure, ESDV 9QBWC0000000oWH4AY), three StampBaseFilter step instances in the amendment/convert block path (lines ~109595, ~116513, ~123420) still have conditionLogic '(1 OR 2) AND 3 AND 4 AND 5' where criterion 5 is 'NetUnitPrice GreaterThan 0'. On a fresh amend-remove line NetUnitPrice is null, causing SF-BRE-00004 to abort repricing before AmendSeedNetUnit can seed the value. The fix is to add criterion 6 (NetUnitPrice IsNull) to each of those three instances and change conditionLogic to '(1 OR 2) AND 3 AND 4 AND (5 OR 6)', exactly matching the patch already applied to the other three StampBaseFilter instances (lines ~85548, ~97288, ~103199). Verify by force-repricing Amendment quote 0Q0WC000003FapR0AS (QLI 0QLWC000003kkKf4AI, Qty=-50000, CancelNetUnitPrice__c=1.5): reprice must return isSuccess=true with NetUnitPrice populated and NetTotalPrice < 0.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FapR0AS/view

---

### G-01 — Currency ‘Unit Price Display’ step double-applies FX  ·  P0 · PROCEDURE-DEFECT · ticket SC-3384

**Exact artifact(s) to edit:**
  - **proc-step** — ExpressionSetDefinitionVersion 9QBWC0000000oWH4AY (V21, Active) — step 'Currency Conversion - Unit Price Display' (name=CurrencyConversionUnitPriceDisplay, sequenceNumber=40, arrayIndex=38). The formula-section-0-input parameter currently reads: InputUnitPrice * IF(STICurrencyIsoCode='EUR',0.9346,...,1.0). The formula-section-0-output parameter writes back to: InputUnitPrice. Fix: change formula-section-0-input to read NetUnitPrice instead of InputUnitPrice (i.e. NetUnitPrice * IF(STICurrencyIsoCode='EUR',0.9346,...,1.0)), so the display field derives from the freshly-computed net base each run rather than the persisted stale UnitPrice.

**Deploy mechanism:** In-place V21 proc edit via RLM canvas (FortraUAT) + activate from Versions list (do NOT create a new version). Only one work-stream may hold the canvas at a time; coordinate with K-01, F-12, F-09, G-02, J-06 which all edit the same ESDV 9QBWC0000000oWH4AY.

**Expected behavior:** The persisted UnitPrice equals the per-ISO converted unit price once (e.g. 1575 USD × 0.9346 = 1471.995 EUR).

**Observed (live, this validation):** QLI 0QLWC000003kmG14AI (AAM Perpetual EUR): NetUnitPrice/NetTotalPrice/TotalLineAmount/TotalPrice = 1471.995 ALL correct, but UnitPrice is FX-applied a second time. Net channel correct; display channel wrong.

**Responsible step / root cause:** Currency Conversion – Unit Price Display (seq 40 / array-index 38): output UnitPrice = InputUnitPrice × IF(ISO=EUR,0.9346,…), but InputUnitPrice is already the currency-converted value carried in from the net steps.

**Fix to implement (NOT yet applied):** Source the Unit-Price-Display input from the pre-currency base (Base_Price__c / Source_List_Price__c = 1575 USD) so it converts once, OR assign UnitPrice = NetUnitPrice after the net currency steps.

**Implementation detail (from artifact pin):** In the active V21 pricing procedure (ESDV 9QBWC0000000oWH4AY), open the 'Currency Conversion - Unit Price Display' step (sequenceNumber=40, name=CurrencyConversionUnitPriceDisplay). The formula-section-0-input currently is 'InputUnitPrice * IF(STICurrencyIsoCode=\'EUR\',0.9346,...)'; because InputUnitPrice is NOT re-seeded from base for plain Perpetual lines (the only writers — AttributeValuePricingCalculatedMode, GSAPricing, etc. — are gated off), it carries the previous run's already-converted value and compounds the FX multiplier on every reprice. Change the input variable from InputUnitPrice to NetUnitPrice (which IS rebuilt from scratch each run via ResetNetToPrePartnerBase + CurrencyConversionNetUnitPrice), so the formula becomes 'NetUnitPrice * IF(STICurrencyIsoCode=\'EUR\',0.9346,...)' with output still mapped to InputUnitPrice (the persisted UnitPrice field). After deploying and repricing the evidence QLI 0QLWC000003kmG14AI on Quote 0Q0WC000003FcrF0AS (EUR, AAM Perpetual Qty=1), verify UnitPrice=1471.995 (= 1575 × 0.9346) and that a second Force-reprice leaves UnitPrice at 1471.995 rather than descending further.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003kmG14AI/view

---

### F-09 — Non-USD partner net double-converted (corporate FX × hardcoded FX) — NEW regression  ·  P1 · PROCEDURE-DEFECT · ticket SC-3384 · ⚠ NEW REGRESSION (from the 2026-06-30 05:56Z in-place edit)

**Exact artifact(s) to edit:**
  - **proc-step** — Rev Mgmt Default Pricing V21 (ESDV 9QBWC0000000oWH4AY, versionNumber 21, Active) — step 'Sync InputUnitPrice from Net' (name: SyncInputUnitPricefromNet, sequenceNumber 2, parent: SyncInputUnitPriceforDiscountBase sequenceNumber 13): AssignmentElement that writes InputUnitPrice = NetUnitPrice unconditionally. For non-USD partner lines, NetUnitPrice at this point holds the platform org-corporate-rate-converted value (e.g. USD 5900 × org-EUR 0.92 = 5428), not the EUR PBE catalog value (5514.14 = 5900 × 0.9346). The fix must change this assignment to source from ListPrice (already correctly set by the PBE lookup to the EUR PBE value) instead of NetUnitPrice for non-USD lines, or add a CurrencyIsoCode guard so the step fires only when CurrencyIsoCode = 'USD' (letting non-USD lines carry ListPrice as their discount base). No other steps need changing — CurrencyConversionNetUnitPrice (seq 39) correctly applies the hardcoded FX to NetUnitPrice at the end.

**Deploy mechanism:** In-place edit to V21 proc canvas (deactivate V21, edit SyncInputUnitPricefromNet assignment to source ListPrice instead of NetUnitPrice for non-USD lines, reactivate from Versions list using ESDV 9QBWC0000000oWH4AY). Deploy via sf CLI api 67 + --metadata-dir MDAPI format, or direct canvas edit then Activate from the Versions list — NOT by creating a new version. Only one work-stream may hold the proc canvas at a time.

**Expected behavior:** Net = currency-converted list × (1 − partner%), single FX (Cobalt Strike EUR: 5514.14 × 0.82 = 4521.59).

**Observed (live, this validation):** Net = 4159.87 = (5900 × 0.92) × 0.82 × 0.9346 — understated ~8%. USD partner control (E-02) correct. This quote PASSed in run-1 at 01:47Z; V21 LastModified 05:56Z (in-place edit) → now FAILs → confirmed regression.

**Responsible step / root cause:** On non-USD partner lines, the partner-discount base (Pre_Partner_Price__c) is computed as USD_list × corporate rate (0.92) BEFORE the discount, and the proc ALSO applies its single hardcoded EUR FX (CurrencyConversionNetUnitPrice seq 35, ×0.9346) at the end — a double conversion.

**Fix to implement (NOT yet applied):** Operate the partner discount on the raw USD list (the same base the non-partner EUR path uses) and let the single intended EUR FX step apply once; remove the corporate-rate pre-conversion from the partner base.

**Implementation detail (from artifact pin):** In V21 (ESDV 9QBWC0000000oWH4AY), locate the 'Sync InputUnitPrice for Discount Base' container (sequenceNumber 13) and its child assignment step 'Sync InputUnitPrice from Net' (SyncInputUnitPricefromNet, seq 2 within that container). The step currently assigns InputUnitPrice = NetUnitPrice unconditionally; on non-USD quotes this picks up a platform-org-rate-converted USD value (5900 × 0.92 = 5428 EUR) rather than the EUR PBE catalog price (5514.14 = 5900 × 0.9346). The fix is to change the source of the InputUnitPrice assignment from NetUnitPrice to ListPrice for non-USD partner lines — either by swapping the section-0-input1 parameter to ListPrice, or by adding an advancedCondition filter that restricts the step to CurrencyIsoCode = 'USD' lines only (leaving non-USD lines with InputUnitPrice = ListPrice, which is already correctly set by the PBE lookup). After deploying and reactivating V21, force-reprice EUR partner quote 0Q0WC000003AaoT0AS and verify: Cobalt Strike NetUnitPrice = 4521.5948 (= 5514.14 × 0.82), Advanced Auth Modes NetUnitPrice = 2502.3915 (= 2943.99 × 0.85), VM Analyst NetUnitPrice = 429.916 (= 467.3 × 0.92); USD partner E-02 control (0Q0WC000003FO1u0AG) must remain 301.75 (= 355 × 0.85). NOT APPLIED — scoping only.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003AaoT0AS/view

---

> Decision table `Attribute_Based_Adjustment_Decision_Table` (0lDa50000007BEuEAM) has NO CurrencyIsoCode input column and is treated as READ-ONLY for this fix — implement via the two AttributePricingFilter container gates (add `CurrencyIsoCode Equals USD`) so the ABA step only fires on USD lines (non-USD lines then fall through to the currency-matched PBE list). Remember criteria-by-position renumbering.

### G-02 — Configured (ABA) pricing is currency-blind — USD override leaks into an EUR line  ·  P0 · PROCEDURE-DEFECT · ticket SC-3384

**Exact artifact(s) to edit:**
  - **proc-step** — ExpressionSetDefinitionVersion 9QBWC0000000oWH4AY (V21, Active) — step 'Attribute Pricing Filter' (name=AttributePricingFilter, sequenceNumber=1, inside ListContainer name=ListContainer sequenceNumber=4). Current conditionLogic: '1 AND 2 AND 3 AND 4' (criteria: ItemContractAttributePasId IsNotNull, ItemPricingSource NotEquals 'LastTransaction', DerivedPricingAttribute IsNotNull, DerivedPricingAttribute Equals false). Fix: add criterion 5 (CurrencyIsoCode Equals 'USD') and change conditionLogic to '1 AND 2 AND 3 AND 4 AND 5', so the Attribute-Based Price step (AttributeBasedPrice, seq=2 in same ListContainer) only fires for USD quote lines. Non-USD lines fall through to the currency-matched PBE UnitPrice (already EUR 2943.99 from the Price Book Entries step at seq=3).
  - **proc-step** — ExpressionSetDefinitionVersion 9QBWC0000000oWH4AY (V21, Active) — step 'Attribute Pricing Filter' (name=AttributePricingFilter8, sequenceNumber=1, inside ListContainer name=ListContainer7 sequenceNumber=5). Current conditionLogic: '(1 OR 2) AND 3' (criteria: IsContracted IsNull, IsContracted Equals false, ItemPricingSource NotEquals 'LastTransaction'). Fix: add criterion 4 (CurrencyIsoCode Equals 'USD') and change conditionLogic to '(1 OR 2) AND 3 AND 4' so the Attribute Discount Entries step (AttributeDiscountEntries, seq=2 in ListContainer7) also only fires for USD lines.
  - **decision-table** — DecisionTable Id=0lDa50000007BEuEAM, DeveloperName=Attribute_Based_Adjustment_Decision_Table (MasterLabel='Decision Tables', setupName='Attribute Discount Entries'). The 6 INPUT columns are PriceAdjustmentScheduleId, ProductId, ProductSellingModelId, EffectiveFrom, EffectiveTo, AttributeAdjConditionsHash — NO CurrencyIsoCode input column. This is confirmed read-only scope for this ticket; the proc-filter approach avoids requiring a DT schema change. If future work adds non-USD ABA rows, CurrencyIsoCode must be added as a 7th INPUT column and the conditionCriteria updated from '1 AND 2 AND 3 AND 4 AND 5 AND 6' to '1 AND 2 AND 3 AND 4 AND 5 AND 6 AND 7'.

**Deploy mechanism:** In-place V21 proc edit via RLM canvas (FortraUAT) + activate from Versions list (do NOT create a new version). Coordinate with G-01, K-01, F-12, F-09, J-06 which all edit ESDV 9QBWC0000000oWH4AY — only one work-stream may hold the canvas at a time.

**Expected behavior:** Pricing lookups include CurrencyIsoCode in the composite key; non-USD ABA rows + a currency-matched PBE fallback are used; no USD-value leak.

**Observed (live, this validation):** L1 0QLWC000003kmG14AI: Source_List_Price__c=Base_Price__c=1575 (USD ABA Override leaked), EUR ListPrice 2943.99 ignored. Second SFTP combo nets $0 (row active+unapplied, no PBE fallback).

**Responsible step / root cause:** Native RLM Attribute-Based Price step (AttributeBasedAdjustment decision-table lookup) carries no CurrencyIsoCode in its key, so a USD-only Override row matches an EUR line; the EUR PBE list is ignored and some attribute combos collapse to $0.

**Fix to implement (NOT yet applied):** Add CurrencyIsoCode to the ABA decision-table key (or seed non-USD override rows) so a USD override cannot match a non-USD line; add a no-match fallback returning the currency-matched PBE list.

**Implementation detail (from artifact pin):** In the active V21 pricing procedure (ESDV 9QBWC0000000oWH4AY), add a CurrencyIsoCode=USD gate to both ABA container filters. (1) Open 'Attribute Pricing Filter' (name=AttributePricingFilter, seq=1 inside ListContainer seq=4): add criterion 5 = CurrencyIsoCode Equals 'USD' and change conditionLogic from '1 AND 2 AND 3 AND 4' to '1 AND 2 AND 3 AND 4 AND 5'. This prevents the Attribute-Based Price step from matching USD-only ABA override rows for EUR quote lines. (2) Apply the same CurrencyIsoCode Equals 'USD' criterion to 'Attribute Pricing Filter' (name=AttributePricingFilter8, seq=1 inside ListContainer7 seq=5), changing its conditionLogic from '(1 OR 2) AND 3' to '(1 OR 2) AND 3 AND 4'. (3) Optionally — or as a follow-on — add a fallback assignment step after each ABA container that sets NetUnitPrice from the PBE UnitPrice when the ABA step produced no match (NetUnitPrice=0), addressing the L2/$0 no-fallback defect which also affects the USD SFTP line. Verify by force-repricing Quote 0Q0WC000003FcrF0AS (EUR, AAMP): L1 QLI 0QLWC000003kmG14AI must show Source_List_Price__c=null and NetUnitPrice=2943.99 EUR (PBE fallback, no ABA override applied); L2 QLI 0QLWC000003kmG24AI must also show NetUnitPrice=2943.99 EUR if fallback is added, else remains at $0 (acceptable if L2 is deferred). USD control QLI 0QLWC000003l1tO4AQ must still show NetUnitPrice=1575 (ABA override still applied in USD).

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FcrF0AS/view

---

> NOTE: an earlier verifier mis-flagged I-03 as BLOCKED ("the proration leg already exists"). The tie-breaker DISPROVED that on live data: a CLEAN list-priced TermDefined line `0QLWC000002LCwH4AW` (PTC=0.7397) comes out FULL 750 on BOTH NetTotalPrice and TotalLineAmount, while only the discounted/adjustment line `0QLWC0000034VY94AM` prorates (3170.71). So the proration multiply (SubscriptionPricing95 / ListContainer93) exists but only fires on the adjustment path. **First reproduce this with a fresh UI-built mid-term TermDefined line, confirm via the explainability trace which leg drops the multiply on the plain list-priced path, THEN gate the proration multiply on SellingModelType=TermDefined regardless of whether an adjustment is present.**

### I-03 — Mid-term Term-Defined net not prorated by fractional PTC (plain list-priced path)  ·  P1 · PROCEDURE-DEFECT · ticket SC-3420 / SC-3411

**Exact artifact(s) to edit:**
  - **other** — QuoteLineItem stale test data — lines 0QLWC000002LCwH4AW and 0QLWC000002SYdV4AW on stale quotes; retire and replace with a fresh UI-built mid-term TermDefined line

**Deploy mechanism:** No deploy. Retire stale proof lines. Re-test by adding a fresh mid-term TermDefined product via the Configure Products UI on a new Quote, repricing once via the UI or REST v67 reprice endpoint, then reading TotalLineAmount (not NetTotalPrice) from the resulting QuoteLineItem to verify PTC fractional multiplication.

**Expected behavior:** Mid-term annual line: PTC=0.7397 (270/365) → NetTotalPrice = 250 × 3 × 0.7397 = 554.79.

**Observed (live, this validation):** Clean list-priced line 0QLWC000002LCwH4AW: PTC=0.7397 derived, but NetTotalPrice AND TotalLineAmount both come out FULL = 750, stable across 3 reprices. The discounted sibling 0QLWC0000034VY94AM DOES prorate (3170.71 = 3465 × 0.9151) — proration only fires on the adjustment path.

**Responsible step / root cause:** The TermDefined net-proration leg (SubscriptionPricing95 / ListContainer93) prorates only the adjustment/discounted path; a plain list-priced TermDefined line derives the fractional PTC but never multiplies the net by it. (Confirmed by tie-breaker against the original ‘no writer exists’ mis-diagnosis.)

**Fix to implement (NOT yet applied):** Ensure the net×PTC multiply applies to non-adjustment (plain list-priced) TermDefined lines too — gate the proration leg on SellingModelType=TermDefined regardless of whether a discount/adjustment is present.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000002LCwH4AW/view

---

> NOTE: E-04 has TWO parts that MUST land together (V2 prehook falls back to 0% on null Non_Orig data, which would BREAK partner pricing): (a) re-point the V21 plan Apex hook from `PartnerPricingPrehook` to `PartnerPricingPrehookV2` (already deployed in the org) — this is the only Apex/plan part of your proc edit; (b) populate `Non_Orig_Software_Pct__c / Non_Orig_Subscription_Pct__c / Non_Orig_New_Maint_Pct__c / Non_Orig_Ren_Maint_Pct__c / Non_Orig_Services_Pct__c` on all 30 `Partner_Pricing_Model__c` rows from the Fortra partner tier schedule (currently all null). Verify with a Deal_Type=`Fortra Originated` partner quote: the Non_Orig band must apply, distinct from the Channel band.

### E-04 — Fortra-Originated partner deals get the channel band, not Non_Orig  ·  P1 · ORG-CONFIG-DEFECT

**Exact artifact(s) to edit:**
  - **apex-class** — PartnerPricingPrehook — execute() / processLineItems() / buildPartnerPercentStampUpdate(): currently wired into V21 procedure plan as the active prehook; reads only PartnerPricingService.resolveTotalPartnerPercent() (channel columns, no dealType arg). Must be replaced by wiring PartnerPricingPrehookV2 into the procedure plan instead.
  - **apex-class** — PartnerPricingPrehookV2 — execute() / processLineItem(): dormant class already present in org; reads PartnerPricingServiceV2.getMarginForProductType(model, productType, dealType) which routes to Non_Orig_* columns when dealType='Fortra Originated'. No code change needed to this class — it must be activated by wiring into the V21 procedure plan.
  - **pricebook-entry** — Partner_Pricing_Model__c — Non_Orig_Software_Pct__c, Non_Orig_Subscription_Pct__c, Non_Orig_New_Maint_Pct__c, Non_Orig_Ren_Maint_Pct__c, Non_Orig_Services_Pct__c fields on all 30 active PPM rows (currently null on all 30, SOQL COUNT=0). Must be populated per Fortra partner tier schedule for Non-Originating deals.
  - **ppm-config** — V21 ExpressionSet ProcedurePlan step that references PartnerPricingPrehook (V1) as the Apex processor — must be re-pointed to PartnerPricingPrehookV2. This is an in-place edit to ESDV 9QBWC0000000oWH4AY (the single active V21 version); no new procedure version should be created.

**Deploy mechanism:** Two-part deploy: (1) Re-point the V21 procedure plan Apex hook from PartnerPricingPrehook to PartnerPricingPrehookV2 via in-place edit to ESDV 9QBWC0000000oWH4AY, then deactivate and reactivate V21 from the Versions list (not canvas). PartnerPricingPrehookV2 is already deployed in the org — no Apex class deploy needed. (2) REST/Bulk data update: populate Non_Orig_Software_Pct__c / Non_Orig_Subscription_Pct__c / Non_Orig_New_Maint_Pct__c / Non_Orig_Ren_Maint_Pct__c / Non_Orig_Services_Pct__c on all 30 Partner_Pricing_Model__c records using the Fortra partner tier schedule. Both parts must land before verification.

**Expected behavior:** Net = List × (1 − Non_Orig_Discount%); a lower discount than channel-originated (e.g. 12% vs 15%).

**Observed (live, this validation):** Quote 0Q0WC0000039bwH0AQ (Deal_Type=‘Fortra Originated’): BoKS Perpetual net = 301.75 = 355 × 0.85 (15% channel column). Deal_Type has zero effect; all 30 Partner_Pricing_Model rows have null Non_Orig_* columns.

**Responsible step / root cause:** Active prehook PartnerPricingPrehook V1 calls getMarginForProductType(model, productType) with no dealType argument (reads channel columns only); the Deal_Type→Non_Orig routing exists only in the dormant V2 service.

**Fix to implement (NOT yet applied):** Wire the Deal_Type-aware V2 prehook into the active plan (or pass dealType in V1) AND populate the Non_Orig_* columns on the 30 PPM rows.

**Implementation detail (from artifact pin):** The active V21 prehook (PartnerPricingPrehook, V1) calls PartnerPricingService.resolveTotalPartnerPercent() with no dealType argument and unconditionally reads the channel (Software_Percent__c) column; the dormant PartnerPricingPrehookV2 already calls PartnerPricingServiceV2.getMarginForProductType(model, productType, dealType), which routes to Non_Orig_* columns when dealType='Fortra Originated'. Step 1: in-place edit ESDV 9QBWC0000000oWH4AY to swap the Apex processor reference from PartnerPricingPrehook to PartnerPricingPrehookV2, then reactivate from the Versions list. Step 2: populate Non_Orig_Software_Pct__c, Non_Orig_Subscription_Pct__c, Non_Orig_New_Maint_Pct__c, Non_Orig_Ren_Maint_Pct__c, Non_Orig_Services_Pct__c on all 30 PPM rows per the Fortra Non-Originating tier schedule (data load via REST or Bulk API). Verify by force-repricing Quote 0Q0WC0000039bwH0AQ (BoKS Perpetual, Deal_Type__c='Fortra Originated', PPM-00028): QLI 0QLWC000003eoAr4AI NetUnitPrice should equal 355 × (1 - Non_Orig_Software_Pct__c/100) rather than 301.75; Partner_Pricing_Source__c should shift from 'System Calculated (Pre-Procedure, Percent Only)' to 'System Calculated'.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000039bwH0AQ/view

---

## Cross-portion coordination (read before you start)

- **You are the sole editor of the V21 procedure.** Batch ALL your proc changes (K-01/F-12 filter, G-01 formula input, F-09 assignment, G-02 filter gates, I-03 proration gate, E-04 prehook re-point) into ONE metadata change, then ONE deactivate->deploy->reactivate. Do not do six separate deploy cycles (each re-activation is a clobber risk).
- **Portions 2 & 3 reprice against the live V21 to verify their own fixes.** While V21 is deactivated or mid-deploy, their verification will fail. Announce when V21 is stable again so they can verify. Keep the deactivation window short.
- **Partner overlap with Portion 2 (J-06):** your E-04 re-points the partner *prehook* (V1->V2); Portion 2 edits the partner *posthook* (`PartnerNetPricePosthook`). Different classes, but both affect partner net — once both land, re-verify a partner quote end-to-end.
- Do NOT touch: `PartnerNetPricePosthook` (Portion 2), `ProductAttributeDefinition` / `CurrencyType` (Portion 2), `PriceBookEntry*` derived data (Portion 3).

## Definition of done

- All 7 defects: re-reprice each evidence record through the re-activated V21 and confirm the target field now resolves to the expected value (no SF-BRE-00004 abort for K-01/F-12; UnitPrice single-FX for G-01; non-USD partner net no longer double-FX'd for F-09; EUR line no longer takes the USD ABA override for G-02; plain list-priced TermDefined net prorated by fractional PTC for I-03; Fortra-Originated partner takes the Non_Orig band for E-04).
- Re-retrieve V21 metadata post-activation to confirm no canvas-clobber revert.
- Re-reprice 3-4 known-good PASS controls (e.g. a USD direct line, a USD partner line E-02, a BoKS derived demo quote) to confirm no regression.
- Document the exact metadata diff + the Non_Orig data values applied. UAT only — do NOT deploy to prod.