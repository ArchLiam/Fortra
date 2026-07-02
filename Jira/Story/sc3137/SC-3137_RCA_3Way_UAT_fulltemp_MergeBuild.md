# SC-3137 — RCA 3-Way Comparison: FortraUAT · fulltemp · MergeBuild

**Date run:** 2026-05-21
**Operator:** liam.jeong.c@fortra.com (all three orgs)
**Purpose:** full side-by-side of the two candidate sources (UAT, fulltemp) against the migration target (MergeBuild), before loading RCA configuration data.

**Source scripts:**
- [`scripts/apex/SC-3137_RCA_Setup_Verification.apex`](../scripts/apex/SC-3137_RCA_Setup_Verification.apex)
- [`scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex`](../scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex)

**Raw logs:**
- UAT — [`rca_diag_FortraUAT.clean.txt`](../scripts/apex/output/rca_diag_FortraUAT.clean.txt) · [`rca_size_FortraUAT.clean.txt`](../scripts/apex/output/rca_size_FortraUAT.clean.txt)
- fulltemp — [`rca_diag_fulltemp.clean.txt`](../scripts/apex/output/rca_diag_fulltemp.clean.txt) · [`rca_size_fulltemp.clean.txt`](../scripts/apex/output/rca_size_fulltemp.clean.txt)
- MergeBuild — [`rca_diag_MergeBuild.clean.txt`](../scripts/apex/output/rca_diag_MergeBuild.clean.txt) · [`rca_size_MergeBuild.clean.txt`](../scripts/apex/output/rca_size_MergeBuild.clean.txt)

---

## TL;DR

| Metric | FortraUAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: |
| **Total RCA rows** | **217,990** | **102,437** | **35,173** |
| **Estimated size** | ~425.8 MB | ~200.1 MB | **~68.7 MB** |
| Fits in 5 GB cap | ✅ (8%) | ✅ (4%) | ✅ (1%) |
| Operator perm = `Revenue_Cloud_Admin` | ✅ | ✅ | ✅ |
| Operator perm = `PCM Administrator` | ❌ | ✅ | ❌ |
| Operator perm = `UnifiedCatalogAdmin` | ❌ | ✅ | ❌ |

**One-line takeaway:** MergeBuild is a clean, minimally-seeded merge target. **UAT** is the only org that holds the 300 `ProductConfigurationRule` rows (the principal payload). fulltemp is missing them entirely.

---

## Size by layer

| Layer | UAT (rows / MB) | fulltemp (rows / MB) | **MergeBuild (rows / MB)** |
| --- | ---: | ---: | ---: |
| Context | 5,533 / 10.81 | 4,978 / 9.72 | **4,282 / 8.36** |
| Pricing Procedure | 66 / 0.13 | 54 / 0.11 | **31 / 0.06** |
| Rule Library | 10 / 0.02 | 7 / 0.01 | **8 / 0.02** |
| Decision Table | 243 / 0.47 | 220 / 0.43 | **248 / 0.48** |
| Product Catalog | 24,527 / 47.90 | 24,527 / 47.90 | **14,104 / 27.55** |
| Pricing Catalog | 183,984 / 359.34 | 69,324 / 135.40 | **16,500 / 32.23** |
| Configuration Rules | 3,627 / 7.08 | 3,327 / 6.50 | **0 / 0.00** |
| **GRAND TOTAL** | **217,990 / 425.76** | **102,437 / 200.07** | **35,173 / 68.70** |

→ MergeBuild's **Product Catalog and Pricing Catalog are roughly half** of UAT/fulltemp size, and Configuration Rules are **completely empty**.

---

## Section 1 — Context Layer

| Object | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: |
| ContextDefinition | 2 | 2 | **2** |
| ContextDefinitionVersion | 2 | 2 | **2** |
| ContextNode | 54 | 53 | **53** |
| ContextAttribute | 918 | 866 | **908** |
| ContextMapping | 17 | 16 | **17** |
| ContextNodeMapping | 142 | 134 | **140** |
| ContextAttributeMapping | 2,229 | 2,118 | **2,043** |
| ContextTag | 915 | **1,781** ⚠️ | **1,034** ⚠️ |
| ContextUseCaseMapping | 6 | 6 | **6** |
| ContextParamMap | **1,248** | 0 | **77** |

