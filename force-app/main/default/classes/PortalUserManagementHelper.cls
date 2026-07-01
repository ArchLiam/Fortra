public with sharing class PortalUserManagementHelper {

	// Adding Invocable/Future method to prevent mixed DML errors
    @InvocableMethod(label='Give Contact Fortra Academy Access')
    public static void giveFortraAcademyAccess(List<Id> contactIds) {
        setContactFortraAcademyAccess(contactIds);
    }

    @future
    private static void setContactFortraAcademyAccess(List<Id> ids) {
        List<Contact> contactsToUpdate = [SELECT Id, Fortra_Academy_Access__c FROM Contact WHERE Id IN :ids AND Fortra_Academy_Access__c = false];
		for(Contact c : contactsToUpdate){
			c.Fortra_Academy_Access__c = true;
		}
		update contactsToUpdate;
    }
    
    @AuraEnabled(cacheable=True)
    public static List<User> getUsers(){
		User runningUser = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return [
			SELECT Id, Name, FirstName, LastName, Email, Profile.Name, LastLoginDate, IsActive
			FROM User
			WHERE Profile.Name LIKE '%Partner User' AND Contact.AccountId = :runningUser.Contact.AccountId AND Id != :runningUser.Id
			ORDER BY CreatedDate DESC
		];
    }

    @AuraEnabled(cacheable=True)
    public static List<User> searchUsers(String searchString){
		User runningUser = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        List<List<SObject>> users = [
			FIND :searchString 
			IN ALL FIELDS 
			RETURNING User(
				Id, Name, FirstName, LastName, Email, Profile.Name, LastLoginDate, IsActive
				WHERE Profile.Name LIKE '%Partner User' AND Contact.AccountId = :runningUser.Contact.AccountId AND Id != :runningUser.Id
				ORDER BY CreatedDate DESC
			)
		];

        return (List<User>) users[0];
    }

    @AuraEnabled
    public static void activateUsers(List<Id> userIds){
        List<User> usersToActivate = [SELECT Id, IsActive FROM User WHERE IsActive = false AND Id IN :userIds];
        for(User u : usersToActivate){
            u.IsActive = true;
        }
        update usersToActivate;
    }

	@AuraEnabled
    public static void deactivateUsers(List<Id> userIds){
        List<User> usersToDeactivate = [SELECT Id, IsActive FROM User WHERE IsActive = true AND Id IN :userIds ];
        for(User u : usersToDeactivate){
            u.IsActive = false;
        }
        update usersToDeactivate;
    }

	@AuraEnabled
	public static void modifyUsersProfile(List<Id> userIds, String profileName){
		List<User> usersToUpdate = new List<User>();
		List<User> selectedUsers = [SELECT Id, ProfileId FROM User WHERE Id IN :userIds];
		Id profileId = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1].Id;
		if(String.isNotBlank(profileId)){
			for(User u : selectedUsers){
				if(u.ProfileId != profileId){
					u.ProfileId = profileId;
					usersToUpdate.add(u);
				}
			}
			update usersToUpdate;
		} else {
			throw new AuraHandledException('Profile with name ' + profileName + ' not found.');
		}
	}
}