/**
 * @description Pure New-Business derived-maintenance net arithmetic, extracted from
 *              PartnerNetPricePosthook.computeNewBusinessMaintenanceNets (Wave-2 decomposition,
 *              increment 15). list net = contributor net x maintenance rate; commercial net = list
 *              net less partner % then software discount %. No SOQL/DML/context — unit-testable.
 *              This is the J-06 / SC-3346 derived-maintenance net formula.
 */
public with sharing class NewMaintenanceNetCalculator {

    /** @description Expected list net = contributor net x maintenance rate (null if either invalid). */
    public static Decimal expectedListNet(Decimal contributorNetPrice, Decimal rate) {
        if (rate == null || rate <= 0 || contributorNetPrice == null || contributorNetPrice <= 0) {
            return null;
        }
        return (contributorNetPrice * rate).setScale(2, RoundingMode.HALF_UP);
    }

    /** @description Commercial net = list net x (1 - partner%/100) x (1 - software%/100). */
    public static Decimal expectedCommercialNet(Decimal listNet, Decimal partnerPercent, Decimal softwareDiscount) {
        Decimal partnerUnitPrice = listNet;
        if (partnerPercent != null && partnerPercent > 0) {
            partnerUnitPrice = (listNet * (1 - (partnerPercent / 100))).setScale(2, RoundingMode.HALF_UP);
        }
        Decimal commercialNet = partnerUnitPrice;
        if (softwareDiscount != null && softwareDiscount > 0) {
            commercialNet = (partnerUnitPrice * (1 - (softwareDiscount / 100))).setScale(2, RoundingMode.HALF_UP);
        }
        return commercialNet;
    }
}
