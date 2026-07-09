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
        // D-PARTNER-1 (PartnerPricing SDD §6.3 / BR-007): identifies any participating partner that
        // is configured on the Quote but lacks a matching pricing model for this line. Null when all
        // participating partners resolve a model.
        public String warning;
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
        // D-PARTNER-1: participating partners configured on the Quote but missing a matching model.
        List<String> missingModelPartners = new List<String>();

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
            } else if (selectedModel == null && billingPartnerId != null) {
                // Billing partner is configured (Discount model on the Quote) but has no matching
                // pricing model for this line — SDD-required warning.
                missingModelPartners.add(partnerLabel(billingPartnerId, partnerNames));
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
                } else if (selectedModel == null) {
                    // Participating partner with no matching Guaranteed-Margin model — SDD-required warning.
                    missingModelPartners.add(partnerLabel(partnerId, partnerNames));
                }
            }

            adjustedPrice = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(currentPrice, allMargins);
        } else {
            return null;
        }

        Result r = new Result(adjustedPrice, totalPercent, detailMaps);
        if (!missingModelPartners.isEmpty()) {
            r.warning = 'Missing partner pricing model for: ' + String.join(missingModelPartners, ', ');
        }
        return r;
    }

    /** @description Display label for a partner in the missing-model warning (name, else the Id). */
    private static String partnerLabel(Id partnerId, Map<Id, String> partnerNames) {
        String partnerName = (partnerNames != null) ? partnerNames.get(partnerId) : null;
        return String.isNotBlank(partnerName) ? partnerName : String.valueOf(partnerId);
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
