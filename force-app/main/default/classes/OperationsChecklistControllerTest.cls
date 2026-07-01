/**
 * @description Test class for OperationsChecklistController
 */
@isTest
private class OperationsChecklistControllerTest {

    @testSetup
    static void setup() {
        // Create test data
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Order Processing',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Test Quote',
            OpportunityId = opp.Id
        );
        insert quote;

        // Create checklist items
        List<Quote_Checklist_Item__c> items = new List<Quote_Checklist_Item__c>();
        items.add(new Quote_Checklist_Item__c(
            Quote__c = quote.Id,
            Item_Name__c = 'Item 1',
            Sort_Order__c = 1,
            Is_Checked__c = true,
            Checked_By__c = UserInfo.getUserId(),
            Checked_Date__c = DateTime.now(),
            Notes__c = 'Test notes 1'
        ));
        items.add(new Quote_Checklist_Item__c(
            Quote__c = quote.Id,
            Item_Name__c = 'Item 2',
            Sort_Order__c = 2,
            Is_Checked__c = false
        ));
        items.add(new Quote_Checklist_Item__c(
            Quote__c = quote.Id,
            Item_Name__c = 'Item 3',
            Sort_Order__c = 3,
            Is_Checked__c = false
        ));
        insert items;
    }

    @isTest
    static void testGetChecklistItems_Success() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        OperationsChecklistController.ChecklistData data =
            OperationsChecklistController.getChecklistItems(quote.Id);
        Test.stopTest();

        // Verify results
        System.assertEquals(3, data.totalItems, 'Should have 3 total items');
        System.assertEquals(1, data.completedItems, 'Should have 1 completed item');
        System.assertEquals(33, data.completionPercentage, 'Completion percentage should be 33%');
        System.assertEquals(3, data.items.size(), 'Should return 3 items');

        // Verify items are sorted by Sort_Order
        System.assertEquals('Item 1', data.items[0].Item_Name__c, 'First item should be Item 1');
        System.assertEquals('Item 2', data.items[1].Item_Name__c, 'Second item should be Item 2');
        System.assertEquals('Item 3', data.items[2].Item_Name__c, 'Third item should be Item 3');

        // Verify checked item details
        System.assertEquals(true, data.items[0].Is_Checked__c, 'Item 1 should be checked');
        System.assertNotEquals(null, data.items[0].Checked_By__c, 'Item 1 should have Checked_By populated');
        System.assertNotEquals(null, data.items[0].Checked_Date__c, 'Item 1 should have Checked_Date populated');
    }

    @isTest
    static void testGetChecklistItems_NoItems() {
        // Create quote with no checklist items
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity 2',
            AccountId = acc.Id,
            StageName = 'Order Processing',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Test Quote 2',
            OpportunityId = opp.Id
        );
        insert quote;

        Test.startTest();
        OperationsChecklistController.ChecklistData data =
            OperationsChecklistController.getChecklistItems(quote.Id);
        Test.stopTest();

        // Verify results
        System.assertEquals(0, data.totalItems, 'Should have 0 total items');
        System.assertEquals(0, data.completedItems, 'Should have 0 completed items');
        System.assertEquals(0, data.completionPercentage, 'Completion percentage should be 0%');
        System.assertEquals(0, data.items.size(), 'Should return 0 items');
    }

    @isTest
    static void testUpdateChecklistItem_CheckItem() {
        Quote_Checklist_Item__c item = [
            SELECT Id
            FROM Quote_Checklist_Item__c
            WHERE Item_Name__c = 'Item 2'
            LIMIT 1
        ];

        Test.startTest();
        OperationsChecklistController.ChecklistItem result =
            OperationsChecklistController.updateChecklistItem(item.Id, true, 'Updated notes');
        Test.stopTest();

        // Verify results
        System.assertEquals(true, result.isChecked, 'Item should be checked');
        System.assertEquals('Updated notes', result.notes, 'Notes should be updated');
        System.assertNotEquals(null, result.checkedBy, 'Checked_By should be populated');
        System.assertNotEquals(null, result.checkedByName, 'Checked_By name should be populated');
        System.assertNotEquals(null, result.checkedDate, 'Checked_Date should be populated');

        // Verify in database
        Quote_Checklist_Item__c updatedItem = [
            SELECT Is_Checked__c, Checked_By__c, Checked_Date__c, Notes__c
            FROM Quote_Checklist_Item__c
            WHERE Id = :item.Id
        ];
        System.assertEquals(true, updatedItem.Is_Checked__c, 'Item should be checked in database');
        System.assertEquals(UserInfo.getUserId(), updatedItem.Checked_By__c, 'Checked_By should be current user');
        System.assertEquals('Updated notes', updatedItem.Notes__c, 'Notes should be updated in database');
    }

    @isTest
    static void testUpdateChecklistItem_UncheckItem() {
        Quote_Checklist_Item__c item = [
            SELECT Id
            FROM Quote_Checklist_Item__c
            WHERE Item_Name__c = 'Item 1'
            LIMIT 1
        ];

        Test.startTest();
        OperationsChecklistController.ChecklistItem result =
            OperationsChecklistController.updateChecklistItem(item.Id, false, null);
        Test.stopTest();

        // Verify results
        System.assertEquals(false, result.isChecked, 'Item should be unchecked');
        System.assertEquals(null, result.checkedBy, 'Checked_By should be null');
        System.assertEquals(null, result.checkedByName, 'Checked_By name should be null');
        System.assertEquals(null, result.checkedDate, 'Checked_Date should be null');

        // Verify in database
        Quote_Checklist_Item__c updatedItem = [
            SELECT Is_Checked__c, Checked_By__c, Checked_Date__c
            FROM Quote_Checklist_Item__c
            WHERE Id = :item.Id
        ];
        System.assertEquals(false, updatedItem.Is_Checked__c, 'Item should be unchecked in database');
        System.assertEquals(null, updatedItem.Checked_By__c, 'Checked_By should be null in database');
        System.assertEquals(null, updatedItem.Checked_Date__c, 'Checked_Date should be null in database');
    }

    @isTest
    static void testUpdateChecklistItem_InvalidId() {
        // Use a fake ID to trigger an exception path
        Id fakeId = 'a00000000000000000';

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            OperationsChecklistController.updateChecklistItem(fakeId, true, 'Test');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // AuraHandledException.getMessage() returns 'Script-thrown exception' in test context
            // so we just verify the exception was thrown
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should be thrown for invalid ID');
    }

    @isTest
    static void testHasCustomPermission() {
        Test.startTest();
        Boolean hasPermission = OperationsChecklistController.hasCustomPermission();
        Test.stopTest();

        // Note: In test context without permission set assigned, this will be false
        // In real usage, users with the permission set will return true
        System.assertNotEquals(null, hasPermission, 'Permission check should return a value');
    }

    @isTest
    static void testGetChecklistItems_AllComplete() {
        // Check all items
        List<Quote_Checklist_Item__c> items = [
            SELECT Id
            FROM Quote_Checklist_Item__c
        ];

        for (Quote_Checklist_Item__c item : items) {
            item.Is_Checked__c = true;
            item.Checked_By__c = UserInfo.getUserId();
            item.Checked_Date__c = DateTime.now();
        }
        update items;

        Quote quote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        OperationsChecklistController.ChecklistData data =
            OperationsChecklistController.getChecklistItems(quote.Id);
        Test.stopTest();

        // Verify results
        System.assertEquals(3, data.totalItems, 'Should have 3 total items');
        System.assertEquals(3, data.completedItems, 'Should have 3 completed items');
        System.assertEquals(100, data.completionPercentage, 'Completion percentage should be 100%');
    }
}