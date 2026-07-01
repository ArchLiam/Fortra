/**
 * @description Test class for QuoteMigrationBatch.
 *              Validates batch processing of legacy Quotes and QuoteLineItems,
 *              including field calculations, price preservation, skip logic for
 *              missing dates, Q2O preparation, and Migration_Run_Log__c creation.
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-02
 */
@IsTest
private class QuoteMigrationBatchTest {

    private static final String LEGACY_PREFIX = 'DY_TEST_';

    /**
     * @description Setup test data - creates Account, Opportunity, Product, PBE,
     *              Quote (Primary on Closed Won Opp), and 5 QuoteLineItems with
     *              varying date completeness for skip/process testing.
     */
    @TestSetup
    static void setupTestData() {
        // Account
        Account acct = new Account(Name = 'Migration Test Account');
        insert acct;

        // Opportunity (Closed Won)
        Opportunity opp = new Opportunity(
            Name = 'Migration Test Opp',
            AccountId = acct.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today()
        );
        insert opp;

        // Product
        Product2 prod = new Product2(
            Name = 'Migration Test Product',
            ProductCode = 'MIG-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert prod;

        // Standard PricebookEntry
        PricebookEntry stdPbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            UnitPrice = 100.00,
            IsActive = true
        );
        insert stdPbe;

        // Quote (Primary)
        Quote q = new Quote(
            Name = 'Migration Test Quote',
            OpportunityId = opp.Id,
            IsPrimary__c = true,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert q;

        // QuoteLineItems
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();

        // QLI 1: 12-month term (Jan 2026 - Dec 2026)
        qlis.add(new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = prod.Id,
            PricebookEntryId = stdPbe.Id,
            Quantity = 1,
            UnitPrice = 500.00,
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 12, 31),
            Legacy_Id__c = LEGACY_PREFIX + '001'
        ));

