/**
 * @description Trigger for QuoteLineItem object
 * @date 2025-01-23
 *
 * Handles:
 * - Automatic hardware assignment when quote lines are added to or removed from groups
 * - COLA (Cost of Living Adjustment) uplift for renewal quote lines
 * - SC-3346/SC-3404: born-net QuoteAction synthesis for auto-added renewal-maintenance lines
 */
trigger QuoteLineItemTrigger on QuoteLineItem (before insert, before update, after insert) {

    if (Trigger.isAfter && Trigger.isInsert) {
        RenewalAssetQuantityHandler.enqueueQuantityNormalization(Trigger.new);
        RenewalQuoteLineHandler.enqueueCarryoverCleanup(Trigger.new);
    }

    if (Trigger.isBefore) {
        // Handle hardware linking on insert and update
        if (Trigger.isInsert || Trigger.isUpdate) {
            QuoteLineItemTriggerHandler.handleHardwareLinking(
                Trigger.new,
                Trigger.oldMap
            );
        }

        // Handle COLA uplift for renewals
        if (Trigger.isInsert) {
            // SC-3346/SC-3404 — synthesize a Type='Renew' QuoteAction on QA-less renewal-maintenance
            // lines BEFORE handleBeforeInsert, so the line is born a priced node and prices born-net
            // (the correct COLA net) instead of settling un-priced and locking to the fossil/$0.
            RenewalQuoteActionStamp.synthesizeRenewQuoteActions(Trigger.new);
            COLAUpliftHandler.handleBeforeInsert(Trigger.new);
        }

        if (Trigger.isUpdate) {
            COLAUpliftHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
