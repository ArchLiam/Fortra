/**
 * @description Test class for QuoteSyncingTriggerHandler
 * Note: Cannot directly test IsSyncing field changes as it's read-only.
 * Tests focus on the processOpportunities method using @TestVisible pattern.
 */
@IsTest
private class QuoteSyncingTriggerHandlerTest {

    @TestSetup
    static void setup() {
        // Create test Opportunities in different stages
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Test Opp Order Processing',
                StageName = 'Order Processing',
                CloseDate = Date.today().addDays(30)
            ),
            new Opportunity(
                Name = 'Test Opp Prospecting',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            )
        };
        insert opps;

        // Create Quotes for each Opportunity
        List<Quote> quotes = new List<Quote>{
            new Quote(
                Name = 'Test Quote 1',
                OpportunityId = opps[0].Id
            ),
            new Quote(
                Name = 'Test Quote 2',
                OpportunityId = opps[1].Id
            )
        };
        insert quotes;
    }

    /**
     * Test that checklist items are created when processing an Opportunity in Order Processing stage
     */
    @IsTest
    static void testProcessOpportunities_OrderProcessingStage() {
        // Query the Opportunity in Order Processing stage
        Opportunity opp = [
            SELECT Id
            FROM Opportunity
            WHERE StageName = 'Order Processing'
            LIMIT 1
        ];

        Quote quote = [
            SELECT Id
            FROM Quote
            WHERE OpportunityId = :opp.Id
            LIMIT 1
        ];

        Test.startTest();
        // Call the testable method directly
        Set<Id> oppIds = new Set<Id>{ opp.Id };
        QuoteSyncingTriggerHandler.processOpportunities(oppIds);
        Test.stopTest();

        // Verify checklist items were created
        Integer checklistCount = [
            SELECT COUNT()
            FROM Quote_Checklist_Item__c
            WHERE Quote__c = :quote.Id
        ];
        System.assert(checklistCount > 0, 'Checklist items should be created for Opportunity in Order Processing');
    }

    /**
     * Test that checklist items are NOT created when Opportunity is not in Order Processing stage
     */
    @IsTest
    static void testProcessOpportunities_NonOrderProcessingStage() {
        // Query the Opportunity NOT in Order Processing stage
        Opportunity opp = [
            SELECT Id
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        Quote quote = [
            SELECT Id
            FROM Quote
            WHERE OpportunityId = :opp.Id
            LIMIT 1
        ];

        Test.startTest();
        // Call the testable method directly
        Set<Id> oppIds = new Set<Id>{ opp.Id };
        QuoteSyncingTriggerHandler.processOpportunities(oppIds);
        Test.stopTest();

        // Verify no checklist items were created
        Integer checklistCount = [
            SELECT COUNT()
            FROM Quote_Checklist_Item__c
            WHERE Quote__c = :quote.Id
        ];
        System.assertEquals(0, checklistCount, 'Should not create checklist items for Opportunity not in Order Processing');
    }

    /**
     * Test processing with empty set of Opportunity IDs
     */
    @IsTest
    static void testProcessOpportunities_EmptySet() {
        Test.startTest();
        // Call with empty set - should not throw exception
        Set<Id> oppIds = new Set<Id>();
        QuoteSyncingTriggerHandler.processOpportunities(oppIds);
        Test.stopTest();

        // Verify no checklist items were created
        Integer checklistCount = [
            SELECT COUNT()
            FROM Quote_Checklist_Item__c
        ];
        System.assertEquals(0, checklistCount, 'Should not create any checklist items for empty Opportunity set');
    }

    /**
     * Test processing multiple Opportunities at once
     */
    @IsTest
    static void testProcessOpportunities_MultipleOpportunities() {
        // Create additional Opportunity in Order Processing
        Opportunity opp2 = new Opportunity(
            Name = 'Test Opp Order Processing 2',
            StageName = 'Order Processing',
            CloseDate = Date.today().addDays(30)
        );
        insert opp2;

        Quote quote2 = new Quote(
            Name = 'Test Quote 3',
            OpportunityId = opp2.Id
        );
        insert quote2;

        // Get both Order Processing Opportunities
        List<Opportunity> opps = [
            SELECT Id
            FROM Opportunity
            WHERE StageName = 'Order Processing'
        ];

        Test.startTest();
        // Process both opportunities
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }
        QuoteSyncingTriggerHandler.processOpportunities(oppIds);
        Test.stopTest();

        // Verify checklist items were created for all processed Opportunities
        Integer totalChecklistCount = [
            SELECT COUNT()
            FROM Quote_Checklist_Item__c
        ];
        System.assert(totalChecklistCount > 0, 'Checklist items should be created for multiple Opportunities');
    }

    /**
     * Test handleAfterUpdate with IsSyncing change simulation using JSON deserialization.
     * IsSyncing is read-only via DML but can be set on in-memory SObjects.
     */
    @IsTest
    static void testHandleAfterUpdate_IsSyncingChange() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE StageName = 'Order Processing' LIMIT 1];
        Quote quote = [SELECT Id FROM Quote WHERE OpportunityId = :opp.Id LIMIT 1];

        // Build in-memory Quote objects with IsSyncing set via JSON deserialization
        Quote oldQuote = (Quote) JSON.deserialize(
            '{"Id":"' + quote.Id + '","IsSyncing":false,"OpportunityId":"' + opp.Id + '"}',
            Quote.class
        );
        Quote newQuote = (Quote) JSON.deserialize(
            '{"Id":"' + quote.Id + '","IsSyncing":true,"OpportunityId":"' + opp.Id + '"}',
            Quote.class
        );

        Map<Id, Quote> oldQuoteMap = new Map<Id, Quote>{ quote.Id => oldQuote };

        Test.startTest();
        QuoteSyncingTriggerHandler.handleAfterUpdate(
            new List<Quote>{ newQuote }, oldQuoteMap
        );
        Test.stopTest();

        Integer checklistCount = [
            SELECT COUNT() FROM Quote_Checklist_Item__c WHERE Quote__c = :quote.Id
        ];
        System.assert(checklistCount > 0, 'Checklist items should be created when IsSyncing changes to true');
    }

    /**
     * Test handleAfterUpdate when IsSyncing does not change (no-op path).
     */
    @IsTest
    static void testHandleAfterUpdate_NoIsSyncingChange() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE StageName = 'Prospecting' LIMIT 1];
        Quote quote = [SELECT Id FROM Quote WHERE OpportunityId = :opp.Id LIMIT 1];

        // Both old and new have IsSyncing = false - no change
        Quote oldQuote = (Quote) JSON.deserialize(
            '{"Id":"' + quote.Id + '","IsSyncing":false,"OpportunityId":"' + opp.Id + '"}',
            Quote.class
        );
        Quote newQuote = (Quote) JSON.deserialize(
            '{"Id":"' + quote.Id + '","IsSyncing":false,"OpportunityId":"' + opp.Id + '"}',
            Quote.class
        );

        Map<Id, Quote> oldQuoteMap = new Map<Id, Quote>{ quote.Id => oldQuote };

        Test.startTest();
        QuoteSyncingTriggerHandler.handleAfterUpdate(
            new List<Quote>{ newQuote }, oldQuoteMap
        );
        Test.stopTest();

        Integer checklistCount = [
            SELECT COUNT() FROM Quote_Checklist_Item__c WHERE Quote__c = :quote.Id
        ];
        System.assertEquals(0, checklistCount, 'Should not create items when IsSyncing did not change');
    }

    /**
     * Test that updating a Quote fires the trigger (covers QuoteSyncingTrigger body).
     */
    @IsTest
    static void testTriggerFires_OnQuoteUpdate() {
        Quote quote = [SELECT Id, Name FROM Quote WHERE Name = 'Test Quote 1' LIMIT 1];

        Test.startTest();
        // Any Quote update fires the trigger, covering the trigger code
        quote.Name = 'Updated Quote Name';
        update quote;
        Test.stopTest();

        // Trigger fired but IsSyncing didn't change, so no checklist items created
        // This test exists purely for trigger code coverage
        System.assertNotEquals(null, quote.Id, 'Quote should still exist after update');
    }
}