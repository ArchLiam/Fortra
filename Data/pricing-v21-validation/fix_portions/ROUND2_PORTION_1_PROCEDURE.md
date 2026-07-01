# V21 Fix — ROUND 2, PORTION 1 of 3: PROCEDURE (the code fixes)

**Your defects (5):** G-02 [P0], H-01 [P0], F-09 [P1], I-03 [P1], E-04 [P1]

**Surface:** All in-place edits to the active V21 ExpressionSet, batched into ONE deactivate→deploy→reactivate. PLUS E-04 needs a data backfill (Non_Orig_* on the 30 Partner_Pricing_Model__c rows) that must land WITH its prehook re-point.

**Boundary:** You are the ONLY tab that edits the V21 procedure. Portions 2 & 3 do data backfills on different objects and will not touch the proc. NOTE: H-01 and F-09 both edit the "Sync InputUnitPrice from Net" step — do them together coherently.

## Mission
Fix your portion of the STILL-FAILING V21 defects, verify on real data, stop. This is round 2 — after the 2026-06-30 22:01Z in-place V21 edit, a live re-verification found **5 defects fixed** (K-01, F-12, G-01, J-06, J-10 — do NOT touch) and these still failing. One of three parallel work-streams; stay strictly in your portion's artifacts.

## Environment
- **Org = FortraUAT** only (`-o FortraUAT`). NEVER the `uat` alias (different org).
- **Active proc:** Rev_Mgmt_Default_Pricing_Procedure V21 — design `9QAWC0000003mg14AA`, active version `ExpressionSetDefinitionVersion` **9QBWC0000000oWH4AY**, runtime `ExpressionSetVersion` 9QMWC00000025LN4AY, context SalesTransactionContextExt_v2 (v23). LastModified 22:01Z.
- REST reprice API = **v67.0**. Live price book = "Fortra Price Book" `01sWC0000022GHFYA2` (active); "Standard Price Book" is INACTIVE.
- Account "Fortra, LLC - Test" `001WC00000XiZP4YAN`.

## Hard rules
1. Retrieve/measure LIVE first (repo drifts); get a before/after.
2. **In-place V21 ONLY — no new versions (no V22).**
3. **RLM canvas re-save CLOBBERS metadata deploys:** after any proc deploy, close ALL canvas tabs, Activate from Setup → Pricing Procedures → **Versions list** (not from a canvas editor), then re-retrieve to confirm no revert BEFORE repricing.
4. **AdvancedListFilter criteria are referenced by POSITION 1..N** (not sequenceNumber): renumber survivors contiguously and update conditionLogic to match.
5. Proc deploy: **api 67 + `--metadata-dir` (MDAPI)**; deactivate → deploy → reactivate from Versions list → re-retrieve → reprice-verify.
6. **UAT ONLY — do NOT deploy to production.**
7. **`ValidationResult` string fields don't work in pricing formulas** — use numeric/boolean or an AssignmentElement.

## Reprice + verify recipe
```bash
cat > /tmp/body.json <<'JSON'
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},
 "graph":{"graphId":"1","records":[{"referenceId":"ref1",
   "record":{"attributes":{"type":"Quote","method":"PATCH","id":"<RECORD_ID>"}}}]}}
JSON
sf api request rest "/services/data/v67.0/connect/rev/sales-transaction/actions/place" --method POST -o FortraUAT --body "$(cat /tmp/body.json)"
sf data query -o FortraUAT -q "SELECT Id,Quantity,UnitPrice,NetUnitPrice,ListPrice,NetTotalPrice,TotalLineAmount,TotalPrice,PricingTermCount,Source_List_Price__c,Pre_Partner_Price__c,Base_Price__c,PartnerDiscountPercent,COLACalculatedPrice__c FROM QuoteLineItem WHERE QuoteId='<q>'"
```
After fixing, re-reprice a known-good PASS control in the same area to confirm no regression. A calc ERROR after your change is a regression, not a pass.

## Already-excluded false positives (do NOT re-open): D-09 (stale FX field), I-02 (off-by-one EndDate), J-05 (Amend QuoteAction), K-02/K-10 (catalog expectation-errors). Out of scope for Fortra: evergreen + contracted scenarios. G-08 (currency rates) is being handled by the FX-config owner separately — not your job.


---

## Your defect fix specs

### G-02 — Configured (ABA) pricing is currency-blind — USD override leaks into an EUR line  ·  P0 · PROCEDURE-DEFECT · SC-3384

