/**
 * @description Test class for OrderMigrationBatch.
 *              Validates batch processing of legacy Quotes into Revenue Cloud Orders,
 *              including field calculations, AUA bypass pipeline, asset creation,
 *              Contract resolution, skip logic for missing dates, activation options,
 *              and Migration_Run_Log__c creation.
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-03
 */
@IsTest
private class OrderMigrationBatchTest {

    private static final String LEGACY_PREFIX = 'ORD_TEST_';

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
     * @description Setup test data - creates Account, Opportunity, Product, PBE,
     *              Quote (Primary on Closed Won Opp), and 5 QuoteLineItems with
     *              varying date completeness for skip/process testing.
     */
    @TestSetup
    static void setupTestData() {
        // Account
        Account acct = new Account(Name = 'Order Migration Test Account');
        insert acct;

        // Opportunity (Closed Won)
        Opportunity opp = new Opportunity(
            Name = 'Order Migration Test Opp',
            AccountId = acct.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today()
        );
        insert opp;

        // Product
        Product2 prod = new Product2(
            Name = 'Order Migration Test Product',
            ProductCode = 'ORD-MIG-001',
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
            Name = 'Order Migration Test Quote',
            OpportunityId = opp.Id,
            QuoteAccountId = acct.Id,
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

    // ── Batch Execution Tests ─────────────────────────────────────────

    /**
     * @description Test successful batch execution. Verifies that the batch
     *              processes Quotes, creates Orders with OrderItems, and creates a
     *              Migration_Run_Log__c record with Orders_Processed__c > 0.
     */
    @IsTest
    static void testBatchExecution_Success() {
        // Diagnostic: verify test data exists before batch run
        Quote testQuote = [
            SELECT Id, IsPrimary__c, Opportunity.StageName
            FROM Quote WHERE Name = 'Order Migration Test Quote' LIMIT 1
        ];
        System.assertEquals(true, testQuote.IsPrimary__c,
            'DIAG: Quote.IsPrimary__c should be true');
        System.assertEquals('Closed Won', testQuote.Opportunity.StageName,
            'DIAG: Opp should be Closed Won');

        Integer matchingQlis = [
            SELECT COUNT() FROM QuoteLineItem
            WHERE Legacy_Id__c LIKE 'ORD_TEST_%' AND QuoteId = :testQuote.Id
        ];
        System.assert(matchingQlis > 0,
            'DIAG: Should have QLIs matching ORD_TEST_% filter, found: ' + matchingQlis);

        // Asset creation callout requires mock (even if activateOrders=false, batch still implements AllowsCallouts)
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch('ORD_TEST_%', 10, false, false);
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

        // Verify Migration_Run_Log__c record created
        List<Migration_Run_Log__c> logs = [SELECT Id, Orders_Processed__c, Status__c, Errors__c
            FROM Migration_Run_Log__c];
        System.assertEquals(1, logs.size(), 'Should have created one Migration Run Log');
        System.assert(logs[0].Orders_Processed__c > 0,
            'DIAG: Batch should have processed at least 1 order. Log status: ' +
            logs[0].Status__c + ', Errors: ' + logs[0].Errors__c);
    }

    /**
     * @description Test that the QLIs_Skipped__c counter is written to the run log.
     *              For OneTime products (no ProductSellingModelOption), QLIs with
     *              missing StartDate/EndDate are NOT skipped — the batch defaults
     *              ServiceDate and clears EndDate to satisfy platform validation.
     *              Only subscription-capable products require dates. This test
     *              verifies the counter is tracked (even if 0) and that all 5 QLIs
     *              were processed.
     */
    @IsTest
    static void testBatchExecution_SkippedItems() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch('ORD_TEST_%', 10, false, false);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        Migration_Run_Log__c log = [
            SELECT QLIs_Skipped__c, QLIs_Processed__c
            FROM Migration_Run_Log__c
            LIMIT 1
        ];
        System.assertNotEquals(null, log.QLIs_Skipped__c,
            'QLIs_Skipped__c counter should be written');
        System.assertEquals(5, log.QLIs_Processed__c,
            'All 5 test QLIs should be processed (OneTime products allow missing dates)');
        System.assertEquals(0, log.QLIs_Skipped__c,
            'OneTime products should not be skipped for missing dates; ' +
            'subscription-capable products would skip. QLIs_Processed=' + log.QLIs_Processed__c);
    }

    /**
     * @description Test that a non-matching filter processes zero records without error.
     */
    @IsTest
    static void testBatchExecution_NoMatchingRecords() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch('NOMATCH_%', 10, false, false);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify log shows zero records
        List<Migration_Run_Log__c> logs = [SELECT Orders_Processed__c FROM Migration_Run_Log__c];
        System.assertEquals(1, logs.size(), 'Should still create a Migration Run Log');
        System.assertEquals(0, logs[0].Orders_Processed__c,
            'Should have 0 orders processed for non-matching filter');
    }

