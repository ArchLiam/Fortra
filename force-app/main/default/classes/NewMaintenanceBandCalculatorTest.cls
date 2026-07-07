@IsTest
private class NewMaintenanceBandCalculatorTest {

    private static final Id PARTNER_A = '001000000000001AAA';
    private static final Id PARTNER_B = '001000000000002AAA';
    private static final Id QUOTE_1 = '0Q0000000000001AAA';
    private static final Id ORDER_1 = '801000000000001AAA';

    private static Map<Id, Partner_Pricing_Model__c> modelsWithBand() {
        return new Map<Id, Partner_Pricing_Model__c>{
            PARTNER_A => new Partner_Pricing_Model__c(New_Maintenance_Percent__c = 20)
        };
    }

    @IsTest
    static void newMaintenanceBand_returnsDiscountModelPercent() {
        System.assertEquals(20, NewMaintenanceBandCalculator.newMaintenanceBand('Discount', PARTNER_A, modelsWithBand()),
            'Discount model New_Maintenance_Percent__c should be the band');
    }

    @IsTest
    static void newMaintenanceBand_nullGuards() {
        Map<Id, Partner_Pricing_Model__c> models = modelsWithBand();
        System.assertEquals(null, NewMaintenanceBandCalculator.newMaintenanceBand('Guaranteed Margin', PARTNER_A, models),
            'Non-Discount pricing model -> null');
        System.assertEquals(null, NewMaintenanceBandCalculator.newMaintenanceBand('Discount', null, models),
            'Null billing partner -> null');
        System.assertEquals(null, NewMaintenanceBandCalculator.newMaintenanceBand('Discount', PARTNER_A, null),
            'Null models -> null');
        System.assertEquals(null, NewMaintenanceBandCalculator.newMaintenanceBand('Discount', PARTNER_B, models),
            'Billing partner not in models -> null');
    }

    @IsTest
    static void billingPartnerIdsFromQuotes_collectsDiscountModelPartners() {
        Map<Id, Quote> quotes = new Map<Id, Quote>{
            QUOTE_1 => new Quote(Id = QUOTE_1, Partner_Pricing_Model__c = 'Discount', Billing_Partner__c = PARTNER_A),
            '0Q0000000000002AAA' => new Quote(Id = '0Q0000000000002AAA', Partner_Pricing_Model__c = 'Guaranteed Margin', Billing_Partner__c = PARTNER_B)
        };
        Set<Id> ids = NewMaintenanceBandCalculator.billingPartnerIdsFromQuotes(quotes);
        System.assertEquals(new Set<Id>{ PARTNER_A }, ids, 'Only Discount-model quotes contribute a billing partner');
        System.assertEquals(new Set<Id>(), NewMaintenanceBandCalculator.billingPartnerIdsFromQuotes(null));
    }

    @IsTest
    static void billingPartnerIdsFromOrders_collectsViaSourceQuote() {
        Order ord = (Order) JSON.deserialize(
            '{"Id":"' + ORDER_1 + '","Quote":{"Partner_Pricing_Model__c":"Discount","Billing_Partner__c":"' + PARTNER_A + '"}}',
            Order.class);
        Order ordNoQuote = new Order(Id = '801000000000002AAA');
        Map<Id, Order> orders = new Map<Id, Order>{ ORDER_1 => ord, ordNoQuote.Id => ordNoQuote };
        Set<Id> ids = NewMaintenanceBandCalculator.billingPartnerIdsFromOrders(orders);
        System.assertEquals(new Set<Id>{ PARTNER_A }, ids);
        System.assertEquals(new Set<Id>(), NewMaintenanceBandCalculator.billingPartnerIdsFromOrders(null));
    }

    @IsTest
    static void bandByQuote_mapsBandPerQuote() {
        Map<Id, Quote> quotes = new Map<Id, Quote>{
            QUOTE_1 => new Quote(Id = QUOTE_1, Partner_Pricing_Model__c = 'Discount', Billing_Partner__c = PARTNER_A)
        };
        Map<Id, Decimal> bands = NewMaintenanceBandCalculator.bandByQuote(quotes, modelsWithBand());
        System.assertEquals(20, bands.get(QUOTE_1));
    }

    @IsTest
    static void bandByOrder_mapsBandPerOrderViaQuote() {
        Order ord = (Order) JSON.deserialize(
            '{"Id":"' + ORDER_1 + '","Quote":{"Partner_Pricing_Model__c":"Discount","Billing_Partner__c":"' + PARTNER_A + '"}}',
            Order.class);
        Map<Id, Order> orders = new Map<Id, Order>{ ORDER_1 => ord };
        Map<Id, Decimal> bands = NewMaintenanceBandCalculator.bandByOrder(orders, modelsWithBand());
        System.assertEquals(20, bands.get(ORDER_1));
    }
}
