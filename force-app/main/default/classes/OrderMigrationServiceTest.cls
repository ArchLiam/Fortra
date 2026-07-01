/**
 * Test class for OrderMigrationService.
 * Validates field calculations, default resolution, record counting,
 * gap analysis, Contract resolution/creation, asset creation API,
 * and wrapper constructors.
 *
 * @author Marc DeBrey
 * @date 2026-03-05
 */
@IsTest
private class OrderMigrationServiceTest {

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

    @TestSetup
    static void setupTestData() {
        // Account
        Account testAccount = new Account(
            Name = 'Order Migration Test Account',
            BillingCountry = 'United States',
            BillingState = 'California'
        );
        insert testAccount;

        // Opportunity (Closed Won)
        Opportunity testOpp = new Opportunity(
            Name = 'Order Migration Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today()
        );
        insert testOpp;

        // Product
        Product2 testProduct = new Product2(
            Name = 'Order Migration Test Product',
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
            Name = 'Order Migration Test Quote',
            OpportunityId = testOpp.Id,
            QuoteAccountId = testAccount.Id,
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

    // ── calculateOrderItemFields Tests ────────────────────────────────

    @IsTest
    static void testCalculateOrderItemFields_12Months() {
        OrderItem oi = new OrderItem(
            ServiceDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 12, 31),
            UnitPrice = 500
        );

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();

        Test.startTest();
        OrderMigrationService.calculateOrderItemFields(oi, defaults);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 1, 1), oi.ServiceDate,
            'ServiceDate should equal StartDate');
        System.assertEquals(12, oi.SubscriptionTerm,
            'SubscriptionTerm should be 12 months for Jan 1 2026 to Dec 31 2026');
    }

    @IsTest
    static void testCalculateOrderItemFields_24Months() {
        OrderItem oi = new OrderItem(
            ServiceDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2027, 12, 31),
            UnitPrice = 1000
        );

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();

        Test.startTest();
        OrderMigrationService.calculateOrderItemFields(oi, defaults);
        Test.stopTest();

        System.assertEquals(24, oi.SubscriptionTerm,
            'SubscriptionTerm should be 24 months for Jan 1 2026 to Dec 31 2027');
    }

    @IsTest
    static void testCalculateOrderItemFields_PeriodBoundary_Anniversary() {
        // When PeriodBoundary = "Anniversary", neither PeriodBoundaryDay nor
        // PeriodBoundaryStartMonth should be set. The platform uses ServiceDate
        // as the billing anchor for Anniversary mode.
        OrderItem oi = new OrderItem(
            ServiceDate = Date.newInstance(2025, 9, 15),
            EndDate = Date.newInstance(2026, 9, 14),
            UnitPrice = 1200
        );

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();
        defaults.oiStringDefaults.put('PeriodBoundary', 'Anniversary');

        Test.startTest();
        OrderMigrationService.calculateOrderItemFields(oi, defaults);
        Test.stopTest();

        System.assertEquals(null, oi.PeriodBoundaryDay,
            'PeriodBoundaryDay must be null when PeriodBoundary is Anniversary');
        System.assertEquals(null, oi.PeriodBoundaryStartMonth,
            'PeriodBoundaryStartMonth must be null when PeriodBoundary is Anniversary');
        System.assertEquals('Anniversary', (String) oi.get('PeriodBoundary'),
            'PeriodBoundary should be Anniversary from CMT default');
        System.assertEquals(Date.newInstance(2025, 9, 15), oi.ServiceDate,
            'ServiceDate should be set from constructor');
    }

    @IsTest
    static void testCalculateOrderItemFields_PeriodBoundary_DayOfPeriod() {
        // When PeriodBoundary = "DayOfPeriod", both PeriodBoundaryDay and
        // PeriodBoundaryStartMonth are set from the StartDate.
        OrderItem oi = new OrderItem(
            ServiceDate = Date.newInstance(2025, 9, 15),
            EndDate = Date.newInstance(2026, 9, 14),
            UnitPrice = 1200
        );

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();
        defaults.oiStringDefaults.put('PeriodBoundary', 'DayOfPeriod');

        Test.startTest();
        OrderMigrationService.calculateOrderItemFields(oi, defaults);
        Test.stopTest();

        System.assertEquals(15, oi.PeriodBoundaryDay,
            'PeriodBoundaryDay should be 15 (day of Sept 15 ServiceDate)');
        System.assertEquals('9', oi.PeriodBoundaryStartMonth,
            'PeriodBoundaryStartMonth should be 9 (September) for DayOfPeriod');
        System.assertEquals('DayOfPeriod', (String) oi.get('PeriodBoundary'),
            'PeriodBoundary should be DayOfPeriod from CMT default');
    }

    @IsTest
    static void testCalculateOrderItemFields_PreservesExistingValues() {
        OrderItem oi = new OrderItem(
            ServiceDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2028, 12, 31),
            UnitPrice = 1500,
            SubscriptionTerm = 36
        );
        oi.put('BillingFrequency2', 'Monthly');

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();
        defaults.oiStringDefaults.put('BillingFrequency2', 'Annual');

        Test.startTest();
        OrderMigrationService.calculateOrderItemFields(oi, defaults);
        Test.stopTest();

        System.assertEquals(36, oi.SubscriptionTerm,
            'SubscriptionTerm should not be overwritten when already set');
        System.assertEquals('Monthly', (String) oi.get('BillingFrequency2'),
            'BillingFrequency2 should not be overwritten when already set');
    }

    // ── applyOrderDefaults Tests ────────────────────────────────────────

    @IsTest
    static void testApplyOrderDefaults_FillsNullFields() {
        Order ord = new Order();

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();
        defaults.orderStringDefaults.put('Description', 'Migration Default');

        Test.startTest();
        OrderMigrationService.applyOrderDefaults(ord, defaults);
        Test.stopTest();

        System.assertEquals('Migration Default', (String) ord.get('Description'),
            'Description should be filled from CMT string default');
    }

    @IsTest
    static void testApplyOrderDefaults_PreservesExistingValues() {
        Order ord = new Order(Description = 'Existing Value');

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();
        defaults.orderStringDefaults.put('Description', 'Should Not Overwrite');

        Test.startTest();
        OrderMigrationService.applyOrderDefaults(ord, defaults);
        Test.stopTest();

        System.assertEquals('Existing Value', ord.Description,
            'Description should not be overwritten when already set');
    }

    @IsTest
    static void testApplyOrderDefaults_NullDefaults() {
        Order ord = new Order();

        Test.startTest();
        OrderMigrationService.applyOrderDefaults(ord, null);
        Test.stopTest();

        // Should not throw — just a no-op
        System.assertNotEquals(null, ord, 'Order should still exist after null defaults');
    }

    // ── resolveDefaults Test ──────────────────────────────────────────

    @IsTest
    static void testResolveDefaults() {
        Test.startTest();
        OrderMigrationService.ResolvedDefaults defaults =
            OrderMigrationService.resolveDefaults();
        Test.stopTest();

        // Defaults object should always be returned (may be empty in test context
        // since CMT records may not be available in @IsTest without SeeAllData)
        System.assertNotEquals(null, defaults,
            'resolveDefaults should return a non-null object');
        System.assertNotEquals(null, defaults.oiStringDefaults,
            'oiStringDefaults map should be initialized');
        System.assertNotEquals(null, defaults.oiIdDefaults,
            'oiIdDefaults map should be initialized');
        System.assertNotEquals(null, defaults.orderStringDefaults,
            'orderStringDefaults map should be initialized');
        System.assertNotEquals(null, defaults.orderIdDefaults,
            'orderIdDefaults map should be initialized');
    }

    // ── getRecordCounts Test ──────────────────────────────────────────

    @IsTest
    static void testGetRecordCounts() {
        Test.startTest();
        OrderMigrationService.OrderMigrationPreview preview =
            OrderMigrationService.getRecordCounts('ORD_TEST_%');
        Test.stopTest();

        System.assertEquals(3, preview.orderItemCount,
            'Should find 3 QLIs matching the filter');
        System.assertEquals(1, preview.quoteCount,
            'Should find 1 Quote containing matching QLIs');
        System.assertEquals(1, preview.itemsMissingDates,
            'Should find 1 QLI with missing start/end dates');
    }

    @IsTest
    static void testGetRecordCounts_SoqlMode() {
        // SOQL mode: user provides a full SELECT FROM Quote query; tool collects
        // matching Quote IDs and counts their QLIs + items missing dates.
        String userSoql = 'SELECT Id FROM Quote WHERE Name = \'Order Migration Test Quote\'';

        Test.startTest();
        OrderMigrationService.OrderMigrationPreview preview =
            OrderMigrationService.getRecordCounts(userSoql);
        Test.stopTest();

        System.assertEquals(1, preview.quoteCount,
            'SOQL mode should find the single matching Quote');
        System.assertEquals(3, preview.orderItemCount,
            'Should count all 3 QLIs under the matched Quote');
        System.assertEquals(1, preview.itemsMissingDates,
            'Should find 1 QLI with null StartDate/EndDate');
    }

    @IsTest
    static void testGetRecordCounts_QnumMode() {
        // QNUM mode: filter is "QNUM:" + comma-separated QuoteNumbers.
        Quote q = [SELECT QuoteNumber FROM Quote
                   WHERE Name = 'Order Migration Test Quote' LIMIT 1];
        String filterClause = 'QNUM:' + q.QuoteNumber;

        Test.startTest();
        OrderMigrationService.OrderMigrationPreview preview =
            OrderMigrationService.getRecordCounts(filterClause);
        Test.stopTest();

        System.assertEquals(1, preview.quoteCount,
            'QNUM mode should find the Quote by number');
        System.assertEquals(3, preview.orderItemCount,
            'Should count 3 QLIs under the matched Quote');
        System.assertEquals(1, preview.itemsMissingDates,
            'Should find 1 QLI with null StartDate/EndDate');
    }

    // ── getFieldGapAnalysis Test ──────────────────────────────────────

    @IsTest
    static void testGetFieldGapAnalysis() {
        Test.startTest();
        List<OrderMigrationService.FieldGapInfo> gaps =
            OrderMigrationService.getFieldGapAnalysis('ORD_TEST_%');
        Test.stopTest();

        System.assert(!gaps.isEmpty(),
            'Should return at least one FieldGapInfo entry');

        // Find the ServiceDate gap entry
        OrderMigrationService.FieldGapInfo serviceDateGap = null;
        for (OrderMigrationService.FieldGapInfo gap : gaps) {
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

    @IsTest
    static void testGetFieldGapAnalysis_SoqlMode() {
        String userSoql = 'SELECT Id FROM Quote WHERE Name = \'Order Migration Test Quote\'';

        Test.startTest();
        List<OrderMigrationService.FieldGapInfo> gaps =
            OrderMigrationService.getFieldGapAnalysis(userSoql);
        Test.stopTest();

        System.assert(!gaps.isEmpty(),
            'SOQL mode should return field gap entries');
        OrderMigrationService.FieldGapInfo serviceDateGap = null;
        for (OrderMigrationService.FieldGapInfo g : gaps) {
            if (g.fieldName == 'ServiceDate') {
                serviceDateGap = g;
                break;
            }
        }
        System.assertNotEquals(null, serviceDateGap,
            'SOQL mode gap analysis should include ServiceDate');
        System.assertEquals(3, serviceDateGap.totalCount,
            'ServiceDate total count should be 3 (all QLIs under matched Quote)');
    }

    @IsTest
    static void testGetFieldGapAnalysis_QnumMode() {
        Quote q = [SELECT QuoteNumber FROM Quote
                   WHERE Name = 'Order Migration Test Quote' LIMIT 1];
        String filterClause = 'QNUM:' + q.QuoteNumber;

        Test.startTest();
        List<OrderMigrationService.FieldGapInfo> gaps =
            OrderMigrationService.getFieldGapAnalysis(filterClause);
        Test.stopTest();

        System.assert(!gaps.isEmpty(),
            'QNUM mode should return field gap entries');
        OrderMigrationService.FieldGapInfo sttGap = null;
        for (OrderMigrationService.FieldGapInfo g : gaps) {
            if (g.fieldName == 'SalesTransactionTypeId') {
                sttGap = g;
                break;
            }
        }
        System.assertNotEquals(null, sttGap,
            'QNUM mode gap analysis should include SalesTransactionTypeId');
    }

    // ── injectSafetyGuards Tests ──────────────────────────────────────

    @IsTest
    static void testInjectSafetyGuards_AcceptsFromQuote() {
        Test.startTest();
        String guarded = OrderMigrationService.injectSafetyGuards(
            'SELECT Id FROM Quote WHERE Legacy_Id__c LIKE \'GS%\'');
        Test.stopTest();

        System.assert(guarded.contains('IsPrimary__c = true'),
            'Guarded SOQL should have IsPrimary__c guard appended');
        System.assert(guarded.contains('Opportunity.StageName = \'Closed Won\''),
            'Guarded SOQL should have StageName guard appended');
    }

    @IsTest
    static void testInjectSafetyGuards_AdmitsLegacyRenewalQuotes() {
        // Legacy renewal quotes have no Opportunity and IsPrimary__c=false; the
        // guard must admit them alongside the standard primary/Closed-Won set.
        Test.startTest();
        String guarded = OrderMigrationService.injectSafetyGuards(
            'SELECT Id FROM Quote WHERE Legacy_Id__c LIKE \'DY%\'');
        Test.stopTest();

        System.assert(guarded.contains('LegacyRenewalQuote__c = true'),
            'Guarded SOQL should include OR LegacyRenewalQuote__c = true so legacy renewal Quotes are not filtered out');
    }

    @IsTest
    static void testInjectSafetyGuards_RejectsFromQuoteLineItem() {
        // Regression: String.contains('FROM QUOTE') returned true for
        // "FROM QUOTELINEITEM", letting Quote-specific guards slip into a
        // QuoteLineItem query and producing a cryptic "Didn't understand
        // relationship 'Opportunity'" error instead of a clear rejection.
        String badSoql = 'SELECT QuoteId FROM QuoteLineItem WHERE EndDate > TODAY';

        Boolean threw = false;
        String message = null;
        Test.startTest();
        try {
            OrderMigrationService.injectSafetyGuards(badSoql);
        } catch (AuraHandledException e) {
            threw = true;
            message = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'injectSafetyGuards should reject FROM QuoteLineItem');
        System.assert(message != null && message.contains('FROM Quote'),
            'Error message should reference FROM Quote, got: ' + message);
    }

    @IsTest
    static void testInjectSafetyGuards_AcceptsSemiJoinSubquery() {
        // Outer FROM is Quote, inner subquery is on QuoteLineItem.
        // This is the recommended pattern for filtering Quotes by QLI-level criteria.
        Test.startTest();
        String guarded = OrderMigrationService.injectSafetyGuards(
            'SELECT Id FROM Quote WHERE Id IN (SELECT QuoteId FROM QuoteLineItem WHERE EndDate > TODAY)');
        Test.stopTest();

        System.assert(guarded.contains('IsPrimary__c = true'),
            'Semi-join query should still get guards appended');
    }

    @IsTest
    static void testInjectSafetyGuards_RejectsInvertedSubquery() {
        // Outer FROM is QuoteLineItem; inner subquery is on Quote.
        // Guards target outer FROM, so this must be rejected even though
        // "FROM Quote" appears somewhere in the string.
        String badSoql =
            'SELECT QuoteId FROM QuoteLineItem WHERE Id IN (SELECT Id FROM Quote WHERE IsPrimary__c = true)';

        Boolean threw = false;
        Test.startTest();
        try {
            OrderMigrationService.injectSafetyGuards(badSoql);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'Outer FROM QuoteLineItem must be rejected even when an inner subquery is FROM Quote');
    }

    @IsTest
    static void testInjectSafetyGuards_RejectsNonQuoteObject() {
        String badSoql = 'SELECT Id FROM Account WHERE Name = \'Test\'';

        Boolean threw = false;
        Test.startTest();
        try {
            OrderMigrationService.injectSafetyGuards(badSoql);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'injectSafetyGuards should reject FROM Account');
    }

    @IsTest
    static void testInjectSafetyGuards_NormalizesNbsp() {
        // Non-breaking spaces (U+00A0) can sneak in from textarea paste and
        // break whitespace-sensitive parsing. The normalizer should convert
        // them before the FROM-Quote check runs.
        String userSoql = 'SELECT Id FROM Quote WHERE Legacy_Id__c LIKE \'X%\'';

        Test.startTest();
        String guarded = OrderMigrationService.injectSafetyGuards(userSoql);
        Test.stopTest();

        System.assert(guarded.contains('IsPrimary__c = true'),
            'NBSP-separated SOQL should still pass validation and get guards');
    }

    @IsTest
    static void testInjectSafetyGuards_NormalizesLessGreaterOperator() {
        // Database.query() doesn't support <> — tool must rewrite to !=.
        String userSoql = 'SELECT Id FROM Quote WHERE Legacy_Id__c <> null';

        Test.startTest();
        String guarded = OrderMigrationService.injectSafetyGuards(userSoql);
        Test.stopTest();

        System.assertEquals(false, guarded.contains('<>'),
            '<> operator should be removed from guarded SOQL');
        System.assertEquals(true, guarded.contains('!='),
            '!= operator should be present after <> normalization');
    }

    @IsTest
    static void testInjectSafetyGuards_InsertsGuardsBeforeOrderBy() {
        // Guards must be positioned before ORDER BY / LIMIT, not after.
        String userSoql =
            'SELECT Id FROM Quote WHERE Id != null ORDER BY CreatedDate DESC LIMIT 10';

        Test.startTest();
        String guarded = OrderMigrationService.injectSafetyGuards(userSoql);
        Test.stopTest();

        Integer guardPos = guarded.indexOf('IsPrimary__c');
        Integer orderByPos = guarded.indexOf('ORDER BY');
        System.assert(guardPos < orderByPos,
            'Guards must be injected before ORDER BY (guards@' + guardPos +
            ', ORDER BY@' + orderByPos + ')');
        System.assert(guarded.contains('LIMIT 10'),
            'Existing LIMIT should be preserved');
    }

    @IsTest
    static void testInjectSafetyGuards_TrimsTrailingSemicolon() {
        String userSoql = 'SELECT Id FROM Quote WHERE Legacy_Id__c = \'X\';';

        Test.startTest();
        String guarded = OrderMigrationService.injectSafetyGuards(userSoql);
        Test.stopTest();

        System.assertEquals(false, guarded.endsWith(';'),
            'Trailing semicolon should be stripped before DML query');
        System.assert(guarded.contains('IsPrimary__c = true'),
            'Guards should still be injected after semicolon removal');
    }

    @IsTest
    static void testInjectSafetyGuards_RejectsBlankInput() {
        Boolean threw = false;
        Test.startTest();
        try {
            OrderMigrationService.injectSafetyGuards('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw,
            'Blank input should throw AuraHandledException');
    }

    // ── executeSoqlPreview Tests ──────────────────────────────────────

    @IsTest
    static void testExecuteSoqlPreview() {
        String userSoql = 'SELECT Id, Name FROM Quote WHERE Name = \'Order Migration Test Quote\'';

        Test.startTest();
        List<Map<String, Object>> results =
            OrderMigrationService.executeSoqlPreview(userSoql);
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Preview should return the single matching Quote row');
        System.assertEquals('Order Migration Test Quote',
            (String) results[0].get('Name'),
            'Name field should be populated in the preview row');
    }

    @IsTest
    static void testExecuteSoqlPreview_KeepsExistingLimit() {
        // When the user supplies their own LIMIT, the preview must not append LIMIT 200.
        // The guards get injected before LIMIT, so " LIMIT " is present and the
        // append-check short-circuits.
        String userSoql = 'SELECT Id FROM Quote LIMIT 1';

        Test.startTest();
        List<Map<String, Object>> results =
            OrderMigrationService.executeSoqlPreview(userSoql);
        Test.stopTest();

        System.assert(results != null, 'Preview should return non-null results');
        System.assert(results.size() <= 1,
            'Existing LIMIT 1 should be preserved (no appended LIMIT 200)');
    }

    // ── isSoqlMode Tests ──────────────────────────────────────────────

    @IsTest
    static void testIsSoqlMode() {
        System.assertEquals(true,
            OrderMigrationService.isSoqlMode('SELECT Id FROM Quote'),
            'Uppercase SELECT should be detected as SOQL mode');
        System.assertEquals(true,
            OrderMigrationService.isSoqlMode('  select id from quote  '),
            'Whitespace + lowercase SELECT should still be SOQL mode');
        System.assertEquals(false,
            OrderMigrationService.isSoqlMode('ORD_TEST_%'),
            'LIKE pattern filter is not SOQL mode');
        System.assertEquals(false,
            OrderMigrationService.isSoqlMode('QNUM:Q-00001'),
            'QNUM prefix filter is not SOQL mode');
        System.assertEquals(false,
            OrderMigrationService.isSoqlMode(null),
            'Null filter is not SOQL mode');
        System.assertEquals(false,
            OrderMigrationService.isSoqlMode(''),
            'Empty filter is not SOQL mode');
    }

    // ── applyQuoteDefaults Tests ──────────────────────────────────────

    @IsTest
    static void testApplyQuoteDefaults_FillsNullFields() {
        Quote q = new Quote();

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();
        defaults.quoteStringDefaults.put('Email', 'test@example.com');

        Test.startTest();
        Boolean changed = OrderMigrationService.applyQuoteDefaults(q, defaults);
        Test.stopTest();

        System.assertEquals(true, changed,
            'Should return true when a null field was filled');
        System.assertEquals('test@example.com', (String) q.get('Email'),
            'Email should be filled from Quote string default');
    }

    @IsTest
    static void testApplyQuoteDefaults_PreservesExistingValues() {
        Quote q = new Quote(Email = 'existing@example.com');

        OrderMigrationService.ResolvedDefaults defaults =
            new OrderMigrationService.ResolvedDefaults();
        defaults.quoteStringDefaults.put('Email', 'should-not-overwrite@example.com');

        Test.startTest();
        Boolean changed = OrderMigrationService.applyQuoteDefaults(q, defaults);
        Test.stopTest();

        System.assertEquals(false, changed,
            'Should return false when no null fields to fill');
        System.assertEquals('existing@example.com', q.Email,
            'Existing Email should not be overwritten');
    }

    @IsTest
    static void testApplyQuoteDefaults_NullDefaults() {
        Quote q = new Quote();

        Test.startTest();
        Boolean changed = OrderMigrationService.applyQuoteDefaults(q, null);
        Test.stopTest();

        System.assertEquals(false, changed,
            'Null defaults should return false without error');
    }

    // ── resolveOrCreateContract Tests ─────────────────────────────────

    @IsTest
    static void testResolveOrCreateContract_Creates() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Order Migration Test Account' LIMIT 1];

        Test.startTest();
        // Pass additional Contract fields to verify they are applied
        Map<String, Object> contractFields = new Map<String, Object>{
            'Name' => 'Test Migration Contract',
            'BillingStreet' => '123 Main St',
            'BillingCity' => 'Austin'
        };
        OrderMigrationService.ContractResult result =
            OrderMigrationService.resolveOrCreateContract(acct.Id, Date.today(), contractFields, false);
        Test.stopTest();

        System.assertNotEquals(null, result.contractId,
            'Contract Id should not be null when creating new contract');
        System.assertEquals(true, result.wasCreated,
            'wasCreated should be true for a new contract');
        System.assertEquals(null, result.errorMessage,
            'errorMessage should be null on success');

        // Verify Contract was actually inserted with additional fields
        Contract c = [SELECT Id, AccountId, Migration_Created__c, Name, BillingStreet, BillingCity
                      FROM Contract WHERE Id = :result.contractId];
        System.assertEquals(acct.Id, c.AccountId,
            'Contract should be linked to the correct Account');
        System.assertEquals(true, c.Migration_Created__c,
            'Contract should have Migration_Created__c = true');
        System.assertEquals('Test Migration Contract', c.Name,
            'Contract Name should be set from additional fields');
        System.assertEquals('123 Main St', c.BillingStreet,
            'BillingStreet should be set from additional fields');
    }

    @IsTest
    static void testResolveOrCreateContract_Reuses() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Order Migration Test Account' LIMIT 1];

        // Pre-create a migration-created Contract with a Legacy_Id__c
        Contract existing = new Contract(
            AccountId = acct.Id,
            ContractTerm = 12,
            StartDate = Date.today(),
            Status = 'Draft',
            Migration_Created__c = true,
            Legacy_Id__c = 'TEST_LEGACY_REUSE_001'
        );
        insert existing;

        Map<String, Object> contractFields = new Map<String, Object>{
            'Legacy_Id__c' => 'TEST_LEGACY_REUSE_001'
        };

        Test.startTest();
        OrderMigrationService.ContractResult result =
            OrderMigrationService.resolveOrCreateContract(acct.Id, Date.today(), contractFields, false);
        Test.stopTest();

        System.assertEquals(existing.Id, result.contractId,
            'Should reuse the existing migration-created Contract by Legacy_Id__c');
        System.assertEquals(false, result.wasCreated,
            'wasCreated should be false when reusing existing contract');
        System.assertEquals(null, result.errorMessage,
            'errorMessage should be null on success');
    }

    @IsTest
    static void testResolveOrCreateContract_DifferentLegacyIdInsertsNew() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Order Migration Test Account' LIMIT 1];

        // Pre-create a migration-created Contract with one Legacy_Id__c
        Contract existing = new Contract(
            AccountId = acct.Id,
            ContractTerm = 12,
            StartDate = Date.today(),
            Status = 'Draft',
            Migration_Created__c = true,
            Legacy_Id__c = 'TEST_LEGACY_DIFF_A'
        );
        insert existing;

        // Caller passes a DIFFERENT Legacy_Id__c — lookup must miss, insert new
        Map<String, Object> contractFields = new Map<String, Object>{
            'Legacy_Id__c' => 'TEST_LEGACY_DIFF_B'
        };

        Test.startTest();
        OrderMigrationService.ContractResult result =
            OrderMigrationService.resolveOrCreateContract(acct.Id, Date.today(), contractFields, false);
        Test.stopTest();

        System.assertNotEquals(existing.Id, result.contractId,
            'Different Legacy_Id__c must not reuse the pre-existing Contract');
        System.assertEquals(true, result.wasCreated,
            'wasCreated should be true when inserting a new Contract');

        Contract inserted = [SELECT Legacy_Id__c FROM Contract WHERE Id = :result.contractId];
        System.assertEquals('TEST_LEGACY_DIFF_B', inserted.Legacy_Id__c,
            'New Contract should carry the Legacy_Id__c from contractFields');
    }

    @IsTest
    static void testResolveOrCreateContract_AccountMismatch() {
        // Account A holds the pre-existing Contract; Account B is the Quote's
        // current QuoteAccountId. Mismatch should produce accountMismatch=true
        // and a null contractId so the caller routes to ContractAccountMismatch.
        Account acctA = [SELECT Id FROM Account WHERE Name = 'Order Migration Test Account' LIMIT 1];
        Account acctB = new Account(Name = 'Order Migration Test Account B');
        insert acctB;

        Contract existing = new Contract(
            AccountId = acctA.Id,
            ContractTerm = 12,
            StartDate = Date.today(),
            Status = 'Draft',
            Migration_Created__c = true,
            Legacy_Id__c = 'TEST_LEGACY_MISMATCH_001'
        );
        insert existing;

        Map<String, Object> contractFields = new Map<String, Object>{
            'Legacy_Id__c' => 'TEST_LEGACY_MISMATCH_001'
        };

        Test.startTest();
        OrderMigrationService.ContractResult result =
            OrderMigrationService.resolveOrCreateContract(acctB.Id, Date.today(), contractFields, false);
        Test.stopTest();

        System.assertEquals(null, result.contractId,
            'contractId must be null when an existing Contract exists with a different Account');
        System.assertEquals(true, result.accountMismatch,
            'accountMismatch flag must be true so caller can route to ContractAccountMismatch category');
        System.assertNotEquals(null, result.errorMessage,
            'errorMessage must describe the mismatch');
        System.assert(result.errorMessage.contains(String.valueOf(existing.Id)),
            'errorMessage should reference the conflicting Contract Id');
    }

    // ── Wrapper Constructor Tests ─────────────────────────────────────

    @IsTest
    static void testAssetCreationResult_Constructor() {
        OrderMigrationService.AssetCreationResult successResult =
            new OrderMigrationService.AssetCreationResult(true, null, '{"isSuccess": true}');

        System.assertEquals(true, successResult.isSuccess, 'isSuccess should be true');
        System.assertEquals(null, successResult.errorMessage, 'errorMessage should be null');
        System.assertEquals('{"isSuccess": true}', successResult.responseBody,
            'responseBody should match');

        OrderMigrationService.AssetCreationResult failResult =
            new OrderMigrationService.AssetCreationResult(false, 'Asset creation error', null);

        System.assertEquals(false, failResult.isSuccess, 'isSuccess should be false');
        System.assertEquals('Asset creation error', failResult.errorMessage, 'errorMessage should match');
        System.assertEquals(null, failResult.responseBody, 'responseBody should be null');
    }

    @IsTest
    static void testContractResult_Constructor() {
        Id fakeId = '800000000000001';

        OrderMigrationService.ContractResult successResult =
            new OrderMigrationService.ContractResult(fakeId, true, null);

        System.assertEquals(fakeId, successResult.contractId, 'contractId should match');
        System.assertEquals(true, successResult.wasCreated, 'wasCreated should be true');
        System.assertEquals(null, successResult.errorMessage, 'errorMessage should be null');

        OrderMigrationService.ContractResult failResult =
            new OrderMigrationService.ContractResult(null, false, 'Test error');

        System.assertEquals(null, failResult.contractId, 'contractId should be null');
        System.assertEquals(false, failResult.wasCreated, 'wasCreated should be false');
        System.assertEquals('Test error', failResult.errorMessage, 'errorMessage should match');
    }

    // ── invokeCreateAssetsFromOrder Test ──────────────────────────────

    @IsTest
    static void testInvokeCreateAssetsFromOrder_MockCallout() {
        // createOrUpdateAssetFromOrder makes an HTTP callout that requires mocking.
        Test.setMock(HttpCalloutMock.class, new MockAssetCreationResponse());

        // Create a real Order for the API call
        Account acct = [SELECT Id FROM Account WHERE Name = 'Order Migration Test Account' LIMIT 1];
        Order ord = new Order(
            AccountId = acct.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        Test.startTest();
        OrderMigrationService.AssetCreationResult result =
            OrderMigrationService.invokeCreateAssetsFromOrder(ord.Id);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess,
            'Asset creation should succeed with mocked 200 response');
        System.assertEquals(null, result.errorMessage,
            'errorMessage should be null on success');
        System.assertNotEquals(null, result.responseBody,
            'responseBody should not be null');
    }

    // ── createAssetContractRelationships Tests ──────────────────────

    @IsTest
    static void testCreateAssetContractRelationships_NoMatchingAssets() {
        // When the Account has no lifecycle-managed Assets, should return 0.
        Account acct = [SELECT Id FROM Account WHERE Name = 'Order Migration Test Account' LIMIT 1];

        Contract c = new Contract(
            AccountId = acct.Id,
            ContractTerm = 12,
            StartDate = Date.today(),
            Status = 'Draft',
            Migration_Created__c = true
        );
        insert c;

        Map<Id, Id> accountToContractMap = new Map<Id, Id>{
            acct.Id => c.Id
        };

        Test.startTest();
        Integer created = OrderMigrationService.createAssetContractRelationships(accountToContractMap);
        Test.stopTest();

        System.assertEquals(0, created,
            'Should return 0 when no lifecycle-managed Assets exist on Account');
    }

    @IsTest
    static void testCreateAssetContractRelationships_EmptyMap() {
        Test.startTest();
        Integer created = OrderMigrationService.createAssetContractRelationships(
            new Map<Id, Id>());
        Test.stopTest();

        System.assertEquals(0, created,
            'Should return 0 for empty map');
    }

    @IsTest
    static void testCreateAssetContractRelationships_NullMap() {
        Test.startTest();
        Integer created = OrderMigrationService.createAssetContractRelationships(null);
        Test.stopTest();

        System.assertEquals(0, created,
            'Should return 0 for null map');
    }

    // ── Pricebook helpers & preset CRUD (feature: pricebook selector) ──

    @IsTest
    static void testGetAvailablePricebooks_ReturnsInsertedPricebook() {
        // Note: In test context, SOQL against Pricebook2 does NOT return the Standard
        // Pricebook (it is accessible by Id via Test.getStandardPricebookId() but is
        // excluded from general queries). So we verify the list includes a custom PB
        // we insert ourselves.
        Pricebook2 customPb = new Pricebook2(Name = 'Available PBs Test', IsActive = true);
        insert customPb;

        Test.startTest();
        List<Pricebook2> pbs = OrderMigrationService.getAvailablePricebooks();
        Test.stopTest();

        Boolean foundCustom = false;
        for (Pricebook2 pb : pbs) {
            if (pb.Id == customPb.Id) { foundCustom = true; break; }
        }
        System.assertEquals(true, foundCustom,
            'Custom pricebook inserted in test should appear in the list');
    }

    @IsTest
    static void testBuildPbeRemapForScope_CoversAndMisses() {
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Order Migration Test Product' LIMIT 1];
        Pricebook2 customPb = new Pricebook2(Name = 'Remap Test PB', IsActive = true);
        insert customPb;
        PricebookEntry coveredPbe = new PricebookEntry(
            Pricebook2Id = customPb.Id, Product2Id = prod.Id,
            UnitPrice = 42.00, IsActive = true
        );
        insert coveredPbe;

        // Uncovered product: create a fresh Product with only a Standard PBE
        Product2 otherProd = new Product2(
            Name = 'Uncovered Product', IsActive = true, QuantityUnitOfMeasure = 'Each'
        );
        insert otherProd;
        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = otherProd.Id, UnitPrice = 10, IsActive = true
        );

        Set<Id> scope = new Set<Id>{ prod.Id, otherProd.Id };

        Test.startTest();
        Map<Id, PricebookEntry> remap =
            OrderMigrationService.buildPbeRemapForScope(
                scope, customPb.Id, UserInfo.getDefaultCurrency());
        Test.stopTest();

        System.assertEquals(1, remap.size(), 'Remap should contain only the covered product');
        System.assert(remap.containsKey(prod.Id), 'Covered product should be in remap');
        System.assert(!remap.containsKey(otherProd.Id), 'Uncovered product should be absent');
    }

    @IsTest
    static void testAnalyzeCoverage_FullAndPartial() {
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Order Migration Test Product' LIMIT 1];
        Pricebook2 fullPb = new Pricebook2(Name = 'Full Coverage PB', IsActive = true);
        insert fullPb;
        insert new PricebookEntry(
            Pricebook2Id = fullPb.Id, Product2Id = prod.Id,
            UnitPrice = 111, IsActive = true
        );

        Pricebook2 emptyPb = new Pricebook2(Name = 'Zero Coverage PB', IsActive = true);
        insert emptyPb;

        Test.startTest();
        OrderMigrationService.CoverageAnalysis fullAnalysis =
            OrderMigrationService.analyzeCoverage(LEGACY_PREFIX + '%', fullPb.Id);
        OrderMigrationService.CoverageAnalysis emptyAnalysis =
            OrderMigrationService.analyzeCoverage(LEGACY_PREFIX + '%', emptyPb.Id);
        Test.stopTest();

        System.assertEquals(1, fullAnalysis.totalQuotes, 'One test Quote in scope');
        System.assertEquals(0, fullAnalysis.skippedQuotes,
            'Full coverage PB should not skip any Quote');
        System.assertEquals(1, fullAnalysis.coveredQuotes,
            'Full coverage PB should fully cover the Quote');
        System.assertEquals(1, fullAnalysis.rows.size(),
            'Expected 1 product coverage row');
        System.assertEquals(true, fullAnalysis.rows[0].hasEntryInTarget,
            'Product should show covered in fullPb');

        System.assertEquals(1, emptyAnalysis.totalQuotes, 'One Quote in scope');
        System.assertEquals(1, emptyAnalysis.skippedQuotes,
            'Empty target PB should mark the Quote as skipped');
        System.assertEquals(false, emptyAnalysis.rows[0].hasEntryInTarget,
            'Product should show uncovered in emptyPb');
    }

    @IsTest
    static void testAnalyzeCoverage_NullTargetReturnsEmpty() {
        Test.startTest();
        OrderMigrationService.CoverageAnalysis a =
            OrderMigrationService.analyzeCoverage(LEGACY_PREFIX + '%', null);
        Test.stopTest();

        System.assertEquals(0, a.totalQuotes,
            'Null target should produce empty analysis');
        System.assertEquals(0, a.rows.size(),
            'Null target should produce empty rows');
    }

    @IsTest
    static void testAutoCreateMissingPbes_CreatesAtSeedPrice() {
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Order Migration Test Product' LIMIT 1];
        Pricebook2 targetPb = new Pricebook2(Name = 'Auto Create Svc PB', IsActive = true);
        insert targetPb;

        List<OrderMigrationService.PbeAutoCreateRequest> reqs =
            new List<OrderMigrationService.PbeAutoCreateRequest>{
                new OrderMigrationService.PbeAutoCreateRequest(
                    prod.Id, UserInfo.getDefaultCurrency(), 77.77)
            };

        Test.startTest();
        OrderMigrationService.AutoCreateResult res =
            OrderMigrationService.autoCreateMissingPbes(reqs, targetPb.Id);
        Test.stopTest();

        System.assertEquals(1, res.created,
            'Should auto-create one PBE for the covered product');
        System.assertEquals(1, res.createdPbeIds.size(),
            'createdPbeIds should have 1 entry');
        System.assertEquals(0, res.errors.size(),
            'No errors expected for a product with a Standard PBE');

        PricebookEntry created = [
            SELECT UnitPrice, IsActive FROM PricebookEntry WHERE Id = :res.createdPbeIds[0]
        ];
        System.assertEquals(77.77, created.UnitPrice,
            'Auto-created PBE should be seeded at the provided seed price');
        System.assertEquals(true, created.IsActive, 'Auto-created PBE should be Active');
    }

    @IsTest
    static void testAutoCreateMissingPbes_AlreadyCoveredSkips() {
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Order Migration Test Product' LIMIT 1];
        Pricebook2 targetPb = new Pricebook2(Name = 'Already Covered PB', IsActive = true);
        insert targetPb;
        insert new PricebookEntry(
            Pricebook2Id = targetPb.Id, Product2Id = prod.Id,
            UnitPrice = 5, IsActive = true
        );

        List<OrderMigrationService.PbeAutoCreateRequest> reqs =
            new List<OrderMigrationService.PbeAutoCreateRequest>{
                new OrderMigrationService.PbeAutoCreateRequest(
                    prod.Id, UserInfo.getDefaultCurrency(), 99)
            };

        Test.startTest();
        OrderMigrationService.AutoCreateResult res =
            OrderMigrationService.autoCreateMissingPbes(reqs, targetPb.Id);
        Test.stopTest();

        System.assertEquals(0, res.created,
            'Should not create when product is already covered');
    }

    @IsTest
    static void testAutoCreateMissingPbes_MissingStandardPbeReported() {
        // Create a product with NO Standard PBE
        Product2 orphan = new Product2(
            Name = 'Orphan Product (no std PBE)',
            IsActive = true, QuantityUnitOfMeasure = 'Each'
        );
        insert orphan;

        Pricebook2 targetPb = new Pricebook2(Name = 'Orphan Target PB', IsActive = true);
        insert targetPb;

        List<OrderMigrationService.PbeAutoCreateRequest> reqs =
            new List<OrderMigrationService.PbeAutoCreateRequest>{
                new OrderMigrationService.PbeAutoCreateRequest(
                    orphan.Id, UserInfo.getDefaultCurrency(), 1)
            };

        Test.startTest();
        OrderMigrationService.AutoCreateResult res =
            OrderMigrationService.autoCreateMissingPbes(reqs, targetPb.Id);
        Test.stopTest();

        System.assertEquals(0, res.created,
            'Should create nothing when Standard PBE is missing');
        System.assertEquals(1, res.productsMissingStandardPbe.size(),
            'Should surface the orphan product in productsMissingStandardPbe');
        System.assertEquals(orphan.Id, res.productsMissingStandardPbe[0],
            'Orphan product id should be reported');
    }

    // ── Saved filter presets ──────────────────────────────────────────

    @IsTest
    static void testSavedFilter_CrudLifecycle() {
        Test.startTest();
        Migration_Saved_Filter__c created = OrderMigrationService.saveFilter(
            null, 'Test Preset', 'like', 'DY_%', 'Demo filter'
        );
        System.assertNotEquals(null, created.Id, 'Save should insert');

        List<Migration_Saved_Filter__c> listed = OrderMigrationService.listSavedFilters();
        System.assert(!listed.isEmpty(), 'List should return the new preset');

        OrderMigrationService.touchSavedFilter(created.Id);
        Migration_Saved_Filter__c touched = [
            SELECT Last_Used_By__c, Last_Used_Date__c FROM Migration_Saved_Filter__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(UserInfo.getUserId(), touched.Last_Used_By__c,
            'Touch should set Last_Used_By__c to running user');
        System.assertNotEquals(null, touched.Last_Used_Date__c,
            'Touch should set Last_Used_Date__c');

        Migration_Saved_Filter__c updated = OrderMigrationService.saveFilter(
            created.Id, 'Updated Preset', 'soql',
            'SELECT Id FROM Quote WHERE Name LIKE \'%Foo%\'', 'Updated desc'
        );
        System.assertEquals('Updated Preset', updated.Name,
            'Save with existing Id should update the record');

        OrderMigrationService.deleteSavedFilter(created.Id);
        Integer remaining = [
            SELECT COUNT() FROM Migration_Saved_Filter__c WHERE Id = :created.Id
        ];
        System.assertEquals(0, remaining, 'Delete should remove the record');
        Test.stopTest();
    }

    @IsTest
    static void testMigrateLocalStorageFilters_BulkInsertSkipsDuplicates() {
        // Seed one existing filter to test duplicate skip behavior
        OrderMigrationService.saveFilter(null, 'Existing', 'like', 'X_%', null);

        List<Map<String, Object>> entries = new List<Map<String, Object>>();
        entries.add(new Map<String, Object>{
            'name' => 'From Local A', 'filterMode' => 'like',
            'filterValue' => 'A_%', 'description' => 'A'
        });
        entries.add(new Map<String, Object>{
            'name' => 'From Local B', 'filterMode' => 'qnum',
            'filterValue' => '123,456', 'description' => null
        });
        // Duplicate of existing (case-insensitive) — should skip
        entries.add(new Map<String, Object>{
            'name' => 'existing', 'filterMode' => 'like',
            'filterValue' => 'DUP_%', 'description' => null
        });
        // Blank name — should skip
        entries.add(new Map<String, Object>{
            'name' => '', 'filterMode' => 'like', 'filterValue' => 'BLANK_%'
        });

        Test.startTest();
        Integer inserted = OrderMigrationService.migrateLocalStorageFilters(entries);
        Test.stopTest();

        System.assertEquals(2, inserted,
            'Should insert 2 new records, skipping the duplicate and the blank');
        Integer total = [SELECT COUNT() FROM Migration_Saved_Filter__c];
        System.assertEquals(3, total,
            'Total should be 3 (existing + 2 migrated)');
    }

    // ── Saved pricebook presets ───────────────────────────────────────

    @IsTest
    static void testSavedPricebookPreset_CrudLifecycle() {
        Pricebook2 pb = new Pricebook2(Name = 'Preset PB', IsActive = true);
        insert pb;

        Test.startTest();
        Migration_Saved_Pricebook_Preset__c created = OrderMigrationService.savePricebookPreset(
            null, 'Default PB Preset', pb.Id, true, 'Demo'
        );
        System.assertNotEquals(null, created.Id, 'Save should insert');

        List<Migration_Saved_Pricebook_Preset__c> listed =
            OrderMigrationService.listSavedPricebookPresets();
        System.assert(!listed.isEmpty(), 'List should return the new preset');

        OrderMigrationService.touchSavedPricebookPreset(created.Id);
        Migration_Saved_Pricebook_Preset__c touched = [
            SELECT Last_Used_By__c FROM Migration_Saved_Pricebook_Preset__c WHERE Id = :created.Id
        ];
        System.assertEquals(UserInfo.getUserId(), touched.Last_Used_By__c,
            'Touch should set Last_Used_By__c');

        OrderMigrationService.savePricebookPreset(
            created.Id, 'Renamed Preset', pb.Id, false, null
        );
        Migration_Saved_Pricebook_Preset__c updated = [
            SELECT Name, Auto_Create_Missing_PBEs__c
            FROM Migration_Saved_Pricebook_Preset__c WHERE Id = :created.Id
        ];
        System.assertEquals('Renamed Preset', updated.Name, 'Save should update Name');
        System.assertEquals(false, updated.Auto_Create_Missing_PBEs__c,
            'Save should update auto-create flag');

        OrderMigrationService.deleteSavedPricebookPreset(created.Id);
        Integer remaining = [
            SELECT COUNT() FROM Migration_Saved_Pricebook_Preset__c WHERE Id = :created.Id
        ];
        System.assertEquals(0, remaining, 'Delete should remove the record');
        Test.stopTest();
    }

    // ── Category catalog ──────────────────────────────────────────────

    @IsTest
    static void testCategoryCatalog_AllFourteenEntries() {
        Map<String, OrderMigrationService.CategoryMetadata> catalog =
            OrderMigrationService.getCategoryCatalog();
        System.assertEquals(14, catalog.size(),
            'Catalog should contain all 14 categories matching the picklist');
        // Spot-check a few well-known categories
        System.assert(catalog.containsKey('NoAccountId'),
            'NoAccountId category should be present');
        System.assert(catalog.containsKey('OiaInsertFailed'),
            'OiaInsertFailed category should be present');
        System.assert(catalog.containsKey('Unhandled'),
            'Unhandled category should be present');
    }

    @IsTest
    static void testIsCleanupRequiredForCategory() {
        // Cleanup required: Order/Contract was created
        System.assertEquals(true,
            OrderMigrationService.isCleanupRequiredForCategory('OrderItemDmlFailed'),
            'OrderItemDmlFailed leaves a partial Order — cleanup required');
        System.assertEquals(true,
            OrderMigrationService.isCleanupRequiredForCategory('OiaInsertFailed'),
            'OiaInsertFailed leaves a successful Order with missing OIAs — cleanup required');
        System.assertEquals(true,
            OrderMigrationService.isCleanupRequiredForCategory('OrderActivationFailed'),
            'OrderActivationFailed leaves a Draft Order — cleanup required');
        // Cleanup NOT required: nothing was created
        System.assertEquals(false,
            OrderMigrationService.isCleanupRequiredForCategory('NoAccountId'),
            'NoAccountId quote was skipped before Order creation — no cleanup needed');
        System.assertEquals(false,
            OrderMigrationService.isCleanupRequiredForCategory('MissingPbeCoverage'),
            'MissingPbeCoverage quote was skipped before Order creation — no cleanup needed');
        System.assertEquals(false,
            OrderMigrationService.isCleanupRequiredForCategory('ContractResolutionFailed'),
            'ContractResolutionFailed quote was skipped before Order creation — no cleanup needed');
        // Unknown category → false (defensive)
        System.assertEquals(false,
            OrderMigrationService.isCleanupRequiredForCategory('NotARealCategory'),
            'Unknown category should default to no cleanup');
    }
}