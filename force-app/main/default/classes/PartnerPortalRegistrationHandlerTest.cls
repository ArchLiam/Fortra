@IsTest
private class PartnerPortalRegistrationHandlerTest {

    @TestSetup
    static void setupData() {
        // Create a baseline user to simulate existing user matched by email
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        // Ensure test org has Standard User profile; if not found, test will fail with clear message
        System.assertNotEquals(null, p, 'Required test profile "Standard User" was not found in this org.');

        User u = new User(
            FirstName = 'Existing',
            LastName = 'User',
            Email = 'existing.user@example.com',
            Username = 'existing.user@example.com',
            Alias = 'exuser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id
        );
        insert u;
        }

    // Helper to build Auth.UserData
    private static Auth.UserData makeUserData(String email, String firstName, String lastName, Map<String, String> attrs) {
        if (attrs == null) attrs = new Map<String, String>();
        // Construct a minimal UserData. identifier is optional for this handler, email is required.
        // Auth.UserData sampleData = new Auth.UserData(
        //     'oidc',                // provider
        //     'idp-userid-123',      // identifier (unused for match)
        //     email,                 // email
        //     firstName,             // firstName
        //     lastName,              // lastName
        //     'en_US',               // locale
        //     'en_US',               // language
        //     attrs,                 // attributeMap
        //     null                   // options
        // );
		Auth.UserData sampleData = new Auth.UserData(
			'testId', 
			firstName, 
			lastName,
        	firstName + ' ' + lastName, 
			email,
			null, 
			'testuserlong', 
			'en_US', 
			'facebook',
        	null, 
			attrs //new Map<String, String>{'language' => 'en_US'}
		);
		return sampleData;
    }

    @IsTest
    static void testCreateUser_NewUserCreated_Active() {
		List<User> owners = [SELECT Id FROM User WHERE Name = 'Fortra System Admin' AND UserRoleId != null LIMIT 1];
		Account a = new Account(Name = 'Example Account', OwnerId = owners[0].Id);
		insert a;
		a.IsPartner = true;
		update a;
        Domain__c exampleDomain = new Domain__c(Domain__c = 'example.com', Approved_for_Portal_Access__c = true, Account__c = a.Id);
        insert exampleDomain;

        PartnerPortalRegistrationHandler h = new PartnerPortalRegistrationHandler();
        Map<String, String> attrs = new Map<String, String>{
            'tz' => 'America/Los_Angeles'
        };
		String username = 'new.user+' + System.now().getTime() + '@example.com';
		Auth.UserData data = makeUserData(username, 'New', 'Person', attrs);

        Test.startTest();
        User created = h.createUser(null, data);
        Test.stopTest();

        System.assertNotEquals(null, created, 'Expected a User to be created');
        User fetched = [SELECT Id, Email, FirstName, LastName, IsActive, Is_Portal_Approved__c, Profile.Name, TimeZoneSidKey
                        FROM User
                        WHERE Id = :created.Id];
        System.assertEquals(username, fetched.Email, 'Email should match input');
        System.assertEquals('New', fetched.FirstName, 'FirstName should map from claims');
        System.assertEquals('Person', fetched.LastName, 'LastName should map from claims');
        System.assertEquals(true, fetched.Is_Portal_Approved__c, 'User should be approved on create per configuration');
        System.assertEquals('Basic Partner User', fetched.Profile.Name, 'Profile should be Basic Partner User');
        System.assertEquals('America/Los_Angeles', fetched.TimeZoneSidKey, 'Time zone should map from claim or default');
    }

	@IsTest
    static void testCreateUser_NewUserCreated_Inactive() {
        PartnerPortalRegistrationHandler h = new PartnerPortalRegistrationHandler();
        Map<String, String> attrs = new Map<String, String>{
            'tz' => 'America/Los_Angeles'
        };
		String username = 'new.user+' + System.now().getTime() + '@example.com';
		Auth.UserData data = makeUserData(username, 'New', 'Person', attrs);

        Test.startTest();
        User created = h.createUser(null, data);
        Test.stopTest();

        System.assertNotEquals(null, created, 'Expected a User to be created');
        User fetched = [SELECT Id, Email, FirstName, LastName, IsActive, Is_Portal_Approved__c,Profile.Name, TimeZoneSidKey
                        FROM User
                        WHERE Id = :created.Id];
        System.assertEquals(username, fetched.Email, 'Email should match input');
        System.assertEquals('New', fetched.FirstName, 'FirstName should map from claims');
        System.assertEquals('Person', fetched.LastName, 'LastName should map from claims');
        System.assertEquals(false, fetched.Is_Portal_Approved__c, 'User should be not be approved on create if domain is not approved');
        System.assertEquals('Basic Partner User', fetched.Profile.Name, 'Profile should be Basic Partner User');
        System.assertEquals('America/Los_Angeles', fetched.TimeZoneSidKey, 'Time zone should map from claim or default');
    }

