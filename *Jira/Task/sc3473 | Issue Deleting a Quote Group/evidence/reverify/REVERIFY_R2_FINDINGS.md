# SC-3473 R2 RE-VERIFICATION — push to NAME the missing map key (read-only)

Date 2026-06-28. Org FortraUAT. 100% read-only (SOQL + Tooling + MDAPI retrieve + local file reads). No DML.

## Live state re-confirmed (authoritative)
- Active pricing procedure: `Rev_Mgmt_Default_Pricing_Procedure` **V16** (ExpressionSetDefinitionVersion 9QBWC0000000niH4AQ, Status=Active). Retrieved live block = `reverify/V16_active_block.xml`.
- Active context: `SalesTransactionContextExt_v2` **V23** (ContextDefinitionVersion 11pWC000002TjF7YAK, IsActive=True, only version). Retrieved live = `reverify/SalesTransactionContextExt_v2_V23.contextDefinition`.
- Repro quote 0Q0WC000002U2020AC: **CalculationStatus = SaveFailedOrIncomplete** (unchanged), LastMod 2026-06-26T16:25:03 by German Wren. ContractId=null, OpportunityId=006WC00000NMOODYA5.

## Map-keyed step trace (full inventory = reverify/V16_mapkeyed_steps_inventory.txt)
Of 109 step/container entries in active V16, the steps that build/read a per-line/per-group/per-product map:
- step[1] Aggregate Price — keys on `SalesTransactionItemGroup` (Text), `isNotNull`-guarded -> EXCLUDES the null-group survivors; group is deleted -> no stale entry. (RE-CONFIRMED, not the throw.)
- step[7/8] AttributeDiscount, step[17] BundleDiscount, step[107] VolumeDiscount — decision-table lookups keyed on (Product, PSM, attr/bound); all gated OFF for these lines (Has_Attribute_Adjustment__c=FALSE on all 4 lines; no bundles; not contracted).
- step[31] DerivedPricing 'Derived Products - Renewals' — keyed on `Contributor/ContributorProduct/ContributorSource/ContributorScope`; gated by `ItemIsDerived__std=true`. Survivors are NOT derived -> does not run for them. (Contributor-dangling-ref hypothesis from mission point 3 is NOT reachable for survivors.)
- step[85] **Proration** (BusinessKnowledgeModel) — consumes `PricingTermUnit + EffectiveFrom + itemTransientEndDate` (itemTransientEndDate derives from line EndDate); outputs `PricingTermCount`. RUNS for every TermDefined line.
- step[98/99/100] SubscriptionPricing — read `ProrationMultiplier <- PricingTermCount`. RUN for TermDefined.
- step[91/92/97/103] category/total aggregates — FLAT sums; Subscription aggregate runs over survivors normally.

## Context V23 hydration trace (mission point 2 — runtime conditionality, not static gap)
- 1120 `contextAttrHydrationDetails`; **0 empty queryAttribute** -> no static hydration gap (RE-CONFIRMED).
- SalesTransactionItem node = 203 attributes; per-line term attributes (SellingModelType, PricingTermUnit, PricingTerm, EndDate-derived) are all platform-inherited (`SalesTransactionContext__stdctx`) and natively hydrated.
- The custom (`__c`) hydration map is symmetric QLI↔OrderItem except `OrderItem.RegionalNetUnitPrice__c` / `OrderItem.AllowRegionalPricing__c` (OrderItem-only) — gated off (Allow_Regional_Pricing__c=FALSE on all lines). (RE-CONFIRMED from prior pass.)
- **No static unmapped attribute is reachable for the survivors.** A runtime-value null (below) is the only remaining channel.

## Configured-pricing dimension (mission point 3) — REFUTED
- All 4 lines: `Has_Attribute_Adjustment__c=False`, `Attribute_Price_Mode__c=null`, no ParentQuoteLineItemId, no Clone_Parent_LineItemId__c.
- `QuoteLineItemAttribute` count for the 4 lines = **0**.
- The AJS net 29060 vs list 2850 markup is NOT attribute/config-based — it is a manually-entered NetUnitPrice. **There is no configuration to leave a dangling reference.** Mission point 3 is closed.

