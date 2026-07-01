/**
 * @description Test class for InitializeChecklistAction quick action
 */
@isTest
private class InitializeChecklistActionTest {

    @testSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Order Processing',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = opp.Id
        );
        insert testQuote;
    }

    @isTest
    static void testInitializeFromAction_Success() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        InitializeChecklistAction.initializeFromAction(new List<Id>{ opp.Id });
        Test.stopTest();

        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        Integer checklistCount = [
            SELECT COUNT() FROM Quote_Checklist_Item__c WHERE Quote__c = :testQuote.Id
        ];
        System.assert(checklistCount > 0, 'Checklist items should be created via quick action');
    }

    @isTest
    static void testInitializeFromAction_MultipleOpportunities() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Opportunity opp2 = new Opportunity(
            Name = 'Test Opportunity 2',
            AccountId = acc.Id,
            StageName = 'Order Processing',
            CloseDate = Date.today().addDays(30)
        );
        insert opp2;

        Quote quote2 = new Quote(
            Name = 'Test Quote 2',
            OpportunityId = opp2.Id
        );
        insert quote2;

        List<Id> oppIds = new List<Id>();
        for (Opportunity o : [SELECT Id FROM Opportunity]) {
            oppIds.add(o.Id);
        }

        Test.startTest();
        InitializeChecklistAction.initializeFromAction(oppIds);
        Test.stopTest();

        Integer totalChecklistCount = [SELECT COUNT() FROM Quote_Checklist_Item__c];
        System.assert(totalChecklistCount > 0, 'Checklist items should be created for multiple opportunities');
    }
}