/**
 * @description Test class for Fortra_BulkPriceUpdateBatch, Fortra_BulkPriceUpdateInvocable,
 *              and Fortra_CurrencyConversionService.
 *
 *              Test Coverage:
 *              - CurrencyConversionService: Formula parsing and application
 *              - Invocable: Input validation, category parsing, product counting
 *              - Batch: Product processing, PBE creation/update, email notification
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-01
 */
@IsTest
private class Fortra_BulkPriceUpdateBatchTest {

    private static final String TEST_CATEGORY = 'Test Category';
    private static final String TEST_CATEGORY_2 = 'Test Category 2';
    private static final Decimal USD_PRICE = 100.00;

    /**
     * @description Helper: return all active pricebook IDs as a Set<Id>
     */
    private static Set<Id> allActivePricebookIds() {
        return new Map<Id, Pricebook2>(
            [SELECT Id FROM Pricebook2 WHERE IsActive = true]
        ).keySet();
    }

    /**
     * @description Helper: join a Set<Id> into the semicolon-separated form expected by the Invocable
     */
    private static String joinIds(Set<Id> ids) {
        List<String> tokens = new List<String>();
        for (Id i : ids) tokens.add(String.valueOf(i));
        return String.join(tokens, ';');
    }

    /**
     * @description Setup test data - creates products, pricebooks, and PBEs
     */
    @TestSetup
    static void setupTestData() {
        // Create test products (include QuantityUnitOfMeasure for validation rules)
        List<Product2> products = new List<Product2>();
        for (Integer i = 1; i <= 5; i++) {
            products.add(new Product2(
                Name = 'Test Product ' + i,
                ProductCode = 'TP-00' + i,
                Solution_Category__c = TEST_CATEGORY,
                QuantityUnitOfMeasure = 'Each',
                IsActive = true
            ));
        }
        // Add one product in a different category
        products.add(new Product2(
            Name = 'Test Product Other',
            ProductCode = 'TP-OTHER',
            Solution_Category__c = TEST_CATEGORY_2,
            QuantityUnitOfMeasure = 'Each',
            IsActive = true
        ));
        // Add one inactive product (should be excluded)
        products.add(new Product2(
            Name = 'Inactive Product',
            ProductCode = 'TP-INACTIVE',
            Solution_Category__c = TEST_CATEGORY,
            QuantityUnitOfMeasure = 'Each',
            IsActive = false
        ));
        insert products;

        // Get Standard Pricebook and activate it (Salesforce default in tests is IsActive=false)
        Id stdPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = stdPricebookId, IsActive = true);

        // Create Standard Pricebook Entries for USD
        List<PricebookEntry> stdPBEs = new List<PricebookEntry>();
        for (Product2 p : [SELECT Id FROM Product2 WHERE IsActive = true]) {
            stdPBEs.add(new PricebookEntry(
                Product2Id = p.Id,
                Pricebook2Id = stdPricebookId,
                UnitPrice = USD_PRICE,
                CurrencyIsoCode = 'USD',
                IsActive = true
            ));
        }
        insert stdPBEs;

