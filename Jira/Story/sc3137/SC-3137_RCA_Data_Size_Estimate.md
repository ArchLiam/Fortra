# SC-3137 — RCA Data Size Estimate for MergeBuild (Partial Copy) Sizing

**Purpose:** size the RCA dataset in FortraUAT before migrating to **MergeBuild** (Partial Copy sandbox).
**Date run:** 2026-05-20
**Source org:** FortraUAT (`00DWC000006eUFF2A2`)
**Script:** [`scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex`](../scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex)
**Raw log:** [`scripts/apex/output/rca_size_FortraUAT.clean.txt`](../scripts/apex/output/rca_size_FortraUAT.clean.txt)
**Sizing rule:** Salesforce standard ~**2 KB / record**.

---

## TL;DR

| Metric | Value |
| --- | ---: |
| **Total RCA rows** | **217,990** |
| **Estimated total size** | **~425.76 MB (~0.42 GB)** |
| Partial Copy limit | 5 GB data |
| **Headroom in MergeBuild** | **~92 %** ✅ Plenty of room |

⚠️ Two objects exceed the **10,000-rows-per-object** cap that applies *only if* refreshing from prod with a Partial Copy sandbox template:
- `PricebookEntry` — 158,798 rows (≈16× over)
- `AttributeBasedAdjRule` — 25,171 rows (≈2.5× over)

If migration is done via **direct data load** (Bulk API / Data Loader / Gearset / Salto) the only limit that matters is the 5 GB total — you are well under it.

---

## Totals by layer

| Layer | Rows | ~Size (KB) | ~Size (MB) |
| --- | ---: | ---: | ---: |
| Context | 5,533 | 11,066 | 10.81 |
| Pricing Procedure | 66 | 132 | 0.13 |
| Rule Library | 10 | 20 | 0.02 |
| Decision Table | 243 | 486 | 0.47 |
| Product Catalog | 24,527 | 49,054 | 47.90 |
| **Pricing Catalog** | **183,984** | **367,968** | **359.34** |
| Configuration Rules | 3,627 | 7,254 | 7.08 |
| **GRAND TOTAL** | **217,990** | **435,980** | **425.76** |

Pricing Catalog dominates (~84 % of total) — driven almost entirely by `PricebookEntry` and `AttributeBasedAdjRule`.

---

## Per-object detail (FortraUAT)

### Context Layer — ~10.81 MB
| Object | Rows | ~Size (KB) |
| --- | ---: | ---: |
| ContextDefinition | 2 | 4.0 |
| ContextDefinitionVersion | 2 | 4.0 |
| ContextNode | 54 | 108.0 |
| ContextAttribute | 918 | 1,836.0 |
| ContextMapping | 17 | 34.0 |
| ContextNodeMapping | 142 | 284.0 |
| ContextAttributeMapping | 2,229 | 4,458.0 |
| ContextTag | 915 | 1,830.0 |
| ContextUseCaseMapping | 6 | 12.0 |
| ContextParamMap | 1,248 | 2,496.0 |

### Pricing Procedure Layer — ~0.13 MB
| Object | Rows | ~Size (KB) |
| --- | ---: | ---: |
| ExpressionSetDefinition | 5 | 10.0 |
| ExpressionSet | 5 | 10.0 |
| ExpressionSetVersion | 10 | 20.0 |
| ExpressionSetDefinitionContextDefinition | 5 | 10.0 |
| ExpressionSetMessageToken | 0 | 0.0 |
| ExpressionSetVariable | _not in org_ | — |
| PricingActionParameters | 2 | 4.0 |
| PricingRecipe | 1 | 2.0 |
| PricingRecipeTableMapping | 12 | 24.0 |
| PricingProcedureOutputMap | 26 | 52.0 |

### Rule Library Layer — ~0.02 MB
| Object | Rows | ~Size (KB) |
| --- | ---: | ---: |
| RuleLibrary | 2 | 4.0 |
| RuleLibraryDefinition | 2 | 4.0 |
| RuleLibraryVersion | 3 | 6.0 |
| RuleLibraryDefVersion | 3 | 6.0 |

