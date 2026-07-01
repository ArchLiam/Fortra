@IsTest
public class AssetMigrationQueueClearHandlerTest {

    @IsTest
    static void testHandleAfterInsert_NullSet_NoOp() {
        Test.startTest();
        AssetMigrationQueueClearHandler.handleAfterInsert(null);
        Test.stopTest();
    }

    @IsTest
    static void testHandleAfterInsert_EmptySet_NoOp() {
        Test.startTest();
        AssetMigrationQueueClearHandler.handleAfterInsert(new Set<Id>());
        Test.stopTest();
    }

    @IsTest
    static void testHandleAfterInsert_NonExistentAssetIds_NoOp() {
        // Provide fake Asset Ids — the SOQL on AssetActionSource will return
        // nothing, the handler returns early without modifying anything.
        Set<Id> fakeIds = new Set<Id>{ '02iWC000000000000A' };

        // Pre-create a run log with a queued detail row to confirm it stays queued.
        Migration_Run_Log__c log = new Migration_Run_Log__c(
            Run_Date__c = Datetime.now(), Status__c = 'Completed');
        insert log;
        Migration_Run_Detail__c d = new Migration_Run_Detail__c(
            Run_Log__c = log.Id, Category__c = 'NoAccountId', Severity__c = 'Skip',
            Quote_Number__c = 'TEST-001',
            Reason__c = 'preserved', Cleanup_Required__c = false,
            In_Rerun_Queue__c = true);
        insert d;

        Test.startTest();
        AssetMigrationQueueClearHandler.handleAfterInsert(fakeIds);
        Test.stopTest();

        Migration_Run_Detail__c reloaded = [
            SELECT In_Rerun_Queue__c FROM Migration_Run_Detail__c WHERE Id = :d.Id];
        System.assertEquals(true, reloaded.In_Rerun_Queue__c,
            'Unrelated queued row should remain queued');
    }
}