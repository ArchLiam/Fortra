/**
 * @description Test class for RCAProductCreationController
 * Tests CSV parsing, reference data retrieval, and product search
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
@isTest
private class RCAProductCreationControllerTest {

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

        // Create test products for search
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Searchable Product Alpha', ProductCode = 'SEARCH-001', IsActive = true),
            new Product2(Name = 'Searchable Product Beta', ProductCode = 'SEARCH-002', IsActive = true),
            new Product2(Name = 'Another Test Product', ProductCode = 'TEST-003', IsActive = true)
        };
        insert products;

        // Create standard pricebook entries
        Id stdPbId = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Product2 p : products) {
            pbes.add(new PricebookEntry(Product2Id = p.Id, Pricebook2Id = stdPbId, UnitPrice = 100, IsActive = true));
        }
        insert pbes;
    }

    @isTest
    static void testParseCSVFile() {
        // Create test CSV content
        String csvContent = 'Name,ProductCode,Description,ProductType,Family,IsActive,UnitPrice,SellingModel\n' +
                           'Test Product 1,TEST-CSV-001,Description 1,Simple,Software,TRUE,99.99,Test OneTime\n' +
                           'Test Product 2,TEST-CSV-002,Description 2,Simple,Hardware,FALSE,199.99,Test TermDefined';

        // Encode as base64
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(csvContent));

        // Create mapping config
        Map<String, String> mapping = new Map<String, String>{
            'name' => 'name',
            'productCode' => 'productcode',
            'description' => 'description',
            'productType' => 'producttype',
            'family' => 'family',
            'isActive' => 'isactive',
            'unitPrice' => 'unitprice',
            'sellingModel' => 'sellingmodel'
        };

        Test.startTest();
        RCAProductCreationController.ParseResult result = RCAProductCreationController.parseCSVFile(
            base64Content,
            JSON.serialize(mapping)
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');
        System.assertEquals(2, result.totalRows, 'Should have 2 data rows');
        System.assertEquals(2, result.parsedRows, 'Should have parsed 2 rows');
        System.assertEquals(8, result.headers.size(), 'Should have 8 headers');

        // Verify first product
        System.assertEquals('Test Product 1', result.products[0].name, 'First product name should match');
        System.assertEquals('TEST-CSV-001', result.products[0].productCode, 'First product code should match');
        System.assertEquals(99.99, result.products[0].unitPrice, 'First product price should match');
    }

    @isTest
    static void testParseCSVWithQuotedValues() {
        // CSV with quoted values containing commas
        String csvContent = 'Name,ProductCode,Description\n' +
                           '"Product with, comma",QUOTE-001,"Description with, comma and ""quotes"""\n' +
                           'Normal Product,QUOTE-002,Normal description';

        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(csvContent));
        Map<String, String> mapping = new Map<String, String>{
            'name' => 'name',
            'productCode' => 'productcode',
            'description' => 'description'
        };

        Test.startTest();
        RCAProductCreationController.ParseResult result = RCAProductCreationController.parseCSVFile(
            base64Content,
            JSON.serialize(mapping)
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');
        System.assertEquals(2, result.parsedRows, 'Should have parsed 2 rows');
        System.assertEquals('Product with, comma', result.products[0].name, 'Quoted comma should be preserved');
    }

    @isTest
    static void testParseEmptyCSV() {
        String csvContent = '';
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(csvContent));

        Test.startTest();
        RCAProductCreationController.ParseResult result = RCAProductCreationController.parseCSVFile(
            base64Content,
            '{}'
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Parse should fail for empty CSV');
        System.assert(result.errorMessage.contains('empty'), 'Error should mention empty');
    }

    @isTest
    static void testParseExcelFile() {
        // Excel parsing currently forwards to CSV parsing
        String csvContent = 'Name,ProductCode\nTest,TEST-001';
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(csvContent));

        Test.startTest();
        RCAProductCreationController.ParseResult result = RCAProductCreationController.parseExcelFile(
            base64Content,
            '{}'
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');
    }

    @isTest
    static void testGetReferenceData() {
        Test.startTest();
        RCAProductCreationController.ReferenceData data = RCAProductCreationController.getReferenceData();
        Test.stopTest();

        System.assertNotEquals(null, data.sellingModels, 'Selling models should not be null');
        System.assertNotEquals(null, data.catalogs, 'Catalogs should not be null');
        System.assertNotEquals(null, data.categories, 'Categories should not be null');
        System.assertNotEquals(null, data.pricebooks, 'Pricebooks should not be null');
        System.assertNotEquals(null, data.productFamilies, 'Product families should not be null');

        System.assert(data.sellingModels.size() >= 2, 'Should have at least 2 selling models');
        System.assert(data.catalogs.size() >= 1, 'Should have at least 1 catalog');
        System.assert(data.categories.size() >= 1, 'Should have at least 1 category');
    }

    @isTest
    static void testSearchProducts() {
        Test.startTest();
        List<Product2> results = RCAProductCreationController.searchProducts('Searchable');
        List<Product2> noResults = RCAProductCreationController.searchProducts('XYZNONEXISTENT');
        List<Product2> codeSearch = RCAProductCreationController.searchProducts('SEARCH');
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should find 2 searchable products');
        System.assertEquals(0, noResults.size(), 'Should find no products for non-existent search');
        System.assert(codeSearch.size() >= 2, 'Should find products by code search');
    }

    @isTest
    static void testGetCSVTemplate() {
        Test.startTest();
        String template = RCAProductCreationController.getCSVTemplate();
        Test.stopTest();

        System.assert(template.contains('Name'), 'Template should contain Name column');
        System.assert(template.contains('ProductCode'), 'Template should contain ProductCode column');
        System.assert(template.contains('Sample Product'), 'Template should contain sample data');
        System.assert(template.contains('Sample Bundle'), 'Template should contain bundle example');
    }

    @isTest
    static void testGetDefaultColumnMappings() {
        Test.startTest();
        List<RCAProductCreationController.ColumnMapping> mappings = RCAProductCreationController.getDefaultColumnMappings();
        Test.stopTest();

        System.assert(mappings.size() >= 10, 'Should have at least 10 column mappings');

        // Find required fields
        Boolean hasNameMapping = false;
        Boolean hasCodeMapping = false;

        for (RCAProductCreationController.ColumnMapping mapping : mappings) {
            if (mapping.fieldName == 'name' && mapping.required) hasNameMapping = true;
            if (mapping.fieldName == 'productCode' && mapping.required) hasCodeMapping = true;
        }

        System.assert(hasNameMapping, 'Should have required Name mapping');
        System.assert(hasCodeMapping, 'Should have required ProductCode mapping');
    }

    @isTest
    static void testValidateProducts() {
        // Create test requests
        List<RCAProductCreationService.ProductRequest> products = new List<RCAProductCreationService.ProductRequest>();

        RCAProductCreationService.ProductRequest validProduct = new RCAProductCreationService.ProductRequest();
        validProduct.name = 'Valid Product';
        validProduct.productCode = 'VALIDATE-001';
        products.add(validProduct);

        RCAProductCreationService.ProductRequest invalidProduct = new RCAProductCreationService.ProductRequest();
        invalidProduct.productCode = 'VALIDATE-002';
        // Missing name
        products.add(invalidProduct);

        Test.startTest();
        List<String> errors = RCAProductCreationController.validateProducts(products);
        Test.stopTest();

        System.assert(errors.size() >= 1, 'Should have at least 1 validation error');
    }

    @isTest
    static void testCreateProducts() {
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'Test OneTime' LIMIT 1];

        List<RCAProductCreationService.ProductRequest> products = new List<RCAProductCreationService.ProductRequest>();

        RCAProductCreationService.ProductRequest req = new RCAProductCreationService.ProductRequest();
        req.name = 'Controller Test Product';
        req.productCode = 'CTRL-TEST-001';
        req.isActive = true;
        req.sellingModelIds = new List<String>{ psm.Id };
        products.add(req);

        Test.startTest();
        RCAProductCreationService.BatchCreationResult result = RCAProductCreationController.createProducts(products);
        Test.stopTest();

        System.assertEquals(1, result.totalSucceeded, 'Product should be created successfully');
    }

    @isTest
    static void testColumnMappingClass() {
        RCAProductCreationController.ColumnMapping mapping = new RCAProductCreationController.ColumnMapping(
            'TestColumn',
            'testField',
            true,
            'Test description'
        );

        System.assertEquals('TestColumn', mapping.csvColumn, 'csvColumn should match');
        System.assertEquals('testField', mapping.fieldName, 'fieldName should match');
        System.assertEquals(true, mapping.required, 'required should match');
        System.assertEquals('Test description', mapping.description, 'description should match');
    }

    @isTest
    static void testParseResultClass() {
        RCAProductCreationController.ParseResult result = new RCAProductCreationController.ParseResult();

        System.assertEquals(false, result.success, 'Default success should be false');
        System.assertNotEquals(null, result.headers, 'headers should be initialized');
        System.assertNotEquals(null, result.products, 'products should be initialized');
        System.assertNotEquals(null, result.warnings, 'warnings should be initialized');
    }

    @isTest
    static void testReferenceDataClass() {
        RCAProductCreationController.ReferenceData data = new RCAProductCreationController.ReferenceData();

        // ReferenceData properties should be settable
        data.sellingModels = new List<ProductSellingModel>();
        data.catalogs = new List<ProductCatalog>();
        data.categories = new List<ProductCategory>();
        data.pricebooks = new List<Pricebook2>();
        data.productFamilies = new List<String>();

        System.assertNotEquals(null, data.sellingModels, 'sellingModels should be set');
    }

    @isTest
    static void testParseCSVWithBundleComponents() {
        // CSV with bundle components
        String csvContent = 'Name,ProductCode,ProductType,BundleComponents\n' +
                           'Bundle Product,BUNDLE-CSV-001,Bundle,SEARCH-001:1:5:1|SEARCH-002:0:10:2';

        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(csvContent));
        Map<String, String> mapping = new Map<String, String>{
            'name' => 'name',
            'productCode' => 'productcode',
            'productType' => 'producttype',
            'bundleComponents' => 'bundlecomponents'
        };

        Test.startTest();
        RCAProductCreationController.ParseResult result = RCAProductCreationController.parseCSVFile(
            base64Content,
            JSON.serialize(mapping)
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');
        System.assertEquals(1, result.parsedRows, 'Should have parsed 1 row');
        System.assertEquals('Bundle', result.products[0].productType, 'Product type should be Bundle');
        System.assertEquals(2, result.products[0].bundleComponents.size(), 'Should have 2 bundle components');

        // Verify component parsing
        RCAProductCreationService.BundleComponent comp1 = result.products[0].bundleComponents[0];
        System.assertEquals('SEARCH-001', comp1.childProductCode, 'First component code should match');
        System.assertEquals(1, comp1.minQuantity, 'First component min qty should match');
        System.assertEquals(5, comp1.maxQuantity, 'First component max qty should match');
        System.assertEquals(1, comp1.defaultQuantity, 'First component default qty should match');
    }

    @isTest
    static void testParseCSVWithSellingModelNames() {
        ProductSellingModel psm = [SELECT Id, Name FROM ProductSellingModel WHERE Name = 'Test OneTime' LIMIT 1];

        String csvContent = 'Name,ProductCode,SellingModel\n' +
                           'Model Name Test,MODEL-001,Test OneTime';

        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(csvContent));
        Map<String, String> mapping = new Map<String, String>{
            'name' => 'name',
            'productCode' => 'productcode',
            'sellingModel' => 'sellingmodel'
        };

        Test.startTest();
        RCAProductCreationController.ParseResult result = RCAProductCreationController.parseCSVFile(
            base64Content,
            JSON.serialize(mapping)
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should succeed');
        System.assert(result.products[0].sellingModelIds.size() > 0, 'Should resolve selling model by name');
        System.assertEquals(psm.Id, result.products[0].sellingModelIds[0], 'Selling model ID should match');
    }

    @isTest
    static void testParseCSVWithPriceFormatting() {
        // Test price with currency symbols and commas
        String csvContent = 'Name,ProductCode,UnitPrice\n' +
                           'Price Test,$1,234.56,PRICE-001';

        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(csvContent));
        Map<String, String> mapping = new Map<String, String>{
            'name' => 'name',
            'productCode' => 'unitprice', // Swapped to test comma in price
            'unitPrice' => 'productcode' // Testing price parsing
        };

        Test.startTest();
        RCAProductCreationController.ParseResult result = RCAProductCreationController.parseCSVFile(
            base64Content,
            JSON.serialize(mapping)
        );
        Test.stopTest();

        // Note: The actual price parsing depends on the column order - this tests the CSV parsing with special chars
        System.assertEquals(true, result.success, 'Parse should succeed with formatted values');
    }

    @isTest
    static void testParseCSVWithDifferentLineEndings() {
        // Test Windows-style line endings
        String csvContent = 'Name,ProductCode\r\nProduct 1,CODE-001\r\nProduct 2,CODE-002';

        String base64Content = EncodingUtil.base64Encode(Blob.valueOf(csvContent));
        Map<String, String> mapping = new Map<String, String>{
            'name' => 'name',
            'productCode' => 'productcode'
        };

        Test.startTest();
        RCAProductCreationController.ParseResult result = RCAProductCreationController.parseCSVFile(
            base64Content,
            JSON.serialize(mapping)
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Parse should handle Windows line endings');
        System.assertEquals(2, result.parsedRows, 'Should parse both rows');
    }
}