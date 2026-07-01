/**
 * Invocable action that populates legacy Asset fields (Status, Quantity, Price)
 * on lifecycle-managed Assets created by createOrUpdateAssetFromOrder.
 *
 * Revenue Cloud's standard action creates Assets with HasLifecycleManagement = true
 * and populates lifecycle fields (CurrentQuantity, LifecycleStartDate, etc.) but
 * leaves legacy fields (Status, Price, Quantity) null. This action fills those
 * fields by reading the AssetActionSource records created alongside each Asset.
 *
 * Called from the Fortra_Assetize_Order flow immediately after the
 * createOrUpdateAssetFromOrder action completes.
 */
public without sharing class PopulateAssetLegacyFieldsAction {

    public class FlowInput {
        @InvocableVariable(required=true label='Order ID' description='The activated Order Id')
        public Id orderId;
    }

    @InvocableMethod(
        label='Populate Asset Legacy Fields'
        description='Sets Status, Quantity, and Price on lifecycle-managed Assets created from an Order'
        category='Revenue'
    )
    public static void populateFields(List<FlowInput> inputs) {
        Set<Id> orderIds = new Set<Id>();
        for (FlowInput input : inputs) {
            if (input.orderId != null) {
                orderIds.add(input.orderId);
            }
        }
        if (orderIds.isEmpty()) return;

        // Get Legacy_Id__c from the parent Orders
        Map<Id, Order> orderMap = new Map<Id, Order>([
            SELECT Id, Legacy_Id__c FROM Order WHERE Id IN :orderIds
        ]);

        // Get OrderItems for the given Orders (include Hardware for Asset mapping)
        Map<Id, OrderItem> orderItemMap = new Map<Id, OrderItem>([
            SELECT Id, Hardware__c, OrderId, Quantity, TotalPrice, NetUnitPrice
            FROM OrderItem
            WHERE OrderId IN :orderIds
        ]);
        if (orderItemMap.isEmpty()) return;
        Set<Id> orderItemIds = orderItemMap.keySet();

        // Query AssetActionSource records linked to these OrderItems
        // ReferenceEntityItemId points to the source OrderItem
        Map<Id, AssetActionSource> assetToSource = new Map<Id, AssetActionSource>();
        for (AssetActionSource aas : [
            SELECT AssetAction.AssetId, ReferenceEntityItemId, Quantity, TotalLineAmount
            FROM AssetActionSource
            WHERE ReferenceEntityItemId IN :orderItemIds
            ORDER BY CreatedDate DESC
        ]) {
            Id assetId = aas.AssetAction.AssetId;
            // Keep first match per Asset (most recent due to ORDER BY)
            if (!assetToSource.containsKey(assetId)) {
                assetToSource.put(assetId, aas);
            }
        }
        if (assetToSource.isEmpty()) return;

        // Build and apply Asset updates
        List<Asset> toUpdate = buildAssetUpdates(assetToSource, orderItemMap, orderMap);
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * Builds Asset update records from AssetActionSource data, mapping fields
     * from OrderItem and Order to the Asset. Separated for testability since
     * AssetActionSource records are system-managed and not DML-insertable in
     * most test contexts.
     */
    @TestVisible
    static List<Asset> buildAssetUpdates(
        Map<Id, AssetActionSource> assetToSource,
        Map<Id, OrderItem> orderItemMap,
        Map<Id, Order> orderMap
    ) {
        List<Asset> toUpdate = new List<Asset>();
        for (Id assetId : assetToSource.keySet()) {
            AssetActionSource src = assetToSource.get(assetId);
            OrderItem sourceItem = orderItemMap.get(src.ReferenceEntityItemId);
            Asset a = new Asset(
                Id = assetId,
                Status = 'Installed',
                Quantity = src.Quantity,
                Price = resolveCommercialAssetPrice(src, sourceItem)
            );

            // Carry Hardware lookup and Legacy_Id from OrderItem/Order to Asset
            if (sourceItem != null) {
                a.Hardware__c = sourceItem.Hardware__c;

                // Carry Legacy_Id from Order to Asset
                Order parentOrder = orderMap.get(sourceItem.OrderId);
                if (parentOrder != null && parentOrder.Legacy_Id__c != null) {
                    a.Legacy_Id__c = parentOrder.Legacy_Id__c;
                }
            }

            toUpdate.add(a);
        }
        return toUpdate;
    }

    @TestVisible
    static Decimal resolveCommercialAssetPrice(AssetActionSource src, OrderItem sourceItem) {
        if (sourceItem != null) {
            Decimal commercialUnit = OrderCommercialNetService.resolveCommercialUnitPrice(sourceItem);
            if (commercialUnit != null) {
                return commercialUnit;
            }
        }
        return src?.TotalLineAmount;
    }
}