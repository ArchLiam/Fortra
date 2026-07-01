@IsTest
private class OrderCommercialNetServiceTest {

    private static OrderItem buildOrderItem(Map<String, Object> fields) {
        return (OrderItem) JSON.deserialize(JSON.serialize(fields), OrderItem.class);
    }

    @IsTest
    static void resolveCommercialUnitPrice_prefersTotalPriceWhenDiscounted() {
        OrderItem oi = buildOrderItem(new Map<String, Object>{
            'Quantity' => 1,
            'TotalPrice' => 3060,
            'NetUnitPrice' => 4000,
            'UnitPrice' => 4000
        });

        System.assertEquals(
            3060,
            OrderCommercialNetService.resolveCommercialUnitPrice(oi),
            'Commercial unit should come from TotalPrice when line total differs from list net'
        );
    }

    @IsTest
    static void resolveCommercialUnitPrice_prefersTotalPriceWhenStaleNetIsLow() {
        OrderItem oi = buildOrderItem(new Map<String, Object>{
            'Quantity' => 1,
            'TotalPrice' => 15300,
            'NetUnitPrice' => 355,
            'UnitPrice' => 355
        });

        System.assertEquals(
            15300,
            OrderCommercialNetService.resolveCommercialUnitPrice(oi),
            'Commercial unit should come from TotalPrice when NetUnitPrice is stale'
        );
    }

    @IsTest
    static void resolveCommercialUnitPrice_usesNetWhenTotalsMatch() {
        OrderItem oi = buildOrderItem(new Map<String, Object>{
            'Quantity' => 1,
            'TotalPrice' => 4183,
            'NetUnitPrice' => 4183,
            'UnitPrice' => 4183
        });

        System.assertEquals(
            4183,
            OrderCommercialNetService.resolveCommercialUnitPrice(oi),
            'When commercial equals list net, keep NetUnitPrice'
        );
    }

    @IsTest
    static void patchOrderItemCommercialUnitPrices_updatesMismatchedLines() {
        Account account = new Account(Name = 'Commercial Net Account');
        insert account;

        Product2 product = new Product2(
            Name = 'Commercial Net Product',
            ProductCode = 'CNP-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true
        );
        insert product;

        Id pricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 20000,
            IsActive = true
        );

        Order orderRecord = new Order(
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = pricebookId
        );
        insert orderRecord;

        OrderItem line = new OrderItem(
            OrderId = orderRecord.Id,
            PricebookEntryId = [
                SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1
            ].Id,
            Quantity = 1,
            UnitPrice = 15300
        );
        insert line;
        update new OrderItem(Id = line.Id, NetUnitPrice = 355);

        Test.startTest();
        Integer patched = OrderCommercialNetService.patchOrderItemCommercialUnitPrices(orderRecord.Id);
        Test.stopTest();

        System.assertEquals(1, patched, 'One line should be patched');
        OrderItem updated = [
            SELECT NetUnitPrice, UnitPrice, TotalPrice
            FROM OrderItem
            WHERE Id = :line.Id
        ];
        System.assertEquals(15300, updated.NetUnitPrice);
        System.assertEquals(15300, updated.UnitPrice);
    }

    @IsTest
    static void finalizeForAssetization_noOpOnNull() {
        Test.startTest();
        System.assertEquals(0, OrderCommercialNetService.finalizeOrderForAssetization(null));
        OrderCommercialNetService.finalizeForAssetization(new List<OrderCommercialNetService.FlowInput>{
            new OrderCommercialNetService.FlowInput()
        });
        Test.stopTest();
    }
}