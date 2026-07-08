/**
 * @description Post-pricing-procedure hook for partner net on quote/order lines.
 *
 *              Why this exists: PartnerPricingPrehookV2 runs before the pricing procedure,
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
 * @version 1.7 - Commit COLACalculatedPrice__c to NetUnitPrice on renewal quotes when DPP
 *                leaves net at zero or stale (subscriptions + New Maintenance on renewal).
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

        if ([SELECT COUNT() FROM OrderItem WHERE OrderId = :orderId] == 0) {
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
        Map<Id, QuoteLineItem> renewalColaByLineId = loadRenewalColaLines(lineItemIds);
        Map<Id, NewMaintInputs> newMaintenanceByLineId = loadNewMaintenanceLines(lineItemIds);
        Id quoteId = resolveQuoteIdFromContextLineItems(lineItems);
        Boolean isRenewalQuote = isRenewalQuoteId(quoteId, renewalColaByLineId);
        if (quoteId != null && !isRenewalQuote) {
            newMaintenanceByLineId.putAll(loadNewMaintenanceLinesForQuote(quoteId));
        }

        List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();
        Map<Id, Map<String, Object>> contextLineById = indexContextLinesById(lineItems);

        for (Map<String, Object> lineItem : lineItems) {
            Map<String, Object> itemUpdate = buildNetPriceUpdate(
                lineItem,
                quoteData,
                partnerModels,
                productTypeByLineId,
                renewalColaByLineId,
                newMaintenanceByLineId,
                isRenewalQuote
            );
            if (itemUpdate == null) {
                itemUpdate = buildAttributeListPriceOnlyUpdate(lineItem, productTypeByLineId);
            } else {
                mergeListPriceStampIntoUpdate(itemUpdate, lineItem, productTypeByLineId);
            }
            if (itemUpdate != null) {
                itemUpdates.add(itemUpdate);
            }
        }

        if (quoteId != null && !isRenewalQuote && !newMaintenanceByLineId.isEmpty()) {
            itemUpdates.addAll(buildSupplementalDerivedMaintenanceUpdates(
                quoteId,
                newMaintenanceByLineId,
                contextLineById,
                itemUpdates
            ));
        }

        if (!itemUpdates.isEmpty()) {
            submitContextUpdates(ctx, ctxInstanceId, itemUpdates);
        }

        Id resolvedQuoteId = quoteId != null ? quoteId : resolveQuoteIdFromContextLineItems(lineItems);
        schedulePostPersistPriceStamp(resolvedQuoteId);

        return itemUpdates.size();
    }

    /**
     * @description TLE "Reprice All" uses the signaling posthook before persist. DML stamps must run
     *              after persist commits, so enqueue a follow-up job (falls back to sync when needed).
     */
    @TestVisible
    private static void schedulePostPersistPriceStamp(Id quoteId) {
        if (quoteId == null) {
            return;
        }

        try {
            if (System.isQueueable() || System.isBatch() || System.isFuture()) {
                PartnerNetPricePosthook.stampAttributeListPricesForQuote(quoteId);
                return;
            }
            System.enqueueJob(new QuotePriceStampQueueable(quoteId));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Post-persist price stamp enqueue failed, running sync: ' + e.getMessage());
            stampAttributeListPricesForQuote(quoteId);
        }
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
        Map<Id, QuoteLineItem> renewalColaByLineId
    ) {
        return buildNetPriceUpdate(
            lineItem, quoteData, partnerModels, productTypeByLineId, renewalColaByLineId, null
        );
    }

    @TestVisible
    private Map<String, Object> buildNetPriceUpdate(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> productTypeByLineId,
        Map<Id, QuoteLineItem> renewalColaByLineId,
        Map<Id, NewMaintInputs> newMaintenanceByLineId
    ) {
        return buildNetPriceUpdate(
            lineItem, quoteData, partnerModels, productTypeByLineId,
            renewalColaByLineId, newMaintenanceByLineId, false
        );
    }

    @TestVisible
    private Map<String, Object> buildNetPriceUpdate(
        Map<String, Object> lineItem,
        QuoteHeaderData quoteData,
        Map<Id, Partner_Pricing_Model__c> partnerModels,
        Map<Id, String> productTypeByLineId,
        Map<Id, QuoteLineItem> renewalColaByLineId,
        Map<Id, NewMaintInputs> newMaintenanceByLineId,
        Boolean isRenewalQuote
    ) {
        Map<String, Object> renewalColaCommit = buildRenewalColaCommitUpdate(lineItem, renewalColaByLineId);
        if (renewalColaCommit != null) {
            return renewalColaCommit;
        }

        Map<String, Object> renewalMaintUpdate = buildRenewalMaintenanceColaUpdate(
            lineItem,
            productTypeByLineId,
            renewalColaByLineId
        );
        if (renewalMaintUpdate != null) {
            return renewalMaintUpdate;
        }

        // SC-3346 RN-COLA-COMMIT: renewal lines owned by COLA must not fall through to deferred partner.
        Id renewalLineId = getLineItemRecordId(lineItem);
        if (renewalLineId != null
            && renewalColaByLineId != null
            && renewalColaByLineId.containsKey(renewalLineId)) {
            return null;
        }

        String productType = PartnerPricingService.resolveProductType(
            getStringFromTag(lineItem, 'Fortra_Product_Type__c'),
            renewalLineId,
            productTypeByLineId
        );

        Id maintLineId = getLineItemRecordId(lineItem);
        NewMaintInputs maintInputs = (maintLineId != null && newMaintenanceByLineId != null)
            ? newMaintenanceByLineId.get(maintLineId)
            : null;

        // V16+: new-business derived maintenance only — renewal COLA lines are handled above.
        if (DerivedMaintenanceClassifier.isNewBusinessDerivedMaintenance(productType, isRenewalQuote == true, renewalLineId, renewalColaByLineId)
            || (maintInputs != null && isRenewalQuote != true)) {
            Map<String, Object> derivedLineItem = adjustNewBusinessDerivedListLineItem(lineItem, maintInputs);
            Map<String, Object> derivedDiscountUpdate = buildDerivedMaintenanceSequentialDiscountUpdate(
                derivedLineItem,
                maintInputs
            );
            if (derivedDiscountUpdate != null) {
                return derivedDiscountUpdate;
            }
            return buildNewMaintenanceUpdate(lineItem, newMaintenanceByLineId);
        }

        // Legacy $0 settled-node fallback for non-maintenance lines.
        Map<String, Object> newMaintUpdate = buildNewMaintenanceUpdate(lineItem, newMaintenanceByLineId);
        if (newMaintUpdate != null) {
            return newMaintUpdate;
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
        Decimal commercialUnitPrice = PartnerNetResolutionCalculator.resolveCommercialUnitPrice(procedureNet, partnerUnitPrice);

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
        addAttributeTierListPriceIfNeeded(attributes, lineItem);

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
        // Delegates to PartnerPricingGate (Wave-2 decomposition, increment 14).
        return PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            lineItem, partnerUnitPrice, partnerDiscountPercent, procedureNet
        );
    }

    @TestVisible
    private Decimal resolveLineTotalFromQuantity(Decimal quantity, Decimal unitPrice) {
        if (unitPrice == null) {
            return null;
        }
        QuoteLineItem stub = new QuoteLineItem(Quantity = quantity);
        return RenewalMaintenancePricingService.resolveColaLineTotal(stub, unitPrice);
    }

    // resolveCommercialUnitPrice extracted to PartnerNetResolutionCalculator (Wave-2 decomposition, increment 6).

    // isDerivedMaintenanceProductType / isNewBusinessDerivedMaintenance extracted to
    // DerivedMaintenanceClassifier (Wave-2 decomposition, increment 3).

    @TestVisible
    private Boolean isRenewalQuoteId(Id quoteId, Map<Id, QuoteLineItem> renewalColaByLineId) {
        if (quoteId == null) {
            return false;
        }
        if (renewalColaByLineId != null && !renewalColaByLineId.isEmpty()) {
            for (QuoteLineItem qli : renewalColaByLineId.values()) {
                if (qli.QuoteId == quoteId) {
                    return true;
                }
            }
        }
        for (Quote q : [SELECT QuoteTypeText__c FROM Quote WHERE Id = :quoteId LIMIT 1]) {
            return q.QuoteTypeText__c == 'Renewal';
        }
        return false;
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

        String productType = PartnerPricingService.resolveProductType(
            getStringFromTag(lineItem, 'Fortra_Product_Type__c'),
            getLineItemRecordId(lineItem),
            productTypeByLineId
        );
        if (DerivedMaintenanceClassifier.isDerivedMaintenanceProductType(productType)) {
            return null;
        }

        // DEF-1 idempotency: on a re-reprice this line's NetUnitPrice already carries the partner
        // discount stamped on the prior pass, so discounting it again compounds (x0.82 each reprice).
        // Prefer the stable pre-partner base; fall back to NetUnitPrice for the first application
        // (the pre-hook skipped this line, so NetUnitPrice is the intended base at that point).
        Decimal currentPrice = getDecimalFromTag(lineItem, 'Pre_Partner_Price__c');
        if (currentPrice == null || currentPrice <= 0) {
            currentPrice = getDecimalFromTag(lineItem, 'NetUnitPrice');
        }
        if (currentPrice == null || currentPrice <= 0) {
            return null;
        }

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
        // Delegates to PartnerPricingGate (Wave-2 decomposition, increment 14).
        return PartnerPricingGate.needsDeferredPartnerPricing(lineItem);
    }

    // resolvePreProcedurePrice extracted to PartnerNetResolutionCalculator (Wave-2 decomposition, increment 6).

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
    // Delegates to shared ContextTagReader (Wave-2 decomposition, increment 11). Kept as a thin
    // seam so the posthook's 13 call sites stay unchanged; canonical logic lives in ContextTagReader.
    private Id getLineItemRecordId(Map<String, Object> lineItem) {
        return ContextTagReader.getLineItemRecordId(lineItem);
    }

    @TestVisible
    // Tag-reading helpers delegate to the shared ContextTagReader (Wave-2 decomposition, increment 7).
    // Kept as thin @TestVisible seams so the posthook's ~47 call sites (and tests) stay unchanged;
    // the canonical parsing logic + its unit tests now live in ContextTagReader.
    private Object extractFieldValue(Map<String, Object> tagData, String fieldName) {
        return ContextTagReader.extractFieldValue(tagData, fieldName);
    }

    @TestVisible
    private String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        return ContextTagReader.getStringFromTag(tagData, fieldName);
    }

    @TestVisible
    private Id getIdFromTag(Map<String, Object> tagData, String fieldName) {
        return ContextTagReader.getIdFromTag(tagData, fieldName);
    }

    @TestVisible
    private Decimal getDecimalFromTag(Map<String, Object> tagData, String fieldName) {
        return ContextTagReader.getDecimalFromTag(tagData, fieldName);
    }

    /**
     * @description Load stamped renewal-maintenance pricing inputs for post-procedure COLA fallback.
     */
    @TestVisible
    private Map<Id, QuoteLineItem> loadRenewalColaLines(Set<Id> lineItemIds) {
        Map<Id, QuoteLineItem> byId = new Map<Id, QuoteLineItem>();
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return byId;
        }

        for (QuoteLineItem qli : [
            SELECT Id, QuoteId, Fortra_Product_Type__c, Base_Price__c, Prior_Partner_Discount__c,
                   Prior_Discretionary_Discount__c, PartnerDiscountPercent, Discount,
                   COLA_Uplift_Percent__c, COLACalculatedPrice__c, Quantity, Quote.QuoteTypeText__c
            FROM QuoteLineItem
            WHERE Id IN :lineItemIds
            AND Quote.QuoteTypeText__c = 'Renewal'
            AND (COLACalculatedPrice__c > 0
                 OR Base_Price__c > 0
                 OR Fortra_Product_Type__c IN ('Renewal Maintenance', 'New Maintenance'))
        ]) {
            byId.put(qli.Id, qli);
        }

        return byId;
    }

    /**
     * @description When COLACalculatedPrice__c is stamped but DPP left NetUnitPrice at zero or a stale
     *              value, commit the COLA net as commercial price (subscriptions and maintenance).
     */
    @TestVisible
    private Map<String, Object> buildRenewalColaCommitUpdate(
        Map<String, Object> lineItem,
        Map<Id, QuoteLineItem> renewalColaByLineId
    ) {
        if (renewalColaByLineId == null || renewalColaByLineId.isEmpty()) {
            return null;
        }

        Id lineItemId = getLineItemRecordId(lineItem);
        if (lineItemId == null || !renewalColaByLineId.containsKey(lineItemId)) {
            return null;
        }

        QuoteLineItem qli = renewalColaByLineId.get(lineItemId);
        if (qli.COLACalculatedPrice__c == null || qli.COLACalculatedPrice__c <= 0) {
            return null;
        }

        Decimal colaNet = qli.COLACalculatedPrice__c.setScale(2, RoundingMode.HALF_UP);
        Decimal procedureNet = getDecimalFromTag(lineItem, 'NetUnitPrice');
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
            new Map<String, Object>{ 'attributeName' => 'Subtotal', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalLineAmount', 'attributeValue' => lineTotal }
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

        System.debug(LoggingLevel.INFO, 'RENEWAL COLA COMMIT: Line ' + lineItemId +
            ' procedureNet=' + procedureNet + ' -> colaNet=' + colaNet);

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    @TestVisible
    private Map<Id, QuoteLineItem> loadRenewalMaintenanceLines(Set<Id> lineItemIds) {
        Map<Id, QuoteLineItem> byId = new Map<Id, QuoteLineItem>();
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return byId;
        }

        for (QuoteLineItem qli : [
            SELECT Id, QuoteId, Fortra_Product_Type__c, Base_Price__c, Prior_Partner_Discount__c,
                   Prior_Discretionary_Discount__c, PartnerDiscountPercent, Discount,
                   COLA_Uplift_Percent__c, COLACalculatedPrice__c, Quantity, Quote.QuoteTypeText__c
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
        if (qli.getPopulatedFieldsAsMap().containsKey('COLACalculatedPrice__c')
            && qli.COLACalculatedPrice__c != null
            && qli.COLACalculatedPrice__c > 0) {
            return null;
        }
        if (!DerivedMaintenanceClassifier.isDerivedMaintenanceProductType(
            PartnerPricingService.resolveProductType(
                qli.getPopulatedFieldsAsMap().containsKey('Fortra_Product_Type__c')
                    ? qli.Fortra_Product_Type__c
                    : null,
                lineItemId,
                productTypeByLineId
            )
        )) {
            return null;
        }

        Decimal procedureNet = getDecimalFromTag(lineItem, 'NetUnitPrice');
        Decimal colaNet = RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(qli);
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
        // Delegates to ContextUpdateNavigator (Wave-2 decomposition, build*Update step 2).
        return ContextUpdateNavigator.resolveRenewalMaintenanceUpdatePath(lineItem, lineItemId, quoteId);
    }

    // Renewal-maintenance COLA net math (computeRenewalMaintenanceColaNet / computeColaFromPriorNet /
    // isContributorBaseOnMaintenanceLine / resolveRenewalDiscretionaryDollars) extracted verbatim to
    // RenewalMaintenanceColaCalculator (Wave-2 decomposition; pure, unit-tested).

    @TestVisible
    private Decimal resolveRenewalPartnerPercent(QuoteLineItem qli) {
        // Delegates to RenewalMaintenanceColaCalculator (Wave-2 decomposition, increment 16).
        return RenewalMaintenanceColaCalculator.resolveRenewalPartnerPercent(qli);
    }

    /**
     * @description Contributor perpetual net (Base_Price__c) + catalog list fallback for a New-Maintenance
     *              line whose derived net the procedure failed to write (asset-copy / settled node).
     */
    @TestVisible
    private class NewMaintInputs {
        public Decimal contributorNetPrice;
        public Boolean contributorNetFromPerpetual;
        public Decimal sourceListPrice;
        public Decimal partnerPercent;
        public Decimal softwareDiscount;
        public Decimal quantity;
        public Decimal rate;
        public Id parentId;
        // J-06: true when partnerPercent is the authoritative New-Maintenance band resolved from
        // the billing partner's Discount model (not a carried license band or stamped value).
        public Boolean partnerBandResolved = false;
        public NewMaintInputs(
            Decimal contributorNetPrice,
            Boolean contributorNetFromPerpetual,
            Decimal sourceListPrice,
            Decimal partnerPercent,
            Decimal softwareDiscount,
            Decimal quantity,
            Decimal rate,
            Id parentId
        ) {
            this.contributorNetPrice = contributorNetPrice;
            this.contributorNetFromPerpetual = contributorNetFromPerpetual;
            this.sourceListPrice = sourceListPrice;
            this.partnerPercent = partnerPercent;
            this.softwareDiscount = softwareDiscount;
            this.quantity = quantity;
            this.rate = rate;
            this.parentId = parentId;
        }
    }

    @TestVisible
    private class ContributorCarryForwardSnapshot {
        public Decimal pricingBase;
        public Decimal partnerPercent;
        public Decimal softwareDiscount;
    }

    // NewBusinessMaintenanceNets promoted to a public top-level class (Wave-2 decomposition,
    // build*Update step 4) so NewMaintenanceNetCalculator can return it. The unqualified references
    // below rebind to the top-level type; the inner decl is deleted here in the SAME deploy so no
    // stale inner shadows it. Zero test/cross-class references, so the relocation is name-transparent.

    /**
     * @description Load New-Maintenance lines and maintenance rate from Maintenance_Rate__mdt.
     *              Eligible for post-procedure $0 fallback only (procedure owns priced lines).
     */
    @TestVisible
    private Map<Id, NewMaintInputs> loadNewMaintenanceLines(Set<Id> lineItemIds) {
        Map<Id, NewMaintInputs> byId = new Map<Id, NewMaintInputs>();
        if (lineItemIds == null || lineItemIds.isEmpty()) {
            return byId;
        }

        Set<Id> qliIds = new Set<Id>();
        Set<Id> orderItemIds = new Set<Id>();
        for (Id lineId : lineItemIds) {
            Schema.SObjectType sot = lineId.getSObjectType();
            if (sot == QuoteLineItem.SObjectType) {
                qliIds.add(lineId);
            } else if (sot == OrderItem.SObjectType) {
                orderItemIds.add(lineId);
            }
        }

        Map<String, Decimal> rateByType = loadMaintenanceRates();

        // Quote line items (quote reprice)
        if (!qliIds.isEmpty()) {
            Map<Id, QuoteLineItem> qlis = new Map<Id, QuoteLineItem>([
                SELECT Id, QuoteId, Product2Id, Base_Price__c, Source_List_Price__c,
                       PartnerDiscountPercent, Discount, Quantity
                FROM QuoteLineItem
                WHERE Id IN :qliIds
                AND Fortra_Product_Type__c = 'New Maintenance'
                AND (Base_Price__c > 0 OR Source_List_Price__c > 0)
            ]);
            if (!qlis.isEmpty()) {
                Map<Id, ContributorCarryForwardSnapshot> contributorByMaintLineId =
                    resolveContributorCarryForwardByMaintenanceQuoteLines(qlis);
                // J-06: derived New-Maintenance partner discount must use the billing partner's
                // New-Maintenance band, not the license contributor's carried Software band.
                Map<Id, Decimal> nmBandByQuote = resolveNewMaintenancePartnerBandByQuote(qlis.values());
                Map<Id, String> tierByLine = new Map<Id, String>();
                for (QuoteLineItemAttribute attr : [
                    SELECT QuoteLineItemId, AttributeValue
                    FROM QuoteLineItemAttribute
                    WHERE QuoteLineItemId IN :qlis.keySet()
                    AND AttributeName = 'Maintenance Type Defn'
                ]) {
                    if (String.isNotBlank(attr.AttributeValue)) {
                        tierByLine.put(attr.QuoteLineItemId, attr.AttributeValue);
                    }
                }
                for (QuoteLineItem qli : qlis.values()) {
                    Decimal rate = NewMaintenanceInputResolver.resolveTierRate(tierByLine.get(qli.Id), rateByType);
                    if (rate == null) {
                        continue;
                    }
                    ContributorCarryForwardSnapshot contributor = contributorByMaintLineId.get(qli.Id);
                    Decimal contributorBase = contributor != null ? contributor.pricingBase : null;
                    Boolean contributorNetFromPerpetual =
                        NewMaintenanceInputResolver.isContributorNetFromPerpetual(contributorBase);
                    Decimal contributorNet =
                        NewMaintenanceInputResolver.resolveContributorNet(contributorBase, qli.Base_Price__c);
                    Decimal partnerPercent = NewMaintenanceInputResolver.resolvePartnerPercent(
                        nmBandByQuote.get(qli.QuoteId),
                        contributor != null ? contributor.partnerPercent : null,
                        qli.PartnerDiscountPercent);
                    Decimal softwareDiscount = NewMaintenanceInputResolver.resolveSoftwareDiscount(
                        contributor != null ? contributor.softwareDiscount : null,
                        qli.Discount);
                    byId.put(qli.Id, new NewMaintInputs(
                        contributorNet, contributorNetFromPerpetual, qli.Source_List_Price__c,
                        partnerPercent, softwareDiscount,
                        qli.Quantity, rate, qli.QuoteId));
                    byId.get(qli.Id).partnerBandResolved = nmBandByQuote.get(qli.QuoteId) != null;
                }
            }
        }

        // Order items (activated/converted orders are priced through the engine, where raw
        // DML can't set UnitPrice; the posthook writes via the context, so the fallback applies here too).
        if (!orderItemIds.isEmpty()) {
            Map<Id, OrderItem> ois = new Map<Id, OrderItem>([
                SELECT Id, OrderId, Product2Id, Base_Price__c, Source_List_Price__c,
                       PartnerDiscountPercent, Quantity
                FROM OrderItem
                WHERE Id IN :orderItemIds
                AND Fortra_Product_Type__c = 'New Maintenance'
                AND (Base_Price__c > 0 OR Source_List_Price__c > 0)
            ]);
            if (!ois.isEmpty()) {
                Map<Id, Decimal> contributorNetByMaintLineId =
                    resolveContributorNetByMaintenanceOrderItems(ois);
                Map<Id, Decimal> nmBandByOrder = resolveNewMaintenancePartnerBandByOrder(ois.values());
                Map<Id, String> tierByLine = new Map<Id, String>();
                for (OrderItemAttribute attr : [
                    SELECT OrderItemId, AttributeValue
                    FROM OrderItemAttribute
                    WHERE OrderItemId IN :ois.keySet()
                    AND AttributeName = 'Maintenance Type Defn'
                ]) {
                    if (String.isNotBlank(attr.AttributeValue)) {
                        tierByLine.put(attr.OrderItemId, attr.AttributeValue);
                    }
                }
                for (OrderItem oi : ois.values()) {
                    Decimal rate = NewMaintenanceInputResolver.resolveTierRate(tierByLine.get(oi.Id), rateByType);
                    if (rate == null) {
                        continue;
                    }
                    Decimal contributorBase = contributorNetByMaintLineId.get(oi.Id);
                    Boolean contributorNetFromPerpetual =
                        NewMaintenanceInputResolver.isContributorNetFromPerpetual(contributorBase);
                    Decimal contributorNet =
                        NewMaintenanceInputResolver.resolveContributorNet(contributorBase, oi.Base_Price__c);
                    byId.put(oi.Id, new NewMaintInputs(
                        contributorNet, contributorNetFromPerpetual, oi.Source_List_Price__c,
                        NewMaintenanceInputResolver.resolvePartnerPercent(
                            nmBandByOrder.get(oi.OrderId), null, oi.PartnerDiscountPercent),
                        null, oi.Quantity, rate, oi.OrderId));
                    byId.get(oi.Id).partnerBandResolved = nmBandByOrder.get(oi.OrderId) != null;
                }
            }
        }

        return byId;
    }

    /**
     * @description J-06: New-Maintenance partner discount band per Quote, read directly from the
     *              billing partner's active Discount pricing model (New_Maintenance_Percent__c)
     *              rather than the license contributor's Software band. Resolved via SOQL on the
     *              Quote so it is independent of pricing-context header tags. Quotes that do not
     *              use Discount partner pricing are omitted; callers then keep existing behavior.
     */
    @TestVisible
    private Map<Id, Decimal> resolveNewMaintenancePartnerBandByQuote(List<QuoteLineItem> maintLines) {
        if (maintLines == null || maintLines.isEmpty()) {
            return new Map<Id, Decimal>();
        }
        Set<Id> quoteIds = new Set<Id>();
        for (QuoteLineItem qli : maintLines) {
            if (qli.QuoteId != null) {
                quoteIds.add(qli.QuoteId);
            }
        }
        if (quoteIds.isEmpty()) {
            return new Map<Id, Decimal>();
        }
        Map<Id, Quote> quotes = new Map<Id, Quote>([
            SELECT Id, Billing_Partner__c, Partner_Pricing_Model__c
            FROM Quote
            WHERE Id IN :quoteIds
        ]);
        Set<Id> billingPartnerIds = NewMaintenanceBandCalculator.billingPartnerIdsFromQuotes(quotes);
        if (billingPartnerIds.isEmpty()) {
            return new Map<Id, Decimal>();
        }
        Map<Id, Partner_Pricing_Model__c> models =
            PartnerPricingService.getPricingModels(billingPartnerIds, 'Discount');
        return NewMaintenanceBandCalculator.bandByQuote(quotes, models);
    }

    /**
     * @description J-06: New-Maintenance partner discount band per Order, resolved from the source
     *              Quote linked on the Order (same Discount-model logic as the Quote path).
     */
    @TestVisible
    private Map<Id, Decimal> resolveNewMaintenancePartnerBandByOrder(List<OrderItem> maintLines) {
        if (maintLines == null || maintLines.isEmpty()) {
            return new Map<Id, Decimal>();
        }
        Set<Id> orderIds = new Set<Id>();
        for (OrderItem oi : maintLines) {
            if (oi.OrderId != null) {
                orderIds.add(oi.OrderId);
            }
        }
        if (orderIds.isEmpty()) {
            return new Map<Id, Decimal>();
        }
        Map<Id, Order> orders = new Map<Id, Order>([
            SELECT Id, Quote.Billing_Partner__c, Quote.Partner_Pricing_Model__c
            FROM Order
            WHERE Id IN :orderIds
        ]);
        Set<Id> billingPartnerIds = NewMaintenanceBandCalculator.billingPartnerIdsFromOrders(orders);
        if (billingPartnerIds.isEmpty()) {
            return new Map<Id, Decimal>();
        }
        Map<Id, Partner_Pricing_Model__c> models =
            PartnerPricingService.getPricingModels(billingPartnerIds, 'Discount');
        return NewMaintenanceBandCalculator.bandByOrder(orders, models);
    }

    // newMaintenanceBand + the New-Maintenance band mapping extracted to NewMaintenanceBandCalculator
    // (Wave-2 decomposition, increment 4 — SOQL loaders stay here, pure mapping moved out).

    /**
     * @description Live contributor perpetual pricing + carried discounts for each maintenance line.
     */
    @TestVisible
    private Map<Id, ContributorCarryForwardSnapshot> resolveContributorCarryForwardByMaintenanceQuoteLines(
        Map<Id, QuoteLineItem> maintLines
    ) {
        Map<Id, ContributorCarryForwardSnapshot> carryForwardByMaintLineId =
            new Map<Id, ContributorCarryForwardSnapshot>();
        if (maintLines == null || maintLines.isEmpty()) {
            return carryForwardByMaintLineId;
        }

        Set<Id> maintProductIds = new Set<Id>();
        Id quoteId;
        for (QuoteLineItem maintLine : maintLines.values()) {
            if (maintLine.Product2Id != null) {
                maintProductIds.add(maintLine.Product2Id);
            }
            if (quoteId == null) {
                quoteId = maintLine.QuoteId;
            }
        }
        if (maintProductIds.isEmpty() || quoteId == null) {
            return carryForwardByMaintLineId;
        }

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

        for (QuoteLineItem maintLine : maintLines.values()) {
            Id contributorProductId = contributorProductByMaintProduct.get(maintLine.Product2Id);
            QuoteLineItem contributorLine = contributorProductId != null
                ? contributorByProductId.get(contributorProductId)
                : null;
            ContributorCarryForwardSnapshot carryForward = buildContributorCarryForwardSnapshot(contributorLine);
            if (carryForward != null) {
                carryForwardByMaintLineId.put(maintLine.Id, carryForward);
            }
        }

        return carryForwardByMaintLineId;
    }

    @TestVisible
    private ContributorCarryForwardSnapshot buildContributorCarryForwardSnapshot(QuoteLineItem contributorLine) {
        if (contributorLine == null) {
            return null;
        }
        Decimal pricingBase = ContributorPricingCalculator.resolveContributorPricingBase(contributorLine);
        if (pricingBase == null || pricingBase <= 0) {
            return null;
        }

        ContributorCarryForwardSnapshot carryForward = new ContributorCarryForwardSnapshot();
        carryForward.pricingBase = pricingBase;
        carryForward.partnerPercent = ContributorPricingCalculator.resolveContributorPartnerPercent(contributorLine, pricingBase);
        carryForward.softwareDiscount = ContributorPricingCalculator.resolveContributorSoftwarePercent(contributorLine, pricingBase, carryForward.partnerPercent);
        return carryForward;
    }

    // resolveContributorPartnerPercent / resolveContributorSoftwarePercent extracted to
    // ContributorPricingCalculator (Wave-2 decomposition, increment 2).

    /**
     * @description Resolves the contributing perpetual line's commercial base for each New-Maintenance
     *              quote line on the same quote.
     */
    @TestVisible
    private Map<Id, Decimal> resolveContributorNetByMaintenanceQuoteLines(Map<Id, QuoteLineItem> maintLines) {
        Map<Id, Decimal> contributorNetByMaintLineId = new Map<Id, Decimal>();
        Map<Id, ContributorCarryForwardSnapshot> carryForwardByMaintLineId =
            resolveContributorCarryForwardByMaintenanceQuoteLines(maintLines);
        for (Id maintLineId : carryForwardByMaintLineId.keySet()) {
            ContributorCarryForwardSnapshot carryForward = carryForwardByMaintLineId.get(maintLineId);
            if (carryForward != null && carryForward.pricingBase != null && carryForward.pricingBase > 0) {
                contributorNetByMaintLineId.put(maintLineId, carryForward.pricingBase);
            }
        }
        return contributorNetByMaintLineId;
    }

    /**
     * @description Resolves the contributing perpetual line's commercial net for each New-Maintenance
     *              order line on the same order.
     */
    @TestVisible
    private Map<Id, Decimal> resolveContributorNetByMaintenanceOrderItems(Map<Id, OrderItem> maintLines) {
        Map<Id, Decimal> contributorNetByMaintLineId = new Map<Id, Decimal>();
        if (maintLines == null || maintLines.isEmpty()) {
            return contributorNetByMaintLineId;
        }

        Set<Id> maintProductIds = new Set<Id>();
        Id orderId;
        for (OrderItem maintLine : maintLines.values()) {
            if (maintLine.Product2Id != null) {
                maintProductIds.add(maintLine.Product2Id);
            }
            if (orderId == null) {
                orderId = maintLine.OrderId;
            }
        }
        if (maintProductIds.isEmpty() || orderId == null) {
            return contributorNetByMaintLineId;
        }

        Map<Id, Id> contributorProductByMaintProduct = new Map<Id, Id>();
        for (PricebookEntryDerivedPrice derivedPrice : [
            SELECT ProductId, ContributingProductId
            FROM PricebookEntryDerivedPrice
            WHERE ProductId IN :maintProductIds
        ]) {
            contributorProductByMaintProduct.put(derivedPrice.ProductId, derivedPrice.ContributingProductId);
        }
        if (contributorProductByMaintProduct.isEmpty()) {
            return contributorNetByMaintLineId;
        }

        Map<Id, OrderItem> contributorByProductId = new Map<Id, OrderItem>();
        for (OrderItem contributorLine : [
            SELECT Product2Id, NetUnitPrice, Base_Price__c, ListPrice, UnitPrice
            FROM OrderItem
            WHERE OrderId = :orderId
            AND Product2Id IN :contributorProductByMaintProduct.values()
        ]) {
            contributorByProductId.put(contributorLine.Product2Id, contributorLine);
        }

        for (OrderItem maintLine : maintLines.values()) {
            Id contributorProductId = contributorProductByMaintProduct.get(maintLine.Product2Id);
            OrderItem contributorLine = contributorProductId != null
                ? contributorByProductId.get(contributorProductId)
                : null;
            Decimal contributorNet = ContributorPricingCalculator.resolveContributorPricingBase(contributorLine);
            if (contributorNet != null && contributorNet > 0) {
                contributorNetByMaintLineId.put(maintLine.Id, contributorNet);
            }
        }

        return contributorNetByMaintLineId;
    }

    // resolveContributorPricingBase (QuoteLineItem + OrderItem overloads) extracted to
    // ContributorPricingCalculator (Wave-2 decomposition, increment 2).

    @TestVisible
    private Map<Id, Map<String, Object>> indexContextLinesById(List<Map<String, Object>> lineItems) {
        // Delegates to ContextUpdateNavigator (Wave-2 decomposition, increment 13).
        return ContextUpdateNavigator.indexContextLinesById(lineItems);
    }

    /**
     * @description Second pass for derived maintenance when the context line lacked updatePath/tags
     *              but the QLI already carries partner/manual % from the contributor perpetual.
     */
    @TestVisible
    private List<Map<String, Object>> buildSupplementalDerivedMaintenanceUpdates(
        Id quoteId,
        Map<Id, NewMaintInputs> newMaintenanceByLineId,
        Map<Id, Map<String, Object>> contextLineById,
        List<Map<String, Object>> existingUpdates
    ) {
        List<Map<String, Object>> supplementalUpdates = new List<Map<String, Object>>();
        if (newMaintenanceByLineId == null || newMaintenanceByLineId.isEmpty()) {
            return supplementalUpdates;
        }

        Set<Id> maintIds = new Set<Id>(newMaintenanceByLineId.keySet());
        Map<Id, QuoteLineItem> qlisById = new Map<Id, QuoteLineItem>([
            SELECT Id, NetUnitPrice, UnitPrice, ListPrice, Quantity, PartnerDiscountPercent, Discount
            FROM QuoteLineItem
            WHERE Id IN :maintIds
        ]);

        for (Id maintId : maintIds) {
            NewMaintInputs inputs = newMaintenanceByLineId.get(maintId);
            if (inputs == null) {
                continue;
            }

            Map<String, Object> lineItem = contextLineById.get(maintId);
            if (lineItem == null) {
                QuoteLineItem qli = qlisById.get(maintId);
                lineItem = new Map<String, Object>{
                    '_recordId' => String.valueOf(maintId),
                    'Fortra_Product_Type__c' => 'New Maintenance',
                    'Quantity' => qli != null ? qli.Quantity : inputs.quantity,
                    'NetUnitPrice' => qli != null ? qli.NetUnitPrice : null,
                    'UnitPrice' => qli != null ? qli.UnitPrice : null,
                    'ListPrice' => qli != null ? qli.ListPrice : null,
                    'PartnerDiscountPercent' => qli != null ? qli.PartnerDiscountPercent : inputs.partnerPercent,
                    'Discount' => qli != null ? qli.Discount : inputs.softwareDiscount
                };
            }

            Map<String, Object> derivedUpdate = buildDerivedMaintenanceSequentialDiscountUpdate(
                adjustNewBusinessDerivedListLineItem(lineItem, inputs),
                inputs
            );
            if (derivedUpdate == null) {
                derivedUpdate = buildNewMaintenanceUpdate(
                    lineItem,
                    new Map<Id, NewMaintInputs>{ maintId => inputs }
                );
            }
            if (derivedUpdate == null) {
                derivedUpdate = buildAttributeListPriceOnlyUpdate(
                    lineItem,
                    new Map<Id, String>{ maintId => 'New Maintenance' }
                );
            }
            if (derivedUpdate != null && !containsEquivalentUpdate(existingUpdates, derivedUpdate)
                && !containsEquivalentUpdate(supplementalUpdates, derivedUpdate)) {
                supplementalUpdates.add(derivedUpdate);
            }
        }

        return supplementalUpdates;
    }

    @TestVisible
    private Boolean containsEquivalentUpdate(
        List<Map<String, Object>> updates,
        Map<String, Object> candidate
    ) {
        // Delegates to ContextUpdateNavigator (Wave-2 decomposition, increment 13).
        return ContextUpdateNavigator.containsEquivalentUpdate(updates, candidate);
    }

    @TestVisible
    private Object extractUpdatePath(Map<String, Object> updatePayload) {
        return ContextUpdateNavigator.extractUpdatePath(updatePayload);
    }

    @TestVisible
    private Id resolveQuoteIdFromContextLineItems(List<Map<String, Object>> lineItems) {
        if (lineItems == null) {
            return null;
        }
        for (Map<String, Object> lineItem : lineItems) {
            Id quoteId = resolveQuoteIdFromLineItem(lineItem);
            if (quoteId != null) {
                return quoteId;
            }
        }
        return null;
    }

    @TestVisible
    private Id resolveQuoteIdFromLineItem(Map<String, Object> lineItem) {
        if (lineItem == null) {
            return null;
        }

        Object updatePath = lineItem.get('_updatePath');
        if (updatePath instanceof List<Object>) {
            List<Object> pathParts = (List<Object>) updatePath;
            if (pathParts.size() >= 2) {
                try {
                    return Id.valueOf(String.valueOf(pathParts[0]));
                } catch (Exception e) {
                    // continue
                }
            }
        }

        Id lineItemId = getLineItemRecordId(lineItem);
        if (lineItemId != null && lineItemId.getSObjectType() == QuoteLineItem.SObjectType) {
            for (QuoteLineItem qli : [SELECT QuoteId FROM QuoteLineItem WHERE Id = :lineItemId LIMIT 1]) {
                return qli.QuoteId;
            }
        }
        return null;
    }

    @TestVisible
    private Map<Id, NewMaintInputs> loadNewMaintenanceLinesForQuote(Id quoteId) {
        if (quoteId == null) {
            return new Map<Id, NewMaintInputs>();
        }
        return loadNewMaintenanceLines(new Map<Id, QuoteLineItem>([
            SELECT Id
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            AND Fortra_Product_Type__c = 'New Maintenance'
        ]).keySet());
    }

    // resolveTierRate + the New-Maintenance per-line input resolution (contributor net / partner% /
    // software discount) extracted to NewMaintenanceInputResolver (Wave-2 decomposition, increment 5).

    @TestVisible
    private Map<String, Decimal> loadMaintenanceRates() {
        Map<String, Decimal> rateByType = new Map<String, Decimal>();
        for (Maintenance_Rate__mdt rateRecord : [
            SELECT MaintenanceType__c, Rate__c FROM Maintenance_Rate__mdt
        ]) {
            if (String.isNotBlank(rateRecord.MaintenanceType__c) && rateRecord.Rate__c != null) {
                rateByType.put(rateRecord.MaintenanceType__c, rateRecord.Rate__c);
            }
        }
        return rateByType;
    }

    /**
     * @description Computes expected derived list and commercial nets from the live contributor perpetual.
     */
    @TestVisible
    private NewBusinessMaintenanceNets computeNewBusinessMaintenanceNets(
        Map<String, Object> lineItem,
        NewMaintInputs maintInputs
    ) {
        // Guard 1 stays in the shell — the calculator receives primitives and cannot null-check
        // maintInputs (moving this into the calculator would NPE on a reachable null-inputs line).
        if (maintInputs == null) {
            return new NewBusinessMaintenanceNets();
        }

        // Guard 2 also in the shell, so the stamped-percent tag reads below keep their original
        // post-guard timing (they were never reached when expectedListNet was null).
        Decimal expectedListNet = NewMaintenanceNetCalculator.expectedListNet(
            maintInputs.contributorNetPrice, maintInputs.rate
        );
        if (expectedListNet == null) {
            return new NewBusinessMaintenanceNets();
        }

        // Stamped-percent reads stay here (pure ListPriceStampCalculator map gets); the J-06 partner%
        // precedence + software fallback + commercial-net compute delegate to the pure calculator
        // (Wave-2 decomposition, build*Update step 5).
        return NewMaintenanceNetCalculator.computeNewBusinessNets(
            expectedListNet,
            maintInputs.partnerBandResolved,
            maintInputs.partnerPercent,
            maintInputs.softwareDiscount,
            resolveStampedPartnerPercent(lineItem),
            resolveStampedManualPercent(lineItem)
        );
    }

    /**
     * @description Re-seeds derived maintenance list net from the live contributor perpetual on each reprice.
     *              Handles both stale-low ($60) and stale-high ($4,000 when perpetual decreased) procedure nets.
     */
    @TestVisible
    private Map<String, Object> adjustNewBusinessDerivedListLineItem(
        Map<String, Object> lineItem,
        NewMaintInputs maintInputs
    ) {
        if (lineItem == null || maintInputs == null) {
            return lineItem;
        }

        NewBusinessMaintenanceNets nets = computeNewBusinessMaintenanceNets(lineItem, maintInputs);
        if (nets.expectedListNet == null || nets.expectedListNet <= 0) {
            return lineItem;
        }

        Decimal procedureNet = getDecimalFromTag(lineItem, 'NetUnitPrice');
        if (procedureNet != null && procedureNet > 0
            && nets.expectedCommercialNet != null
            && procedureNet.setScale(2, RoundingMode.HALF_UP) == nets.expectedCommercialNet.setScale(2, RoundingMode.HALF_UP)) {
            return lineItem;
        }

        Map<String, Object> adjusted = new Map<String, Object>(lineItem);
        adjusted.put('NetUnitPrice', nets.expectedListNet);
        adjusted.put('UnitPrice', nets.expectedListNet);
        return adjusted;
    }

    @TestVisible
    private Map<String, Object> buildDerivedMaintenanceSequentialDiscountUpdate(
        Map<String, Object> lineItem,
        NewMaintInputs maintInputs
    ) {
        Id lineItemId = getLineItemRecordId(lineItem);
        Id quoteId = maintInputs != null ? maintInputs.parentId : resolveQuoteIdFromLineItem(lineItem);
        Object updatePath = resolveRenewalMaintenanceUpdatePath(lineItem, lineItemId, quoteId);
        if (updatePath == null) {
            return null;
        }

        NewBusinessMaintenanceNets nets = computeNewBusinessMaintenanceNets(lineItem, maintInputs);
        Decimal derivedListNet = nets.expectedListNet != null && nets.expectedListNet > 0
            ? nets.expectedListNet
            : getDecimalFromTag(lineItem, 'NetUnitPrice');
        if (derivedListNet == null || derivedListNet <= 0) {
            return null;
        }

        Decimal partnerPercent = nets.partnerPercent;
        Decimal manualPercent = nets.softwareDiscount;
        if ((partnerPercent == null || partnerPercent <= 0) && (manualPercent == null || manualPercent <= 0)) {
            return null;
        }

        // Sequential partner-then-software discount (build*Update step 3a): identical to the prior
        // inline (pre-init to base, apply only when percent > 0) — see SequentialDiscountCalculator.
        Decimal partnerUnitPrice = SequentialDiscountCalculator.applyDiscountPercent(derivedListNet, partnerPercent);
        Decimal commercialNet = SequentialDiscountCalculator.applyDiscountPercent(partnerUnitPrice, manualPercent);

        if (commercialNet >= derivedListNet) {
            return null;
        }

        Decimal existingNet = getDecimalFromTag(lineItem, 'NetUnitPrice');
        if (existingNet != null
            && nets.expectedCommercialNet != null
            && existingNet.setScale(2, RoundingMode.HALF_UP) == nets.expectedCommercialNet.setScale(2, RoundingMode.HALF_UP)) {
            return null;
        }

        Decimal quantity = getDecimalFromTag(lineItem, 'Quantity');
        if (quantity == null || quantity <= 0) {
            quantity = 1;
        }
        Decimal lineTotal = (commercialNet * quantity).setScale(2, RoundingMode.HALF_UP);

        System.debug(LoggingLevel.INFO, 'DERIVED MAINT DISCOUNT: list=' + derivedListNet +
            ' partner%=' + partnerPercent + ' manual%=' + manualPercent + ' net=' + commercialNet);

        // Attribute-map assembly delegated to the pure DerivedMaintenancePayloadBuilder
        // (Wave-2 decomposition, build*Update step 6). All arithmetic/guards stay above.
        return DerivedMaintenancePayloadBuilder.buildSequentialDiscountPayload(
            updatePath,
            commercialNet,
            lineTotal,
            partnerUnitPrice,
            derivedListNet,
            maintInputs != null ? maintInputs.contributorNetPrice : null,
            partnerPercent,
            manualPercent
        );
    }

    @TestVisible
    private Decimal resolveStampedPartnerPercent(Map<String, Object> lineItem) {
        // Delegates to ListPriceStampCalculator (Wave-2 decomposition, increment 12).
        return ListPriceStampCalculator.resolveStampedPartnerPercent(lineItem);
    }

    @TestVisible
    private Decimal resolveStampedManualPercent(Map<String, Object> lineItem) {
        return ListPriceStampCalculator.resolveStampedManualPercent(lineItem);
    }

    @TestVisible
    private void addAttributeTierListPriceIfNeeded(
        List<Map<String, Object>> attributes,
        Map<String, Object> lineItem
    ) {
        Decimal listPriceToStamp = resolveAttributeTierListPrice(lineItem, null);
        if (listPriceToStamp == null) {
            return;
        }

        attributes.add(new Map<String, Object>{
            'attributeName' => 'ListPrice',
            'attributeValue' => listPriceToStamp
        });
    }

    @TestVisible
    private void mergeListPriceStampIntoUpdate(
        Map<String, Object> itemUpdate,
        Map<String, Object> lineItem,
        Map<Id, String> productTypeByLineId
    ) {
        if (itemUpdate == null || !itemUpdate.containsKey('attributes')) {
            return;
        }

        Object attrsObj = itemUpdate.get('attributes');
        if (!(attrsObj instanceof List<Map<String, Object>>)) {
            return;
        }

        List<Map<String, Object>> attributes = (List<Map<String, Object>>) attrsObj;
        for (Map<String, Object> attribute : attributes) {
            if (attribute != null && attribute.get('attributeName') == 'ListPrice') {
                return;
            }
        }

        Decimal listPriceToStamp = resolveAttributeTierListPrice(lineItem, productTypeByLineId);
        if (listPriceToStamp == null) {
            return;
        }

        attributes.add(new Map<String, Object>{
            'attributeName' => 'ListPrice',
            'attributeValue' => listPriceToStamp
        });
    }

    /**
     * @description Stamp ListPrice so users see attribute/tier price, not pricebook entry.
     *              Perpetual: Base_Price__c ($20k). Derived maintenance: procedure derived list ($4k).
     */
    @TestVisible
    private Decimal resolveAttributeTierListPrice(
        Map<String, Object> lineItem,
        Map<Id, String> productTypeByLineId
    ) {
        // Delegates to ListPriceStampCalculator (Wave-2 decomposition, increment 12).
        return ListPriceStampCalculator.resolveAttributeTierListPrice(lineItem, productTypeByLineId);
    }

    @TestVisible
    private Map<String, Object> buildAttributeListPriceOnlyUpdate(Map<String, Object> lineItem) {
        return buildAttributeListPriceOnlyUpdate(lineItem, null);
    }

    @TestVisible
    private Map<String, Object> buildAttributeListPriceOnlyUpdate(
        Map<String, Object> lineItem,
        Map<Id, String> productTypeByLineId
    ) {
        Id lineItemId = getLineItemRecordId(lineItem);
        Id quoteId = resolveQuoteIdFromLineItem(lineItem);
        Object updatePath = resolveRenewalMaintenanceUpdatePath(lineItem, lineItemId, quoteId);
        if (updatePath == null) {
            return null;
        }

        Decimal listPriceToStamp = resolveAttributeTierListPrice(lineItem, productTypeByLineId);
        if (listPriceToStamp == null) {
            return null;
        }

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'attributeName' => 'ListPrice', 'attributeValue' => listPriceToStamp }
            }
        };
    }

    /**
     * @description Post-procedure fallback for a New-Maintenance line the procedure left at $0.
     *              net = maintenance_rate x contributor pre-partner base, less carried partner/manual %.
     */
    @TestVisible
    private Map<String, Object> buildNewMaintenanceUpdate(
        Map<String, Object> lineItem,
        Map<Id, NewMaintInputs> newMaintenanceByLineId
    ) {
        if (newMaintenanceByLineId == null || newMaintenanceByLineId.isEmpty()) {
            return null;
        }
        Id lineItemId = getLineItemRecordId(lineItem);
        if (lineItemId == null || !newMaintenanceByLineId.containsKey(lineItemId)) {
            return null;
        }

        // Only act when the procedure left the net unset/zero — never override a priced line.
        Decimal procedureNet = getDecimalFromTag(lineItem, 'NetUnitPrice');
        if (procedureNet != null && procedureNet > 0) {
            return null;
        }

        NewMaintInputs inputs = newMaintenanceByLineId.get(lineItemId);
        if (inputs == null || inputs.rate == null || inputs.rate <= 0) {
            return null;
        }

        Boolean usesContributorNet = inputs.contributorNetPrice != null && inputs.contributorNetPrice > 0;
        Decimal pricingBase = usesContributorNet
            ? inputs.contributorNetPrice
            : inputs.sourceListPrice;
        if (pricingBase == null || pricingBase <= 0) {
            return null;
        }

        Decimal net = (pricingBase * inputs.rate).setScale(2, RoundingMode.HALF_UP);
        if (net <= 0) {
            return null;
        }

        // build*Update step 3b: net less partner% then software% (SequentialDiscountCalculator).
        // Keep the coalesced-to-0 locals — they are stamped into the payload below.
        Decimal partnerPercent = inputs.partnerPercent != null ? inputs.partnerPercent : 0;
        net = SequentialDiscountCalculator.applyDiscountPercent(net, partnerPercent);
        Decimal softwareDiscount = inputs.softwareDiscount != null ? inputs.softwareDiscount : 0;
        net = SequentialDiscountCalculator.applyDiscountPercent(net, softwareDiscount);
        if (net <= 0) {
            return null;
        }

        Object updatePath = resolveRenewalMaintenanceUpdatePath(lineItem, lineItemId, inputs.parentId);
        if (updatePath == null) {
            return null;
        }

        Decimal quantity = getDecimalFromTag(lineItem, 'Quantity');
        if (quantity == null || quantity <= 0) {
            quantity = inputs.quantity != null ? inputs.quantity : 1;
        }
        Decimal lineTotal = (net * quantity).setScale(2, RoundingMode.HALF_UP);

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => net },
            new Map<String, Object>{ 'attributeName' => 'NetTotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'Subtotal', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalLineAmount', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'PartnerUnitPrice', 'attributeValue' => net },
            new Map<String, Object>{
                'attributeName' => 'Partner_Pricing_Source__c',
                'attributeValue' => 'System Calculated (Post-Procedure Fallback)'
            }
        };
        if (inputs.partnerPercent != null && inputs.partnerPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => inputs.partnerPercent
            });
        }

        System.debug(LoggingLevel.INFO, 'NEW MAINT FALLBACK: Line ' + lineItemId +
            ' base=' + pricingBase + ' net=' + net + ' contributorNet=' + usesContributorNet);

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
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

    /**
     * @description RCA persist often leaves ListPrice at the pricebook value. Stamp attribute/tier
     *              list on QLIs after persist so users see the real price ($20k perpetual, $4k maint).
     */
    @TestVisible
    public static Integer stampAttributeListPricesForQuote(Id quoteId) {
        if (quoteId == null) {
            return 0;
        }

        Map<String, Decimal> rateByType = new PartnerNetPricePosthook().loadMaintenanceRates();
        Map<Id, String> tierByLine = new Map<Id, String>();
        for (QuoteLineItemAttribute attr : [
            SELECT QuoteLineItemId, AttributeValue
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId IN (
                SELECT Id FROM QuoteLineItem WHERE QuoteId = :quoteId
            )
            AND AttributeName = 'Maintenance Type Defn'
        ]) {
            if (String.isNotBlank(attr.AttributeValue)) {
                tierByLine.put(attr.QuoteLineItemId, attr.AttributeValue);
            }
        }

        List<QuoteLineItem> updates = new List<QuoteLineItem>();
        for (QuoteLineItem qli : [
            SELECT Id, Fortra_Product_Type__c, Base_Price__c, Pre_Partner_Price__c,
                   ListPrice, UnitPrice, NetUnitPrice, PartnerUnitPrice, Source_List_Price__c,
                   PartnerDiscountPercent, Discount, Partner_Pricing_Source__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
        ]) {
            QuoteLineItem upd = buildAttributeListPriceStampUpdate(qli, rateByType, tierByLine);
            if (upd != null) {
                updates.add(upd);
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
        return updates.size();
    }

    @TestVisible
    private static QuoteLineItem buildAttributeListPriceStampUpdate(
        QuoteLineItem qli,
        Map<String, Decimal> rateByType,
        Map<Id, String> tierByLine
    ) {
        if (qli == null) {
            return null;
        }

        QuoteLineItem upd = new QuoteLineItem(Id = qli.Id);
        Boolean changed = false;
        String productType = qli.Fortra_Product_Type__c;

        if (productType == 'Perpetual' || productType == 'Software') {
            Decimal basePrice = qli.Base_Price__c != null && qli.Base_Price__c > 0
                ? qli.Base_Price__c
                : qli.Pre_Partner_Price__c;
            if (basePrice != null && basePrice > 0
                && (qli.Source_List_Price__c == null || qli.Source_List_Price__c < basePrice)) {
                upd.Source_List_Price__c = basePrice;
                changed = true;
            }
        } else if (productType == 'New Maintenance' || productType == 'Renewal Maintenance') {
            Decimal derivedList = resolveDerivedMaintenanceListPrice(qli, rateByType, tierByLine);

            Decimal partnerPercent = qli.PartnerDiscountPercent;
            if (derivedList != null && partnerPercent != null && partnerPercent > 0) {
                // build*Update step 3c: inside the partnerPercent>0 guard, identical to the inline.
                Decimal partnerNet = SequentialDiscountCalculator.applyDiscountPercent(derivedList, partnerPercent);
                if (qli.PartnerUnitPrice == null
                    || qli.PartnerUnitPrice.setScale(2, RoundingMode.HALF_UP) != partnerNet) {
                    upd.PartnerUnitPrice = partnerNet;
                    changed = true;
                }
            }

            if (qli.Partner_Pricing_Source__c != 'System Calculated (Post-Procedure)') {
                upd.Partner_Pricing_Source__c = 'System Calculated (Post-Procedure)';
                changed = true;
            }
        }

        return changed ? upd : null;
    }

    @TestVisible
    private static Decimal resolveDerivedMaintenanceListPrice(
        QuoteLineItem qli,
        Map<String, Decimal> rateByType,
        Map<Id, String> tierByLine
    ) {
        // Delegates to ListPriceStampCalculator (Wave-2 decomposition, increment 12).
        return ListPriceStampCalculator.resolveDerivedMaintenanceListPrice(qli, rateByType, tierByLine);
    }
}