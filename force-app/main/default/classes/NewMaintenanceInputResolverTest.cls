@IsTest
private class NewMaintenanceInputResolverTest {

    @IsTest
    static void resolveTierRate_returnsPositiveRateOrNull() {
        Map<String, Decimal> rates = new Map<String, Decimal>{ 'Standard' => 0.20, 'Zeroed' => 0 };
        System.assertEquals(0.20, NewMaintenanceInputResolver.resolveTierRate('Standard', rates));
        System.assertEquals(null, NewMaintenanceInputResolver.resolveTierRate('Zeroed', rates), 'Zero rate -> null');
        System.assertEquals(null, NewMaintenanceInputResolver.resolveTierRate('Unknown', rates), 'Unknown tier -> null');
        System.assertEquals(null, NewMaintenanceInputResolver.resolveTierRate(null, rates), 'Blank tier -> null');
    }

    @IsTest
    static void isContributorNetFromPerpetual_trueOnlyForPositive() {
        System.assertEquals(true, NewMaintenanceInputResolver.isContributorNetFromPerpetual(100));
        System.assertEquals(false, NewMaintenanceInputResolver.isContributorNetFromPerpetual(0));
        System.assertEquals(false, NewMaintenanceInputResolver.isContributorNetFromPerpetual(-5));
        System.assertEquals(false, NewMaintenanceInputResolver.isContributorNetFromPerpetual(null));
    }

    @IsTest
    static void resolveContributorNet_prefersPositivePerpetualBaseElseLineBase() {
        System.assertEquals(3000, NewMaintenanceInputResolver.resolveContributorNet(3000, 500));
        System.assertEquals(500, NewMaintenanceInputResolver.resolveContributorNet(0, 500));
        System.assertEquals(500, NewMaintenanceInputResolver.resolveContributorNet(null, 500));
    }

    @IsTest
    static void resolvePartnerPercent_bandThenContributorThenLine() {
        System.assertEquals(18, NewMaintenanceInputResolver.resolvePartnerPercent(18, 12, 5), 'Band wins');
        System.assertEquals(12, NewMaintenanceInputResolver.resolvePartnerPercent(null, 12, 5), 'Contributor when no band');
        System.assertEquals(5, NewMaintenanceInputResolver.resolvePartnerPercent(null, null, 5), 'Line when neither');
        // Order-line pattern: no contributor % -> band or line
        System.assertEquals(5, NewMaintenanceInputResolver.resolvePartnerPercent(null, null, 5));
    }

    @IsTest
    static void resolveSoftwareDiscount_contributorElseLine() {
        System.assertEquals(7, NewMaintenanceInputResolver.resolveSoftwareDiscount(7, 3));
        System.assertEquals(3, NewMaintenanceInputResolver.resolveSoftwareDiscount(null, 3));
        System.assertEquals(null, NewMaintenanceInputResolver.resolveSoftwareDiscount(null, null));
    }
}
