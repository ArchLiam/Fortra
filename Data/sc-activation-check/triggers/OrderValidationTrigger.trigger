trigger OrderValidationTrigger on Order (before insert) {
    OrderValidationTriggerHandler.handleBeforeInsert(Trigger.new);
}