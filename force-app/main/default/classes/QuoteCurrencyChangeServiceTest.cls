@isTest
public class QuoteCurrencyChangeServiceTest {
    
    @testSetup
    static void setup() {
        // Create test product
        Product2 testProduct = new Product2(
			IsActive = true,    
			Name = 'Test Product',
            ProductCode = 'TEST-001',
			QuantityUnitOfMeasure = 'Each'
        );
        insert testProduct;
        
        // Create standard price book entry
        Id standardPricebookId = Test.getStandardPricebookId();
        
        PricebookEntry standardPrice = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100.00,
            IsActive = true,
            CurrencyIsoCode = 'USD'
        );
        insert standardPrice;
        
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
        
        // Create test quote line
        QuoteLineItem testLine = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = testProduct.Id,
            PricebookEntryId = standardPrice.Id,
            Quantity = 10,
            UnitPrice = 100.00
        );
        insert testLine;
    }
    
    @isTest
    static void testSuccessfulCurrencyChange() {
        // Get test quote
        Quote quote = [SELECT Id, CurrencyIsoCode FROM Quote LIMIT 1];
        
        // Create request
        QuoteCurrencyChangeService.Request req = new QuoteCurrencyChangeService.Request();
        req.quoteId = quote.Id;
        req.oldCurrency = 'USD';
        req.newCurrency = 'EUR';
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService.Result> results = 
            QuoteCurrencyChangeService.handleCurrencyChange(new List<QuoteCurrencyChangeService.Request>{req});
        Test.stopTest();
        
        // Verify results
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Operation should be successful');
        System.assert(results[0].message.contains('Successfully recalculated'), 'Success message should be returned');
        
        // Verify quote lines were recreated
        List<QuoteLineItem> newLines = [SELECT Id FROM QuoteLineItem 
                                        WHERE QuoteId = :quote.Id];
        System.assertEquals(1, newLines.size(), 'Should have one quote line');
        // Note: CurrencyIsoCode is inherited from parent Quote
        
        // Verify audit task was created
        List<Task> auditTasks = [SELECT Id, Subject FROM Task WHERE WhatId = :quote.Id];
        System.assertEquals(1, auditTasks.size(), 'Should create audit task');
        System.assert(auditTasks[0].Subject.contains('USD to EUR'), 'Audit task should show currency change');
    }
    
    @isTest
    static void testCurrencyChangeWithNoLines() {
        // Get test quote and delete its lines
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        delete [SELECT Id FROM QuoteLineItem WHERE QuoteId = :quote.Id];
        
        // Create request
        QuoteCurrencyChangeService.Request req = new QuoteCurrencyChangeService.Request();
        req.quoteId = quote.Id;
        req.oldCurrency = 'USD';
        req.newCurrency = 'CAD';
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService.Result> results = 
            QuoteCurrencyChangeService.handleCurrencyChange(new List<QuoteCurrencyChangeService.Request>{req});
        Test.stopTest();
        
        // Verify results
        System.assertEquals(true, results[0].success, 'Operation should be successful');
        System.assert(results[0].message.contains('No quote lines'), 'Should indicate no lines to recalculate');
    }
    
    @isTest
    static void testErrorHandling() {
        // Create request with invalid quote ID
        QuoteCurrencyChangeService.Request req = new QuoteCurrencyChangeService.Request();
        req.quoteId = '0Q0000000000000AAA'; // Invalid ID pattern for Quote
        req.oldCurrency = 'USD';
        req.newCurrency = 'EUR';
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService.Result> results = 
            QuoteCurrencyChangeService.handleCurrencyChange(new List<QuoteCurrencyChangeService.Request>{req});
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, results[0].success, 'Operation should fail');
        System.assert(results[0].message.contains('Error'), 'Error message should be returned');
    }
    
    @isTest
    static void testBulkOperation() {
        // Create multiple quotes
        List<Quote> quotes = new List<Quote>();
        Account acc = [SELECT Id FROM Account LIMIT 1];
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
        List<QuoteCurrencyChangeService.Request> requests = new List<QuoteCurrencyChangeService.Request>();
        for (Quote q : quotes) {
            QuoteCurrencyChangeService.Request req = new QuoteCurrencyChangeService.Request();
            req.quoteId = q.Id;
            req.oldCurrency = 'USD';
            req.newCurrency = 'AUD';
            requests.add(req);
        }
        
        // Execute
        Test.startTest();
        List<QuoteCurrencyChangeService.Result> results = 
            QuoteCurrencyChangeService.handleCurrencyChange(requests);
        Test.stopTest();
        
        // Verify all operations succeeded
        System.assertEquals(5, results.size(), 'Should process all requests');
        for (QuoteCurrencyChangeService.Result res : results) {
            System.assertEquals(true, res.success, 'All operations should succeed');
        }
    }
}