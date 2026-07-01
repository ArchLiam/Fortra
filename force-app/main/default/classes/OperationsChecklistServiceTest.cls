/**
 * @description Test class for OperationsChecklistService CRUD operations
 */
@isTest
private class OperationsChecklistServiceTest {

    @testSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Pricing & Approval',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = opp.Id
        );
        insert testQuote;

        // Create checklist items for the Quote
        List<Quote_Checklist_Item__c> items = new List<Quote_Checklist_Item__c>();
        items.add(new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Contract Signed',
            Sort_Order__c = 1,
            Is_Checked__c = false
        ));
        items.add(new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Payment Terms',
            Sort_Order__c = 2,
            Is_Checked__c = false
        ));
        items.add(new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Legal Entity',
            Sort_Order__c = 3,
            Is_Checked__c = true,
            Checked_By__c = UserInfo.getUserId(),
            Checked_Date__c = DateTime.now()
        ));
        insert items;
    }

    @isTest
    static void testGetChecklistItems_ReturnsItems() {
        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Test Quote' LIMIT 1];

        Test.startTest();
        List<Quote_Checklist_Item__c> items = OperationsChecklistService.getChecklistItems(testQuote.Id);
        Test.stopTest();

        System.assertEquals(3, items.size(), 'Should return 3 checklist items');
        System.assertEquals('Contract Signed', items[0].Item_Name__c, 'First item should be Contract Signed (sort order 1)');
        System.assertEquals('Payment Terms', items[1].Item_Name__c, 'Second item should be Payment Terms (sort order 2)');
        System.assertEquals('Legal Entity', items[2].Item_Name__c, 'Third item should be Legal Entity (sort order 3)');
    }

    @isTest
    static void testGetChecklistItems_NoItems() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp2 = new Opportunity(
            Name = 'Empty Opp',
            AccountId = acc.Id,
            StageName = 'Pricing & Approval',
            CloseDate = Date.today().addDays(30)
        );
        insert opp2;

        Quote emptyQuote = new Quote(
            Name = 'Empty Quote',
            OpportunityId = opp2.Id
        );
        insert emptyQuote;

        Test.startTest();
        List<Quote_Checklist_Item__c> items = OperationsChecklistService.getChecklistItems(emptyQuote.Id);
        Test.stopTest();

        System.assertEquals(0, items.size(), 'Should return no checklist items');
    }

    @isTest
    static void testUpdateChecklistItem_CheckItem() {
        Quote_Checklist_Item__c uncheckedItem = [
            SELECT Id FROM Quote_Checklist_Item__c
            WHERE Item_Name__c = 'Contract Signed' LIMIT 1
        ];

        Test.startTest();
        Quote_Checklist_Item__c updated = OperationsChecklistService.updateChecklistItem(
            uncheckedItem.Id, true, 'Verified with legal team'
        );
        Test.stopTest();

        System.assertEquals(true, updated.Is_Checked__c, 'Item should be checked');
        System.assertEquals(UserInfo.getUserId(), updated.Checked_By__c, 'Checked_By should be current user');
        System.assertNotEquals(null, updated.Checked_Date__c, 'Checked_Date should be set');
        System.assertEquals('Verified with legal team', updated.Notes__c, 'Notes should be set');
    }

    @isTest
    static void testUpdateChecklistItem_UncheckItem() {
        Quote_Checklist_Item__c checkedItem = [
            SELECT Id FROM Quote_Checklist_Item__c
            WHERE Item_Name__c = 'Legal Entity' LIMIT 1
        ];

        Test.startTest();
        Quote_Checklist_Item__c updated = OperationsChecklistService.updateChecklistItem(
            checkedItem.Id, false, null
        );
        Test.stopTest();

        System.assertEquals(false, updated.Is_Checked__c, 'Item should be unchecked');
        System.assertEquals(null, updated.Checked_By__c, 'Checked_By should be cleared');
        System.assertEquals(null, updated.Checked_Date__c, 'Checked_Date should be cleared');
    }

    @isTest
    static void testUpdateChecklistItemNotes() {
        Quote_Checklist_Item__c item = [
            SELECT Id FROM Quote_Checklist_Item__c
            WHERE Item_Name__c = 'Payment Terms' LIMIT 1
        ];

        Test.startTest();
        Quote_Checklist_Item__c updated = OperationsChecklistService.updateChecklistItemNotes(
            item.Id, 'Net 30 confirmed by finance'
        );
        Test.stopTest();

        System.assertEquals('Net 30 confirmed by finance', updated.Notes__c, 'Notes should be updated');
    }

    @isTest
    static void testUpdateChecklistItem_WithNotes() {
        Quote_Checklist_Item__c item = [
            SELECT Id FROM Quote_Checklist_Item__c
            WHERE Item_Name__c = 'Payment Terms' LIMIT 1
        ];

        Test.startTest();
        Quote_Checklist_Item__c updated = OperationsChecklistService.updateChecklistItem(
            item.Id, true, 'Net 30 - approved by CFO'
        );
        Test.stopTest();

        System.assertEquals(true, updated.Is_Checked__c, 'Item should be checked');
        System.assertEquals('Net 30 - approved by CFO', updated.Notes__c, 'Notes should be updated');
        System.assertEquals(UserInfo.getUserId(), updated.Checked_By__c, 'Checked_By should be set');
    }
}