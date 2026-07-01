/**
 * @description Trigger on Opportunity to manage Hardware record lifecycle
 * @author Claude Code
 * @date 2025-01-25
 *
 * When Opportunity stage changes:
 * - 'Closed Lost': Delete Hardware records with Status='Quoting' (if not referenced by other Opportunities)
 * - 'Order Processing': Change Hardware Status from 'Quoting' to 'Active'
 */
trigger OpportunityTrigger on Opportunity (before insert, before update, after update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            OpportunityTriggerHandler.handleBeforeInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            OpportunityTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        OpportunityTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}