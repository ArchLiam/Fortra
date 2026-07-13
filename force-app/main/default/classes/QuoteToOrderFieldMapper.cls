/**
 * @description Maps custom fields from QuoteLineItems to OrderItems after createOrderFromQuote.
 * The standard createOrderFromQuote action does not map custom lookup fields.
 * This invocable bridges that gap — call it between createOrderFromQuote and
 * SplitPowerOrderLines in the Q2O flow.
 *
 * Field mappings:
 *   QLI.Hardware__c            → OI.Hardware__c
 *   QLI.Hardware_ID__c         → OI.Hardware_ID__c
 *   QLI.Partition_Reference__c → OI.Partition_Record__c
 *   QLI.Source_List_Price__c   → OI.Source_List_Price__c (stamped by Stamp_Source_List_Price flow on QLI)
 *
 * FORTRA-PRODUCT-018 Step 5: derived maintenance lines on New/Net-New quotes also persist
 * maintenance Base / Partner$ / Discretionary$ onto OrderItem for renewal carry-forward.
 * Renewal quotes: copies stamped QLI carry-forward fields (Base, Prior Partner$/Disc$, net)
 * onto OrderItem because createOrderFromQuote does not map those custom fields.
 */
public with sharing class QuoteToOrderFieldMapper {

    @InvocableMethod(
        label='Map Quote Line Fields to Order Items'
        description='Copies Hardware and Partition references from source QuoteLineItems to OrderItems after Q2O conversion'
        category='Order Management'
    )
    public static List<MapResult> mapFields(List<MapRequest> requests) {
        Set<Id> orderIds = new Set<Id>();
        for (MapRequest request : requests) {
            if (request.orderId != null) {
                orderIds.add(request.orderId);
            }
        }

        Map<Id, MaintenanceOrderDecompositionService.OrderMaintenanceWork> workByOrderId =
            MaintenanceOrderDecompositionService.loadWorkBulk(orderIds);

        List<MapResult> results = new List<MapResult>();
        for (MapRequest request : requests) {
            MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
                request.orderId != null ? workByOrderId.get(request.orderId) : null;
            results.add(processOrder(request.orderId, work));
        }
        return results;
    }

    public class MapRequest {
        @InvocableVariable(label='Order ID' description='The Order created by createOrderFromQuote' required=true)
        public Id orderId;
    }

    public class MapResult {
        @InvocableVariable(label='Success' description='Whether the mapping operation succeeded')
        public Boolean success;

        @InvocableVariable(label='Items Mapped' description='Number of OrderItems that received field values')
        public Integer itemsMapped;

        @InvocableVariable(label='Header Mapped' description='Whether Bill To / Ship To header fields were copied from Quote')
        public Boolean headerMapped;

        @InvocableVariable(label='Error Message' description='Error message if the operation failed')
        public String errorMessage;

        public MapResult() {
            this.success = true;
            this.itemsMapped = 0;
            this.headerMapped = false;
            this.errorMessage = '';
        }
    }

    private static MapResult processOrder(
        Id orderId,
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work
    ) {
        MapResult result = new MapResult();

        if (orderId == null) {
            result.success = false;
            result.errorMessage = 'Order ID is required';
            return result;
        }

        try {
            if (work == null) {
                work = MaintenanceOrderDecompositionService.loadWork(orderId);
            }
            result.headerMapped = MaintenanceOrderDecompositionService.applyOrderHeaderFromWork(work);

            if (work.allOrderItems.isEmpty()) {
                System.debug('QuoteToOrderFieldMapper: No OrderItems found on Order ' + orderId);
                return result;
            }

            // Map fields from QLI to OrderItem (uses data loaded once in loadWork)
            Map<Id, OrderItem> patchById = new Map<Id, OrderItem>();
            for (OrderItem oi : work.allOrderItems) {
                if (oi.QuoteLineItemId == null) {
                    continue;
                }

                QuoteLineItem sourceQLI = work.qliById.get(oi.QuoteLineItemId);
                if (sourceQLI == null) {
                    continue;
                }

                Boolean changed = false;
                OrderItem patch = new OrderItem(Id = oi.Id);

                // Hardware__c
                if (sourceQLI.Hardware__c != null && oi.Hardware__c != sourceQLI.Hardware__c) {
                    patch.Hardware__c = sourceQLI.Hardware__c;
                    changed = true;
                }

                // Hardware_ID__c
                if (sourceQLI.Hardware_ID__c != null && oi.Hardware_ID__c != sourceQLI.Hardware_ID__c) {
                    patch.Hardware_ID__c = sourceQLI.Hardware_ID__c;
                    changed = true;
                }

                // Partition_Reference__c (QLI) → Partition_Record__c (OrderItem)
                if (sourceQLI.Partition_Reference__c != null && oi.Partition_Record__c != sourceQLI.Partition_Reference__c) {
                    patch.Partition_Record__c = sourceQLI.Partition_Reference__c;
                    changed = true;
                }
                
                // Ship_To_Address
                if(sourceQLI.Quote != null && sourceQLI.Quote.Ship_To_Place__c != null){
                    patch.Ship_To_Address__c = sourceQLI.Quote.Ship_To_Place__c;
                    changed = true;
                }

                // Source_List_Price__c (derived maintenance pricing input from stamp flow)
                if (sourceQLI.Source_List_Price__c != null
                    && oi.Source_List_Price__c != sourceQLI.Source_List_Price__c) {
                    patch.Source_List_Price__c = sourceQLI.Source_List_Price__c;
                    changed = true;
                }

                // SC-3384: carry the ABA raw-USD net snapshot so the order-side reprice (which does not
                // re-run the ESD) stays provenance-based and idempotent (no re-scale of a localized net).
                if (sourceQLI.ABA_Raw_Net__c != null && oi.ABA_Raw_Net__c != sourceQLI.ABA_Raw_Net__c) {
                    patch.ABA_Raw_Net__c = sourceQLI.ABA_Raw_Net__c;
                    changed = true;
                }

                if (changed) {
                    patchById.put(oi.Id, patch);
                }
            }

            mergeOrderItemPatches(patchById, MaintenanceOrderDecompositionService.buildPatchesFromWork(work));
            mergeOrderItemPatches(
                patchById,
                MaintenanceOrderDecompositionService.buildRenewalCarryForwardPatchesFromWork(work)
            );

            Integer itemsMapped = applyOrderItemPatches(patchById);
            if (itemsMapped > 0) {
                result.itemsMapped = itemsMapped;
                System.debug('QuoteToOrderFieldMapper: Mapped fields on ' + itemsMapped + ' OrderItem(s)');
            } else {
                System.debug('QuoteToOrderFieldMapper: No fields needed mapping (all null or already set)');
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage() + ' at line ' + e.getLineNumber();
            System.debug('QuoteToOrderFieldMapper ERROR: ' + result.errorMessage);
        }

        return result;
    }

    @TestVisible
    private static void mergeOrderItemPatches(Map<Id, OrderItem> target, Map<Id, OrderItem> additional) {
        for (Id orderItemId : additional.keySet()) {
            OrderItem extra = additional.get(orderItemId);
            if (target.containsKey(orderItemId)) {
                OrderItem existing = target.get(orderItemId);
                if (extra.Base_Price__c != null) {
                    existing.Base_Price__c = extra.Base_Price__c;
                }
                if (extra.Prior_Partner_Discount__c != null) {
                    existing.Prior_Partner_Discount__c = extra.Prior_Partner_Discount__c;
                }
                if (extra.Prior_Discretionary_Discount__c != null) {
                    existing.Prior_Discretionary_Discount__c = extra.Prior_Discretionary_Discount__c;
                }
                if (extra.UnitPrice != null) {
                    existing.UnitPrice = extra.UnitPrice;
                }
                if (extra.NetUnitPrice != null) {
                    existing.NetUnitPrice = extra.NetUnitPrice;
                }
                if (extra.PartnerUnitPrice != null) {
                    existing.PartnerUnitPrice = extra.PartnerUnitPrice;
                }
                if (extra.TotalLineAmount != null) {
                    existing.TotalLineAmount = extra.TotalLineAmount;
                }
                if (extra.Source_List_Price__c != null) {
                    existing.Source_List_Price__c = extra.Source_List_Price__c;
                }
            } else {
                target.put(orderItemId, extra);
            }
        }
    }

    @TestVisible
    private static Integer applyOrderItemPatches(Map<Id, OrderItem> patchById) {
        if (patchById.isEmpty()) {
            return 0;
        }

        try {
            update patchById.values();
            return patchById.size();
        } catch (DmlException e) {
            if (!isOrderProductDetailPricingLock(e)) {
                throw e;
            }
            stripCommercialPricingFromPatches(patchById);
            if (patchById.isEmpty()) {
                return 0;
            }
            update patchById.values();
            return patchById.size();
        }
    }

    @TestVisible
    private static Boolean isOrderProductDetailPricingLock(DmlException e) {
        return e.getMessage() != null && e.getMessage().contains('Order Product Detail');
    }

    @TestVisible
    private static void stripCommercialPricingFromPatches(Map<Id, OrderItem> patchById) {
        for (OrderItem patch : patchById.values()) {
            patch.UnitPrice = null;
            patch.NetUnitPrice = null;
            patch.PartnerUnitPrice = null;
            patch.TotalLineAmount = null;
        }
    }
}