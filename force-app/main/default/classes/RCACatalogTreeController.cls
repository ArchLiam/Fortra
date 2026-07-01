/**
 * @description Controller class for RCA Product Creator catalog/category tree navigation
 * Provides methods for navigating ProductCatalog and ProductCategory hierarchies
 * and retrieving products within catalogs and categories
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
public with sharing class RCACatalogTreeController {

    /**
     * @description Get all active product catalogs
     * @return List of ProductCatalog records
     */
    @AuraEnabled(cacheable=true)
    public static List<CatalogWrapper> getProductCatalogs() {
        List<CatalogWrapper> results = new List<CatalogWrapper>();

        List<ProductCatalog> catalogs = [
            SELECT Id, Name,
                   (SELECT Id FROM ContainedCategories WHERE ParentCategoryId = null)
            FROM ProductCatalog
            ORDER BY Name
            LIMIT 100
        ];

        for (ProductCatalog catalog : catalogs) {
            CatalogWrapper wrapper = new CatalogWrapper();
            wrapper.id = catalog.Id;
            wrapper.name = catalog.Name;
            wrapper.hasCategories = catalog.ContainedCategories != null &&
                                    !catalog.ContainedCategories.isEmpty();
            wrapper.categoryCount = catalog.ContainedCategories != null ?
                                    catalog.ContainedCategories.size() : 0;
            results.add(wrapper);
        }

        return results;
    }

    /**
     * @description Get top-level categories for a catalog (where ParentCategoryId is null)
     * @param catalogId The ProductCatalog ID
     * @return List of CategoryWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<CategoryWrapper> getCategoriesForCatalog(Id catalogId) {
        List<CategoryWrapper> results = new List<CategoryWrapper>();

        if (catalogId == null) {
            return results;
        }

        List<ProductCategory> categories = [
            SELECT Id, Name, Description, ParentCategoryId, CatalogId,
                   (SELECT Id FROM ChildCategories)
            FROM ProductCategory
            WHERE CatalogId = :catalogId
            AND ParentCategoryId = null
            ORDER BY Name
            LIMIT 200
        ];

        // Get ACTIVE product counts per category
        Set<Id> categoryIds = new Set<Id>();
        for (ProductCategory cat : categories) {
            categoryIds.add(cat.Id);
        }
        Map<Id, Integer> activeProductCounts = getActiveProductCountsByCategory(categoryIds);

        for (ProductCategory cat : categories) {
            CategoryWrapper wrapper = new CategoryWrapper();
            wrapper.id = cat.Id;
            wrapper.name = cat.Name;
            wrapper.description = cat.Description;
            wrapper.parentCategoryId = cat.ParentCategoryId;
            wrapper.catalogId = cat.CatalogId;
            wrapper.hasSubcategories = cat.ChildCategories != null &&
                                       !cat.ChildCategories.isEmpty();
            wrapper.subcategoryCount = cat.ChildCategories != null ?
                                       cat.ChildCategories.size() : 0;
            wrapper.productCount = activeProductCounts.containsKey(cat.Id) ?
                                   activeProductCounts.get(cat.Id) : 0;
            results.add(wrapper);
        }

        return results;
    }

    /**
     * @description Get subcategories for a parent category
     * @param parentCategoryId The parent ProductCategory ID
     * @return List of CategoryWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<CategoryWrapper> getSubcategories(Id parentCategoryId) {
        List<CategoryWrapper> results = new List<CategoryWrapper>();

        if (parentCategoryId == null) {
            return results;
        }

        List<ProductCategory> categories = [
            SELECT Id, Name, Description, ParentCategoryId, CatalogId,
                   (SELECT Id FROM ChildCategories)
            FROM ProductCategory
            WHERE ParentCategoryId = :parentCategoryId
            ORDER BY Name
            LIMIT 200
        ];

        // Get ACTIVE product counts per category
        Set<Id> categoryIds = new Set<Id>();
        for (ProductCategory cat : categories) {
            categoryIds.add(cat.Id);
        }
        Map<Id, Integer> activeProductCounts = getActiveProductCountsByCategory(categoryIds);

        for (ProductCategory cat : categories) {
            CategoryWrapper wrapper = new CategoryWrapper();
            wrapper.id = cat.Id;
            wrapper.name = cat.Name;
            wrapper.description = cat.Description;
            wrapper.parentCategoryId = cat.ParentCategoryId;
            wrapper.catalogId = cat.CatalogId;
            wrapper.hasSubcategories = cat.ChildCategories != null &&
                                       !cat.ChildCategories.isEmpty();
            wrapper.subcategoryCount = cat.ChildCategories != null ?
                                       cat.ChildCategories.size() : 0;
            wrapper.productCount = activeProductCounts.containsKey(cat.Id) ?
                                   activeProductCounts.get(cat.Id) : 0;
            results.add(wrapper);
        }

        return results;
    }

    /**
     * @description Get all products in a specific category AND all its subcategories
     * This matches the cumulative count shown in the tree
     * @param categoryId The ProductCategory ID
     * @return List of ProductWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductWrapper> getProductsInCategory(Id categoryId) {
        List<ProductWrapper> results = new List<ProductWrapper>();

        if (categoryId == null) {
            return results;
        }

        // Get the category and its catalog
        ProductCategory category = [
            SELECT Id, CatalogId
            FROM ProductCategory
            WHERE Id = :categoryId
            LIMIT 1
        ];

        // Get all categories in this catalog to build hierarchy
        Map<Id, Id> categoryToParent = new Map<Id, Id>();
        for (ProductCategory cat : [
            SELECT Id, ParentCategoryId
            FROM ProductCategory
            WHERE CatalogId = :category.CatalogId
        ]) {
            categoryToParent.put(cat.Id, cat.ParentCategoryId);
        }

        // Get all descendant category IDs (including self)
        Set<Id> allCategoryIds = getAllDescendantIds(categoryId, categoryToParent);

        // Query via junction object for ALL descendant categories
        List<ProductCategoryProduct> junctions = [
            SELECT Id, ProductId,
                   Product.Id, Product.Name, Product.ProductCode, Product.Description,
                   Product.Family, Product.Type, Product.DecompositionScope, Product.IsActive
            FROM ProductCategoryProduct
            WHERE ProductCategoryId IN :allCategoryIds
            AND Product.IsActive = true
            ORDER BY Product.Name
            LIMIT 500
        ];

        // Get existing decomp rules for these products
        Set<Id> productIds = new Set<Id>();
        for (ProductCategoryProduct pcp : junctions) {
            productIds.add(pcp.ProductId);
        }

        Map<Id, Integer> existingDecompCounts = getExistingDecompCounts(productIds);

        // Use set to avoid duplicates (product can be in multiple categories)
        Set<Id> addedProductIds = new Set<Id>();

        for (ProductCategoryProduct pcp : junctions) {
            if (addedProductIds.contains(pcp.ProductId)) {
                continue;
            }
            addedProductIds.add(pcp.ProductId);

            Product2 p = pcp.Product;
            ProductWrapper wrapper = new ProductWrapper();
            wrapper.id = p.Id;
            wrapper.name = p.Name;
            wrapper.productCode = p.ProductCode;
            wrapper.description = p.Description;
            wrapper.family = p.Family;
            wrapper.productType = p.Type;
            wrapper.decompositionScope = p.DecompositionScope;
            wrapper.isActive = p.IsActive;
            wrapper.hasExistingTechnicalProducts = existingDecompCounts.containsKey(p.Id) &&
                                                    existingDecompCounts.get(p.Id) > 0;
            wrapper.existingTechProductCount = existingDecompCounts.containsKey(p.Id) ?
                                                existingDecompCounts.get(p.Id) : 0;
            results.add(wrapper);
        }

        return results;
    }

    /**
     * @description Get all products in a catalog (all products across all categories)
     * @param catalogId The ProductCatalog ID
     * @return List of ProductWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductWrapper> getProductsInCatalog(Id catalogId) {
        List<ProductWrapper> results = new List<ProductWrapper>();

        if (catalogId == null) {
            return results;
        }

        // Get all categories for this catalog
        Set<Id> categoryIds = new Set<Id>();
        for (ProductCategory cat : [SELECT Id FROM ProductCategory WHERE CatalogId = :catalogId]) {
            categoryIds.add(cat.Id);
        }

        if (categoryIds.isEmpty()) {
            return results;
        }

        // Query via junction object
        List<ProductCategoryProduct> junctions = [
            SELECT Id, ProductId,
                   Product.Id, Product.Name, Product.ProductCode, Product.Description,
                   Product.Family, Product.Type, Product.DecompositionScope, Product.IsActive
            FROM ProductCategoryProduct
            WHERE ProductCategoryId IN :categoryIds
            AND Product.IsActive = true
            ORDER BY Product.Name
            LIMIT 500
        ];

        // Get existing decomp rules for these products
        Set<Id> productIds = new Set<Id>();
        for (ProductCategoryProduct pcp : junctions) {
            productIds.add(pcp.ProductId);
        }

        Map<Id, Integer> existingDecompCounts = getExistingDecompCounts(productIds);

        // Use set to avoid duplicates (product can be in multiple categories)
        Set<Id> addedProductIds = new Set<Id>();

        for (ProductCategoryProduct pcp : junctions) {
            if (addedProductIds.contains(pcp.ProductId)) {
                continue;
            }
            addedProductIds.add(pcp.ProductId);

            Product2 p = pcp.Product;
            ProductWrapper wrapper = new ProductWrapper();
            wrapper.id = p.Id;
            wrapper.name = p.Name;
            wrapper.productCode = p.ProductCode;
            wrapper.description = p.Description;
            wrapper.family = p.Family;
            wrapper.productType = p.Type;
            wrapper.decompositionScope = p.DecompositionScope;
            wrapper.isActive = p.IsActive;
            wrapper.hasExistingTechnicalProducts = existingDecompCounts.containsKey(p.Id) &&
                                                    existingDecompCounts.get(p.Id) > 0;
            wrapper.existingTechProductCount = existingDecompCounts.containsKey(p.Id) ?
                                                existingDecompCounts.get(p.Id) : 0;
            results.add(wrapper);
        }

        return results;
    }

    /**
     * @description Build tree items for lightning-tree component
     * Eagerly loads catalogs with ALL category levels (full hierarchy)
     * (Note: lightning-tree chevron clicks don't fire onselect, so we load everything upfront)
     * @return List of TreeNode for lightning-tree
     */
    @AuraEnabled(cacheable=true)
    public static List<TreeNode> getTreeRoot() {
        List<TreeNode> nodes = new List<TreeNode>();

        // Get all catalogs
        List<ProductCatalog> catalogs = [
            SELECT Id, Name
            FROM ProductCatalog
            ORDER BY Name
            LIMIT 100
        ];

        // Get all catalog IDs
        Set<Id> catalogIds = new Set<Id>();
        for (ProductCatalog cat : catalogs) {
            catalogIds.add(cat.Id);
        }

        // Get ALL categories for all catalogs (not just top-level)
        List<ProductCategory> allCategories = [
            SELECT Id, Name, Description, CatalogId, ParentCategoryId
            FROM ProductCategory
            WHERE CatalogId IN :catalogIds
            ORDER BY Name
            LIMIT 2000
        ];

        // Get CUMULATIVE product counts for ALL categories
        Map<Id, Integer> activeProductCounts = new Map<Id, Integer>();
        for (Id catalogId : catalogIds) {
            Set<Id> catIdsForCatalog = new Set<Id>();
            for (ProductCategory cat : allCategories) {
                if (cat.CatalogId == catalogId) {
                    catIdsForCatalog.add(cat.Id);
                }
            }
            if (!catIdsForCatalog.isEmpty()) {
                Map<Id, Integer> catalogCounts = getCumulativeProductCountsByCategory(catIdsForCatalog, catalogId);
                activeProductCounts.putAll(catalogCounts);
            }
        }

        // Build maps for tree construction
        Map<Id, List<ProductCategory>> categoryByCatalog = new Map<Id, List<ProductCategory>>();
        Map<Id, List<ProductCategory>> childrenByParent = new Map<Id, List<ProductCategory>>();

        for (ProductCategory cat : allCategories) {
            // Map by catalog (top-level only)
            if (cat.ParentCategoryId == null) {
                if (!categoryByCatalog.containsKey(cat.CatalogId)) {
                    categoryByCatalog.put(cat.CatalogId, new List<ProductCategory>());
                }
                categoryByCatalog.get(cat.CatalogId).add(cat);
            }

            // Map children by parent
            if (cat.ParentCategoryId != null) {
                if (!childrenByParent.containsKey(cat.ParentCategoryId)) {
                    childrenByParent.put(cat.ParentCategoryId, new List<ProductCategory>());
                }
                childrenByParent.get(cat.ParentCategoryId).add(cat);
            }
        }

        // Build tree nodes recursively
        for (ProductCatalog catalog : catalogs) {
            TreeNode catalogNode = new TreeNode();
            catalogNode.name = catalog.Id;
            catalogNode.label = catalog.Name;
            catalogNode.nodeType = 'catalog';
            catalogNode.expanded = false;
            catalogNode.items = new List<TreeNode>();

            // Add category children (recursively)
            List<ProductCategory> topLevelCategories = categoryByCatalog.get(catalog.Id);
            if (topLevelCategories != null) {
                for (ProductCategory cat : topLevelCategories) {
                    TreeNode categoryNode = buildCategoryNode(cat, childrenByParent, activeProductCounts, 'category');
                    catalogNode.items.add(categoryNode);
                }
            }

            nodes.add(catalogNode);
        }

        return nodes;
    }

    /**
     * @description Recursively build a category tree node with all its children
     * @param cat The ProductCategory record
     * @param childrenByParent Map of parent ID to child categories
     * @param productCounts Map of category ID to product count
     * @param nodeType The type of node ('category' or 'subcategory')
     * @return TreeNode with all descendants
     */
    private static TreeNode buildCategoryNode(
        ProductCategory cat,
        Map<Id, List<ProductCategory>> childrenByParent,
        Map<Id, Integer> productCounts,
        String nodeType
    ) {
        TreeNode node = new TreeNode();
        node.name = cat.Id;
        node.label = cat.Name;
        node.nodeType = nodeType;
        node.expanded = false;
        node.productCount = productCounts.containsKey(cat.Id) ? productCounts.get(cat.Id) : 0;
        node.metatext = node.productCount + ' products';
        node.items = new List<TreeNode>();

        // Recursively add children
        List<ProductCategory> children = childrenByParent.get(cat.Id);
        if (children != null) {
            for (ProductCategory child : children) {
                TreeNode childNode = buildCategoryNode(child, childrenByParent, productCounts, 'subcategory');
                node.items.add(childNode);
            }
        }

        return node;
    }

    /**
     * @description Get child tree nodes for a parent node (catalog or category)
     * @param parentId The parent node ID (catalog or category)
     * @param parentType The parent type ('catalog' or 'category')
     * @return List of TreeNode children
     */
    @AuraEnabled
    public static List<TreeNode> getTreeChildren(Id parentId, String parentType) {
        List<TreeNode> nodes = new List<TreeNode>();

        if (parentType == 'catalog') {
            // Get top-level categories
            List<ProductCategory> categories = [
                SELECT Id, Name, Description,
                       (SELECT Id FROM ChildCategories)
                FROM ProductCategory
                WHERE CatalogId = :parentId
                AND ParentCategoryId = null
                ORDER BY Name
                LIMIT 200
            ];

            // Get ACTIVE product counts per category (matching getProductsInCategory filter)
            Set<Id> categoryIds = new Set<Id>();
            for (ProductCategory cat : categories) {
                categoryIds.add(cat.Id);
            }
            Map<Id, Integer> activeProductCounts = getActiveProductCountsByCategory(categoryIds);

            for (ProductCategory cat : categories) {
                TreeNode node = new TreeNode();
                node.name = cat.Id;
                node.label = cat.Name;
                node.nodeType = 'category';
                node.expanded = false;
                node.productCount = activeProductCounts.containsKey(cat.Id) ?
                                    activeProductCounts.get(cat.Id) : 0;
                node.metatext = node.productCount + ' products';
                node.items = new List<TreeNode>();

                // Add placeholder if has subcategories
                if (cat.ChildCategories != null && !cat.ChildCategories.isEmpty()) {
                    TreeNode placeholder = new TreeNode();
                    placeholder.name = 'loading-' + cat.Id;
                    placeholder.label = 'Loading...';
                    placeholder.nodeType = 'loading';
                    node.items.add(placeholder);
                }

                nodes.add(node);
            }
        } else if (parentType == 'category') {
            // Get subcategories
            List<ProductCategory> subcategories = [
                SELECT Id, Name, Description,
                       (SELECT Id FROM ChildCategories)
                FROM ProductCategory
                WHERE ParentCategoryId = :parentId
                ORDER BY Name
                LIMIT 200
            ];

            // Get ACTIVE product counts per category (matching getProductsInCategory filter)
            Set<Id> categoryIds = new Set<Id>();
            for (ProductCategory cat : subcategories) {
                categoryIds.add(cat.Id);
            }
            Map<Id, Integer> activeProductCounts = getActiveProductCountsByCategory(categoryIds);

            for (ProductCategory cat : subcategories) {
                TreeNode node = new TreeNode();
                node.name = cat.Id;
                node.label = cat.Name;
                node.nodeType = 'subcategory';
                node.expanded = false;
                node.productCount = activeProductCounts.containsKey(cat.Id) ?
                                    activeProductCounts.get(cat.Id) : 0;
                node.metatext = node.productCount + ' products';
                node.items = new List<TreeNode>();

                // Add placeholder if has more subcategories
                if (cat.ChildCategories != null && !cat.ChildCategories.isEmpty()) {
                    TreeNode placeholder = new TreeNode();
                    placeholder.name = 'loading-' + cat.Id;
                    placeholder.label = 'Loading...';
                    placeholder.nodeType = 'loading';
                    node.items.add(placeholder);
                }

                nodes.add(node);
            }
        }

        return nodes;
    }

    /**
     * @description Get count of ACTIVE products per category (direct products only)
     * This ensures the count shown in tree matches what getProductsInCategory returns
     * @param categoryIds Set of ProductCategory IDs to count
     * @return Map of CategoryId to count of active products
     */
    private static Map<Id, Integer> getActiveProductCountsByCategory(Set<Id> categoryIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();

        if (categoryIds == null || categoryIds.isEmpty()) {
            return counts;
        }

        // Initialize all to 0
        for (Id categoryId : categoryIds) {
            counts.put(categoryId, 0);
        }

        // Count active products per category via junction object
        for (AggregateResult ar : [
            SELECT ProductCategoryId, COUNT(Id) cnt
            FROM ProductCategoryProduct
            WHERE ProductCategoryId IN :categoryIds
            AND Product.IsActive = true
            GROUP BY ProductCategoryId
        ]) {
            Id categoryId = (Id) ar.get('ProductCategoryId');
            Integer cnt = (Integer) ar.get('cnt');
            counts.put(categoryId, cnt);
        }

        return counts;
    }

    /**
     * @description Get CUMULATIVE count of UNIQUE ACTIVE products per category (including all subcategories)
     * This shows total unique products in the category hierarchy (deduplicates products in multiple categories)
     * @param categoryIds Set of ProductCategory IDs to count
     * @param catalogId The catalog ID to scope the query
     * @return Map of CategoryId to cumulative count of unique active products
     */
    private static Map<Id, Integer> getCumulativeProductCountsByCategory(Set<Id> categoryIds, Id catalogId) {
        Map<Id, Integer> counts = new Map<Id, Integer>();

        if (categoryIds == null || categoryIds.isEmpty()) {
            return counts;
        }

        // Initialize all to 0
        for (Id categoryId : categoryIds) {
            counts.put(categoryId, 0);
        }

        // Get all categories in this catalog with their parent relationships
        Map<Id, Id> categoryToParent = new Map<Id, Id>();
        for (ProductCategory cat : [
            SELECT Id, ParentCategoryId
            FROM ProductCategory
            WHERE CatalogId = :catalogId
        ]) {
            categoryToParent.put(cat.Id, cat.ParentCategoryId);
        }

        // Get all product-to-category mappings for active products in this catalog
        Map<Id, Set<Id>> categoryToProducts = new Map<Id, Set<Id>>();
        for (ProductCategoryProduct pcp : [
            SELECT ProductCategoryId, ProductId
            FROM ProductCategoryProduct
            WHERE ProductCategory.CatalogId = :catalogId
            AND Product.IsActive = true
        ]) {
            if (!categoryToProducts.containsKey(pcp.ProductCategoryId)) {
                categoryToProducts.put(pcp.ProductCategoryId, new Set<Id>());
            }
            categoryToProducts.get(pcp.ProductCategoryId).add(pcp.ProductId);
        }

        // For each category we're interested in, count UNIQUE products from it and all descendants
        for (Id categoryId : categoryIds) {
            // Get all descendant category IDs (including self)
            Set<Id> descendantIds = getAllDescendantIds(categoryId, categoryToParent);

            // Collect unique product IDs across all descendants
            Set<Id> uniqueProductIds = new Set<Id>();
            for (Id descendantId : descendantIds) {
                Set<Id> productsInCategory = categoryToProducts.get(descendantId);
                if (productsInCategory != null) {
                    uniqueProductIds.addAll(productsInCategory);
                }
            }

            counts.put(categoryId, uniqueProductIds.size());
        }

        return counts;
    }

    /**
     * @description Get all descendant category IDs for a given category (including self)
     * @param categoryId The parent category ID
     * @param categoryToParent Map of category ID to parent category ID
     * @return Set of all descendant category IDs including the input category
     */
    private static Set<Id> getAllDescendantIds(Id categoryId, Map<Id, Id> categoryToParent) {
        Set<Id> descendants = new Set<Id>();
        descendants.add(categoryId);

        // Build reverse map: parent -> children
        Map<Id, Set<Id>> parentToChildren = new Map<Id, Set<Id>>();
        for (Id catId : categoryToParent.keySet()) {
            Id parentId = categoryToParent.get(catId);
            if (parentId != null) {
                if (!parentToChildren.containsKey(parentId)) {
                    parentToChildren.put(parentId, new Set<Id>());
                }
                parentToChildren.get(parentId).add(catId);
            }
        }

        // BFS to find all descendants
        List<Id> queue = new List<Id>{ categoryId };
        while (!queue.isEmpty()) {
            Id current = queue.remove(0);
            Set<Id> children = parentToChildren.get(current);
            if (children != null) {
                for (Id childId : children) {
                    if (!descendants.contains(childId)) {
                        descendants.add(childId);
                        queue.add(childId);
                    }
                }
            }
        }

        return descendants;
    }

    /**
     * @description Get count of existing decomposition rules per product
     * @param productIds Set of Product IDs to check
     * @return Map of ProductId to count of existing decomp rules
     */
    private static Map<Id, Integer> getExistingDecompCounts(Set<Id> productIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();

        if (productIds == null || productIds.isEmpty()) {
            return counts;
        }

        // Initialize all to 0
        for (Id productId : productIds) {
            counts.put(productId, 0);
        }

        // Count existing decomp rules
        for (AggregateResult ar : [
            SELECT SourceProductId, COUNT(Id) cnt
            FROM ProductFulfillmentDecompRule
            WHERE SourceProductId IN :productIds
            GROUP BY SourceProductId
        ]) {
            Id productId = (Id) ar.get('SourceProductId');
            Integer cnt = (Integer) ar.get('cnt');
            counts.put(productId, cnt);
        }

        return counts;
    }

    // ========== Wrapper Classes ==========

    public class CatalogWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Boolean hasCategories { get; set; }
        @AuraEnabled public Integer categoryCount { get; set; }
    }

    public class CategoryWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String parentCategoryId { get; set; }
        @AuraEnabled public String catalogId { get; set; }
        @AuraEnabled public Boolean hasSubcategories { get; set; }
        @AuraEnabled public Integer subcategoryCount { get; set; }
        @AuraEnabled public Integer productCount { get; set; }
    }

    public class ProductWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String family { get; set; }
        @AuraEnabled public String productType { get; set; }
        @AuraEnabled public String decompositionScope { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Boolean hasExistingTechnicalProducts { get; set; }
        @AuraEnabled public Integer existingTechProductCount { get; set; }
    }

    public class TreeNode {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String nodeType { get; set; }
        @AuraEnabled public Boolean expanded { get; set; }
        @AuraEnabled public Integer productCount { get; set; }
        @AuraEnabled public String metatext { get; set; }
        @AuraEnabled public List<TreeNode> items { get; set; }
    }
}