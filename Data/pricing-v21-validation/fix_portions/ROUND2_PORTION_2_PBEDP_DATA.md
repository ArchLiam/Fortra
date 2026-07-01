# V21 Fix — ROUND 2, PORTION 2 of 3: DATA — Derived-PBE contributor config (PBEDP)

**Your defects (1):** J-09 [P0]

**Surface:** A data backfill of PriceBookEntryDerivedPrice rows (REST/Bulk). No procedure edit, no Apex.

**Boundary:** Do NOT edit the V21 procedure (Portion 1 owns it) or any Apex. You touch only PriceBookEntryDerivedPrice. This is a DATA fix and is partially gated — see the caveat.

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

### J-09 — Derived line with no PBEDP config row prices silently null  ·  P0 · ORG-CONFIG-DEFECT · SC-3372 / M5-PBEDP

**Verified STILL FAILING (22:01Z, live):** STILL FAILING (DATA): PBE 01uWC000005wsZpYAI IsDerived=true, active, USD, book active, UnitPrice=0 (by design) with 0 PriceBookEntryDerivedPrice rows → QLI 0QLWC000003KEbO4AW Net=null. 3453 active IsDerived PBEs org-wide.

**Exact artifact(s):**
  - **pricebook-entry** — PriceBookEntryDerivedPrice (PBEDP) — INSERT ~476 rows for high-confidence IsDerived PBEs lacking contributor config. Staged payload: Data/sc-maint/sc3346_fix/m5_pbedp/backfill_HICONF.csv (476 rows, 477 lines with header). Minimal fields per row: PricebookEntryId, ContributingProductId, Formula=UnitPrice, PricingSource=Product, DerivedPricingScope=Both, EffectiveFrom=2026-04-01, EffectiveTo=2099-12-31, Legacy_Rule_Id__c marker. ProductId and ProductSellingModelId are auto-derived from the PBE — do NOT set them. Disputed PBE: 01uWC000005wsZpYAI (GS-GSE-RNM-EF8). Coverage baseline: 199 PBEDP-covered PBEs out of 1889 active IsDerived PBEs in Fortra Price Book (01sWC0000022GHFYA2) as of 2026-06-30.

**Deploy:** REST/Bulk data insert — POST PriceBookEntryDerivedPrice records via Salesforce REST Composite or Bulk API against FortraUAT (-o FortraUAT). No procedure republish required. Reversible via Legacy_Rule_Id__c marker delete. Requires fresh explicit DML auth from Marc DeBrey (contributor mapping confirmation) before execution per SC-3372 standing rule.

**Expected:** Backfill PBEDP rows for all IsDerived PBEs (or remove the native element if the Fortra formula suffices); a clear error, not a silent null.

**Fix (NOT yet applied):** Backfill PBEDP rows for the uncovered IsDerived PBEs, or remove the native DerivedProducts element (Fortra custom formula already covers it). Config/data only.

**Implementation detail:** The native DerivedProducts elements (V21 steps 41-42) pull a contributing-product reference via the PriceBookEntryDerivedPrice (PBEDP) join table. PBE 01uWC000005wsZpYAI (GS-GSE-RNM-EF8, IsDerived=true) has 0 PBEDP rows, so the native element produces a silent null (no error, no NetUnitPrice) instead of the expected hard-error. The fix is a pure data backfill: insert PBEDP rows for the ~476 high-confidence uncovered IsDerived PBEs using the pre-staged payload at Data/sc-maint/sc3346_fix/m5_pbedp/backfill_HICONF.csv. Each PBEDP row needs PricebookEntryId + ContributingProductId (license product) + Formula=UnitPrice + PricingSource=Product + DerivedPricingScope=Both + EffectiveFrom=2026-04-01 + EffectiveTo=2099-12-31; do NOT set ProductId or ProductSellingModelId (read-only, auto-derived). After insert, Force-reprice QLI 0QLWC000003KEbO4AW on Quote 0Q0WC0000029Agw0AE and confirm Source_List_Price__c stamps non-null and NetUnitPrice resolves to a non-zero value; also confirm that repriced lines do NOT surface the 'contributing products missing' hard-error. The remaining ~1,410 business-gated uncovered PBEs (ambiguous contributor / zero-list contributor) are out of scope for this work-stream and need Marc DeBrey crosswalk confirmation.

⚠️ DATA-ONLY, PARTIALLY GATED. Per prior analysis (SC-3372 / M5-PBEDP): the staged ~476-row PBEDP CSV was ~47% mis-scoped (221 pointed at the inactive Standard Price Book); only ~253 rows are actionable, and sign-off is gated on **Marc DeBrey**. Your job: (1) build/validate the actionable PBEDP rows for active-Fortra-Price-Book IsDerived PBEs that lack contributor config, insert them via REST/Bulk, reprice to confirm the null→priced flip; (2) produce the EXACT list of the non-actionable/ambiguous PBEs and hand them to Marc — do NOT blind-insert the mis-scoped rows.

**Verify:** reprice the evidence record and confirm the field flips to the expected value; re-check a same-area control.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000029Agw0AE/view

---

## Cross-portion coordination
- Do NOT edit the V21 procedure (P1 owns it) or any Apex. You touch only PriceBookEntryDerivedPrice.
- Verify by repricing derived quotes through live V21 AFTER Portion 1 announces it is stable.
- This is a partially-gated data fix — do the actionable subset, escalate the rest (Marc DeBrey). Do NOT touch ProductAttributeDefinition (P3).

## Definition of done
J-09: after inserting the actionable PBEDP rows, reprice a previously-null derived line (e.g. QLI 0QLWC000003KEbO4AW) and confirm it prices non-null. Deliver: rows inserted (count + reversible marker) + the exact blocked/ambiguous list for Marc. UAT only.