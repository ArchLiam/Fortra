@IsTest
private class RenewalMaintenanceColaCalculatorTest {

    private static QuoteLineItem qli(Map<String, Object> fields) {
        return (QuoteLineItem) JSON.deserialize(JSON.serialize(fields), QuoteLineItem.class);
    }

    @IsTest
    static void computeNet_appliesColaToBaseMinusPriorDiscounts() {
        // (Base 3400 - priorPartner 200 - priorDisc 100) = 3100 ; x1.03 = 3193.00
        QuoteLineItem q = qli(new Map<String, Object>{
            'Base_Price__c' => 3400,
            'Prior_Partner_Discount__c' => 200,
            'Prior_Discretionary_Discount__c' => 100,
            'COLA_Uplift_Percent__c' => 3
        });
        System.assertEquals(3193.00, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(q));
    }

    @IsTest
    static void computeNet_zeroColaLeavesPreColaNet() {
        QuoteLineItem q = qli(new Map<String, Object>{ 'Base_Price__c' => 1000, 'COLA_Uplift_Percent__c' => 0 });
        System.assertEquals(1000.00, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(q));
    }

    @IsTest
    static void computeNet_nullOrNonPositiveBaseReturnsNull() {
        System.assertEquals(null, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(null));
        System.assertEquals(null, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(
            qli(new Map<String, Object>{ 'Base_Price__c' => 0 })));
    }

    @IsTest
    static void computeNet_contributorBaseFallsBackToStampedColaPrice() {
        // Base 20000 (>=10000) and preColaNet (5000) < 50% of base => contributor base => use COLACalculatedPrice.
        QuoteLineItem q = qli(new Map<String, Object>{
            'Base_Price__c' => 20000,
            'Prior_Partner_Discount__c' => 15000,
            'COLA_Uplift_Percent__c' => 3,
            'COLACalculatedPrice__c' => 3151.80
        });
        System.assertEquals(3151.80, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(q));
    }

    @IsTest
    static void computeColaFromPriorNet_prefersStampedPrice() {
        System.assertEquals(3151.80, RenewalMaintenanceColaCalculator.computeColaFromPriorNet(
            qli(new Map<String, Object>{ 'COLACalculatedPrice__c' => 3151.80 }), 3));
        System.assertEquals(null, RenewalMaintenanceColaCalculator.computeColaFromPriorNet(
            qli(new Map<String, Object>{ 'COLACalculatedPrice__c' => 0 }), 3));
        System.assertEquals(null, RenewalMaintenanceColaCalculator.computeColaFromPriorNet(null, 3));
    }

    @IsTest
    static void isContributorBase_trueOnlyForLargeBaseWithLowPreColaNet() {
        QuoteLineItem big = qli(new Map<String, Object>{ 'Base_Price__c' => 20000 });
        System.assertEquals(true, RenewalMaintenanceColaCalculator.isContributorBaseOnMaintenanceLine(big, 5000));
        System.assertEquals(false, RenewalMaintenanceColaCalculator.isContributorBaseOnMaintenanceLine(big, 15000));
        QuoteLineItem small = qli(new Map<String, Object>{ 'Base_Price__c' => 5000 });
        System.assertEquals(false, RenewalMaintenanceColaCalculator.isContributorBaseOnMaintenanceLine(small, 1000));
        System.assertEquals(false, RenewalMaintenanceColaCalculator.isContributorBaseOnMaintenanceLine(big, 0));
    }

    @IsTest
    static void resolveDiscretionary_prefersPriorThenComputesFromDiscount() {
        // prior discretionary present -> use it verbatim
        System.assertEquals(18, RenewalMaintenanceColaCalculator.resolveRenewalDiscretionaryDollars(
            qli(new Map<String, Object>{ 'Prior_Discretionary_Discount__c' => 18 })));
        // no prior, Discount 10% of (Base 1000 - priorPartner 500) = 50.00
        System.assertEquals(50.00, RenewalMaintenanceColaCalculator.resolveRenewalDiscretionaryDollars(
            qli(new Map<String, Object>{ 'Base_Price__c' => 1000, 'Prior_Partner_Discount__c' => 500, 'Discount' => 10 })));
        // no prior, no discount -> 0
        System.assertEquals(0, RenewalMaintenanceColaCalculator.resolveRenewalDiscretionaryDollars(
            qli(new Map<String, Object>{ 'Base_Price__c' => 1000 })));
    }

    @IsTest
    static void resolveRenewalPartnerPercent_stampedElseDerivedFromPrior() {
        // stamped PartnerDiscountPercent > 0 wins
        System.assertEquals(18, RenewalMaintenanceColaCalculator.resolveRenewalPartnerPercent(
            qli(new Map<String, Object>{ 'PartnerDiscountPercent' => 18 })));
        // derive from prior partner $ / base: 250/1000*100 = 25.00
        System.assertEquals(25.00, RenewalMaintenanceColaCalculator.resolveRenewalPartnerPercent(
            qli(new Map<String, Object>{ 'Base_Price__c' => 1000, 'Prior_Partner_Discount__c' => 250 })));
        // no base -> null
        System.assertEquals(null, RenewalMaintenanceColaCalculator.resolveRenewalPartnerPercent(
            qli(new Map<String, Object>{ 'Prior_Partner_Discount__c' => 250 })));
        // base but no prior partner -> null
        System.assertEquals(null, RenewalMaintenanceColaCalculator.resolveRenewalPartnerPercent(
            qli(new Map<String, Object>{ 'Base_Price__c' => 1000 })));
    }
}
