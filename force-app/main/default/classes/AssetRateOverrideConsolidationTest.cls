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

    /**
     * D-16: the bulk invocable must query all orders in ONE SOQL regardless of order count.
     * Uses already-aligned (no-discount, net==list) lines so the SELECT runs but produces no
     * patch — measuring the query budget with zero DML/flow noise. Pre-fix (per-order loop)
     * this would be 3 SOQL for 3 orders.
     */
    @IsTest
    static void prepareForAssetization_bulkOrdersUseSingleQuery() {
        Account account = new Account(Name = 'Bulk Override Query Account');
        insert account;

        Product2 product = new Product2(
            Name = 'Bulk Override Query Product',
            ProductCode = 'BOQ-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true
        );
        insert product;

        Id pricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true
        );
        Id pbeId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1].Id;

        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < 3; i++) {
            orders.add(new Order(
                AccountId = account.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = pricebookId
            ));
        }
        insert orders;

        List<OrderItem> lines = new List<OrderItem>();
        for (Order o : orders) {
            lines.add(new OrderItem(
                OrderId = o.Id,
                PricebookEntryId = pbeId,
                Quantity = 1,
                UnitPrice = 100
            ));
        }
        insert lines;
        List<OrderItem> aligned = new List<OrderItem>();
        for (OrderItem l : lines) {
            aligned.add(new OrderItem(Id = l.Id, NetUnitPrice = 100));
        }
        update aligned;

        List<AssetRateOverrideConsolidationService.FlowInput> inputs =
            new List<AssetRateOverrideConsolidationService.FlowInput>();
        for (Order o : orders) {
            AssetRateOverrideConsolidationService.FlowInput fi =
                new AssetRateOverrideConsolidationService.FlowInput();
            fi.orderId = o.Id;
            inputs.add(fi);
        }

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        AssetRateOverrideConsolidationService.prepareForAssetization(inputs);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assertEquals(1, soqlUsed,
            'Bulk assetization must query all orders in ONE SOQL regardless of order count; got ' + soqlUsed);
    }

    /**
     * D-16: bulkified invocable still aligns every order's discounted line to commercial net
     * across a multi-order (N>1) invocation — the record-triggered activation batch case.
     */
    @IsTest
    static void prepareForAssetization_bulkOrdersAllPatched() {
        Account account = new Account(Name = 'Bulk Override Patch Account');
        insert account;

        Product2 product = new Product2(
            Name = 'Bulk Override Patch Product',
            ProductCode = 'BOP-' + String.valueOf(Crypto.getRandomInteger()),
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
        Id pbeId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1].Id;

        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < 3; i++) {
            orders.add(new Order(
                AccountId = account.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = pricebookId
            ));
        }
        insert orders;

        List<OrderItem> lines = new List<OrderItem>();
        for (Order o : orders) {
            lines.add(new OrderItem(
                OrderId = o.Id,
                PricebookEntryId = pbeId,
                Quantity = 1,
                UnitPrice = 319.50
            ));
        }
        insert lines;
        List<OrderItem> discounted = new List<OrderItem>();
        for (OrderItem l : lines) {
            discounted.add(new OrderItem(
                Id = l.Id,
                NetUnitPrice = 450,
                PartnerDiscountPercent = 15,
                Discount = 10
            ));
        }
        update discounted;

        List<AssetRateOverrideConsolidationService.FlowInput> inputs =
            new List<AssetRateOverrideConsolidationService.FlowInput>();
        for (Order o : orders) {
            AssetRateOverrideConsolidationService.FlowInput fi =
                new AssetRateOverrideConsolidationService.FlowInput();
            fi.orderId = o.Id;
            inputs.add(fi);
        }

        Test.startTest();
        AssetRateOverrideConsolidationService.prepareForAssetization(inputs);
        Test.stopTest();

        for (OrderItem updated : [SELECT NetUnitPrice, UnitPrice FROM OrderItem WHERE Id IN :lines]) {
            System.assertEquals(319.50, updated.NetUnitPrice, 'Each order line aligns to commercial net');
            System.assertEquals(319.50, updated.UnitPrice, 'Each order line aligns to commercial net');
        }
    }
}