# RCA Setup Diff — fulltemp vs. MergeBuild

**Date:** 2026-05-21
**Source raw logs:**
- [fulltemp_rca_2026-05-21.txt](fulltemp_rca_2026-05-21.txt)
- [mergebuild_rca_2026-05-21.txt](mergebuild_rca_2026-05-21.txt)

**Orgs**
| Alias | Org ID | User who ran the script |
| --- | --- | --- |
| `fulltemp` | `00DWJ000008WCcX2AW` | liam.jeong.c@fortra.com.fulltemp |
| `MergeBuild` | `00Dct000004lXJBEA2` | liam.jeong.c@fortra.com.mergebuild |

**Methodology notes**
- Script (`scripts/apex/rca_diagnostic.apex`) had to be patched before it would compile in either org: removed `ContextDefinition.IsCustom` (does not exist), `ContextDefinitionVersion.InheritedFromVersion` (correct field is `InheritedApexVersion`), and `PricingRecipe.Name` / `PricingRecipe.DefaultPricingProcedure.DeveloperName` relationship (PricingRecipe uses `DeveloperName`/`MasterLabel` and `DefaultPricingProcedureId` only). All detail queries were also wrapped in try/catch defensively.
- Identical script was run against both orgs after the patch — diff is apples-to-apples.

---

## 1. Section 0 — Object counts

| Object | fulltemp | MergeBuild | Δ | Δ% | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| ContextDefinition | 2 | 2 | 0 | 0% | |
| ContextDefinitionVersion | 2 | 2 | 0 | 0% | See structural note below |
| ContextNode | 53 | 53 | 0 | 0% | Per-parent counts differ slightly |
| ContextAttribute | 866 | 908 | +42 | +4.85% | |
| ContextMapping | 16 | 17 | +1 | +6.25% | |
| ContextNodeMapping | 134 | 140 | +6 | +4.48% | |
| ContextAttributeMapping | 2118 | 2043 | -75 | -3.54% | |
| **ContextTag** | **1781** | **1034** | **-747** | **-41.94%** | **Known / acceptable** — platform-managed inheritance artifact (per task warning) |
| ContextUseCaseMapping | 6 | 6 | 0 | 0% | |
| ExpressionSet | 2 | 4 | +2 | +100% | |
| ExpressionSetVersion | 2 | 7 | +5 | +250% | |
| ExpressionSetDefinition | 5 | 4 | -1 | -20% | fulltemp has extra "Test" ESD |
| ExpressionSetDefinitionContextDefinition | 4 | 4 | 0 | 0% | Membership differs — see §3 |
| PricingActionParameters | 0 | 0 | 0 | — | |
| PricingRecipe | 1 | 1 | 0 | 0% | |
| PricingRecipeTableMapping | 14 | 11 | -3 | -21.43% | |
| **PricingProcedureOutputMap** | **26** | **0** | **-26** | **-100%** | **STRUCTURAL GAP** — present in fulltemp, missing in MergeBuild |
| RuleLibrary | 1 | 2 | +1 | +100% | |
| RuleLibraryDefinition | 2 | 2 | 0 | 0% | Membership differs — see §4 |
| RuleLibraryVersion | 1 | 2 | +1 | +100% | |
| RuleLibraryDefVersion | 3 | 2 | -1 | -33.33% | |
| Product2 | 8846 | 5214 | -3632 | -41.06% | |
| ProductClassification | 121 | 121 | 0 | 0% | |
| **ProductConfigurationFlow** | **1** | **0** | **-1** | **-100%** | **STRUCTURAL GAP** — fulltemp only |
| ProductConfigurationRule | 0 | 0 | 0 | — | |
| **ProductFulfillmentDecompRule** | **3326** | **0** | **-3326** | **-100%** | **STRUCTURAL GAP** — fulltemp only |
| **AttributeBasedAdjRule** | **25171** | **0** | **-25171** | **-100%** | **STRUCTURAL GAP** — fulltemp only |
| AttributeDefinition | 17 | 17 | 0 | 0% | |
| AttributeCategory | 11 | 11 | 0 | 0% | |
| DecisionMatrixDefinition | 0 | 0 | 0 | — | |
| DecisionTable | 19 | 22 | +3 | +15.79% | Membership differs — see §5 |
| CalculationMatrixColumn | 0 | 0 | 0 | — | |
| DecisionTableParameter | 163 | 182 | +19 | +11.66% | |

