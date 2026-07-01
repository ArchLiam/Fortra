/**
 * @description Test class for OrderMigrationController.
 *              Validates AuraEnabled methods for previewing, analyzing,
 *              and executing order migrations.
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-03
 */
@IsTest
private class OrderMigrationControllerTest {

    // Test data constants
    private static final String TEST_ACCOUNT_NAME = 'Order Migration Test Account';
    private static final String TEST_LEGACY_PREFIX = 'ORD_TEST_';
    private static final String TEST_FILTER = 'ORD_TEST_%';

    // ── HttpCalloutMock for createOrUpdateAssetFromOrder ──────────────

    private class MockAssetCreationResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('[{"actionName":"createOrUpdateAssetFromOrder","isSuccess":true,"outputValues":{"asyncOperationTracker":"https://test.salesforce.com/services/data/v62.0/async-operations/123"}}]');
            return res;
        }
    }

    // ── Test Setup ────────────────────────────────────────────────────

    /**
     * @description Create test data: Account, Opportunity, Quote, Products, PBEs, and QLIs.
     *              Three QLIs are created with Legacy_Id__c values ORD_TEST_001, ORD_TEST_002,
     *              ORD_TEST_003. The third QLI has null StartDate and EndDate to test
     *              field gap analysis.
     */
    @TestSetup
    static void setupTestData() {
        // Create Account
        Account testAccount = new Account(
            Name = TEST_ACCOUNT_NAME,
            BillingCountry = 'United States',
            BillingState = 'California',
            BillingCity = 'San Francisco',
            BillingStreet = '123 Order Migration Test St'
        );
        insert testAccount;

        // Create Opportunity (Closed Won for migration scenario)
        Opportunity testOpp = new Opportunity(
            Name = 'Order Migration Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-30)
        );
        insert testOpp;

        // Get standard pricebook
        Id pricebookId = Test.getStandardPricebookId();

        // Create Quote
        Quote testQuote = new Quote(
            Name = 'Order Migration Test Quote',
            OpportunityId = testOpp.Id,
            QuoteAccountId = testAccount.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft',
            IsPrimary__c = true
        );
        insert testQuote;

        // Create Product
        Product2 testProduct = new Product2(
            Name = 'Order Migration Test Product',
            ProductCode = 'ORD-MIG-PROD-001',
            IsActive = true,
            Family = 'Software'
        );
        insert testProduct;

        // Create PricebookEntry
        PricebookEntry testPbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 5000.00,
            IsActive = true
        );
        insert testPbe;

        // Create 3 QuoteLineItems
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();

        // QLI 1 - valid dates
        qlis.add(new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = testPbe.Id,
            Product2Id = testProduct.Id,
            Quantity = 1,
            UnitPrice = 5000.00,
            Legacy_Id__c = TEST_LEGACY_PREFIX + '001',
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 12, 31)
        ));

        // QLI 2 - valid dates
        qlis.add(new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = testPbe.Id,
            Product2Id = testProduct.Id,
            Quantity = 2,
            UnitPrice = 3000.00,
            Legacy_Id__c = TEST_LEGACY_PREFIX + '002',
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 12, 31)
        ));

        // QLI 3 - null dates (to test field gap analysis)
        qlis.add(new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = testPbe.Id,
            Product2Id = testProduct.Id,
            Quantity = 1,
            UnitPrice = 2000.00,
            Legacy_Id__c = TEST_LEGACY_PREFIX + '003'
        ));

        insert qlis;
    }

    // ── getRecordCounts Tests ─────────────────────────────────────────

    /**
     * @description Test getRecordCounts with a valid filter.
     *              Expects at least 1 quote and 2 QLIs (those with valid dates).
     */
    @IsTest
    static void testGetRecordCounts() {
        Test.startTest();
        OrderMigrationService.OrderMigrationPreview preview =
            OrderMigrationController.getRecordCounts(TEST_FILTER);
        Test.stopTest();

        System.assertNotEquals(null, preview, 'Preview should not be null');
        System.assert(preview.quoteCount >= 1,
            'Should find at least 1 quote, found: ' + preview.quoteCount);
        System.assert(preview.orderItemCount >= 2,
            'Should find at least 2 QLIs (source data for OrderItems), found: ' + preview.orderItemCount);
    }

    /**
     * @description Test getRecordCounts with an empty filter.
     *              Expects AuraHandledException.
     */
    @IsTest
    static void testGetRecordCounts_EmptyFilter() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            OrderMigrationController.getRecordCounts('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Filter is required', e.getMessage(),
                'Error message should indicate filter is required');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for empty filter');
    }

    // ── getFieldGapAnalysis Tests ─────────────────────────────────────

    /**
     * @description Test getFieldGapAnalysis with a valid filter.
     *              Expects non-empty results with ServiceDate showing nullCount > 0
     *              because the third QLI has null dates.
     */
    @IsTest
    static void testGetFieldGapAnalysis() {
        Test.startTest();
        List<OrderMigrationService.FieldGapInfo> gaps =
            OrderMigrationController.getFieldGapAnalysis(TEST_FILTER);
        Test.stopTest();

        System.assertNotEquals(null, gaps, 'Gap analysis should not be null');
        System.assert(!gaps.isEmpty(), 'Gap analysis should return at least one field');

        // Find ServiceDate entry and verify it has nulls
        Boolean foundServiceDate = false;
        for (OrderMigrationService.FieldGapInfo gap : gaps) {
            if (gap.fieldName == 'ServiceDate') {
                foundServiceDate = true;
                System.assert(gap.nullCount > 0,
                    'ServiceDate should have at least 1 null value from QLI without dates');
            }
        }
        System.assert(foundServiceDate, 'Should include ServiceDate in field gap analysis');
    }

    /**
     * @description Test getFieldGapAnalysis with an empty filter.
     *              Expects AuraHandledException.
     */
    @IsTest
    static void testGetFieldGapAnalysis_EmptyFilter() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            OrderMigrationController.getFieldGapAnalysis('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Filter is required', e.getMessage(),
                'Error message should indicate filter is required');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for empty filter');
    }

    // ── startMigration Tests ──────────────────────────────────────────

    /**
     * @description Test startMigration with valid params.
     *              Expects a non-null job ID string. Uses mock for asset creation callout.
     */
    @IsTest
    static void testStartMigration() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Test.startTest();
        String jobId = OrderMigrationController.startMigration(TEST_FILTER, 10, false, false, null, false);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job ID should not be null');
        System.assert(String.isNotBlank(jobId), 'Job ID should not be blank');
    }

    /**
     * @description Test startMigration with an empty filter.
     *              Expects AuraHandledException.
     */
    @IsTest
    static void testStartMigration_EmptyFilter() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            OrderMigrationController.startMigration('', 10, false, false, null, false);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Filter is required', e.getMessage(),
                'Error message should indicate filter is required');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for empty filter');
    }

    // ── getBatchStatus Tests ──────────────────────────────────────────

    /**
     * @description Test getBatchStatus with a valid job ID from startMigration.
     *              After Test.stopTest the batch completes synchronously,
     *              so the status map should contain relevant keys.
     */
    @IsTest
    static void testGetBatchStatus() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Test.startTest();
        String jobId = OrderMigrationController.startMigration(TEST_FILTER, 10, false, false, null, false);
        Test.stopTest();

        Map<String, Object> status = OrderMigrationController.getBatchStatus(jobId);

        System.assertNotEquals(null, status, 'Status map should not be null');
        System.assert(status.containsKey('status'), 'Status map should contain status key');
        System.assert(status.containsKey('itemsProcessed'), 'Status map should contain itemsProcessed key');
        System.assert(status.containsKey('totalItems'), 'Status map should contain totalItems key');
        System.assert(status.containsKey('progressPercent'), 'Status map should contain progressPercent key');
        System.assert(status.containsKey('isComplete'), 'Status map should contain isComplete key');
    }

    /**
     * @description Test getBatchStatus with an empty job ID.
     *              Expects a map with an 'error' key instead of throwing.
     */
    @IsTest
    static void testGetBatchStatus_EmptyJobId() {
        Test.startTest();
        Map<String, Object> status = OrderMigrationController.getBatchStatus('');
        Test.stopTest();

        System.assertNotEquals(null, status, 'Status map should not be null');
        System.assert(status.containsKey('error'), 'Status map should contain error key for empty job ID');
        System.assertEquals('Job ID is required', status.get('error'),
            'Error message should indicate Job ID is required');
    }

    // ── abortMigration Tests ──────────────────────────────────────────

    @IsTest
    static void testAbortMigration_EmptyJobId() {
        Boolean threw = false;
        Test.startTest();
        try {
            OrderMigrationController.abortMigration('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'abortMigration should reject blank job IDs');
    }

    @IsTest
    static void testAbortMigration_JobNotFound() {
        Boolean threw = false;
        Test.startTest();
        try {
            // 707 is the AsyncApexJob key prefix — well-formed but nonexistent.
            OrderMigrationController.abortMigration('707000000000000AAA');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'abortMigration should reject unknown job IDs');
    }

    // ── getMigrationDefaults Test ─────────────────────────────────────

    /**
     * @description Test getMigrationDefaults.
     *              Should return a list (possibly empty if no CMT records
     *              exist in test context) without throwing.
     */
    @IsTest
    static void testGetMigrationDefaults() {
        Test.startTest();
        List<Migration_Field_Default__mdt> defaults =
            OrderMigrationController.getMigrationDefaults();
        Test.stopTest();

        System.assertNotEquals(null, defaults, 'Defaults list should not be null');
        // CMT records may or may not be visible in test context,
        // so we only verify no exception was thrown and a list was returned.
    }

    // ── Pricebook selector + preset endpoints (feature) ───────────────

    @IsTest
    static void testGetAvailablePricebooks() {
        // Test context excludes the Standard Pricebook from SOQL, so we assert on
        // a custom pricebook we insert ourselves.
        Pricebook2 customPb = new Pricebook2(Name = 'Ctrl Available PB Test', IsActive = true);
        insert customPb;

        Test.startTest();
        List<Pricebook2> pbs = OrderMigrationController.getAvailablePricebooks();
        Test.stopTest();

        System.assertNotEquals(null, pbs, 'Should return a list');
        Boolean found = false;
        for (Pricebook2 pb : pbs) {
            if (pb.Id == customPb.Id) { found = true; break; }
        }
        System.assertEquals(true, found,
            'Custom pricebook inserted in test should appear in the list');
    }

    @IsTest
    static void testGetCoverageAnalysis_NullPricebookReturnsEmpty() {
        Test.startTest();
        OrderMigrationService.CoverageAnalysis a =
            OrderMigrationController.getCoverageAnalysis(TEST_FILTER, null);
        Test.stopTest();

        System.assertNotEquals(null, a, 'Analysis should be non-null even when target is null');
        System.assertEquals(0, a.totalQuotes,
            'Null target pricebook should short-circuit to empty analysis');
    }

    @IsTest
    static void testGetCoverageAnalysis_EmptyFilterThrows() {
        Boolean thrown = false;
        Test.startTest();
        try {
            OrderMigrationController.getCoverageAnalysis('', null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Empty filter should raise AuraHandledException');
    }

    @IsTest
    static void testSavedFilter_EndpointRoundTrip() {
        Test.startTest();
        Migration_Saved_Filter__c created = OrderMigrationController.saveFilter(
            null, 'Ctrl Preset', 'like', 'X_%', null
        );
        System.assertNotEquals(null, created.Id, 'Save should persist');

        List<Migration_Saved_Filter__c> listed = OrderMigrationController.listSavedFilters();
        System.assert(!listed.isEmpty(), 'List endpoint should return saved entries');

        OrderMigrationController.touchSavedFilter(created.Id);
        OrderMigrationController.deleteSavedFilter(created.Id);
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT() FROM Migration_Saved_Filter__c WHERE Id = :created.Id
        ];
        System.assertEquals(0, remaining, 'Delete endpoint should remove the record');
    }

    @IsTest
    static void testSavedFilter_SaveBlankNameRejected() {
        Boolean thrown = false;
        Test.startTest();
        try {
            OrderMigrationController.saveFilter(null, '', 'like', 'X_%', null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Blank name should raise AuraHandledException');
    }

    @IsTest
    static void testSavedPricebookPreset_EndpointRoundTrip() {
        Pricebook2 pb = new Pricebook2(Name = 'Ctrl PB', IsActive = true);
        insert pb;

        Test.startTest();
        Migration_Saved_Pricebook_Preset__c created =
            OrderMigrationController.savePricebookPreset(
                null, 'Ctrl PB Preset', pb.Id, true, 'From controller test'
            );
        System.assertNotEquals(null, created.Id, 'Save should persist');

        List<Migration_Saved_Pricebook_Preset__c> listed =
            OrderMigrationController.listSavedPricebookPresets();
        System.assert(!listed.isEmpty(), 'List endpoint should return saved entries');

        OrderMigrationController.touchSavedPricebookPreset(created.Id);
        OrderMigrationController.deleteSavedPricebookPreset(created.Id);
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT() FROM Migration_Saved_Pricebook_Preset__c WHERE Id = :created.Id
        ];
        System.assertEquals(0, remaining, 'Delete endpoint should remove the record');
    }

    @IsTest
    static void testSavedPricebookPreset_MissingPricebookRejected() {
        Boolean thrown = false;
        Test.startTest();
        try {
            OrderMigrationController.savePricebookPreset(null, 'No PB', null, false, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assertEquals(true, thrown,
            'Null pricebook id should raise AuraHandledException');
    }

    @IsTest
    static void testMigrateLocalStorageFilters_Endpoint() {
        List<Map<String, Object>> entries = new List<Map<String, Object>>();
        entries.add(new Map<String, Object>{
            'name' => 'Ctrl Migrated', 'filterMode' => 'like',
            'filterValue' => 'CTRL_%'
        });

        Test.startTest();
        Integer inserted = OrderMigrationController.migrateLocalStorageFilters(entries);
        Test.stopTest();

        System.assertEquals(1, inserted, 'Endpoint should insert one record');
    }

    // ── Run report bucket aggregator ──────────────────────────────────

    @IsTest
    static void testGetRunDetailBuckets_AggregatesByCategory() {
        Quote q = [SELECT Id, QuoteNumber FROM Quote LIMIT 1];
        Migration_Run_Log__c log = new Migration_Run_Log__c(
            Run_Date__c = Datetime.now(),
            Status__c = 'Completed'
        );
        insert log;

        // Two NoAccountId rows for the SAME quote → bucket count=2, quoteCount=1
        // One MissingPbeCoverage row for the same quote → separate bucket
        List<Migration_Run_Detail__c> details = new List<Migration_Run_Detail__c>{
            new Migration_Run_Detail__c(
                Run_Log__c = log.Id, Category__c = 'NoAccountId', Severity__c = 'Skip',
                Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
                Reason__c = 'Quote is missing QuoteAccountId',
                Cleanup_Required__c = false),
            new Migration_Run_Detail__c(
                Run_Log__c = log.Id, Category__c = 'NoAccountId', Severity__c = 'Skip',
                Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
                Reason__c = 'Quote is missing QuoteAccountId',
                Cleanup_Required__c = false),
            new Migration_Run_Detail__c(
                Run_Log__c = log.Id, Category__c = 'MissingPbeCoverage', Severity__c = 'Skip',
                Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
                Reason__c = '1 product missing PricebookEntry',
                Cleanup_Required__c = false)
        };
        insert details;

        Test.startTest();
        List<OrderMigrationController.BucketSummary> buckets =
            OrderMigrationController.getRunDetailBuckets(log.Id);
        Test.stopTest();

        System.assertEquals(2, buckets.size(),
            'Two distinct categories should yield two buckets');
        Map<String, OrderMigrationController.BucketSummary> byApi =
            new Map<String, OrderMigrationController.BucketSummary>();
        for (OrderMigrationController.BucketSummary b : buckets) {
            byApi.put(b.apiName, b);
        }
        System.assertEquals(2, byApi.get('NoAccountId').count,
            'NoAccountId should have 2 detail rows');
        System.assertEquals(1, byApi.get('NoAccountId').quoteCount,
            'NoAccountId should dedupe to 1 distinct Quote');
        System.assertEquals(false, byApi.get('NoAccountId').cleanupRequired,
            'NoAccountId should not require cleanup');
        System.assertEquals(1, byApi.get('MissingPbeCoverage').count,
            'MissingPbeCoverage should have 1 detail row');
    }

    @IsTest
    static void testGetRunDetailBuckets_NullRunLog() {
        Test.startTest();
        List<OrderMigrationController.BucketSummary> buckets =
            OrderMigrationController.getRunDetailBuckets(null);
        Test.stopTest();

        System.assertEquals(0, buckets.size(),
            'Null runLogId should produce empty bucket list');
    }

    // ── Rerun Queue endpoints ─────────────────────────────────────────

    @IsTest
    static void testAddBucketToQueue_FlipsFlagAndStampsMetadata() {
        Quote q = [SELECT Id, QuoteNumber FROM Quote LIMIT 1];
        Migration_Run_Log__c log = new Migration_Run_Log__c(
            Run_Date__c = Datetime.now(), Status__c = 'Completed');
        insert log;
        Migration_Run_Detail__c d = new Migration_Run_Detail__c(
            Run_Log__c = log.Id, Category__c = 'NoAccountId', Severity__c = 'Skip',
            Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
            Reason__c = 'test', Cleanup_Required__c = false);
        insert d;

        Test.startTest();
        Integer added = OrderMigrationController.addBucketToQueue(log.Id, 'NoAccountId');
        Test.stopTest();

        System.assertEquals(1, added, 'One row should be flipped');
        Migration_Run_Detail__c reloaded = [
            SELECT In_Rerun_Queue__c, Queued_Date__c, Queued_By__c
            FROM Migration_Run_Detail__c WHERE Id = :d.Id
        ];
        System.assertEquals(true, reloaded.In_Rerun_Queue__c, 'Flag should be true');
        System.assertNotEquals(null, reloaded.Queued_Date__c, 'Queued_Date should be stamped');
        System.assertEquals(UserInfo.getUserId(), reloaded.Queued_By__c,
            'Queued_By should be running user');
    }

    @IsTest
    static void testGetRerunQueueBuckets_AggregatesAcrossRunLogs() {
        Quote q = [SELECT Id, QuoteNumber FROM Quote LIMIT 1];
        Migration_Run_Log__c logA = new Migration_Run_Log__c(
            Run_Date__c = Datetime.now(), Status__c = 'Completed');
        Migration_Run_Log__c logB = new Migration_Run_Log__c(
            Run_Date__c = Datetime.now(), Status__c = 'Completed');
        insert new List<Migration_Run_Log__c>{ logA, logB };

        // Same Quote, different run logs, different categories — all queued
        insert new List<Migration_Run_Detail__c>{
            new Migration_Run_Detail__c(
                Run_Log__c = logA.Id, Category__c = 'NoAccountId', Severity__c = 'Skip',
                Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
                Reason__c = 'a', Cleanup_Required__c = false,
                In_Rerun_Queue__c = true),
            new Migration_Run_Detail__c(
                Run_Log__c = logB.Id, Category__c = 'OiaInsertFailed', Severity__c = 'Error',
                Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
                Reason__c = 'b', Cleanup_Required__c = true,
                In_Rerun_Queue__c = true),
            // Decoy: NOT queued, should be invisible
            new Migration_Run_Detail__c(
                Run_Log__c = logB.Id, Category__c = 'ContractResolutionFailed', Severity__c = 'Error',
                Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
                Reason__c = 'c', Cleanup_Required__c = false,
                In_Rerun_Queue__c = false)
        };

        Test.startTest();
        OrderMigrationController.RerunQueueSummary summary =
            OrderMigrationController.getRerunQueueBuckets();
        Test.stopTest();

        System.assertEquals(2, summary.buckets.size(),
            'Two queued categories across two run logs');
        System.assertEquals(1, summary.totalDistinctQuotes,
            'Same Quote in both buckets should dedupe to 1');
    }

    @IsTest
    static void testRemoveFromQueue_ScopedAndGlobal() {
        Quote q = [SELECT Id, QuoteNumber FROM Quote LIMIT 1];
        Migration_Run_Log__c log = new Migration_Run_Log__c(
            Run_Date__c = Datetime.now(), Status__c = 'Completed');
        insert log;
        Migration_Run_Detail__c d1 = new Migration_Run_Detail__c(
            Run_Log__c = log.Id, Category__c = 'NoAccountId', Severity__c = 'Skip',
            Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
            Reason__c = 'a', Cleanup_Required__c = false,
            In_Rerun_Queue__c = true);
        Migration_Run_Detail__c d2 = new Migration_Run_Detail__c(
            Run_Log__c = log.Id, Category__c = 'OiaInsertFailed', Severity__c = 'Error',
            Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
            Reason__c = 'b', Cleanup_Required__c = true,
            In_Rerun_Queue__c = true);
        insert new List<Migration_Run_Detail__c>{ d1, d2 };

        Test.startTest();
        Integer scoped = OrderMigrationController.removeFromQueue(
            new List<String>{ q.QuoteNumber }, 'NoAccountId');
        Test.stopTest();

        System.assertEquals(1, scoped, 'Scoped remove clears only the matching category');
        Migration_Run_Detail__c r1 = [
            SELECT In_Rerun_Queue__c FROM Migration_Run_Detail__c WHERE Id = :d1.Id];
        Migration_Run_Detail__c r2 = [
            SELECT In_Rerun_Queue__c FROM Migration_Run_Detail__c WHERE Id = :d2.Id];
        System.assertEquals(false, r1.In_Rerun_Queue__c, 'NoAccountId row cleared');
        System.assertEquals(true, r2.In_Rerun_Queue__c, 'OiaInsertFailed row preserved');
    }

    @IsTest
    static void testClearQueue_FlipsAllFlags() {
        Quote q = [SELECT Id, QuoteNumber FROM Quote LIMIT 1];
        Migration_Run_Log__c log = new Migration_Run_Log__c(
            Run_Date__c = Datetime.now(), Status__c = 'Completed');
        insert log;
        insert new List<Migration_Run_Detail__c>{
            new Migration_Run_Detail__c(
                Run_Log__c = log.Id, Category__c = 'NoAccountId', Severity__c = 'Skip',
                Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
                Reason__c = 'a', Cleanup_Required__c = false,
                In_Rerun_Queue__c = true),
            new Migration_Run_Detail__c(
                Run_Log__c = log.Id, Category__c = 'OiaInsertFailed', Severity__c = 'Error',
                Quote__c = q.Id, Quote_Number__c = q.QuoteNumber,
                Reason__c = 'b', Cleanup_Required__c = true,
                In_Rerun_Queue__c = true)
        };

        Test.startTest();
        Integer cleared = OrderMigrationController.clearQueue();
        Test.stopTest();

        System.assertEquals(2, cleared, 'Both queued rows cleared');
        Integer remaining = [
            SELECT COUNT() FROM Migration_Run_Detail__c
            WHERE In_Rerun_Queue__c = true
        ];
        System.assertEquals(0, remaining, 'Nothing should remain in queue');
    }

    @IsTest
    static void testGetRunDetailRows_FiltersByCategory() {
        Quote q = [SELECT Id, QuoteNumber FROM Quote LIMIT 1];
        Migration_Run_Log__c log = new Migration_Run_Log__c(
            Run_Date__c = Datetime.now(), Status__c = 'Completed');
        insert log;

        insert new List<Migration_Run_Detail__c>{
            new Migration_Run_Detail__c(
                Run_Log__c = log.Id, Category__c = 'NoAccountId', Severity__c = 'Skip',
                Quote_Number__c = q.QuoteNumber, Reason__c = 'a', Cleanup_Required__c = false),
            new Migration_Run_Detail__c(
                Run_Log__c = log.Id, Category__c = 'OiaInsertFailed', Severity__c = 'Error',
                Quote_Number__c = q.QuoteNumber, Reason__c = 'b', Cleanup_Required__c = true)
        };

        Test.startTest();
        List<Migration_Run_Detail__c> rows =
            OrderMigrationController.getRunDetailRows(log.Id, 'OiaInsertFailed');
        Test.stopTest();

        System.assertEquals(1, rows.size(),
            'Only the OiaInsertFailed row should be returned');
        System.assertEquals('OiaInsertFailed', rows[0].Category__c,
            'Returned row should match requested category');
    }
}