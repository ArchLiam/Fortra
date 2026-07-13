/**
 * @description Tests AssetArrFromOrderItemHandler / AssetArrFromOrderItemTrigger, the Apex
 *              replacement for the deprecated flow Fortra_Asset_Copy_ARR_From_OrderItem, verifying
 *              that Order_Line_ARR__c is copied onto the related Asset's ARR__c.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class AssetArrFromOrderItemHandlerTest {

    /**
     * @description Builds and inserts an Account, Product2, standard PricebookEntry, Order and
     *              OrderItem, stamping the given ARR value onto the OrderItem's Order_Line_ARR__c
     *              so tests have a source line item to copy from.
     * @param arr the ARR value to set on the OrderItem's Order_Line_ARR__c field
     * @return the inserted OrderItem seeded with the supplied ARR value
     */
    private static OrderItem buildSourceOrderItem(Decimal arr) {
        Account acct = new Account(Name = 'ARR Copy Test Acct');
        insert acct;

        Product2 prod = new Product2(Name = 'ARR Copy Test Product', IsActive = true);
        insert prod;

        Id stdPb = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPb, Product2Id = prod.Id, UnitPrice = 100, IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acct.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPb
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100,
            Order_Line_ARR__c = arr
        );
        insert oi;
        return oi;
    }

    /**
     * @description Verifies that when an Asset is linked to an OrderItem via AssetAction and
     *              AssetActionSource, updating the Asset fires the handler and copies the
     *              OrderItem's Order_Line_ARR__c value onto the Asset's ARR__c.
     */
    @isTest
    static void copiesOrderItemArrOntoAsset() {
        OrderItem oi = buildSourceOrderItem(1200);
        Order ord = [SELECT AccountId FROM Order WHERE Id = :oi.OrderId LIMIT 1];
        Asset asset = new Asset(
            Name = 'ARR Copy Test Asset',
            AccountId = ord.AccountId,
            Product2Id = oi.Product2Id,
            ARR__c = 0
        );
        insert asset;

        AssetAction action = new AssetAction(
            AssetId = asset.Id,
            Type = 'Generate',
            CategoryEnum = 'Initial Sale',
            ActionDate = Date.today(),
            QuantityChange = 1,
            MrrChange = 100,
            Amount = 1200
        );
        insert action;

        AssetActionSource src = new AssetActionSource(
            AssetActionId = action.Id,
            ReferenceEntityItemId = oi.Id
        );
        insert src;

        // Reset the recursion guard so the update below is processed, then fire the trigger.
        AssetArrFromOrderItemHandler.processedAssetIds.clear();

        Test.startTest();
        update new Asset(Id = asset.Id, Name = 'ARR Copy Test Asset v2');
        Test.stopTest();

        Asset result = [SELECT ARR__c FROM Asset WHERE Id = :asset.Id LIMIT 1];
        System.assertEquals(1200, result.ARR__c, 'Asset.ARR__c should be copied from OrderItem.Order_Line_ARR__c');
    }

    /**
     * @description Verifies that updating an Asset with no AssetAction/OrderItem link is a no-op,
     *              leaving the Asset's ARR__c value unchanged.
     */
    @isTest
    static void noOrderItemLinkIsNoOp() {
        Account acct = new Account(Name = 'ARR NoLink Acct');
        insert acct;
        Asset asset = new Asset(Name = 'ARR NoLink Asset', AccountId = acct.Id, ARR__c = 55);
        insert asset;

        AssetArrFromOrderItemHandler.processedAssetIds.clear();
        Test.startTest();
        update new Asset(Id = asset.Id, Name = 'ARR NoLink Asset v2');
        Test.stopTest();

        Asset result = [SELECT ARR__c FROM Asset WHERE Id = :asset.Id LIMIT 1];
        System.assertEquals(55, result.ARR__c, 'No AssetAction/OrderItem link -> ARR unchanged');
    }
}