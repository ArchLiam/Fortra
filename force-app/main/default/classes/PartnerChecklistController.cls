public with sharing class PartnerChecklistController {

	@AuraEnabled
    public static void updateChecklistItems(List<Partner_Checklist_Item__c> items) {
        try {
			System.debug('updateChecklistItems: ' + items);
            upsert items Duplicate_Identifier__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error upserting records: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Partner_Checklist_Item__c> getChecklistItems() {
		List<Partner_Checklist_Item__c> checklistItems = [
			SELECT Id, Name, Checklist_Item__c, Completed__c, Completion_Date__c, User__c, URL__c, Sort_Order__c, Duplicate_Identifier__c, Metadata_Developer_Name__c
			FROM Partner_Checklist_Item__c
			WHERE User__c = :UserInfo.getUserId()
			ORDER BY Sort_Order__c ASC
		];
		System.debug('getChecklistItems: ' + checklistItems);

		if(checklistItems.size() == 0) {
			checklistItems = new List<Partner_Checklist_Item__c>();
			for(Partner_Checklist_Definition__mdt templateItem : getChecklistTemplateItems()) {
				Partner_Checklist_Item__c newItem = new Partner_Checklist_Item__c(					
					Metadata_Developer_Name__c = templateItem.DeveloperName,
					Checklist_Item__c = templateItem.Display_Label__c,
					User__c = UserInfo.getUserId(),	
					Name = templateItem.Display_Label__c.left(80),
					Duplicate_Identifier__c = UserInfo.getUserId() + '_' + templateItem.DeveloperName.left(237),
					Sort_Order__c = templateItem.Sort_Order__c,
					URL__c = templateItem.URL__c,
					Completion_Date__c = null,
					Completed__c = false
				);
				checklistItems.add(newItem);
			}
		}

		return checklistItems;
    }

    public static List<Partner_Checklist_Definition__mdt> getChecklistTemplateItems() {
		Boolean isBasicPartnerUser = false;
		Boolean isMidTierPartnerUser = false;
		Boolean isTopTierPartnerUser = false;
		
		Profile userProfile = [SELECT Id, Name FROM Profile WHERE Id = :UserInfo.getProfileId()];
		switch on userProfile.Name {
			when 'Basic Partner User' {
				isBasicPartnerUser = true;
			}
			when 'Mid-Tier Partner User' {
				isMidTierPartnerUser = true;
				
			}
			when else {
				isTopTierPartnerUser = true;
			}
		}

		String query = 	'SELECT Id, DeveloperName, MasterLabel, Active__c, Basic_Partner_Users__c, Description__c, Display_Label__c, Mid_Tier_Partner_Users__c, Sort_Order__c, Top_Tier_Partner_Users__c, URL__c FROM Partner_Checklist_Definition__mdt';
		query += ' WHERE Active__c = true';
		if(isBasicPartnerUser) {
			query += ' AND Basic_Partner_Users__c = true';
		}
		else if(isMidTierPartnerUser) {
			query += ' AND Mid_Tier_Partner_Users__c = true';
		}
		else {
			query += ' AND Top_Tier_Partner_Users__c = true';
		}
		query += ' ORDER BY Sort_Order__c ASC';

		List<Partner_Checklist_Definition__mdt> checklistTemplateItems = database.query(query);
		System.debug('getChecklistTemplateItems: ' + checklistTemplateItems);
		return checklistTemplateItems;
    }
}