### Structural gaps (count > 0 in one org, 0 in the other)

| Object | fulltemp | MergeBuild | Direction |
| --- | ---: | ---: | --- |
| PricingProcedureOutputMap | 26 | 0 | fulltemp only |
| ProductConfigurationFlow | 1 | 0 | fulltemp only |
| ProductFulfillmentDecompRule | 3326 | 0 | fulltemp only |
| AttributeBasedAdjRule | 25171 | 0 | fulltemp only |

No object is non-zero in MergeBuild and zero in fulltemp.

---

## 2. ContextDefinition / ContextDefinitionVersion (ApiName/DeveloperName audit)

### ContextDefinition (DeveloperName)
| DeveloperName | fulltemp | MergeBuild |
| --- | :-: | :-: |
| ProductDiscoveryContextExt | ✓ (`inheritedFrom=ProductDiscoveryContext__stdctx`) | ✓ (same `inheritedFrom`) |
| SalesTransactionContextExt | ✓ (`inheritedFrom=SalesTransactionContext__stdctx`) | ✓ (same `inheritedFrom`) |

Both DeveloperNames and parent inheritance pointers match. **No mismatches.**

### ContextDefinitionVersion — version + active state (compare on `(DeveloperName, IsActive=true)`)

| CD DeveloperName | fulltemp version (active?) | MergeBuild version (active?) | Note |
| --- | --- | --- | --- |
| ProductDiscoveryContextExt | v1 (active=**false**) | v3 (active=true) | **⚠ fulltemp has NO active CDV for this CD** — every CDV is inactive |
| SalesTransactionContextExt | v2 (active=true) | v3 (active=true) | Version number differs — **expected** per platform-version warning |

VersionNumber differences are flagged but **acceptable** per the task's CDV warning, EXCEPT for ProductDiscoveryContextExt where fulltemp has no active CDV at all.

### ContextNode per-CDV
| CD DeveloperName | fulltemp CDV nodes | MergeBuild CDV nodes |
| --- | ---: | ---: |
| ProductDiscoveryContextExt | 8 | 9 (+1) |
| SalesTransactionContextExt | 45 | 44 (-1) |
| **Total** | **53** | **53** |

---

## 3. ExpressionSet / ExpressionSetDefinition / ExpressionSetVersion (ApiName audit) + ESD↔CD junctions

### ExpressionSetDefinition DeveloperNames
| DeveloperName | fulltemp | MergeBuild |
| --- | :-: | :-: |
| Product_Discovery_Pricing_Procedure | ✓ | ✓ |
| Rev_Mgmt_Default_Pricing_Procedure | ✓ | ✓ |
| Salesforce_Default_Pricing_Discovery_Procedure | ✓ | ✓ |
| Salesforce_Pricing_Discovery_Procedure | ✓ | ✓ |
| **Test** | **✓** | ✗ | **fulltemp only — likely stray sandbox test ESD; not promoted to MergeBuild** |

### ExpressionSet ApiNames
| ApiName | fulltemp (UsageType) | MergeBuild (UsageType) |
| --- | --- | --- |
| **Product_Discovery_Pricing_Procedure** | ✗ | DefaultPricing | **MISSING in fulltemp** |
| **Rev_Mgmt_Default_Pricing_Procedure** | ✗ | DefaultPricing | **MISSING in fulltemp** |
| Salesforce_Default_Pricing_Discovery_Procedure | PricingDiscovery | PricingDiscovery | match |
| Salesforce_Pricing_Discovery_Procedure | PricingDiscovery | PricingDiscovery | match |

