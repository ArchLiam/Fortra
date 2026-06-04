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
 */
public with sharing class QuoteToOrderFieldMapper {

    @InvocableMethod(
        label='Map Quote Line Fields to Order Items'
        description='Copies Hardware and Partition references from source QuoteLineItems to OrderItems after Q2O conversion'
        category='Order Management'
    )
    public static List<MapResult> mapFields(List<MapRequest> requests) {
        List<MapResult> results = new List<MapResult>();
        for (MapRequest request : requests) {
            results.add(processOrder(request.orderId));
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

        @InvocableVariable(label='Error Message' description='Error message if the operation failed')
        public String errorMessage;

        public MapResult() {
            this.success = true;
            this.itemsMapped = 0;
            this.errorMessage = '';
        }
    }

    private static MapResult processOrder(Id orderId) {
        MapResult result = new MapResult();

        if (orderId == null) {
            result.success = false;
            result.errorMessage = 'Order ID is required';
            return result;
        }

        try {
            // Query OrderItems that have a source QuoteLineItemId (set by createOrderFromQuote)
            List<OrderItem> orderItems = [
                SELECT Id, QuoteLineItemId, Hardware__c, Hardware_ID__c, Partition_Record__c, Ship_To_Address__c
                FROM OrderItem
                WHERE OrderId = :orderId
                  AND QuoteLineItemId != null
            ];

            if (orderItems.isEmpty()) {
                System.debug('QuoteToOrderFieldMapper: No OrderItems with QuoteLineItemId found on Order ' + orderId);
                return result;
            }

            // Collect source QLI IDs
            Set<Id> qliIds = new Set<Id>();
            for (OrderItem oi : orderItems) {
                qliIds.add(oi.QuoteLineItemId);
            }

            // Query source QuoteLineItems for the fields we need to map
            Map<Id, QuoteLineItem> qliMap = new Map<Id, QuoteLineItem>([
                SELECT Id, Hardware__c, Hardware_ID__c, Partition_Reference__c, Quote.Ship_To_Place__c
                FROM QuoteLineItem
                WHERE Id IN :qliIds
            ]);

            // Map fields from QLI to OrderItem
            List<OrderItem> toUpdate = new List<OrderItem>();
            for (OrderItem oi : orderItems) {
                QuoteLineItem sourceQLI = qliMap.get(oi.QuoteLineItemId);
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

                if (changed) {
                    toUpdate.add(patch);
                }
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
                result.itemsMapped = toUpdate.size();
                System.debug('QuoteToOrderFieldMapper: Mapped fields on ' + toUpdate.size() + ' OrderItem(s)');
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
}