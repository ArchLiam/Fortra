/**
 * @description Test class for ChecklistValidationService
 */
@isTest
private class ChecklistValidationServiceTest {

    @testSetup
    static void setup() {
        // Create test Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create test Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Pricing & Approval',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Create Quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = opp.Id
        );
        insert testQuote;

        // Create checklist items
        List<Quote_Checklist_Item__c> items = new List<Quote_Checklist_Item__c>();
        items.add(new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Item 1',
            Sort_Order__c = 1,
            Is_Checked__c = true
        ));
        items.add(new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Item 2',
            Sort_Order__c = 2,
            Is_Checked__c = false
        ));
        items.add(new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Item 3',
            Sort_Order__c = 3,
            Is_Checked__c = false
        ));
        insert items;
    }

    @isTest
    static void testValidateChecklistComplete_Incomplete() {
        // Get test quote
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        // Create request
        ChecklistValidationService.ValidationRequest request = new ChecklistValidationService.ValidationRequest();
        request.quoteId = testQuote.Id;

        // Execute
        Test.startTest();
        List<ChecklistValidationService.ValidationResult> results =
            ChecklistValidationService.validateChecklistComplete(new List<ChecklistValidationService.ValidationRequest>{request});
        Test.stopTest();

        // Verify
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].isComplete, 'Checklist should be incomplete');
        System.assertEquals(3, results[0].totalItems, 'Should have 3 total items');
        System.assertEquals(1, results[0].completedItems, 'Should have 1 completed item');
        System.assertEquals(2, results[0].incompleteItems.size(), 'Should have 2 incomplete items');
        System.assert(results[0].errorMessage.contains('Cannot convert Quote to Order'), 'Should have error message');
        System.assert(results[0].errorMessage.contains('Item 2'), 'Should list Item 2 as incomplete');
        System.assert(results[0].errorMessage.contains('Item 3'), 'Should list Item 3 as incomplete');
    }

    @isTest
    static void testValidateChecklistComplete_Complete() {
        // Get test quote and items
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        List<Quote_Checklist_Item__c> items = [SELECT Id FROM Quote_Checklist_Item__c WHERE Quote__c = :testQuote.Id];

        // Check all items
        for (Quote_Checklist_Item__c item : items) {
            item.Is_Checked__c = true;
        }
        update items;

        // Create request
        ChecklistValidationService.ValidationRequest request = new ChecklistValidationService.ValidationRequest();
        request.quoteId = testQuote.Id;

        // Execute
        Test.startTest();
        List<ChecklistValidationService.ValidationResult> results =
            ChecklistValidationService.validateChecklistComplete(new List<ChecklistValidationService.ValidationRequest>{request});
        Test.stopTest();

        // Verify
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].isComplete, 'Checklist should be complete');
        System.assertEquals(3, results[0].totalItems, 'Should have 3 total items');
        System.assertEquals(3, results[0].completedItems, 'Should have 3 completed items');
        System.assertEquals(0, results[0].incompleteItems.size(), 'Should have 0 incomplete items');
    }

    @isTest
    static void testValidateChecklistComplete_NoItems() {
        // Create new Quote without checklist items
        Account acc = new Account(Name = 'Test Account 2');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity 2',
            AccountId = acc.Id,
            StageName = 'Pricing & Approval',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quoteNoItems = new Quote(
            Name = 'Quote Without Items',
            OpportunityId = opp.Id
        );
        insert quoteNoItems;

        // Create request
        ChecklistValidationService.ValidationRequest request = new ChecklistValidationService.ValidationRequest();
        request.quoteId = quoteNoItems.Id;

        // Execute
        Test.startTest();
        List<ChecklistValidationService.ValidationResult> results =
            ChecklistValidationService.validateChecklistComplete(new List<ChecklistValidationService.ValidationRequest>{request});
        Test.stopTest();

        // Verify
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].isComplete, 'Should be incomplete');
        System.assert(results[0].errorMessage.contains('No checklist items found'), 'Should have appropriate error message');
    }

    @isTest
    static void testValidateChecklistComplete_MultipleRequests() {
        // Get test quote
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        // Create multiple requests (same quote for simplicity)
        List<ChecklistValidationService.ValidationRequest> requests = new List<ChecklistValidationService.ValidationRequest>();
        for (Integer i = 0; i < 3; i++) {
            ChecklistValidationService.ValidationRequest request = new ChecklistValidationService.ValidationRequest();
            request.quoteId = testQuote.Id;
            requests.add(request);
        }

        // Execute
        Test.startTest();
        List<ChecklistValidationService.ValidationResult> results =
            ChecklistValidationService.validateChecklistComplete(requests);
        Test.stopTest();

        // Verify
        System.assertEquals(3, results.size(), 'Should return three results');
        for (ChecklistValidationService.ValidationResult result : results) {
            System.assertEquals(false, result.isComplete, 'All should be incomplete');
        }
    }
}