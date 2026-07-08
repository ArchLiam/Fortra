/**
 * @description Partner-pricing dispatch extracted verbatim from PartnerPricingPrehookV2.processLineItem
 *              (Wave-2 hook-thinning, round-4 incr 3). Resolves the adjusted price + total percent +
 *              margin-detail maps for a line under the Discount or Guaranteed-Margin model. The margin
 *              MATH stays in PartnerPricingServiceV2; participation resolution reuses the already-
 *              extracted PartnerParticipationResolver. Builds the detail maps directly (same shape as
 *              the hook's PartnerMarginDetail.toMap()) so this class stays decoupled from that inner
 *              type and from QuoteHeaderData — the hook shell threads in primitives. No SOQL/DML/context.
 */
public with sharing class PartnerMarginDispatcher {

    private static final String MODEL_GUARANTEED_MARGIN = 'Guaranteed Margin';
    private static final String MODEL_DISCOUNT = 'Discount';

    public class Result {
        public Decimal adjustedPrice;
        public Decimal totalPercent;
        public List<Map<String, Object>> detailMaps;
        public Result(Decimal adjustedPrice, Decimal totalPercent, List<Map<String, Object>> detailMaps) {
            this.adjustedPrice = adjustedPrice;
            this.totalPercent = totalPercent;
            this.detailMaps = detailMaps;
        }
    }

    /** @description Null return = unknown pricing model (shell logs SKIP + returns, as before). */
    public static Result resolve(
        String partnerPricingModel,
        Id billingPartnerId,
        String dealType,
        Id resellerId,
        Id distributorId,
        Id referralPartnerId,
        Map<Id, List<Partner_Pricing_Model__c>> partnerModels,
        Map<Id, String> partnerNames,
        String unit,
        String solutionGroup,
        String solutionCategory,
        Decimal currentPrice,
        String productType
    ) {
        Decimal adjustedPrice = currentPrice;
        Decimal totalPercent = 0;
        List<Map<String, Object>> detailMaps = new List<Map<String, Object>>();

        if (partnerPricingModel == MODEL_DISCOUNT) {
            List<Partner_Pricing_Model__c> billingPartnerModels = partnerModels.get(billingPartnerId);
            Partner_Pricing_Model__c selectedModel = PartnerPricingServiceV2.selectBestModelForLine(
                billingPartnerModels,
                unit,
                solutionGroup,
                solutionCategory
            );

            Decimal discountPercent = PartnerPricingServiceV2.getMarginForProductType(
                selectedModel,
                productType,
                dealType
            );
            adjustedPrice = PartnerPricingServiceV2.calculateDiscountPrice(currentPrice, discountPercent);
            totalPercent = discountPercent;

            if (selectedModel != null && discountPercent > 0) {
                detailMaps.add(detail(
                    billingPartnerId,
                    partnerNames.get(billingPartnerId),
                    'Billing Partner',
                    discountPercent
                ));
            }
        } else if (partnerPricingModel == MODEL_GUARANTEED_MARGIN) {
            List<Decimal> allMargins = new List<Decimal>();

            for (Id partnerId : PartnerParticipationResolver.collectPartnerIds(
                    billingPartnerId, true, resellerId, distributorId, referralPartnerId)) {
                Partner_Pricing_Model__c selectedModel = PartnerPricingServiceV2.selectBestModelForLine(
                    partnerModels.get(partnerId),
                    unit,
                    solutionGroup,
                    solutionCategory
                );

                Decimal margin = PartnerPricingServiceV2.getMarginForProductType(
                    selectedModel,
                    productType,
                    dealType
                );

                if (margin != null && margin > 0) {
                    allMargins.add(margin);
                    detailMaps.add(detail(
                        partnerId,
                        partnerNames.get(partnerId),
                        PartnerParticipationResolver.resolvePartnerRole(
                            partnerId, billingPartnerId, resellerId, distributorId, referralPartnerId),
                        margin
                    ));
                    totalPercent += margin;
                }
            }

            adjustedPrice = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(currentPrice, allMargins);
        } else {
            return null;
        }

        return new Result(adjustedPrice, totalPercent, detailMaps);
    }

    // Byte-identical to the hook's PartnerMarginDetail.toMap() key order/shape.
    private static Map<String, Object> detail(Id partnerId, String partnerName, String partnerRole, Decimal marginPercent) {
        return new Map<String, Object>{
            'partnerId' => partnerId,
            'partnerName' => partnerName,
            'partnerRole' => partnerRole,
            'marginPercent' => marginPercent
        };
    }
}