### Context-version state — three different version trees

| Definition | UAT | fulltemp | **MergeBuild** |
| --- | --- | --- | --- |
| `ProductDiscoveryContextExt` | **v21 active** | **v1 inactive** ❌ | **v3 active** (2026-05-15) |
| `SalesTransactionContextExt` | **v24 active** | **v2 active** | **v3 active** (2026-05-15) |

→ No two orgs are on the same version. **MergeBuild's v3 active state matches Prod exactly** (this is a deliberate baseline).

⚠️ **Context\* objects are not DML-able** (see Section 8). You cannot directly insert ContextNode/Attribute/Mapping rows. Any context migration must go through metadata (Context Definition deployment). The row-count differences between MergeBuild and UAT/fulltemp here are downstream of CDV-version state — they will not be reconciled by data load.

---

## Section 2 — Pricing Procedure Layer

| Object | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: |
| ExpressionSetDefinition | 5 | 5 | **4** |
| ExpressionSet | 5 | 2 | **4** |
| ExpressionSetVersion | 10 | 2 | **7** |
| ExpressionSetDefinitionContextDefinition | 5 | 4 | **4** |
| ExpressionSetMessageToken | 0 | 0 | **0** |
| PricingActionParameters | 2 | 0 | **0** |
| PricingRecipe | 1 | 1 | **1** |
| PricingRecipeTableMapping | 12 | 14 ⚠️ | **11** |
| PricingProcedureOutputMap | 26 | 26 | **0** |

### ExpressionSets present per org

| ExpressionSet | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: |
| `Product_Discovery_Pricing_Procedure` | ✅ | ❌ | ✅ |
| `Rev_Mgmt_Default_Pricing_Procedure` | ✅ | ❌ | ✅ |
| `Salesforce_Default_Pricing_Discovery_Procedure` | ✅ | ✅ | ✅ |
| `Salesforce_Pricing_Discovery_Procedure` | ✅ | ✅ | ✅ |
| `Test` | ✅ | ❌ | ❌ |

### ExpressionSetVersions — MergeBuild detail

| ExpressionSet | UAT versions | fulltemp versions | **MergeBuild versions** | MergeBuild active |
| --- | --- | --- | --- | --- |
| `Product_Discovery_Pricing_Procedure` | v1 (active) | — | v1 | v1 ✅ |
| `Rev_Mgmt_Default_Pricing_Procedure` | v1–v6 (v6 active) | — | v1, v4, v5, v6 | v6 ✅ |
| `Salesforce_Default_Pricing_Discovery_Procedure` | v1 (active) | v1 (active) | v1 | v1 ✅ |
| `Salesforce_Pricing_Discovery_Procedure` | v1 (active) | v1 (active) | v1 | v1 ✅ |
| `Test` | v1 (active) | — | — | — |

→ MergeBuild's Rev_Mgmt has a v2/v3 **gap** but the active version (v6) matches UAT.

### Junctions (ExpressionSetDefinitionContextDefinition)

| Junction | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: |
| `Product_Discovery_Pricing_Procedure ↔ ProductDiscoveryContextExt` | ✅ | ✅ | ✅ |
| `Rev_Mgmt_Default_Pricing_Procedure ↔ SalesTransactionContextExt` | ✅ | ❌ MISSING | ✅ |
| `Salesforce_Default_Pricing_Discovery_Procedure ↔ SalesTransactionContext__stdctx (exec)` | ✅ | ✅ | ✅ |
| `Salesforce_Pricing_Discovery_Procedure ↔ SalesTransactionContextExt` | ✅ | ✅ | ✅ |
| `Test ↔ ...` | ✅ | ❌ | ❌ |

### PricingActionParameters

