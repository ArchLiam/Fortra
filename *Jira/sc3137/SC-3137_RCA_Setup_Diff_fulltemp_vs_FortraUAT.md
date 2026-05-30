# SC-3137 — RCA Setup Diagnostic: fulltemp vs FortraUAT vs FortraProduction

**Purpose:** verify the data deployment from FortraUAT (source) into fulltemp (target), and compare both against FortraProduction (the eventual source of truth).
**Date run:** 2026-05-20
**Operator:** liam.jeong.c@fortra.com (all three orgs)
**Script:** [`scripts/apex/SC-3137_RCA_Setup_Verification.apex`](../scripts/apex/SC-3137_RCA_Setup_Verification.apex)
**Raw logs:**
- [`scripts/apex/output/rca_diag_FortraProduction.clean.txt`](../scripts/apex/output/rca_diag_FortraProduction.clean.txt)
- [`scripts/apex/output/rca_diag_FortraUAT.clean.txt`](../scripts/apex/output/rca_diag_FortraUAT.clean.txt)
- [`scripts/apex/output/rca_diag_fulltemp.clean.txt`](../scripts/apex/output/rca_diag_fulltemp.clean.txt)

---

## TL;DR

The three orgs are at **three different stages** of the RCA build, and the recent UAT→fulltemp deploy carried over **definitions** but lost most **runtime configuration**:

- ❌ **fulltemp is missing 3 of 5 ExpressionSets** that exist in UAT (incl. all 6 versions of `Rev_Mgmt_Default_Pricing_Procedure`).
- ❌ **fulltemp has 0 of 300 ProductConfigurationRules** present in UAT — prod also has 0.
- ❌ **fulltemp is missing 2 PricingActionParameters** (Order / Quote bindings). Prod also has 0.
- ❌ **fulltemp is missing 1 RuleLibrary** (`Rule_Library` from UAT). **Prod has a different second library entirely** (`ProductRuleLibrary`).
- ❌ **fulltemp is missing 3 DecisionTables** vs UAT. **Prod is missing 10 of UAT's 22**.
- ❌ **`ProductDiscoveryContextExt`** — UAT v21 active, Prod v3 active (newly built 2026-05-15), **fulltemp v1 inactive** → no active version in fulltemp.
- ⚠️ **+866 ContextTags** and **+2 PricingRecipeTableMappings** in fulltemp — stale rows the deploy did not clean up.
- ⚠️ **Production has no TaxPolicy/TaxTreatment objects** (feature not enabled there yet) and **zero AttributeBasedAdjRule, ProductFulfillmentDecompRule** rows — prod is much earlier in the build than UAT/fulltemp.

**Bottom line:** fulltemp cannot run RCA pricing / product discovery as-is. Choose between two re-baselines:
- **From UAT** — get all 300 ConfigurationRules, all ExpressionSets, full Tax + AttributeBasedAdj suite. Highest-fidelity sandbox state.
- **From Prod** — minimal but production-true baseline. Will need UAT's runtime config layered on top.

---

## Section 1 — Context Layer

| Object | FortraProduction | FortraUAT | fulltemp |
| --- | ---: | ---: | ---: |
| ContextDefinition | 2 | 2 | 2 |
| ContextDefinitionVersion | 2 | 2 | 2 |
| ContextNode | 52 | 54 | 53 |
| ContextAttribute | 771 | 918 | 866 |
| ContextMapping | 17 | 17 | 16 |
| ContextNodeMapping | 139 | 142 | 134 |
| ContextAttributeMapping | 2 031 | 2 229 | 2 118 |
| **ContextTag** | 775 | 915 | **1 781** ⚠️ |
| ContextUseCaseMapping | 0 | 6 | 6 |
| ContextParamMap | 0 | 1 248 | 0 |

### ⚠️ Critical: context-version drift — no two orgs are on the same version

| ContextDefinition | FortraProduction | FortraUAT | fulltemp |
| --- | --- | --- | --- |
| `ProductDiscoveryContextExt` | **v3** active=true (created 2026-05-15) | **v21** active=true | **v1 active=false** ❌ |
| `SalesTransactionContextExt` | **v3** active=true (created 2026-05-15) | **v24** active=true | **v2** active=true |

Three independent version trees:
- Prod was rebuilt fresh on 2026-05-15 (v3 in both).
- UAT has gone through 21+/24+ iterations.
- fulltemp's `ProductDiscoveryContextExt v1` is **inactive** — no active version, so the context cannot resolve at runtime.

