# RCA End-to-End Test Report — FortraUAT (2026-06-13)

**Scope:** exhaustive E2E test of the Revenue Cloud (RCA) implementation — every RCA sObject + standard/custom actions. **Create/edit only, nothing deleted.** All test records tagged `ZZ_E2E_RCA_20260613`. No live pricing-config edits; no Order activation; no Workday/MuleSoft/Tax external side-effects. Method: 8 lifecycle clusters in parallel (9 agents, 427 tool calls), `describe → count → safe tagged create/edit → verify` per sObject + action exercise.

## Verdict
**GREEN on data-model integrity · AMBER on prod-deployment readiness.** The pricing *engine* was deliberately left as a UI/authorized-run gap (HARD RULE 4). No data corruption, no broken graphs, no orphaned references found anywhere.

## Coverage
- **113 distinct RCA sObjects** across 8 clusters · **100% READ pass (113/113)**.
- **79 createable** objects exercised full **CREATE + EDIT + READ** (tagged).
- **13 platform-managed read-only** — verified read + negative-control insert-rejection.
- **21 createable-per-describe but BLOCKED** by data/config/uniqueness/UI dependency (not defects).
- Referential-integrity sweep on live data **CLEAN**: 0 orphans across 13,072 ABA / 57,076 conditions (1,661 distinct products); real configurable bundle (DCS Essentials, 15 active children + 202 active config rules) fully coherent; Quote→Order convert mirroring exact; RLM asset-renewal chain bidirectionally coherent; BillingSchedule pipeline healthy (2,347 ReadyForInvoicing, actively generating).

## Defects (ranked)
**HIGH**
- **D1 — OrderItem Apex-DML split-brain.** OrderItem rejects ALL Apex DML: `insert` → "use insertAsync()/insertImmediate()"; **and `Database.insertImmediate` won't even compile** ("Argument must be of virtual sObject type"). The **REST API succeeds** (created `802WC00000OktRtYAJ`). The documented `insertImmediate` escape hatch is non-functional for OrderItem → any Apex automation building OrderItems breaks; must route through managed connect/PlaceOrder or REST. (Order *header* Apex insert works.)
- **D2 — SC-3384 currency-blind data gap (confirmed).** 100% of AttributeBasedAdjustment (13,072/13,072) and Attribute_Tier_Pricing_Storage__c (1,117/1,117) are USD-only; all 13,072 ABA are `AdjustmentType=Override`. Non-USD configured pricing has no data to resolve → USD fallback. Data-coverage defect, no CRUD remedy.

**MEDIUM**
- **D3 — Live custom pricing classes below the 75% prod gate:** QuoteToOrderFieldMapper 65.2%, COLAUpliftHandler 38.8%, PartnerPricingService 41.7%. Would block a prod package deploy.
- **D4 — Two DEAD signaling prehooks left Active at 0%:** `COLAUpliftPrehook` (0/575) and `PartnerPricingPrehook` (0/604) — superseded V1s still implementing `SignalingApexProcessor`; re-wiring risk → deactivate.
- **D5 — Known Failed DecisionTable persists:** `Asset_Action_Source_Entries_Decision_Table_V2` RefreshStatus=Failed ("Hash Key Group >200 rows").

**LOW / DX**
- D6 Product2.Type is FLS-read-only on update (can't promote an existing product to Bundle via API). D7 ProductRelatedMaterial create → opaque "Complete this field" (UI-injected FK). D8 OrderItemAttribute: `ExternalId` is an ID-ref (not free text), `AttributeValue` uneditable on picklist attrs (must use AttributePicklistValueId). D9 Sales_Territory__c.Unique_Value__c silently overwritten by a before-save flow (as-designed composite key). D10 junction/adjustment objects reject Name + lack Description (tag via parent FK). D11 GearsetExternalId__c/Legacy_Rule_Id__c capped at 18 chars. D12 PriceBookEntryDerivedPrice strict, poorly-surfaced create validation (SC-3372 relevant).

**HEALTH SIGNAL**
- D13 — Transient decomposition row-lock: 1 STFR (000068046) Failed at 2026-06-12 16:05 UTC with `UNABLE_TO_LOCK_ROW` (DRO_DATA_ACCESS_ERROR) — ~1.2% of 7-day STFRs; concurrency, not systemic. Monitor.

## Actions — standard + custom
- **Standard CRUD** (product/catalog/category/bundle/overrides/qualifications/selling-model-option/ramp/fulfillment; attribute+picklist+assign; ABA rule+conditions+adjustment+BBA+tier; PBE+derived+schedule/tier; quote+QLI+QLIA+groups+adjustments; order+OrderItem(REST)+OIA; contract/asset/contract-item-price; tax/usage policy; custom __c): **PASS**.
- **Verification (read-only)**: active pricing procedure = **V14** (sole active; drift vs memory V12/V13); ContextDefinitions active (SalesTransactionContextExt v34, ProductDiscovery v23, _v2 v23); DecisionTables 15 Completed / 1 Failed / 7 null; convert mirroring + renewal chain + billing pipeline verified on existing data. **PASS**.
- **Custom Apex/Flow wired-live**: AttributeVolumePricingPrehook 86%, HardwareAttributePricingPrehook 89%, PartnerNetPricePosthook 77%, RegionalServicesPricingPrehook 79%, OrderRepriceInvocable 90%, RenewalMaintenancePricingService 92%, MaintenanceOrderDecompositionService 79%, QLDescriptionGeneratorPrehook 80% — **PASS**; QuoteToOrderFieldMapper 65% (LOW); COLAUpliftPrehook & PartnerPricingPrehook **DEAD (0%)**. Live flows verified active (Stamp_Maintenance_Pricing_Inputs, Stamp_Source_List_Price, Fortra_OrderItem_Set_Dates, ..._Workday_Contract_Line_Type, etc.).
- **BLOCKED (by rule)**: live headless reprice (managed engine context — HARD RULE 4; proven: direct DML leaves NetUnitPrice null/CalculationStatus=NotStarted → the **Reprice action is the architectural gate**); ExpressionSet/DecisionTable/Context edits (RULE 4); order activation / convert-firing / Workday/Tax callouts (RULE 5).

## Key corrections to prior knowledge
- **"RLM blocks ALL Quote DML" is REFUTED** for INSERT/UPDATE on **Draft** Quotes (both succeeded via Apex/API). The real gate is the **pricing-action engine context**, not Quote DML. The OrderItem Apex-DML block (D1) is the genuine, narrower restriction.
- Active pricing procedure = **V14** (always pull live; memory said V12/V13).

## Recommendation
Fit-for-UAT and data-coherent. Before any prod promotion: (a) fix the OrderItem Apex path or document a REST-only contract; (b) close the SC-3384 non-USD data gap; (c) raise the three sub-75% classes + deactivate the two dead prehooks; (d) run an authorized UI Reprice + FINEST pass to close the pricing-action verification gap; (e) load Tax/Usage config+data for true E2E coverage.

*Full per-cluster detail + every created record Id: workflow output `Data/sc-maint/e2e/` (run wf_acaa3bfe-b7a). Test records remain in the org (tagged `ZZ_E2E_RCA_20260613`); none deleted per directive.*
