/**
 * @description Test class for PartnerPricingServiceV2
 * @author Marc DeBrey
 * @date December 2025
 */
@isTest
private class PartnerPricingServiceV2Test {

    @TestSetup
    static void setupTestData() {
        // Create test Accounts (Partners)
        Account partnerA = new Account(
            Name = 'Test Partner A',
            Type = 'Partner'
        );
        Account partnerB = new Account(
            Name = 'Test Partner B',
            Type = 'Partner'
        );
        Account partnerNoPricing = new Account(
            Name = 'Partner No Pricing',
            Type = 'Partner'
        );
        insert new List<Account>{ partnerA, partnerB, partnerNoPricing };

        // Create Partner Pricing Models for Partner A (both models)
        Partner_Pricing_Model__c modelAGuaranteed = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Guaranteed Margin',
            Is_Active__c = true,
            Is_Default__c = true,
            Software_Percent__c = 15.00,
            New_Maintenance_Percent__c = 12.00,
            Renewal_Maintenance_Percent__c = 10.00,
            Subscription_Percent__c = 18.00,
            Services_Percent__c = 20.00,
            Non_Orig_Software_Pct__c = 9.00,
            Non_Orig_New_Maint_Pct__c = 7.00,
            Non_Orig_Ren_Maint_Pct__c = 6.00,
            Non_Orig_Subscription_Pct__c = 11.00,
            Non_Orig_Services_Pct__c = 13.00
        );

