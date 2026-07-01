/**
 * Test class for QuoteMigrationService.
 * Validates field calculations, default resolution, record counting,
 * gap analysis, and price field capture/restore.
 *
 * @author Marc DeBrey
 * @date 2026-02-27
 */
@IsTest
private class QuoteMigrationServiceTest {

    private static final String LEGACY_PREFIX = 'DY_TEST_';

    @TestSetup
    static void setupTestData() {
        // Account
        Account testAccount = new Account(
            Name = 'Migration Test Account',
            BillingCountry = 'United States',
            BillingState = 'California'
        );
        insert testAccount;

        // Opportunity (Closed Won)
        Opportunity testOpp = new Opportunity(
            Name = 'Migration Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today()
        );
        insert testOpp;

        // Product
        Product2 testProduct = new Product2(
            Name = 'Migration Test Product',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert testProduct;

        // Standard PricebookEntry
        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry stdPbe = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert stdPbe;

        // Quote (primary, linked to Closed Won opp)
        Quote testQuote = new Quote(
            Name = 'Migration Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = stdPricebookId,
            IsPrimary__c = true
        );
        insert testQuote;

        // QLI 1: 12-month term
        QuoteLineItem qli1 = new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = stdPbe.Id,
            Product2Id = testProduct.Id,
            Quantity = 1,
            UnitPrice = 500,
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 12, 31),
            Legacy_Id__c = LEGACY_PREFIX + '001'
        );

