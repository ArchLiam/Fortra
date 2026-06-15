/**
 * @description Post-pricing-procedure hook for partner net on quote/order lines.
 *
 *              Why this exists: PartnerPricingPrehook runs before the pricing procedure,
 *              but Rev Mgmt Default Pricing recalculates NetUnitPrice from ListPrice and
 *              wipes pre-hook partner writes. Derived maintenance lines also have
 *              UnitPrice/ListPrice = 0 until DPP formulas run in-procedure.
 *
 *              This hook runs AFTER the procedure to:
 *              1. Stamp PartnerUnitPrice (partner-tier net from Partner_Pricing_Model__c)
 *              2. Apply deferred partner pricing on derived maintenance when needed
 *              3. Preserve procedure NetUnitPrice when it is LOWER than partner net
 *                 (ManualDiscount / ItemDiscountPercentage — discretionary discount)
 *
 *              Commercial net (NetUnitPrice / TotalPrice) = lower of procedure net vs partner net.
 *              Partner net is always stored on PartnerUnitPrice for decomposition / COLA.
 *
 * @author Coastal Cloud
 * @date June 2026
 * @version 1.4 - Apply COLA net + carry forward partner/software discount % on renewal maintenance when procedure leaves NetUnitPrice at zero
 * @version 1.5 - SC-3346 RN-COLA-COMMIT: a renewal-maintenance line is owned entirely by the COLA path.
 *                When the procedure already committed the correct COLA net, buildRenewalMaintenanceColaUpdate
 *                returns null; previously the line then fell through to deferred partner pricing and was
 *                re-discounted (67.38 -> 60.64). Skip deferred partner pricing for any renewal-maintenance line.
 */
