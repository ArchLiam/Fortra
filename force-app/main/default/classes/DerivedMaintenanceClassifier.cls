/**
 * @description Pure derived-maintenance line classification predicates, extracted verbatim from
 *              PartnerNetPricePosthook (Wave-2 decomposition, increment 3). Deterministic: operate
 *              on the product type and in-memory maps only — no SOQL, no RCA context.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class DerivedMaintenanceClassifier {

    /**
     * @description True for the derived-maintenance product types (New / Renewal Maintenance).
     * @param productType The product type string to classify.
     * @return True when the product type is New Maintenance or Renewal Maintenance.
     */
    public static Boolean isDerivedMaintenanceProductType(String productType) {
        return productType == 'New Maintenance' || productType == 'Renewal Maintenance';
    }

    /**
     * @description True for a NEW-business derived-maintenance line — a New-Maintenance line on a
     *              non-renewal quote that is not already handled by the renewal-COLA path.
     * @param productType The product type of the line being evaluated.
     * @param isRenewalQuote Whether the owning quote is a renewal quote.
     * @param lineItemId The QuoteLineItem Id used to check the renewal-COLA map.
     * @param renewalColaByLineId Map of line Ids already handled by the renewal-COLA path.
     * @return True when the line is a new-business New-Maintenance line not covered by renewal COLA.
     */
    public static Boolean isNewBusinessDerivedMaintenance(
        String productType,
        Boolean isRenewalQuote,
        Id lineItemId,
        Map<Id, QuoteLineItem> renewalColaByLineId
    ) {
        if (isRenewalQuote || productType != 'New Maintenance') {
            return false;
        }
        if (lineItemId != null && renewalColaByLineId != null && renewalColaByLineId.containsKey(lineItemId)) {
            return false;
        }
        return true;
    }
}