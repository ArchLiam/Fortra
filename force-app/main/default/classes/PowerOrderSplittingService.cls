/**
 * @description Service class for splitting Power order lines during Quote-to-Order conversion.
 * When a Power product order line has quantity > 1, this service splits it into individual
 * lines (qty=1 each) and handles associated Hardware and Partition records according to
 * the product's Power Split Type configuration.
 *
 * Split Types:
 * - "Order Line Only": Order lines split, Hardware SHARED, Partitions CLONED
 * - "Order Line and Hardware": Order lines split, Hardware CLONED, Partitions CLONED
 *
 * Bulk-safe: any number of Orders passed in one invocable call are processed together with a
 * fixed SOQL/DML budget (queries use IN :orderIds, each phase DMLs once across all orders).
 * No SOQL or DML runs inside a loop.
 */
public with sharing class PowerOrderSplittingService {

    private static final String SPLIT_TYPE_ORDER_LINE_ONLY = 'Order Line Only';
    private static final String SPLIT_TYPE_ORDER_LINE_AND_HARDWARE = 'Order Line and Hardware';
    private static final String SOLUTION_GROUP_POWER = 'Power';

    // Cached field describe for OrderItem
    private static Map<String, Schema.SObjectField> orderItemFieldMap;

    @InvocableMethod(
        label='Split Power Order Lines'
        description='Splits Power order lines with qty > 1 into individual lines and handles hardware/partition cloning'
        category='Order Management'
    )
    public static List<SplitResult> splitPowerOrderLines(List<SplitRequest> requests) {
        List<SplitResult> results = new List<SplitResult>();
        Map<Id, SplitResult> resultByOrderId = new Map<Id, SplitResult>();
        Set<Id> orderIds = new Set<Id>();

        for (SplitRequest request : requests) {
            SplitResult result = new SplitResult();
            results.add(result);
            if (request.orderId == null) {
                result.success = false;
                result.errorMessage = 'Order ID is required';
                continue;
            }
            orderIds.add(request.orderId);
            resultByOrderId.put(request.orderId, result);
        }

        if (!orderIds.isEmpty()) {
            processOrders(orderIds, resultByOrderId);
        }

        return results;
    }

    public class SplitRequest {
        @InvocableVariable(label='Order ID' description='The Order ID to process for Power line splitting' required=true)
        public Id orderId;
    }

    public class SplitResult {
        @InvocableVariable(label='Success' description='Whether the splitting operation succeeded')
        public Boolean success;

        @InvocableVariable(label='Lines Created' description='Number of new order lines created from splitting')
        public Integer linesCreated;

        @InvocableVariable(label='Hardware Cloned' description='Number of hardware records cloned')
        public Integer hardwareCloned;

        @InvocableVariable(label='Partitions Cloned' description='Number of partition records cloned')
        public Integer partitionsCloned;

        @InvocableVariable(label='Error Message' description='Error message if the operation failed')
        public String errorMessage;

        public SplitResult() {
            this.success = true;
            this.linesCreated = 0;
            this.hardwareCloned = 0;
            this.partitionsCloned = 0;
            this.errorMessage = '';
        }
    }

    /**
     * @description Backward-compatible single-order entry point. Delegates to the bulk path so
     * existing callers and tests keep working while the invocable stays bulk-safe.
     */
    public static SplitResult processOrder(Id orderId) {
        SplitRequest request = new SplitRequest();
        request.orderId = orderId;
        return splitPowerOrderLines(new List<SplitRequest>{ request })[0];
    }

    /**
     * @description Bulk Power-line splitting across many Orders in one transaction. Preserves the
     * per-order phase logic and index lockstep; only the SOQL/DML are batched across orders.
     * Order.ValidationResult (the RC activation gate) is captured per order and restored to null
     * for any order we actually split that was clean beforehand.
     */
    private static void processOrders(Set<Id> orderIds, Map<Id, SplitResult> resultByOrderId) {
        // Capture pre-existing ValidationResult per order (RC activation gate). ANY OrderItem DML
        // flips a null ValidationResult to 'TransactionIncomplete', blocking activation with the
        // misleading "prices aren't updated" error; we restore null at the end for orders we split.
        Map<Id, String> preValidationResultByOrder = new Map<Id, String>();
        for (Order ord : [SELECT Id, OrderNumber, ValidationResult FROM Order WHERE Id IN :orderIds]) {
            preValidationResultByOrder.put(ord.Id, ord.ValidationResult);
        }

        Savepoint sp = Database.setSavepoint();

        try {
            // Qualifying order items across all orders, with ALL accessible fields, deterministically ordered.
            List<OrderItem> itemsToSplit = queryOrderItemsToSplit(orderIds);
            System.debug('PowerOrderSplittingService: Qualifying items to split: ' + itemsToSplit.size());

            if (itemsToSplit.isEmpty()) {
                return;
            }

            // Collect related record IDs across all orders
            Set<Id> partitionIds = new Set<Id>();
            Set<Id> hardwareIds = new Set<Id>();
            for (OrderItem oi : itemsToSplit) {
                if (oi.Partition_Record__c != null) {
                    partitionIds.add(oi.Partition_Record__c);
                }
                if (oi.Hardware__c != null) {
                    hardwareIds.add(oi.Hardware__c);
                }
            }

            Map<Id, Partition__c> partitionMap = queryPartitions(partitionIds);
            Map<Id, Hardware__c> hardwareMap = queryHardware(hardwareIds);

            // Phase 1: Build clone OrderItems in memory (qty-1 clones per original).
            // The original OrderItem is KEPT and updated in place to count as the first slot.
            List<OrderItem> newItems = new List<OrderItem>();
            List<Hardware__c> newHardwareRecords = new List<Hardware__c>();

            for (OrderItem original : itemsToSplit) {
                SplitResult result = resultByOrderId.get(original.OrderId);
                Integer qty = Integer.valueOf(original.Quantity);
                String splitType = original.Product2.Power_Split_Type__c;
                if (String.isBlank(splitType)) {
                    splitType = SPLIT_TYPE_ORDER_LINE_ONLY;
                }
                Boolean cloneHw = (splitType == SPLIT_TYPE_ORDER_LINE_AND_HARDWARE);

                Decimal manualDiscountPer = original.Manual_Discount__c != null ?
                    original.Manual_Discount__c / qty : null;
                Decimal displacedARRPer = original.Displaced_ARR__c != null ?
                    original.Displaced_ARR__c / qty : null;

                Hardware__c origHw = original.Hardware__c != null ?
                    hardwareMap.get(original.Hardware__c) : null;

                // Create (qty - 1) clones. The original counts as slot 0; clones are slots 1..qty-1.
                for (Integer i = 1; i < qty; i++) {
                    OrderItem splitItem = createFullClone(original);
                    splitItem.Quantity = 1;
                    splitItem.Manual_Discount__c = manualDiscountPer;
                    splitItem.Displaced_ARR__c = displacedARRPer;
                    splitItem.Is_Split_Line__c = true;
                    splitItem.Original_Order_Item__c = original.Id;

                    if (cloneHw && original.Hardware__c != null) {
                        splitItem.Hardware__c = null;
                    }

                    newItems.add(splitItem);
                }

                // Clone hardware for clones (slots 1..qty-1) if "Order Line and Hardware"
                if (cloneHw && origHw != null) {
                    for (Integer i = 1; i < qty; i++) {
                        newHardwareRecords.add(cloneHardwareRecord(origHw, i));
                        if (result != null) {
                            result.hardwareCloned++;
                        }
                    }
                }

                if (result != null) {
                    result.linesCreated += (qty - 1);
                }
            }

            // Phase 2: Insert cloned hardware (all orders)
            if (!newHardwareRecords.isEmpty()) {
                insert newHardwareRecords;
            }

            // Phase 3: Assign cloned hardware IDs to clone OrderItems (slots 1..qty-1)
            Integer hwIdx = 0;
            Integer itemIdx = 0;
            for (OrderItem original : itemsToSplit) {
                Integer qty = Integer.valueOf(original.Quantity);
                String splitType = original.Product2.Power_Split_Type__c;
                if (String.isBlank(splitType)) {
                    splitType = SPLIT_TYPE_ORDER_LINE_ONLY;
                }
                Boolean cloneHw = (splitType == SPLIT_TYPE_ORDER_LINE_AND_HARDWARE);

                for (Integer i = 1; i < qty; i++) {
                    if (cloneHw && original.Hardware__c != null && hwIdx < newHardwareRecords.size()) {
                        newItems[itemIdx].Hardware__c = newHardwareRecords[hwIdx].Id;
                        hwIdx++;
                    }
                    itemIdx++;
                }
            }

            // Phase 4: Insert clone OrderItems (all orders)
            if (!newItems.isEmpty()) {
                insert newItems;
                System.debug('PowerOrderSplittingService: Inserted ' + newItems.size() + ' new OrderItems');
            }

            // Phase 5: Update originals in place (Quantity=1, distribute amounts, unmark split)
            List<OrderItem> originalsToUpdate = new List<OrderItem>();
            for (OrderItem original : itemsToSplit) {
                Integer qty = Integer.valueOf(original.Quantity);

                Decimal manualDiscountPer = original.Manual_Discount__c != null ?
                    original.Manual_Discount__c / qty : null;
                Decimal displacedARRPer = original.Displaced_ARR__c != null ?
                    original.Displaced_ARR__c / qty : null;

                originalsToUpdate.add(new OrderItem(
                    Id = original.Id,
                    Quantity = 1,
                    Manual_Discount__c = manualDiscountPer,
                    Displaced_ARR__c = displacedARRPer,
                    Is_Split_Line__c = false,
                    Original_Order_Item__c = null
                ));
            }
            if (!originalsToUpdate.isEmpty()) {
                update originalsToUpdate;
            }

            // Phase 6: Create cloned partitions (one per clone slot 1..qty-1).
            List<Partition__c> newPartitions = new List<Partition__c>();
            hwIdx = 0;
            for (OrderItem original : itemsToSplit) {
                SplitResult result = resultByOrderId.get(original.OrderId);
                Integer qty = Integer.valueOf(original.Quantity);
                String splitType = original.Product2.Power_Split_Type__c;
                if (String.isBlank(splitType)) {
                    splitType = SPLIT_TYPE_ORDER_LINE_ONLY;
                }
                Boolean cloneHw = (splitType == SPLIT_TYPE_ORDER_LINE_AND_HARDWARE);
                Partition__c origPartition = original.Partition_Record__c != null ?
                    partitionMap.get(original.Partition_Record__c) : null;

                if (origPartition != null) {
                    for (Integer i = 1; i < qty; i++) {
                        Id hwIdForPartition;
                        if (cloneHw && hwIdx < newHardwareRecords.size()) {
                            hwIdForPartition = newHardwareRecords[hwIdx].Id;
                            hwIdx++;
                        } else {
                            hwIdForPartition = original.Hardware__c;
                        }
                        newPartitions.add(clonePartitionRecord(origPartition, hwIdForPartition, i));
                        if (result != null) {
                            result.partitionsCloned++;
                        }
                    }
                }
            }

            if (!newPartitions.isEmpty()) {
                insert newPartitions;
            }

            // Phase 7: Update clone OrderItems with their cloned partition references
            List<OrderItem> itemsToUpdatePartition = new List<OrderItem>();
            Integer partIdx = 0;
            itemIdx = 0;
            for (OrderItem original : itemsToSplit) {
                Integer qty = Integer.valueOf(original.Quantity);
                Partition__c origPartition = original.Partition_Record__c != null ?
                    partitionMap.get(original.Partition_Record__c) : null;

                for (Integer i = 1; i < qty; i++) {
                    if (origPartition != null && partIdx < newPartitions.size()) {
                        newItems[itemIdx].Partition_Record__c = newPartitions[partIdx].Id;
                        itemsToUpdatePartition.add(newItems[itemIdx]);
                        partIdx++;
                    }
                    itemIdx++;
                }
            }

            if (!itemsToUpdatePartition.isEmpty()) {
                update itemsToUpdatePartition;
            }

            // Phase 8: Restore Order.ValidationResult to null for each order we actually split
            // that was clean beforehand (never mask a pre-existing validation issue).
            List<Order> ordersToClear = new List<Order>();
            for (Id orderId : orderIds) {
                SplitResult result = resultByOrderId.get(orderId);
                if (result != null && result.linesCreated > 0 && preValidationResultByOrder.get(orderId) == null) {
                    ordersToClear.add(new Order(Id = orderId, ValidationResult = null));
                }
            }
            if (!ordersToClear.isEmpty()) {
                update ordersToClear;
                System.debug('PowerOrderSplittingService: Cleared Order.ValidationResult on ' + ordersToClear.size() + ' order(s)');
            }

        } catch (Exception e) {
            Database.rollback(sp);
            String msg = e.getMessage() + ' at line ' + e.getLineNumber();
            for (Id orderId : orderIds) {
                SplitResult result = resultByOrderId.get(orderId);
                if (result != null) {
                    result.success = false;
                    result.errorMessage = msg;
                    result.linesCreated = 0;
                    result.hardwareCloned = 0;
                    result.partitionsCloned = 0;
                }
            }
            System.debug('PowerOrderSplittingService ERROR: ' + msg);
        }
    }

    /**
     * @description Query order items to split (across many orders) using dynamic SOQL with ALL
     * accessible fields, so createFullClone() copies every attribute to the split items.
     */
    private static List<OrderItem> queryOrderItemsToSplit(Set<Id> orderIds) {
        Map<String, Schema.SObjectField> fieldMap = getOrderItemFieldMap();
        List<String> queryFields = new List<String>();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            if (dfr.isAccessible()) {
                queryFields.add(fieldName);
            }
        }

        // Add parent relationship fields needed for split logic
        queryFields.add('Product2.Power_Split_Type__c');
        queryFields.add('Product2.Solution_Group__c');
        queryFields.add('Product2.Name');

        String solGroup = SOLUTION_GROUP_POWER;
        String soql = 'SELECT ' + String.join(queryFields, ', ')
            + ' FROM OrderItem'
            + ' WHERE OrderId IN :orderIds'
            + ' AND Product2.Solution_Group__c = :solGroup'
            + ' AND Quantity > 1'
            + ' ORDER BY OrderId, Id';

        return Database.query(soql);
    }

    /**
     * @description Create a full clone of an OrderItem, copying all createable fields.
     */
    private static OrderItem createFullClone(OrderItem original) {
        OrderItem clone = new OrderItem();
        Map<String, Schema.SObjectField> fieldMap = getOrderItemFieldMap();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            if (dfr.isCreateable()) {
                try {
                    Object val = original.get(fieldName);
                    if (val != null) {
                        clone.put(fieldName, val);
                    }
                } catch (Exception e) {
                    // Skip fields that can't be read from the queried record
                }
            }
        }
        return clone;
    }

    private static Map<String, Schema.SObjectField> getOrderItemFieldMap() {
        if (orderItemFieldMap == null) {
            orderItemFieldMap = Schema.SObjectType.OrderItem.fields.getMap();
        }
        return orderItemFieldMap;
    }

    private static Map<Id, Partition__c> queryPartitions(Set<Id> partitionIds) {
        if (partitionIds.isEmpty()) {
            return new Map<Id, Partition__c>();
        }
        return new Map<Id, Partition__c>([
            SELECT Id, Name, Hardware__c, Partition_ID__c, Partition_Name__c,
                   Partition_Number__c, Number_of_Processors__c,
                   License_Key__c, Status__c, Activation_Date__c,
                   Expiration_Date__c, Notes__c
            FROM Partition__c
            WHERE Id IN :partitionIds
        ]);
    }

    private static Map<Id, Hardware__c> queryHardware(Set<Id> hardwareIds) {
        if (hardwareIds.isEmpty()) {
            return new Map<Id, Hardware__c>();
        }
        return new Map<Id, Hardware__c>([
            SELECT Id, Name, Account__c, Primary_Contact__c, Parent_Hardware__c,
                   Location__c, Primary_Quote__c, Primary_Order__c, Primary_Asset__c,
                   Serial_Number__c, Model_Number__c, Manufacturer__c, Hardware_Type__c
            FROM Hardware__c
            WHERE Id IN :hardwareIds
        ]);
    }

    private static Hardware__c cloneHardwareRecord(Hardware__c original, Integer index) {
        Hardware__c cloned = new Hardware__c();
        cloned.Account__c = original.Account__c;
        cloned.Primary_Contact__c = original.Primary_Contact__c;
        cloned.Parent_Hardware__c = original.Parent_Hardware__c;
        cloned.Location__c = original.Location__c;
        cloned.Serial_Number__c = original.Serial_Number__c != null ?
            original.Serial_Number__c + '-SPLIT-' + index : null;
        cloned.Model_Number__c = original.Model_Number__c;
        cloned.Manufacturer__c = original.Manufacturer__c;
        cloned.Hardware_Type__c = original.Hardware_Type__c;
        return cloned;
    }

    private static Partition__c clonePartitionRecord(Partition__c original, Id hardwareId, Integer index) {
        Partition__c cloned = new Partition__c();
        cloned.Hardware__c = hardwareId;
        cloned.Partition_ID__c = original.Partition_ID__c != null ?
            original.Partition_ID__c + '-SPLIT-' + index : null;
        cloned.Partition_Name__c = original.Partition_Name__c != null ?
            original.Partition_Name__c + ' (Split ' + index + ')' : null;
        cloned.Partition_Number__c = original.Partition_Number__c;
        cloned.Number_of_Processors__c = original.Number_of_Processors__c;
        cloned.Status__c = original.Status__c;
        cloned.Activation_Date__c = original.Activation_Date__c;
        cloned.Expiration_Date__c = original.Expiration_Date__c;
        cloned.Notes__c = original.Notes__c;
        return cloned;
    }
}
