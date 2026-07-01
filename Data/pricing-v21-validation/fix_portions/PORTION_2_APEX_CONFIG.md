# V21 Fix — PORTION 2 of 3: APEX + INDEPENDENT CONFIG

**Your defects (3):** J-06 [P0], A-07 [P2], G-08 [P2]

**Your surface:** One Apex class edit + two independent data/config backfills. NONE of these touch the V21 procedure metadata.

**Boundary:** Do NOT edit the V21 procedure (Portion 1 owns it). Your three items hit three different artifacts (an Apex class, ProductAttributeDefinition records, and CurrencyType admin) and do not collide with each other.

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

### J-06 — Partner discount on derived maintenance uses the license band, not the New-Maintenance band  ·  P0 · PROCEDURE-DEFECT · ticket SC-3346 / SC-3359

**Exact artifact(s) to edit:**
  - **apex-class** — PartnerNetPricePosthook — loadNewMaintenanceLines (line ~1372-1374) and buildContributorCarryForwardSnapshot / resolveContributorPartnerPercent (lines ~1497-1526)

**Deploy mechanism:** Apex class deploy via sf CLI (sf project deploy start --source-dir ... -o FortraUAT). Retrieve live class first (sc-j06-verify/unpackaged/classes/ or Data/sc3473/j06_audit_live/classes/); edit; deploy. No proc version bump needed.

**Expected behavior:** Maint net = 71 × (1−0.12) = 62.48 (partner discount applied once at the New-Maintenance %).

**Observed (live, this validation):** Maint NetUnitPrice = 60.35 = 71 × (1−0.15): correct single application, WRONG band (15% carried from license). License net 301.75 correct. Stable across reprices (prior one-cycle lag is gone).

**Responsible step / root cause:** PartnerNetPricePosthook.resolveContributorPartnerPercent returns the license contributor’s PartnerDiscountPercent (Software 15%) and carries it onto the derived-maintenance line instead of the New-Maintenance band (12%).

**Fix to implement (NOT yet applied):** Resolve the derived-maintenance partner % from the Quote’s Partner_Pricing_Model__c via getMarginForProductType(model,'New Maintenance') instead of inheriting the contributor’s license %.

**Implementation detail (from artifact pin):** In PartnerNetPricePosthook.loadNewMaintenanceLines (line ~1372-1374), the derived New-Maintenance line inherits partnerPercent from ContributorCarryForwardSnapshot.partnerPercent, which was built by buildContributorCarryForwardSnapshot → resolveContributorPartnerPercent and returns the CONTRIBUTOR (license) line's PartnerDiscountPercent = 15 (Software band). The correct band for a 'New Maintenance' product is New_Maintenance_Percent__c = 12, accessible via PartnerPricingService.getMarginForProductType(model, 'New Maintenance'). The call to getMarginForProductType is structurally bypassed for derived maintenance by isDerivedMaintenanceProductType (line 550-552 returns null from calculateDeferredPartnerPrice). Fix: in loadNewMaintenanceLines, after the contributor carry-forward is resolved, resolve the active Partner_Pricing_Model__c for the QLI's Quote (already loaded in partnerModels via quoteData) and call PartnerPricingService.getMarginForProductType(model, 'New Maintenance') to obtain the correct discount percent; use THAT value as partnerPercent for the NewMaintInputs constructor instead of contributor.partnerPercent. Keep contributor.pricingBase (355) as the contributorNet — only the percent band source changes. Verify by repricing Quote 0Q0WC000003FdCD0A0 (Q-J06-58422) via REST v67 force-reprice and confirming maint QLI 0QLWC000003kmeE4AQ NetUnitPrice = 62.48 = 71 * (1 − 0.12), not 60.35.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FdCD0A0/view

---

### A-07 — Maintenance-family inconsistency — ~1497 products lack the Maintenance-Type attribute  ·  P2 · ORG-CONFIG-DEFECT · ticket SC-3346

**Exact artifact(s) to edit:**
  - **product-attribute** — ProductAttributeDefinition — AttributeDefinitionId=0tjWC000000096bYAA (Maintenance_Type_Defn / MTD) — INSERT ~1567 rows for active New Maintenance Product2 records currently missing MTD (1683 total active New Maint products; only 116 carry MTD today = 6.9%)

