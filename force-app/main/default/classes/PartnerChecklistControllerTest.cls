@IsTest
private class PartnerChecklistControllerTest {

    @TestSetup
    static void testSetup() {
        UserRole portalRole = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1];
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        User runningUser = new User(
            LastName = 'Admin',
            Alias = 'admin',
            Email = 'admin@test.com',
            Username = 'admin' + System.currentTimeMillis() + '@test.com',
            ProfileId = adminProfile.Id,
            UserRoleId = portalRole.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert runningUser;

        System.runAs(runningUser) {
            // Create a Partner Account
            Account partnerAcc = new Account(Name = 'Partner Success Corp');
            insert partnerAcc;

            // Create Contacts
            List<Contact> partnerContacts = new List<Contact>{
                new Contact(FirstName = 'Basic', LastName = 'User', AccountId = partnerAcc.Id, Email = 'basic@test.com'),
                new Contact(FirstName = 'Mid', LastName = 'User', AccountId = partnerAcc.Id, Email = 'mid@test.com'),
                new Contact(FirstName = 'Top', LastName = 'User', AccountId = partnerAcc.Id, Email = 'top@test.com')
            };
            insert partnerContacts;

            // Query Partner Profiles
            Map<String, Id> profileMap = new Map<String, Id>();
            List<String> profileNames = new List<String>{ 'Basic Partner User', 'Mid-Tier Partner User', 'Top-Tier Partner User' };
            for (Profile p : [SELECT Id, Name FROM Profile WHERE Name IN :profileNames]) {
                profileMap.put(p.Name, p.Id);
            }

            // Create Partner Users
            List<User> usersToInsert = new List<User>();
            usersToInsert.add(createPartnerUser(partnerContacts[0], profileMap.get('Basic Partner User'), 'basicp'));
            usersToInsert.add(createPartnerUser(partnerContacts[1], profileMap.get('Mid-Tier Partner User'), 'midp'));
            usersToInsert.add(createPartnerUser(partnerContacts[2], profileMap.get('Top-Tier Partner User'), 'topp'));

            insert usersToInsert;
        }
    }

	@IsTest
    static void testHappyPath() {
		User basic = [SELECT Id FROM User WHERE Profile.Name = 'Basic Partner User' AND IsActive = true ORDER BY CreatedDate DESC LIMIT 1];
		happyPathProcess(basic);
        User mid   = [SELECT Id FROM User WHERE Profile.Name = 'Mid-Tier Partner User' AND IsActive = true ORDER BY CreatedDate DESC LIMIT 1];
		happyPathProcess(mid);
        User top   = [SELECT Id FROM User WHERE Profile.Name = 'Top-Tier Partner User' AND IsActive = true ORDER BY CreatedDate DESC LIMIT 1];
		happyPathProcess(top);
	}

	@IsTest
    static void testDuplicatePrevention() {
		User basic = [SELECT Id FROM User WHERE Profile.Name = 'Basic Partner User' AND IsActive = true ORDER BY CreatedDate DESC LIMIT 1];
		happyPathProcess(basic);

		List<Partner_Checklist_Item__c> items = [
			SELECT Id, Name, Checklist_Item__c, Completed__c, Completion_Date__c, User__c, URL__c, Sort_Order__c, Duplicate_Identifier__c, Metadata_Developer_Name__c
			FROM Partner_Checklist_Item__c
			WHERE User__c = :basic.Id
			ORDER BY Sort_Order__c ASC
		];
		System.assertEquals(5, items.size(), 'Should have 5 checklist items for basic partner user.');

		Partner_Checklist_Item__c duplicateItem = new Partner_Checklist_Item__c(
			User__c = basic.Id,
			Checklist_Item__c = items[0].Checklist_Item__c,
			Name = items[0].Name,
			Sort_Order__c = items[0].Sort_Order__c,
			URL__c = items[0].URL__c,
			Completion_Date__c = Date.today(),
			Completed__c = true,
			Duplicate_Identifier__c = items[0].Duplicate_Identifier__c
		);
		PartnerChecklistController.updateChecklistItems(new List<Partner_Checklist_Item__c>{ duplicateItem });

		List<Partner_Checklist_Item__c> updatedItems = [SELECT Id FROM Partner_Checklist_Item__c WHERE User__c = :basic.Id];
		System.assertEquals(5, updatedItems.size(), 'Should still only have 5 checklist items for basic partner user.');
	}

	@IsTest
    static void testUnhappyPath() {
		User basicUser = [SELECT Id FROM User WHERE Profile.Name = 'Basic Partner User' AND IsActive = true ORDER BY CreatedDate DESC LIMIT 1];

        System.runAs(basicUser) {
            Partner_Checklist_Item__c badItem = new Partner_Checklist_Item__c(
                Name = 'Invalid - Exceeding the 80 character limit for this field - this is too long, over 80 characters for sure',
                User__c = basicUser.Id
            );

            Test.startTest();
            Boolean threw = false;
            try {
                PartnerChecklistController.updateChecklistItems(new List<Partner_Checklist_Item__c>{ badItem });
            } catch (AuraHandledException e) {
                threw = true;
            }
            Test.stopTest();

            System.assertEquals(true, threw, 'Exception path should be covered and throw AuraHandledException');
        }
    }

	private static User createPartnerUser(Contact c, Id profileId, String alias) {
        return new User(
            FirstName = c.FirstName,
            LastName = c.LastName,
            Email = c.Email,
            Username = c.Email + System.currentTimeMillis() + '.test',
            Alias = alias,
            ProfileId = profileId,
            ContactId = c.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
			IsActive = true
        );
    }

	private static void happyPathProcess(User u) {
		System.runAs(u){
			List<Partner_Checklist_Item__c> items = PartnerChecklistController.getChecklistItems();
			for(Partner_Checklist_Item__c item : items){
				System.assertEquals(u.Id, item.User__c);
			}

			items[0].Completed__c = true;
			items[0].Completion_Date__c = Date.today();
			PartnerChecklistController.updateChecklistItems(items);

			List<Partner_Checklist_Item__c> updatedItems = PartnerChecklistController.getChecklistItems();
			Integer completedCount = 0;
			for(Partner_Checklist_Item__c item : updatedItems){
				if(item.Completed__c == true){
					System.assertEquals(true, item.Completed__c);
					System.assertNotEquals(null, item.Completion_Date__c);
					completedCount++;
				}
			}

			System.assertEquals(1, completedCount);
		}
	}
}