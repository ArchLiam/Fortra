@isTest
private class TerritoryFlowHelperTest {

	@isTest
    static void testNamedAccount() {
        // Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA');
        insert testLead;

		// Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Named_Account__c = testAccount.Id,
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			BDR__c = UserInfo.getUserId(),
			Country__c = null
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testIndustryAndCountry() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'Canada', CountryCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'Canada', BillingCountryCode = 'CA');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Industry__c = testAccount.Industry,
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Country__c = testLead.Country,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testIndustryAndStateZip() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA', PostalCode = '90001');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Industry__c = testAccount.Industry,
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Country__c = testLead.Country,
			State__c = testLead.StateCode,
			Zip_Code__c = testLead.PostalCode,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testIndustryAndState() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Industry__c = testAccount.Industry,
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Country__c = testLead.Country,
			State__c = testLead.StateCode,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testIndustry() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Industry__c = testAccount.Industry,
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			BDR__c = UserInfo.getUserId(),
			Country__c = null
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testCountryAndSolutionCategory() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'Canada', CountryCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power', Solution_Category__c = 'IPP');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
			Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Solution_Category__c = testProduct.Solution_Category__c,
			Country__c = testLead.Country,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testCountryAndSolutionGroup() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'Canada', CountryCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
			Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Country__c = testLead.Country,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testStateAndZipAndSolutionCategory() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA', PostalCode = '90001');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power', Solution_Category__c = 'IPP');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Solution_Category__c = testProduct.Solution_Category__c,
			Country__c = testLead.Country,
			State__c = testLead.StateCode,
			Zip_Code__c = testLead.PostalCode,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testStateAndZipAndSolutionGroup() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA', PostalCode = '90001');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Country__c = testLead.Country,
			State__c = testLead.StateCode,
			Zip_Code__c = testLead.PostalCode,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testStateAndSolutionCategory() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power', Solution_Category__c = 'IPP');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Solution_Category__c = testProduct.Solution_Category__c,
			Country__c = testLead.Country,
			State__c = testLead.StateCode,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testStateAndSolutionGroup() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Country__c = testLead.Country,
			State__c = testLead.StateCode,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	/*
	@isTest
    static void testGroupDefault() {
		// Create test Lead
        Lead testLead = new Lead(LastName = 'Test Lead', Company = 'Test Company', Country = 'United States', CountryCode = 'US');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
		System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }
	*/

	@isTest
    static void testUnitOnly() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Unit__c = testProduct.Unit__c,
			BDR__c = UserInfo.getUserId(),
			Country__c = null
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
		System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	@isTest
    static void testNoMatch() {
		Group unassociatedQueue = [SELECT Id FROM Group WHERE DeveloperName = 'Unassociated_Inquiries_Queue' LIMIT 1];

		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Unit__c = 'Cyber',
            Solution_Group__c = 'Defensive Security',
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(unassociatedQueue.Id, responses[0].productAssignments[0].OwnerId_Text__c);
    }

	// We shouldn't have a problem with bulkification and this doesn't work with the new duplicate rules
	/* @isTest
    static void testBulkTerritories() {
		Group unassociatedQueue = [SELECT Id FROM Group WHERE DeveloperName = 'Unassociated_Inquiries_Queue' LIMIT 1];

		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Company = 'Test Company', Country = 'United States', CountryCode = 'US');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA', BillingPostalCode = '90001');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

		// Create test Sales Territory
		List<Sales_Territory__c> territories = new List<Sales_Territory__c>();
		for(Integer i = 0; i < 500; i++) {
			// Create test Sales Territory
			Sales_Territory__c tempTerritory = new Sales_Territory__c(
				Name = 'Test Territory ' + i,
				Unit__c = 'Cyber',
				Solution_Group__c = 'Defensive Security',
				BDR__c = UserInfo.getUserId()
			);
			territories.add(tempTerritory);
		}
		insert territories;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(unassociatedQueue.Id, responses[0].productAssignments[0].OwnerId_Text__c);
    }
	*/

	@isTest
    static void testStateAndSolutionGroupNotification() {
		// Create test Lead
        Lead testLead = new Lead(Sales_Inquiry_Name__c = 'Test Lead', FirstName = 'Test', LastName = 'Lead', Email = 'test.lead@example.com', Company = 'Test Company', Country = 'United States', CountryCode = 'US', StateCode = 'CA');
        insert testLead;

        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Industry = 'Technology', BillingCountry = 'United States', BillingCountryCode = 'US', BillingStateCode = 'CA');
        insert testAccount;

        // Create test Marketing Product
        Marketing_Product__c testProduct = new Marketing_Product__c(Name = 'Test Product', Unit__c = 'Tech', Solution_Group__c = 'Power');
        insert testProduct;

        // Create test Sales Territory
		Sales_Territory__c testTerritory = new Sales_Territory__c(
            Name = 'Test Territory',
            Unit__c = testProduct.Unit__c,
            Solution_Group__c = testProduct.Solution_Group__c,
			Country__c = testAccount.BillingCountry,
			State__c = testAccount.BillingStateCode,
			BDR__c = UserInfo.getUserId()
        );
        insert testTerritory;

        // Request
        TerritoryFlowHelper.Request req1 = new TerritoryFlowHelper.Request();
        req1.account = testAccount;
		req1.lead = testLead;
        req1.marketingProducts = new List<Marketing_Product__c>{ testProduct };
		req1.processType = 'Notification';

        // Call method
        List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req1 });

        // Assertion
        System.assertEquals(testProduct.Id, responses[0].productAssignments[0].Marketing_Product__c);
		System.assertEquals(testTerritory.Id, responses[0].productAssignments[0].Sales_Territory__c);
    }

	/* Anonymous Apex
		String leadId = '00Qdp000008sW1VEAU';

		Lead lead = [SELECT Id, Account__c FROM Lead WHERE Id = :leadId];
		Account account = [SELECT Id, Industry FROM Account WHERE Id = :lead.Account__c];
		List<Product_of_Interest__c> productsOfInterest = [SELECT Id, Marketing_Product__c FROM Product_of_Interest__c WHERE Sales_Inquiry__c = :lead.Id];

		TerritoryFlowHelper.Request req = new TerritoryFlowHelper.Request();
        req.account = account;
		req.lead = lead;
        req.marketingProducts = new List<Marketing_Product__c>();

		Set<Id> productIds = new Set<Id>();
		for(Product_of_Interest__c poi : productsOfInterest) {
			productIds.add(poi.Marketing_Product__c);
		}
		req.marketingProducts = [SELECT Id, Unit__c, Solution_Group__c FROM Marketing_Product__c WHERE Id IN :productIds];

		List<TerritoryFlowHelper.Response> responses = TerritoryFlowHelper.getProductAssignments(new List<TerritoryFlowHelper.Request>{ req });
		System.debug('Responses: ' + responses);
	*/
}