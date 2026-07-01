/**
 * @description Invocable Apex action to initiate bulk multi-currency price updates.
 *              This class bridges Screen Flow to Batch Apex for processing 200+ products.
 *
 *              Called from: Fortra_Bulk_Price_Update_Flow
 *
 *              Responsibilities:
 *              1. Validate input (categories required)
 *              2. Count products to be processed
 *              3. Start batch job with configurable batch size
 *              4. Return job ID and product count to Flow
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-01
 */
public with sharing class Fortra_BulkPriceUpdateInvocable {

    // Default batch size (50 products per batch)
    private static final Integer DEFAULT_BATCH_SIZE = 50;

    /**
     * @description Input wrapper for the invocable action
     */
    public class BulkPriceUpdateRequest {
        @InvocableVariable(
            label='Solution Categories'
            description='Semicolon-separated list of Solution Category values to process'
            required=true
        )
        public String solutionCategories;

        @InvocableVariable(
            label='Pricebook IDs'
            description='Semicolon-separated list of Pricebook2 IDs to apply updates to'
            required=true
        )
        public String pricebookIds;

        @InvocableVariable(
            label='Batch Size'
            description='Number of products to process per batch (default: 50)'
            required=false
        )
        public Integer batchSize;

        @InvocableVariable(
            label='Preview Only'
            description='When true, returns product count and estimates without starting a batch job'
            required=false
        )
        public Boolean previewOnly;
    }

    /**
     * @description Output wrapper for the invocable action
     */
    public class BulkPriceUpdateResult {
        @InvocableVariable(label='Success' description='Whether the batch was successfully started')
        public Boolean success;

        @InvocableVariable(label='Job ID' description='The AsyncApexJob ID for tracking')
        public String jobId;

        @InvocableVariable(label='Product Count' description='Number of products to be processed')
        public Integer productCount;

        @InvocableVariable(label='Error Message' description='Error message if batch failed to start')
        public String errorMessage;

        @InvocableVariable(label='Categories Processed' description='List of categories being processed')
        public String categoriesProcessed;

        @InvocableVariable(label='Pricebooks Processed' description='Comma-separated names of selected pricebooks')
        public String pricebooksProcessed;

        @InvocableVariable(label='Estimated PBE Count' description='Estimated number of PricebookEntries to create/update')
        public Integer estimatedPBECount;

        @InvocableVariable(label='Pricebook Estimates' description='Per-pricebook PBE count breakdown')
        public List<PricebookEstimate> pricebookEstimates;

        @InvocableVariable(label='Pricebook Breakdown HTML' description='Pre-rendered <li> rows for the preview screen')
        public String pricebookBreakdownHtml;

        @InvocableVariable(label='Standard Warning' description='Warning text when Standard PB is excluded but USD Standard PBEs are missing')
        public String standardWarning;

        @InvocableVariable(label='Blocking Warning' description='True when the run cannot proceed and Flow should route to a block screen')
        public Boolean blockingWarning;
    }

    /**
     * @description Per-pricebook estimate row used in the preview breakdown
     */
    public class PricebookEstimate {
        @InvocableVariable(label='Pricebook ID')
        public String pricebookId;

        @InvocableVariable(label='Pricebook Name')
        public String pricebookName;

        @InvocableVariable(label='Is Standard')
        public Boolean isStandard;

        @InvocableVariable(label='Estimated PBE Count')
        public Integer estimatedPBECount;
    }

    /**
     * @description Main invocable method to start the bulk price update batch
     * @param requests List of bulk update requests
     * @return List of results with job IDs and product counts
     */
    @InvocableMethod(
        label='Start Bulk Multi-Currency Price Update'
        description='Initiates a batch job to update prices for products in selected Solution Categories across all currencies'
        category='Pricing'
    )
    public static List<BulkPriceUpdateResult> startBulkPriceUpdate(List<BulkPriceUpdateRequest> requests) {
        List<BulkPriceUpdateResult> results = new List<BulkPriceUpdateResult>();

        for (BulkPriceUpdateRequest request : requests) {
            results.add(processRequest(request));
        }

        return results;
    }

    /**
     * @description Process a single bulk update request
     * @param request The input request
     * @return The result with job ID or error
     */
    private static BulkPriceUpdateResult processRequest(BulkPriceUpdateRequest request) {
        BulkPriceUpdateResult result = new BulkPriceUpdateResult();
        result.success = false;
        result.blockingWarning = false;

        try {
            // Validate categories input
            if (String.isBlank(request.solutionCategories)) {
                result.errorMessage = 'At least one Solution Category is required';
                return result;
            }

            // Parse categories (semicolon-separated)
            Set<String> categories = parseSolutionCategories(request.solutionCategories);

            if (categories.isEmpty()) {
                result.errorMessage = 'No valid Solution Categories provided';
                return result;
            }

            // Validate pricebookIds input
            if (String.isBlank(request.pricebookIds)) {
                result.errorMessage = 'At least one Pricebook is required';
                return result;
            }

            Set<Id> pricebookIdSet = parsePricebookIds(request.pricebookIds);

            if (pricebookIdSet.isEmpty()) {
                result.errorMessage = 'No valid Pricebook IDs provided';
                return result;
            }

            System.debug(LoggingLevel.INFO, 'Parsed categories: ' + categories);
            System.debug(LoggingLevel.INFO, 'Parsed pricebookIds: ' + pricebookIdSet);

            // Count products to process
            Integer productCount = countProducts(categories);

            if (productCount == 0) {
                result.errorMessage = 'No active products found for the selected categories';
                result.productCount = 0;
                result.categoriesProcessed = String.join(new List<String>(categories), '; ');
                return result;
            }

            // Build per-pricebook estimates (one row per selected, active pricebook)
            // Standard sorted first via IsStandard DESC, Name ASC
            Integer currencyCount = countActiveCurrencies();
            List<PricebookEstimate> estimates = new List<PricebookEstimate>();
            List<String> pricebookLabels = new List<String>();
            Id standardPbId = null;

            String breakdownHtml = '';
            for (Pricebook2 pb : [
                SELECT Id, Name, IsStandard
                FROM Pricebook2
                WHERE Id IN :pricebookIdSet
                AND IsActive = true
                ORDER BY IsStandard DESC, Name ASC
            ]) {
                if (pb.IsStandard) {
                    standardPbId = pb.Id;
                }
                PricebookEstimate est = new PricebookEstimate();
                est.pricebookId = pb.Id;
                est.pricebookName = pb.Name;
                est.isStandard = pb.IsStandard;
                est.estimatedPBECount = productCount * currencyCount;
                estimates.add(est);
                String label = pb.Name + (pb.IsStandard ? ' (Standard)' : '');
                pricebookLabels.add(label);
                breakdownHtml += '<li><strong>' + label.escapeHtml4() + '</strong>: '
                    + est.estimatedPBECount + ' PricebookEntries</li>';
            }

            if (estimates.isEmpty()) {
                result.errorMessage = 'Selected Pricebooks were not found or are inactive';
                return result;
            }

            // If Standard is NOT in the selection, verify USD Standard PBEs exist
            // for every product in scope (source-of-truth read in the batch).
            if (standardPbId == null) {
                Integer missingUSDStandard = countProductsMissingUSDStandard(categories);
                if (missingUSDStandard > 0) {
                    result.standardWarning = missingUSDStandard +
                        ' product(s) have no USD price in the Standard Pricebook. ' +
                        'Include the Standard Pricebook in your selection or fix the data before proceeding.';
                    result.blockingWarning = true;
                }
            }

            // Populate common result fields
            result.success = true;
            result.productCount = productCount;
            result.categoriesProcessed = String.join(new List<String>(categories), '; ');
            result.pricebooksProcessed = String.join(pricebookLabels, ', ');
            result.estimatedPBECount = productCount * estimates.size() * currencyCount;
            result.pricebookEstimates = estimates;
            result.pricebookBreakdownHtml = breakdownHtml;

            // If preview only, return counts without starting a batch
            if (request.previewOnly == true) {
                System.debug(LoggingLevel.INFO, 'Preview only - Products: ' + productCount +
                    ', Pricebooks: ' + estimates.size() +
                    ', Estimated PBEs: ' + result.estimatedPBECount +
                    ', BlockingWarning: ' + result.blockingWarning);
                return result;
            }

            // Block start when Standard is excluded but USD Standard PBEs missing
            if (result.blockingWarning == true) {
                result.success = false;
                result.errorMessage = result.standardWarning;
                return result;
            }

            // Determine batch size
            Integer batchSize = (request.batchSize != null && request.batchSize > 0)
                ? request.batchSize
                : DEFAULT_BATCH_SIZE;

            // Start batch job
            Fortra_BulkPriceUpdateBatch batch = new Fortra_BulkPriceUpdateBatch(
                categories,
                pricebookIdSet,
                UserInfo.getUserId()
            );

            Id jobId = Database.executeBatch(batch, batchSize);

            System.debug(LoggingLevel.INFO, 'Batch job started: ' + jobId);
            System.debug(LoggingLevel.INFO, 'Products to process: ' + productCount);
            System.debug(LoggingLevel.INFO, 'Estimated PBEs: ' + result.estimatedPBECount);

            result.jobId = jobId;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error starting bulk price update: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            result.success = false;
            result.errorMessage = 'Failed to start batch: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Parse semicolon-separated pricebook ID string into a typed Set
     * @param idString The semicolon-separated IDs (or null/blank)
     * @return Set of valid Ids; entries that don't cast to Id are skipped
     */
    @TestVisible
    private static Set<Id> parsePricebookIds(String idString) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(idString)) {
            return ids;
        }
        for (String token : idString.split(';')) {
            String trimmed = token.trim();
            if (String.isBlank(trimmed)) continue;
            try {
                ids.add((Id) trimmed);
            } catch (StringException e) {
                // Skip invalid Id tokens silently; processRequest validates emptiness afterward
            }
        }
        return ids;
    }

    /**
     * @description Count products in the selected categories that lack a USD entry in the Standard Pricebook.
     *              Used to detect whether excluding Standard from the selection would break the run.
     */
    @TestVisible
    private static Integer countProductsMissingUSDStandard(Set<String> categories) {
        return [
            SELECT COUNT()
            FROM Product2
            WHERE Solution_Category__c IN :categories
            AND IsActive = true
            AND Id NOT IN (
                SELECT Product2Id FROM PricebookEntry
                WHERE Pricebook2.IsStandard = true
                AND CurrencyIsoCode = 'USD'
                AND IsActive = true
            )
        ];
    }

    /**
     * @description Parse semicolon-separated category string into a Set
     * @param categoriesString The semicolon-separated categories
     * @return Set of trimmed, non-empty category values
     */
    @TestVisible
    private static Set<String> parseSolutionCategories(String categoriesString) {
        Set<String> categories = new Set<String>();

        if (String.isBlank(categoriesString)) {
            return categories;
        }

        for (String category : categoriesString.split(';')) {
            String trimmed = category.trim();
            if (String.isNotBlank(trimmed)) {
                categories.add(trimmed);
            }
        }

        return categories;
    }

    /**
     * @description Count active products for the given Solution Categories
     * @param categories Set of category values
     * @return Count of matching products
     */
    @TestVisible
    private static Integer countProducts(Set<String> categories) {
        return [
            SELECT COUNT()
            FROM Product2
            WHERE Solution_Category__c IN :categories
            AND IsActive = true
        ];
    }

    /**
     * @description Count active pricebooks. Used only by the AuraEnabled getProductPreview
     *              method below. The Invocable estimation path uses pricebookIdSet.size().
     */
    @TestVisible
    private static Integer countActivePricebooks() {
        return [SELECT COUNT() FROM Pricebook2 WHERE IsActive = true];
    }

    /**
     * @description Count active currencies from CMDT
     * @return Number of active currency formulas
     */
    private static Integer countActiveCurrencies() {
        return [
            SELECT COUNT()
            FROM Currency_Conversion_Formula__mdt
            WHERE Is_Active__c = true
        ];
    }

    /**
     * @description Get distinct Solution Category values for Flow picklist
     *              Called by Flow to populate the multi-select options
     * @return List of distinct Solution Category values
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getSolutionCategories() {
        Set<String> categories = new Set<String>();

        for (AggregateResult ar : [
            SELECT Solution_Category__c
            FROM Product2
            WHERE Solution_Category__c != NULL
            AND IsActive = true
            GROUP BY Solution_Category__c
            ORDER BY Solution_Category__c
        ]) {
            String category = (String)ar.get('Solution_Category__c');
            if (String.isNotBlank(category)) {
                categories.add(category);
            }
        }

        List<String> result = new List<String>(categories);
        result.sort();
        return result;
    }

    /**
     * @description Get product preview for selected categories
     *              Called by Flow to show preview before confirming
     * @param categoriesString Semicolon-separated list of categories
     * @return Map with count and first N product names
     */
    @AuraEnabled
    public static Map<String, Object> getProductPreview(String categoriesString) {
        Map<String, Object> preview = new Map<String, Object>();

        Set<String> categories = parseSolutionCategories(categoriesString);

        if (categories.isEmpty()) {
            preview.put('count', 0);
            preview.put('products', new List<String>());
            preview.put('error', 'No categories selected');
            return preview;
        }

        // Get count
        Integer count = countProducts(categories);
        preview.put('count', count);

        // Get first 25 product names for preview
        List<String> productNames = new List<String>();
        for (Product2 p : [
            SELECT Name, ProductCode
            FROM Product2
            WHERE Solution_Category__c IN :categories
            AND IsActive = true
            ORDER BY Name
            LIMIT 25
        ]) {
            productNames.add(p.Name + (String.isNotBlank(p.ProductCode) ? ' (' + p.ProductCode + ')' : ''));
        }
        preview.put('products', productNames);

        // Add pricebook and currency counts for estimation
        preview.put('pricebookCount', countActivePricebooks());
        preview.put('currencyCount', countActiveCurrencies());

        return preview;
    }

    /**
     * @description Check the status of a running batch job
     * @param jobId The AsyncApexJob ID
     * @return Map with job status details
     */
    @AuraEnabled
    public static Map<String, Object> checkBatchStatus(String jobId) {
        Map<String, Object> status = new Map<String, Object>();

        if (String.isBlank(jobId)) {
            status.put('error', 'Job ID is required');
            return status;
        }

        try {
            AsyncApexJob job = [
                SELECT Id, Status, JobItemsProcessed, TotalJobItems,
                       NumberOfErrors, CreatedDate, CompletedDate,
                       ExtendedStatus
                FROM AsyncApexJob
                WHERE Id = :jobId
                LIMIT 1
            ];

            status.put('status', job.Status);
            status.put('itemsProcessed', job.JobItemsProcessed);
            status.put('totalItems', job.TotalJobItems);
            status.put('errors', job.NumberOfErrors);
            status.put('createdDate', job.CreatedDate);
            status.put('completedDate', job.CompletedDate);
            status.put('extendedStatus', job.ExtendedStatus);

            // Calculate progress percentage
            Integer progress = 0;
            if (job.TotalJobItems != null && job.TotalJobItems > 0) {
                progress = (job.JobItemsProcessed * 100) / job.TotalJobItems;
            }
            status.put('progressPercent', progress);

            // Determine if complete
            status.put('isComplete', job.Status == 'Completed' || job.Status == 'Failed' || job.Status == 'Aborted');

        } catch (Exception e) {
            status.put('error', 'Job not found: ' + e.getMessage());
        }

        return status;
    }
}