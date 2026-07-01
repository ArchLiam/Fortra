public with sharing class TerritoryFlowHelper {
	public static final String tempId = Product_Assignment__c.sObjectType.getDescribe().getKeyPrefix() + '00000000000';

	@InvocableMethod(label='Get Product Assignments' description='Returns the product assignments for a given list of marketing products')
	public static List<Response> getProductAssignments(List<Request> requests) {
		//Variables
		List<Product_Assignment__c> productAssignments = new List<Product_Assignment__c>();
		List<Sales_Territory__c> salesTerritories = [SELECT Id, Name, Named_Account__c, Industry__c, Unit__c, Solution_Group__c, Solution_Category__c, Country__c, State__c, Zip_Code__c, Account_Executive__c, BDR__c FROM Sales_Territory__c];
		Group unassociatedQueue = [SELECT Id FROM Group WHERE DeveloperName = 'Unassociated_Inquiries_Queue' LIMIT 1];
		List<String> fieldNamesByPriority = new List<String>{'Solution_Category__c', 'Solution_Group__c', 'Unit__c'};
		TerritoryParametersWrapper params = new TerritoryParametersWrapper();

		// Pre-filtered lists
		List<Sales_Territory__c> namedAccountTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> industryTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> industryCountryTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> industryCountryStateTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> industryCountryStateZipTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> countryTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> countryStateTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> countryStateZipTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> solutionCategoryTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> solutionGroupTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> unitOnlyTerritories = new List<Sales_Territory__c>();
		List<Sales_Territory__c> groupDefaultTerritories = new List<Sales_Territory__c>();

		// Filter Lists
		for(Sales_Territory__c st : salesTerritories) {
			// Named Account
			if(st.Named_Account__c != null){
				System.debug('Named Account Territory: ' + st);
				namedAccountTerritories.add(st);
			}
			// Industry Only
			else if(st.Named_Account__c == null && st.Industry__c != null && st.Country__c == null && st.State__c == null && st.Zip_Code__c == null){
				System.debug('Industry Territory: ' + st);
				industryTerritories.add(st);
			}
			// Industry and Country
			else if(st.Named_Account__c == null && st.Industry__c != null && st.Country__c != null && st.State__c == null && st.Zip_Code__c == null) {
				System.debug('Industry and Country Territory: ' + st);
				industryCountryTerritories.add(st);
			}
			// Industry and Country and State
			else if(st.Named_Account__c == null && st.Industry__c != null && st.Country__c != null && st.State__c != null && st.Zip_Code__c == null) {
				System.debug('Industry and Country and State Territory: ' + st);
				industryCountryStateTerritories.add(st);
			}
			// Industry and Country, State, and Zip
			else if(st.Named_Account__c == null && st.Industry__c != null && st.Country__c != null && st.State__c != null && st.Zip_Code__c != null) {
				System.debug('Industry and Country, State, and Zip Territory: ' + st);
				industryCountryStateZipTerritories.add(st);
			}
			// Country
			else if(st.Named_Account__c == null && st.Industry__c == null && st.Country__c != null && st.State__c == null && st.Zip_Code__c == null) {
				System.debug('Country Territory: ' + st);
				countryTerritories.add(st);
			}
			// Country and State
			else if(st.Named_Account__c == null && st.Industry__c == null && st.Country__c != null && st.State__c != null && st.Zip_Code__c == null) {
				System.debug('Country and State Territory: ' + st);
				countryStateTerritories.add(st);
			}
			// Country, State, and Zip
			else if(st.Named_Account__c == null && st.Industry__c == null && st.Country__c != null && st.State__c != null && st.Zip_Code__c != null) {
				System.debug('Country, State, and Zip Territory: ' + st);
				countryStateZipTerritories.add(st);
			}
			// Solution Category
			else if(st.Named_Account__c == null && st.Industry__c == null && st.Country__c == null && st.State__c == null && st.Zip_Code__c == null && st.Unit__c != null && st.Solution_Group__c != null && st.Solution_Category__c != null ) {
				System.debug('Solution Category Territory: ' + st);
				solutionCategoryTerritories.add(st);
			}
			// Solution Group Only
			else if(st.Named_Account__c == null && st.Industry__c == null && st.Country__c == null && st.State__c == null && st.Zip_Code__c == null && st.Unit__c != null && st.Solution_Group__c != null && st.Solution_Category__c == null ) {
				System.debug('Solution Group Only Territory: ' + st);
				solutionGroupTerritories.add(st);
			}
			// Unit Only
			else if(st.Named_Account__c == null && st.Industry__c == null && st.Unit__c != null && st.Solution_Group__c == null && st.Solution_Category__c == null ) {
				System.debug('Unit Only Territory: ' + st);
				unitOnlyTerritories.add(st);
			}
			// Group Default
			else {
				System.debug('Group Default Territory: ' + st);
				groupDefaultTerritories.add(st);
			}
		}

		// Request Loop
		for(Request r : requests){
			Lead lead = r.lead;
			Account account = r.account; // lead.Account__c or lead.PartnerAccountId
			List<Marketing_Product__c> marketingProducts = r.marketingProducts;
			Boolean notificationProcess = r.processType == 'Notification' ? true : false;

			// Set Location Fields based on Process Type
			String resultingCountry, resultingStateCode, resultingPostalCode;
			if(notificationProcess) {
				resultingCountry = account.BillingCountry;
				resultingStateCode = account.BillingStateCode;
				resultingPostalCode = account.BillingPostalCode;
			} else {
				resultingCountry = lead.Country;
				resultingStateCode = lead.StateCode;
				resultingPostalCode = lead.PostalCode;
			}

			// Marketing Products Loop
			for (Integer i = 1; i <= marketingProducts.size(); i++) {
				Marketing_Product__c marketingProduct = marketingProducts[i - 1];
				Product_Assignment__c productAssignment;
				params.marketingProductId = marketingProduct.Id;
				params.index = i;

				for(String prioritizedField : fieldNamesByPriority){
					if(String.isBlank((String) marketingProduct.get(prioritizedField))) {
						// Continue if the prioritized field is blank
						continue;
					}

					// Set Category, Group, and Unit
					System.debug('Prioritized Field: ' + prioritizedField);
					if(prioritizedField == 'Solution_Category__c') {
						params.unit = marketingProduct.Unit__c;
						params.solutionGroup = marketingProduct.Solution_Group__c;
						params.solutionCategory = marketingProduct.Solution_Category__c;
					} else if(prioritizedField == 'Solution_Group__c') {
						params.unit = marketingProduct.Unit__c;
						params.solutionGroup = marketingProduct.Solution_Group__c;
						params.solutionCategory = null;
					} else if(prioritizedField == 'Unit__c') {
						params.unit = marketingProduct.Unit__c;
						params.solutionGroup = null;
						params.solutionCategory = null;
					}

					// Named Account
					System.debug('CHECKING: Named Account | ' + account.Id);
					if(String.isNotBlank(account.Id)){
						params.accountId = account.Id;
						params.industry = null;
						params.country = null;
						params.stateCode = null;
						params.zipCode = null;
						params.salesTerritories = namedAccountTerritories;
						productAssignment = checkTerritories(params);
						if(productAssignment != null) {
							productAssignments.add(productAssignment);
							System.debug('MATCHED: Named Account');
							break;
						}
					}

					// Industry Variations
					if(String.isNotBlank(account.Industry)){ 
						// Industry and Country
						System.debug('CHECKING: Industry and Country | ' + resultingCountry + ' | ' + resultingStateCode + ' | ' + resultingPostalCode);
						if(String.isNotBlank(resultingCountry) && String.isBlank(resultingStateCode) && String.isBlank(resultingPostalCode)){ 
							params.accountId = null;
							params.industry = account.Industry;
							params.country = resultingCountry;
							params.stateCode = null;
							params.zipCode = null;
							params.salesTerritories = industryCountryTerritories;
							productAssignment = checkTerritories(params);
							if(productAssignment != null) {
								productAssignments.add(productAssignment);
								System.debug('MATCHED: Industry and Country');
								break;
							}
						}

						// Industry and State/Zip
						System.debug('CHECKING: Industry and State/Zip | ' + resultingPostalCode);
						if(String.isNotBlank(resultingPostalCode)){ 
							params.accountId = null;
							params.industry = account.Industry;
							params.country = resultingCountry;
							params.stateCode = resultingStateCode;
							params.zipCode = resultingPostalCode;
							params.salesTerritories = industryCountryStateZipTerritories;
							productAssignment = checkTerritories(params);
							if(productAssignment != null) {
								productAssignments.add(productAssignment);
								System.debug('MATCHED: Industry and State/Zip');
								break;
							}
						}

						// Industry and State
						System.debug('CHECKING: Industry and State | ' + resultingStateCode + ' | ' + resultingPostalCode);
						if(String.isNotBlank(resultingStateCode) && String.isBlank(resultingPostalCode)){ 
							params.accountId = null;
							params.industry = account.Industry;
							params.country = resultingCountry;
							params.stateCode = resultingStateCode;
							params.zipCode = null;
							params.salesTerritories = industryCountryStateTerritories;
							productAssignment = checkTerritories(params);
							if(productAssignment != null) {
								productAssignments.add(productAssignment);
								System.debug('MATCHED: Industry and State');
								break;
							}
						}

						// Industry Only
						System.debug('CHECKING: Industry | ' + account.Industry);
						params.accountId = null;
						params.industry = account.Industry;
						params.country = null;
						params.stateCode = null;
						params.zipCode = null;
						params.salesTerritories = industryTerritories;
						productAssignment = checkTerritories(params);
						if(productAssignment != null) {
							productAssignments.add(productAssignment);
							System.debug('MATCHED: Industry');
							break;
						}
					}

					// Country
					System.debug('CHECKING: Country and ' + prioritizedField + ' | ' + resultingCountry + ' | ' + resultingStateCode + ' | ' + resultingPostalCode);
					if(String.isNotBlank(resultingCountry) && resultingCountry != 'United States' && String.isBlank(resultingStateCode) && String.isBlank(resultingPostalCode)){
						params.accountId = null;
						params.industry = null;
						params.country = resultingCountry;
						params.stateCode = null;
						params.zipCode = null;
						params.salesTerritories = countryTerritories;
						productAssignment = checkTerritories(params);
						if(productAssignment != null) {
							productAssignments.add(productAssignment);
							System.debug('MATCHED: Country and ' + prioritizedField);
							break;
						}
					}

					// State/Zip
					System.debug('CHECKING: State/Zip and ' + prioritizedField + ' | ' + resultingPostalCode);
					if(String.isNotBlank(resultingPostalCode)){
						params.accountId = null;
						params.industry = null;
						params.country = resultingCountry;
						params.stateCode = resultingStateCode;
						params.zipCode = resultingPostalCode;
						params.salesTerritories = countryStateZipTerritories;
						productAssignment = checkTerritories(params);
						if(productAssignment != null) {
							productAssignments.add(productAssignment);
							System.debug('MATCHED: State/Zip and ' + prioritizedField);
							break;
						}
					}

					// State
					System.debug('CHECKING: State and ' + prioritizedField + ' | ' + resultingStateCode);
					if(String.isNotBlank(resultingStateCode)){ // && String.isBlank(resultingPostalCode)){ // 2026-03-24 Removing to broaden scope
						params.accountId = null;
						params.industry = null;
						params.country = resultingCountry;
						params.stateCode = resultingStateCode;
						params.zipCode = null;
						params.salesTerritories = countryStateTerritories;
						productAssignment = checkTerritories(params);
						if(productAssignment != null) {
							productAssignments.add(productAssignment);
							System.debug('MATCHED: State and ' + prioritizedField);
							break;
						}
					}

					// Prioritized Field Only
					System.debug('CHECKING: Prioritized Field Only | ' + prioritizedField);
					params.accountId = null;
					params.industry = null;
					params.country = null;
					params.stateCode = null;
					params.zipCode = null;
					if(prioritizedField == 'Solution_Category__c') {
						params.salesTerritories = solutionCategoryTerritories;
					} else if(prioritizedField == 'Solution_Group__c') {
						params.salesTerritories = solutionGroupTerritories;
					}
					productAssignment = checkTerritories(params);
					if(productAssignment != null) {
						productAssignments.add(productAssignment);
						System.debug('MATCHED: ' + prioritizedField);
						break;
					}
				}

				// Exit second loop
				if(productAssignment != null) {
					continue;
				}

				// Unit
				System.debug('CHECKING: Unit Only | ' + marketingProduct.Unit__c);
				params.unit = marketingProduct.Unit__c;
				params.solutionGroup = null;
				params.solutionCategory = null;
				params.accountId = null;
				params.industry = null;
				params.country = null;
				params.stateCode = null;
				params.zipCode = null;
				params.salesTerritories = unitOnlyTerritories;
				productAssignment = checkTerritories(params);
				if(productAssignment != null) {
					productAssignments.add(productAssignment);
					System.debug('MATCHED: Unit Only');
					continue;
				}

				// Group Default
				System.debug('CHECKING: Group Default');
				params.unit = null;
				params.solutionGroup = null;
				params.solutionCategory = null;
				params.accountId = null;
				params.industry = null;
				params.country = null;
				params.stateCode = null;
				params.zipCode = null;
				params.salesTerritories = groupDefaultTerritories;
				productAssignment = checkTerritories(params);
				if(productAssignment != null) {
					productAssignments.add(productAssignment);
					System.debug('MATCHED: Group Default');
					continue;
				}

				/* No Matches */
				System.debug('CHECKING: No Match');
				productAssignment = new Product_Assignment__c(
					Marketing_Product__c = marketingProduct.Id,
					Sales_Territory__c = null,
					OwnerId_Text__c = unassociatedQueue.Id,
					Id = tempId + String.valueOf(params.index),
					Index__c = params.index
				);
				productAssignments.add(productAssignment);
				System.debug('MATCHED: No Match');
			}
		}

		Response response = new Response();
		response.productAssignments = productAssignments;
		return new List<Response>{ response };
	}

	public static Product_Assignment__c checkTerritories(TerritoryParametersWrapper params){
		for(Sales_Territory__c salesTerritory : params.salesTerritories) {
			System.debug('checkTerritory: ' + salesTerritory);
			System.debug('params.AccountId: ' + params.accountId);
			System.debug('params.Industry: ' + params.industry);
			System.debug('params.Unit: ' + params.unit);
			System.debug('params.SolutionGroup: ' + params.solutionGroup);
			System.debug('params.SolutionCategory: ' + params.solutionCategory);
			System.debug('params.Country: ' + params.country);
			System.debug('params.State: ' + params.stateCode);
			System.debug('params.ZipCode: ' + params.zipCode);
			if( salesTerritory.Named_Account__c == params.accountId && 
				salesTerritory.Industry__c == params.industry &&
				salesTerritory.Unit__c == params.unit &&
				salesTerritory.Solution_Group__c == params.solutionGroup &&
				salesTerritory.Solution_Category__c == params.solutionCategory &&
				salesTerritory.Country__c == params.country &&
				salesTerritory.State__c == params.stateCode &&
				salesTerritory.Zip_Code__c == params.zipCode
			) {
				Product_Assignment__c productAssignment = new Product_Assignment__c();
				productAssignment.Marketing_Product__c = params.marketingProductId;
				productAssignment.Sales_Territory__c = salesTerritory.Id;
				productAssignment.OwnerId_Text__c = null;
				productAssignment.Id = tempId + String.valueOf(params.index);
				productAssignment.Index__c = params.index;
				return productAssignment;
			}
		}
		return null;
	}

	public class Request {
		@InvocableVariable(defaultValue = 'Assignment' description = 'Assignment, CAM, or Notification')
		public String processType;

        @InvocableVariable(required = true description = 'Inquiry')
        public Lead lead;
		
		@InvocableVariable(required = true description = 'Account__c or PartnerAccountId')
        public Account account;

        @InvocableVariable(required = true)
        public List<Marketing_Product__c> marketingProducts;
    }

	public class Response {
        @InvocableVariable
        public List<Product_Assignment__c> productAssignments;
    }

	public class TerritoryParametersWrapper {
		public String accountId;
		public String industry;
		public String unit;
		public String solutionGroup;
		public String solutionCategory;
		public String country;
		public String stateCode;
		public String zipCode;
		public String marketingProductId;
		public List<Sales_Territory__c> salesTerritories;
		public Integer index;
	}
}