| DeveloperName | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: |
| `Order_1773419454521` (Rev_Mgmt / SalesTransactionContextExt / Order) | ✅ | ❌ | ❌ |
| `Quote_1773419454927` (Rev_Mgmt / SalesTransactionContextExt / Quote) | ✅ | ❌ | ❌ |

→ MergeBuild needs both Order/Quote action params. **Not DML-able — metadata deploy only.**

### Stale extras

- fulltemp has **+2 PricingRecipeTableMapping** rows (14 vs UAT 12) — leftover from prior state.

---

## Section 3 — Rule Library Layer

| Object | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: |
| RuleLibrary | 2 | 1 | **2** |
| RuleLibraryDefinition | 2 | 2 | **2** |
| RuleLibraryVersion | 3 | 1 | **2** |
| RuleLibraryDefVersion | 3 | 3 | **2** |

| RuleLibrary DeveloperName | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: |
| `DRORuleLibrary` | ✅ | ✅ | ✅ |
| `ProductRuleLibrary` | ❌ | ❌ | ✅ |
| `Rule_Library` ("Rule Library for Configurator") | ✅ | ❌ | ❌ |

⚠️ **The three orgs have three different "second library" states.** MergeBuild matches Prod (`ProductRuleLibrary`), UAT has `Rule_Library`, fulltemp has neither.

**Load implication:** if you load from UAT, anything that references `Rule_Library` by API name will fail unless you either:
- pre-create `Rule_Library` in MergeBuild (3-row pre-load), OR
- remap the FK at load time to `ProductRuleLibrary`.

---

## Section 4 — Product Catalog Layer

| Object | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: |
| Product2 (total) | 8,846 | 8,846 | **5,214** |
| Product2 (active) | 7,453 | 7,453 | (not measured) |
| ProductCatalog | 2 | 2 | **2** |
| ProductCategory | 187 | 187 | **187** |
| ProductCategoryProduct | 2,200 | 2,200 | **1,639** |
| ProductClassification | 121 | 121 | **121** |
| **ProductClassificationAttr** | 379 | 379 | **0** ⚠️ |
| **ProductRelatedComponent** | 1,417 | 1,417 | **0** ⚠️ |
| **ProductComponentGroup** | 421 | 421 | **2** ⚠️ |
| ProductSellingModel | 9 | 9 | **9** |
| ProductSellingModelOption | 8,794 | 8,794 | **4,779** |
| AttributeDefinition | 17 | 17 | **17** |
| AttributeCategory | 11 | 11 | **11** |
| AttributePicklist | 15 | 15 | **15** |
| AttributePicklistValue | 2,108 | 2,108 | **2,108** |

→ Three glaring holes in MergeBuild: `ProductClassificationAttr`, `ProductRelatedComponent`, `ProductComponentGroup`. These power bundle/configurator behavior — they **must** be loaded before any rule data that references them.

→ Product2 in MergeBuild (5,214) is ~3,600 fewer than UAT/fulltemp (8,846). Decide whether to add the missing products or keep MergeBuild's leaner catalog.

→ ProductSellingModelOption follows the same gap (4,779 vs 8,794).

---

## Section 5 — Pricing Catalog Layer

| Object | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: |
| Pricebook2 | 11 | 2 | **11** |
| **PricebookEntry** | **158,798** | **44,144** | **16,486** ⚠️ |
| PriceAdjustmentSchedule | 1 | 3 | **0** |
| PriceAdjustmentTier | 0 | 0 | **0** |
| **AttributeBasedAdjRule** | 25,171 | 25,171 | **0** |
| AttributeBasedAdj | _not in org_ | _not in org_ | _not in org_ |
| ProrationPolicy | 1 | 1 | **1** |
| ProrationPolicyTier | _not in org_ | _not in org_ | _not in org_ |
| TaxPolicy | 1 | 1 | **1** |
| TaxTreatment | 1 | 2 | **1** |
| TaxRate | 0 | 0 | **0** |

→ MergeBuild **already has 16,486 PricebookEntry rows** — collision risk on insert. Decide before load:
- **Tear down with `PbeTeardownBatch`** then bulk insert from UAT (158K), OR
- **Upsert by external ID** to preserve existing rows.

