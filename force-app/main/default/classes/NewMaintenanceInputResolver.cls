/**
 * @description Pure New-Maintenance line input-resolution logic, extracted from
 *              PartnerNetPricePosthook.loadNewMaintenanceLines (Wave-2 decomposition, increment 5).
 *              The loader keeps its SOQL; this holds the per-line fallback precedence (contributor
 *              net, partner %, software discount) + tier-rate lookup. Field-based, deterministic —
 *              no SOQL, no RCA context, no inner-class coupling — so it is unit-testable.
 */
public with sharing class NewMaintenanceInputResolver {

    /** @description Maintenance tier -> rate; null unless a positive rate resolves. */
    public static Decimal resolveTierRate(String tier, Map<String, Decimal> rateByType) {
        Decimal rate = String.isNotBlank(tier) ? rateByType.get(tier) : null;
        return (rate != null && rate > 0) ? rate : null;
    }

    /** @description True when the contributor perpetual base is a positive net (vs the line's own base). */
    public static Boolean isContributorNetFromPerpetual(Decimal contributorPricingBase) {
        return contributorPricingBase != null && contributorPricingBase > 0;
    }

    /** @description Contributor net = the perpetual base when positive, else the line's own base price. */
    public static Decimal resolveContributorNet(Decimal contributorPricingBase, Decimal lineBasePrice) {
        return isContributorNetFromPerpetual(contributorPricingBase) ? contributorPricingBase : lineBasePrice;
    }

    /**
     * @description Partner % precedence: New-Maintenance band > carried contributor partner % >
     *              the line's own partner %. (Order lines pass a null contributor % — band > line %.)
     */
    public static Decimal resolvePartnerPercent(
        Decimal bandPercent,
        Decimal contributorPartnerPercent,
        Decimal linePartnerPercent
    ) {
        if (bandPercent != null) {
            return bandPercent;
        }
        if (contributorPartnerPercent != null) {
            return contributorPartnerPercent;
        }
        return linePartnerPercent;
    }

    /** @description Software discount % = carried contributor software % when present, else the line's discount. */
    public static Decimal resolveSoftwareDiscount(Decimal contributorSoftwarePercent, Decimal lineDiscount) {
        return contributorSoftwarePercent != null ? contributorSoftwarePercent : lineDiscount;
    }
}
