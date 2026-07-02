/**
 * @description Service class for Partner Pricing business logic.
 *              Provides reusable methods for pricing calculations, model validation,
 *              and partner pricing configuration management.
 * @author Marc DeBrey
 * @date December 2025
 */
public without sharing class PartnerPricingServiceV2 {

    private static final String DEAL_TYPE_FORTRA_ORIGINATED = 'Fortra Originated';

    /**
     * @description Gets all valid pricing model candidates for multiple partners (bulk operation)
     * @param partnerIds Set of Account IDs
     * @param modelType The model type to retrieve
     * @return Map of Account ID to ordered list of Partner_Pricing_Model__c candidates
     */
    public static Map<Id, List<Partner_Pricing_Model__c>> getPricingModelCandidates(Set<Id> partnerIds, String modelType) {
        Map<Id, List<Partner_Pricing_Model__c>> modelsByPartner = new Map<Id, List<Partner_Pricing_Model__c>>();

        if (partnerIds == null || partnerIds.isEmpty() || String.isBlank(modelType)) {
            return modelsByPartner;
        }

        for (Partner_Pricing_Model__c model : [
            SELECT Id, Account__c, Model_Type__c, Is_Active__c, Is_Default__c, CreatedDate,
                   Software_Percent__c, New_Maintenance_Percent__c, Renewal_Maintenance_Percent__c,
                   Subscription_Percent__c, Services_Percent__c,
                   Non_Orig_New_Maint_Pct__c, Non_Orig_Ren_Maint_Pct__c, Non_Orig_Services_Pct__c,
                   Non_Orig_Software_Pct__c, Non_Orig_Subscription_Pct__c,
                   Unit__c, Solution_Group__c, Solution_Category__c,
                   Effective_Start_Date__c, Effective_End_Date__c
            FROM Partner_Pricing_Model__c
            WHERE Account__c IN :partnerIds
            AND Model_Type__c = :modelType
            AND Is_Active__c = true
            AND (Effective_Start_Date__c = null OR Effective_Start_Date__c <= TODAY)
            AND (Effective_End_Date__c = null OR Effective_End_Date__c >= TODAY)
            ORDER BY Account__c, CreatedDate DESC
        ]) {
            if (!modelsByPartner.containsKey(model.Account__c)) {
                modelsByPartner.put(model.Account__c, new List<Partner_Pricing_Model__c>());
            }
            modelsByPartner.get(model.Account__c).add(model);
        }

        return modelsByPartner;
    }

    /**
     * @description Selects the best matching model for a quote line based on hierarchy specificity
     * @param models Candidate pricing models for a single partner, ordered newest first
     * @param unit Product Unit value
     * @param solutionGroup Product Solution Group value
     * @param solutionCategory Product Solution Category value
     * @return Best matching Partner_Pricing_Model__c or null if none applies
     */
    public static Partner_Pricing_Model__c selectBestModelForLine(
        List<Partner_Pricing_Model__c> models,
        String unit,
        String solutionGroup,
        String solutionCategory
    ) {
        if (models == null || models.isEmpty()) {
            return null;
        }

        if (String.isNotBlank(solutionCategory)) {
            for (Partner_Pricing_Model__c model : models) {
                if (model.Solution_Category__c == solutionCategory) {
                    return model;
                }
            }
        }

        if (String.isNotBlank(solutionGroup)) {
            for (Partner_Pricing_Model__c model : models) {
                if (String.isBlank(model.Solution_Category__c) &&
                    model.Solution_Group__c == solutionGroup) {
                    return model;
                }
            }
        }

        if (String.isNotBlank(unit)) {
            for (Partner_Pricing_Model__c model : models) {
                if (String.isBlank(model.Solution_Category__c) &&
                    String.isBlank(model.Solution_Group__c) &&
                    model.Unit__c == unit) {
                    return model;
                }
            }
        }

        for (Partner_Pricing_Model__c model : models) {
            if (String.isBlank(model.Solution_Category__c) &&
                String.isBlank(model.Solution_Group__c) &&
                String.isBlank(model.Unit__c)) {
                return model;
            }
        }

        return null;
    }

    /**
     * @description Gets the margin percentage for a specific product type from a pricing model
     *              and deal type specific discount set.
     * @param model The Partner Pricing Model record
     * @param productType The Fortra_Product_Type__c value (e.g., "Software", "Subscription")
     * @param dealType The Quote Deal_Type__c value
     * @return Decimal percentage (e.g., 15.00 for 15%)
     */
    public static Decimal getMarginForProductType(
        Partner_Pricing_Model__c model,
        String productType,
        String dealType
    ) {
        if (model == null || String.isBlank(productType)) {
            return 0;
        }

        Boolean useNonOriginating = dealType == DEAL_TYPE_FORTRA_ORIGINATED;

        switch on productType {
            when 'Software', 'Perpetual' {
                return useNonOriginating
                    ? (model.Non_Orig_Software_Pct__c != null ? model.Non_Orig_Software_Pct__c : 0)
                    : (model.Software_Percent__c != null ? model.Software_Percent__c : 0);
            }
            when 'New Maintenance' {
                return useNonOriginating
                    ? (model.Non_Orig_New_Maint_Pct__c != null ? model.Non_Orig_New_Maint_Pct__c : 0)
                    : (model.New_Maintenance_Percent__c != null ? model.New_Maintenance_Percent__c : 0);
            }
            when 'Renewal Maintenance' {
                return useNonOriginating
                    ? (model.Non_Orig_Ren_Maint_Pct__c != null ? model.Non_Orig_Ren_Maint_Pct__c : 0)
                    : (model.Renewal_Maintenance_Percent__c != null ? model.Renewal_Maintenance_Percent__c : 0);
            }
            when 'Subscription', 'SaaS Subscription' {
                return useNonOriginating
                    ? (model.Non_Orig_Subscription_Pct__c != null ? model.Non_Orig_Subscription_Pct__c : 0)
                    : (model.Subscription_Percent__c != null ? model.Subscription_Percent__c : 0);
            }
            when 'Services', 'Professional Service', 'Renewal Services' {
                return useNonOriginating
                    ? (model.Non_Orig_Services_Pct__c != null ? model.Non_Orig_Services_Pct__c : 0)
                    : (model.Services_Percent__c != null ? model.Services_Percent__c : 0);
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

        Decimal totalMarginPercent = 0;
        for (Decimal marginPercent : partnerMargins) {
            if (marginPercent != null && marginPercent > 0) {
                totalMarginPercent += marginPercent;
            }
        }

        if (totalMarginPercent > 100) {
            totalMarginPercent = 100;
        }

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