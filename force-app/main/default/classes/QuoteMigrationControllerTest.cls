/**
 * @description Test class for QuoteMigrationController
 * @author Marc DeBrey
 * @version 1.1
 * @since 2026-02
 */
@IsTest
private class QuoteMigrationControllerTest {

    // Test data constants
    private static final String TEST_ACCOUNT_NAME = 'Migration Test Account';
    private static final String TEST_LEGACY_PREFIX = 'DY_TEST_';
    private static final String TEST_FILTER = 'DY_%';

    /**
     * @description Create test data: Account, Opportunity, Quote, Products, PBEs, and QLIs.
     *              Three QLIs are created with Legacy_Id__c values DY_TEST_001, DY_TEST_002,
     *              DY_TEST_003. The third QLI has null ServiceDate and EndDate to test
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
            BillingStreet = '123 Migration Test St'
        );
        insert testAccount;

        // Create Opportunity (Closed Won for migration scenario)
        Opportunity testOpp = new Opportunity(
            Name = 'Migration Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-30)
        );
        insert testOpp;

        // Get standard pricebook
        Id pricebookId = Test.getStandardPricebookId();

        // Create Quote
        Quote testQuote = new Quote(
            Name = 'Migration Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft',
            IsPrimary__c = true
        );
        insert testQuote;

        // Create Product
        Product2 testProduct = new Product2(
            Name = 'Migration Test Product',
            ProductCode = 'MIG-PROD-001',
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
            ServiceDate = Date.today(),
            EndDate = Date.today().addMonths(12)
        ));

        // QLI 2 - valid dates
        qlis.add(new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = testPbe.Id,
            Product2Id = testProduct.Id,
            Quantity = 2,
            UnitPrice = 3000.00,
            Legacy_Id__c = TEST_LEGACY_PREFIX + '002',
            ServiceDate = Date.today(),
            EndDate = Date.today().addMonths(12)
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

        // Create attribute data for attribute loading tests
        AttributePicklist testPicklist = new AttributePicklist(
            Name = 'Controller Test Picklist'
        );
        insert testPicklist;

        AttributeDefinition adPicklist = new AttributeDefinition(
            Name = 'Server Type',
            DeveloperName = 'Ctrl_Server_Type',
            Label = 'Server Type',
            DataType = 'Picklist',
            PicklistId = testPicklist.Id,
            IsActive = true
        );
        insert adPicklist;

        insert new AttributePicklistValue(
            Name = 'Production', Code = 'CPROD', Value = 'Production',
            PicklistId = testPicklist.Id
        );
    }

    /**
     * @description Test getRecordCounts with a valid filter.
     *              Expects at least 1 quote and 2 QLIs (those with valid dates).
     */
    @IsTest
    static void testGetRecordCounts() {
        Test.startTest();
        QuoteMigrationService.MigrationPreview preview =
            QuoteMigrationController.getRecordCounts(TEST_FILTER);
        Test.stopTest();

        System.assertNotEquals(null, preview, 'Preview should not be null');
        System.assert(preview.quoteCount >= 1, 'Should find at least 1 quote');
        System.assert(preview.qliCount >= 2, 'Should find at least 2 QLIs');
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
            QuoteMigrationController.getRecordCounts('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Filter is required', e.getMessage(),
                'Error message should indicate filter is required');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for empty filter');
    }

    /**
     * @description Test getFieldGapAnalysis with a valid filter.
     *              Expects non-empty results with ServiceDate showing nullCount > 0
     *              because the third QLI has null ServiceDate.
     */
    @IsTest
    static void testGetFieldGapAnalysis() {
        Test.startTest();
        List<QuoteMigrationService.FieldGapInfo> gaps =
            QuoteMigrationController.getFieldGapAnalysis(TEST_FILTER);
        Test.stopTest();

        System.assertNotEquals(null, gaps, 'Gap analysis should not be null');
        System.assert(!gaps.isEmpty(), 'Gap analysis should return at least one field');

        // Find ServiceDate entry and verify it has nulls
        Boolean foundServiceDate = false;
        for (QuoteMigrationService.FieldGapInfo gap : gaps) {
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
            QuoteMigrationController.getFieldGapAnalysis('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Filter is required', e.getMessage(),
                'Error message should indicate filter is required');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for empty filter');
    }

    /**
     * @description Test startMigration with valid parameters (no reprice).
     *              Expects a non-null job ID string.
     */
    @IsTest
    static void testStartMigration() {
        Test.startTest();
        String jobId = QuoteMigrationController.startMigration(TEST_FILTER, false, 10, false);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job ID should not be null');
        System.assert(String.isNotBlank(jobId), 'Job ID should not be blank');
    }

    /**
     * @description Test startMigration with includeReprice=true.
     *              Expects a non-null job ID string.
     */
    @IsTest
    static void testStartMigration_WithReprice() {
        Test.startTest();
        String jobId = QuoteMigrationController.startMigration(TEST_FILTER, false, 10, true);
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
            QuoteMigrationController.startMigration('', false, 10, false);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Filter is required', e.getMessage(),
                'Error message should indicate filter is required');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for empty filter');
    }

