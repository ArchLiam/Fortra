/**
 * @description Pure New-Maintenance partner-band mapping: determines which billing partners are in
 *              play and resolves the discount band per line, operating on loaded SObjects and partner
 *              pricing models with no SOQL and no RCA context (unit-testable).
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class NewMaintenanceBandCalculator {

    /**
     * @description The New-Maintenance discount band from a billing partner's Discount pricing model.
     *              Returns null unless the model is Discount and a positive New_Maintenance_Percent__c
     *              resolves, so callers fall back to existing behavior.
     * @param pricingModel The partner pricing model name; must be 'Discount' to yield a band.
     * @param billingPartnerId The billing partner whose pricing model supplies the band.
     * @param models Billing-partner Id to Partner_Pricing_Model__c lookup.
     * @return The positive New-Maintenance band, or null when not a Discount model or no positive band resolves.
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

    /**
     * @description Discount-model billing-partner Ids from loaded Quotes.
     * @param quotes Quote Id to Quote lookup to scan for Discount-model billing partners.
     * @return The set of billing-partner Ids referenced by Discount-model quotes.
     */
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

    /**
     * @description Discount-model billing-partner Ids from loaded Orders (via each source Quote).
     * @param orders Order Id to Order lookup (with source Quote) to scan for Discount-model billing partners.
     * @return The set of billing-partner Ids referenced by Discount-model source quotes.
     */
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

    /**
     * @description New-Maintenance band keyed by Quote Id.
     * @param quotes Quote Id to Quote lookup to resolve bands for.
     * @param models Billing-partner Id to Partner_Pricing_Model__c lookup.
     * @return Map of Quote Id to its resolved New-Maintenance band, excluding quotes with no band.
     */
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

    /**
     * @description New-Maintenance band keyed by Order Id (resolved from each Order's source Quote).
     * @param orders Order Id to Order lookup (with source Quote) to resolve bands for.
     * @param models Billing-partner Id to Partner_Pricing_Model__c lookup.
     * @return Map of Order Id to its resolved New-Maintenance band, excluding orders with no band.
     */
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