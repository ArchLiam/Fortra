@IsTest
private class BackfillAssetHardwareBatchTest {

    private static Integer fakeIdCounter = 1;

    private static Id fakeIdFor(Schema.SObjectType sobjectType) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        String body = String.valueOf(fakeIdCounter++).leftPad(12, '0');
        return Id.valueOf(keyPrefix + body);
    }

    /**
     * Builds an AssetActionSource (system-managed, not insertable) with a parent
     * AssetAction.AssetId populated, via JSON deserialization.
     */
    private static AssetActionSource mockSource(Id assetId, Id orderItemId) {
        return (AssetActionSource) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'ReferenceEntityItemId' => orderItemId,
                'AssetAction' => new Map<String, Object>{ 'AssetId' => assetId }
            }),
            AssetActionSource.class
        );
    }

    @IsTest
    static void mapAssetsToOrderItems_keepsFirstPerAsset() {
        Id assetA = fakeIdFor(Asset.SObjectType);
        Id assetB = fakeIdFor(Asset.SObjectType);
        Id oi1 = fakeIdFor(OrderItem.SObjectType);
        Id oi2 = fakeIdFor(OrderItem.SObjectType);
        Id oi3 = fakeIdFor(OrderItem.SObjectType);

        // assetA appears twice (first wins); assetB once; one row with null asset.
        List<AssetActionSource> sources = new List<AssetActionSource>{
            mockSource(assetA, oi1),
            mockSource(assetA, oi2),
            mockSource(assetB, oi3),
            mockSource(null, oi3)
        };

        Map<Id, Id> result = BackfillAssetHardwareBatch.mapAssetsToOrderItems(sources);

        System.assertEquals(2, result.size(), 'Two distinct assets mapped');
        System.assertEquals(oi1, result.get(assetA), 'First match per asset is kept');
        System.assertEquals(oi3, result.get(assetB));
    }

    @IsTest
    static void buildBackfillUpdates_onlyMissingHardwareCandidates() {
        Id assetMissing = fakeIdFor(Asset.SObjectType);   // candidate
        Id assetHasHw   = fakeIdFor(Asset.SObjectType);   // already has hw -> skip
        Id assetNoOi    = fakeIdFor(Asset.SObjectType);   // no source hw -> skip
        Id assetNotInSet= fakeIdFor(Asset.SObjectType);   // not in assetsById -> skip
        Id oiWithHw   = fakeIdFor(OrderItem.SObjectType);
        Id oiNoHw     = fakeIdFor(OrderItem.SObjectType);
        Id hwId       = fakeIdFor(Account.SObjectType);   // any Id stands in for a Hardware lookup in-memory

        Map<Id, Id> assetToOrderItem = new Map<Id, Id>{
            assetMissing => oiWithHw,
            assetHasHw   => oiWithHw,
            assetNoOi    => oiNoHw,
            assetNotInSet=> oiWithHw
        };
        Map<Id, Id> orderItemToHardware = new Map<Id, Id>{ oiWithHw => hwId };
        Map<Id, Asset> assetsById = new Map<Id, Asset>{
            assetMissing => new Asset(Id = assetMissing, Hardware__c = null),
            assetHasHw   => new Asset(Id = assetHasHw, Hardware__c = hwId),
            assetNoOi    => new Asset(Id = assetNoOi, Hardware__c = null)
            // assetNotInSet intentionally absent
        };

        List<Asset> updates = BackfillAssetHardwareBatch.buildBackfillUpdates(
            assetToOrderItem, orderItemToHardware, assetsById
        );

        System.assertEquals(1, updates.size(), 'Only the missing-hardware candidate is updated');
        System.assertEquals(assetMissing, updates[0].Id);
        System.assertEquals(hwId, updates[0].Hardware__c);
    }

    @IsTest
    static void applyUpdates_countsSuccessAndFailure() {
        Account acc = new Account(Name = 'Backfill Apply Acct');
        insert acc;
        Product2 prod = new Product2(Name = 'Backfill Prod', IsActive = true, QuantityUnitOfMeasure = 'Each');
        insert prod;
        Hardware__c hw = new Hardware__c(
            Account__c = acc.Id,
            Serial_Number__c = 'BACKFILL-SN-' + String.valueOf(Crypto.getRandomLong()).right(8)
        );
        insert hw;
        Asset realAsset = new Asset(Name = 'Backfill Asset', AccountId = acc.Id, Product2Id = prod.Id);
        insert realAsset;

        BackfillAssetHardwareBatch batch = new BackfillAssetHardwareBatch();

        Test.startTest();
        // One valid update (succeeds) + one bogus Id (fails) -> partial success.
        List<Asset> updates = new List<Asset>{
            new Asset(Id = realAsset.Id, Hardware__c = hw.Id),
            new Asset(Id = fakeIdFor(Asset.SObjectType), Hardware__c = hw.Id)
        };
        batch.applyUpdates(updates);
        // Empty input is a no-op.
        batch.applyUpdates(new List<Asset>());
        Test.stopTest();

        System.assertEquals(1, batch.updatedCount, 'One successful update');
        System.assertEquals(1, batch.failedCount, 'One failed update (bogus Id)');

        Asset reloaded = [SELECT Hardware__c FROM Asset WHERE Id = :realAsset.Id];
        System.assertEquals(hw.Id, reloaded.Hardware__c, 'Real asset hardware backfilled');
    }

    @IsTest
    static void batchLifecycle_runsClean() {
        Account acc = new Account(Name = 'Backfill Lifecycle Acct');
        insert acc;
        Product2 prod = new Product2(Name = 'Backfill LC Prod', IsActive = true, QuantityUnitOfMeasure = 'Each');
        insert prod;
        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId, Product2Id = prod.Id, UnitPrice = 100, IsActive = true
        );
        insert pbe;
        Hardware__c hw = new Hardware__c(
            Account__c = acc.Id,
            Serial_Number__c = 'BACKFILL-LC-' + String.valueOf(Crypto.getRandomLong()).right(8)
        );
        insert hw;
        Order ord = new Order(
            AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = stdPbId
        );
        insert ord;
        OrderItem oi = new OrderItem(
            OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 100, Hardware__c = hw.Id
        );
        insert oi;

        Test.startTest();
        Database.executeBatch(new BackfillAssetHardwareBatch(), 200);
        Test.stopTest();
        // No AssetActionSource exists in test context, so the batch finds the
        // order line but resolves no assets and completes without error.
    }
}