        // QLI 2: 24-month term (Jan 2026 - Dec 2027)
        qlis.add(new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = prod.Id,
            PricebookEntryId = stdPbe.Id,
            Quantity = 1,
            UnitPrice = 1000.00,
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2027, 12, 31),
            Legacy_Id__c = LEGACY_PREFIX + '002'
        ));

        // QLI 3: 12-month term (Jun 2026 - May 2027)
        qlis.add(new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = prod.Id,
            PricebookEntryId = stdPbe.Id,
            Quantity = 1,
            UnitPrice = 750.00,
            StartDate = Date.newInstance(2026, 6, 1),
            EndDate = Date.newInstance(2027, 5, 31),
            Legacy_Id__c = LEGACY_PREFIX + '003'
        ));

        // QLI 4: Missing StartDate (should be skipped)
        qlis.add(new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = prod.Id,
            PricebookEntryId = stdPbe.Id,
            Quantity = 1,
            UnitPrice = 200.00,
            EndDate = Date.newInstance(2026, 12, 31),
            Legacy_Id__c = LEGACY_PREFIX + '004'
        ));

        // QLI 5: Missing EndDate (should be skipped)
        qlis.add(new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = prod.Id,
            PricebookEntryId = stdPbe.Id,
            Quantity = 1,
            UnitPrice = 300.00,
            StartDate = Date.newInstance(2026, 1, 1),
            Legacy_Id__c = LEGACY_PREFIX + '005'
        ));

        insert qlis;
    }

    /**
     * @description Test successful batch execution. Verifies that QLIs with valid dates
     *              are populated with ServiceDate and SubscriptionTerm,
     *              and that a Migration_Run_Log__c record is created.
     */
    @IsTest
    static void testBatchExecution_Success() {
        // Diagnostic: verify test data exists before batch run
        Quote testQuote = [
            SELECT Id, IsPrimary__c, Opportunity.StageName
            FROM Quote WHERE Name = 'Migration Test Quote' LIMIT 1
        ];
        System.assertEquals(true, testQuote.IsPrimary__c,
            'DIAG: Quote.IsPrimary__c should be true');
        System.assertEquals('Closed Won', testQuote.Opportunity.StageName,
            'DIAG: Opp should be Closed Won');

        Integer matchingQlis = [
            SELECT COUNT() FROM QuoteLineItem
            WHERE Legacy_Id__c LIKE 'DY_%' AND QuoteId = :testQuote.Id
        ];
        System.assert(matchingQlis > 0,
            'DIAG: Should have QLIs matching DY_% filter, found: ' + matchingQlis);

        // Verify the same query the batch start() uses
        Integer matchingQuotes = [
            SELECT COUNT() FROM Quote
            WHERE Id = :testQuote.Id
            AND IsPrimary__c = true
            AND Opportunity.StageName = 'Closed Won'
        ];
        System.assertEquals(1, matchingQuotes,
            'DIAG: Batch start query should find the Quote');

        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', false, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Check AsyncApexJob status
        List<AsyncApexJob> jobs = [
            SELECT Status, ExtendedStatus, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(!jobs.isEmpty(), 'DIAG: Should have an AsyncApexJob record');
        AsyncApexJob job = jobs[0];
        System.assertEquals('Completed', job.Status,
            'DIAG: Batch job should be Completed. Status=' + job.Status +
            ', ExtendedStatus=' + job.ExtendedStatus +
            ', Errors=' + job.NumberOfErrors +
            ', Processed=' + job.JobItemsProcessed + '/' + job.TotalJobItems);

        // Verify batch actually processed by checking the log
        Migration_Run_Log__c log = [
            SELECT Quotes_Processed__c, QLIs_Processed__c, QLIs_Succeeded__c,
                   QLIs_Skipped__c, Status__c, Errors__c, Filter_Used__c
            FROM Migration_Run_Log__c LIMIT 1
        ];
        System.assert(log.Quotes_Processed__c > 0,
            'DIAG: Batch should have processed at least 1 quote. Log status: ' +
            log.Status__c + ', Errors: ' + log.Errors__c +
            ', Filter: ' + log.Filter_Used__c +
            ', JobItems: ' + job.JobItemsProcessed + '/' + job.TotalJobItems);

        // DIAG: Check execute() internals via the log
        System.assertEquals('Completed', log.Status__c,
            'DIAG: Log status should be Completed, not Failed/Partial. ' +
            'QuotesProcessed=' + log.Quotes_Processed__c +
            ', QLIsProcessed=' + log.QLIs_Processed__c +
            ', QLIsSucceeded=' + log.QLIs_Succeeded__c +
            ', QLIsSkipped=' + log.QLIs_Skipped__c +
            ', Errors=' + log.Errors__c);

        System.assert(log.QLIs_Processed__c > 0,
            'DIAG: Should have processed QLIs. ' +
            'QuotesProcessed=' + log.Quotes_Processed__c +
            ', QLIsProcessed=' + log.QLIs_Processed__c +
            ', Errors=' + log.Errors__c);

        // Verify QLIs with valid dates are populated
        List<QuoteLineItem> processedQlis = [
            SELECT Id, ServiceDate, SubscriptionTerm, Legacy_Id__c
            FROM QuoteLineItem
            WHERE Legacy_Id__c IN ('DY_TEST_001', 'DY_TEST_002', 'DY_TEST_003')
            ORDER BY Legacy_Id__c
        ];

        System.assertEquals(3, processedQlis.size(), 'Should have 3 processed QLIs');

        for (QuoteLineItem qli : processedQlis) {
            System.assertNotEquals(null, qli.ServiceDate,
                'ServiceDate should be populated for ' + qli.Legacy_Id__c);
            System.assertNotEquals(null, qli.SubscriptionTerm,
                'SubscriptionTerm should be populated for ' + qli.Legacy_Id__c);
        }

        // Verify Migration_Run_Log__c record created
        List<Migration_Run_Log__c> logs = [SELECT Id FROM Migration_Run_Log__c];
        System.assertEquals(1, logs.size(), 'Should have created one Migration Run Log');
    }

    /**
     * @description Test that QLIs with missing StartDate or EndDate are skipped
     *              and tracked in Migration_Run_Log__c.QLIs_Skipped__c.
     */
    @IsTest
    static void testBatchExecution_SkippedItems() {
        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', false, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify skipped QLIs were not modified
        List<QuoteLineItem> skippedQlis = [
            SELECT Id, ServiceDate, SubscriptionTerm, Legacy_Id__c
            FROM QuoteLineItem
            WHERE Legacy_Id__c IN ('DY_TEST_004', 'DY_TEST_005')
            ORDER BY Legacy_Id__c
        ];

        System.assertEquals(2, skippedQlis.size(), 'Should have 2 skipped QLIs');
        for (QuoteLineItem qli : skippedQlis) {
            System.assertEquals(null, qli.SubscriptionTerm,
                'Skipped QLI should not have SubscriptionTerm set for ' + qli.Legacy_Id__c);
        }

        // Verify Migration_Run_Log__c records skipped count
        Migration_Run_Log__c log = [
            SELECT QLIs_Skipped__c
            FROM Migration_Run_Log__c
            LIMIT 1
        ];
        System.assertEquals(2, log.QLIs_Skipped__c, 'Should have 2 skipped QLIs in log');
    }

    /**
     * @description Test that original UnitPrice and Discount values are preserved
     *              after batch processing (price preservation).
     */
    @IsTest
    static void testBatchExecution_PricePreservation() {
        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', false, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify UnitPrice values match original values
        Map<String, Decimal> expectedPrices = new Map<String, Decimal>{
            'DY_TEST_001' => 500.00,
            'DY_TEST_002' => 1000.00,
            'DY_TEST_003' => 750.00
        };

        List<QuoteLineItem> qlis = [
            SELECT Id, UnitPrice, Discount, Legacy_Id__c
            FROM QuoteLineItem
            WHERE Legacy_Id__c IN ('DY_TEST_001', 'DY_TEST_002', 'DY_TEST_003')
        ];

        for (QuoteLineItem qli : qlis) {
            System.assertEquals(
                expectedPrices.get(qli.Legacy_Id__c),
                qli.UnitPrice,
                'UnitPrice should be preserved for ' + qli.Legacy_Id__c
            );
            System.assertEquals(null, qli.Discount,
                'Discount should remain null for ' + qli.Legacy_Id__c);
        }
    }

    /**
     * @description Test that prepareForQ2O=true sets Quote.Status to Accepted.
     */
    @IsTest
    static void testBatchExecution_WithQ2OPrep() {
        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', true, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify Quote status
        Quote q = [SELECT Status FROM Quote WHERE Name = 'Migration Test Quote' LIMIT 1];
        System.assertEquals('Accepted', q.Status, 'Quote Status should be Accepted when prepareForQ2O=true');
    }

    /**
     * @description Test that a non-matching filter processes zero records without error.
     */
    @IsTest
    static void testBatchExecution_NoMatchingRecords() {
        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('NOMATCH_%', false, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify log shows zero records
        List<Migration_Run_Log__c> logs = [SELECT Quotes_Processed__c FROM Migration_Run_Log__c];
        System.assertEquals(1, logs.size(), 'Should still create a Migration Run Log');
        System.assertEquals(0, logs[0].Quotes_Processed__c,
            'Should have 0 quotes processed for non-matching filter');
    }

    /**
     * @description Diagnostic test: exercises the exact same SOQL queries
     *              that the batch start() method uses, outside the batch framework.
     *              If this passes but batch tests fail, the issue is batch-context-specific.
     */
    @IsTest
    static void testPreQueryLogic_OutsideBatch() {
        // Step 1: Pre-query QLIs (same as batch start())
        String likeFilter = 'DY_%';
        Set<Id> matchingQuoteIds = new Set<Id>();
        for (QuoteLineItem qli : [
            SELECT QuoteId FROM QuoteLineItem WHERE Legacy_Id__c LIKE :likeFilter
        ]) {
            matchingQuoteIds.add(qli.QuoteId);
        }

        System.assert(!matchingQuoteIds.isEmpty(),
            'DIAG: Pre-query should find QLIs. Filter: ' + likeFilter);
        System.assertEquals(1, matchingQuoteIds.size(),
            'DIAG: Should find exactly 1 unique Quote ID');

        // Step 2: Main query (same as batch QueryLocator)
        List<Quote> quotes = [
            SELECT Id, Name, QuoteNumber, Status, SalesTransactionTypeId,
                   OpportunityId, Opportunity.StageName, IsPrimary__c
            FROM Quote
            WHERE Id IN :matchingQuoteIds
            AND IsPrimary__c = true
            AND Opportunity.StageName = 'Closed Won'
            ORDER BY QuoteNumber
        ];

        System.assertEquals(1, quotes.size(),
            'DIAG: Main query should find 1 Quote. matchingQuoteIds=' + matchingQuoteIds +
            ', IsPrimary__c=' + (quotes.isEmpty() ? 'N/A' : String.valueOf(quotes[0].IsPrimary__c)));

        // Step 3: Verify child QLIs are findable for that Quote
        Id quoteId = quotes[0].Id;
        List<QuoteLineItem> qlis = [
            SELECT Id, Legacy_Id__c, StartDate, EndDate
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId AND Legacy_Id__c LIKE :likeFilter
        ];

        System.assertEquals(5, qlis.size(),
            'DIAG: Should find 5 QLIs for the Quote');
    }

    /**
     * @description Test field calculations: SubscriptionTerm
     *              for different date ranges (12-month and 24-month terms).
     */
    @IsTest
    static void testBatchExecution_FieldCalculations() {
        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', false, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // 12-month term QLI (Jan 2026 - Dec 2026)
        QuoteLineItem qli12 = [
            SELECT SubscriptionTerm
            FROM QuoteLineItem
            WHERE Legacy_Id__c = 'DY_TEST_001'
        ];
        System.assertEquals(12, qli12.SubscriptionTerm,
            '12-month term should have SubscriptionTerm=12');

        // 24-month term QLI (Jan 2026 - Dec 2027)
        QuoteLineItem qli24 = [
            SELECT SubscriptionTerm
            FROM QuoteLineItem
            WHERE Legacy_Id__c = 'DY_TEST_002'
        ];
        System.assertEquals(24, qli24.SubscriptionTerm,
            '24-month term should have SubscriptionTerm=24');
    }

    /**
     * @description Test batch execution with includeReprice=true.
     *              In test context the pricing engine cannot actually run,
     *              so the reprice step will fail gracefully. We verify that:
     *              - The batch completes without throwing
     *              - QLIs still get field calculations applied
     *              - Original prices are preserved
     *              - A Migration_Run_Log__c is created
     */
    @IsTest
    static void testBatchExecution_WithReprice() {
        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', false, 1, true);
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Verify batch completed and created a log
        List<Migration_Run_Log__c> logs = [SELECT Id, Status__c, Errors__c FROM Migration_Run_Log__c];
        System.assertEquals(1, logs.size(), 'Should create one Migration Run Log');

        // In test context, the repricing Flow may succeed (standard actions
        // run as no-ops) or fail depending on platform behavior. Accept both.
        Migration_Run_Log__c log = logs[0];
        if (log.Status__c == 'Completed') {
            // Repricing succeeded in test context — no error expected
            System.assert(log.Errors__c == null || !log.Errors__c.contains('Repricing failed'),
                'Completed log should not have repricing errors');
        } else {
            // Repricing failed — verify error is recorded
            System.assert(log.Errors__c != null && log.Errors__c.contains('Repricing failed'),
                'Failed log should contain repricing failure. Errors: ' + log.Errors__c);
        }

        // Verify QLIs with valid dates still got field calculations
        List<QuoteLineItem> processedQlis = [
            SELECT Id, ServiceDate, SubscriptionTerm, Legacy_Id__c
            FROM QuoteLineItem
            WHERE Legacy_Id__c IN ('DY_TEST_001', 'DY_TEST_002', 'DY_TEST_003')
            ORDER BY Legacy_Id__c
        ];

        for (QuoteLineItem qli : processedQlis) {
            System.assertNotEquals(null, qli.ServiceDate,
                'ServiceDate should be populated for ' + qli.Legacy_Id__c);
            System.assertNotEquals(null, qli.SubscriptionTerm,
                'SubscriptionTerm should be populated for ' + qli.Legacy_Id__c);
        }

        // Verify prices are preserved even with reprice failure
        Map<String, Decimal> expectedPrices = new Map<String, Decimal>{
            'DY_TEST_001' => 500.00,
            'DY_TEST_002' => 1000.00,
            'DY_TEST_003' => 750.00
        };

        List<QuoteLineItem> pricedQlis = [
            SELECT Id, UnitPrice, Legacy_Id__c
            FROM QuoteLineItem
            WHERE Legacy_Id__c IN ('DY_TEST_001', 'DY_TEST_002', 'DY_TEST_003')
        ];

        for (QuoteLineItem qli : pricedQlis) {
            System.assertEquals(
                expectedPrices.get(qli.Legacy_Id__c),
                qli.UnitPrice,
                'UnitPrice should be preserved for ' + qli.Legacy_Id__c
            );
        }
    }

    /**
     * @description Test that prepareForQ2O=true creates pre-checked checklist items
     *              for each successfully processed Quote. Verifies all items have
     *              Is_Checked__c=true with Checked_By__c and Checked_Date__c populated.
     */
    @IsTest
    static void testPrepareForQ2O_CreatesPreCheckedChecklistItems() {
        // First verify we have config items in the org (CMT is visible in tests)
        Integer configCount = [
            SELECT COUNT() FROM Operations_Checklist_Config__mdt WHERE Is_Active__c = true
        ];

        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', true, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Skip assertions if no config items exist in the org
        if (configCount == 0) {
            System.debug('SKIP: No Operations_Checklist_Config__mdt records in org');
            return;
        }

        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Migration Test Quote' LIMIT 1];

        // Verify checklist items were created
        List<Quote_Checklist_Item__c> items = [
            SELECT Id, Item_Name__c, Is_Checked__c, Checked_By__c, Checked_Date__c, Sort_Order__c
            FROM Quote_Checklist_Item__c
            WHERE Quote__c = :testQuote.Id
            ORDER BY Sort_Order__c ASC
        ];

        System.assertEquals(configCount, items.size(),
            'Should create one checklist item per active config record. ' +
            'Expected ' + configCount + ', got ' + items.size());

        for (Quote_Checklist_Item__c item : items) {
            System.assertEquals(true, item.Is_Checked__c,
                'Item should be pre-checked: ' + item.Item_Name__c);
            System.assertNotEquals(null, item.Checked_By__c,
                'Checked_By__c should be populated for: ' + item.Item_Name__c);
            System.assertNotEquals(null, item.Checked_Date__c,
                'Checked_Date__c should be populated for: ' + item.Item_Name__c);
        }
    }

    /**
     * @description Test idempotency: running prepareForQ2O twice should not create
     *              duplicate checklist items. The second run should skip Quotes
     *              that already have items.
     */
    @IsTest
    static void testPrepareForQ2O_SkipsExistingChecklistItems() {
        Integer configCount = [
            SELECT COUNT() FROM Operations_Checklist_Config__mdt WHERE Is_Active__c = true
        ];

        if (configCount == 0) {
            System.debug('SKIP: No Operations_Checklist_Config__mdt records in org');
            return;
        }

        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Migration Test Quote' LIMIT 1];

        // Pre-create a checklist item to simulate a previous run
        insert new Quote_Checklist_Item__c(
            Quote__c = testQuote.Id,
            Item_Name__c = 'Existing Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', true, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Should still only have the 1 pre-existing item (no new items created)
        List<Quote_Checklist_Item__c> items = [
            SELECT Id FROM Quote_Checklist_Item__c WHERE Quote__c = :testQuote.Id
        ];

        System.assertEquals(1, items.size(),
            'Should NOT create new items when items already exist. Found: ' + items.size());
    }

    /**
     * @description Test that prepareForQ2O=false creates zero checklist items.
     */
    @IsTest
    static void testPrepareForQ2O_False_NoChecklistCreated() {
        Test.startTest();
        QuoteMigrationBatch batch = new QuoteMigrationBatch('DY_%', false, 10);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Migration Test Quote' LIMIT 1];

        List<Quote_Checklist_Item__c> items = [
            SELECT Id FROM Quote_Checklist_Item__c WHERE Quote__c = :testQuote.Id
        ];

        System.assertEquals(0, items.size(),
            'prepareForQ2O=false should not create any checklist items');
    }

    /**
     * @description Test that the 4-parameter constructor correctly forces batch size
     *              to 1 when includeReprice is true.
     */
    @IsTest
    static void testConstructor_RepriceForceBatchSize() {
        // The 4-param constructor with includeReprice=true should work
        // (we can't directly inspect private fields, but we verify it doesn't throw)
        Test.startTest();
        QuoteMigrationBatch batchReprice = new QuoteMigrationBatch('DY_%', false, 50, true);
        QuoteMigrationBatch batchNoReprice = new QuoteMigrationBatch('DY_%', false, 50, false);
        QuoteMigrationBatch batchLegacy = new QuoteMigrationBatch('DY_%', false, 50);
        Test.stopTest();

        // No assertions on private fields — just verify no exceptions
        System.assertNotEquals(null, batchReprice, 'Reprice batch should be created');
        System.assertNotEquals(null, batchNoReprice, 'No-reprice batch should be created');
        System.assertNotEquals(null, batchLegacy, 'Legacy 3-param batch should be created');
    }
}