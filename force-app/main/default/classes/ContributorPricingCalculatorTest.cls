@IsTest
private class ContributorPricingCalculatorTest {

    private static QuoteLineItem qli(Map<String, Object> f) {
        return (QuoteLineItem) JSON.deserialize(JSON.serialize(f), QuoteLineItem.class);
    }
    private static OrderItem oi(Map<String, Object> f) {
        return (OrderItem) JSON.deserialize(JSON.serialize(f), OrderItem.class);
    }

    @IsTest
    static void partnerPercent_prefersStampedThenComputesFromPriorDollars() {
        System.assertEquals(15, ContributorPricingCalculator.resolveContributorPartnerPercent(
            qli(new Map<String, Object>{ 'PartnerDiscountPercent' => 15 }), 1000));
        System.assertEquals(12, ContributorPricingCalculator.resolveContributorPartnerPercent(
            qli(new Map<String, Object>{ 'Partner_Discount_Percent__c' => 12 }), 1000));
        // Prior partner $100 / base 1000 => 10.00%
        System.assertEquals(10.00, ContributorPricingCalculator.resolveContributorPartnerPercent(
            qli(new Map<String, Object>{ 'Prior_Partner_Discount__c' => 100 }), 1000));
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorPartnerPercent(
            qli(new Map<String, Object>{}), 1000));
    }

    @IsTest
    static void softwarePercent_prefersDiscountThenComputesFromPriorDisc() {
        System.assertEquals(8, ContributorPricingCalculator.resolveContributorSoftwarePercent(
            qli(new Map<String, Object>{ 'Discount' => 8 }), 1000, 0));
        // preManualNet = 1000 * (1 - 10%) = 900 ; 50/900*100 = 5.56
        System.assertEquals(5.56, ContributorPricingCalculator.resolveContributorSoftwarePercent(
            qli(new Map<String, Object>{ 'Prior_Discretionary_Discount__c' => 50 }), 1000, 10));
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorSoftwarePercent(
            qli(new Map<String, Object>{}), 1000, 0));
    }

    @IsTest
    static void pricingBase_qli_prefersPrePartnerThenBaseThenNetOverListThenListThenUnit() {
        System.assertEquals(2000, ContributorPricingCalculator.resolveContributorPricingBase(
            qli(new Map<String, Object>{ 'Pre_Partner_Price__c' => 2000, 'Base_Price__c' => 1500 })));
        System.assertEquals(1500, ContributorPricingCalculator.resolveContributorPricingBase(
            qli(new Map<String, Object>{ 'Base_Price__c' => 1500 })));
        // Net (3000) > List (2000) => use Net
        System.assertEquals(3000, ContributorPricingCalculator.resolveContributorPricingBase(
            qli(new Map<String, Object>{ 'NetUnitPrice' => 3000, 'ListPrice' => 2000 })));
        // Net (1000) not > List (2000) => fall through to List
        System.assertEquals(2000, ContributorPricingCalculator.resolveContributorPricingBase(
            qli(new Map<String, Object>{ 'NetUnitPrice' => 1000, 'ListPrice' => 2000 })));
        System.assertEquals(500, ContributorPricingCalculator.resolveContributorPricingBase(
            qli(new Map<String, Object>{ 'UnitPrice' => 500 })));
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorPricingBase((QuoteLineItem) null));
    }

    @IsTest
    static void pricingBase_orderItem_prefersNetThenBaseThenListThenUnit() {
        System.assertEquals(3000, ContributorPricingCalculator.resolveContributorPricingBase(
            oi(new Map<String, Object>{ 'NetUnitPrice' => 3000, 'Base_Price__c' => 1500 })));
        System.assertEquals(1500, ContributorPricingCalculator.resolveContributorPricingBase(
            oi(new Map<String, Object>{ 'Base_Price__c' => 1500 })));
        System.assertEquals(2000, ContributorPricingCalculator.resolveContributorPricingBase(
            oi(new Map<String, Object>{ 'ListPrice' => 2000 })));
        System.assertEquals(500, ContributorPricingCalculator.resolveContributorPricingBase(
            oi(new Map<String, Object>{ 'UnitPrice' => 500 })));
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorPricingBase((OrderItem) null));
    }

    @IsTest
    static void partnerPercent_priorRequiresPositiveBaseAndRounds() {
        // Prior-dollar path needs a positive pricing base, else null.
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorPartnerPercent(
            qli(new Map<String, Object>{ 'Prior_Partner_Discount__c' => 100 }), null),
            'prior partner $ with null base -> null');
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorPartnerPercent(
            qli(new Map<String, Object>{ 'Prior_Partner_Discount__c' => 100 }), 0),
            'prior partner $ with zero base -> null');
        // 50 / 300 * 100 = 16.6667 -> HALF_UP 16.67
        System.assertEquals(16.67, ContributorPricingCalculator.resolveContributorPartnerPercent(
            qli(new Map<String, Object>{ 'Prior_Partner_Discount__c' => 50 }), 300),
            'prior $ / base -> HALF_UP rounded percent');
        // Zero stamped PartnerDiscountPercent falls through to Partner_Discount_Percent__c.
        System.assertEquals(12, ContributorPricingCalculator.resolveContributorPartnerPercent(
            qli(new Map<String, Object>{ 'PartnerDiscountPercent' => 0, 'Partner_Discount_Percent__c' => 12 }), 1000),
            'zero stamped percent -> falls through to custom field 12');
    }

    @IsTest
    static void softwarePercent_nullPartnerAndZeroBaseGuards() {
        // partnerPercent null -> preManualNet == pricingBase (no partner reduction): 50 / 1000 * 100 = 5.00
        System.assertEquals(5.00, ContributorPricingCalculator.resolveContributorSoftwarePercent(
            qli(new Map<String, Object>{ 'Prior_Discretionary_Discount__c' => 50 }), 1000, null),
            'null partner -> preManualNet is the base -> 5.00');
        // Zero base -> preManualNet 0 -> guarded -> null
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorSoftwarePercent(
            qli(new Map<String, Object>{ 'Prior_Discretionary_Discount__c' => 50 }), 0, null),
            'zero base -> preManualNet 0 -> null');
        // Zero stamped Discount with no prior discretionary -> null
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorSoftwarePercent(
            qli(new Map<String, Object>{ 'Discount' => 0 }), 1000, 0),
            'zero Discount and no prior -> null');
    }

    @IsTest
    static void pricingBase_qli_netAloneWithoutListIsIgnored() {
        // QLI only takes Net when Net > List; a Net with no List (and nothing else) yields null.
        System.assertEquals(null, ContributorPricingCalculator.resolveContributorPricingBase(
            qli(new Map<String, Object>{ 'NetUnitPrice' => 3000 })),
            'QLI Net without List -> null (Net>List guard not satisfiable)');
        // Zero Base_Price__c falls through to ListPrice.
        System.assertEquals(1200, ContributorPricingCalculator.resolveContributorPricingBase(
            qli(new Map<String, Object>{ 'Base_Price__c' => 0, 'ListPrice' => 1200 })),
            'zero Base_Price__c -> falls through to List 1200');
    }

    @IsTest
    static void pricingBase_orderItem_netWinsUnconditionallyUnlikeQli() {
        // OrderItem takes Net whenever positive, even below List (contrast with the QLI Net>List rule).
        System.assertEquals(1000, ContributorPricingCalculator.resolveContributorPricingBase(
            oi(new Map<String, Object>{ 'NetUnitPrice' => 1000, 'ListPrice' => 2000 })),
            'OrderItem Net wins even when below List');
        // Zero Net falls through to Base.
        System.assertEquals(1500, ContributorPricingCalculator.resolveContributorPricingBase(
            oi(new Map<String, Object>{ 'NetUnitPrice' => 0, 'Base_Price__c' => 1500 })),
            'zero Net -> falls through to Base 1500');
    }
}
