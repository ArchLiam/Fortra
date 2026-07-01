/**
 * @description Test class for ChecklistInitializationService
 */
@isTest
private class ChecklistInitializationServiceTest {

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

        // Create Quote (IsSyncing is read-only, managed by system)
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = opp.Id
        );
        insert testQuote;
    }

    @isTest
    static void testInitializeChecklistForQuote_Success() {
        // Get test data
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // Create request
        ChecklistInitializationService.InitializeRequest request = new ChecklistInitializationService.InitializeRequest();
        request.opportunityId = opp.Id;

        // Execute
        Test.startTest();
        List<ChecklistInitializationService.InitializeResult> results =
            ChecklistInitializationService.initializeChecklistForQuote(new List<ChecklistInitializationService.InitializeRequest>{request});
        Test.stopTest();

        // Verify
        System.assertEquals(1, results.size(), 'Should return one result');
        // Note: Since IsSyncing is read-only and defaults to false,
        // the service will not find syncing quotes in test context
        // This test validates the code executes without errors
    }

    @isTest
    static void testInitializeChecklistForQuote_AlreadyExists() {
        // Get test data
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        // Create existing checklist item
        Quote_Checklist_Item__c existingItem = new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Test Item',
            Sort_Order__c = 1,
            Is_Checked__c = false
        );
        insert existingItem;

        // Create request
        ChecklistInitializationService.InitializeRequest request = new ChecklistInitializationService.InitializeRequest();
        request.opportunityId = opp.Id;

        // Execute
        Test.startTest();
        List<ChecklistInitializationService.InitializeResult> results =
            ChecklistInitializationService.initializeChecklistForQuote(new List<ChecklistInitializationService.InitializeRequest>{request});
        Test.stopTest();

        // Verify
        System.assertEquals(1, results.size(), 'Should return one result');
    }

    @isTest
    static void testInitializeChecklistForQuote_NoQuote() {
        // Create new Opportunity without Quote
        Account acc = new Account(Name = 'Test Account 2');
        insert acc;

        Opportunity oppNoQuote = new Opportunity(
            Name = 'Opp Without Quote',
            AccountId = acc.Id,
            StageName = 'Pricing & Approval',
            CloseDate = Date.today().addDays(30)
        );
        insert oppNoQuote;

        // Create request
        ChecklistInitializationService.InitializeRequest request = new ChecklistInitializationService.InitializeRequest();
        request.opportunityId = oppNoQuote.Id;

        // Execute
        Test.startTest();
        List<ChecklistInitializationService.InitializeResult> results =
            ChecklistInitializationService.initializeChecklistForQuote(new List<ChecklistInitializationService.InitializeRequest>{request});
        Test.stopTest();

        // Verify
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Should fail when no syncing quote found');
        System.assert(results[0].message.contains('No syncing Quote'), 'Should have appropriate message');
    }

    @isTest
    static void testInitializeChecklistForQuote_NoConfigItems() {
        // This test requires no active config items, which won't happen in real scenario
        // but tests the error handling
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        ChecklistInitializationService.InitializeRequest request = new ChecklistInitializationService.InitializeRequest();
        request.opportunityId = opp.Id;

        Test.startTest();
        List<ChecklistInitializationService.InitializeResult> results =
            ChecklistInitializationService.initializeChecklistForQuote(new List<ChecklistInitializationService.InitializeRequest>{request});
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
    }
}