**Deploy mechanism:** REST/Bulk data insert — query the ~1567 active New Maintenance Product2 Ids lacking a PAD row for AttributeDefinitionId=0tjWC000000096bYAA, then Bulk API v2 insert new ProductAttributeDefinition rows with: AttributeDefinitionId=0tjWC000000096bYAA, Name='Maintenance Type', DefaultValue='Standard', IsPriceImpacting=true, IsRequired=false, IsHidden=false, IsReadOnly=false, Status='Active', AttributeCategoryId=0v3WC00000005ZEYAY, ProductClassificationAttributeId=11CWC000007hls42AA. No proc deploy, no Apex deploy.

**Expected behavior:** Every maintenance product carries Maintenance Type Defn (or a documented fallback, e.g. Standard 0.20) so the tier resolves.

**Observed (live, this validation):** BoKS PASSES (has MTD): 0.20 × 355 = 71. FIM CCM FAILS (no MTD): all CCM New-Maint lines net $0/null. Only 186 of 1683 active New-Maintenance products carry MTD (~89% missing).

**Responsible step / root cause:** Step 39 Derived Pricing Formula looks up the tier on the Maintenance Type Defn attribute; a product missing the attribute returns tier=0 → NetUnitPrice=0 (or native 100%-copy). No safe-default tier in the procedure.

**Fix to implement (NOT yet applied):** Backfill the Maintenance_Type_Defn attribute on the ~1497 products lacking it (esp. the FIM CCM family), or add a documented Standard 0.20 default to step 39. Config/data, not a procedure bug per se.

**Implementation detail (from artifact pin):** The defect is a pure org-config gap: ~1567 of 1683 active New Maintenance Product2 records have NO ProductAttributeDefinition row for the Maintenance_Type_Defn attribute (AttributeDefinitionId=0tjWC000000096bYAA). V21 step 39 'Derived Pricing Formula' (tier lookup on MTD AttributeValue) returns 0 when the attribute is absent, producing NetUnitPrice=0. The BoKS positive control (PIAMBK 01tWC00000DD1bsYAD) has the MTD PAD with DefaultValue='Standard' and IsPriceImpacting=true and prices correctly to 0.20 x Source_List_Price. Fix = Bulk API v2 insert one new PAD row per gap product, copying the field shape from existing MTD PADs: AttributeDefinitionId=0tjWC000000096bYAA, Name='Maintenance Type', DefaultValue='Standard', IsPriceImpacting=true, IsRequired=false, IsHidden=false, IsReadOnly=false, Status='Active', AttributeCategoryId=0v3WC00000005ZEYAY, ProductClassificationAttributeId=11CWC000007hls42AA. Identify the gap with: SELECT Id FROM Product2 WHERE Fortra_Product_Type__c='New Maintenance' AND IsActive=true AND Id NOT IN (SELECT Product2Id FROM ProductAttributeDefinition WHERE AttributeDefinitionId='0tjWC000000096bYAA'). Verify by Force-repricing an FIM CCM maintenance quote (e.g. 0Q0WC000003AqV30AK) — CCMMSN and CCMLSE lines should show NetUnitPrice = SLP x 0.20 (Standard tier). NOT APPLIED.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view

---

### G-08 — Org FX rates corrupted to 1.0 on 6 currencies (reporting/invoicing only — proc decoupled)  ·  P2 · ORG-CONFIG-DEFECT · ticket SC-3384

**Exact artifact(s) to edit:**
  - **currency-admin** — CurrencyType.ConversionRate — 6 ISO codes: ARS (set to 666.6667), CHF (0.885), GBP (0.7874), ILS (3.6251), JPY (149.2537), NZD (1.6667); plus DatedConversionRate new rows from 2026-02-14 onward for each of the same 6 ISOs

**Deploy mechanism:** Setup > Manage Currencies (FortraUAT org): edit each corrupted CurrencyType record in the UI or via the CurrencyType sObject REST API. For Advanced Currency Management (DatedConversionRate), add new effective-dated rows for each of the 6 currencies starting 2026-02-14 (the day after the last confirmed reset). No proc deploy, no Apex deploy, no metadata deploy required.

**Expected behavior:** Authorized rates maintained per the FX table (ARS 666.67, CHF 0.885, GBP 0.7874, ILS 3.6251, JPY 149.25, NZD 1.6667).

