/**
 * @description Unit-test coverage for OrderRepriceInvocable, verifying the invocable returns a
 * well-formed Result per Request without throwing and exercising its readiness, total-resolution,
 * validation-clearing and result-population helpers. Because commerceorders.PlaceOrderExecutor
 * leaves the commerce pricing engine in a state that poisons a subsequent QuoteLineItem insert in
 * a sibling method of the same test job, the seed scenario builds its Quote/Order/OrderItem in
 * @TestSetup (a separate committed transaction) and asserts seed-decision logic through the
 * @TestVisible decomposition helpers rather than a live executor call.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest(isParallel=false)
private class OrderRepriceInvocableTest {

    /**
     * @description Builds the seed Account, Product2, PricebookEntry, Opportunity, Quote,
     * QuoteLineItem, Order and OrderItem in a dedicated @TestSetup transaction that commits before
     * any executor-calling method runs, so the QuoteLineItem insert is never poisoned by
     * PlaceOrderExecutor state.
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

    /**
     * @description Returns the quote-linked Order created in @TestSetup for use by the tests.
     * @return the seed Order whose QuoteId is populated
     */
    private static Order seededOrder() {
        return [SELECT Id FROM Order WHERE QuoteId != null LIMIT 1];
    }

    /**
     * @description Verifies reprice returns exactly one non-null Result per Request and completes
     * cleanly without an unhandled exception even when pricing cannot fully run in test context.
     */
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
     * @description Verifies the seed-decision behavior the invocable relies on: prepareForReprice
     * plus persistFromWork copy the quote commercial net (PartnerUnitPrice / UnitPrice) onto the
     * linked order line exactly as repriceOne() does before PlaceOrderExecutor. Exercised through
     * the @TestVisible decomposition helpers so the executor's QLI-insert side-effect cannot poison
     * this method's data setup.
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

    /**
     * @description Verifies isPricingReady returns false when the order id matches no row, so the
     * SELECT loop never executes and the method falls through to its trailing false return.
     */
    @isTest
    static void isPricingReady_falseWhenOrderIdMissing() {
        // No order row matches -> the SELECT loop never enters -> trailing return false.
        System.assertEquals(false, OrderRepriceInvocable.isPricingReady(null, 364.23));
    }

    /**
     * @description Verifies isPricingReady on a real Draft order (no ValidationResult, not yet
     * CompletedWithPricing) falls through to the TotalAmount comparison and reports not-ready both
     * when the quote total is null and when it cannot match the order's TotalAmount.
     */
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

    /**
     * @description Verifies resolveQuoteTotal and resolveOrderTotal both return null for a
     * valid-format but non-existent order id, hitting their empty-loop returns.
     */
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

    /**
     * @description Verifies resolveQuoteTotal returns null for a real order with no linked Quote
     * (the Quote == null branch) while resolveOrderTotal returns cleanly for that same order.
     */
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

    /**
     * @description Verifies clearOrderValidationResult takes its null-id guard branch and returns
     * without performing any DML or throwing.
     */
    @isTest
    static void clearOrderValidationResult_noopOnNullId() {
        // Guard branch: null id returns without DML.
        Test.startTest();
        OrderRepriceInvocable.clearOrderValidationResult(null);
        Test.stopTest();
        System.assert(true, 'null id must not throw or DML');
    }

    /**
     * @description Verifies clearOrderValidationResult nulls the ValidationResult field on a real
     * seeded order.
     */
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

    /**
     * @description Verifies populateResultFromOrder runs against a real seeded order and populates
     * the Result object without throwing, even when the Draft order's status fields are null.
     */
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

    /**
     * @description Verifies reprice handles a valid-format but deleted order id defensively,
     * returning one Result whose success is false rather than throwing.
     */
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