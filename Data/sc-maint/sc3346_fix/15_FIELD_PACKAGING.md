# SC-3346 — FIELD-PACKAGING fix (M-3 / M-6 / B-2 field gate)

**Date:** 2026-06-14 · **Org of record:** FortraUAT · **Scope:** custom-field packaging only (Apex/procedure packaging deferred — see §4)

## 1. What was done (this session)

Retrieved the **13 load-bearing SC-3346 custom fields** from FortraUAT into version control
(`force-app/main/default/objects/*/fields/`) and created a deploy manifest
[`manifest/sc3346_fields.xml`](../../../manifest/sc3346_fields.xml).

| Object | Field | Type | Notes |
|---|---|---|---|
| QuoteLineItem | Source_List_Price__c | Currency(16,2) | derived-pricing input |
| QuoteLineItem | Prior_Partner_Discount__c | Currency | renewal COLA operand |
| QuoteLineItem | Prior_Discretionary_Discount__c | Currency | renewal COLA operand |
| QuoteLineItem | Final_Year_COLA_Calculated_Price__c | Currency | multi-year (inert at commit, still referenced) |
| QuoteLineItem | COLA_Outyear_Uplift_Percent__c | Number | out-year approval flag input |
| OrderItem | Source_List_Price__c | Currency(16,2) | Q2O carry-forward (M-4) |
| OrderItem | Base_Price__c | Number(16,2) | decomposition base |
| OrderItem | COLACalculatedPrice__c | Currency(14,2) | COLA carry-forward |
| OrderItem | COLA_Uplift_Percent__c | Number(16,2) | COLA carry-forward |
| OrderItem | Prior_Partner_Discount__c | Currency(16,2) | COLA carry-forward |
| OrderItem | Prior_Discretionary_Discount__c | Currency(16,2) | COLA carry-forward |
| Order | Quote_Type__c | Picklist (New/Upsell/Renewal/Amendment/Cancellation/Net-New) | pricing-context gate |
| Order | QuoteTypeText__c | Formula(Text) = TEXT(Quote_Type__c) | pricing-context gate |

Standard objects (OrderItem, Order) are staged **fields-only** (no object-meta.xml) — source format
deploys decomposed fields without it, and fabricating an object-meta risks clobbering org-level
sharing/action-override settings on deploy.

## 2. How the set was derived (authoritative, not the report's counts)

`(fields existing in UAT but NOT in FortraProd) ∩ (fields referenced by the SC-3346 build)`,
then minus fields already in `force-app`. Live diff: QLI 88 prod / 109 UAT, OI 68 / 97, Order 96 / 125.

**Correction vs the E2E report:** the report said "ALL 7 OrderItem-side fields." The rigorous
load-bearing OI set is **6**, not 7. The likely 7th — `Original_Order_Item__c` — is attributed by
DECOMP-SPLIT to SC-3210/SC-3368 (quantity-split FK), **not** SC-3346. `Maintenance_Discount_Percent__c`
is not referenced by the build.

## 3. Cross-ticket prod prerequisites (FLAGGED — not bundled here)

The SC-3346 Apex (esp. `MaintenanceOrderDecompositionService`) **references** UAT-only fields owned by
other tickets. These must already exist in prod (via their own cutovers) or the SC-3346 Apex will not
compile in prod. Do **not** silently fold them into the SC-3346 deploy:

- **Regional pricing (SC-3374):** `OrderItem.AllowRegionalPricing__c`, `OrderItem.RegionalNetUnitPrice__c`
- **Attribute pricing (SC-3384/3390):** `OrderItem.Attribute_Multiplier_Pct__c`, `OrderItem.Attribute_Price_Mode__c`, `OrderItem.Has_Attribute_Adjustment__c`
- **Order rollups / classification:** `Order.Deal_Type__c`, `Order.GSW__c`, `Order.Total_Services__c`, `Order.Total_Software__c`, `Order.Total_Subscription__c`
- **Other:** `OrderItem.Partition_Record__c`

## 4. Remaining packaging gap — DEFERRED until the build stabilizes

Confirmed missing from `force-app` (M-3 / B-2), intentionally **not** captured now:

- **8 of 9 SC-3346 Apex classes** absent from `force-app/main/default/classes`: COLAUpliftPrehook,
  COLAUpliftHandler, PartnerNetPricePosthook, PartnerPricingService, MaintenanceOrderDecompositionService,
  OrderRepriceInvocable, RenewalMaintenancePricingService, QuoteRenewalTypeHandler. (Only QuoteToOrderFieldMapper is in repo.)
- **Pricing procedure version**: `expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure` container
  is present but the repo copy is **not** the live V14 logic.

**Why deferred:** `COLAUpliftPrehook` (and likely others) are under **active rework** for the SC-3404
commit fix + the test-regression seam migration. Capturing live Apex snapshots now would version-control
pre-final code. Package the code + V14 procedure as the **last** step, after SC-3404 + TEST-SUITE land.

## 5. Repo hygiene blocker found

`force-app/main/default/classes/rca_diagnostic.cls-meta.xml` is an **orphan** (meta with no `.cls`,
committed in 09b07fb). It makes `sf project retrieve/deploy` in **source format** fail with
`ExpectedSourceFilesError`. Must be resolved (restore the `.cls` or remove the orphan meta) before any
source-format deploy of `force-app` — including this field set. This session worked around it via an
MDAPI staging retrieve.

## 6. Validation

- All 13 field-meta files parse as well-formed XML.
- Field types/picklist values match live UAT (retrieved directly from the org).
- `Order.Quote_Type__c` value set captured in full (6 values).
