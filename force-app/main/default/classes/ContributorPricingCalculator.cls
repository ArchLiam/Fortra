/**
 * @description Pure contributor-line pricing helpers, extracted verbatim from PartnerNetPricePosthook
 *              (Wave-2 decomposition, increment 2). Derive the contributing perpetual line's commercial
 *              base and carried partner/software discount percentages for derived-maintenance pricing.
 *              Deterministic: read QuoteLineItem / OrderItem fields only — no SOQL, no RCA context —
 *              so they are unit-testable without the pricing runtime.
 */
public with sharing class ContributorPricingCalculator {

    public static Decimal resolveContributorPartnerPercent(QuoteLineItem contributorLine, Decimal pricingBase) {
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

    public static Decimal resolveContributorSoftwarePercent(
        QuoteLineItem contributorLine,
        Decimal pricingBase,
        Decimal partnerPercent
    ) {
        if (contributorLine.Discount != null && contributorLine.Discount > 0) {
            return contributorLine.Discount;
        }
        Decimal preManualNet = pricingBase;
        if (partnerPercent != null && partnerPercent > 0) {
            preManualNet = (pricingBase * (1 - (partnerPercent / 100))).setScale(2, RoundingMode.HALF_UP);
        }
        if (contributorLine.Prior_Discretionary_Discount__c != null
            && contributorLine.Prior_Discretionary_Discount__c > 0
            && preManualNet != null && preManualNet > 0) {
            return (contributorLine.Prior_Discretionary_Discount__c / preManualNet * 100)
                .setScale(2, RoundingMode.HALF_UP);
        }
        return null;
    }

    public static Decimal resolveContributorPricingBase(QuoteLineItem contributorLine) {
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

    public static Decimal resolveContributorPricingBase(OrderItem contributorLine) {
        if (contributorLine == null) {
            return null;
        }
        if (contributorLine.NetUnitPrice != null && contributorLine.NetUnitPrice > 0) {
            return contributorLine.NetUnitPrice;
        }
        if (contributorLine.Base_Price__c != null && contributorLine.Base_Price__c > 0) {
            return contributorLine.Base_Price__c;
        }
        if (contributorLine.ListPrice != null && contributorLine.ListPrice > 0) {
            return contributorLine.ListPrice;
        }
        if (contributorLine.UnitPrice != null && contributorLine.UnitPrice > 0) {
            return contributorLine.UnitPrice;
        }
        return null;
    }
}
