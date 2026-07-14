/**
 * Invocable Action: Creates AssetContractRelationship records for Assets
 * created from an Order that has a ContractId.
 *
 * Called by Fortra_Assetize_Order flow after createOrUpdateAssetFromOrder.
 *
 * Prerequisites for ACR creation:
 *   1. Order must have a ContractId
 *   2. Contract must have an AppUsageAssignment (RevenueLifecycleManagement)
 *   3. ACR StartDate is required; EndDate must be <= Contract EndDate
 *   4. Assets must not already have an ACR to this Contract
 */
public with sharing class AssetContractLinkerAction {

    public class ActionInput {
        @InvocableVariable(label='Order ID' required=true)
        public Id orderId;
    }

    public class ActionOutput {
        @InvocableVariable(label='ACRs Created Count')
        public Integer acrsCreated;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='Success')
        public Boolean success;
    }

    @InvocableMethod(label='Link Assets to Contract' description='Creates AssetContractRelationship records for Order assets' category='Revenue Cloud')
    public static List<ActionOutput> linkAssetsToContract(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            output.acrsCreated = 0;
            output.success = true;

            try {
                processOrder(input.orderId, output);
            } catch (Exception e) {
                output.success = false;
                output.errorMessage = e.getMessage();
            }

            outputs.add(output);
        }

        return outputs;
    }

    private static void processOrder(Id orderId, ActionOutput output) {
        // Get Order with ContractId
        List<Order> orders = [
            SELECT Id, ContractId, Contract.StartDate, Contract.EndDate
            FROM Order
            WHERE Id = :orderId AND ContractId != null
            LIMIT 1
        ];

        if (orders.isEmpty()) {
            // No contract on this order - nothing to do
            return;
        }

        Order ord = orders[0];
        Id contractId = ord.ContractId;
        Date contractStart = ord.Contract.StartDate;
        Date contractEnd = ord.Contract.EndDate;

        // Ensure Contract has RLM AppUsageAssignment
        ensureContractAUA(contractId);

        // Find Assets created from this Order via AssetAction → OrderAction chain
        Set<Id> assetIds = getAssetsFromOrder(orderId);
        if (assetIds.isEmpty()) {
            return;
        }

        // Find which assets already have ACR to this contract
        Set<Id> existingAcrAssetIds = new Set<Id>();
        for (AssetContractRelationship acr : [
            SELECT AssetId
            FROM AssetContractRelationship
            WHERE AssetId IN :assetIds AND ContractId = :contractId
        ]) {
            existingAcrAssetIds.add(acr.AssetId);
        }

        // Create ACRs for assets that don't have one yet
        List<AssetContractRelationship> newAcrs = new List<AssetContractRelationship>();
        DateTime startDt = DateTime.newInstance(contractStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = contractEnd != null
            ? DateTime.newInstance(contractEnd, Time.newInstance(0, 0, 0, 0))
            : null;

        for (Id assetId : assetIds) {
            if (!existingAcrAssetIds.contains(assetId)) {
                AssetContractRelationship acr = new AssetContractRelationship(
                    AssetId = assetId,
                    ContractId = contractId,
                    StartDate = startDt
                );
                if (endDt != null) {
                    acr.EndDate = endDt;
                }
                newAcrs.add(acr);
            }
        }

        if (!newAcrs.isEmpty()) {
            insert newAcrs;
            output.acrsCreated = newAcrs.size();
        }
    }

    private static void ensureContractAUA(Id contractId) {
        List<AppUsageAssignment> existing = [
            SELECT Id FROM AppUsageAssignment
            WHERE RecordId = :contractId
            AND AppUsageType = 'RevenueLifecycleManagement'
            LIMIT 1
        ];

        if (existing.isEmpty()) {
            AppUsageAssignment aua = new AppUsageAssignment(
                RecordId = contractId,
                AppUsageType = 'RevenueLifecycleManagement'
            );
            insert aua;
        }
    }

    private static Set<Id> getAssetsFromOrder(Id orderId) {
        // ReferenceEntityItemId on AssetActionSource references OrderItem (not OrderAction)
        // Path: Order → OrderItem → AssetActionSource → AssetAction → Asset
        Set<Id> orderItemIds = new Set<Id>();
        for (OrderItem oi : [SELECT Id FROM OrderItem WHERE OrderId = :orderId]) {
            orderItemIds.add(oi.Id);
        }

        if (orderItemIds.isEmpty()) {
            return new Set<Id>();
        }

        Set<Id> assetIds = new Set<Id>();
        for (AssetAction aa : [
            SELECT AssetId FROM AssetAction
            WHERE Id IN (
                SELECT AssetActionId FROM AssetActionSource
                WHERE ReferenceEntityItemId IN :orderItemIds
            )
        ]) {
            assetIds.add(aa.AssetId);
        }

        return assetIds;
    }
}