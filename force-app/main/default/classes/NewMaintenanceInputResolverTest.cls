/**
 * @description Unit tests for NewMaintenanceInputResolver, verifying the pure input-resolution helpers that
 *              derive tier rates, contributor nets, partner percentages, and software discounts for new maintenance pricing.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class NewMaintenanceInputResolverTest {

    /**
     * @description Verifies resolveTierRate returns the mapped positive rate for a known tier and null when the rate is zero,
     *              the tier is unknown, or the tier is blank.
     */
    @IsTest
    static void resolveTierRate_returnsPositiveRateOrNull() {
        Map<String, Decimal> rates = new Map<String, Decimal>{ 'Standard' => 0.20, 'Zeroed' => 0 };
        System.assertEquals(0.20, NewMaintenanceInputResolver.resolveTierRate('Standard', rates));
        System.assertEquals(null, NewMaintenanceInputResolver.resolveTierRate('Zeroed', rates), 'Zero rate -> null');
        System.assertEquals(null, NewMaintenanceInputResolver.resolveTierRate('Unknown', rates), 'Unknown tier -> null');
        System.assertEquals(null, NewMaintenanceInputResolver.resolveTierRate(null, rates), 'Blank tier -> null');
    }

    /**
     * @description Verifies resolveEffectiveTierRate returns the line tier's rate when it resolves, falls back to the
     *              default tier's rate when the line tier is blank or off-list, never overrides a resolved line tier,
     *              and returns null when the default tier is blank (fallback retired) or the default has no positive rate.
     */
    @IsTest
    static void resolveEffectiveTierRate_fallsBackToDefaultOnlyWhenNeeded() {
        Map<String, Decimal> rates = new Map<String, Decimal>{ 'Standard' => 0.20, 'Premier' => 0.30, 'Zeroed' => 0 };
        System.assertEquals(0.30, NewMaintenanceInputResolver.resolveEffectiveTierRate('Premier', rates, 'Standard'),
            'Resolved line tier wins over the default');
        System.assertEquals(0.20, NewMaintenanceInputResolver.resolveEffectiveTierRate(null, rates, 'Standard'),
            'Blank tier -> default tier rate');
        System.assertEquals(0.20, NewMaintenanceInputResolver.resolveEffectiveTierRate('Unknown', rates, 'Standard'),
            'Off-list tier -> default tier rate');
        System.assertEquals(null, NewMaintenanceInputResolver.resolveEffectiveTierRate(null, rates, null),
            'Blank default tier retires the fallback -> null');
        System.assertEquals(null, NewMaintenanceInputResolver.resolveEffectiveTierRate(null, rates, 'Zeroed'),
            'Default tier with non-positive rate -> null');
    }

    /**
     * @description Verifies isContributorNetFromPerpetual returns true only for a positive perpetual base and false for zero,
     *              negative, or null values.
     */
    @IsTest
    static void isContributorNetFromPerpetual_trueOnlyForPositive() {
        System.assertEquals(true, NewMaintenanceInputResolver.isContributorNetFromPerpetual(100));
        System.assertEquals(false, NewMaintenanceInputResolver.isContributorNetFromPerpetual(0));
        System.assertEquals(false, NewMaintenanceInputResolver.isContributorNetFromPerpetual(-5));
        System.assertEquals(false, NewMaintenanceInputResolver.isContributorNetFromPerpetual(null));
    }

    /**
     * @description Verifies resolveContributorNet prefers a positive perpetual base and otherwise falls back to the line base
     *              when the perpetual base is zero or null.
     */
    @IsTest
    static void resolveContributorNet_prefersPositivePerpetualBaseElseLineBase() {
        System.assertEquals(3000, NewMaintenanceInputResolver.resolveContributorNet(3000, 500));
        System.assertEquals(500, NewMaintenanceInputResolver.resolveContributorNet(0, 500));
        System.assertEquals(500, NewMaintenanceInputResolver.resolveContributorNet(null, 500));
    }

    /**
     * @description Verifies resolvePartnerPercent applies the precedence of band percent, then contributor percent, then line
     *              percent when higher-priority values are null.
     */
    @IsTest
    static void resolvePartnerPercent_bandThenContributorThenLine() {
        System.assertEquals(18, NewMaintenanceInputResolver.resolvePartnerPercent(18, 12, 5), 'Band wins');
        System.assertEquals(12, NewMaintenanceInputResolver.resolvePartnerPercent(null, 12, 5), 'Contributor when no band');
        System.assertEquals(5, NewMaintenanceInputResolver.resolvePartnerPercent(null, null, 5), 'Line when neither');
        // Order-line pattern: no contributor % -> band or line
        System.assertEquals(5, NewMaintenanceInputResolver.resolvePartnerPercent(null, null, 5));
    }

    /**
     * @description Verifies resolveSoftwareDiscount prefers the contributor discount and falls back to the line discount,
     *              returning null when both are null.
     */
    @IsTest
    static void resolveSoftwareDiscount_contributorElseLine() {
        System.assertEquals(7, NewMaintenanceInputResolver.resolveSoftwareDiscount(7, 3));
        System.assertEquals(3, NewMaintenanceInputResolver.resolveSoftwareDiscount(null, 3));
        System.assertEquals(null, NewMaintenanceInputResolver.resolveSoftwareDiscount(null, null));
    }
}