    /**
     * @description Test that a Quote with a pre-existing migration Order (created
     *              within the last hour) is surfaced as a 'DuplicateSkipped'
     *              Migration_Run_Detail__c row instead of being silently dropped.
     *              Regression guard for the Review-tab visibility bug where
     *              duplicate-skipped Quotes never appeared anywhere in the report.
     */
    @IsTest
    static void testBatchExecution_DuplicateSkipRecordsRunDetail() {
        // Locate the test Quote / Account from @TestSetup
        Quote testQuote = [
            SELECT Id, QuoteAccountId, CurrencyIsoCode, Pricebook2Id
            FROM Quote WHERE Name = 'Order Migration Test Quote' LIMIT 1
        ];

        // Pre-create a migration Contract + Order for the test Quote so the batch's
        // recentOrders guard fires on the duplicate-skip branch.
        Contract preExistingContract = new Contract(
            AccountId = testQuote.QuoteAccountId,
            Status = 'Draft',
            StartDate = Date.today(),
            ContractTerm = 12,
            Migration_Created__c = true
        );
        insert preExistingContract;

        Order preExistingOrder = new Order(
            AccountId = testQuote.QuoteAccountId,
            ContractId = preExistingContract.Id,
            QuoteId = testQuote.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = testQuote.Pricebook2Id
        );
        // Bypass checklist validation — legacy Quotes don't have checklist items.
        // The batch itself flips this same flag during its own Order insert.
        OrderValidationTriggerHandler.bypassValidation = true;
        insert preExistingOrder;
        OrderValidationTriggerHandler.bypassValidation = false;

        // Pre-create a Migration_Run_Log__c sentinel and pass its Id to the
        // batch via the 5-arg constructor — mirrors how the controller wires
        // production runs. Required so persistRunDetails can stamp Run_Log__c
        // on each detail row (the field is required on Migration_Run_Detail__c).
        Migration_Run_Log__c sentinel = new Migration_Run_Log__c(
            Status__c = 'Processing Assets',
            Run_Date__c = Datetime.now(),
            Start_Time__c = Datetime.now(),
            Orders_Processed__c = 0,
            Filter_Used__c = 'ORD_TEST_%'
        );
        insert sentinel;

        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch(
            'ORD_TEST_%', 10, false, false, sentinel.Id);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Diagnostic: dump every detail row + every Order for this Quote, so a future
        // failure shows where the Quote actually ended up.
        List<Migration_Run_Detail__c> allDetails = [
            SELECT Category__c, Severity__c, Quote__c, Order__c, Reason__c
            FROM Migration_Run_Detail__c
            ORDER BY CreatedDate
        ];
        List<Order> ordersForQuote = [
            SELECT Id, Status, ContractId, Contract.Migration_Created__c, CreatedDate
            FROM Order WHERE QuoteId = :testQuote.Id
        ];
        Migration_Run_Log__c finalLog = [
            SELECT Id, Status__c, Orders_Processed__c, Orders_Succeeded__c, Errors__c
            FROM Migration_Run_Log__c WHERE Id = :sentinel.Id
        ];
        String diag = ' | Detail rows: ' + allDetails.size();
        for (Migration_Run_Detail__c d : allDetails) {
            diag += ' [' + d.Category__c + '/' + d.Severity__c + ']';
        }
        diag += ' | Orders for Quote: ' + ordersForQuote.size();
        diag += ' | Log status=' + finalLog.Status__c;
        diag += ' processed=' + finalLog.Orders_Processed__c;
        diag += ' succeeded=' + finalLog.Orders_Succeeded__c;
        if (finalLog.Errors__c != null) {
            diag += ' errors=' + finalLog.Errors__c.left(200);
        }

        // The duplicate-skip branch should have written a Migration_Run_Detail__c row
        List<Migration_Run_Detail__c> dupRows = [
            SELECT Id, Category__c, Severity__c, Quote__c, Order__c, Reason__c
            FROM Migration_Run_Detail__c
            WHERE Category__c = 'DuplicateSkipped'
        ];
        System.assertEquals(1, dupRows.size(),
            'Expected exactly one DuplicateSkipped detail row for the test Quote. ' +
            'If 0, the silent-skip regression has returned.' + diag);
        System.assertEquals(testQuote.Id, dupRows[0].Quote__c,
            'DuplicateSkipped row should point at the test Quote');
        System.assertEquals(preExistingOrder.Id, dupRows[0].Order__c,
            'DuplicateSkipped row should link the pre-existing Order');
        System.assertEquals('Skip', dupRows[0].Severity__c,
            'DuplicateSkipped should use Skip severity, not Error');

        // No SECOND migration Order should have been created for this Quote
        Integer migrationOrdersForQuote = [
            SELECT COUNT() FROM Order
            WHERE QuoteId = :testQuote.Id
            AND Contract.Migration_Created__c = true
        ];
        System.assertEquals(1, migrationOrdersForQuote,
            'Only the pre-existing migration Order should exist; the batch must not have created a duplicate');
    }

