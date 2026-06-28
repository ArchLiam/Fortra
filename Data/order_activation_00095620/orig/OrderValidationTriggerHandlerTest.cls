@isTest
private class OrderValidationTriggerHandlerTest {

    @testSetup
    static void setupTestData() {
        // Create test Account (required for Order creation)
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create test Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Create test Quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = opp.Id
        );
        insert testQuote;

        // Create checklist items for the Quote
        List<Quote_Checklist_Item__c> items = new List<Quote_Checklist_Item__c>();
        items.add(new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Customer Credit Check',
            Sort_Order__c = 1,
            Is_Checked__c = false
        ));
        items.add(new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Final Approval',
            Sort_Order__c = 2,
            Is_Checked__c = false
        ));
        insert items;
    }

    @isTest
    static void testOrderCreation_ChecklistIncomplete_ShouldFail() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Order testOrder = new Order(
            QuoteId = testQuote.Id,
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(testOrder, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Order creation should fail with incomplete checklist');
        System.assert(result.getErrors()[0].getMessage().contains('incomplete'),
            'Error message should mention incomplete items');
    }

    @isTest
    static void testOrderCreation_ChecklistComplete_ShouldSucceed() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<Quote_Checklist_Item__c> items = [
            SELECT Id
            FROM Quote_Checklist_Item__c
            WHERE Quote__c = :testQuote.Id
        ];

        for (Quote_Checklist_Item__c item : items) {
            item.Is_Checked__c = true;
            item.Checked_By__c = UserInfo.getUserId();
            item.Checked_Date__c = System.now();
        }
        update items;

        Order testOrder = new Order(
            QuoteId = testQuote.Id,
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(testOrder, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Order creation should succeed with complete checklist');
        System.assertNotEquals(null, result.getId(), 'Order should be created');
    }

    @isTest
    static void testOrderCreation_NoQuote_ShouldSucceed() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Order testOrder = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(testOrder, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Order creation should succeed without Quote');
    }

    @isTest
    static void testOrderCreation_BypassValidation_ShouldSucceed() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Checklist is incomplete, but bypass is enabled (migration scenario)
        OrderValidationTriggerHandler.bypassValidation = true;

        Order testOrder = new Order(
            QuoteId = testQuote.Id,
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(testOrder, false);
        Test.stopTest();

        OrderValidationTriggerHandler.bypassValidation = false;
        System.assert(result.isSuccess(), 'Order creation should succeed when bypass is enabled');
    }

    @isTest
    static void testBulkOrderCreation_MixedChecklist() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Quote completeQuote = new Quote(
            Name = 'Complete Quote',
            OpportunityId = opp.Id
        );
        insert completeQuote;

        Quote_Checklist_Item__c completeItem = new Quote_Checklist_Item__c(
            Quote__c = completeQuote.Id,
            Item_Name__c = 'Item',
            Sort_Order__c = 1,
            Is_Checked__c = true,
            Checked_By__c = UserInfo.getUserId(),
            Checked_Date__c = System.now()
        );
        insert completeItem;

        Quote incompleteQuote = [SELECT Id FROM Quote WHERE Name = 'Test Quote' LIMIT 1];

        List<Order> orders = new List<Order>();
        orders.add(new Order(QuoteId = completeQuote.Id, AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today()));
        orders.add(new Order(QuoteId = incompleteQuote.Id, AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today()));

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(orders, false);
        Test.stopTest();

        System.assert(results[0].isSuccess(), 'Order with complete checklist should succeed');
        System.assert(!results[1].isSuccess(), 'Order with incomplete checklist should fail');
    }
}