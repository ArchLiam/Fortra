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
        return patchOrderLinesForAssetization(orderId);
    }

    @TestVisible
    static Integer patchOrderLinesForAssetization(Id orderId) {
        List<OrderItem> patches = new List<OrderItem>();
        for (OrderItem oi : [
            SELECT Id, Quantity, TotalPrice, NetUnitPrice, UnitPrice,
                   PartnerDiscountPercent, Discount, Manual_Discount__c, DiscountAmount
            FROM OrderItem
            WHERE OrderId = :orderId
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
        }

        if (patches.isEmpty()) {
            return 0;
        }
        update patches;
        return patches.size();
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
        for (FlowInput input : inputs) {
            if (input?.orderId != null) {
                prepareOrderForAssetization(input.orderId);
            }
        }
    }
}