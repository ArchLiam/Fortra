/**
 * @description Test class for QuoteRepricingController
 * Tests quote repricing operations with various scenarios
 */
@isTest
private class QuoteRepricingControllerTest {

    /**
     * @description Setup test data for all test methods
     */
    @testSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        // Create test Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        // Create test Pricebook
        Pricebook2 standardPricebook = new Pricebook2(
            Id = Test.getStandardPricebookId(),
            IsActive = true
        );

        // Create test Product
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert testProduct;

        // Create PricebookEntry
        PricebookEntry testPbe = new PricebookEntry(
            Pricebook2Id = standardPricebook.Id,
            Product2Id = testProduct.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert testPbe;

        // Create test Quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebook.Id,
            Status = 'Draft'
        );
        insert testQuote;

        // Create test QuoteLineItems
        List<QuoteLineItem> lineItems = new List<QuoteLineItem>();
        for (Integer i = 0; i < 5; i++) {
            lineItems.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                PricebookEntryId = testPbe.Id,
                Quantity = 10,
                UnitPrice = 100.00,
                Discount = 0
            ));
        }
        insert lineItems;
    }

    /**
     * @description Test successful repricing with line items
     */
    @isTest
    static void testRepriceQuote_Success() {
        // Get test quote
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            QuoteRepricingController.repriceQuote(testQuote.Id, 'PERCENTAGE');
        Test.stopTest();

        // Verify result
        System.assert(result.success, 'Repricing should succeed');
        System.assertEquals(5, result.itemCount, 'Should reprice 5 line items');
        System.assert(result.message.contains('applied successfully'),
            'Success message should be returned');
    }

    /**
     * @description Test repricing with no line items
     */
    @isTest
    static void testRepriceQuote_NoLineItems() {
        // Create a quote with no line items
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        Pricebook2 standardPricebook = new Pricebook2(
            Id = Test.getStandardPricebookId(),
            IsActive = true
        );

        Quote emptyQuote = new Quote(
            Name = 'Empty Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebook.Id,
            Status = 'Draft'
        );
        insert emptyQuote;

        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            QuoteRepricingController.repriceQuote(emptyQuote.Id, 'PERCENTAGE');
        Test.stopTest();

        // Verify result
        System.assert(result.success, 'Should succeed with no items');
        System.assertEquals('No line items to reprice', result.message,
            'Should return no items message');
        System.assertEquals(0, result.itemCount, 'Item count should be 0');
    }

    /**
     * @description Test repricing with invalid quote ID
     */
    @isTest
    static void testRepriceQuote_InvalidQuoteId() {
        // Create a quote and delete it to get a valid but non-existent ID
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        Pricebook2 standardPricebook = new Pricebook2(
            Id = Test.getStandardPricebookId(),
            IsActive = true
        );

        Quote tempQuote = new Quote(
            Name = 'Temp Quote for Deletion',
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebook.Id,
            Status = 'Draft'
        );
        insert tempQuote;
        Id fakeQuoteId = tempQuote.Id;
        delete tempQuote;

        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            QuoteRepricingController.repriceQuote(fakeQuoteId, 'PERCENTAGE');
        Test.stopTest();

        // Verify result
        System.assert(!result.success, 'Should fail with invalid quote ID');
        System.assert(result.message.contains('Quote not found'),
            'Should return quote not found message');
    }

    /**
     * @description Test isQuoteAvailable when quote is available
     */
    @isTest
    static void testIsQuoteAvailable_Available() {
        // Get test quote
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        Boolean available = QuoteRepricingController.isQuoteAvailable(testQuote.Id);
        Test.stopTest();

        // Verify result
        System.assert(available, 'Quote should be available');
    }

    /**
     * @description Test isQuoteAvailable with invalid ID
     */
    @isTest
    static void testIsQuoteAvailable_InvalidId() {
        // Create a quote and delete it to get a valid but non-existent ID
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        Pricebook2 standardPricebook = new Pricebook2(
            Id = Test.getStandardPricebookId(),
            IsActive = true
        );

        Quote tempQuote = new Quote(
            Name = 'Temp Quote for Deletion',
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebook.Id,
            Status = 'Draft'
        );
        insert tempQuote;
        Id fakeQuoteId = tempQuote.Id;
        delete tempQuote;

        Test.startTest();
        Boolean available = QuoteRepricingController.isQuoteAvailable(fakeQuoteId);
        Test.stopTest();

        // Verify result
        System.assert(!available, 'Should return false for invalid quote ID');
    }

    /**
     * @description Test waitForQuoteAvailable with available quote
     */
    @isTest
    static void testWaitForQuoteAvailable_Available() {
        // Get test quote
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        QuoteRepricingController.AvailabilityResult result =
            QuoteRepricingController.waitForQuoteAvailable(testQuote.Id, 5, 100);
        Test.stopTest();

        // Verify result
        System.assert(result.available, 'Quote should be available');
        System.assert(result.attempts >= 1, 'Should have made at least 1 attempt');
        System.assert(result.message.contains('available'),
            'Message should indicate availability');
    }

    /**
     * @description Test waitForQuoteAvailable with default parameters
     */
    @isTest
    static void testWaitForQuoteAvailable_DefaultParams() {
        // Get test quote
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        QuoteRepricingController.AvailabilityResult result =
            QuoteRepricingController.waitForQuoteAvailable(testQuote.Id, null, null);
        Test.stopTest();

        // Verify result - should use defaults (10 attempts, 500ms)
        System.assert(result.available, 'Quote should be available');
        System.assert(result.attempts >= 1, 'Should have made at least 1 attempt');
    }

    /**
     * @description Test waitForQuoteAvailable with locked quote scenario
     */
    @isTest
    static void testWaitForQuoteAvailable_Locked() {
        // Create a quote and delete it to get a valid but non-existent ID to simulate locked/unavailable
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        Pricebook2 standardPricebook = new Pricebook2(
            Id = Test.getStandardPricebookId(),
            IsActive = true
        );

        Quote tempQuote = new Quote(
            Name = 'Temp Quote for Deletion',
            OpportunityId = testOpp.Id,
            Pricebook2Id = standardPricebook.Id,
            Status = 'Draft'
        );
        insert tempQuote;
        Id fakeQuoteId = tempQuote.Id;
        delete tempQuote;

        Test.startTest();
        QuoteRepricingController.AvailabilityResult result =
            QuoteRepricingController.waitForQuoteAvailable(fakeQuoteId, 3, 100);
        Test.stopTest();

        // Verify result
        System.assert(!result.available, 'Quote should not be available');
        System.assertEquals(3, result.attempts, 'Should have made 3 attempts');
        System.assert(result.message.contains('locked'),
            'Message should indicate quote is locked');
    }

    /**
     * @description Test RepricingResult wrapper class initialization
     */
    @isTest
    static void testRepricingResult_Initialization() {
        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            new QuoteRepricingController.RepricingResult();
        Test.stopTest();

        // Verify default values
        System.assertEquals(false, result.success, 'Success should default to false');
        System.assertEquals('', result.message, 'Message should default to empty string');
        System.assertEquals(0, result.itemCount, 'Item count should default to 0');
    }

    /**
     * @description Test AvailabilityResult wrapper class initialization
     */
    @isTest
    static void testAvailabilityResult_Initialization() {
        Test.startTest();
        QuoteRepricingController.AvailabilityResult result =
            new QuoteRepricingController.AvailabilityResult();
        Test.stopTest();

        // Verify default values
        System.assertEquals(false, result.available, 'Available should default to false');
        System.assertEquals(0, result.attempts, 'Attempts should default to 0');
        System.assertEquals('', result.message, 'Message should default to empty string');
    }

    /**
     * @description Test repricing with AMOUNT discount type
     * Note: With distribution logic, the total discount ($50) is distributed across all lines
     * 5 equal lines at $1000 each = $5000 total, so each line gets $50 * (1000/5000) = $10
     */
    @isTest
    static void testRepriceQuote_AmountDiscount() {
        // Get test quote
        Quote testQuote = [SELECT Id, Header_Discount_Value__c, Manual_Discount__c FROM Quote LIMIT 1];

        // Set an amount discount value (total to distribute)
        testQuote.Header_Discount_Value__c = 50.00;
        testQuote.Manual_Discount__c = 50.00;
        // Leave Header_Distribution_Logic__c null to default to Proportionate
        update testQuote;

        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            QuoteRepricingController.repriceQuote(testQuote.Id, 'AMOUNT');
        Test.stopTest();

        // Verify result
        System.assert(result.success, 'Amount discount repricing should succeed');
        System.assertEquals(5, result.itemCount, 'Should reprice all 5 line items');
        System.assert(result.message.contains('$50'),
            'Success message should show dollar amount, got: ' + result.message);
        System.assert(result.message.contains('applied successfully'),
            'Success message should confirm application');

        // Verify line items have DiscountAmount set and Discount cleared
        // With proportionate distribution: $50 across 5 equal lines = $10 per line
        // But DiscountAmount is PER-UNIT, so with Qty=10, per-unit = $10/10 = $1
        List<QuoteLineItem> updatedItems = [
            SELECT Id, Discount, DiscountAmount, Quantity
            FROM QuoteLineItem
            WHERE QuoteId = :testQuote.Id
        ];
        for (QuoteLineItem item : updatedItems) {
            System.assertEquals(null, item.Discount,
                'Percentage discount should be cleared for AMOUNT type');
            // Each line: $50 total / 5 lines = $10 per line, then / Qty 10 = $1 per unit
            System.assertEquals(1.00, item.DiscountAmount,
                'DiscountAmount should be $1 per unit ($50 / 5 lines / 10 qty)');
        }
    }

    /**
     * @description Test proportionate distribution of AMOUNT discount
     * Ensures $500 total discount is distributed proportionally across line items
     * rather than applying $500 to each line (which would fail validation)
     */
    @isTest
    static void testRepriceQuote_AmountDiscount_ProportionateDistribution() {
        // Get test quote - has 5 lines at $1000 subtotal each = $5000 total
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        // Set a large amount discount with Proportionate distribution
        testQuote.Header_Discount_Value__c = 500.00;
        testQuote.Header_Distribution_Logic__c = 'Proportionate';
        update testQuote;

        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            QuoteRepricingController.repriceQuote(testQuote.Id, 'AMOUNT');
        Test.stopTest();

        // Verify result - should succeed by distributing $500 across lines
        System.assert(result.success, 'Proportionate amount discount should succeed. Got: ' + result.message);
        System.assertEquals(5, result.itemCount, 'Should reprice all 5 line items');

        // Verify line items have proportionally distributed DiscountAmount
        // Each line is $1000 of $5000 total (20%), so each gets $500 * 0.20 = $100 per LINE
        // But DiscountAmount is PER-UNIT, so with Qty=10: $100 / 10 = $10 per unit
        List<QuoteLineItem> updatedItems = [
            SELECT Id, Discount, DiscountAmount, Subtotal, Quantity
            FROM QuoteLineItem
            WHERE QuoteId = :testQuote.Id
        ];

        Decimal totalDistributedDiscount = 0;
        for (QuoteLineItem item : updatedItems) {
            System.assertEquals(null, item.Discount,
                'Percentage discount should be cleared');
            System.assertNotEquals(null, item.DiscountAmount,
                'DiscountAmount should be set');
            // Each line gets $100 total, but DiscountAmount is per-unit: $100 / 10 qty = $10
            System.assertEquals(10.00, item.DiscountAmount,
                'Per-unit discount should be $10 ($100 line discount / 10 qty)');
            // Calculate actual line discount for total check
            totalDistributedDiscount += item.DiscountAmount * item.Quantity;
        }

        // Total distributed should equal the header discount
        System.assertEquals(500.00, totalDistributedDiscount,
            'Total distributed discount should equal header discount');
    }

    /**
     * @description Test equal distribution of AMOUNT discount
     */
    @isTest
    static void testRepriceQuote_AmountDiscount_EqualDistribution() {
        // Get test quote
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        // Set amount discount with Equal distribution
        testQuote.Header_Discount_Value__c = 250.00;
        testQuote.Header_Distribution_Logic__c = 'Equal';
        update testQuote;

        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            QuoteRepricingController.repriceQuote(testQuote.Id, 'AMOUNT');
        Test.stopTest();

        // Verify result
        System.assert(result.success, 'Equal amount discount should succeed. Got: ' + result.message);
        System.assertEquals(5, result.itemCount, 'Should reprice all 5 line items');

        // Verify line items have equally distributed DiscountAmount
        // $250 / 5 lines = $50 per LINE, but DiscountAmount is per-unit
        // With Qty=10: $50 / 10 = $5 per unit
        List<QuoteLineItem> updatedItems = [
            SELECT Id, DiscountAmount, Quantity
            FROM QuoteLineItem
            WHERE QuoteId = :testQuote.Id
        ];

        for (QuoteLineItem item : updatedItems) {
            System.assertEquals(5.00, item.DiscountAmount,
                'Per-unit discount should be $5 ($50 line discount / 10 qty)');
        }
    }

    /**
     * @description Test that zero-subtotal lines are excluded from AMOUNT distribution
     * Lines with Subtotal=0 (e.g. bundled items) should get $0 discount,
     * and the full discount should be distributed across eligible lines only
     */
    @isTest
    static void testRepriceQuote_AmountDiscount_ZeroSubtotalLines() {
        // Get test quote and its line items
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> existingItems = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :testQuote.Id];

        // Delete existing items and create a mix: 2 priced + 3 zero-priced
        delete existingItems;

        // Need a PricebookEntry
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :Test.getStandardPricebookId() LIMIT 1];

        List<QuoteLineItem> mixedItems = new List<QuoteLineItem>();
        // 2 priced lines at $100 each (Qty=1)
        for (Integer i = 0; i < 2; i++) {
            mixedItems.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = 100.00
            ));
        }
        // 3 zero-priced lines (bundled items)
        for (Integer i = 0; i < 3; i++) {
            mixedItems.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = 0.00
            ));
        }
        insert mixedItems;

        // Apply $50 Equal distribution
        testQuote.Header_Discount_Value__c = 50.00;
        testQuote.Header_Distribution_Logic__c = 'Equal';
        update testQuote;

        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            QuoteRepricingController.repriceQuote(testQuote.Id, 'AMOUNT');
        Test.stopTest();

        System.assert(result.success, 'Should succeed. Got: ' + result.message);

        // Verify: $50 distributed only across 2 priced lines, $0 for zero-priced
        List<QuoteLineItem> updated = [
            SELECT Id, UnitPrice, Subtotal, DiscountAmount
            FROM QuoteLineItem
            WHERE QuoteId = :testQuote.Id
            ORDER BY UnitPrice DESC
        ];

        Decimal totalApplied = 0;
        for (QuoteLineItem item : updated) {
            if (item.UnitPrice > 0) {
                // $50 / 2 eligible lines = $25 per line (Qty=1, so $25 per unit)
                System.assertEquals(25.00, item.DiscountAmount,
                    'Priced line should get $25 ($50 / 2 eligible lines)');
            } else {
                System.assertEquals(0, item.DiscountAmount,
                    'Zero-priced line should get $0 discount');
            }
            totalApplied += (item.DiscountAmount != null ? item.DiscountAmount : 0);
        }
        System.assertEquals(50.00, totalApplied,
            'Total discount applied should equal header discount');
    }

    /**
     * @description Test repricing with partial update failures
     * Note: This is a theoretical test as Database.update with allOrNone=false
     * is difficult to simulate failures in a test context
     */
    @isTest
    static void testRepriceQuote_WithQuoteFields() {
        // Get test quote
        Quote testQuote = [SELECT Id, Header_Discount_Value__c, Manual_Discount__c FROM Quote LIMIT 1];

        // Update quote with discount values
        testQuote.Header_Discount_Value__c = 15.00;
        testQuote.Manual_Discount__c = 15.00;
        update testQuote;

        Test.startTest();
        QuoteRepricingController.RepricingResult result =
            QuoteRepricingController.repriceQuote(testQuote.Id, 'PERCENTAGE');
        Test.stopTest();

        // Verify result
        System.assert(result.success, 'Repricing should succeed with discount values');
        System.assertEquals(5, result.itemCount, 'Should reprice all line items');
    }
}