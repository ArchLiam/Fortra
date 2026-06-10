/**
 * @description Maps custom fields from a converted Quote to the new Order/OrderItems after
 * createOrderFromQuote. The standard createOrderFromQuote action does not map custom lookup
 * fields. This invocable bridges that gap — call it between createOrderFromQuote and
 * SplitPowerOrderLines in the Q2O flow.
 *
 * Bulk-safe: regardless of how many MapRequests are passed, the whole invocation issues a
 * fixed 3 SOQL (Order, OrderItem, QuoteLineItem) + at most 2 DML (Order header, OrderItem).
 * No SOQL or DML runs inside any loop.
 *
 * OrderItem (line-level) mappings:
 *   QLI.Hardware__c            → OI.Hardware__c
 *   QLI.Hardware_ID__c         → OI.Hardware_ID__c
 *   QLI.Partition_Reference__c → OI.Partition_Record__c
 *   QLI.Quote.Ship_To_Place__c → OI.Ship_To_Address__c
 *
 * Order (header-level) Bill To / Ship To carryover (replaces the prior
 * Update_Order_Record_with_Bill_to_Ship_To_Address flow element):
 *   Order.Bill_To_Account__c ← Quote.AccountId                      (SC-3339: per Ben Kozlowski's
 *                              business rule "Account Name → Bill To Account" — the Quote's
 *                              customer account, direct, always populated)
 *   Order.Ship_To_Account__c ← Quote.Ship_To_Place__r.Account__c   (the ship-to PLACE's account;
 *                              not specified in SC-3339, retained as-is; left null when no Ship_To_Place)
 *   Order.Bill_To_Address__c ← Quote.Bill_To_Place__c
 *   Order.Ship_To_Address__c ← Quote.Ship_To_Place__c
 *   Order.BillToContactId    ← Quote.BillToContactId
 *   Order.ShipToContactId    ← Quote.ContactId
 *
 * The Order's own Bill_To_Place__c / Ship_To_Place__c continue to be carried by the platform
 * Context Mapping Engine during createOrderFromQuote and are intentionally not touched here.
 */
