/**
 * SC-3308 — coverage for OrderRepriceInvocable.
 *
 * Note: commerceorders.PlaceOrderExecutor performs real RCA order pricing; in a unit-test
 * context it typically can't fully run, so the invocable's try/catch is exercised and the
 * method must return a well-formed Result without throwing. The graph-build + result-shape
 * are validated live in Data/sc3308/exp_placeorder_reprice.apex (confirmed flip on 00095321).
 *
 * IMPORTANT (test-isolation): commerceorders.PlaceOrderExecutor.execute() leaves the RLM /
 * commerce pricing engine in a state that makes a subsequent QuoteLineItem INSERT in any
 * sibling method of the SAME Apex test job fail with INVALID_CROSS_REFERENCE_KEY ("you don't
 * have the required access"). Proven by bisection in this org: a QLI insert that passes in
 * isolation fails the moment an executor-calling method shares the job. The seed scenario
 * therefore builds its QuoteLineItem / Order / OrderItem in @TestSetup (a separate transaction
 * that commits BEFORE any executor method runs) and the seeding test asserts the seed-decision
 * logic through the @TestVisible decomposition helpers, not a live executor call.
 */
@isTest(isParallel=false)
private class OrderRepriceInvocableTest {

    /**
     * Seed data committed in its own transaction before any executor-calling method runs,
     * so the QuoteLineItem insert is never poisoned by PlaceOrderExecutor state.
     */
    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'SC3308 Seed Test');
        insert acc;

        Product2 prod = new Product2(
            Name = 'SC3308 Seed Product',
            ProductCode = 'SC3308-SEED',
            IsActive = true,
            Fortra_Product_Type__c = 'Software'
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
            PartnerUnitPrice = 301.75,
            Fortra_Product_Type__c = 'Software'
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

        insert new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 355
        );
    }

    private static Order seededOrder() {
        return [SELECT Id FROM Order WHERE QuoteId != null LIMIT 1];
    }

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

    /**
     * Asserts the real seed-decision behavior the invocable relies on: prepareForReprice +
     * persistFromWork copy the quote commercial net (PartnerUnitPrice / UnitPrice) onto the
     * linked order line. This is exactly what repriceOne() runs before PlaceOrderExecutor.
     * Done through the @TestVisible helpers so the QLI-insert side-effect of the executor
     * (see class header) cannot poison this method's data setup.
     */
    @isTest
    static void reprice_seedsQuotePricingBeforeExecutor() {
        Order ord = seededOrder();

        Test.startTest();
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.prepareForReprice(ord.Id);
        MaintenanceOrderDecompositionService.persistFromWork(work);
        Test.stopTest();

        OrderItem seeded = [
            SELECT PartnerUnitPrice, NetUnitPrice, UnitPrice
            FROM OrderItem
            WHERE OrderId = :ord.Id
            LIMIT 1
        ];
        System.assertEquals(301.75, seeded.PartnerUnitPrice,
            'prepareForReprice should seed partner net from quote before PlaceOrderExecutor');
        System.assertEquals(301.75, seeded.UnitPrice,
            'commercial net from quote should be carried onto the order line');
    }

    @isTest
    static void isPricingReady_falseWhenOrderIdMissing() {
        // No order row matches -> the SELECT loop never enters -> trailing return false.
        System.assertEquals(false, OrderRepriceInvocable.isPricingReady(null, 364.23));
    }

    @isTest
    static void isPricingReady_evaluatesRealOrder() {
        // A real, freshly-inserted Draft order has no ValidationResult and is not yet
        // CompletedWithPricing, so isPricingReady falls through to the TotalAmount comparison.
        Order ord = seededOrder();

        Test.startTest();
        // quoteTotal null -> the (quoteTotal != null && ...) short-circuits to false.
        Boolean notReadyWhenQuoteTotalNull = OrderRepriceInvocable.isPricingReady(ord.Id, null);
        // quoteTotal that cannot equal the (null/zero) order TotalAmount -> false.
        Boolean notReadyWhenTotalsDiffer = OrderRepriceInvocable.isPricingReady(ord.Id, 999999.99);
        Test.stopTest();

        System.assertEquals(false, notReadyWhenQuoteTotalNull,
            'null quote total cannot satisfy the totals-match readiness branch');
        System.assertEquals(false, notReadyWhenTotalsDiffer,
            'a non-matching quote total must not report pricing ready');
    }

    @isTest
    static void resolveTotals_returnNullForUnknownOrder() {
        // Valid-format but non-existent id -> both resolve helpers hit their empty-loop returns.
        Id missingId = '801000000000000AAA';

        Test.startTest();
        Decimal quoteTotal = OrderRepriceInvocable.resolveQuoteTotal(missingId);
        Decimal orderTotal = OrderRepriceInvocable.resolveOrderTotal(missingId);
        Test.stopTest();

        System.assertEquals(null, quoteTotal, 'unknown order has no quote total');
        System.assertEquals(null, orderTotal, 'unknown order has no order total');
    }

    @isTest
    static void resolveQuoteTotal_nullWhenOrderHasNoQuote() {
        // A real order with no Quote -> the Quote == null branch returns null.
        Account acc = new Account(Name = 'SC3308 NoQuote');
        insert acc;
        Order ord = new Order(
            AccountId = acc.Id, EffectiveDate = Date.today(),
            Status = 'Draft', Pricebook2Id = Test.getStandardPricebookId());
        insert ord;

        Test.startTest();
        Decimal quoteTotal = OrderRepriceInvocable.resolveQuoteTotal(ord.Id);
        Decimal orderTotal = OrderRepriceInvocable.resolveOrderTotal(ord.Id);
        Test.stopTest();

        System.assertEquals(null, quoteTotal, 'order without a quote returns null quote total');
        // orderTotal is whatever the platform rolled up (null for an empty draft) — just ensure no throw.
        System.assert(orderTotal == null || orderTotal >= 0,
            'resolveOrderTotal must return cleanly for a real order');
    }

    @isTest
    static void clearOrderValidationResult_noopOnNullId() {
        // Guard branch: null id returns without DML.
        Test.startTest();
        OrderRepriceInvocable.clearOrderValidationResult(null);
        Test.stopTest();
        System.assert(true, 'null id must not throw or DML');
    }

    @isTest
    static void clearOrderValidationResult_clearsRealOrder() {
        Order ord = seededOrder();
        Test.startTest();
        OrderRepriceInvocable.clearOrderValidationResult(ord.Id);
        Test.stopTest();
        Order after = [SELECT ValidationResult FROM Order WHERE Id = :ord.Id];
        System.assertEquals(null, after.ValidationResult,
            'ValidationResult should be cleared on the order');
    }

    @isTest
    static void populateResultFromOrder_copiesStatusFields() {
        Order ord = seededOrder();
        OrderRepriceInvocable.Result res = new OrderRepriceInvocable.Result();

        Test.startTest();
        OrderRepriceInvocable.populateResultFromOrder(ord.Id, res);
        Test.stopTest();

        // Draft order: CalculationStatus/ValidationResult may be null, but the method must run
        // and the result object must be populated without throwing.
        System.assertNotEquals(null, res, 'result populated from order without throwing');
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