# 07 — B-4 fix plan: renewal formula null-guards

**Status:** ✅ DONE + ACCEPTED 2026-06-12 — V14 **ACTIVATED** (sole active version), reprice clean (no gack), renewal formula computes **67.38** in-flight on the null-COLACalc fallback (proves the ISNULL guard works; no V15 needed). **Caveat:** committed renewal price on a maintenance-only quote is still blocked by `MissingContributor` (**SC-3372**, separate) — contributor resolved via M-5 PBEDP but not on the cart. Cutover note: the LWC "Reactivate All Dependencies" caused an 8-versions-active corruption; recovered via per-row Activate to single-active V14.

**(historical) STEP 1 — V14 deployed Inactive to FortraUAT (authorized; B-4 only, M-2 not bundled). Verified live: V140 block present, ISNULL-guarded renewal formula in V14, exactly 1 Active version (still V13), 14 blocks total. **Zero live impact** until V14 is activated. STEP 2 (activate V14 + context resync + validation) PENDING — the deliberate cutover.

Working dir: `Data/sc-maint/sc3346_b4/` (apply/ = deployed source; clone_v14.py = the surgical clone+edit; verify_x/ = post-deploy re-retrieve). Deployed via `sf project deploy start --metadata-dir apply/unpackaged` (dry-run passed first; the `metadata.transfer:Finalizing` CLI error was cosmetic — deploy landed).

## The exact change
- **Element:** `DerivedPricingRenewals` (label "Derived Pricing - Renewals"), in the active procedure version, formula `<value>` at **line 66873**, output `NetUnitPrice`.
- **Active version:** the only `<status>Active</status>` block (line 64841), `fullName …_V130`, label "Rev Mgmt Default Pricing V13". (The `<versionNumber>12</versionNumber>` at L64829 belongs to the *preceding inactive* block — clone the V13/V130 block.)

**BEFORE** (verbatim):
```
IF ( QuoteTypeText__c = 'Renewal' , IF ( COLACalculatedPrice__c > 0 , COLACalculatedPrice__c , ( Base_Price__c - Prior_Partner_Discount__c - Prior_Discretionary_Discount__c ) * ( 1 + ( COLA_Uplift_Percent__c / 100 ) ) ) , NetUnitPrice )
```
**AFTER** (only the ELSE-arm operands wrapped; gate + COLA branch byte-identical):
```
IF ( QuoteTypeText__c = 'Renewal' , IF ( COLACalculatedPrice__c > 0 , COLACalculatedPrice__c , ( IF ( ISNULL ( Base_Price__c ) , 0 , Base_Price__c ) - IF ( ISNULL ( Prior_Partner_Discount__c ) , 0 , Prior_Partner_Discount__c ) - IF ( ISNULL ( Prior_Discretionary_Discount__c ) , 0 , Prior_Discretionary_Discount__c ) ) * ( 1 + ( IF ( ISNULL ( COLA_Uplift_Percent__c ) , 0 , COLA_Uplift_Percent__c ) / 100 ) ) ) , NetUnitPrice )
```

## CRITICAL correction to the original peer-review spec: ISNULL, not BLANKVALUE
The review's fix said `BLANKVALUE(x,0)`. **`BLANKVALUE` has zero precedent in this RLM ExpressionSet engine** (grep of the 70,448-line file: `BLANKVALUE`=0, `NULLVALUE`=0, `ISBLANK`=0, `ISNULL`=14). `ISNULL` is the house idiom and **already compiles inside the active block** (lines 68196, 68261: `IF ( ISNULL ( ItemTotalAdjustmentAmount ) , 0 , … )`). `BLANKVALUE` only appears in `.flow` metadata (a different formula engine) — using it here risks a deploy-time compile rejection. **Use ISNULL.**

This brings the procedure into parity with the Apex `RenewalMaintenancePricingService.computeColaNet` (already null-guards each operand) — a convergent fix, not new behavior.

## Execution mechanism — clone, don't edit in place
Editing the active version in place is the exact anti-pattern that caused the `contextDefinitionName` gack. Both prior deploys (SC-3345 V9, SC-3374 V10) cloned a new version. So:
1. Fresh-retrieve live (active version churns V9→V12→V13 in days) — abort if it's churned past V13.
2. **Clone** the Active V13 block → new **V14** block, `<status>Inactive</status>`; leave V13 byte-identical.
3. Apply the one formula edit (line 66873) **inside the V14 clone only**.
4. Validate-only deploy → real deploy. **V14 lands Inactive = zero live impact.**
5. **Activate V14** (Setup → ExpressionSet builder; auto-deactivates V13).
6. **MANDATORY context resync** (the gack mitigation): Context Def Manager LWC → Deactivate All Dependencies → verify `SalesTransactionContextExt_v2` OrderEntitiesMapping carries all 7 attrs the formula reads → Sync/re-publish → Reactivate All Dependencies. **Skipping this re-opens gack 572633412-308158.**
7. **Rollback** (if needed): re-Activate V13 (version delete is platform-blocked) + re-sync context.

`ExpressionSetDefinition` metadata-deploys cleanly (unlike the B-5 DecisionTable) — proven by the prior v9/v10 deploys. mdapi 2-type package (ContextDefinition + ExpressionSetDefinition).

## Validation
- **B-4 positive:** Year-2→Year-3 renewal, Base_Price__c=71, priors null, COLACalculatedPrice__c=0 → Reprice All → assert NetUnitPrice = 71 (not 0/garbage).
- **No-gack gate (highest priority):** any non-renewal quote → Reprice All / Convert → completes with NO contextDefinitionName gack (proves resync took).
- **Shared-ticket regressions (expected no-ops, all on non-renewal branches):** SC-3393 Services add, SC-3372 derived PBE, SC-3359 partner net, SC-3384 non-USD line.
- **Apex:** `RenewalMaintenancePricingServiceTest` + neighbors green.

## M-2 bundling (optional)
The adjacent `DerivedPricingNewBusiness` (line 66808) has the same unguarded `Base_Price__c` and could take the same ISNULL guard in the same V14 edit/resync cycle (saves a second risky cycle). **But** this is only the *null-guard slice* of M-2 — M-2's core issue (competing new-business formulas + `MTD` vs `MDT` filter mismatch) is a separate, larger design decision. Bundling the null-guard is cheap hardening; full M-2 resolution is its own item. Confirm with Finance that null `Base_Price__c`→0 (new business) is acceptable before bundling.

## Finance/semantics note
ISNULL→0 means: null priors → price = Base_Price__c; null COLA → 1.0 (no uplift). For a *real* Year-3 renewal these are non-null (carried forward), so this is an edge/safety guard against mis-pricing — but confirm "no prior + no COLA → price = Base" is the intended floor, not a default uplift.
