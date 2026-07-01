# V21 Fix — PORTION 3 of 3: DERIVED-PBE DATA

**Your defects (2):** J-09 [P0], J-10 [P0]

**Your surface:** Two data backfills in the derived-PriceBookEntry space (PriceBookEntryDerivedPrice rows + PricebookEntry.IsDerived flags). No procedure edits, no Apex.

**Boundary:** Do NOT edit the V21 procedure (Portion 1 owns it). Both your items operate on the derived-PBE config for overlapping products, so you own that space exclusively.

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

### J-09 — Derived line with no PBEDP config row prices silently null  ·  P0 · ORG-CONFIG-DEFECT · ticket SC-3372 / M5-PBEDP

**Exact artifact(s) to edit:**
  - **pricebook-entry** — PriceBookEntryDerivedPrice (PBEDP) — INSERT ~476 rows for high-confidence IsDerived PBEs lacking contributor config. Staged payload: Data/sc-maint/sc3346_fix/m5_pbedp/backfill_HICONF.csv (476 rows, 477 lines with header). Minimal fields per row: PricebookEntryId, ContributingProductId, Formula=UnitPrice, PricingSource=Product, DerivedPricingScope=Both, EffectiveFrom=2026-04-01, EffectiveTo=2099-12-31, Legacy_Rule_Id__c marker. ProductId and ProductSellingModelId are auto-derived from the PBE — do NOT set them. Disputed PBE: 01uWC000005wsZpYAI (GS-GSE-RNM-EF8). Coverage baseline: 199 PBEDP-covered PBEs out of 1889 active IsDerived PBEs in Fortra Price Book (01sWC0000022GHFYA2) as of 2026-06-30.

**Deploy mechanism:** REST/Bulk data insert — POST PriceBookEntryDerivedPrice records via Salesforce REST Composite or Bulk API against FortraUAT (-o FortraUAT). No procedure republish required. Reversible via Legacy_Rule_Id__c marker delete. Requires fresh explicit DML auth from Marc DeBrey (contributor mapping confirmation) before execution per SC-3372 standing rule.

**Expected behavior:** Backfill PBEDP rows for all IsDerived PBEs (or remove the native element if the Fortra formula suffices); a clear error, not a silent null.

**Observed (live, this validation):** QLI 0QLWC000003KEbO4AW (GS-GSE-RNM-EF8, PBE IsDerived=true, uncovered): NetUnitPrice=null, ListPrice=0, TotalPrice=0. Only 199 of 1889 active IsDerived PBEs in the live book are PBEDP-covered.

**Responsible step / root cause:** Native Derived Products pull (steps 41–42) maps the contributing product via a PriceBookEntryDerivedPrice (PBEDP) row; an IsDerived PBE with 0 PBEDP rows yields NetUnitPrice=null with no hard error.

**Fix to implement (NOT yet applied):** Backfill PBEDP rows for the uncovered IsDerived PBEs, or remove the native DerivedProducts element (Fortra custom formula already covers it). Config/data only.

**Implementation detail (from artifact pin):** The native DerivedProducts elements (V21 steps 41-42) pull a contributing-product reference via the PriceBookEntryDerivedPrice (PBEDP) join table. PBE 01uWC000005wsZpYAI (GS-GSE-RNM-EF8, IsDerived=true) has 0 PBEDP rows, so the native element produces a silent null (no error, no NetUnitPrice) instead of the expected hard-error. The fix is a pure data backfill: insert PBEDP rows for the ~476 high-confidence uncovered IsDerived PBEs using the pre-staged payload at Data/sc-maint/sc3346_fix/m5_pbedp/backfill_HICONF.csv. Each PBEDP row needs PricebookEntryId + ContributingProductId (license product) + Formula=UnitPrice + PricingSource=Product + DerivedPricingScope=Both + EffectiveFrom=2026-04-01 + EffectiveTo=2099-12-31; do NOT set ProductId or ProductSellingModelId (read-only, auto-derived). After insert, Force-reprice QLI 0QLWC000003KEbO4AW on Quote 0Q0WC0000029Agw0AE and confirm Source_List_Price__c stamps non-null and NetUnitPrice resolves to a non-zero value; also confirm that repriced lines do NOT surface the 'contributing products missing' hard-error. The remaining ~1,410 business-gated uncovered PBEs (ambiguous contributor / zero-list contributor) are out of scope for this work-stream and need Marc DeBrey crosswalk confirmation.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000029Agw0AE/view

---

### J-10 — EUR derived-maintenance line prices $0 — IsDerived flag only on the USD PBE  ·  P0 · ORG-CONFIG-DEFECT · ticket SC-3384

