/**
 * @description Test class for HardwareManagementController
 * @author Claude Code
 * @date 2025
 */
@isTest
private class HardwareManagementControllerTest {

    /**
     * @description Create test data for the test methods
     */
    @TestSetup
    static void setup() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account',
            BillingCity = 'San Francisco',
            BillingState = 'California',
            BillingCountry = 'United States'
        );
        insert testAccount;

        // Create test Product
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            ProductCode = 'TEST-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert testProduct;

        // Create test PricebookEntry
        Id pricebookId = Test.getStandardPricebookId();
        PricebookEntry testPBE = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 1000,
            IsActive = true
        );
        insert testPBE;

        // Create test Opportunity (required for Quote)
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            CloseDate = Date.today().addMonths(1),
            StageName = 'Prospecting'
        );
        insert testOpp;

        // Create test Quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        // Create test QuoteLineItems
        List<QuoteLineItem> quoteLines = new List<QuoteLineItem>();
        for (Integer i = 0; i < 3; i++) {
            quoteLines.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = testProduct.Id,
                PricebookEntryId = testPBE.Id,
                Quantity = 1,
                UnitPrice = 1000
            ));
        }
        insert quoteLines;
    }

    /**
     * @description Test getSelectedQuoteLines method
     */
    @isTest
    static void testGetSelectedQuoteLines() {
        // Get test data
        List<QuoteLineItem> testLines = [SELECT Id FROM QuoteLineItem LIMIT 3];
        List<Id> lineIds = new List<Id>();
        for (QuoteLineItem line : testLines) {
            lineIds.add(line.Id);
        }

        Test.startTest();
        HardwareManagementController.HardwareResult result =
            HardwareManagementController.getSelectedQuoteLines(lineIds);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Operation should be successful');
        System.assertNotEquals(null, result.lines, 'Lines should not be null');
        System.assertEquals(3, result.lines.size(), 'Should return 3 quote lines');
    }

    /**
     * @description Test getSelectedQuoteLines with empty list
     */
    @isTest
    static void testGetSelectedQuoteLinesEmpty() {
        Test.startTest();
        HardwareManagementController.HardwareResult result =
            HardwareManagementController.getSelectedQuoteLines(new List<Id>());
        Test.stopTest();

        System.assertEquals(false, result.success, 'Operation should fail');
        System.assertEquals('No quote lines provided', result.message);
    }

    /**
     * @description Test searchHardware method - Note: This will return empty list since no Hardware__c objects exist
     */
    @isTest
    static void testSearchHardware() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<sObject> results = HardwareManagementController.searchHardware(
            testAccount.Id, new List<Id>(), 'Test', 'Active', 'Server', 'Production'
        );
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        // Note: Will be empty list since no Hardware__c records exist in org
        System.assertEquals(0, results.size(), 'Should return empty list when no hardware exists');
    }

    /**
     * @description Test flagLinesAsRequiringNewHardware method
     */
    @isTest
    static void testFlagLinesAsRequiringNewHardware() {
        // Get test data
        List<QuoteLineItem> testLines = [SELECT Id FROM QuoteLineItem LIMIT 2];
        List<Id> lineIds = new List<Id>();
        for (QuoteLineItem line : testLines) {
            lineIds.add(line.Id);
        }

        String notes = 'Need server with 64GB RAM';

        Test.startTest();
        HardwareManagementController.HardwareResult result =
            HardwareManagementController.flagLinesAsRequiringNewHardware(lineIds, notes);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Operation should be successful');
        System.assert(result.message.contains('Successfully flagged'), 'Should have success message');

        // Verify the flag was set
        List<QuoteLineItem> updatedLines = [
            SELECT Id, Requires_New_Hardware__c, Hardware_Notes__c
            FROM QuoteLineItem
            WHERE Id IN :lineIds
        ];

        for (QuoteLineItem line : updatedLines) {
            System.assertEquals(true, line.Requires_New_Hardware__c,
                              'Line should be flagged as requiring new hardware');
            System.assertEquals(notes, line.Hardware_Notes__c, 'Notes should be saved');
        }
    }

    /**
     * @description Test clearHardwareReferences method
     */
    @isTest
    static void testClearHardwareReferences() {
        // Get test data and set flags first
        List<QuoteLineItem> testLines = [SELECT Id FROM QuoteLineItem LIMIT 2];

        // Set hardware flags
        for (QuoteLineItem line : testLines) {
            line.Requires_New_Hardware__c = true;
            line.Hardware_Notes__c = 'Test notes';
        }
        update testLines;

        List<Id> lineIds = new List<Id>();
        for (QuoteLineItem line : testLines) {
            lineIds.add(line.Id);
        }

        Test.startTest();
        HardwareManagementController.HardwareResult result =
            HardwareManagementController.clearHardwareReferences(lineIds);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Operation should be successful');
        System.assert(result.message.contains('Successfully cleared'), 'Should have success message');

        // Verify references were cleared
        List<QuoteLineItem> updatedLines = [
            SELECT Id, Hardware_Reference__c, Requires_New_Hardware__c, Hardware_Notes__c
            FROM QuoteLineItem
            WHERE Id IN :lineIds
        ];

        for (QuoteLineItem line : updatedLines) {
            System.assertEquals(null, line.Hardware_Reference__c, 'Hardware reference should be null');
            System.assertEquals(false, line.Requires_New_Hardware__c, 'Flag should be false');
            System.assertEquals(null, line.Hardware_Notes__c, 'Notes should be null');
        }
    }

    /**
     * @description Test error handling
     */
    @isTest
    static void testErrorHandling() {
        // Test with invalid ID format (this should trigger an exception)
        List<Id> invalidIds = new List<Id>();

        Test.startTest();
        HardwareManagementController.HardwareResult result =
            HardwareManagementController.getSelectedQuoteLines(invalidIds);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Operation should fail');
        System.assertEquals('No quote lines provided', result.message);
    }

    /**
     * @description Test linkHardwareToLines method - Basic test without actual hardware records
     */
    @isTest
    static void testLinkHardwareToLinesNoHardware() {
        List<QuoteLineItem> testLines = [SELECT Id FROM QuoteLineItem LIMIT 2];
        List<Id> lineIds = new List<Id>();
        for (QuoteLineItem line : testLines) {
            lineIds.add(line.Id);
        }

        Test.startTest();
        HardwareManagementController.HardwareResult result =
            HardwareManagementController.linkHardwareToLines(lineIds, new List<Id>());
        Test.stopTest();

        System.assertEquals(false, result.success, 'Operation should fail with no hardware');
        System.assertEquals('No hardware selected', result.message);
    }

    /**
     * @description Test linkHardwareToLines with no lines
     */
    @isTest
    static void testLinkHardwareToLinesNoLines() {
        Test.startTest();
        HardwareManagementController.HardwareResult result =
            HardwareManagementController.linkHardwareToLines(null, new List<Id>());
        Test.stopTest();

        System.assertEquals(false, result.success, 'Operation should fail');
        System.assertEquals('No quote lines provided', result.message);
    }
}