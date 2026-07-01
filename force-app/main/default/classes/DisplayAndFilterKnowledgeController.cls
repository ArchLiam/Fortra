public with sharing class DisplayAndFilterKnowledgeController {
    @AuraEnabled(cacheable=true)
	public static List<Knowledge__kav> getKnowledgeArticles() {
		String sObjectName = 'Knowledge__kav';
		Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(sObjectName);
		Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
		Map<String, Schema.SObjectField> fieldsMap = describeResult.fields.getMap();
		List<String> fieldNames = new List<String>();
		for (String fieldName : fieldsMap.keySet()) {
			if (fieldsMap.get(fieldName).getDescribe().isAccessible()) {
				fieldNames.add(fieldName);
			}
		}
		String query = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + sObjectName;
		query += ' WHERE PublishStatus = \'Online\'';

		List<Knowledge__kav> knowledgeArticles = Database.query(query);

		return knowledgeArticles;
	}
}