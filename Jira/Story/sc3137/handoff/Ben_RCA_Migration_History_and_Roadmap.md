# SC-3137 — RCA Configuration Data Migration: Roadmap

*Prepared for Ben Kozlowski (Principal Solution Architect, Coastal Cloud) | by Liam Jeong, 5S Infusion | Drafted 2026-05-22 | Cutover: 2026-06-08 (T-17)*

---

## TL;DR

Fortra is migrating Revenue Cloud Advanced (RCA) configuration data from `FortraUAT` to `FortraProduction` through a 4-org staging path: **UAT → fulltemp → MergeBuild → Production**. Approximately 228k records across ~50 sObjects in three layers (PCM foundation → PCM + Pricing → Configurator + Rules).

**Current state (as of 2026-05-22):**

- Cycle 1 (UAT → fulltemp) — ✅ Complete
- Cycle 2 (fulltemp → MergeBuild) — 🟡 ~99% complete by data volume
- Cutover (MergeBuild → Production) — 🔴 Scheduled 2026-06-08

**One critical open item:** `ProductConfigurationRule` (302 rules in UAT, 0 in MergeBuild). The principal SC-3137 payload. No public Salesforce migration path was found through any standard tool — only a single-record UI wizard in the Product Catalog Management app. 302-row manual-entry worklist staged at `Data/sc3137/pcr_manual_entry_worklist.csv`.

**Remaining work:** PCR resolution decision (Salesforce Support case vs manual entry), production purge per `Ben_Production_RCA_Purge_Plan.md`, post-purge load, functional smoke test. Estimated 4–6 hours of Liam-side execution at cutover, plus stakeholder coordination on Marc's prerequisite steps.

---

## 1. Scope and three-org flow

| Cycle | Hop | Purpose | Status |
|---|---|---|---|
| Cycle 1 | UAT → fulltemp | Full teardown + clean rebuild dress rehearsal | ✅ Complete (2026-05-18) |
| Cycle 2 | fulltemp → MergeBuild | Pre-cutover dress rehearsal against MergeBuild's prod-baseline skeleton | 🟡 ~99% complete |
| Cutover | MergeBuild → Production | Production go-live | 🔴 Scheduled 2026-06-08 |

**Scale.** ~228k records across ~50 RCA sObjects. Three objects dominate: `PricebookEntry` (158,798), `AttributeBasedAdjRule` (25,171), `Product2` (8,846) — 84% of total data volume.

**Org versions:**

| Org | API | RC `InheritedFromVersion` |
|---|---|---|
| FortraUAT | 67.0 | 67.11 |
| fulltemp | 66.0 | 66.24 |
| MergeBuild | 66.0 | 66.24 |
| FortraProduction | TBD | TBD — verify pre-cutover |

Production's RC platform version is unknown and is a pre-cutover verification item.

---

## 2. Phase model

| Phase | Layer | Objects | Status |
|---|---|---|---|
| Phase 1 | PCM Foundation | UnitOfMeasureClass, UnitOfMeasure, ProductClassification, AttributeDefinition, AttributeCategory, ProductSellingModel, TaxPolicy, TaxTreatment, RecordType | ✅ Complete |
| Phase 2 | PCM + Pricing | Pricebook2, Product2, PricebookEntry, ProductSellingModelOption, ProductAttributeDefinition, ProductConfigurationProperty | ✅ Complete |
| Phase 3a | Configurator reference data | ContextDefinition chain, ExpressionSet chain, RuleLibrary chain, PricingRecipe, ProductConfigurationFlow | ✅ Complete |
| Phase 3b | Per-product rules | AttributeBasedAdjRule, ProductFulfillmentDecompRule, ProductConfigurationRule, BundleBasedAdjustment | ⚠️ ABA + PFDR done; PCR open |

`ProductConfigurationRule` is the only remaining data-layer gap between MergeBuild and UAT.

---

## 3. Current state by track (MergeBuild as of 2026-05-22)

