# SC-3137 — Pre-Migration Diagnosis: RCA Config → MergeBuild (4-Way)

**Date run:** 2026-05-21
**Operator:** liam.jeong.c@fortra.com (all four orgs)
**Question:** load RCA configuration data into MergeBuild — choose source between **FortraUAT** and **fulltemp**, identify risks before execution.
**Scripts:**
- [`scripts/apex/SC-3137_RCA_Setup_Verification.apex`](../scripts/apex/SC-3137_RCA_Setup_Verification.apex)
- [`scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex`](../scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex)
**New MergeBuild logs:**
- [`scripts/apex/output/rca_diag_MergeBuild.log`](../scripts/apex/output/rca_diag_MergeBuild.log)
- [`scripts/apex/output/rca_size_MergeBuild.log`](../scripts/apex/output/rca_size_MergeBuild.log)

---

## TL;DR — MergeBuild looks like a half-seeded merge target

| Org | Rows | Size | Vs MergeBuild |
| --- | ---: | ---: | --- |
| **MergeBuild** | **35,173** | **~68.7 MB** | (target) |
| FortraProduction | 52,553 | ~102.6 MB | +49% rows |
| fulltemp | 102,437 | ~200.1 MB | +191% rows |
| FortraUAT | 217,990 | ~425.8 MB | +519% rows |

MergeBuild is the **smallest of the four** and is in a peculiar **prod-baseline + UAT-overlay hybrid**:

