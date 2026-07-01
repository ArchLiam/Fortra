trigger OrderValidationTrigger on Order (before insert, before update) {
    if (Trigger.isInsert) {
        OrderValidationTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        OrderValidationTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}