public with sharing class DunAndBradstreetHelper {

	@InvocableMethod(label='Duns Search' description='Callout D&B via Mulesoft - get results without commiting enriching DML')
	public static List<List<Account>> dunsSearch(List<Account> accounts) {
		System.debug('dunsSearch');
		List<List<Account>> accountsToReturn = new List<List<Account>>();
		List<DunsResponseWrapper> responses = new List<DunsResponseWrapper>();

		for (Account account : accounts) {
			System.debug('Request Account: ' + account);
			DunsResponseWrapper wrapper = DunAndBradstreetHandler.dunsCallout(account);
			responses.add(wrapper);
		}

		for (DunsResponseWrapper wrapper : responses) {
			// Stop if it's a bad request, otherwise continue and let searchForAccount() search Salesforce
			if(wrapper.responsePayload.statusCode == 400) {
				System.debug('DUNS Callout Error - Code: ' + wrapper.responsePayload.statusCode + ', Message: ' + wrapper.responsePayload.errorMessage);
				// throw new CalloutException('DUNS Callout Error - Code: ' + wrapper.errorCode + ', Message: ' + wrapper.errorMessage);
			} else {
				DunsResponseWrapper result = searchForAccount(wrapper);
				if(result.account_Results.size() > 0) {
					accountsToReturn.add(result.account_Results);
				}
			}
		}

		return accountsToReturn;
	}

	public static DunsResponseWrapper searchForAccount(DunsResponseWrapper wrapper) {
		List<Account> resultingAccounts = new List<Account>();

		// No data returned
		if(wrapper.responsePayload?.data == null || wrapper.responsePayload.data.size() == 0) {
			// Check Salesforce for existing Account via DUNS
			String originatingDuns = wrapper.originating_Account != null ? wrapper.originating_Account.DB_DUNS__c : null;
			if(String.isNotBlank(originatingDuns)) {
				List<Account> dunsSearch = database.query(selectStar('Account', 'DB_DUNS__c = :originatingDuns AND DB_DUNS__c != null AND Id != null'));
				if(dunsSearch != null && dunsSearch.size() > 0) {
					resultingAccounts.add(dunsSearch[0]);
				}
			}

			// Check via Duplicates Rules
			Map<Integer, List<SObject>> duplicateResults = assessDuplicates(new List<SObject>{wrapper.originating_Account});
			if (duplicateResults.containsKey(0) && duplicateResults.get(0).size() > 0) { // Check first index since we're only passing in one record
				List<SObject> matches = duplicateResults.get(0);
				System.debug('Found ' + matches.size() + ' potential duplicates.');
				for (SObject match : matches) {
					Account matchingAcc = (Account) match; 
					System.debug('Match Name: ' + matchingAcc.Name + ' | ID: ' + matchingAcc.Id);
					resultingAccounts.add(matchingAcc);
				}
			} else {
				System.debug('No duplicates found. Safe to proceed with insert.');
			}

			// Return
			wrapper.account_Results = resultingAccounts;
			return wrapper;
		}

		// Build Sets and Maps for Queries
		Set<String> dunsStrings = new Set<String>();
		for(DunsResponseWrapper.DunsResult dunsResult : wrapper.responsePayload.data) {
			System.debug('domesticDuns: ' + dunsResult.domesticDuns);
			if(dunsResult.domesticDuns != null) { dunsStrings.add(dunsResult.domesticDuns.duns); }
			System.debug('globalDuns: ' + dunsResult.globalDuns);
			if(dunsResult.globalDuns != null) { dunsStrings.add(dunsResult.globalDuns.duns); }
			System.debug('sitesDuns: ' + dunsResult.sitesDuns);
			if(dunsResult.sitesDuns != null) { dunsStrings.add(dunsResult.sitesDuns.duns); }
		}
		Map<String, Account> dunsToAccountMap = new Map<String, Account>();
		for(Account a : database.query(selectStar('Account', 'DB_DUNS__c IN :dunsStrings AND DB_DUNS__c != null AND Id != null'))) {
			dunsToAccountMap.put(a.DB_DUNS__c, a);
		}

		// Loop Results
		for(DunsResponseWrapper.DunsResult dunsResult : wrapper.responsePayload.data) {
			DunsResponseWrapper.CompanyDetail domesticResult = dunsResult.domesticDuns;
			DunsResponseWrapper.CompanyDetail globalResult = dunsResult.globalDuns;
			DunsResponseWrapper.CompanyDetail siteResult = dunsResult.sitesDuns;
			Account resultingAccount;

			// Callout returned a result
			if(String.isNotBlank(siteResult?.duns) || String.isNotBlank(domesticResult?.duns) || String.isNotBlank(globalResult?.duns)) {
				// 1. Search for existing Account via DUNS
				Account domesticLevelAccount = dunsToAccountMap.get(domesticResult?.duns);
				Account globalLevelAccount = dunsToAccountMap.get(globalResult?.duns);
				Account siteLevelAccount = dunsToAccountMap.get(siteResult?.duns);
				if(domesticLevelAccount != null) {
					System.debug('Domestic Level DUNS Account Found');
					resultingAccount = setAccountValues(domesticLevelAccount, domesticResult); // Found an Account in Salesforce via DUNS
				} else if(globalLevelAccount != null) {
					System.debug('Global Level DUNS Account Found');
					resultingAccount = setAccountValues(globalLevelAccount, globalResult); // Found an Account in Salesforce via DUNS
				} else if(siteLevelAccount != null) {
					System.debug('Site Level DUNS Account Found');
					resultingAccount = setAccountValues(siteLevelAccount, siteResult) ; // Found an Account in Salesforce via DUNS
				} else {
					// 2. Search for existing Account via Duplicates rules
					Map<Integer, List<SObject>> duplicateResults = assessDuplicates(new List<SObject>{wrapper.originating_Account});
					if (duplicateResults.containsKey(0) && duplicateResults.get(0).size() > 0) { // Check first index since we're only passing in one record
						System.debug('Duplicate Account Found');
						Account bestMatch = (Account) duplicateResults.get(0)[0]; // Use the first, highest confidence, match
						System.debug('Using Best Match: ' + bestMatch.Id + ' --- ' + bestMatch.Name);
						resultingAccount = bestMatch; // Found an Account in Salesforce via Duplicates
					}

					// 3. No existing Account found
					System.debug('No Existing Account Found');
					if(domesticResult?.duns != null) {
						System.debug('Using Domestic Level Result');
						resultingAccount = setAccountValues(null, dunsResult.domesticDuns);
					} else if(globalResult?.duns != null) {
						System.debug('Using Global Level Result');
						resultingAccount = setAccountValues(null, dunsResult.globalDuns);
					} else if(siteResult?.duns != null) {
						System.debug('Using Site Level Result');
						resultingAccount = setAccountValues(null, dunsResult.sitesDuns);
					}
				}
			} else {
				// Callout did not return a result - do not set resulting_Account
			}

			if(resultingAccount != null) {
				System.debug('resultingAccount: ' + resultingAccount);
				resultingAccounts.add(resultingAccount);
			}
		}

		wrapper.account_Results = resultingAccounts;
		for(Account a : resultingAccounts){
			System.debug('Resulting Account: ' + a);
		}
		return wrapper;
	}

    public static DunsResponseWrapper handleDunsResponse(DunsResponseWrapper wrapper) {
		List<Account> resultingAccounts = new List<Account>();
		Account siteLevelDunsAccount;
		Account domesticUltimateDunsAccount;
		Account globalUltimateDunsAccount;

		// No data returned
		if(wrapper.responsePayload?.data == null || wrapper.responsePayload.data.size() == 0) {
			// Check Salesforce for existing Account via DUNS
			String originatingDuns = wrapper.originating_Account != null ? wrapper.originating_Account.DB_DUNS__c : null;
			if(String.isNotBlank(originatingDuns)) {
				List<Account> dunsSearch = database.query(selectStar('Account', 'DB_DUNS__c = :originatingDuns AND DB_DUNS__c != null AND Id != null'));
				if(dunsSearch != null && dunsSearch.size() > 0) {
					resultingAccounts.add(dunsSearch[0]);
				}
			}

			// Check via Duplicates Rules
			Map<Integer, List<SObject>> duplicateResults = assessDuplicates(new List<SObject>{wrapper.originating_Account});
			if (duplicateResults.containsKey(0) && duplicateResults.get(0).size() > 0) { // Check first index since we're only passing in one record
				System.debug('Duplicate Account Found');
				Account bestMatch = (Account) duplicateResults.get(0)[0]; // Use the first, highest confidence, match
				System.debug('Using Best Match: ' + bestMatch.Id + ' --- ' + bestMatch.Name);
				resultingAccounts.add(bestMatch); // Found an Account in Salesforce via Duplicates
			}

			// Return
			wrapper.account_Results = resultingAccounts;
			return wrapper;
		}

		// Single Result Returned
		if(wrapper.responsePayload.data.size() == 1) {
			DunsResponseWrapper.DunsResult dunsResult = wrapper.responsePayload.data[0];
			DunsResponseWrapper.CompanyDetail domesticResult = dunsResult.domesticDuns;
			DunsResponseWrapper.CompanyDetail globalResult = dunsResult.globalDuns;
			DunsResponseWrapper.CompanyDetail siteResult = dunsResult.sitesDuns;

			if(String.isNotBlank(domesticResult?.duns)) {
				// Search via Duns
				List<Account> domesticLevelList = database.query(selectStar('Account', 'DB_DUNS__c = \'' + domesticResult.duns + '\' AND DB_DUNS__c != null AND Id != null LIMIT 1'));
				if(domesticLevelList.size() > 0) { 
					domesticUltimateDunsAccount = domesticLevelList[0]; 
					System.debug('Domestic Level Account Found: ' + domesticUltimateDunsAccount.Id + ' --- ' + domesticUltimateDunsAccount.DB_DUNS__c);
				}
				// Search via Duplicate Rules
				else{
					Account tempDomesticAccount = setAccountValues(null, domesticResult);
					Map<Integer, List<SObject>> duplicateResults = assessDuplicates(new List<SObject>{tempDomesticAccount});
					if (duplicateResults.containsKey(0) && duplicateResults.get(0).size() > 0) { // Check first index since we're only passing in one record
						System.debug('Domestic Level Duplicate Account Found');
						Account bestMatch = (Account) duplicateResults.get(0)[0]; // Use the first, highest confidence, match
						System.debug('Using Best Match: ' + bestMatch.Id + ' --- ' + bestMatch.Name);
						domesticUltimateDunsAccount = bestMatch; // Found an Account in Salesforce via Duplicates
					}
				}
			}
			if(String.isNotBlank(globalResult?.duns)) {
				// Search via Duns
				List<Account> globalLevelList = database.query(selectStar('Account', 'DB_DUNS__c = \'' + globalResult.duns + '\' AND DB_DUNS__c != null AND Id != null LIMIT 1'));
				if(globalLevelList.size() > 0) { 
					globalUltimateDunsAccount = globalLevelList[0]; 
					System.debug('Global Level Account Found: ' + globalUltimateDunsAccount.Id + ' --- ' + globalUltimateDunsAccount.DB_DUNS__c);
				}
				// Search via Duplicate Rules
				else{
					Account tempGlobalAccount = setAccountValues(null, globalResult);
					Map<Integer, List<SObject>> duplicateResults = assessDuplicates(new List<SObject>{tempGlobalAccount});
					if (duplicateResults.containsKey(0) && duplicateResults.get(0).size() > 0) { // Check first index since we're only passing in one record
						System.debug('Global Level Duplicate Account Found');
						Account bestMatch = (Account) duplicateResults.get(0)[0]; // Use the first, highest confidence, match
						System.debug('Using Best Match: ' + bestMatch.Id + ' --- ' + bestMatch.Name);
						globalUltimateDunsAccount = bestMatch; // Found an Account in Salesforce via Duplicates
					}
				}
			}
			if(String.isNotBlank(siteResult?.duns)) {
				// Search via Duns
				List<Account> siteLevelList = database.query(selectStar('Account', 'DB_DUNS__c = \'' + siteResult.duns + '\' AND DB_DUNS__c != null AND Id != null LIMIT 1'));
				if(siteLevelList.size() > 0) { 
					siteLevelDunsAccount = siteLevelList[0]; 
					System.debug('Site Level Account Found: ' + siteLevelDunsAccount.Id + ' --- ' + siteLevelDunsAccount.DB_DUNS__c);
				} 
				// Search via Duplicate Rules
				else{
					Account tempSiteAccount = setAccountValues(null, siteResult);
					Map<Integer, List<SObject>> duplicateResults = assessDuplicates(new List<SObject>{tempSiteAccount});
					if (duplicateResults.containsKey(0) && duplicateResults.get(0).size() > 0) { // Check first index since we're only passing in one record
						System.debug('Site Level Duplicate Account Found');
						Account bestMatch = (Account) duplicateResults.get(0)[0]; // Use the first, highest confidence, match
						System.debug('Using Best Match: ' + bestMatch.Id + ' --- ' + bestMatch.Name);
						siteLevelDunsAccount = bestMatch; // Found an Account in Salesforce via Duplicates
					}
				}
			}

			/* Removed 2026-06-23 - No longer creating site level accounts unless that's the only thing returned
			// If all three values are returned (site level, global ultimate, domestic ultimate) then upsert the three accounts connected via Parent Account lookup
			if(String.isNotBlank(siteResult?.duns) && String.isNotBlank(domesticResult?.duns) && String.isNotBlank(globalResult?.duns)) { 
				System.debug('Site, domestic, and global returned');

				globalUltimateDunsAccount = setAccountValues(globalUltimateDunsAccount, globalResult);
				globalUltimateDunsAccount.DB_Enriched__c = 'Enriched';
				globalUltimateDunsAccount.ParentId = null;
				resultingAccounts.add(globalUltimateDunsAccount);
				System.debug('Global Ultimate Account: ' + globalUltimateDunsAccount.Id + ' --- ' + globalUltimateDunsAccount.DB_DUNS__c);
				upsert globalUltimateDunsAccount;

				if(domesticResult.duns != globalResult.duns) {
					domesticUltimateDunsAccount = setAccountValues(domesticUltimateDunsAccount, domesticResult);
					domesticUltimateDunsAccount.DB_Enriched__c = 'Enriched';
					domesticUltimateDunsAccount.ParentId = globalUltimateDunsAccount.Id;
					resultingAccounts.add(domesticUltimateDunsAccount);
					System.debug('Domestic Ultimate Account: ' + domesticUltimateDunsAccount.Id + ' --- ' + domesticUltimateDunsAccount.DB_DUNS__c);
					upsert domesticUltimateDunsAccount;
				}

				siteLevelDunsAccount = setAccountValues(siteLevelDunsAccount, siteResult);
				siteLevelDunsAccount.DB_Enriched__c = 'Enriched';
				siteLevelDunsAccount.ParentId = domesticResult.duns != globalResult.duns ? domesticUltimateDunsAccount.Id : globalUltimateDunsAccount.Id;
				resultingAccounts.add(siteLevelDunsAccount);
				System.debug('Site Account: ' + siteLevelDunsAccount.Id + ' --- ' + siteLevelDunsAccount.DB_DUNS__c);
				upsert siteLevelDunsAccount;
			}
			*/

			// Domestic and Global Returned - Disregard Site Level
			if(String.isNotBlank(domesticResult?.duns) && String.isNotBlank(globalResult?.duns)) { //String.isBlank(siteResult?.duns) && 
				System.debug('Global and domestic returned');

				globalUltimateDunsAccount = setAccountValues(globalUltimateDunsAccount, globalResult);
				globalUltimateDunsAccount.DB_Enriched__c = 'Enriched';
				globalUltimateDunsAccount.ParentId = null;
				resultingAccounts.add(globalUltimateDunsAccount);
				System.debug('Global Ultimate Account: ' + globalUltimateDunsAccount.Id + ' --- ' + globalUltimateDunsAccount.DB_DUNS__c);
				upsert globalUltimateDunsAccount;

				if(domesticResult.duns != globalResult.duns) {
					domesticUltimateDunsAccount = setAccountValues(domesticUltimateDunsAccount, domesticResult);
					domesticUltimateDunsAccount.DB_Enriched__c = 'Enriched';
					domesticUltimateDunsAccount.ParentId = globalUltimateDunsAccount.Id;
					resultingAccounts.add(domesticUltimateDunsAccount);
					System.debug('Domestic Ultimate Account: ' + domesticUltimateDunsAccount.Id + ' --- ' + domesticUltimateDunsAccount.DB_DUNS__c);
					upsert domesticUltimateDunsAccount;
				}
			}

			// Only Domestic Level Returned
			if(String.isNotBlank(domesticResult?.duns) && String.isBlank(globalResult?.duns)) {
				System.debug('Only domestic returned');

				domesticUltimateDunsAccount = setAccountValues(domesticUltimateDunsAccount, domesticResult);
				domesticUltimateDunsAccount.DB_Enriched__c = 'Enriched';
				resultingAccounts.add(domesticUltimateDunsAccount);
				System.debug('Domestic Ultimate Account: ' + domesticUltimateDunsAccount.Id + ' --- ' + domesticUltimateDunsAccount.DB_DUNS__c);
				upsert domesticUltimateDunsAccount;
			}

			// Only Global Level Returned
			if(String.isBlank(domesticResult?.duns) && String.isNotBlank(globalResult?.duns)) {
				System.debug('Only global returned');

				globalUltimateDunsAccount = setAccountValues(globalUltimateDunsAccount, globalResult);
				globalUltimateDunsAccount.DB_Enriched__c = 'Enriched';
				globalUltimateDunsAccount.ParentId = null;
				resultingAccounts.add(globalUltimateDunsAccount);
				System.debug('Global Ultimate Account: ' + globalUltimateDunsAccount.Id + ' --- ' + globalUltimateDunsAccount.DB_DUNS__c);
				upsert globalUltimateDunsAccount;
			}

			// Only Site Level Returned
			if(String.isBlank(domesticResult?.duns) && String.isBlank(globalResult?.duns) && String.isNotBlank(siteResult?.duns)) {
				System.debug('Only site returned');

				// No Existing Account Found
				if(siteLevelDunsAccount == null) {
					System.debug('Setting site level account to originating account: ' + wrapper.originating_Account.Id + ' --- ' + wrapper.originating_Account.DB_DUNS__c);
					siteLevelDunsAccount = wrapper.originating_Account;
				}

				siteLevelDunsAccount = setAccountValues(siteLevelDunsAccount, siteResult);
				siteLevelDunsAccount.DB_Enriched__c = 'Enriched';
				resultingAccounts.add(siteLevelDunsAccount);
				System.debug('Site Account: ' + siteLevelDunsAccount.Id + ' --- ' + siteLevelDunsAccount.DB_DUNS__c);
				upsert siteLevelDunsAccount;
			}
		} else {
			// More than one returned - don't do anything
			// DB_Enriched__c will default to "Not Enriched"
			// The flow Account_After_Insert_Update_D_B_Enrichment will set DB_Enriched__c to "Failed Enrichment"
			// Someone will have to run the Screen_Flow_Account_Enrichment flow to manually select the right one and then enrich it
		}

		System.debug('Resulting Accounts: ' + resultingAccounts);
		wrapper.account_Results = resultingAccounts;
		return wrapper;
	}

	public static Account setAccountValues(Account account, DunsResponseWrapper.CompanyDetail companyDetail) {
		// Set new account if null
		if(account == null) {
			account = new Account();
		}

		// Site Fields
		account.DB_Block_Id__c = companyDetail.blockID;
		account.DB_Block_Status__c = companyDetail.blockStatus;
		account.DB_Telephone_Number__c = companyDetail.telephoneNumber;
		account.DB_Start_Date__c = companyDetail.startDate;
		account.DB_Incorporated_Date__c = companyDetail.incorporatedDate;
		account.DB_Operating_Status__c = companyDetail.operatingStatus;
		account.DB_Address__CountryCode__s = companyDetail.countryCode;
		account.DB_Address__City__s = companyDetail.city;
		account.DB_Address__StateCode__s = isStateCodeValid(companyDetail.stateCode) ? companyDetail.stateCode : null;
		account.DB_Address__PostalCode__s = companyDetail.postalCode;
		account.DB_Address__Street__s = companyDetail.street;
		account.DB_Number_of_Employees_Scope__c = companyDetail.numberOfEmployeesScope;
		account.DB_Yearly_Revenue_Currency__c = companyDetail.yearlyRevenueCurrency;
		account.DB_Code__c = String.valueOf(companyDetail.dnbCode);
		account.DB_Number_of_Employees__c = companyDetail.numberOfEmployees;
		account.DB_Yearly_Revenue__c = String.isNotBlank(companyDetail.yearlyRevenue) ? Long.valueOf(companyDetail.yearlyRevenue) : null;
		if(companyDetail.websiteAddress != null) {
			account.DB_Website__c = companyDetail.websiteAddress.url;
		}

		// Set D&B fields if they're blank
		account.DB_Name__c = String.isBlank(account.DB_Name__c) ? companyDetail.primaryName : account.DB_Name__c;
		account.DB_DUNS__c = String.isBlank(account.DB_DUNS__c) ? companyDetail.duns : account.DB_DUNS__c;
		account.DB_Domestic_Ultimate_Name__c = String.isBlank(account.DB_Domestic_Ultimate_Name__c) ? companyDetail.primaryName : account.DB_Domestic_Ultimate_Name__c;
		account.DB_Domestic_Ultimate_DUNS__c = String.isBlank(account.DB_Domestic_Ultimate_DUNS__c) ? companyDetail.domesticUltimateDuns : account.DB_Domestic_Ultimate_DUNS__c;
		account.DB_Global_Ultimate_Name__c = String.isBlank(account.DB_Global_Ultimate_Name__c) ? companyDetail.primaryName : account.DB_Global_Ultimate_Name__c;
		account.DB_Global_Ultimate_DUNS__c = String.isBlank(account.DB_Global_Ultimate_DUNS__c) ? companyDetail.globalUltimateDuns : account.DB_Global_Ultimate_DUNS__c;

		// Set standard fields if they're blank
		account.Name = String.isBlank(account.Name) ? companyDetail.primaryName : account.Name;
		account.Phone = String.isBlank(account.Phone) ? companyDetail.telephoneNumber : account.Phone;
		account.Website = String.isBlank(account.Website) && companyDetail.websiteAddress != null ? companyDetail.websiteAddress.url : account.Website;
		account.BillingCountryCode = String.isBlank(account.BillingCountryCode) ? companyDetail.countryCode : account.BillingCountryCode;
		account.BillingCity = String.isBlank(account.BillingCity) ? companyDetail.city : account.BillingCity;
		account.BillingStateCode = String.isBlank(account.BillingStateCode) && isStateCodeValid(companyDetail.stateCode) ? companyDetail.stateCode : account.BillingStateCode;
		account.BillingPostalCode = String.isBlank(account.BillingPostalCode) ? companyDetail.postalCode : account.BillingPostalCode;
		account.BillingStreet = String.isBlank(account.BillingStreet) ? companyDetail.street : account.BillingStreet;

		return account;
	}

	public static Boolean isStateCodeValid(String stateCode) {
		if (String.isBlank(stateCode)) {
			return true;
		}

		Schema.DescribeFieldResult fieldDescribe = Account.BillingStateCode.getDescribe();
		for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
			if (picklistEntry.isActive() && String.valueOf(picklistEntry.getValue()).equalsIgnoreCase(stateCode)) {
				return true;
			}
		}

		return false;
	}

	public static String selectStar(String sObjectName, String whereCondition) {
		Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(sObjectName);
		Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
		Map<String, Schema.SObjectField> fieldsMap = describeResult.fields.getMap();
		List<String> fieldNames = new List<String>();
		for (String fieldName : fieldsMap.keySet()) {
			if (fieldsMap.get(fieldName).getDescribe().isAccessible()) { // Make sure it's accessible
				if(fieldsMap.get(fieldName).getDescribe().getType() != Schema.DisplayType.ADDRESS) { // Exclude Address fields
					if(fieldName != 'HS_Sync_Payload__c' && fieldName != 'Workday_Sync_Message__c' && fieldName != 'Workday_Sync_Payload__c') { // Other Exclusions
						fieldNames.add(fieldName);
					}
				}
			}
		}

		String query = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + sObjectName;
		
		if(String.isNotBlank(whereCondition)){
			query += ' WHERE ' + whereCondition;
		}

		// System.debug('selectStar: ' + query);
		return query;
    }

	public static Map<Integer, List<SObject>> assessDuplicates(List<SObject> recordsToCheck) {
		Map<Integer, List<SObject>> resultsMap = new Map<Integer, List<SObject>>(); // Key: Index of the input list, Value: List of matches found for that record
		Set<Id> allMatchedIds = new Set<Id>();

		// If no active rule exists for this object then return empty map
		String sObjectType = String.valueOf(recordsToCheck[0].getSObjectType());
		List<DuplicateRule> activeRules = [ SELECT Id, DeveloperName FROM DuplicateRule WHERE SObjectType = :sObjectType AND IsActive = true LIMIT 1];
		if(activeRules.size() == 0) { 
			System.debug('No active duplicate rules found for ' + sObjectType);
			return resultsMap;
		}
		
		// Find Duplicates
		List<Datacloud.FindDuplicatesResult> findResults = Datacloud.FindDuplicates.findDuplicates(recordsToCheck);
		for (Integer i = 0; i < findResults.size(); i++) {
			resultsMap.put(i, new List<SObject>());
			
			for (Datacloud.DuplicateResult dupeResult : findResults[i].getDuplicateResults()) {
				for (Datacloud.MatchResult matchResult : dupeResult.getMatchResults()) {
					if (matchResult.isSuccess()) {
						for (Datacloud.MatchRecord matchRecord : matchResult.getMatchRecords()) {
							SObject match = matchRecord.getRecord();
							resultsMap.get(i).add(match);
							allMatchedIds.add(match.Id);
						}
					}
				}
			}
		}
		
		// Re-query matches to get full field data and replace "partial" records in the map with "full" records
		if (allMatchedIds.size() > 0) {
			String sObjType = String.valueOf(recordsToCheck[0].getSObjectType());
			Map<Id, SObject> fullRecords = new Map<Id, SObject>(
				Database.query(selectStar(sObjType, 'Id IN :allMatchedIds'))
			);
			
			for (Integer index : resultsMap.keySet()) {
				List<SObject> partialList = resultsMap.get(index);
				List<SObject> fullList = new List<SObject>();
				for(SObject p : partialList) {
					fullList.add(fullRecords.get(p.Id));
				}
				resultsMap.put(index, fullList);
			}
		}

		return resultsMap;
	}
}