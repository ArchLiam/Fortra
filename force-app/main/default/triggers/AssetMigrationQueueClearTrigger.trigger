/**
 * After-insert trigger on Asset. When an Asset is created from a migration-
 * created Contract, clears In_Rerun_Queue__c on any Migration_Run_Detail__c
 * rows for the Quote that produced this Asset. Implements the strict
 * "Full Pipeline succeeded" auto-remove milestone (Order + AUA + Asset).
 */
trigger AssetMigrationQueueClearTrigger on Asset (after insert) {
    AssetMigrationQueueClearHandler.handleAfterInsert(Trigger.newMap.keySet());
}