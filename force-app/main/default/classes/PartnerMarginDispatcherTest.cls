@IsTest
private class PartnerMarginDispatcherTest {

    static final Id BILLING = '001000000000001AAA';
    static final Id RESELLER = '001000000000002AAA';

    @IsTest
    static void resolve_unknownModelReturnsNull() {
        System.assertEquals(null, PartnerMarginDispatcher.resolve(
            'Bogus Model', BILLING, 'New', null, null, null,
            new Map<Id, List<Partner_Pricing_Model__c>>(), new Map<Id, String>(),
            'U', 'SG', 'SC', 1000, 'Software'),
            'unknown model -> null (shell logs SKIP + returns)');
    }

    @IsTest
    static void resolve_discountNoModelLeavesPriceUnchanged() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'New', null, null, null,
            new Map<Id, List<Partner_Pricing_Model__c>>(), new Map<Id, String>{ BILLING => 'ACME' },
            'U', 'SG', 'SC', 1000, 'Software');
        System.assertNotEquals(null, r, 'Discount returns a result');
        System.assertEquals(1000, r.adjustedPrice, 'no matching model -> no discount');
        System.assertEquals(0, r.detailMaps.size(), 'no model -> no margin detail');
    }

    @IsTest
    static void resolve_guaranteedMarginNoModelsNoMargins() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'New', RESELLER, null, null,
            new Map<Id, List<Partner_Pricing_Model__c>>(), new Map<Id, String>(),
            'U', 'SG', 'SC', 1000, 'Software');
        System.assertNotEquals(null, r, 'GM returns a result');
        System.assertEquals(0, r.totalPercent, 'no models -> 0% total');
        System.assertEquals(0, r.detailMaps.size(), 'no models -> no margin details');
    }

    static final Id DISTRIB = '001000000000003AAA';
    static final Id REFERRAL = '001000000000004AAA';

    // Build a Discount/GM model whose solution fields are all blank so selectBestModelForLine
    // returns it via the final all-blank fallback when the selectors are passed null.
    private static Map<Id, List<Partner_Pricing_Model__c>> modelsFor(Id partnerId, Partner_Pricing_Model__c model) {
        return new Map<Id, List<Partner_Pricing_Model__c>>{ partnerId => new List<Partner_Pricing_Model__c>{ model } };
    }

    private static Map<String, Object> detailById(PartnerMarginDispatcher.Result r, Id partnerId) {
        Map<String, Object> match = null;
        for (Map<String, Object> d : r.detailMaps) {
            if (d.get('partnerId') == partnerId) {
                match = d;
            }
        }
        return match;
    }

    @IsTest
    static void resolve_discountMatchingModelAppliesPercentAndBuildsDetail() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'New', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(Software_Percent__c = 20)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'Software');
        System.assertEquals(800.00, r.adjustedPrice, '1000 less 20% discount = 800.00');
        System.assertEquals(20, r.totalPercent, 'total percent = the 20% discount');
        System.assertEquals(1, r.detailMaps.size(), 'one billing-partner detail');
        Map<String, Object> d = r.detailMaps[0];
        System.assertEquals(BILLING, d.get('partnerId'), 'detail partnerId');
        System.assertEquals('ACME', d.get('partnerName'), 'detail partnerName from names map');
        System.assertEquals('Billing Partner', d.get('partnerRole'), 'discount detail role');
        System.assertEquals(20, (Decimal) d.get('marginPercent'), 'detail marginPercent');
    }

    @IsTest
    static void resolve_discountModelPresentButZeroPercentNoDetail() {
        // Model exists but the productType maps to the switch's else -> 0% -> price unchanged, no detail.
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'New', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(Software_Percent__c = 20)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'Hardware');
        System.assertEquals(1000, r.adjustedPrice, 'unmapped productType -> 0% -> price unchanged');
        System.assertEquals(0, r.totalPercent, '0% total');
        System.assertEquals(0, r.detailMaps.size(), 'selectedModel != null but 0% -> no detail');
    }

    @IsTest
    static void resolve_discountNewMaintenanceProductTypeUsesMaintField() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'New', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(New_Maintenance_Percent__c = 25)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'New Maintenance');
        System.assertEquals(750.00, r.adjustedPrice, 'New Maintenance productType reads New_Maintenance_Percent__c = 25% -> 750.00');
        System.assertEquals(25, r.totalPercent, '25% New Maintenance band');
    }

    @IsTest
    static void resolve_discountFortraOriginatedUsesNonOrigPercent() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'Fortra Originated', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(Software_Percent__c = 20, Non_Orig_Software_Pct__c = 30)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'Software');
        System.assertEquals(700.00, r.adjustedPrice, 'Fortra Originated -> Non_Orig 30% -> 700.00');
        System.assertEquals(30, r.totalPercent, 'Non-originating 30% wins for Fortra Originated deal');
    }

    @IsTest
    static void resolve_guaranteedMarginAdditiveAcrossPartners() {
        Map<Id, List<Partner_Pricing_Model__c>> models = new Map<Id, List<Partner_Pricing_Model__c>>{
            BILLING => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 15) },
            RESELLER => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 10) }
        };
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'New', RESELLER, null, null,
            models, new Map<Id, String>{ BILLING => 'ACME', RESELLER => 'RES' },
            null, null, null, 1000, 'Software');
        System.assertEquals(750.00, r.adjustedPrice, 'additive 15%+10% = 25% -> 1000 x 0.75 = 750.00');
        System.assertEquals(25, r.totalPercent, 'total percent = 15 + 10');
        System.assertEquals(2, r.detailMaps.size(), 'one detail per participating partner');
        Map<String, Object> billingDetail = detailById(r, BILLING);
        Map<String, Object> resellerDetail = detailById(r, RESELLER);
        System.assertEquals('Billing Partner', billingDetail.get('partnerRole'), 'billing role');
        System.assertEquals(15, (Decimal) billingDetail.get('marginPercent'), 'billing margin 15');
        System.assertEquals('Reseller', resellerDetail.get('partnerRole'), 'reseller role resolved');
        System.assertEquals(10, (Decimal) resellerDetail.get('marginPercent'), 'reseller margin 10');
    }

    @IsTest
    static void resolve_guaranteedMarginExcludesZeroMarginPartner() {
        Map<Id, List<Partner_Pricing_Model__c>> models = new Map<Id, List<Partner_Pricing_Model__c>>{
            BILLING => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 15) },
            RESELLER => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 0) }
        };
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'New', RESELLER, null, null,
            models, new Map<Id, String>{ BILLING => 'ACME', RESELLER => 'RES' },
            null, null, null, 1000, 'Software');
        System.assertEquals(850.00, r.adjustedPrice, 'only billing 15% counts -> 1000 x 0.85 = 850.00');
        System.assertEquals(15, r.totalPercent, 'zero-margin reseller excluded from total');
        System.assertEquals(1, r.detailMaps.size(), 'zero-margin partner produces no detail');
        System.assertEquals(BILLING, r.detailMaps[0].get('partnerId'), 'the surviving detail is the billing partner');
    }

    @IsTest
    static void resolve_guaranteedMarginFortraOriginatedUsesNonOrig() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'Fortra Originated', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(Software_Percent__c = 20, Non_Orig_Software_Pct__c = 30)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'Software');
        System.assertEquals(700.00, r.adjustedPrice, 'GM Fortra Originated -> Non_Orig 30% -> 700.00');
        System.assertEquals(30, r.totalPercent, 'Non-originating 30% margin');
    }
}
