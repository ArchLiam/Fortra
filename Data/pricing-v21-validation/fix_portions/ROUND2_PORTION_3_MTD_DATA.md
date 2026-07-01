# V21 Fix — ROUND 2, PORTION 3 of 3: DATA — Maintenance-Type attribute (MTD)

**Your defects (1):** A-07 [P2]

**Surface:** A data backfill of ProductAttributeDefinition rows for the Maintenance_Type_Defn attribute (REST/Bulk). No procedure edit, no Apex.

**Boundary:** Do NOT edit the V21 procedure (Portion 1 owns it) or any Apex. You touch only ProductAttributeDefinition. This is a DATA fix and is largely blocked — see the caveat.

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

### A-07 — Maintenance-family inconsistency — ~1497 products lack the Maintenance-Type attribute  ·  P2 · ORG-CONFIG-DEFECT · SC-3346

**Verified STILL FAILING (22:01Z, live):** STILL FAILING (DATA): ProductAttributeDefinition for Maintenance_Type_Defn (0tjWC000000096bYAA) still 186 rows vs 1683 active New-Maintenance products — ~1497 missing; NOT backfilled since run3.

**Exact artifact(s):**
  - **product-attribute** — ProductAttributeDefinition — AttributeDefinitionId=0tjWC000000096bYAA (Maintenance_Type_Defn / MTD) — INSERT ~1567 rows for active New Maintenance Product2 records currently missing MTD (1683 total active New Maint products; only 116 carry MTD today = 6.9%)

**Deploy:** REST/Bulk data insert — query the ~1567 active New Maintenance Product2 Ids lacking a PAD row for AttributeDefinitionId=0tjWC000000096bYAA, then Bulk API v2 insert new ProductAttributeDefinition rows with: AttributeDefinitionId=0tjWC000000096bYAA, Name='Maintenance Type', DefaultValue='Standard', IsPriceImpacting=true, IsRequired=false, IsHidden=false, IsReadOnly=false, Status='Active', AttributeCategoryId=0v3WC00000005ZEYAY, ProductClassificationAttributeId=11CWC000007hls42AA. No proc deploy, no Apex deploy.

**Expected:** Every maintenance product carries Maintenance Type Defn (or a documented fallback, e.g. Standard 0.20) so the tier resolves.

**Fix (NOT yet applied):** Backfill the Maintenance_Type_Defn attribute on the ~1497 products lacking it (esp. the FIM CCM family), or add a documented Standard 0.20 default to step 39. Config/data, not a procedure bug per se.

**Implementation detail:** The defect is a pure org-config gap: ~1567 of 1683 active New Maintenance Product2 records have NO ProductAttributeDefinition row for the Maintenance_Type_Defn attribute (AttributeDefinitionId=0tjWC000000096bYAA). V21 step 39 'Derived Pricing Formula' (tier lookup on MTD AttributeValue) returns 0 when the attribute is absent, producing NetUnitPrice=0. The BoKS positive control (PIAMBK 01tWC00000DD1bsYAD) has the MTD PAD with DefaultValue='Standard' and IsPriceImpacting=true and prices correctly to 0.20 x Source_List_Price. Fix = Bulk API v2 insert one new PAD row per gap product, copying the field shape from existing MTD PADs: AttributeDefinitionId=0tjWC000000096bYAA, Name='Maintenance Type', DefaultValue='Standard', IsPriceImpacting=true, IsRequired=false, IsHidden=false, IsReadOnly=false, Status='Active', AttributeCategoryId=0v3WC00000005ZEYAY, ProductClassificationAttributeId=11CWC000007hls42AA. Identify the gap with: SELECT Id FROM Product2 WHERE Fortra_Product_Type__c='New Maintenance' AND IsActive=true AND Id NOT IN (SELECT Product2Id FROM ProductAttributeDefinition WHERE AttributeDefinitionId='0tjWC000000096bYAA'). Verify by Force-repricing an FIM CCM maintenance quote (e.g. 0Q0WC000003AqV30AK) — CCMMSN and CCMLSE lines should show NetUnitPrice = SLP x 0.20 (Standard tier). NOT APPLIED.

⚠️ DATA-ONLY, LARGELY BLOCKED. Per prior analysis ([A-07 MTD backfill mis-scoped]): a blanket 1567-row identical-PAD insert is NOT viable — the ProductClassificationAttribute is per-classification (non-nillable), ~935 products have a null BasedOnId, only ~91 are cleanly backfillable, and the FIM CCM family specifically is unreachable this way. Your job: (1) backfill ONLY the ~91 cleanly-actionable products and reprice-verify; (2) produce the exact blocked list (esp. FIM CCM) with the reason each is blocked, for a product-owner decision on whether to add MTD or add a Standard-0.20 default to step 39. Do NOT blind-insert 1567 rows.

**Verify:** reprice the evidence record and confirm the field flips to the expected value; re-check a same-area control.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view

---

## Cross-portion coordination
- Do NOT edit the V21 procedure (P1 owns it) or any Apex. You touch only ProductAttributeDefinition (Maintenance_Type_Defn).
- Verify by repricing a FIM CCM maint line AFTER Portion 1 is stable.
- This is a largely-blocked data fix — backfill the ~91 viable, escalate FIM CCM (~1497) to the product owner. Do NOT touch PriceBookEntryDerivedPrice (P2).

## Definition of done
A-07: after backfilling the ~91 viable MTD rows, reprice one of those maint lines and confirm a non-zero derived tier. Deliver: rows inserted + the exact blocked list (FIM CCM etc.) with the reason each is blocked, for the product owner. UAT only.