→ `AttributeBasedAdjRule` (25,171 rows) is the **single largest piece of net-new data** going in. UAT and fulltemp both have it; MergeBuild has none.

→ MergeBuild has **11 Pricebook2 records** (same as UAT). Verify by DeveloperName before linking PBE.

---

## Section 6 — Decision Table Layer

| Object | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: |
| DecisionMatrixDefinition | 0 | 0 | **0** |
| DecisionTable | 22 | 19 | **22** ✅ |
| DecisionTableParameter | 179 | 163 | **182** |
| DecisionTableDatasetLink | 22 | 19 | **22** |
| CalculationMatrix | 20 | 19 | **22** |
| CalculationMatrixVersion/Row/Column | 0 / 0 / 0 | 0 / 0 / 0 | **0 / 0 / 0** |

### DecisionTables — by org membership

| DecisionTable DeveloperName | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: |
| `Asset_Action_Source_Entries_Decision_Table_V2` | ✅ | ✅ | ✅ |
| `Attribute_Based_Adjustment_Decision_Table` | ✅ | ✅ | ✅ |
| `Attribute_Tier_Pricing_Matrix` | ✅ | ✅ | ✅ |
| `Bundle_Based_Adjustment_Decision_Table` | ✅ | ✅ | ✅ |
| `CalculatedVolumeDiscountPriceAdjusmentTier` | ✅ | ✅ | ✅ |
| `Contract_Pricing_Adjustment_Tiers` | ✅ | ✅ | ✅ |
| `Contract_Pricing_Entries_Decision_Table` | ✅ | ✅ | ✅ |
| `Contract_Pricing_Volume_Tiers` | ✅ | ✅ | ✅ |
| `Cyber_Partner_Discount_Matrix` | ✅ | ✅ | ✅ |
| `Derived_Pricing_Entries_Decision_Table` | ✅ | ✅ | ✅ |
| `Fortra_Regional_Pricing` | ✅ | ✅ | ✅ |
| `Fulfillment_Step_Jeopardy_Rule_Decision_Table` | ✅ | ❌ | ✅ |
| `FulfillmentFalloutRules` | ✅ | ❌ | ✅ |
| `Index_Rate_Decision_Table` | ✅ | ✅ | ✅ |
| `MaintenanceType` | ✅ | ❌ | ✅ |
| `Price_Adjustment_Tier_Decision_Table` | ✅ | ✅ | ✅ |
| `Price_Book_Entry_Decision_Table_v2` | ✅ | ✅ | ✅ |
| `PriceModeVolumeDiscountPriceAdjusmentTier` | ✅ | ✅ | ✅ |
| `Regional_Pricing` | ✅ | ✅ | ✅ |
| `StandardTax` | ✅ | ✅ | ✅ |
| `Tech_Partner_Discount_Matrix` | ✅ | ✅ | ✅ |
| `Tiered_Adjustment_Tier_Decision_Table` | ✅ | ✅ | ✅ |
| **Total** | **22** | **19** | **22** |

→ **MergeBuild already has all 22 UAT-built tables.** No DT names are missing. fulltemp is missing 3 (Fulfillment / Maintenance set).

→ MergeBuild has **+3 DecisionTableParameter** vs UAT (182 vs 179) and **+2 CalculationMatrix** (22 vs 20). May or may not be intentional — worth a one-pass diff.

---

## Section 7 — Configuration Rules + Fulfillment

| Object | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: |
| ProductConfigurationFlow | 1 | 1 | **0** |
| **ProductConfigurationRule** | **300** | **0** ⚠️ | **0** ⚠️ |
| ProductFulfillmentDecompRule | 3,326 | 3,326 | **0** (object exists) |

→ This is the **payload row**. **300 ConfigurationRules live only in UAT.** fulltemp is empty here — sourcing from fulltemp would reproduce the gap.

→ ProductFulfillmentDecompRule object **exists** in MergeBuild (unlike Prod). The 3,326 rows from either UAT or fulltemp are loadable.

---

## Section 8 — DML Restrictions (identical across all three orgs)

