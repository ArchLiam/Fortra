/**
 * @description Trigger for OrderItem.
 * @date 2026-06-25
 *
 * Handles:
 * - SC-3441: seeds CancelNetUnitPrice__c (originating asset NET) on cancellation /
 *   negative-quantity order lines, BEFORE the pricing procedure runs, so the procedure's
 *   Cancel Net Seed block can credit the line (TotalPrice = net * -1).
 *
 * One trigger per object; all logic lives in CancelLineNetSeedHandler.
 */
trigger OrderItemTrigger on OrderItem (before insert, before update) {

    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        // SC-3441: seed asset NET on cancellation (negative-qty) lines.
        // isInsert gates the direct NetUnitPrice write (writeable only pre-OrderItemDetail).
        CancelLineNetSeedHandler.handleOrderItems(Trigger.new, Trigger.isInsert);
    }
}