Both `Product_Discovery_Pricing_Procedure` and `Rev_Mgmt_Default_Pricing_Procedure` exist as ExpressionSetDefinition in fulltemp but have **no corresponding ExpressionSet instances** — i.e. no executable pricing-procedure rules wired to those ESDs in fulltemp.

### ExpressionSetVersion ApiNames
fulltemp (2):
- `Salesforce_Default_Pricing_Discovery_ProcedureV1` — active
- `Salesforce_Pricing_Discovery_Procedure_V1` — active

MergeBuild (7):
- `Product_Discovery_Pricing_Procedure_V1` — active
- `Rev_Mgmt_Default_Pricing_Procedure_V1` — inactive
- `Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V40` — inactive
- `Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V50` — inactive
- `Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V60` — active
- `Salesforce_Default_Pricing_Discovery_ProcedureV1` — active
- `Salesforce_Pricing_Discovery_Procedure_V1` — active

The two shared ESVs (`Salesforce_*`) have **matching ApiNames** across orgs. The extra MergeBuild ESVs all belong to the two ExpressionSets missing from fulltemp.

### ExpressionSetDefinitionContextDefinition junctions — line-by-line

| # | Junction (ESD ↔ CD, inheritsFrom) | fulltemp | MergeBuild |
| - | --- | :-: | :-: |
| 1 | Product_Discovery_Pricing_Procedure ↔ ProductDiscoveryContextExt (`ProductDiscoveryContext__stdctx`) | ✓ | ✓ |
| 2 | **Rev_Mgmt_Default_Pricing_Procedure ↔ SalesTransactionContextExt (`SalesTransactionContext__stdctx`)** | **✗** | **✓** |
| 3 | Salesforce_Default_Pricing_Discovery_Procedure ↔ null (`null`) | ✓ | ✓ |
| 4 | Salesforce_Pricing_Discovery_Procedure ↔ SalesTransactionContextExt (`SalesTransactionContext__stdctx`) | ✓ | ✓ |
| 5 | **Test ↔ null (`null`)** | **✓** | **✗** |

**Diff summary:**
- ⚠ **Junction missing in MergeBuild only:** `Test ↔ null` — but this is the stray `Test` ESD that should not be promoted, so this is not a migration gap.
- ⚠ **Junction missing in fulltemp:** `Rev_Mgmt_Default_Pricing_Procedure ↔ SalesTransactionContextExt` — consistent with the missing `Rev_Mgmt_Default_Pricing_Procedure` ExpressionSet/ExpressionSetVersion in fulltemp. **fulltemp is the org behind here**, not MergeBuild.

---

## 4. RuleLibrary / RuleLibraryDefinition (ApiName/DeveloperName audit)

### RuleLibrary (ApiName)
| ApiName | fulltemp | MergeBuild |
| --- | :-: | :-: |
| DRORuleLibrary | ✓ | ✓ |
| **ProductRuleLibrary** | ✗ | ✓ | **MergeBuild only** |

### RuleLibraryDefinition (DeveloperName)
| DeveloperName | fulltemp | MergeBuild |
| --- | :-: | :-: |
| DRORuleLibrary | ✓ | ✓ |
| **Rule_Library** | **✓** | ✗ | **fulltemp only** |
| **ProductRuleLibrary** | ✗ | **✓** | **MergeBuild only** |

Net: each org has one RLD the other lacks. The MergeBuild `ProductRuleLibrary` matches a like-named `RuleLibrary` instance, while the fulltemp `Rule_Library` RLD has no matching `RuleLibrary` row (RuleLibrary count is 1 in fulltemp = `DRORuleLibrary` only).

---

## 5. DecisionTable membership diff

Same 19 in both orgs. MergeBuild adds three:
- `Fulfillment_Step_Jeopardy_Rule_Decision_Table`
- `FulfillmentFalloutRules`
- `MaintenanceType`

No DT exists in fulltemp but is missing in MergeBuild.

`DecisionMatrixDefinition` is 0 in both orgs (no detail to compare).

---

## 6. Permset audit (Section 6)