    /**
     * @description Test getBatchStatus with a valid job ID from startMigration.
     *              After Test.stopTest the batch completes synchronously,
     *              so the status map should contain relevant keys.
     */
    @IsTest
    static void testGetBatchStatus() {
        Test.startTest();
        String jobId = QuoteMigrationController.startMigration(TEST_FILTER, false, 10, false);
        Test.stopTest();

        Map<String, Object> status = QuoteMigrationController.getBatchStatus(jobId);

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
        Map<String, Object> status = QuoteMigrationController.getBatchStatus('');
        Test.stopTest();

        System.assertNotEquals(null, status, 'Status map should not be null');
        System.assert(status.containsKey('error'), 'Status map should contain error key for empty job ID');
        System.assertEquals('Job ID is required', status.get('error'),
            'Error message should indicate Job ID is required');
    }

    /**
     * @description Test getMigrationDefaults.
     *              Should return a list (possibly empty if no CMT records
     *              exist in test context) without throwing.
     */
    @IsTest
    static void testGetMigrationDefaults() {
        Test.startTest();
        List<Migration_Field_Default__mdt> defaults =
            QuoteMigrationController.getMigrationDefaults();
        Test.stopTest();

        System.assertNotEquals(null, defaults, 'Defaults list should not be null');
        // CMT records may or may not be visible in test context,
        // so we only verify no exception was thrown and a list was returned.
    }

    // ── Attribute Loading Tests ───────────────────────────────────────

    /**
     * @description Test previewAttributeLoad with valid CSV content.
     */
    @IsTest
    static void testPreviewAttributeLoad() {
        String csv = 'Legacy_Id__c,Server Type\n' +
                      TEST_LEGACY_PREFIX + '001,Production\n' +
                      TEST_LEGACY_PREFIX + '002,Production';

        Test.startTest();
        AttributeLoadingService.AttributePreview preview =
            QuoteMigrationController.previewAttributeLoad(csv);
        Test.stopTest();

        System.assertNotEquals(null, preview, 'Preview should not be null');
        System.assertEquals(2, preview.rowCount, 'Should find 2 CSV rows');
        System.assertEquals(2, preview.attributeCount, 'Should find 2 attributes to create');
        System.assert(preview.errors.isEmpty(), 'Should have no blocking errors');
    }

    /**
     * @description Test previewAttributeLoad with empty CSV.
     */
    @IsTest
    static void testPreviewAttributeLoad_EmptyCsv() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            QuoteMigrationController.previewAttributeLoad('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('CSV content is required', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw for empty CSV');
    }

    /**
     * @description Test startAttributeLoad with valid CSV content.
     *              Note: QLIA creation count not asserted because QuoteLineItemAttribute
     *              is an internal sObject that uses Database.insertImmediate() which
     *              does not persist in test context. Verified via manual E2E testing.
     */
    @IsTest
    static void testStartAttributeLoad() {
        String csv = 'Legacy_Id__c,Server Type\n' +
                      TEST_LEGACY_PREFIX + '001,Production';

        Test.startTest();
        String jobId = QuoteMigrationController.startAttributeLoad(csv);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job ID should not be null');
        System.assert(String.isNotBlank(jobId), 'Job ID should not be blank');

        // Verify batch completed
        AsyncApexJob job = [
            SELECT Status FROM AsyncApexJob WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete successfully');
    }

    /**
     * @description Test startAttributeLoad with empty CSV.
     */
    @IsTest
    static void testStartAttributeLoad_EmptyCsv() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            QuoteMigrationController.startAttributeLoad('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('CSV content is required', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw for empty CSV');
    }

    /**
     * @description Test getAttributeLoadStatus with a valid job ID.
     */
    @IsTest
    static void testGetAttributeLoadStatus() {
        String csv = 'Legacy_Id__c,Server Type\n' +
                      TEST_LEGACY_PREFIX + '001,Production';

        Test.startTest();
        String jobId = QuoteMigrationController.startAttributeLoad(csv);
        Test.stopTest();

        Map<String, Object> status = QuoteMigrationController.getAttributeLoadStatus(jobId);
        System.assertNotEquals(null, status, 'Status map should not be null');
        System.assert(status.containsKey('status'), 'Should contain status key');
        System.assert(status.containsKey('isComplete'), 'Should contain isComplete key');
    }
}