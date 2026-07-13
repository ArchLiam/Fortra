/**
 * @description Resolves the adjusted price, total percent, and margin-detail maps for a line under
 *              the Discount or Guaranteed-Margin partner-pricing model. Delegates the margin math to
 *              PartnerPricingServiceV2 and participation resolution to PartnerParticipationResolver,
 *              and builds the detail maps from primitives (matching the hook's
 *              PartnerMarginDetail.toMap() shape) so it stays decoupled from the hook's inner types.
 *              Performs no SOQL, DML, or context access.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
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

    /**
     * @description Resolves partner-pricing adjustments for a single line under the Discount or
     *              Guaranteed-Margin model, returning the adjusted price, total percent, and
     *              margin-detail maps, plus an optional warning for participating partners that lack
     *              a matching model. Returns null for an unknown pricing model (the shell logs SKIP
     *              and returns).
     * @param partnerPricingModel Pricing model configured on the Quote ('Discount' or 'Guaranteed Margin').
     * @param billingPartnerId Id of the billing partner.
     * @param dealType Deal type used when selecting the applicable margin.
     * @param resellerId Id of the participating reseller partner.
     * @param distributorId Id of the participating distributor partner.
     * @param referralPartnerId Id of the participating referral partner.
     * @param partnerModels Partner pricing models keyed by partner Id.
     * @param partnerNames Partner display names keyed by partner Id.
     * @param unit Unit of measure for the line, used in model selection.
     * @param solutionGroup Solution group for the line, used in model selection.
     * @param solutionCategory Solution category for the line, used in model selection.
     * @param currentPrice Current line price to be adjusted.
     * @param productType Product type used to look up the margin/discount percent.
     * @return Result carrying the adjusted price, total percent, detail maps, and optional missing-model warning; null when the pricing model is unknown.
     */
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

    /**
     * @description Returns the display label for a partner in the missing-model warning, using the
     *              partner name when available and falling back to the partner Id.
     * @param partnerId Id of the partner to label.
     * @param partnerNames Partner display names keyed by partner Id.
     * @return The partner name when non-blank, otherwise the string form of the partner Id.
     */
    private static String partnerLabel(Id partnerId, Map<Id, String> partnerNames) {
        String partnerName = (partnerNames != null) ? partnerNames.get(partnerId) : null;
        return String.isNotBlank(partnerName) ? partnerName : String.valueOf(partnerId);
    }

    /**
     * @description Builds the margin-detail map for one participating partner, byte-identical to the
     *              key order and shape of the hook's PartnerMarginDetail.toMap().
     * @param partnerId Id of the participating partner.
     * @param partnerName Display name of the partner.
     * @param partnerRole Resolved role of the partner on the line.
     * @param marginPercent Margin or discount percent applied for the partner.
     * @return A map with partnerId, partnerName, partnerRole, and marginPercent keys.
     */
    private static Map<String, Object> detail(Id partnerId, String partnerName, String partnerRole, Decimal marginPercent) {
        return new Map<String, Object>{
            'partnerId' => partnerId,
            'partnerName' => partnerName,
            'partnerRole' => partnerRole,
            'marginPercent' => marginPercent
        };
    }
}