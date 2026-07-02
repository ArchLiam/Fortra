# SC-3473 Re-verification synthesis (2026-06-28, read-only)

## Independently re-confirmed live (this pass)
- Quote 0Q0WC000002U2020AC: CalculationStatus=SaveFailedOrIncomplete, Status=Accepted, USD, IsSyncing=true, LastMod 2026-06-26T16:25:03 by German Wren (005a500001SfRd7AAF). Group undeleted, 4 lines.
- Active proc: Rev_Mgmt_Default_Pricing_Procedure V16 (ExpressionSetDefinitionVersion 9QBWC0000000niH4AQ, Status=Active), metadata LastModifiedDate 2026-06-27T05:49:42 (day AFTER failure).
- Active context: SalesTransactionContextExt_v2 V23 (11pWC000002TjF7YAK, IsActive=true).
- QLI term-state: survivors SUSPIN (02122365/66) PTC=1 End=2027-03-17 clean; grouped Abstract (04266919) TermDefined PT=1 but PTC=null End=null (MALFORMED); grouped AJS (04266918) OneTime PTC=0 End=null.
- Org-wide: 20 SaveFailedOrIncomplete, 47 PriceCalculationFailed, 836 CompletedWithPricing, 165612 NotStarted. This quote is most-recently-modified of the 20.
- Malformed-TermDefined condition (StartDate set, EndDate+PTC null) exists on 79 quotes org-wide -> NECESSARY-here, NOT SUFFICIENT.

## Verdict
Prior RCA CONFIRMED on all 5 load-bearing facts; REFINED on the trigger (named most-probable runtime null key = V16 Proration BKM term/period lookup on the malformed Abstract TermDefined line). Two prior framings OVERTURNED (AJS "configured/attribute" pricing = actually manual NetUnitPrice, 0 QuoteLineItemAttribute; "only HW group with survivors" = actually 7 such quotes, 6 healthy). Wedged SaveFailedOrIncomplete REFRAMES diagnosis: the failure recurs on every save over the malformed in-flight line, not a one-off delete-path quirk -> a plain Reprice-All likely re-throws, so it is NOT a reliable clear-the-wedge lever.
