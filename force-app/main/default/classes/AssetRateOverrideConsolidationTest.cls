@IsTest
private class AssetRateOverrideConsolidationTest {

    private static OrderItem buildOrderItem(Map<String, Object> fields) {
        return (OrderItem) JSON.deserialize(JSON.serialize(fields), OrderItem.class);
    }

    @IsTest
    static void hasPartnerOrManualDiscount_detectsPartnerPercent() {
        OrderItem oi = buildOrderItem(new Map<String, Object>{
            'PartnerDiscountPercent' => 15,
            'Discount' => 0
        });
        System.assert(AssetRateOverrideConsolidationService.hasPartnerOrManualDiscount(oi));
    }

    @IsTest
    static void hasPartnerOrManualDiscount_falseWhenNoDiscounts() {
        OrderItem oi = buildOrderItem(new Map<String, Object>{
            'PartnerDiscountPercent' => 0,
            'Discount' => null,
            'Manual_Discount__c' => null
        });
        System.assertEquals(false, AssetRateOverrideConsolidationService.hasPartnerOrManualDiscount(oi));
    }

    @IsTest
    static void resolveCommercialUnit_usesTotalPriceWhenDiscounted() {
        OrderItem oi = buildOrderItem(new Map<String, Object>{
            'Quantity' => 1,
            'TotalPrice' => 319.50,
            'NetUnitPrice' => 450,
            'UnitPrice' => 450,
            'PartnerDiscountPercent' => 15,
            'Discount' => 10
        });

        System.assertEquals(
            319.50,
            AssetRateOverrideConsolidationService.resolveCommercialUnitForAssetization(oi)
        );
    }

    @IsTest
    static void resolveCommercialUnit_keepsListNetWhenNoDiscounts() {
        OrderItem oi = buildOrderItem(new Map<String, Object>{
            'Quantity' => 1,
            'TotalPrice' => 4183,
            'NetUnitPrice' => 4183,
            'UnitPrice' => 4183,
            'PartnerDiscountPercent' => 0,
            'Discount' => 0
        });

        System.assertEquals(
            4183,
            AssetRateOverrideConsolidationService.resolveCommercialUnitForAssetization(oi)
        );
    }

    @IsTest
    static void patchOrderLines_updatesDiscountedLineOnly() {
        Account account = new Account(Name = 'Override Consolidation Account');
        insert account;

        Product2 product = new Product2(
            Name = 'Override Product',
            ProductCode = 'ORC-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true
        );
        insert product;

        Id pricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 450,
            IsActive = true
        );

        Order orderRecord = new Order(
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = pricebookId
        );
        insert orderRecord;

        Id pbeId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1].Id;

        OrderItem discountedLine = new OrderItem(
            OrderId = orderRecord.Id,
            PricebookEntryId = pbeId,
            Quantity = 1,
            UnitPrice = 319.50
        );
        insert discountedLine;
        update new OrderItem(
            Id = discountedLine.Id,
            NetUnitPrice = 450,
            PartnerDiscountPercent = 15,
            Discount = 10
        );

        Test.startTest();
        Integer patched = AssetRateOverrideConsolidationService.prepareOrderForAssetization(orderRecord.Id);
        AssetRateOverrideConsolidationService.prepareForAssetization(new List<AssetRateOverrideConsolidationService.FlowInput>{
            new AssetRateOverrideConsolidationService.FlowInput()
        });
        Test.stopTest();

        System.assertEquals(1, patched);
        OrderItem updated = [
            SELECT NetUnitPrice, UnitPrice
            FROM OrderItem
            WHERE Id = :discountedLine.Id
        ];
        System.assertEquals(319.50, updated.NetUnitPrice);
        System.assertEquals(319.50, updated.UnitPrice);
    }
}