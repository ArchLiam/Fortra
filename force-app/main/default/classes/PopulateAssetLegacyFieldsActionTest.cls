@IsTest
public class PopulateAssetLegacyFieldsActionTest {

    @IsTest
    static void testEmptyInput() {
        List<PopulateAssetLegacyFieldsAction.FlowInput> inputs =
            new List<PopulateAssetLegacyFieldsAction.FlowInput>();

        Test.startTest();
        PopulateAssetLegacyFieldsAction.populateFields(inputs);
        Test.stopTest();
        // Should complete without error - empty list hits early return
    }

    @IsTest
    static void testNullOrderId() {
        PopulateAssetLegacyFieldsAction.FlowInput input =
            new PopulateAssetLegacyFieldsAction.FlowInput();
        input.orderId = null;

        Test.startTest();
        PopulateAssetLegacyFieldsAction.populateFields(
            new List<PopulateAssetLegacyFieldsAction.FlowInput>{ input }
        );
        Test.stopTest();
        // Should complete without error - null filtered out, hits early return
    }

    @IsTest
    static void testOrderWithNoItems() {
        Account acc = new Account(Name = 'Test PopulateAssetLegacy Account');
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft'
        );
        insert ord;

        PopulateAssetLegacyFieldsAction.FlowInput input =
            new PopulateAssetLegacyFieldsAction.FlowInput();
        input.orderId = ord.Id;

