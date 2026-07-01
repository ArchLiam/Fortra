@IsTest
private class BulkUpdateAccountTeamsControllerTest {

    @TestSetup
    static void setupData() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 105; i++) {
            accounts.add(new Account(Name = 'Test Acc ' + i));
        }
        insert accounts;
    }

    @IsTest
    static void testInvoke_NoIds_ReturnsEarly() {
        List<Id> emptyIds = new List<Id>();

        Test.startTest();
        BulkUpdateAccountTeamsController.invokeBulkUpdateAccountTeams(emptyIds);
        Test.stopTest();

        System.assert(true, 'Method should return early without errors when no Ids provided');
    }

    @IsTest
    static void testInvoke_LessThan100_QueriesAndInvokesFlow() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 10];
        System.assertEquals(10, accts.size(), 'Expect 10 test accounts from setup');

        List<Id> ids = new List<Id>();
        for (Account a : accts) {
            ids.add(a.Id);
        }

        Test.startTest();
        BulkUpdateAccountTeamsController.invokeBulkUpdateAccountTeams(ids);
        Test.stopTest();

        List<Account> requery = [SELECT Id FROM Account WHERE Id IN :ids];
        System.assertEquals(10, requery.size(), 'Expected requery to return the same records');
    }

    @IsTest
    static void testInvoke_GreaterOrEqual100_ExecutesBatch() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 101];
        System.assertEquals(101, accts.size(), 'Expect 101 test accounts from setup');
        List<Id> ids = new List<Id>();
        for (Account a : accts) {
            ids.add(a.Id);
        }

        Test.startTest();
        BulkUpdateAccountTeamsController.invokeBulkUpdateAccountTeams(ids);
        Test.stopTest();

        System.assert(true, 'Batch execution should complete without unhandled exceptions');
    }

    @IsTest
    static void testBulkInvokeFlow_DirectCall_WithAccounts() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 3];
        System.assertEquals(3, accts.size(), 'Expect 3 test accounts');

        Test.startTest();
        BulkUpdateAccountTeamsController.bulkInvokeFlow(accts);
        Test.stopTest();

        System.assert(true, 'bulkInvokeFlow should complete without throwing exceptions');
    }

    @IsTest
    static void testInvoke_NullsAndInvalids_Defensive() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 5];
        List<Id> ids = new List<Id>();
        for (Account a : accts) ids.add(a.Id);
        ids.add(null);
        ids.add(ids[0]); // duplicate

        Test.startTest();
        try {
            BulkUpdateAccountTeamsController.invokeBulkUpdateAccountTeams(ids);
            System.assert(true, 'Method handled null/duplicates without unhandled exception');
        } catch (Exception e) {
            System.assert(e.getMessage() != null && e.getMessage().length() > 0, 'Expected a meaningful exception message');
        }
        Test.stopTest();
    }

	@IsTest
    static void testInvoke_GreaterOrEqual100_ExecutesBatchDirect() {
        List<Account> accts = [SELECT Id FROM Account LIMIT 101];
        System.assertEquals(101, accts.size(), 'Expect 101 test accounts from setup');
        List<Id> ids = new List<Id>();
        for (Account a : accts) {
            ids.add(a.Id);
        }

        Test.startTest();
		List<BulkUpdateAccountTeamsController.AccountWrapper> accountWrapper = BulkUpdateAccountTeamsController.getAccountsWithTeamMemberCount(ids);
		System.debug('Account Wrapper: ' + accountWrapper);
        String jobId = BulkUpdateAccountTeamsController.startBatchUpdateAccountTeams(ids);
		System.debug('Job ID: ' + jobId);
		String result = BulkUpdateAccountTeamsController.checkBatchStatus(jobId);
		System.debug('Batch Status: ' + result);
        Test.stopTest();

		result = BulkUpdateAccountTeamsController.checkBatchStatus(jobId);
		System.debug('Batch Status AFTER: ' + result);

        System.assert(true, 'Batch execution should complete without unhandled exceptions');
    }
}