@isTest
public class QuoteCurrencyChangeService_FixedTest {
    
    @testSetup
    static void setup() {
        // Create test products
        Product2 testProduct1 = new Product2(
			IsActive = true,    
			Name = 'Test Product 1',
            ProductCode = 'TEST-001',
			QuantityUnitOfMeasure = 'Each'
        );
        Product2 testProduct2 = new Product2(
            IsActive = true,
			Name = 'Test Product 2',
            ProductCode = 'TEST-002',
			QuantityUnitOfMeasure = 'Each'
        );
        insert new List<Product2>{testProduct1, testProduct2};
        
        // Get standard price book
        Id standardPricebookId = Test.getStandardPricebookId();
        
        // Create PricebookEntries for USD
        PricebookEntry pbeUSD1 = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = testProduct1.Id,
            UnitPrice = 100.00,
            IsActive = true,
            CurrencyIsoCode = 'USD'
        );
        PricebookEntry pbeUSD2 = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = testProduct2.Id,
            UnitPrice = 200.00,
            IsActive = true,
            CurrencyIsoCode = 'USD'
        );
        
        // Create PricebookEntries for EUR
        PricebookEntry pbeEUR1 = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = testProduct1.Id,
            UnitPrice = 85.00,
            IsActive = true,
            CurrencyIsoCode = 'EUR'
        );
        PricebookEntry pbeEUR2 = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = testProduct2.Id,
            UnitPrice = 170.00,
            IsActive = true,
            CurrencyIsoCode = 'EUR'
        );
        
        // Create PricebookEntries for CAD (only for product1, to test missing PBE scenario)
        PricebookEntry pbeCAD1 = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = testProduct1.Id,
            UnitPrice = 130.00,
            IsActive = true,
            CurrencyIsoCode = 'CAD'
        );
        
        insert new List<PricebookEntry>{pbeUSD1, pbeUSD2, pbeEUR1, pbeEUR2, pbeCAD1};
        
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        // Create test opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            CurrencyIsoCode = 'USD'
        );
        insert testOpp;
        
        // Create test quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebookId,
            CurrencyIsoCode = 'USD'
        );
        insert testQuote;
        
        // Create test quote lines
        QuoteLineItem line1 = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = testProduct1.Id,
            PricebookEntryId = pbeUSD1.Id,
            Quantity = 10,
            UnitPrice = 100.00
        );
        QuoteLineItem line2 = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = testProduct2.Id,
            PricebookEntryId = pbeUSD2.Id,
            Quantity = 5,
            UnitPrice = 200.00
        );
        insert new List<QuoteLineItem>{line1, line2};
    }
    
    @isTest
    static void testSuccessfulCurrencyChangeUSDtoEUR() {
        // Get test quote
        Quote quote = [SELECT Id, CurrencyIsoCode FROM Quote LIMIT 1];
        System.assertEquals('USD', quote.CurrencyIsoCode, 'Quote should start in USD');
        
        // Create request
        QuoteCurrencyChangeService_Fixed.Request req = new QuoteCurrencyChangeService_Fixed.Request();
        req.quoteId = quote.Id;
        req.oldCurrency = 'USD';
        req.newCurrency = 'EUR';
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService_Fixed.Result> results = 
            QuoteCurrencyChangeService_Fixed.handleCurrencyChange(
                new List<QuoteCurrencyChangeService_Fixed.Request>{req}
            );
        Test.stopTest();
        
        // Verify results
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Operation should be successful');
        System.assert(results[0].message.contains('Successfully'), 'Success message should be returned');
        
        // Verify quote currency was updated
        Quote updatedQuote = [SELECT Id, CurrencyIsoCode FROM Quote WHERE Id = :quote.Id];
        System.assertEquals('EUR', updatedQuote.CurrencyIsoCode, 'Quote currency should be EUR');
        
        // Verify quote lines were recreated with EUR prices
        List<QuoteLineItem> newLines = [SELECT Id, UnitPrice, Product2Id 
                                        FROM QuoteLineItem 
                                        WHERE QuoteId = :quote.Id
                                        ORDER BY Product2Id];
        System.assertEquals(2, newLines.size(), 'Should have two quote lines');
        System.assertEquals(85.00, newLines[0].UnitPrice, 'First product should have EUR price');
        System.assertEquals(170.00, newLines[1].UnitPrice, 'Second product should have EUR price');
        
        // Verify audit task was created
        List<Task> auditTasks = [SELECT Id, Subject FROM Task WHERE WhatId = :quote.Id];
        System.assertEquals(1, auditTasks.size(), 'Should create audit task');
        System.assert(auditTasks[0].Subject.contains('USD to EUR'), 'Audit task should show currency change');
    }
    
    @isTest
    static void testPartialSuccessWithMissingPBE() {
        // Get test quote
        Quote quote = [SELECT Id, CurrencyIsoCode FROM Quote LIMIT 1];
        
        // Create request to change to CAD (only one product has CAD price)
        QuoteCurrencyChangeService_Fixed.Request req = new QuoteCurrencyChangeService_Fixed.Request();
        req.quoteId = quote.Id;
        req.oldCurrency = 'USD';
        req.newCurrency = 'CAD';
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService_Fixed.Result> results = 
            QuoteCurrencyChangeService_Fixed.handleCurrencyChange(
                new List<QuoteCurrencyChangeService_Fixed.Request>{req}
            );
        Test.stopTest();
        
        // Verify results
        System.assertEquals(true, results[0].success, 'Operation should be successful');
        
        // Verify only one line was created (product with CAD price)
        List<QuoteLineItem> newLines = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :quote.Id];
        System.assertEquals(1, newLines.size(), 'Should have only one quote line');
    }
    
    @isTest
    static void testCurrencyChangeWithNoLines() {
        // Get test quote and delete its lines
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        delete [SELECT Id FROM QuoteLineItem WHERE QuoteId = :quote.Id];
        
        // Create request
        QuoteCurrencyChangeService_Fixed.Request req = new QuoteCurrencyChangeService_Fixed.Request();
        req.quoteId = quote.Id;
        req.oldCurrency = 'USD';
        req.newCurrency = 'EUR';
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService_Fixed.Result> results = 
            QuoteCurrencyChangeService_Fixed.handleCurrencyChange(
                new List<QuoteCurrencyChangeService_Fixed.Request>{req}
            );
        Test.stopTest();
        
        // Verify results
        System.assertEquals(true, results[0].success, 'Operation should be successful');
        System.assert(results[0].message.contains('No quote lines'), 'Should indicate no lines to recalculate');
        
        // Verify quote currency was still updated
        Quote updatedQuote = [SELECT Id, CurrencyIsoCode FROM Quote WHERE Id = :quote.Id];
        System.assertEquals('EUR', updatedQuote.CurrencyIsoCode, 'Quote currency should be EUR');
    }
    
    @isTest
    static void testErrorHandling() {
        // Create request with invalid quote ID
        QuoteCurrencyChangeService_Fixed.Request req = new QuoteCurrencyChangeService_Fixed.Request();
        req.quoteId = '0Q0000000000000AAA'; // Invalid ID
        req.oldCurrency = 'USD';
        req.newCurrency = 'EUR';
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService_Fixed.Result> results = 
            QuoteCurrencyChangeService_Fixed.handleCurrencyChange(
                new List<QuoteCurrencyChangeService_Fixed.Request>{req}
            );
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, results[0].success, 'Operation should fail');
        System.assert(results[0].message.contains('Error'), 'Error message should be returned');
    }
    
    @isTest
    static void testBulkOperation() {
        // Create multiple quotes
        List<Quote> quotes = new List<Quote>();
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Id pricebookId = Test.getStandardPricebookId();
        
        for (Integer i = 0; i < 5; i++) {
            quotes.add(new Quote(
                Name = 'Test Quote ' + i,
                OpportunityId = opp.Id,
                Pricebook2Id = pricebookId,
                CurrencyIsoCode = 'USD'
            ));
        }
        insert quotes;
        
        // Create requests
        List<QuoteCurrencyChangeService_Fixed.Request> requests = new List<QuoteCurrencyChangeService_Fixed.Request>();
        for (Quote q : quotes) {
            QuoteCurrencyChangeService_Fixed.Request req = new QuoteCurrencyChangeService_Fixed.Request();
            req.quoteId = q.Id;
            req.oldCurrency = 'USD';
            req.newCurrency = 'EUR';
            requests.add(req);
        }
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService_Fixed.Result> results = 
            QuoteCurrencyChangeService_Fixed.handleCurrencyChange(requests);
        Test.stopTest();
        
        // Verify all operations succeeded
        System.assertEquals(5, results.size(), 'Should process all requests');
        for (QuoteCurrencyChangeService_Fixed.Result res : results) {
            System.assertEquals(true, res.success, 'All operations should succeed');
        }
    }
}