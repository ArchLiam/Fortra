/**
 * @description Pure renewal-maintenance COLA net calculation, extracted verbatim from
 *              PartnerNetPricePosthook (Wave-2 decomposition of the 2,563-line posthook).
 *              Deterministic: reads QuoteLineItem fields only — no SOQL, no RCA context I/O,
 *              no shared state — so it is unit-testable without the pricing runtime.
 */
public with sharing class RenewalMaintenanceColaCalculator {

    /**
     * @description Renewal-maintenance commercial net = (Base − prior partner$ − prior disc$) × (1 + COLA%).
     *              Falls back to the prior year's stamped COLA net when the pre-COLA base is non-positive
     *              or Base_Price__c still holds the contributor perpetual base.
     */
    public static Decimal computeRenewalMaintenanceColaNet(QuoteLineItem qli) {
        if (qli == null || qli.Base_Price__c == null || qli.Base_Price__c <= 0) {
            return null;
        }

        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        Decimal priorDisc = resolveRenewalDiscretionaryDollars(qli);
        Decimal colaPercent = qli.COLA_Uplift_Percent__c != null ? qli.COLA_Uplift_Percent__c : 0;

        Decimal preColaNet = qli.Base_Price__c - priorPartner - priorDisc;
        if (preColaNet <= 0 || isContributorBaseOnMaintenanceLine(qli, preColaNet)) {
            return computeColaFromPriorNet(qli, colaPercent);
        }

        return (preColaNet * (1 + (colaPercent / 100))).setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * @description Year 2+ COLA applies to the prior year's commercial net (e.g. $3,060 + 3% = $3,151.80).
     *              Falls back when Base_Price__c still holds the contributor perpetual base ($20k).
     */
    public static Decimal computeColaFromPriorNet(QuoteLineItem qli, Decimal colaPercent) {
        if (qli == null) {
            return null;
        }
        if (qli.COLACalculatedPrice__c != null && qli.COLACalculatedPrice__c > 0) {
            return qli.COLACalculatedPrice__c.setScale(2, RoundingMode.HALF_UP);
        }
        return null;
    }

    public static Boolean isContributorBaseOnMaintenanceLine(QuoteLineItem qli, Decimal preColaNet) {
        if (qli == null || qli.Base_Price__c == null || preColaNet == null || preColaNet <= 0) {
            return false;
        }
        return qli.Base_Price__c >= 10000 && preColaNet < (qli.Base_Price__c * 0.5);
    }

    public static Decimal resolveRenewalDiscretionaryDollars(QuoteLineItem qli) {
        if (qli.Prior_Discretionary_Discount__c != null && qli.Prior_Discretionary_Discount__c > 0) {
            return qli.Prior_Discretionary_Discount__c;
        }
        if (qli.Discount == null || qli.Discount <= 0) {
            return 0;
        }

        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        return ((qli.Base_Price__c - priorPartner) * (qli.Discount / 100)).setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * @description Renewal partner discount % for a maintenance line: the stamped
     *              PartnerDiscountPercent when positive, else derived from the prior partner
     *              dollars over base price. Null when no base or no prior partner dollars.
     *              (Wave-2 decomposition, increment 16 — moved verbatim from the posthook.)
     */
    public static Decimal resolveRenewalPartnerPercent(QuoteLineItem qli) {
        if (qli.PartnerDiscountPercent != null && qli.PartnerDiscountPercent > 0) {
            return qli.PartnerDiscountPercent;
        }
        if (qli.Base_Price__c == null || qli.Base_Price__c <= 0) {
            return null;
        }
        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        if (priorPartner <= 0) {
            return null;
        }
        return ((priorPartner / qli.Base_Price__c) * 100).setScale(2, RoundingMode.HALF_UP);
    }
}
