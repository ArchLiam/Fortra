/**
 * @description Characterization tests that pin the current behavior of the pure, public-static
 *              partner-margin methods on PartnerPricingServiceV2, so any consolidation that
 *              changes a pinned value fails here first and forces an explicit decision. Models
 *              are built in memory with no DML and no RCA runtime.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class PricingCharacterizationTest {

    /**
     * @description Builds an in-memory pricing model with standard (Channel-Originated) percents
     *              populated while deliberately leaving the Non-Originating percents null.
     * @return A Partner_Pricing_Model__c seeded with standard percents and null Non_Orig_* fields.
     */
    private static Partner_Pricing_Model__c baseModel() {
        return new Partner_Pricing_Model__c(
            Software_Percent__c            = 20,
            New_Maintenance_Percent__c     = 25,
            Renewal_Maintenance_Percent__c = 22,
            Subscription_Percent__c        = 18,
            Services_Percent__c            = 10
        );
    }

    /**
     * @description Verifies that a Channel-Originated line reads each product type's standard
     *              percent field (Software, Subscription, New Maintenance).
     */
    @isTest
    static void marginForProductType_channelOriginated_usesStandardPercents() {
        Partner_Pricing_Model__c m = baseModel();
        System.assertEquals(20, PartnerPricingServiceV2.getMarginForProductType(m, 'Software', 'Channel Originated'),
            'Channel-originated Software must read Software_Percent__c');
        System.assertEquals(18, PartnerPricingServiceV2.getMarginForProductType(m, 'Subscription', 'Channel Originated'),
            'Channel-originated Subscription must read Subscription_Percent__c');
        System.assertEquals(25, PartnerPricingServiceV2.getMarginForProductType(m, 'New Maintenance', 'Channel Originated'),
            'Channel-originated New Maintenance must read New_Maintenance_Percent__c');
    }

    /**
     * @description Verifies the E-04 fix: a Fortra-Originated line with a null Non_Orig_* percent
     *              falls back to the standard (catalog) percent, while a model with both the
     *              Non_Orig and standard percents null still yields 0.
     */
    @isTest
    static void marginForProductType_fortraOriginated_nullNonOrig_fallsBackToCatalog_E04Fixed() {
        // E-04 FIX (Wave 3b, "catalog" decision): Fortra-Originated + null Non_Orig_* now falls back to the
        // standard (catalog) percent instead of silently returning 0%. (This test previously asserted 0.)
        Partner_Pricing_Model__c m = baseModel(); // Non_Orig_* null; standard Software=20, Subscription=18
        System.assertEquals(20, PartnerPricingServiceV2.getMarginForProductType(m, 'Software', 'Fortra Originated'),
            'E-04 fixed: null Non_Orig_Software falls back to catalog Software_Percent__c (20)');
        System.assertEquals(18, PartnerPricingServiceV2.getMarginForProductType(m, 'Subscription', 'Fortra Originated'),
            'E-04 fixed: null Non_Orig_Subscription falls back to catalog Subscription_Percent__c (18)');
        // Both null (no Non_Orig AND no standard percent) still yields 0.
        Partner_Pricing_Model__c empty = new Partner_Pricing_Model__c();
        System.assertEquals(0, PartnerPricingServiceV2.getMarginForProductType(empty, 'Software', 'Fortra Originated'),
            'null Non_Orig AND null standard -> 0');
    }

    /**
     * @description Verifies that a Fortra-Originated line reads the populated Non_Orig_* percent
     *              fields in preference to the standard catalog percents.
     */
    @isTest
    static void marginForProductType_fortraOriginated_populatedNonOrig_usesNonOrig() {
        Partner_Pricing_Model__c m = baseModel();
        m.Non_Orig_Software_Pct__c     = 12;
        m.Non_Orig_Subscription_Pct__c = 9;
        System.assertEquals(12, PartnerPricingServiceV2.getMarginForProductType(m, 'Software', 'Fortra Originated'),
            'Fortra-Originated Software reads Non_Orig_Software_Pct__c when populated');
        System.assertEquals(9, PartnerPricingServiceV2.getMarginForProductType(m, 'Subscription', 'Fortra Originated'),
            'Fortra-Originated Subscription reads Non_Orig_Subscription_Pct__c when populated');
    }

    /**
     * @description Verifies the guardrails that return 0 when the model is null, the product type
     *              is blank, or the product type is unrecognized (when-else branch).
     */
    @isTest
    static void marginForProductType_nullModelOrBlankOrUnknownType_returnsZero() {
        System.assertEquals(0, PartnerPricingServiceV2.getMarginForProductType(null, 'Software', 'Channel Originated'),
            'Null model -> 0');
        System.assertEquals(0, PartnerPricingServiceV2.getMarginForProductType(baseModel(), '', 'Channel Originated'),
            'Blank product type -> 0');
        System.assertEquals(0, PartnerPricingServiceV2.getMarginForProductType(baseModel(), 'Widgets', 'Channel Originated'),
            'Unknown product type -> 0 (when-else)');
    }

    /**
     * @description Verifies the guaranteed-margin calculation applies margins additively and
     *              honors its guardrails: null list price passes through, an empty margin list
     *              returns the list price, and total margin caps at 100% so the price floors at 0.
     */
    @isTest
    static void guaranteedMargin_additive_and_guardrails() {
        System.assertEquals(750.00, PartnerPricingServiceV2.calculateGuaranteedMarginPrice(1000, new List<Decimal>{15, 10}),
            'Additive: 1000 x (1 - 0.25) = 750');
        System.assertEquals(null, PartnerPricingServiceV2.calculateGuaranteedMarginPrice(null, new List<Decimal>{10}),
            'Null list price passes through');
        System.assertEquals(1000, PartnerPricingServiceV2.calculateGuaranteedMarginPrice(1000, new List<Decimal>()),
            'Empty margins -> list price');
        System.assertEquals(0.00, PartnerPricingServiceV2.calculateGuaranteedMarginPrice(1000, new List<Decimal>{120}),
            'Total margin caps at 100% -> price floors at 0');
    }

    /**
     * @description Verifies the discount-price calculation and its guardrails: a positive discount
     *              reduces the list price, a zero discount returns the list price, and a null list
     *              price passes through.
     */
    @isTest
    static void discountModel_and_guardrails() {
        System.assertEquals(800.00, PartnerPricingServiceV2.calculateDiscountPrice(1000, 20),
            'Discount: 1000 x (1 - 0.20) = 800');
        System.assertEquals(1000, PartnerPricingServiceV2.calculateDiscountPrice(1000, 0),
            'Zero discount returns list price');
        System.assertEquals(null, PartnerPricingServiceV2.calculateDiscountPrice(null, 20),
            'Null list price passes through');
    }

    /**
     * @description Verifies the model-selection hierarchy where Solution Category beats Group beats
     *              Unit beats the all-blank default, that a non-matching line falls back to the
     *              default model, and that an empty candidate list returns null.
     */
    @isTest
    static void selectBestModel_hierarchy_categoryOverGroupOverUnitOverDefault() {
        Partner_Pricing_Model__c cat  = new Partner_Pricing_Model__c(Solution_Category__c = 'SecureFileTransfer', Software_Percent__c = 1);
        Partner_Pricing_Model__c grp  = new Partner_Pricing_Model__c(Solution_Group__c = 'Managed',              Software_Percent__c = 2);
        Partner_Pricing_Model__c unit = new Partner_Pricing_Model__c(Unit__c = 'License',                        Software_Percent__c = 3);
        Partner_Pricing_Model__c def  = new Partner_Pricing_Model__c(Software_Percent__c = 4);
        List<Partner_Pricing_Model__c> models = new List<Partner_Pricing_Model__c>{ cat, grp, unit, def };

        System.assertEquals(1, PartnerPricingServiceV2.selectBestModelForLine(models, 'License', 'Managed', 'SecureFileTransfer').Software_Percent__c,
            'Solution Category match wins the hierarchy');
        System.assertEquals(4, PartnerPricingServiceV2.selectBestModelForLine(models, 'Other', 'Other', 'Other').Software_Percent__c,
            'Falls back to the all-blank default model');
        System.assertEquals(null, PartnerPricingServiceV2.selectBestModelForLine(new List<Partner_Pricing_Model__c>(), 'x', 'y', 'z'),
            'Empty candidate list -> null');
    }
}