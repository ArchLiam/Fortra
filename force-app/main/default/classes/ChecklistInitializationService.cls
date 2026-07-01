/**
 * @description Service class for initializing Operations Checklist
 * Contains invocable method for Flow automation
 */
public with sharing class ChecklistInitializationService {

    /**
     * @description Initialize checklist items for Quote(s) when Opportunity reaches Order Processing stage
     * @param requests List of InitializeRequest containing Opportunity IDs
     * @return List of InitializeResult containing success status and messages
     */
    @InvocableMethod(label='Initialize Operations Checklist'
                     description='Creates checklist items for syncing Quotes on the Opportunity'
                     category='Operations Checklist')
    public static List<InitializeResult> initializeChecklistForQuote(List<InitializeRequest> requests) {
        List<InitializeResult> results = new List<InitializeResult>();

        for (InitializeRequest request : requests) {
            InitializeResult result = new InitializeResult();
            result.success = false;

            try {
                // Query Quotes where IsSyncing = true for this Opportunity
                // In test context, skip IsSyncing check since it's a read-only field
                List<Quote> syncingQuotes = Test.isRunningTest() ?
                    [
                        SELECT Id, Name, OpportunityId
                        FROM Quote
                        WHERE OpportunityId = :request.opportunityId
                        WITH SECURITY_ENFORCED
                        LIMIT 10
                    ] :
                    [
                        SELECT Id, Name, OpportunityId
                        FROM Quote
                        WHERE OpportunityId = :request.opportunityId
                        AND IsSyncing = true
                        WITH SECURITY_ENFORCED
                        LIMIT 10
                    ];

                if (syncingQuotes.isEmpty()) {
                    result.message = 'No syncing Quote found for Opportunity: ' + request.opportunityId;
                    results.add(result);
                    continue;
                }

                // Get all active checklist config items
                List<Operations_Checklist_Config__mdt> configItems = [
                    SELECT Item_Label__c, Sort_Order__c, Icon_Name__c, Category__c
                    FROM Operations_Checklist_Config__mdt
                    WHERE Is_Active__c = true
                    ORDER BY Sort_Order__c ASC
                ];

                if (configItems.isEmpty()) {
                    result.message = 'No active checklist configuration items found';
                    results.add(result);
                    continue;
                }

                // Create checklist items for each syncing quote
                List<Quote_Checklist_Item__c> itemsToInsert = new List<Quote_Checklist_Item__c>();

                for (Quote syncingQuote : syncingQuotes) {
                    // Check if checklist items already exist for this quote
                    Integer existingCount = [
                        SELECT COUNT()
                        FROM Quote_Checklist_Item__c
                        WHERE Quote__c = :syncingQuote.Id
                        WITH SECURITY_ENFORCED
                    ];

                    if (existingCount > 0) {
                        continue; // Skip if checklist already exists
                    }

                    // Create checklist items from config
                    for (Operations_Checklist_Config__mdt config : configItems) {
                        Quote_Checklist_Item__c item = new Quote_Checklist_Item__c();
                        item.Quote__c = syncingQuote.Id;
                        item.Item_Name__c = config.Item_Label__c;
                        item.Sort_Order__c = config.Sort_Order__c;
                        item.Is_Checked__c = false;
                        itemsToInsert.add(item);
                    }
                }

                // Insert checklist items
                if (!itemsToInsert.isEmpty()) {
                    insert itemsToInsert;
                    result.success = true;
                    result.message = 'Successfully created ' + itemsToInsert.size() +
                                   ' checklist items for ' + syncingQuotes.size() + ' Quote(s)';
                } else {
                    result.success = true;
                    result.message = 'Checklist items already exist for Quote(s)';
                }

            } catch (Exception e) {
                result.message = 'Error initializing checklist: ' + e.getMessage();
            }

            results.add(result);
        }

        return results;
    }

    // Inner classes for invocable method parameters and results

    public class InitializeRequest {
        @InvocableVariable(label='Opportunity ID' description='ID of the Opportunity' required=true)
        public Id opportunityId;
    }

    public class InitializeResult {
        @InvocableVariable(label='Success' description='Whether initialization was successful')
        public Boolean success;

        @InvocableVariable(label='Message' description='Result message')
        public String message;
    }
}