        // QLI 2: 24-month term
        QuoteLineItem qli2 = new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = stdPbe.Id,
            Product2Id = testProduct.Id,
            Quantity = 2,
            UnitPrice = 1000,
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2027, 12, 31),
            Legacy_Id__c = LEGACY_PREFIX + '002'
        );

        // QLI 3: no dates (should be counted as missing dates)
        QuoteLineItem qli3 = new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = stdPbe.Id,
            Product2Id = testProduct.Id,
            Quantity = 1,
            UnitPrice = 200,
            Legacy_Id__c = LEGACY_PREFIX + '003'
        );

        insert new List<QuoteLineItem>{ qli1, qli2, qli3 };
    }

    // ── calculateQLIFields Tests ──────────────────────────────────────

    @IsTest
    static void testCalculateQLIFields_12Months() {
        QuoteLineItem qli = new QuoteLineItem(
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 12, 31),
            UnitPrice = 500
        );

        QuoteMigrationService.ResolvedDefaults defaults =
            new QuoteMigrationService.ResolvedDefaults();

        Test.startTest();
        QuoteMigrationService.calculateQLIFields(qli, defaults);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 1, 1), qli.ServiceDate,
            'ServiceDate should equal StartDate');
        System.assertEquals(12, qli.SubscriptionTerm,
            'SubscriptionTerm should be 12 months');
        // PeriodBoundaryDay is only set when PeriodBoundary = "DayOfPeriod"
        // With empty defaults, PeriodBoundary is null so PeriodBoundaryDay remains null
        System.assertEquals(null, qli.PeriodBoundaryDay,
            'PeriodBoundaryDay should be null when PeriodBoundary is not DayOfPeriod');
        System.assertEquals(null, qli.PeriodBoundaryStartMonth,
            'PeriodBoundaryStartMonth should be null when PeriodBoundary is not DayOfPeriod');
    }

    @IsTest
    static void testCalculateQLIFields_24Months() {
        QuoteLineItem qli = new QuoteLineItem(
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2027, 12, 31),
            UnitPrice = 1000
        );

        QuoteMigrationService.ResolvedDefaults defaults =
            new QuoteMigrationService.ResolvedDefaults();

        Test.startTest();
        QuoteMigrationService.calculateQLIFields(qli, defaults);
        Test.stopTest();

        System.assertEquals(24, qli.SubscriptionTerm,
            'SubscriptionTerm should be 24 months');
    }

    @IsTest
    static void testCalculateQLIFields_PartialYear() {
        QuoteLineItem qli = new QuoteLineItem(
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2027, 6, 30),
            UnitPrice = 750
        );

        QuoteMigrationService.ResolvedDefaults defaults =
            new QuoteMigrationService.ResolvedDefaults();

        Test.startTest();
        QuoteMigrationService.calculateQLIFields(qli, defaults);
        Test.stopTest();

        // monthsBetween(2026-01-01, 2027-06-30) = 17 or 18 depending on day
        System.assert(qli.SubscriptionTerm >= 17 && qli.SubscriptionTerm <= 18,
            'SubscriptionTerm should be approximately 18 months, got: ' + qli.SubscriptionTerm);
    }

    @IsTest
    static void testCalculateQLIFields_ShortTerm() {
        QuoteLineItem qli = new QuoteLineItem(
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 6, 30),
            UnitPrice = 300
        );

        QuoteMigrationService.ResolvedDefaults defaults =
            new QuoteMigrationService.ResolvedDefaults();

        Test.startTest();
        QuoteMigrationService.calculateQLIFields(qli, defaults);
        Test.stopTest();

        // PricingTermCount is system-managed (not writeable) — set by pricing engine
        System.assert(qli.SubscriptionTerm >= 5 && qli.SubscriptionTerm <= 6,
            'SubscriptionTerm should be approximately 6 months, got: ' + qli.SubscriptionTerm);
    }

    @IsTest
    static void testCalculateQLIFields_PeriodBoundary_Anniversary() {
        // When PeriodBoundary = "Anniversary", neither PeriodBoundaryDay nor
        // PeriodBoundaryStartMonth should be set. The platform uses ServiceDate
        // as the billing anchor for Anniversary mode.
        QuoteLineItem qli = new QuoteLineItem(
            StartDate = Date.newInstance(2025, 9, 15),
            EndDate = Date.newInstance(2026, 9, 14),
            UnitPrice = 1200
        );

        QuoteMigrationService.ResolvedDefaults defaults =
            new QuoteMigrationService.ResolvedDefaults();
        defaults.qliStringDefaults.put('PeriodBoundary', 'Anniversary');

        Test.startTest();
        QuoteMigrationService.calculateQLIFields(qli, defaults);
        Test.stopTest();

        System.assertEquals(null, qli.PeriodBoundaryDay,
            'PeriodBoundaryDay must be null when PeriodBoundary is Anniversary');
        System.assertEquals(null, qli.PeriodBoundaryStartMonth,
            'PeriodBoundaryStartMonth must be null when PeriodBoundary is Anniversary');
        System.assertEquals('Anniversary', (String) qli.get('PeriodBoundary'),
            'PeriodBoundary should be Anniversary from CMT default');
        System.assertEquals(Date.newInstance(2025, 9, 15), qli.ServiceDate,
            'ServiceDate should equal StartDate');
    }

    @IsTest
    static void testCalculateQLIFields_PeriodBoundary_DayOfPeriod() {
        // When PeriodBoundary = "DayOfPeriod", both PeriodBoundaryDay and
        // PeriodBoundaryStartMonth are set from the StartDate.
        QuoteLineItem qli = new QuoteLineItem(
            StartDate = Date.newInstance(2025, 9, 15),
            EndDate = Date.newInstance(2026, 9, 14),
            UnitPrice = 1200
        );

        QuoteMigrationService.ResolvedDefaults defaults =
            new QuoteMigrationService.ResolvedDefaults();
        defaults.qliStringDefaults.put('PeriodBoundary', 'DayOfPeriod');

        Test.startTest();
        QuoteMigrationService.calculateQLIFields(qli, defaults);
        Test.stopTest();

        System.assertEquals(15, qli.PeriodBoundaryDay,
            'PeriodBoundaryDay should be 15 (day of Sept 15 StartDate)');
        System.assertEquals('9', qli.PeriodBoundaryStartMonth,
            'PeriodBoundaryStartMonth should be 9 (September) for DayOfPeriod');
        System.assertEquals('DayOfPeriod', (String) qli.get('PeriodBoundary'),
            'PeriodBoundary should be DayOfPeriod from CMT default');
    }

    @IsTest
    static void testCalculateQLIFields_PreservesExistingValues() {
        QuoteLineItem qli = new QuoteLineItem(
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2028, 12, 31),
            UnitPrice = 1500,
            SubscriptionTerm = 36,
            BillingFrequency = 'Monthly'
        );

        QuoteMigrationService.ResolvedDefaults defaults =
            new QuoteMigrationService.ResolvedDefaults();
        defaults.qliStringDefaults.put('BillingFrequency', 'Annual');

        Test.startTest();
        QuoteMigrationService.calculateQLIFields(qli, defaults);
        Test.stopTest();

        System.assertEquals(36, qli.SubscriptionTerm,
            'SubscriptionTerm should not be overwritten when already set');
        System.assertEquals('Monthly', (String) qli.get('BillingFrequency'),
            'BillingFrequency should not be overwritten when already set');
    }

    // ── resolveDefaults Test ──────────────────────────────────────────

    @IsTest
    static void testResolveDefaults() {
        Test.startTest();
        QuoteMigrationService.ResolvedDefaults defaults =
            QuoteMigrationService.resolveDefaults();
        Test.stopTest();

        // Defaults object should always be returned (may be empty in test context
        // since CMT records may not be available in @IsTest without SeeAllData)
        System.assertNotEquals(null, defaults,
            'resolveDefaults should return a non-null object');
        System.assertNotEquals(null, defaults.qliStringDefaults,
            'qliStringDefaults map should be initialized');
        System.assertNotEquals(null, defaults.qliIdDefaults,
            'qliIdDefaults map should be initialized');
        System.assertNotEquals(null, defaults.quoteStringDefaults,
            'quoteStringDefaults map should be initialized');
        System.assertNotEquals(null, defaults.quoteIdDefaults,
            'quoteIdDefaults map should be initialized');
    }

    // ── getRecordCounts Test ──────────────────────────────────────────

    @IsTest
    static void testGetRecordCounts() {
        Test.startTest();
        QuoteMigrationService.MigrationPreview preview =
            QuoteMigrationService.getRecordCounts('DY_TEST_%');
        Test.stopTest();

        System.assertEquals(3, preview.qliCount,
            'Should find 3 QLIs matching the filter');
        System.assertEquals(1, preview.quoteCount,
            'Should find 1 Quote containing matching QLIs');
        System.assertEquals(1, preview.qlisWithMissingDates,
            'Should find 1 QLI with missing start/end dates');
    }

    // ── getFieldGapAnalysis Test ──────────────────────────────────────

    @IsTest
    static void testGetFieldGapAnalysis() {
        Test.startTest();
        List<QuoteMigrationService.FieldGapInfo> gaps =
            QuoteMigrationService.getFieldGapAnalysis('DY_TEST_%');
        Test.stopTest();

        System.assert(!gaps.isEmpty(),
            'Should return at least one FieldGapInfo entry');

        // Find the ServiceDate gap entry
        QuoteMigrationService.FieldGapInfo serviceDateGap = null;
        for (QuoteMigrationService.FieldGapInfo gap : gaps) {
            if (gap.fieldName == 'ServiceDate') {
                serviceDateGap = gap;
                break;
            }
        }
        System.assertNotEquals(null, serviceDateGap,
            'Should have a ServiceDate field gap entry');
        System.assertEquals(3, serviceDateGap.totalCount,
            'Total count should be 3 QLIs');
        // ServiceDate is null on all 3 test QLIs (not set in test setup)
        System.assertEquals(3, serviceDateGap.nullCount,
            'All 3 QLIs should have null ServiceDate');
    }

    // ── capturePriceFields / restorePriceFields Tests ─────────────────

    @IsTest
    static void testCapturePriceFields() {
        QuoteLineItem qli = new QuoteLineItem(
            UnitPrice = 500,
            Discount = 10
        );

        Test.startTest();
        Map<String, Object> prices =
            QuoteMigrationService.capturePriceFields(qli);
        Test.stopTest();

        System.assertEquals(500, (Decimal) prices.get('UnitPrice'),
            'Captured UnitPrice should be 500');
        System.assertEquals(10, (Decimal) prices.get('Discount'),
            'Captured Discount should be 10');
    }

    @IsTest
    static void testRestorePriceFields() {
        QuoteLineItem qli = new QuoteLineItem(
            UnitPrice = 500,
            Discount = 10
        );

        // Capture original prices
        Map<String, Object> prices =
            QuoteMigrationService.capturePriceFields(qli);

        // Modify the QLI
        qli.UnitPrice = 999;
        qli.Discount = 50;

        Test.startTest();
        QuoteMigrationService.restorePriceFields(qli, prices);
        Test.stopTest();

        System.assertEquals(500, qli.UnitPrice,
            'UnitPrice should be restored to 500');
        System.assertEquals(10, qli.Discount,
            'Discount should be restored to 10');
    }

    @IsTest
    static void testRestorePriceFields_NullMap() {
        QuoteLineItem qli = new QuoteLineItem(
            UnitPrice = 500,
            Discount = 10
        );

        Test.startTest();
        QuoteMigrationService.restorePriceFields(qli, null);
        Test.stopTest();

        // Values should remain unchanged when null map is passed
        System.assertEquals(500, qli.UnitPrice,
            'UnitPrice should be unchanged when null prices map is passed');
        System.assertEquals(10, qli.Discount,
            'Discount should be unchanged when null prices map is passed');
    }

    @IsTest
    static void testCapturePriceFields_NullValues() {
        QuoteLineItem qli = new QuoteLineItem(
            UnitPrice = 750
            // Discount is intentionally null
        );

        Test.startTest();
        Map<String, Object> prices =
            QuoteMigrationService.capturePriceFields(qli);
        Test.stopTest();

        System.assertEquals(750, (Decimal) prices.get('UnitPrice'),
            'Captured UnitPrice should be 750');
        System.assertEquals(null, prices.get('Discount'),
            'Captured Discount should be null when not set');
    }

    // ── repriceQuote Tests ────────────────────────────────────────────

    @IsTest
    static void testRepriceQuote_HandlesGracefully() {
        // The repricing Flow (Fortra_Quote_Reprice) orchestrates buildContext →
        // runSalesforcePricing → persistContextData. In test context these actions
        // may succeed (no-op) or fail depending on org configuration.
        // Either way, repriceQuote should never throw — it wraps results.
        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Migration Test Quote' LIMIT 1];

        Test.startTest();
        QuoteMigrationService.RepricingResult result =
            QuoteMigrationService.repriceQuote(testQuote.Id);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'RepricingResult should not be null');
        // The result may be success or failure depending on test context,
        // but we verify no unhandled exception was thrown and the wrapper is valid.
        if (!result.isSuccess) {
            System.assert(String.isNotBlank(result.errorMessage),
                'Error message should be populated on failure');
        }
    }

    @IsTest
    static void testRepricingResult_Constructor() {
        // Test the wrapper class directly
        QuoteMigrationService.RepricingResult successResult =
            new QuoteMigrationService.RepricingResult(true, null, 'exec-123');

        System.assertEquals(true, successResult.isSuccess, 'isSuccess should be true');
        System.assertEquals(null, successResult.errorMessage, 'errorMessage should be null');
        System.assertEquals('exec-123', successResult.executionId, 'executionId should match');

        QuoteMigrationService.RepricingResult failResult =
            new QuoteMigrationService.RepricingResult(false, 'Test error', null);

        System.assertEquals(false, failResult.isSuccess, 'isSuccess should be false');
        System.assertEquals('Test error', failResult.errorMessage, 'errorMessage should match');
        System.assertEquals(null, failResult.executionId, 'executionId should be null');
    }

    @IsTest
    static void testRepriceFlowConstant() {
        // Verify the Flow name constant is accessible and has a non-blank value
        System.assert(String.isNotBlank(QuoteMigrationService.REPRICE_FLOW_NAME),
            'Reprice Flow name constant should not be blank');
    }
}