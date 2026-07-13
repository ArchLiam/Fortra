/**
 * @description Provides pure, deterministic partner-net and pre-procedure price resolution
 *              helpers with no SOQL or RCA context, so they are unit-testable without the
 *              pricing runtime.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class PartnerNetResolutionCalculator {

    /**
     * @description Resolves the commercial unit price as the procedure net when it is positive and
     *              below the partner unit price, otherwise the partner unit price.
     * @param procedureNet The net unit price produced by the pricing procedure.
     * @param partnerUnitPrice The partner unit price used as the fallback ceiling.
     * @return The scaled procedure net when it undercuts the partner price, else the partner unit price.
     */
    public static Decimal resolveCommercialUnitPrice(Decimal procedureNet, Decimal partnerUnitPrice) {
        if (procedureNet != null && procedureNet > 0 && procedureNet < partnerUnitPrice) {
            return procedureNet.setScale(2, RoundingMode.HALF_UP);
        }
        return partnerUnitPrice;
    }

    /**
     * @description Resolves the pre-procedure price using the precedence regional net, then unit
     *              price, then list price, selecting the first positive value.
     * @param regionalNetUnitPrice The regional net unit price, taking highest precedence when positive.
     * @param unitPrice The unit price, used when the regional net is absent or non-positive.
     * @param listPrice The list price, used as the final fallback.
     * @return The first positive price by precedence, or the list price fallback.
     */
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