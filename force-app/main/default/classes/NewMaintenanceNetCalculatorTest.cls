@IsTest
private class NewMaintenanceNetCalculatorTest {

    @IsTest
    static void expectedListNet_contributorTimesRate() {
        System.assertEquals(20.00, NewMaintenanceNetCalculator.expectedListNet(100, 0.20), 'contributor 100 x rate 0.20');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(100, 0), 'zero rate -> null');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(100, null), 'null rate -> null');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(0, 0.20), 'zero contributor -> null');
        System.assertEquals(null, NewMaintenanceNetCalculator.expectedListNet(null, 0.20), 'null contributor -> null');
    }

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
}
