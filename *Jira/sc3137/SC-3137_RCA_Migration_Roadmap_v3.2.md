# SC-3137 — RCA Configuration Data Migration — Roadmap

**Jira:** SC-3137 | **Program:** Fortra Org Merge — Unified Sales & Quoting
**Path:** Fortra UAT → fulltemp → MergeBuild → Production
**Cutover:** 2026-06-08 | **Owner:** Liam Jeong (5S Infusion)
**Last updated:** 2026-05-21 | **Roadmap v3.8**
**Status:** Cycle 1 COMPLETE; **Cycle 2 DATA LAYER COMPLETE except ProductConfigurationRule (the principal payload)** — Practice (25), Product2 (312), Bucket B (134 CAMs), Bucket C (1 PRTM + 26 PPOM), Stage 3 (25,171 ABA + 3,326 PFDR + 1 PCF + PFDR FK backfill), all 5 residual product-graph loads (PCA, PCP, PSMO, PCG, PRC), and Bucket D (2 PricingActionParameters). **Total platform-validation residue:** ~53 records (49 PCA hierarchy + 4 PRC bundle-mismatch). **NEW CRITICAL OPEN ITEM (CF-8):** ProductConfigurationRule (302 rows in UAT, 0 in MB) has **no programmatic migration path** discovered via standard Salesforce tooling (sf CLI, Gearset Metadata, Metadata API describeMetadata, Tooling API, REST/Bulk data API, SOAP Enterprise API via Salesforce Inspector all confirmed blocked). Apex DML pilot remains untested. **Remaining critical-path:** Resolve PCR migration approach (see RC-17 + CF-8); end-to-end RCA functional smoke test.
**Supersedes:** v3.7 (2026-05-21 evening); v3.6 (2026-05-21 evening); v3.5 (2026-05-21 evening); v3.4 (2026-05-21 evening); v3.3 (2026-05-21 afternoon); v3.2 (2026-05-21 morning); v3.1 (draft, not committed); v3.0 (2026-05-19); v2 (2026-05-15)

---

## 0. Changelog

Milestone log — newest first. A milestone is a blocker/CF reaching terminal state, a phase moving, a decision landing, or a structural finding that changes the plan.

