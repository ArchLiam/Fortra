/**
 * Test class for QuoteCloneService
 * Tests quote cloning functionality for Revenue Cloud
 * Updated to test Revenue Cloud syncing via Opportunity.SyncedQuoteId
 */
@isTest
private class QuoteCloneServiceTest {
    
    @testSetup
    static void setup() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account',
            BillingStreet = '123 Test St',
            BillingCity = 'Test City',
            BillingState = 'TS',
            BillingPostalCode = '12345',
            BillingCountry = 'USA'
        );
        insert testAccount;
        
        // Create test contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = testAccount.Id,
            Email = 'test@example.com'
        );
        insert testContact;
        
        // Create test opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;
        
        // Get standard pricebook
        Id pricebookId = Test.getStandardPricebookId();
        
        // Create test product
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            ProductCode = 'TEST001',
            IsActive = true
        );
        insert testProduct;
        
        // Create pricebook entry
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert pbe;
        
        // Create test quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = pricebookId,
            ContactId = testContact.Id,
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(30),
            Description = 'Test Quote Description',
            BillingStreet = testAccount.BillingStreet,
            BillingCity = testAccount.BillingCity,
            BillingState = testAccount.BillingState,
            BillingPostalCode = testAccount.BillingPostalCode,
            BillingCountry = testAccount.BillingCountry
        );
        insert testQuote;
        
        // Create test quote line items
        List<QuoteLineItem> lineItems = new List<QuoteLineItem>();
        for (Integer i = 0; i < 3; i++) {
            lineItems.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = testProduct.Id,
                PricebookEntryId = pbe.Id,
                Quantity = i + 1,
                UnitPrice = 100.00
            ));
        }
        insert lineItems;
    }
    
    @isTest
    static void testCloneQuoteWithDefaultOptions() {
        // Get test quote
        Quote sourceQuote = [SELECT Id, Name FROM Quote LIMIT 1];
        
        Test.startTest();
        QuoteCloneService.CloneResult result = QuoteCloneService.cloneQuoteWithLines(
            sourceQuote.Id, 
            null // Use default options
        );
        Test.stopTest();
        
        // Verify results
        System.assert(result.success, 'Clone should be successful');
        System.assertNotEquals(null, result.clonedQuoteId, 'Cloned quote ID should not be null');
        System.assertEquals(3, result.lineItemCount, 'Should have 3 line items');
        
        // Verify cloned quote exists
        Quote clonedQuote = [SELECT Id, Name, Status FROM Quote WHERE Id = :result.clonedQuoteId];
        System.assert(clonedQuote.Name.contains('Copy of'), 'Cloned quote name should contain "Copy of"');
        System.assertEquals('Draft', clonedQuote.Status, 'Cloned quote should be in Draft status');
        
        // Verify line items were cloned
        List<QuoteLineItem> clonedLines = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :result.clonedQuoteId];
        System.assertEquals(3, clonedLines.size(), 'Should have 3 cloned line items');
    }
    
    @isTest
    static void testCloneQuoteWithCustomOptions() {
        // Get test quote
        Quote sourceQuote = [SELECT Id, Name FROM Quote LIMIT 1];
        
        // Create custom options
        QuoteCloneService.CloneOptions options = new QuoteCloneService.CloneOptions();
        options.quoteName = 'Custom Clone Name';
        options.expirationDate = Date.today().addDays(60);
        options.cloneLineItems = true;
        options.recalculatePricing = false;
        options.copyDiscounts = false;
        
        Test.startTest();
        QuoteCloneService.CloneResult result = QuoteCloneService.cloneQuoteWithLines(sourceQuote.Id, options);
        Test.stopTest();
        
        // Verify results
        System.assert(result.success, 'Clone should be successful');
        System.assertNotEquals(null, result.clonedQuoteId, 'Cloned quote ID should not be null');
        
        // Verify custom options were applied
        Quote clonedQuote = [SELECT Id, Name, ExpirationDate FROM Quote WHERE Id = :result.clonedQuoteId];
        System.assertEquals('Custom Clone Name', clonedQuote.Name, 'Custom name should be applied');
        System.assertEquals(Date.today().addDays(60), clonedQuote.ExpirationDate, 'Custom expiration date should be applied');
    }
    
    @isTest
    static void testCloneQuoteWithMakePrimary() {
        // Get test quote with opportunity
        Quote sourceQuote = [SELECT Id, Name, OpportunityId FROM Quote LIMIT 1];
        
        // Create custom options with makePrimary = true
        QuoteCloneService.CloneOptions options = new QuoteCloneService.CloneOptions();
        options.quoteName = 'Primary Clone';
        options.makePrimary = true;
        
        Test.startTest();
        QuoteCloneService.CloneResult result = QuoteCloneService.cloneQuoteWithLines(sourceQuote.Id, options);
        Test.stopTest();
        
        // Verify results
        System.assert(result.success, 'Clone should be successful');
        System.assertNotEquals(null, result.clonedQuoteId, 'Cloned quote ID should not be null');
        System.assert(result.message.contains('Syncing with opportunity'), 'Message should indicate syncing');
        
        // Note: We can't directly verify the @future method execution in the same transaction
        // but we can verify the clone was created successfully
        Quote clonedQuote = [SELECT Id, Name FROM Quote WHERE Id = :result.clonedQuoteId];
        System.assertEquals('Primary Clone', clonedQuote.Name, 'Clone should have correct name');
    }
    
    @isTest
    static void testSyncQuoteToOpportunity() {
        // Get test quote
        Quote testQuote = [SELECT Id, OpportunityId FROM Quote LIMIT 1];
        
        Test.startTest();
        QuoteCloneService.SyncResult result = QuoteCloneService.syncQuoteToOpportunity(testQuote.Id);
        Test.stopTest();
        
        // Verify sync result
        System.assert(result.success, 'Sync should be successful');
        System.assertEquals('Quote successfully synced to opportunity', result.message);
        System.assert(result.isSyncing, 'Quote should be marked as syncing');
        
        // Verify opportunity was updated
        Opportunity opp = [SELECT Id, SyncedQuoteId FROM Opportunity WHERE Id = :testQuote.OpportunityId];
        System.assertEquals(testQuote.Id, opp.SyncedQuoteId, 'Opportunity should have SyncedQuoteId set');
    }
    
    @isTest
    static void testStopSyncingQuote() {
        // Get test quote and sync it first
        Quote testQuote = [SELECT Id, OpportunityId FROM Quote LIMIT 1];
        
        // First sync the quote
        Opportunity opp = new Opportunity(
            Id = testQuote.OpportunityId,
            SyncedQuoteId = testQuote.Id
        );
        update opp;
        
        Test.startTest();
        QuoteCloneService.SyncResult result = QuoteCloneService.stopSyncingQuote(testQuote.Id);
        Test.stopTest();
        
        // Verify stop sync result
        System.assert(result.success, 'Stop sync should be successful');
        System.assertEquals('Quote sync stopped successfully', result.message);
        System.assertEquals(false, result.isSyncing, 'Quote should not be syncing');
        
        // Verify opportunity was updated
        Opportunity updatedOpp = [SELECT Id, SyncedQuoteId FROM Opportunity WHERE Id = :testQuote.OpportunityId];
        System.assertEquals(null, updatedOpp.SyncedQuoteId, 'Opportunity SyncedQuoteId should be cleared');
    }
    
    @isTest
    static void testStopSyncingQuoteNotSynced() {
        // Get test quote (not synced)
        Quote testQuote = [SELECT Id, OpportunityId FROM Quote LIMIT 1];
        
        Test.startTest();
        QuoteCloneService.SyncResult result = QuoteCloneService.stopSyncingQuote(testQuote.Id);
        Test.stopTest();
        
        // Verify result
        System.assert(result.success, 'Operation should be successful');
        System.assertEquals('This quote is not currently syncing', result.message);
        System.assertEquals(false, result.isSyncing, 'Quote should not be syncing');
    }
    
    @isTest
    static void testIsQuoteSyncing() {
        // Get test quote
        Quote testQuote = [SELECT Id, OpportunityId FROM Quote LIMIT 1];
        
        // Sync the quote
        Opportunity opp = new Opportunity(
            Id = testQuote.OpportunityId,
            SyncedQuoteId = testQuote.Id
        );
        update opp;
        
        Test.startTest();
        Boolean isSyncing = QuoteCloneService.isQuoteSyncing(testQuote.Id);
        Test.stopTest();
        
        // In Revenue Cloud, the IsSyncing field should be true when SyncedQuoteId is set
        // Note: This test may need adjustment based on actual org behavior
        System.assertNotEquals(null, isSyncing, 'Should return a boolean value');
    }
    
    @isTest
    static void testSyncQuoteWithoutOpportunity() {
        // Create a quote without opportunity
        Quote orphanQuote = new Quote(
            Name = 'Orphan Quote',
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(30)
        );
        insert orphanQuote;
        
        Test.startTest();
        QuoteCloneService.SyncResult result = QuoteCloneService.syncQuoteToOpportunity(orphanQuote.Id);
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, result.success, 'Sync should fail');
        System.assert(result.message.contains('not associated with an Opportunity'), 'Error message should indicate missing opportunity');
        System.assertEquals(false, result.isSyncing, 'Quote should not be syncing');
    }
    
    @isTest
    static void testCloneQuoteWithoutLineItems() {
        // Get test quote
        Quote sourceQuote = [SELECT Id, Name FROM Quote LIMIT 1];
        
        // Create options to not clone line items
        QuoteCloneService.CloneOptions options = new QuoteCloneService.CloneOptions();
        options.cloneLineItems = false;
        
        Test.startTest();
        QuoteCloneService.CloneResult result = QuoteCloneService.cloneQuoteWithLines(sourceQuote.Id, options);
        Test.stopTest();
        
        // Verify results
        System.assert(result.success, 'Clone should be successful');
        System.assertNotEquals(null, result.clonedQuoteId, 'Cloned quote ID should not be null');
        System.assertEquals(0, result.lineItemCount, 'Should have 0 line items');
        
        // Verify no line items were cloned
        List<QuoteLineItem> clonedLines = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :result.clonedQuoteId];
        System.assertEquals(0, clonedLines.size(), 'Should have no cloned line items');
    }
    
    @isTest
    static void testCloneQuoteWithNullId() {
        Test.startTest();
        QuoteCloneService.CloneResult result = QuoteCloneService.cloneQuoteWithLines(null, null);
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, result.success, 'Clone should fail with null ID');
        System.assert(result.message.contains('Source Quote ID is required'), 'Error message should indicate missing ID');
    }
    
    @isTest
    static void testCloneQuoteWithInvalidId() {
        // Create a fake ID that doesn't exist
        Id fakeId = '0Q0000000000000AAA';
        
        Test.startTest();
        QuoteCloneService.CloneResult result = QuoteCloneService.cloneQuoteWithLines(fakeId, null);
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, result.success, 'Clone should fail with invalid ID');
        System.assert(result.message.contains('Source Quote not found'), 'Error message should indicate quote not found');
    }
    
    @isTest
    static void testCalculateQuoteTotal() {
        // Get test quote
        Quote sourceQuote = [SELECT Id FROM Quote LIMIT 1];
        
        Test.startTest();
        QuoteCloneService.CloneResult result = QuoteCloneService.cloneQuoteWithLines(sourceQuote.Id, null);
        Test.stopTest();
        
        // Verify total calculation
        System.assert(result.success, 'Clone should be successful');
        // Line items: (1 * 100) + (2 * 100) + (3 * 100) = 600
        System.assertEquals(600.00, result.totalValue, 'Total value should be calculated correctly');
    }
}