        Test.startTest();
        PopulateAssetLegacyFieldsAction.populateFields(
            new List<PopulateAssetLegacyFieldsAction.FlowInput>{ input }
        );
        Test.stopTest();
        // Should complete without error - no OrderItems, hits early return
    }

    @IsTest
    static void testOrderWithItemsNoAssetActionSource() {
        Account acc = new Account(Name = 'Test PopulateAssetLegacy Account');
        insert acc;

        Product2 prod = new Product2(Name = 'Test Product', IsActive = true, QuantityUnitOfMeasure = 'Each');
        insert prod;

        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPbId
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 5,
            UnitPrice = 100
        );
        insert oi;

        PopulateAssetLegacyFieldsAction.FlowInput input =
            new PopulateAssetLegacyFieldsAction.FlowInput();
        input.orderId = ord.Id;

        Test.startTest();
        PopulateAssetLegacyFieldsAction.populateFields(
            new List<PopulateAssetLegacyFieldsAction.FlowInput>{ input }
        );
        Test.stopTest();
        // Should complete without error - OrderItems found but no AssetActionSource
        // records exist (they are system-managed by createOrUpdateAssetFromOrder)
    }

    // =====================================================================
    // Strategy B Tests: Call buildAssetUpdates() directly with mock data.
    // AssetAction/AssetActionSource are system-managed objects that cannot
    // be DML-inserted in test context. These tests exercise the core
    // update-building logic without requiring platform-managed records.
    // =====================================================================

    @IsTest
    static void testBuildAssetUpdates_FullUpdate() {
        Account acc = new Account(Name = 'Test Build Updates Full');
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(acc, dml);

        Product2 prod = new Product2(Name = 'Test LCM Product', IsActive = true, QuantityUnitOfMeasure = 'Each');
        insert prod;

        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId, Product2Id = prod.Id, UnitPrice = 5000, IsActive = true
        );
        insert pbe;

        Hardware__c hw = new Hardware__c(
            Account__c = acc.Id,
            Serial_Number__c = 'BUILD-TEST-SN-' + String.valueOf(Crypto.getRandomLong()).right(8)
        );
        insert hw;

        Order ord = new Order(
            AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft',
            Pricebook2Id = stdPbId, Legacy_Id__c = 'LEGACY-001'
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 3,
            UnitPrice = 5000, Hardware__c = hw.Id
        );
        insert oi;

        Asset ast = new Asset(Name = 'Test Asset', AccountId = acc.Id, Product2Id = prod.Id);
        insert ast;

        // Build mock AssetActionSource data (no DML needed)
        AssetActionSource mockAas = new AssetActionSource(
            ReferenceEntityItemId = oi.Id,
            Quantity = 3,
            TotalLineAmount = 15000
        );
        Map<Id, AssetActionSource> assetToSource = new Map<Id, AssetActionSource>{
            ast.Id => mockAas
        };
        Map<Id, OrderItem> orderItemMap = new Map<Id, OrderItem>([
            SELECT Id, Hardware__c, OrderId FROM OrderItem WHERE Id = :oi.Id
        ]);
        Map<Id, Order> orderMap = new Map<Id, Order>([
            SELECT Id, Legacy_Id__c FROM Order WHERE Id = :ord.Id
        ]);

        Test.startTest();
        List<Asset> result = PopulateAssetLegacyFieldsAction.buildAssetUpdates(
            assetToSource, orderItemMap, orderMap
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should produce 1 Asset update');
        Asset updated = result[0];
        System.assertEquals(ast.Id, updated.Id, 'Asset Id should match');
        System.assertEquals('Installed', updated.Status, 'Status should be Installed');
        System.assertEquals(3, updated.Quantity, 'Quantity should be 3');
        System.assertEquals(15000, updated.Price, 'Price should be 15000');
        System.assertEquals(hw.Id, updated.Hardware__c, 'Hardware should map from OrderItem');
        System.assertEquals('LEGACY-001', updated.Legacy_Id__c, 'Legacy_Id should map from Order');
    }

    @IsTest
    static void testBuildAssetUpdates_NoHardwareNoLegacy() {
        Account acc = new Account(Name = 'Test No HW Legacy');
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(acc, dml);

        Product2 prod = new Product2(Name = 'Test Product NL', IsActive = true, QuantityUnitOfMeasure = 'Each');
        insert prod;

        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId, Product2Id = prod.Id, UnitPrice = 2000, IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft',
            Pricebook2Id = stdPbId
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 2000
        );
        insert oi;

        Asset ast = new Asset(Name = 'Test Asset NL', AccountId = acc.Id, Product2Id = prod.Id);
        insert ast;

        AssetActionSource mockAas = new AssetActionSource(
            ReferenceEntityItemId = oi.Id, Quantity = 1, TotalLineAmount = 2000
        );
        Map<Id, AssetActionSource> assetToSource = new Map<Id, AssetActionSource>{ ast.Id => mockAas };
        Map<Id, OrderItem> orderItemMap = new Map<Id, OrderItem>([
            SELECT Id, Hardware__c, OrderId FROM OrderItem WHERE Id = :oi.Id
        ]);
        Map<Id, Order> orderMap = new Map<Id, Order>([
            SELECT Id, Legacy_Id__c FROM Order WHERE Id = :ord.Id
        ]);

        Test.startTest();
        List<Asset> result = PopulateAssetLegacyFieldsAction.buildAssetUpdates(
            assetToSource, orderItemMap, orderMap
        );
        Test.stopTest();

        System.assertEquals(1, result.size());
        Asset updated = result[0];
        System.assertEquals('Installed', updated.Status);
        System.assertEquals(1, updated.Quantity);
        System.assertEquals(2000, updated.Price);
        System.assertEquals(null, updated.Hardware__c, 'No hardware when OrderItem has none');
        System.assertEquals(null, updated.Legacy_Id__c, 'No legacy ID when Order has none');
    }

    @IsTest
    static void testBuildAssetUpdates_usesCommercialTotalPrice() {
        OrderItem oi = (OrderItem) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'Id' => fakeIdFor(OrderItem.SObjectType),
                'Quantity' => 1,
                'TotalPrice' => 15300,
                'NetUnitPrice' => 355,
                'OrderId' => fakeIdFor(Order.SObjectType)
            }),
            OrderItem.class
        );
        AssetActionSource mockAas = new AssetActionSource(
            ReferenceEntityItemId = oi.Id,
            Quantity = 1,
            TotalLineAmount = 355
        );
        Asset ast = new Asset(
            Id = fakeIdFor(Asset.SObjectType),
            Name = 'Commercial Asset'
        );

        List<Asset> result = PopulateAssetLegacyFieldsAction.buildAssetUpdates(
            new Map<Id, AssetActionSource>{ ast.Id => mockAas },
            new Map<Id, OrderItem>{ oi.Id => oi },
            new Map<Id, Order>()
        );

        System.assertEquals(1, result.size());
        System.assertEquals(15300, result[0].Price, 'Asset price should use commercial TotalPrice');
    }

    private static Integer fakeIdCounter = 1;

    private static Id fakeIdFor(Schema.SObjectType sobjectType) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        String body = String.valueOf(fakeIdCounter++).leftPad(12, '0');
        return Id.valueOf(keyPrefix + body);
    }

    @IsTest
    static void testBuildAssetUpdates_MultipleAssets() {
        Account acc = new Account(Name = 'Test Multi Build');
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(acc, dml);

        Product2 prod1 = new Product2(Name = 'Prod A', IsActive = true, QuantityUnitOfMeasure = 'Each');
        Product2 prod2 = new Product2(Name = 'Prod B', IsActive = true, QuantityUnitOfMeasure = 'Each');
        insert new List<Product2>{ prod1, prod2 };

        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe1 = new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = prod1.Id, UnitPrice = 1000, IsActive = true);
        PricebookEntry pbe2 = new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = prod2.Id, UnitPrice = 2000, IsActive = true);
        insert new List<PricebookEntry>{ pbe1, pbe2 };

        Order ord = new Order(
            AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft',
            Pricebook2Id = stdPbId, Legacy_Id__c = 'MULTI-001'
        );
        insert ord;

        OrderItem oi1 = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe1.Id, Quantity = 2, UnitPrice = 1000);
        OrderItem oi2 = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe2.Id, Quantity = 5, UnitPrice = 2000);
        insert new List<OrderItem>{ oi1, oi2 };

        Asset ast1 = new Asset(Name = 'Asset A', AccountId = acc.Id, Product2Id = prod1.Id);
        Asset ast2 = new Asset(Name = 'Asset B', AccountId = acc.Id, Product2Id = prod2.Id);
        insert new List<Asset>{ ast1, ast2 };

        AssetActionSource mock1 = new AssetActionSource(ReferenceEntityItemId = oi1.Id, Quantity = 2, TotalLineAmount = 2000);
        AssetActionSource mock2 = new AssetActionSource(ReferenceEntityItemId = oi2.Id, Quantity = 5, TotalLineAmount = 10000);
        Map<Id, AssetActionSource> assetToSource = new Map<Id, AssetActionSource>{
            ast1.Id => mock1, ast2.Id => mock2
        };
        Map<Id, OrderItem> orderItemMap = new Map<Id, OrderItem>([
            SELECT Id, Hardware__c, OrderId FROM OrderItem WHERE OrderId = :ord.Id
        ]);
        Map<Id, Order> orderMap = new Map<Id, Order>([
            SELECT Id, Legacy_Id__c FROM Order WHERE Id = :ord.Id
        ]);

        Test.startTest();
        List<Asset> result = PopulateAssetLegacyFieldsAction.buildAssetUpdates(
            assetToSource, orderItemMap, orderMap
        );
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should produce 2 Asset updates');
        Map<Id, Asset> resultMap = new Map<Id, Asset>();
        for (Asset a : result) { resultMap.put(a.Id, a); }

        System.assertEquals('Installed', resultMap.get(ast1.Id).Status);
        System.assertEquals(2, resultMap.get(ast1.Id).Quantity);
        System.assertEquals(2000, resultMap.get(ast1.Id).Price);
        System.assertEquals('Installed', resultMap.get(ast2.Id).Status);
        System.assertEquals(5, resultMap.get(ast2.Id).Quantity);
        System.assertEquals(10000, resultMap.get(ast2.Id).Price);
    }

    @IsTest
    static void testBuildAssetUpdates_SourceItemNotInMap() {
        Account acc = new Account(Name = 'Test Source Not Found');
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(acc, dml);

        Product2 prod = new Product2(Name = 'Test Prod', IsActive = true, QuantityUnitOfMeasure = 'Each');
        insert prod;

        Asset ast = new Asset(Name = 'Test Asset Orphan', AccountId = acc.Id, Product2Id = prod.Id);
        insert ast;

        // Mock AAS with a fake ReferenceEntityItemId that won't be in orderItemMap
        Id fakeOrderItemId = OrderItem.sObjectType.getDescribe().getKeyPrefix() + '000000000001';
        AssetActionSource mockAas = new AssetActionSource(
            ReferenceEntityItemId = fakeOrderItemId, Quantity = 7, TotalLineAmount = 42000
        );
        Map<Id, AssetActionSource> assetToSource = new Map<Id, AssetActionSource>{ ast.Id => mockAas };
        // Empty orderItemMap - source item not found
        Map<Id, OrderItem> orderItemMap = new Map<Id, OrderItem>();
        Map<Id, Order> orderMap = new Map<Id, Order>();

        Test.startTest();
        List<Asset> result = PopulateAssetLegacyFieldsAction.buildAssetUpdates(
            assetToSource, orderItemMap, orderMap
        );
        Test.stopTest();

        System.assertEquals(1, result.size());
        Asset updated = result[0];
        System.assertEquals('Installed', updated.Status, 'Status still set');
        System.assertEquals(7, updated.Quantity, 'Quantity from AAS');
        System.assertEquals(42000, updated.Price, 'Price from AAS');
        System.assertEquals(null, updated.Hardware__c, 'No hardware when source item not found');
        System.assertEquals(null, updated.Legacy_Id__c, 'No legacy when source item not found');
    }
}