**Observed (live, this validation):** 6 of 11 non-USD currencies sit at placeholder 1.0; DatedConversionRate confirms ARS/CHF/GBP/JPY reset to 1.0 on 2026-02-11/12/13. Any foreign txn since consolidates at face value. Pricing proc unaffected (proven by G-01 reading the mdt).

**Responsible step / root cause:** Admin-maintained CurrencyType.ConversionRate (NOT a V21 step). The pricing steps 33–36 are clean (they read Currency_Conversion_Formula__mdt); the defect surface is reports, DocGen FX, and Workday invoicing consolidation.

**Fix to implement (NOT yet applied):** Reload CurrencyType.ConversionRate + forward-dated rows from the authoritative table and stop the 2026-02-11 reset automation. No pricing-procedure change.

**Implementation detail (from artifact pin):** Six non-USD currencies in FortraUAT have CurrencyType.ConversionRate = 1.0 (placeholder) instead of the authoritative ARR rates: ARS 666.6667, CHF 0.885, GBP 0.7874, ILS 3.6251, JPY 149.2537, NZD 1.6667. DatedConversionRate rows for ARS/GBP/JPY were reset to 1.0 on 2026-02-11 through 2026-02-13; CHF has never held a real rate in UAT. The V21 pricing procedure itself is NOT affected — it reads Currency_Conversion_Formula__mdt (all 10 records correct) and is decoupled from CurrencyType entirely. The impact is limited to reports, dashboards, DocGen FX consolidation, and Workday invoicing (any foreign transaction dated >= 2026-02-11 consolidates at face value, e.g. JPY 221M shown as USD 221M). Fix: in Setup > Manage Currencies, update the six CurrencyType records to the authoritative rates above, then add DatedConversionRate rows effective 2026-02-14 for ARS/GBP/JPY/ILS/NZD (CHF needs its first real row). Optionally deactivate orphan currencies MXN and SEK which are not in the official 5- or 10-currency scope. Verify by re-querying CurrencyType and DatedConversionRate; no repricing required since the proc is unaffected.

**Verify:** Force-reprice the evidence record(s) through live V21 and confirm the field above resolves to the expected value; re-confirm a same-area PASS control still passes.
**Evidence record:** https://fortra--uat.sandbox.my.salesforce.com/lightning/setup/CurrencySettings/home

---

## Cross-portion coordination (read before you start)

- **Do NOT edit the V21 procedure** — Portion 1 owns it. Your three items are an Apex class, ProductAttributeDefinition inserts, and CurrencyType admin; none require a proc change.
- **Verification timing:** you verify by repricing through the live V21, which Portion 1 is editing in-place. Do your edits anytime, but run your final reprice-verification when Portion 1 confirms V21 is stable (it will announce). Your J-06 Apex deploy itself does not need the proc.
- **Partner overlap with Portion 1 (E-04):** your J-06 fixes the partner *posthook* band; Portion 1 re-points the partner *prehook*. Different classes — independent edits, but re-verify a partner quote after both land.
- **Derived-maintenance overlap with Portion 3:** your A-07 backfills the Maintenance-Type *attribute*; Portion 3 backfills *PBE* derived config. Different objects/products — no collision; just be aware both touch derived-maintenance pricing.
- Do NOT touch: the V21 ExpressionSet (Portion 1), `Partner_Pricing_Model__c` Non_Orig columns (Portion 1 / E-04), `PriceBookEntry*` derived data (Portion 3).

## Definition of done

- J-06: re-reprice the evidence quote; derived-maintenance partner line nets the New-Maintenance band (62.48 = 71x0.88), not 60.35; license line still 301.75.
- A-07: after the MTD attribute backfill, reprice a FIM CCM New-Maintenance line and confirm it derives a non-zero tier (no longer $0/100%-copy); BoKS still 71.
- G-08: confirm the 6 CurrencyType rates + dated rows are corrected (ARS 666.6667, CHF 0.885, GBP 0.7874, ILS 3.6251, JPY 149.2537, NZD 1.6667); spot-check a report/Workday-facing conversion. (Pricing proc is decoupled, so no reprice needed.)
- Document records changed (class diff, PAD insert count + Ids, CurrencyType edits). UAT only — do NOT deploy to prod.