public with sharing class BulkUpdateAccountTeamsBatch implements Database.Batchable<SObject>, Database.Stateful {
	public Set<Id> accountIds = new Set<Id>();
	public List<BulkUpdateAccountTeamsController.BulkUpdateAccountTeamsResult> allResults = new List<BulkUpdateAccountTeamsController.BulkUpdateAccountTeamsResult>();

	public Database.QueryLocator start(Database.BatchableContext bc) {
		String query = 'SELECT Id FROM Account WHERE Id IN :accountIds';
		return Database.getQueryLocator(query);
	}
	
	public void execute(Database.BatchableContext bc, List<SObject> scope) {
		List<BulkUpdateAccountTeamsController.BulkUpdateAccountTeamsResult> results = BulkUpdateAccountTeamsController.bulkInvokeFlow((List<Account>) scope);
		allResults.addAll(results);
	}
	
	public void finish(Database.BatchableContext bc) {
		String cacheKey = bc.getJobId();
		cacheKey = cacheKey.left(15);
		Cache.Org.put(cacheKey, JSON.serialize(this.allResults), 300);
	}
}