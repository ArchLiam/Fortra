# SC-3441 QuoteLineItemTrigger — exact minimal change to re-apply

Verified 2026-06-25 against LIVE FortraUAT (ApexTrigger 01qWC0000043n8LYAQ, api 61).
The live trigger is byte-identical to the repo `_live_check` copy — NO DRIFT since last retrieve.
The only handler missing from live is the SC-3441 call; all other live handlers are preserved verbatim.

## Live API version to PRESERVE
- QuoteLineItemTrigger live apiVersion = **61.0** (package meta set to 61.0, NOT the repo's stray 62.0).

## The diff (live  ->  redeploy copy)
Two additive hunks only; nothing else changes:

1. Header comment bullet (line 8):
   `+ * - SC-3441: seeds CancelNetUnitPrice__c on cancellation / negative-quantity lines`

2. Inside the existing `if (Trigger.isBefore) { ... }` block, after the COLA update branch:
   ```apex
           // SC-3441: seed asset NET on cancellation (negative-qty) lines
           if (Trigger.isInsert || Trigger.isUpdate) {
               CancelLineNetSeedHandler.handleQuoteLines(Trigger.new);
           }
   ```

All four existing live handler calls are kept untouched:
- RenewalMaintenanceAutoAddHandler.enqueueIfNeeded  (after ins/upd)
- RenewalAssetQuantityHandler.enqueueQuantityNormalization  (after ins)
- QuoteLineItemTriggerHandler.handleHardwareLinking  (before ins/upd)
- COLAUpliftHandler.handleBeforeInsert / handleBeforeUpdate  (before ins / before upd)

## Dependency check (all Active live)
- RenewalMaintenanceAutoAddHandler (api 62), RenewalAssetQuantityHandler (api 62),
  QuoteLineItemTriggerHandler (api 61), COLAUpliftHandler (api 59) — all present.
- Field CancelNetUnitPrice__c — Currency(16,2) — present on BOTH OrderItem and QuoteLineItem.
- OrderItem has ZERO live triggers => OrderItemTrigger is a safe net-new add.

## NOTE: separate live trigger on QuoteLineItem
`QuoteLineItemExchangeRateTrigger` (01qWC000005jIVlYAM, api 62, Active) also exists on
QuoteLineItem but is unrelated and is NOT in this package — leave it alone.