**Verified STILL FAILING (22:01Z, live):** STILL FAILING (22:01Z reprice): EUR line 0QLWC000003kmG14AI Source_List_Price__c=Base_Price__c=1575 (USD ABA override) → Net 1471.995 (=1575×0.9346); EUR PBE list 2943.99 ignored. 2nd combo line Net=$0. EUR PBE valid/active.

**Exact artifact(s):**
  - **proc-step** — ExpressionSetDefinitionVersion 9QBWC0000000oWH4AY (V21, Active) — step 'Attribute Pricing Filter' (name=AttributePricingFilter, sequenceNumber=1, inside ListContainer name=ListContainer sequenceNumber=4). Current conditionLogic: '1 AND 2 AND 3 AND 4' (criteria: ItemContractAttributePasId IsNotNull, ItemPricingSource NotEquals 'LastTransaction', DerivedPricingAttribute IsNotNull, DerivedPricingAttribute Equals false). Fix: add criterion 5 (CurrencyIsoCode Equals 'USD') and change conditionLogic to '1 AND 2 AND 3 AND 4 AND 5', so the Attribute-Based Price step (AttributeBasedPrice, seq=2 in same ListContainer) only fires for USD quote lines. Non-USD lines fall through to the currency-matched PBE UnitPrice (already EUR 2943.99 from the Price Book Entries step at seq=3).
  - **proc-step** — ExpressionSetDefinitionVersion 9QBWC0000000oWH4AY (V21, Active) — step 'Attribute Pricing Filter' (name=AttributePricingFilter8, sequenceNumber=1, inside ListContainer name=ListContainer7 sequenceNumber=5). Current conditionLogic: '(1 OR 2) AND 3' (criteria: IsContracted IsNull, IsContracted Equals false, ItemPricingSource NotEquals 'LastTransaction'). Fix: add criterion 4 (CurrencyIsoCode Equals 'USD') and change conditionLogic to '(1 OR 2) AND 3 AND 4' so the Attribute Discount Entries step (AttributeDiscountEntries, seq=2 in ListContainer7) also only fires for USD lines.
  - **decision-table** — DecisionTable Id=0lDa50000007BEuEAM, DeveloperName=Attribute_Based_Adjustment_Decision_Table (MasterLabel='Decision Tables', setupName='Attribute Discount Entries'). The 6 INPUT columns are PriceAdjustmentScheduleId, ProductId, ProductSellingModelId, EffectiveFrom, EffectiveTo, AttributeAdjConditionsHash — NO CurrencyIsoCode input column. This is confirmed read-only scope for this ticket; the proc-filter approach avoids requiring a DT schema change. If future work adds non-USD ABA rows, CurrencyIsoCode must be added as a 7th INPUT column and the conditionCriteria updated from '1 AND 2 AND 3 AND 4 AND 5 AND 6' to '1 AND 2 AND 3 AND 4 AND 5 AND 6 AND 7'.

**Deploy:** In-place V21 proc edit via RLM canvas (FortraUAT) + activate from Versions list (do NOT create a new version). Coordinate with G-01, K-01, F-12, F-09, J-06 which all edit ESDV 9QBWC0000000oWH4AY — only one work-stream may hold the canvas at a time.

**Expected:** Pricing lookups include CurrencyIsoCode in the composite key; non-USD ABA rows + a currency-matched PBE fallback are used; no USD-value leak.

**Fix (NOT yet applied):** Add CurrencyIsoCode to the ABA decision-table key (or seed non-USD override rows) so a USD override cannot match a non-USD line; add a no-match fallback returning the currency-matched PBE list.

**Implementation detail:** In the active V21 pricing procedure (ESDV 9QBWC0000000oWH4AY), add a CurrencyIsoCode=USD gate to both ABA container filters. (1) Open 'Attribute Pricing Filter' (name=AttributePricingFilter, seq=1 inside ListContainer seq=4): add criterion 5 = CurrencyIsoCode Equals 'USD' and change conditionLogic from '1 AND 2 AND 3 AND 4' to '1 AND 2 AND 3 AND 4 AND 5'. This prevents the Attribute-Based Price step from matching USD-only ABA override rows for EUR quote lines. (2) Apply the same CurrencyIsoCode Equals 'USD' criterion to 'Attribute Pricing Filter' (name=AttributePricingFilter8, seq=1 inside ListContainer7 seq=5), changing its conditionLogic from '(1 OR 2) AND 3' to '(1 OR 2) AND 3 AND 4'. (3) Optionally — or as a follow-on — add a fallback assignment step after each ABA container that sets NetUnitPrice from the PBE UnitPrice when the ABA step produced no match (NetUnitPrice=0), addressing the L2/$0 no-fallback defect which also affects the USD SFTP line. Verify by force-repricing Quote 0Q0WC000003FcrF0AS (EUR, AAMP): L1 QLI 0QLWC000003kmG14AI must show Source_List_Price__c=null and NetUnitPrice=2943.99 EUR (PBE fallback, no ABA override applied); L2 QLI 0QLWC000003kmG24AI must also show NetUnitPrice=2943.99 EUR if fallback is added, else remains at $0 (acceptable if L2 is deferred). USD control QLI 0QLWC000003l1tO4AQ must still show NetUnitPrice=1575 (ABA override still applied in USD).

