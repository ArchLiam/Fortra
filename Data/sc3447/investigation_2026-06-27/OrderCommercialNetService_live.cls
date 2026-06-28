/**
 * @description Aligns OrderItem commercial unit prices before assetization so RCA copies
 *              negotiated net (TotalPrice) onto assets instead of stale NetUnitPrice from
 *              the pricing waterfall.
 *
 *              Does not call PartnerNetPricePosthook here — pricing context is already
 *              stamped during quote reprice / Q2O. Re-running the posthook at activation
 *              can gack or leave createOrUpdateAssetFromOrder stuck at ContextPersistence
 *              without spawning AssetizationAsyncJob.
 */
public with sharing class OrderCommercialNetService {

    /**
     * @description Patches order lines whose UnitPrice/NetUnitPrice are stale vs TotalPrice.
     *              Call immediately before createOrUpdateAssetFromOrder in Fortra_Assetize_Order.
     */
    public static Integer finalizeOrderForAssetization(Id orderId) {
        return patchOrderItemCommercialUnitPrices(orderId);
    }

    /**
     * @description When TotalPrice reflects commercial net but NetUnitPrice is stale (e.g.
     *              perpetual $15,300 total vs $355 unit), align unit fields before assets copy pricing.
     */
    @TestVisible
    public static Integer patchOrderItemCommercialUnitPrices(Id orderId) {
        if (orderId == null) {
            return 0;
        }

        List<OrderItem> patches = new List<OrderItem>();
        for (OrderItem oi : [
            SELECT Id, Quantity, TotalPrice, NetUnitPrice, UnitPrice
            FROM OrderItem
            WHERE OrderId = :orderId
        ]) {
            Decimal commercialUnit = resolveCommercialUnitPrice(oi);
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

    @TestVisible
    public static Decimal resolveCommercialUnitPrice(OrderItem oi) {
        if (oi == null) {
            return null;
        }

        Map<String, Object> populated = oi.getPopulatedFieldsAsMap();
        if (!populated.containsKey('TotalPrice')) {
            return null;
        }

        if (oi.TotalPrice == null || oi.TotalPrice <= 0) {
            return null;
        }

        Decimal quantity = oi.Quantity != null && oi.Quantity > 0 ? oi.Quantity : 1;
        Decimal commercialUnit = (oi.TotalPrice / quantity).setScale(2, RoundingMode.HALF_UP);
        Decimal listUnit = oi.NetUnitPrice != null && oi.NetUnitPrice > 0 ? oi.NetUnitPrice : null;

        if (listUnit == null) {
            return commercialUnit;
        }

        Decimal listLineTotal = (listUnit * quantity).setScale(2, RoundingMode.HALF_UP);
        if (oi.TotalPrice != listLineTotal) {
            return commercialUnit;
        }

        return listUnit;
    }

    public class FlowInput {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    @InvocableMethod(
        label='Finalize Order Commercial Net for Assetization'
        description='Aligns OrderItem unit prices to commercial net before createOrUpdateAssetFromOrder'
        category='Revenue'
    )
    public static void finalizeForAssetization(List<FlowInput> inputs) {
        if (inputs == null) {
            return;
        }
        for (FlowInput input : inputs) {
            if (input?.orderId != null) {
                finalizeOrderForAssetization(input.orderId);
            }
        }
    }
}
