/**
 * @description Unit tests for PartnerMarginDispatcher.resolve, covering Discount and
 *              Guaranteed Margin partner pricing models, missing-model warnings,
 *              product-type band selection, Fortra-originated non-orig percents, and
 *              additive multi-partner margin behavior.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class PartnerMarginDispatcherTest {

    static final Id BILLING = '001000000000001AAA';
    static final Id RESELLER = '001000000000002AAA';

    /**
     * @description Verifies an unrecognized pricing model name causes resolve to log a SKIP
     *              and return null.
     */
    @IsTest
    static void resolve_unknownModelReturnsNull() {
        System.assertEquals(null, PartnerMarginDispatcher.resolve(
            'Bogus Model', BILLING, 'New', null, null, null,
            new Map<Id, List<Partner_Pricing_Model__c>>(), new Map<Id, String>(),
            'U', 'SG', 'SC', 1000, 'Software'),
            'unknown model -> null (shell logs SKIP + returns)');
    }

    /**
     * @description Verifies a Discount request with a configured billing partner but no matching
     *              pricing model leaves the price unchanged, produces no margin detail, and emits
     *              a warning naming the partner (D-PARTNER-1).
     */
    @IsTest
    static void resolve_discountNoModelLeavesPriceUnchanged() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'New', null, null, null,
            new Map<Id, List<Partner_Pricing_Model__c>>(), new Map<Id, String>{ BILLING => 'ACME' },
            'U', 'SG', 'SC', 1000, 'Software');
        System.assertNotEquals(null, r, 'Discount returns a result');
        System.assertEquals(1000, r.adjustedPrice, 'no matching model -> no discount');
        System.assertEquals(0, r.detailMaps.size(), 'no model -> no margin detail');
        System.assertEquals('Missing partner pricing model for: ACME', r.warning,
            'D-PARTNER-1: billing partner configured but no model -> warning names it');
    }

    /**
     * @description Verifies a Guaranteed Margin request with no pricing models yields a 0% total
     *              and no margin details.
     */
    @IsTest
    static void resolve_guaranteedMarginNoModelsNoMargins() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'New', RESELLER, null, null,
            new Map<Id, List<Partner_Pricing_Model__c>>(), new Map<Id, String>(),
            'U', 'SG', 'SC', 1000, 'Software');
        System.assertNotEquals(null, r, 'GM returns a result');
        System.assertEquals(0, r.totalPercent, 'no models -> 0% total');
        System.assertEquals(0, r.detailMaps.size(), 'no models -> no margin details');
    }

    static final Id DISTRIB = '001000000000003AAA';
    static final Id REFERRAL = '001000000000004AAA';

    /**
     * @description Wraps a single pricing model under a partner Id. The model's solution fields are
     *              left blank so selectBestModelForLine returns it via the all-blank fallback when
     *              the selectors are passed null.
     * @param partnerId the partner Id to key the model list under
     * @param model the Partner_Pricing_Model__c to associate with the partner
     * @return a map of partner Id to a single-element list containing the given model
     */
    private static Map<Id, List<Partner_Pricing_Model__c>> modelsFor(Id partnerId, Partner_Pricing_Model__c model) {
        return new Map<Id, List<Partner_Pricing_Model__c>>{ partnerId => new List<Partner_Pricing_Model__c>{ model } };
    }

    /**
     * @description Finds the margin detail map for a given partner Id within a resolve Result.
     * @param r the PartnerMarginDispatcher.Result whose detailMaps are searched
     * @param partnerId the partner Id whose detail map is sought
     * @return the matching detail map, or null if no detail exists for the partner
     */
    private static Map<String, Object> detailById(PartnerMarginDispatcher.Result r, Id partnerId) {
        Map<String, Object> match = null;
        for (Map<String, Object> d : r.detailMaps) {
            if (d.get('partnerId') == partnerId) {
                match = d;
            }
        }
        return match;
    }

    /**
     * @description Verifies a Discount request with a matching Software model applies the software
     *              percent to the price, records the total percent, and builds a single billing-
     *              partner detail map with no warning.
     */
    @IsTest
    static void resolve_discountMatchingModelAppliesPercentAndBuildsDetail() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'New', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(Software_Percent__c = 20)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'Software');
        System.assertEquals(800.00, r.adjustedPrice, '1000 less 20% discount = 800.00');
        System.assertEquals(20, r.totalPercent, 'total percent = the 20% discount');
        System.assertEquals(1, r.detailMaps.size(), 'one billing-partner detail');
        Map<String, Object> d = r.detailMaps[0];
        System.assertEquals(BILLING, d.get('partnerId'), 'detail partnerId');
        System.assertEquals('ACME', d.get('partnerName'), 'detail partnerName from names map');
        System.assertEquals('Billing Partner', d.get('partnerRole'), 'discount detail role');
        System.assertEquals(20, (Decimal) d.get('marginPercent'), 'detail marginPercent');
        System.assertEquals(null, r.warning, 'D-PARTNER-1: matching model -> no warning');
    }

    /**
     * @description Verifies mixed participation (D-PARTNER-1): when one partner has a model and one
     *              does not, the warning names only the model-less participating partner while
     *              pricing from the partner with a model still applies.
     */
    @IsTest
    static void resolve_guaranteedMarginWarnsOnlyMissingModelPartner() {
        Map<Id, List<Partner_Pricing_Model__c>> models = new Map<Id, List<Partner_Pricing_Model__c>>{
            BILLING => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 15) }
        };
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'New', RESELLER, null, null,
            models, new Map<Id, String>{ BILLING => 'ACME', RESELLER => 'RES' },
            null, null, null, 1000, 'Software');
        System.assertEquals('Missing partner pricing model for: RES', r.warning,
            'only the model-less participating partner (reseller) is named');
        System.assertEquals(15, r.totalPercent, 'billing 15% still applies');
    }

    /**
     * @description Verifies that when a model exists but the product type maps to a 0% band, the
     *              price is unchanged, no detail is built, and no missing-model warning is emitted
     *              (D-PARTNER-1).
     */
    @IsTest
    static void resolve_discountModelPresentButZeroPercentNoDetail() {
        // Model exists but the productType maps to the switch's else -> 0% -> price unchanged, no detail.
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'New', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(Software_Percent__c = 20)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'Hardware');
        System.assertEquals(1000, r.adjustedPrice, 'unmapped productType -> 0% -> price unchanged');
        System.assertEquals(0, r.totalPercent, '0% total');
        System.assertEquals(0, r.detailMaps.size(), 'selectedModel != null but 0% -> no detail');
        System.assertEquals(null, r.warning, 'D-PARTNER-1: model present (just 0% for this type) is NOT a missing-model warning');
    }

    /**
     * @description Verifies a Discount request for the New Maintenance product type reads the
     *              New_Maintenance_Percent__c field and applies that band to the price.
     */
    @IsTest
    static void resolve_discountNewMaintenanceProductTypeUsesMaintField() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'New', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(New_Maintenance_Percent__c = 25)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'New Maintenance');
        System.assertEquals(750.00, r.adjustedPrice, 'New Maintenance productType reads New_Maintenance_Percent__c = 25% -> 750.00');
        System.assertEquals(25, r.totalPercent, '25% New Maintenance band');
    }

    /**
     * @description Verifies a Discount request on a Fortra Originated deal uses the non-originating
     *              software percent rather than the standard software percent.
     */
    @IsTest
    static void resolve_discountFortraOriginatedUsesNonOrigPercent() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Discount', BILLING, 'Fortra Originated', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(Software_Percent__c = 20, Non_Orig_Software_Pct__c = 30)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'Software');
        System.assertEquals(700.00, r.adjustedPrice, 'Fortra Originated -> Non_Orig 30% -> 700.00');
        System.assertEquals(30, r.totalPercent, 'Non-originating 30% wins for Fortra Originated deal');
    }

    /**
     * @description Verifies a Guaranteed Margin request sums the software percents across the
     *              billing and reseller partners additively, applies the combined discount, and
     *              builds a role-labeled detail per participating partner.
     */
    @IsTest
    static void resolve_guaranteedMarginAdditiveAcrossPartners() {
        Map<Id, List<Partner_Pricing_Model__c>> models = new Map<Id, List<Partner_Pricing_Model__c>>{
            BILLING => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 15) },
            RESELLER => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 10) }
        };
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'New', RESELLER, null, null,
            models, new Map<Id, String>{ BILLING => 'ACME', RESELLER => 'RES' },
            null, null, null, 1000, 'Software');
        System.assertEquals(750.00, r.adjustedPrice, 'additive 15%+10% = 25% -> 1000 x 0.75 = 750.00');
        System.assertEquals(25, r.totalPercent, 'total percent = 15 + 10');
        System.assertEquals(2, r.detailMaps.size(), 'one detail per participating partner');
        Map<String, Object> billingDetail = detailById(r, BILLING);
        Map<String, Object> resellerDetail = detailById(r, RESELLER);
        System.assertEquals('Billing Partner', billingDetail.get('partnerRole'), 'billing role');
        System.assertEquals(15, (Decimal) billingDetail.get('marginPercent'), 'billing margin 15');
        System.assertEquals('Reseller', resellerDetail.get('partnerRole'), 'reseller role resolved');
        System.assertEquals(10, (Decimal) resellerDetail.get('marginPercent'), 'reseller margin 10');
    }

    /**
     * @description Verifies a Guaranteed Margin request excludes a zero-margin partner from the
     *              total percent and produces no detail for it, leaving only the billing partner's
     *              margin and detail.
     */
    @IsTest
    static void resolve_guaranteedMarginExcludesZeroMarginPartner() {
        Map<Id, List<Partner_Pricing_Model__c>> models = new Map<Id, List<Partner_Pricing_Model__c>>{
            BILLING => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 15) },
            RESELLER => new List<Partner_Pricing_Model__c>{ new Partner_Pricing_Model__c(Software_Percent__c = 0) }
        };
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'New', RESELLER, null, null,
            models, new Map<Id, String>{ BILLING => 'ACME', RESELLER => 'RES' },
            null, null, null, 1000, 'Software');
        System.assertEquals(850.00, r.adjustedPrice, 'only billing 15% counts -> 1000 x 0.85 = 850.00');
        System.assertEquals(15, r.totalPercent, 'zero-margin reseller excluded from total');
        System.assertEquals(1, r.detailMaps.size(), 'zero-margin partner produces no detail');
        System.assertEquals(BILLING, r.detailMaps[0].get('partnerId'), 'the surviving detail is the billing partner');
    }

    /**
     * @description Verifies a Guaranteed Margin request on a Fortra Originated deal uses the
     *              non-originating software percent for the margin calculation.
     */
    @IsTest
    static void resolve_guaranteedMarginFortraOriginatedUsesNonOrig() {
        PartnerMarginDispatcher.Result r = PartnerMarginDispatcher.resolve(
            'Guaranteed Margin', BILLING, 'Fortra Originated', null, null, null,
            modelsFor(BILLING, new Partner_Pricing_Model__c(Software_Percent__c = 20, Non_Orig_Software_Pct__c = 30)),
            new Map<Id, String>{ BILLING => 'ACME' },
            null, null, null, 1000, 'Software');
        System.assertEquals(700.00, r.adjustedPrice, 'GM Fortra Originated -> Non_Orig 30% -> 700.00');
        System.assertEquals(30, r.totalPercent, 'Non-originating 30% margin');
    }
}