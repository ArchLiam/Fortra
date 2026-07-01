@isTest
private class PortalUserManagementHelperTest {

	@TestSetup
	static void testSetup(){
		// Need userrole when creating portal users
		UserRole userrole = [Select Id, DeveloperName From UserRole Where DeveloperName = 'System_Admin' LIMIT 1];
		User adminUser = [Select Id, UserRoleId From User Where Profile.Name='System Administrator' AND isActive = true LIMIT 1];
		adminUser.UserRoleId = userRole.Id;
		update adminUser;

		System.runAs(adminUser){
			Account acct = new Account(Name = 'Test Account');
			insert acct;

			// List<Contact> contacts = new List<Contact>{
			// 	new Contact(FirstName = 'Basic', LastName = 'Contact', AccountId = acct.Id, Phone = '1234567890', Workday_Phone_Country_ISO_Code__c = 'USA', MobilePhone = '1234567890', Workday_MobilePhone_Country_ISO_Code__c = 'USA'),
			// 	new Contact(FirstName = 'Mid',   LastName = 'Contact', AccountId = acct.Id, Phone = '1234567890', Workday_Phone_Country_ISO_Code__c = 'USA', MobilePhone = '0987654321', Workday_MobilePhone_Country_ISO_Code__c = 'USA'),
			// 	new Contact(FirstName = 'Top',   LastName = 'Contact', AccountId = acct.Id, Phone = '1234567890', Workday_Phone_Country_ISO_Code__c = 'USA', MobilePhone = '1122334455', Workday_MobilePhone_Country_ISO_Code__c = 'USA')
			// };
			// insert contacts;

			// Getting error when inserting multiple contacts in a list, so inserting them one by one
			insert new Contact(FirstName = 'Basic', LastName = 'Contact', AccountId = acct.Id, Phone = '1234567890', Workday_Phone_Country_ISO_Code__c = 'USA', MobilePhone = '1234567890', Workday_MobilePhone_Country_ISO_Code__c = 'USA');
			insert new Contact(FirstName = 'Mid',   LastName = 'Contact', AccountId = acct.Id, Phone = '1234567890', Workday_Phone_Country_ISO_Code__c = 'USA', MobilePhone = '0987654321', Workday_MobilePhone_Country_ISO_Code__c = 'USA');
			insert new Contact(FirstName = 'Top',   LastName = 'Contact', AccountId = acct.Id, Phone = '1234567890', Workday_Phone_Country_ISO_Code__c = 'USA', MobilePhone = '1122334455', Workday_MobilePhone_Country_ISO_Code__c = 'USA');
		}

		Profile basicPartnerProfile = 	[SELECT Id, Name FROM Profile WHERE Name = 'Basic Partner User' LIMIT 1];
		Profile midPartnerProfile = 	[SELECT Id, Name FROM Profile WHERE Name = 'Mid-Tier Partner User' LIMIT 1];
		Profile topPartnerProfile = 	[SELECT Id, Name FROM Profile WHERE Name = 'Top-Tier Partner User' LIMIT 1];

		String uniq = String.valueOf(DateTime.now().getTime());

		User basicUser = new User(
			Alias = 'basic',
			Email = 'basicUser' + uniq + '@example.com',
			EmailEncodingKey = 'UTF-8',
			LastName = 'BasicUser',
			LanguageLocaleKey = 'en_US',
			LocaleSidKey = 'en_US',
			TimeZoneSidKey = 'America/Los_Angeles',
			UserName = 'basicUser.' + uniq + '@example.com',
			ProfileId = basicPartnerProfile.Id,
			ContactId = [SELECT Id FROM Contact WHERE FirstName = 'Basic' AND LastName = 'Contact' LIMIT 1].Id
		);

		User midUser = new User(
			Alias = 'mid',
			Email = 'midUser' + uniq + '@example.com',
			EmailEncodingKey = 'UTF-8',
			LastName = 'MidUser',
			LanguageLocaleKey = 'en_US',
			LocaleSidKey = 'en_US',
			TimeZoneSidKey = 'America/Los_Angeles',
			UserName = 'midUser.' + uniq + '@example.com',
			ProfileId = midPartnerProfile.Id,
			ContactId = [SELECT Id FROM Contact WHERE FirstName = 'Mid' AND LastName = 'Contact' LIMIT 1].Id
		);

		User topUser = new User(
			Alias = 'top',
			Email = 'topUser' + uniq + '@example.com',
			EmailEncodingKey = 'UTF-8',
			LastName = 'TopUser',
			LanguageLocaleKey = 'en_US',
			LocaleSidKey = 'en_US',
			TimeZoneSidKey = 'America/Los_Angeles',
			UserName = 'topUser.' + uniq + '@example.com',
			ProfileId = topPartnerProfile.Id,
			ContactId = [SELECT Id FROM Contact WHERE FirstName = 'Top' AND LastName = 'Contact' LIMIT 1].Id
		);

		insert new List<User>{basicUser, midUser, topUser};
		for(Contact c : [SELECT Id, AccountId FROM Contact]){
			System.debug('Contact: ' + c);
		}
		for(User u : [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id IN :new List<Id>{basicUser.Id, midUser.Id, topUser.Id}]){
			System.debug('User: ' + u);
		}
	}

