# SC-3473 R3 Re-verification + Workaround Engineering (READ-ONLY)
Date: 2026-06-28 | Org: FortraUAT | No DML performed.

## Live re-verification (all queries run 2026-06-28)
| Claim | Result | Query |
|---|---|---|
| Quote CalculationStatus = SaveFailedOrIncomplete | CONFIRMED (still wedged; LastModified 2026-06-26 by 005a500001SfRd7AAF) | `SELECT CalculationStatus,Status FROM Quote WHERE Id='0Q0WC000002U2020AC'` |
| Quote Status = Accepted, USD, group undeleted | CONFIRMED | same + QuoteLineGroup query |
| Group 1C9WC00000097of0AA "Test HW1" still present, Hardware_Group_Type__c=true, Hardware__c=a0nWC000001wdV3YAI | CONFIRMED | `SELECT Id,Name,Hardware_Group_Type__c,Hardware__c FROM QuoteLineGroup WHERE QuoteId=...` |
| 4 lines: 2 survivors (SUSPIN, null group, Net=List=20000, PTC=1) + 2 grouped (AJS Net29060/List2850 PTC=0; Abstract Net4356/List46 PTC=null) | CONFIRMED | `SELECT ... FROM QuoteLineItem WHERE QuoteId=...` |
| Active procedure Rev_Mgmt_Default_Pricing_Procedure V16 | CONFIRMED | Tooling ExpressionSetDefinitionVersion Active |
| Active context SalesTransactionContextExt_v2 V23 | CONFIRMED | Tooling ContextDefinitionVersion IsActive=true |
| Opp 006WC00000NMOODYA5 open (Pre-Qualified), still SyncedQuoteId=this quote | CONFIRMED | `SELECT StageName,IsClosed,SyncedQuoteId FROM Opportunity` |

## Dev-guide grounded mechanism (rlm_dev_guide.txt)
- L128259-128260 (VERBATIM): "This API saves and commits the quote header first, then processes configuration, pricing, and persistence for components, such as line items and groups. If a later step fails, the header isn't rolled back." -> explains "quote was not updated" + header-commit.
- L124875 (VERBATIM): pricingPref **Force — Reprices ALL lines.** (QLE Delete Group uses Force.)
- L124876: **System — delta pricing request on the UNPROCESSED lines** (only when Delta Pricing enabled).
- L124878: **Skip — Skips the pricing request on ALL lines.**
- L128213-128227: Place Quote API exposes pricingPref {Force|Skip|System}, default System; and `configuration` input {RunAndAllowErrors|RunAndBlockErrors|Skip}.
- L127165-127208: Ungroup example INCLUDES the surviving QuoteLineItems in the payload with QuoteLineGroupId=null set on them (lines are PUT/updated, not deleted) -> Ungroup still detaches+touches the lines through the same place pipeline.
- L124946-124957: TransactionProcessingType supports a named "SkipPricingAndTaxStep" with PricingPreference:Skip — supported admin lever to skip pricing.
- L123243-123245: SaveFailedOrIncomplete = "recent changes weren't saved" / UI "Some Records Weren't Saved" — designed status fired while raw NPE leaked (robustness gap, H6 holds).

## Decisive reasoning for workarounds
- The throw is in the FORCED reprice of survivors after grouped-line teardown. Any path that (a) does NOT force a full reprice, or (b) removes the problematic configured grouped lines via a path that doesn't reprice the survivors-with-this-context, AVOIDS the NPE.
- pricingPref:Skip (Force->Skip) is the cleanest avoid: skips pricing on all lines, group still deletes, header+graph still persist. NOT exposed in QLE UI -> requires a direct ConnectApi/Anonymous-Apex Place call (DML).
- Reprice-All on the wedged quote reprices ALL 4 lines incl. the broken configured grouped lines -> likely re-throws the SAME NPE; low odds of clearing the wedge.