**Exact artifact(s) to edit:**
  - **pricebook-entry** — PricebookEntry.IsDerived — all active non-USD PBEs in Fortra Price Book (01sWC0000022GHFYA2) whose Product2Id has at least one USD PBE with IsDerived=true. Org-confirmed: 3453 derived PBEs exist (100% USD); 0 non-USD derived PBEs exist. Scope query (two-pass, SOQL self-join not supported): (1) collect Product2Ids from PricebookEntry WHERE IsDerived=true AND CurrencyIsoCode='USD'; (2) PATCH IsDerived=true on PricebookEntry WHERE Product2Id IN <that set> AND IsDerived=false AND CurrencyIsoCode != 'USD' AND IsActive=true AND Pricebook2Id='01sWC0000022GHFYA2'. Evidence record for J-10: EUR PBE 01uWC000005wzX8YAI (Product2 01tWC00000DD1bsYAD, BoKS NewMaintenance) IsDerived=false confirmed live 2026-06-30; its USD twin 01uWC000005wsbUYAQ IsDerived=true.

**Deploy mechanism:** REST/Bulk data update only. No proc deploy, no Apex deploy. Two-pass: (1) query USD derived Product2Ids; (2) Bulk API v2 PATCH or REST composite to set IsDerived=true on matching non-USD PBEs. No UAT deploy authorization needed beyond the standard per-ticket data-DML ack (per feedback_uat_deploy_authorization.md).

**Expected behavior:** Net = priorAssetNet × (1+COLA%) × currencyMult, committed once; stable across reprices.

**Observed (live, this validation):** EUR maint line 0QLWC000003kinW4AQ: NetUnitPrice/UnitPrice/ListPrice = 0; COLACalculatedPrice__c=3666.90 stamped but never committed. License line correct. Org-wide ALL 3453 IsDerived=true PBEs are USD.

**Responsible step / root cause:** The derived-net committer (Derived Maintenance Net Filter / Derived Products – Renewals) gates on PBE.IsDerived, which is true only on the USD PBE; the EUR PBE has IsDerived=false so the COLA-derived net is never committed.

**Fix to implement (NOT yet applied):** Set IsDerived=true on the non-USD PBEs for every product whose USD PBE is IsDerived=true (SC-3384 currency-completeness family). Data-only PricebookEntry fix.

**Implementation detail (from artifact pin):** The V21 derived-maintenance committer gates on PBE.IsDerived (surfaced as ItemIsDerived__std in the pricing context); when that flag is false the COLA stamp fires but NetUnitPrice is never written, yielding $0. All 3453 derived PBEs in the org have IsDerived=true only on their USD entry — every non-USD PBE for the same products has IsDerived=false — so any non-USD derived renewal hits this $0. Fix: run a two-pass Bulk REST update: collect Product2Ids from PBEs WHERE IsDerived=true AND CurrencyIsoCode='USD', then PATCH IsDerived=true on all active non-USD PBEs in Fortra Price Book for those same products. Verify by force-repricing EUR Quote 0Q0WC000003FZN70AO (BoKS EUR, #00781510) and confirming QLI 0QLWC000003kinW4AQ NetUnitPrice is non-zero (expected ~3177–3667 depending on basis); also confirm COLACalculatedPrice__c value now commits to NetUnitPrice. This fix is independent of V21 proc edits and does not collide with SC-3384's configured-pricing (ABA/Apex) workstream, though both are in the same currency-completeness family; ship independently.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZN70AO/view

---

## Cross-portion coordination (read before you start)

- **Do NOT edit the V21 procedure or any Apex** — Portions 1 & 2 own those. You operate only on `PriceBookEntryDerivedPrice` (J-09 inserts) and `PricebookEntry.IsDerived` (J-10 updates).
- **J-09 and J-10 share the derived-PBE space** and are both yours — sequence them so you do not double-touch the same PBE set (do J-10 IsDerived first, then J-09 PBEDP backfill on the now-correct set, or query carefully).
- **Verification timing:** you verify by repricing derived/maintenance quotes through live V21, which Portion 1 is editing. Do your data backfills anytime, but run final reprice-verification when Portion 1 confirms V21 is stable.
- **Derived-maintenance overlap with Portion 2 (A-07):** A-07 backfills the Maintenance-Type *attribute* (ProductAttributeDefinition); you backfill *PBE* config. Different objects — no collision.
- Do NOT touch: the V21 ExpressionSet (Portion 1), any Apex class (Portions 1/2), `ProductAttributeDefinition` / `CurrencyType` (Portion 2).

## Definition of done

- J-10: after setting IsDerived=true on the non-USD derived PBEs, reprice an EUR derived-maintenance quote and confirm NetUnitPrice is committed (COLACalculatedPrice -> NetUnitPrice, no longer $0).
- J-09: after the PBEDP backfill, reprice a previously-uncovered IsDerived line (e.g. GS-GSE-RNM-EF8) and confirm it no longer prices silent null.
- Confirm a known-good covered derived line (BoKS) still prices correctly (no regression).
- Document the PBEDP rows inserted (count + reversible Legacy_Rule_ marker) and the PBE Ids set IsDerived=true. UAT only — do NOT deploy to prod.