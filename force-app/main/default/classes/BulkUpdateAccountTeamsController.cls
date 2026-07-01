public with sharing class BulkUpdateAccountTeamsController {

	// Invocable method to trigger bulk update of Account Teams
	@InvocableMethod(label='Bulk Update Account Teams via Batch')
	public static void invokeBulkUpdateAccountTeams(List<Id> accountIds) {
		if(accountIds.size() == 0) {
			return;
		} else if (accountIds.size() < 100) {
			startBulkUpdateAccountTeams(accountIds);
		} else {
			startBatchUpdateAccountTeams(accountIds);
		}
	}

	// Retrieve Accounts with their Team Member Counts
	@AuraEnabled(cacheable=true)
    public static List<AccountWrapper> getAccountsWithTeamMemberCount(List<Id> accountIds) {
        List<AccountWrapper> results = new List<AccountWrapper>();
        List<Account> accounts = [
            SELECT Id, Name, Industry, (SELECT Id FROM AccountTeamMembers)
            FROM Account
			WHERE Id IN :accountIds
        ];

        for (Account acc : accounts) {
            Integer count = 0;
            if (acc.AccountTeamMembers != null) {
                count = acc.AccountTeamMembers.size();
            }
            results.add(new AccountWrapper(acc, count));
        }

        return results;
    }

	// Run bulk update synchronously (100 or fewer)
	@AuraEnabled
	public static List<BulkUpdateAccountTeamsResult> startBulkUpdateAccountTeams(List<Id> accountIds) {
		if(accountIds.size() == 0) {
			return new List<BulkUpdateAccountTeamsResult>();
		} else { // Generally 100 records or less
			List<Account> accounts = [SELECT Id FROM Account WHERE Id IN :accountIds];
			return bulkInvokeFlow(accounts);
		}
	}

	// Run bulk update via batch (more than 100)
	@AuraEnabled
	public static String startBatchUpdateAccountTeams(List<Id> accountIds) {
		if(accountIds.size() == 0) {
			return null;
		} else {
			Set<Id> accountIdSet = new Set<Id>(accountIds);
			BulkUpdateAccountTeamsBatch atmBatch = new BulkUpdateAccountTeamsBatch();
			atmBatch.accountIds = accountIdSet;
			String jobId = Database.executeBatch(atmBatch, 200); // Change this number to control the batch size
			jobId = jobId.left(15);
			return jobId;
		}
	}

	// Poll the status of a batch job
	@AuraEnabled
	public static String checkBatchStatus(String jobId) {
		AsyncApexJob job = [SELECT Status, JobItemsProcessed, TotalJobItems FROM AsyncApexJob WHERE Id = :jobId];
		
		if (job.Status == 'Completed') {
			return getResultsFromCache(jobId); 
		}
		return job.Status;
	}

	// Retrieve results from Cache and clear the cache entry
	@AuraEnabled
    public static String getResultsFromCache(String jobId) {
        String cachedData = (String) Cache.Org.get(jobId);
        if (cachedData != null) {
            Cache.Org.remove(jobId);
            return cachedData;
        }
		return null;
    }

	// Core method to invoke the Flow for a list of Accounts
    public static List<BulkUpdateAccountTeamsResult> bulkInvokeFlow(List<Account> accounts) {
		List<Map<String, Object>> flowInputs = new List<Map<String, Object>>();

		for (Account acc : accounts) {
			Map<String, Object> inputParams = new Map<String, Object>();
			inputParams.put('accountRecordId', (String) acc.Id);
			flowInputs.add(inputParams);
		}

		Invocable.Action action = Invocable.Action.createCustomAction('flow', 'Subflow_Account_Team_Member_Assignment');
		action.setInvocations(flowInputs);

		List<Invocable.Action.Result> results = action.invoke();

		List<BulkUpdateAccountTeamsResult> resultWrappers = new List<BulkUpdateAccountTeamsResult>();
		for (Integer i = 0; i < results.size(); i++) {
			BulkUpdateAccountTeamsResult resultWrapper = new BulkUpdateAccountTeamsResult();
			resultWrapper.accountId = (String) results[i].getInvocationParameters().get('accountRecordId');
			resultWrapper.status = (String) results[i].getOutputParameters().get('Flow__InterviewStatus');
			List<Object> outputATMs = (List<Object>) results[i].getOutputParameters().get('AccountTeamMemberCollection');
			// resultWrapper.accountTeamMembers = (outputATMs.size() > 0) ? (List<AccountTeamMember>) outputATMs : new List<AccountTeamMember>();
			resultWrapper.accountTeamMemberCount = outputATMs.size();
			resultWrappers.add(resultWrapper);
			
			if (results[i].isSuccess()) {
				System.debug('Success: ' + results[i].getAction());					// apiVersion, invocations, invokeFromLightningComponent, name
				System.debug('Success: ' + results[i].getInvocationParameters());	// accountRecordId
				System.debug('Success: ' + results[i].getOutputParameters());		// AccountTeamMemberCollection, Flow__InterviewGuid, Flow__InterviewStatus
			} else{
				System.debug('Error: ' + results[i].getErrors()[0].getMessage());
			}
		}

		return resultWrappers;
	}

	// Wrapper class for Flow invocation results
	public class BulkUpdateAccountTeamsResult {
		@AuraEnabled public String status;
		@AuraEnabled public String accountId;
		@AuraEnabled public Integer accountTeamMemberCount;
		@AuraEnabled public List<AccountTeamMember> accountTeamMembers;
	}

	// Wrapper class for Account with Team Member Count
	public class AccountWrapper {
        @AuraEnabled public Account account;
        @AuraEnabled public Integer teamMemberCount;

        public AccountWrapper(Account acc, Integer count) {
            this.account = acc;
            this.teamMemberCount = count;
        }
    }
}