**Verify:** reprice the evidence record and confirm the field flips to the expected value; re-check a same-area control.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FcrF0AS/view

---

> H-01 & F-09 both edit "Sync InputUnitPrice from Net" (SyncInputUnitPricefromNet). H-01 = re-seed the direct-line discount base from ListPrice (idempotency); F-09 = source the non-USD partner base from ListPrice (not the org-corporate-converted net). Do them as one coherent change to that step + guards.

### H-01 — Manual line-level amount discount compounds across reprices  ·  P0 · PROCEDURE-DEFECT · discount-compounding class (F-07/E-03 family)

**Verified STILL FAILING (22:01Z, live):** STILL FAILING: Quote 0Q0WC000003Fs1Z0AS net erodes across identical reprices 20000→15000→10000 (−5000 each). Non-idempotent discount base — TotalAdjustmentAmount stays −20000 but net keeps dropping.

**Exact artifact(s):**
  - (see fix below)

**Expected:** Net = list − entered amount, stable on every reprice (e.g. 50000 − 5000 = 45000 each time).

**Fix (NOT yet applied):** Re-seed the discount base from ListPrice for direct lines before the manual-amount step (mirror the F-07 ‘Reset Net to Pre-Partner Base’ / E-03 OneTime-seed pattern, extended to the non-partner case).

**Verify:** reprice the evidence record and confirm the field flips to the expected value; re-check a same-area control.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fs1Z0AS/view

---

### F-09 — Non-USD partner net double-converted (corporate FX × hardcoded FX) — NEW regression  ·  P1 · PROCEDURE-DEFECT · SC-3384

**Verified STILL FAILING (22:01Z, live):** STILL FAILING: Quote 0Q0WC000003AaoT0AS Cobalt Strike EUR Net=4159.867216 (=5900×0.92×0.82×0.9346, double FX); Pre_Partner_Price__c=5428 (=USD 5900×0.92). Expected 4521.5948. EUR PBE list 5514.14 valid.

**Exact artifact(s):**
  - **proc-step** — Rev Mgmt Default Pricing V21 (ESDV 9QBWC0000000oWH4AY, versionNumber 21, Active) — step 'Sync InputUnitPrice from Net' (name: SyncInputUnitPricefromNet, sequenceNumber 2, parent: SyncInputUnitPriceforDiscountBase sequenceNumber 13): AssignmentElement that writes InputUnitPrice = NetUnitPrice unconditionally. For non-USD partner lines, NetUnitPrice at this point holds the platform org-corporate-rate-converted value (e.g. USD 5900 × org-EUR 0.92 = 5428), not the EUR PBE catalog value (5514.14 = 5900 × 0.9346). The fix must change this assignment to source from ListPrice (already correctly set by the PBE lookup to the EUR PBE value) instead of NetUnitPrice for non-USD lines, or add a CurrencyIsoCode guard so the step fires only when CurrencyIsoCode = 'USD' (letting non-USD lines carry ListPrice as their discount base). No other steps need changing — CurrencyConversionNetUnitPrice (seq 39) correctly applies the hardcoded FX to NetUnitPrice at the end.

**Deploy:** In-place edit to V21 proc canvas (deactivate V21, edit SyncInputUnitPricefromNet assignment to source ListPrice instead of NetUnitPrice for non-USD lines, reactivate from Versions list using ESDV 9QBWC0000000oWH4AY). Deploy via sf CLI api 67 + --metadata-dir MDAPI format, or direct canvas edit then Activate from the Versions list — NOT by creating a new version. Only one work-stream may hold the proc canvas at a time.

**Expected:** Net = currency-converted list × (1 − partner%), single FX (Cobalt Strike EUR: 5514.14 × 0.82 = 4521.59).

**Fix (NOT yet applied):** Operate the partner discount on the raw USD list (the same base the non-partner EUR path uses) and let the single intended EUR FX step apply once; remove the corporate-rate pre-conversion from the partner base.

