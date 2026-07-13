/**
 * @description Pure list-price / stamped-discount resolvers with no SOQL, DML, or RCA context.
 *              Resolves the ListPrice value to stamp and the carried partner/manual discount
 *              percents from either a context line map or a QuoteLineItem. Unit-testable.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class ListPriceStampCalculator {

    /**
     * @description Stamped partner discount % carried on a context line
     *              (PartnerDiscountPercent tag, else Partner_Discount_Percent__c).
     * @param lineItem Context line map whose tags carry the partner discount percent.
     * @return The stamped partner discount percent, or null when none is carried.
     */
    public static Decimal resolveStampedPartnerPercent(Map<String, Object> lineItem) {
        Decimal partnerPercent = ContextTagReader.getDecimalFromTag(lineItem, 'PartnerDiscountPercent');
        if (partnerPercent != null && partnerPercent > 0) {
            return partnerPercent;
        }
        return ContextTagReader.getDecimalFromTag(lineItem, 'Partner_Discount_Percent__c');
    }

    /**
     * @description Stamped manual discount % carried on a context line
     *              (ItemDiscountPercentage tag, else Discount).
     * @param lineItem Context line map whose tags carry the manual discount percent.
     * @return The stamped manual discount percent, or null when none is carried.
     */
    public static Decimal resolveStampedManualPercent(Map<String, Object> lineItem) {
        Decimal manualPercent = ContextTagReader.getDecimalFromTag(lineItem, 'ItemDiscountPercentage');
        if (manualPercent != null && manualPercent > 0) {
            return manualPercent;
        }
        return ContextTagReader.getDecimalFromTag(lineItem, 'Discount');
    }

    /**
     * @description ListPrice to stamp for attribute-tier / derived lines. Derived maintenance uses
     *              the net (or unit) as list when above the current ListPrice; otherwise the base
     *              (or pre-partner) price when it exceeds the current ListPrice. Null = no restamp.
     * @param lineItem Context line map supplying product type, net/unit, base and current ListPrice.
     * @param productTypeByLineId Fallback map of product type keyed by line record Id.
     * @return The ListPrice to stamp, or null when no restamp applies.
     */
    public static Decimal resolveAttributeTierListPrice(
        Map<String, Object> lineItem,
        Map<Id, String> productTypeByLineId
    ) {
        String productType = PartnerPricingService.resolveProductType(
            ContextTagReader.getStringFromTag(lineItem, 'Fortra_Product_Type__c'),
            ContextTagReader.getLineItemRecordId(lineItem),
            productTypeByLineId
        );

        if (DerivedMaintenanceClassifier.isDerivedMaintenanceProductType(productType)) {
            Decimal derivedList = ContextTagReader.getDecimalFromTag(lineItem, 'NetUnitPrice');
            if (derivedList == null || derivedList <= 0) {
                derivedList = ContextTagReader.getDecimalFromTag(lineItem, 'UnitPrice');
            }
            if (derivedList == null || derivedList <= 0) {
                return null;
            }

            Decimal listPrice = ContextTagReader.getDecimalFromTag(lineItem, 'ListPrice');
            if (listPrice != null && listPrice >= derivedList) {
                return null;
            }
            return derivedList;
        }

        Decimal basePrice = ContextTagReader.getDecimalFromTag(lineItem, 'Base_Price__c');
        if (basePrice == null || basePrice <= 0) {
            basePrice = ContextTagReader.getDecimalFromTag(lineItem, 'Pre_Partner_Price__c');
        }
        if (basePrice == null || basePrice <= 0) {
            return null;
        }

        Decimal listPrice = ContextTagReader.getDecimalFromTag(lineItem, 'ListPrice');
        if (listPrice != null && listPrice >= basePrice) {
            return null;
        }
        return basePrice;
    }

    /**
     * @description Derived-maintenance ListPrice from a QuoteLineItem: unit price when it already
     *              tops net; else base x tier-rate; else net grossed-up by carried partner/manual %.
     * @param qli QuoteLineItem supplying unit/net/base prices and carried discount percents.
     * @param rateByType Tier-rate multipliers keyed by tier name.
     * @param tierByLine Tier name keyed by QuoteLineItem Id, used to look up the rate.
     * @return The derived-maintenance ListPrice, or null when none can be resolved.
     */
    public static Decimal resolveDerivedMaintenanceListPrice(
        QuoteLineItem qli,
        Map<String, Decimal> rateByType,
        Map<Id, String> tierByLine
    ) {
        if (qli.UnitPrice != null && qli.UnitPrice > 0
            && (qli.NetUnitPrice == null || qli.UnitPrice >= qli.NetUnitPrice)) {
            return qli.UnitPrice;
        }

        Decimal rate = null;
        if (rateByType != null && tierByLine != null) {
            String tier = tierByLine.get(qli.Id);
            if (String.isNotBlank(tier) && rateByType.containsKey(tier)) {
                rate = rateByType.get(tier);
            }
        }

        Decimal basePrice = qli.Base_Price__c != null && qli.Base_Price__c > 0
            ? qli.Base_Price__c
            : qli.Pre_Partner_Price__c;
        if (rate != null && rate > 0 && basePrice != null && basePrice > 0) {
            return (basePrice * rate).setScale(2, RoundingMode.HALF_UP);
        }

        if (qli.NetUnitPrice != null && qli.NetUnitPrice > 0) {
            Decimal partnerPercent = qli.PartnerDiscountPercent != null ? qli.PartnerDiscountPercent : 0;
            Decimal manualPercent = qli.Discount != null ? qli.Discount : 0;
            Decimal divisor = (1 - (partnerPercent / 100)) * (1 - (manualPercent / 100));
            if (divisor > 0) {
                return (qli.NetUnitPrice / divisor).setScale(2, RoundingMode.HALF_UP);
            }
        }

        return null;
    }
}