- ✅ **Context** — v3 active=true on both definitions (matches Prod, dated 2026-05-15)
- ✅ **RuleLibrary** — `DRORuleLibrary` + `ProductRuleLibrary` (matches **Prod**, not UAT's `Rule_Library`)
- ✅ **DecisionTable** — has **all 22** UAT-built tables (richer than Prod which has 12)
- ✅ **ExpressionSets** — has **4 of UAT's 5** (missing only `Test`). Includes both Rev_Mgmt + Product_Discovery
- ✅ **Tax objects + ProductFulfillmentDecompRule object** present (UAT-style, not Prod)
- ❌ **Empty runtime tables**: `ProductConfigurationRule=0`, `ProductFulfillmentDecompRule=0`, `AttributeBasedAdjRule=0`, `PricingProcedureOutputMap=0`, `PricingActionParameters=0`
- ❌ **Product-graph holes**: `ProductClassificationAttr=0` (others 372–379), `ProductRelatedComponent=0` (others 1,401–1,417), `ProductComponentGroup=2` (others 416–421)
- ⚠️ **PricebookEntry already has 16,486 rows** — collision risk on insert
- ⚠️ **ContextTag = 1,034** — higher than Prod (775), lower than fulltemp (1,781) — possible stale rows

---

## 4-way snapshot — Context Layer

| Object | Prod | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: | ---: |
| ContextDefinition | 2 | 2 | 2 | **2** |
| ContextDefinitionVersion | 2 | 2 | 2 | **2** |
| ContextNode | 52 | 54 | 53 | **53** |
| ContextAttribute | 771 | 918 | 866 | **908** |
| ContextMapping | 17 | 17 | 16 | **17** |
| ContextNodeMapping | 139 | 142 | 134 | **140** |
| ContextAttributeMapping | 2,031 | 2,229 | 2,118 | **2,043** |
| ContextTag | 775 | 915 | 1,781 | **1,034** ⚠️ |
| ContextUseCaseMapping | 0 | 6 | 6 | **6** |
| ContextParamMap | 0 | 1,248 | 0 | **77** |

### Context-version state

| Definition | Prod | UAT | fulltemp | **MergeBuild** |
| --- | --- | --- | --- | --- |
| `ProductDiscoveryContextExt` | **v3 active** (2026-05-15) | v21 active | v1 **inactive** ❌ | **v3 active** (2026-05-15) ✅ |
| `SalesTransactionContextExt` | **v3 active** (2026-05-15) | v24 active | v2 active | **v3 active** (2026-05-15) ✅ |

→ MergeBuild's CDV state **exactly matches Prod** — both versions are v3, active, dated 2026-05-15. This is the cleanest CDV state of any sandbox. **Do not deploy UAT's v21/v24** unless you intend to bump MergeBuild's CDV away from the Prod baseline.

---

## Pricing Procedure Layer

| Object | Prod | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: | ---: |
| ExpressionSetDefinition | 2 | 5 | 5 | **4** |
| ExpressionSet | 2 | 5 | 2 | **4** |
| ExpressionSetVersion | 2 | 10 | 2 | **7** |
| ExpressionSetDefinitionContextDefinition | 2 | 5 | 4 | **4** |
| PricingActionParameters | 0 | 2 | 0 | **0** |
| PricingRecipe | 1 | 1 | 1 | **1** (`NGPDefaultRecipe`) |
| PricingRecipeTableMapping | 11 | 12 | 14 | **11** (matches Prod) |
| PricingProcedureOutputMap | 0 | 26 | 26 | **0** |

### ExpressionSets present per org

| ExpressionSet | Prod | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: | :---: |
| `Product_Discovery_Pricing_Procedure` | ❌ | ✅ | ❌ | ✅ |
| `Rev_Mgmt_Default_Pricing_Procedure` | ✅ | ✅ | ❌ | ✅ |
| `Salesforce_Default_Pricing_Discovery_Procedure` | ✅ | ✅ | ✅ | ✅ |
| `Salesforce_Pricing_Discovery_Procedure` | ❌ | ✅ | ✅ | ✅ |
| `Test` | ❌ | ✅ | ❌ | ❌ |

### ExpressionSetVersion detail (MergeBuild)

| Set | Versions in MergeBuild | Active version |
| --- | --- | --- |
| `Product_Discovery_Pricing_Procedure` | v1 | v1 ✅ |
| `Rev_Mgmt_Default_Pricing_Procedure` | v1, v4, v5, v6 | **v6** ✅ (v1/v4/v5 inactive) |
| `Salesforce_Default_Pricing_Discovery_Procedure` | v1 | v1 ✅ |
| `Salesforce_Pricing_Discovery_Procedure` | v1 | v1 ✅ |

→ MergeBuild's Rev_Mgmt has the **UAT-style v6 active** path with v1/v4/v5 history retained. Missing v2/v3 (gap).

### Junctions (MergeBuild)

```
Product_Discovery_Pricing_Procedure        <-> ProductDiscoveryContextExt
Rev_Mgmt_Default_Pricing_Procedure         <-> SalesTransactionContextExt   ← present!
Salesforce_Default_Pricing_Discovery_Proc. <-> SalesTransactionContext__stdctx (executable)
Salesforce_Pricing_Discovery_Procedure     <-> SalesTransactionContextExt
```

→ Critically, the `Rev_Mgmt_Default ↔ SalesTransactionContextExt` junction is **present** (fulltemp was missing this).

**Gap vs UAT:** `Test` ExpressionSet, all Rev_Mgmt v2/v3, all `PricingActionParameters` (Order/Quote bindings), all 26 `PricingProcedureOutputMap` rows.

---

## Rule Library Layer

| Object | Prod | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: | ---: |
| RuleLibrary | 2 | 2 | 1 | **2** |
| RuleLibraryDefinition | 2 | 2 | 2 | **2** |
| RuleLibraryVersion | 2 | 3 | 1 | **2** |
| RuleLibraryDefVersion | 2 | 3 | 3 | **2** |

| RuleLibrary DeveloperName | Prod | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: | :---: |
| `DRORuleLibrary` | ✅ | ✅ | ✅ | ✅ |
| `ProductRuleLibrary` | ✅ | ❌ | ❌ | ✅ (matches **Prod**) |
| `Rule_Library` | ❌ | ✅ | ❌ | ❌ |

→ ⚠️ **MergeBuild matches Prod's naming**, not UAT's. If you load from UAT, anything referencing `Rule_Library` by external ID/name will need either (a) remapping to `ProductRuleLibrary`, or (b) creating `Rule_Library` first to preserve the FK.

---

## Product Catalog Layer

| Object | Prod | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: | ---: |
| Product2 | 5,421 | 8,846 | 8,846 | **5,214** |
| Product2 (active) | 5,421 | 7,453 | 7,453 | (not measured) |
| ProductCatalog | 2 | 2 | 2 | **2** |
| ProductCategory | 187 | 187 | 187 | **187** |
| ProductCategoryProduct | 4,047 | 2,200 | 2,200 | **1,639** |
| ProductClassification | 110 | 121 | 121 | **121** |
| **ProductClassificationAttr** | 372 | 379 | 379 | **0** ⚠️ |
| **ProductRelatedComponent** | 1,401 | 1,417 | 1,417 | **0** ⚠️ |
| **ProductComponentGroup** | 416 | 421 | 421 | **2** ⚠️ |
| ProductSellingModel | 9 | 9 | 9 | **9** |
| ProductSellingModelOption | 5,421 | 8,794 | 8,794 | **4,779** |
| AttributeDefinition | 16 | 17 | 17 | **17** |
| AttributeCategory | 11 | 11 | 11 | **11** |
| AttributePicklist | 15 | 15 | 15 | **15** |
| AttributePicklistValue | 2,108 | 2,108 | 2,108 | **2,108** |

→ **Three giant holes** in MergeBuild's product graph: `ProductClassificationAttr`, `ProductRelatedComponent`, `ProductComponentGroup`. These are required for bundle/configurator behavior and **must** be loaded.

→ Product2 in MergeBuild (5,214) is closer to Prod (5,421) than to UAT/fulltemp (8,846). Loading 8,846 from UAT would add ~3.6K extra rows on top of a Prod-like baseline.

---

## Pricing Catalog Layer

| Object | Prod | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: | ---: |
| Pricebook2 | 1 | 11 | 2 | **11** |
| **PricebookEntry** | 27,093 | 158,798 | 44,144 | **16,486** ⚠️ |
| PriceAdjustmentSchedule | 3 | 1 | 3 | **0** |
| PriceAdjustmentTier | 1,953 | 0 | 0 | **0** |
| **AttributeBasedAdjRule** | 0 | 25,171 | 25,171 | **0** |
| ProrationPolicy | 1 | 1 | 1 | **1** |
| TaxPolicy | _n/a_ | 1 | 1 | **1** |
| TaxTreatment | _n/a_ | 1 | 2 | **1** |
| TaxRate | 0 | 0 | 0 | **0** |

→ MergeBuild **already has 16,486 PricebookEntries** — pre-existing data. Choose between:
- (a) load PBE into the existing 16,486 (merge mode, requires upsert key like external ID, otherwise duplicate-row collisions on the natural key `Pricebook2Id + Product2Id + CurrencyIsoCode`),
- (b) tear down PBE first with `PbeTeardownBatch`, then load fresh.

→ `AttributeBasedAdjRule` and the runtime rule tables are **empty** in MergeBuild — this is the data the user is principally trying to load.

---

## Configuration Rules + Decision Tables

| Object | Prod | UAT | fulltemp | **MergeBuild** |
| --- | ---: | ---: | ---: | ---: |
| ProductConfigurationFlow | 0 | 1 | 1 | **0** |
| **ProductConfigurationRule** | 0 | 300 | 0 | **0** |
| ProductFulfillmentDecompRule | _n/a_ | 3,326 | 3,326 | **0** (object exists) |
| DecisionTable | 12 | 22 | 19 | **22** ✅ |
| DecisionTableParameter | 113 | 179 | 163 | **182** |
| CalculationMatrix | 12 | 20 | 19 | **22** |

→ MergeBuild has **all 22 UAT-built DecisionTables** plus a few more parameters (182 vs UAT 179). DT schema is the most complete of any sandbox.

→ `ProductConfigurationFlow` and the 300 `ProductConfigurationRule` rows from UAT are the **main payload** — only UAT has them.

---

## Permset audit (operator)

| Permset | Prod | UAT | fulltemp | **MergeBuild** |
| --- | :---: | :---: | :---: | :---: |
| `ProductCatalogManagementAdministrator` | ❌ | ❌ | ✅ | ❌ MISSING |
| `UnifiedCatalogAdmin` | ❌ | ❌ | ✅ | ❌ MISSING |
| `Revenue_Cloud_Admin` | ❌ | ✅ | ✅ | ✅ ASSIGNED |

→ **Assign the two missing permsets to your MergeBuild user before loading**, otherwise direct DML/admin operations on PCM / UnifiedCatalog objects will fail.

---

## DML restrictions (identical in all four orgs)

Same non-DML-able list as before — these objects cannot be loaded via Data Loader / Bulk API:

```
ContextDefinition, ContextDefinitionVersion, ContextNode, ContextAttribute,
ExpressionSetDefinition, PricingActionParameters
```

→ Must move via **metadata deployment** (Context Definition deployment path), not data load. Same applies to any UAT → MergeBuild migration.

---

## Source choice — UAT vs fulltemp

| Dimension | Load from UAT | Load from fulltemp |
| --- | --- | --- |
| Total size | 425.8 MB (well under 5 GB) | 200.1 MB |
| `ProductConfigurationRule` count | **300** ✅ | 0 ❌ |
| `ProductFulfillmentDecompRule` | 3,326 | 3,326 (same) |
| `AttributeBasedAdjRule` | 25,171 | 25,171 (same) |
| `PricebookEntry` | 158,798 (16× over 10K cap) | 44,144 (4× over) |
| ExpressionSet completeness | Full set incl. `Test` | Missing 3 of UAT's 5 |
| Junction `Rev_Mgmt ↔ SalesTransactionContextExt` | Present | **Missing** |
| RuleLibrary naming | `Rule_Library` (mismatched vs MergeBuild's `ProductRuleLibrary`) | Only `DRORuleLibrary` (also mismatched) |
| `PricingActionParameters` | 2 (Order/Quote bindings, references Rev_Mgmt) | 0 |
| `PricingProcedureOutputMap` | 26 | 26 |
| ContextDefinitionVersion compatibility | UAT is v21/v24 — **incompatible with MergeBuild's v3** | fulltemp v1 inactive — **also incompatible** |
| Data freshness | latest | snapshot, may be stale |
| Has CDV-version drift baked in? | Yes (high CDV) | Yes (inactive v1) |

**Recommendation: load from UAT.**

The 300 `ProductConfigurationRule` rows are **only in UAT** and are the principal piece of data MergeBuild lacks. fulltemp is missing those entirely — loading from fulltemp would reproduce the gap that the SC-3137 diagnostic already flagged.

Caveats when loading from UAT:
1. **Skip Context\*** — MergeBuild's v3 baseline is intentional. Loading UAT's v21/v24 Context tables would break alignment with Prod.
2. **Skip PricingActionParameters / ExpressionSetDefinition** — not DML-able. Use metadata if needed.
3. **Remap RuleLibrary references** — UAT's `Rule_Library` → MergeBuild's `ProductRuleLibrary`. Anything referencing a RuleLibrary by name needs translation. (Or pre-create `Rule_Library` in MergeBuild before load to preserve FKs.)
4. **Decide PBE strategy first** — tear down MergeBuild's existing 16,486 with `PbeTeardownBatch` if you want a clean reload from UAT's 158,798, OR upsert by external ID if available.
5. **Three product-graph holes must be filled**: `ProductClassificationAttr` (379), `ProductRelatedComponent` (1,417), `ProductComponentGroup` (421) — these need to load before any rules that reference them.

---

## Recommended load order (UAT → MergeBuild)

The dependency chain:

1. **Pre-flight**
   - Assign `ProductCatalogManagementAdministrator` + `UnifiedCatalogAdmin` permsets in MergeBuild.
   - Decide PBE strategy. If tearing down: run `PbeTeardownBatch` first.
   - Tear down any other pre-existing rows you don't want kept (`RcaTeardownBatch` for AttrBasedAdjRule, ProductConfigurationRule, etc. — currently all 0 in MergeBuild, so likely no-op).
   - Verify `Rule_Library` will be created or remapped.

2. **Product-graph backfill** (load order matters)
   1. `ProductClassificationAttr` (379)
   2. `ProductComponentGroup` (421)
   3. `ProductRelatedComponent` (1,417)
   4. Net-new Product2 deltas if catalog parity is desired (or skip and keep MergeBuild's 5,214 baseline)

3. **Pricing data**
   1. Missing Pricebook2 records (UAT has 11 vs MergeBuild 11 — verify match by DeveloperName)
   2. `PricebookEntry` (158,798 if PBE was torn down; otherwise upsert)
   3. `AttributeBasedAdjRule` (25,171) — empty in MergeBuild
   4. `PriceAdjustmentSchedule` / `PriceAdjustmentTier` if needed

4. **Rule-library payload**
   1. Create `Rule_Library` (or remap to `ProductRuleLibrary`) + version + def-version
   2. `ProductConfigurationFlow` (1)
   3. `ProductConfigurationRule` (300) — **the primary deliverable**
   4. `ProductFulfillmentDecompRule` (3,326)

5. **Context/PP layer — metadata only**
   - Skip Context* data load; deploy via metadata if changes needed (currently MergeBuild's v3 matches Prod and probably should stay).
   - `ExpressionSetDefinition` / `PricingActionParameters` — metadata-only.

6. **Stale row cleanup (post-load)**
   - Re-run diag script and compare to UAT — sweep any orphan ContextTag rows if delta widens.

---

## Net observation

MergeBuild is in a **deliberately mixed state**: Prod-baseline for Context + RuleLibrary names + Product2 count, UAT-baseline for DecisionTables + Tax + ProductFulfillmentDecompRule object. It looks engineered to be the merge target where Prod-shape meets UAT-runtime — exactly what you need to ship UAT's runtime config into a Prod-like skeleton.

**Highest-leverage source is UAT**, but the migration is **not a flat data-copy** — three risks demand pre-load decisions:

1. **PricebookEntry collision** (16,486 already there)
2. **RuleLibrary naming divergence** (`Rule_Library` vs `ProductRuleLibrary`)
3. **Context drift** (UAT v21/v24 vs MergeBuild v3 — must skip Context\* in the data load)

Address those three before kicking off the load and the runtime payload (`ProductConfigurationRule`, `AttributeBasedAdjRule`, `ProductFulfillmentDecompRule`) will land cleanly.