fulltemp's lower Context* counts vs UAT (−1 node, −52 attrs, −8 node mappings, −111 attr mappings) are consistent with successive CDV bumps adding nodes/attributes that v1/v2 in fulltemp does not yet have.

⚠️ **fulltemp has nearly 2× the ContextTags** as either prod or UAT — stale rows.

---

## Section 2 — Pricing Procedure Layer (largest gap)

| Object | FortraProduction | FortraUAT | fulltemp |
| --- | ---: | ---: | ---: |
| ExpressionSetDefinition | 2 | 5 | 5 |
| **ExpressionSet** | **2** | **5** | **2** |
| **ExpressionSetVersion** | 2 | 10 | 2 |
| **ExpressionSetDefinitionContextDefinition** | 2 | 5 | 4 |

### ExpressionSets present per org
| ExpressionSet | Prod | UAT | fulltemp |
| --- | :---: | :---: | :---: |
| `Product_Discovery_Pricing_Procedure` (DefaultPricing) | ❌ | ✅ | ❌ |
| `Rev_Mgmt_Default_Pricing_Procedure` (DefaultPricing) | ✅ | ✅ | ❌ |
| `Salesforce_Default_Pricing_Discovery_Procedure` (PricingDiscovery) | ✅ | ✅ | ✅ |
| `Salesforce_Pricing_Discovery_Procedure` (PricingDiscovery) | ❌ | ✅ | ✅ |
| `Test` (ProductQualification) | ❌ | ✅ | ❌ |

- **UAT has the full set of 5.**
- **Prod has 2** — only the ones that ship with the package + `Rev_Mgmt_Default_Pricing_Procedure`.
- **fulltemp has a different 2** — the two Salesforce-default ones — and is missing the org-specific `Rev_Mgmt` entirely.

### Missing in fulltemp (vs UAT) — same list as before
- `Product_Discovery_Pricing_Procedure` and its v1 (active in UAT).
- `Rev_Mgmt_Default_Pricing_Procedure` and **all v1–v6** (only v6 active in UAT).
- `Test` and its v1.
- Junction: `Rev_Mgmt_Default_Pricing_Procedure ↔ SalesTransactionContextExt`.

→ If targeting **prod-parity**, fulltemp only needs `Rev_Mgmt_Default_Pricing_Procedure` + v1. If targeting **UAT-parity**, fulltemp needs all 3 missing sets.

---

## Section 3 — Pricing Action & Recipe Layer

| Object | FortraProduction | FortraUAT | fulltemp |
| --- | ---: | ---: | ---: |
| **PricingActionParameters** | **0** | 2 | **0** |
| PricingRecipe | 1 (`NGPDefaultRecipe`) | 1 (`NGPDefaultRecipe`) | 1 (`NGPDefaultRecipe`) |
| **PricingRecipeTableMapping** | 11 | 12 | **14** ⚠️ |
| PricingProcedureOutputMap | **0** | 26 | 26 |

### Missing PricingActionParameters in fulltemp (vs UAT)
- `Order_1773419454521` — proc=`Rev_Mgmt_Default_Pricing_Procedure`, ctx=`SalesTransactionContextExt`, obj=Order
- `Quote_1773419454927` — proc=`Rev_Mgmt_Default_Pricing_Procedure`, ctx=`SalesTransactionContextExt`, obj=Quote

(both reference `Rev_Mgmt_Default_Pricing_Procedure`, which is missing as an ExpressionSet — see Section 2)

Prod also has **0 PricingActionParameters** and **0 PricingProcedureOutputMap** — these are UAT-only configuration that have not been promoted to prod yet.

### Stale extras in fulltemp
- PricingRecipeTableMapping has **14** rows vs UAT 12 vs Prod 11 → investigate the extra 2 in fulltemp (stale from prior state).

---

## Section 4 — Rule Library Layer

| Object | FortraProduction | FortraUAT | fulltemp |
| --- | ---: | ---: | ---: |
| RuleLibrary | 2 | 2 | 1 |
| RuleLibraryDefinition | 2 | 2 | 2 |
| RuleLibraryVersion | 2 | 3 | 1 |
| RuleLibraryDefVersion | 2 | 3 | 3 |

### RuleLibrary DeveloperNames diverge across all three ⚠️
| RuleLibrary | Prod | UAT | fulltemp |
| --- | :---: | :---: | :---: |
| `DRORuleLibrary` | ✅ | ✅ | ✅ |
| `ProductRuleLibrary` | ✅ | ❌ | ❌ |
| `Rule_Library` ("Rule Library for Configurator") | ❌ | ✅ | ❌ |