public with sharing class QuoteToOrderFieldMapper {

    @InvocableMethod(
        label='Map Quote Line Fields to Order Items'
        description='Copies Hardware/Partition references to OrderItems and Bill To/Ship To account, address and contact references to the Order header after Q2O conversion'
        category='Order Management'
    )
    public static List<MapResult> mapFields(List<MapRequest> requests) {
        List<MapResult> results = new List<MapResult>();
        Map<Id, MapResult> resultByOrderId = new Map<Id, MapResult>();
        Set<Id> orderIds = new Set<Id>();

        // Build one result per request and collect the order ids to process in bulk.
        for (MapRequest request : requests) {
            MapResult result = new MapResult();
            results.add(result);
            if (request.orderId == null) {
                result.success = false;
                result.errorMessage = 'Order ID is required';
                continue;
            }
            orderIds.add(request.orderId);
            resultByOrderId.put(request.orderId, result);
        }

        if (orderIds.isEmpty()) {
            return results;
        }

        try {
            mapOrderHeaders(orderIds, resultByOrderId);      // 1 SOQL + (≤1 DML)
            mapOrderItemFields(orderIds, resultByOrderId);   // 2 SOQL + (≤1 DML)
        } catch (Exception e) {
            String msg = e.getMessage() + ' at line ' + e.getLineNumber();
            for (Id orderId : orderIds) {
                MapResult result = resultByOrderId.get(orderId);
                if (result != null) {
                    result.success = false;
                    result.errorMessage = msg;
                }
            }
            System.debug('QuoteToOrderFieldMapper ERROR: ' + msg);
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

        @InvocableVariable(label='Header Mapped' description='Whether the Order header Bill To/Ship To fields were updated')
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

    /**
     * @description Bulk-stamps the Order header Bill To / Ship To account, address and contact
     * references from each Order's source Quote. Bill To Account is the Quote's customer
     * AccountId (SC-3339); Ship To Account is derived from the ship-to Place's Account__c
     * (left null when no Ship_To_Place). One SOQL for all orders, one DML for all changed
     * orders; idempotent.
     */
    private static void mapOrderHeaders(Set<Id> orderIds, Map<Id, MapResult> resultByOrderId) {
        List<Order> orders = [
            SELECT Id, QuoteId,
                   Bill_To_Account__c, Ship_To_Account__c,
                   Bill_To_Address__c, Ship_To_Address__c,
                   BillToContactId, ShipToContactId,
                   Quote.AccountId,
                   Quote.Bill_To_Place__c,
                   Quote.Ship_To_Place__c, Quote.Ship_To_Place__r.Account__c,
                   Quote.BillToContactId, Quote.ContactId
            FROM Order
            WHERE Id IN :orderIds
        ];

        List<Order> toUpdate = new List<Order>();
        for (Order ord : orders) {
            if (ord.QuoteId == null) {
                continue;
            }

            Order patch = new Order(Id = ord.Id);
            Boolean changed = false;

            // Bill To Account ← Quote.AccountId (SC-3339: Ben's rule "Account Name → Bill To Account";
            // the Quote's customer account, direct — not place-derived)
            if (ord.Quote.AccountId != null
                    && ord.Bill_To_Account__c != ord.Quote.AccountId) {
                patch.Bill_To_Account__c = ord.Quote.AccountId;
                changed = true;
            }

            // Ship To Account ← ship-to Place's Account (leave null when no Ship_To_Place)
            if (ord.Quote.Ship_To_Place__c != null
                    && ord.Ship_To_Account__c != ord.Quote.Ship_To_Place__r.Account__c) {
                patch.Ship_To_Account__c = ord.Quote.Ship_To_Place__r.Account__c;
                changed = true;
            }

            // Bill To Address (Place) ← Quote.Bill_To_Place
            if (ord.Quote.Bill_To_Place__c != null
                    && ord.Bill_To_Address__c != ord.Quote.Bill_To_Place__c) {
                patch.Bill_To_Address__c = ord.Quote.Bill_To_Place__c;
                changed = true;
            }

            // Ship To Address (Place) ← Quote.Ship_To_Place
            if (ord.Quote.Ship_To_Place__c != null
                    && ord.Ship_To_Address__c != ord.Quote.Ship_To_Place__c) {
                patch.Ship_To_Address__c = ord.Quote.Ship_To_Place__c;
                changed = true;
            }

            // Bill To Contact ← Quote.BillToContactId
            if (ord.Quote.BillToContactId != null
                    && ord.BillToContactId != ord.Quote.BillToContactId) {
                patch.BillToContactId = ord.Quote.BillToContactId;
                changed = true;
            }

            // Ship To Contact ← Quote.ContactId (preserves prior flow behavior)
            if (ord.Quote.ContactId != null
                    && ord.ShipToContactId != ord.Quote.ContactId) {
                patch.ShipToContactId = ord.Quote.ContactId;
                changed = true;
            }

            if (changed) {
                toUpdate.add(patch);
                MapResult result = resultByOrderId.get(ord.Id);
                if (result != null) {
                    result.headerMapped = true;
                }
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
            System.debug('QuoteToOrderFieldMapper: Mapped Bill To/Ship To header on ' + toUpdate.size() + ' Order(s)');
        }
    }

    /**
     * @description Bulk-maps Hardware / Partition / Ship_To_Address references from each source
     * QuoteLineItem to its OrderItem. Two SOQL (OrderItems, then their QLIs) and one DML for all
     * changed OrderItems; idempotent.
     */
    private static void mapOrderItemFields(Set<Id> orderIds, Map<Id, MapResult> resultByOrderId) {
        // OrderItems that have a source QuoteLineItemId (set by createOrderFromQuote)
        List<OrderItem> orderItems = [
            SELECT Id, OrderId, QuoteLineItemId, Hardware__c, Hardware_ID__c, Partition_Record__c, Ship_To_Address__c
            FROM OrderItem
            WHERE OrderId IN :orderIds
              AND QuoteLineItemId != null
        ];

        if (orderItems.isEmpty()) {
            return;
        }

        Set<Id> qliIds = new Set<Id>();
        for (OrderItem oi : orderItems) {
            qliIds.add(oi.QuoteLineItemId);
        }

        Map<Id, QuoteLineItem> qliMap = new Map<Id, QuoteLineItem>([
            SELECT Id, Hardware__c, Hardware_ID__c, Partition_Reference__c, Quote.Ship_To_Place__c
            FROM QuoteLineItem
            WHERE Id IN :qliIds
        ]);

        List<OrderItem> toUpdate = new List<OrderItem>();
        Map<Id, Integer> mappedCountByOrder = new Map<Id, Integer>();

        for (OrderItem oi : orderItems) {
            QuoteLineItem sourceQLI = qliMap.get(oi.QuoteLineItemId);
            if (sourceQLI == null) {
                continue;
            }

            Boolean changed = false;
            OrderItem patch = new OrderItem(Id = oi.Id);

            if (sourceQLI.Hardware__c != null && oi.Hardware__c != sourceQLI.Hardware__c) {
                patch.Hardware__c = sourceQLI.Hardware__c;
                changed = true;
            }
            if (sourceQLI.Hardware_ID__c != null && oi.Hardware_ID__c != sourceQLI.Hardware_ID__c) {
                patch.Hardware_ID__c = sourceQLI.Hardware_ID__c;
                changed = true;
            }
            if (sourceQLI.Partition_Reference__c != null && oi.Partition_Record__c != sourceQLI.Partition_Reference__c) {
                patch.Partition_Record__c = sourceQLI.Partition_Reference__c;
                changed = true;
            }
            if (sourceQLI.Quote != null && sourceQLI.Quote.Ship_To_Place__c != null
                    && oi.Ship_To_Address__c != sourceQLI.Quote.Ship_To_Place__c) {
                patch.Ship_To_Address__c = sourceQLI.Quote.Ship_To_Place__c;
                changed = true;
            }

            if (changed) {
                toUpdate.add(patch);
                Integer current = mappedCountByOrder.get(oi.OrderId);
                mappedCountByOrder.put(oi.OrderId, (current == null ? 0 : current) + 1);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
            System.debug('QuoteToOrderFieldMapper: Mapped fields on ' + toUpdate.size() + ' OrderItem(s)');
        }

        for (Id orderId : mappedCountByOrder.keySet()) {
            MapResult result = resultByOrderId.get(orderId);
            if (result != null) {
                result.itemsMapped = mappedCountByOrder.get(orderId);
            }
        }
    }
}
