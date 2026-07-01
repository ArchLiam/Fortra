/**
 * Created by german.wren on 3/2/2026.
 */

public with sharing class FortraBillingEventItemTriggerHandler {

    // Recursion guard.
    private static Boolean isRunning = false;

    public static void handleAfterInsertOrUpdate(Map<Id, pse__Billing_Event_Item__c> newMap, Map<Id, pse__Billing_Event_Item__c> oldMap) {
        if (isRunning) return;

        isRunning = true;

        try {
            System.debug(LoggingLevel.INFO,
                    'Starting Billing Event Trigger to publish WD platform event');
            List<pse__Billing_Event_Item__c> newList = [SELECT Id, Workday_Sync_Status__c, pse__Milestone__r.C_Quote_Line_Item__c,
                                    pse__Project__r.CurrencyIsoCode, pse__Category__c, pse__Quantity__c, pse__Unit_Price__c, pse__Amount__c
                                    FROM pse__Billing_Event_Item__c WHERE Id IN: newMap.keySet()];

            List<pse__Billing_Event_Item__c> newlyReleased = new List<pse__Billing_Event_Item__c>();

            for (pse__Billing_Event_Item__c cur : newList) {
                // Only act if new value is true
                if (cur.Workday_Sync_Status__c != 'Pending') continue;

                // Insert: if new value is Pending, publish event
                // Update: if updated value, check if old value was not Pending and new value is Pending
                Boolean oldWasPublished = false;
                if (oldMap != null) {
                    pse__Billing_Event_Item__c oldRec = oldMap.get(cur.Id);
                    oldWasPublished = (oldRec != null && oldRec.Workday_Sync_Status__c == 'Pending');
                }

                //Only update if billing event item was not Pending and is moved to Pending
                if (!oldWasPublished) {
                    newlyReleased.add(cur);
                }
            }

            System.debug(LoggingLevel.INFO,
                    'Billing Event Items found to publish := ' + newlyReleased.size());

            List<Billing_Event_Item_Released_WD__e> eventsToPublish = new List<Billing_Event_Item_Released_WD__e>();

            if (!newlyReleased.isEmpty()) {
                List<Id> quoteLineIds = new List<Id>();
                for (pse__Billing_Event_Item__c toRelease : newlyReleased) {
                    if (!String.isBlank(toRelease.pse__Milestone__r.C_Quote_Line_Item__c)) {
                        quoteLineIds.add(toRelease.pse__Milestone__r.C_Quote_Line_Item__c);
                    }
                }

                Map<Id, String> quoteLineToWDContractLine = new Map<Id, String>();
                List<OrderItem> orderItems = [SELECT Id, Workday_Sync_Correlation_Id__c, QuoteLineItemId FROM OrderItem WHERE QuoteLineItemId IN: quoteLineIds];
                for(OrderItem i : orderItems)
                {
                    if (!String.isBlank(i.Id) && !String.isBlank(i.QuoteLineItemId)) {
                        quoteLineToWDContractLine.put(i.QuoteLineItemId, i.Id);
                    }
                }

                System.debug(LoggingLevel.INFO,
                        'Matching WD Contract Line Items found := ' + quoteLineToWDContractLine.size());

                if (quoteLineToWDContractLine.size() > 0) {
                    for (pse__Billing_Event_Item__c toRelease : newlyReleased) {

                        //Set values for this platform event
                        Billing_Event_Item_Released_WD__e event = new Billing_Event_Item_Released_WD__e();
                        event.Billing_Event_Item_ID__c = toRelease.Id;
                        event.Transaction_Date__c = Datetime.now();
                        event.Submit_for_Review__c = true;
                        event.Currency_Reference__c = toRelease.pse__Project__r.CurrencyIsoCode;
                        if (toRelease.pse__Category__c == 'Timecard') {
                            System.debug(LoggingLevel.INFO,
                                    'Preparing Timecard Event to publish');
                            event.Unit_of_Measure_Reference__c = 'HUR';
                            event.Quantity__c = toRelease.pse__Quantity__c;
                            event.Rate__c = toRelease.pse__Unit_Price__c;
                        } else {
                            System.debug(LoggingLevel.INFO,
                                    'Preparing Milestone Event to publish');
                            event.Unit_of_Measure_Reference__c = 'EA';
                            event.Quantity__c = 1;
                            event.Rate__c = toRelease.pse__Amount__c;
                        }
                        event.Contract_Line_Reference__c = quoteLineToWDContractLine.get(toRelease.pse__Milestone__r.C_Quote_Line_Item__c);
                        if (!String.isBlank(event.Contract_Line_Reference__c)) {
                            event.Contract_Line_Reference__c = event.Contract_Line_Reference__c + '_Usage Based';
                            eventsToPublish.add(event);
                        }
                        else {
                            System.debug(LoggingLevel.ERROR,
                                    'Could not find WD Contract Line Id for billing event item: ' + event.Billing_Event_Item_ID__c);
                        }
                    }
                }
            }

            System.debug(LoggingLevel.INFO,
                    'Platform Events to publish := ' + eventsToPublish.size());
            //Publish events and update billing event item
            if (!eventsToPublish.isEmpty()) {
                List<Database.SaveResult> results = EventBus.publish(eventsToPublish);

                for (Integer i = 0; i < results.size(); i++) {

                    if (results.get(i).isSuccess()) {
                        System.debug(LoggingLevel.INFO,
                                'Platform Event published successfully for Billing Event Item ' +
                                        eventsToPublish.get(i).Billing_Event_Item_ID__c
                        );
                    } else {
                        for (Database.Error err : results.get(i).getErrors()) {
                            System.debug(LoggingLevel.ERROR,
                                    'Platform Event publish FAILED for Billing Event Item ' + eventsToPublish.get(i).Billing_Event_Item_ID__c +
                                            ' status=' + err.getStatusCode() +
                                            ' message=' + err.getMessage()
                            );
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, e.getMessage());
        } finally {
            isRunning = false;
        }
    }
}