→ The second RuleLibrary is **named differently in prod (`ProductRuleLibrary`) vs UAT (`Rule_Library`)**. This is not a missing-rows problem — these are two different libraries living in two different orgs. Need to reconcile which DeveloperName should be canonical.

fulltemp has neither of those second libraries — only `DRORuleLibrary`.

The Definition rows for both libraries exist in fulltemp; only the runtime `RuleLibrary` + versions are missing.

---

## Section 5 — Product Catalog Layer

| Object | FortraProduction | FortraUAT | fulltemp |
| --- | ---: | ---: | ---: |
| Product2 (total) | **5 421** | 8 846 | 8 846 |
| Product2 (active) | 5 421 | 7 453 | 7 453 |
| ProductClassification | 110 | 121 | 121 |
| ProductConfigurationFlow | 0 | 1 | 1 |
| **ProductConfigurationRule** | **0** | **300** | **0** ⚠️ |
| ProductFulfillmentDecompRule | _object not in org_ | 3 326 | 3 326 |
| AttributeBasedAdjRule | **0** | 25 171 | 25 171 |
| AttributeDefinition | 16 | 17 | 17 |
| AttributeCategory | 11 | 11 | 11 |

- **fulltemp has 0 ProductConfigurationRules** — none of UAT's 300 made it across.
- **Prod also has 0** — so prod doesn't yet know about any of the 300 rules.
- **`ProductFulfillmentDecompRule` object does not exist in prod yet** (sandbox-only preview).
- **`AttributeBasedAdjRule` is empty in prod** but 25,171 in UAT and fulltemp.
- **Product2 in prod is 5,421** vs 8,846 in UAT/fulltemp — sandboxes have 3,425 more products than prod, likely test data.

---

## Section 6 — Decision Table Layer

| Object | FortraProduction | FortraUAT | fulltemp |
| --- | ---: | ---: | ---: |
| DecisionMatrixDefinition | 0 | 0 | 0 |
| **DecisionTable** | 12 | 22 | 19 |
| **DecisionTableParameter** | 113 | 179 | 163 |
| CalculationMatrixColumn | 0 | 0 | 0 |

### DecisionTables — by org membership
| DecisionTable DeveloperName | Prod | UAT | fulltemp |
| --- | :---: | :---: | :---: |
| `Asset_Action_Source_Entries_Decision_Table_V2` | ✅ | ✅ | ✅ |
| `Attribute_Based_Adjustment_Decision_Table` | ✅ | ✅ | ✅ |
| `Attribute_Tier_Pricing_Matrix` | ❌ | ✅ | ✅ |
| `Bundle_Based_Adjustment_Decision_Table` | ✅ | ✅ | ✅ |
| `CalculatedVolumeDiscountPriceAdjusmentTier` | ❌ | ✅ | ✅ |
| `Contract_Pricing_Adjustment_Tiers` | ✅ | ✅ | ✅ |
| `Contract_Pricing_Entries_Decision_Table` | ✅ | ✅ | ✅ |
| `Contract_Pricing_Volume_Tiers` | ✅ | ✅ | ✅ |
| `Cyber_Partner_Discount_Matrix` | ❌ | ✅ | ✅ |
| `Derived_Pricing_Entries_Decision_Table` | ✅ | ✅ | ✅ |
| `Fortra_Regional_Pricing` | ❌ | ✅ | ✅ |
| `Fulfillment_Step_Jeopardy_Rule_Decision_Table` | ❌ | ✅ | ❌ |
| `FulfillmentFalloutRules` | ❌ | ✅ | ❌ |
| `Index_Rate_Decision_Table` | ✅ | ✅ | ✅ |
| `MaintenanceType` | ❌ | ✅ | ❌ |
| `Price_Adjustment_Tier_Decision_Table` | ✅ | ✅ | ✅ |
| `Price_Book_Entry_Decision_Table_v2` | ✅ | ✅ | ✅ |
| `PriceModeVolumeDiscountPriceAdjusmentTier` | ❌ | ✅ | ✅ |
| `Regional_Pricing` | ❌ | ✅ | ✅ |
| `StandardTax` | ✅ | ✅ | ✅ |
| `Tech_Partner_Discount_Matrix` | ❌ | ✅ | ✅ |
| `Tiered_Adjustment_Tier_Decision_Table` | ✅ | ✅ | ✅ |
| **Total** | **12** | **22** | **19** |