> ⚠ **The diagnostic ran as `liam.jeong.c@fortra.com.<alias>` (Liam's user), NOT Sara's DevOps integration user.** The script audits whichever user runs it (`UserInfo.getUserId()`), so to verify Sara's user the script would need to be filtered by her `AssigneeId` or executed via that user's session. Results below are for Liam's user in each org.

| Permset | fulltemp (liam) | MergeBuild (liam) |
| --- | :-: | :-: |
| ProductCatalogManagementAdministrator | ASSIGNED | **MISSING** |
| UnifiedCatalogAdmin | ASSIGNED | ASSIGNED |
| Revenue_Cloud_Admin | ASSIGNED | ASSIGNED |

**Action:** Liam's MergeBuild user is missing `ProductCatalogManagementAdministrator`. To verify Sara's DevOps integration user, re-run with the WHERE filter pointing at her AssigneeId in both orgs.

---

## 7. Section 7 — DML restrictions

All 11 objects audited produce **identical** `createable / updateable / deletable / hasGearsetExtId` flags across both orgs:

| Object | createable | updateable | deletable | hasGearsetExtId |
| --- | :-: | :-: | :-: | :-: |
| ContextAttribute | false | false | false | false |
| ContextDefinition | false | false | false | false |
| ContextDefinitionVersion | false | false | false | false |
| ContextNode | false | false | false | false |
| ExpressionSet | **true** | **true** | **true** | false |
| ExpressionSetDefinition | false | false | false | false |
| ExpressionSetDefinitionContextDefinition | false | false | false | false |
| ExpressionSetVersion | **true** | **true** | **true** | false |
| PricingActionParameters | false | false | false | false |
| PricingRecipe | false | false | false | false |
| RuleLibrary | **true** | **true** | **true** | false |

**No DML restriction differences between the orgs.** Three objects are DML-writable in both (`ExpressionSet`, `ExpressionSetVersion`, `RuleLibrary`); all others are read-only via the standard SObject API in both orgs. The `gearsetexternalid__c` field is absent from every audited object in both orgs.

(Note: the task spec referred to "Section 8 of the diagnostic" for DML restrictions; in the actual script DML restrictions are Section 7. There is no Section 8.)

---

## Overall summary

**Structural gaps to investigate (fulltemp has, MergeBuild lacks):**
1. `PricingProcedureOutputMap` (26 → 0)
2. `ProductConfigurationFlow` (1 → 0)
3. `ProductFulfillmentDecompRule` (3326 → 0)
4. `AttributeBasedAdjRule` (25171 → 0)
5. `RuleLibraryDefinition` `Rule_Library` (DeveloperName)

**Gaps in the other direction (MergeBuild has, fulltemp lacks):**
1. `ExpressionSet` `Product_Discovery_Pricing_Procedure` + corresponding ESV (`Product_Discovery_Pricing_Procedure_V1`)
2. `ExpressionSet` `Rev_Mgmt_Default_Pricing_Procedure` + 4 ESVs (v1, v4, v5, v6)
3. ESD↔CD junction `Rev_Mgmt_Default_Pricing_Procedure ↔ SalesTransactionContextExt`
4. `RuleLibrary` + `RuleLibraryDefinition` `ProductRuleLibrary`
5. 3 DecisionTables: `Fulfillment_Step_Jeopardy_Rule_Decision_Table`, `FulfillmentFalloutRules`, `MaintenanceType`

**Known / acceptable differences (per task spec):**
- `ContextTag` count delta (-41.94%) — platform-managed inheritance artifact; both orgs non-zero
- CDV `VersionNumber` differences (v1/v2 vs v3) — expected drift between fulltemp and MergeBuild

**No differences in:**
- DML restrictions
- ContextDefinition DeveloperNames / inheritance parents
- ExpressionSetDefinition DeveloperNames (apart from the stray `Test` in fulltemp)
- Total ContextNode count

**One open item:** ProductDiscoveryContextExt in fulltemp has only `v1 (active=false)`; in MergeBuild it has `v3 (active=true)`. If anything in fulltemp depends on an active CDV for this CD, it will not resolve.
