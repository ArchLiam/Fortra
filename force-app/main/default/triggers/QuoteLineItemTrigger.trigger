/**
 * @description Trigger for QuoteLineItem object
 * @date 2025-01-23
 *
 * Handles:
 * - Automatic hardware assignment when quote lines are added to or removed from groups
 * - COLA (Cost of Living Adjustment) uplift for renewal quote lines
 */
trigger QuoteLineItemTrigger on QuoteLineItem (before insert, before update, after insert) {

    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        RenewalMaintenanceAutoAddHandler.enqueueIfNeeded(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        RenewalAssetQuantityHandler.enqueueQuantityNormalization(Trigger.new);
    }

    if (Trigger.isBefore) {
        // Handle hardware linking on insert and update
        if (Trigger.isInsert || Trigger.isUpdate) {
            QuoteLineItemTriggerHandler.handleHardwareLinking(
                Trigger.new,
                Trigger.oldMap
            );
        }

        // SC-3384: re-point any PricebookEntry whose currency differs from the parent Quote's
        // (managed RLM auto-add resolves a currency-blind PBE) before native validation fires.
        if (Trigger.isInsert) {
            QuoteLineItemCurrencyCorrectionHandler.correctPricebookEntryCurrency(Trigger.new);
        }

        // Handle COLA uplift for renewals
        if (Trigger.isInsert) {
            COLAUpliftHandler.handleBeforeInsert(Trigger.new);
        }

        if (Trigger.isUpdate) {
            COLAUpliftHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}