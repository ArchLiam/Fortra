# K-07 Smoke Result — Co-owned version churn drops logic deltas (V16 vs V20 reconcile)
Date: 2026-06-30 (UTC) / 2026-06-29 local. Org: FortraUAT. Active proc: Rev_Mgmt_Default_Pricing_Procedure V21 (Id 9QBWC0000000oWH4AY, single Active of 21 versions).

## Method
Retrieved LIVE V21 metadata fresh (MDAPI, ExpressionSetDefinitionVersion, api 67) to
Data/sc3473/k07_validation/retrieve/mdapi/.../Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V210.expressionSetVersion
Then Force-repriced REAL quotes via connect/rev/sales-transaction/actions/place and read fresh field values.

## Live V21 metadata (the serialized snapshot)
- description: "...V20 (COLA proration + guards + currency) with Derived Pricing Formula reverted to 3-tier. DRAFT."
- Derived Pricing Formula value (verbatim): IF(QuoteTypeText__c='Renewal', NetUnitPrice,
  IF(AttributeValue='Premier',0.30, IF(AttributeValue='Standard',0.20, IF(AttributeValue='Professional',0.20, 0))) * contributorBase)
  => ONLY 3 tiers serialized. Basic/Premium/Express/Expert -> 0 fallback in metadata.
- StartProrationPeriod x6, ItemSubscriptionTerm x1, PricingTermCount x18, Proration actionType x1, ProrationTermDefined x4, Evergreen/OneTime PTC constants present.

## Runtime (Force-reprice, fresh LastModifiedDate 2026-06-30T03:16-03:17)
Quote Q-K07 0Q0WC000003FZVB0A4, BoKS license 355 + 4 NewMaint lines keyed by Maintenance Type Defn:
- 04267122 Basic   (NOT in 3-tier metadata) -> NetUnitPrice 53.25  = 0.15 x 355  (metadata would give $0)
- 04267123 Standard (in metadata 0.20)       -> 71      = 0.20 x 355
- 04267126 Expert  (NOT in metadata)          -> 124.25 = 0.35 x 355  (metadata would give $0)
- 04267127 Premium (NOT in metadata)          -> 85.20  = 0.24 x 355  (metadata would give $0)
TermDefined line (Quote 0Q0WC000002U2020AC, QLI 0QLWC000003jN8P4AU "Abstract"): after reprice
PricingTermCount=1, EndDate=2027-06-25 (Start 2026-06-26 +12mo), SubscriptionTerm=1, Net 4356; reprice isSuccess=true (guards skip null-PB lines clean).

## Verdict: PASS (runtime correct end-to-end) + GOVERNANCE/DURABILITY finding
All 3 K-07 deltas execute correctly at runtime under live V21: 7-tier derived reduction, TermDefined proration sub-tree, guards.
BUT the serialized V21 metadata diverges from the compiled runtime: metadata = 3-tier "DRAFT", runtime = 7-tier. This IS the
co-owned clobber/re-apply ping-pong K-07 warns about. Exposure if the 3-tier snapshot is ever republished: 79 NewMaintenance
QLIs org-wide currently carry NetUnitPrice>0 under the 7-tier runtime; any on a dropped tier would zero out. No live mispricing today.
defect_provenance: SC-3473 / COLA V16-V20 (durability/governance, not a runtime mispricing).
