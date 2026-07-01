/**
 * @description Trigger on Quote to initialize checklist when IsSyncing is set to true
 */
trigger QuoteSyncingTrigger on Quote (after update) {
    QuoteSyncingTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}