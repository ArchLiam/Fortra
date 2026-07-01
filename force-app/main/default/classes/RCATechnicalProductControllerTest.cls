/**
 * @description Test class for RCATechnicalProductController
 * Tests LWC controller methods for technical product creation UI
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
@isTest
private class RCATechnicalProductControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create commercial products (bundle products)
        List<Product2> products = new List<Product2>();

        Product2 bundleProduct1 = new Product2(
            Name = 'Enterprise Bundle',
            ProductCode = 'ENT-BUNDLE-001',
            Description = 'Enterprise software bundle',
            Family = 'Software',
            IsActive = true,
            Type = 'Bundle',
            DecompositionScope = 'Bundle',
            QuantityUnitOfMeasure = 'Each',
            // Workday integration fields
            Workday_Sales_Item_ID__c = 'WD-ENT-001',
            Rev_Category__c = 'Enterprise Subscription',
            Finance_Business_Unit__c = 'BU-ENTERPRISE',
            Fortra_Product_Type__c = 'Subscription'
        );
        products.add(bundleProduct1);

        Product2 bundleProduct2 = new Product2(
            Name = 'Professional Bundle',
            ProductCode = 'PRO-BUNDLE-001',
            Description = 'Professional software bundle',
            Family = 'Software',
            IsActive = true,
            Type = 'Bundle',
            DecompositionScope = 'Bundle',
            QuantityUnitOfMeasure = 'Each'
        );
        products.add(bundleProduct2);

        Product2 standardProduct = new Product2(
            Name = 'Standard Widget',
            ProductCode = 'STD-WIDGET-001',
            Description = 'Standard widget product',
            Family = 'Hardware',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        products.add(standardProduct);

        Product2 inactiveProduct = new Product2(
            Name = 'Inactive Product',
            ProductCode = 'INACTIVE-001',
            Description = 'This product is inactive',
            Family = 'Software',
            IsActive = false,
            Type = 'Bundle'
        );
        products.add(inactiveProduct);

        insert products;

        // Create an existing technical product linked to bundleProduct1
        Product2 existingTech = new Product2(
            Name = 'Enterprise Bundle - Technical',
            ProductCode = 'ENT-BUNDLE-001-TECH',
            Description = 'Existing technical product',
            Family = 'Software',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
            // No Type or DecompositionScope for technical products
        );
        insert existingTech;

        // Create decomposition rule linking them
        ProductFulfillmentDecompRule decompRule = new ProductFulfillmentDecompRule(
            Name = 'Enterprise Bundle Decomp Rule',
            SourceProductId = bundleProduct1.Id,
            DestinationProductId = existingTech.Id,
            Priority = 1
        );
        insert decompRule;
    }

    @isTest
    static void testSearchCommercialProducts_AllFilter() {
        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.searchCommercialProducts('Bundle', 'all');
        Test.stopTest();

        System.assert(results.size() >= 2, 'Should find at least 2 bundle products');

        // Verify wrapper properties are populated
        Boolean foundEnterprise = false;
        for (RCATechnicalProductController.CommercialProductWrapper wrapper : results) {
            if (wrapper.productCode == 'ENT-BUNDLE-001') {
                foundEnterprise = true;
                System.assertEquals('Enterprise Bundle', wrapper.name);
                System.assertEquals('Bundle', wrapper.productType);
                System.assertEquals(true, wrapper.isActive);
                System.assertEquals(true, wrapper.hasExistingTechnicalProducts,
                    'Enterprise bundle should have existing technical products');
                System.assertEquals(1, wrapper.existingTechProductCount);
            }
        }
        System.assert(foundEnterprise, 'Should find Enterprise Bundle');
    }

    @isTest
    static void testSearchCommercialProducts_BundleFilter() {
        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.searchCommercialProducts('Bundle', 'bundle');
        Test.stopTest();

        // Should only return products with Type = 'Bundle'
        for (RCATechnicalProductController.CommercialProductWrapper wrapper : results) {
            System.assertEquals('Bundle', wrapper.productType,
                'Bundle filter should only return Bundle type products');
        }
    }

    @isTest
    static void testSearchCommercialProducts_CommercialFilter() {
        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.searchCommercialProducts('Bundle', 'commercial');
        Test.stopTest();

        // Should return products with Type or DecompositionScope set
        for (RCATechnicalProductController.CommercialProductWrapper wrapper : results) {
            System.assert(
                wrapper.productType != null || wrapper.decompositionScope != null,
                'Commercial filter should only return products with Type or DecompositionScope'
            );
        }
    }

    @isTest
    static void testSearchCommercialProducts_ByProductCode() {
        Test.startTest();
        // Use exact code to avoid matching the tech product (ENT-BUNDLE-001-TECH)
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.searchCommercialProducts('ENT-BUNDLE-001', 'all');
        Test.stopTest();

        // Search by product code should find both commercial and tech product with this code prefix
        System.assert(results.size() >= 1, 'Should find at least 1 product by code');
        Boolean foundTarget = false;
        for (RCATechnicalProductController.CommercialProductWrapper wrapper : results) {
            if (wrapper.productCode == 'ENT-BUNDLE-001') {
                foundTarget = true;
                break;
            }
        }
        System.assert(foundTarget, 'Should find ENT-BUNDLE-001 product');
    }

    @isTest
    static void testSearchCommercialProducts_NoResults() {
        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.searchCommercialProducts('NONEXISTENT', 'all');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should find no products');
    }

    @isTest
    static void testSearchCommercialProducts_ExcludesInactive() {
        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.searchCommercialProducts('Inactive', 'all');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should not return inactive products');
    }

    @isTest
    static void testGetProductsByIds() {
        List<Product2> products = [SELECT Id FROM Product2 WHERE IsActive = true AND ProductCode LIKE '%BUNDLE%'];
        List<String> productIds = new List<String>();
        for (Product2 p : products) {
            productIds.add(p.Id);
        }

        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.getProductsByIds(productIds);
        Test.stopTest();

        System.assertEquals(productIds.size(), results.size(), 'Should return all requested products');

        // Verify existing technical products are loaded
        for (RCATechnicalProductController.CommercialProductWrapper wrapper : results) {
            if (wrapper.productCode == 'ENT-BUNDLE-001') {
                System.assertEquals(1, wrapper.existingTechnicalProducts.size(),
                    'Should have existing technical products populated');
                System.assertEquals('ENT-BUNDLE-001-TECH',
                    wrapper.existingTechnicalProducts[0].productCode);
            }
        }
    }

    @isTest
    static void testGetProductsByIds_EmptyList() {
        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.getProductsByIds(new List<String>());
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty input should return empty list');
    }

    @isTest
    static void testGetProductsByIds_NullList() {
        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.getProductsByIds(null);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Null input should return empty list');
    }

    @isTest
    static void testGetReferenceData() {
        Test.startTest();
        RCATechnicalProductController.ReferenceData refData =
            RCATechnicalProductController.getReferenceData();
        Test.stopTest();

        System.assertNotEquals(null, refData, 'Reference data should not be null');
        System.assertNotEquals(null, refData.productFamilies, 'Product families should not be null');
        System.assertNotEquals(null, refData.productClassifications, 'Product classifications should not be null');
        System.assertNotEquals(null, refData.rulesets, 'Rulesets should not be null');

        // Verify product families include at least some values
        // (depends on org configuration)
        System.assert(refData.productFamilies.size() >= 0, 'Product families list should be initialized');
    }

    @isTest
    static void testGetSuggestedTechnicalProduct() {
        Product2 commercial = [SELECT Id FROM Product2 WHERE ProductCode = 'PRO-BUNDLE-001' LIMIT 1];

        Test.startTest();
        RCATechnicalProductController.TechnicalProductSuggestion suggestion =
            RCATechnicalProductController.getSuggestedTechnicalProduct(commercial.Id);
        Test.stopTest();

        System.assertEquals('Professional Bundle - Technical', suggestion.suggestedName);
        System.assertEquals('PRO-BUNDLE-001-TECH', suggestion.suggestedCode);
        System.assert(suggestion.suggestedDescription.contains('Professional Bundle'));
        System.assertEquals('Software', suggestion.suggestedFamily);
    }

    @isTest
    static void testGetSuggestedTechnicalProduct_CodeConflict() {
        // ENT-BUNDLE-001-TECH already exists from test setup
        Product2 commercial = [SELECT Id FROM Product2 WHERE ProductCode = 'ENT-BUNDLE-001' LIMIT 1];

        Test.startTest();
        RCATechnicalProductController.TechnicalProductSuggestion suggestion =
            RCATechnicalProductController.getSuggestedTechnicalProduct(commercial.Id);
        Test.stopTest();

        // Should append a number since ENT-BUNDLE-001-TECH exists
        System.assertNotEquals('ENT-BUNDLE-001-TECH', suggestion.suggestedCode,
            'Should generate unique code when conflict exists');
        System.assert(suggestion.suggestedCode.startsWith('ENT-BUNDLE-001-TECH'),
            'Should be based on original code');
    }

    @isTest
    static void testGetBulkSuggestedTechnicalProducts() {
        List<Product2> products = [SELECT Id FROM Product2 WHERE IsActive = true AND ProductCode LIKE '%BUNDLE%'];
        List<String> productIds = new List<String>();
        for (Product2 p : products) {
            productIds.add(p.Id);
        }

        Test.startTest();
        Map<String, RCATechnicalProductController.TechnicalProductSuggestion> suggestions =
            RCATechnicalProductController.getBulkSuggestedTechnicalProducts(productIds);
        Test.stopTest();

        System.assertEquals(productIds.size(), suggestions.size(),
            'Should have suggestion for each product');

        // Verify no duplicate codes in suggestions
        Set<String> codes = new Set<String>();
        for (RCATechnicalProductController.TechnicalProductSuggestion suggestion : suggestions.values()) {
            System.assert(!codes.contains(suggestion.suggestedCode),
                'Bulk suggestions should not have duplicate codes');
            codes.add(suggestion.suggestedCode);
        }
    }

    @isTest
    static void testGetBulkSuggestedTechnicalProducts_EmptyList() {
        Test.startTest();
        Map<String, RCATechnicalProductController.TechnicalProductSuggestion> suggestions =
            RCATechnicalProductController.getBulkSuggestedTechnicalProducts(new List<String>());
        Test.stopTest();

        System.assertEquals(0, suggestions.size(), 'Empty input should return empty map');
    }

    @isTest
    static void testValidateRequests() {
        Product2 commercial = [SELECT Id FROM Product2 WHERE ProductCode = 'PRO-BUNDLE-001' LIMIT 1];

        List<Map<String, Object>> requests = new List<Map<String, Object>>();
        Map<String, Object> request = new Map<String, Object>();
        request.put('commercialProductId', commercial.Id);
        request.put('technicalProductName', 'Test Tech');
        request.put('technicalProductCode', 'TEST-TECH-VALIDATE');
        request.put('decompRulePriority', 1);
        requests.add(request);

        String requestsJson = JSON.serialize(requests);

        Test.startTest();
        List<String> errors = RCATechnicalProductController.validateRequests(requestsJson);
        Test.stopTest();

        System.assertEquals(0, errors.size(), 'Valid request should have no errors');
    }

    @isTest
    static void testCreateTechnicalProducts() {
        Product2 commercial = [SELECT Id FROM Product2 WHERE ProductCode = 'PRO-BUNDLE-001' LIMIT 1];

        List<Map<String, Object>> requests = new List<Map<String, Object>>();
        Map<String, Object> request = new Map<String, Object>();
        request.put('commercialProductId', commercial.Id);
        request.put('technicalProductName', 'Pro Bundle - Technical');
        request.put('technicalProductCode', 'PRO-BUNDLE-001-TECH-NEW');
        request.put('technicalProductDescription', 'Technical product');
        request.put('family', 'Software');
        request.put('decompRulePriority', 1);
        request.put('isActive', true);
        requests.add(request);

        String requestsJson = JSON.serialize(requests);

        Test.startTest();
        RCATechnicalProductService.BatchCreationResult result =
            RCATechnicalProductController.createTechnicalProducts(requestsJson);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Should have 1 success');
        System.assertEquals(0, result.totalFailed, 'Should have 0 failures');

        // Verify technical product was created
        List<Product2> techProducts = [
            SELECT Id, Name, ProductCode
            FROM Product2
            WHERE ProductCode = 'PRO-BUNDLE-001-TECH-NEW'
        ];
        System.assertEquals(1, techProducts.size(), 'Technical product should be created');

        // Verify decomp rule was created
        List<ProductFulfillmentDecompRule> rules = [
            SELECT Id
            FROM ProductFulfillmentDecompRule
            WHERE SourceProductId = :commercial.Id
            AND DestinationProductId = :techProducts[0].Id
        ];
        System.assertEquals(1, rules.size(), 'Decomp rule should be created');
    }

    @isTest
    static void testWrapperClasses() {
        // Test CommercialProductWrapper
        RCATechnicalProductController.CommercialProductWrapper wrapper =
            new RCATechnicalProductController.CommercialProductWrapper();
        wrapper.id = 'testId';
        wrapper.name = 'Test Product';
        wrapper.productCode = 'TEST-001';
        wrapper.description = 'Description';
        wrapper.family = 'Software';
        wrapper.productType = 'Bundle';
        wrapper.decompositionScope = 'Bundle';
        wrapper.isActive = true;
        wrapper.hasExistingTechnicalProducts = false;
        wrapper.existingTechProductCount = 0;
        wrapper.existingTechnicalProducts = new List<RCATechnicalProductController.TechnicalProductInfo>();
        // Workday integration fields
        wrapper.workdaySalesItemId = 'WD-TEST-001';
        wrapper.revCategory = 'Test Category';
        wrapper.financeBusinessUnit = 'BU-TEST';
        wrapper.fortraProductType = 'Test License';

        System.assertEquals('testId', wrapper.id);
        System.assertEquals('Test Product', wrapper.name);
        System.assertEquals('WD-TEST-001', wrapper.workdaySalesItemId);
        System.assertEquals('Test Category', wrapper.revCategory);
        System.assertEquals('BU-TEST', wrapper.financeBusinessUnit);
        System.assertEquals('Test License', wrapper.fortraProductType);

        // Test TechnicalProductInfo
        RCATechnicalProductController.TechnicalProductInfo techInfo =
            new RCATechnicalProductController.TechnicalProductInfo();
        techInfo.id = 'techId';
        techInfo.name = 'Tech Product';
        techInfo.productCode = 'TECH-001';
        techInfo.priority = 1;
        techInfo.decompRuleId = 'ruleId';

        System.assertEquals('techId', techInfo.id);
        System.assertEquals(1, techInfo.priority);

        // Test TechnicalProductSuggestion
        RCATechnicalProductController.TechnicalProductSuggestion suggestion =
            new RCATechnicalProductController.TechnicalProductSuggestion();
        suggestion.suggestedName = 'Suggested Name';
        suggestion.suggestedCode = 'SUGGESTED-CODE';
        suggestion.suggestedDescription = 'Suggested Description';
        suggestion.suggestedFamily = 'Family';
        // Workday integration fields
        suggestion.workdaySalesItemId = 'WD-SUGG-001';
        suggestion.revCategory = 'Suggested Category';
        suggestion.financeBusinessUnit = 'BU-SUGGESTED';
        suggestion.fortraProductType = 'Suggested License';

        System.assertEquals('Suggested Name', suggestion.suggestedName);
        System.assertEquals('SUGGESTED-CODE', suggestion.suggestedCode);
        System.assertEquals('WD-SUGG-001', suggestion.workdaySalesItemId);
        System.assertEquals('Suggested Category', suggestion.revCategory);

        // Test ReferenceData
        RCATechnicalProductController.ReferenceData refData =
            new RCATechnicalProductController.ReferenceData();
        refData.productClassifications = new List<ProductClassification>();
        refData.rulesets = new List<Ruleset>();
        refData.productFamilies = new List<String>{'Family1', 'Family2'};

        System.assertEquals(2, refData.productFamilies.size());
    }

    @isTest
    static void testSearchCommercialProducts_ReturnsWorkdayFields() {
        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.searchCommercialProducts('Enterprise Bundle', 'all');
        Test.stopTest();

        // Find the Enterprise Bundle product
        RCATechnicalProductController.CommercialProductWrapper enterpriseBundle = null;
        for (RCATechnicalProductController.CommercialProductWrapper wrapper : results) {
            if (wrapper.productCode == 'ENT-BUNDLE-001') {
                enterpriseBundle = wrapper;
                break;
            }
        }

        System.assertNotEquals(null, enterpriseBundle, 'Should find Enterprise Bundle');

        // Verify Workday fields are populated
        System.assertEquals('WD-ENT-001', enterpriseBundle.workdaySalesItemId,
            'Should return Workday Sales Item ID');
        System.assertEquals('Enterprise Subscription', enterpriseBundle.revCategory,
            'Should return Rev Category');
        System.assertEquals('BU-ENTERPRISE', enterpriseBundle.financeBusinessUnit,
            'Should return Finance Business Unit');
        System.assertEquals('Subscription', enterpriseBundle.fortraProductType,
            'Should return Fortra Product Type');
    }

    @isTest
    static void testGetProductsByIds_ReturnsWorkdayFields() {
        Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'ENT-BUNDLE-001' LIMIT 1];

        Test.startTest();
        List<RCATechnicalProductController.CommercialProductWrapper> results =
            RCATechnicalProductController.getProductsByIds(new List<String>{ product.Id });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 product');

        RCATechnicalProductController.CommercialProductWrapper wrapper = results[0];

        // Verify Workday fields are populated
        System.assertEquals('WD-ENT-001', wrapper.workdaySalesItemId,
            'Should return Workday Sales Item ID');
        System.assertEquals('Enterprise Subscription', wrapper.revCategory,
            'Should return Rev Category');
        System.assertEquals('BU-ENTERPRISE', wrapper.financeBusinessUnit,
            'Should return Finance Business Unit');
        System.assertEquals('Subscription', wrapper.fortraProductType,
            'Should return Fortra Product Type');
    }

    @isTest
    static void testGetSuggestedTechnicalProduct_IncludesWorkdayFields() {
        Product2 commercial = [SELECT Id FROM Product2 WHERE ProductCode = 'ENT-BUNDLE-001' LIMIT 1];

        Test.startTest();
        RCATechnicalProductController.TechnicalProductSuggestion suggestion =
            RCATechnicalProductController.getSuggestedTechnicalProduct(commercial.Id);
        Test.stopTest();

        // Verify Workday fields are inherited in suggestion
        System.assertEquals('WD-ENT-001', suggestion.workdaySalesItemId,
            'Suggestion should include Workday Sales Item ID from commercial product');
        System.assertEquals('Enterprise Subscription', suggestion.revCategory,
            'Suggestion should include Rev Category from commercial product');
        System.assertEquals('BU-ENTERPRISE', suggestion.financeBusinessUnit,
            'Suggestion should include Finance Business Unit from commercial product');
        System.assertEquals('Subscription', suggestion.fortraProductType,
            'Suggestion should include Fortra Product Type from commercial product');
    }
}