**Implementation detail:** In V21 (ESDV 9QBWC0000000oWH4AY), locate the 'Sync InputUnitPrice for Discount Base' container (sequenceNumber 13) and its child assignment step 'Sync InputUnitPrice from Net' (SyncInputUnitPricefromNet, seq 2 within that container). The step currently assigns InputUnitPrice = NetUnitPrice unconditionally; on non-USD quotes this picks up a platform-org-rate-converted USD value (5900 × 0.92 = 5428 EUR) rather than the EUR PBE catalog price (5514.14 = 5900 × 0.9346). The fix is to change the source of the InputUnitPrice assignment from NetUnitPrice to ListPrice for non-USD partner lines — either by swapping the section-0-input1 parameter to ListPrice, or by adding an advancedCondition filter that restricts the step to CurrencyIsoCode = 'USD' lines only (leaving non-USD lines with InputUnitPrice = ListPrice, which is already correctly set by the PBE lookup). After deploying and reactivating V21, force-reprice EUR partner quote 0Q0WC000003AaoT0AS and verify: Cobalt Strike NetUnitPrice = 4521.5948 (= 5514.14 × 0.82), Advanced Auth Modes NetUnitPrice = 2502.3915 (= 2943.99 × 0.85), VM Analyst NetUnitPrice = 429.916 (= 467.3 × 0.92); USD partner E-02 control (0Q0WC000003FO1u0AG) must remain 301.75 (= 355 × 0.85). NOT APPLIED — scoping only.

**Verify:** reprice the evidence record and confirm the field flips to the expected value; re-check a same-area control.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003AaoT0AS/view

---

### I-03 — Mid-term Term-Defined net not prorated by fractional PTC (plain list-priced path)  ·  P1 · PROCEDURE-DEFECT · SC-3420 / SC-3411

**Verified STILL FAILING (22:01Z, live):** STILL FAILING: QLI 0QLWC000002LCwH4AW PricingTermCount=0.7397260273972603 (correct), but NetTotalPrice=TotalLineAmount=750 (full, not prorated 554.79). Real UI-built line.

**Exact artifact(s):**
  - **other** — QuoteLineItem stale test data — lines 0QLWC000002LCwH4AW and 0QLWC000002SYdV4AW on stale quotes; retire and replace with a fresh UI-built mid-term TermDefined line

**Deploy:** No deploy. Retire stale proof lines. Re-test by adding a fresh mid-term TermDefined product via the Configure Products UI on a new Quote, repricing once via the UI or REST v67 reprice endpoint, then reading TotalLineAmount (not NetTotalPrice) from the resulting QuoteLineItem to verify PTC fractional multiplication.

**Expected:** Mid-term annual line: PTC=0.7397 (270/365) → NetTotalPrice = 250 × 3 × 0.7397 = 554.79.

**Fix (NOT yet applied):** Ensure the net×PTC multiply applies to non-adjustment (plain list-priced) TermDefined lines too — gate the proration leg on SellingModelType=TermDefined regardless of whether a discount/adjustment is present.

**Verify:** reprice the evidence record and confirm the field flips to the expected value; re-check a same-area control.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000002LCwH4AW/view

---

> E-04 has TWO parts that MUST land together (V2 prehook falls back to 0% on null Non_Orig → would BREAK partner pricing): (a) re-point the V21 plan Apex hook from `PartnerPricingPrehook` to `PartnerPricingPrehookV2` (already deployed) — the only Apex/plan part of your proc edit; (b) populate Non_Orig_Software_Pct__c / Non_Orig_Subscription_Pct__c / Non_Orig_New_Maint_Pct__c / Non_Orig_Ren_Maint_Pct__c / Non_Orig_Services_Pct__c on all 30 Partner_Pricing_Model__c rows (confirmed 0/30 set). Verify on the Fortra-Originated quote 0Q0WC0000039bwH0AQ.

### E-04 — Fortra-Originated partner deals get the channel band, not Non_Orig  ·  P1 · ORG-CONFIG-DEFECT

**Verified STILL FAILING (22:01Z, live):** STILL FAILING: Quote 0Q0WC0000039bwH0AQ BoKS Perpetual Net=301.75 (=355×0.85 CHANNEL 15% band); Deal_Type=Fortra Originated ignored. CONFIRMED 0 of 30 Partner_Pricing_Model__c rows have Non_Orig_Software_Pct__c populated.

