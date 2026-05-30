# SC-3137 — Production RCA Data Purge Plan

*Prepared for Ben Kozlowski (Principal Solution Architect, Coastal Cloud) | by Liam Jeong, 5S Infusion | Drafted 2026-05-22 | Cutover: 2026-06-08*

---

## Summary

Production is **not empty.** All RCA-related rows in `FortraProduction` were created by a single Fortra integration user (`nir.kailash.c@fortra.com`) via earlier Gearset deploys. Marc DeBrey has flagged **16 RCA-related objects (~46.7k rows) for purge** on his 2026-05-15 spreadsheet, intent being to replace them with the authoritative UAT-origin master set at cutover.

The operation is a **per-object reconcile**, not a blanket teardown. The dominant selector pattern is `GearsetExternalId__c IS NOT NULL` (100% fill on 9 of 11 objects that have the field). Two objects need alternate selectors. Four objects flagged by Marc need pre-cutover decision points. Four core RCA features must be enabled by Marc before purge + load can run.

Total execution window estimate: **30–50 minutes purge + 2–3 hours load + verification.**

The principal SC-3137 payload (`ProductConfigurationRule`, 302 rules) **has no programmatic migration path** — confirmed today against prod schema as well (`createable=False` on every field, same as MergeBuild). PCR resolution is tracked separately; not in scope for this purge plan.

---

## 1. Production state (2026-05-22 live)

`FortraProduction` org `00Da5000015FRLrEAO`. Fresh diagnostic captured today:

| Layer | Prod state | Source |
|---|---|---|
| ContextDefinition / Version | 2 / 2 (`ProductDiscoveryContextExt v3`, `SalesTransactionContextExt v3` — both active, dated 2026-05-15) | Marc's prior CDV deploy — matches MergeBuild v3 baseline |
| Context children | CN=52, CA=771, CM=17, CNM=139, CAM=2,031, CTag=775 | Downstream of v3 CDV |
| RuleLibrary chain | 2 / 2 / 2 / 2 | Prod-aligned (`DRORuleLibrary` + `ProductRuleLibrary`) |
| Decision Tables | 12 (vs UAT 22) | Subset; missing 10 |
| Product Catalog | 2 ProductCatalog, 187 ProductCategory, 5,421 Product2 (all active) | Gearset deploy by `nir.kailash.c` |
| PricebookEntry | 27,093 | Gearset deploy by `nir.kailash.c` (single creator, 100% of rows) |
| Pricing rules | 0 ABA, 0 PCR, 0 PCF | Empty — load target |
| Pricing procedure stack | 2 ES, 2 ESD, 2 ESV — `Rev_Mgmt_Default_Pricing_Procedure v1` active, junction to `SalesTransactionContextExt` already bound | Partial; missing 3 of UAT's 5 ESs |
| PricingActionParameters | 0 | Manual UI creation needed (RC-16 / cutover-day work) |
| PricingRecipe | 1 (`NGPDefaultRecipe`) | Platform-seeded; do not touch |
| `pse__Practice__c` schema | does not exist | PSA managed package not installed |
| `TaxPolicy` / `TaxTreatment` schema | do not exist | Tax feature not enabled |
| `ProductFulfillmentDecompRule` schema | does not exist | RCA feature not fully enabled |
| `ProductConfigurationRule` schema | exists, `createable=False`, `updateable=False`, `deletable=True` | Same constraint as MergeBuild; no programmatic path |
| Operator permsets (Liam) | PCM Admin, UnifiedCatalogAdmin, Revenue_Cloud_Admin all **MISSING** | Pre-cutover assignment required |

**Operational consequence.** The fulltemp-style blanket teardown is moot. The work is selective: purge what Marc has flagged as superseded-by-UAT, leave what is shared baseline, load what is still empty. **Marc's cutover steps 1 and 2 must enable Tax, PFDR, PSA (if in scope), and the operator's permsets before SC-3137 step 5b can begin.**

---

## 2. SC-3137 in Marc's cutover sequence

SC-3137 is **step 5b** in Marc's 7-step production cutover sequence. Steps 1–5a are hard handoff gates.