- **fulltemp vs UAT:** missing 3 — `Fulfillment_Step_Jeopardy_Rule_Decision_Table`, `FulfillmentFalloutRules`, `MaintenanceType`.
- **Prod vs UAT:** missing 10 — fulfillment/maintenance/partner-discount/regional-pricing tables that UAT has built but have not been promoted to prod.

---

## Section 7 — Permset audit (operator user)

| Permset | FortraProduction | FortraUAT | fulltemp |
| --- | :---: | :---: | :---: |
| `ProductCatalogManagementAdministrator` | ❌ MISSING | ❌ MISSING | ✅ ASSIGNED |
| `UnifiedCatalogAdmin` | ❌ MISSING | ❌ MISSING | ✅ ASSIGNED |
| `Revenue_Cloud_Admin` | ❌ **MISSING** | ✅ ASSIGNED | ✅ ASSIGNED |

→ The operator user has **zero RCA admin permsets in prod** and **only Revenue_Cloud_Admin in UAT**. Assign the missing ones before running RCA admin work in those orgs.

---

## Section 8 — DML restrictions (identical in all three orgs)

No `GearsetExternalId__c` on any of the listed objects in any org:

| Object | createable | updateable | deletable |
| --- | :---: | :---: | :---: |
| ContextDefinition | ❌ | ❌ | ❌ |
| ContextDefinitionVersion | ❌ | ❌ | ❌ |
| ExpressionSet | ✅ | ✅ | ✅ |
| ExpressionSetVersion | ✅ | ✅ | ✅ |
| ExpressionSetDefinition | ❌ | ❌ | ❌ |
| PricingActionParameters | ❌ | ❌ | ❌ |
| ContextNode | ❌ | ❌ | ❌ |
| ContextAttribute | ❌ | ❌ | ❌ |

→ Context*, ExpressionSetDefinition, and PricingActionParameters are not directly DML-able in any of the three orgs; they must move via metadata (Context Definition deployment), not data-loader inserts. This is why the ContextDefinitionVersions diverge: the source-of-truth version-bumping path was not used during deploy.

---

## Suggested next steps

The right action depends on whether you want fulltemp to mirror **UAT** (richest config) or **Prod** (baseline shipped state):

### Path A — re-baseline fulltemp from UAT (everything UAT has built)
1. **Re-deploy ExpressionSets + versions** from UAT: `Product_Discovery_Pricing_Procedure`, `Rev_Mgmt_Default_Pricing_Procedure` (v1–v6), `Test`, and the missing Rev_Mgmt junction.
2. **Bring across all 300 ProductConfigurationRules** from UAT.
3. **Activate the correct ContextDefinitionVersions**: re-deploy UAT's `ProductDiscoveryContextExt v21` and `SalesTransactionContextExt v24` (or activate v1/v2 if a fresh version path is preferred).
4. **Re-deploy** `Rule_Library` ("Rule Library for Configurator") + 2 versions from UAT.
5. **Re-deploy** the 3 missing DecisionTables (`Fulfillment_Step_Jeopardy_Rule_Decision_Table`, `FulfillmentFalloutRules`, `MaintenanceType`) and their parameters.
6. **Re-deploy** the 2 PricingActionParameters (Order/Quote), after Rev_Mgmt ExpressionSet is in place.

### Path B — re-baseline fulltemp from Prod (production-true shape)
1. Drop the missing-but-UAT-only items above — prod doesn't have them either.
2. **Reconcile RuleLibrary naming** — Prod has `ProductRuleLibrary`; UAT has `Rule_Library`. Decide which name is canonical and align both directions.
3. **Bring across `Rev_Mgmt_Default_Pricing_Procedure` + v1** (from prod or UAT — they agree on this one).
4. **Re-create `ProductDiscoveryContextExt v3` and `SalesTransactionContextExt v3`** in fulltemp (or rebuild fresh — these are the live prod versions).
5. Recognize that prod has **no Tax objects, no FulfillmentDecompRule object, no AttributeBasedAdjRule rows, no ConfigurationRules** — so a prod baseline is much thinner. Plan whether those features are scoped for the next prod release.

### Both paths — clean up stale rows in fulltemp
- **+866 ContextTags** in fulltemp vs UAT (and **+1006 vs prod**) — decide whether to clean up.
- **+2 PricingRecipeTableMappings** in fulltemp vs UAT (and **+3 vs prod**) — investigate.
