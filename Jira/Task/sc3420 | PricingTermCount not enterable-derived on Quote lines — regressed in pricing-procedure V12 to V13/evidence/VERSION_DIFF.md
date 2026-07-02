# Evidence — pricing-procedure version diff (the smoking gun)

Source: live metadata retrieve from FortraUAT, 2026-06-16, package
`ExpressionSetDefinition Rev_Mgmt_Default_Pricing_Procedure` + `ExpressionSetDefinitionVersion *` + `ContextDefinition SalesTransactionContextExt_v2`.
Raw files: `Data/sc3420/live_retrieve/unpackaged/expressionSetVersion/`.

## Version status + PricingTermCount footprint

| File (version) | versionNumber | status | `PricingTermCount` refs | `actionType=Proration` steps |
|---|---|---|---|---|
| `...V1` | 1 | Inactive | 18 | 2 |
| `...Revenue_Management_Default_Pricing_Procedure0` | 2 | Inactive | 18 | 2 |
| `...V30` | 3 | Inactive | 18 | 2 |
| `...V40` | 4 | Inactive | 18 | 2 |
| `...V50` | 5 | Inactive | 18 | 2 |
| `...V60` | 6 | Inactive | 18 | 2 |
| `...SFRev...V70` | 7 | Inactive | 18 | 2 |
| `...V80` | 8 | Inactive | 18 | 2 |
| `...V90` | 9 | Inactive | 18 | 2 |
| `...V100` | 10 | Inactive | 18 | 2 |
| `...V110` | 11 | Inactive | **18** | **2** |
| `...V120` | 12 | Inactive | **16** | **1** |
| `...V130` | 13 | Inactive | 16 | 1 |
| **`...V140`** | **14** | **ACTIVE** | **16** | **1** |
| `...V150` | 15 | Draft | 16 | 1 |

**The footprint drops 18→16 (and Proration 2→1) exactly at V11→V12.** Everything ≥ V12 (incl. live-active V14) is missing the step.

## The two PricingTermCount references that disappear (V11 → V12)

Both removed refs belong to **Proration** steps whose output `ProrationMultiplier` (output=true) is mapped to `PricingTermCount`:

```
V11  Proration steps (both write PricingTermCount):
  name=Proration     parentStep=TermDefinedSubscriptionFilterontheSellingModelTypeLineLevel   ← TermDefined  [DELETED]
  name=Proration72   parentStep=EvergreenanytimeprorationfilterLinelevel                       ← Evergreen    [kept, re-id'd]

V12 / V14  Proration steps:
  name=Proration     parentStep=EvergreenanytimeprorationfilterLinelevel                       ← Evergreen ONLY
  (no TermDefined Proration step; no TermDefinedSubscriptionFilter... container)
```

`grep -c "TermDefined"`:  V11 = 7,  V12 = 2,  V14 = 2.
The container name `TermDefinedSubscriptionFilterontheSellingModelTypeLineLevel` exists in V11, **absent** in V12/V14.

## V14 subscription filter conditions (proves TermDefined lines reach no writer)

```
ListOperation73 (gate of the surviving Proration):
   SellingModelType = 'Evergreen' AND AllowPartialProrationPeriods = true AND itemTransientEndDate IsNotNull   → excludes TermDefined
ListOperation77 (ListContainer76):  SellingModelType != 'Evergreen' AND != 'TermDefined'                      → OneTime/other
ListOperation81 (ListContainer80):  SellingModelType = 'Evergreen' AND AllowPartial=false AND endDate IsNull   → Evergreen-no-proration
ListOperation84 (ListContainer83):  SellingModelType = 'TermDefined' OR 'Evergreen'                            → subscription PRICING (reads PTC, never writes)
```

TermDefined lines only match `ListContainer83`, whose Subscription Pricing steps consume `PricingTermCount` as an **input** (`ProrationMultiplier`, input=true) — there is no write.

## Step-name churn V11 → V12 (context: this was the Maintenance-Derived / COLA rebuild)

Removed in V12 (incl. the PTC writer + its filter):
`TermDefinedSubscriptionFilterontheSellingModelTypeLineLevel`, `Proration72`, `COLAUpliftonRenewal21`, `RegionalNetReconcile*`, `RegionalServicesPrice27`, `SubscriptionPricing73/77/83`, `AttributePricingFilter47`, many `ListContainer*`/`ListOperation*` (re-numbered).

Added in V12:
`DerivedProductsNativePull`, `DerivedProductsNonRenewal`, `PartnerDiscountDerivedMaintenance{,19,20}`, `StampPartnerUnitPriceDerivedMaintenance`, `COLAUpliftNetonRenewal`, `COLAUpliftonRenewal27`, `SubscriptionPricing80/86`, re-numbered containers.

→ V12 = Maintenance Derived Pricing / COLA build. The TermDefined Proration writer was dropped during that re-number/rebuild — collateral, not intentional (removing it breaks ARR/convert/activate for every TermDefined product).

## Context definition is intact (refutes the "context de-sync" theory)

`SalesTransactionContextExt_v2.contextDefinition` still maps `PricingTermCount`:
- line 728-730: `SalesTransactionItem/PricingTermCount` (write-back)
- line 5453-5458: `QuoteEntitiesMapping/SalesTransactionItem/PricingTermCount` hydration (read-in)

So a restored writer step will persist. The break is purely the missing procedure step.
