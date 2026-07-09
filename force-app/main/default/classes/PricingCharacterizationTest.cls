/**
 * Characterization tests for the live partner-margin seams (PartnerPricingServiceV2).
 *
 * These PIN the CURRENT behavior of the pure, public-static pricing methods — including the
 * known E-04 quirk (Fortra-Originated + null Non_Orig -> 0%). A Wave-3 consolidation that
 * changes any pinned value MUST fail here first, forcing an explicit, documented decision
 * rather than a silent regression. No DML, no RCA runtime — models are built in memory.
 *
 * Ref: docs/pricing-refactor/PRICING_REFACTOR_PLAN.md  (INV-5, INV-6/E-04, D-11/D-12, Wave 0 Step 0.7)
 */
@isTest
private class PricingCharacterizationTest {

    // Standard (Channel-Originated) percents populated; Non-Originating left NULL on purpose (E-04).
    private static Partner_Pricing_Model__c baseModel() {
        return new Partner_Pricing_Model__c(
            Software_Percent__c            = 20,
            New_Maintenance_Percent__c     = 25,
            Renewal_Maintenance_Percent__c = 22,
            Subscription_Percent__c        = 18,
            Services_Percent__c            = 10
        );
    }

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

    @isTest
    static void marginForProductType_nullModelOrBlankOrUnknownType_returnsZero() {
        System.assertEquals(0, PartnerPricingServiceV2.getMarginForProductType(null, 'Software', 'Channel Originated'),
            'Null model -> 0');
        System.assertEquals(0, PartnerPricingServiceV2.getMarginForProductType(baseModel(), '', 'Channel Originated'),
            'Blank product type -> 0');
        System.assertEquals(0, PartnerPricingServiceV2.getMarginForProductType(baseModel(), 'Widgets', 'Channel Originated'),
            'Unknown product type -> 0 (when-else)');
    }

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

    @isTest
    static void discountModel_and_guardrails() {
        System.assertEquals(800.00, PartnerPricingServiceV2.calculateDiscountPrice(1000, 20),
            'Discount: 1000 x (1 - 0.20) = 800');
        System.assertEquals(1000, PartnerPricingServiceV2.calculateDiscountPrice(1000, 0),
            'Zero discount returns list price');
        System.assertEquals(null, PartnerPricingServiceV2.calculateDiscountPrice(null, 20),
            'Null list price passes through');
    }

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
