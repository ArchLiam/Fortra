# FIELD-PACKAGING — Resolution

**Status:** ✅ Field gap closed in `force-app` + deploy manifest built (the scenario's core). Whole-build manifest (M-3/B-2) = cutover follow-up. No org deploy — repo/source change only.
**Org:** FortraUAT · Date: 2026-06-14 · Owner: Liam.

## Defect
SC-3346 load-bearing custom fields exist live in UAT but were missing from version-controlled `force-app` and staged in **no** `package.xml` → a standard prod pipeline would deploy the V14 procedure / Apex / flows that reference these fields against a prod where they don't exist → **deploy failure**.

## What was already done (parallel session, before this)
QLI's 20 SC-3346 COLA/maintenance fields and the Order gate fields (`Quote_Type__c`, `QuoteTypeText__c`) were already added to `force-app`. Current gap was narrower than the original report's "5 QLI + 7 OI + 2 Order".

## What this resolution did
**1. Added the 5 remaining SC-3346 maintenance fields to `force-app`** (extracted from a live UAT retrieve, source-format):
- `OrderItem.Fortra_Product_Type__c` (Picklist; **confirmed SC-3346** — referenced 3× by `MaintenanceOrderDecompositionService`), `OrderItem.Maintenance_Discount_Percent__c` (Percent).
- `Order.Maintenance_Date__c` (Date), `Order.New_Maintenance__c` (Currency, "New Maintenance amount on this order"), `Order.Renewal_Maintenance_Quote__c` (Lookup).

**2. Added the GlobalValueSet dependency** `Fortra_Product_Type` (values: Software / Perpetual / New Maintenance / Renewal Maintenance / Subscription / SaaS / Services …) — referenced by `Fortra_Product_Type__c`; the field deploy fails without it.

**3. Built the SC-3346 field deploy manifest** `package_sc3346_fields.xml` — **33 CustomField members** (QLI 20, OI 8, Order 5) + the GlobalValueSet — resolving the "0 package.xml staging" gap.

## Deliberately EXCLUDED (not SC-3346)
The 5 `Prior_*` **hardware** fields the original report counted in its "7 OrderItem-side fields" — `Prior_Feature_Code__c`, `Prior_Group_Number__c`, `Prior_Model__c`, `Prior_Number_of_Processors__c`, `Prior_Serial_Number__c` (Lookups/Picklist/Number for serial, model, processors). These are **hardware carry-forward**, not maintenance pricing — referenced by neither `MaintenanceOrderDecompositionService` nor the Q2O mapper; they belong to the hardware/Power-split feature (the same domain as `Original_Order_Item__c` / `PowerOrderSplittingService`, SC-3210/3368). The report over-counted them via name pattern-match. Package them under their own ticket, not SC-3346.

## Follow-ups (cutover)
1. **Whole-build manifest (M-3 / B-2):** this resolves the *field* portion; the V14 **procedure**, the **Apex hook stack** (COLAUpliftPrehook/Handler, PartnerNetPricePosthook, MaintenanceOrderDecompositionService, QuoteToOrderFieldMapper, Renewal* handlers), and the **flows** (Stamp_Maintenance_Pricing_Inputs, Stamp_Source_List_Price, Fortra_Create_Renewal_Quote, Fortra_RCA_Renewal_Enhancement) + the **MTD AttributeDefinition** + the **CMDTs** (Maintenance_Rate__mdt, COLA_Uplift_Rules__mdt) must be added to a full SC-3346 deploy manifest.
2. **⚠️ Stale procedure in force-app:** `force-app/.../Rev_Mgmt_Default_Pricing_Procedure` is a stale **_V1** (per SC-3372). **Re-baseline from live V14** before any procedure deploy, or prod reverts V14→V1.
3. **Validate at cutover:** dry-run the manifest against a fresh org. (Note: a pre-existing tracked orphan `force-app/.../classes/rca_diagnostic.cls-meta.xml` — a `.cls-meta.xml` with no `.cls` — blocks source-format retrieve/deploy; remove it under a cleanup ticket to unblock the cutover pipeline.)
4. **Commit** the new `force-app` files (5 field-meta.xml + 1 globalValueSet-meta.xml) — currently untracked in the working tree.

## Artifacts (`Data/sc-maint/sc3346_fix/field_packaging/`)
`package_sc3346_fields.xml` (manifest), `live_{QuoteLineItem,OrderItem,Order}.txt` (live SC-3346 field inventory), `stage/` (the MDAPI retrieve the field-metas were extracted from).
