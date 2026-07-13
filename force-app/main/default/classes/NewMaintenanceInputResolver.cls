/**
 * @description Resolves per-line New-Maintenance pricing inputs — contributor net,
 *              partner-percent precedence, software discount and tier-rate lookup — using
 *              deterministic, field-based logic with no SOQL or RCA context, so it is unit-testable.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class NewMaintenanceInputResolver {

    /**
     * @description Looks up the maintenance rate for the given tier, returning null unless a positive rate resolves.
     * @param tier Maintenance tier key to look up.
     * @param rateByType Map of maintenance tier to its rate.
     * @return The positive rate for the tier, or null when the tier is blank or the rate is missing/non-positive.
     */
    public static Decimal resolveTierRate(String tier, Map<String, Decimal> rateByType) {
        Decimal rate = String.isNotBlank(tier) ? rateByType.get(tier) : null;
        return (rate != null && rate > 0) ? rate : null;
    }

    /**
     * @description Resolves the effective maintenance rate for a line, falling back to a default tier's
     *              rate when the line carries no selectable tier — its product classification does not
     *              model a maintenance tier, so no tier attribute can ever be stamped or chosen. Passing
     *              a blank defaultTier disables the fallback and preserves the strict (null) behaviour.
     * @param tier Maintenance tier key selected on the line (may be blank/absent).
     * @param rateByType Map of maintenance tier to its rate.
     * @param defaultTier Default tier key applied when the line's own tier does not resolve to a rate;
     *                    blank disables the fallback.
     * @return The line tier's positive rate; else the default tier's positive rate; else null.
     */
    public static Decimal resolveEffectiveTierRate(
        String tier,
        Map<String, Decimal> rateByType,
        String defaultTier
    ) {
        Decimal rate = resolveTierRate(tier, rateByType);
        if (rate != null) {
            return rate;
        }
        return String.isNotBlank(defaultTier) ? resolveTierRate(defaultTier, rateByType) : null;
    }

    /**
     * @description Determines whether the contributor perpetual base should be used as the net (vs the line's own base).
     * @param contributorPricingBase Contributor perpetual base price.
     * @return True when the contributor perpetual base is a positive net.
     */
    public static Boolean isContributorNetFromPerpetual(Decimal contributorPricingBase) {
        return contributorPricingBase != null && contributorPricingBase > 0;
    }

    /**
     * @description Resolves the contributor net as the perpetual base when positive, else the line's own base price.
     * @param contributorPricingBase Contributor perpetual base price.
     * @param lineBasePrice The line's own base price used as fallback.
     * @return The contributor perpetual base when positive, otherwise the line base price.
     */
    public static Decimal resolveContributorNet(Decimal contributorPricingBase, Decimal lineBasePrice) {
        return isContributorNetFromPerpetual(contributorPricingBase) ? contributorPricingBase : lineBasePrice;
    }

    /**
     * @description Applies partner-percent precedence: New-Maintenance band > carried contributor partner % >
     *              the line's own partner %. (Order lines pass a null contributor % — band > line %.)
     * @param bandPercent New-Maintenance band partner percent (highest precedence).
     * @param contributorPartnerPercent Carried contributor partner percent.
     * @param linePartnerPercent The line's own partner percent (lowest precedence).
     * @return The first non-null partner percent in precedence order.
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

    /**
     * @description Resolves the software discount as the carried contributor software % when present, else the line's discount.
     * @param contributorSoftwarePercent Carried contributor software discount percent.
     * @param lineDiscount The line's own discount used as fallback.
     * @return The contributor software percent when non-null, otherwise the line discount.
     */
    public static Decimal resolveSoftwareDiscount(Decimal contributorSoftwarePercent, Decimal lineDiscount) {
        return contributorSoftwarePercent != null ? contributorSoftwarePercent : lineDiscount;
    }
}