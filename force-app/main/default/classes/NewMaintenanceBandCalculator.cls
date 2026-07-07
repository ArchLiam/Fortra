/**
 * @description Pure New-Maintenance partner-band mapping, extracted from PartnerNetPricePosthook
 *              (Wave-2 decomposition, increment 4 — SOQL-vs-pure split). The posthook resolvers keep
 *              the SOQL loads (Quote/Order + PartnerPricingService.getPricingModels); this calculator
 *              holds the pure logic (which billing partners are in play, and the band per line).
 *              No SOQL, no RCA context — unit-testable on loaded SObjects + models.
 */
public with sharing class NewMaintenanceBandCalculator {

    /**
     * @description The New-Maintenance discount band from a billing partner's Discount pricing model.
     *              Returns null unless the model is Discount and a positive New_Maintenance_Percent__c
     *              resolves, so callers fall back to existing behavior.
     */
    public static Decimal newMaintenanceBand(
        String pricingModel,
        Id billingPartnerId,
        Map<Id, Partner_Pricing_Model__c> models
    ) {
        if (pricingModel != 'Discount' || billingPartnerId == null || models == null) {
            return null;
        }
        Partner_Pricing_Model__c model = models.get(billingPartnerId);
        if (model == null) {
            return null;
        }
        Decimal band = PartnerPricingService.getMarginForProductType(model, 'New Maintenance');
        return (band != null && band > 0) ? band : null;
    }

    /** @description Discount-model billing-partner Ids from loaded Quotes. */
    public static Set<Id> billingPartnerIdsFromQuotes(Map<Id, Quote> quotes) {
        Set<Id> billingPartnerIds = new Set<Id>();
        if (quotes == null) {
            return billingPartnerIds;
        }
        for (Quote q : quotes.values()) {
            if (q.Partner_Pricing_Model__c == 'Discount' && q.Billing_Partner__c != null) {
                billingPartnerIds.add(q.Billing_Partner__c);
            }
        }
        return billingPartnerIds;
    }

    /** @description Discount-model billing-partner Ids from loaded Orders (via each source Quote). */
    public static Set<Id> billingPartnerIdsFromOrders(Map<Id, Order> orders) {
        Set<Id> billingPartnerIds = new Set<Id>();
        if (orders == null) {
            return billingPartnerIds;
        }
        for (Order ord : orders.values()) {
            if (ord.Quote != null
                && ord.Quote.Partner_Pricing_Model__c == 'Discount'
                && ord.Quote.Billing_Partner__c != null) {
                billingPartnerIds.add(ord.Quote.Billing_Partner__c);
            }
        }
        return billingPartnerIds;
    }

    /** @description New-Maintenance band keyed by Quote Id. */
    public static Map<Id, Decimal> bandByQuote(
        Map<Id, Quote> quotes,
        Map<Id, Partner_Pricing_Model__c> models
    ) {
        Map<Id, Decimal> bands = new Map<Id, Decimal>();
        if (quotes == null) {
            return bands;
        }
        for (Quote q : quotes.values()) {
            Decimal band = newMaintenanceBand(q.Partner_Pricing_Model__c, q.Billing_Partner__c, models);
            if (band != null) {
                bands.put(q.Id, band);
            }
        }
        return bands;
    }

    /** @description New-Maintenance band keyed by Order Id (resolved from each Order's source Quote). */
    public static Map<Id, Decimal> bandByOrder(
        Map<Id, Order> orders,
        Map<Id, Partner_Pricing_Model__c> models
    ) {
        Map<Id, Decimal> bands = new Map<Id, Decimal>();
        if (orders == null) {
            return bands;
        }
        for (Order ord : orders.values()) {
            if (ord.Quote == null) {
                continue;
            }
            Decimal band = newMaintenanceBand(ord.Quote.Partner_Pricing_Model__c, ord.Quote.Billing_Partner__c, models);
            if (band != null) {
                bands.put(ord.Id, band);
            }
        }
        return bands;
    }
}
