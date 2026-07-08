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

    /**
     * @description Assemble the New-Business derived-maintenance nets from an already-computed
     *              list net plus the J-06 partner% precedence (resolved band > stamped > carried)
     *              and the software-discount fallback (stamped > carried), then the commercial net.
     *              Extracted from PartnerNetPricePosthook.computeNewBusinessMaintenanceNets (Wave-2
     *              decomposition, build*Update step 5). The two guards (maintInputs==null and
     *              expectedListNet==null) stay in the posthook shell, which also performs the
     *              stamped-percent tag reads and passes them in as primitives — so this method is
     *              pure over primitives. `expectedListNet` is always non-null here (shell-guarded).
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
