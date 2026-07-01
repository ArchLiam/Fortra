/**
 * @description Apex Before Hook for Revenue Cloud pricing that resolves Partner_Pricing_Model__c
 *              and stamps PartnerDiscountPercent (+ audit/warnings) on every eligible line.
 *              Partner dollar discount is applied in DPP V16 (ManualDiscount on InputUnitPrice).
 *
 *              Supports two models:
 *              1. Guaranteed Margin (ADDITIVE): SUM(all partner margins%) → PartnerDiscountPercent
 *              2. Discount: Billing Partner's Discount% → PartnerDiscountPercent
 *
 * @author Marc DeBrey
 * @date December 2025
 *
 * @note Executes in Procedure Plan after regional/attribute prep and before DPP.
 *       Stamps maintenance Base_Price__c / Pre_Partner_Price__c from the contributor perpetual
 *       line's pre-discount base (spreadsheet: maint rate x perpetual base before partner).
 *
 * @version 3.2 - Carry perpetual partner/manual % to derived maintenance; pre-discount base for derived list
 */
global class PartnerPricingPrehook implements RevSignaling.SignalingApexProcessor {

    // Recursion prevention flag
    private static Boolean isProcessing = false;

    // Model type constants
    private static final String MODEL_GUARANTEED_MARGIN = 'Guaranteed Margin';
    private static final String MODEL_DISCOUNT = 'Discount';
    private static final String PARTNER_SOURCE_PERCENT_ONLY = 'System Calculated (Pre-Procedure, Percent Only)';

    /**
     * @description Inner class to hold Quote header data extracted from context
     */
    @TestVisible
    private class QuoteHeaderData {
        public Id quoteId;
        public Id billingPartnerId;
        public String partnerPricingModel;
        public Id resellerId;
        public Id distributorId;
        public Id referralPartnerId;

        public Boolean hasPartnerPricing() {
            return billingPartnerId != null && String.isNotBlank(partnerPricingModel);
        }
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
            System.debug(LoggingLevel.INFO, 'PartnerPricingPrehook: Starting execution');
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
            Map<Id, Partner_Pricing_Model__c> partnerModels = loadPartnerPricingModels(
                partnerIds, quoteData.partnerPricingModel
            );
            System.debug(LoggingLevel.INFO, 'Loaded pricing models: ' + partnerModels.size());

            // Get partner names for audit trail
            Map<Id, String> partnerNames = getPartnerNames(partnerIds);

            // Check for partners missing the required pricing model and build warning
            String partnerWarning = buildMissingModelWarning(
                partnerIds,
                partnerModels,
                partnerNames,
                quoteData
            );

            // If no pricing models found, we may still need to set warnings
            if (partnerModels.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'No pricing models found for partners');

                // If there's a warning, still process line items to set the warning attribute
                if (String.isNotBlank(partnerWarning)) {
                    System.debug(LoggingLevel.INFO, 'Setting warning on line items: ' + partnerWarning);
                    Integer linesWithWarning = processLineItemsWithWarningOnly(
                        ctxInstanceId,
                        partnerWarning
                    );
                    response.status = RevSignaling.TransactionStatus.SUCCESS;
                    response.message = 'Partner pricing skipped - ' + partnerWarning + ' (' + linesWithWarning + ' lines warned)';
                    return response;
                }

                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'Partner pricing skipped - no pricing models configured for partners';
                return response;
            }

            // Query line items from context and process
            Integer linesProcessed = processLineItems(
                ctxInstanceId,
                quoteData,
                partnerModels,
                partnerNames,
                partnerWarning
            );

            System.debug(LoggingLevel.INFO, '----------------------------------------');
            System.debug(LoggingLevel.INFO, 'Partner Pricing Pre-Hook Summary:');
            System.debug(LoggingLevel.INFO, '  - Model: ' + quoteData.partnerPricingModel);
            System.debug(LoggingLevel.INFO, '  - Partners: ' + partnerIds.size());
            System.debug(LoggingLevel.INFO, '  - Lines processed: ' + linesProcessed);
            System.debug(LoggingLevel.INFO, '----------------------------------------');

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Partner pricing percent stamped. Model: ' + quoteData.partnerPricingModel +
                              ', Partners: ' + partnerIds.size() +
                              ', Lines: ' + linesProcessed;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PartnerPricingPrehook error: ' + e.getMessage());
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

            return parseQuoteHeaderApiResponse(ctx.queryTags(queryInput));

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error querying Quote header: ' + e.getMessage());
            return null;
        }
    }

    @TestVisible
    private QuoteHeaderData parseQuoteHeaderApiResponse(Map<String, Object> apiResponse) {
        System.debug(LoggingLevel.INFO, 'queryTags API response keys: ' + (apiResponse != null ? String.valueOf(apiResponse.keySet()) : 'null'));

        if (apiResponse == null) {
            System.debug(LoggingLevel.WARN, 'queryTags returned null');
            return null;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            if (qrObj instanceof Map<String, Object>) {
                queryResult = (Map<String, Object>) qrObj;
                System.debug(LoggingLevel.INFO, 'Extracted nested queryResult with keys: ' + queryResult.keySet());
            } else {
                System.debug(LoggingLevel.WARN, 'queryResult is not a Map: ' + qrObj);
                return null;
            }
        } else if (apiResponse.containsKey('SalesTransaction')) {
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

        Object transactionObj = queryResult.get('SalesTransaction');
        if (transactionObj == null) {
            System.debug(LoggingLevel.WARN, 'SalesTransaction value is null');
            return null;
        }

        System.debug(LoggingLevel.INFO, 'SalesTransaction type: ' + transactionObj);

        Map<String, Object> transactionData;
        String quoteIdFromPath = null;
        if (transactionObj instanceof List<Object>) {
            List<Object> transactions = (List<Object>) transactionObj;
            if (transactions.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'SalesTransaction list is empty');
                return null;
            }
            Object firstTransaction = transactions[0];
            System.debug(LoggingLevel.INFO, 'First transaction type: ' + firstTransaction);

            if (firstTransaction instanceof Map<String, Object>) {
                Map<String, Object> txnWrapper = (Map<String, Object>) firstTransaction;
                if (txnWrapper.containsKey('tagValue')) {
                    Object tagValue = txnWrapper.get('tagValue');
                    if (tagValue instanceof Map<String, Object>) {
                        transactionData = (Map<String, Object>) tagValue;
                        System.debug(LoggingLevel.INFO, 'Extracted tagValue with keys: ' + transactionData.keySet());
                    } else {
                        System.debug(LoggingLevel.WARN, 'tagValue is not a Map: ' + tagValue);
                        return null;
                    }

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
        data.resellerId = getIdFromTag(transactionData, 'Reseller__c');
        data.distributorId = getIdFromTag(transactionData, 'Distributor__c');
        data.referralPartnerId = getIdFromTag(transactionData, 'Referral_Partner__c');

        return data;
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
        Set<Id> partnerIds = new Set<Id>();

        if (quoteData == null || quoteData.billingPartnerId == null) {
            return partnerIds;
        }

        // Billing Partner always participates
        partnerIds.add(quoteData.billingPartnerId);

        // For Guaranteed Margin, include all partners
        if (quoteData.partnerPricingModel == MODEL_GUARANTEED_MARGIN) {
            if (quoteData.resellerId != null) {
                partnerIds.add(quoteData.resellerId);
            }
            if (quoteData.distributorId != null) {
                partnerIds.add(quoteData.distributorId);
            }
            if (quoteData.referralPartnerId != null) {
                partnerIds.add(quoteData.referralPartnerId);
            }
        }
        // For Discount model, only billing partner (already added)

        return partnerIds;
    }

    /**
     * @description Load partner pricing models for given Account IDs
     * @param accountIds Set of partner Account IDs
     * @param modelType The model type to load ("Guaranteed Margin" or "Discount")
     * @return Map of Account ID to pricing model record
     */
    @TestVisible
    private Map<Id, Partner_Pricing_Model__c> loadPartnerPricingModels(Set<Id> accountIds, String modelType) {
        return PartnerPricingService.getPricingModels(accountIds, modelType);
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
     * @param partnerModels Map of partner pricing models
     * @param partnerNames Map of partner names for audit
     * @param partnerWarning Warning message if partners are missing pricing models
     * @return Number of lines processed
     */
    @TestVisible
    private Integer processLineItems(
        String ctxInstanceId,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> partnerNames,
        String partnerWarning
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

            List<Map<String, Object>> lineItems = parseLineItemApiResponse(apiResponse);
            if (lineItems.isEmpty()) {
                return 0;
            }

            System.debug(LoggingLevel.INFO, 'Found ' + lineItems.size() + ' line items to process');

            Set<Id> lineItemIds = new Set<Id>();
            for (Map<String, Object> lineItem : lineItems) {
                Id recordId = getLineItemRecordId(lineItem);
                if (recordId != null) {
                    lineItemIds.add(recordId);
                }
            }
            Map<Id, String> productTypeByLineId = PartnerPricingService.ensureProductTypesLoaded(
                lineItemIds,
                PartnerPricingService.loadProductTypesForTransactionLines(lineItemIds)
            );
            Map<Id, ContributorCarryForward> contributorCarryForwardByMaintLineId = loadContributorCarryForwardForMaintenanceLines(
                lineItemIds,
                quoteData.quoteId,
                productTypeByLineId
            );

            // Build updates for all line items
            List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();

            for (Map<String, Object> lineItem : lineItems) {

                Map<String, Object> itemUpdate = processLineItem(
                    lineItem,
                    quoteData,
                    partnerModels,
                    partnerNames,
                    partnerWarning,
                    productTypeByLineId,
                    contributorCarryForwardByMaintLineId
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

    @TestVisible
    private List<Map<String, Object>> parseLineItemApiResponse(Map<String, Object> apiResponse) {
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();

        if (apiResponse == null) {
            System.debug(LoggingLevel.WARN, 'queryTags for SalesTransactionItem returned null');
            return lineItems;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            if (qrObj instanceof Map<String, Object>) {
                queryResult = (Map<String, Object>) qrObj;
            } else {
                System.debug(LoggingLevel.WARN, 'queryResult is not a Map for line items');
                return lineItems;
            }
        } else if (apiResponse.containsKey('SalesTransactionItem')) {
            queryResult = apiResponse;
        } else {
            System.debug(LoggingLevel.WARN, 'No SalesTransactionItem tag in context');
            return lineItems;
        }

        if (!queryResult.containsKey('SalesTransactionItem')) {
            System.debug(LoggingLevel.WARN, 'SalesTransactionItem not found in queryResult');
            return lineItems;
        }

        Object itemsObj = queryResult.get('SalesTransactionItem');
        List<Object> rawLineItems = itemsObj instanceof List<Object>
            ? (List<Object>) itemsObj
            : new List<Object>{ itemsObj };

        for (Object rawItem : rawLineItems) {
            if (rawItem instanceof Map<String, Object>) {
                Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;
                if (itemWrapper.containsKey('tagValue')) {
                    Object tagValue = itemWrapper.get('tagValue');
                    if (tagValue instanceof Map<String, Object>) {
                        Map<String, Object> lineItemData = new Map<String, Object>();
                        lineItemData.putAll((Map<String, Object>) tagValue);

                        if (itemWrapper.containsKey('dataPath')) {
                            Object dataPath = itemWrapper.get('dataPath');
                            if (dataPath instanceof List<Object>) {
                                List<Object> pathParts = (List<Object>) dataPath;
                                if (!pathParts.isEmpty()) {
                                    lineItemData.put('_recordId', String.valueOf(pathParts[pathParts.size() - 1]));

                                    List<Object> updatePath = pathParts.clone();
                                    if (!updatePath.isEmpty()) {
                                        updatePath.remove(0);
                                    }
                                    lineItemData.put('_updatePath', updatePath);
                                }
                            }
                        }
                        lineItems.add(lineItemData);
                    }
                } else {
                    Map<String, Object> mutableItem = new Map<String, Object>();
                    mutableItem.putAll(itemWrapper);
                    lineItems.add(mutableItem);
                }
            }
        }

        return lineItems;
    }

    /**
     * @description Process a single line item and calculate partner pricing
     * @param lineItem The line item data from context
     * @param quoteData Quote header data
     * @param partnerModels Map of partner pricing models
     * @param partnerNames Map of partner names for audit
     * @param partnerWarning Warning message if partners are missing pricing models
     * @return Map of field updates or null if no update needed
     */
    @TestVisible
    private Map<String, Object> processLineItem(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> partnerNames,
        String partnerWarning
    ) {
        return processLineItem(lineItem, quoteData, partnerModels, partnerNames, partnerWarning, null);
    }

    @TestVisible
    private Map<String, Object> processLineItem(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> partnerNames,
        String partnerWarning,
        Map<Id, String> productTypeByLineId
    ) {
        return processLineItem(
            lineItem,
            quoteData,
            partnerModels,
            partnerNames,
            partnerWarning,
            productTypeByLineId,
            null
        );
    }

    @TestVisible
    private Map<String, Object> processLineItem(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> partnerNames,
        String partnerWarning,
        Map<Id, String> productTypeByLineId,
        Map<Id, ContributorCarryForward> contributorCarryForwardByMaintLineId
    ) {
        String lineItemId = (String) lineItem.get('_recordId');
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'SourceRecordId');
        }
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'Id');
        }
        if (String.isBlank(lineItemId)) {
            return null;
        }

        Id recordId = getLineItemRecordId(lineItem);
        String productType = PartnerPricingService.resolveProductType(
            getStringFromTag(lineItem, 'Fortra_Product_Type__c'),
            recordId,
            productTypeByLineId
        );

        return buildPartnerPercentStampUpdate(
            lineItem,
            lineItemId,
            quoteData,
            partnerModels,
            partnerNames,
            productType,
            partnerWarning,
            contributorCarryForwardByMaintLineId
        );
    }

    /**
     * @description Stamp PartnerDiscountPercent and audit fields for any product type.
     *              Derived maintenance also receives contributor pre-discount base for DPP.
     */
    @TestVisible
    private Map<String, Object> buildPartnerPercentStampUpdate(
        Map<String, Object> lineItem,
        String lineItemId,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> partnerNames,
        String productType,
        String partnerWarning
    ) {
        return buildPartnerPercentStampUpdate(
            lineItem,
            lineItemId,
            quoteData,
            partnerModels,
            partnerNames,
            productType,
            partnerWarning,
            null
        );
    }

    @TestVisible
    private Map<String, Object> buildPartnerPercentStampUpdate(
        Map<String, Object> lineItem,
        String lineItemId,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> partnerNames,
        String productType,
        String partnerWarning,
        Map<Id, ContributorCarryForward> contributorCarryForwardByMaintLineId
    ) {
        Object updatePath = lineItem.get('_updatePath');
        if (updatePath == null) {
            System.debug(LoggingLevel.WARN, 'SKIP: Line ' + lineItemId + ' has no _updatePath for percent stamp');
            return null;
        }

        Decimal totalPercent = PartnerPricingService.resolveTotalPartnerPercent(
            quoteData.partnerPricingModel,
            quoteData.billingPartnerId,
            partnerModels,
            productType
        );
        Id recordId = getLineItemRecordId(lineItem);
        ContributorCarryForward carryForward = (recordId != null && contributorCarryForwardByMaintLineId != null)
            ? contributorCarryForwardByMaintLineId.get(recordId)
            : null;
        Decimal contributorBase = carryForward != null ? carryForward.pricingBase : null;
        Boolean stampMaintContributorBase = productType == 'New Maintenance'
            && contributorBase != null
            && contributorBase > 0;

        if (productType == 'New Maintenance' && carryForward != null) {
            if (carryForward.partnerPercent != null && carryForward.partnerPercent > 0) {
                totalPercent = carryForward.partnerPercent;
            }
        }

        if ((totalPercent == null || totalPercent <= 0) && String.isBlank(partnerWarning) && !stampMaintContributorBase
            && (carryForward == null || carryForward.manualPercent == null || carryForward.manualPercent <= 0)) {
            return null;
        }

        if ((totalPercent == null || totalPercent <= 0) && String.isBlank(partnerWarning) && stampMaintContributorBase) {
            return buildMaintenanceContributorCarryForwardUpdate(lineItem, lineItemId, carryForward);
        }

        if ((totalPercent == null || totalPercent <= 0) && String.isNotBlank(partnerWarning)) {
            return buildWarningOnlyUpdate(lineItem, lineItemId, partnerWarning);
        }

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => totalPercent
            },
            new Map<String, Object>{
                'attributeName' => 'Partner_Pricing_Model_Applied__c',
                'attributeValue' => quoteData.partnerPricingModel
            },
            new Map<String, Object>{
                'attributeName' => 'Partner_Pricing_Source__c',
                'attributeValue' => PARTNER_SOURCE_PERCENT_ONLY
            }
        };

        if (stampMaintContributorBase) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Base_Price__c',
                'attributeValue' => contributorBase
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Pre_Partner_Price__c',
                'attributeValue' => contributorBase
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Source_List_Price__c',
                'attributeValue' => contributorBase
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'InputUnitPrice',
                'attributeValue' => contributorBase
            });
        }

        if (productType == 'New Maintenance' && carryForward != null
            && carryForward.manualPercent != null && carryForward.manualPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Discount',
                'attributeValue' => carryForward.manualPercent
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'ItemDiscountPercentage',
                'attributeValue' => carryForward.manualPercent
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Partner_Discount_Percent__c',
                'attributeValue' => totalPercent != null && totalPercent > 0 ? totalPercent : carryForward.partnerPercent
            });
        }

        String marginDetail = PartnerPricingService.buildPartnerMarginDetailJson(
            quoteData.partnerPricingModel,
            quoteData.billingPartnerId,
            quoteData.resellerId,
            quoteData.distributorId,
            quoteData.referralPartnerId,
            partnerModels,
            partnerNames,
            productType
        );
        if (String.isNotBlank(marginDetail)) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Partner_Margin_Detail__c',
                'attributeValue' => marginDetail
            });
        }

        if (String.isNotBlank(partnerWarning)) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Partner_Pricing_Warning__c',
                'attributeValue' => partnerWarning
            });
        }

        System.debug(LoggingLevel.INFO, 'PERCENT STAMP: Line ' + lineItemId + ' type ' + productType +
            ' -> PartnerDiscountPercent ' + totalPercent + '%');

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    @TestVisible
    private Id getLineItemRecordId(Map<String, Object> lineItem) {
        String lineItemId = (String) lineItem.get('_recordId');
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'SourceRecordId');
        }
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'Id');
        }
        if (String.isBlank(lineItemId)) {
            return null;
        }
        try {
            return Id.valueOf(lineItemId);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Derived maintenance lines have UnitPrice/ListPrice = 0 until DPP runs in-procedure.
     *              Stamp PartnerDiscountPercent so the procedure partner block can apply before software discount.
     */
    @TestVisible
    private Boolean isZeroListMaintenanceLine(
        String productType,
        Decimal regionalNetUnitPrice,
        Decimal unitPrice,
        Decimal listPrice
    ) {
        if (!isMaintenanceProductType(productType)) {
            return false;
        }

        return (regionalNetUnitPrice == null || regionalNetUnitPrice <= 0)
            && (unitPrice == null || unitPrice <= 0)
            && (listPrice == null || listPrice <= 0);
    }

    @TestVisible
    private Boolean isMaintenanceProductType(String productType) {
        return productType == 'New Maintenance' || productType == 'Renewal Maintenance';
    }

    @TestVisible
    private Map<Id, ContributorCarryForward> loadContributorCarryForwardForMaintenanceLines(
        Set<Id> lineItemIds,
        Id quoteId,
        Map<Id, String> productTypeByLineId
    ) {
        Map<Id, ContributorCarryForward> carryForwardByMaintLineId = new Map<Id, ContributorCarryForward>();
        if (lineItemIds == null || lineItemIds.isEmpty() || quoteId == null) {
            return carryForwardByMaintLineId;
        }

        Set<Id> maintLineIds = new Set<Id>();
        for (Id lineId : lineItemIds) {
            String productType = productTypeByLineId != null ? productTypeByLineId.get(lineId) : null;
            if (productType == 'New Maintenance') {
                maintLineIds.add(lineId);
            }
        }
        if (maintLineIds.isEmpty()) {
            return carryForwardByMaintLineId;
        }

        Map<Id, Id> maintProductByLineId = new Map<Id, Id>();
        for (QuoteLineItem maintLine : [
            SELECT Id, Product2Id
            FROM QuoteLineItem
            WHERE Id IN :maintLineIds
        ]) {
            maintProductByLineId.put(maintLine.Id, maintLine.Product2Id);
        }

        Set<Id> maintProductIds = new Set<Id>(maintProductByLineId.values());
        Map<Id, Id> contributorProductByMaintProduct = new Map<Id, Id>();
        for (PricebookEntryDerivedPrice derivedPrice : [
            SELECT ProductId, ContributingProductId
            FROM PricebookEntryDerivedPrice
            WHERE ProductId IN :maintProductIds
        ]) {
            contributorProductByMaintProduct.put(derivedPrice.ProductId, derivedPrice.ContributingProductId);
        }
        if (contributorProductByMaintProduct.isEmpty()) {
            return carryForwardByMaintLineId;
        }

        Map<Id, QuoteLineItem> contributorByProductId = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem contributorLine : [
            SELECT Product2Id, NetUnitPrice, Base_Price__c, Pre_Partner_Price__c, ListPrice, UnitPrice,
                   PartnerDiscountPercent, Partner_Discount_Percent__c, Discount,
                   Prior_Partner_Discount__c, Prior_Discretionary_Discount__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            AND Product2Id IN :contributorProductByMaintProduct.values()
        ]) {
            contributorByProductId.put(contributorLine.Product2Id, contributorLine);
        }

        for (Id maintLineId : maintLineIds) {
            Id maintProductId = maintProductByLineId.get(maintLineId);
            Id contributorProductId = contributorProductByMaintProduct.get(maintProductId);
            QuoteLineItem contributorLine = contributorProductId != null
                ? contributorByProductId.get(contributorProductId)
                : null;
            ContributorCarryForward carryForward = buildContributorCarryForward(contributorLine);
            if (carryForward != null) {
                carryForwardByMaintLineId.put(maintLineId, carryForward);
            }
        }

        return carryForwardByMaintLineId;
    }

    @TestVisible
    private ContributorCarryForward buildContributorCarryForward(QuoteLineItem contributorLine) {
        if (contributorLine == null) {
            return null;
        }

        Decimal pricingBase = resolveContributorPricingBase(contributorLine);
        if (pricingBase == null || pricingBase <= 0) {
            return null;
        }

        Decimal partnerPercent = resolveContributorPartnerPercent(contributorLine, pricingBase);
        Decimal manualPercent = resolveContributorManualPercent(contributorLine, pricingBase, partnerPercent);

        ContributorCarryForward carryForward = new ContributorCarryForward();
        carryForward.pricingBase = pricingBase;
        carryForward.partnerPercent = partnerPercent;
        carryForward.manualPercent = manualPercent;
        return carryForward;
    }

    @TestVisible
    private Decimal resolveContributorPartnerPercent(QuoteLineItem contributorLine, Decimal pricingBase) {
        if (contributorLine.PartnerDiscountPercent != null && contributorLine.PartnerDiscountPercent > 0) {
            return contributorLine.PartnerDiscountPercent;
        }
        if (contributorLine.Partner_Discount_Percent__c != null && contributorLine.Partner_Discount_Percent__c > 0) {
            return contributorLine.Partner_Discount_Percent__c;
        }
        if (contributorLine.Prior_Partner_Discount__c != null && contributorLine.Prior_Partner_Discount__c > 0
            && pricingBase != null && pricingBase > 0) {
            return (contributorLine.Prior_Partner_Discount__c / pricingBase * 100).setScale(2, RoundingMode.HALF_UP);
        }
        return null;
    }

    @TestVisible
    private Decimal resolveContributorManualPercent(
        QuoteLineItem contributorLine,
        Decimal pricingBase,
        Decimal partnerPercent
    ) {
        if (contributorLine.Discount != null && contributorLine.Discount > 0) {
            return contributorLine.Discount;
        }

        Decimal preManualNet = null;
        if (contributorLine.NetUnitPrice != null && contributorLine.NetUnitPrice > 0
            && contributorLine.Prior_Discretionary_Discount__c != null
            && contributorLine.Prior_Discretionary_Discount__c > 0) {
            preManualNet = contributorLine.NetUnitPrice + contributorLine.Prior_Discretionary_Discount__c;
        } else if (pricingBase != null && pricingBase > 0) {
            Decimal partnerRate = partnerPercent != null ? partnerPercent : 0;
            preManualNet = (pricingBase * (1 - (partnerRate / 100))).setScale(2, RoundingMode.HALF_UP);
        }

        if (contributorLine.Prior_Discretionary_Discount__c != null
            && contributorLine.Prior_Discretionary_Discount__c > 0
            && preManualNet != null && preManualNet > 0) {
            return (contributorLine.Prior_Discretionary_Discount__c / preManualNet * 100)
                .setScale(2, RoundingMode.HALF_UP);
        }
        return null;
    }

    @TestVisible
    private Decimal resolveContributorPricingBase(QuoteLineItem contributorLine) {
        if (contributorLine == null) {
            return null;
        }
        if (contributorLine.Pre_Partner_Price__c != null && contributorLine.Pre_Partner_Price__c > 0) {
            return contributorLine.Pre_Partner_Price__c;
        }
        if (contributorLine.Base_Price__c != null && contributorLine.Base_Price__c > 0) {
            return contributorLine.Base_Price__c;
        }
        if (contributorLine.NetUnitPrice != null && contributorLine.NetUnitPrice > 0
            && contributorLine.ListPrice != null && contributorLine.ListPrice > 0
            && contributorLine.NetUnitPrice > contributorLine.ListPrice) {
            return contributorLine.NetUnitPrice;
        }
        if (contributorLine.ListPrice != null && contributorLine.ListPrice > 0) {
            return contributorLine.ListPrice;
        }
        if (contributorLine.UnitPrice != null && contributorLine.UnitPrice > 0) {
            return contributorLine.UnitPrice;
        }
        return null;
    }

    @TestVisible
    private Map<String, Object> buildMaintenanceContributorCarryForwardUpdate(
        Map<String, Object> lineItem,
        String lineItemId,
        ContributorCarryForward carryForward
    ) {
        if (carryForward == null || carryForward.pricingBase == null || carryForward.pricingBase <= 0) {
            return null;
        }

        Object updatePath = lineItem.get('_updatePath');
        if (updatePath == null) {
            return null;
        }

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'attributeName' => 'Base_Price__c',
                'attributeValue' => carryForward.pricingBase
            },
            new Map<String, Object>{
                'attributeName' => 'Pre_Partner_Price__c',
                'attributeValue' => carryForward.pricingBase
            },
            new Map<String, Object>{
                'attributeName' => 'Source_List_Price__c',
                'attributeValue' => carryForward.pricingBase
            },
            new Map<String, Object>{
                'attributeName' => 'InputUnitPrice',
                'attributeValue' => carryForward.pricingBase
            }
        };

        if (carryForward.partnerPercent != null && carryForward.partnerPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => carryForward.partnerPercent
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Partner_Discount_Percent__c',
                'attributeValue' => carryForward.partnerPercent
            });
        }
        if (carryForward.manualPercent != null && carryForward.manualPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Discount',
                'attributeValue' => carryForward.manualPercent
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'ItemDiscountPercentage',
                'attributeValue' => carryForward.manualPercent
            });
        }

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    @TestVisible
    private Map<String, Object> buildMaintenanceContributorBaseUpdate(
        Map<String, Object> lineItem,
        String lineItemId,
        Decimal contributorBase
    ) {
        Object updatePath = lineItem.get('_updatePath');
        if (updatePath == null) {
            return null;
        }

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'attributeName' => 'Base_Price__c',
                    'attributeValue' => contributorBase
                },
                new Map<String, Object>{
                    'attributeName' => 'Pre_Partner_Price__c',
                    'attributeValue' => contributorBase
                },
                new Map<String, Object>{
                    'attributeName' => 'Source_List_Price__c',
                    'attributeValue' => contributorBase
                },
                new Map<String, Object>{
                    'attributeName' => 'InputUnitPrice',
                    'attributeValue' => contributorBase
                }
            }
        };
    }

    @TestVisible
    private Map<String, Object> buildPartnerPercentOnlyUpdate(
        Map<String, Object> lineItem,
        String lineItemId,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> partnerNames,
        String productType,
        String partnerWarning
    ) {
        return buildPartnerPercentStampUpdate(
            lineItem,
            lineItemId,
            quoteData,
            partnerModels,
            partnerNames,
            productType,
            partnerWarning
        );
    }

    @TestVisible
    private Decimal calculatePartnerPercentTotal(
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        String productType
    ) {
        if (quoteData == null || partnerModels == null || partnerModels.isEmpty()) {
            return null;
        }

        if (quoteData.partnerPricingModel == MODEL_DISCOUNT) {
            Partner_Pricing_Model__c billingModel = partnerModels.get(quoteData.billingPartnerId);
            if (billingModel == null) {
                return null;
            }
            return PartnerPricingService.getMarginForProductType(billingModel, productType);
        }

        if (quoteData.partnerPricingModel == MODEL_GUARANTEED_MARGIN) {
            Decimal totalPercent = 0;
            for (Partner_Pricing_Model__c model : partnerModels.values()) {
                Decimal margin = PartnerPricingService.getMarginForProductType(model, productType);
                if (margin != null && margin > 0) {
                    totalPercent += margin;
                }
            }
            return totalPercent > 0 ? totalPercent : null;
        }

        return null;
    }

    /**
     * @description Determine partner role for a given partner ID
     * @param partnerId The Account ID
     * @param quoteData Quote header data
     * @return Role name string
     */
    @TestVisible
    private String getPartnerRole(Id partnerId, QuoteHeaderData quoteData) {
        if (partnerId == quoteData.billingPartnerId) {
            return 'Billing Partner';
        } else if (partnerId == quoteData.resellerId) {
            return 'Reseller';
        } else if (partnerId == quoteData.distributorId) {
            return 'Distributor';
        } else if (partnerId == quoteData.referralPartnerId) {
            return 'Referral Partner';
        }
        return 'Unknown';
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
    @TestVisible
    private Object extractFieldValue(Map<String, Object> tagData, String fieldName) {
        if (tagData == null || !tagData.containsKey(fieldName)) {
            return null;
        }
        Object fieldObj = tagData.get(fieldName);
        if (fieldObj == null) {
            return null;
        }

        // Check if the field value is wrapped in the new Context API format
        // Structure: { tagValue: actualValue, dmlStatus: "...", isDirty: false, ... }
        if (fieldObj instanceof Map<String, Object>) {
            Map<String, Object> fieldWrapper = (Map<String, Object>) fieldObj;
            if (fieldWrapper.containsKey('tagValue')) {
                return fieldWrapper.get('tagValue');
            }
            // If it's a map but doesn't have tagValue, it might be the direct value (unlikely)
            // Return null to avoid treating metadata as actual value
            System.debug(LoggingLevel.FINE, 'Field ' + fieldName + ' is a Map without tagValue: ' + fieldWrapper.keySet());
            return null;
        }

        // Legacy format: direct value (not wrapped)
        return fieldObj;
    }

    /**
     * @description Resolve the base price for partner margin calculations.
     *              Regional Services Pricing writes to RegionalNetUnitPrice__c (not UnitPrice),
     *              so that field must be checked first when present.
     * @param regionalNetUnitPrice Regional-adjusted price from prior waterfall step
     * @param unitPrice Current unit price from context
     * @param listPrice List price fallback
     * @return Base price to apply partner margins against
     */
    @TestVisible
    private Decimal resolveBasePrice(Decimal regionalNetUnitPrice, Decimal unitPrice, Decimal listPrice) {
        if (regionalNetUnitPrice != null && regionalNetUnitPrice > 0) {
            return regionalNetUnitPrice;
        }
        if (unitPrice != null && unitPrice > 0) {
            return unitPrice;
        }
        return listPrice;
    }

    /**
     * @description Extract String value from tag data
     */
    @TestVisible
    private String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        return val != null ? String.valueOf(val) : null;
    }

    /**
     * @description Extract Decimal value from tag data
     */
    @TestVisible
    private Decimal getDecimalFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        if (val == null) {
            return null;
        }
        if (val instanceof Decimal) {
            return (Decimal) val;
        }
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Extract Id value from tag data
     */
    @TestVisible
    private Id getIdFromTag(Map<String, Object> tagData, String fieldName) {
        String val = getStringFromTag(tagData, fieldName);
        if (String.isBlank(val)) {
            return null;
        }
        try {
            return Id.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Check if model is within effective date range
     * @param model The Partner Pricing Model record
     * @param checkDate The date to check against
     * @return Boolean indicating if model is effective
     */
    @TestVisible
    private Boolean isModelEffective(Partner_Pricing_Model__c model, Date checkDate) {
        if (model == null) {
            return false;
        }

        if (!model.Is_Active__c) {
            return false;
        }

        if (model.Effective_Start_Date__c != null && checkDate < model.Effective_Start_Date__c) {
            return false;
        }

        if (model.Effective_End_Date__c != null && checkDate > model.Effective_End_Date__c) {
            return false;
        }

        return true;
    }

    /**
     * @description Build partner margin detail JSON for audit trail
     * @param partnerDetails List of maps containing partner ID, name, and margin
     * @return JSON string with margin breakdown
     */
    @TestVisible
    private String buildMarginDetailJson(List<Map<String, Object>> partnerDetails) {
        if (partnerDetails == null || partnerDetails.isEmpty()) {
            return null;
        }

        return JSON.serialize(partnerDetails);
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

            List<Map<String, Object>> clearAttributes = new List<Map<String, Object>>();
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
                clearAttributes.add(new Map<String, Object>{
                    'attributeName' => fieldName,
                    'attributeValue' => null
                });
            }

            List<Map<String, Object>> itemUpdates = buildDataPathUpdatesFromApiResponse(apiResponse, clearAttributes);
            clearedCount = itemUpdates.size();

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

    /**
     * @description Process line items to set warning only (when no pricing models found)
     * @param ctxInstanceId The context instance ID
     * @param partnerWarning The warning message to set
     * @return Number of lines processed
     */
    @TestVisible
    private Integer processLineItemsWithWarningOnly(
        String ctxInstanceId,
        String partnerWarning
    ) {
        Integer processedCount = 0;

        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();

            // Query line items from context - use same format as processLineItems
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            };

            Map<String, Object> apiResponse = ctx.queryTags(queryInput);

            if (apiResponse == null) {
                System.debug(LoggingLevel.WARN, 'queryTags returned null for warning update');
                return 0;
            }

            List<Map<String, Object>> warningAttributes = new List<Map<String, Object>>{
                new Map<String, Object>{
                    'attributeName' => 'Partner_Pricing_Warning__c',
                    'attributeValue' => partnerWarning
                }
            };
            List<Map<String, Object>> itemUpdates = buildDataPathUpdatesFromApiResponse(apiResponse, warningAttributes);
            processedCount = itemUpdates.size();

            // Submit updates
            if (!itemUpdates.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'Submitting ' + itemUpdates.size() + ' warning updates');
                submitContextUpdates(ctx, ctxInstanceId, itemUpdates);
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error setting warnings: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        }

        return processedCount;
    }

    /**
     * @description Build an update containing only the warning attribute (no pricing applied)
     * @param lineItem The line item data
     * @param lineItemId The line item ID for logging
     * @param partnerWarning The warning message to set
     * @return Map of field updates with just the warning attribute
     */
    @TestVisible
    private Map<String, Object> buildWarningOnlyUpdate(
        Map<String, Object> lineItem,
        String lineItemId,
        String partnerWarning
    ) {
        Map<String, Object> result = new Map<String, Object>();

        // Get the update path (dataPath minus context instance ID)
        Object updatePath = lineItem.get('_updatePath');
        if (updatePath == null) {
            System.debug(LoggingLevel.WARN, 'SKIP: Line ' + lineItemId + ' has no _updatePath for warning update');
            return null;
        }
        result.put('nodePath', new Map<String, Object>{ 'dataPath' => updatePath });

        List<Map<String, Object>> attributes = new List<Map<String, Object>>();

        // Only set the warning attribute
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Partner_Pricing_Warning__c',
            'attributeValue' => partnerWarning
        });

        result.put('attributes', attributes);

        System.debug(LoggingLevel.INFO, 'WARNING ONLY: Line ' + lineItemId + ' - ' + partnerWarning);

        return result;
    }

    /**
     * @description Build warning message for partners missing the required pricing model
     * @param partnerIds All partner IDs that should participate in pricing
     * @param partnerModels Map of partners that have the required pricing model
     * @param partnerNames Map of partner Account IDs to Names
     * @param quoteData Quote header data with pricing model selection
     * @return Warning message string, or null if all partners have the required model
     */
    @TestVisible
    private String buildMissingModelWarning(
        Set<Id> partnerIds,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> partnerNames,
        QuoteHeaderData quoteData
    ) {
        // Find partners that don't have the required model
        List<String> missingPartners = new List<String>();

        if (quoteData.partnerPricingModel == MODEL_DISCOUNT) {
            // For Discount model, only billing partner is relevant
            if (quoteData.billingPartnerId != null && !partnerModels.containsKey(quoteData.billingPartnerId)) {
                String partnerName = partnerNames.get(quoteData.billingPartnerId);
                if (String.isNotBlank(partnerName)) {
                    missingPartners.add(partnerName + ' (Billing Partner)');
                } else {
                    missingPartners.add('Billing Partner [ID: ' + quoteData.billingPartnerId + ']');
                }
            }
        } else if (quoteData.partnerPricingModel == MODEL_GUARANTEED_MARGIN) {
            // For Guaranteed Margin, check all partners
            for (Id partnerId : partnerIds) {
                if (!partnerModels.containsKey(partnerId)) {
                    String partnerName = partnerNames.get(partnerId);
                    String role = getPartnerRole(partnerId, quoteData);

                    if (String.isNotBlank(partnerName)) {
                        missingPartners.add(partnerName + ' (' + role + ')');
                    } else {
                        missingPartners.add(role + ' [ID: ' + partnerId + ']');
                    }
                }
            }
        }

        if (missingPartners.isEmpty()) {
            return null;
        }

        // Build warning message
        String warning = 'WARNING: The following partner(s) do not have a "' + quoteData.partnerPricingModel +
                        '" pricing model configured: ' + String.join(missingPartners, ', ') + '.';

        System.debug(LoggingLevel.WARN, warning);
        return warning;
    }

    @TestVisible
    private List<Map<String, Object>> buildDataPathUpdatesFromApiResponse(
        Map<String, Object> apiResponse,
        List<Map<String, Object>> attributes
    ) {
        List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();

        if (apiResponse == null || attributes == null || attributes.isEmpty()) {
            return itemUpdates;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            if (!(qrObj instanceof Map<String, Object>)) {
                return itemUpdates;
            }
            queryResult = (Map<String, Object>) qrObj;
        } else if (apiResponse.containsKey('SalesTransactionItem')) {
            queryResult = apiResponse;
        } else {
            return itemUpdates;
        }

        if (!queryResult.containsKey('SalesTransactionItem')) {
            return itemUpdates;
        }

        Object itemsObj = queryResult.get('SalesTransactionItem');
        List<Object> rawLineItems = itemsObj instanceof List<Object>
            ? (List<Object>) itemsObj
            : new List<Object>{ itemsObj };

        for (Object rawItem : rawLineItems) {
            if (!(rawItem instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;
            if (!itemWrapper.containsKey('dataPath')) {
                continue;
            }

            Object dataPath = itemWrapper.get('dataPath');
            if (!(dataPath instanceof List<Object>)) {
                continue;
            }

            List<Object> pathParts = (List<Object>) dataPath;
            if (pathParts.isEmpty()) {
                continue;
            }

            List<Object> updatePath = pathParts.clone();
            updatePath.remove(0);

            itemUpdates.add(new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
                'attributes' => attributes
            });
        }

        return itemUpdates;
    }

    @TestVisible
    private class ContributorCarryForward {
        public Decimal pricingBase;
        public Decimal partnerPercent;
        public Decimal manualPercent;
    }
}