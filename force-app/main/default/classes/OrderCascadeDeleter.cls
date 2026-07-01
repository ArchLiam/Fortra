public with sharing class OrderCascadeDeleter {

    public class Input {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    public class Output {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Order Number Deleted')
        public String orderNumber;
    }

    @InvocableMethod(label='Cascade Delete Order' description='Deletes an Order and all dependent fulfillment records (FOs, FOLIs, step sources, steps, plan, AUA)')
    public static List<Output> cascadeDelete(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(runOne(inp.orderId));
        }
        return results;
    }

    private static Output runOne(Id orderId) {
        Output out = new Output();
        Savepoint sp = Database.setSavepoint();
        try {
            List<Order> orders = [SELECT Id, OrderNumber, Status, FulfillmentPlanId FROM Order WHERE Id = :orderId LIMIT 1];
            if (orders.isEmpty()) {
                out.success = false;
                out.message = 'Order not found: ' + orderId;
                return out;
            }
            Order ord = orders[0];
            out.orderNumber = ord.OrderNumber;
            Id planId = ord.FulfillmentPlanId;

            List<Id> foliIds = new List<Id>();
            List<Id> oiIds = new List<Id>();
            for (FulfillmentOrderLineItem foli : [SELECT Id FROM FulfillmentOrderLineItem WHERE FulfillmentOrder.OrderId = :orderId]) foliIds.add(foli.Id);
            for (OrderItem oi : [SELECT Id FROM OrderItem WHERE OrderId = :orderId]) oiIds.add(oi.Id);

            Set<Id> stepSourceIds = new Set<Id>();
            if (!foliIds.isEmpty()) {
                for (FulfillmentStepSource fss : [SELECT Id FROM FulfillmentStepSource WHERE SourceLineItemId IN :foliIds]) stepSourceIds.add(fss.Id);
            }
            if (!oiIds.isEmpty()) {
                for (FulfillmentStepSource fss : [SELECT Id FROM FulfillmentStepSource WHERE SourceLineItemId IN :oiIds]) stepSourceIds.add(fss.Id);
            }
            if (!stepSourceIds.isEmpty()) {
                delete [SELECT Id FROM FulfillmentStepSource WHERE Id IN :stepSourceIds];
            }

            if (planId != null) {
                Set<Id> stepIds = new Map<Id, FulfillmentStep>([SELECT Id FROM FulfillmentStep WHERE FulfillmentPlanId = :planId]).keySet();
                if (!stepIds.isEmpty()) {
                    List<FulfillmentStepDependency> deps = [
                        SELECT Id FROM FulfillmentStepDependency
                        WHERE DependentStepId IN :stepIds OR DependsOnStepId IN :stepIds
                    ];
                    if (!deps.isEmpty()) Database.delete(deps, false);
                }
            }

            Set<Id> lineSourceRelIds = new Set<Id>();
            if (!foliIds.isEmpty()) {
                for (FulfillmentLineSourceRel r : [SELECT Id FROM FulfillmentLineSourceRel WHERE FulfilmentOrderLineId IN :foliIds]) lineSourceRelIds.add(r.Id);
                for (FulfillmentLineSourceRel r : [SELECT Id FROM FulfillmentLineSourceRel WHERE SourceLineItemId IN :foliIds]) lineSourceRelIds.add(r.Id);
            }
            if (!oiIds.isEmpty()) {
                for (FulfillmentLineSourceRel r : [SELECT Id FROM FulfillmentLineSourceRel WHERE SourceLineItemId IN :oiIds]) lineSourceRelIds.add(r.Id);
            }
            if (!lineSourceRelIds.isEmpty()) {
                delete [SELECT Id FROM FulfillmentLineSourceRel WHERE Id IN :lineSourceRelIds];
            }

            if (!foliIds.isEmpty()) {
                List<FulfillmentLineRel> lineRels = [SELECT Id FROM FulfillmentLineRel WHERE MainFulfillmentOrderItemId IN :foliIds OR AssociatedFulfillOrderItemId IN :foliIds];
                if (!lineRels.isEmpty()) delete lineRels;

                List<FulfillmentLineAttribute> lineAttrs = [SELECT Id FROM FulfillmentLineAttribute WHERE FulfillmentOrderLineItemId IN :foliIds];
                if (!lineAttrs.isEmpty()) delete lineAttrs;
            }

            List<Id> faIds = new List<Id>();
            for (FulfillmentOrderLineItem foli : [SELECT FulfillmentAssetId FROM FulfillmentOrderLineItem WHERE FulfillmentOrder.OrderId = :orderId AND FulfillmentAssetId != null]) {
                faIds.add(foli.FulfillmentAssetId);
            }
            if (!faIds.isEmpty()) {
                List<AssetFulfillmentDecomp> decomps = [SELECT Id FROM AssetFulfillmentDecomp WHERE FulfillmentTargetAssetId IN :faIds OR FulfillmentSourceAssetId IN :faIds];
                if (!decomps.isEmpty()) delete decomps;
            }

            List<FulfillmentOrderLineItem> folis = [SELECT Id FROM FulfillmentOrderLineItem WHERE FulfillmentOrder.OrderId = :orderId];
            if (!folis.isEmpty()) delete folis;

            if (!faIds.isEmpty()) {
                List<FulfillmentAsset> fas = [SELECT Id FROM FulfillmentAsset WHERE Id IN :faIds];
                if (!fas.isEmpty()) delete fas;
            }

            List<FulfillmentOrder> fos = [SELECT Id FROM FulfillmentOrder WHERE OrderId = :orderId];
            if (!fos.isEmpty()) delete fos;

            if (planId != null) {
                Database.delete(new FulfillmentPlan(Id = planId), false);
                List<FulfillmentStep> remainingSteps = [SELECT Id FROM FulfillmentStep WHERE FulfillmentPlanId = :planId];
                if (!remainingSteps.isEmpty()) {
                    for (FulfillmentStep s : remainingSteps) {
                        try { delete s; } catch (Exception ignored) {}
                    }
                }
            }

            List<AppUsageAssignment> auas = [SELECT Id FROM AppUsageAssignment WHERE RecordId = :orderId];
            if (!auas.isEmpty()) delete auas;

            if (ord.Status == 'Activated' || ord.Status == 'Order Complete') {
                ord.Status = 'Draft';
                update ord;
            }

            delete ord;

            out.success = true;
            out.message = 'Order ' + ord.OrderNumber + ' and all fulfillment dependencies deleted.';
        } catch (Exception e) {
            Database.rollback(sp);
            out.success = false;
            out.message = e.getTypeName() + ': ' + e.getMessage();
        }
        return out;
    }
}