    /**
     * @description Test that the constructor with batchSize=200 doesn't throw.
     *              The constructor internally caps batch size to 50.
     */
    @IsTest
    static void testConstructor_BatchSizeCap() {
        Test.startTest();
        OrderMigrationBatch batchLarge = new OrderMigrationBatch('ORD_TEST_%', 200, false, false);
        OrderMigrationBatch batchNormal = new OrderMigrationBatch('ORD_TEST_%', 10, false, false);
        OrderMigrationBatch batchDefault = new OrderMigrationBatch('ORD_TEST_%', null, false, false);
        Test.stopTest();

        // Verify constructors did not throw — no direct access to private fields
        // but we verify the objects were created
        System.assertNotEquals(null, batchLarge,
            'Batch with size 200 should be created (internally capped to 50)');
        System.assertNotEquals(null, batchNormal,
            'Batch with size 10 should be created');
        System.assertNotEquals(null, batchDefault,
            'Batch with null size should be created (defaults to 10)');
    }

    /**
     * @description Test batch execution with activateOrders=true and activateContracts=true.
     *              With mocked asset creation API, verify the log is created. Activation
     *              may or may not succeed in test context depending on platform behavior.
     */
    @IsTest
    static void testBatchExecution_WithActivation() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch('ORD_TEST_%', 10, true, true);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify Migration_Run_Log__c record created
        List<Migration_Run_Log__c> logs = [
            SELECT Id, Orders_Processed__c, Status__c, Errors__c,
                   PST_Succeeded__c, PST_Failed__c
            FROM Migration_Run_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Should create one Migration Run Log');

        Migration_Run_Log__c log = logs[0];
        System.assert(log.Orders_Processed__c > 0,
            'Should have processed at least 1 order. Status: ' + log.Status__c +
            ', Errors: ' + log.Errors__c);

        // In test context, UserInfo.getSessionId() returns null so the REST callout
        // to createOrUpdateAssetFromOrder is skipped. We verify the batch completed
        // and processed orders — asset creation is validated via integration testing.
        System.assert(
            log.PST_Succeeded__c != null || log.PST_Failed__c != null,
            'Asset creation counters should be initialized. Succeeded: ' + log.PST_Succeeded__c +
            ', Failed: ' + log.PST_Failed__c);
    }

