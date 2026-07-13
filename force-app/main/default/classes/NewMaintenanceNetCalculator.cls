/**
 * @description Pure New-Business derived-maintenance net arithmetic with no SOQL, DML, or context,
 *              making it unit-testable. List net = contributor net x maintenance rate; commercial
 *              net = list net less the partner percent then the software-discount percent.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class NewMaintenanceNetCalculator {

    /**
     * @description Computes the expected list net as contributor net price times the maintenance rate.
     * @param contributorNetPrice Net price of the contributing license line the maintenance derives from
     * @param rate Maintenance rate applied to the contributor net price
     * @return List net rounded to two decimals, or null when either input is null or non-positive
     */
    public static Decimal expectedListNet(Decimal contributorNetPrice, Decimal rate) {
        if (rate == null || rate <= 0 || contributorNetPrice == null || contributorNetPrice <= 0) {
            return null;
        }
        return (contributorNetPrice * rate).setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * @description Applies the partner discount then the software discount to the list net to
     *              produce the commercial net; each discount is skipped when null or non-positive.
     * @param listNet List net the discounts are applied to
     * @param partnerPercent Partner discount percentage
     * @param softwareDiscount Software discount percentage
     * @return Commercial net after both discounts, rounded to two decimals
     */
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

    /**
     * @description Assembles the New-Business derived-maintenance nets from an already-computed list
     *              net, resolving the partner percent by precedence (resolved band, then stamped,
     *              then carried) and the software discount by fallback (stamped, then carried),
     *              then computing the commercial net.
     * @param expectedListNet Pre-computed list net for the maintenance line
     * @param partnerBandResolved Whether an authoritative partner band was resolved for this line
     * @param inputsPartnerPercent Partner percent carried on the line inputs
     * @param inputsSoftwareDiscount Software discount carried on the line inputs
     * @param stampedPartnerPercent Partner percent stamped on the line
     * @param stampedManualPercent Manual software discount percent stamped on the line
     * @return Populated nets holding the list net, resolved percentages, and the commercial net
     */
    public static NewBusinessMaintenanceNets computeNewBusinessNets(
        Decimal expectedListNet,
        Boolean partnerBandResolved,
        Decimal inputsPartnerPercent,
        Decimal inputsSoftwareDiscount,
        Decimal stampedPartnerPercent,
        Decimal stampedManualPercent
    ) {
        NewBusinessMaintenanceNets nets = new NewBusinessMaintenanceNets();
        nets.expectedListNet = expectedListNet;

        if (partnerBandResolved && inputsPartnerPercent != null && inputsPartnerPercent > 0) {
            // J-06: the authoritative New-Maintenance band from the partner Discount model overrides
            // the license band the prehook stamped onto this derived-maintenance line.
            nets.partnerPercent = inputsPartnerPercent;
        } else {
            nets.partnerPercent = stampedPartnerPercent;
            if (nets.partnerPercent == null || nets.partnerPercent <= 0) {
                nets.partnerPercent = inputsPartnerPercent;
            }
        }
        nets.softwareDiscount = stampedManualPercent;
        if (nets.softwareDiscount == null || nets.softwareDiscount <= 0) {
            nets.softwareDiscount = inputsSoftwareDiscount;
        }

        nets.expectedCommercialNet = expectedCommercialNet(
            nets.expectedListNet, nets.partnerPercent, nets.softwareDiscount
        );
        return nets;
    }
}