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
 *   QLI.Source_List_Price__c   → OI.Source_List_Price__c (DISABLED — use flow + context definition)
 *
 * FORTRA-PRODUCT-018 Step 5: derived maintenance lines on New/Net-New quotes also persist
 * maintenance Base / Partner$ / Discretionary$ onto OrderItem for renewal carry-forward.
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

    private static MapResult processOrder(Id orderId) {
        MapResult result = new MapResult();

        if (orderId == null) {
            result.success = false;
            result.errorMessage = 'Order ID is required';
            return result;
        }

        try {
            MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
                MaintenanceOrderDecompositionService.loadWork(orderId);
            result.headerMapped = mapOrderHeaderFromQuote(orderId);

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

                /*
                // Source_List_Price__c (derived maintenance pricing input) — DISABLED
                if (sourceQLI.Source_List_Price__c != null) {
                    patch.Source_List_Price__c = sourceQLI.Source_List_Price__c;
                    changed = true;
                }
                */

                if (changed) {
                    patchById.put(oi.Id, patch);
                }
            }

            mergeOrderItemPatches(patchById, MaintenanceOrderDecompositionService.buildPatchesFromWork(work));

            if (!patchById.isEmpty()) {
                update patchById.values();
                result.itemsMapped = patchById.size();
                System.debug('QuoteToOrderFieldMapper: Mapped fields on ' + patchById.size() + ' OrderItem(s)');
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

    /**
     * @description Copies Bill To / Ship To header fields from the source Quote onto the Order.
     *              Bill To Account = Quote.AccountId (SC-3339, direct customer account); Ship To
     *              Account is derived from the ship-to Place's Account__c.
     */
    @TestVisible
    private static Boolean mapOrderHeaderFromQuote(Id orderId) {
        List<Order> orders = [
            SELECT Id, QuoteId, BillToContactId, ShipToContactId,
                   Bill_To_Account__c, Ship_To_Account__c,
                   Bill_To_Address__c, Ship_To_Address__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        if (orders.isEmpty() || orders[0].QuoteId == null) {
            return false;
        }

        Order ord = orders[0];
        List<Quote> quotes = [
            SELECT Id, AccountId, BillToContactId, ContactId, Bill_To_Place__c, Ship_To_Place__c
            FROM Quote
            WHERE Id = :ord.QuoteId
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            return false;
        }

        Quote sourceQuote = quotes[0];
        Set<Id> placeIds = new Set<Id>();
        if (sourceQuote.Bill_To_Place__c != null) {
            placeIds.add(sourceQuote.Bill_To_Place__c);
        }
        if (sourceQuote.Ship_To_Place__c != null) {
            placeIds.add(sourceQuote.Ship_To_Place__c);
        }

        Map<Id, Places__c> placeById = new Map<Id, Places__c>();
        if (!placeIds.isEmpty()) {
            placeById = new Map<Id, Places__c>([
                SELECT Id, Account__c
                FROM Places__c
                WHERE Id IN :placeIds
            ]);
        }

        Order patch = new Order(Id = ord.Id);
        Boolean changed = false;

        // Bill To Account <- Quote customer account (SC-3339: "Account Name -> Bill To Account",
        // direct customer AccountId, NOT the bill-to place's account)
        if (sourceQuote.AccountId != null && ord.Bill_To_Account__c != sourceQuote.AccountId) {
            patch.Bill_To_Account__c = sourceQuote.AccountId;
            changed = true;
        }

        if (sourceQuote.Bill_To_Place__c != null && ord.Bill_To_Address__c != sourceQuote.Bill_To_Place__c) {
            patch.Bill_To_Address__c = sourceQuote.Bill_To_Place__c;
            changed = true;
        }

        if (sourceQuote.Ship_To_Place__c != null) {
            Places__c shipPlace = placeById.get(sourceQuote.Ship_To_Place__c);
            if (shipPlace != null && shipPlace.Account__c != null && ord.Ship_To_Account__c != shipPlace.Account__c) {
                patch.Ship_To_Account__c = shipPlace.Account__c;
                changed = true;
            }
            if (ord.Ship_To_Address__c != sourceQuote.Ship_To_Place__c) {
                patch.Ship_To_Address__c = sourceQuote.Ship_To_Place__c;
                changed = true;
            }
        }

        if (sourceQuote.BillToContactId != null && ord.BillToContactId != sourceQuote.BillToContactId) {
            patch.BillToContactId = sourceQuote.BillToContactId;
            changed = true;
        }

        if (sourceQuote.ContactId != null && ord.ShipToContactId != sourceQuote.ContactId) {
            patch.ShipToContactId = sourceQuote.ContactId;
            changed = true;
        }

        if (!changed) {
            return false;
        }

        update patch;
        return true;
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
            } else {
                target.put(orderItemId, extra);
            }
        }
    }
}