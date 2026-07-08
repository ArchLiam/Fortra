/**
 * @description Apex Before Hook for Revenue Cloud pricing that applies partner pricing
 *              adjustments based on the Quote's selected Partner Pricing Model.
 *              Supports two models:
 *              1. Guaranteed Margin (ADDITIVE): List Price x (1 - SUM(all partner margins%))
 *              2. Discount: List Price x (1 - Billing Partner's Discount%)
 *
 * @author Marc DeBrey
 * @date December 2025
 *
 * @note This implementation uses the RevSignaling.SignalingApexProcessor interface
 *       introduced in Summer '25. Requires "Procedure Plan Orchestration for Pricing"
 *       to be enabled in Revenue Settings.
 *
 * @note Executes AFTER Regional Pricing and BEFORE COLA in the pricing procedure.
 *       Pre_Partner_Price__c captures the price AFTER Regional Pricing has been applied.
 *
 * @version 2.1 - Propagate partner-adjusted price to NetUnitPrice/UnitPrice for OneTime lines
 */
global class PartnerPricingPrehookV2 implements RevSignaling.SignalingApexProcessor {

    // Recursion prevention flag
    private static Boolean isProcessing = false;

    // Model type constants
    private static final String MODEL_GUARANTEED_MARGIN = 'Guaranteed Margin';
    private static final String MODEL_DISCOUNT = 'Discount';

    /**
     * @description Inner class to hold Quote header data extracted from context
     */
    @TestVisible
    private class QuoteHeaderData {
        public Id quoteId;
        public Id billingPartnerId;
        public String partnerPricingModel;
        public String dealType;
        public Id resellerId;
        public Id distributorId;
        public Id referralPartnerId;

        public Boolean hasPartnerPricing() {
            return billingPartnerId != null && String.isNotBlank(partnerPricingModel);
        }
    }

    /**
     * @description Inner class to hold line-level data extracted from the SalesTransactionItem context payload.
     */
    @TestVisible
    private class LineItemContextData {
        public Id lineItemId;
        public String productType;
        public String unit;
        public String solutionGroup;
        public String solutionCategory;
    }

    /**
     * @description Inner class to track margin details for audit trail
     */
    @TestVisible
    private class PartnerMarginDetail {
        public Id partnerId;
        public String partnerName;
        public String partnerRole;
        public Decimal marginPercent;

        public PartnerMarginDetail(Id pId, String pName, String pRole, Decimal margin) {
            this.partnerId = pId;
            this.partnerName = pName;
            this.partnerRole = pRole;
            this.marginPercent = margin;
        }

        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'partnerId' => this.partnerId,
                'partnerName' => this.partnerName,
                'partnerRole' => this.partnerRole,
                'marginPercent' => this.marginPercent
            };
        }
    }

    /**
     * @description Execute method called by Revenue Cloud pricing orchestration
     * @param request The transaction request containing context ID
     * @return TransactionResponse indicating success or failure
     */
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        // Recursion prevention
        if (isProcessing) {
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Partner pricing hook skipped - already processing';
            return response;
        }

        try {
            isProcessing = true;

            String ctxInstanceId = request.ctxInstanceId;

            System.debug(LoggingLevel.INFO, '========================================');
            System.debug(LoggingLevel.INFO, 'PartnerPricingPrehookV2: Starting execution');
            System.debug(LoggingLevel.INFO, 'Context Instance ID: ' + ctxInstanceId);
            System.debug(LoggingLevel.INFO, '========================================');

            if (String.isBlank(ctxInstanceId)) {
                response.status = RevSignaling.TransactionStatus.FAILED;
                response.message = 'Context instance ID is required';
                return response;
            }

            // Query Quote header data from context
            QuoteHeaderData quoteData = queryQuoteHeaderFromContext(ctxInstanceId);

            if (quoteData == null) {
                System.debug(LoggingLevel.WARN, 'Could not extract Quote header from context');
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'Partner pricing skipped - could not read Quote header';
                return response;
            }

            // Early exit if no partner pricing configured - clear any stale values
            if (!quoteData.hasPartnerPricing()) {
                System.debug(LoggingLevel.INFO, 'No Billing Partner or Pricing Model set - clearing stale values');
                Integer cleared = clearPartnerPricingFields(ctxInstanceId);
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'Partner pricing cleared - no billing partner or model configured (' + cleared + ' lines cleared)';
                return response;
            }

            System.debug(LoggingLevel.INFO, 'Quote ID: ' + quoteData.quoteId);
            System.debug(LoggingLevel.INFO, 'Billing Partner: ' + quoteData.billingPartnerId);
            System.debug(LoggingLevel.INFO, 'Pricing Model: ' + quoteData.partnerPricingModel);
            System.debug(LoggingLevel.INFO, 'Deal Type: ' + quoteData.dealType);
            System.debug(LoggingLevel.INFO, 'Reseller: ' + quoteData.resellerId);
            System.debug(LoggingLevel.INFO, 'Distributor: ' + quoteData.distributorId);
            System.debug(LoggingLevel.INFO, 'Referral Partner: ' + quoteData.referralPartnerId);

            // Collect partner IDs based on model type
            Set<Id> partnerIds = collectPartnerIds(quoteData);
            System.debug(LoggingLevel.INFO, 'Partners to process: ' + partnerIds.size());

            if (partnerIds.isEmpty()) {
                Integer cleared = clearPartnerPricingFields(ctxInstanceId);
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'Partner pricing cleared - no valid partner IDs (' + cleared + ' lines cleared)';
                return response;
            }

            // Load Partner Pricing Model records
            Map<Id, List<Partner_Pricing_Model__c>> partnerModels = loadPartnerPricingModels(
                partnerIds, quoteData.partnerPricingModel
            );
            System.debug(LoggingLevel.INFO, 'Loaded pricing models: ' + partnerModels.size());

            // Get partner names for audit trail
            Map<Id, String> partnerNames = getPartnerNames(partnerIds);

            // Query line items from context and process
            Integer linesProcessed = processLineItems(
                ctxInstanceId,
                quoteData,
                partnerModels,
                partnerNames
            );

            System.debug(LoggingLevel.INFO, '----------------------------------------');
            System.debug(LoggingLevel.INFO, 'Partner Pricing Pre-Hook Summary:');
            System.debug(LoggingLevel.INFO, '  - Model: ' + quoteData.partnerPricingModel);
            System.debug(LoggingLevel.INFO, '  - Partners: ' + partnerIds.size());
            System.debug(LoggingLevel.INFO, '  - Lines processed: ' + linesProcessed);
            System.debug(LoggingLevel.INFO, '----------------------------------------');

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Partner pricing applied. Model: ' + quoteData.partnerPricingModel +
                              ', Partners: ' + partnerIds.size() +
                              ', Lines: ' + linesProcessed;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PartnerPricingPrehookV2 error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());

            // Return SUCCESS even on error to avoid blocking pricing
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Partner pricing completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    /**
     * @description Query Quote header fields from the SalesTransaction context tag
     * @param ctxInstanceId The context instance ID
     * @return QuoteHeaderData with extracted fields
     */
    @TestVisible
    private QuoteHeaderData queryQuoteHeaderFromContext(String ctxInstanceId) {
        try {
            // Get the context service
            Context.IndustriesContext ctx = new Context.IndustriesContext();

            // Query the SalesTransaction tag for Quote header data
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransaction' }
            };

            Map<String, Object> apiResponse = ctx.queryTags(queryInput);
            System.debug(LoggingLevel.INFO, 'queryTags API response keys: ' + (apiResponse != null ? String.valueOf(apiResponse.keySet()) : 'null'));

            if (apiResponse == null) {
                System.debug(LoggingLevel.WARN, 'queryTags returned null');
                return null;
            }

            // The API returns a wrapper with isDone, isSuccess, and queryResult
            // We need to extract the nested queryResult first
            Map<String, Object> queryResult;
            if (apiResponse.containsKey('queryResult')) {
                // New format: {isDone, isSuccess, queryResult: {SalesTransaction: [...]}}
                Object qrObj = apiResponse.get('queryResult');
                if (qrObj instanceof Map<String, Object>) {
                    queryResult = (Map<String, Object>) qrObj;
                    System.debug(LoggingLevel.INFO, 'Extracted nested queryResult with keys: ' + queryResult.keySet());
                } else {
                    System.debug(LoggingLevel.WARN, 'queryResult is not a Map: ' + qrObj);
                    return null;
                }
            } else if (apiResponse.containsKey('SalesTransaction')) {
                // Legacy format: {SalesTransaction: [...]} directly
                queryResult = apiResponse;
                System.debug(LoggingLevel.INFO, 'Using legacy response format');
            } else {
                System.debug(LoggingLevel.WARN, 'No SalesTransaction tag in context. Response keys: ' + apiResponse.keySet());
                return null;
            }

            if (!queryResult.containsKey('SalesTransaction')) {
                System.debug(LoggingLevel.WARN, 'SalesTransaction not found in queryResult');
                return null;
            }

            // Extract Quote data from the tag
            Object transactionObj = queryResult.get('SalesTransaction');
            if (transactionObj == null) {
                System.debug(LoggingLevel.WARN, 'SalesTransaction value is null');
                return null;
            }

            System.debug(LoggingLevel.INFO, 'SalesTransaction type: ' + transactionObj);

            // Handle both single record and list responses
            Map<String, Object> transactionData;
            String quoteIdFromPath = null;  // Quote ID extracted from dataPath (new API format)
            if (transactionObj instanceof List<Object>) {
                List<Object> transactions = (List<Object>) transactionObj;
                if (transactions.isEmpty()) {
                    System.debug(LoggingLevel.WARN, 'SalesTransaction list is empty');
                    return null;
                }
                Object firstTransaction = transactions[0];
                System.debug(LoggingLevel.INFO, 'First transaction type: ' + firstTransaction);

                // Check if it's a wrapper with tagValue (new API format)
                if (firstTransaction instanceof Map<String, Object>) {
                    Map<String, Object> txnWrapper = (Map<String, Object>) firstTransaction;
                    if (txnWrapper.containsKey('tagValue')) {
                        // New format: {tagValue: {actual data}, dataPath: [...]}
                        Object tagValue = txnWrapper.get('tagValue');
                        if (tagValue instanceof Map<String, Object>) {
                            transactionData = (Map<String, Object>) tagValue;
                            System.debug(LoggingLevel.INFO, 'Extracted tagValue with keys: ' + transactionData.keySet());
                        } else {
                            System.debug(LoggingLevel.WARN, 'tagValue is not a Map: ' + tagValue);
                            return null;
                        }

                        // Extract Quote ID from dataPath
                        // dataPath structure for SalesTransaction: [contextInstanceId, QuoteId]
                        // Quote ID is at index 1 (also the last element)
                        if (txnWrapper.containsKey('dataPath')) {
                            Object dataPath = txnWrapper.get('dataPath');
                            if (dataPath instanceof List<Object>) {
                                List<Object> pathParts = (List<Object>) dataPath;
                                if (pathParts.size() > 1) {
                                    quoteIdFromPath = String.valueOf(pathParts[1]);
                                    System.debug(LoggingLevel.INFO, 'Extracted Quote ID from dataPath: ' + quoteIdFromPath);
                                }
                            }
                        }
                    } else {
                        // Legacy format: direct data
                        transactionData = txnWrapper;
                        System.debug(LoggingLevel.INFO, 'Using direct transaction data with keys: ' + transactionData.keySet());
                    }
                } else {
                    System.debug(LoggingLevel.WARN, 'First transaction is not a Map: ' + firstTransaction);
                    return null;
                }
            } else if (transactionObj instanceof Map<String, Object>) {
                transactionData = (Map<String, Object>) transactionObj;
                System.debug(LoggingLevel.INFO, 'Direct Map transaction data with keys: ' + transactionData.keySet());
            } else {
                System.debug(LoggingLevel.WARN, 'Unexpected SalesTransaction type: ' + transactionObj);
                return null;
            }

            QuoteHeaderData data = new QuoteHeaderData();
            // Try to get Quote ID from dataPath first (new API format), then fall back to tagValue (legacy)
            Id quoteIdParsed = null;
            if (String.isNotBlank(quoteIdFromPath)) {
                try {
                    quoteIdParsed = Id.valueOf(quoteIdFromPath);
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Could not parse Quote ID from dataPath: ' + quoteIdFromPath);
                }
            }
            data.quoteId = quoteIdParsed != null ? quoteIdParsed : getIdFromTag(transactionData, 'Id');
            data.billingPartnerId = getIdFromTag(transactionData, 'Billing_Partner__c');
            data.partnerPricingModel = getStringFromTag(transactionData, 'Partner_Pricing_Model__c');
            data.dealType = getStringFromTag(transactionData, 'Deal_Type__c');
            data.resellerId = getIdFromTag(transactionData, 'Reseller__c');
            data.distributorId = getIdFromTag(transactionData, 'Distributor__c');
            data.referralPartnerId = getIdFromTag(transactionData, 'Referral_Partner__c');

            return data;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error querying Quote header: ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description Collect partner IDs based on pricing model
     *              - Discount: Only Billing Partner
     *              - Guaranteed Margin: All partners (Billing + Reseller + Distributor + Referral)
     * @param quoteData The Quote header data
     * @return Set of Account IDs for partners
     */
    @TestVisible
    private Set<Id> collectPartnerIds(QuoteHeaderData quoteData) {
        // Delegates to PartnerParticipationResolver (Wave-2 hook-thinning); the shell unpacks the
        // QuoteHeaderData DTO and passes the isGuaranteedMargin boolean so the resolver stays
        // decoupled from the inner type + the MODEL_GUARANTEED_MARGIN constant.
        if (quoteData == null) {
            return new Set<Id>();
        }
        return PartnerParticipationResolver.collectPartnerIds(
            quoteData.billingPartnerId,
            quoteData.partnerPricingModel == MODEL_GUARANTEED_MARGIN,
            quoteData.resellerId,
            quoteData.distributorId,
            quoteData.referralPartnerId
        );
    }

    /**
     * @description Load partner pricing models for given Account IDs
     * @param accountIds Set of partner Account IDs
     * @param modelType The model type to load ("Guaranteed Margin" or "Discount")
     * @return Map of Account ID to pricing model record
     */
    @TestVisible
    private Map<Id, List<Partner_Pricing_Model__c>> loadPartnerPricingModels(Set<Id> accountIds, String modelType) {
        return PartnerPricingServiceV2.getPricingModelCandidates(accountIds, modelType);
    }

    /**
     * @description Get Account names for audit trail
     * @param accountIds Set of Account IDs
     * @return Map of Account ID to Name
     */
    @TestVisible
    private Map<Id, String> getPartnerNames(Set<Id> accountIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) {
            return names;
        }

        for (Account acc : [SELECT Id, Name FROM Account WHERE Id IN :accountIds]) {
            names.put(acc.Id, acc.Name);
        }
        return names;
    }

    /**
     * @description Process line items and apply partner pricing
     * @param ctxInstanceId The context instance ID
     * @param quoteData Quote header data
     * @param partnerModels Map of partner pricing model candidates
     * @param partnerNames Map of partner names for audit
     * @return Number of lines processed
     */
    @TestVisible
    private Integer processLineItems(
        String ctxInstanceId,
        QuoteHeaderData quoteData,
        Map<Id, List<Partner_Pricing_Model__c>> partnerModels,
        Map<Id, String> partnerNames
    ) {
        Integer processedCount = 0;

        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();

            // Query line items from context
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            };

            Map<String, Object> apiResponse = ctx.queryTags(queryInput);

            if (apiResponse == null) {
                System.debug(LoggingLevel.WARN, 'queryTags for SalesTransactionItem returned null');
                return 0;
            }

            // Handle nested response structure: {isDone, isSuccess, queryResult: {SalesTransactionItem: [...]}}
            Map<String, Object> queryResult;
            if (apiResponse.containsKey('queryResult')) {
                Object qrObj = apiResponse.get('queryResult');
                if (qrObj instanceof Map<String, Object>) {
                    queryResult = (Map<String, Object>) qrObj;
                } else {
                    System.debug(LoggingLevel.WARN, 'queryResult is not a Map for line items');
                    return 0;
                }
            } else if (apiResponse.containsKey('SalesTransactionItem')) {
                queryResult = apiResponse;
            } else {
                System.debug(LoggingLevel.WARN, 'No SalesTransactionItem tag in context');
                return 0;
            }

            if (!queryResult.containsKey('SalesTransactionItem')) {
                System.debug(LoggingLevel.WARN, 'SalesTransactionItem not found in queryResult');
                return 0;
            }

            Object itemsObj = queryResult.get('SalesTransactionItem');
            List<Object> rawLineItems;

            if (itemsObj instanceof List<Object>) {
                rawLineItems = (List<Object>) itemsObj;
            } else {
                rawLineItems = new List<Object>{ itemsObj };
            }

            // Extract actual line item data from tagValue wrappers if present
            // Also extract record ID from dataPath since it's not in tagValue
            List<Map<String, Object>> lineItems = new List<Map<String, Object>>();
            for (Object rawItem : rawLineItems) {
                if (rawItem instanceof Map<String, Object>) {
                    Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;
                    if (itemWrapper.containsKey('tagValue')) {
                        // New format: {tagValue: {actual data}, dataPath: [contextId, recordId]}
                        Object tagValue = itemWrapper.get('tagValue');
                        if (tagValue instanceof Map<String, Object>) {
                            // Create a new mutable map - the context API returns immutable maps
                            Map<String, Object> lineItemData = new Map<String, Object>();
                            lineItemData.putAll((Map<String, Object>) tagValue);

                            // Extract record ID and full dataPath from wrapper
                            // dataPath structure varies by tag type:
                            //   SalesTransaction: [contextInstanceId, QuoteId]
                            //   SalesTransactionItem: [contextInstanceId, QuoteId, QuoteLineItemId]
                            // The record ID for the current tag is ALWAYS the LAST element
                            // We need the full dataPath (minus first element) for context updates
                            if (itemWrapper.containsKey('dataPath')) {
                                Object dataPath = itemWrapper.get('dataPath');
                                if (dataPath instanceof List<Object>) {
                                    List<Object> pathParts = (List<Object>) dataPath;
                                    if (!pathParts.isEmpty()) {
                                        // Last element is always the record ID for this tag type
                                        lineItemData.put('_recordId', String.valueOf(pathParts[pathParts.size() - 1]));

                                        // Store the update path (dataPath minus first element) for context updates
                                        // Context API requires nodePath.dataPath without the context instance ID
                                        List<Object> updatePath = pathParts.clone();
                                        if (!updatePath.isEmpty()) {
                                            updatePath.remove(0);  // Remove context instance ID
                                        }
                                        lineItemData.put('_updatePath', updatePath);
                                    }
                                }
                            }
                            lineItems.add(lineItemData);
                        }
                    } else {
                        // Legacy format: direct data - also clone to make mutable
                        Map<String, Object> mutableItem = new Map<String, Object>();
                        mutableItem.putAll(itemWrapper);
                        lineItems.add(mutableItem);
                    }
                }
            }

            System.debug(LoggingLevel.INFO, 'Found ' + lineItems.size() + ' line items to process');

            Map<Id, LineItemContextData> lineContextById = buildLineItemContextDataById(lineItems);

            // Build updates for all line items
            List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();

            for (Map<String, Object> lineItem : lineItems) {
                Map<String, Object> itemUpdate = processLineItem(
                    lineItem,
                    quoteData,
                    partnerModels,
                    partnerNames,
                    lineContextById
                );

                if (itemUpdate != null) {
                    itemUpdates.add(itemUpdate);
                    processedCount++;
                }
            }

            // Submit updates to context
            if (!itemUpdates.isEmpty()) {
                submitContextUpdates(ctx, ctxInstanceId, itemUpdates);
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error processing line items: ' + e.getMessage());
        }

        return processedCount;
    }

    /**
     * @description Build line-level data from SalesTransactionItem context tags
     * @param lineItems Line item nodes returned from context query
     * @return Map of QuoteLineItem ID to resolved line context data
     */
    @TestVisible
    private Map<Id, LineItemContextData> buildLineItemContextDataById(List<Map<String, Object>> lineItems) {
        Map<Id, LineItemContextData> lineContextById = new Map<Id, LineItemContextData>();

        if (lineItems == null || lineItems.isEmpty()) {
            return lineContextById;
        }

        for (Map<String, Object> lineItem : lineItems) {
            LineItemContextData lineData = buildLineItemContextData(lineItem);
            if (lineData != null && lineData.lineItemId != null) {
                lineContextById.put(lineData.lineItemId, lineData);
            }
        }

        return lineContextById;
    }

    /**
     * @description Extract a line item's hierarchy and product metadata from context tags
     * @param lineItem The SalesTransactionItem payload
     * @return Resolved line item context data
     */
    @TestVisible
    private LineItemContextData buildLineItemContextData(Map<String, Object> lineItem) {
        if (lineItem == null) {
            return null;
        }

        String lineItemId = (String) lineItem.get('_recordId');
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'SourceRecordId');
        }
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'Id');
        }

        Id lineItemRecordId = null;
        if (String.isNotBlank(lineItemId)) {
            try {
                lineItemRecordId = Id.valueOf(lineItemId);
            } catch (Exception e) {
                System.debug(LoggingLevel.FINE, 'Ignoring non-Id line item value: ' + lineItemId);
            }
        }

        LineItemContextData lineData = new LineItemContextData();
        lineData.lineItemId = lineItemRecordId;
        lineData.productType = getStringFromTag(lineItem, 'Fortra_Product_Type__c');
        lineData.unit = getStringFromTag(lineItem, 'Unit__c');
        lineData.solutionGroup = getStringFromTag(lineItem, 'Solution_Group__c');
        lineData.solutionCategory = getStringFromTag(lineItem, 'Solution_Category__c');
        return lineData;
    }

    /**
     * @description Process a single line item and calculate partner pricing
     * @param lineItem The line item data from context
     * @param quoteData Quote header data
     * @param partnerModels Map of partner pricing model candidates
     * @param partnerNames Map of partner names for audit
     * @param lineContextById Map of line item metadata extracted from context tags
     * @return Map of field updates or null if no update needed
     */
    @TestVisible
    private Map<String, Object> processLineItem(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, List<Partner_Pricing_Model__c>> partnerModels,
        Map<Id, String> partnerNames,
        Map<Id, LineItemContextData> lineContextById
    ) {
        if (partnerModels == null) {
            partnerModels = new Map<Id, List<Partner_Pricing_Model__c>>();
        }
        if (partnerNames == null) {
            partnerNames = new Map<Id, String>();
        }

        System.debug(LoggingLevel.INFO, '--- Processing Line Item ---');
        System.debug(LoggingLevel.INFO, 'Available fields: ' + lineItem.keySet());

        String lineItemId = (String) lineItem.get('_recordId');
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'SourceRecordId');
        }
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'Id');
        }
        System.debug(LoggingLevel.INFO, 'Line Item Id: ' + lineItemId);

        if (String.isBlank(lineItemId)) {
            System.debug(LoggingLevel.INFO, 'SKIP: No Id field found. _recordId=' + lineItem.get('_recordId'));
            return null;
        }

        Decimal regionalNetUnitPrice = getDecimalFromTag(lineItem, 'RegionalNetUnitPrice__c');
        Decimal unitPrice = getDecimalFromTag(lineItem, 'UnitPrice');
        Decimal listPrice = getDecimalFromTag(lineItem, 'ListPrice');
        System.debug(LoggingLevel.INFO, 'RegionalNetUnitPrice__c from context: ' + regionalNetUnitPrice);
        System.debug(LoggingLevel.INFO, 'UnitPrice from context: ' + unitPrice);
        System.debug(LoggingLevel.INFO, 'ListPrice from context: ' + listPrice);

        Decimal currentPrice = resolveBasePrice(regionalNetUnitPrice, unitPrice, listPrice);

        if (currentPrice == null || currentPrice <= 0) {
            System.debug(LoggingLevel.INFO, 'SKIP: Line ' + lineItemId + ' has no price (RegionalNetUnitPrice__c=' +
                regionalNetUnitPrice + ', UnitPrice=' + unitPrice + ', ListPrice=' + listPrice + ')');
            return null;
        }

        Id lineItemRecordId;
        try {
            lineItemRecordId = Id.valueOf(lineItemId);
        } catch (Exception e) {
            lineItemRecordId = null;
        }

        LineItemContextData lineData = (lineItemRecordId != null && lineContextById != null)
            ? lineContextById.get(lineItemRecordId)
            : null;

        String productType = lineData != null ? lineData.productType : null;
        if (String.isBlank(productType)) {
            productType = getStringFromTag(lineItem, 'Fortra_Product_Type__c');
        }
        if (String.isBlank(productType)) {
            productType = 'Software';
        }

        String unit = lineData != null ? lineData.unit : null;
        if (String.isBlank(unit)) {
            unit = getStringFromTag(lineItem, 'Unit__c');
        }

        String solutionGroup = lineData != null ? lineData.solutionGroup : null;
        if (String.isBlank(solutionGroup)) {
            solutionGroup = getStringFromTag(lineItem, 'Solution_Group__c');
        }

        String solutionCategory = lineData != null ? lineData.solutionCategory : null;
        if (String.isBlank(solutionCategory)) {
            solutionCategory = getStringFromTag(lineItem, 'Solution_Category__c');
        }

        // Partner-pricing dispatch (Discount vs Guaranteed Margin) delegated to the pure
        // PartnerMarginDispatcher (Wave-2 hook-thinning, round-4 incr 3). Margin math stays in
        // PartnerPricingServiceV2; participation reuses PartnerParticipationResolver; the shell threads
        // in the QuoteHeaderData fields as primitives (avoids promoting that inner type).
        PartnerMarginDispatcher.Result dispatch = PartnerMarginDispatcher.resolve(
            quoteData.partnerPricingModel,
            quoteData.billingPartnerId,
            quoteData.dealType,
            quoteData.resellerId,
            quoteData.distributorId,
            quoteData.referralPartnerId,
            partnerModels,
            partnerNames,
            unit,
            solutionGroup,
            solutionCategory,
            currentPrice,
            productType
        );
        if (dispatch == null) {
            System.debug(LoggingLevel.INFO, 'SKIP: Unknown pricing model: ' + quoteData.partnerPricingModel);
            return null;
        }
        Decimal adjustedPrice = dispatch.adjustedPrice;
        Decimal totalPercent = dispatch.totalPercent;

        System.debug(LoggingLevel.INFO, 'SUCCESS: Line ' + lineItemId + ' price adjusted from ' + currentPrice + ' to ' + adjustedPrice);

        // Build result map with nodePath structure required by Context API
        // The updateContextAttributes API requires:
        //   nodePathAndAttributes: [{nodePath: {dataPath: [...]}, attributes: [...]}]
        Map<String, Object> result = new Map<String, Object>();

        // Get the update path (dataPath minus context instance ID)
        Object updatePath = lineItem.get('_updatePath');
        if (updatePath == null) {
            System.debug(LoggingLevel.WARN, 'SKIP: Line ' + lineItemId + ' has no _updatePath for context update');
            return null;
        }
        result.put('nodePath', new Map<String, Object>{ 'dataPath' => updatePath });

        // Margin-detail maps come straight from the dispatcher (Wave-2 thinning, round-4 incr 3).
        List<Map<String, Object>> detailMaps = dispatch.detailMaps;

        List<Map<String, Object>> attributes = PartnerPricingPayloadBuilder.buildPartnerPricingAttributes(
            currentPrice,
            adjustedPrice,
            quoteData.partnerPricingModel,
            detailMaps,
            totalPercent
        );

        result.put('attributes', attributes);

        System.debug(LoggingLevel.DEBUG, 'Line ' + lineItemId + ': ' + currentPrice + ' -> ' + adjustedPrice +
                    ' (' + totalPercent + '% ' + quoteData.partnerPricingModel + ')');

        return result;
    }

    /**
     * @description Determine partner role for a given partner ID
     * @param partnerId The Account ID
     * @param quoteData Quote header data
     * @return Role name string
     */
    @TestVisible
    private String getPartnerRole(Id partnerId, QuoteHeaderData quoteData) {
        // Delegates to PartnerParticipationResolver (Wave-2 hook-thinning).
        return PartnerParticipationResolver.resolvePartnerRole(
            partnerId,
            quoteData.billingPartnerId,
            quoteData.resellerId,
            quoteData.distributorId,
            quoteData.referralPartnerId
        );
    }

    /**
     * @description Submit context attribute updates using the correct Context API format
     *              The API requires: {contextId, nodePathAndAttributes: [{nodePath: {dataPath}, attributes}]}
     * @param ctx The IndustriesContext instance
     * @param ctxInstanceId Context instance ID
     * @param itemUpdates List of item updates with nodePath and attributes
     */
    @TestVisible
    private void submitContextUpdates(
        Context.IndustriesContext ctx,
        String ctxInstanceId,
        List<Map<String, Object>> itemUpdates
    ) {
        try {
            // Context API requires nodePathAndAttributes key, NOT items
            // Each update must have: {nodePath: {dataPath: [...]}, attributes: [...]}
            Map<String, Object> updateInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'nodePathAndAttributes' => itemUpdates
            };

            System.debug(LoggingLevel.INFO, '--- PREHOOK: SUBMITTING CONTEXT UPDATE ---');
            System.debug(LoggingLevel.INFO, 'Context ID: ' + ctxInstanceId);
            System.debug(LoggingLevel.INFO, 'Number of items: ' + itemUpdates.size());

            Map<String, Object> updateResult = ctx.updateContextAttributes(updateInput);
            System.debug(LoggingLevel.INFO, 'Successfully submitted ' + itemUpdates.size() + ' item updates');
            System.debug(LoggingLevel.INFO, 'Update result: ' + updateResult);

        } catch (Exception e) {
            // Handle non-updatable state (e.g., delete operations)
            if (e.getMessage() != null && e.getMessage().containsIgnoreCase('not in updatable state')) {
                System.debug(LoggingLevel.INFO, 'Context not in updatable state - skipping updates');
            } else {
                System.debug(LoggingLevel.ERROR, 'Error updating context: ' + e.getMessage());
                System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            }
        }
    }

    // ============================================
    // Tag Value Extraction Helper Methods
    // ============================================

    /**
     * @description Extract the raw value from a field in tag data.
     *              The Context API returns field values in a wrapper structure:
     *              fieldName: { tagValue: actualValue, dmlStatus: "...", ... }
     *              This method handles both the new wrapped format and legacy direct values.
     * @param tagData The tag data map containing fields
     * @param fieldName The field name to extract
     * @return The unwrapped value or null
     */
    // Delegates to shared ContextTagReader (Wave-2 decomposition, increment 9 — verified
    // functionally equivalent; the only prior diff was a FINE-level debug line, no behavior change).
    @TestVisible
    private Object extractFieldValue(Map<String, Object> tagData, String fieldName) {
        return ContextTagReader.extractFieldValue(tagData, fieldName);
    }

    /**
     * @description Resolve the base price for partner margin calculations.
     *              Regional Services Pricing writes to RegionalNetUnitPrice__c (not UnitPrice),
     *              so that field must be checked first when present.
     */
    @TestVisible
    private Decimal resolveBasePrice(Decimal regionalNetUnitPrice, Decimal unitPrice, Decimal listPrice) {
        // Delegates to shared PartnerNetResolutionCalculator (Wave-2 decomposition, increment 10 —
        // byte-identical to resolvePreProcedurePrice).
        return PartnerNetResolutionCalculator.resolvePreProcedurePrice(regionalNetUnitPrice, unitPrice, listPrice);
    }

    /**
     * @description Extract String value from tag data
     */
    @TestVisible
    private String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        return ContextTagReader.getStringFromTag(tagData, fieldName);
    }

    /**
     * @description Extract Decimal value from tag data
     */
    @TestVisible
    private Decimal getDecimalFromTag(Map<String, Object> tagData, String fieldName) {
        return ContextTagReader.getDecimalFromTag(tagData, fieldName);
    }

    /**
     * @description Extract Id value from tag data
     */
    @TestVisible
    private Id getIdFromTag(Map<String, Object> tagData, String fieldName) {
        return ContextTagReader.getIdFromTag(tagData, fieldName);
    }

    /**
     * @description Clear all partner pricing fields on every line item in the context.
     *              Called when the hook determines partner pricing should NOT apply
     *              (no billing partner, no model, or no valid partner IDs) so that
     *              stale values from a previous reprice do not persist.
     * @param ctxInstanceId The context instance ID
     * @return Number of line items cleared
     */
    @TestVisible
    private Integer clearPartnerPricingFields(String ctxInstanceId) {
        Integer clearedCount = 0;

        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();

            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            };

            Map<String, Object> apiResponse = ctx.queryTags(queryInput);

            if (apiResponse == null) {
                System.debug(LoggingLevel.WARN, 'queryTags returned null for clear operation');
                return 0;
            }

            // Handle nested response structure
            Map<String, Object> queryResult;
            if (apiResponse.containsKey('queryResult')) {
                Object qrObj = apiResponse.get('queryResult');
                if (qrObj instanceof Map<String, Object>) {
                    queryResult = (Map<String, Object>) qrObj;
                } else {
                    System.debug(LoggingLevel.WARN, 'queryResult is not a Map for clear operation');
                    return 0;
                }
            } else if (apiResponse.containsKey('SalesTransactionItem')) {
                queryResult = apiResponse;
            } else {
                System.debug(LoggingLevel.WARN, 'No SalesTransactionItem tag for clear operation');
                return 0;
            }

            if (!queryResult.containsKey('SalesTransactionItem')) {
                System.debug(LoggingLevel.WARN, 'SalesTransactionItem not found for clear operation');
                return 0;
            }

            Object itemsObj = queryResult.get('SalesTransactionItem');
            List<Object> rawLineItems;

            if (itemsObj instanceof List<Object>) {
                rawLineItems = (List<Object>) itemsObj;
            } else {
                rawLineItems = new List<Object>{ itemsObj };
            }

            List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();

            for (Object rawItem : rawLineItems) {
                if (rawItem instanceof Map<String, Object>) {
                    Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;

                    if (itemWrapper.containsKey('dataPath')) {
                        Object dataPath = itemWrapper.get('dataPath');
                        if (dataPath instanceof List<Object>) {
                            List<Object> pathParts = (List<Object>) dataPath;
                            if (!pathParts.isEmpty()) {
                                List<Object> updatePath = pathParts.clone();
                                updatePath.remove(0);  // Remove context instance ID

                                Map<String, Object> result = new Map<String, Object>();
                                result.put('nodePath', new Map<String, Object>{ 'dataPath' => updatePath });

                                List<Map<String, Object>> attributes = new List<Map<String, Object>>();

                                // Clear all partner pricing output fields
                                for (String fieldName : new List<String>{
                                    'Pre_Partner_Price__c',
                                    'Partner_Adjusted_Price__c',
                                    'Partner_Discount_Percent__c',
                                    'Partner_Pricing_Model_Applied__c',
                                    'Partner_Pricing_Source__c',
                                    'Partner_Margin_Detail__c',
                                    'Partner_Pricing_Warning__c',
                                    'PartnerUnitPrice',
                                    'PartnerDiscountPercent'
                                }) {
                                    attributes.add(new Map<String, Object>{
                                        'attributeName' => fieldName,
                                        'attributeValue' => null
                                    });
                                }

                                result.put('attributes', attributes);
                                itemUpdates.add(result);
                                clearedCount++;
                            }
                        }
                    }
                }
            }

            if (!itemUpdates.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'Clearing partner pricing fields on ' + itemUpdates.size() + ' line items');
                submitContextUpdates(ctx, ctxInstanceId, itemUpdates);
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error clearing partner pricing fields: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        }

        return clearedCount;
    }

}