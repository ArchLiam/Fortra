/**
 * @description Pure partner-net / pre-procedure price resolution helpers, extracted verbatim from
 *              PartnerNetPricePosthook (Wave-2 decomposition, increment 6). Deterministic — no SOQL,
 *              no RCA context — so unit-testable without the pricing runtime.
 */
public with sharing class PartnerNetResolutionCalculator {

    /** @description Commercial unit = the procedure net when it is positive and below the partner unit price, else the partner unit price. */
    public static Decimal resolveCommercialUnitPrice(Decimal procedureNet, Decimal partnerUnitPrice) {
        if (procedureNet != null && procedureNet > 0 && procedureNet < partnerUnitPrice) {
            return procedureNet.setScale(2, RoundingMode.HALF_UP);
        }
        return partnerUnitPrice;
    }

    /** @description Pre-procedure price precedence: regional net > unit price > list price. */
    public static Decimal resolvePreProcedurePrice(Decimal regionalNetUnitPrice, Decimal unitPrice, Decimal listPrice) {
        if (regionalNetUnitPrice != null && regionalNetUnitPrice > 0) {
            return regionalNetUnitPrice;
        }
        if (unitPrice != null && unitPrice > 0) {
            return unitPrice;
        }
        return listPrice;
    }
}