| Track | MB Count | UAT Reference | Status |
|---|---:|---:|---|
| AttributeBasedAdjRule | 25,171 | 25,171 | ✅ At parity |
| ProductFulfillmentDecompRule | 3,326 | 3,326 | ✅ At parity |
| ProductConfigurationFlow | 1 | 1 | ✅ At parity |
| **ProductConfigurationRule** | **0** | **302** | 🔴 **Open critical** |
| PricingActionParameters | 2 | 2 | ✅ At parity |
| PricingRecipe | 1 | 1 | ✅ At parity |
| PricingRecipeTableMapping | 12 | 12 | ✅ At parity |
| PricingProcedureOutputMap | 26 | 26 | ✅ At parity |
| Product2 | 8,853 | 8,807 | ✅ At parity (+46 MB-specific) |
| ProductClassification | 121 | 121 | ✅ At parity |
| ProductClassificationAttr | 330 | 379 | ⚠️ 49 documented residue |
| ProductCategoryProduct | 2,200 | 2,200 | ✅ At parity |
| ProductSellingModel | 9 | 9 | ✅ At parity |
| ProductSellingModelOption | 8,799 | 8,794 | ✅ At parity (+5 pre-existing) |
| ProductComponentGroup | 421 | 421 | ✅ At parity |
| ProductRelatedComponent | 1,413 | 1,417 | ⚠️ 4 documented residue |
| pse__Practice__c | 25 | 29 | ⚠️ 25 reachable Practices migrated |
| ContextAttributeMapping | 2,177 | 2,229 | ⚠️ 52 platform-version drift |
| DecisionTable | 22 | 22 | ✅ At parity |
| DecisionTableParameter | 182 | 179 | ✅ At parity (+3 v3 platform) |
| ExpressionSet / Definition / Version | 4 / 4 / 7 | 5 / 5 / 10 | ✅ Adequate |
| RuleLibrary chain | 2 / 2 / 2 / 2 | 2 / 2 / 3 / 3 | ✅ Adequate |
| ContextDefinition / Version | 2 / 2 (v3 active) | 2 / 2 (v21/v24) | ✅ MergeBuild v3 matches Prod baseline |
| ContextNode / Attribute / Mapping / NodeMapping / Tag | 53 / 908 / 17 / 140 / 1,034 | 54 / 918 / 17 / 142 / 915 | ✅ Adequate (downstream of CDV version) |

**Total documented residue:** ~53 records across PCA hierarchy validation + PRC bundle mismatches. Accepted as platform-validation residue.

---

## 4. Cycle 1 (UAT → fulltemp) — summary

Completed 2026-05-18. fulltemp teardown ran in two passes (high-volume `PricebookEntry` via Batch Apex, balance of catalog objects synchronously), followed by Phase 1+2 clean rebuild from UAT. End state: fulltemp populated with UAT data through Phase 2; Stage 3 reference layer left in place (registered, not re-imported, because Context / ExpressionSet / RuleLibrary entities are not DML-deletable and re-importing produces duplicates).

Full execution record is in `~/Desktop/SC-3137_Teardown_History`.

---

## 5. Cycle 2 (fulltemp → MergeBuild) — summary

Executed 2026-05-19 → 2026-05-22 in five sub-phases:

1. **Stage 1 + Stage 2** (2026-05-19/20) — Phase 1 PCM foundation and Phase 2 PCM + Pricing deployed via Gearset Compare and Deploy. Clean.
2. **Stage 3 reference data** (2026-05-20) — Configurator + Pricing Procedure stack via Gearset "Preserve references" mode. 25,171 AttributeBasedAdjRule + 3,326 ProductFulfillmentDecompRule + 1 ProductConfigurationFlow landed. PFDR Product2 FKs were nulled on deploy (Gearset cross-reference matched on Id, fulltemp Ids ≠ MB Ids) and were backfilled via SF CLI bulk upsert from the parsed `Name` field.
3. **Practice migration** (2026-05-21) — 25 `pse__Practice__c` records migrated in 4 dependency waves (root → mid-tier → intermediate → leaves) to satisfy MergeBuild's "Parent Practice Required" validation rule. 100% success per wave.
4. **Product2 gap closure** (2026-05-21) — 312-record gap closed. A preflight collision check caught a 91% stale-inventory rate from a concurrent Gearset job and filtered the actual load to 312 truly-missing rows.
5. **Buckets B / C / D + residual product-graph loads** (2026-05-21/22) — Context Attribute Mapping deltas (134 Fortra-custom rows), PricingRecipeTableMapping + PricingProcedureOutputMap loads, residual ProductClassificationAttr / ProductCategoryProduct / ProductSellingModelOption / ProductComponentGroup / ProductRelatedComponent loads, and 2 PricingActionParameters created via Setup UI.