| # | Description | Tool | Owner |
|---|---|---|---|
| 1 | Manual enablement of Revenue Cloud Advanced, Tax, ProductFulfillmentDecompRule | Setup UI | Marc |
| 2 | Manual setup: bind `SalesTransactionContextExt`, Rebuild Product Index, assign Fortra permsets to operator, confirm `Fortra_Pricing_PreHook` | Setup UI | Marc |
| 3 | SF Project Build metadata (Lightning Record Pages, non-RCA fields, Actions, Flows) | Gearset Metadata | Sara |
| 4 | Pricing Procedure Stack — 8 phases (ExpressionSets, versions, Context bindings, PricingActionParameters) | Gearset Metadata | TBD |
| 5a | Custom Metadata records — `COLA_Uplift_Rules`, `MyCAP_Rules`, `Services_Regional_Pricing` | Gearset Metadata | TBD |
| **5b** | **RCA Configuration Data Deploy + this purge plan** | **Gearset RCA Add-on (Data) + SF CLI** | **Liam (SC-3137)** |
| 6 | Decision Table activation per table after rows are loaded | Setup UI | Marc |
| 7 | Rebuild Product Index in Setup | Setup UI | Marc |

---

## 3. Per-object disposition matrix

The authoritative purge list is Marc DeBrey's "Production Record Counts by Object — May 15, 2026" spreadsheet, filtered to `Consider Purge = Yes AND Purge = Yes`. Counts below reconciled with today's live prod query.

Decision codes:

