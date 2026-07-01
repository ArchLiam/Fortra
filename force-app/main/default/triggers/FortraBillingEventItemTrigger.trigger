/**
 * Created by german.wren on 2/27/2026.
 */

trigger FortraBillingEventItemTrigger on pse__Billing_Event_Item__c (after insert, after update) {


    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
          FortraBillingEventItemTriggerHandler.handleAfterInsertOrUpdate(Trigger.newMap, Trigger.oldMap);
        }
    }


}