global class PartnerNetPricePosthook implements RevSignaling.SignalingApexProcessor {

    private static final String PARTNER_SOURCE_PROCEDURE = 'System Calculated (Procedure)';

    private static final String MODEL_GUARANTEED_MARGIN = 'Guaranteed Margin';
    private static final String MODEL_DISCOUNT = 'Discount';
    private static final String CONTEXT_DEFINITION_NAME = 'SalesTransactionContextExt_v2';

    private static Boolean isProcessing = false;

    @TestVisible
    private class QuoteHeaderData {
        public Id billingPartnerId;
        public String partnerPricingModel;
        public Id resellerId;
        public Id distributorId;
        public Id referralPartnerId;

        public Boolean hasPartnerPricing() {
            return billingPartnerId != null && String.isNotBlank(partnerPricingModel);
        }
    }

    @TestVisible
    private class PartnerPriceResult {
        public Decimal currentPrice;
        public Decimal adjustedPrice;
        public Decimal totalPercent;
        public String pricingModel;
    }

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        if (isProcessing) {
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Partner net price posthook skipped - already processing';
            return response;
        }

        try {
            isProcessing = true;

            String ctxInstanceId = request.ctxInstanceId;
            if (String.isBlank(ctxInstanceId)) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'Partner net price posthook skipped - no context id';
                return response;
            }

            Integer linesUpdated = applyPartnerNetPrices(ctxInstanceId);
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Partner net price applied to ' + linesUpdated + ' line(s)';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PartnerNetPricePosthook error: ' + e.getMessage());
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Partner net price posthook completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    /**
     * @description After PlaceOrderExecutor, RCA context is no longer updatable in-procedure.
     *              Rebuild context from the Order, apply partner net / TotalPrice, and persist.
     */
    public static Integer applyNetPricesToOrder(Id orderId) {
        if (orderId == null) {
            return 0;
        }

        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();
            Map<String, Object> buildResult = ctx.buildContext(new Map<String, Object>{
                'contextDefinitionName' => CONTEXT_DEFINITION_NAME,
                'sourceRecordId' => orderId
            });

            String contextId = resolveContextId(buildResult);
            if (String.isBlank(contextId)) {
                return 0;
            }

            PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
            Integer updated = posthook.applyPartnerNetPrices(contextId);
            ctx.persistContext(new Map<String, Object>{ 'contextId' => contextId });
            return updated;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'applyNetPricesToOrder failed: ' + e.getMessage());
            return 0;
        }
    }

    @TestVisible
    private static String resolveContextId(Map<String, Object> buildResult) {
        if (buildResult == null) {
            return null;
        }
        Object contextId = buildResult.get('contextId');
        if (contextId == null) {
            contextId = buildResult.get('contextInstanceId');
        }
        return contextId != null ? String.valueOf(contextId) : null;
    }

    @TestVisible
    private Integer applyPartnerNetPrices(String ctxInstanceId) {
        Context.IndustriesContext ctx = new Context.IndustriesContext();
        List<Map<String, Object>> lineItems = queryLineItems(ctx, ctxInstanceId);
        if (lineItems.isEmpty()) {
            return 0;
        }

        QuoteHeaderData quoteData = queryQuoteHeaderFromContext(ctx, ctxInstanceId);
        Map<Id, Partner_Pricing_Model__c> partnerModels = new Map<Id, Partner_Pricing_Model__c>();
        if (quoteData != null && quoteData.hasPartnerPricing()) {
            partnerModels = PartnerPricingService.getPricingModels(
                collectPartnerIds(quoteData),
                quoteData.partnerPricingModel
            );
        }

        Set<Id> lineItemIds = new Set<Id>();
        for (Map<String, Object> lineItem : lineItems) {
            Id lineItemId = getLineItemRecordId(lineItem);
            if (lineItemId != null) {
                lineItemIds.add(lineItemId);
            }
        }
        Map<Id, String> productTypeByLineId = PartnerPricingService.ensureProductTypesLoaded(
            lineItemIds,
            PartnerPricingService.loadProductTypesForTransactionLines(lineItemIds)
        );
        Map<Id, QuoteLineItem> renewalMaintenanceByLineId = loadRenewalMaintenanceLines(lineItemIds);

        List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();

        for (Map<String, Object> lineItem : lineItems) {
            Map<String, Object> itemUpdate = buildNetPriceUpdate(
                lineItem,
                quoteData,
                partnerModels,
                productTypeByLineId,
                renewalMaintenanceByLineId
            );
            if (itemUpdate != null) {
                itemUpdates.add(itemUpdate);
            }
        }

        if (!itemUpdates.isEmpty()) {
            submitContextUpdates(ctx, ctxInstanceId, itemUpdates);
        }

        return itemUpdates.size();
    }

    @TestVisible
    private Map<String, Object> buildNetPriceUpdate(Map<String, Object> lineItem) {
        return buildNetPriceUpdate(lineItem, null, null, null);
    }

    @TestVisible
    private Map<String, Object> buildNetPriceUpdate(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels
    ) {
        return buildNetPriceUpdate(lineItem, quoteData, partnerModels, null);
    }

    @TestVisible
    private Map<String, Object> buildNetPriceUpdate(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> productTypeByLineId
    ) {
        return buildNetPriceUpdate(lineItem, quoteData, partnerModels, productTypeByLineId, null);
    }

    @TestVisible
    private Map<String, Object> buildNetPriceUpdate(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> productTypeByLineId,
        Map<Id, QuoteLineItem> renewalMaintenanceByLineId
    ) {
        Map<String, Object> renewalMaintUpdate = buildRenewalMaintenanceColaUpdate(
            lineItem,
            productTypeByLineId,
            renewalMaintenanceByLineId
        );
        if (renewalMaintUpdate != null) {
            return renewalMaintUpdate;
        }

        // SC-3346 RN-COLA-COMMIT: a renewal-maintenance line is priced entirely by the COLA path.
        // buildRenewalMaintenanceColaUpdate returns null both when the line is NOT a renewal-maintenance
        // line AND when the procedure already committed the correct COLA net (procedureNet == colaNet).
        // In the latter case the line must NOT fall through to deferred partner pricing, which would
        // re-discount the already-net COLA price (e.g. 67.38 -> 60.64). The COLA net already nets out the
        // prior partner discount, so partner pricing must never run a second time for these lines.
        Id renewalMaintLineId = getLineItemRecordId(lineItem);
        if (renewalMaintLineId != null
            && renewalMaintenanceByLineId != null
            && renewalMaintenanceByLineId.containsKey(renewalMaintLineId)) {
            return null;
        }

        Object updatePath = lineItem.get('_updatePath');
        if (updatePath == null) {
            return null;
        }

        Decimal partnerUnitPrice = getDecimalFromTag(lineItem, 'PartnerUnitPrice');
        Decimal existingPartnerPercent = getDecimalFromTag(lineItem, 'PartnerDiscountPercent');
        Decimal procedureNet = getDecimalFromTag(lineItem, 'NetUnitPrice');
        PartnerPriceResult deferredResult = null;

        if (shouldSkipProcedureOwnedPartner(lineItem, partnerUnitPrice, existingPartnerPercent, procedureNet)) {
            return null;
        }

        if (partnerUnitPrice == null || partnerUnitPrice <= 0) {
            deferredResult = calculateDeferredPartnerPrice(
                lineItem,
                quoteData,
                partnerModels,
                productTypeByLineId
            );
            if (deferredResult != null) {
                partnerUnitPrice = deferredResult.adjustedPrice;
            }
        }

        if (partnerUnitPrice == null || partnerUnitPrice <= 0) {
            return null;
        }

        Decimal existingPartnerUnit = getDecimalFromTag(lineItem, 'PartnerUnitPrice');
        Decimal commercialUnitPrice = resolveCommercialUnitPrice(procedureNet, partnerUnitPrice);

        if (deferredResult == null && procedureNet != null && procedureNet == commercialUnitPrice) {
            if (commercialUnitPrice == partnerUnitPrice) {
                return null;
            }
            if (existingPartnerUnit != null && existingPartnerUnit == partnerUnitPrice) {
                return null;
            }
        }

        Decimal quantity = getDecimalFromTag(lineItem, 'Quantity');
        Decimal lineTotal = resolveLineTotalFromQuantity(quantity, commercialUnitPrice);

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => commercialUnitPrice },
            new Map<String, Object>{ 'attributeName' => 'NetTotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'Subtotal', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalLineAmount', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'PartnerUnitPrice', 'attributeValue' => partnerUnitPrice }
        };

        if (deferredResult != null) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Pre_Partner_Price__c',
                'attributeValue' => deferredResult.currentPrice
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Partner_Adjusted_Price__c',
                'attributeValue' => deferredResult.adjustedPrice
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Partner_Pricing_Model_Applied__c',
                'attributeValue' => deferredResult.pricingModel
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Partner_Pricing_Source__c',
                'attributeValue' => 'System Calculated (Post-Procedure)'
            });
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => deferredResult.totalPercent
            });
        }

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    /**
     * @description When the pricing procedure already stamped partner tier (V11+ derived maint
     *              container), do not re-run deferred partner math in the posthook.
     */
    @TestVisible
    private Boolean shouldSkipProcedureOwnedPartner(
        Map<String, Object> lineItem,
        Decimal partnerUnitPrice,
        Decimal partnerDiscountPercent,
        Decimal procedureNet
    ) {
        if (partnerUnitPrice == null || partnerUnitPrice <= 0) {
            return false;
        }

        Decimal commercialUnitPrice = resolveCommercialUnitPrice(procedureNet, partnerUnitPrice);
        Decimal existingPartnerUnit = getDecimalFromTag(lineItem, 'PartnerUnitPrice');

        if (procedureNet != null && procedureNet > 0 && procedureNet == commercialUnitPrice) {
            if (commercialUnitPrice == partnerUnitPrice) {
                return true;
            }
            if (existingPartnerUnit != null && existingPartnerUnit == partnerUnitPrice) {
                return true;
            }
        }

        String pricingSource = getStringFromTag(lineItem, 'Partner_Pricing_Source__c');
        return String.isNotBlank(pricingSource)
            && pricingSource.contains('Procedure')
            && partnerDiscountPercent != null
            && partnerDiscountPercent > 0
            && procedureNet != null
            && procedureNet == commercialUnitPrice;
    }

    @TestVisible
    private Decimal resolveLineTotalFromQuantity(Decimal quantity, Decimal unitPrice) {
        if (unitPrice == null) {
            return null;
        }
        QuoteLineItem stub = new QuoteLineItem(Quantity = quantity);
        return RenewalMaintenancePricingService.resolveColaLineTotal(stub, unitPrice);
    }

    @TestVisible
    private Decimal resolveCommercialUnitPrice(Decimal procedureNet, Decimal partnerUnitPrice) {
        if (procedureNet != null && procedureNet > 0 && procedureNet < partnerUnitPrice) {
            return procedureNet.setScale(2, RoundingMode.HALF_UP);
        }
        return partnerUnitPrice;
    }

    /**
     * @description Partner pricing for lines the pre-hook skipped because UnitPrice/ListPrice
     *              were zero when it ran (derived maintenance after procedure sets NetUnitPrice).
     */
    @TestVisible
    private PartnerPriceResult calculateDeferredPartnerPrice(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> productTypeByLineId
    ) {
        if (quoteData == null || !quoteData.hasPartnerPricing() || partnerModels == null || partnerModels.isEmpty()) {
            return null;
        }

        if (!needsDeferredPartnerPricing(lineItem)) {
            return null;
        }

        Decimal currentPrice = getDecimalFromTag(lineItem, 'NetUnitPrice');
        if (currentPrice == null || currentPrice <= 0) {
            return null;
        }

        String productType = PartnerPricingService.resolveProductType(
            getStringFromTag(lineItem, 'Fortra_Product_Type__c'),
            getLineItemRecordId(lineItem),
            productTypeByLineId
        );

        PartnerPriceResult result = new PartnerPriceResult();
        result.currentPrice = currentPrice;
        result.pricingModel = quoteData.partnerPricingModel;

        if (quoteData.partnerPricingModel == MODEL_DISCOUNT) {
            Partner_Pricing_Model__c billingModel = partnerModels.get(quoteData.billingPartnerId);
            if (billingModel == null) {
                return null;
            }

            Decimal discountPercent = PartnerPricingService.getMarginForProductType(billingModel, productType);
            if (discountPercent == null || discountPercent <= 0) {
                return null;
            }

            result.adjustedPrice = PartnerPricingService.calculateDiscountPrice(currentPrice, discountPercent);
            result.totalPercent = discountPercent;
        } else if (quoteData.partnerPricingModel == MODEL_GUARANTEED_MARGIN) {
            List<Decimal> allMargins = new List<Decimal>();

            for (Id partnerId : partnerModels.keySet()) {
                Partner_Pricing_Model__c model = partnerModels.get(partnerId);
                Decimal margin = PartnerPricingService.getMarginForProductType(model, productType);
                if (margin != null && margin > 0) {
                    allMargins.add(margin);
                }
            }

            if (allMargins.isEmpty()) {
                return null;
            }

            result.adjustedPrice = PartnerPricingService.calculateGuaranteedMarginPrice(currentPrice, allMargins);
            result.totalPercent = 0;
            for (Decimal margin : allMargins) {
                result.totalPercent += margin;
            }
        } else {
            return null;
        }

        if (result.adjustedPrice == null || result.adjustedPrice == currentPrice) {
            return null;
        }

        return result;
    }

    @TestVisible
    private Boolean needsDeferredPartnerPricing(Map<String, Object> lineItem) {
        Decimal partnerUnitPrice = getDecimalFromTag(lineItem, 'PartnerUnitPrice');
        if (partnerUnitPrice != null && partnerUnitPrice > 0) {
            return false;
        }

        Decimal netUnitPrice = getDecimalFromTag(lineItem, 'NetUnitPrice');
        if (netUnitPrice == null || netUnitPrice <= 0) {
            return false;
        }

        Decimal preProcedurePrice = resolvePreProcedurePrice(
            getDecimalFromTag(lineItem, 'RegionalNetUnitPrice__c'),
            getDecimalFromTag(lineItem, 'UnitPrice'),
            getDecimalFromTag(lineItem, 'ListPrice')
        );
        return preProcedurePrice == null || preProcedurePrice <= 0;
    }

    @TestVisible
    private Decimal resolvePreProcedurePrice(Decimal regionalNetUnitPrice, Decimal unitPrice, Decimal listPrice) {
        if (regionalNetUnitPrice != null && regionalNetUnitPrice > 0) {
            return regionalNetUnitPrice;
        }
        if (unitPrice != null && unitPrice > 0) {
            return unitPrice;
        }
        return listPrice;
    }

    @TestVisible
    private Set<Id> collectPartnerIds(QuoteHeaderData quoteData) {
        Set<Id> partnerIds = new Set<Id>();

        if (quoteData == null || quoteData.billingPartnerId == null) {
            return partnerIds;
        }

        partnerIds.add(quoteData.billingPartnerId);

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

        return partnerIds;
    }

    @TestVisible
    private QuoteHeaderData queryQuoteHeaderFromContext(Context.IndustriesContext ctx, String ctxInstanceId) {
        try {
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransaction' }
            };

            Map<String, Object> apiResponse = ctx.queryTags(queryInput);
            return parseQuoteHeaderApiResponse(apiResponse);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error querying Quote header in posthook: ' + e.getMessage());
            return null;
        }
    }

    @TestVisible
    private QuoteHeaderData parseQuoteHeaderApiResponse(Map<String, Object> apiResponse) {
        if (apiResponse == null) {
            return null;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            if (!(qrObj instanceof Map<String, Object>)) {
                return null;
            }
            queryResult = (Map<String, Object>) qrObj;
        } else if (apiResponse.containsKey('SalesTransaction')) {
            queryResult = apiResponse;
        } else {
            return null;
        }

        if (!queryResult.containsKey('SalesTransaction')) {
            return null;
        }

        Object transactionObj = queryResult.get('SalesTransaction');
        if (transactionObj == null) {
            return null;
        }

        Map<String, Object> transactionData;
        if (transactionObj instanceof List<Object>) {
            List<Object> transactions = (List<Object>) transactionObj;
            if (transactions.isEmpty()) {
                return null;
            }
            Object firstTransaction = transactions[0];
            if (!(firstTransaction instanceof Map<String, Object>)) {
                return null;
            }
            Map<String, Object> txnWrapper = (Map<String, Object>) firstTransaction;
            if (txnWrapper.containsKey('tagValue')) {
                Object tagValue = txnWrapper.get('tagValue');
                if (!(tagValue instanceof Map<String, Object>)) {
                    return null;
                }
                transactionData = (Map<String, Object>) tagValue;
            } else {
                transactionData = txnWrapper;
            }
        } else if (transactionObj instanceof Map<String, Object>) {
            transactionData = (Map<String, Object>) transactionObj;
        } else {
            return null;
        }

        QuoteHeaderData data = new QuoteHeaderData();
        data.billingPartnerId = getIdFromTag(transactionData, 'Billing_Partner__c');
        data.partnerPricingModel = getStringFromTag(transactionData, 'Partner_Pricing_Model__c');
        data.resellerId = getIdFromTag(transactionData, 'Reseller__c');
        data.distributorId = getIdFromTag(transactionData, 'Distributor__c');
        data.referralPartnerId = getIdFromTag(transactionData, 'Referral_Partner__c');

        if (!data.hasPartnerPricing()) {
            enrichPartnerDataFromSourceQuote(transactionData, data);
        }
        return data;
    }

    /**
     * @description Order reprice hydrates SalesTransaction from Order, which lacks Billing_Partner__c.
     *              Fall back to the source Quote linked on the Order.
     */
    @TestVisible
    private void enrichPartnerDataFromSourceQuote(
        Map<String, Object> transactionData,
        QuoteHeaderData data
    ) {
        Id sourceRecordId = getIdFromTag(transactionData, 'Id');
        if (sourceRecordId == null) {
            sourceRecordId = getIdFromTag(transactionData, 'SalesTransactionSource');
        }
        if (sourceRecordId == null || sourceRecordId.getSObjectType() != Order.SObjectType) {
            return;
        }

        for (Order ord : [
            SELECT Quote.Billing_Partner__c, Quote.Partner_Pricing_Model__c,
                   Quote.Reseller__c, Quote.Distributor__c, Quote.Referral_Partner__c
            FROM Order
            WHERE Id = :sourceRecordId
            LIMIT 1
        ]) {
            if (ord.Quote == null) {
                return;
            }
            data.billingPartnerId = ord.Quote.Billing_Partner__c;
            data.partnerPricingModel = ord.Quote.Partner_Pricing_Model__c;
            data.resellerId = ord.Quote.Reseller__c;
            data.distributorId = ord.Quote.Distributor__c;
            data.referralPartnerId = ord.Quote.Referral_Partner__c;
        }
    }

    @TestVisible
    private List<Map<String, Object>> queryLineItems(Context.IndustriesContext ctx, String ctxInstanceId) {
        try {
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            };
            return parseLineItemApiResponse(ctx.queryTags(queryInput));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'queryLineItems failed: ' + e.getMessage());
            return new List<Map<String, Object>>();
        }
    }

    @TestVisible
    private List<Map<String, Object>> parseLineItemApiResponse(Map<String, Object> apiResponse) {
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();

        if (apiResponse == null) {
            return lineItems;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            if (!(qrObj instanceof Map<String, Object>)) {
                return lineItems;
            }
            queryResult = (Map<String, Object>) qrObj;
        } else if (apiResponse.containsKey('SalesTransactionItem')) {
            queryResult = apiResponse;
        } else {
            return lineItems;
        }

        if (!queryResult.containsKey('SalesTransactionItem')) {
            return lineItems;
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
            if (!itemWrapper.containsKey('tagValue')) {
                continue;
            }

            Object tagValue = itemWrapper.get('tagValue');
            if (!(tagValue instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> lineItemData = new Map<String, Object>();
            lineItemData.putAll((Map<String, Object>) tagValue);

            if (itemWrapper.containsKey('dataPath')) {
                Object dataPath = itemWrapper.get('dataPath');
                if (dataPath instanceof List<Object>) {
                    List<Object> pathParts = (List<Object>) dataPath;
                    if (!pathParts.isEmpty()) {
                        lineItemData.put('_recordId', String.valueOf(pathParts[pathParts.size() - 1]));

                        List<Object> updatePath = pathParts.clone();
                        updatePath.remove(0);
                        lineItemData.put('_updatePath', updatePath);
                    }
                }
            }

            lineItems.add(lineItemData);
        }

        return lineItems;
    }

    @TestVisible
    private void submitContextUpdates(
        Context.IndustriesContext ctx,
        String ctxInstanceId,
        List<Map<String, Object>> itemUpdates
    ) {
        Map<String, Object> updateInput = new Map<String, Object>{
            'contextId' => ctxInstanceId,
            'nodePathAndAttributes' => itemUpdates
        };

        try {
            ctx.updateContextAttributes(updateInput);
        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().containsIgnoreCase('not in updatable state')) {
                System.debug(LoggingLevel.INFO, 'Context not in updatable state - skipping partner net price updates');
                return;
            }
            System.debug(LoggingLevel.ERROR, 'Error updating partner net price context: ' + e.getMessage());
        }
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

    @TestVisible
    private Object extractFieldValue(Map<String, Object> tagData, String fieldName) {
        if (tagData == null || !tagData.containsKey(fieldName)) {
            return null;
        }

        Object fieldObj = tagData.get(fieldName);
        if (fieldObj == null) {
            return null;
        }

        if (fieldObj instanceof Map<String, Object>) {
            Map<String, Object> fieldWrapper = (Map<String, Object>) fieldObj;
            if (fieldWrapper.containsKey('tagValue')) {
                return fieldWrapper.get('tagValue');
            }
            return null;
        }

        return fieldObj;
    }

    @TestVisible
    private String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        return val != null ? String.valueOf(val) : null;
    }

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
     * @description Load stamped renewal-maintenance pricing inputs for post-procedure COLA fallback.
     */
    @TestVisible
    private Map<Id, QuoteLineItem> loadRenewalMaintenanceLines(Set<Id> lineItemIds) {
        Map<Id, QuoteLineItem> byId = new Map<Id, QuoteLineItem>();
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return byId;
        }

        for (QuoteLineItem qli : [
            SELECT Id, QuoteId, Fortra_Product_Type__c, Base_Price__c, Prior_Partner_Discount__c,
                   Prior_Discretionary_Discount__c, PartnerDiscountPercent, Discount,
                   COLA_Uplift_Percent__c, Quantity, Quote.QuoteTypeText__c
            FROM QuoteLineItem
            WHERE Id IN :lineItemIds
            AND Fortra_Product_Type__c = 'Renewal Maintenance'
            AND Quote.QuoteTypeText__c = 'Renewal'
        ]) {
            byId.put(qli.Id, qli);
        }

        return byId;
    }

    /**
     * @description Apply stamped COLA net to renewal maintenance when DPP leaves NetUnitPrice
     *              at zero or at a stale Last Transaction price that does not match COLA net.
     */
    @TestVisible
    private Map<String, Object> buildRenewalMaintenanceColaUpdate(
        Map<String, Object> lineItem,
        Map<Id, String> productTypeByLineId,
        Map<Id, QuoteLineItem> renewalMaintenanceByLineId
    ) {
        if (renewalMaintenanceByLineId == null || renewalMaintenanceByLineId.isEmpty()) {
            return null;
        }

        Id lineItemId = getLineItemRecordId(lineItem);
        if (lineItemId == null || !renewalMaintenanceByLineId.containsKey(lineItemId)) {
            return null;
        }

        QuoteLineItem qli = renewalMaintenanceByLineId.get(lineItemId);
        Decimal procedureNet = getDecimalFromTag(lineItem, 'NetUnitPrice');
        Decimal colaNet = computeRenewalMaintenanceColaNet(qli);
        if (colaNet == null || colaNet <= 0) {
            return null;
        }
        if (procedureNet != null && procedureNet > 0
            && procedureNet.setScale(2, RoundingMode.HALF_UP) == colaNet) {
            return null;
        }

        Object updatePath = resolveRenewalMaintenanceUpdatePath(lineItem, lineItemId, qli.QuoteId);
        if (updatePath == null) {
            return null;
        }

        Decimal lineTotal = RenewalMaintenancePricingService.resolveColaLineTotal(qli, colaNet);
        if (lineTotal == null) {
            return null;
        }

        Decimal partnerPercent = resolveRenewalPartnerPercent(qli);
        Decimal softwareDiscount = qli.Discount != null ? qli.Discount : 0;

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'NetTotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'InputUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'PartnerUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'COLACalculatedPrice__c', 'attributeValue' => colaNet }
        };

        if (partnerPercent != null && partnerPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => partnerPercent
            });
        }
        if (softwareDiscount > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Discount',
                'attributeValue' => softwareDiscount
            });
        }

        System.debug(LoggingLevel.INFO, 'RENEWAL MAINT COLA: Line ' + lineItemId +
            ' -> Net=' + colaNet + ' Partner%=' + partnerPercent + ' Discount%=' + softwareDiscount);

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    @TestVisible
    private Object resolveRenewalMaintenanceUpdatePath(
        Map<String, Object> lineItem,
        Id lineItemId,
        Id quoteId
    ) {
        Object updatePath = lineItem.get('_updatePath');
        if (updatePath != null) {
            return updatePath;
        }
        if (quoteId == null || lineItemId == null) {
            return null;
        }
        return new List<Object>{ String.valueOf(quoteId), String.valueOf(lineItemId) };
    }

    @TestVisible
    private Decimal computeRenewalMaintenanceColaNet(QuoteLineItem qli) {
        if (qli == null || qli.Base_Price__c == null || qli.Base_Price__c <= 0) {
            return null;
        }

        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        Decimal priorDisc = resolveRenewalDiscretionaryDollars(qli);
        Decimal colaPercent = qli.COLA_Uplift_Percent__c != null ? qli.COLA_Uplift_Percent__c : 0;

        Decimal preColaNet = qli.Base_Price__c - priorPartner - priorDisc;
        if (preColaNet <= 0) {
            return null;
        }

        return (preColaNet * (1 + (colaPercent / 100))).setScale(2, RoundingMode.HALF_UP);
    }

    @TestVisible
    private Decimal resolveRenewalDiscretionaryDollars(QuoteLineItem qli) {
        if (qli.Prior_Discretionary_Discount__c != null && qli.Prior_Discretionary_Discount__c > 0) {
            return qli.Prior_Discretionary_Discount__c;
        }
        if (qli.Discount == null || qli.Discount <= 0) {
            return 0;
        }

        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        return ((qli.Base_Price__c - priorPartner) * (qli.Discount / 100)).setScale(2, RoundingMode.HALF_UP);
    }

    @TestVisible
    private Decimal resolveRenewalPartnerPercent(QuoteLineItem qli) {
        if (qli.PartnerDiscountPercent != null && qli.PartnerDiscountPercent > 0) {
            return qli.PartnerDiscountPercent;
        }
        if (qli.Base_Price__c == null || qli.Base_Price__c <= 0) {
            return null;
        }
        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        if (priorPartner <= 0) {
            return null;
        }
        return ((priorPartner / qli.Base_Price__c) * 100).setScale(2, RoundingMode.HALF_UP);
    }

    public class PostPricingContextRequest {
        @InvocableVariable(required=true label='Context Instance Id')
        public String contextInstanceId;
    }

    @InvocableMethod(
        label='Apply Partner Net Price Post-Pricing'
        description='Runs PartnerNetPricePosthook on the pricing context after DPP and before persist'
    )
    public static List<Integer> applyPostPricingNetPrices(List<PostPricingContextRequest> requests) {
        List<Integer> results = new List<Integer>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (PostPricingContextRequest request : requests) {
            Integer linesUpdated = 0;
            if (request != null && String.isNotBlank(request.contextInstanceId)) {
                linesUpdated = new PartnerNetPricePosthook().applyPartnerNetPrices(request.contextInstanceId);
            }
            results.add(linesUpdated);
        }
        return results;
    }
}