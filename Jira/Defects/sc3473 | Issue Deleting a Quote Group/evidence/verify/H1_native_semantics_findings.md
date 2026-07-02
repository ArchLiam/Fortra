# H1-selling-model-mix — native-semantics lens verification (READ-ONLY)
Date 2026-06-28. Org FortraUAT (00DWC000006eUFF2A2). All read-only.

## Premise corrections (VERIFIED)
1. ACTIVE pricing-procedure version is V16 (Tooling: ExpressionSetDefinitionVersion,
   Rev_Mgmt_Default_Pricing_Procedure, V16 Status=Active; V15 Inactive). The local
   retrieve in mission_B/live_source shows V15 Active = STALE mirror.
2. The "129 GroupingAndAggregatePricing native steps" is a COUNTING ARTIFACT: grep over
   the whole expressionSetDefinition spans ALL 20 versions (~6 each => 129 total).
   The ACTIVE V16 has exactly **6** GroupingAndAggregatePricing action steps (not 129).
   (sed V16 region 86649-92384: `grep -c GroupingAndAggregatePricing` = 6.)

## Core refutation — NONE of the 6 aggregate steps key on selling model
Parsed all 6 GroupingAndAggregatePricing steps in active V16:
- #1 AggregatePrice (seq36): group-count=0 (FLAT), SUM TotalLineAmount -> Subtotal
- #2 AggregatePrice106 (seq37): group-count=1, group key = **SalesTransactionItemGroup**
     (the item-GROUP id, Text), SUM ItemNetTotalPrice -> ItemGroupSummarySubtotal;
     condition-0 = SalesTransactionItemGroup isNotNull
- #3 Services Aggregate (seq2): group-count=0 (FLAT) -> Total_Services__c
- #4 Software Aggregate (seq2): group-count=0 (FLAT) -> Total_Software__c
- #5 Subscription Aggregate (seq2): group-count=0 (FLAT) -> Total_Subscription__c
- #6 Total Amount (seq34): group-count=0 (FLAT) SUM ItemNetTotalPrice -> TotalAmount
=> 5/6 are FLAT (no key). The ONLY keyed one keys on the GROUP id, NOT selling model /
   PSM / PricingTerm / PricingTermCount. No selling-model-keyed aggregate map exists in
   the active procedure. The hypothesised "map keyed by selling-model/term" is absent.
=> Also: the surviving ungrouped lines have null SalesTransactionItemGroup, so the one
   keyed step's isNotNull condition EXCLUDES them; they never enter that keyed map, and
   the deleted group is gone => no stale OneTime entry survives to be looked up.

## SM-mix is not necessary/sufficient (scale)
- Org-wide: >=812 quotes mix OneTime AND TermDefined lines at the quote level
  (QuoteLineItem SOQL, 50k-row cap). These reprice constantly without this NPE.
  A selling-model-keyed-map-goes-stale mechanism would break at this scale; it doesn't.
- Mission E uniqueness (re-derived from all_hwgroup_sm.json) is real but SCOPED: of 17
  in-group hardware sets, exactly 1 mixes OneTime+TermDefined (the failing group). That
  is a CORRELATION/discriminator, not a throw mechanism.

## Web / platform doc — points to a DIFFERENT subsystem (the refute condition)
- The ONLY documented sibling of this exact JEP-358 error in RLM (applikontech RLM
  troubleshooting guide) is:
  "...hydrating additional context fields: Cannot invoke
   industries.context.api.service.model.runtime.schema.impl.defaultimpl.
   DefaultContextRuntimeEntityAttribute.getTags() because the return value of
   java.util.Map.get(Object) is null"
  Subsystem = Industries CONTEXT SERVICE runtime during CONTEXT HYDRATION; stated cause =
  Context Definition Mappings / custom tag mappings; "No direct connection" to selling model.
  This is precisely H1's own REFUTE condition ("throw in a context-hydration
  (industries.context) frame unrelated to selling model").
- No authoritative source ties this error string to GroupingAndAggregatePricing /
  selling-model aggregation.

## Verdict: REFUTED (lens = native-semantics)
The named native subsystem (selling-model/term aggregate map) does NOT exist as claimed in
the active procedure; the documented native throw site for this error is context hydration,
not selling-model aggregation. SM-mix is a correlated discriminator, not the mechanism.
