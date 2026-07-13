/**
 * @description Unit tests for RenewalMaintenanceNetCalculator, verifying the pure first-renewal
 *              derived-maintenance net — (assetPrice − prior partner − prior discretionary) × (1 + COLA%).
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class RenewalMaintenanceNetCalculatorTest {

    /**
     * @description Verifies the first-renewal net subtracts the prior partner and discretionary dollars
     *              from the GROSS asset base then applies COLA — the client worked example
     *              ((200 - 20 - 40) x 1.03 = 144.20) and the live BoKS case ((71 - 10.65) x 1.0785 = 65.09).
     */
    @IsTest
    static void computeFirstRenewalNet_threeComponent() {
        System.assertEquals(144.20, RenewalMaintenanceNetCalculator.computeFirstRenewalNet(200, 20, 40, null, 3),
            'client worked example');
        System.assertEquals(65.09, RenewalMaintenanceNetCalculator.computeFirstRenewalNet(71, 10.65, 0, null, 7.85),
            'live BoKS first renewal');
        System.assertEquals(3645.33, RenewalMaintenanceNetCalculator.computeFirstRenewalNet(4000, 600, 20, 10, 7.85),
            'discretionary first renewal nets both $ discounts once (not the 660.04 the procedure produced)');
    }

    /**
     * @description Verifies the discretionary dollars are derived from the line percent discount only
     *              when no discretionary dollars are carried, netted off the partner-reduced base.
     */
    @IsTest
    static void computeFirstRenewalNet_discountFallback() {
        // partner 100; disc = (1000 - 100) x 10% = 90; net = 1000 - 100 - 90 = 810 ; x1.10 = 891.00
        System.assertEquals(891.00, RenewalMaintenanceNetCalculator.computeFirstRenewalNet(1000, 100, 0, 10, 10),
            'discount fallback net');
    }

    /**
     * @description Verifies a null asset price or a non-positive pre-COLA net yields null (no fabricated price).
     */
    @IsTest
    static void computeFirstRenewalNet_nullGuards() {
        System.assertEquals(null, RenewalMaintenanceNetCalculator.computeFirstRenewalNet(null, 10, 0, null, 5),
            'null asset price -> null');
        System.assertEquals(null, RenewalMaintenanceNetCalculator.computeFirstRenewalNet(100, 100, 0, null, 5),
            'non-positive pre-COLA net -> null');
    }
}