## NEW differential — the prior "only quote with survivors" claim was WRONG; the true discriminator is sharper
7 (not 1) HW-type-group quotes have ungrouped survivors:
| Quote | Grouped composition | Survivors | CalcStatus |
|---|---|---|---|
| **0Q0WC000002U2020AC** | **Perpetual/OneTime + Subscription/TermDefined (MIXED, in-group)** | 2 Subscription/TermDefined | **SaveFailedOrIncomplete** |
| 0Q0WC000002Hj1B0AS | (none grouped now) | 2 Subscription/TermDefined | CompletedWithPricing |
| 0Q0WC000002Ly1d0AC | Perpetual/OneTime only (single-SM) | 2 Perpetual/OneTime | CompletedWithPricing |
| 0Q0WC000002X6qH0AS | (none grouped now) | 2 Subscription/TermDefined | CompletedWithPricing |
| 0Q0WC00000372Ef0AI | (none grouped now) | Services+Subscription+Perpetual | CompletedWithPricing |
| 0Q0WC0000038zZF0AY | (none grouped now) | 1 Software/TermDefined | CompletedWithPricing |
| 0Q0WC000003A6f70AC | (none grouped now) | NewMaint+Perpetual+Subscription | CompletedWithPricing |

Only the failing quote currently holds an in-group mix and is the only one in SaveFailedOrIncomplete.

## THE SMOKING GUN (new, read-only, data-grounded)
Line provenance on the failing quote:
- 2 SUSPIN survivors: created 2026-03-18, TermDefined, **EndDate=2027-03-17, PTC=1 — complete, ZERO null fields**.
- AJS (deleted): created 2026-06-26 16:05:46, OneTime, EndDate=null PTC=0 — normal for OneTime.
- **Abstract (deleted): created 2026-06-26 16:05:50, SellingModelType=TermDefined, PricingTermUnit=Annual, PricingTerm=1, but EndDate=null AND PricingTermCount=null — MALFORMED term line.**

The HW group "Test HW1" + its AJS/Abstract lines were ADDED 2026-06-26; the Abstract TermDefined line was born without EndDate/PTC, and the quote went to SaveFailedOrIncomplete the same hour. This is the SC-3420 / SC-3411 / SC-3406 "TermDefined null EndDate/PTC" family (deleted Proration step / read-only PTC).

**Mechanism:** The V16 Proration BKM (step 85) for a TermDefined line looks up a proration period using `EffectiveFrom + itemTransientEndDate(=EndDate) + PricingTermUnit`. With EndDate=null -> itemTransientEndDate=null, the native proration-period **`Map.get(periodKey)` returns null**, and a downstream `.toString()` on that value throws the JEP-358 NPE. The Delete-Group `pricingPref:Force` re-runs the full procedure over the transaction graph that still includes the malformed Abstract line during the calc pass, so the reprice re-throws and the header (committed first) is not rolled back -> "Your quote was not updated."

## Most-probable named key (best read-only inference)
**The null key is the proration-period / term-count lookup for the malformed TermDefined "Abstract" line — driven by null `EndDate` (-> null `itemTransientEndDate`) with `PricingTermUnit=Annual`.** This is a RUNTIME null in the Proration/Subscription BKM, NOT a static context-mapping gap and NOT a selling-model aggregate. It is consistent with the documented `getTags()` sibling (same `DefaultContextRuntimeEntityAttribute` map family) and with the org's TermDefined-term-field defect cluster.

## Honest limit
- Org-wide, 79 quotes carry a malformed TermDefined line (EndDate+PTC null); 74 are CompletedWithPricing. So the malformed term is NECESSARY-here but not SUFFICIENT alone — the throw needs the confluence: malformed TermDefined line **inside a HW group being deleted with a forced full reprice over the in-flight graph**. The exact native frame (Proration vs a contributor/tag frame) and the literal map key string are still only confirmable by an authorized FINEST-logged Delete-Group repro (DML).
- A FINEST trace would show either `Proration`/`SubscriptionPricing` BKM evaluating the Abstract line with a null period, or a `DefaultContextRuntimeEntityAttribute` map miss on the term attribute — naming the literal key.
