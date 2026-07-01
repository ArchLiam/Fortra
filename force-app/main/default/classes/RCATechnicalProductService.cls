/**
 * @description Service class for bulk creation of RCA Technical Products
 * Creates Technical Product2 records and ProductFulfillmentDecompRule records
 * linking commercial products to their technical product counterparts.
 * Also updates commercial products to set DecompositionScope = 'OrderLineItem'
 * to enable decomposition at order time for each order line.
 *
 * Additionally creates related records for technical products:
 * - ProductSellingModelOption: Inherited from commercial product
 * - PricebookEntry: Copied from commercial product (same prices)
 * - ProductCategoryProduct: Same category as commercial product
 *
 * All related record creation is required - if any fails, the entire
 * transaction is rolled back using Database.Savepoint.
 *
 * Technical Products are fulfillment items that don't have:
 * - Type (stays null)
 * - DecompositionScope (stays null)
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
public with sharing class RCATechnicalProductService {

    // Cache the Technical Product record type ID
    private static Id technicalProductRecordTypeId;

    /**
     * @description Get the Technical Product record type ID
     */
    private static Id getTechnicalProductRecordTypeId() {
        if (technicalProductRecordTypeId == null) {
            List<RecordType> rts = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Product2'
                AND DeveloperName = 'Technical_Product'
                AND IsActive = true
                LIMIT 1
            ];
            if (!rts.isEmpty()) {
                technicalProductRecordTypeId = rts[0].Id;
            }
        }
        return technicalProductRecordTypeId;
    }

    /**
     * @description Wrapper class for technical product creation request
     */
    public class TechnicalProductRequest {
        @AuraEnabled public String commercialProductId { get; set; }
        @AuraEnabled public String commercialProductName { get; set; }
        @AuraEnabled public String commercialProductCode { get; set; }
        @AuraEnabled public String technicalProductName { get; set; }
        @AuraEnabled public String technicalProductCode { get; set; }
        @AuraEnabled public String technicalProductDescription { get; set; }
        @AuraEnabled public String family { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Integer decompRulePriority { get; set; }
        @AuraEnabled public String productClassificationId { get; set; }
        @AuraEnabled public String rulesetId { get; set; }
        @AuraEnabled public Map<String, Object> customFields { get; set; }

        public TechnicalProductRequest() {
            this.isActive = true;
            this.decompRulePriority = 1;
            this.customFields = new Map<String, Object>();
        }
    }

    /**
     * @description Result wrapper for technical product creation
     */
    public class TechnicalProductResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String commercialProductId { get; set; }
        @AuraEnabled public String commercialProductCode { get; set; }
        @AuraEnabled public String technicalProductId { get; set; }
        @AuraEnabled public String technicalProductCode { get; set; }
        @AuraEnabled public String decompRuleId { get; set; }
        @AuraEnabled public Boolean commercialProductUpdated { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }

        // Related record tracking
        @AuraEnabled public Integer sellingModelOptionsCreated { get; set; }
        @AuraEnabled public Integer pricebookEntriesCreated { get; set; }
        @AuraEnabled public Integer categoryProductsCreated { get; set; }

        public TechnicalProductResult() {
            this.success = false;
            this.commercialProductUpdated = false;
            this.warnings = new List<String>();
            this.sellingModelOptionsCreated = 0;
            this.pricebookEntriesCreated = 0;
            this.categoryProductsCreated = 0;
        }
    }

    /**
     * @description Batch result wrapper
     */
    public class BatchCreationResult {
        @AuraEnabled public Integer totalRequested { get; set; }
        @AuraEnabled public Integer totalSucceeded { get; set; }
        @AuraEnabled public Integer totalFailed { get; set; }
        @AuraEnabled public List<TechnicalProductResult> results { get; set; }
        @AuraEnabled public String batchId { get; set; }

        public BatchCreationResult() {
            this.totalRequested = 0;
            this.totalSucceeded = 0;
            this.totalFailed = 0;
            this.results = new List<TechnicalProductResult>();
        }
    }

    /**
     * @description Wrapper class to hold related records queried from commercial products
     * Used to create corresponding records for technical products
     */
    private class CommercialProductRelatedData {
        // Map<CommercialProductId, List<ProductSellingModelOption>>
        public Map<Id, List<ProductSellingModelOption>> sellingModelOptionsByProduct;

        // Map<CommercialProductId, List<PricebookEntry>>
        public Map<Id, List<PricebookEntry>> pricebookEntriesByProduct;

        // Map<CommercialProductId, List<ProductCategoryProduct>>
        public Map<Id, List<ProductCategoryProduct>> categoryProductsByProduct;

        // Standard Pricebook ID (needed because Standard PBE must be created before custom)
        public Id standardPricebookId;

        public CommercialProductRelatedData() {
            this.sellingModelOptionsByProduct = new Map<Id, List<ProductSellingModelOption>>();
            this.pricebookEntriesByProduct = new Map<Id, List<PricebookEntry>>();
            this.categoryProductsByProduct = new Map<Id, List<ProductCategoryProduct>>();
        }
    }

    /**
     * @description Query related records from commercial products for copying to technical products
     * Bulk queries ProductSellingModelOption, PricebookEntry, and ProductCategoryProduct
     * @param commercialProductIds Set of commercial product IDs
     * @return CommercialProductRelatedData containing all related records by product ID
     */
    private static CommercialProductRelatedData queryCommercialProductRelatedRecords(Set<Id> commercialProductIds) {
        CommercialProductRelatedData data = new CommercialProductRelatedData();

        if (commercialProductIds == null || commercialProductIds.isEmpty()) {
            return data;
        }

        // Query Standard Pricebook ID
        List<Pricebook2> stdPricebooks = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        if (!stdPricebooks.isEmpty()) {
            data.standardPricebookId = stdPricebooks[0].Id;
        }

        // Query ProductSellingModelOptions for commercial products
        for (ProductSellingModelOption psmo : [
            SELECT Id, Product2Id, ProductSellingModelId, IsDefault
            FROM ProductSellingModelOption
            WHERE Product2Id IN :commercialProductIds
        ]) {
            if (!data.sellingModelOptionsByProduct.containsKey(psmo.Product2Id)) {
                data.sellingModelOptionsByProduct.put(psmo.Product2Id, new List<ProductSellingModelOption>());
            }
            data.sellingModelOptionsByProduct.get(psmo.Product2Id).add(psmo);
        }

        // Query PricebookEntries for commercial products
        // Order by IsStandard DESC so standard pricebook entries come first
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, Pricebook2.IsStandard, UnitPrice,
                   IsActive, ProductSellingModelId, UseStandardPrice
            FROM PricebookEntry
            WHERE Product2Id IN :commercialProductIds
            ORDER BY Pricebook2.IsStandard DESC
        ]) {
            if (!data.pricebookEntriesByProduct.containsKey(pbe.Product2Id)) {
                data.pricebookEntriesByProduct.put(pbe.Product2Id, new List<PricebookEntry>());
            }
            data.pricebookEntriesByProduct.get(pbe.Product2Id).add(pbe);
        }

        // Query ProductCategoryProducts for commercial products
        for (ProductCategoryProduct pcp : [
            SELECT Id, ProductId, ProductCategoryId
            FROM ProductCategoryProduct
            WHERE ProductId IN :commercialProductIds
        ]) {
            if (!data.categoryProductsByProduct.containsKey(pcp.ProductId)) {
                data.categoryProductsByProduct.put(pcp.ProductId, new List<ProductCategoryProduct>());
            }
            data.categoryProductsByProduct.get(pcp.ProductId).add(pcp);
        }

        return data;
    }

    /**
     * @description Process DML save results and update TechnicalProductResult with errors/warnings
     * @param saveResults Array of Database.SaveResult from DML operation
     * @param indexToCommercialId Map of list index to commercial product ID
     * @param resultMap Map of commercial product ID to TechnicalProductResult
     * @param recordType Name of the record type being processed (for error messages)
     * @param countField Which count field to increment on success
     * @return Number of failures encountered
     */
    private static Integer processRelatedRecordResults(
        Database.SaveResult[] saveResults,
        Map<Integer, Id> indexToCommercialId,
        Map<String, TechnicalProductResult> resultMap,
        String recordType,
        String countField
    ) {
        Integer failureCount = 0;

        for (Integer i = 0; i < saveResults.size(); i++) {
            Id commercialId = indexToCommercialId.get(i);
            if (commercialId == null) continue;

            TechnicalProductResult result = resultMap.get(String.valueOf(commercialId));
            if (result == null) continue;

            if (saveResults[i].isSuccess()) {
                // Increment the appropriate counter
                if (countField == 'sellingModelOptions') {
                    result.sellingModelOptionsCreated++;
                } else if (countField == 'pricebookEntries') {
                    result.pricebookEntriesCreated++;
                } else if (countField == 'categoryProducts') {
                    result.categoryProductsCreated++;
                }
            } else {
                failureCount++;
                String errorMsg = recordType + ' creation failed: ' + saveResults[i].getErrors()[0].getMessage();
                result.warnings.add(errorMsg);
                // Per requirements: if ANY related record fails, mark entire creation as failed
                result.success = false;
                result.errorMessage = errorMsg;
            }
        }

        return failureCount;
    }

    /**
     * @description Create related records (ProductSellingModelOption, PricebookEntry, ProductCategoryProduct)
     * for successfully created technical products
     * @param resultMap Map of commercial product ID to TechnicalProductResult
     * @param techProductIdToCommercialId Map of technical product ID to commercial product ID
     * @param commercialData Related data queried from commercial products
     * @return true if all related records created successfully, false if any failures
     */
    private static Boolean createTechnicalProductRelatedRecords(
        Map<String, TechnicalProductResult> resultMap,
        Map<Id, Id> techProductIdToCommercialId,
        CommercialProductRelatedData commercialData
    ) {
        Boolean allSuccess = true;

        // Lists for bulk insert
        List<ProductSellingModelOption> psmoList = new List<ProductSellingModelOption>();
        List<PricebookEntry> standardPbeList = new List<PricebookEntry>();
        List<PricebookEntry> customPbeList = new List<PricebookEntry>();
        List<ProductCategoryProduct> pcpList = new List<ProductCategoryProduct>();

        // Tracking maps for error association (index -> commercialProductId)
        Map<Integer, Id> psmoIndexToCommercialId = new Map<Integer, Id>();
        Map<Integer, Id> stdPbeIndexToCommercialId = new Map<Integer, Id>();
        Map<Integer, Id> customPbeIndexToCommercialId = new Map<Integer, Id>();
        Map<Integer, Id> pcpIndexToCommercialId = new Map<Integer, Id>();

        for (Id techProductId : techProductIdToCommercialId.keySet()) {
            Id commercialId = techProductIdToCommercialId.get(techProductId);
            TechnicalProductResult result = resultMap.get(String.valueOf(commercialId));

            // Skip if product creation failed or no technical product ID
            if (result == null || !result.success || String.isBlank(result.technicalProductId)) {
                continue;
            }

            // 1. Create ProductSellingModelOptions
            List<ProductSellingModelOption> commercialPsmos = commercialData.sellingModelOptionsByProduct.get(commercialId);
            if (commercialPsmos != null) {
                for (ProductSellingModelOption srcPsmo : commercialPsmos) {
                    ProductSellingModelOption newPsmo = new ProductSellingModelOption();
                    newPsmo.Product2Id = techProductId;
                    newPsmo.ProductSellingModelId = srcPsmo.ProductSellingModelId;
                    newPsmo.IsDefault = srcPsmo.IsDefault;
                    psmoIndexToCommercialId.put(psmoList.size(), commercialId);
                    psmoList.add(newPsmo);
                }
            }

            // 2. Create PricebookEntries (Standard first, then custom)
            // Track unique combinations to avoid duplicates (Pricebook2Id + ProductSellingModelId)
            List<PricebookEntry> commercialPbes = commercialData.pricebookEntriesByProduct.get(commercialId);
            if (commercialPbes != null) {
                Set<String> processedPbeKeys = new Set<String>();
                for (PricebookEntry srcPbe : commercialPbes) {
                    // Skip entries without valid Pricebook2Id
                    if (srcPbe.Pricebook2Id == null) {
                        continue;
                    }

                    // Generate unique key for deduplication (safe string conversion)
                    String pricebookIdStr = String.valueOf(srcPbe.Pricebook2Id);
                    String sellingModelIdStr = srcPbe.ProductSellingModelId != null ? String.valueOf(srcPbe.ProductSellingModelId) : 'null';
                    String pbeKey = pricebookIdStr + '_' + sellingModelIdStr;

                    // Skip if we already have an entry for this Pricebook + SellingModel combination
                    if (processedPbeKeys.contains(pbeKey)) {
                        continue;
                    }
                    processedPbeKeys.add(pbeKey);

                    PricebookEntry newPbe = new PricebookEntry();
                    newPbe.Product2Id = techProductId;
                    newPbe.Pricebook2Id = srcPbe.Pricebook2Id;
                    newPbe.UnitPrice = srcPbe.UnitPrice;
                    newPbe.IsActive = srcPbe.IsActive;
                    // Copy ProductSellingModelId if present
                    if (srcPbe.ProductSellingModelId != null) {
                        newPbe.ProductSellingModelId = srcPbe.ProductSellingModelId;
                    }

                    if (srcPbe.Pricebook2.IsStandard) {
                        stdPbeIndexToCommercialId.put(standardPbeList.size(), commercialId);
                        standardPbeList.add(newPbe);
                    } else {
                        customPbeIndexToCommercialId.put(customPbeList.size(), commercialId);
                        customPbeList.add(newPbe);
                    }
                }
            }

            // 3. Create ProductCategoryProducts
            List<ProductCategoryProduct> commercialPcps = commercialData.categoryProductsByProduct.get(commercialId);
            if (commercialPcps != null) {
                for (ProductCategoryProduct srcPcp : commercialPcps) {
                    ProductCategoryProduct newPcp = new ProductCategoryProduct();
                    newPcp.ProductId = techProductId;
                    newPcp.ProductCategoryId = srcPcp.ProductCategoryId;
                    pcpIndexToCommercialId.put(pcpList.size(), commercialId);
                    pcpList.add(newPcp);
                }
            }
        }

        // Insert ProductSellingModelOptions
        if (!psmoList.isEmpty()) {
            Database.SaveResult[] psmoResults = Database.insert(psmoList, false);
            Integer failures = processRelatedRecordResults(psmoResults, psmoIndexToCommercialId, resultMap, 'ProductSellingModelOption', 'sellingModelOptions');
            if (failures > 0) allSuccess = false;
        }

        // Insert Standard PricebookEntries FIRST (Salesforce requirement)
        if (!standardPbeList.isEmpty()) {
            Database.SaveResult[] stdPbeResults = Database.insert(standardPbeList, false);
            Integer failures = processRelatedRecordResults(stdPbeResults, stdPbeIndexToCommercialId, resultMap, 'Standard PricebookEntry', 'pricebookEntries');
            if (failures > 0) allSuccess = false;
        }

        // Insert Custom PricebookEntries (must be after Standard)
        if (!customPbeList.isEmpty()) {
            Database.SaveResult[] customPbeResults = Database.insert(customPbeList, false);
            Integer failures = processRelatedRecordResults(customPbeResults, customPbeIndexToCommercialId, resultMap, 'Custom PricebookEntry', 'pricebookEntries');
            if (failures > 0) allSuccess = false;
        }

        // Insert ProductCategoryProducts
        if (!pcpList.isEmpty()) {
            Database.SaveResult[] pcpResults = Database.insert(pcpList, false);
            Integer failures = processRelatedRecordResults(pcpResults, pcpIndexToCommercialId, resultMap, 'ProductCategoryProduct', 'categoryProducts');
            if (failures > 0) allSuccess = false;
        }

        return allSuccess;
    }

    /**
     * @description Main entry point for bulk technical product creation
     * @param requests List of TechnicalProductRequest objects
     * @return BatchCreationResult with success/failure details
     */
    public static BatchCreationResult createTechnicalProducts(List<TechnicalProductRequest> requests) {
        BatchCreationResult batchResult = new BatchCreationResult();
        batchResult.totalRequested = requests.size();
        batchResult.batchId = generateBatchId();

        // Set savepoint for rollback if related record creation fails
        Savepoint sp = Database.setSavepoint();

        // Map to track results by commercial product ID
        Map<String, TechnicalProductResult> resultMap = new Map<String, TechnicalProductResult>();
        Map<String, TechnicalProductRequest> requestMap = new Map<String, TechnicalProductRequest>();

        // Collect commercial product IDs (both String and Id versions)
        Set<String> commercialProductIds = new Set<String>();
        Set<Id> commercialProductIdSet = new Set<Id>();
        for (TechnicalProductRequest req : requests) {
            if (String.isNotBlank(req.commercialProductId)) {
                commercialProductIds.add(req.commercialProductId);
                try {
                    commercialProductIdSet.add(Id.valueOf(req.commercialProductId));
                } catch (Exception e) {
                    // Invalid ID format - will be caught in validation
                }
            }
        }

        // Query commercial products to get default field values (including Fortra custom fields and Workday integration fields)
        Map<Id, Product2> commercialProductMap = new Map<Id, Product2>([
            SELECT Id, Name, ProductCode, Description, Family, IsActive,
                   QuantityUnitOfMeasure, StockKeepingUnit, DecompositionScope,
                   Solution_Group__c, Fortra_Product_Type__c, Solution_Category__c,
                   Solution__c, Legacy_Brand_Name__c, Rev_Category__c, Rev_Category_Name__c,
                   Workday_Sales_Item_ID__c, Finance_Business_Unit__c
            FROM Product2
            WHERE Id IN :commercialProductIds
        ]);

        // Query related records from commercial products for copying to technical products
        CommercialProductRelatedData commercialRelatedData = queryCommercialProductRelatedRecords(commercialProductIdSet);

        // Initialize results
        for (TechnicalProductRequest req : requests) {
            TechnicalProductResult result = new TechnicalProductResult();
            result.commercialProductId = req.commercialProductId;
            result.commercialProductCode = req.commercialProductCode;
            result.technicalProductCode = req.technicalProductCode;
            resultMap.put(req.commercialProductId, result);
            requestMap.put(req.commercialProductId, req);
        }

        // Step 1: Create Technical Product2 records
        List<Product2> technicalProducts = new List<Product2>();
        Map<String, String> techProductToCommercial = new Map<String, String>();

        for (TechnicalProductRequest req : requests) {
            try {
                Product2 commercialProduct = commercialProductMap.get(req.commercialProductId);
                Product2 techProduct = createTechnicalProduct2(req, commercialProduct);
                technicalProducts.add(techProduct);
                // We'll map after insert using ProductCode since we don't have Id yet
            } catch (Exception e) {
                TechnicalProductResult result = resultMap.get(req.commercialProductId);
                result.success = false;
                result.errorMessage = 'Failed to create Product2: ' + e.getMessage();
            }
        }

        // Insert Technical Products
        if (!technicalProducts.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(technicalProducts, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                Product2 techProd = technicalProducts[i];
                // Find the corresponding request by product code
                TechnicalProductRequest req = findRequestByTechProductCode(requests, techProd.ProductCode);
                if (req == null) continue;

                TechnicalProductResult result = resultMap.get(req.commercialProductId);

                if (saveResults[i].isSuccess()) {
                    result.technicalProductId = saveResults[i].getId();
                    techProductToCommercial.put(saveResults[i].getId(), req.commercialProductId);
                } else {
                    result.success = false;
                    result.errorMessage = 'Product2 insert failed: ' + saveResults[i].getErrors()[0].getMessage();
                }
            }
        }

        // Step 2: Create ProductFulfillmentDecompRule records
        List<ProductFulfillmentDecompRule> decompRules = new List<ProductFulfillmentDecompRule>();
        Map<String, String> ruleToCommercial = new Map<String, String>();

        for (String techProductId : techProductToCommercial.keySet()) {
            String commercialId = techProductToCommercial.get(techProductId);
            TechnicalProductRequest req = requestMap.get(commercialId);
            TechnicalProductResult result = resultMap.get(commercialId);

            // Only create decomp rule if technical product was created successfully
            if (String.isNotBlank(result.technicalProductId)) {
                try {
                    ProductFulfillmentDecompRule rule = createDecompRule(req, result.technicalProductId);
                    decompRules.add(rule);
                    // Create a unique key for this rule
                    String ruleKey = req.commercialProductId + '_' + result.technicalProductId;
                    ruleToCommercial.put(ruleKey, commercialId);
                } catch (Exception e) {
                    result.warnings.add('Failed to create DecompRule: ' + e.getMessage());
                }
            }
        }

        // Insert Decomposition Rules
        if (!decompRules.isEmpty()) {
            Database.SaveResult[] ruleResults = Database.insert(decompRules, false);

            for (Integer i = 0; i < ruleResults.size(); i++) {
                ProductFulfillmentDecompRule rule = decompRules[i];
                String ruleKey = rule.SourceProductId + '_' + rule.DestinationProductId;
                String commercialId = ruleToCommercial.get(ruleKey);

                if (commercialId != null) {
                    TechnicalProductResult result = resultMap.get(commercialId);

                    if (ruleResults[i].isSuccess()) {
                        result.decompRuleId = ruleResults[i].getId();
                        result.success = true;
                    } else {
                        result.warnings.add('DecompRule insert failed: ' + ruleResults[i].getErrors()[0].getMessage());
                        // Still mark as success if product was created
                        if (String.isNotBlank(result.technicalProductId)) {
                            result.success = true;
                        }
                    }
                }
            }
        }

        // Step 3: Update commercial products to set DecompositionScope = 'OrderLineItem'
        // This enables decomposition to fire at order time for each order line
        List<Product2> commercialProductsToUpdate = new List<Product2>();
        for (TechnicalProductResult result : resultMap.values()) {
            // Only update if technical product and decomp rule were created successfully
            if (result.success && String.isNotBlank(result.decompRuleId)) {
                Product2 commercialProd = commercialProductMap.get(result.commercialProductId);
                // Only update if DecompositionScope is not already set
                if (commercialProd != null && String.isBlank(commercialProd.DecompositionScope)) {
                    Product2 updateProd = new Product2(
                        Id = commercialProd.Id,
                        DecompositionScope = 'OrderLineItem'
                    );
                    commercialProductsToUpdate.add(updateProd);
                }
            }
        }

        // Update Commercial Products with DecompositionScope
        if (!commercialProductsToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(commercialProductsToUpdate, false);

            for (Integer i = 0; i < updateResults.size(); i++) {
                Product2 updatedProd = commercialProductsToUpdate[i];
                TechnicalProductResult result = resultMap.get(updatedProd.Id);

                if (result != null) {
                    if (updateResults[i].isSuccess()) {
                        result.commercialProductUpdated = true;
                    } else {
                        result.warnings.add('Failed to set DecompositionScope on commercial product: ' +
                            updateResults[i].getErrors()[0].getMessage());
                    }
                }
            }
        }

        // Mark commercial products that already had DecompositionScope as "updated" (no change needed)
        for (TechnicalProductResult result : resultMap.values()) {
            if (result.success && !result.commercialProductUpdated) {
                Product2 commercialProd = commercialProductMap.get(result.commercialProductId);
                if (commercialProd != null && String.isNotBlank(commercialProd.DecompositionScope)) {
                    result.commercialProductUpdated = true; // Already had scope set
                }
            }
        }

        // Mark any products without decomp rules but with successful product creation as success
        for (TechnicalProductResult result : resultMap.values()) {
            if (String.isNotBlank(result.technicalProductId) && String.isBlank(result.errorMessage)) {
                result.success = true;
            }
        }

        // Step 4: Create related records (ProductSellingModelOption, PricebookEntry, ProductCategoryProduct)
        // Build techProductIdToCommercialId map from techProductToCommercial (String -> Id)
        Map<Id, Id> techProductIdToCommercialId = new Map<Id, Id>();
        for (String techProductIdStr : techProductToCommercial.keySet()) {
            String commercialIdStr = techProductToCommercial.get(techProductIdStr);
            try {
                techProductIdToCommercialId.put(
                    Id.valueOf(techProductIdStr),
                    Id.valueOf(commercialIdStr)
                );
            } catch (Exception e) {
                // Skip invalid IDs
            }
        }

        // Create related records for technical products
        Boolean relatedRecordsSuccess = createTechnicalProductRelatedRecords(
            resultMap,
            techProductIdToCommercialId,
            commercialRelatedData
        );

        // If any related record creation failed, rollback ALL changes
        // Per requirements: Required behavior - fail if can't create related records
        if (!relatedRecordsSuccess) {
            Database.rollback(sp);

            // Mark all results as failed since we rolled back
            for (TechnicalProductResult result : resultMap.values()) {
                if (result.success) {
                    result.success = false;
                    if (String.isBlank(result.errorMessage)) {
                        result.errorMessage = 'Transaction rolled back due to related record creation failure. Check warnings for details.';
                    }
                    // Clear the IDs since records were rolled back
                    result.technicalProductId = null;
                    result.decompRuleId = null;
                    result.commercialProductUpdated = false;
                }
            }
        }

        // Calculate totals
        for (TechnicalProductResult result : resultMap.values()) {
            batchResult.results.add(result);
            if (result.success) {
                batchResult.totalSucceeded++;
            } else {
                batchResult.totalFailed++;
            }
        }

        return batchResult;
    }

    /**
     * @description Find request by technical product code
     */
    private static TechnicalProductRequest findRequestByTechProductCode(List<TechnicalProductRequest> requests, String productCode) {
        for (TechnicalProductRequest req : requests) {
            if (req.technicalProductCode == productCode) {
                return req;
            }
        }
        return null;
    }

    /**
     * @description Create Technical Product2 record
     * Technical products have NO Type and NO DecompositionScope
     * Default values are inherited from the commercial product
     */
    private static Product2 createTechnicalProduct2(TechnicalProductRequest req, Product2 commercialProduct) {
        Product2 prod = new Product2();

        // Set Technical Product record type
        Id techRecordTypeId = getTechnicalProductRecordTypeId();
        if (techRecordTypeId != null) {
            prod.RecordTypeId = techRecordTypeId;
        }

        // Required fields from request
        prod.Name = req.technicalProductName;
        prod.ProductCode = req.technicalProductCode;

        // Use request values if provided, otherwise inherit from commercial product
        prod.Description = String.isNotBlank(req.technicalProductDescription)
            ? req.technicalProductDescription
            : (commercialProduct != null ? commercialProduct.Description : null);

        prod.Family = String.isNotBlank(req.family)
            ? req.family
            : (commercialProduct != null ? commercialProduct.Family : null);

        prod.IsActive = req.isActive != null
            ? req.isActive
            : (commercialProduct != null ? commercialProduct.IsActive : true);

        // Inherit QuantityUnitOfMeasure from commercial product (required for active products)
        prod.QuantityUnitOfMeasure = commercialProduct != null && String.isNotBlank(commercialProduct.QuantityUnitOfMeasure)
            ? commercialProduct.QuantityUnitOfMeasure
            : 'Each';

        // Inherit StockKeepingUnit if commercial product has one
        if (commercialProduct != null && String.isNotBlank(commercialProduct.StockKeepingUnit)) {
            prod.StockKeepingUnit = commercialProduct.StockKeepingUnit + '-TECH';
        }

        // Inherit Fortra custom fields from commercial product
        if (commercialProduct != null) {
            prod.Solution_Group__c = commercialProduct.Solution_Group__c;
            prod.Fortra_Product_Type__c = commercialProduct.Fortra_Product_Type__c;
            prod.Solution_Category__c = commercialProduct.Solution_Category__c;
            prod.Solution__c = commercialProduct.Solution__c;
            prod.Legacy_Brand_Name__c = commercialProduct.Legacy_Brand_Name__c;
            prod.Rev_Category__c = commercialProduct.Rev_Category__c;
            prod.Rev_Category_Name__c = commercialProduct.Rev_Category_Name__c;
            // Workday integration fields
            // Note: Workday_Sales_Item_ID__c is NOT copied because it has a unique constraint in Salesforce.
            // If the unique constraint is removed, this field can be copied to enable shared billing identifiers.
            // Technical products will need their own Workday IDs or the constraint must be removed.
            prod.Finance_Business_Unit__c = commercialProduct.Finance_Business_Unit__c;
        }

        // Technical products do NOT have Type or DecompositionScope set
        // These fields stay null to indicate they are fulfillment/technical products

        // Apply custom fields (these override any inherited values)
        if (req.customFields != null) {
            for (String fieldName : req.customFields.keySet()) {
                try {
                    prod.put(fieldName, req.customFields.get(fieldName));
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Failed to set custom field ' + fieldName + ': ' + e.getMessage());
                }
            }
        }

        return prod;
    }

    /**
     * @description Create ProductFulfillmentDecompRule record
     * Links commercial product (Source) to technical product (Destination)
     */
    private static ProductFulfillmentDecompRule createDecompRule(TechnicalProductRequest req, String technicalProductId) {
        ProductFulfillmentDecompRule rule = new ProductFulfillmentDecompRule();

        // Name is REQUIRED - generate from commercial product code and tech product code
        rule.Name = req.commercialProductCode + ' to ' + req.technicalProductCode;

        rule.SourceProductId = req.commercialProductId;
        rule.DestinationProductId = technicalProductId;
        rule.Priority = req.decompRulePriority != null ? req.decompRulePriority : 1;

        // Optional fields
        if (String.isNotBlank(req.productClassificationId)) {
            rule.SourceProductClassificationId = req.productClassificationId;
        }
        if (String.isNotBlank(req.rulesetId)) {
            rule.ExecuteOnRuleId = req.rulesetId;
        }

        return rule;
    }

    /**
     * @description Generate unique batch ID
     */
    private static String generateBatchId() {
        return 'TECH-' + DateTime.now().format('yyyyMMdd-HHmmss') + '-' +
               String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 6);
    }

    /**
     * @description Validate technical product requests before creation
     */
    @AuraEnabled
    public static List<String> validateRequests(List<TechnicalProductRequest> requests) {
        List<String> errors = new List<String>();
        Set<String> technicalProductCodes = new Set<String>();
        Set<String> commercialProductIds = new Set<String>();

        for (TechnicalProductRequest req : requests) {
            // Validate required fields
            if (String.isBlank(req.commercialProductId)) {
                errors.add('Commercial Product is required for: ' + req.technicalProductName);
            } else {
                commercialProductIds.add(req.commercialProductId);
            }

            if (String.isBlank(req.technicalProductCode)) {
                errors.add('Technical Product Code is required for: ' + req.technicalProductName);
            } else if (technicalProductCodes.contains(req.technicalProductCode)) {
                errors.add('Duplicate technical product code in request: ' + req.technicalProductCode);
            } else {
                technicalProductCodes.add(req.technicalProductCode);
            }

            if (String.isBlank(req.technicalProductName)) {
                errors.add('Technical Product Name is required for code: ' + req.technicalProductCode);
            }
        }

        // Check commercial products exist
        if (!commercialProductIds.isEmpty()) {
            Set<Id> existingIds = new Map<Id, Product2>(
                [SELECT Id FROM Product2 WHERE Id IN :commercialProductIds]
            ).keySet();

            for (String reqId : commercialProductIds) {
                if (!existingIds.contains(reqId)) {
                    errors.add('Commercial Product not found: ' + reqId);
                }
            }
        }

        // Check for existing technical products with same codes
        if (!technicalProductCodes.isEmpty()) {
            List<Product2> existing = [SELECT ProductCode FROM Product2 WHERE ProductCode IN :technicalProductCodes];
            for (Product2 p : existing) {
                errors.add('Product code already exists: ' + p.ProductCode);
            }
        }

        return errors;
    }

    /**
     * @description Get existing decomposition rules for commercial products
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductFulfillmentDecompRule> getExistingDecompRules(List<String> commercialProductIds) {
        return [
            SELECT Id, SourceProductId, SourceProduct.Name, SourceProduct.ProductCode,
                   DestinationProductId, DestinationProduct.Name, DestinationProduct.ProductCode,
                   Priority, SourceProductClassificationId, ExecuteOnRuleId
            FROM ProductFulfillmentDecompRule
            WHERE SourceProductId IN :commercialProductIds
            ORDER BY SourceProductId, Priority
        ];
    }

    /**
     * @description Get ProductClassifications for decomp rule configuration
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductClassification> getProductClassifications() {
        return [
            SELECT Id, Name
            FROM ProductClassification
            ORDER BY Name
            LIMIT 200
        ];
    }

    /**
     * @description Get available Rulesets for decomp rule configuration
     */
    @AuraEnabled(cacheable=true)
    public static List<Ruleset> getRulesets() {
        return [
            SELECT Id, Name
            FROM Ruleset
            ORDER BY Name
            LIMIT 100
        ];
    }
}