/**
 * @description Test class for RCACatalogTreeController
 * Tests catalog/category tree navigation and product retrieval methods
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
@isTest
private class RCACatalogTreeControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create a test ProductCatalog
        ProductCatalog catalog = new ProductCatalog(
            Name = 'Test Catalog'
        );
        insert catalog;

        // Create top-level categories
        ProductCategory parentCategory = new ProductCategory(
            Name = 'Parent Category',
            CatalogId = catalog.Id
        );
        insert parentCategory;

        // Create subcategory
        ProductCategory childCategory = new ProductCategory(
            Name = 'Child Category',
            CatalogId = catalog.Id,
            ParentCategoryId = parentCategory.Id
        );
        insert childCategory;

        // Create test products (must include QuantityUnitOfMeasure for active products)
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < 5; i++) {
            products.add(new Product2(
                Name = 'Test Product ' + i,
                ProductCode = 'TEST-PROD-' + i,
                Description = 'Test product description ' + i,
                Family = 'Software',
                IsActive = true,
                QuantityUnitOfMeasure = 'Each'
            ));
        }
        insert products;

        // Associate products with categories via junction object
        List<ProductCategoryProduct> junctions = new List<ProductCategoryProduct>();
        for (Integer i = 0; i < products.size(); i++) {
            // Add first 3 products to parent category
            if (i < 3) {
                junctions.add(new ProductCategoryProduct(
                    ProductCategoryId = parentCategory.Id,
                    ProductId = products[i].Id
                ));
            }
            // Add last 2 products to child category
            if (i >= 3) {
                junctions.add(new ProductCategoryProduct(
                    ProductCategoryId = childCategory.Id,
                    ProductId = products[i].Id
                ));
            }
        }
        insert junctions;

        // Create a technical product and decomp rule for one product
        Product2 techProduct = new Product2(
            Name = 'Test Technical Product',
            ProductCode = 'TEST-TECH-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert techProduct;

        ProductFulfillmentDecompRule decompRule = new ProductFulfillmentDecompRule(
            Name = 'Test Decomp Rule',
            SourceProductId = products[0].Id,
            DestinationProductId = techProduct.Id,
            Priority = 1
        );
        insert decompRule;
    }

    @isTest
    static void testGetProductCatalogs() {
        Test.startTest();
        List<RCACatalogTreeController.CatalogWrapper> catalogs =
            RCACatalogTreeController.getProductCatalogs();
        Test.stopTest();

        System.assert(catalogs.size() > 0, 'Should return at least one catalog');

        RCACatalogTreeController.CatalogWrapper testCatalog = null;
        for (RCACatalogTreeController.CatalogWrapper cat : catalogs) {
            if (cat.name == 'Test Catalog') {
                testCatalog = cat;
                break;
            }
        }

        System.assertNotEquals(null, testCatalog, 'Should find Test Catalog');
        System.assert(testCatalog.hasCategories, 'Catalog should have categories');
    }

    @isTest
    static void testGetCategoriesForCatalog() {
        ProductCatalog catalog = [SELECT Id FROM ProductCatalog WHERE Name = 'Test Catalog' LIMIT 1];

        Test.startTest();
        List<RCACatalogTreeController.CategoryWrapper> categories =
            RCACatalogTreeController.getCategoriesForCatalog(catalog.Id);
        Test.stopTest();

        System.assertEquals(1, categories.size(), 'Should return 1 top-level category');

        RCACatalogTreeController.CategoryWrapper parentCat = categories[0];
        System.assertEquals('Parent Category', parentCat.name);
        System.assert(parentCat.hasSubcategories, 'Parent category should have subcategories');
        System.assertEquals(1, parentCat.subcategoryCount);
        System.assertEquals(3, parentCat.productCount, 'Parent category should have 3 products');
    }

    @isTest
    static void testGetCategoriesForCatalog_NullId() {
        Test.startTest();
        List<RCACatalogTreeController.CategoryWrapper> categories =
            RCACatalogTreeController.getCategoriesForCatalog(null);
        Test.stopTest();

        System.assertEquals(0, categories.size(), 'Should return empty list for null catalog ID');
    }

    @isTest
    static void testGetSubcategories() {
        ProductCategory parentCategory = [
            SELECT Id FROM ProductCategory WHERE Name = 'Parent Category' LIMIT 1
        ];

        Test.startTest();
        List<RCACatalogTreeController.CategoryWrapper> subcategories =
            RCACatalogTreeController.getSubcategories(parentCategory.Id);
        Test.stopTest();

        System.assertEquals(1, subcategories.size(), 'Should return 1 subcategory');

        RCACatalogTreeController.CategoryWrapper childCat = subcategories[0];
        System.assertEquals('Child Category', childCat.name);
        System.assertEquals(false, childCat.hasSubcategories, 'Child category should not have subcategories');
        System.assertEquals(2, childCat.productCount, 'Child category should have 2 products');
    }

    @isTest
    static void testGetSubcategories_NullId() {
        Test.startTest();
        List<RCACatalogTreeController.CategoryWrapper> subcategories =
            RCACatalogTreeController.getSubcategories(null);
        Test.stopTest();

        System.assertEquals(0, subcategories.size(), 'Should return empty list for null parent ID');
    }

    @isTest
    static void testGetProductsInCategory() {
        ProductCategory parentCategory = [
            SELECT Id FROM ProductCategory WHERE Name = 'Parent Category' LIMIT 1
        ];

        Test.startTest();
        List<RCACatalogTreeController.ProductWrapper> products =
            RCACatalogTreeController.getProductsInCategory(parentCategory.Id);
        Test.stopTest();

        // With cumulative behavior: 3 direct + 2 from child category = 5 total
        System.assertEquals(5, products.size(), 'Should return 5 products (3 direct + 2 from subcategory)');

        // Check that one product has existing technical products
        Boolean foundWithTech = false;
        for (RCACatalogTreeController.ProductWrapper p : products) {
            if (p.hasExistingTechnicalProducts) {
                foundWithTech = true;
                System.assertEquals(1, p.existingTechProductCount);
                break;
            }
        }
        System.assert(foundWithTech, 'Should find at least one product with existing technical product');
    }

    @isTest
    static void testGetProductsInCategory_NullId() {
        Test.startTest();
        List<RCACatalogTreeController.ProductWrapper> products =
            RCACatalogTreeController.getProductsInCategory(null);
        Test.stopTest();

        System.assertEquals(0, products.size(), 'Should return empty list for null category ID');
    }

    @isTest
    static void testGetProductsInCatalog() {
        ProductCatalog catalog = [SELECT Id FROM ProductCatalog WHERE Name = 'Test Catalog' LIMIT 1];

        Test.startTest();
        List<RCACatalogTreeController.ProductWrapper> products =
            RCACatalogTreeController.getProductsInCatalog(catalog.Id);
        Test.stopTest();

        System.assertEquals(5, products.size(), 'Should return 5 unique products from all categories');
    }

    @isTest
    static void testGetProductsInCatalog_NullId() {
        Test.startTest();
        List<RCACatalogTreeController.ProductWrapper> products =
            RCACatalogTreeController.getProductsInCatalog(null);
        Test.stopTest();

        System.assertEquals(0, products.size(), 'Should return empty list for null catalog ID');
    }

    @isTest
    static void testGetTreeRoot() {
        Test.startTest();
        List<RCACatalogTreeController.TreeNode> nodes =
            RCACatalogTreeController.getTreeRoot();
        Test.stopTest();

        System.assert(nodes.size() > 0, 'Should return at least one tree node');

        RCACatalogTreeController.TreeNode testNode = null;
        for (RCACatalogTreeController.TreeNode node : nodes) {
            if (node.label == 'Test Catalog') {
                testNode = node;
                break;
            }
        }

        System.assertNotEquals(null, testNode, 'Should find Test Catalog node');
        System.assertEquals('catalog', testNode.nodeType);
        System.assert(testNode.items != null && testNode.items.size() > 0,
            'Catalog node should have placeholder items');
    }

    @isTest
    static void testGetTreeChildren_Catalog() {
        ProductCatalog catalog = [SELECT Id FROM ProductCatalog WHERE Name = 'Test Catalog' LIMIT 1];

        Test.startTest();
        List<RCACatalogTreeController.TreeNode> children =
            RCACatalogTreeController.getTreeChildren(catalog.Id, 'catalog');
        Test.stopTest();

        System.assertEquals(1, children.size(), 'Should return 1 top-level category');

        RCACatalogTreeController.TreeNode categoryNode = children[0];
        System.assertEquals('Parent Category', categoryNode.label);
        System.assertEquals('category', categoryNode.nodeType);
        System.assertEquals(3, categoryNode.productCount);
        System.assert(categoryNode.items != null && categoryNode.items.size() > 0,
            'Category node should have placeholder for subcategories');
    }

    @isTest
    static void testGetTreeChildren_Category() {
        ProductCategory parentCategory = [
            SELECT Id FROM ProductCategory WHERE Name = 'Parent Category' LIMIT 1
        ];

        Test.startTest();
        List<RCACatalogTreeController.TreeNode> children =
            RCACatalogTreeController.getTreeChildren(parentCategory.Id, 'category');
        Test.stopTest();

        System.assertEquals(1, children.size(), 'Should return 1 subcategory');

        RCACatalogTreeController.TreeNode subcatNode = children[0];
        System.assertEquals('Child Category', subcatNode.label);
        System.assertEquals('subcategory', subcatNode.nodeType);
        System.assertEquals(2, subcatNode.productCount);
    }

    @isTest
    static void testActiveProductCountExcludesInactive() {
        // Get existing category
        ProductCategory parentCategory = [
            SELECT Id FROM ProductCategory WHERE Name = 'Parent Category' LIMIT 1
        ];

        // Create an inactive product and associate with category
        Product2 inactiveProduct = new Product2(
            Name = 'Inactive Test Product',
            ProductCode = 'INACTIVE-001',
            IsActive = false
        );
        insert inactiveProduct;

        ProductCategoryProduct junction = new ProductCategoryProduct(
            ProductCategoryId = parentCategory.Id,
            ProductId = inactiveProduct.Id
        );
        insert junction;

        Test.startTest();

        // Get category info - count should still be 3 (excludes inactive product)
        ProductCatalog catalog = [SELECT Id FROM ProductCatalog WHERE Name = 'Test Catalog' LIMIT 1];
        List<RCACatalogTreeController.CategoryWrapper> categories =
            RCACatalogTreeController.getCategoriesForCatalog(catalog.Id);

        // Get products in category - should still be 3 (excludes inactive)
        List<RCACatalogTreeController.ProductWrapper> products =
            RCACatalogTreeController.getProductsInCategory(parentCategory.Id);

        // Get tree children - count should still be 3
        List<RCACatalogTreeController.TreeNode> treeChildren =
            RCACatalogTreeController.getTreeChildren(catalog.Id, 'catalog');

        Test.stopTest();

        // Verify category count excludes inactive product
        System.assertEquals(3, categories[0].productCount,
            'Category product count should exclude inactive products');

        // Verify products list excludes inactive product
        // With cumulative behavior: 3 direct + 2 from child category = 5 active products
        System.assertEquals(5, products.size(),
            'Products list should exclude inactive products (5 active from parent + child)');

        // Verify tree node count excludes inactive product
        System.assertEquals(3, treeChildren[0].productCount,
            'Tree node product count should exclude inactive products');
    }

    @isTest
    static void testWrapperClasses() {
        // Test CatalogWrapper
        RCACatalogTreeController.CatalogWrapper catalogWrapper =
            new RCACatalogTreeController.CatalogWrapper();
        catalogWrapper.id = 'testId';
        catalogWrapper.name = 'Test Catalog';
        catalogWrapper.hasCategories = true;
        catalogWrapper.categoryCount = 5;
        System.assertEquals('testId', catalogWrapper.id);
        System.assertEquals('Test Catalog', catalogWrapper.name);

        // Test CategoryWrapper
        RCACatalogTreeController.CategoryWrapper categoryWrapper =
            new RCACatalogTreeController.CategoryWrapper();
        categoryWrapper.id = 'catId';
        categoryWrapper.name = 'Test Category';
        categoryWrapper.description = 'Test description';
        categoryWrapper.parentCategoryId = 'parentId';
        categoryWrapper.catalogId = 'catalogId';
        categoryWrapper.hasSubcategories = true;
        categoryWrapper.subcategoryCount = 3;
        categoryWrapper.productCount = 10;
        System.assertEquals('catId', categoryWrapper.id);
        System.assertEquals(3, categoryWrapper.subcategoryCount);

        // Test ProductWrapper
        RCACatalogTreeController.ProductWrapper productWrapper =
            new RCACatalogTreeController.ProductWrapper();
        productWrapper.id = 'prodId';
        productWrapper.name = 'Test Product';
        productWrapper.productCode = 'TEST-001';
        productWrapper.description = 'Product description';
        productWrapper.family = 'Software';
        productWrapper.productType = 'Bundle';
        productWrapper.decompositionScope = 'Standalone';
        productWrapper.isActive = true;
        productWrapper.hasExistingTechnicalProducts = true;
        productWrapper.existingTechProductCount = 2;
        System.assertEquals('prodId', productWrapper.id);
        System.assertEquals(true, productWrapper.hasExistingTechnicalProducts);

        // Test TreeNode
        RCACatalogTreeController.TreeNode treeNode =
            new RCACatalogTreeController.TreeNode();
        treeNode.name = 'nodeId';
        treeNode.label = 'Node Label';
        treeNode.nodeType = 'catalog';
        treeNode.expanded = false;
        treeNode.productCount = 5;
        treeNode.metatext = '5 products';
        treeNode.items = new List<RCACatalogTreeController.TreeNode>();
        System.assertEquals('nodeId', treeNode.name);
        System.assertEquals('catalog', treeNode.nodeType);
    }
}