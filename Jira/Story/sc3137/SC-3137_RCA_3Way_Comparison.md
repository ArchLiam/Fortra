# SC-3137 — RCA 3-Way Comparison: FortraProduction · FortraUAT · fulltemp

**Date run:** 2026-05-20
**Operator:** liam.jeong.c@fortra.com (all three orgs)
**Scripts:**
- [`scripts/apex/SC-3137_RCA_Setup_Verification.apex`](../scripts/apex/SC-3137_RCA_Setup_Verification.apex)
- [`scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex`](../scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex)

**Raw logs:**
- [`rca_diag_FortraProduction.clean.txt`](../scripts/apex/output/rca_diag_FortraProduction.clean.txt)
- [`rca_diag_FortraUAT.clean.txt`](../scripts/apex/output/rca_diag_FortraUAT.clean.txt)
- [`rca_diag_fulltemp.clean.txt`](../scripts/apex/output/rca_diag_fulltemp.clean.txt)
- [`rca_size_FortraProduction.clean.txt`](../scripts/apex/output/rca_size_FortraProduction.clean.txt)
- [`rca_size_FortraUAT.clean.txt`](../scripts/apex/output/rca_size_FortraUAT.clean.txt)
- [`rca_size_fulltemp.clean.txt`](../scripts/apex/output/rca_size_fulltemp.clean.txt)

---

## TL;DR

| Org | RCA Rows | RCA Size | vs 5 GB cap |
| --- | ---: | ---: | ---: |
| **FortraProduction** | **52,553** | **~102.6 MB (~0.10 GB)** | 2 % used |
| **FortraUAT** | **217,990** | **~425.8 MB (~0.42 GB)** | 8 % used |
| **fulltemp** | **102,437** | **~200.1 MB (~0.20 GB)** | 4 % used |

- **All three would fit comfortably** in a Partial Copy sandbox (5 GB limit).
- The **10K-rows-per-object refresh-template cap** is exceeded only by `PricebookEntry` in all three, plus `AttributeBasedAdjRule` in UAT and fulltemp. Prod's `AttributeBasedAdjRule` is empty.
- **Production is the smallest org** by far — most RCA *runtime* config (PricingActionParameters, ProductConfigurationRule, AttributeBasedAdjRule, ProductFulfillmentDecompRule) is **not yet in prod**.
- **TaxPolicy / TaxTreatment objects are not even present in prod** (feature not enabled there yet).
- **The operator user has zero RCA admin permsets in production** (`Revenue_Cloud_Admin`, `ProductCatalogManagementAdministrator`, `UnifiedCatalogAdmin` all MISSING).

---

## Size totals by layer

| Layer | FortraProduction | FortraUAT | fulltemp |
| --- | ---: | ---: | ---: |
| Context | 3,789 rows / 7.40 MB | 5,533 rows / 10.81 MB | 4,978 rows / 9.72 MB |
| Pricing Procedure | 20 / 0.04 MB | 66 / 0.13 MB | 54 / 0.11 MB |
| Rule Library | 8 / 0.02 MB | 10 / 0.02 MB | 7 / 0.01 MB |
| Decision Table | 149 / 0.29 MB | 243 / 0.47 MB | 220 / 0.43 MB |
| Product Catalog | 19,536 / 38.16 MB | 24,527 / 47.90 MB | 24,527 / 47.90 MB |
| Pricing Catalog | 29,051 / 56.74 MB | **183,984 / 359.34 MB** | 69,324 / 135.40 MB |
| Configuration Rules | 0 / 0.00 MB | 3,627 / 7.08 MB | 3,327 / 6.50 MB |
| **TOTAL** | **52,553 / 102.64 MB** | **217,990 / 425.76 MB** | **102,437 / 200.07 MB** |

---

## Section 1 — Context Layer (per object)

| Object | Production | UAT | fulltemp |
| --- | ---: | ---: | ---: |
| ContextDefinition | 2 | 2 | 2 |
| ContextDefinitionVersion | 2 | 2 | 2 |
| ContextNode | 52 | 54 | 53 |
| ContextAttribute | 771 | 918 | 866 |
| ContextMapping | 17 | 17 | 16 |
| ContextNodeMapping | 139 | 142 | 134 |
| ContextAttributeMapping | 2,031 | 2,229 | 2,118 |
| ContextTag | 775 | 915 | **1,781** ⚠️ |
| ContextUseCaseMapping | 0 | 6 | 6 |
| ContextParamMap | 0 | 1,248 | 0 |

### Context-version drift
| ContextDefinition | Production | FortraUAT | fulltemp |
| --- | --- | --- | --- |
| `ProductDiscoveryContextExt` | **v3 active=true** (created 2026-05-15) | v21 active=true | **v1 active=false** ❌ |
| `SalesTransactionContextExt` | **v3 active=true** (created 2026-05-15) | v24 active=true | v2 active=true |

