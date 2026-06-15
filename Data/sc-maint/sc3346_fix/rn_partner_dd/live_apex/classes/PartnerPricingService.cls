/**
 * @description Service class for Partner Pricing business logic.
 *              Provides reusable methods for pricing calculations, model validation,
 *              and partner pricing configuration management.
 * @author Marc DeBrey
 * @date December 2025
 */
public without sharing class PartnerPricingService {
    /**
     * @description Gets the Partner Pricing Model record for a specific partner and model type
     * @param partnerId The Account ID of the partner
     * @param modelType The model type ("Guaranteed Margin" or "Discount")
     * @return Partner_Pricing_Model__c record or null if not found
     */
    public static Partner_Pricing_Model__c getPricingModel(Id partnerId, String modelType) {
        if (partnerId == null || String.isBlank(modelType)) {
            return null;
        }

        List<Partner_Pricing_Model__c> models = [
            SELECT Id, Account__c, Model_Type__c, Is_Active__c, Is_Default__c,
                   Software_Percent__c, New_Maintenance_Percent__c, Renewal_Maintenance_Percent__c,
                   Subscription_Percent__c, Services_Percent__c,
                   Effective_Start_Date__c, Effective_End_Date__c
            FROM Partner_Pricing_Model__c
            WHERE Account__c = :partnerId
            AND Model_Type__c = :modelType
            AND Is_Active__c = true
            AND (Effective_Start_Date__c = null OR Effective_Start_Date__c <= TODAY)
            AND (Effective_End_Date__c = null OR Effective_End_Date__c >= TODAY)
            LIMIT 1
        ];

        return models.isEmpty() ? null : models[0];
    }

    /**
     * @description Gets partner pricing models for multiple partners (bulk operation)
     * @param partnerIds Set of Account IDs
     * @param modelType The model type to retrieve
     * @return Map of Account ID to Partner_Pricing_Model__c
     */
    public static Map<Id, Partner_Pricing_Model__c> getPricingModels(Set<Id> partnerIds, String modelType) {
        Map<Id, Partner_Pricing_Model__c> modelsByPartner = new Map<Id, Partner_Pricing_Model__c>();

        if (partnerIds == null || partnerIds.isEmpty() || String.isBlank(modelType)) {
            return modelsByPartner;
        }

        for (Partner_Pricing_Model__c model : [
            SELECT Id, Account__c, Model_Type__c, Is_Active__c, Is_Default__c,
                   Software_Percent__c, New_Maintenance_Percent__c, Renewal_Maintenance_Percent__c,
                   Subscription_Percent__c, Services_Percent__c,
                   Effective_Start_Date__c, Effective_End_Date__c
            FROM Partner_Pricing_Model__c
            WHERE Account__c IN :partnerIds
            AND Model_Type__c = :modelType
            AND Is_Active__c = true
            AND (Effective_Start_Date__c = null OR Effective_Start_Date__c <= TODAY)
            AND (Effective_End_Date__c = null OR Effective_End_Date__c >= TODAY)
        ]) {
            modelsByPartner.put(model.Account__c, model);
        }

        return modelsByPartner;
    }

    /**
     * @description Resolve Fortra product type for partner margin selection.
     *              Uses the context value when present; otherwise falls back to the
     *              QuoteLineItem field and then Product2 (derived maintenance lines
     *              often have a null line-level copy).
     */
    public static String resolveProductType(String contextProductType, Id quoteLineItemId) {
        if (String.isNotBlank(contextProductType)) {
            return contextProductType;
        }

        if (quoteLineItemId != null) {
            for (QuoteLineItem qli : [
                SELECT Fortra_Product_Type__c, Product2.Fortra_Product_Type__c
                FROM QuoteLineItem
                WHERE Id = :quoteLineItemId
                LIMIT 1
            ]) {
                if (String.isNotBlank(qli.Fortra_Product_Type__c)) {
                    return qli.Fortra_Product_Type__c;
                }
                if (String.isNotBlank(qli.Product2.Fortra_Product_Type__c)) {
                    return qli.Product2.Fortra_Product_Type__c;
                }
            }
        }

        return 'Software';
    }

    /**
     * @description Bulk-load product types for quote lines (avoids per-line SOQL in posthooks).
     */
    public static Map<Id, String> loadProductTypesForLines(Set<Id> quoteLineItemIds) {
        Map<Id, String> productTypeByLineId = new Map<Id, String>();

        if (quoteLineItemIds == null || quoteLineItemIds.isEmpty()) {
            return productTypeByLineId;
        }

        Map<Id, Id> product2IdByLineId = new Map<Id, Id>();
        for (QuoteLineItem qli : [
            SELECT Id, Product2Id, Fortra_Product_Type__c, Product2.Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE Id IN :quoteLineItemIds
        ]) {
            String productType = String.isNotBlank(qli.Fortra_Product_Type__c)
                ? qli.Fortra_Product_Type__c
                : qli.Product2.Fortra_Product_Type__c;
            if (String.isNotBlank(productType)) {
                productTypeByLineId.put(qli.Id, productType);
            } else if (qli.Product2Id != null) {
                product2IdByLineId.put(qli.Id, qli.Product2Id);
            }
        }

        if (!product2IdByLineId.isEmpty()) {
            Map<Id, Product2> productById = new Map<Id, Product2>([
                SELECT Id, Fortra_Product_Type__c
                FROM Product2
                WHERE Id IN :product2IdByLineId.values()
            ]);
            for (Id qliId : product2IdByLineId.keySet()) {
                Product2 prod = productById.get(product2IdByLineId.get(qliId));
                if (prod != null && String.isNotBlank(prod.Fortra_Product_Type__c)) {
                    productTypeByLineId.put(qliId, prod.Fortra_Product_Type__c);
                }
            }
        }

        return productTypeByLineId;
    }

    /**
     * @description Bulk-load product types keyed by transaction line record Id (QuoteLineItem or OrderItem).
     */
    public static Map<Id, String> loadProductTypesForTransactionLines(Set<Id> lineRecordIds) {
        Map<Id, String> productTypeByLineId = loadProductTypesForLines(lineRecordIds);

        if (lineRecordIds == null || lineRecordIds.isEmpty()) {
            return productTypeByLineId;
        }

        Set<Id> unresolvedOrderItemIds = new Set<Id>();
        for (Id lineRecordId : lineRecordIds) {
            if (!productTypeByLineId.containsKey(lineRecordId)) {
                unresolvedOrderItemIds.add(lineRecordId);
            }
        }
        if (unresolvedOrderItemIds.isEmpty()) {
            return productTypeByLineId;
        }

        Set<Id> quoteLineItemIds = new Set<Id>();
        Map<Id, Id> orderItemIdByQliId = new Map<Id, Id>();

        for (OrderItem oi : [
            SELECT Id, QuoteLineItemId, Fortra_Product_Type__c, Product2.Fortra_Product_Type__c
            FROM OrderItem
            WHERE Id IN :unresolvedOrderItemIds
        ]) {
            String productType = String.isNotBlank(oi.Fortra_Product_Type__c)
                ? oi.Fortra_Product_Type__c
                : oi.Product2.Fortra_Product_Type__c;
            if (String.isNotBlank(productType)) {
                productTypeByLineId.put(oi.Id, productType);
                continue;
            }
            if (oi.QuoteLineItemId != null) {
                quoteLineItemIds.add(oi.QuoteLineItemId);
                orderItemIdByQliId.put(oi.QuoteLineItemId, oi.Id);
            }
        }

        if (!quoteLineItemIds.isEmpty()) {
            Map<Id, String> productTypeByQliId = loadProductTypesForLines(quoteLineItemIds);
            for (Id qliId : productTypeByQliId.keySet()) {
                Id orderItemId = orderItemIdByQliId.get(qliId);
                if (orderItemId != null) {
                    productTypeByLineId.put(orderItemId, productTypeByQliId.get(qliId));
                }
            }
        }

        return productTypeByLineId;
    }

    /**
     * @description Batch-resolves any line ids missing from a pre-loaded product type map.
     *              Call once before per-line resolveProductType(..., map) to avoid N fallback SOQL.
     */
    public static Map<Id, String> ensureProductTypesLoaded(
        Set<Id> lineRecordIds,
        Map<Id, String> productTypeByLineId
    ) {
        if (productTypeByLineId == null) {
            productTypeByLineId = new Map<Id, String>();
        }
        if (lineRecordIds == null || lineRecordIds.isEmpty()) {
            return productTypeByLineId;
        }

        Set<Id> missingIds = new Set<Id>();
        for (Id lineRecordId : lineRecordIds) {
            if (lineRecordId != null && !productTypeByLineId.containsKey(lineRecordId)) {
                missingIds.add(lineRecordId);
            }
        }
        if (missingIds.isEmpty()) {
            return productTypeByLineId;
        }

        productTypeByLineId.putAll(loadProductTypesForTransactionLines(missingIds));
        return productTypeByLineId;
    }

    /**
     * @description Resolve product type using an optional bulk-loaded map from loadProductTypesForLines.
     *              On map miss, falls through to the single-arg overload (QLI field + Product2 lookup).
     */
    public static String resolveProductType(
        String contextProductType,
        Id quoteLineItemId,
        Map<Id, String> productTypeByLineId
    ) {
        if (String.isNotBlank(contextProductType)) {
            return contextProductType;
        }

        if (quoteLineItemId != null && productTypeByLineId != null) {
            if (productTypeByLineId.containsKey(quoteLineItemId)) {
                return productTypeByLineId.get(quoteLineItemId);
            }
            return resolveProductType(contextProductType, quoteLineItemId);
        }

        return resolveProductType(contextProductType, quoteLineItemId);
    }

    /**
     * @description Gets the margin percentage for a specific product type from a pricing model
     * @param model The Partner Pricing Model record
     * @param productType The Fortra_Product_Type__c value (e.g., "Software", "Subscription")
     * @return Decimal percentage (e.g., 15.00 for 15%)
     */
    public static Decimal getMarginForProductType(Partner_Pricing_Model__c model, String productType) {
        if (model == null || String.isBlank(productType)) {
            return 0;
        }

        switch on productType {
            when 'Software', 'Perpetual' {
                return model.Software_Percent__c != null ? model.Software_Percent__c : 0;
            }
            when 'New Maintenance' {
                return model.New_Maintenance_Percent__c != null ? model.New_Maintenance_Percent__c : 0;
            }
            when 'Renewal Maintenance' {
                return model.Renewal_Maintenance_Percent__c != null ? model.Renewal_Maintenance_Percent__c : 0;
            }
            when 'Subscription', 'SaaS Subscription' {
                return model.Subscription_Percent__c != null ? model.Subscription_Percent__c : 0;
            }
            when 'Services', 'Professional Service', 'Renewal Services' {
                return model.Services_Percent__c != null ? model.Services_Percent__c : 0;
            }
            when else {
                return 0;
            }
        }
    }

    /**
     * @description Calculate Guaranteed Margin price using ADDITIVE formula.
     *              Formula: List Price x (1 - SUM(all partner margins%))
     *              Example: $1000 with margins [15%, 10%] = $1000 × (1 - 0.25) = $750
     * @param listPrice Original list price
     * @param partnerMargins List of margin percentages from all partners (as decimals, e.g., 15 for 15%)
     * @return Adjusted price after all margins applied
     */
    public static Decimal calculateGuaranteedMarginPrice(Decimal listPrice, List<Decimal> partnerMargins) {
        if (listPrice == null || listPrice <= 0) {
            return listPrice;
        }

        if (partnerMargins == null || partnerMargins.isEmpty()) {
            return listPrice;
        }

        // SUM all margins (ADDITIVE approach)
        Decimal totalMarginPercent = 0;
        for (Decimal marginPercent : partnerMargins) {
            if (marginPercent != null && marginPercent > 0) {
                totalMarginPercent += marginPercent;
            }
        }

        // Cap at 100% to avoid negative prices
        if (totalMarginPercent > 100) {
            totalMarginPercent = 100;
        }

        // Apply: Price × (1 - totalMargin%)
        Decimal multiplier = 1 - (totalMarginPercent / 100);
        return (listPrice * multiplier).setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * @description Calculate Discount Model price
     *              Formula: List Price x (1 - Billing Partner's Discount%)
     * @param listPrice Original list price
     * @param discountPercent Billing partner's discount percentage (as decimal, e.g., 20 for 20%)
     * @return Adjusted price after discount applied
     */
    public static Decimal calculateDiscountPrice(Decimal listPrice, Decimal discountPercent) {
        if (listPrice == null || listPrice <= 0) {
            return listPrice;
        }

        if (discountPercent == null || discountPercent <= 0) {
            return listPrice;
        }

        Decimal multiplier = 1 - (discountPercent / 100);
        return (listPrice * multiplier).setScale(2, RoundingMode.HALF_UP);
    }

}