	@isTest
	static void getUsersTest(){
		User runningUser = [SELECT Id FROM User WHERE LastName = 'TopUser' LIMIT 1];
		List<User> users = new List<User>();

		System.runAs(runningUser){
			users = PortalUserManagementHelper.getUsers();
		}

		System.assert(users.size() == 2, 'getUsers should return 2 users (excluding the running user)');
	}

	@isTest
	static void searchUsersTest(){
		// Have to set fixed search results when using SOSL
		List<User> allUsers = [SELECT Id, Name FROM User WHERE Profile.Name LIKE '%Partner User' AND CreatedDate = TODAY];
		Id [] fixedSearchResults= new Id[allUsers.size()];
		for(Integer i=0; i<allUsers.size(); i++){
			fixedSearchResults[i] = allUsers[i].Id;
		}
        Test.setFixedSearchResults(fixedSearchResults);

		User runningUser = [SELECT Id FROM User WHERE LastName = 'TopUser' LIMIT 1];
		List<User> users = new List<User>();

		System.runAs(runningUser){
			users = PortalUserManagementHelper.searchUsers('user');
		}

		System.assert(users.size() == 2, 'searchUsers should return 2 users (excluding the running user)');
	}

	@isTest
	static void modifyUsersTest(){
		User runningUser = [SELECT Id FROM User WHERE LastName = 'TopUser' LIMIT 1];
		List<User> users = new List<User>();

		System.runAs(runningUser){
			users = PortalUserManagementHelper.getUsers();
		}
		
		User basicUser;
		for(User u : users){
			if(u.Profile.Name == 'Basic Partner User'){
				basicUser = u;
				break;
			}
		}
		
		// Deactivate the user
		PortalUserManagementHelper.deactivateUsers(new List<Id>{basicUser.Id});
		basicUser = [SELECT Id, IsActive FROM User WHERE Id = :basicUser.Id];
		System.assert(!basicUser.IsActive, 'User should be deactivated');

		// Activate the user
		PortalUserManagementHelper.activateUsers(new List<Id>{basicUser.Id});
		basicUser = [SELECT Id, IsActive FROM User WHERE Id = :basicUser.Id];
		System.assert(basicUser.IsActive, 'User should be activated');

		// Modify profile
		Profile midPartnerProfile = [SELECT Id, Name FROM Profile WHERE Name = 'Mid-Tier Partner User' LIMIT 1];
		PortalUserManagementHelper.modifyUsersProfile(new List<Id>{basicUser.Id}, midPartnerProfile.Name);
		basicUser = [SELECT Id, ProfileId FROM User WHERE Id = :basicUser.Id];
		System.assertEquals(midPartnerProfile.Id, basicUser.ProfileId, 'User profile should be updated to Mid-Tier Partner User');
	}
}