→ Prod is on **v3** (freshly created mid-May). UAT has gone through 21+/24+ iterations. fulltemp has the oldest versions and `ProductDiscoveryContextExt` is **inactive**. None of the three orgs share a version number — they have drifted independently.

---

## Section 2 — Pricing Procedure Layer

| Object | Production | UAT | fulltemp |
| --- | ---: | ---: | ---: |
| ExpressionSetDefinition | 2 | 5 | 5 |
| ExpressionSet | 2 | 5 | 2 |
| ExpressionSetVersion | 2 | 10 | 2 |
| ExpressionSetDefinitionContextDefinition | 2 | 5 | 4 |
| PricingActionParameters | **0** | 2 | 0 |
| PricingRecipe | 1 | 1 | 1 |
| PricingRecipeTableMapping | 11 | 12 | 14 |
| PricingProcedureOutputMap | **0** | 26 | 26 |

### ExpressionSets present in each org
| ExpressionSet | Prod | UAT | fulltemp |
| --- | :---: | :---: | :---: |
| `Product_Discovery_Pricing_Procedure` | ❌ | ✅ | ❌ |
| `Rev_Mgmt_Default_Pricing_Procedure` | ✅ | ✅ | ❌ |
| `Salesforce_Default_Pricing_Discovery_Procedure` | ✅ | ✅ | ✅ |
| `Salesforce_Pricing_Discovery_Procedure` | ❌ | ✅ | ✅ |
| `Test` | ❌ | ✅ | ❌ |

→ Only **2 of 5** ExpressionSets exist in prod. UAT has the full set. fulltemp has a different 2-of-5 subset.

---

## Section 3 — Pricing Action & Recipe

| Object | Production | UAT | fulltemp |
| --- | ---: | ---: | ---: |
| **PricingActionParameters** | **0** | 2 | 0 |
| PricingRecipe | 1 (`NGPDefaultRecipe`) | 1 (`NGPDefaultRecipe`) | 1 (`NGPDefaultRecipe`) |
| PricingRecipeTableMapping | 11 | 12 | 14 |
| PricingProcedureOutputMap | **0** | 26 | 26 |

→ Prod has the `NGPDefaultRecipe` shell but **no output-map rows and no Action Parameters** — runtime wiring is absent in prod.

---

## Section 4 — Rule Library

| Object | Production | UAT | fulltemp |
| --- | ---: | ---: | ---: |
| RuleLibrary | 2 | 2 | 1 |
| RuleLibraryDefinition | 2 | 2 | 2 |
| RuleLibraryVersion | 2 | 3 | 1 |
| RuleLibraryDefVersion | 2 | 3 | 3 |

### Names differ across orgs ⚠️
| RuleLibrary DeveloperName | Prod | UAT | fulltemp |
| --- | :---: | :---: | :---: |
| `DRORuleLibrary` | ✅ | ✅ | ✅ |
| `ProductRuleLibrary` | ✅ | ❌ | ❌ |
| `Rule_Library` ("Rule Library for Configurator") | ❌ | ✅ | ❌ |

→ Prod and UAT have **different second-library names**: prod has `ProductRuleLibrary`, UAT has `Rule_Library`. fulltemp has only `DRORuleLibrary`. Three different states.

---

## Section 5 — Product Catalog

| Object | Production | UAT | fulltemp |
| --- | ---: | ---: | ---: |
| Product2 (total / active) | 5,421 / 5,421 | 8,846 / 7,453 | 8,846 / 7,453 |
| ProductCatalog | 2 | 2 | 2 |
| ProductCategory | 187 | 187 | 187 |
| **ProductCategoryProduct** | **4,047** | 2,200 | 2,200 |
| ProductClassification | 110 | 121 | 121 |
| ProductClassificationAttr | 372 | 379 | 379 |
| ProductRelatedComponent | 1,401 | 1,417 | 1,417 |
| ProductComponentGroup | 416 | 421 | 421 |
| ProductSellingModel | 9 | 9 | 9 |
| **ProductSellingModelOption** | **5,421** | 8,794 | 8,794 |
| AttributeDefinition | 16 | 17 | 17 |
| AttributeCategory | 11 | 11 | 11 |
| AttributePicklist | 15 | 15 | 15 |
| AttributePicklistValue | 2,108 | 2,108 | 2,108 |

→ Production has **3,425 fewer Product2 records** than UAT/fulltemp, but **1,847 more ProductCategoryProduct rows** — products in prod are mapped to more categories on average.

---

## Section 6 — Decision Tables

| Object | Production | UAT | fulltemp |
| --- | ---: | ---: | ---: |
| DecisionMatrixDefinition | 0 | 0 | 0 |
| DecisionTable | 12 | 22 | 19 |
| DecisionTableParameter | 113 | 179 | 163 |
| DecisionTableDatasetLink | 12 | 22 | 19 |
| CalculationMatrix | 12 | 20 | 19 |
| CalculationMatrixVersion / Row / Column | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |

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

→ UAT has the richest set (22). Prod is missing 10 of them, mostly the partner-discount/regional-pricing/fulfillment/maintenance tables.