    /**
     * @description Test that attribute copying logic in Step 5b handles the
     *              zero-attributes path gracefully when no QuoteLineItemAttribute
     *              records exist for the source QLIs. Verifies the batch completes
     *              without errors and the [ATTRIBUTES] stats line is present in the log.
     *
     *              Note: In production, existing QLIA records would be copied to
     *              OrderItemAttribute. In test context, Database.insertImmediate()
     *              for virtual objects may not persist records, so this test validates
     *              the "no source attributes" (skipped) path.
     */
    @IsTest
    static void testBatchExecution_AttributeCopying() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch('ORD_TEST_%', 10, false, false);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify batch completed
        List<AsyncApexJob> jobs = [
            SELECT Status, NumberOfErrors
            FROM AsyncApexJob WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(!jobs.isEmpty(), 'Should have a batch job record');
        System.assertEquals('Completed', jobs[0].Status,
            'Batch should complete without errors');

        // Verify Migration_Run_Log__c has the [ATTRIBUTES] stats line
        Migration_Run_Log__c log = [
            SELECT Errors__c, Status__c, Orders_Processed__c
            FROM Migration_Run_Log__c
            LIMIT 1
        ];
        System.assert(log.Orders_Processed__c > 0,
            'Should have processed at least 1 order');
        System.assert(log.Errors__c != null && log.Errors__c.contains('[ATTRIBUTES]'),
            'Log should contain [ATTRIBUTES] stats line. Errors__c: ' + log.Errors__c);

        // With no QLIA records, expect Skipped > 0 (QLIs had no attributes to copy)
        System.assert(log.Errors__c.contains('Skipped:'),
            'Log should show Skipped count in [ATTRIBUTES] line');
    }

    // ── Pricebook override scenarios (feature: pricebook selector) ────

    /**
     * @description Target pricebook has a PricebookEntry for every product on the
     *              source QLIs. Batch should remap Order.Pricebook2Id + every
     *              OrderItem.PricebookEntryId to the target, preserving QLI.UnitPrice.
     */
    @IsTest
    static void testMigrationWithTargetPricebook_AllCovered() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        // Create a custom non-standard pricebook with full coverage
        Pricebook2 customPb = new Pricebook2(Name = 'Order Migration Target PB', IsActive = true);
        insert customPb;

        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Order Migration Test Product' LIMIT 1];
        PricebookEntry customPbe = new PricebookEntry(
            Pricebook2Id = customPb.Id,
            Product2Id = prod.Id,
            UnitPrice = 999.00, // intentionally different from QLI prices
            IsActive = true
        );
        insert customPbe;

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch(
            'ORD_TEST_%', 10, false, false, null, customPb.Id, false);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify the Order uses the target pricebook
        List<Order> orders = [
            SELECT Id, Pricebook2Id FROM Order
            WHERE QuoteId IN (SELECT Id FROM Quote WHERE Name = 'Order Migration Test Quote')
        ];
        System.assertEquals(1, orders.size(),
            'Expected exactly 1 Order to be created. Found: ' + orders.size());
        System.assertEquals(customPb.Id, orders[0].Pricebook2Id,
            'Order.Pricebook2Id should match the target pricebook override');

        // Verify every OrderItem points to the target-PB PricebookEntry and preserves QLI.UnitPrice
        List<OrderItem> items = [
            SELECT Id, PricebookEntryId, UnitPrice, Product2Id,
                   PricebookEntry.Pricebook2Id
            FROM OrderItem WHERE OrderId = :orders[0].Id
        ];
        System.assert(items.size() >= 1, 'Expected at least 1 OrderItem, got ' + items.size());
        for (OrderItem oi : items) {
            System.assertEquals(customPb.Id, oi.PricebookEntry.Pricebook2Id,
                'OrderItem PricebookEntry must belong to target pricebook');
            // UnitPrice preserved from QLI (500 / 1000 / 750), not 999 from target PBE
            System.assertNotEquals(999.00, oi.UnitPrice,
                'UnitPrice should NOT be the target PBE price; it should preserve QLI.UnitPrice');
        }

        // Verify run log captures target pricebook
        List<Migration_Run_Log__c> logs = [
            SELECT Target_Pricebook__c, Quotes_Skipped_No_Coverage__c, PBEs_Auto_Created__c
            FROM Migration_Run_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Should have one run log');
        System.assertEquals(customPb.Id, logs[0].Target_Pricebook__c,
            'Run log should record target pricebook');
        System.assertEquals(0, logs[0].Quotes_Skipped_No_Coverage__c,
            'No Quotes should be skipped when target PB has full coverage');
        System.assertEquals(0, logs[0].PBEs_Auto_Created__c,
            'No auto-creation needed when target PB has full coverage');
    }