Total Cycle 2 throughput: ~35,200 rows landed across 14 RCA objects.

---

## 6. ProductConfigurationRule — the open item

`ProductConfigurationRule` (PCR) is the principal SC-3137 payload. 302 rules in UAT, 0 in MergeBuild.

Tested migration paths and result:

| Path | Result |
|---|---|
| sf CLI metadata retrieve/deploy | Type not in CLI registry |
| Gearset Compare and Deploy (Metadata) | PCR not exposed |
| Gearset Sandbox Seeding (Data) | Only `ProductConfigurationRuleShare` exposed, not PCR |
| Salesforce SOAP Metadata API describeMetadata | No `ProductConfig*` types returned |
| Tooling API | "sObject type not supported" |
| REST `POST /sobjects/ProductConfigurationRule/` | `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY` |
| Bulk Data API | Same constraint |
| Salesforce Inspector | "Unknown field" on every column |
| Anonymous Apex DML | `Field is not writeable: ProductConfigurationRule.Name` at compile |

The only working path is the **Product Catalog Management → Product Configuration Rules** tab in the UI, which exposes a "New" button driving a multi-step wizard (Rule Details → Rule Criteria → Save). No bulk import. Each rule requires single-record manual entry.

**Three options for resolution:**

1. **Salesforce Support escalation.** Open a case for the official RCA migration runbook. Response time 1–2 business days.
2. **Manual UI entry.** 302 rules × ~3 min/rule ≈ 15 hours. Split-able across team. Worklist CSV staged at `Data/sc3137/pcr_manual_entry_worklist.csv` (lean) and `pcr_manual_entry_list.csv` (with raw JSON criteria) — both files parsed into a human-readable `CriteriaHumanReadable` column.
3. **Scope deferral.** Decision by Marc / leadership on whether SC-3137 ships without PCR if no path emerges before cutover.

If PCR is not resolved before 2026-06-08, SC-3137 closes "feature-complete except enforcement of co-requisite / dependency rules." Customers can configure quotes with invalid product combinations (e.g., add-on without base license) until the rules are entered.

---

## 7. Known residue and platform constraints

- **128 ProductClassificationAttr rows** rejected by the platform's internal classification hierarchy validation (affects 47 PCs / 10 ADs). Platform-managed semantic validation; no data-manipulation fix. Runtime pricing engine resolves through internal hierarchy regardless of direct PCA row.
- **4 ProductRelatedComponent rows** rejected on bundle-component-group mismatch (parent PCG `ParentProductId` doesn't match the PRC's `ParentProductId`).
- **Platform-version drift between MergeBuild (66.24) and UAT (67.11).** Manifests as ~52 ContextAttribute / ContextAttributeMapping row differences that are version evolution, not migration gaps. MB v3 schema has rows UAT doesn't, and vice versa.
- **PSA managed package not in production.** `pse__Practice__c` doesn't exist as schema in prod (confirmed via `sf sobject describe -s pse__Practice__c -o FortraProduction`). `Product2.Practice__c` will null on prod load. Acceptable per current Fortra design.
- **Tax / ProductFulfillmentDecompRule features not yet enabled in production.** Confirmed via prod schema check. Marc's cutover step 1 enables these before SC-3137 can run.

---

## 8. Remaining work

| Item | Owner | Estimate |
|---|---|---|
| Resolve PCR migration path | Liam + Marc + possibly Salesforce Support | 1–15 hours depending on path |
| Production data purge (per `Ben_Production_RCA_Purge_Plan.md`) | Liam | 30–50 min |
| Production data load (Phases 1 → 2 → 3a → 3b) | Liam | 2–3 hours |
| End-to-end functional smoke test (build quote, price, configure bundle) | Liam | 30–60 min |
| Production RC platform version verification | Wren + Liam | 5 min — pre-cutover gate |
| PCM Product source-of-truth lock (resolve concurrent edits) | Marc | 30 min stakeholder call |
| Production credentials issued | Wren | Pre-cutover gate |

**Total Liam-side cutover-day execution estimate (excluding PCR resolution): 4–6 hours wall time.**

---

## 9. Cutover prerequisites — Marc's 7-step sequence

SC-3137 is **step 5b** in Marc's production cutover sequence. Steps 1–5a are hard handoff gates.