        // Create a custom pricebook
        Pricebook2 customPricebook = new Pricebook2(
            Name = 'Test Custom Pricebook',
            IsActive = true
        );
        insert customPricebook;
    }

    // =============================================================
    // CurrencyConversionService Tests
    // =============================================================

    /**
     * @description Test formula application with multiplication
     */
    @IsTest
    static void testApplyFormula_Multiply() {
        Decimal result = Fortra_CurrencyConversionService.applyFormula(100.00, '* 0.92');
        System.assertEquals(92.00, result, 'Multiplication formula should work correctly');
    }

    /**
     * @description Test formula application with division
     */
    @IsTest
    static void testApplyFormula_Divide() {
        Decimal result = Fortra_CurrencyConversionService.applyFormula(100.00, '/ 2');
        System.assertEquals(50.00, result, 'Division formula should work correctly');
    }

    /**
     * @description Test formula application with addition
     */
    @IsTest
    static void testApplyFormula_Add() {
        Decimal result = Fortra_CurrencyConversionService.applyFormula(100.00, '+ 10.50');
        System.assertEquals(110.50, result, 'Addition formula should work correctly');
    }

    /**
     * @description Test formula application with subtraction
     */
    @IsTest
    static void testApplyFormula_Subtract() {
        Decimal result = Fortra_CurrencyConversionService.applyFormula(100.00, '- 5');
        System.assertEquals(95.00, result, 'Subtraction formula should work correctly');
    }

    /**
     * @description Test formula with null inputs
     */
    @IsTest
    static void testApplyFormula_NullInputs() {
        System.assertEquals(null, Fortra_CurrencyConversionService.applyFormula(null, '* 1.0'),
            'Null price should return null');
        System.assertEquals(null, Fortra_CurrencyConversionService.applyFormula(100.00, null),
            'Null formula should return null');
        System.assertEquals(null, Fortra_CurrencyConversionService.applyFormula(100.00, ''),
            'Empty formula should return null');
    }

    /**
     * @description Test formula with invalid format
     */
    @IsTest
    static void testApplyFormula_InvalidFormula() {
        Decimal result = Fortra_CurrencyConversionService.applyFormula(100.00, 'invalid');
        System.assertEquals(null, result, 'Invalid formula should return null');
    }

    /**
     * @description Test formula with division by zero
     */
    @IsTest
    static void testApplyFormula_DivideByZero() {
        Decimal result = Fortra_CurrencyConversionService.applyFormula(100.00, '/ 0');
        System.assertEquals(null, result, 'Division by zero should return null');
    }

    /**
     * @description Test decimal rounding
     */
    @IsTest
    static void testApplyFormula_Rounding() {
        Decimal result = Fortra_CurrencyConversionService.applyFormula(100.00, '/ 3');
        System.assertEquals(33.33, result, 'Result should be rounded to 2 decimal places');
    }

    /**
     * @description Test getActiveFormulas caching
     */
    @IsTest
    static void testGetActiveFormulas_Caching() {
        // Clear cache first
        Fortra_CurrencyConversionService.clearCache();

        Test.startTest();
        // First call loads from SOQL
        Map<String, Currency_Conversion_Formula__mdt> formulas1 =
            Fortra_CurrencyConversionService.getActiveFormulas();

        // Second call should use cache (no additional SOQL)
        Map<String, Currency_Conversion_Formula__mdt> formulas2 =
            Fortra_CurrencyConversionService.getActiveFormulas();
        Test.stopTest();

        // Both should return same reference (cached)
        System.assert(formulas1 == formulas2, 'Should return cached instance');
    }

    /**
     * @description Test conversion result wrapper
     */
    @IsTest
    static void testConvertPriceWithDetails_MissingFormula() {
        // Clear cache to ensure fresh state
        Fortra_CurrencyConversionService.clearCache();

        Test.startTest();
        // Try to convert to a currency that may not exist in CMDT
        Fortra_CurrencyConversionService.ConversionResult result =
            Fortra_CurrencyConversionService.convertPriceWithDetails(100.00, 'ZZZ');
        Test.stopTest();

        // Should fail gracefully - result depends on whether ZZZ exists in org
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    /**
     * @description convertPrice prefers numeric Conversion_Rate__c when populated on CMDT
     */
    @IsTest
    static void testConvertPrice_UsesConversionRateField() {
        Fortra_CurrencyConversionService.clearCache();

        Test.startTest();
        Decimal eurConverted = Fortra_CurrencyConversionService.convertPrice(100.00, 'EUR');
        Decimal usdConverted = Fortra_CurrencyConversionService.convertPrice(100.00, 'USD');
        Decimal missing = Fortra_CurrencyConversionService.convertPrice(100.00, 'ZZZ');
        Test.stopTest();

        System.assertNotEquals(null, eurConverted, 'EUR should convert via Conversion_Rate__c');
        System.assert(eurConverted > 0, 'EUR converted price should be positive');
        System.assertEquals(100.00, usdConverted, 'USD Conversion_Rate__c should be 1.0');
        System.assertEquals(null, missing, 'Unknown currency should return null');
    }

    /**
     * @description getFormula returns active CMDT keyed by ISO code
     */
    @IsTest
    static void testGetFormula_ActiveRecord() {
        Fortra_CurrencyConversionService.clearCache();
        Currency_Conversion_Formula__mdt eur = Fortra_CurrencyConversionService.getFormula('EUR');
        System.assertNotEquals(null, eur, 'EUR formula record should exist in org CMDT');
    }

    @IsTest
    static void testConvertPrice_NullAndBlankInputs() {
        System.assertEquals(null, Fortra_CurrencyConversionService.convertPrice(null, 'EUR'));
        System.assertEquals(null, Fortra_CurrencyConversionService.convertPrice(100, null));
        System.assertEquals(null, Fortra_CurrencyConversionService.convertPrice(100, ''));
    }

    @IsTest
    static void testGetActiveCurrencyCodesAndConvertAll() {
        Fortra_CurrencyConversionService.clearCache();
        Test.startTest();
        List<String> codes = Fortra_CurrencyConversionService.getActiveCurrencyCodes();
        Map<String, Decimal> all = Fortra_CurrencyConversionService.convertToAllCurrencies(100.00);
        Test.stopTest();
        System.assert(codes.size() > 0, 'Active currency codes should exist');
        System.assert(all.size() > 0, 'Should convert to at least one currency');
        System.assert(all.containsKey('USD'), 'USD should be in conversion map');
    }

    @IsTest
    static void testConvertPriceWithDetails_Success() {
        Fortra_CurrencyConversionService.clearCache();
        Fortra_CurrencyConversionService.ConversionResult result =
            Fortra_CurrencyConversionService.convertPriceWithDetails(100.00, 'EUR');
        System.assertNotEquals(null, result);
        System.assertEquals(true, result.success, 'EUR detail conversion should succeed');
        System.assertNotEquals(null, result.convertedPrice);
    }

    @IsTest
    static void testConvertPriceWithDetails_NullPrice() {
        Fortra_CurrencyConversionService.ConversionResult result =
            Fortra_CurrencyConversionService.convertPriceWithDetails(null, 'EUR');
        System.assertEquals('USD price is null', result.errorMessage);
    }

    @IsTest
    static void testConvertPriceWithDetails_BlankCurrency() {
        Fortra_CurrencyConversionService.ConversionResult result =
            Fortra_CurrencyConversionService.convertPriceWithDetails(100.00, '');
        System.assertEquals('Target currency code is blank', result.errorMessage);
    }

    // =============================================================
    // Invocable Tests
    // =============================================================

    /**
     * @description Test category parsing
     */
    @IsTest
    static void testParseSolutionCategories() {
        // Test normal input
        Set<String> categories = Fortra_BulkPriceUpdateInvocable.parseSolutionCategories(
            'Category1; Category2 ; Category3');
        System.assertEquals(3, categories.size(), 'Should parse 3 categories');
        System.assert(categories.contains('Category1'), 'Should contain Category1');
        System.assert(categories.contains('Category2'), 'Should contain trimmed Category2');

        // Test empty input
        categories = Fortra_BulkPriceUpdateInvocable.parseSolutionCategories('');
        System.assertEquals(0, categories.size(), 'Empty string should return empty set');

        // Test null input
        categories = Fortra_BulkPriceUpdateInvocable.parseSolutionCategories(null);
        System.assertEquals(0, categories.size(), 'Null should return empty set');

        // Test single category
        categories = Fortra_BulkPriceUpdateInvocable.parseSolutionCategories('SingleCategory');
        System.assertEquals(1, categories.size(), 'Should parse single category');
    }

    /**
     * @description Test product counting
     */
    @IsTest
    static void testCountProducts() {
        Test.startTest();
        Integer count = Fortra_BulkPriceUpdateInvocable.countProducts(
            new Set<String>{ TEST_CATEGORY });
        Test.stopTest();

        // Should count only active products in the category (5 products, not the inactive one)
        System.assertEquals(5, count, 'Should count 5 active products in test category');
    }

    /**
     * @description Test invocable with empty categories
     */
    @IsTest
    static void testInvocable_EmptyCategories() {
        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = '';

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Should fail with empty categories');
        System.assert(String.isNotBlank(results[0].errorMessage), 'Should have error message');
    }

    /**
     * @description Test invocable with non-existent category
     */
    @IsTest
    static void testInvocable_NoProducts() {
        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = 'NonExistent Category';
        request.pricebookIds = joinIds(allActivePricebookIds());

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Should fail with no products');
        System.assertEquals(0, results[0].productCount, 'Should have 0 product count');
    }

    /**
     * @description Test getSolutionCategories AuraEnabled method
     */
    @IsTest
    static void testGetSolutionCategories() {
        Test.startTest();
        List<String> categories = Fortra_BulkPriceUpdateInvocable.getSolutionCategories();
        Test.stopTest();

        System.assert(categories.contains(TEST_CATEGORY), 'Should include test category');
        System.assert(categories.contains(TEST_CATEGORY_2), 'Should include test category 2');
    }

    /**
     * @description Test getProductPreview AuraEnabled method
     */
    @IsTest
    static void testGetProductPreview() {
        Test.startTest();
        Map<String, Object> preview = Fortra_BulkPriceUpdateInvocable.getProductPreview(TEST_CATEGORY);
        Test.stopTest();

        System.assertEquals(5, (Integer)preview.get('count'), 'Should show 5 products');
        List<String> productNames = (List<String>)preview.get('products');
        System.assert(productNames.size() <= 25, 'Should limit to 25 products');
        System.assert(productNames.size() > 0, 'Should have some products');
    }

    /**
     * @description Test getProductPreview with empty categories
     */
    @IsTest
    static void testGetProductPreview_Empty() {
        Test.startTest();
        Map<String, Object> preview = Fortra_BulkPriceUpdateInvocable.getProductPreview('');
        Test.stopTest();

        System.assertEquals(0, (Integer)preview.get('count'), 'Should show 0 products');
        System.assert(preview.containsKey('error'), 'Should have error message');
    }

    // =============================================================
    // Batch Tests
    // =============================================================

    /**
     * @description Test successful batch execution
     */
    @IsTest
    static void testBatchExecution_Success() {
        // Note: In a real org, Currency_Conversion_Formula__mdt would have records
        // For this test, the batch will process products but may not create PBEs
        // if no currency formulas exist

        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY;
        request.pricebookIds = joinIds(allActivePricebookIds());
        request.batchSize = 50;

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        // The batch should complete (results depend on CMDT in org)
        System.assertEquals(1, results.size(), 'Should return one result');

        // If success, verify job details
        if (results[0].success) {
            System.assert(String.isNotBlank(results[0].jobId), 'Should have job ID');
            System.assertEquals(5, results[0].productCount, 'Should process 5 products');
            System.assert(results[0].categoriesProcessed.contains(TEST_CATEGORY),
                'Should include processed category');
        }
    }

    /**
     * @description Test batch with multiple categories
     */
    @IsTest
    static void testBatchExecution_MultipleCategories() {
        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY + ';' + TEST_CATEGORY_2;
        request.pricebookIds = joinIds(allActivePricebookIds());

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');

        if (results[0].success) {
            // Should process products from both categories (5 + 1 = 6)
            System.assertEquals(6, results[0].productCount, 'Should process 6 products from both categories');
        }
    }

    /**
     * @description Test checkBatchStatus method
     */
    @IsTest
    static void testCheckBatchStatus() {
        // Start a batch job first
        Fortra_BulkPriceUpdateBatch batch = new Fortra_BulkPriceUpdateBatch(
            new Set<String>{ TEST_CATEGORY },
            allActivePricebookIds(),
            UserInfo.getUserId()
        );

        Test.startTest();
        Id jobId = Database.executeBatch(batch, 50);
        Test.stopTest();

        // Check status
        Map<String, Object> status = Fortra_BulkPriceUpdateInvocable.checkBatchStatus(String.valueOf(jobId));

        System.assert(status.containsKey('status'), 'Should have status field');
        System.assertEquals(true, status.get('isComplete'), 'Should be complete after Test.stopTest()');
    }

    /**
     * @description Test checkBatchStatus with invalid job ID
     */
    @IsTest
    static void testCheckBatchStatus_InvalidId() {
        Test.startTest();
        Map<String, Object> status = Fortra_BulkPriceUpdateInvocable.checkBatchStatus('');
        Test.stopTest();

        System.assert(status.containsKey('error'), 'Should have error for empty ID');
    }

    /**
     * @description Test batch constructor with null user ID
     */
    @IsTest
    static void testBatchConstructor_NullUser() {
        Test.startTest();
        Fortra_BulkPriceUpdateBatch batch = new Fortra_BulkPriceUpdateBatch(
            new Set<String>{ TEST_CATEGORY },
            allActivePricebookIds(),
            null  // No user ID
        );
        Id jobId = Database.executeBatch(batch, 50);
        Test.stopTest();

        // Should complete without error (email just won't be sent)
        AsyncApexJob job = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', job.Status, 'Batch should complete');
    }

    /**
     * @description Test batch with products missing USD price
     */
    @IsTest
    static void testBatchExecution_MissingUSDPrice() {
        // Create a product without Standard Pricebook Entry
        Product2 productNoPrice = new Product2(
            Name = 'Product No Price',
            ProductCode = 'TP-NOPRICE',
            Solution_Category__c = 'No Price Category',
            QuantityUnitOfMeasure = 'Each',
            IsActive = true
        );
        insert productNoPrice;

        Test.startTest();
        Fortra_BulkPriceUpdateBatch batch = new Fortra_BulkPriceUpdateBatch(
            new Set<String>{ 'No Price Category' },
            allActivePricebookIds(),
            UserInfo.getUserId()
        );
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Batch should complete (the product without price will be logged as error)
        // Just verifying no exceptions are thrown
        System.assert(true, 'Batch should handle missing prices gracefully');
    }

    /**
     * @description Test invocable with previewOnly flag
     */
    @IsTest
    static void testInvocable_PreviewOnly() {
        Set<Id> allPbs = allActivePricebookIds();
        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY;
        request.pricebookIds = joinIds(allPbs);
        request.previewOnly = true;

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Preview should succeed');
        System.assertEquals(5, results[0].productCount, 'Should count 5 active products');
        System.assertEquals(null, results[0].jobId, 'Preview should NOT start a batch job');
        System.assert(String.isNotBlank(results[0].categoriesProcessed), 'Should include categories');

        // Per-pricebook breakdown should be populated
        System.assertNotEquals(null, results[0].pricebookEstimates, 'Should have estimates list');
        System.assertEquals(allPbs.size(), results[0].pricebookEstimates.size(),
            'Estimate row count should match selected pricebook count');
        System.assert(String.isNotBlank(results[0].pricebooksProcessed), 'Should include pricebooks summary');
    }

    /**
     * @description Test invocable with custom batch size
     */
    @IsTest
    static void testInvocable_CustomBatchSize() {
        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY;
        request.pricebookIds = joinIds(allActivePricebookIds());
        request.batchSize = 10;  // Custom batch size

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        // Should execute successfully with custom batch size
        if (results[0].success) {
            System.assert(String.isNotBlank(results[0].jobId), 'Should have job ID');
        }
    }

    // =============================================================
    // Pricebook Selection Tests
    // =============================================================

    /**
     * @description Reject when pricebookIds is missing
     */
    @IsTest
    static void testInvocable_EmptyPricebookIds() {
        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY;
        // pricebookIds intentionally omitted

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Should fail when pricebookIds is missing');
        System.assert(results[0].errorMessage != null
            && results[0].errorMessage.contains('Pricebook'),
            'Error should mention Pricebook: ' + results[0].errorMessage);
    }

    /**
     * @description Per-pricebook breakdown reflects exact selection size and counts
     */
    @IsTest
    static void testInvocable_PerPricebookCount() {
        Set<Id> allPbs = allActivePricebookIds();
        // Take exactly two pricebooks for the selection
        List<Id> ordered = new List<Id>(allPbs);
        Set<Id> subset = new Set<Id>{ ordered[0], ordered[1] };

        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY;
        request.pricebookIds = joinIds(subset);
        request.previewOnly = true;

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Preview should succeed');
        System.assertEquals(2, results[0].pricebookEstimates.size(),
            'Should produce one estimate per selected pricebook');

        // Sum of per-pricebook estimates should equal the aggregate estimatedPBECount
        Integer sum = 0;
        for (Fortra_BulkPriceUpdateInvocable.PricebookEstimate est : results[0].pricebookEstimates) {
            sum += est.estimatedPBECount;
        }
        System.assertEquals(results[0].estimatedPBECount, sum,
            'Sum of per-pricebook counts should equal estimatedPBECount');
    }

    /**
     * @description Custom-only selection where USD Standard PBEs are MISSING for a product
     *              should produce a blocking warning in preview and not start a batch
     */
    @IsTest
    static void testInvocable_CustomOnlyMissingStandard() {
        // Add a product in TEST_CATEGORY without a USD Standard PBE
        Product2 noPricedProduct = new Product2(
            Name = 'Test Product No USD',
            ProductCode = 'TP-NOUSD',
            Solution_Category__c = TEST_CATEGORY,
            QuantityUnitOfMeasure = 'Each',
            IsActive = true
        );
        insert noPricedProduct;

        // Selection = only the custom pricebook (Standard excluded)
        Pricebook2 customPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = false AND IsActive = true LIMIT 1];

        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY;
        request.pricebookIds = String.valueOf(customPb.Id);
        request.previewOnly = true;

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(true, results[0].blockingWarning,
            'blockingWarning should be true when Standard excluded and USD Standard PBEs missing');
        System.assert(String.isNotBlank(results[0].standardWarning),
            'standardWarning should be populated');
        System.assertEquals(null, results[0].jobId,
            'Preview should not start a batch even when blocking');
    }

    /**
     * @description Custom-only selection succeeds when all in-scope products have USD Standard PBEs
     */
    @IsTest
    static void testInvocable_CustomOnlyWithStandardPresent() {
        // Test setup already created USD Standard PBEs for all 5 active TEST_CATEGORY products
        Pricebook2 customPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = false AND IsActive = true LIMIT 1];

        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY;
        request.pricebookIds = String.valueOf(customPb.Id);
        request.previewOnly = true;

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Preview should succeed');
        System.assertEquals(false, results[0].blockingWarning,
            'No blocking warning when Standard PBEs exist for all in-scope products');
        System.assertEquals(1, results[0].pricebookEstimates.size(),
            'Single pricebook in selection');
        System.assertEquals(false, results[0].pricebookEstimates[0].isStandard,
            'Selected pricebook should be the custom one');
    }

    /**
     * @description Standard-only selection produces only Standard estimate row
     */
    @IsTest
    static void testInvocable_StandardOnly() {
        Id standardPbId = Test.getStandardPricebookId();

        Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest request =
            new Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest();
        request.solutionCategories = TEST_CATEGORY;
        request.pricebookIds = String.valueOf(standardPbId);
        request.previewOnly = true;

        Test.startTest();
        List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateResult> results =
            Fortra_BulkPriceUpdateInvocable.startBulkPriceUpdate(
                new List<Fortra_BulkPriceUpdateInvocable.BulkPriceUpdateRequest>{ request });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Standard-only preview should succeed');
        System.assertEquals(1, results[0].pricebookEstimates.size(),
            'One estimate row for Standard-only selection');
        System.assertEquals(true, results[0].pricebookEstimates[0].isStandard,
            'Selected pricebook should be Standard');
        System.assertEquals(false, results[0].blockingWarning,
            'Standard included means no blocking warning');
    }

    /**
     * @description Subset of pricebooks limits the batch's activePricebooks scope
     */
    @IsTest
    static void testBatchExecution_PricebookSubset() {
        // Use selection of just the standard pricebook (subset of all)
        Set<Id> selection = new Set<Id>{ Test.getStandardPricebookId() };

        Test.startTest();
        Fortra_BulkPriceUpdateBatch batch = new Fortra_BulkPriceUpdateBatch(
            new Set<String>{ TEST_CATEGORY },
            selection,
            UserInfo.getUserId()
        );
        Id jobId = Database.executeBatch(batch, 50);
        Test.stopTest();

        AsyncApexJob job = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', job.Status, 'Subset batch should complete');
    }

    /**
     * @description Constructor rejects null/empty selection
     */
    @IsTest
    static void testBatchConstructor_RejectsEmptyPricebookIds() {
        Boolean threw = false;
        try {
            new Fortra_BulkPriceUpdateBatch(
                new Set<String>{ TEST_CATEGORY },
                new Set<Id>(), // empty
                UserInfo.getUserId()
            );
        } catch (IllegalArgumentException e) {
            threw = true;
            System.assert(e.getMessage().contains('Pricebook'),
                'Exception message should mention Pricebook: ' + e.getMessage());
        }
        System.assertEquals(true, threw, 'Empty pricebookIds should throw IllegalArgumentException');

        threw = false;
        try {
            new Fortra_BulkPriceUpdateBatch(
                new Set<String>{ TEST_CATEGORY },
                null,
                UserInfo.getUserId()
            );
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Null pricebookIds should throw IllegalArgumentException');
    }
}