No `GearsetExternalId__c` field on any of these objects in any org:

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

→ Same restriction in all three orgs. Context\*, ExpressionSetDefinition, and PricingActionParameters must travel via **metadata** (Context Definition deployment), not Bulk API.

---

## Section 9 — Permset Audit (operator user)

| Permset | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: |
| `ProductCatalogManagementAdministrator` | ❌ MISSING | ✅ ASSIGNED | ❌ MISSING |
| `UnifiedCatalogAdmin` | ❌ MISSING | ✅ ASSIGNED | ❌ MISSING |
| `Revenue_Cloud_Admin` | ✅ ASSIGNED | ✅ ASSIGNED | ✅ ASSIGNED |

→ **Assign PCM Admin + UnifiedCatalogAdmin to the MergeBuild operator user before loading.** Direct DML on PCM / UnifiedCatalog objects will otherwise be blocked.

---

## Source decision matrix — UAT vs fulltemp → MergeBuild

| Dimension | Load from UAT | Load from fulltemp | Verdict |
| --- | --- | --- | :--- |
| `ProductConfigurationRule` (the payload) | 300 | 0 | **UAT only** |
| `ProductFulfillmentDecompRule` | 3,326 | 3,326 | tie |
| `AttributeBasedAdjRule` | 25,171 | 25,171 | tie |
| Full ExpressionSet set | ✅ (5/5) | ❌ (2/5) | **UAT** |
| `Rev_Mgmt ↔ SalesTransactionContextExt` junction | ✅ | ❌ MISSING | **UAT** |
| `PricingActionParameters` (Order/Quote) | 2 (metadata deploy) | 0 | **UAT** |
| `PricingProcedureOutputMap` | 26 | 26 | tie |
| RuleLibrary alignment with MergeBuild | partial (`Rule_Library` mismatch with `ProductRuleLibrary`) | worse (no second library at all) | UAT |
| PBE row count (size) | 158,798 (16× over 10K cap) | 44,144 (4× over) | fulltemp lighter |
| ContextDefinitionVersion compatibility | UAT v21/v24 — incompatible with MergeBuild v3 | fulltemp v1/v2 — also incompatible | tie (skip Context\* either way) |
| ContextTag stale-row baseline | clean (915) | bloated (1,781) | UAT cleaner |
| Total size | 425.8 MB | 200.1 MB | fulltemp lighter |
| Data freshness | latest | snapshot, drifted | **UAT** |

→ **UAT wins on every functional dimension.** fulltemp's only advantages are lighter PBE volume and lighter total size — neither is a blocker, since MergeBuild has 5 GB of headroom and direct data load bypasses the 10K cap.

---

## Migration risk register (UAT → MergeBuild)

| # | Risk | Impact | Mitigation |
| --- | --- | --- | --- |
| 1 | **PBE collision** — MergeBuild has 16,486 rows; UAT has 158,798 | Duplicate-key failures on `(Pricebook2, Product2, CurrencyIsoCode)` | Either tear down with `PbeTeardownBatch` first, OR upsert by external ID |
| 2 | **RuleLibrary naming mismatch** — UAT `Rule_Library` vs MergeBuild `ProductRuleLibrary` | FK references to `Rule_Library` will fail | Pre-create `Rule_Library` in MergeBuild, OR remap at load time |
| 3 | **Context-version drift** — UAT v21/v24 vs MergeBuild v3 | Loading UAT Context\* would break Prod-alignment | **Skip Context\* in data load** (also not DML-able) |
| 4 | **Operator permset gaps** — missing PCM Admin + UC Admin in MergeBuild | DML on PCM/UC objects blocked | Assign both permsets before kickoff |
| 5 | **Product-graph holes** — MergeBuild has 0 ProductClassificationAttr/RelatedComponent and 2 ComponentGroup | Bundle/configurator rules will fail FK validation | Load in order: ProductClassificationAttr (379) → ProductComponentGroup (421) → ProductRelatedComponent (1,417) BEFORE rule data |
| 6 | **Pricebook2 alignment** — both orgs have 11, but verify DeveloperName match | PBE inserts could land in wrong Pricebook | Diff Pricebook2 DeveloperNames first |
| 7 | **Product2 catalog delta** — MergeBuild 5,214 vs UAT 8,846 | Rules referencing missing Product2 records will fail | Decide: load delta products from UAT, OR scope rule load to MergeBuild's existing 5,214 |
| 8 | **AttributeBasedAdjRule volume** — 25,171 rows | Long-running bulk load | Use Bulk API v2, monitor jobs |
| 9 | **PricingActionParameters not DML-able** | Order/Quote bindings cannot be inserted | Metadata deploy (Context Definition / Pricing Procedure metadata path) |
| 10 | **ContextTag drift** — MergeBuild already at 1,034 vs UAT 915 | Possible orphan tags | Optional post-load cleanup pass |