- **2026-05-21** — **Roadmap v3.8.** **ProductConfigurationRule migration block discovered.** Post-everything diagnostic showed PCR is the only object still at 0 in MergeBuild (UAT has 302). PCR is the SC-3137 principal payload per §1. Investigated migration paths exhaustively: (1) `sf project retrieve start -m ProductConfigurationRule` → "Missing metadata type definition in registry" (CLI 2.64.8); (2) Gearset Compare and Deploy Metadata → no `ProductConfigurationRule` entry in any category, search for `ConfigurationRule` / `Configurator` returns 0 matches; (3) Salesforce SOAP Metadata API `describeMetadata` v62.0 → no `ProductConfig*` types in response (62KB response, 0 hits); (4) Tooling API → `INVALID_TYPE: sObject type 'ProductConfigurationRule' is not supported`; (5) Setup Quick Find for `Configuration` → returns only generic config screens (Tax, Invoice, Clause), no PCR-management screen; (6) Salesforce Inspector → all 8 PCR fields show `Error: Unknown field` in Insert field mapping (uses SOAP Enterprise API, same constraint as REST/Bulk). PCR has `createable=false` on every field per object describe — confirmed metadata-only at platform level. **The only programmatic path remaining untested: Anonymous Apex DML** (Apex sometimes bypasses REST-layer `createable` enforcement, as seen inversely with PRTM/PPOM in RC-13). Pilot deferred at user direction; will be tested next session. **RC-17** (PCR has no public migration tooling) and **CF-8** (PCR is the SC-3137 principal payload but has no automated migration path) added. **Cutover impact:** if PCR cannot be migrated programmatically before 2026-06-08, options are (a) Salesforce Support ticket for the official RCA migration runbook, (b) manual recreation through Product Configurator UI (~300 rules × N minutes each), or (c) escalate timeline.
- **2026-05-21** — **Roadmap v3.7.** **Bucket D closed.** Liam created the 2 PricingActionParameters records via Setup → Feature Settings → Salesforce Pricing → Pricing Action Parameters (NOT the procedure-builder canvas as v3.x roadmaps incorrectly stated — the canvas exposes Elements, Resources, Properties, and Element Details, none of which surface Action Parameters in this RC version). Records created: `Order_1779421459828` (Order/SalesTransactionContextExt/OrderEntitiesMapping/Rev_Mgmt_Default_Pricing_Procedure) and `Quote_1779421625525` (Quote/SalesTransactionContextExt/QuoteEntitiesMapping/Rev_Mgmt_Default_Pricing_Procedure). Verified via SOQL: `SELECT COUNT() FROM PricingActionParameters` returns 2. The other 2 v3.x Bucket D items (Rev_Mgmt ↔ SalesTransactionContextExt junction binding and ProductDiscoveryContextExt v3 activation) were already in place from prior Gearset Preserve-references deploys. **RC-16** (PricingActionParameters lives in Setup, not procedure-builder canvas) added. **Cycle 2 data layer is now complete.** Only RCA functional smoke test remains before cutover dress rehearsal sign-off.
- **2026-05-21** — **Roadmap v3.6.** Residual product-graph gap loads — all 5 objects landed via sequential SF CLI per-object pattern (same approach as Buckets B/C). Diagnostic + content-level diff + composite-key FK remap (Product2 via ProductCode, ProductClassification via Code, AttributeDefinition via DeveloperName-with-fulltemp-`_1`-stripped, ProductSellingModel via Name, ProductComponentGroup via (Name, ParentProduct.ProductCode), ProductRelationshipType via Name (Ids stable cross-org per RC-13 platform-seeded pattern)) per object. Results: **PCA 47/96** (49 platform-validation residue per CF-7), **PCP 561/561**, **PSMO 4,020/4,020**, **PCG 419/419**, **PRC 1,413/1,417** (4 platform-validation residue: "Select a group related to the same bundle as this component" — likely fulltemp/MB drift on the 2 pre-existing MB PCGs whose ParentProduct doesn't match the inserted PRCs). MB final state: PCA 330/379, PCP 2,200/2,200, PSMO 8,799/8,794 (MB +5 pre-existing extras), PCG 421/421, PRC 1,413/1,417. **Cycle 2 data layer essentially complete.** Only Bucket D manual UI residue + functional smoke test remain.
- **2026-05-21** — **Roadmap v3.5.** **Major correction + Stage 3 actually completed.** Diagnostic parity check uncovered that v3.4 (and earlier) claims of "Stage 3 RCA migrated to MergeBuild via Gearset Preserve references" were FALSE — Gearset Phase 3 deployments only went UAT→fulltemp, never UAT/fulltemp→MergeBuild. MergeBuild's AttributeBasedAdjRule was 0, ProductFulfillmentDecompRule 0, ProductConfigurationFlow 0 at start of session (vs claimed 25,171 / 3,326 / 1). Confirmed by inspecting Gearset Data History — all "RCA Migration Phase 3" entries showed target = `liam.jeong.c@fortra.com.fulltemp`, not MergeBuild. **Liam ran Gearset rerun of Phase 3 with target = MergeBuild** in the afternoon; Gearset reported `25171 ABA records included`, `3326 PFDR records included`, `1 PCF record included`. Post-deploy verification confirmed all rows landed BUT exposed a critical issue: **PFDR's `SourceProductId` and `DestinationProductId` were null on all 3,326 rows** because Gearset's "Preserve references" for Product2 defaulted to Id-match, and fulltemp Product2 Ids ≠ MB Product2 Ids; Gearset's "Exclude missing references" step silently stripped the FKs. **FK backfill executed via SF CLI**: parsed PFDR `Name` field (format `{src_code} to {dst_code}`), resolved both ProductCodes against MB Product2 (6,595/6,595 codes matched), produced 3,326 update payload, ran `sf data upsert bulk` with `-i Id` (LF line endings, NOT CRLF — `sf data upsert bulk` accepts LF only, unlike `sf data import bulk` which requires CRLF). Result: 3,326/3,326 PFDR rows now have both Product2 FKs populated. **RC-15** (Gearset Preserve references strips FKs silently when match key is Id and source/target Ids differ) added. **Status correction:** Cycle 2 is now genuinely ~90% complete (Stage 3 fully landed; only Bucket D manual UI + functional smoke test remain).
- **2026-05-21** — **Roadmap v3.4.** Bucket B closed. Content-level diff revealed v3.2's "~3,400-row Apex pre-loader" premise was based on the FULL row count of Context-family children in UAT, not the actual gap. Real gap: 207 UAT-only CAMs, of which 67 were `__std` platform-version-drift artifacts (skip), 6 were `TestCategoryProduct__c` test fixtures (skip), and **134 were genuine Fortra-custom field projections** missing in MB v3 baseline (load). All 134 inserted via REST `sf data create record` into MergeBuild (1 pilot + 133 batch, 100% success). MB ContextAttributeMapping: 2043 → 2177. Residual delta to UAT: 52 rows (= 73 UAT-only platform-drift/test still missing − 21 MB-only `ProductDiscoveryMapping_Clone` extensions). Symmetric. **CAM accepts REST DML** (createable=true is honored, unlike PRTM where Apex DML was rejected — RC-13). MergeBuild v3 CDV has 27 ContextAttributes under `AssetActionSrcPriceAdjustment__std` that UAT v21/v24 doesn't have, confirming MB v3 ≠ UAT v21/v24 with non-overlapping platform additions/removals — proving the 3-way diagnostic doc's correct call that "row-count differences are downstream of CDV-version state and will not be reconciled by data load." **RC-14** (Content-level diff before data-load scope) added. ProductDiscoveryContextExt fully at parity (9 nodes / 66 attrs ≡); SalesTransactionContextExt has the residual 52-row asymmetry.
- **2026-05-21** — **Roadmap v3.3.** Bucket C closed. PRTM gap (1 row: `NGPDefaultRecipe / PriceAdjustmentMatrix / CalculatedVolumeDiscountPriceAdjusmentTier / IsInternal=false`; MB Id `12Ict000001NnPFEA0`) loaded into MergeBuild via REST. PPOM gap (26 rows) loaded from fulltemp via REST with composite-key FK remap: PRTM via `(Recipe, PCT, DT.DevName, IsInternal)`, DTP via `(DT.DevName, FieldName, Sequence, Usage)`, DT via `DeveloperName`. All 14 `(OutputType, PricingComponentType)` categories match fulltemp distribution exactly. **Pre-existing v3.2 premise that `CalculationMatrixColumn` was the PPOM root cause was wrong** — CMC is empty in all 3 orgs (UAT, fulltemp, MergeBuild) and not a dependency for this org's RC implementation. Real PPOM root cause was prior Gearset deploys not performing PRTM + DTP composite-key remap. **RC-13** (PRTM/PPOM Apex DML rejected; use REST + composite-key remap) added. fulltemp scored 113/163 DTP Id-identical with MB vs UAT 89/179 — fulltemp is the cleaner source for PPOM-class objects.
- **2026-05-21** — **Roadmap v3.2.** Major Cycle 2 progress. Stage 3 RCA migration to MergeBuild completed via Gearset "Preserve references" mode (revision-level "Select related objects and deployment methods" config — not the per-object Configure screen). AttributeBasedAdjRule 25,171/25,171, ProductFulfillmentDecompRule 3,326/3,326, PricingRecipe 1/1, ProductConfigurationFlow 1/1 all clean. **RC-9** (Preserve references pattern) added. PCA load to MergeBuild executed: 251/379 succeeded, 128 failed with platform-enforced classification hierarchy validation — accepted as residue (no DML remediation possible; RC platform version drift fulltemp 66.24 vs UAT 67.11 makes MergeBuild's hierarchy check stricter). **RC-10** (platform version mismatch) added as cutover pre-flight check. **pse__Practice__c topological wave migration** — recursive FK gap surfaced during Product2 load (312 UAT Product2 rows referenced 19 Practices missing from MergeBuild). Closure analysis: 19 direct + 6 chained parents = 25. Custom validation rule "Parent Practice Required. There are too many top-level Practices in the system" forced 4-wave topological insert (1 + 2 + 5 + 17 = 25/25 clean). **RC-11** added. **Product2 gap closure** — original 3,639-row gap inventory was 91% stale (3,327 already in MergeBuild via concurrent Gearset job, confirmed via reverse-Id `GearsetExternalId__c` match on 200/200 sample). Filtered to true 312-row gap, 312/312 succeeded clean. **RC-12** (stale gap inventory protocol) added. **CF-2 (Sara permset audit) demoted** from pre-cutover blocker to post-cutover hardening — cutover will execute as named Liam user, not Sara; Sara permset audit moves to follow-up scope.
- **2026-05-20** — **Stage 3 reference data deployed via Gearset "Preserve references."** The key discovery: Gearset has a hidden config screen ("Select related objects and deployment methods" at the revision/deployment level, not the per-object Configure dialog) that exposes per-object match-key control. Two modes used: (1) **Upsert + ApiName/DeveloperName** for natural-key-matchable objects (PricingRecipe, ProductFulfillmentDecompRule, AttributeBasedAdjRule with `GearsetExternalId__c`, ProductConfigurationFlow). (2) **"Preserve references"** for platform-managed entities that already exist in target with org-specific Ids (ContextDefinition, ContextDefinitionVersion, ExpressionSet, ExpressionSetDefinition, ExpressionSetVersion, RuleLibrary, RuleLibraryDefinition, RuleLibraryDefinitionVersion, RuleLibraryVersion). Children's FKs resolve via target lookup rather than redeploying the parent. Pricing procedure ESD↔SalesTransactionContextExt junction binding for `Rev_Mgmt_Default_Pricing_Procedure` remains as manual residue per org hop — junction missing in fulltemp, target's procedure-builder canvas requires manual binding.
- **2026-05-19** — **Roadmap v3.0** (see prior changelog for full detail). Cycle 1 Stage 2 PAD chain resolved; Stage 1 verified; tax fixture verified.
- **Earlier history:** v3.0 changelog retained; see prior roadmap for Cycle 1 detail.

---

## 1. Summary

End-to-end migration of Revenue Cloud Advanced (RCA) configuration data + metadata from `FortraUAT` to Production ahead of the 2026-06-08 cutover. The ticket goal is to migrate **RCA functionality fully** — the configuration and pricing engine must work end-to-end (build a quote, price it, configure a bundle, run the rules).

Deployment is phased (PCM foundation → PCM+Pricing → Configurator+Rules) because RCA's cross-layer dependencies and layer-specific failure families make a single-shot load unviable. The phased plan executes once per environment hop ("cycle").

**Three-org flow**

| Cycle | Hop | Purpose | Status |
|---|---|---|---|
| Cycle 1 | UAT → fulltemp | Mock validation — teardown + clean rebuild | ✅ Complete |
| Cycle 2 | fulltemp → MergeBuild | Pre-cutover dress rehearsal | 🟡 In progress (~80% complete) |
| Cutover | MergeBuild → Production | Production go-live | 🔴 Scheduled 2026-06-08 |

**Scale:** ~228,000 records across ~50 objects. Three objects dominate: PricebookEntry (158,798), AttributeBasedAdjRule (25,171), Product2 (8,846) — 84% of all data volume.

**Org versions (cutover pre-flight check — RC-10):**

| Org | API | RC Platform InheritedFromVersion |
|---|---|---|
| FortraUAT | 67.0 | 67.11 |
| fulltemp / MergeBuild | 66.0 | 66.24 |
| Production | TBD | TBD — verify pre-cutover |

---

## 2. Current State Snapshot (2026-05-21)

Cycle 2 progress against MergeBuild target.

| Track | Count | Status |
|---|---|---|
| AttributeBasedAdjRule | 25,171 / 25,171 | ✅ Migrated to MergeBuild 2026-05-21 PM via Gearset rerun (fulltemp→MB); v3.4 and earlier claims of completion were FALSE (Gearset Phase 3 had only gone UAT→fulltemp) |
| ProductFulfillmentDecompRule | 3,326 / 3,326 + FK backfill | ✅ Migrated 2026-05-21 PM; PFDR Source/DestinationProductId backfilled via SF CLI after Gearset's "Preserve references" silently stripped them (see RC-15) |
| Pricing procedures / ESD / ESV | various | ✅ Preserve references mode |
| ContextDefinition / CDV | 2 / 2 | ✅ Preserve references |
| RuleLibrary chain | various | ✅ Preserve references |
| PricingRecipe | 1 / 1 | ✅ Upsert/DeveloperName |
| ProductConfigurationFlow | 1 / 1 | ✅ Migrated |
| Product2 (UAT parity) | 8,853 / 8,807 expected | ✅ Gap closed; +46 MB-specific products from Marc |
| ProductClassificationAttr | 251 / 379 + 128 residue | ⚠️ Platform-validation residue documented |
| pse__Practice__c | 25 / 25 | ✅ Topological wave migration complete |
| Bucket B — Context family (Fortra-custom ContextAttributeMappings) | 134 / 134 | ✅ Complete 2026-05-21 (content-level diff scoped from "~3,400" to 134 actual Fortra-custom rows; rest is platform-version drift, intentionally skipped) |
| Bucket C — Decision-table layer (PRTM/PPOM) | 12 / 12 + 26 / 26 | ✅ Complete 2026-05-21 (fulltemp source, REST + composite-key remap; CMC-gap premise was false) |
| Bucket D — Platform residue (PAP, junction binding, PCA validation) | various | ⚠️ Documented; manual UI per org hop |
| Rev_Mgmt_Default_Pricing_Procedure ESD↔SalesTransactionContextExt junction | absent in fulltemp | ⚠️ Manual procedure-builder UI per org hop |
| PricingActionParameters (2 rows) | absent | ⚠️ `isCreateable=false`, requires manual procedure-builder canvas creation per org hop |

**MergeBuild org state (post-Stage 3 + Practice + Product2 closure):**

- Product2: 8,853 (UAT: 8,807; +46 MergeBuild-specific from Marc)
- ProductClassification: 121 (UAT parity)
- pse__Practice__c: 25 (was 0 prior to today's migration)
- AttributeBasedAdjRule: 25,171 (fulltemp parity; landed 2026-05-21 PM)
- ProductFulfillmentDecompRule: 3,326 (fulltemp parity; FKs backfilled via SF CLI)
- ProductConfigurationFlow: 1 (fulltemp parity; landed 2026-05-21 PM)
- ProductClassificationAttr: 330 (was 283; +47; 49 platform-validation residue per CF-7)
- ProductCategoryProduct: 2,200 (fulltemp parity; was 1,639; +561)
- ProductSellingModelOption: 8,799 (was 4,779; +4,020; MB +5 pre-existing extras vs fulltemp's 8,794)
- ProductComponentGroup: 421 (fulltemp parity; was 2; +419)
- ProductRelatedComponent: 1,413 (was 0; +1,413; 4 platform-validation residue: same-bundle PCG validation)
- PricingRecipeTableMapping: 12 (UAT parity; was 11 prior to Bucket C)
- PricingProcedureOutputMap: 26 (UAT/fulltemp parity; was 0 prior to Bucket C)
- ContextAttributeMapping: 2,177 (was 2,043 prior to Bucket B; residual 52-row delta vs UAT 2,229 is platform-drift + test-fixture residue, intentional)
- AttributeDefinition / ProductClassificationAttr: requires final reconcile pass

---

## 3. Stages by Phase

### Phase 1 — PCM Foundation (Stage 1)
**Status:** ✅ Complete. Loaded and verified in fulltemp 2026-05-18; reproduced in MergeBuild.

Objects: UnitOfMeasureClass (RC-6 fixture), UnitOfMeasure (RC-6 fixture), ProductClassification, AttributeDefinition, AttributeCategory, ProductSellingModel, TaxPolicy (RC-1 verified), TaxTreatment (RC-1 verified), RecordType.

### Phase 2 — PCM + Pricing (Stage 2)
**Status:** ✅ Complete (Cycle 1 and Cycle 2). PAD blocker chain RESOLVED (see v3.0 changelog). PricebookEntry chunking (2 chunks × ~80k = 158,798) clean; PAD 9,589/9,589; Product2 8,846 with BasedOnId matching UAT (4,086 null = UAT parity).

Objects: Pricebook2, Product2 (with `BasedOnId` per RC-8), PricebookEntry (chunked per RC-7), ProductSellingModelOption, ProductAttributeDefinition, ProductConfigurationProperty.

### Phase 3 — Configurator + Rules (Stage 3)
**Status:** ✅ Reference data + ABA complete via Gearset (2026-05-20). Per-product rules (PCR per RC-2) on track.

Sub-phases:
- **Stage 3a — Reference data.** ContextDefinition (chain), ExpressionSet (chain), RuleLibrary (chain), PricingRecipe, ProductConfigurationFlow — all via Gearset Preserve references / Upsert.
- **Stage 3b — Per-product rules.** AttributeBasedAdjRule (25,171), ProductFulfillmentDecompRule (3,326), ProductConfigurationRule, BundleBasedAdjustment.

### Phase 4 — Activation
**Status:** ⏸️ Pending. See §10 Activation Runbook.

Manual UI steps per org hop: Sync Pricing Data, ExpressionSet version activation, decision-table activation, Product Index rebuild, Rev_Mgmt junction binding, PAP creation, CDV activation for ProductDiscoveryContextExt (fulltemp only).

---

## 4. Remaining Critical Path (in execution order)

Items needed to close Cycle 2 and prepare for cutover.

### 4.1. Bucket B — Context family (Fortra-custom ContextAttributeMappings)
**Status:** ✅ Complete 2026-05-21. Final scope was MUCH smaller than the v3.2 estimate of "~3,400 rows": 134 rows total, ~30 min wall time including diagnostic.

**Corrected diagnosis:** The "~3,400 rows" figure in v3.2 was the FULL ContextNode/Attribute/Mapping child count in UAT, not the actual gap. Content-level diff scoped per active ContextDefinition (UAT v21 ↔ MB v3 for ProductDiscoveryContextExt; UAT v24 ↔ MB v3 for SalesTransactionContextExt) showed:

- **ProductDiscoveryContextExt:** full parity (9 nodes / 66 attrs each, common = 9 / 66, UAT-only = 0).
- **SalesTransactionContextExt:** 1 UAT-only ContextNode (`AssetActionSourceAssetPromotion__std` — platform-version-drift, skip), 37 UAT-only ContextAttributes (all `__std` paths or under the missing node — skip), **207 UAT-only ContextAttributeMappings** broken down as:
  - 134 Fortra-custom (non-`__std`) → **load**
  - 67 `__std` platform-version drift → skip
  - 6 `TestCategoryProduct__c` test fixtures (CNM parent absent in MB) → skip
- **27 MB-only ContextAttributes** under `AssetActionSrcPriceAdjustment__std` and 21 MB-only CAMs under `ProductDiscoveryMapping_Clone` — these are platform additions in v3 that UAT v21/v24 doesn't have. Leave alone.

**Resolution executed:**
- 1 CAM pilot via REST (`sf data create record`) → MB Id `11Rct000000hVjhEAE` for `OrderEntitiesMapping > Order > AWSMarketplaceAgreementId2__c`. Confirms CAM accepts REST DML.
- 133 CAMs in REST batch loop → 133/133 succeeded.
- MB ContextAttributeMapping: 2043 → 2177.
- Residual delta to UAT: 52 rows = (73 UAT-only platform-drift/test still missing) − (21 MB-only `ProductDiscoveryMapping_Clone` extensions). Symmetric.

See RC-14 for the reusable "content-level diff before data-load scope" pattern.

### 4.2. Bucket C — Decision-table layer (PRTM/PPOM)
**Status:** ✅ Complete 2026-05-21. Final scope was much smaller than the v3.2 estimate: 1 PRTM + 26 PPOM, ~15 min wall time.

**Corrected diagnosis:** `CalculationMatrixColumn` is empty in all 3 orgs (UAT, fulltemp, MergeBuild). Not a dependency for this org's RC implementation; the v3.2 "CMC gap" premise was wrong. Real PPOM root cause was prior Gearset deploys not performing PRTM + DTP composite-key remap.

**Resolution executed:**
- 1 PRTM inserted via REST: `(NGPDefaultRecipe, PriceAdjustmentMatrix, CalculatedVolumeDiscountPriceAdjusmentTier, IsInternal=false)` → MB Id `12Ict000001NnPFEA0`.
- 26 PPOMs inserted via REST from fulltemp with composite-key FK remap (PRTM, DTP, DT). All 14 `(OutputType, PricingComponentType)` categories match fulltemp distribution exactly.
- Source choice: fulltemp DTP Id alignment with MB (113/163 identical) beat UAT (89/179 identical).

See RC-13 for the reusable PRTM/PPOM REST + composite-key-remap pattern.

### 4.3. Bucket D — Platform residue (documented, manual)
**Status:** ⚠️ Documented. Estimated 20 min per org hop.

Three documented residue items requiring manual UI work at each org-hop (fulltemp → MergeBuild → Production):

1. **PricingActionParameters (2 rows)** — `isCreateable=false`, no DML path. Manual creation in procedure-builder canvas at each org.
2. **Rev_Mgmt ESD↔SalesTransactionContextExt junction binding** — junction absent in fulltemp; manual binding via Setup UI per org.
3. **ProductDiscoveryContextExt CDV v1 activation in fulltemp** — manual activation via Setup UI.
4. **128 PCA platform-validation residue** — accepted as documented residue. No remediation possible (platform-managed semantic hierarchy validation). Affects 47 PCs / 10 ADs. Runtime pricing engine resolves attributes through platform's internal hierarchy regardless of direct PCA row.

### 4.4. Verification + diagnostic parity check
**Status:** ⏸️ Pending. Estimated 30 min.

Run the RCA setup verification Apex diagnostic on both fulltemp and MergeBuild; diff outputs. Confirms parity before cutover dress-rehearsal complete sign-off.

---

## 5. Recent Findings & RC Items

### RC-1 — Tax fixture (verify-only per org)
**Status:** ✅ Verified. Both UAT and fulltemp/MergeBuild hold canonical TaxPolicy + Active TaxTreatment. STEP A is verify-only per org. For production, verify Tax feature is enabled by Marc's cutover step 1 before SC-3137 begins.

### RC-2 — PAD/PCP reference-only parent scope
**Status:** ✅ Resolved. AttributeDefinition + ProductClassificationAttr added as reference-only parents in Stage 2 template.

### RC-3 — Stage template scope prune (Account + CODA)
**Status:** ✅ Applied. Account + c2g__CODA* objects pruned from RCA stage templates (CPQ-base-clone artifacts).

### RC-4 — fulltemp teardown procedure
**Status:** ✅ Executed 2026-05-18. See `SC-3137_Teardown_History.md`.

### RC-5 — PSM import as standard upsert
**Status:** ✅ Resolved. All 9 UAT PSM external IDs match the 9 fulltemp survivors.

### RC-6 — UoM pair Apex fixture (4-pass)
**Status:** ✅ Applied. Replaces Gearset seeding of UnitOfMeasure / UnitOfMeasureClass. See `SC-3137_UoM_Fixture.apex`.

### RC-7 — Standard Pricebook GearsetExternalId__c alignment
**Status:** ✅ Applied. Standard Pricebook `IsStandard=true` has no portable cross-org identity; aligned via fixture.

### RC-8 — Product2 BasedOnId in scope + ProductClassification reference-only
**Status:** ✅ Applied. Product2 re-run as UPSERT with `BasedOnId` populated; `BasedOnId null = 4,086` matches UAT exactly.

### RC-9 — Gearset "Preserve references" mode for platform-managed entities
**Status:** ✅ Pattern established 2026-05-20. Use case: RCA platform entities (CD, CDV, ES, ESD, ESV, RL, RLD, RLDV, RLV, ContextTag) that exist in both source and target with org-specific Ids and that should NOT be redeployed. Gearset resolves children's FK lookups against target's existing parents.

**How to apply:** In Gearset deployment, navigate to the revision-level "Select related objects and deployment methods" screen (NOT the per-object Configure dialog). Per object, choose: Upsert (with match key) for natural-key-matchable, Preserve references for platform-managed, Exclude for objects out of scope. This is the canonical pattern for RCA migrations going forward.

### RC-10 — RC platform version mismatch as cutover pre-flight check
**Status:** ⚠️ Active risk. fulltemp/MergeBuild InheritedFromVersion is 66.24; UAT is 67.11. Production version TBD.

**Symptoms:** Stricter hierarchy validation in MergeBuild's RC platform than UAT (manifests as PCA 128/379 failures with "classification hierarchy" errors that don't occur in UAT). ContextTag count differs (UAT 915 vs fulltemp 1,781) — suggests internal platform schema drift between RC versions.

**Pre-cutover action:** verify production's RC platform InheritedFromVersion. If different from MergeBuild, the dress rehearsal does not fully predict cutover behavior — budget extra time for unknown validation differences.

### RC-11 — pse__Practice__c topological-wave migration pattern
**Status:** ✅ Resolved 2026-05-21. Pattern reusable for any hierarchy + Parent-required validation rule scenario.

**Problem:** MergeBuild's `pse__Practice__c` has a custom validation rule: "Parent Practice Required. There are too many top-level Practices in the system." Bulk-inserting Practices with FKs nullified fails 24/25 — only the legitimate root survived.

**Solution:** Insert in topological waves by hierarchy depth. After each wave, rebuild the Name → MB-Id map and resolve the next wave's `pse__Parent_Practice__c` + `pse__Global_Practice__c` against just-inserted parents. `pse__Practice__c` has no `GearsetExternalId__c` field; Name is the only reliable cross-org key.

**Reference implementation:** `Data/sc3137/product2_load/run_practice_waves.py`. Pattern applies to any sObject with hierarchy + parent-required validation rule.

**Wave structure used (25 records, 4 waves):**
- Wave 1 (depth 0): Global Practice (root) — 1 record
- Wave 2 (depth 1): Cyber, Tech — 2 records
- Wave 3 (depth 2): Defensive Security, Offensive Security, Power, RPA+, Managed File Transfer — 5 records
- Wave 4 (depth 3): 17 leaf practices — 17 records

### RC-12 — Stale gap inventory protocol
**Status:** ✅ Pattern established 2026-05-21.

**Problem:** Gap inventories generated more than a few hours before insert can be 90%+ stale if any concurrent migration activity occurs. On 2026-05-21, a 3,639-row gap inventory had 3,327 rows already inserted into MergeBuild via a concurrent Gearset job. Without preflight collision check, the insert would have produced 3,327 `DUPLICATE_VALUE` errors and obscured the diagnostic signal for the truly-missing 312.

**Protocol:**
1. At preflight time, re-query target org by natural key (`ProductCode` for Product2, `DeveloperName` for metadata-pattern objects, `GearsetExternalId__c` for Gearset-tracked objects).
2. Filter payload to truly-missing rows.
3. If collision rate exceeds 5%, **halt and investigate concurrent activity** before proceeding.
4. Sample 200 collision rows and verify natural-key + `GearsetExternalId__c` match expected reverse-Id pattern; this confirms a prior Gearset job vs unrelated data divergence.

Pattern applies to all Bulk API or Apex-driven migrations where concurrent migration activity is possible (i.e., Cycle 2 and cutover).

### RC-13 — PRTM/PPOM Apex DML rejected; REST + composite-key remap
**Status:** ✅ Pattern established 2026-05-21.

**Problem:** `PricingRecipeTableMapping` and `PricingProcedureOutputMap` are RC platform-managed entities. Apex `insert` returns `DML operation Insert not allowed on PricingRecipeTableMapping` despite the describe reporting fields as `createable=true`. Also: PPOM has only **3 createable fields** (`PricingRecipeTableMappingId`, `OutputType`, `OutputFieldNameId`) — everything else (`PricingComponentType`, `OutputFieldNameString`, `LookupField`, `IsPricingRecipeActive`) is auto-derived from the parent PRTM and linked DTP. On PRTM, `IsInternal` is not writeable either (auto-set by platform).

**Solution:** Use REST API (`sf data create record` or REST POST) instead of Apex DML. Build cross-org FK maps by composite key:
- DT remap: `DeveloperName`
- DTP remap: `(DT.DeveloperName, FieldName, Sequence, Usage)` — confirmed unique in all 3 orgs
- PRTM remap: `(PricingRecipe.DeveloperName, PricingComponentType, DT.DeveloperName, IsInternal)`

**Source-org choice:** pick the source with higher cross-org Id alignment to MB. On 2026-05-21, fulltemp had 113/163 DTPs with identical Ids in MB vs UAT's 89/179 — fulltemp won. Generally: fulltemp/MergeBuild share more RC platform Ids because both are newer sandboxes from a more recent base than UAT.

**Reference implementations:** `Data/sc3137/bucket_c_*.txt` + `bucket_c_*.log` artifacts; `/tmp/build_and_load_ppom.py` (FK reachability + payload build); `/tmp/load_ppom.py` (REST insert loop).

### RC-14 — Content-level diff before data-load scope
**Status:** ✅ Pattern established 2026-05-21.

**Problem:** Both Bucket B (Context family) and Bucket C (PRTM/PPOM) were originally scoped from row-count diagnostic comparisons that turned out to be misleading. Bucket B's "~3,400 rows" was the full count, not the gap. Bucket C's "CMC gap" was a false premise (CMC empty in all 3 orgs). In both cases, count-based scoping inflated estimated effort by 10×–25×.

**Solution:** For any RCA migration where the source and target are on different ContextDefinitionVersion versions (or any platform-managed schema that evolves), perform a **content-level diff** before scoping:
1. Identify the natural-key fields for the object (often composite — DT.DeveloperName, FieldName, Sequence, etc.).
2. Pull rows from source and target, scoped to matching parent containers (e.g., active CDV per ContextDefinition).
3. Categorize each "source-only" row:
   - **Load** if it's an org-specific custom (e.g., `__c` suffix, no `InheritedFrom`, no `__std` in name/path).
   - **Skip** if it's platform-managed (`__std` suffix or `InheritedFrom` path under `*__stdctx/...`) — these are platform-version artifacts.
   - **Skip** if it's test/QA data (look for `Test*` prefixes, demo names).
4. For "target-only" rows: leave alone. They are usually platform-version-newer additions or org-specific extensions you don't want to disturb.

**Why this matters:** Platform-managed entities like `ContextNode`, `ContextAttribute`, `CalculationMatrixColumn`, and similar inherit content from RC platform versions. Two sandboxes on different RC platform versions will diverge in non-overlapping ways. A naive "load the delta from source" approach will mix incompatible version content into the target's baseline. Content diff + classification produces the right load list.

**Reference:** `/tmp/bucket_b_content_diff.py`, `/tmp/bucket_b_cam_diff.py`, `/tmp/bucket_b_cam_reachability.py`. Output saved in `Data/sc3137/bucket_b_*.txt`.

### RC-15 — Gearset Preserve references strips FKs silently when source/target Ids differ
**Status:** ✅ Pattern established 2026-05-21.

**Problem:** Gearset's "Preserve references" mode on a related object (e.g., Product2 on a ProductFulfillmentDecompRule deployment) defaults to matching by `Id`. When source and target orgs have different Ids for the same logical record (which is typical cross-sandbox — fulltemp Product2 Ids ≠ MergeBuild Product2 Ids), the cross-reference lookup fails. Gearset's subsequent "Exclude missing references" step then **silently nulls out the FK fields** on the deployed records rather than failing the deployment. Result: records land in the target with structurally null parent references — functionally hollow.

On 2026-05-21 PM, this caused all 3,326 ProductFulfillmentDecompRule records deployed fulltemp→MergeBuild to land with `SourceProductId = null` and `DestinationProductId = null`. Gearset reported "Deployment completed successfully" — only direct post-deploy queries (`SELECT COUNT() FROM PFDR WHERE SourceProductId != null`) revealed the issue.

**Two solutions:**
1. **Preventive:** In Gearset's "Select related objects and deployment methods" screen, change Preserve references match key from `Id` to a natural key per object — e.g., Product2 → `ProductCode`, ProductClassification → `Code`, DecisionTable → `DeveloperName`. This is per-object configuration; verify each Preserve-references row before clicking Deploy.
2. **Remedial (when preventive missed):** Post-deploy FK backfill via SF CLI. For PFDR, the `Name` field encodes both ProductCodes (format `{src} to {dst}`); for other objects, identify whatever natural-key field encodes the FK content. Resolve in target, build update payload, run `sf data upsert bulk -i Id` (LF line endings).

**Verification protocol:** After any Gearset deploy involving Preserve references on related objects, query each FK field's fill rate. If any FK shows null on records where it should be populated, run the remedial backfill before declaring the deploy complete.

**Reference implementation:** `/tmp/pfdr_fk_resolve_v2.py` (read-only resolver) + `/tmp/pfdr_updates.csv` + `sf data upsert bulk -o MergeBuild -s ProductFulfillmentDecompRule -f /tmp/pfdr_updates.csv -i Id -w 15`. Job `750ct00000USGyDAAX`.

**Critical cutover impact:** When the production cutover runs Phase 3 Gearset, this same trap exists. Either fix the per-object match keys in the Gearset template BEFORE the cutover deploy, or budget time for the same PFDR FK backfill (and equivalent for any other affected object) immediately after the production push.

---

## 6. Open Concern-Findings (CF Items)

| ID | Description | Status |
|---|---|---|
| CF-1 | Phase 1 deployed 5 objects as Status=Draft — activation runbook captures (§10) | Closed — runbook covers |
| CF-2 | **Sara's DevOps integration user permset audit.** Was tracked as hard pre-cutover gate. **Demoted 2026-05-21** to post-cutover hardening — cutover will execute as named Liam user; Sara permset audit moves to follow-up scope. Filed as separate ticket. | ⚠️ Demoted to follow-up |
| CF-3 | fulltemp contamination (15 test PCs, dual LegalEntity hierarchy DNU entries). Teardown cleared earlier-imported data; LE hierarchy + non-RCA pollution remain. Confirm LegalEntity cleanup ownership outside SC-3137. | Partially addressed |
| CF-4 | Phase 1 Draft activation mechanism — captured in §10 activation runbook | Closed |
| CF-5 | PAD/PCP failure object-list scope defect | Closed (superseded by RC-2) |
| CF-6 | **MergeBuild's 9,318 PCM Product records have concurrent edits between Liam (UAT-origin) and Marc (MergeBuild-origin).** Source-of-truth needs clarification before cutover sync. | ⚠️ Open — needs Marc decision |
| CF-7 | **128 PCA platform-validation residue** (47 PCs / 10 ADs). Documented, no remediation possible. Runtime pricing engine resolves through platform's internal hierarchy. Verify runtime behavior in MergeBuild before cutover. | ⚠️ Documented residue |
| CF-8 | **ProductConfigurationRule (302 rows, the SC-3137 principal payload) has no programmatic migration path.** Confirmed blocked via sf CLI, Gearset Metadata, SOAP Metadata API, Tooling API, REST/Bulk Data API, and Salesforce Inspector. Anonymous Apex DML remains the only untested programmatic option. Fallback paths: Salesforce Support escalation or manual UI recreation. **Cutover blocker until resolved.** See RC-17. | 🔴 Open — critical |

---

## 7. Open Decisions — Marc DeBrey

| Decision | Why it's needed |
|---|---|
| **PCM Product source-of-truth between UAT-origin (Liam) and MergeBuild-origin (Marc) edits.** CF-6. ~9,318 PCM Product records have concurrent edits in both orgs. Define merge strategy before cutover sync. | Critical — blocks final reconcile |
| **Tax feature enablement in production** (Marc's cutover step 1). If Tax not enabled by cutover, drop RC-1 fixture from prod scope. | Affects SC-3137 prod scope |
| **`ProductFulfillmentDecompRule` object enablement in production** (Marc's cutover step 1) before SC-3137 can load 3,326 rows. | Critical — blocks Stage 3 in prod |
| Slide vs Gearset orchestration (`stageGraph.ts` — spec or deployer?) | Determines deploy ordering ownership |
| Sign-off on RC-9, RC-10, RC-11, RC-12 (new structural patterns) | Architecture confirmation |

---

## 8. Open Decisions / Handoffs — Other Stakeholders

| Stakeholder | Decision / Action |
|---|---|
| Jomil | Confirm 06-08 cutover Gearset push runs **manually as Liam**, not as Sara's DevOps integration user. Determines whether CF-2 stays demoted or returns as a pre-cutover gate. |
| Sara | Coordinate post-cutover hardening: provision DevOps integration user in prod with the 3 permsets (`force.ProductCatalogManagementAdministrator` + `force.UnifiedCatalogAdmin` + `Revenue_Cloud_Admin`) — for ongoing automation only, not 06-08 |
| TBD (step 4 owner) | Execute pricing-procedure-stack metadata deploy (ExpressionSets, ExpressionSetVersions, PricingActionParameters, Context bindings) BEFORE SC-3137 runs in prod |
| TBD (step 5a owner) | Execute custom-metadata-type deploy (`COLA_Uplift_Rules`, `MyCAP_Rules`, `Services_Regional_Pricing`) BEFORE SC-3137 runs in prod |
| Wren | Provide production credentials for Liam to execute SC-3137 step 5b |

---

## 9. SC-3137 in Marc's Production Cutover Sequence

| # | Description | Tool | Owner |
|---|---|---|---|
| 1 | Manual enablement of Revenue Cloud Advanced in Salesforce UI | UI | Marc |
| 2 | Manual setup: bind `SalesTransactionContextExt`, Rebuild Product Index, assign Fortra permsets, confirm `Fortra_Pricing_PreHook` | UI | Marc |
| 3 | SF Project Build metadata deployment (Lightning Record Pages, non-RCA fields, Actions, Flows) | Gearset Metadata | Sara |
| 4 | Pricing Procedure Stack — 8 phases (ExpressionSets, versions, Context bindings, PricingActionParameters) | Gearset Metadata | TBD |
| 5a | Custom Metadata records — `COLA_Uplift_Rules`, `MyCAP_Rules`, `Services_Regional_Pricing` | Gearset Metadata | TBD |
| **5b** | **RCA Configuration Data Deploy — THIS TICKET** | **Gearset RCA Add-on (Data) + Apex pre-loaders** | **Liam (SC-3137)** |
| 6 | Decision Table rows — activate each table after rows are loaded | UI | Marc |
| 7 | Rebuild Product Index in Setup | UI | Marc |

**Critical-path dependency:** SC-3137 step 5b cannot start until steps 1-5a are complete. Treat as hard handoff gates.

---

## 10. Activation Runbook (per org hop)

Manual UI steps required at each org hop (fulltemp → MergeBuild → Production). Ordered.

**STEP A — Tax fixture verification.** Verify TaxPolicy + Active TaxTreatment present on native LegalEntity. RC-1.

**STEP B — pse__Practice__c topological wave load.** Run waves in dependency order if Practices need to land. RC-11.

**STEP C — Product2.TaxPolicyId backfill.** Run after Product2 Stage 2 seed; populates TaxPolicy FK on all migrated Product2 rows.

**STEP D — Stage 2 catalog object verification.** Confirm `PricebookEntry COUNT = 158,798`, `Product2 = 8,846 (+46 in MergeBuild)`, `ProductAttributeDefinition = 9,589 (with 0 INVALID_INPUT)`.

**STEP E — Stage 3 reference data verification.** Confirm ContextDefinition, ExpressionSet, RuleLibrary chains present.

**STEP F — Activation steps.**
1. Sync Pricing Data (Setup → Pricing → Sync Pricing Data)
2. ExpressionSet version activation (Pricing Procedure builder UI — Active checkbox on canonical version)
3. Decision Table activation per table (Marc's cutover step 6)
4. Product Index rebuild (Setup — Marc's cutover step 7)
5. Rev_Mgmt ESD↔SalesTransactionContextExt junction binding (Setup → Pricing → Pricing Procedures → Rev_Mgmt → bind to SalesTransactionContextExt)
6. PricingActionParameters creation in procedure-builder canvas (2 records, manual)
7. ProductDiscoveryContextExt CDV v1 activation (Setup → Pricing → Context Definitions)

**STEP G — Validation queries.** Run RCA setup verification Apex diagnostic; compare against source-org baseline.

---

## 11. Pre-Cutover Gates (06-08 minus 18 days)

| Gate | Owner | Status |
|---|---|---|
| ~~Bucket B Apex pre-loader complete in fulltemp~~ | Liam | n/a — scope was 134 CAMs not "3,400 rows"; UAT→MB direct, no fulltemp staging needed |
| ~~Bucket B Apex pre-loader complete in MergeBuild~~ | Liam | ✅ Done 2026-05-21 (134 CAMs via REST; see RC-14) |
| ~~Bucket C PRTM/PPOM diagnosis + fix in MergeBuild~~ | Liam | ✅ Done 2026-05-21 (1 PRTM + 26 PPOM via REST; see RC-13) |
| Bucket D PAP + junction binding manual in MergeBuild | Liam | ⏸️ Pending |
| RCA setup verification diagnostic — fulltemp vs MergeBuild parity | Liam | ⏸️ Pending |
| ~~Sara DevOps integration user permset audit~~ | ~~Sara/Liam~~ | ⚠️ Demoted to post-cutover |
| RC platform version check — production InheritedFromVersion vs MergeBuild's 66.24 | Liam (verify with Wren) | ⏸️ Pending — RC-10 |
| Tax + ProductFulfillmentDecompRule features enabled in production | Marc | ⏸️ Pending (Marc step 1) |
| PCM Product source-of-truth decision (Liam-edit vs Marc-edit) | Marc | ⏸️ CF-6 |
| Production credentials issued to Liam | Wren | ⏸️ Pending |

---

## 12. Cutover Day Plan (2026-06-08)

**Pre-flight (T-2 hours):**
1. Verify Marc's steps 1, 2, 3 complete.
2. Verify step 4 (pricing procedure stack metadata) deployed.
3. Verify step 5a (custom metadata records) deployed.
4. Run RC platform version check — confirm prod RC version matches MergeBuild dress-rehearsal baseline.
5. Run gap-inventory query against prod (RC-12 protocol) — confirm prod target state matches expected starting point.

**Step 5b execution (estimated 4-6 hours):**
1. Stage 1 — Phase 1 PCM foundation via Gearset.
2. Tax fixture STEP A.
3. pse__Practice__c topological wave load (if not already present from prior steps).
4. Stage 2 — Phase 2 PCM + Pricing (Product2, PricebookEntry chunked, PAD, PCP).
5. Tax fixture STEP C — Product2.TaxPolicyId backfill.
6. Stage 3a — Reference data via Gearset Preserve references.
7. Stage 3b — Per-product rules (ABA, PFDR, PCR).
8. Bucket B — Context family Apex pre-loader.
9. Bucket C — Decision-table layer (PRTM/PPOM) via Gearset.
10. Bucket D — Manual UI residue (PAP, junction binding, CDV activation).
11. Activation runbook STEP F.
12. Verification — full RCA diagnostic Apex; compare to MergeBuild baseline.
13. Handoff to Marc for steps 6 and 7.

**Stop-on-error policy:** Halt on any failure exceeding the documented residue threshold for that step. Escalate to Jomil; do not unilaterally accept new residue categories on cutover day.

---

## 13. Post-Cutover Hardening (follow-up scope)

Items deferred from cutover-blocking to post-cutover.

| Item | Owner | Notes |
|---|---|---|
| Sara DevOps integration user permset audit + assignment in prod | Sara / Liam | CF-2. Needed for ongoing automation (Gearset scheduled jobs, Sweep recurring syncs) after Liam's consultant engagement ends |
| PCM Product source-of-truth reconciliation between UAT-edits and MergeBuild-edits | Marc / Liam | CF-6. May require ad-hoc reconcile pass after cutover |
| RC platform upgrade to align fulltemp/MergeBuild → 67.x to match UAT | Marc / Fortra IT | RC-10. Removes the version-drift residue surface |
| PCA platform-validation residue review (128 rows / 47 PCs / 10 ADs) | Liam / Marc | CF-7. Verify runtime pricing engine resolves correctly despite missing PCA junction rows |
| LegalEntity hierarchy cleanup (DNU-prefixed entries from CPQ-base-clone) | TBD | CF-3 partial — non-RCA scope |

---

## 14. Tools & Artifacts

| File | Purpose |
|---|---|
| `SC-3137_RCA_Migration_Roadmap.md` (this file, v3.2) | Authoritative project roadmap |
| `SC-3137_Tax_Object_Remediation.apex` | Tax dedup + fixture create/verify + Product2 TaxPolicyId backfill (RC-1) |
| `SC-3137_UoM_Fixture.apex` | RC-6 — UoM pair 4-pass load |
| `SC-3137_StdPricebook_ExtId_Fixture.apex` | RC-7 — Standard Pricebook GearsetExternalId__c alignment |
| `JunctionRealigner.cls` (v2) | Cross-org external-ID realignment for in-both-orgs junctions |
| `SC-3137_Teardown_History.md` | Executed teardown record + reusable mergebuild/production replay runbook |
| `RcaTeardownBatch.cls` | Generic object-name teardown Batch class |
| `SC-3137_Production_Teardown_Plan.md` | Production-specific teardown plan (v0.2 reframed for non-empty prod) |
| `Data/sc3137/product2_load/run_practice_waves.py` | RC-11 — pse__Practice__c topological wave migration reference implementation |
| `Data/sc3137/product2_load/` | Product2 + Practice migration artifacts (CSVs, payloads, logs) |
| `Data/sc3137/pca_load/` | PCA migration artifacts (load CSV, failed-records CSV, post-flight verification) |
| `Data/sc3137/bucket_c_*.txt` + `*.log` | Bucket C artifacts: 3-org diagnostic, PRTM/DTP cross-org compare, PPOM payload build, REST insert log, post-flight verification |
| `Data/sc3137/bucket_b_*.txt` + `*.log` | Bucket B artifacts: 3-org Context-family diagnostic, content-level diff (UAT v21/v24 ↔ MB v3), CAM reachability check, 134-row REST insert log, post-flight verification |
| `Data/sc3137/stage3_pre_push_baseline.json` + `pfdr_fk_resolve*.txt` + `pfdr_update_bulk.log` | Stage 3 artifacts: pre-push baseline, fulltemp→MB Gearset rerun verification, PFDR FK backfill (resolve + bulk upsert) |
| `Data/sc3137/{pca,pcp,psmo,pcg,prc}_*.txt` + `*_insert.log` + `*_failed_results.csv` | Residual gap load artifacts: per-object diagnostic, payload build, insert log, failure detail for the 49 PCA + 4 PRC platform-validation residue rows |
| TBD — Bucket B Apex pre-loader scripts | 5 scripts for ContextNode → ContextAttribute → ContextMapping → ContextNodeMapping → ContextAttributeMapping |
| `RCA_Architect_Reference___Interactive.tsx` | Architect reference UI (background reading) |
| `Salesforce_Revenue_Cloud_Advanced__Architect_Reference_and_Configuration_Rules_Deep_Dive.md` | Architect reference doc (background reading) |

---

## 15. Org Aliases (SF CLI)

| Alias | Username | API | Purpose |
|---|---|---|---|
| `FortraUAT` | `liam.jeong.c@fortra.com.uat` | 67.0 | Source — Revenue Cloud UAT |
| `MergeBuild` | `liam.jeong.c@fortra.com.mergebuild` | 66.0 | Cycle 2 target — Pre-cutover dress rehearsal |
| `fortradp2` | DP2 sandbox | — | OmniStudio/DocGen work (separate from SC-3137) |

Note: fulltemp alias has historically been ambiguous in CLI — actual UAT is now `FortraUAT`. The MergeBuild alias became the canonical Cycle 2 target after fulltemp work completed.

---

## 16. Timeline & Risk

**Cutover 2026-06-08** — 18 days out as of 2026-05-21.

**Remaining critical-path work estimate:**

| Item | Estimate | Owner |
|---|---|---|
| ~~Bucket B Apex pre-loader (fulltemp + MergeBuild)~~ | ✅ Done 2026-05-21 (~30 min wall time including diagnostic) | Liam |
| ~~Bucket C PRTM/PPOM diagnosis + fix~~ | ✅ Done 2026-05-21 (~15 min wall time) | Liam |
| Bucket D Manual UI (PAP + junction + CDV) in MergeBuild | ~20 min | Liam |
| RCA setup verification diagnostic parity check | ~30 min | Liam |
| Cutover dress-rehearsal full re-run validation (optional) | ~6 hours | Liam |
| **TOTAL remaining Liam-side** | **~7 hours** | |

**Risk — schedule.** Bucket B is the largest remaining unknown (3,400 rows across 5 sObjects with sequential dependencies and manual CDV mapping). If Bucket B reveals a deeper CDV version-mismatch problem than currently scoped, budget could escalate. Mitigation: do Bucket B against fulltemp first as a learning exercise, then replay against MergeBuild.

**Risk — concurrent activity.** RC-12 protocol mandatory for any insert at cutover. Marc may continue editing PCM data in MergeBuild between now and cutover; CF-6 needs source-of-truth lockdown 48-72 hours before cutover.

**Risk — RC platform version drift (RC-10).** Production's RC version unknown. If different from MergeBuild's 66.24, dress rehearsal may not fully predict cutover behavior. Verify pre-cutover with Wren.

**Risk — Marc's prerequisite steps (cutover steps 1-5a).** Hard handoff gates. Any delay in steps 1-5a delays SC-3137 step 5b. Treat as critical-path external dependency.

---

## 17. Action Items — In Order

**Immediate (this week, 2026-05-21 to 2026-05-23):**
1. ⏸️ Verify with Jomil: 06-08 cutover Gearset push runs manually as Liam (not Sara). Confirms CF-2 demotion stands.
2. ⏸️ Bucket D manual residue cleanup in MergeBuild — PAP creation, Rev_Mgmt junction binding, CDV activation. ~20 min.
3. ✅ Bucket C PRTM/PPOM diagnostic + fix complete 2026-05-21. CMC was a false premise (empty in all 3 orgs); real fix was REST insert with composite-key FK remap. See RC-13.

**Pre-cutover dress rehearsal completion (by 2026-05-30):**
4. ✅ Bucket B complete 2026-05-21 — 134 ContextAttributeMappings into MergeBuild via REST (no fulltemp staging needed; content-level diff scoped it to direct UAT→MB load). See RC-14.
5. ✅ Bucket C PRTM/PPOM fix complete (merged with diagnostic on 2026-05-21).
6. ⏸️ RCA setup verification diagnostic parity check (fulltemp vs MergeBuild).
7. ⏸️ End-to-end RCA functionality validation in MergeBuild — build a quote, price it, configure a bundle, run rules.
8. ⏸️ PCM Product source-of-truth lock with Marc (CF-6).

**Cutover prep (T-7 days, 2026-06-01):**
9. ⏸️ Verify production RC platform InheritedFromVersion with Wren (RC-10).
10. ⏸️ Verify Marc's cutover steps 1, 2 enablement plan.
11. ⏸️ Confirm step-4 and step-5a owners and execution timing.
12. ⏸️ Production credentials issued to Liam (Wren).
13. ⏸️ Cutover-day runbook walk-through with Jomil.

**Cutover day (2026-06-08):**
14. ⏸️ Execute §12 Cutover Day Plan.

**Post-cutover:**
15. ⏸️ Sara permset audit + assignment in prod (CF-2 follow-up).
16. ⏸️ PCA platform-validation residue review (CF-7).
17. ⏸️ LegalEntity hierarchy cleanup ownership (CF-3 partial).

---

## 18. Quick Reference — Recent Key Findings

Snippets useful in standup / Slack / ticket comments without rereading the full doc.

**Gearset "Preserve references" pattern (RC-9).** Revision-level config screen, NOT per-object Configure dialog. Use for platform-managed entities that exist in both orgs with org-specific Ids (CD, CDV, ES, ESD, ESV, RL chain, ContextTag). Children's FK lookups resolve against target.

**pse__Practice__c topological waves (RC-11).** MergeBuild validation rule "Parent Practice Required" forces wave-by-depth insertion. 4 waves: depth 0 root → depth 1 (2 records) → depth 2 (5 records) → depth 3 (17 leaves). Name is only cross-org key (no GearsetExternalId__c field).

**Stale gap inventory protocol (RC-12).** Re-query target at preflight time. >5% collision rate → halt and investigate. 91% collision rate caught on 2026-05-21 (3,327/3,639 already loaded by concurrent Gearset job).

**PRTM/PPOM REST + composite-key remap (RC-13).** Apex DML blocked on `PricingRecipeTableMapping` / `PricingProcedureOutputMap` despite describe reporting createable. Use REST. PPOM has only 3 createable fields (others auto-derived). Cross-org Id stability is partial; remap by composite key. fulltemp typically shares more RC platform Ids with MB than UAT does.

**Content-level diff before data-load scope (RC-14).** Row-count diffs can overstate gaps by 10×–25×. Always do content-level diff with classification (load vs platform-drift vs test) before scoping any RCA migration involving platform-managed entities (Context*, CalculationMatrix*, etc.). Bucket B went from "~3,400 rows / 4 hours" to "134 rows / 30 min" after content diff. Bucket C went from "CMC gap blocker" to "false premise" after content diff.

**PricingActionParameters lives in Setup, not procedure-builder canvas (RC-16).** PricingActionParameters records are created via Setup → Feature Settings → Salesforce Pricing → Pricing Action Parameters (a list view with a "New" button). The v3.x roadmaps incorrectly stated "create via procedure-builder canvas" — the canvas (Pricing Procedure > Version > Edit) exposes Elements, Resources, Properties, and Element Details, none of which surface Action Parameters in this RC version. Each PAP binds (Object, ContextDefinition, ContextMapping, PricingProcedure). Required for Rev_Mgmt pricing procedure to activate on Order and Quote contexts at runtime.

**ProductConfigurationRule has no public migration tooling (RC-17).** PCR (the SC-3137 principal payload, 302 rows in UAT) has `createable=false` on every field at the platform describe layer. Standard Salesforce tooling cannot insert PCR records: sf CLI metadata registry omits the type, Gearset's Metadata Compare doesn't expose it, Salesforce SOAP Metadata API describeMetadata returns no `ProductConfig*` types, Tooling API explicitly rejects with "sObject type not supported", REST/Bulk data API insert is blocked by the field-level constraint, and Salesforce Inspector shows "Unknown field" for every column. Only path remaining untested is **Anonymous Apex DML** (sometimes bypasses REST-layer `createable` per the RC-13 inverse pattern with PRTM/PPOM). If Apex DML also fails, the documented fallback is (a) Salesforce Support escalation for the official RCA migration runbook, or (b) Product Configurator UI manual recreation. See CF-8.

**Gearset Preserve references silently strips FKs (RC-15).** When Gearset deploys an object whose FK references a "Preserve references" related object, the cross-reference uses Id-match by default. Cross-sandbox Ids differ → lookup fails → Gearset's "Exclude missing references" step nulls out the FK silently. Deployment reports "success." Always (a) configure per-object Preserve references match keys to natural keys (ProductCode, Code, DeveloperName) BEFORE deploy, AND (b) verify FK fill rate post-deploy. On 2026-05-21, all 3,326 PFDR rows landed with null SourceProductId/DestinationProductId; backfilled via SF CLI from parsed `Name` field.

**RC platform version drift (RC-10).** fulltemp/MergeBuild 66.24 vs UAT 67.11. Causes stricter hierarchy validation in target. Verify prod InheritedFromVersion before cutover.

**Sara permset audit demoted (CF-2).** Cutover runs as Liam, not Sara. Audit moves to post-cutover hardening for ongoing automation.

**PCA platform residue (CF-7).** 128/379 PCAs fail with platform's internal classification hierarchy validation. Accepted as residue; runtime pricing engine resolves through internal hierarchy regardless of direct PCA row.

**Product2 parity confirmed (2026-05-21).** MergeBuild 8,853 = UAT 8,807 + 46 Marc-specific MB products. Gap closed.

---

*End of roadmap v3.2*
