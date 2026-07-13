/**
 * @description Unit tests for NewMaintenanceNetCalculator, verifying list-net and commercial-net
 *              computations, partner/software discount precedence, negative-input handling, and rounding.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class NewMaintenanceNetCalculatorTest {

    /**
     * @description Verifies expectedListNet multiplies contributor by rate, and returns null when
     *              either the rate or contributor is zero or null.
     */
    @IsTest
    static void expectedListNet_contributorTimesRate() {
        System.assertEquals(20.00, NewMaintenanceNetCalculator.expectedListNet(100, 0.20), 'contributor 100 x rate 0.20');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(100, 0), 'zero rate -> null');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(100, null), 'null rate -> null');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(0, 0.20), 'zero contributor -> null');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(null, 0.20), 'null contributor -> null');
    }

    /**
     * @description Verifies expectedCommercialNet applies the partner discount then the software
     *              discount in sequence, and passes list through when discounts are null or zero.
     */
    @IsTest
    static void expectedCommercialNet_partnerThenSoftware() {
        // partner 10% only
        System.assertEquals(900.00, NewMaintenanceNetCalculator.expectedCommercialNet(1000, 10, 0),
            'list 1000 less 10% partner = 900');
        // partner 10% then software 5%: 900 x 0.95 = 855
        System.assertEquals(855.00, NewMaintenanceNetCalculator.expectedCommercialNet(1000, 10, 5),
            'list 1000 less 10% then 5% = 855');
        // no discounts -> list passes through
        System.assertEquals(1000, NewMaintenanceNetCalculator.expectedCommercialNet(1000, null, null),
            'no discounts -> list net');
        System.assertEquals(1000, NewMaintenanceNetCalculator.expectedCommercialNet(1000, 0, 0),
            'zero discounts -> list net');
    }

    /**
     * @description Verifies computeNewBusinessNets precedence: a resolved partner band wins over the
     *              stamped percent, while stamped percents win when the band is not resolved, with
     *              carried inputs used as the fallback for null values.
     */
    @IsTest
    static void computeNewBusinessNets_j06Precedence() {
        // Band resolved wins over the stamped percent; software falls back to carried inputs.
        NewBusinessMaintenanceNets a = NewMaintenanceNetCalculator.computeNewBusinessNets(
            1000, true, 15, 5, 99, null);
        System.assertEquals(1000, a.expectedListNet, 'listNet passthrough');
        System.assertEquals(15, a.partnerPercent, 'resolved band wins over stamped 99');
        System.assertEquals(5, a.softwareDiscount, 'stamped null -> carried 5');
        System.assertEquals(807.50, a.expectedCommercialNet, '1000 less 15% then 5% = 807.50');

        // Band NOT resolved -> stamped percents win.
        NewBusinessMaintenanceNets b = NewMaintenanceNetCalculator.computeNewBusinessNets(
            1000, false, 15, 5, 20, 10);
        System.assertEquals(20, b.partnerPercent, 'stamped partner 20 wins');
        System.assertEquals(10, b.softwareDiscount, 'stamped software 10 wins');
        System.assertEquals(720.00, b.expectedCommercialNet, '1000 less 20% then 10% = 720.00');

        // Band NOT resolved, stamped null -> carried inputs.
        NewBusinessMaintenanceNets c = NewMaintenanceNetCalculator.computeNewBusinessNets(
            1000, false, 15, 5, null, null);
        System.assertEquals(15, c.partnerPercent, 'stamped null -> carried partner 15');
        System.assertEquals(5, c.softwareDiscount, 'stamped null -> carried software 5');
        System.assertEquals(807.50, c.expectedCommercialNet, '1000 less 15% then 5% = 807.50');
    }

    /**
     * @description Verifies expectedListNet returns null for negative rate or contributor and applies
     *              HALF_UP rounding to two decimal places.
     */
    @IsTest
    static void expectedListNet_negativeInputsAndRounding() {
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(100, -0.20), 'negative rate -> null');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(-100, 0.20), 'negative contributor -> null');
        // 100 x 0.12345 = 12.34500 -> HALF_UP to 2dp = 12.35
        System.assertEquals(12.35, NewMaintenanceNetCalculator.expectedListNet(100, 0.12345), 'HALF_UP rounds 12.345 up to 12.35');
    }

    /**
     * @description Verifies expectedCommercialNet passes list to the software leg when partner is null,
     *              treats negative percents as no discount, and rounds each discount leg independently.
     */
    @IsTest
    static void expectedCommercialNet_softwareOnlyNegativesAndTwoStepRounding() {
        // partner null -> list passes straight to the software leg: 1000 x 0.95 = 950.00
        System.assertEquals(950.00, NewMaintenanceNetCalculator.expectedCommercialNet(1000, null, 5),
            'null partner -> software-only 5% -> 950.00');
        // negative percents are treated like no discount
        System.assertEquals(1000, NewMaintenanceNetCalculator.expectedCommercialNet(1000, -10, -5),
            'negative discounts -> list passes through');
        // 999.99 x 0.9 = 899.991 -> 899.99 ; 899.99 x 0.95 = 854.9905 -> 854.99 (each leg rounds independently)
        System.assertEquals(854.99, NewMaintenanceNetCalculator.expectedCommercialNet(999.99, 10, 5),
            'two-step independent rounding = 854.99');
    }

    /**
     * @description Verifies computeNewBusinessNets skips the band branch and falls back to the stamped
     *              percent when the partner band is resolved but the partner input percent is null.
     */
    @IsTest
    static void computeNewBusinessNets_bandResolvedButNoInputsFallsToStamped() {
        // partnerBandResolved true but inputsPartnerPercent null -> the band branch is skipped -> stamped wins.
        NewBusinessMaintenanceNets n = NewMaintenanceNetCalculator.computeNewBusinessNets(
            1000, true, null, 5, 20, null);
        System.assertEquals(20, n.partnerPercent, 'band resolved but no input -> stamped 20');
        System.assertEquals(5, n.softwareDiscount, 'stamped software null -> carried 5');
        System.assertEquals(760.00, n.expectedCommercialNet, '1000 less 20% then 5% = 760.00');
    }

    /**
     * @description Verifies computeNewBusinessNets leaves the software discount null when no stamped or
     *              carried software value exists, applying the partner-only discount to the commercial net.
     */
    @IsTest
    static void computeNewBusinessNets_bandResolvedSoftwareNullLeavesNullSoftware() {
        NewBusinessMaintenanceNets n = NewMaintenanceNetCalculator.computeNewBusinessNets(
            1000, true, 15, null, null, null);
        System.assertEquals(15, n.partnerPercent, 'resolved band 15');
        System.assertEquals(null, n.softwareDiscount, 'no stamped or carried software -> null');
        System.assertEquals(850.00, n.expectedCommercialNet, 'partner-only 15% -> 850.00');
    }

    /**
     * @description Verifies computeNewBusinessNets passes the list net through unchanged when all
     *              partner and software discount inputs are zero.
     */
    @IsTest
    static void computeNewBusinessNets_allZeroDiscountsPassThrough() {
        NewBusinessMaintenanceNets n = NewMaintenanceNetCalculator.computeNewBusinessNets(
            1000, false, 0, 0, 0, 0);
        System.assertEquals(0, n.partnerPercent, 'all-zero partner -> 0');
        System.assertEquals(0, n.softwareDiscount, 'all-zero software -> 0');
        System.assertEquals(1000, n.expectedCommercialNet, 'zero discounts -> list net passthrough');
    }
}