---

## Section — Pricing Catalog (huge variance)

| Object | Production | UAT | fulltemp |
| --- | ---: | ---: | ---: |
| Pricebook2 | 1 | 11 | 2 |
| **PricebookEntry** | **27,093** | **158,798** | **44,144** |
| PriceAdjustmentSchedule | 3 | 1 | 3 |
| **PriceAdjustmentTier** | **1,953** | 0 | 0 |
| **AttributeBasedAdjRule** | **0** | **25,171** | **25,171** |
| ProrationPolicy | 1 | 1 | 1 |
| TaxPolicy | _not in org_ | 1 | 1 |
| TaxTreatment | _not in org_ | 1 | 2 |
| TaxRate | 0 | 0 | 0 |

→ Three very different shapes:
- **Prod:** 1 pricebook, 27K entries, 1,953 price-adjustment tiers, no AttributeBasedAdjRule, **no Tax objects at all**.
- **UAT:** 11 pricebooks, **158K entries**, 25K adjustment rules, has Tax.
- **fulltemp:** 2 pricebooks, 44K entries, identical 25K adjustment rules as UAT (so deploy did preserve those), has Tax.

---

## Section 7 — Configuration Rules

| Object | Production | UAT | fulltemp |
| --- | ---: | ---: | ---: |
| ProductConfigurationFlow | 0 | 1 | 1 |
| **ProductConfigurationRule** | **0** | **300** | **0** |
| ProductFulfillmentDecompRule | _not in org_ | 3,326 | 3,326 |

→ Prod has **no ProductConfigurationRules** at all — these are still being built in UAT. fulltemp received the FulfillmentDecompRules from UAT (3,326 match) but **not** the 300 ConfigurationRules.

---

## Section — Permset audit (operator, current user)

| Permset | Production | UAT | fulltemp |
| --- | :---: | :---: | :---: |
| `ProductCatalogManagementAdministrator` | ❌ MISSING | ❌ MISSING | ✅ ASSIGNED |
| `UnifiedCatalogAdmin` | ❌ MISSING | ❌ MISSING | ✅ ASSIGNED |
| `Revenue_Cloud_Admin` | ❌ **MISSING** | ✅ ASSIGNED | ✅ ASSIGNED |

→ Your prod user is missing **all three** RCA admin permsets. UAT user is missing PCM/UC Admin. fulltemp has all three. Assign them in prod (and ideally in UAT) before doing direct RCA admin work there.

---

## Section — DML restrictions (identical across orgs)

In all three orgs, the same setup-style objects are non-DML-able (no `GearsetExternalId__c` on any):

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

→ Context*, ExpressionSetDefinition, and PricingActionParameters must be deployed via **metadata (Context Definition deployment)**, not direct data load. This applies equally to any prod → MergeBuild migration.

---

## MergeBuild sizing — implications by source choice

The user asked about **moving RCA data to MergeBuild (Partial Copy)**. The source matters:

| Source org | Total size | Largest object | 10K-row-cap violations (refresh-template path only) |
| --- | ---: | --- | --- |
| **FortraProduction** | **102.6 MB** | PricebookEntry (27,093) | **1** object: PricebookEntry |
| **FortraUAT** | **425.8 MB** | PricebookEntry (158,798) | **2** objects: PricebookEntry, AttributeBasedAdjRule (25,171) |
| **fulltemp** | **200.1 MB** | PricebookEntry (44,144) | **2** objects: PricebookEntry, AttributeBasedAdjRule (25,171) |

All three fit comfortably in MergeBuild's 5 GB cap.

**Recommended path:** direct data load (Bulk API / Data Loader / Gearset / Salto) — bypasses the 10K cap. None of these orgs need anywhere near 5 GB.

If migrating from prod specifically, expect to also need to **layer UAT's runtime config on top** (ConfigurationRules, AttributeBasedAdjRule, additional ExpressionSets/versions, Tax objects, missing DecisionTables) — these don't exist in prod yet.

---

## Net observation

Each of the three orgs is at a **different stage of the RCA build**:

- **Prod** — early/baseline. Has the core definitions and 2 ExpressionSets, but most runtime configuration (Rules, Adjustment Rules, Tax, FulfillmentDecompRules) is absent. Context versions on v3.
- **UAT** — the most-built. Full ExpressionSet set, 300 ConfigurationRules, 3,326 FulfillmentDecompRules, full Tax + AttributeBasedAdj, ContextDefinitionVersions on v21/v24.
- **fulltemp** — partial copy of UAT after a recent data deploy. Got most volume-heavy data (Product2, AttributeBasedAdjRule, ProductFulfillmentDecompRule) but missed the 300 ConfigurationRules and several ExpressionSets/versions. Its ContextDefinitionVersions stayed on v1/v2 — the deploy did **not** carry version state.

Before refreshing/loading into MergeBuild, decide which org's state you actually want as the seed — prod for "ship-ready baseline," UAT for "everything we've built so far."
