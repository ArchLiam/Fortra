@IsTest
private class PartnerNetResolutionCalculatorTest {

    @IsTest
    static void resolveCommercialUnitPrice_lowerOfProcedureNetOrPartner() {
        System.assertEquals(241.40, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(241.40, 301.75),
            'Procedure net lower than partner -> net');
        System.assertEquals(301.75, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(301.75, 301.75),
            'Equal -> partner');
        System.assertEquals(301.75, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(355, 301.75),
            'Net higher -> partner');
        System.assertEquals(62.48, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(71, 62.48),
            'Net higher -> partner');
        System.assertEquals(500, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(null, 500),
            'Null net -> partner');
        System.assertEquals(500, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(0, 500),
            'Non-positive net -> partner');
    }

    @IsTest
    static void resolvePreProcedurePrice_regionalThenUnitThenList() {
        System.assertEquals(900, PartnerNetResolutionCalculator.resolvePreProcedurePrice(900, 1000, 1100));
        System.assertEquals(1000, PartnerNetResolutionCalculator.resolvePreProcedurePrice(null, 1000, 1100));
        System.assertEquals(1100, PartnerNetResolutionCalculator.resolvePreProcedurePrice(null, null, 1100));
        System.assertEquals(1000, PartnerNetResolutionCalculator.resolvePreProcedurePrice(0, 1000, 1100),
            'Non-positive regional -> unit');
    }
}
