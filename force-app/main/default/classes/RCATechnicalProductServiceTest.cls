/**
 * @description Test class for RCATechnicalProductService
 * Tests technical product creation, validation, and decomposition rule creation
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
@isTest
private class RCATechnicalProductServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create commercial products (products that would be sold)
        List<Product2> commercialProducts = new List<Product2>();

        Product2 bundleProduct = new Product2(
            Name = 'Test Bundle Product',
            ProductCode = 'TEST-BUNDLE-001',
            Description = 'Test bundle for technical product creation',
            Family = 'Software',
            IsActive = true,
            Type = 'Bundle',
            DecompositionScope = 'Bundle',
            QuantityUnitOfMeasure = 'Each',
            // Workday integration fields
            Workday_Sales_Item_ID__c = 'WD-SALES-123',
            Rev_Category__c = 'Subscription',
            Finance_Business_Unit__c = 'BU-001',
            Fortra_Product_Type__c = 'Software'
        );
        commercialProducts.add(bundleProduct);

        Product2 standardProduct = new Product2(
            Name = 'Test Standard Product',
            ProductCode = 'TEST-STD-001',
            Description = 'Test standard product',
            Family = 'Hardware',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            // Workday integration fields
            Workday_Sales_Item_ID__c = 'WD-SALES-456',
            Rev_Category__c = 'Perpetual',
            Finance_Business_Unit__c = 'BU-002',
            Fortra_Product_Type__c = 'Software'
        );
        commercialProducts.add(standardProduct);

        // Third product without related records for testing that scenario
        Product2 bareProduct = new Product2(
            Name = 'Test Bare Product',
            ProductCode = 'TEST-BARE-001',
            Description = 'Product without related records',
            Family = 'Services',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        commercialProducts.add(bareProduct);

        insert commercialProducts;

        // Create ProductSellingModels (Term and Perpetual)
        // Note: When PricingTermUnit = 'Months', PricingTerm must be 1 per Salesforce validation
        // Note: Code__c is a custom required field in Fortra org
        ProductSellingModel termModel = new ProductSellingModel(
            Name = 'Term Model',
            Code__c = 'TERM-TEST',
            SellingModelType = 'TermDefined',
            PricingTermUnit = 'Months',
            PricingTerm = 1,
            Status = 'Active'
        );
        ProductSellingModel perpetualModel = new ProductSellingModel(
            Name = 'Perpetual Model',
            Code__c = 'PERP-TEST',
            SellingModelType = 'Evergreen',
            PricingTermUnit = 'Months',
            PricingTerm = 1,
            Status = 'Active'
        );
        insert new List<ProductSellingModel>{ termModel, perpetualModel };

        // Create ProductSellingModelOptions for bundle product (both models)
        ProductSellingModelOption bundlePsmo1 = new ProductSellingModelOption(
            Product2Id = bundleProduct.Id,
            ProductSellingModelId = termModel.Id,
            IsDefault = true
        );
        ProductSellingModelOption bundlePsmo2 = new ProductSellingModelOption(
            Product2Id = bundleProduct.Id,
            ProductSellingModelId = perpetualModel.Id,
            IsDefault = false
        );
        // Create ProductSellingModelOption for standard product (just term model)
        ProductSellingModelOption stdPsmo = new ProductSellingModelOption(
            Product2Id = standardProduct.Id,
            ProductSellingModelId = termModel.Id,
            IsDefault = true
        );
        insert new List<ProductSellingModelOption>{ bundlePsmo1, bundlePsmo2, stdPsmo };

        // Get Standard Pricebook (use Test method for proper test isolation)
        Id standardPricebookId = Test.getStandardPricebookId();

        // Create custom pricebook
        Pricebook2 customPricebook = new Pricebook2(
            Name = 'Test Custom Pricebook',
            IsActive = true
        );
        insert customPricebook;

        // Create PricebookEntries - Standard pricebook first (required by Salesforce)
        List<PricebookEntry> standardPbes = new List<PricebookEntry>();
        standardPbes.add(new PricebookEntry(
            Product2Id = bundleProduct.Id,
            Pricebook2Id = standardPricebookId,
            UnitPrice = 1000.00,
            IsActive = true
        ));
        standardPbes.add(new PricebookEntry(
            Product2Id = standardProduct.Id,
            Pricebook2Id = standardPricebookId,
            UnitPrice = 500.00,
            IsActive = true
        ));
        insert standardPbes;

        // Create custom pricebook entries
        List<PricebookEntry> customPbes = new List<PricebookEntry>();
        customPbes.add(new PricebookEntry(
            Product2Id = bundleProduct.Id,
            Pricebook2Id = customPricebook.Id,
            UnitPrice = 900.00, // Discounted price
            IsActive = true
        ));
        customPbes.add(new PricebookEntry(
            Product2Id = standardProduct.Id,
            Pricebook2Id = customPricebook.Id,
            UnitPrice = 450.00,
            IsActive = true
        ));
        insert customPbes;

        // Create ProductCategory and Catalog for category assignment testing
        ProductCatalog testCatalog = new ProductCatalog(
            Name = 'Test Catalog'
        );
        insert testCatalog;

        ProductCategory testCategory = new ProductCategory(
            Name = 'Test Software Category',
            CatalogId = testCatalog.Id
        );
        ProductCategory testCategory2 = new ProductCategory(
            Name = 'Test Hardware Category',
            CatalogId = testCatalog.Id
        );
        insert new List<ProductCategory>{ testCategory, testCategory2 };

        // Create ProductCategoryProducts - bundle in both categories, standard in one
        ProductCategoryProduct bundlePcp1 = new ProductCategoryProduct(
            ProductId = bundleProduct.Id,
            ProductCategoryId = testCategory.Id
        );
        ProductCategoryProduct bundlePcp2 = new ProductCategoryProduct(
            ProductId = bundleProduct.Id,
            ProductCategoryId = testCategory2.Id
        );
        ProductCategoryProduct stdPcp = new ProductCategoryProduct(
            ProductId = standardProduct.Id,
            ProductCategoryId = testCategory2.Id
        );
        insert new List<ProductCategoryProduct>{ bundlePcp1, bundlePcp2, stdPcp };
    }

    @isTest
    static void testValidateRequests_ValidRequest() {
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Test Bundle - Technical';
        request.technicalProductCode = 'TEST-BUNDLE-001-TECH';
        request.technicalProductDescription = 'Technical product for test bundle';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        List<String> errors = RCATechnicalProductService.validateRequests(requests);
        Test.stopTest();

        System.assertEquals(0, errors.size(), 'Valid request should have no errors');
    }

    @isTest
    static void testValidateRequests_MissingRequiredFields() {
        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        // Request missing commercial product ID
        RCATechnicalProductService.TechnicalProductRequest request1 =
            new RCATechnicalProductService.TechnicalProductRequest();
        request1.technicalProductName = 'Test Technical';
        request1.technicalProductCode = 'TEST-TECH';
        requests.add(request1);

        // Request missing name - use proper 18-char dummy Id format
        RCATechnicalProductService.TechnicalProductRequest request2 =
            new RCATechnicalProductService.TechnicalProductRequest();
        request2.commercialProductId = '01tdp000000000JAAQ'; // Dummy Product2 Id format
        request2.technicalProductCode = 'TEST-TECH-2';
        requests.add(request2);

        Test.startTest();
        List<String> errors = RCATechnicalProductService.validateRequests(requests);
        Test.stopTest();

        System.assert(errors.size() > 0, 'Missing required fields should generate errors');
    }

    @isTest
    static void testValidateRequests_DuplicateCodes() {
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        // Two requests with same code
        RCATechnicalProductService.TechnicalProductRequest request1 =
            new RCATechnicalProductService.TechnicalProductRequest();
        request1.commercialProductId = commercial.Id;
        request1.commercialProductCode = commercial.ProductCode;
        request1.technicalProductName = 'Test Tech 1';
        request1.technicalProductCode = 'DUPLICATE-CODE';
        request1.decompRulePriority = 1;
        requests.add(request1);

        RCATechnicalProductService.TechnicalProductRequest request2 =
            new RCATechnicalProductService.TechnicalProductRequest();
        request2.commercialProductId = commercial.Id;
        request2.commercialProductCode = commercial.ProductCode;
        request2.technicalProductName = 'Test Tech 2';
        request2.technicalProductCode = 'DUPLICATE-CODE';
        request2.decompRulePriority = 2;
        requests.add(request2);

        Test.startTest();
        List<String> errors = RCATechnicalProductService.validateRequests(requests);
        Test.stopTest();

        System.assert(errors.size() > 0, 'Duplicate codes should generate an error');
        Boolean foundDuplicateError = false;
        for (String error : errors) {
            if (error.containsIgnoreCase('duplicate')) {
                foundDuplicateError = true;
                break;
            }
        }
        System.assert(foundDuplicateError, 'Should contain duplicate code error message');
    }

    @isTest
    static void testCreateTechnicalProducts_SingleProduct() {
        Product2 commercial = [SELECT Id, Name, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Test Bundle - Technical';
        request.technicalProductCode = 'TEST-BUNDLE-001-TECH';
        request.technicalProductDescription = 'Technical product for test bundle';
        request.family = 'Software';
        request.decompRulePriority = 1;
        request.isActive = true;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assertEquals(0, result.totalFailed, 'Should have 0 failures');
        System.assertEquals(1, result.results.size(), 'Should have 1 result');
        System.assert(result.results[0].success, 'Result should be successful');
        System.assertNotEquals(null, result.results[0].technicalProductId, 'Should have technical product ID');
        System.assertNotEquals(null, result.results[0].decompRuleId, 'Should have decomp rule ID');

        // Verify the technical product was created correctly
        Product2 techProduct = [
            SELECT Id, Name, ProductCode, Type, DecompositionScope, IsActive
            FROM Product2
            WHERE Id = :result.results[0].technicalProductId
        ];
        System.assertEquals('Test Bundle - Technical', techProduct.Name);
        System.assertEquals('TEST-BUNDLE-001-TECH', techProduct.ProductCode);
        System.assertEquals(null, techProduct.Type, 'Technical product should have null Type');
        System.assertEquals(null, techProduct.DecompositionScope, 'Technical product should have null DecompositionScope');
        System.assertEquals(true, techProduct.IsActive);

        // Verify the decomposition rule was created
        ProductFulfillmentDecompRule decompRule = [
            SELECT Id, SourceProductId, DestinationProductId, Priority
            FROM ProductFulfillmentDecompRule
            WHERE Id = :result.results[0].decompRuleId
        ];
        System.assertEquals(commercial.Id, decompRule.SourceProductId);
        System.assertEquals(techProduct.Id, decompRule.DestinationProductId);
        System.assertEquals(1, decompRule.Priority);
    }

    @isTest
    static void testCreateTechnicalProducts_MultipleProducts() {
        List<Product2> commercials = [SELECT Id, ProductCode FROM Product2];

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        Integer counter = 1;
        for (Product2 commercial : commercials) {
            RCATechnicalProductService.TechnicalProductRequest request =
                new RCATechnicalProductService.TechnicalProductRequest();
            request.commercialProductId = commercial.Id;
            request.commercialProductCode = commercial.ProductCode;
            request.technicalProductName = 'Tech Product ' + counter;
            request.technicalProductCode = 'TECH-' + counter;
            request.decompRulePriority = counter;
            request.isActive = true;
            requests.add(request);
            counter++;
        }

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(commercials.size(), result.totalSucceeded,
            'Should have created technical products for all commercial products');
        System.assertEquals(0, result.totalFailed, 'Should have 0 failures');

        // Verify all products were created
        List<Product2> techProducts = [
            SELECT Id FROM Product2 WHERE ProductCode LIKE 'TECH-%'
        ];
        System.assertEquals(commercials.size(), techProducts.size());

        // Verify all decomp rules were created
        List<ProductFulfillmentDecompRule> rules = [
            SELECT Id FROM ProductFulfillmentDecompRule WHERE SourceProductId IN :commercials
        ];
        System.assertEquals(commercials.size(), rules.size());
    }

    @isTest
    static void testCreateTechnicalProducts_WithOptionalFields() {
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Full Technical Product';
        request.technicalProductCode = 'FULL-TECH-001';
        request.technicalProductDescription = 'Full description';
        request.family = 'Services';
        request.decompRulePriority = 5;
        request.isActive = true;
        // Note: productClassificationId and rulesetId would be set if those records exist
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded);

        Product2 techProduct = [
            SELECT Id, Name, ProductCode, Description, Family
            FROM Product2
            WHERE ProductCode = 'FULL-TECH-001'
        ];
        System.assertEquals('Full Technical Product', techProduct.Name);
        System.assertEquals('Full description', techProduct.Description);
        System.assertEquals('Services', techProduct.Family);
    }

    @isTest
    static void testCreateTechnicalProducts_PartialFailure() {
        // Get two different commercial products - service uses commercialProductId as key
        Product2 commercial1 = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];
        Product2 commercial2 = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-STD-001' LIMIT 1];

        // First, create a product with a code we'll try to duplicate
        Product2 existingTech = new Product2(
            Name = 'Existing Tech',
            ProductCode = 'EXISTING-TECH-CODE',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert existingTech;

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        // Valid request for first commercial product
        RCATechnicalProductService.TechnicalProductRequest validRequest =
            new RCATechnicalProductService.TechnicalProductRequest();
        validRequest.commercialProductId = commercial1.Id;
        validRequest.commercialProductCode = commercial1.ProductCode;
        validRequest.technicalProductName = 'Valid Tech';
        validRequest.technicalProductCode = 'VALID-TECH-CODE';
        validRequest.decompRulePriority = 1;
        requests.add(validRequest);

        // Invalid request for second commercial product - duplicate product code
        RCATechnicalProductService.TechnicalProductRequest invalidRequest =
            new RCATechnicalProductService.TechnicalProductRequest();
        invalidRequest.commercialProductId = commercial2.Id;
        invalidRequest.commercialProductCode = commercial2.ProductCode;
        invalidRequest.technicalProductName = 'Duplicate Code Tech';
        invalidRequest.technicalProductCode = 'EXISTING-TECH-CODE'; // This already exists
        invalidRequest.decompRulePriority = 2;
        requests.add(invalidRequest);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        // The service should handle the duplicate gracefully
        // Each request uses a different commercialProductId so we should get 2 results
        System.assert(result.results.size() == 2, 'Should have results for both requests');
    }

    @isTest
    static void testWrapperClasses() {
        // Test TechnicalProductRequest
        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = 'testId';
        request.commercialProductName = 'Commercial Name';
        request.commercialProductCode = 'COMM-CODE';
        request.technicalProductName = 'Test Name';
        request.technicalProductCode = 'TEST-CODE';
        request.technicalProductDescription = 'Test Description';
        request.family = 'Test Family';
        request.decompRulePriority = 1;
        request.isActive = true;
        request.productClassificationId = 'classId';
        request.rulesetId = 'rulesetId';

        System.assertEquals('testId', request.commercialProductId);
        System.assertEquals('Test Name', request.technicalProductName);
        System.assertEquals('TEST-CODE', request.technicalProductCode);
        System.assertEquals('Test Family', request.family);

        // Test TechnicalProductResult
        RCATechnicalProductService.TechnicalProductResult result =
            new RCATechnicalProductService.TechnicalProductResult();
        result.success = true;
        result.commercialProductId = 'commId';
        result.commercialProductCode = 'COMM-CODE';
        result.technicalProductId = 'techId';
        result.technicalProductCode = 'TECH-CODE';
        result.decompRuleId = 'ruleId';
        result.errorMessage = null;
        result.warnings = new List<String>();

        System.assertEquals(true, result.success);
        System.assertEquals('techId', result.technicalProductId);

        // Test BatchCreationResult
        RCATechnicalProductService.BatchCreationResult batchResult =
            new RCATechnicalProductService.BatchCreationResult();
        batchResult.totalRequested = 7;
        batchResult.totalSucceeded = 5;
        batchResult.totalFailed = 2;
        batchResult.results = new List<RCATechnicalProductService.TechnicalProductResult>();
        batchResult.batchId = 'BATCH-123';

        System.assertEquals(7, batchResult.totalRequested);
        System.assertEquals(5, batchResult.totalSucceeded);
        System.assertEquals(2, batchResult.totalFailed);
    }

    @isTest
    static void testGetExistingDecompRules() {
        Product2 commercial = [SELECT Id FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        // Create a technical product and decomp rule
        Product2 techProduct = new Product2(
            Name = 'Existing Tech Product',
            ProductCode = 'EXIST-TECH-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert techProduct;

        ProductFulfillmentDecompRule rule = new ProductFulfillmentDecompRule(
            Name = 'TEST-BUNDLE-001 to EXIST-TECH-001',
            SourceProductId = commercial.Id,
            DestinationProductId = techProduct.Id,
            Priority = 1
        );
        insert rule;

        Test.startTest();
        List<ProductFulfillmentDecompRule> rules =
            RCATechnicalProductService.getExistingDecompRules(new List<String>{ commercial.Id });
        Test.stopTest();

        System.assertEquals(1, rules.size(), 'Should return 1 decomp rule');
        System.assertEquals(commercial.Id, rules[0].SourceProductId);
        System.assertEquals(techProduct.Id, rules[0].DestinationProductId);
    }

    @isTest
    static void testGetProductClassifications() {
        Test.startTest();
        List<ProductClassification> classifications = RCATechnicalProductService.getProductClassifications();
        Test.stopTest();

        // Just verify it doesn't throw an error - classifications may or may not exist
        System.assertNotEquals(null, classifications);
    }

    @isTest
    static void testGetRulesets() {
        Test.startTest();
        List<Ruleset> rulesets = RCATechnicalProductService.getRulesets();
        Test.stopTest();

        // Just verify it doesn't throw an error - rulesets may or may not exist
        System.assertNotEquals(null, rulesets);
    }

    @isTest
    static void testCreateTechnicalProducts_InheritsWorkdayFields() {
        // This test verifies that Workday-related fields are inherited from commercial product
        // Note: Workday_Sales_Item_ID__c is NOT copied because it has a unique constraint in Salesforce
        Product2 commercial = [
            SELECT Id, ProductCode, Workday_Sales_Item_ID__c, Rev_Category__c, Finance_Business_Unit__c, Fortra_Product_Type__c
            FROM Product2
            WHERE ProductCode = 'TEST-BUNDLE-001'
            LIMIT 1
        ];

        // Verify commercial product has Workday fields set
        System.assertEquals('WD-SALES-123', commercial.Workday_Sales_Item_ID__c, 'Commercial product should have Workday Sales Item ID');

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Workday Test - Technical';
        request.technicalProductCode = 'WORKDAY-TEST-TECH';
        request.technicalProductDescription = 'Technical product to test Workday field inheritance';
        request.family = 'Software';
        request.decompRulePriority = 1;
        request.isActive = true;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assertNotEquals(null, result.results[0].technicalProductId, 'Should have technical product ID');

        // Verify the technical product inherited Workday-related fields
        // Note: Workday_Sales_Item_ID__c is NOT copied due to unique constraint
        Product2 techProduct = [
            SELECT Id, Name, ProductCode,
                   Workday_Sales_Item_ID__c, Rev_Category__c, Finance_Business_Unit__c, Fortra_Product_Type__c
            FROM Product2
            WHERE Id = :result.results[0].technicalProductId
        ];

        System.assertEquals('Workday Test - Technical', techProduct.Name);
        System.assertEquals('WORKDAY-TEST-TECH', techProduct.ProductCode);

        // Verify Workday-related fields were inherited (except Workday_Sales_Item_ID__c which has unique constraint)
        System.assertEquals(null, techProduct.Workday_Sales_Item_ID__c,
            'Technical product should NOT inherit Workday Sales Item ID (unique constraint)');
        System.assertEquals('Subscription', techProduct.Rev_Category__c,
            'Technical product should inherit Rev Category');
        System.assertEquals('BU-001', techProduct.Finance_Business_Unit__c,
            'Technical product should inherit Finance Business Unit');
        System.assertEquals('Software', techProduct.Fortra_Product_Type__c,
            'Technical product should inherit Fortra Product Type');
    }

    // ============================================================================
    // Tests for Related Record Creation (ProductSellingModelOption, PricebookEntry, ProductCategoryProduct)
    // ============================================================================

    @isTest
    static void testCreateTechnicalProducts_CreatesSellingModelOptions() {
        // Test that ProductSellingModelOptions are inherited from commercial product
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-STD-001' LIMIT 1];

        // Verify commercial product has a PSMO
        List<ProductSellingModelOption> commercialPsmos = [
            SELECT Id, ProductSellingModelId, IsDefault
            FROM ProductSellingModelOption
            WHERE Product2Id = :commercial.Id
        ];
        System.assertEquals(1, commercialPsmos.size(), 'Commercial product should have 1 PSMO');

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'PSMO Test - Technical';
        request.technicalProductCode = 'PSMO-TEST-TECH';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assert(result.results[0].success, 'Result should be successful');
        System.assertEquals(1, result.results[0].sellingModelOptionsCreated,
            'Should report 1 selling model option created');

        // Verify the technical product has a PSMO
        List<ProductSellingModelOption> techPsmos = [
            SELECT Id, ProductSellingModelId, IsDefault
            FROM ProductSellingModelOption
            WHERE Product2Id = :result.results[0].technicalProductId
        ];
        System.assertEquals(1, techPsmos.size(), 'Technical product should have 1 PSMO');
        System.assertEquals(commercialPsmos[0].ProductSellingModelId, techPsmos[0].ProductSellingModelId,
            'PSMO should reference the same selling model');
        System.assertEquals(commercialPsmos[0].IsDefault, techPsmos[0].IsDefault,
            'PSMO IsDefault should match commercial');
    }

    @isTest
    static void testCreateTechnicalProducts_CreatesPricebookEntries() {
        // Test that PricebookEntries are copied from commercial product
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-STD-001' LIMIT 1];

        // Verify commercial product has PBEs
        List<PricebookEntry> commercialPbes = [
            SELECT Id, Pricebook2Id, UnitPrice, Pricebook2.IsStandard
            FROM PricebookEntry
            WHERE Product2Id = :commercial.Id
        ];
        System.assertEquals(2, commercialPbes.size(), 'Commercial product should have 2 PBEs (standard + custom)');

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'PBE Test - Technical';
        request.technicalProductCode = 'PBE-TEST-TECH';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assert(result.results[0].success, 'Result should be successful');
        System.assertEquals(2, result.results[0].pricebookEntriesCreated,
            'Should report 2 pricebook entries created');

        // Verify the technical product has PBEs with correct prices
        List<PricebookEntry> techPbes = [
            SELECT Id, Pricebook2Id, UnitPrice, Pricebook2.IsStandard
            FROM PricebookEntry
            WHERE Product2Id = :result.results[0].technicalProductId
        ];
        System.assertEquals(2, techPbes.size(), 'Technical product should have 2 PBEs');

        // Verify prices match
        for (PricebookEntry techPbe : techPbes) {
            for (PricebookEntry commPbe : commercialPbes) {
                if (techPbe.Pricebook2Id == commPbe.Pricebook2Id) {
                    System.assertEquals(commPbe.UnitPrice, techPbe.UnitPrice,
                        'PBE UnitPrice should match commercial product');
                }
            }
        }
    }

    @isTest
    static void testCreateTechnicalProducts_CreatesCategoryProducts() {
        // Test that ProductCategoryProducts are created for same categories
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-STD-001' LIMIT 1];

        // Verify commercial product has a category assignment
        List<ProductCategoryProduct> commercialPcps = [
            SELECT Id, ProductCategoryId
            FROM ProductCategoryProduct
            WHERE ProductId = :commercial.Id
        ];
        System.assertEquals(1, commercialPcps.size(), 'Commercial product should have 1 category assignment');

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'PCP Test - Technical';
        request.technicalProductCode = 'PCP-TEST-TECH';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assert(result.results[0].success, 'Result should be successful');
        System.assertEquals(1, result.results[0].categoryProductsCreated,
            'Should report 1 category product created');

        // Verify the technical product has the same category
        List<ProductCategoryProduct> techPcps = [
            SELECT Id, ProductCategoryId
            FROM ProductCategoryProduct
            WHERE ProductId = :result.results[0].technicalProductId
        ];
        System.assertEquals(1, techPcps.size(), 'Technical product should have 1 category assignment');
        System.assertEquals(commercialPcps[0].ProductCategoryId, techPcps[0].ProductCategoryId,
            'Technical product should be in same category as commercial');
    }

    @isTest
    static void testCreateTechnicalProducts_MultipleSellingModels() {
        // Test that multiple PSMOs are inherited (bundle product has 2)
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        // Verify commercial product has 2 PSMOs
        List<ProductSellingModelOption> commercialPsmos = [
            SELECT Id, ProductSellingModelId, IsDefault
            FROM ProductSellingModelOption
            WHERE Product2Id = :commercial.Id
        ];
        System.assertEquals(2, commercialPsmos.size(), 'Commercial product should have 2 PSMOs');

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Multi PSMO - Technical';
        request.technicalProductCode = 'MULTI-PSMO-TECH';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assertEquals(2, result.results[0].sellingModelOptionsCreated,
            'Should report 2 selling model options created');

        // Verify the technical product has both PSMOs
        List<ProductSellingModelOption> techPsmos = [
            SELECT Id, ProductSellingModelId, IsDefault
            FROM ProductSellingModelOption
            WHERE Product2Id = :result.results[0].technicalProductId
        ];
        System.assertEquals(2, techPsmos.size(), 'Technical product should have 2 PSMOs');
    }

    @isTest
    static void testCreateTechnicalProducts_MultiplePricebooks() {
        // Test that both standard and custom PBEs are created (bundle product has both)
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Multi PBE - Technical';
        request.technicalProductCode = 'MULTI-PBE-TECH';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assertEquals(2, result.results[0].pricebookEntriesCreated,
            'Should report 2 pricebook entries created (standard + custom)');

        // Verify the technical product has both PBEs (standard + custom)
        List<PricebookEntry> techPbes = [
            SELECT Id, Pricebook2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id = :result.results[0].technicalProductId
        ];
        System.assertEquals(2, techPbes.size(), 'Technical product should have 2 PBEs');

        // Verify both PBEs have valid prices (copied from commercial product)
        Set<Id> pricebookIds = new Set<Id>();
        for (PricebookEntry pbe : techPbes) {
            System.assertNotEquals(null, pbe.UnitPrice, 'PBE should have a price');
            System.assert(pbe.UnitPrice > 0, 'PBE price should be positive');
            pricebookIds.add(pbe.Pricebook2Id);
        }
        // Verify we have entries in 2 different pricebooks
        System.assertEquals(2, pricebookIds.size(), 'Should have PBEs in 2 different pricebooks');
    }

    @isTest
    static void testCreateTechnicalProducts_MultipleCategories() {
        // Test that multiple category assignments are created (bundle product has 2)
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        // Verify commercial product has 2 category assignments
        List<ProductCategoryProduct> commercialPcps = [
            SELECT Id, ProductCategoryId
            FROM ProductCategoryProduct
            WHERE ProductId = :commercial.Id
        ];
        System.assertEquals(2, commercialPcps.size(), 'Commercial product should have 2 category assignments');

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Multi Cat - Technical';
        request.technicalProductCode = 'MULTI-CAT-TECH';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assertEquals(2, result.results[0].categoryProductsCreated,
            'Should report 2 category products created');

        // Verify the technical product has both category assignments
        List<ProductCategoryProduct> techPcps = [
            SELECT Id, ProductCategoryId
            FROM ProductCategoryProduct
            WHERE ProductId = :result.results[0].technicalProductId
        ];
        System.assertEquals(2, techPcps.size(), 'Technical product should have 2 category assignments');
    }

    @isTest
    static void testCreateTechnicalProducts_NoRelatedRecords() {
        // Test that creation succeeds even when commercial product has no related records
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BARE-001' LIMIT 1];

        // Verify commercial product has no related records
        System.assertEquals(0, [SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id = :commercial.Id],
            'Bare product should have no PSMOs');
        System.assertEquals(0, [SELECT COUNT() FROM PricebookEntry WHERE Product2Id = :commercial.Id],
            'Bare product should have no PBEs');
        System.assertEquals(0, [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId = :commercial.Id],
            'Bare product should have no PCPs');

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Bare Product - Technical';
        request.technicalProductCode = 'BARE-TECH';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assert(result.results[0].success, 'Result should be successful');
        System.assertEquals(0, result.results[0].sellingModelOptionsCreated, 'Should have 0 PSMOs created');
        System.assertEquals(0, result.results[0].pricebookEntriesCreated, 'Should have 0 PBEs created');
        System.assertEquals(0, result.results[0].categoryProductsCreated, 'Should have 0 PCPs created');

        // Verify technical product exists
        System.assertNotEquals(null, result.results[0].technicalProductId, 'Should have technical product ID');
    }

    @isTest
    static void testCreateTechnicalProducts_AllRelatedRecords() {
        // Test comprehensive creation with all related record types
        Product2 commercial = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001' LIMIT 1];

        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            new List<RCATechnicalProductService.TechnicalProductRequest>();

        RCATechnicalProductService.TechnicalProductRequest request =
            new RCATechnicalProductService.TechnicalProductRequest();
        request.commercialProductId = commercial.Id;
        request.commercialProductCode = commercial.ProductCode;
        request.technicalProductName = 'Full Related - Technical';
        request.technicalProductCode = 'FULL-RELATED-TECH';
        request.decompRulePriority = 1;
        requests.add(request);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductService.createTechnicalProducts(requests);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 successful creation');
        System.assert(result.results[0].success, 'Result should be successful');

        // Bundle product has: 2 PSMOs, 2 PBEs, 2 PCPs
        System.assertEquals(2, result.results[0].sellingModelOptionsCreated, 'Should have 2 PSMOs created');
        System.assertEquals(2, result.results[0].pricebookEntriesCreated, 'Should have 2 PBEs created');
        System.assertEquals(2, result.results[0].categoryProductsCreated, 'Should have 2 PCPs created');

        // Verify all records exist
        Id techProductId = result.results[0].technicalProductId;
        System.assertEquals(2, [SELECT COUNT() FROM ProductSellingModelOption WHERE Product2Id = :techProductId]);
        System.assertEquals(2, [SELECT COUNT() FROM PricebookEntry WHERE Product2Id = :techProductId]);
        System.assertEquals(2, [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId = :techProductId]);
    }

    @isTest
    static void testWrapperClasses_RelatedRecordFields() {
        // Test that the new TechnicalProductResult fields work correctly
        RCATechnicalProductService.TechnicalProductResult result =
            new RCATechnicalProductService.TechnicalProductResult();

        // Verify default values
        System.assertEquals(0, result.sellingModelOptionsCreated, 'Default should be 0');
        System.assertEquals(0, result.pricebookEntriesCreated, 'Default should be 0');
        System.assertEquals(0, result.categoryProductsCreated, 'Default should be 0');

        // Test setting values
        result.sellingModelOptionsCreated = 5;
        result.pricebookEntriesCreated = 10;
        result.categoryProductsCreated = 3;

        System.assertEquals(5, result.sellingModelOptionsCreated);
        System.assertEquals(10, result.pricebookEntriesCreated);
        System.assertEquals(3, result.categoryProductsCreated);
    }
}