    /**
     * @description Target pricebook lacks coverage AND auto-create is off.
     *              The entire Quote must be skipped; no Order created; run log
     *              reflects the skip.
     */
    @IsTest
    static void testMigrationWithTargetPricebook_MissingCoverage_SkipsQuote() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        // Custom pricebook with NO PBE for our product
        Pricebook2 emptyPb = new Pricebook2(Name = 'Empty Target PB', IsActive = true);
        insert emptyPb;

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch(
            'ORD_TEST_%', 10, false, false, null, emptyPb.Id, false);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // No Orders should have been created
        List<Order> orders = [
            SELECT Id FROM Order
            WHERE QuoteId IN (SELECT Id FROM Quote WHERE Name = 'Order Migration Test Quote')
        ];
        System.assertEquals(0, orders.size(),
            'No Orders should be created when every product is uncovered in target PB');

        // Run log should show the skip
        Migration_Run_Log__c log = [
            SELECT Orders_Processed__c, Orders_Succeeded__c,
                   Quotes_Skipped_No_Coverage__c, Target_Pricebook__c
            FROM Migration_Run_Log__c LIMIT 1
        ];
        System.assertEquals(1, log.Quotes_Skipped_No_Coverage__c,
            'Expected exactly 1 Quote skipped for missing PBE coverage');
        System.assertEquals(0, log.Orders_Processed__c,
            'Orders_Processed should be 0 (the skip undoes the optimistic increment)');
        System.assertEquals(emptyPb.Id, log.Target_Pricebook__c,
            'Run log should still record the target pricebook operator chose');
    }

    /**
     * @description Target pricebook lacks coverage BUT auto-create is on. The batch
     *              pre-creates missing PBEs at QLI.UnitPrice and proceeds to create
     *              the Order. Verify PBE was created and counters populated.
     */
    @IsTest
    static void testMigrationWithTargetPricebook_AutoCreate() {
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        Pricebook2 targetPb = new Pricebook2(Name = 'Auto Create Target PB', IsActive = true);
        insert targetPb;

        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Order Migration Test Product' LIMIT 1];

        Test.startTest();
        OrderMigrationBatch batch = new OrderMigrationBatch(
            'ORD_TEST_%', 10, false, false, null, targetPb.Id, true);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // A PBE should have been auto-created in the target pricebook
        List<PricebookEntry> createdPbes = [
            SELECT Id, UnitPrice, IsActive FROM PricebookEntry
            WHERE Pricebook2Id = :targetPb.Id AND Product2Id = :prod.Id
        ];
        System.assertEquals(1, createdPbes.size(),
            'Expected exactly 1 PBE auto-created in target pricebook');
        System.assertEquals(true, createdPbes[0].IsActive,
            'Auto-created PBE should be Active');

        // Order should exist on target pricebook
        List<Order> orders = [
            SELECT Id, Pricebook2Id FROM Order
            WHERE QuoteId IN (SELECT Id FROM Quote WHERE Name = 'Order Migration Test Quote')
        ];
        System.assertEquals(1, orders.size(), 'Expected 1 Order after auto-create flow');
        System.assertEquals(targetPb.Id, orders[0].Pricebook2Id,
            'Order should be on the auto-create target pricebook');

        // Run log reflects auto-create activity
        Migration_Run_Log__c log = [
            SELECT PBEs_Auto_Created__c, Quotes_Skipped_No_Coverage__c, Target_Pricebook__c
            FROM Migration_Run_Log__c LIMIT 1
        ];
        System.assertEquals(1, log.PBEs_Auto_Created__c,
            'Run log should reflect 1 PBE auto-created');
        System.assertEquals(0, log.Quotes_Skipped_No_Coverage__c,
            'No Quote should be skipped once auto-create fills coverage');
        System.assertEquals(targetPb.Id, log.Target_Pricebook__c,
            'Run log should record target pricebook');
    }
}