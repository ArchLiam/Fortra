/**
 * @description Pure contributor-line pricing helpers that derive the contributing perpetual line's
 *              commercial base and carried partner/software discount percentages for derived-maintenance
 *              pricing. Deterministic: read QuoteLineItem / OrderItem fields only — no SOQL, no RCA
 *              context — so they are unit-testable without the pricing runtime.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class ContributorPricingCalculator {

    /**
     * @description Resolves the contributing line's effective partner-discount percentage, preferring the
     *              live PartnerDiscountPercent / custom percent field and falling back to reconstructing the
     *              percentage from the prior partner discount amount against the supplied pricing base.
     * @param contributorLine The contributing perpetual QuoteLineItem to read discount fields from.
     * @param pricingBase The commercial base used to convert a prior partner-discount amount into a percentage.
     * @return The partner-discount percentage, or null when none can be resolved.
     */
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

    /**
     * @description Resolves the contributing line's effective software (discretionary) discount percentage,
     *              preferring the live Discount field and otherwise reconstructing it from the prior
     *              discretionary discount amount against the partner-net base derived from pricingBase and
     *              partnerPercent.
     * @param contributorLine The contributing perpetual QuoteLineItem to read discount fields from.
     * @param pricingBase The commercial base before partner and discretionary discounts are applied.
     * @param partnerPercent The partner-discount percentage applied ahead of the discretionary discount.
     * @return The software (discretionary) discount percentage, or null when none can be resolved.
     */
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

    /**
     * @description Resolves the commercial pricing base for a contributing QuoteLineItem, selecting the first
     *              positive value in precedence order: pre-partner price, base price, net unit price when it
     *              exceeds list price, list price, then unit price.
     * @param contributorLine The contributing perpetual QuoteLineItem to derive the base from.
     * @return The resolved pricing base, or null when the line is null or no positive candidate exists.
     */
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

    /**
     * @description Resolves the commercial pricing base for a contributing OrderItem, selecting the first
     *              positive value in precedence order: net unit price, base price, list price, then unit price.
     * @param contributorLine The contributing perpetual OrderItem to derive the base from.
     * @return The resolved pricing base, or null when the line is null or no positive candidate exists.
     */
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