        Partner_Pricing_Model__c modelADiscount = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = false,
            Software_Percent__c = 25.00,
            New_Maintenance_Percent__c = 22.00,
            Renewal_Maintenance_Percent__c = 20.00,
            Subscription_Percent__c = 28.00,
            Services_Percent__c = 30.00,
            Non_Orig_Software_Pct__c = 19.00,
            Non_Orig_New_Maint_Pct__c = 17.00,
            Non_Orig_Ren_Maint_Pct__c = 15.00,
            Non_Orig_Subscription_Pct__c = 21.00,
            Non_Orig_Services_Pct__c = 23.00
        );

        // Create Partner Pricing Model for Partner B (only Guaranteed Margin)
        Partner_Pricing_Model__c modelBGuaranteed = new Partner_Pricing_Model__c(
            Account__c = partnerB.Id,
            Model_Type__c = 'Guaranteed Margin',
            Is_Active__c = true,
            Is_Default__c = true,
            Software_Percent__c = 10.00,
            New_Maintenance_Percent__c = 8.00,
            Renewal_Maintenance_Percent__c = 6.00,
            Subscription_Percent__c = 12.00,
            Services_Percent__c = 15.00,
            Non_Orig_Software_Pct__c = 5.00,
            Non_Orig_New_Maint_Pct__c = 4.00,
            Non_Orig_Ren_Maint_Pct__c = 3.00,
            Non_Orig_Subscription_Pct__c = 6.00,
            Non_Orig_Services_Pct__c = 7.00
        );

        insert new List<Partner_Pricing_Model__c>{ modelAGuaranteed, modelADiscount, modelBGuaranteed };
    }

    @isTest
    static void testGetMarginForProductType_AllTypes() {
        Partner_Pricing_Model__c model = getTestModel('Test Partner A', 'Guaranteed Margin');

        Test.startTest();
        Decimal softwareMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Software', null);
        Decimal perpetualMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Perpetual', null);
        Decimal newMaintMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'New Maintenance', null);
        Decimal renewalMaintMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Renewal Maintenance', null);
        Decimal subscriptionMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Subscription', null);
        Decimal saasMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'SaaS Subscription', null);
        Decimal servicesMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Services', null);
        Decimal profServiceMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Professional Service', null);
        Decimal renewalServiceMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Renewal Services', null);
        Decimal unknownMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Unknown Type', null);
        Test.stopTest();

        System.assertEquals(15.00, softwareMargin, 'Software margin should be 15');
        System.assertEquals(15.00, perpetualMargin, 'Perpetual should map to Software');
        System.assertEquals(12.00, newMaintMargin, 'New Maintenance margin should be 12');
        System.assertEquals(10.00, renewalMaintMargin, 'Renewal Maintenance margin should be 10');
        System.assertEquals(18.00, subscriptionMargin, 'Subscription margin should be 18');
        System.assertEquals(18.00, saasMargin, 'SaaS Subscription should map to Subscription');
        System.assertEquals(20.00, servicesMargin, 'Services margin should be 20');
        System.assertEquals(20.00, profServiceMargin, 'Professional Service should map to Services');
        System.assertEquals(20.00, renewalServiceMargin, 'Renewal Services should map to Services');
        System.assertEquals(0, unknownMargin, 'Unknown type should return 0');
    }

    @isTest
    static void testGetMarginForProductType_NullParams() {
        Partner_Pricing_Model__c model = getTestModel('Test Partner A', 'Guaranteed Margin');

        Test.startTest();
        Decimal margin1 = PartnerPricingServiceV2.getMarginForProductType(null, 'Software', null);
        Decimal margin2 = PartnerPricingServiceV2.getMarginForProductType(model, null, null);
        Decimal margin3 = PartnerPricingServiceV2.getMarginForProductType(model, '', null);
        Test.stopTest();

        System.assertEquals(0, margin1, 'Null model should return 0');
        System.assertEquals(0, margin2, 'Null product type should return 0');
        System.assertEquals(0, margin3, 'Empty product type should return 0');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_SingleMargin() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 15.00 }; // 15%

        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // ADDITIVE formula with single margin: 1000 * (1 - 0.15) = 1000 * 0.85 = 850.00
        System.assertEquals(850.00, result, 'Single margin calculation incorrect');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_AdditiveMargins() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 15.00, 10.00 }; // 15% + 10% = 25%

        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // ADDITIVE formula: 1000 * (1 - (0.15 + 0.10)) = 1000 * (1 - 0.25) = 1000 * 0.75 = 750.00
        System.assertEquals(750.00, result, 'ADDITIVE margin calculation incorrect');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_MultipleMargins() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 15.00, 10.00, 5.00 }; // 15% + 10% + 5% = 30%

        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // ADDITIVE formula: 1000 * (1 - (0.15 + 0.10 + 0.05)) = 1000 * (1 - 0.30) = 700.00
        System.assertEquals(700.00, result, 'Multiple ADDITIVE margin calculation incorrect');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_CapAt100Percent() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 60.00, 50.00 }; // 60% + 50% = 110% (capped at 100%)

        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // ADDITIVE formula with cap: 1000 * (1 - 1.00) = 0.00 (capped at 100%)
        System.assertEquals(0.00, result, 'Should cap at 100% and return 0');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_ZeroMargin() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 0, 15.00, 0 };

        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // Expected: 1000 * 0.85 = 850.00 (zero margins are skipped)
        System.assertEquals(850.00, result, 'Zero margins should be skipped');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_NullPrice() {
        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(null, new List<Decimal>{ 15.00 });
        Test.stopTest();

        System.assertEquals(null, result, 'Null price should return null');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_ZeroPrice() {
        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(0, new List<Decimal>{ 15.00 });
        Test.stopTest();

        System.assertEquals(0, result, 'Zero price should return zero');
    }

    @isTest
    static void testCalculateDiscountPrice_Standard() {
        Decimal listPrice = 1000.00;
        Decimal discountPercent = 20.00;

        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateDiscountPrice(listPrice, discountPercent);
        Test.stopTest();

        // Expected: 1000 * (1 - 0.20) = 800.00
        System.assertEquals(800.00, result, 'Discount calculation incorrect');
    }

    @isTest
    static void testCalculateDiscountPrice_ZeroDiscount() {
        Decimal listPrice = 1000.00;
        Decimal discountPercent = 0;

        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateDiscountPrice(listPrice, discountPercent);
        Test.stopTest();

        System.assertEquals(1000.00, result, 'Zero discount should return original price');
    }

    @isTest
    static void testCalculateDiscountPrice_NullParams() {
        Test.startTest();
        Decimal result1 = PartnerPricingServiceV2.calculateDiscountPrice(null, 20.00);
        Decimal result2 = PartnerPricingServiceV2.calculateDiscountPrice(1000.00, null);
        Test.stopTest();

        System.assertEquals(null, result1, 'Null price should return null');
        System.assertEquals(1000.00, result2, 'Null discount should return original price');
    }

    @isTest
    static void testCalculateDiscountPrice_Rounding() {
        Decimal listPrice = 99.99;
        Decimal discountPercent = 33.33;

        Test.startTest();
        Decimal result = PartnerPricingServiceV2.calculateDiscountPrice(listPrice, discountPercent);
        Test.stopTest();

        // Expected: 99.99 * (1 - 0.3333) = 99.99 * 0.6667 = 66.66 (rounded)
        System.assertEquals(66.66, result, 'Rounding should produce 66.66');
    }

    @isTest
    static void testEffectiveDateFiltering() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        // Create an expired model
        Partner_Pricing_Model__c expiredModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Guaranteed Margin',
            Is_Active__c = true,
            Is_Default__c = false,
            Software_Percent__c = 99.00,
            Effective_Start_Date__c = Date.today().addDays(-30),
            Effective_End_Date__c = Date.today().addDays(-1)
        );
        insert expiredModel;

        // Create a future model
        Partner_Pricing_Model__c futureModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = false,
            Software_Percent__c = 88.00,
            Effective_Start_Date__c = Date.today().addDays(30),
            Effective_End_Date__c = Date.today().addDays(60)
        );
        insert futureModel;

        Test.startTest();
        List<Partner_Pricing_Model__c> candidates = PartnerPricingServiceV2.getPricingModelCandidates(
            new Set<Id>{ partnerA.Id },
            'Guaranteed Margin'
        ).get(partnerA.Id);
        Test.stopTest();

        System.assertNotEquals(null, candidates, 'Should find valid candidates');
        System.assertEquals(1, candidates.size(), 'Expired records should not be returned');
        System.assertEquals(15.00, candidates[0].Software_Percent__c, 'Should return current model, not expired');
    }

    @isTest
    static void testGetPricingModelCandidates_Bulk() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        Test.startTest();
        Map<Id, List<Partner_Pricing_Model__c>> candidates = PartnerPricingServiceV2.getPricingModelCandidates(
            new Set<Id>{ partnerA.Id, partnerB.Id },
            'Guaranteed Margin'
        );
        Test.stopTest();

        System.assertEquals(2, candidates.size(), 'Should return candidate lists for both partners');
        System.assertEquals(1, candidates.get(partnerA.Id).size(), 'Partner A should have one guaranteed margin candidate');
        System.assertEquals(1, candidates.get(partnerB.Id).size(), 'Partner B should have one guaranteed margin candidate');
    }

    @isTest
    static void testGetPricingModelCandidates_EmptyInputs() {
        Test.startTest();
        Map<Id, List<Partner_Pricing_Model__c>> candidates1 = PartnerPricingServiceV2.getPricingModelCandidates(null, 'Guaranteed Margin');
        Map<Id, List<Partner_Pricing_Model__c>> candidates2 = PartnerPricingServiceV2.getPricingModelCandidates(new Set<Id>(), 'Guaranteed Margin');
        Map<Id, List<Partner_Pricing_Model__c>> candidates3 = PartnerPricingServiceV2.getPricingModelCandidates(new Set<Id>{ null }, null);
        Test.stopTest();

        System.assertEquals(0, candidates1.size(), 'Null set should return empty map');
        System.assertEquals(0, candidates2.size(), 'Empty set should return empty map');
        System.assertEquals(0, candidates3.size(), 'Null model type should return empty map');
    }

    @isTest
    static void testSelectBestModelForLine_CategoryWins() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Partner_Pricing_Model__c unitModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Unit__c = 'Cybersecurity',
            Software_Percent__c = 21.00
        );
        Partner_Pricing_Model__c groupModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Solution_Group__c = 'Data Protection',
            Software_Percent__c = 22.00
        );
        Partner_Pricing_Model__c categoryModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Solution_Category__c = 'Backup',
            Software_Percent__c = 23.00
        );
        insert new List<Partner_Pricing_Model__c>{ unitModel, groupModel, categoryModel };

        Test.startTest();
        List<Partner_Pricing_Model__c> models = PartnerPricingServiceV2.getPricingModelCandidates(
            new Set<Id>{ partnerA.Id },
            'Discount'
        ).get(partnerA.Id);
        Partner_Pricing_Model__c selectedModel = PartnerPricingServiceV2.selectBestModelForLine(
            models,
            'Cybersecurity',
            'Data Protection',
            'Backup'
        );
        Test.stopTest();

        System.assertNotEquals(null, selectedModel, 'Should find a matching model');
        System.assertEquals(categoryModel.Id, selectedModel.Id, 'Category match should win over broader hierarchy levels');
    }

    @isTest
    static void testSelectBestModelForLine_GroupFallback() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Partner_Pricing_Model__c groupModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Solution_Group__c = 'Managed Security',
            Software_Percent__c = 24.00
        );
        insert groupModel;

        Test.startTest();
        List<Partner_Pricing_Model__c> models = PartnerPricingServiceV2.getPricingModelCandidates(
            new Set<Id>{ partnerA.Id },
            'Discount'
        ).get(partnerA.Id);
        Partner_Pricing_Model__c selectedModel = PartnerPricingServiceV2.selectBestModelForLine(
            models,
            'Cybersecurity',
            'Managed Security',
            'No Match'
        );
        Test.stopTest();

        System.assertEquals(groupModel.Id, selectedModel.Id, 'Should fall back to solution group when no category match exists');
    }

    @isTest
    static void testSelectBestModelForLine_UnitFallback() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Partner_Pricing_Model__c unitModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Unit__c = 'Infrastructure',
            Software_Percent__c = 26.00
        );
        insert unitModel;

        Test.startTest();
        List<Partner_Pricing_Model__c> models = PartnerPricingServiceV2.getPricingModelCandidates(
            new Set<Id>{ partnerA.Id },
            'Discount'
        ).get(partnerA.Id);
        Partner_Pricing_Model__c selectedModel = PartnerPricingServiceV2.selectBestModelForLine(
            models,
            'Infrastructure',
            'No Match',
            'No Match'
        );
        Test.stopTest();

        System.assertEquals(unitModel.Id, selectedModel.Id, 'Should fall back to unit when broader levels are the only match');
    }

    @isTest
    static void testSelectBestModelForLine_BlankFallback() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Test.startTest();
        List<Partner_Pricing_Model__c> models = PartnerPricingServiceV2.getPricingModelCandidates(
            new Set<Id>{ partnerA.Id },
            'Discount'
        ).get(partnerA.Id);
        Partner_Pricing_Model__c selectedModel = PartnerPricingServiceV2.selectBestModelForLine(
            models,
            'No Match',
            'No Match',
            'No Match'
        );
        Test.stopTest();

        System.assertNotEquals(null, selectedModel, 'Should fall back to the generic model when no hierarchy value matches');
        System.assertEquals(null, selectedModel.Unit__c, 'Fallback model should not have Unit populated');
        System.assertEquals(null, selectedModel.Solution_Group__c, 'Fallback model should not have Solution Group populated');
        System.assertEquals(null, selectedModel.Solution_Category__c, 'Fallback model should not have Solution Category populated');
    }

    @isTest
    static void testSelectBestModelForLine_NoMatchReturnsNull() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Partner_Pricing_Model__c categoryOnlyModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Guaranteed Margin',
            Is_Active__c = true,
            Solution_Category__c = 'Email Security',
            Software_Percent__c = 12.00
        );
        insert categoryOnlyModel;

        Test.startTest();
        List<Partner_Pricing_Model__c> models = new List<Partner_Pricing_Model__c>{ categoryOnlyModel };
        Partner_Pricing_Model__c selectedModel = PartnerPricingServiceV2.selectBestModelForLine(
            models,
            'No Match',
            'No Match',
            'No Match'
        );
        Test.stopTest();

        System.assertEquals(null, selectedModel, 'Should return null when no hierarchy match and no blank fallback exist');
    }

    @isTest
    static void testSelectBestModelForLine_NewestCreatedWins() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Partner_Pricing_Model__c olderModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Solution_Group__c = 'Cloud Security',
            Software_Percent__c = 27.00
        );
        Partner_Pricing_Model__c newerModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Solution_Group__c = 'Cloud Security',
            Software_Percent__c = 29.00
        );
        insert olderModel;
        insert newerModel;

        Test.setCreatedDate(olderModel.Id, System.now().addMinutes(-10));
        Test.setCreatedDate(newerModel.Id, System.now().addMinutes(-1));

        Test.startTest();
        List<Partner_Pricing_Model__c> models = PartnerPricingServiceV2.getPricingModelCandidates(
            new Set<Id>{ partnerA.Id },
            'Discount'
        ).get(partnerA.Id);
        Partner_Pricing_Model__c selectedModel = PartnerPricingServiceV2.selectBestModelForLine(
            models,
            'No Match',
            'Cloud Security',
            'No Match'
        );
        Test.stopTest();

        System.assertEquals(newerModel.Id, selectedModel.Id, 'Newest created matching record should win same-level ties');
    }

    @isTest
    static void testGetMarginForProductType_FortraOriginatedUsesNonOriginatingFields() {
        Partner_Pricing_Model__c model = getTestModel('Test Partner A', 'Discount');

        Test.startTest();
        Decimal softwareMargin = PartnerPricingServiceV2.getMarginForProductType(
            model,
            'Software',
            'Fortra Originated'
        );
        Decimal subscriptionMargin = PartnerPricingServiceV2.getMarginForProductType(
            model,
            'Subscription',
            'Fortra Originated'
        );
        Test.stopTest();

        System.assertEquals(19.00, softwareMargin, 'Fortra Originated should use the non-originating software field');
        System.assertEquals(21.00, subscriptionMargin, 'Fortra Originated should use the non-originating subscription field');
    }

    @isTest
    static void testGetMarginForProductType_StandardFieldsUsedForOtherDealTypes() {
        Partner_Pricing_Model__c model = getTestModel('Test Partner A', 'Discount');

        Test.startTest();
        Decimal softwareMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Software', 'Partner Registered');
        Decimal servicesMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Services', null);
        Test.stopTest();

        System.assertEquals(25.00, softwareMargin, 'Non-Fortra deal types should use the standard software field');
        System.assertEquals(30.00, servicesMargin, 'Null deal type should use the standard services field');
    }

    private static Partner_Pricing_Model__c getTestModel(String accountName, String modelType) {
        return [
            SELECT Id, Account__c, Model_Type__c, Is_Active__c, Is_Default__c, CreatedDate,
                   Software_Percent__c, New_Maintenance_Percent__c, Renewal_Maintenance_Percent__c,
                   Subscription_Percent__c, Services_Percent__c,
                   Non_Orig_New_Maint_Pct__c, Non_Orig_Ren_Maint_Pct__c, Non_Orig_Services_Pct__c,
                   Non_Orig_Software_Pct__c, Non_Orig_Subscription_Pct__c,
                   Unit__c, Solution_Group__c, Solution_Category__c,
                   Effective_Start_Date__c, Effective_End_Date__c
            FROM Partner_Pricing_Model__c
            WHERE Account__r.Name = :accountName
            AND Model_Type__c = :modelType
            LIMIT 1
        ];
    }

}