**Exact artifact(s):**
  - **apex-class** — PartnerPricingPrehook — execute() / processLineItems() / buildPartnerPercentStampUpdate(): currently wired into V21 procedure plan as the active prehook; reads only PartnerPricingService.resolveTotalPartnerPercent() (channel columns, no dealType arg). Must be replaced by wiring PartnerPricingPrehookV2 into the procedure plan instead.
  - **apex-class** — PartnerPricingPrehookV2 — execute() / processLineItem(): dormant class already present in org; reads PartnerPricingServiceV2.getMarginForProductType(model, productType, dealType) which routes to Non_Orig_* columns when dealType='Fortra Originated'. No code change needed to this class — it must be activated by wiring into the V21 procedure plan.
  - **pricebook-entry** — Partner_Pricing_Model__c — Non_Orig_Software_Pct__c, Non_Orig_Subscription_Pct__c, Non_Orig_New_Maint_Pct__c, Non_Orig_Ren_Maint_Pct__c, Non_Orig_Services_Pct__c fields on all 30 active PPM rows (currently null on all 30, SOQL COUNT=0). Must be populated per Fortra partner tier schedule for Non-Originating deals.
  - **ppm-config** — V21 ExpressionSet ProcedurePlan step that references PartnerPricingPrehook (V1) as the Apex processor — must be re-pointed to PartnerPricingPrehookV2. This is an in-place edit to ESDV 9QBWC0000000oWH4AY (the single active V21 version); no new procedure version should be created.

**Deploy:** Two-part deploy: (1) Re-point the V21 procedure plan Apex hook from PartnerPricingPrehook to PartnerPricingPrehookV2 via in-place edit to ESDV 9QBWC0000000oWH4AY, then deactivate and reactivate V21 from the Versions list (not canvas). PartnerPricingPrehookV2 is already deployed in the org — no Apex class deploy needed. (2) REST/Bulk data update: populate Non_Orig_Software_Pct__c / Non_Orig_Subscription_Pct__c / Non_Orig_New_Maint_Pct__c / Non_Orig_Ren_Maint_Pct__c / Non_Orig_Services_Pct__c on all 30 Partner_Pricing_Model__c records using the Fortra partner tier schedule. Both parts must land before verification.

**Expected:** Net = List × (1 − Non_Orig_Discount%); a lower discount than channel-originated (e.g. 12% vs 15%).

**Fix (NOT yet applied):** Wire the Deal_Type-aware V2 prehook into the active plan (or pass dealType in V1) AND populate the Non_Orig_* columns on the 30 PPM rows.

**Implementation detail:** The active V21 prehook (PartnerPricingPrehook, V1) calls PartnerPricingService.resolveTotalPartnerPercent() with no dealType argument and unconditionally reads the channel (Software_Percent__c) column; the dormant PartnerPricingPrehookV2 already calls PartnerPricingServiceV2.getMarginForProductType(model, productType, dealType), which routes to Non_Orig_* columns when dealType='Fortra Originated'. Step 1: in-place edit ESDV 9QBWC0000000oWH4AY to swap the Apex processor reference from PartnerPricingPrehook to PartnerPricingPrehookV2, then reactivate from the Versions list. Step 2: populate Non_Orig_Software_Pct__c, Non_Orig_Subscription_Pct__c, Non_Orig_New_Maint_Pct__c, Non_Orig_Ren_Maint_Pct__c, Non_Orig_Services_Pct__c on all 30 PPM rows per the Fortra Non-Originating tier schedule (data load via REST or Bulk API). Verify by force-repricing Quote 0Q0WC0000039bwH0AQ (BoKS Perpetual, Deal_Type__c='Fortra Originated', PPM-00028): QLI 0QLWC000003eoAr4AI NetUnitPrice should equal 355 × (1 - Non_Orig_Software_Pct__c/100) rather than 301.75; Partner_Pricing_Source__c should shift from 'System Calculated (Pre-Procedure, Percent Only)' to 'System Calculated'.

**Verify:** reprice the evidence record and confirm the field flips to the expected value; re-check a same-area control.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000039bwH0AQ/view

---

## Cross-portion coordination
- You are the sole editor of the V21 procedure — batch ALL your proc changes (G-02 filters, H-01+F-09 Sync step, I-03 proration gate, E-04 re-point) into ONE deactivate→deploy→reactivate.
- Portions 2 & 3 reprice against live V21 to verify; keep your deactivation window short and announce when V21 is stable.
- Do NOT touch PriceBookEntryDerivedPrice (P2) or ProductAttributeDefinition (P3).

## Definition of done
All 5: reprice each evidence record and confirm the fix (G-02 EUR line no longer takes USD 1575, no $0 combo; H-01 net stable across ≥3 reprices; F-09 Cobalt net ≈4521.59; I-03 net prorated by PTC ≈554.79; E-04 Fortra-Originated takes the Non_Orig band ≠301.75). Re-retrieve V21 post-activate (no clobber). Reprice 2-3 PASS controls (USD direct, USD partner E-02, BoKS derived) for no regression. Document the metadata diff + Non_Orig values. UAT only.