# NB-DERIVED-TIER — Fix Spec (NEW, unticketed defect)

**Status:** Fix built + v67-validated; deploy paused (V14 being edited by a concurrent session — see §7 stale-package caveat).
**Org:** FortraUAT · **Procedure:** `Rev_Mgmt_Default_Pricing_Procedure` V14 (sole Active, ESV def `9QAWC0000003mg14AA`, version row `9QBWC0000000nIT4AY`).
**Severity:** HIGH · **Owner:** SC-3346 build · **Date:** 2026-06-13

## 1. Defect
The live V14 new-business derived-maintenance formula hard-codes only **3 of 7** maintenance tiers. Every other tier hits the `, 0 )` fallback → `× 0` → **$0 maintenance NetUnitPrice**.

Element: **`DerivedPricingFormula`** (label "Derived Pricing Formula", parentStep `ListContainer9`, `FormulaBasedPricing` → output `NetUnitPrice`), live file line **71642**:
```
IF ( AttributeValue = 'Premier' , 0.30 ,
 IF ( AttributeValue = 'Standard' , 0.20 ,
  IF ( AttributeValue = 'Professional' , 0.20 , 0 ) ) ) * Source_List_Price__c
```
This is the **live** new-business derived net (proven by NB-DERIVED-NET: Standard 0.20 × 355 = 71). The rates are inlined — the formula does **0** `Maintenance_Rate__mdt` lookups, so the table can silently drift from the formula.

## 2. Root cause (live-verified)
- `Maintenance_Rate__mdt` source-of-truth = **7 tiers** (live `Rate__c`): Basic 0.15, Professional 0.20, Standard 0.20, Premium 0.24, Express 0.30, Premier 0.30, Expert 0.35.
- MTD picklist (AttributeDefinition `0tjWC000000096bYAA`) has **8** values — the 7 above + orphan **`platinum`** (no `Maintenance_Rate__mdt` row).
- The formula handles only Premier/Standard/Professional. Basic, Premium, Express, Expert, platinum → fallback `0`.

**Live mis-pricing tally** (102,123 MTD QuoteLineItemAttribute rows, pulled 2026-06-13):
| Tier | Rows | Rate | Status |
|---|---|---|---|
| Premier | 42,604 | 0.30 | ✅ handled |
| Professional | 41,881 | 0.20 | ✅ handled |
| Standard | 16,588 | 0.20 | ✅ handled |
| **Premium** | **833** | 0.24 | ❌ → $0 |
| **Basic** | **185** | 0.15 | ❌ → $0 |
| **Expert** | **13** | 0.35 | ❌ → $0 |
| **platinum** | **18** | — (orphan) | ❌ → $0 |
| Express | 0 (live) | 0.30 | ❌ (defined, unused) |

= **1,031 legit rows** mis-pricing $0 (Premium/Basic/Expert) + 18 orphan platinum.

> Note: among *Draft new-maintenance* lines today, only Standard/Premier are present — the 1,031 broken rows are on non-draft/renewal lines. The renewal-maintenance path uses `DerivedPricingRenewals`, a *different* formula; this fix is for **new-business** derived maintenance.

## 3. Fix (decision: complete the inline IF-chain)
Decisions taken (user, 2026-06-13): **complete the inline IF** (surgical; same proven pattern; lowest blast radius — data-driving from `Maintenance_Rate__mdt` is the proper long-term design, filed as a follow-up §8). **platinum → leave $0 + flag** (do not invent a price).

Corrected `DerivedPricingFormula` (all 7 CMDT tiers; platinum falls to the `0` else, flagged):
```
IF ( AttributeValue = 'Premier' , 0.30 ,
 IF ( AttributeValue = 'Expert' , 0.35 ,
  IF ( AttributeValue = 'Express' , 0.30 ,
   IF ( AttributeValue = 'Premium' , 0.24 ,
    IF ( AttributeValue = 'Standard' , 0.20 ,
     IF ( AttributeValue = 'Professional' , 0.20 ,
      IF ( AttributeValue = 'Basic' , 0.15 , 0 ) ) ) ) ) ) ) * Source_List_Price__c
```
Built as a **single-line** edit (only file line 71642 changes; inactive V13 occurrence at 66025 left untouched). Package: `Data/sc-maint/sc3346_fix/deploy/` (1-line diff vs live, parens balanced, all 7 tiers asserted present). v67 dry-run = clean (only "version is active, deactivate" remains).

## 4. Deploy plan — in-place V14 (user choice)
API **67.0** required (v66 → `Property 'dataType' not valid`). Metadata-format package → use **`--metadata-dir`** (the `-d` flag uses project `sourceApiVersion=66.0` and fails).
1. **[UI]** Deactivate V14 (Pricing Procedure → Versions → V14 → Deactivate). ⚠️ pricing offline.
2. **[CLI]** `sf project deploy start --metadata-dir Data/sc-maint/sc3346_fix/deploy --api-version 67.0 -o FortraUAT`
   (ignore cosmetic `metadata.transfer:Finalizing`; confirm by re-retrieve.)
3. **[UI]** Reactivate **the single V14 row** (NEVER "Reactivate All Dependencies" — that activated 8 versions = past corruption).
4. **[CLI]** Verify (§6).

## 5. Rollback
`Data/sc-maint/sc3346_fix/rollback/` = pristine current-live V14 (0-diff). Redeploy same as §4-2 after deactivating V14.

## 6. Verification
- Re-retrieve V14 → confirm `DerivedPricingFormula` now lists all 7 tiers.
- Confirm V14 still **sole Active** (`ExpressionSetDefinitionVersion … Status='Active'`).
- Regression: Force-reprice a Standard + a Premier new-maintenance Draft line → unchanged (0.20×SLP, 0.30×SLP). Watch the reprice for the `contextDefinitionName` gack (a pure formula-literal change should NOT need a `SalesTransactionContextExt_v2` resync, but confirm).
- New tiers (Premium/Basic/Expert) share the **identical code path** as Standard → guaranteed correct by construction; gold-standard empirical proof needs a Premium new-maintenance line added via the configurator (optional follow-up).

## 7. ⚠️ Stale-package caveat
A concurrent session is editing V14 (2026-06-13). The staged `deploy/` package was built from a retrieve taken **before** their edit. Before deploying, **re-retrieve live V14, re-apply the single-line tier fix on top of their version, re-validate** — do NOT deploy the current package over their changes.

## 8. Follow-ups (separate)
- **File the ticket** — this defect is currently unticketed (NEW).
- **platinum cleanup** — 18 orphan rows + the picklist value; business to define a rate or remap/retire the value.
- **Data-drive the tier rate** — replace the inline IF with a `Maintenance_Rate__mdt`-driven lookup (CalculationMatrix or a stamp-flow rate field) so the formula can never drift from the table. Larger change; relates to peer-review finding M-2.
- **Dead-code** — `DerivedPricingNewBusiness` (line 71772, `Base_Price__c × 3-tier`) is M-2 dead-code with the same incomplete chain; left untouched (not pricing-live). Remove/complete under M-2.
