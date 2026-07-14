/**
 * @description Step 12 — prepares order lines before assetization so RCA does not copy
 *              stacked partner/manual Percentage+Amount rate adjustments onto assets.
 *
 *              Products with partner or manual discount: align unit fields to commercial
 *              net (TotalPrice) so the asset receives a single negotiated rate.
 *              Products without those discounts: keep list/net alignment unchanged.
 *
 *              DPP V16 partner/manual steps use writeBackData=[] so the quote waterfall
 *              still calculates discounts but does not persist adjustment stacks to the
 *              order/asset binding object.
 */
public with sharing class AssetRateOverrideConsolidationService {

    /**
     * @description Patches order lines immediately before createOrUpdateAssetFromOrder.
     */
    public static Integer prepareOrderForAssetization(Id orderId) {
        if (orderId == null) {
            return 0;
        }
        Map<Id, Integer> counts = patchOrderLinesForAssetizationBulk(new Set<Id>{ orderId });
        return counts.containsKey(orderId) ? counts.get(orderId) : 0;
    }

    @TestVisible
    static Integer patchOrderLinesForAssetization(Id orderId) {
        return prepareOrderForAssetization(orderId);
    }

    /**
     * @description D-16 bulk variant: aligns commercial net on every line of the given orders in a
     *              single SOQL + single DML, so the invocable stays governor-safe when the async
     *              record-triggered Fortra_Assetize_Order flow batches multiple activated Orders
     *              into one transaction. Mirrors the bulkified sibling PopulateAssetLegacyFieldsAction
     *              in the same flow. Returns per-order patched-line counts.
     */
    @TestVisible
    static Map<Id, Integer> patchOrderLinesForAssetizationBulk(Set<Id> orderIds) {
        Map<Id, Integer> countsByOrderId = new Map<Id, Integer>();
        if (orderIds == null || orderIds.isEmpty()) {
            return countsByOrderId;
        }
        for (Id orderId : orderIds) {
            if (orderId != null) {
                countsByOrderId.put(orderId, 0);
            }
        }

        List<OrderItem> patches = new List<OrderItem>();
        for (OrderItem oi : [
            SELECT Id, OrderId, Quantity, TotalPrice, NetUnitPrice, UnitPrice,
                   PartnerDiscountPercent, Discount, Manual_Discount__c, DiscountAmount
            FROM OrderItem
            WHERE OrderId IN :orderIds
        ]) {
            Decimal commercialUnit = resolveCommercialUnitForAssetization(oi);
            if (commercialUnit == null) {
                continue;
            }
            if (oi.NetUnitPrice == commercialUnit && oi.UnitPrice == commercialUnit) {
                continue;
            }
            patches.add(new OrderItem(
                Id = oi.Id,
                NetUnitPrice = commercialUnit,
                UnitPrice = commercialUnit
            ));
            countsByOrderId.put(oi.OrderId, countsByOrderId.get(oi.OrderId) + 1);
        }

        if (patches.isEmpty()) {
            return countsByOrderId;
        }
        update patches;
        return countsByOrderId;
    }

    /**
     * @description True when the line carries partner or discretionary manual discount inputs.
     */
    @TestVisible
    static Boolean hasPartnerOrManualDiscount(OrderItem oi) {
        if (oi == null) {
            return false;
        }
        if (oi.PartnerDiscountPercent != null && oi.PartnerDiscountPercent > 0) {
            return true;
        }
        if (oi.Discount != null && oi.Discount > 0) {
            return true;
        }
        if (oi.Manual_Discount__c != null && oi.Manual_Discount__c > 0) {
            return true;
        }
        if (oi.DiscountAmount != null && oi.DiscountAmount > 0) {
            return true;
        }
        return false;
    }

    /**
     * @description Lines with discounts always use commercial net; others use list/net rules.
     */
    @TestVisible
    static Decimal resolveCommercialUnitForAssetization(OrderItem oi) {
        if (oi == null) {
            return null;
        }

        Map<String, Object> populated = oi.getPopulatedFieldsAsMap();
        if (!populated.containsKey('TotalPrice') || oi.TotalPrice == null || oi.TotalPrice <= 0) {
            return null;
        }

        Decimal quantity = oi.Quantity != null && oi.Quantity > 0 ? oi.Quantity : 1;

        if (hasPartnerOrManualDiscount(oi)) {
            return (oi.TotalPrice / quantity).setScale(2, RoundingMode.HALF_UP);
        }

        return OrderCommercialNetService.resolveCommercialUnitPrice(oi);
    }

    public class FlowInput {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    @InvocableMethod(
        label='Prepare Order for Asset Override Consolidation'
        description='Aligns order line unit prices before assetization; handles optional partner/manual discounts'
        category='Revenue'
    )
    public static void prepareForAssetization(List<FlowInput> inputs) {
        if (inputs == null) {
            return;
        }
        Set<Id> orderIds = new Set<Id>();
        for (FlowInput input : inputs) {
            if (input?.orderId != null) {
                orderIds.add(input.orderId);
            }
        }
        patchOrderLinesForAssetizationBulk(orderIds);
    }
}