    @IsTest
    static void testCreateUser_ThrowsWhenEmailMissing() {
        PartnerPortalRegistrationHandler h = new PartnerPortalRegistrationHandler();
        Auth.UserData data = makeUserData(null, 'No', 'Email', null);

        Boolean threw = false;
        try {
            Test.startTest();
            h.createUser(null, data);
            Test.stopTest();
        } catch (Exception ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Email is required'), 'Expected email required message');
        }
        System.assertEquals(true, threw, 'Should throw when email is missing');
    }

    @IsTest
    static void testUpdateUser_UpdatesMappedFields() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Before',
            LastName = 'Change',
            Email = 'update.me@example.com',
            Username = 'update.me@example.com',
            Alias = 'updateme',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id
        );
        insert u;

        PartnerPortalRegistrationHandler h = new PartnerPortalRegistrationHandler();
        Map<String, String> attrs = new Map<String, String>{ 'tz' => 'America/Denver' };
        Auth.UserData data = makeUserData('update.me@example.com', 'After', 'Updated', attrs);

        Test.startTest();
        h.updateUser(u.Id, null, data);
        Test.stopTest();

        User refreshed = [SELECT FirstName, LastName, Email, TimeZoneSidKey FROM User WHERE Id = :u.Id];
        System.assertEquals('After', refreshed.FirstName, 'First name should update');
        System.assertEquals('Updated', refreshed.LastName, 'Last name should update');
        System.assertEquals('update.me@example.com', refreshed.Email, 'Email should update/retain');
        System.assertEquals('America/Denver', refreshed.TimeZoneSidKey, 'Time zone should update from claims');
    }

    @IsTest
    static void testUpdateUser_NoOpWhenMissingInputs() {
        PartnerPortalRegistrationHandler h = new PartnerPortalRegistrationHandler();
        // Should not throw
        Test.startTest();
        h.updateUser(null, null, null);
        Test.stopTest();
        System.assert(true, 'No exception expected');
    }

	@IsTest
    static void testAssignPermissionSets_AssignsWhenNamesMatch() {
        List<PermissionSet> anyPs = [SELECT Id, Name FROM PermissionSet WHERE IsOwnedByProfile = false AND Name LIKE 'Accounts%' LIMIT 1];
        System.assertEquals(false, anyPs.isEmpty(), 'Test requires at least one assignable Permission Set in the org.');
        PermissionSet ps = anyPs[0];

        Profile prof = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        System.assertNotEquals(null, prof, 'Profile "Standard User" must exist for test user creation.');
        Long ts = System.now().getTime();
        User u = new User(
            FirstName = 'Perm',
            LastName = 'Target',
            Email = 'perm.assign+' + ts + '@example.com',
            Username = 'perm.assign+' + ts + '@example.com',
            Alias = 'permtgt',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = prof.Id
        );
        insert u;

        Test.startTest();
        PartnerPortalRegistrationHandler.testInvoke_assignPermissionSets(u.Id, new Set<String>{ ps.Name });
        Test.stopTest();

        List<PermissionSetAssignment> assigned = [
            SELECT Id, PermissionSet.Name, AssigneeId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :u.Id
        ];
        System.assertEquals(2, assigned.size(), 'Exactly two PermissionSetAssignment should have been created');
        // System.assertEquals(ps.Name, assigned[1].PermissionSet.Name, 'Assigned Permission Set name should match input');
    }

    @IsTest
    static void testAssignPermissionSets_IgnoresUnknownNamesAndEmpty() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        Long ts = System.now().getTime();
        User u = new User(
            FirstName = 'No',
            LastName = 'Match',
            Email = 'perm.none+' + ts + '@example.com',
            Username = 'perm.none+' + ts + '@example.com',
            Alias = 'permnonn',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = prof.Id
        );
        insert u;

        Set<String> bogus = new Set<String>{ 'THIS_WILL_NOT_EXIST_' + ts };
        PartnerPortalRegistrationHandler.testInvoke_assignPermissionSets(u.Id, bogus);

        Integer psaCountAfterBogus = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :u.Id];
        System.assertEquals(1, psaCountAfterBogus, 'No PermissionSetAssignment should be created for unknown names');

        PartnerPortalRegistrationHandler.testInvoke_assignPermissionSets(u.Id, new Set<String>());

        Integer psaCountAfterEmpty = [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :u.Id];
        System.assertEquals(1, psaCountAfterEmpty, 'Empty set should not create any PermissionSetAssignment records');
    }

    @IsTest
    static void testNameCorrections() {
		Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

		Auth.UserData onePartData = makeUserData('test@test.com', 'First', null, new Map<String, String>{});
		User onePartUser = PartnerPortalRegistrationHandler.buildUserFromData(onePartData, profile.Id, true);
		System.assertEquals('First', onePartUser.FirstName);
		System.assertEquals(null, onePartUser.MiddleName);
		System.assertEquals('User', onePartUser.LastName);

		Auth.UserData twoPartName = makeUserData('test@test.com', 'First Last', null, new Map<String, String>{});
		User twoPartUser = PartnerPortalRegistrationHandler.buildUserFromData(twoPartName, profile.Id, true);
		System.assertEquals('First', twoPartUser.FirstName);
		System.assertEquals(null, twoPartUser.MiddleName);
		System.assertEquals('Last', twoPartUser.LastName);

		Auth.UserData threePartName = makeUserData('test@test.com', 'First Middle Last', null, new Map<String, String>{});
		User threePartUser = PartnerPortalRegistrationHandler.buildUserFromData(threePartName, profile.Id, true);
		System.assertEquals('First', threePartUser.FirstName);
		System.assertEquals('Middle', threePartUser.MiddleName);
		System.assertEquals('Last', threePartUser.LastName);

		Auth.UserData fourPartName = makeUserData('test@test.com', 'First Second Third Last', null, new Map<String, String>{});
		User fourPartUser = PartnerPortalRegistrationHandler.buildUserFromData(fourPartName, profile.Id, true);
		System.assertEquals('First', fourPartUser.FirstName);
		System.assertEquals('Second', fourPartUser.MiddleName);
		System.assertEquals('Third Last', fourPartUser.LastName);
	}	
}

