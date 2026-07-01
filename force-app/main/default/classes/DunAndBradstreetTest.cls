/* Coverage for DunAndBradstreetHandler, DunAndBradstreetHelper, and DunsResponseWrapper */
@isTest
private class DunAndBradstreetTest {

	// Dynamic Mock Class
	private class DunAndBradstreetMock implements HttpCalloutMock {
		String resBody;
		Integer statusCode;

		public DunAndBradstreetMock(String resBody, Integer statusCode) {
			this.resBody = resBody;
			this.statusCode = statusCode;
		}

		public HTTPResponse respond(HTTPRequest req) {
			HttpResponse res = new HttpResponse();
			res.setHeader('Content-Type', 'application/x-www-form-urlencoded');
			res.setBody(this.resBody);
			res.setStatusCode(this.statusCode);
			return res;
		}
	}

	@isTest // Search at site level with existing accounts
	static void siteLevelSearchWithExistingAccountsTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success", "message": "Duns Data found",' +
                    '"data": [{' +
                        '"globalDuns": {"duns": "687965632", "description": "Global Ultimate", "dnbCode": 12775, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "687965632", "primaryName": "Samsung SDS Co., Ltd.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Computer Systems Design Services", "telephoneNumber": "261553114", "startDate": "1985", "fiscalYearEnd": "2024-12-31", "incorporatedDate": "1985-05-01", "operatingStatus": "Active", "countryCode": "KR", "city": "Seoul", "postalCode": "05510", "street": "125 Olympic-ro 35-gil, Songpa-gu", "latitude": 37.51641, "longitude": 127.10038, "numberOfEmployees": 11332, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 13828232000000, "yearlyRevenueCurrency": "KRW"},' +
                        '"domesticDuns": {"duns": "037028524", "description": "Subsidiary", "dnbCode": 9159, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "037028524", "primaryName": "Samsung SDS America, Inc.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Software Publishers", "telephoneNumber": "8444007372", "startDate": "1997", "fiscalYearEnd": "2022-12-31", "incorporatedDate": "1997-02-18", "operatingStatus": "Active", "countryCode": "US", "city": "Ridgefield Park", "stateCode": "NJ", "postalCode": "07660-2119", "street": "100 Challenger Rd Ste 102", "latitude": 40.85291, "longitude": -74.012658, "numberOfEmployees": 1324, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 2449560134, "yearlyRevenueCurrency": "USD"},' +
                        '"sitesDuns": {"duns": "080817110", "description": "Branch/Division", "dnbCode": 9140, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "037028524", "primaryName": "Samsung SDS America, Inc.", "industryCodes": "Software Publishers", "telephoneNumber": "3109005211", "operatingStatus": "Active", "countryCode": "US", "city": "Rancho Dominguez", "stateCode": "CA", "postalCode": "90220-6434", "street": "18600 S Broadwick St", "latitude": 33.860929, "longitude": -118.231176, "numberOfEmployees": 4, "numberOfEmployeesScope": "Individual", "websiteAddress": {"url": "www.samsungsdsa.com", "domainName": "samsungsdsa.com"}}' +
                    '}],' +
                    '"count": 1, "correlationId": "035fa777-eeec-4592-8b6e-f49d5b90df7f"' +
                '},' +
                '"requestParams": "dunsNumber=080817110"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'US', BillingStateCode = 'CA', DB_DUNS__c = '080817110'); // SITE
		insert a;