- **PURGE** — delete prod rows, then load fresh from UAT/MB
- **KEEP** — leave alone (out of scope or already correct)
- **LOAD** — prod is empty (or schema doesn't exist yet); full load after Marc's prerequisite gates
- **SKIP** — no-op
- **CONFIRM** — Marc-flagged but evidence suggests mis-tag; must verify before action

| # | Object | Prod | UAT | MB | Decision | Selector | Notes |
|---:|---|---:|---:|---:|---|---|---|
| 1 | `Attribute_Tier_Pricing_Storage__c` | 1,147 | 1,115 | 1,115 | **PURGE** | `CreatedById = '<nir.kailash.c>'` ⚠️ no `GearsetExternalId__c` field | Custom object. 100% Nir-created in prod. Net +32 vs UAT/MB. Marc-flagged as RCA master from UAT. |
| 2 | `DataUsePurpose` | 0 | 0 | 0 | **SKIP** | n/a | Zero everywhere |
| 3 | `EntitlementTemplate` | 0 | 0 | 0 | **SKIP** | n/a | Zero everywhere |
| 4 | `PriceAdjustmentSchedule` | 3 | 1 | 0 | **PURGE + LOAD** | `GearsetExternalId__c != null` (100% fill) | Prod 3, UAT 1; net delta likely 2 superseded |
| 5 | `PriceAdjustmentTier` | 1,953 | 0 | 0 | **PURGE** | `CreatedById = '<nir.kailash.c>'` ⚠️ **`GearsetExternalId__c` only 10% filled (200/1953)** — Gearset-fence would miss 1,753 rows | All 1,953 are 100% Nir-created. UAT and MB are 0; this is purely prod-only data. |
| 6 | `Pricebook2` | 1 | 11 | 11 | **PURGE + LOAD** | `IsStandard = false` (preserve Standard) | Prod has only the Standard Pricebook (1); load 10 missing non-standard from UAT/MB |
| 7 | `PricebookEntry` | 27,093 | 158,798 | 31,785 | **PURGE + LOAD** | `GearsetExternalId__c != null` (100% fill) | All 27,093 Nir-created. Use `PbeTeardownBatch.cls` at scope 500. Largest single object. |
| 8 | `ProcessDefinition` | 10 | 15 | 14 | **🔴 CONFIRM** | n/a | **All 10 prod records are NOT RCA** (2 Knowledge workflows, Marketing Funds Approval, Deal Reg Approval, 6 PSA timecard/expense/skill approvals). Live business processes. **Default: KEEP. Require explicit Marc confirmation before any action.** |
| 9 | `Product2` | 5,421 | 8,846 | 8,853 | **PURGE + LOAD** | `GearsetExternalId__c != null` (100% fill) | 100% Nir-created. Master from UAT (8,846) or MB (8,853). |
| 10 | `ProductCatalog` | 2 | 10 | 2 | **PURGE + LOAD** | `GearsetExternalId__c != null` (100% fill) | Prod and MB align (2 each); UAT 10. Decide load source before deploy. |
| 11 | `ProductCategory` | 187 | 209 | 187 | **PURGE + LOAD** | `GearsetExternalId__c != null` (100% fill) | Prod and MB align; UAT has 22 more |
| 12 | `ProductCategoryProduct` | 4,047 | 2,200 | 2,200 | **PURGE + LOAD** | `GearsetExternalId__c != null` (100% fill) | Prod has MORE than UAT/MB; Marc's intent is to align to UAT-origin 2,200 |
| 13 | `ProductRelatedComponent` | 1,401 | 1,417 | 1,413 | **PURGE + LOAD** | `GearsetExternalId__c != null` (100% fill) | Bundle topology. Net delta to MB ≈ +12 rows |
| 14 | `ProductSellingModel` | 9 | 9 | 9 | **KEEP** | n/a | Three orgs agree; PSM is lifecycle-locked anyway (cannot delete; one-way Draft → Active → Inactive). Safe to leave. |
| 15 | `ProductSellingModelOption` | 5,421 | 8,794 | 8,799 | **PURGE + LOAD** | `CreatedById = '<nir.kailash.c>'` ⚠️ no `GearsetExternalId__c` field | All 5,421 Nir-created. Net delta to MB ≈ +3,378 rows. |
| 16 | `Quote` | 2 | 166,090 | 1 | **PURGE** | All rows (verified test data) | **Confirmed today:** both prod Quotes are explicit test records by Coastal Cloud staff. See §6.1. Do NOT pull Quote data from UAT (166k live quotes). |

### Objects requiring schema enablement before SC-3137 step 5b

Four objects do not exist as schema in `FortraProduction` (confirmed today via `sf sobject describe`):

| Object | UAT | MB | Note |
|---|---:|---:|---|
| `ProductFulfillmentDecompRule` | 3,326 | 3,326 | Marc cutover step 1 — RCA feature enablement |
| `TaxPolicy` | 1 | 1 | Marc cutover step 1 — Tax feature enablement |
| `TaxTreatment` | 1 | 1 | Marc cutover step 1 — Tax feature enablement |
| `pse__Practice__c` | 29 | 25 | PSA managed package — not installed in prod; `Product2.Practice__c` FK will null on prod load (acceptable per current Fortra design) |

### Objects to leave alone

| Object | Prod | Notes |
|---|---:|---|
| `ContextDefinition` / `ContextDefinitionVersion` | 2 / 2 (v3 active) | Already at intended v3 baseline; matches MergeBuild |
| `ContextNode` / `ContextAttribute` / `ContextMapping` / `ContextNodeMapping` / `ContextTag` | 52 / 771 / 17 / 139 / 775 | Downstream of v3 CDV; row-count differences are platform-version downstream, not data gaps |
| `RuleLibrary` chain | 2 / 2 / 2 / 2 | Prod-aligned naming |
| `PricingRecipe` | 1 (`NGPDefaultRecipe`) | Platform-seeded; Id stable cross-org |
| `AttributeDefinition` / `AttributeCategory` / `AttributePicklist` / `AttributePicklistValue` | 16 / 11 / 15 / 2,108 | Phase 1 baseline; prod has 1 fewer AttributeDefinition than UAT (16 vs 17) — verify which is missing during load planning |

### Objects to load (post-purge or independent)

| Object | Prod | Source | Notes |
|---|---:|---|---|
| `AttributeBasedAdjRule` | 0 | UAT/MB (25,171) | Phase 3b principal load |
| `ProductConfigurationFlow` | 0 | UAT (1) | Phase 3b |
| `ProductFulfillmentDecompRule` | n/a → load 3,326 | UAT/MB | After Marc step 1 enables the feature |
| `PricingActionParameters` | 0 | Manual Setup UI per RC-16 (no migration path; 2 records, ~10 min) | After Marc step 1 |
| `PricingRecipeTableMapping` | 11 | UAT (12) | One row missing — load with composite-key remap pattern used in MergeBuild |
| `PricingProcedureOutputMap` | 0 | UAT (26) | Phase 3a |
| `ProductClassification` | 110 | UAT (121) | 11 missing |
| `ProductClassificationAttr` | 372 | UAT (379) | 7 missing (subset of MergeBuild's documented 49 platform-validation residue) |
| `ProductComponentGroup` | 416 | UAT (421) | 5 missing |
| `DecisionTable` | 12 | UAT (22) | 10 missing; activate each per Marc step 6 after rows load |
| `DecisionTableParameter` | 113 | UAT (179) | 66 missing |
| `UnitOfMeasure` / `UnitOfMeasureClass` | 0 / 0 | UAT (22 / 4) via Apex fixture | Schema exists; needs 4-pass UoM fixture per RC-6 |
| `ExpressionSet` / `ExpressionSetDefinition` / `ExpressionSetVersion` | 2 / 2 / 2 | UAT (5 / 5 / 10) | Via Gearset Preserve References per RC-9, or part of Marc cutover step 4 |
| `ProductConfigurationRule` | 0 | UAT (302) — **no programmatic path** | Separate decision (Salesforce Support / manual entry / scope deferral); not in this purge plan |

---

## 4. Purge order — reverse-dependency

Salesforce throws `DELETE_NOT_ALLOWED` if a parent is deleted while children still reference it. Execute in this order:

```
WAVE 1 — leaf / dependent data
  1a. PriceAdjustmentTier              (1,953)  — children of PriceAdjustmentSchedule
  1b. ProductRelatedComponent          (1,401)  — references Product2 + ProductComponentGroup
  1c. ProductCategoryProduct           (4,047)  — junction Product2 ↔ ProductCategory
  1d. ProductSellingModelOption        (5,421)  — junction Product2 ↔ ProductSellingModel
  1e. Attribute_Tier_Pricing_Storage__c (1,147)  — custom; verify no QuoteLine FKs
  1f. PricebookEntry                  (27,093)  — junction Pricebook2 ↔ Product2  (PbeTeardownBatch, scope 500)
  1g. Quote                                (2)  — verified test data; verify no Order linkage at T-0

WAVE 2 — mid-level
  2a. PriceAdjustmentSchedule              (3)  — parent of PriceAdjustmentTier (already gone)
  2b. ProductCategory                    (187)  — parent of ProductCategoryProduct (already gone)

WAVE 3 — root catalog objects
  3a. ProductCatalog                       (2)  — parent of ProductCategory (already gone)
  3b. Product2                         (5,421)  — referenced by ALL above; must be last in the product graph

KEEP / DO NOT DELETE
  ProductSellingModel (9)       — lifecycle-locked (cannot delete in any reachable status)
  ProcessDefinition (10)        — confirmed NOT RCA; default KEEP unless Marc explicitly confirms
  Pricebook2 (1, Standard)      — Standard Pricebook is not deletable by design (selector excludes it)
```

### Batch sizing and runtime estimates

| Object | Volume | Strategy | Est. runtime |
|---|---:|---|---|
| `PricebookEntry` | 27,093 | `PbeTeardownBatch.cls` (Bulk API, scope 500) | 8–15 min |
| `Product2` | 5,421 | Bulk API DELETE, 1 call | 1–2 min |
| `ProductSellingModelOption` | 5,421 | Bulk API DELETE, 1 call | 1–2 min |
| `ProductCategoryProduct` | 4,047 | Bulk API DELETE, 1 call | 1–2 min |
| `PriceAdjustmentTier` | 1,953 | Bulk API DELETE, 1 call | <1 min |
| `ProductRelatedComponent` | 1,401 | Bulk API DELETE, 1 call | <1 min |
| `Attribute_Tier_Pricing_Storage__c` | 1,147 | Bulk API DELETE, 1 call | <1 min |
| `ProductCategory` | 187 | REST | <1 min |
| `Pricebook2` (non-Standard) | 0 (after Standard fence) | n/a | — |
| `ProductCatalog` | 2 | REST | <1 min |
| `PriceAdjustmentSchedule` | 3 | REST | <1 min |
| `Quote` | 2 | REST | <1 min |
| **Total purge window** | **46,694** | | **15–25 min wall time** |

---

## 5. Selector strategy

Production was seeded by a single integration user (`nir.kailash.c@fortra.com`), confirmed today across all 6 high-volume purge-candidate objects (100% sole creator). This makes the **CreatedById fence** a reliable backup selector everywhere `GearsetExternalId__c` is partial or absent.

### Primary selector: `GearsetExternalId__c IS NOT NULL`

Applies to 8 objects (verified 100% fill today):

```
Product2, PricebookEntry, Pricebook2, ProductCategory, ProductCatalog,
ProductCategoryProduct, ProductRelatedComponent, ProductSellingModel,
PriceAdjustmentSchedule
```

### Fallback selectors

| Object | Reason | Selector |
|---|---|---|
| `PriceAdjustmentTier` | `GearsetExternalId__c` only 10% filled (200/1,953) | `CreatedById = '<nir.kailash.c.user.Id>'` (100% of rows match) |
| `ProductSellingModelOption` | No `GearsetExternalId__c` field | `CreatedById = '<nir.kailash.c.user.Id>'` (100% match) |
| `Attribute_Tier_Pricing_Storage__c` | No `GearsetExternalId__c` field | `CreatedById = '<nir.kailash.c.user.Id>'` (100% match) |
| `Quote` | Limited to 2 verified test records | `Name LIKE 'Test Quote%'` |
| `Pricebook2` | Must preserve Standard | `IsStandard = false` |

### Mandatory pre-DELETE validation

For every selector above, run `SELECT COUNT() FROM <Object> WHERE <selector>` before `DELETE`. Confirm count matches Marc's expected purge volume from his spreadsheet. **If divergent by more than 5%, halt** — selector is wrong or prod has drifted since 2026-05-15.

---

## 6. Sensitive items — verify before delete

### 6.1 `Quote` — verified test data (low risk)

Confirmed today via direct SOQL:

| Id | Name | Status | Account | Opportunity | Created By | Created |
|---|---|---|---|---|---|---|
| `0Q0a50000018TInCAM` | Test Quote | Draft | — | — | `nicholas.hackworth@coastalcloud.fortra` | 2025-06-17 |
| `0Q0aZ000007ldGPSAY` | Test Quote 2 | Draft | Test Account | Test Opportunity | `aaron.broom@coastalcloud.fortra` | 2026-05-15 |

Both are explicit test records by Coastal Cloud staff. No live customer linkage. Safe to purge after Marc/Liam sign-off. Re-verify at T-2h that no real customer Quote has appeared since 2026-05-22.

### 6.2 `ProductConfigurationRule` schema exists with `createable=False`

**New finding today (2026-05-22):** `ProductConfigurationRule` schema **exists in production** (confirmed via `sf sobject describe`), but with the same constraint as MergeBuild: `createable=False`, `updateable=False`, `deletable=True`. **Same migration block as MB — no programmatic insert path.**

The 302-rule resolution decision (Salesforce Support / manual UI entry / scope deferral) applies identically to prod as to MB. Not in scope for this purge plan; tracked separately.

### 6.3 `ProductSellingModel` — lifecycle-locked, keep regardless

Cycle 1 testing in fulltemp proved PSM cannot be deleted in any reachable status (`Draft → Active → Inactive` is one-way; deletion requires `Draft`; `Draft` is unreachable from any other status). Prod has 9 PSM rows at parity with UAT/MB; leave them in place. PSM is excluded from the purge order regardless of Marc's flag.

### 6.4 `ProcessDefinition` — 🔴 likely Marc mis-tag

All 10 prod `ProcessDefinition` records, re-verified today:

| Name | Type | State | Target |
|---|---|---|---|
| KBWorkflow | State | Inactive | KnowledgeArticle |
| KBTranslationSubWorkflow | State | Inactive | KnowledgeArticleVersion |
| Marketing Funds Request Approval V4 | Approval | Active | `Marketing_Fund_Request__c` |
| Deal Registration Approval | Approval | Active | Opportunity |
| PSA Manager Approves ER | Approval | Active | `pse__Expense_Report__c` |
| PSA PM Approves Expense Report | Approval | Active | `pse__Expense_Report__c` |
| PSA Skills/Certification Resource to LM | Approval | Active | `pse__Skill_Certification_Rating__c` |
| PSA Timecard PM to LM of Project/Global | Approval | Active | `pse__Timecard_Header__c` |
| PSA Timecard Resource to PM of Project | Approval | Active | `pse__Timecard_Header__c` |
| PSA Timecard Auto-Approve | Approval | Inactive | `pse__Timecard_Header__c` |

All 10 are live Workflow / Approval Process definitions for Knowledge, Marketing, Sales (Deal Reg), and PSA. **None is an RCA artifact.** Marc's purge flag on this object is almost certainly erroneous. **Action: explicit Marc confirmation required before any action. Default: KEEP.**

### 6.5 `Product2` downstream dependency scan

Prod has 5,421 Product2 records (all `nir.kailash.c`-created). Before bulk-deleting, scan for live references:

```sql
SELECT COUNT() FROM OpportunityLineItem WHERE Product2Id IN (<purge target ids>)
SELECT COUNT() FROM OrderItem           WHERE Product2Id IN (<purge target ids>)
SELECT COUNT() FROM QuoteLineItem       WHERE Product2Id IN (<purge target ids>)
SELECT COUNT() FROM Asset               WHERE Product2Id IN (<purge target ids>)
```

If any returns non-zero, those rows have downstream commitments and cannot be hard-deleted (`DELETE_FAILED: linked records exist`). Mitigation: switch from DELETE to `IsActive = false` for the affected Product2 rows. Marc's spreadsheet shows prod `OpportunityLineItem` = 0 and `QuoteLineItem` = 0 as of 2026-05-15; re-verify at T-0.

### 6.6 `Attribute_Tier_Pricing_Storage__c` +32 row delta

Prod has 1,147 (all Nir-created); UAT and MB have 1,115. Marc's spreadsheet notes "Master data set is coming from UAT" but the +32 delta suggests either prod has unique extension rows or earlier Nir activity diverged. **[verify with Liam / Marc]** whether the +32 are real Fortra extensions to retain or contamination to purge.

---

## 7. Selector validation procedure (mandatory)

Before any `DELETE`:

1. Run `SELECT COUNT() FROM <Object> WHERE <selector>` — capture in `purge_preflight.txt`
2. Compare against Marc's expected purge volume (his "Active" column)
3. If divergent by more than ~5%, **halt** — selector mismatch or prod has drifted
4. Spot-check 3–5 sample rows: `SELECT Id, CreatedById, GearsetExternalId__c FROM ... LIMIT 5` — confirm they match intended profile
5. Get Marc/Liam green light, then execute `DELETE` (Bulk API)
6. After delete, query the same selector again — confirm count = 0
7. Capture results in `purge_postflight_<object>.txt`

Repeat per object. No skipped validations.

---

## 8. Rollback plan

Salesforce default DELETE is **soft delete:**

- Records go to `IsDeleted = true` state, retrievable via `SELECT ... ALL ROWS` and the UI Recycle Bin
- Default retention: 15 days, or until Recycle Bin is full (50 KB × num licenses)
- Hard delete via Bulk API `hardDelete` operation is **not recoverable**

**Mandatory rules during cutover window:**

- Use `sf data delete bulk` (which is soft delete by default per the CLI's underlying API)
- **Do NOT empty Recycle Bin** during the cutover window or for 7 days post-cutover
- If anything goes wrong, run `undelete` within 15 days

If a category of records must be permanently removed (e.g., recovered space after sign-off), wait until 7 days post-cutover with Marc/Liam sign-off, then use Bulk API `hardDelete` only on confirmed-stable records.

---

## 9. Delete-lock surfaces

Behaviors observed in Cycle 1 / Cycle 2 that may apply at cutover:

| Object | Behavior | Mitigation |
|---|---|---|
| `Pricebook2` (Standard) | `IsStandard=true` cannot be deleted | Selector `WHERE IsStandard = false` |
| `ProductSellingModel` | Lifecycle-locked (Draft → Active → Inactive one-way) | Keep — excluded from purge |
| `ProductRelatedComponent` (bundle structures) | May reject delete if parent bundle Product2 is referenced by a quote line | Verify no QuoteLineItem references the bundle first |
| `TaxTreatment` | Deletable but with platform Inactive-and-park pattern | `IsActive=false` first, then delete (likely irrelevant in prod since TaxTreatment schema doesn't exist yet) |

These do not surface via `sf sobject describe` (most show `deletable: true` in describe). The pattern is **try delete, fall back to deactivate-and-park if locked.**

---

## 10. Pre-purge gates

Mandatory confirmations before purge starts:

| Gate | Owner | Verification |
|---|---|---|
| Marc cutover step 1 complete — RCA enablement, Tax enablement, PFDR object available, Rebuild Product Index | Marc | `sf sobject describe -s ProductFulfillmentDecompRule -o FortraProduction` returns existing schema; `SELECT COUNT() FROM TaxPolicy` returns 1 |
| Marc cutover step 2 complete — permsets assigned to operator user, junction binding confirmed, `Fortra_Pricing_PreHook` confirmed | Marc | Operator user has PCM Admin + UnifiedCatalogAdmin + Revenue_Cloud_Admin permsets |
| Marc cutover steps 3, 4, 5a complete — metadata deploys, Pricing Procedure stack, custom metadata records | Sara / TBD | Spot check via SOQL on `ExpressionSetDefinition` count and PricingActionParameters presence |
| Production credentials issued to Liam | Wren | `sf org display -o FortraProduction` returns `Connected` |
| 🔴 **`ProcessDefinition` mis-tag clarified** — Marc explicit yes/no on whether to delete the 10 non-RCA approval processes | Marc | **Default: KEEP if no explicit yes** |
| Production RC platform `InheritedFromVersion` confirmed compatible with MergeBuild's 66.24 | Wren | Pre-cutover query |
| No live customer Quote created in the 2 prod Quote slots since 2026-05-22 | Marc | Re-verify at T-2h via `Name LIKE 'Test Quote%'` |
| `Attribute_Tier_Pricing_Storage__c` +32 row delta classified (real Fortra extension vs contamination) | Liam + Marc | Resolved before §6.6 selector commits |
| PCM Product source-of-truth decision — concurrent edits between `nir.kailash.c` (prod-origin) and Liam (UAT-origin) | Marc | Resolved before load phase |

If any gate is open at T-2h, **halt**; do not run purge against incomplete state.

---

## 11. Post-purge load sequence

After purge completes, load follows the standard Phase 1 → 2 → 3a → 3b order:

1. **Phase 1** — PCM foundation (UnitOfMeasure / UoMClass 4-pass fixture per RC-6, AttributeDefinition / AttributeCategory / ProductSellingModel verify, RecordType)
2. **Phase 2** — PCM + Pricing (Product2 with `BasedOnId`, PricebookEntry chunked, PAD, PCP, PSMO)
3. **Phase 3a** — Reference data via Gearset Preserve References **with per-object natural-key matching** (Product2 → ProductCode, ProductClassification → Code, DecisionTable → DeveloperName) — see RC-15 preventive
4. **Phase 3b** — Per-product rules: AttributeBasedAdjRule (25K), ProductFulfillmentDecompRule (3.3K + FK backfill if Gearset strips FKs again), ProductConfigurationFlow (1)
5. **Bucket B** — Context family deltas (likely skippable per RC-14 — prod CDV is v3 baseline matching MB)
6. **Bucket C** — PricingRecipeTableMapping (1-row delta) + PricingProcedureOutputMap (26 rows) via REST + composite-key remap per RC-13
7. **Bucket D** — 2 PricingActionParameters via Setup UI per RC-16
8. **PCR** — currently no programmatic path; defer per separate decision

Total load window estimate: **2–3 hours wall time**, weighted toward PBE bulk and ABA bulk.

---

## 12. Risk register

| # | Risk | Probability | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Marc edits prod data during purge window | Medium | Selector might delete Marc's new work | Time-locked window — explicit Marc lockout 2h before, 4h after purge starts |
| R2 | Selector returns more rows than expected (drift since 2026-05-15 snapshot) | Medium | Could delete real data | Mandatory pre-DELETE COUNT validation; halt if delta > 5% |
| R3 | RC platform delete-lock on PRC or PSMO | Low | DELETE_NOT_ALLOWED; partial purge | Inactive-and-park fallback for affected rows |
| R4 | **`ProcessDefinition` mis-tag purges live approval processes** | **Critical if not caught** | Marketing / Sales / PSA approval flows break | Default to KEEP; explicit Marc green light required to PURGE |
| R5 | Marc's prerequisite steps (1–5a) incomplete at cutover T-2h | High | SC-3137 step 5b blocked | Hard gate; SOQL verification at T-2h, T-1h, T-0 |
| R6 | Production RC platform version drift from MergeBuild | Unknown | New validation behaviors not seen in dress rehearsal | Verify prod `InheritedFromVersion` with Wren pre-cutover |
| R7 | Live Quote / Order references to purged Product2 | Low (per Marc snapshot) | Delete fails or breaks linked record | Pre-purge dependency scan on `OpportunityLineItem`, `OrderItem`, `Asset`, `QuoteLineItem` |
| R8 | PCR cannot be migrated programmatically — principal payload short | High | SC-3137 ships without enforced co-requisite rules | Out of purge-plan scope; tracked separately. UI manual-entry path documented in `Data/sc3137/pcr_manual_entry_worklist.csv` (302 rules) |
| R9 | Bulk API DELETE soft-deletes leave Recycle Bin full → blocks subsequent deletes | Low | DELETE failures mid-purge | Pre-check Recycle Bin space; do not hardDelete during window |

---

## 13. Operator runbook outline

Cutover-day execution sequence:

1. **T-2h** — Pre-flight gates §10 all green
2. **T-1h** — Marc cutover steps 1–5a verified complete; permsets assigned to operator
3. **T-0:00** — Selector validation §7 per object
4. **T+0:00** — Wave 1 deletes (~15 min)
5. **T+0:15** — Wave 1 post-flight count verify
6. **T+0:20** — Wave 2 deletes
7. **T+0:25** — Wave 3 deletes
8. **T+0:30** — Full post-purge state capture (re-run RCA setup verification Apex against prod, save baseline)
9. **T+0:35** — Begin Phase 1 of load sequence §11
10. **T+1:30** — End of Phase 2 checkpoint
11. **T+2:30** — End of Phase 3b; smoke test
12. **T+3:00** — Hand off to Marc for cutover steps 6 + 7

**SC-3137 step 5b total window: ~3.0–3.5 hours.**

---

## 14. Artifacts referenced

- [SC-3137 RCA Migration Roadmap (internal v3.8)](../../../docs/SC-3137_RCA_Migration_Roadmap_v3.2.md)
- [Companion document — RCA Migration History & Roadmap](Ben_RCA_Migration_History_and_Roadmap.md)
- [Production RCA setup verification 2026-05-20](../../../scripts/apex/output/rca_diag_FortraProduction.clean.txt) — baseline
- Marc DeBrey's "Production Record Counts by Object — May 15, 2026" — authoritative purge candidate list (`~/Downloads/Production Record Counts by Object - May 15, 2026 - May 15, 2026.csv`)
- [`PbeTeardownBatch.cls`](../../../force-app/main/default/classes/PbeTeardownBatch.cls) — chunked PricebookEntry teardown Batch class
- [`RcaTeardownBatch.cls`](../../../force-app/main/default/classes/RcaTeardownBatch.cls) — generic RCA object teardown Batch class
- `/tmp/prod_diag_2026-05-22.json` — fresh 3-org count snapshot from today (Prod / UAT / MB) for all 50+ RCA-relevant objects

---

## 15. Open items needing Liam input

- **[verify with Liam]** Exact decision on whether to source post-purge load from UAT or MergeBuild. MB is more aligned to Marc's expected end-state shape; UAT is more current. Roadmap §10 doesn't lock this in.
- **[verify with Liam / Marc]** Whether `Attribute_Tier_Pricing_Storage__c`'s +32 prod delta vs UAT (1,147 vs 1,115) is real Fortra extension data or `nir.kailash.c` contamination.
- **[verify with Liam]** Whether to include Bucket B (Context family) loads in the cutover window or treat as post-cutover. Prod CDV is v3 baseline; 199-row gap is likely platform drift not real data and may not be needed.
- **[verify with Marc]** `ProcessDefinition` 10-record purge flag — confirmed all 10 are non-RCA approval processes. Default KEEP unless explicit yes.

---

*End of document*