| # | Description | Owner |
|---|---|---|
| 1 | Enable Revenue Cloud Advanced, Tax, ProductFulfillmentDecompRule | Marc |
| 2 | Bind SalesTransactionContextExt, Rebuild Product Index, assign Fortra permsets, confirm Fortra_Pricing_PreHook | Marc |
| 3 | SF Project Build metadata (Lightning Record Pages, non-RCA fields, Actions, Flows) | Sara |
| 4 | Pricing Procedure Stack — 8 phases (ExpressionSets, versions, Context bindings, PricingActionParameters) | TBD |
| 5a | Custom Metadata records (`COLA_Uplift_Rules`, `MyCAP_Rules`, `Services_Regional_Pricing`) | TBD |
| **5b** | **RCA Configuration Data Deploy — SC-3137** | **Liam** |
| 6 | Decision Table activation (per table, after rows are loaded) | Marc |
| 7 | Rebuild Product Index in Setup | Marc |

---

## 10. Tools and artifacts

| File / location | Purpose |
|---|---|
| [`docs/SC-3137_RCA_Migration_Roadmap_v3.2.md`](../../../docs/SC-3137_RCA_Migration_Roadmap_v3.2.md) | Authoritative project roadmap (internal v3.8) |
| [`Ben_Production_RCA_Purge_Plan.md`](Ben_Production_RCA_Purge_Plan.md) | Production purge runbook (companion doc) |
| `scripts/apex/SC-3137_RCA_Setup_Verification.apex` | RCA diagnostic — run against any org for current-state baseline |
| `scripts/apex/SC-3137_RCA_Data_Size_Estimate.apex` | RCA data size estimator |
| `scripts/apex/SC-3137_Tax_Object_Remediation.apex` | Tax fixture + `Product2.TaxPolicyId` backfill |
| `scripts/apex/SC-3137_UoM_Fixture.apex` | UnitOfMeasure pair 4-pass load |
| `scripts/apex/SC-3137_StdPricebook_ExtId_Fixture.apex` | Standard Pricebook GearsetExternalId__c alignment |
| `force-app/main/default/classes/RcaTeardownBatch.cls` | Generic RCA object teardown Batch class |
| `force-app/main/default/classes/PbeTeardownBatch.cls` | PricebookEntry teardown (superseded by `RcaTeardownBatch`) |
| `Data/sc3137/product2_load/run_practice_waves.py` | Practice topological-wave migration reference |
| `Data/sc3137/pcr_manual_entry_worklist.csv` | 302-row PCR manual-entry worklist (lean) |
| `Data/sc3137/pcr_manual_entry_list.csv` | Full PCR reference with raw JSON criteria |
| `Data/sc3137/{bucket_b,bucket_c,pca,pcp,psmo,pcg,prc}_*.txt`, `*_insert.log`, `*_failed_results.csv` | Per-object load artifacts |
| `scripts/apex/output/rca_diag_FortraProduction.clean.txt` | 2026-05-20 production baseline diagnostic |
| `~/Desktop/SC-3137_Teardown_History` | Cycle 1 teardown execution record |

---

## 11. Timeline and risk

**Cutover** — 2026-06-08 (T-17 days as of 2026-05-22).

**Top risks:**

1. **PCR resolution timing.** If the Salesforce Support path doesn't yield an answer before cutover and no programmatic path emerges, the ~15-hour manual entry must be scheduled. Earliest action: open Salesforce case immediately.
2. **Production RC platform version unknown.** If prod's RC platform differs materially from MergeBuild's 66.24, the dress rehearsal does not fully predict cutover behavior — budget extra time for unknown validation differences.
3. **Marc's prerequisite steps 1–5a.** Hard handoff gates. Any delay in those steps delays SC-3137 step 5b. Treat as critical-path external dependency.
4. **Concurrent edits between now and cutover.** Marc may continue editing PCM data in MergeBuild and production. Source-of-truth lockdown needed 48–72 hours pre-cutover; preflight collision checks mandatory at cutover.
5. **Production purge selector validation.** Marc's purge spreadsheet flags 10 `ProcessDefinition` records that are confirmed not RCA (Knowledge workflows, Marketing approvals, PSA timecards). Default for those is KEEP unless Marc explicitly confirms. See companion purge plan §6.2.

---

*End of document*