### Decision Table Layer — ~0.47 MB
| Object | Rows | ~Size (KB) |
| --- | ---: | ---: |
| DecisionMatrixDefinition | 0 | 0.0 |
| DecisionTable | 22 | 44.0 |
| DecisionTableParameter | 179 | 358.0 |
| DecisionTableDatasetLink | 22 | 44.0 |
| CalculationMatrix | 20 | 40.0 |
| CalculationMatrixVersion | 0 | 0.0 |
| CalculationMatrixRow | 0 | 0.0 |
| CalculationMatrixColumn | 0 | 0.0 |

### Product Catalog — ~47.90 MB
| Object | Rows | ~Size (KB) |
| --- | ---: | ---: |
| Product2 | 8,846 | 17,692.0 |
| ProductCatalog | 2 | 4.0 |
| ProductCategory | 187 | 374.0 |
| ProductCategoryProduct | 2,200 | 4,400.0 |
| ProductClassification | 121 | 242.0 |
| ProductClassificationAttr | 379 | 758.0 |
| ProductAttributeSet | _not in org_ | — |
| ProductAttributeSetItem | _not in org_ | — |
| ProductRelatedComponent | 1,417 | 2,834.0 |
| ProductComponentGroup | 421 | 842.0 |
| ProductSellingModel | 9 | 18.0 |
| ProductSellingModelOption | 8,794 | 17,588.0 |
| AttributeDefinition | 17 | 34.0 |
| AttributeCategory | 11 | 22.0 |
| AttributePicklist | 15 | 30.0 |
| AttributePicklistValue | 2,108 | 4,216.0 |

### Pricing Catalog — ~359.34 MB
| Object | Rows | ~Size (KB) |
| --- | ---: | ---: |
| Pricebook2 | 11 | 22.0 |
| **PricebookEntry** | **158,798** | **317,596.0** |
| PriceAdjustmentSchedule | 1 | 2.0 |
| PriceAdjustmentTier | 0 | 0.0 |
| **AttributeBasedAdjRule** | **25,171** | **50,342.0** |
| AttributeBasedAdj | _not in org_ | — |
| ProrationPolicy | 1 | 2.0 |
| ProrationPolicyTier | _not in org_ | — |
| TaxPolicy | 1 | 2.0 |
| TaxTreatment | 1 | 2.0 |
| TaxRate | 0 | 0.0 |

### Configuration Rules — ~7.08 MB
| Object | Rows | ~Size (KB) |
| --- | ---: | ---: |
| ProductConfigurationFlow | 1 | 2.0 |
| ProductConfigurationRule | 300 | 600.0 |
| ProductRule | _not in org_ | — |
| ProductFulfillmentDecompRule | 3,326 | 6,652.0 |
| ProductFulfillmentStep | _not in org_ | — |

---

## Migration path options

| Path | Pros | Cons |
| --- | --- | --- |
| **Sandbox refresh template (Partial Copy)** | One-shot, official, copies metadata too | **Hard cap of 10,000 rows/object** — `PricebookEntry` and `AttributeBasedAdjRule` will be truncated |
| **Direct data load** (Bulk API / Data Loader / Gearset / Salto) | No per-object cap; only the 5 GB total matters | More setup; need to manage Context* (non-DML-able — see SC-3137 diff report); load order matters |

For RCA setup data specifically, the **direct-data-load** path is the only one that preserves PricebookEntry and AttributeBasedAdjRule completely. Note that `ContextDefinition`, `ContextDefinitionVersion`, `ContextNode`, `ContextAttribute`, `ExpressionSetDefinition`, `PricingActionParameters` are **not directly DML-able** (per Section 8 of the SC-3137 diff report) — they must be deployed via metadata / Context Definition deployment, not data load.

---

## Caveats on the estimate

- 2 KB / record is the documented Salesforce average. Real per-record size varies — long text fields and rich text inflate it; minimal records can be smaller. Treat as ±20 %.
- Even at 2× the estimate (~0.85 GB), MergeBuild still has > 4 GB headroom.
- File storage (ContentVersion / Attachments / etc.) is **not included** — Partial Copy has a separate 5 GB file-storage limit. If RCA depends on attached files (e.g., DocGen templates), size those separately.
