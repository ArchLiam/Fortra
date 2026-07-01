/**
 * @description Service class for bulk creation of RCA Technical Products
 * Handles creation of Product2, ProductSellingModelOption, ProductCategoryProduct,
 * ProductComponentGroup, ProductRelatedComponent, and PricebookEntry records
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
public with sharing class RCAProductCreationService {

    // Cache for ProductSellingModel records
    private static Map<String, ProductSellingModel> sellingModelCache;
    private static Map<String, ProductCategory> categoryCache;
    private static Map<String, Pricebook2> pricebookCache;
    private static Id standardPricebookId;

    /**
     * @description Wrapper class for product creation request
     */
    public class ProductRequest {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String productType { get; set; } // Simple, Bundle
        @AuraEnabled public String family { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String categoryId { get; set; }
        @AuraEnabled public String catalogId { get; set; }
        @AuraEnabled public List<String> sellingModelIds { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public List<String> pricebookIds { get; set; }
        @AuraEnabled public List<BundleComponent> bundleComponents { get; set; }
        @AuraEnabled public String externalId { get; set; } // For tracking/mapping
        @AuraEnabled public Map<String, Object> customFields { get; set; }

        public ProductRequest() {
            this.isActive = true;
            this.sellingModelIds = new List<String>();
            this.pricebookIds = new List<String>();
            this.bundleComponents = new List<BundleComponent>();
            this.customFields = new Map<String, Object>();
        }
    }

    /**
     * @description Wrapper class for bundle component definition
     */
    public class BundleComponent {
        @AuraEnabled public String childProductCode { get; set; }
        @AuraEnabled public String childProductId { get; set; }
        @AuraEnabled public String groupName { get; set; }
        @AuraEnabled public Integer minQuantity { get; set; }
        @AuraEnabled public Integer maxQuantity { get; set; }
        @AuraEnabled public Integer defaultQuantity { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }

        public BundleComponent() {
            this.minQuantity = 0;
            this.maxQuantity = 999;
            this.defaultQuantity = 1;
            this.isRequired = false;
            this.sortOrder = 0;
        }
    }

    /**
     * @description Result wrapper for product creation
     */
    public class ProductCreationResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String productId { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String externalId { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }
        @AuraEnabled public Integer sellingModelOptionsCreated { get; set; }
        @AuraEnabled public Integer pricebookEntriesCreated { get; set; }
        @AuraEnabled public Integer bundleComponentsCreated { get; set; }

        public ProductCreationResult() {
            this.success = false;
            this.warnings = new List<String>();
            this.sellingModelOptionsCreated = 0;
            this.pricebookEntriesCreated = 0;
            this.bundleComponentsCreated = 0;
        }
    }

    /**
     * @description Batch result wrapper
     */
    public class BatchCreationResult {
        @AuraEnabled public Integer totalRequested { get; set; }
        @AuraEnabled public Integer totalSucceeded { get; set; }
        @AuraEnabled public Integer totalFailed { get; set; }
        @AuraEnabled public List<ProductCreationResult> results { get; set; }
        @AuraEnabled public String batchId { get; set; }

        public BatchCreationResult() {
            this.totalRequested = 0;
            this.totalSucceeded = 0;
            this.totalFailed = 0;
            this.results = new List<ProductCreationResult>();
        }
    }

    /**
     * @description Main entry point for bulk product creation
     * @param requests List of ProductRequest objects
     * @return BatchCreationResult with success/failure details
     */
    public static BatchCreationResult createProducts(List<ProductRequest> requests) {
        BatchCreationResult batchResult = new BatchCreationResult();
        batchResult.totalRequested = requests.size();
        batchResult.batchId = generateBatchId();

        // Initialize caches
        initializeCaches();

        // Separate simple and bundle products
        List<ProductRequest> simpleProducts = new List<ProductRequest>();
        List<ProductRequest> bundleProducts = new List<ProductRequest>();

        for (ProductRequest req : requests) {
            if (req.productType == 'Bundle' && req.bundleComponents != null && !req.bundleComponents.isEmpty()) {
                bundleProducts.add(req);
            } else {
                simpleProducts.add(req);
            }
        }

        // Process simple products first (bundles may reference them)
        Map<String, ProductCreationResult> simpleResults = processSimpleProducts(simpleProducts);
        batchResult.results.addAll(simpleResults.values());

        // Process bundle products
        Map<String, ProductCreationResult> bundleResults = processBundleProducts(bundleProducts);
        batchResult.results.addAll(bundleResults.values());

        // Calculate totals
        for (ProductCreationResult result : batchResult.results) {
            if (result.success) {
                batchResult.totalSucceeded++;
            } else {
                batchResult.totalFailed++;
            }
        }

        return batchResult;
    }

    /**
     * @description Process simple (non-bundle) products
     */
    private static Map<String, ProductCreationResult> processSimpleProducts(List<ProductRequest> requests) {
        Map<String, ProductCreationResult> results = new Map<String, ProductCreationResult>();

        if (requests.isEmpty()) {
            return results;
        }

        // Create Product2 records
        List<Product2> productsToInsert = new List<Product2>();
        Map<String, ProductRequest> productCodeToRequest = new Map<String, ProductRequest>();

        for (ProductRequest req : requests) {
            ProductCreationResult result = new ProductCreationResult();
            result.productCode = req.productCode;
            result.externalId = req.externalId;

            try {
                Product2 prod = createProduct2Record(req);
                productsToInsert.add(prod);
                productCodeToRequest.put(req.productCode, req);
                results.put(req.productCode, result);
            } catch (Exception e) {
                result.success = false;
                result.errorMessage = 'Failed to create Product2: ' + e.getMessage();
                results.put(req.productCode, result);
            }
        }

        // Insert Product2 records
        if (!productsToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(productsToInsert, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                Product2 prod = productsToInsert[i];
                ProductCreationResult result = results.get(prod.ProductCode);

                if (saveResults[i].isSuccess()) {
                    result.productId = saveResults[i].getId();
                    result.success = true;
                } else {
                    result.success = false;
                    result.errorMessage = 'Product2 insert failed: ' + saveResults[i].getErrors()[0].getMessage();
                }
            }
        }

        // Create related records for successful products
        createRelatedRecords(results, productCodeToRequest);

        return results;
    }

    /**
     * @description Process bundle products
     */
    private static Map<String, ProductCreationResult> processBundleProducts(List<ProductRequest> requests) {
        Map<String, ProductCreationResult> results = new Map<String, ProductCreationResult>();

        if (requests.isEmpty()) {
            return results;
        }

        // First create the parent bundle products (same as simple)
        for (ProductRequest req : requests) {
            req.productType = 'Bundle'; // Ensure type is set
        }

        results = processSimpleProducts(requests);

        // Now create bundle structure for successful products
        createBundleStructure(results, requests);

        return results;
    }

    /**
     * @description Create Product2 record from request
     */
    private static Product2 createProduct2Record(ProductRequest req) {
        Product2 prod = new Product2();
        prod.Name = req.name;
        prod.ProductCode = req.productCode;
        prod.Description = req.description;
        prod.Family = req.family;
        prod.IsActive = req.isActive != null ? req.isActive : true;

        // Set product type for RCA
        if (req.productType == 'Bundle') {
            prod.Type = 'Bundle';
        }

        // Apply custom fields
        if (req.customFields != null) {
            for (String fieldName : req.customFields.keySet()) {
                try {
                    prod.put(fieldName, req.customFields.get(fieldName));
                } catch (Exception e) {
                    // Log warning but continue
                    System.debug(LoggingLevel.WARN, 'Failed to set custom field ' + fieldName + ': ' + e.getMessage());
                }
            }
        }

        return prod;
    }

    /**
     * @description Create related records (ProductSellingModelOption, ProductCategoryProduct, PricebookEntry)
     */
    private static void createRelatedRecords(Map<String, ProductCreationResult> results, Map<String, ProductRequest> requestMap) {
        List<ProductSellingModelOption> psmoList = new List<ProductSellingModelOption>();
        List<ProductCategoryProduct> pcpList = new List<ProductCategoryProduct>();
        List<PricebookEntry> pbeList = new List<PricebookEntry>();
        List<PricebookEntry> standardPbeList = new List<PricebookEntry>();

        Map<String, String> psmoToProductCode = new Map<String, String>();
        Map<String, String> pcpToProductCode = new Map<String, String>();
        Map<String, String> pbeToProductCode = new Map<String, String>();

        for (String productCode : results.keySet()) {
            ProductCreationResult result = results.get(productCode);

            if (!result.success || String.isBlank(result.productId)) {
                continue;
            }

            ProductRequest req = requestMap.get(productCode);
            if (req == null) {
                continue;
            }

            // Create ProductSellingModelOptions
            if (req.sellingModelIds != null) {
                for (String sellingModelId : req.sellingModelIds) {
                    ProductSellingModelOption psmo = new ProductSellingModelOption();
                    psmo.Product2Id = result.productId;
                    psmo.ProductSellingModelId = sellingModelId;
                    psmoList.add(psmo);
                    psmoToProductCode.put(sellingModelId + result.productId, productCode);
                }
            }

            // Create ProductCategoryProduct
            // Note: CatalogId is automatically derived from ProductCategory's CatalogId
            if (String.isNotBlank(req.categoryId)) {
                ProductCategoryProduct pcp = new ProductCategoryProduct();
                pcp.ProductId = result.productId;
                pcp.ProductCategoryId = req.categoryId;
                pcpList.add(pcp);
                pcpToProductCode.put(result.productId, productCode);
            }

            // Create PricebookEntries (standard first, then custom)
            if (req.unitPrice != null) {
                // Get the first selling model for PBE (or use default)
                String sellingModelId = null;
                if (req.sellingModelIds != null && !req.sellingModelIds.isEmpty()) {
                    sellingModelId = req.sellingModelIds[0];
                }

                // Standard Pricebook Entry
                PricebookEntry standardPbe = new PricebookEntry();
                standardPbe.Product2Id = result.productId;
                standardPbe.Pricebook2Id = standardPricebookId;
                standardPbe.UnitPrice = req.unitPrice;
                standardPbe.IsActive = true;
                if (String.isNotBlank(sellingModelId)) {
                    standardPbe.ProductSellingModelId = sellingModelId;
                }
                standardPbeList.add(standardPbe);
                pbeToProductCode.put('STD' + result.productId, productCode);

                // Custom Pricebook Entries
                if (req.pricebookIds != null) {
                    for (String pbId : req.pricebookIds) {
                        if (pbId != standardPricebookId) {
                            PricebookEntry pbe = new PricebookEntry();
                            pbe.Product2Id = result.productId;
                            pbe.Pricebook2Id = pbId;
                            pbe.UnitPrice = req.unitPrice;
                            pbe.IsActive = true;
                            if (String.isNotBlank(sellingModelId)) {
                                pbe.ProductSellingModelId = sellingModelId;
                            }
                            pbeList.add(pbe);
                            pbeToProductCode.put(pbId + result.productId, productCode);
                        }
                    }
                }
            }
        }

        // Insert ProductSellingModelOptions
        if (!psmoList.isEmpty()) {
            Database.SaveResult[] psmoResults = Database.insert(psmoList, false);
            updateResultCounts(psmoResults, psmoToProductCode, results, 'sellingModelOptionsCreated');
        }

        // Insert ProductCategoryProducts
        if (!pcpList.isEmpty()) {
            Database.SaveResult[] pcpResults = Database.insert(pcpList, false);
            for (Integer i = 0; i < pcpResults.size(); i++) {
                if (!pcpResults[i].isSuccess()) {
                    String productCode = pcpToProductCode.get(pcpList[i].ProductId);
                    if (productCode != null && results.containsKey(productCode)) {
                        results.get(productCode).warnings.add('ProductCategoryProduct failed: ' + pcpResults[i].getErrors()[0].getMessage());
                    }
                }
            }
        }

        // Insert Standard PricebookEntries first
        if (!standardPbeList.isEmpty()) {
            Database.SaveResult[] stdPbeResults = Database.insert(standardPbeList, false);
            updateResultCounts(stdPbeResults, pbeToProductCode, results, 'pricebookEntriesCreated');
        }

        // Then insert Custom PricebookEntries
        if (!pbeList.isEmpty()) {
            Database.SaveResult[] pbeResults = Database.insert(pbeList, false);
            updateResultCounts(pbeResults, pbeToProductCode, results, 'pricebookEntriesCreated');
        }
    }

    /**
     * @description Create bundle structure (ProductComponentGroup and ProductRelatedComponent)
     */
    private static void createBundleStructure(Map<String, ProductCreationResult> results, List<ProductRequest> requests) {
        // Group components by group name
        Map<String, List<ProductComponentGroup>> groupsToInsert = new Map<String, List<ProductComponentGroup>>();
        Map<String, List<BundleComponent>> componentsByGroup = new Map<String, List<BundleComponent>>();
        Map<String, String> groupKeyToProductCode = new Map<String, String>();

        // Build lookup for child products by code
        Set<String> childProductCodes = new Set<String>();
        for (ProductRequest req : requests) {
            if (req.bundleComponents != null) {
                for (BundleComponent comp : req.bundleComponents) {
                    if (String.isNotBlank(comp.childProductCode)) {
                        childProductCodes.add(comp.childProductCode);
                    }
                }
            }
        }

        Map<String, Id> childProductMap = new Map<String, Id>();
        if (!childProductCodes.isEmpty()) {
            for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :childProductCodes]) {
                childProductMap.put(p.ProductCode, p.Id);
            }
        }

        // Create ProductComponentGroups
        List<ProductComponentGroup> allGroups = new List<ProductComponentGroup>();
        Map<String, ProductRequest> groupToRequest = new Map<String, ProductRequest>();

        for (ProductRequest req : requests) {
            ProductCreationResult result = results.get(req.productCode);
            if (result == null || !result.success || String.isBlank(result.productId)) {
                continue;
            }

            if (req.bundleComponents == null || req.bundleComponents.isEmpty()) {
                continue;
            }

            // Group components by group name
            Map<String, List<BundleComponent>> groupedComponents = new Map<String, List<BundleComponent>>();
            for (BundleComponent comp : req.bundleComponents) {
                String groupName = String.isNotBlank(comp.groupName) ? comp.groupName : 'Default';
                if (!groupedComponents.containsKey(groupName)) {
                    groupedComponents.put(groupName, new List<BundleComponent>());
                }
                groupedComponents.get(groupName).add(comp);
            }

            // Create groups
            for (String groupName : groupedComponents.keySet()) {
                ProductComponentGroup pcg = new ProductComponentGroup();
                pcg.ParentProductId = result.productId;
                pcg.Name = groupName;
                pcg.Sequence = 1;
                allGroups.add(pcg);

                String groupKey = result.productId + '|' + groupName;
                groupKeyToProductCode.put(groupKey, req.productCode);
                componentsByGroup.put(groupKey, groupedComponents.get(groupName));
            }
        }

        // Insert groups
        if (!allGroups.isEmpty()) {
            Database.SaveResult[] groupResults = Database.insert(allGroups, false);

            // Create ProductRelatedComponents for successful groups
            List<ProductRelatedComponent> prcList = new List<ProductRelatedComponent>();
            Map<String, String> prcToProductCode = new Map<String, String>();

            for (Integer i = 0; i < groupResults.size(); i++) {
                if (groupResults[i].isSuccess()) {
                    ProductComponentGroup pcg = allGroups[i];
                    String groupKey = pcg.ParentProductId + '|' + pcg.Name;
                    List<BundleComponent> components = componentsByGroup.get(groupKey);
                    String productCode = groupKeyToProductCode.get(groupKey);

                    if (components != null) {
                        for (BundleComponent comp : components) {
                            Id childId = String.isNotBlank(comp.childProductId) ?
                                comp.childProductId : childProductMap.get(comp.childProductCode);

                            if (childId != null) {
                                ProductRelatedComponent prc = new ProductRelatedComponent();
                                prc.ProductComponentGroupId = groupResults[i].getId();
                                prc.ParentProductId = pcg.ParentProductId;
                                prc.ChildProductId = childId;
                                prc.MinQuantity = comp.minQuantity;
                                prc.MaxQuantity = comp.maxQuantity;
                                prc.Quantity = comp.defaultQuantity;
                                prc.IsComponentRequired = comp.isRequired;
                                prc.Sequence = comp.sortOrder;
                                prcList.add(prc);
                                prcToProductCode.put(String.valueOf(childId) + String.valueOf(groupResults[i].getId()), productCode);
                            } else if (productCode != null && results.containsKey(productCode)) {
                                results.get(productCode).warnings.add(
                                    'Child product not found: ' + comp.childProductCode
                                );
                            }
                        }
                    }
                } else {
                    String groupKey = allGroups[i].ParentProductId + '|' + allGroups[i].Name;
                    String productCode = groupKeyToProductCode.get(groupKey);
                    if (productCode != null && results.containsKey(productCode)) {
                        results.get(productCode).warnings.add(
                            'ProductComponentGroup failed: ' + groupResults[i].getErrors()[0].getMessage()
                        );
                    }
                }
            }

            // Insert ProductRelatedComponents
            if (!prcList.isEmpty()) {
                Database.SaveResult[] prcResults = Database.insert(prcList, false);
                updateResultCounts(prcResults, prcToProductCode, results, 'bundleComponentsCreated');
            }
        }
    }

    /**
     * @description Update result counts based on save results
     */
    private static void updateResultCounts(Database.SaveResult[] saveResults, Map<String, String> keyToProductCode,
                                          Map<String, ProductCreationResult> results, String countField) {
        for (Integer i = 0; i < saveResults.size(); i++) {
            // Find the product code for this result
            for (String key : keyToProductCode.keySet()) {
                String productCode = keyToProductCode.get(key);
                if (productCode != null && results.containsKey(productCode)) {
                    ProductCreationResult result = results.get(productCode);
                    if (saveResults[i].isSuccess()) {
                        if (countField == 'sellingModelOptionsCreated') {
                            result.sellingModelOptionsCreated++;
                        } else if (countField == 'pricebookEntriesCreated') {
                            result.pricebookEntriesCreated++;
                        } else if (countField == 'bundleComponentsCreated') {
                            result.bundleComponentsCreated++;
                        }
                    }
                    break;
                }
            }
        }
    }

    /**
     * @description Initialize caches for reference data
     */
    private static void initializeCaches() {
        // Cache ProductSellingModels
        if (sellingModelCache == null) {
            sellingModelCache = new Map<String, ProductSellingModel>();
            for (ProductSellingModel psm : [SELECT Id, Name, SellingModelType, Status
                                            FROM ProductSellingModel
                                            WHERE Status = 'Active']) {
                sellingModelCache.put(psm.Id, psm);
                sellingModelCache.put(psm.Name, psm);
            }
        }

        // Cache ProductCategories
        if (categoryCache == null) {
            categoryCache = new Map<String, ProductCategory>();
            for (ProductCategory pc : [SELECT Id, Name FROM ProductCategory]) {
                categoryCache.put(pc.Id, pc);
                categoryCache.put(pc.Name, pc);
            }
        }

        // Cache Standard Pricebook
        if (standardPricebookId == null) {
            Pricebook2 stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
            standardPricebookId = stdPb.Id;
        }
    }

    /**
     * @description Generate unique batch ID
     */
    private static String generateBatchId() {
        return 'BATCH-' + DateTime.now().format('yyyyMMdd-HHmmss') + '-' +
               String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 6);
    }

    /**
     * @description Get active ProductSellingModels
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductSellingModel> getActiveSellingModels() {
        return [SELECT Id, Name, SellingModelType, PricingTerm, PricingTermUnit, Status
                FROM ProductSellingModel
                WHERE Status = 'Active'
                ORDER BY Name];
    }

    /**
     * @description Get ProductCatalogs
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductCatalog> getProductCatalogs() {
        return [SELECT Id, Name FROM ProductCatalog ORDER BY Name];
    }

    /**
     * @description Get ProductCategories by catalog
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductCategory> getCategoriesByCatalog(String catalogId) {
        if (String.isBlank(catalogId)) {
            return [SELECT Id, Name, ParentCategoryId FROM ProductCategory ORDER BY Name];
        }
        return [SELECT Id, Name, ParentCategoryId
                FROM ProductCategory
                WHERE CatalogId = :catalogId
                ORDER BY Name];
    }

    /**
     * @description Get active Pricebooks
     */
    @AuraEnabled(cacheable=true)
    public static List<Pricebook2> getActivePricebooks() {
        return [SELECT Id, Name, IsStandard, IsActive
                FROM Pricebook2
                WHERE IsActive = true
                ORDER BY IsStandard DESC, Name];
    }

    /**
     * @description Validate product requests before creation
     */
    @AuraEnabled
    public static List<String> validateRequests(List<ProductRequest> requests) {
        List<String> errors = new List<String>();
        Set<String> productCodes = new Set<String>();

        // Check for existing product codes
        for (ProductRequest req : requests) {
            if (String.isBlank(req.productCode)) {
                errors.add('Product code is required for: ' + req.name);
            } else if (productCodes.contains(req.productCode)) {
                errors.add('Duplicate product code in request: ' + req.productCode);
            } else {
                productCodes.add(req.productCode);
            }

            if (String.isBlank(req.name)) {
                errors.add('Product name is required for code: ' + req.productCode);
            }
        }

        // Check for existing products with same codes
        if (!productCodes.isEmpty()) {
            List<Product2> existing = [SELECT ProductCode FROM Product2 WHERE ProductCode IN :productCodes];
            for (Product2 p : existing) {
                errors.add('Product code already exists: ' + p.ProductCode);
            }
        }

        return errors;
    }
}