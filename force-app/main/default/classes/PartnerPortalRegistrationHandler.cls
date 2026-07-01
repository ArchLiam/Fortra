global class PartnerPortalRegistrationHandler implements Auth.RegistrationHandler {
/************ SETUP ************/
	// Custom exception for registration handler errors
	class RegHandlerException extends Exception {}

	// Defaults
	private static final Set<String> CONFIG_PERMISSION_SETS = new Set<String>();
    private static final String CONFIG_PROFILE_NAME = 'Basic Partner User';
    private static final String DEFAULT_TIMEZONE = 'America/Los_Angeles';
    private static final String DEFAULT_LOCALE = 'en_US';
    private static final String DEFAULT_LANGUAGE = 'en_US';
    private static final String DEFAULT_EMAIL_ENCODING = 'UTF-8';

/************ MAIN METHODS ************/
    // Called on first-time authentication when no existing link is found.
    public User createUser(Id portalId, Auth.UserData data) {
		System.debug('PartnerPortalRegistrationHandler.createUser: ' + data);
        if (data == null) {
            throw new RegHandlerException('UserData was null in registration handler.');
        }
        if (String.isBlank(data.email)) {
            throw new RegHandlerException('Email is required to create a User via registration handler.');
        }

        // Resolve Profile by name
        Profile targetProfile = resolveProfileByName(CONFIG_PROFILE_NAME);
        if (targetProfile == null) {
            throw new RegHandlerException('Configured Profile Name not found: ' + CONFIG_PROFILE_NAME);
        }

		// Check Domain__c to determine whether to activate user
		List<Domain__c> domains = [SELECT Id FROM Domain__c WHERE Domain__c = :data.email.split('@')[1] AND Approved_for_Portal_Access__c = true LIMIT 1];
		Boolean isPortalApproved = false;
		if (!domains.isEmpty()) {
			isPortalApproved = true;
		}

        // Construct User
        User u = buildUserFromData(data, targetProfile.Id, isPortalApproved);

        // Insert with USER_MODE to respect permissions
        Database.SaveResult sr = Database.insert(u, AccessLevel.USER_MODE);
        if (!sr.isSuccess()) {
            throw buildSaveException('insert', sr);
        }

        // Assign permission sets (none by default)
        if (!CONFIG_PERMISSION_SETS.isEmpty()) {
            assignPermissionSets(u.Id, CONFIG_PERMISSION_SETS);
        }

		System.debug('PartnerPortalRegistrationHandler.createUser - Created user: ' + u);
        return u;
    }

    // Called on subsequent authentications to refresh mapped fields.
    public void updateUser(Id userId, Id portalId, Auth.UserData data) {
		System.debug('PartnerPortalRegistrationHandler.updateUser: ' + userId + ', ' + data);
        if (userId == null || data == null) {
			System.debug('PartnerPortalRegistrationHandler.updateUser - No userId or data to update');
            return;
        }

        User u = [SELECT Id, FirstName, LastName, Email, TimeZoneSidKey, LocaleSidKey, LanguageLocaleKey, EmailEncodingKey FROM User WHERE Id = :userId WITH USER_MODE];

        applyUserFieldUpdates(u, data);
		System.debug('PartnerPortalRegistrationHandler.updateUser - Updated user: ' + u);
        Database.SaveResult sr = Database.update(u, AccessLevel.USER_MODE);
        if (!sr.isSuccess()) {
            throw buildSaveException('update', sr);
        }
    }

/************ HELPER METHODS ************/
    // Build a new User from Auth.UserData and defaults
	@TestVisible
    private static User buildUserFromData(Auth.UserData data, Id profileId, Boolean isPortalApproved) {
        String email = data.email;
		String username = deriveUsername(email);
		String alias = deriveAlias(data.firstName, data.lastName, email);
		String firstName = String.isBlank(data.firstName) ? '' : data.firstName;
		String middleName = '';
		String lastName = String.isBlank(data.lastName) ? '' : data.lastName;

		// Split Full Name if FirstName or LastName are missing
		if ((String.isBlank(firstName) || String.isBlank(lastName)) && String.isNotBlank(data.fullName)) {
			String[] parts = data.fullName.trim().replace('null', '').split(' ');
			if(parts.size() == 1) {
				firstName = parts[0];
			} else if (parts.size() == 2) {
				firstName = parts[0];
				lastName = parts[1];
			} else if (parts.size() > 2) {
				firstName = parts[0];
				middleName = parts[1];
				for(Integer i=2; i < parts.size(); i++){
					lastName += parts[i] + ' ';
				}
			}
		}
		firstName = String.isBlank(firstName) ? 'Portal' : firstName.left(40).trim();
		middleName = String.isBlank(middleName) ? null : middleName.left(40).trim();
		lastName = String.isBlank(lastName) ? 'User' : lastName.left(80).trim();

        User u = new User();
        u.ProfileId = profileId;
        u.Username = username;
        u.Email = email;
        u.FirstName = firstName;
		u.MiddleName = middleName;
        u.LastName = lastName;
        u.Alias = alias;
        u.TimeZoneSidKey = claimOrDefault(data, 'tz', DEFAULT_TIMEZONE);
        u.LocaleSidKey = DEFAULT_LOCALE;
        u.LanguageLocaleKey = DEFAULT_LANGUAGE;
        u.EmailEncodingKey = DEFAULT_EMAIL_ENCODING;
		u.IsActive = true;

        // Populate ContactId
        if (!String.isBlank(email)) {
            // 1) Lookup Contact by email
            List<Contact> contactsByEmail = [SELECT Id FROM Contact WHERE Email = :email WITH USER_MODE LIMIT 1];
            if (!contactsByEmail.isEmpty()) {
                u.ContactId = contactsByEmail[0].Id;
				isPortalApproved = true;
				// TODO: Make sure the Contact.Owner has a role - might just be a data problem
            } else {
                // 2) Ensure default Account exists
                String defaultAccountName = 'Pending Partners'; // Assign to default account, a flow will reassign if necessary
                Account defaultAccount;

                List<Account> accounts = [SELECT Id, OwnerId FROM Account WHERE Name = :defaultAccountName LIMIT 1];
                if (!accounts.isEmpty()) {
                    defaultAccount = accounts[0];
                } else {
                    // Try to set the owner to 'Fortra System Admin' with a role
                    Id ownerIdToSet = null;
                    List<User> owners = [SELECT Id FROM User WHERE Name = 'Fortra System Admin' AND UserRoleId != null LIMIT 1];
                    if (!owners.isEmpty()) {
                        ownerIdToSet = owners[0].Id;
                    }

                    Account a = new Account(Name = defaultAccountName);
                    if (ownerIdToSet != null) {
                        a.OwnerId = ownerIdToSet;
                    }
                    Database.SaveResult asr = Database.insert(a, AccessLevel.USER_MODE);
                    if (asr.isSuccess()) {
                        defaultAccount = new Account(Id = asr.getId());
                    }
                }

                // 3) Create Contact if we have or created an account --- TODO: Any additional fields to set?
                if (defaultAccount != null) {
                    Contact c = new Contact(
                        AccountId = defaultAccount.Id,
                        FirstName = firstName,
						MiddleName = middleName,
                        LastName = lastName,
                        Email = email
                    );
                    Database.SaveResult csr = Database.insert(c, AccessLevel.USER_MODE);
                    if (csr.isSuccess()) {
                        u.ContactId = csr.getId();
                    }
                }
            }
        }

		u.Is_Portal_Approved__c = isPortalApproved;
        return u;
    }

    // Update selected fields on existing user
    private static void applyUserFieldUpdates(User u, Auth.UserData data) {
        if (u == null || data == null) return;

        if (!String.isBlank(data.firstName)) u.FirstName = data.firstName;
        if (!String.isBlank(data.lastName)) u.LastName = data.lastName;
        if (!String.isBlank(data.email)) u.Email = data.email;

        String tz = claimOrNull(data, 'tz');
        if (!String.isBlank(tz)) u.TimeZoneSidKey = tz;
    }

    // Resolve profile by Name (no hardcoded Ids)
    private static Profile resolveProfileByName(String profileName) {
        if (String.isBlank(profileName)) return null;
        List<Profile> profs = [SELECT Id, Name FROM Profile WHERE Name = :profileName LIMIT 1];
        return profs.isEmpty() ? null : profs[0];
    }

    // Assign permission sets by names
    private static void assignPermissionSets(Id userId, Set<String> permsetNames) {
        if (userId == null || permsetNames == null || permsetNames.isEmpty()) return;

		Map<String, PermissionSet> nameToPs = new Map<String, PermissionSet>();
		for(PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :permsetNames]) {
			nameToPs.put(ps.Name, ps);
		}

        List<PermissionSetAssignment> inserts = new List<PermissionSetAssignment>();
        for (String psName : permsetNames) {
            PermissionSet ps = nameToPs.get(psName);
            if (ps != null) {
                inserts.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id));
            }
        }
        if (!inserts.isEmpty()) {
            Database.SaveResult[] results = Database.insert(inserts, false, AccessLevel.USER_MODE);
            for (Database.SaveResult r : results) {
                if (!r.isSuccess()) throw buildSaveException('permission set assignment insert', r);
            }
        }
    }

    @TestVisible
    private static void testInvoke_assignPermissionSets(Id userId, Set<String> permsetNames) {
        assignPermissionSets(userId, permsetNames);
    }

    private static String deriveUsername(String email) {
        // Typically username must be globally unique; using email here assumes uniqueness strategy is handled by IdP policy.
        return email;
    }

    private static String deriveAlias(String first, String last, String email) {
        String base = '';
        if (!String.isBlank(first)) base += first.substring(0, Math.min(2, first.length()));
        if (!String.isBlank(last)) base += last.substring(0, Math.min(2, last.length()));
        if (String.isBlank(base)) {
            Integer at = email != null ? email.indexOf('@') : -1;
            base = at > 0 ? email.substring(0, Math.min(8, at)) : 'user';
        }
        base = base.replaceAll('[^A-Za-z0-9]', '');
        if (base.length() > 8) base = base.substring(0, 8);
        if (base.length() == 0) base = 'user';
        return base;
    }

	private static String claimOrNull(Auth.UserData data, String key) {
        return (data != null && data.attributeMap != null) ? data.attributeMap.get(key) : null;
    }

    private static String claimOrDefault(Auth.UserData data, String key, String fallback) {
        String v = claimOrNull(data, key);
        return String.isBlank(v) ? fallback : v;
        }

    private static RegHandlerException buildSaveException(String op, Database.SaveResult sr) {
        String msg = 'Registration handler ' + op + ' failed: ';
        for (Database.Error e : sr.getErrors()) {
            msg += '[' + e.getStatusCode() + '] ' + e.getMessage() + ' ';
        }
        return new RegHandlerException(msg.trim());
    }
}