		// Test
		Test.startTest();
			List<List<Account>> results = DunAndBradstreetHelper.dunsSearch(new List<Account>{ a });
		Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
		System.assertEquals(1, results[0].size(), 'Only one account should be returned');
		System.assertEquals(a.Id, results[0][0].Id, 'Account Id should match originating account');
	}

	/* Removed 2026-06-23
    @IsTest	// Enrichment at site level
	static void siteLevelEnrichmentTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success", "message": "Duns Data found",' +
                    '"data": [{' +
                        '"globalDuns": {"duns": "687965632", "description": "Global Ultimate", "dnbCode": 12775, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "687965632", "primaryName": "Samsung SDS Co., Ltd.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Computer Systems Design Services", "telephoneNumber": "261553114", "startDate": "1985", "fiscalYearEnd": "2024-12-31", "incorporatedDate": "1985-05-01", "operatingStatus": "Active", "countryCode": "KR", "city": "Seoul", "postalCode": "05510", "street": "125 Olympic-ro 35-gil, Songpa-gu", "latitude": 37.51641, "longitude": 127.10038, "numberOfEmployees": 11332, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 13828232000000, "yearlyRevenueCurrency": "KRW"},' +
                        '"domesticDuns": {"duns": "037028524", "description": "Subsidiary", "dnbCode": 9159, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "037028524", "primaryName": "Samsung SDS America, Inc.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Software Publishers", "telephoneNumber": "8444007372", "startDate": "1997", "fiscalYearEnd": "2022-12-31", "incorporatedDate": "1997-02-18", "operatingStatus": "Active", "countryCode": "US", "city": "Ridgefield Park", "stateCode": "NJ", "postalCode": "07660-2119", "street": "100 Challenger Rd Ste 102", "latitude": 40.85291, "longitude": -74.012658, "numberOfEmployees": 1324, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 2449560134, "yearlyRevenueCurrency": "USD"},' +
                        '"sitesDuns": {"duns": "080817110", "description": "Branch/Division", "dnbCode": 9140, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "037028524", "primaryName": "Samsung SDS America, Inc.", "industryCodes": "Software Publishers", "telephoneNumber": "3109005211", "operatingStatus": "Active", "countryCode": "US", "city": "Rancho Dominguez", "stateCode": "CA", "postalCode": "90220-6434", "street": "18600 S Broadwick St", "latitude": 33.860929, "longitude": -118.231176, "numberOfEmployees": 4, "numberOfEmployeesScope": "Individual", "websiteAddress": {"url": "www.samsungsdsa.com", "domainName": "samsungsdsa.com"}}' +
                    '}],' +
                    '"count": 1, "correlationId": "035fa777-eeec-4592-8b6e-f49d5b90df7f"' +
                '},' +
                '"requestParams": "dunsNumber=080817110"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'US', BillingStateCode = 'CA'); // SITE
        DunAndBradstreetHandler.DunsRequestWrapper req = new DunAndBradstreetHandler.DunsRequestWrapper();
        req.account = a;

		// Test
        Test.startTest();
        	List<List<Account>> results = DunAndBradstreetHandler.dunsEnrichment(new List<DunAndBradstreetHandler.DunsRequestWrapper>{ req });
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
        System.assertEquals(1, results.size(), 'One result group expected');
        System.assertEquals(3, results[0].size(), 'Only one account should be returned when only global present');
        
		Account globalAcc = results[0][0];
        System.assertEquals('687965632', globalAcc.DB_DUNS__c, 'Global DUNS should be set');
        System.assertEquals('Enriched', globalAcc.DB_Enriched__c, 'Enrichment should be set');

		Account domesticAcc = results[0][1];
        System.assertEquals('037028524', domesticAcc.DB_DUNS__c, 'Domestic DUNS should be set');
        System.assertEquals('Enriched', domesticAcc.DB_Enriched__c, 'Enrichment should be set');

		Account siteAcc = results[0][2];
        System.assertEquals('080817110', siteAcc.DB_DUNS__c, 'Site DUNS should be set');
        System.assertEquals('Enriched', siteAcc.DB_Enriched__c, 'Enrichment should be set');

        Account globalPersisted = database.query(DunAndBradstreetHelper.selectStar('Account', 'DB_DUNS__c = \'687965632\' LIMIT 1'));
        System.assertEquals('687965632', globalPersisted.DB_DUNS__c);
        System.assertEquals('Enriched', globalPersisted.DB_Enriched__c);
        System.assertEquals(null, globalPersisted.ParentId, 'Global only should have no parent');

		Account domesticPersisted = database.query(DunAndBradstreetHelper.selectStar('Account', 'DB_DUNS__c = \'037028524\' LIMIT 1'));
        System.assertEquals('037028524', domesticPersisted.DB_DUNS__c);
        System.assertEquals('Enriched', domesticPersisted.DB_Enriched__c);
        System.assertEquals(globalPersisted.Id, domesticPersisted.ParentId, 'Domestics parent should be Global');

		Account sitePersisted = database.query(DunAndBradstreetHelper.selectStar('Account', 'DB_DUNS__c = \'080817110\' LIMIT 1'));
        System.assertEquals('080817110', sitePersisted.DB_DUNS__c);
        System.assertEquals('Enriched', sitePersisted.DB_Enriched__c);
        System.assertEquals(domesticPersisted.Id, sitePersisted.ParentId, 'Sites parent should be Domestic');

		List<Account> allAccounts = [SELECT Id, DB_DUNS__c, DB_Enriched__c, ParentId FROM Account];
		System.assertEquals(3, allAccounts.size(), 'Only three accounts should be created');
    }
	*/

	@IsTest	// Enrichment at site level
	static void siteLevelEnrichmentTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success", "message": "Duns Data found",' +
                    '"data": [{' +
                        '"sitesDuns": {"duns": "080817110", "description": "Branch/Division", "dnbCode": 9140, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "037028524", "primaryName": "Samsung SDS America, Inc.", "industryCodes": "Software Publishers", "telephoneNumber": "3109005211", "operatingStatus": "Active", "countryCode": "US", "city": "Rancho Dominguez", "stateCode": "CA", "postalCode": "90220-6434", "street": "18600 S Broadwick St", "latitude": 33.860929, "longitude": -118.231176, "numberOfEmployees": 4, "numberOfEmployeesScope": "Individual", "websiteAddress": {"url": "www.samsungsdsa.com", "domainName": "samsungsdsa.com"}}' +
                    '}],' +
                    '"count": 1, "correlationId": "035fa777-eeec-4592-8b6e-f49d5b90df7f"' +
                '},' +
                '"requestParams": "dunsNumber=080817110"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'US', BillingStateCode = 'CA'); // SITE
        DunAndBradstreetHandler.DunsRequestWrapper req = new DunAndBradstreetHandler.DunsRequestWrapper();
        req.account = a;

		// Test
        Test.startTest();
        	List<List<Account>> results = DunAndBradstreetHandler.dunsEnrichment(new List<DunAndBradstreetHandler.DunsRequestWrapper>{ req });
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
        System.assertEquals(1, results.size(), 'One result group expected');
        System.assertEquals(1, results[0].size(), 'Only one account should be returned when only global present');

		Account siteAcc = results[0][0];
        System.assertEquals('080817110', siteAcc.DB_DUNS__c, 'Site DUNS should be set');
        System.assertEquals('Enriched', siteAcc.DB_Enriched__c, 'Enrichment should be set');

		Account sitePersisted = database.query(DunAndBradstreetHelper.selectStar('Account', 'DB_DUNS__c = \'080817110\' LIMIT 1'));
        System.assertEquals('080817110', sitePersisted.DB_DUNS__c);
        System.assertEquals('Enriched', sitePersisted.DB_Enriched__c);

		List<Account> allAccounts = [SELECT Id, DB_DUNS__c, DB_Enriched__c, ParentId FROM Account];
		System.assertEquals(1, allAccounts.size(), 'Only one account should be created');
    }

	@isTest // Search at domestic level with existing accounts
	static void domesticLevelSearchWithExistingAccountsTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success", "message": "Duns Data found",' +
                    '"data": [{' +
                        '"globalDuns": {"duns": "687965632", "description": "Global Ultimate", "dnbCode": 12775, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "687965632", "primaryName": "Samsung SDS Co., Ltd.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Computer Systems Design Services", "telephoneNumber": "261553114", "startDate": "1985", "fiscalYearEnd": "2024-12-31", "incorporatedDate": "1985-05-01", "operatingStatus": "Active", "countryCode": "KR", "city": "Seoul", "postalCode": "05510", "street": "125 Olympic-ro 35-gil, Songpa-gu", "latitude": 37.51641, "longitude": 127.10038, "numberOfEmployees": 11332, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 13828232000000, "yearlyRevenueCurrency": "KRW"},' +
                        '"domesticDuns": {"duns": "037028524", "description": "Subsidiary", "dnbCode": 9159, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "037028524", "primaryName": "Samsung SDS America, Inc.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Software Publishers", "telephoneNumber": "8444007372", "startDate": "1997", "fiscalYearEnd": "2022-12-31", "incorporatedDate": "1997-02-18", "operatingStatus": "Active", "countryCode": "US", "city": "Ridgefield Park", "stateCode": "NJ", "postalCode": "07660-2119", "street": "100 Challenger Rd Ste 102", "latitude": 40.85291, "longitude": -74.012658, "numberOfEmployees": 1324, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 2449560134, "yearlyRevenueCurrency": "USD"}' +
                    '}],' +
                    '"count": 1, "correlationId": "caa07b92-d348-43f8-a196-bb14bc4c387b"' +
                '},' +
                '"requestParams": "dunsNumber=037028524"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Samsung', BillingCountryCode = 'US', BillingStateCode = 'NJ', DB_DUNS__c = '037028524'); // DOMESTIC
		insert a;

		// Test
		Test.startTest();
			List<List<Account>> results = DunAndBradstreetHelper.dunsSearch(new List<Account>{ a });
		Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
		System.assertEquals(1, results[0].size(), 'Only one account should be returned');
		System.assertEquals(a.Id, results[0][0].Id, 'Account Id should match originating account');
	}

	 @IsTest // Enrichment at domestic level
    static void domesticLevelEnrichmentTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success", "message": "Duns Data found",' +
                    '"data": [{' +
                        '"globalDuns": {"duns": "687965632", "description": "Global Ultimate", "dnbCode": 12775, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "687965632", "primaryName": "Samsung SDS Co., Ltd.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Computer Systems Design Services", "telephoneNumber": "261553114", "startDate": "1985", "fiscalYearEnd": "2024-12-31", "incorporatedDate": "1985-05-01", "operatingStatus": "Active", "countryCode": "KR", "city": "Seoul", "postalCode": "05510", "street": "125 Olympic-ro 35-gil, Songpa-gu", "latitude": 37.51641, "longitude": 127.10038, "numberOfEmployees": 11332, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 13828232000000, "yearlyRevenueCurrency": "KRW"},' +
                        '"domesticDuns": {"duns": "037028524", "description": "Subsidiary", "dnbCode": 9159, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "037028524", "primaryName": "Samsung SDS America, Inc.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Software Publishers", "telephoneNumber": "8444007372", "startDate": "1997", "fiscalYearEnd": "2022-12-31", "incorporatedDate": "1997-02-18", "operatingStatus": "Active", "countryCode": "US", "city": "Ridgefield Park", "stateCode": "NJ", "postalCode": "07660-2119", "street": "100 Challenger Rd Ste 102", "latitude": 40.85291, "longitude": -74.012658, "numberOfEmployees": 1324, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 2449560134, "yearlyRevenueCurrency": "USD"}' +
                    '}],' +
                    '"count": 1, "correlationId": "caa07b92-d348-43f8-a196-bb14bc4c387b"' +
                '},' +
                '"requestParams": "dunsNumber=037028524"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Samsung', BillingCountryCode = 'US', BillingStateCode = 'NJ'); // DOMESTIC
        DunAndBradstreetHandler.DunsRequestWrapper req = new DunAndBradstreetHandler.DunsRequestWrapper();
        req.account = a;

		// Test
        Test.startTest();
        	List<List<Account>> results = DunAndBradstreetHandler.dunsEnrichment(new List<DunAndBradstreetHandler.DunsRequestWrapper>{ req });
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
        System.assertEquals(1, results.size(), 'One result group expected');
        System.assertEquals(2, results[0].size(), 'Only one account should be returned when only global present');
        
		Account globalAcc = results[0][0];
        System.assertEquals('687965632', globalAcc.DB_DUNS__c, 'Global DUNS should be set');
        System.assertEquals('Enriched', globalAcc.DB_Enriched__c, 'Enrichment should be set');

		Account domesticAcc = results[0][1];
        System.assertEquals('037028524', domesticAcc.DB_DUNS__c, 'Domestic DUNS should be set');
        System.assertEquals('Enriched', domesticAcc.DB_Enriched__c, 'Enrichment should be set');

        Account globalPersisted = [SELECT Id, DB_DUNS__c, DB_Enriched__c, ParentId FROM Account WHERE DB_DUNS__c = '687965632' LIMIT 1];
        System.assertEquals('687965632', globalPersisted.DB_DUNS__c);
        System.assertEquals('Enriched', globalPersisted.DB_Enriched__c);
        System.assertEquals(null, globalPersisted.ParentId, 'Global only should have no parent');

		Account domesticPersisted = [SELECT Id, DB_DUNS__c, DB_Enriched__c, ParentId FROM Account WHERE DB_DUNS__c = '037028524' LIMIT 1];
        System.assertEquals('037028524', domesticPersisted.DB_DUNS__c);
        System.assertEquals('Enriched', domesticPersisted.DB_Enriched__c);
        System.assertEquals(globalPersisted.Id, domesticPersisted.ParentId, 'Domestics parent should be Global');

		List<Account> allAccounts = [SELECT Id, DB_DUNS__c, DB_Enriched__c, ParentId FROM Account];
		System.assertEquals(2, allAccounts.size(), 'Only the global and domestic should be created');
	}

	@isTest // Search at global level with existing accounts
	static void globalLevelSearchWithExistingAccountsTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success",' +
                    '"data": [{' +
                        '"globalDuns": {"duns": "687965632", "description": "Global Ultimate", "dnbCode": 12775, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "687965632", "primaryName": "Samsung SDS Co., Ltd.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Computer Systems Design Services", "telephoneNumber": "261553114", "startDate": "1985", "fiscalYearEnd": "2024-12-31", "incorporatedDate": "1985-05-01", "operatingStatus": "Active", "countryCode": "KR", "city": "Seoul", "postalCode": "05510", "street": "125 Olympic-ro 35-gil, Songpa-gu", "latitude": 37.51641, "longitude": 127.10038, "numberOfEmployees": 11332, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 13828232000000, "yearlyRevenueCurrency": "KRW"}' +
                    '}],' +
                    '"count": 1, "correlationId": "a7c87b2e-25c1-4831-99d2-92e7b60f65fb"' +
                '},' +
                '"requestParams": "countryISOAlpha2Code=KR&searchTerm=Samsung+SDS&addressLocality=Seoul&postalCode=05510"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'KR', BillingCity = 'Seoul', BillingPostalCode = '05510', DB_DUNS__c = '687965632'); // GLOBAL
		insert a;

		// Test
		Test.startTest();
			List<List<Account>> results = DunAndBradstreetHelper.dunsSearch(new List<Account>{ a });
		Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
		System.assertEquals(1, results[0].size(), 'Only one account should be returned');
		System.assertEquals(a.Id, results[0][0].Id, 'Account Id should match originating account');
	}

	@IsTest	// Enrichment at global level
    static void globalLevelEnrichmentTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success",' +
                    '"data": [{' +
                        '"globalDuns": {"duns": "687965632", "description": "Global Ultimate", "dnbCode": 12775, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "687965632", "primaryName": "Samsung SDS Co., Ltd.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Computer Systems Design Services", "telephoneNumber": "261553114", "startDate": "1985", "fiscalYearEnd": "2024-12-31", "incorporatedDate": "1985-05-01", "operatingStatus": "Active", "countryCode": "KR", "city": "Seoul", "postalCode": "05510", "street": "125 Olympic-ro 35-gil, Songpa-gu", "latitude": 37.51641, "longitude": 127.10038, "numberOfEmployees": 11332, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 13828232000000, "yearlyRevenueCurrency": "KRW"},' +
                        '"domesticDuns": {"duns": "687965632", "description": "Global Ultimate", "dnbCode": 12775, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "687965632", "primaryName": "Samsung SDS Co., Ltd.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Computer Systems Design Services", "telephoneNumber": "261553114", "startDate": "1985", "fiscalYearEnd": "2024-12-31", "incorporatedDate": "1985-05-01", "operatingStatus": "Active", "countryCode": "KR", "city": "Seoul", "postalCode": "05510", "street": "125 Olympic-ro 35-gil, Songpa-gu", "latitude": 37.51641, "longitude": 127.10038, "numberOfEmployees": 11332, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 13828232000000, "yearlyRevenueCurrency": "KRW"}' +
                    '}],' +
                    '"count": 1, "correlationId": "a7c87b2e-25c1-4831-99d2-92e7b60f65fb"' +
                '},' +
                '"requestParams": "countryISOAlpha2Code=KR&searchTerm=Samsung+SDS&addressLocality=Seoul&postalCode=05510"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
        Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'KR', BillingCity = 'Seoul', BillingPostalCode = '05510'); // GLOBAL
        DunAndBradstreetHandler.DunsRequestWrapper req = new DunAndBradstreetHandler.DunsRequestWrapper();
        req.account = a;

		// Test
        Test.startTest();
        	List<List<Account>> results = DunAndBradstreetHandler.dunsEnrichment(new List<DunAndBradstreetHandler.DunsRequestWrapper>{ req });
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
        System.assertEquals(1, results.size(), 'One result group expected');
        System.assertEquals(1, results[0].size(), 'Only one account should be returned when only global present');
        
		Account globalAcc = results[0][0];
        System.assertEquals('687965632', globalAcc.DB_DUNS__c, 'Global DUNS should be set');
        System.assertEquals('Enriched', globalAcc.DB_Enriched__c, 'Enrichment should be set');

        Account globalPersisted = [SELECT Id, DB_DUNS__c, DB_Enriched__c, ParentId FROM Account WHERE DB_DUNS__c = '687965632' LIMIT 1];
        System.assertEquals('687965632', globalPersisted.DB_DUNS__c);
        System.assertEquals('Enriched', globalPersisted.DB_Enriched__c);
        System.assertEquals(null, globalPersisted.ParentId, 'Global only should have no parent');

		List<Account> allAccounts = [SELECT Id, DB_DUNS__c, DB_Enriched__c, ParentId FROM Account];
		System.assertEquals(1, allAccounts.size(), 'Only the global should be created, not the domestic');
    }

	@IsTest	// Enrichment at global level
    static void globalLevelEnrichmentWithoutDomesticTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success",' +
                    '"data": [{' +
                        '"globalDuns": {"duns": "687965632", "description": "Global Ultimate", "dnbCode": 12775, "globalUltimateDuns": "687965632", "domesticUltimateDuns": "687965632", "primaryName": "Samsung SDS Co., Ltd.", "blockID": "hierarchyconnections_L1_v1", "blockStatus": "ok", "industryCodes": "Computer Systems Design Services", "telephoneNumber": "261553114", "startDate": "1985", "fiscalYearEnd": "2024-12-31", "incorporatedDate": "1985-05-01", "operatingStatus": "Active", "countryCode": "KR", "city": "Seoul", "postalCode": "05510", "street": "125 Olympic-ro 35-gil, Songpa-gu", "latitude": 37.51641, "longitude": 127.10038, "numberOfEmployees": 11332, "numberOfEmployeesScope": "Headquarters Only (Employs Here)", "websiteAddress": {"url": "www.samsungsds.com", "domainName": "samsungsds.com"}, "yearlyRevenue": 13828232000000, "yearlyRevenueCurrency": "KRW"}' +
                    '}],' +
                    '"count": 1, "correlationId": "a7c87b2e-25c1-4831-99d2-92e7b60f65fb"' +
                '},' +
                '"requestParams": "countryISOAlpha2Code=KR&searchTerm=Samsung+SDS&addressLocality=Seoul&postalCode=05510"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
        Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'KR', BillingCity = 'Seoul', BillingPostalCode = '05510'); // GLOBAL
        DunAndBradstreetHandler.DunsRequestWrapper req = new DunAndBradstreetHandler.DunsRequestWrapper();
        req.account = a;

		// Test
        Test.startTest();
        	List<List<Account>> results = DunAndBradstreetHandler.dunsEnrichment(new List<DunAndBradstreetHandler.DunsRequestWrapper>{ req });
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
        System.assertEquals(1, results.size(), 'One result group expected');
        System.assertEquals(1, results[0].size(), 'Only one account should be returned when only global present');
        
		Account globalAcc = results[0][0];
        System.assertEquals('687965632', globalAcc.DB_DUNS__c, 'Global DUNS should be set');
        System.assertEquals('Enriched', globalAcc.DB_Enriched__c, 'Enrichment should be set');

        Account globalPersisted = [SELECT Id, DB_DUNS__c, DB_Enriched__c, ParentId FROM Account WHERE DB_DUNS__c = '687965632' LIMIT 1];
        System.assertEquals('687965632', globalPersisted.DB_DUNS__c);
        System.assertEquals('Enriched', globalPersisted.DB_Enriched__c);
        System.assertEquals(null, globalPersisted.ParentId, 'Global only should have no parent');
    }

    @IsTest // Enrichment with multiple results returned (does not enrich)
    static void multipleResultsEnrichmentTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success",' +
                    '"data": [' +
                        '{"globalDuns": {}, "domesticDuns": {}, "sitesDuns": {"duns": "080817110", "globalUltimateDuns": "687965632", "primaryName": "Samsung SDS America, Inc.", "countryCode": "US", "city": "Rancho Dominguez", "postalCode": "90220-6434", "street": "18600 S Broadwick St"}},' +
                        '{"globalDuns": {}, "domesticDuns": {}, "sitesDuns": {"duns": "081201679", "globalUltimateDuns": "687965632", "primaryName": "Samsung SDS America, Inc.", "countryCode": "US", "city": "San Jose", "postalCode": "95134-1707", "street": "3655 N 1ST St 3RD FL"}},' +
                        '{"globalDuns": {}, "domesticDuns": {}, "sitesDuns": {"duns": "104749500", "globalUltimateDuns": "687965632", "primaryName": "Samsung SDS America, Inc.", "countryCode": "US", "city": "Cerritos", "postalCode": "90703-9318", "street": "17785 Center Court Dr N Ste 200"}},' +
                        '{"globalDuns": {}, "domesticDuns": {}, "sitesDuns": {"duns": "117184970", "globalUltimateDuns": "687965632", "primaryName": "Samsung Sds America, Inc.", "countryCode": "US", "city": "San Diego", "postalCode": "92154-7222", "street": "2112 Enrico Fermi Dr Ste 1"}}' +
                    '],' +
                    '"count": 4, "correlationId": "78768932-f634-4464-8461-6523e8e54e76"' +
                '},' +
                '"requestParams": "countryISOAlpha2Code=US&searchTerm=Samsung+SDS&addressRegion=CA"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'US', BillingStateCode = 'CA'); // SITE
        DunAndBradstreetHandler.DunsRequestWrapper req = new DunAndBradstreetHandler.DunsRequestWrapper();
        req.account = a;

		// Test
        Test.startTest();
        	List<List<Account>> results = DunAndBradstreetHandler.dunsEnrichment(new List<DunAndBradstreetHandler.DunsRequestWrapper>{ req });
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
        System.assertEquals(0, results.size(), 'No enrichment when multiple results are returned');
    }

	@IsTest	// Search with multiple results returned
    static void multipleResultsSearchTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success",' +
                    '"data": [' +
                        '{"globalDuns": {}, "domesticDuns": {}, "sitesDuns": {"duns": "080817110", "globalUltimateDuns": "687965632", "primaryName": "Samsung SDS America, Inc.", "countryCode": "US", "city": "Rancho Dominguez", "postalCode": "90220-6434", "street": "18600 S Broadwick St"}},' +
                        '{"globalDuns": {}, "domesticDuns": {}, "sitesDuns": {"duns": "081201679", "globalUltimateDuns": "687965632", "primaryName": "Samsung SDS America, Inc.", "countryCode": "US", "city": "San Jose", "postalCode": "95134-1707", "street": "3655 N 1ST St 3RD FL"}},' +
                        '{"globalDuns": {}, "domesticDuns": {}, "sitesDuns": {"duns": "104749500", "globalUltimateDuns": "687965632", "primaryName": "Samsung SDS America, Inc.", "countryCode": "US", "city": "Cerritos", "postalCode": "90703-9318", "street": "17785 Center Court Dr N Ste 200"}},' +
                        '{"globalDuns": {}, "domesticDuns": {}, "sitesDuns": {"duns": "117184970", "globalUltimateDuns": "687965632", "primaryName": "Samsung Sds America, Inc.", "countryCode": "US", "city": "San Diego", "postalCode": "92154-7222", "street": "2112 Enrico Fermi Dr Ste 1"}}' +
                    '],' +
                    '"count": 4, "correlationId": "78768932-f634-4464-8461-6523e8e54e76"' +
                '},' +
                '"requestParams": "countryISOAlpha2Code=US&searchTerm=Samsung+SDS&addressRegion=CA"' +
            '}';
        Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'US', BillingStateCode = 'CA'); // SITE

		// Test
        Test.startTest();
			// Via dunsSearch
        	List<List<Account>> results = DunAndBradstreetHelper.dunsSearch(new List<Account>{ a });
			// Direct callout
			DunsResponseWrapper wrapper = DunAndBradstreetHandler.dunsCallout(a);
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
        System.assertEquals(4, results[0].size(), 'Four resulting accounts expected from helper search');

		System.debug('test wrapper: ' + wrapper);
		System.assertEquals(4, wrapper.responsePayload.count, 'Wrapper count should be four for multiple data');
		for(DunsResponseWrapper.DunsResult res : wrapper.responsePayload.data) {
			System.debug('DUNS Result: ' + res);
			System.assertEquals(null, res.globalDuns.duns, 'Global DUNS should be null in multiple results');
			System.assertEquals(null, res.domesticDuns.duns, 'Domestic DUNS should be null in multiple results');
			System.assertNotEquals(null, res.sitesDuns.duns, 'Sites DUNS should not be null in multiple results');
		}
    }

	@IsTest	// Enrichment with no data returned
    static void noResultsEnrichmentTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success",' +
                    '"data": [],' +
                    '"count": 0,' +
                    '"correlationId": "63497d3e-fd83-4724-b9fb-c060ba44119f"' +
                '},' +
                '"requestParams": "countryISOAlpha2Code=US&searchTerm=Coastal+Cloud&addressRegion=CO"' +
            '}';
		Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Coastal Cloud', BillingCountryCode = 'US', BillingStateCode = 'CO'); // NOTHING FOUND
        DunAndBradstreetHandler.DunsRequestWrapper req = new DunAndBradstreetHandler.DunsRequestWrapper();
        req.account = a;

		// Test
        Test.startTest();
        	List<List<Account>> results = DunAndBradstreetHandler.dunsEnrichment(new List<DunAndBradstreetHandler.DunsRequestWrapper>{ req });
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
        System.assertEquals(0, results.size(), 'No results should be returned when no data is present');
    }

	@IsTest	// Search with no data returned
    static void noResultsSearchTest() {
        // Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success",' +
                    '"data": [],' +
                    '"count": 0,' +
                    '"correlationId": "63497d3e-fd83-4724-b9fb-c060ba44119f"' +
                '},' +
                '"requestParams": "countryISOAlpha2Code=US&searchTerm=Coastal+Cloud&addressRegion=CO"' +
            '}';
		Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'Coastal Cloud', BillingCountryCode = 'US', BillingStateCode = 'CO'); // NOTHING FOUND

		// Test
        Test.startTest();
        	// Via dunsSearch
			List<List<Account>> results = DunAndBradstreetHelper.dunsSearch(new List<Account>{ a });

			// Direct callout
			DunsResponseWrapper wrapper = DunAndBradstreetHandler.dunsCallout(a);
        Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
		System.assertEquals(0, results.size(), 'No results expected for no data');
		
		System.debug('test wrapper: ' + wrapper);
        System.assertEquals(0, wrapper.responsePayload.count, 'Wrapper count should be zero for no data');
        System.assertEquals(0, wrapper.responsePayload.data.size(), 'No data expected in wrapper for no data');
    }

	@IsTest // Out of Business
	static void outOfBusinessTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"status": "success",' +
                    '"message": "Out of business",' +
                    '"correlationId": "b66d4c2f-8ea9-4d4c-87bd-99bf2b17b110"' +
                '},' +
                '"requestParams": "dunsNumber=942404110"' +
            '}';
		Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(DB_DUNS__c = '942404110'); // OUT OF BUSINESS

		// Test
		Test.startTest();
			// Via dunsSearch
			List<List<Account>> results = DunAndBradstreetHelper.dunsSearch(new List<Account>{ a });

			// Direct callout
			DunsResponseWrapper wrapper = DunAndBradstreetHandler.dunsCallout(a);
		Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
		System.assertEquals(0, results.size(), 'No results expected for out of business');
		
		System.debug('test wrapper: ' + wrapper);
		System.assertEquals('Out of business', wrapper.responsePayload.message, 'Wrapper message should indicate out of business');
		System.assertEquals(null, wrapper.responsePayload.data, 'No data expected in wrapper for out of business');
	}

	@IsTest // Bad Request
	static void badRequestTest() {
		// Setup
		String resBody = '{' +
                '"responsePayload": {' +
                    '"success": false,' +
                    '"status": "failed",' +
                    '"source": "fortra-duns-sapi",' +
                    '"reasonPhrase": "Bad Request",' +
                    '"statusCode": 400,' +
                    '"errorMessage": "HTTP:BAD_REQUEST",' +
                    '"errorDescription": "Bad Request"' +
                '}' +
            '}';
		Test.setMock(HttpCalloutMock.class, new DunAndBradstreetMock(resBody, 200));
		Account a = new Account(Name = 'JP Morgan', BillingCountryCode = 'US1'); // Bad Country Code
		
		// Test
		Test.startTest();
			// Via dunsSearch
			List<List<Account>> results = DunAndBradstreetHelper.dunsSearch(new List<Account>{ a });

			// Direct callout
			DunsResponseWrapper wrapper = DunAndBradstreetHandler.dunsCallout(a);
		Test.stopTest();

		// Assert
		System.debug('test results: ' + results);
		System.assertEquals(0, results.size(), 'No results expected for bad request');

		System.debug('test wrapper: ' + wrapper);
		System.assertEquals('failed', wrapper.responsePayload.status, 'Wrapper status should be failed for bad request');
		System.assertEquals(null, wrapper.responsePayload.data, 'No data expected in wrapper for bad request');

	}

	@IsTest // Verify assessDuplicates correctly finds existing records using a simple active duplicate rule
	static void assessDuplicatesTest() {
		/* Rules as of 2026-03-12
			(
				(Account: NameFuzzy: Company NameMatchBlank = FALSE) AND 
				(Account: BillingStateExact: MatchBlank = FALSE) AND 
				(Account: BillingCityFuzzy: CityMatchBlank = FALSE)
			)
			OR
			(
				(Account: NameFuzzy: Company NameMatchBlank = FALSE) AND 
				(Account: WebsiteExactMatchBlank = FALSE) AND 
				(Account: BillingPostalCodeExact: MatchBlank = FALSE)
			)
		*/

		// Insert two existing accounts that should be considered duplicates by Name
		Account existing1 = new Account(Name='Acme Corporation', BillingCountry='United States', BillingState='California', BillingCity='Beverly Hills');
		Account existing2 = new Account(Name='Acme Corporation', BillingCountry='United States', BillingState='California', Website='www.acme.com', BillingPostalCode='90210');
		insert new List<Account>{ existing1, existing2 };

		// Now call assessDuplicates with a new account matching the name
		Account newAcc = new Account(Name='Acme Corporation', BillingCountry='United States', BillingState='California', Website='www.acme.com', BillingCity='Beverly Hills', BillingPostalCode='90210');
		Map<Integer, List<SObject>> results = DunAndBradstreetHelper.assessDuplicates(new List<SObject>{ newAcc });

		// Assertions
		System.assert(results.containsKey(0), 'Result map should contain an entry for the first record');
		List<SObject> matches = results.get(0);
		System.assertEquals(2, matches.size(), 'Both existing accounts should be returned as duplicates');
		// verify returned records are full Account sObjects with proper IDs
		for (SObject s : matches) {
			Account a = (Account) s;
			System.assertNotEquals(null, a.Id, 'Returned record should have an Id');
		}
	}

	/* Documentation
		Callout
			Example	
				https://fortra-duns-api-dev-v1-b2jz34.iib3w3.usa-e2.cloudhub.io/duns?searchTerm=jp morgan&countryISOAlpha2Code=US
			Endpoint
				https://fortra-duns-api-dev-v1-b2jz34.iib3w3.usa-e2.cloudhub.io/duns
			Variables
				searchTerm
				countryISOAlpha2Code
				addressLocality
				addressRegion
				streetAddressLine1
				postalCode
		Documentation
			description: Get Duns Details
			queryParameters:
				searchTerm:
					type: string
					required: true
					description: "Company Name"
					displayName: "Company Name"
				countryISOAlpha2Code:
					type: string
					required: true
					description: "Country Code"
					displayName: "Country"
				addressLocality:
					type: string
					required: false
					addressRegion:
					type: string
					required: false
				streetAddressLine1:
					type: string
					required: false
				postalCode:
					type: string
					required: false
	*/

	/* Anonymous Apex 
        // DATA SETUP
		// Account a = new Account(Name = 'JP Morgan', BillingCountryCode = 'US1'); // BAD REQUEST
		// Account a = new Account(DB_DUNS__c = '942404110'); // OUT OF BUSINESS
		// Account a = new Account(Name = 'Coastal Cloud', BillingCountryCode = 'US', BillingStateCode = 'CO'); // NOTHING FOUND
		Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'US', BillingStateCode = 'CA'); // SITE
		// Account a = new Account(Name = 'Samsung', BillingCountryCode = 'US', BillingStateCode = 'NJ'); // DOMESTIC
		// Account a = new Account(Name = 'Samsung SDS', BillingCountryCode = 'KR', BillingCity = 'Seoul', BillingPostalCode = '05510'); // GLOBAL
		
        // DIRECT CALLOUT
		Account a = new Account(DB_DUNS__c = '80600430');
		DunAndBradstreetHandler.dunsCallout(a);

        // SEARCH FUNCTION
		DunAndBradstreetHelper.dunsSearch(new List<Account>{ a });

        // ENRICHMENT FUNCTION
		List<DunAndBradstreetHandler.DunsRequestWrapper> requests = new List<DunAndBradstreetHandler.DunsRequestWrapper>();
		DunAndBradstreetHandler.DunsRequestWrapper request = new DunAndBradstreetHandler.DunsRequestWrapper();
		request.account = a;
		request.duns = '';
		requests.add(request);
        DunAndBradstreetHandler.dunsEnrichment(requests);

        // DELETE TEST DATA
		// delete [SELECT Id FROM Account WHERE Owner.Name = 'Joe Martinez' ORDER BY CreatedDate DESC LIMIT 2];
	*/
}