/**
 * @description Test class for RCAProductCreationService
 * Tests bulk product creation, bundle support, and related record creation
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
@isTest
private class RCAProductCreationServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create test ProductSellingModels
        List<ProductSellingModel> sellingModels = new List<ProductSellingModel>{
            new ProductSellingModel(Name = 'Test OneTime', SellingModelType = 'OneTime', Status = 'Active'),
            new ProductSellingModel(Name = 'Test TermDefined', SellingModelType = 'TermDefined', Status = 'Active', PricingTerm = 12, PricingTermUnit = 'Months')
        };
        insert sellingModels;

        // Create test ProductCatalog
        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog');
        insert catalog;

        // Create test ProductCategory
        ProductCategory category = new ProductCategory(Name = 'Test Category', CatalogId = catalog.Id);
        insert category;

        // Create test child products for bundle testing
        List<Product2> childProducts = new List<Product2>{
            new Product2(Name = 'Child Product 1', ProductCode = 'CHILD-001', IsActive = true),
            new Product2(Name = 'Child Product 2', ProductCode = 'CHILD-002', IsActive = true)
        };
        insert childProducts;

        // Create standard pricebook entries for child products
        Id stdPbId = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = new List<PricebookEntry>{
            new PricebookEntry(Product2Id = childProducts[0].Id, Pricebook2Id = stdPbId, UnitPrice = 10, IsActive = true),
            new PricebookEntry(Product2Id = childProducts[1].Id, Pricebook2Id = stdPbId, UnitPrice = 20, IsActive = true)
        };
        insert pbes;
    }

    @isTest
    static void testCreateSimpleProduct() {
        // Get test data
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Test OneTime' LIMIT 1];
        ProductCategory cat = [SELECT Id FROM ProductCategory WHERE Name = 'Test Category' LIMIT 1];
        ProductCatalog catalog = [SELECT Id FROM ProductCatalog WHERE Name = 'Test Catalog' LIMIT 1];

        // Create request
        RCAProductCreationService.ProductRequest req = new RCAProductCreationService.ProductRequest();
        req.name = 'Test Simple Product';
        req.productCode = 'TEST-SIMPLE-001';
        req.description = 'Test product description';
        req.family = 'Software';
        req.isActive = true;
        req.unitPrice = 99.99;
        req.sellingModelIds = new List<String>{ psm.Id };
        req.categoryId = cat.Id;
        req.catalogId = catalog.Id;
        req.pricebookIds = new List<String>{ Test.getStandardPricebookId() };

        Test.startTest();
        RCAProductCreationService.BatchCreationResult result = RCAProductCreationService.createProducts(
            new List<RCAProductCreationService.ProductRequest>{ req }
        );
        Test.stopTest();

        // Assertions
        System.assertEquals(1, result.totalRequested, 'Should have 1 product requested');
        System.assertEquals(1, result.totalSucceeded, 'Should have 1 product succeeded');
        System.assertEquals(0, result.totalFailed, 'Should have 0 products failed');
        System.assertNotEquals(null, result.batchId, 'Batch ID should be generated');

        // Verify product was created
        List<Product2> products = [SELECT Id, Name, ProductCode FROM Product2 WHERE ProductCode = 'TEST-SIMPLE-001'];
        System.assertEquals(1, products.size(), 'Product should be created');
        System.assertEquals('Test Simple Product', products[0].Name, 'Product name should match');

        // Verify ProductSellingModelOption was created
        List<ProductSellingModelOption> psmos = [SELECT Id FROM ProductSellingModelOption WHERE Product2Id = :products[0].Id];
        System.assertEquals(1, psmos.size(), 'ProductSellingModelOption should be created');

        // Verify PricebookEntry was created
        List<PricebookEntry> pbes = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2Id = :products[0].Id];
        System.assert(pbes.size() >= 1, 'PricebookEntry should be created');
    }

    @isTest
    static void testCreateBundleProduct() {
        // Get test data
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Test TermDefined' LIMIT 1];

        // Create bundle request
        RCAProductCreationService.ProductRequest req = new RCAProductCreationService.ProductRequest();
        req.name = 'Test Bundle Product';
        req.productCode = 'TEST-BUNDLE-001';
        req.description = 'Test bundle description';
        req.productType = 'Bundle';
        req.isActive = true;
        req.unitPrice = 199.99;
        req.sellingModelIds = new List<String>{ psm.Id };

        // Add bundle components
        RCAProductCreationService.BundleComponent comp1 = new RCAProductCreationService.BundleComponent();
        comp1.childProductCode = 'CHILD-001';
        comp1.groupName = 'Test Group';
        comp1.minQuantity = 1;
        comp1.maxQuantity = 5;
        comp1.defaultQuantity = 1;
        comp1.isRequired = true;
        comp1.sortOrder = 1;

        RCAProductCreationService.BundleComponent comp2 = new RCAProductCreationService.BundleComponent();
        comp2.childProductCode = 'CHILD-002';
        comp2.groupName = 'Test Group';
        comp2.minQuantity = 0;
        comp2.maxQuantity = 10;
        comp2.defaultQuantity = 2;
        comp2.isRequired = false;
        comp2.sortOrder = 2;

        req.bundleComponents = new List<RCAProductCreationService.BundleComponent>{ comp1, comp2 };

        Test.startTest();
        RCAProductCreationService.BatchCreationResult result = RCAProductCreationService.createProducts(
            new List<RCAProductCreationService.ProductRequest>{ req }
        );
        Test.stopTest();

        // Assertions
        System.assertEquals(1, result.totalSucceeded, 'Bundle product should be created successfully');

        // Verify bundle product was created
        List<Product2> bundles = [SELECT Id, Type FROM Product2 WHERE ProductCode = 'TEST-BUNDLE-001'];
        System.assertEquals(1, bundles.size(), 'Bundle product should exist');

        // Verify ProductComponentGroup was created
        List<ProductComponentGroup> groups = [SELECT Id, Name FROM ProductComponentGroup WHERE ParentProductId = :bundles[0].Id];
        System.assertEquals(1, groups.size(), 'ProductComponentGroup should be created');
        System.assertEquals('Test Group', groups[0].Name, 'Group name should match');

        // Verify ProductRelatedComponents were created
        List<ProductRelatedComponent> components = [SELECT Id FROM ProductRelatedComponent WHERE ParentProductId = :bundles[0].Id];
        System.assertEquals(2, components.size(), 'Two bundle components should be created');
    }

    @isTest
    static void testBulkProductCreation() {
        // Get test data
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Test OneTime' LIMIT 1];

        // Create multiple product requests
        List<RCAProductCreationService.ProductRequest> requests = new List<RCAProductCreationService.ProductRequest>();

        for (Integer i = 1; i <= 50; i++) {
            RCAProductCreationService.ProductRequest req = new RCAProductCreationService.ProductRequest();
            req.name = 'Bulk Product ' + i;
            req.productCode = 'BULK-' + String.valueOf(i).leftPad(3, '0');
            req.isActive = true;
            req.unitPrice = 100 + i;
            req.sellingModelIds = new List<String>{ psm.Id };
            requests.add(req);
        }

        Test.startTest();
        RCAProductCreationService.BatchCreationResult result = RCAProductCreationService.createProducts(requests);
        Test.stopTest();

        // Assertions
        System.assertEquals(50, result.totalRequested, 'Should have 50 products requested');
        System.assertEquals(50, result.totalSucceeded, 'Should have 50 products succeeded');
        System.assertEquals(0, result.totalFailed, 'Should have 0 products failed');

        // Verify all products were created
        Integer count = [SELECT COUNT() FROM Product2 WHERE ProductCode LIKE 'BULK-%'];
        System.assertEquals(50, count, 'All 50 products should be created');
    }

    @isTest
    static void testValidateRequests() {
        // Create requests with various validation issues
        List<RCAProductCreationService.ProductRequest> requests = new List<RCAProductCreationService.ProductRequest>();

        // Request without name
        RCAProductCreationService.ProductRequest req1 = new RCAProductCreationService.ProductRequest();
        req1.productCode = 'VALID-001';
        requests.add(req1);

        // Request without product code
        RCAProductCreationService.ProductRequest req2 = new RCAProductCreationService.ProductRequest();
        req2.name = 'Valid Name';
        requests.add(req2);

        // Duplicate product codes
        RCAProductCreationService.ProductRequest req3 = new RCAProductCreationService.ProductRequest();
        req3.name = 'Test 3';
        req3.productCode = 'DUPLICATE-001';
        requests.add(req3);

        RCAProductCreationService.ProductRequest req4 = new RCAProductCreationService.ProductRequest();
        req4.name = 'Test 4';
        req4.productCode = 'DUPLICATE-001';
        requests.add(req4);

        // Existing product code
        RCAProductCreationService.ProductRequest req5 = new RCAProductCreationService.ProductRequest();
        req5.name = 'Test 5';
        req5.productCode = 'CHILD-001'; // Already exists from test setup
        requests.add(req5);

        Test.startTest();
        List<String> errors = RCAProductCreationService.validateRequests(requests);
        Test.stopTest();

        // Assertions
        System.assert(errors.size() >= 4, 'Should have at least 4 validation errors');

        Boolean hasNameError = false;
        Boolean hasCodeError = false;
        Boolean hasDuplicateError = false;
        Boolean hasExistingError = false;

        for (String error : errors) {
            if (error.contains('name is required')) hasNameError = true;
            if (error.contains('Product code is required')) hasCodeError = true;
            if (error.contains('Duplicate product code')) hasDuplicateError = true;
            if (error.contains('already exists')) hasExistingError = true;
        }

        System.assert(hasNameError, 'Should have name required error');
        System.assert(hasCodeError, 'Should have code required error');
        System.assert(hasDuplicateError, 'Should have duplicate code error');
        System.assert(hasExistingError, 'Should have existing code error');
    }

    @isTest
    static void testGetActiveSellingModels() {
        Test.startTest();
        List<ProductSellingModel> models = RCAProductCreationService.getActiveSellingModels();
        Test.stopTest();

        System.assert(models.size() >= 2, 'Should return at least 2 selling models');
    }

    @isTest
    static void testGetProductCatalogs() {
        Test.startTest();
        List<ProductCatalog> catalogs = RCAProductCreationService.getProductCatalogs();
        Test.stopTest();

        System.assert(catalogs.size() >= 1, 'Should return at least 1 catalog');
    }

    @isTest
    static void testGetCategoriesByCatalog() {
        ProductCatalog catalog = [SELECT Id FROM ProductCatalog WHERE Name = 'Test Catalog' LIMIT 1];

        Test.startTest();
        List<ProductCategory> categories = RCAProductCreationService.getCategoriesByCatalog(catalog.Id);
        List<ProductCategory> allCategories = RCAProductCreationService.getCategoriesByCatalog(null);
        Test.stopTest();

        System.assert(categories.size() >= 1, 'Should return at least 1 category for catalog');
        System.assert(allCategories.size() >= 1, 'Should return categories when no catalog specified');
    }

    @isTest
    static void testGetActivePricebooks() {
        Test.startTest();
        List<Pricebook2> pricebooks = RCAProductCreationService.getActivePricebooks();
        Test.stopTest();

        System.assert(pricebooks.size() >= 1, 'Should return at least 1 pricebook (standard)');
    }

    @isTest
    static void testProductRequestDefaults() {
        RCAProductCreationService.ProductRequest req = new RCAProductCreationService.ProductRequest();

        System.assertEquals(true, req.isActive, 'Default isActive should be true');
        System.assertNotEquals(null, req.sellingModelIds, 'sellingModelIds should be initialized');
        System.assertNotEquals(null, req.pricebookIds, 'pricebookIds should be initialized');
        System.assertNotEquals(null, req.bundleComponents, 'bundleComponents should be initialized');
        System.assertNotEquals(null, req.customFields, 'customFields should be initialized');
    }

    @isTest
    static void testBundleComponentDefaults() {
        RCAProductCreationService.BundleComponent comp = new RCAProductCreationService.BundleComponent();

        System.assertEquals(0, comp.minQuantity, 'Default minQuantity should be 0');
        System.assertEquals(999, comp.maxQuantity, 'Default maxQuantity should be 999');
        System.assertEquals(1, comp.defaultQuantity, 'Default defaultQuantity should be 1');
        System.assertEquals(false, comp.isRequired, 'Default isRequired should be false');
        System.assertEquals(0, comp.sortOrder, 'Default sortOrder should be 0');
    }

    @isTest
    static void testProductCreationResultDefaults() {
        RCAProductCreationService.ProductCreationResult result = new RCAProductCreationService.ProductCreationResult();

        System.assertEquals(false, result.success, 'Default success should be false');
        System.assertNotEquals(null, result.warnings, 'warnings should be initialized');
        System.assertEquals(0, result.sellingModelOptionsCreated, 'Default PSMO count should be 0');
        System.assertEquals(0, result.pricebookEntriesCreated, 'Default PBE count should be 0');
        System.assertEquals(0, result.bundleComponentsCreated, 'Default component count should be 0');
    }

    @isTest
    static void testBatchCreationResultDefaults() {
        RCAProductCreationService.BatchCreationResult result = new RCAProductCreationService.BatchCreationResult();

        System.assertEquals(0, result.totalRequested, 'Default totalRequested should be 0');
        System.assertEquals(0, result.totalSucceeded, 'Default totalSucceeded should be 0');
        System.assertEquals(0, result.totalFailed, 'Default totalFailed should be 0');
        System.assertNotEquals(null, result.results, 'results should be initialized');
    }

    @isTest
    static void testMixedSimpleAndBundleCreation() {
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Test OneTime' LIMIT 1];

        List<RCAProductCreationService.ProductRequest> requests = new List<RCAProductCreationService.ProductRequest>();

        // Simple product
        RCAProductCreationService.ProductRequest simpleReq = new RCAProductCreationService.ProductRequest();
        simpleReq.name = 'Mixed Simple Product';
        simpleReq.productCode = 'MIXED-SIMPLE-001';
        simpleReq.productType = 'Simple';
        simpleReq.sellingModelIds = new List<String>{ psm.Id };
        requests.add(simpleReq);

        // Bundle product
        RCAProductCreationService.ProductRequest bundleReq = new RCAProductCreationService.ProductRequest();
        bundleReq.name = 'Mixed Bundle Product';
        bundleReq.productCode = 'MIXED-BUNDLE-001';
        bundleReq.productType = 'Bundle';
        bundleReq.sellingModelIds = new List<String>{ psm.Id };

        RCAProductCreationService.BundleComponent comp = new RCAProductCreationService.BundleComponent();
        comp.childProductCode = 'CHILD-001';
        comp.groupName = 'Mixed Group';
        bundleReq.bundleComponents = new List<RCAProductCreationService.BundleComponent>{ comp };
        requests.add(bundleReq);

        Test.startTest();
        RCAProductCreationService.BatchCreationResult result = RCAProductCreationService.createProducts(requests);
        Test.stopTest();

        System.assertEquals(2, result.totalRequested, 'Should have 2 products requested');
        System.assertEquals(2, result.totalSucceeded, 'Should have 2 products succeeded');
    }

    @isTest
    static void testEmptyRequestList() {
        Test.startTest();
        RCAProductCreationService.BatchCreationResult result = RCAProductCreationService.createProducts(
            new List<RCAProductCreationService.ProductRequest>()
        );
        Test.stopTest();

        System.assertEquals(0, result.totalRequested, 'Should have 0 products requested');
        System.assertEquals(0, result.totalSucceeded, 'Should have 0 products succeeded');
        System.assertEquals(0, result.totalFailed, 'Should have 0 products failed');
    }

    @isTest
    static void testCustomFieldsSupport() {
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Test OneTime' LIMIT 1];

        RCAProductCreationService.ProductRequest req = new RCAProductCreationService.ProductRequest();
        req.name = 'Custom Field Product';
        req.productCode = 'CUSTOM-FIELD-001';
        req.sellingModelIds = new List<String>{ psm.Id };
        req.customFields = new Map<String, Object>{
            'Description' => 'Set via custom fields'
        };

        Test.startTest();
        RCAProductCreationService.BatchCreationResult result = RCAProductCreationService.createProducts(
            new List<RCAProductCreationService.ProductRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Product should be created');

        Product2 createdProduct = [SELECT Description FROM Product2 WHERE ProductCode = 'CUSTOM-FIELD-001'];
        System.assertEquals('Set via custom fields', createdProduct.Description, 'Custom field should be set');
    }
}