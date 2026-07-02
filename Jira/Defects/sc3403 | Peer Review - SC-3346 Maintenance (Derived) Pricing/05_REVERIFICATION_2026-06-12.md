# 05 — Re-verification of all blockers/defects (2026-06-12)

Trigger: "Nir said fixed the issues." Re-verified every B-/M- finding from `02_BLOCKERS_AND_DEFECTS.md` against **live FortraUAT** (default org) on 2026-06-12, not against local/stale copies. Method: fresh Apex test run `707WC00002yM0Cm` (147/147 pass, 0 fail), live Tooling-API class bodies, live data queries, and the live active `ExpressionSetDefinition` (`Rev_Mgmt_Default_Pricing_Procedure`, retrieved to `Data/sc-maint/reverify/expset/`). Verification artifacts under `Data/sc-maint/reverify/`.

## Verdict: NOT all fixed — 4 RESOLVED · 3 PARTIAL · 4 NOT RESOLVED. **NO-GO stands.**

Nir made real changes today (2026-06-12): created the 2 missing `PriceBookEntryDerivedPrice` rows (M-5, 20:11Z), edited `COLAUpliftPrehook` (19:59Z) and `PartnerNetPricePosthook` (20:42Z) — landing the B-3 partner-rate fix and renewal-maintenance net persistence (B-4 symptom). But the two **formula-level** defects (B-4 null-guards, M-2 competing formulas), the **decision-table** blocker (B-5), and the doc/coverage items remain.

| ID | Sev | Finding (short) | Status | Live evidence (2026-06-12) |
|----|-----|-----------------|--------|----------------------------|
| **B-3** | 🔴 | Partner rate picks Software 15% not Maint 12% | ✅ **RESOLVED** | `PartnerPricingService` bulk overload now falls through to Product2 lookup on map-miss (live L241/244 `return resolveProductType(contextProductType, quoteLineItemId)`), no more hard `return 'Software'`. Test `…usesProductTypeFromBulkMapWhenContextBlank` **passes**. |
| **B-4** | 🔴 | Renewal carry-forward broken | 🟡 **PARTIAL** | Symptom fixed: order 00095475 line now Base=71/PriorPartner=8.52/UnitPrice=60.64 (was null/null/0). **But** the renewal formula (active block, file L66873) is **byte-identical** to the review — **no IsNull/BLANKVALUE guards** on Base/Prior*/COLA. Unguarded fallback untested (1 of 16,482 lines; that one rescued by the `COLACalculatedPrice>0` branch). Still effectively a blocker. |
| **B-5** | 🔴 | Renewal source decision table refresh FAILED | ❌ **NOT RESOLVED** | `Asset_Action_Source_Entries_Decision_Table_V2` still `RefreshStatus=Failed`, `LastSyncDate=null`, same `Hash Key Group contains more than 200 rows`. `LastModifiedDate=2026-06-12T20:52Z` (re-attempted today, still fails). Only Failed table in org. AssetActionSource=430,335. |
| **B-6** | 🔴 | Decomposition persisted inconsistently | ✅ **RESOLVED** | `MaintenanceOrderDecompositionService.buildPatchesFromWork` sets Base=decomp.maintenanceBase (L312); `OrderRepriceInvocable` calls persistFromWork **unconditionally** (L38/L70). Live: **0** maintenance OIs with Base=355 license leak; all 13 maint OIs since 2026-06-11 carry Base = source×0.20 (e.g. 00095467 Base 55000 = 275000×0.20). |
| **M-1** | 🟠 | "No Apex prehook" principle false | ❌ **NOT RESOLVED** | Both `COLAUpliftPrehook` (L21) & `PartnerNetPricePosthook` (L22) still `implements RevSignaling.SignalingApexProcessor` and still write net; Nir edited them today but did **not** remove them. SDD/HANDOFF still claim "no prehook" — not reconciled. (Design/doc item, not a runtime defect.) |
| **M-2** | 🟠 | Two competing new-business formulas | ❌ **NOT RESOLVED** | Active block still has **3** NetUnitPrice writers on derived lines: `DerivedPricingNetUnitPriceValueReset` (→0 for new-biz, L66743), `DerivedPricingFormula` (×Source_List_Price__c, gate `MTD`, L66678), `DerivedPricingNewBusiness` (×Base_Price__c, gate `MDT`+renewal, L66808). Inconsistent `MTD` vs `MDT` literal persists. |
| **M-3** | 🟠 | contextDefinitionName / prod context gap | 🟡 **PARTIAL** | UAT reprice test `reprice_seedsQuotePricingBeforeExecutor` now **passes**; UAT has `SalesTransactionContextExt_v2`. **PROD still lacks it** (only base `SalesTransactionContextExt`); PNP still hardcodes `…_v2` (L28). Prod deploy still blocked. |
| **M-4** | 🟠 | Source_List_Price__c Q2O mapping disabled | ✅ **RESOLVED** | LIVE deployed `QuoteToOrderFieldMapper` (240 lines) has the mapping **active** (L134-137, merge L195-196); no disabled block. Only the stale repo copies (force-app + Data/sc-maint/src) still show the commented-out version. |
| **M-5** | 🟠 | 2 of 4 derived PBEs lack PBEDP | ✅ **RESOLVED** | All 4 PBEs now have `PriceBookEntryDerivedPrice` (Formula=UnitPrice). The 2 missing (XPNZ RRM-Standard, XPPB RRM-Fortra/OneTime) created **2026-06-12 20:11Z by Nir Kailash**. All 4 active. |
| **M-6** | 🟠 | COLAUpliftPrehook prod copy stale | ❌ **NOT RESOLVED** | Prod=39,956 vs UAT=43,272 (delta 3,316, exactly as reviewed). Prod has **zero** renewal-maintenance COLA refs. Nuance: SC-3346 is UAT-only; prod deploy intentionally pending → likely *correctly* still open, not a live prod defect. Divergent lineages (prod=Marc, UAT=Nir) — needs reconcile, not overwrite. |
| **M-7** | 🟠 | Renewal classes untested | 🟡 **PARTIAL** | `RenewalMaintenancePricingService` **2%→92%** ✅. **But** `RenewalQuoteHeaderHandler` 15% and `RenewalAssetQuantityHandler` 36% **unchanged**; `PartnerPricingService` 42%; `COLAUpliftPrehook` 0%. |

## Version-label reconciliation
The active procedure block's `<versionNumber>` element = **12**, but its `<fullName>`/label = **"…V130" / "Rev Mgmt Default Pricing V13"** — it is the only `<status>Active</status>` block. So the review's "V130:" line refs *were* against the active version; my earlier "active is V12 not V13" was reading the `<versionNumber>` element of that same block. Same block, two labels. The procedure churns versions daily — re-verify formulas against the live Active block after any republish.

## Must-close before GO
1. **B-5** — re-design the decision-table hash key (<200 rows/group) or filter AssetActionSource; require `RefreshStatus=Completed`.
2. **B-4** — add IsNull/BLANKVALUE guards to `DerivedPricingRenewals`; add a Year-2→Year-3 test that actually exercises the discount fallback (COLACalculatedPrice=0).
3. **M-2** — collapse to ONE new-business formula; fix `MTD`/`MDT`.
4. **M-7** — cover `RenewalQuoteHeaderHandler` / `RenewalAssetQuantityHandler`.
5. **M-1 / M-3 / M-6** — doc reconciliation + prod context/prehook deploy plan (prod-auth gated).
