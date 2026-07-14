/**
 * Idempotency guard for the Fortra_Assetize_Order flow.
 *
 * The assetize flow triggers when an Order enters Status = "Activated" OR
 * "Order Complete" (an Order may reach the second without ever committing the
 * first, e.g. an amendment that goes Draft -> Provisioned -> Order Complete).
 * This action reports, per Order, whether that Order has already produced
 * assetization output -- an AssetActionSource linked to one of its OrderItems --
 * so the flow assetizes exactly once and never re-invokes the non-idempotent
 * native createOrUpdateAssetFromOrder action (which emits a fresh AssetAction and
 * asset state period on every call and can hit an optimistic-lock collision on a
 * second run).
 *
 * without sharing: the guard must see assetization output regardless of the
 * running (automated) user's sharing, so a false negative can never cause a
 * duplicate assetization.
 *
 * Bulk-safe: two SOQL total regardless of how many Orders batch through the
 * async path (Lightning Flow Scanner / compliance sec.2.3, sec.2.5).
 */
public without sharing class OrderAssetizationGuard {

    public class FlowInput {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    public class FlowOutput {
        @InvocableVariable(label='Already Assetized')
        public Boolean alreadyAssetized;
    }

    @InvocableMethod(
        label='Check Order Already Assetized'
        description='True when the Order already has assetization output (an AssetActionSource on any of its OrderItems).'
        category='Revenue'
    )
    public static List<FlowOutput> checkAlreadyAssetized(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();
        if (inputs == null || inputs.isEmpty()) {
            return outputs;
        }

        Set<Id> orderIds = new Set<Id>();
        for (FlowInput input : inputs) {
            if (input != null && input.orderId != null) {
                orderIds.add(input.orderId);
            }
        }

        Set<Id> assetizedOrderIds = findAssetizedOrderIds(orderIds);

        for (FlowInput input : inputs) {
            FlowOutput out = new FlowOutput();
            out.alreadyAssetized = input != null
                && input.orderId != null
                && assetizedOrderIds.contains(input.orderId);
            outputs.add(out);
        }
        return outputs;
    }

    /**
     * Returns the subset of orderIds that already have assetization output.
     * One SOQL to map OrderItem -> Order, one SOQL over AssetActionSource.
     */
    @TestVisible
    static Set<Id> findAssetizedOrderIds(Set<Id> orderIds) {
        Set<Id> assetizedOrderIds = new Set<Id>();
        if (orderIds == null || orderIds.isEmpty()) {
            return assetizedOrderIds;
        }

        Map<Id, Id> orderItemToOrder = new Map<Id, Id>();
        for (OrderItem oi : [SELECT Id, OrderId FROM OrderItem WHERE OrderId IN :orderIds]) {
            orderItemToOrder.put(oi.Id, oi.OrderId);
        }
        if (orderItemToOrder.isEmpty()) {
            return assetizedOrderIds;
        }

        // AssetActionSource.ReferenceEntityItemId points at the source OrderItem;
        // its presence means createOrUpdateAssetFromOrder already ran for that line.
        for (AssetActionSource aas : [
            SELECT ReferenceEntityItemId
            FROM AssetActionSource
            WHERE ReferenceEntityItemId IN :orderItemToOrder.keySet()
        ]) {
            Id parentOrderId = orderItemToOrder.get(aas.ReferenceEntityItemId);
            if (parentOrderId != null) {
                assetizedOrderIds.add(parentOrderId);
            }
        }
        return assetizedOrderIds;
    }
}
