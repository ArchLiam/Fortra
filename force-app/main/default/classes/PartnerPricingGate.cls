/**
 * @description Pure partner-pricing decision predicates extracted verbatim from
 *              PartnerNetPricePosthook (Wave-2 decomposition, increment 14). Decide whether a line
 *              needs deferred partner pricing and whether the procedure already owns the partner net
 *              (so the posthook should skip it). No SOQL, no DML, no RCA context — unit-testable.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class PartnerPricingGate {

    /**
     * @description True when the pricing procedure already stamped the partner net (so the posthook
     *              must not re-apply it): the procedure net equals the commercial unit price and
     *              matches the partner unit price, or the line is flagged Procedure-sourced.
     * @param lineItem The context line-item tag map being evaluated.
     * @param partnerUnitPrice The partner-specific unit price for the line.
     * @param partnerDiscountPercent The partner discount percentage applied to the line.
     * @param procedureNet The net unit price the pricing procedure produced.
     * @return True when the procedure already owns the partner net so the posthook should skip it.
     */
    public static Boolean shouldSkipProcedureOwnedPartner(
        Map<String, Object> lineItem,
        Decimal partnerUnitPrice,
        Decimal partnerDiscountPercent,
        Decimal procedureNet
    ) {
        if (partnerUnitPrice == null || partnerUnitPrice <= 0) {
            return false;
        }

        Decimal commercialUnitPrice = PartnerNetResolutionCalculator.resolveCommercialUnitPrice(procedureNet, partnerUnitPrice);
        Decimal existingPartnerUnit = ContextTagReader.getDecimalFromTag(lineItem, 'PartnerUnitPrice');

        if (procedureNet != null && procedureNet > 0 && procedureNet == commercialUnitPrice) {
            if (commercialUnitPrice == partnerUnitPrice) {
                return true;
            }
            if (existingPartnerUnit != null && existingPartnerUnit == partnerUnitPrice) {
                return true;
            }
        }

        String pricingSource = ContextTagReader.getStringFromTag(lineItem, 'Partner_Pricing_Source__c');
        return String.isNotBlank(pricingSource)
            && pricingSource.contains('Procedure')
            && partnerDiscountPercent != null
            && partnerDiscountPercent > 0
            && procedureNet != null
            && procedureNet == commercialUnitPrice;
    }

    /**
     * @description True for a line the pre-hook skipped (partner unit price still 0) but the
     *              procedure has since set a positive net over a zero pre-procedure price — i.e.
     *              derived maintenance that needs partner pricing applied post-procedure.
     * @param lineItem The context line-item tag map being evaluated.
     * @return True when the line requires partner pricing applied after the procedure runs.
     */
    public static Boolean needsDeferredPartnerPricing(Map<String, Object> lineItem) {
        Decimal partnerUnitPrice = ContextTagReader.getDecimalFromTag(lineItem, 'PartnerUnitPrice');
        if (partnerUnitPrice != null && partnerUnitPrice > 0) {
            return false;
        }

        Decimal netUnitPrice = ContextTagReader.getDecimalFromTag(lineItem, 'NetUnitPrice');
        if (netUnitPrice == null || netUnitPrice <= 0) {
            return false;
        }

        Decimal preProcedurePrice = PartnerNetResolutionCalculator.resolvePreProcedurePrice(
            ContextTagReader.getDecimalFromTag(lineItem, 'RegionalNetUnitPrice__c'),
            ContextTagReader.getDecimalFromTag(lineItem, 'UnitPrice'),
            ContextTagReader.getDecimalFromTag(lineItem, 'ListPrice')
        );
        return preProcedurePrice == null || preProcedurePrice <= 0;
    }
}