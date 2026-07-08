/**
 * @description Copies the source OrderItem's Order_Line_ARR__c onto Asset.ARR__c after an Asset is
 *              created or updated. This is the Apex replacement for the deprecated record-triggered
 *              flow `Fortra_Asset_Copy_ARR_From_OrderItem` (A-3 / SC ARR consolidation): the ARR
 *              logic now lives entirely in Apex alongside the split-time apportionment in
 *              PowerOrderSplittingService, so a Power qty-split's apportioned per-unit ARR flows
 *              through to each per-unit Asset instead of an N-fold overcount.
 *
 *              Traversal mirrors the flow exactly: Asset -> AssetAction (by AssetId) ->
 *              AssetActionSource (by AssetActionId) -> OrderItem (by ReferenceEntityItemId). Only
 *              writes when the OrderItem ARR is non-null and differs from the current Asset.ARR__c.
 */
public with sharing class AssetArrFromOrderItemHandler {

    // Recursion guard: the ARR write is an Asset update that re-fires the after-update trigger.
    @TestVisible
    private static Set<Id> processedAssetIds = new Set<Id>();

    public static void copyArrFromOrderItem(List<Asset> triggerNew) {
        if (triggerNew == null || triggerNew.isEmpty()) {
            return;
        }

        Set<Id> assetIds = new Set<Id>();
        for (Asset a : triggerNew) {
            if (a.Id != null && !processedAssetIds.contains(a.Id)) {
                assetIds.add(a.Id);
            }
        }
        if (assetIds.isEmpty()) {
            return;
        }

        // Asset -> AssetAction (earliest action per Asset = the create action, matching the flow's
        // single-record Get). ORDER BY CreatedDate keeps selection deterministic on multi-action Assets.
        Map<Id, Id> assetIdToActionId = new Map<Id, Id>();
        for (AssetAction aa : [
            SELECT Id, AssetId
            FROM AssetAction
            WHERE AssetId IN :assetIds
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (!assetIdToActionId.containsKey(aa.AssetId)) {
                assetIdToActionId.put(aa.AssetId, aa.Id);
            }
        }
        if (assetIdToActionId.isEmpty()) {
            return;
        }

        // AssetAction -> AssetActionSource.ReferenceEntityItemId (the source OrderItem Id).
        Map<Id, Id> actionIdToRefItemId = new Map<Id, Id>();
        for (AssetActionSource src : [
            SELECT Id, AssetActionId, ReferenceEntityItemId
            FROM AssetActionSource
            WHERE AssetActionId IN :assetIdToActionId.values()
              AND ReferenceEntityItemId != null
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (!actionIdToRefItemId.containsKey(src.AssetActionId)) {
                actionIdToRefItemId.put(src.AssetActionId, src.ReferenceEntityItemId);
            }
        }
        if (actionIdToRefItemId.isEmpty()) {
            return;
        }

        // ReferenceEntityItemId -> OrderItem.Order_Line_ARR__c. Non-OrderItem reference Ids simply
        // do not match and are skipped (the flow's Get Order Item is OrderItem-typed).
        Map<Id, Decimal> orderItemIdToArr = new Map<Id, Decimal>();
        for (OrderItem oi : [
            SELECT Id, Order_Line_ARR__c
            FROM OrderItem
            WHERE Id IN :actionIdToRefItemId.values()
        ]) {
            orderItemIdToArr.put(oi.Id, oi.Order_Line_ARR__c);
        }
        if (orderItemIdToArr.isEmpty()) {
            return;
        }

        List<Asset> toUpdate = new List<Asset>();
        for (Asset a : triggerNew) {
            if (!assetIds.contains(a.Id)) {
                continue;
            }
            Id actionId = assetIdToActionId.get(a.Id);
            if (actionId == null) {
                continue;
            }
            Id refItemId = actionIdToRefItemId.get(actionId);
            if (refItemId == null || !orderItemIdToArr.containsKey(refItemId)) {
                continue;
            }
            Decimal sourceArr = orderItemIdToArr.get(refItemId);
            // Flow guard: only when non-null AND differs from the current Asset value.
            if (sourceArr != null && sourceArr != a.ARR__c) {
                toUpdate.add(new Asset(Id = a.Id, ARR__c = sourceArr));
                processedAssetIds.add(a.Id);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
