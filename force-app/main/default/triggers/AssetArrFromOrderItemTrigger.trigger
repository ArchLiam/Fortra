/**
 * @description Apex replacement for the deprecated flow `Fortra_Asset_Copy_ARR_From_OrderItem`.
 *              Copies the source OrderItem's Order_Line_ARR__c onto Asset.ARR__c (A-3 / ARR
 *              consolidation to Apex). Runs after insert AND update to match the flow's
 *              CreateAndUpdate trigger and to catch the OrderItem linkage whenever it becomes available.
 */
trigger AssetArrFromOrderItemTrigger on Asset (after insert, after update) {
    AssetArrFromOrderItemHandler.copyArrFromOrderItem(Trigger.new);
}