/* SSO Data 
UserData:[
	attributeMap={
		email=midtierpartnerprofile@coastal.us.invalid, 
		email_verified=true, 
		given_name=Mid-Tier Partner Profile, 
		name=Mid-Tier Partner Profile, 
		preferred_username=midtierpartnerprofile@coastal.us.invalid, 
		sfdc_networkid=0DBdp0000000I3N, 
		sub=f:b65c2bee-f08d-4e2e-92eb-b752cd95496c:cd1873c2-64ee-41da-ae0d-12474cd503e4
	}, 
	email=midtierpartnerprofile@coastal.us.invalid, 
	firstName=Mid-Tier Partner Profile, 
	fullName=Mid-Tier Partner Profile, 
	idToken=eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ4TU9CdzVEc01BQ3M2ZUZvdmpmNjdjRmoyZHR6Z2F5WE5TR2dIOTdzMXc0In0.eyJleHAiOjE3Njc5MjA1MjgsImlhdCI6MTc2NzkyMDIyOCwiYXV0aF90aW1lIjoxNzY3OTIwMjI3LCJqdGkiOiJiMjc0YWJkNC0wNGFmLWZiZmQtNzUwYy1kYjBmMjM5MDUwMzUiLCJpc3MiOiJodHRwczovL2ZvdW5kYXRpb24uZm91bmRhdGlvbi1kZXYuY2xvdWRvcHMuZm9ydHJhZGV2LmNvbS9pZHAvcmVhbG1zL3Byb2R1Y3RzIiwiYXVkIjoic2FsZXNmb3JjZS1pbnRlZ3JhdGlvbi1jb25maWRlbnRpYWwiLCJzdWIiOiJmOmI2NWMyYmVlLWYwOGQtNGUyZS05MmViLWI3NTJjZDk1NDk2YzpjZDE4NzNjMi02NGVlLTQxZGEtYWUwZC0xMjQ3NGNkNTAzZTQiLCJ0eXAiOiJJRCIsImF6cCI6InNhbGVzZm9yY2UtaW50ZWdyYXRpb24tY29uZmlkZW50aWFsIiwic2lkIjoiYmI2YWJiOGMtMzAwMC00MzkyLTlkYWUtNjQyYTg3NjAyNGZhIiwiYXRfaGFzaCI6IkpSdTBfUEZwckZySmFPSUl5TS1SQUEiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6Ik1pZC1UaWVyIFBhcnRuZXIgUHJvZmlsZSIsImZvcnRyYS50ZW5hbnRJZCI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMCIsInByZWZlcnJlZF91c2VybmFtZSI6Im1pZHRpZXJwYXJ0bmVycHJvZmlsZUBjb2FzdGFsLnVzLmludmFsaWQiLCJnaXZlbl9uYW1lIjoiTWlkLVRpZXIgUGFydG5lciBQcm9maWxlIiwiZW1haWwiOiJtaWR0aWVycGFydG5lcnByb2ZpbGVAY29hc3RhbC51cy5pbnZhbGlkIn0.a3gcnwqcvGf-ygvWF5CpPj_BQsOFmuVyQfVj-esnSvuZPOoQQJXapsR1IQZAOckjfULpc7x9fLArC4xXmETf1qu9fYL5jp8bcsS_0HBnue0kW9UA-MiOQveqZCVQrPFFDG3Ry2XjnL3od5woinXL6UyLzvAj7Wf7JH8pri3Vixo7bk3iUJB3JKeRtWW_bEjoz2yGCLBKi_xPBRZkCnVfYkJf8MvX648m9LbpykeIdx9FqjEsFP5ot5jVhjuUoMAhvo_jxCOKlmRDDO8_LbTe9MTpbvCnZcSL0UmTr4tYu99gYrZw_coIsLeBhqtIviHqQWEKMJxQZMM4tIE46EnsDw, 
	idTokenJSONString={
		"at_hash":"JRu0_PFprFrJaOIIyM-RAA",
		"sub":"f:b65c2bee-f08d-4e2e-92eb-b752cd95496c:cd1873c2-64ee-41da-ae0d-12474cd503e4",
		"email_verified":true,
		"iss":"https://foundation.foundation-dev.cloudops.fortradev.com/idp/realms/products",
		"typ":"ID",
		"preferred_username":"midtierpartnerprofile@coastal.us.invalid",
		"given_name":"Mid-Tier Partner Profile",
		"sid":"bb6abb8c-3000-4392-9dae-642a876024fa",
		"aud":"salesforce-integration-confidential",
		"azp":"salesforce-integration-confidential"
		"auth_time":1767920227,
		"name":"Mid-Tier Partner Profile",
		"fortra.tenantId":"00000000-0000-0000-0000-000000000000",
		"exp":1767920528,
		"iat":1767920228,
		"jti":"b274abd4-04af-fbfd-750c-db0f23905035",
		"email":"midtierpartnerprofile@coastal.us.invalid"
	}, 
	identifier=f:b65c2bee-f08d-4e2e-92eb-b752cd95496c:cd1873c2-64ee-41da-ae0d-12474cd503e4, 
	lastName=null, 
	link=null, 
	locale=null, 
	provider=Open ID Connect, 
	siteLoginUrl=null, 
	userInfoJSONString={
		"sub":"f:b65c2bee-f08d-4e2e-92eb-b752cd95496c:cd1873c2-64ee-41da-ae0d-12474cd503e4",
		"email_verified":true,
		"name":"Mid-Tier Partner Profile",
		"preferred_username":"midtierpartnerprofile@coastal.us.invalid",
		"given_name":"Mid-Tier Partner Profile",
		"email":"midtierpartnerprofile@coastal.us.invalid"
	}, 
	username=midtierpartnerprofile@coastal.us.invalid
]
*/