---

## Recommended load order (UAT → MergeBuild)

1. **Pre-flight**
   1. Assign `ProductCatalogManagementAdministrator` + `UnifiedCatalogAdmin` to MergeBuild operator
   2. Pre-create `Rule_Library` in MergeBuild OR confirm remap strategy
   3. Verify Pricebook2 DeveloperName parity between UAT and MergeBuild
   4. Run `PbeTeardownBatch` in MergeBuild (16,486 → 0) if doing a clean PBE reload
   5. (Optional) Diff DecisionTableParameter + CalculationMatrix deltas (MergeBuild has +3/+2 vs UAT)

2. **Product-graph backfill** (FK prerequisites)
   1. Product2 deltas if loading the missing 3,632 (optional)
   2. ProductSellingModelOption deltas
   3. `ProductClassificationAttr` (379)
   4. `ProductComponentGroup` (421)
   5. `ProductRelatedComponent` (1,417)
   6. ProductCategoryProduct deltas (UAT 2,200 vs MergeBuild 1,639)

3. **Pricing data**
   1. `PricebookEntry` (158,798 — bulk insert or upsert)
   2. `PriceAdjustmentSchedule` / `PriceAdjustmentTier`
   3. `AttributeBasedAdjRule` (25,171)

4. **Rule library payload**
   1. RuleLibrary `Rule_Library` (or skip if remapping to `ProductRuleLibrary`)
   2. RuleLibraryVersion + RuleLibraryDefVersion deltas
   3. `ProductConfigurationFlow` (1)
   4. **`ProductConfigurationRule` (300)** — primary deliverable
   5. `ProductFulfillmentDecompRule` (3,326)

5. **Metadata-only** (Context Definition deployment, not data load)
   - `ExpressionSetDefinition` deltas if needed (UAT 5 vs MergeBuild 4 — missing `Test`)
   - `PricingActionParameters` Order/Quote bindings
   - Skip `ContextDefinition` / `ContextDefinitionVersion` / `ContextNode` / `ContextAttribute` — MergeBuild's v3 baseline is intentional

6. **Post-load verification**
   - Re-run `SC-3137_RCA_Setup_Verification.apex` against MergeBuild
   - Compare row counts to UAT layer-by-layer
   - Sweep stale ContextTag delta if it widens

---

## Net observation

UAT and fulltemp differ from MergeBuild in **size and shape**, but only **UAT has the data** that MergeBuild needs. fulltemp is a stale partial copy that lost the 300 ConfigurationRules, 3 ExpressionSets, the Rev_Mgmt junction, and an active ProductDiscoveryContextExt — sourcing from it would reproduce those gaps.

MergeBuild itself is in a deliberate **Prod-baseline + UAT-overlay** state: Prod-style Context/RuleLibrary/Product2/PricingRecipe, UAT-style DecisionTables/Tax/ProductFulfillmentDecompRule object. The job of this migration is to fill the **empty runtime tables** (ConfigurationRule, AttrBasedAdjRule, FulfillmentDecompRule) and the **product-graph holes** (ClassificationAttr, RelatedComponent, ComponentGroup) — all of which UAT has and fulltemp may or may not.

Pick UAT. Address the three pre-load decisions (PBE strategy, RuleLibrary remap, skip Context\*). Then execute the load order above.
