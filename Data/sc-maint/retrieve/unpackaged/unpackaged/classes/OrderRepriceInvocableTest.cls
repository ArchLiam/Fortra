/**
 * SC-3308 — coverage for OrderRepriceInvocable.
 *
 * Note: commerceorders.PlaceOrderExecutor performs real RCA order pricing; in a unit-test
 * context it typically can't fully run, so the invocable's try/catch is exercised and the
 * method must return a well-formed Result without throwing. The graph-build + result-shape
 * are validated live in Data/sc3308/exp_placeorder_reprice.apex (confirmed flip on 00095321).
 */
@isTest
private class OrderRepriceInvocableTest {

    @isTest
    static void reprice_returnsResultPerRequest_andNeverThrows() {
        Account acc = new Account(Name = 'SC3308 Reprice Test');
        insert acc;

        Order ord = new Order(
            AccountId     = acc.Id,
            EffectiveDate = Date.today(),
            Status        = 'Draft',
            Pricebook2Id  = Test.getStandardPricebookId());
        insert ord;

        OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
        req.orderId = ord.Id;

        Test.startTest();
        List<OrderRepriceInvocable.Result> results =
            OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one Result per Request');
        System.assertNotEquals(null, results[0], 'Result must be returned, not null');
        // success may be true or false depending on whether pricing runs in test context;
        // the contract is only that the invocable returns cleanly without an unhandled exception.
    }

    @isTest
    static void reprice_seedsQuotePricingBeforeExecutor() {
        Account acc = new Account(Name = 'SC3308 Seed Test');
        insert acc;

        Product2 prod = new Product2(
            Name = 'SC3308 Seed Product',
            ProductCode = 'SC3308-SEED',
            IsActive = true
        );
        insert prod;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = prod.Id,
            UnitPrice = 355,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acc.Id,
            Name = 'SC3308 Seed Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'SC3308 Seed Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 301.75,
            PartnerUnitPrice = 301.75
        );
        insert qli;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPBId,
            QuoteId = q.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 355
        );
        insert oi;

        OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
        req.orderId = ord.Id;

        Test.startTest();
        OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req });
        Test.stopTest();

        OrderItem seeded = [
            SELECT PartnerUnitPrice, NetUnitPrice, UnitPrice
            FROM OrderItem
            WHERE Id = :oi.Id
        ];
        System.assertEquals(301.75, seeded.PartnerUnitPrice,
            'prepareForReprice should seed partner net from quote before PlaceOrderExecutor');
        System.assertEquals(301.75, seeded.UnitPrice);
    }

    @isTest
    static void isPricingReady_falseWhenOrderIdMissing() {
        System.assertEquals(false, OrderRepriceInvocable.isPricingReady(null, 364.23));
    }

    @isTest
    static void reprice_handlesMissingOrderGracefully() {
        // Defensive: a valid-format but non-existent (deleted) order id must not throw.
        Account acc = new Account(Name = 'SC3308 Reprice Test 2');
        insert acc;
        Order ord = new Order(
            AccountId     = acc.Id,
            EffectiveDate = Date.today(),
            Status        = 'Draft',
            Pricebook2Id  = Test.getStandardPricebookId());
        insert ord;
        Id deletedId = ord.Id;
        delete ord;

        OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
        req.orderId = deletedId;

        Test.startTest();
        List<OrderRepriceInvocable.Result> results =
            OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one Result per Request');
        System.assertEquals(false, results[0].success, 'unknown order cannot succeed');
    }
}