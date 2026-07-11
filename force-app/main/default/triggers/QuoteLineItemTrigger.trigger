/**
 * @description Single trigger for QuoteLineItem; routes every event to QuoteLineItemTriggerHandler.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
trigger QuoteLineItemTrigger on QuoteLineItem (
    before insert, before update, after insert, after update
) {
    QuoteLineItemTriggerHandler handler = new QuoteLineItemTriggerHandler();

    switch on Trigger.operationType {
        when BEFORE_INSERT { handler.beforeInsert(Trigger.new); }
        when BEFORE_UPDATE { handler.beforeUpdate(Trigger.new, Trigger.oldMap); }
        when AFTER_INSERT  { handler.afterInsert(Trigger.newMap); }
        when AFTER_UPDATE  { handler.afterUpdate(Trigger.newMap, Trigger.oldMap); }
    }
}
