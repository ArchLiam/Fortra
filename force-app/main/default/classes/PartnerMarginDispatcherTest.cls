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
}
