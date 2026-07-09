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

    @IsTest
    static void newMaintenanceBand_zeroOrNegativePercentIsNull() {
        Map<Id, Partner_Pricing_Model__c> zeroBand = new Map<Id, Partner_Pricing_Model__c>{
            PARTNER_A => new Partner_Pricing_Model__c(New_Maintenance_Percent__c = 0)
        };
        System.assertEquals(null, NewMaintenanceBandCalculator.newMaintenanceBand('Discount', PARTNER_A, zeroBand),
            'zero New_Maintenance_Percent__c -> null (caller falls back)');
        Map<Id, Partner_Pricing_Model__c> negBand = new Map<Id, Partner_Pricing_Model__c>{
            PARTNER_A => new Partner_Pricing_Model__c(New_Maintenance_Percent__c = -5)
        };
        System.assertEquals(null, NewMaintenanceBandCalculator.newMaintenanceBand('Discount', PARTNER_A, negBand),
            'negative New_Maintenance_Percent__c -> null');
    }

    @IsTest
    static void billingPartnerIdsFromQuotes_excludesNullPartnerCollectsMultiple() {
        Map<Id, Quote> quotes = new Map<Id, Quote>{
            QUOTE_1 => new Quote(Id = QUOTE_1, Partner_Pricing_Model__c = 'Discount', Billing_Partner__c = PARTNER_A),
            '0Q0000000000002AAA' => new Quote(Id = '0Q0000000000002AAA', Partner_Pricing_Model__c = 'Discount', Billing_Partner__c = null),
            '0Q0000000000003AAA' => new Quote(Id = '0Q0000000000003AAA', Partner_Pricing_Model__c = 'Discount', Billing_Partner__c = PARTNER_B)
        };
        System.assertEquals(new Set<Id>{ PARTNER_A, PARTNER_B },
            NewMaintenanceBandCalculator.billingPartnerIdsFromQuotes(quotes),
            'Discount quotes with a billing partner collected; null-partner Discount quote excluded');
        System.assertEquals(new Set<Id>(),
            NewMaintenanceBandCalculator.billingPartnerIdsFromQuotes(new Map<Id, Quote>()),
            'empty quotes map -> empty set');
    }

    @IsTest
    static void billingPartnerIdsFromOrders_excludesNonDiscountAndNullPartner() {
        Order discountA = (Order) JSON.deserialize(
            '{"Id":"' + ORDER_1 + '","Quote":{"Partner_Pricing_Model__c":"Discount","Billing_Partner__c":"' + PARTNER_A + '"}}',
            Order.class);
        Order nonDiscountB = (Order) JSON.deserialize(
            '{"Id":"801000000000003AAA","Quote":{"Partner_Pricing_Model__c":"Guaranteed Margin","Billing_Partner__c":"' + PARTNER_B + '"}}',
            Order.class);
        Order discountNullPartner = (Order) JSON.deserialize(
            '{"Id":"801000000000004AAA","Quote":{"Partner_Pricing_Model__c":"Discount"}}',
            Order.class);
        Map<Id, Order> orders = new Map<Id, Order>{
            discountA.Id => discountA, nonDiscountB.Id => nonDiscountB, discountNullPartner.Id => discountNullPartner
        };
        System.assertEquals(new Set<Id>{ PARTNER_A },
            NewMaintenanceBandCalculator.billingPartnerIdsFromOrders(orders),
            'only the Discount order with a billing partner contributes');
    }

    @IsTest
    static void bandByQuote_skipsNonResolvingQuotes() {
        Map<Id, Quote> quotes = new Map<Id, Quote>{
            QUOTE_1 => new Quote(Id = QUOTE_1, Partner_Pricing_Model__c = 'Discount', Billing_Partner__c = PARTNER_A),
            '0Q0000000000002AAA' => new Quote(Id = '0Q0000000000002AAA', Partner_Pricing_Model__c = 'Guaranteed Margin', Billing_Partner__c = PARTNER_A)
        };
        Map<Id, Decimal> bands = NewMaintenanceBandCalculator.bandByQuote(quotes, modelsWithBand());
        System.assertEquals(1, bands.size(), 'only the Discount quote resolves a band');
        System.assertEquals(20, bands.get(QUOTE_1), 'Discount quote band');
        System.assertEquals(null, bands.get('0Q0000000000002AAA'), 'GM quote absent from band map');
        System.assertEquals(new Map<Id, Decimal>(), NewMaintenanceBandCalculator.bandByQuote(null, modelsWithBand()),
            'null quotes -> empty band map');
    }

    @IsTest
    static void bandByOrder_skipsNullQuoteAndNonDiscount() {
        Order discountA = (Order) JSON.deserialize(
            '{"Id":"' + ORDER_1 + '","Quote":{"Partner_Pricing_Model__c":"Discount","Billing_Partner__c":"' + PARTNER_A + '"}}',
            Order.class);
        Order nullQuote = new Order(Id = '801000000000005AAA');
        Order gmOrder = (Order) JSON.deserialize(
            '{"Id":"801000000000006AAA","Quote":{"Partner_Pricing_Model__c":"Guaranteed Margin","Billing_Partner__c":"' + PARTNER_A + '"}}',
            Order.class);
        Map<Id, Order> orders = new Map<Id, Order>{
            discountA.Id => discountA, nullQuote.Id => nullQuote, gmOrder.Id => gmOrder
        };
        Map<Id, Decimal> bands = NewMaintenanceBandCalculator.bandByOrder(orders, modelsWithBand());
        System.assertEquals(1, bands.size(), 'only the Discount order with a source quote resolves');
        System.assertEquals(20, bands.get(ORDER_1), 'Discount order band');
        System.assertEquals(new Map<Id, Decimal>(), NewMaintenanceBandCalculator.bandByOrder(null, modelsWithBand()),
            'null orders -> empty band map');
    }
}
