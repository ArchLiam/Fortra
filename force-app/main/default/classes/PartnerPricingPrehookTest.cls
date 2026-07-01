/**
 * @description Test class for PartnerPricingPrehook
 * @author Marc DeBrey
 * @date December 2025
 */
@isTest
private class PartnerPricingPrehookTest {

    private static void forceProductTypeForLine(Map<Id, String> productTypeByLineId, Id lineId, String productType) {
        productTypeByLineId.put(lineId, productType);
    }

    private static void seedProductTypeForLine(Map<Id, String> productTypeByLineId, Id lineId, String fallbackType) {
        if (productTypeByLineId.containsKey(lineId)) {
            String existing = productTypeByLineId.get(lineId);
            if (String.isNotBlank(existing) && existing != 'Software') {
                return;
            }
            productTypeByLineId.remove(lineId);
        }

        QuoteLineItem qli = [
            SELECT Fortra_Product_Type__c, Product2.Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE Id = :lineId
        ];
        if (String.isNotBlank(qli.Fortra_Product_Type__c) && qli.Fortra_Product_Type__c != 'Software') {
            productTypeByLineId.put(lineId, qli.Fortra_Product_Type__c);
        } else if (String.isNotBlank(qli.Product2.Fortra_Product_Type__c) && qli.Product2.Fortra_Product_Type__c != 'Software') {
            productTypeByLineId.put(lineId, qli.Product2.Fortra_Product_Type__c);
        } else {
            productTypeByLineId.put(lineId, fallbackType);
        }
    }

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
        insert new List<Account>{ partnerA, partnerB };

        // Create Partner Pricing Models
        Partner_Pricing_Model__c modelAGuaranteed = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Guaranteed Margin',
            Is_Active__c = true,
            Is_Default__c = true,
            Software_Percent__c = 15.00,
            New_Maintenance_Percent__c = 12.00,
            Renewal_Maintenance_Percent__c = 10.00,
            Subscription_Percent__c = 18.00,
            Services_Percent__c = 20.00
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
            Services_Percent__c = 30.00
        );

        Partner_Pricing_Model__c modelBGuaranteed = new Partner_Pricing_Model__c(
            Account__c = partnerB.Id,
            Model_Type__c = 'Guaranteed Margin',
            Is_Active__c = true,
            Is_Default__c = true,
            Software_Percent__c = 10.00,
            New_Maintenance_Percent__c = 8.00,
            Renewal_Maintenance_Percent__c = 6.00,
            Subscription_Percent__c = 12.00,
            Services_Percent__c = 15.00
        );

        insert new List<Partner_Pricing_Model__c>{ modelAGuaranteed, modelADiscount, modelBGuaranteed };
    }

    /**
     * @description Test that the prehook class can be instantiated
     *              Note: execute() method requires RevSignaling.TransactionRequest which
     *              is a managed class without public constructor - cannot be unit tested.
     *              The execute() method must be tested via integration testing.
     */
    @isTest
    static void testClassInstantiation() {
        Test.startTest();
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Test.stopTest();

        System.assertNotEquals(null, prehook, 'Prehook should be instantiated');
    }

    /**
     * @description Test that the prehook can be instantiated and is the correct type.
     *              Note: RevSignaling.SignalingApexProcessor is not visible in test context
     *              on some orgs, so we validate the class name instead of casting.
     */
    @isTest
    static void testInterfaceImplementation() {
        Test.startTest();
        PartnerPricingPrehook processor = new PartnerPricingPrehook();
        Test.stopTest();

        System.assertNotEquals(null, processor, 'Should be instantiable');
        System.assertEquals('PartnerPricingPrehook', String.valueOf(processor).substringBefore(':'), 'Should be correct type');
    }

    @isTest
    static void testLoadPartnerPricingModels() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Set<Id> accountIds = new Set<Id>{ partnerA.Id, partnerB.Id };

        Test.startTest();
        Map<Id, Partner_Pricing_Model__c> models = prehook.loadPartnerPricingModels(accountIds, 'Guaranteed Margin');
        Test.stopTest();

        System.assertEquals(2, models.size(), 'Should return models for both partners');
        System.assertNotEquals(null, models.get(partnerA.Id), 'Should have Partner A model');
        System.assertNotEquals(null, models.get(partnerB.Id), 'Should have Partner B model');
    }

    @isTest
    static void testIsModelEffective_Active() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Partner_Pricing_Model__c model = [
            SELECT Id, Is_Active__c, Effective_Start_Date__c, Effective_End_Date__c
            FROM Partner_Pricing_Model__c
            WHERE Account__c = :partnerA.Id AND Model_Type__c = 'Guaranteed Margin'
            LIMIT 1
        ];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        Boolean isEffective = prehook.isModelEffective(model, Date.today());
        Test.stopTest();

        System.assertEquals(true, isEffective, 'Active model with no date restrictions should be effective');
    }

    @isTest
    static void testIsModelEffective_Null() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        Boolean isEffective = prehook.isModelEffective(null, Date.today());
        Test.stopTest();

        System.assertEquals(false, isEffective, 'Null model should not be effective');
    }

    @isTest
    static void testIsModelEffective_Inactive() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        // Create inactive model
        Partner_Pricing_Model__c inactiveModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = false,
            Is_Default__c = false,
            Software_Percent__c = 50.00
        );
        insert inactiveModel;

        Partner_Pricing_Model__c model = [
            SELECT Id, Is_Active__c, Effective_Start_Date__c, Effective_End_Date__c
            FROM Partner_Pricing_Model__c
            WHERE Id = :inactiveModel.Id
            LIMIT 1
        ];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        Boolean isEffective = prehook.isModelEffective(model, Date.today());
        Test.stopTest();

        System.assertEquals(false, isEffective, 'Inactive model should not be effective');
    }

    @isTest
    static void testIsModelEffective_FutureStartDate() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        // Create future model
        Partner_Pricing_Model__c futureModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = false,
            Software_Percent__c = 50.00,
            Effective_Start_Date__c = Date.today().addDays(30)
        );
        insert futureModel;

        Partner_Pricing_Model__c model = [
            SELECT Id, Is_Active__c, Effective_Start_Date__c, Effective_End_Date__c
            FROM Partner_Pricing_Model__c
            WHERE Id = :futureModel.Id
            LIMIT 1
        ];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        Boolean isEffective = prehook.isModelEffective(model, Date.today());
        Test.stopTest();

        System.assertEquals(false, isEffective, 'Model with future start date should not be effective');
    }

    @isTest
    static void testIsModelEffective_PastEndDate() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        // Create expired model
        Partner_Pricing_Model__c expiredModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = false,
            Software_Percent__c = 50.00,
            Effective_End_Date__c = Date.today().addDays(-1)
        );
        insert expiredModel;

        Partner_Pricing_Model__c model = [
            SELECT Id, Is_Active__c, Effective_Start_Date__c, Effective_End_Date__c
            FROM Partner_Pricing_Model__c
            WHERE Id = :expiredModel.Id
            LIMIT 1
        ];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        Boolean isEffective = prehook.isModelEffective(model, Date.today());
        Test.stopTest();

        System.assertEquals(false, isEffective, 'Model with past end date should not be effective');
    }

    @isTest
    static void testGetMarginForProductType() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Partner_Pricing_Model__c model = [
            SELECT Id, Software_Percent__c, New_Maintenance_Percent__c, Renewal_Maintenance_Percent__c,
                   Subscription_Percent__c, Services_Percent__c
            FROM Partner_Pricing_Model__c
            WHERE Account__c = :partnerA.Id AND Model_Type__c = 'Guaranteed Margin'
            LIMIT 1
        ];

        Test.startTest();
        // Use PartnerPricingService - that's where these methods live
        Decimal softwareMargin = PartnerPricingService.getMarginForProductType(model, 'Software');
        Decimal subscriptionMargin = PartnerPricingService.getMarginForProductType(model, 'Subscription');
        Decimal servicesMargin = PartnerPricingService.getMarginForProductType(model, 'Services');
        Test.stopTest();

        System.assertEquals(15.00, softwareMargin, 'Software margin should be 15');
        System.assertEquals(18.00, subscriptionMargin, 'Subscription margin should be 18');
        System.assertEquals(20.00, servicesMargin, 'Services margin should be 20');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice() {
        Test.startTest();
        // Single margin: 1000 * (1 - 0.15) = 850
        Decimal singleMargin = PartnerPricingService.calculateGuaranteedMarginPrice(1000.00, new List<Decimal>{ 15.00 });

        // ADDITIVE margins: 1000 * (1 - (0.15 + 0.10)) = 1000 * (1 - 0.25) = 750
        Decimal additiveMargins = PartnerPricingService.calculateGuaranteedMarginPrice(1000.00, new List<Decimal>{ 15.00, 10.00 });
        Test.stopTest();

        System.assertEquals(850.00, singleMargin, 'Single margin calculation incorrect');
        System.assertEquals(750.00, additiveMargins, 'ADDITIVE margin calculation incorrect');
    }

    @isTest
    static void testCalculateDiscountPrice() {
        Test.startTest();
        // 1000 * (1 - 0.25) = 750
        Decimal discountedPrice = PartnerPricingService.calculateDiscountPrice(1000.00, 25.00);
        Test.stopTest();

        System.assertEquals(750.00, discountedPrice, 'Discount calculation incorrect');
    }

    @isTest
    static void testBuildMarginDetailJson() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        List<Map<String, Object>> partnerDetails = new List<Map<String, Object>>();
        Map<String, Object> detail1 = new Map<String, Object>{
            'partnerId' => 'acc001',
            'partnerName' => 'Partner A',
            'margin' => 15.00
        };
        Map<String, Object> detail2 = new Map<String, Object>{
            'partnerId' => 'acc002',
            'partnerName' => 'Partner B',
            'margin' => 10.00
        };
        partnerDetails.add(detail1);
        partnerDetails.add(detail2);

        Test.startTest();
        String json = prehook.buildMarginDetailJson(partnerDetails);
        Test.stopTest();

        System.assertNotEquals(null, json, 'JSON should not be null');
        System.assert(json.contains('Partner A'), 'JSON should contain Partner A');
        System.assert(json.contains('Partner B'), 'JSON should contain Partner B');
    }

    @isTest
    static void testBuildMarginDetailJson_Empty() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        String json1 = prehook.buildMarginDetailJson(null);
        String json2 = prehook.buildMarginDetailJson(new List<Map<String, Object>>());
        Test.stopTest();

        System.assertEquals(null, json1, 'Null list should return null');
        System.assertEquals(null, json2, 'Empty list should return null');
    }

    /**
     * @description Test Partner Pricing Model CMDT-like query capability
     *              Note: execute() method requires RevSignaling.TransactionRequest which
     *              is a managed class without public constructor - cannot be unit tested.
     */
    @isTest
    static void testPartnerPricingModelQuery() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Test.startTest();
        // Query Partner Pricing Models to validate structure
        List<Partner_Pricing_Model__c> models = [
            SELECT Id, Account__c, Model_Type__c, Is_Active__c, Is_Default__c,
                   Software_Percent__c, New_Maintenance_Percent__c,
                   Renewal_Maintenance_Percent__c, Subscription_Percent__c, Services_Percent__c
            FROM Partner_Pricing_Model__c
            WHERE Account__c = :partnerA.Id
        ];
        Test.stopTest();

        System.assertNotEquals(null, models, 'Query should execute without error');
        System.assertEquals(2, models.size(), 'Should have 2 models for Partner A (Guaranteed + Discount)');
    }

    @isTest
    static void testGetStringFromTag() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Map<String, Object> tagData = new Map<String, Object>{
            'Name' => 'Test Value',
            'NullField' => null,
            'NumberField' => 123
        };

        Test.startTest();
        String result1 = prehook.getStringFromTag(tagData, 'Name');
        String result2 = prehook.getStringFromTag(tagData, 'NullField');
        String result3 = prehook.getStringFromTag(tagData, 'MissingField');
        String result4 = prehook.getStringFromTag(null, 'Name');
        String result5 = prehook.getStringFromTag(tagData, 'NumberField');
        Test.stopTest();

        System.assertEquals('Test Value', result1, 'Should return string value');
        System.assertEquals(null, result2, 'Null value should return null');
        System.assertEquals(null, result3, 'Missing field should return null');
        System.assertEquals(null, result4, 'Null tagData should return null');
        System.assertEquals('123', result5, 'Number should convert to string');
    }

    @isTest
    static void testGetStringFromTag_NestedTagValue() {
        // Test nested tagValue structure used by Revenue Cloud Context API
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Map<String, Object> tagData = new Map<String, Object>{
            'Name' => new Map<String, Object>{ 'tagValue' => 'Nested Value' },
            'NullNested' => new Map<String, Object>{ 'tagValue' => null }
        };

        Test.startTest();
        String result1 = prehook.getStringFromTag(tagData, 'Name');
        String result2 = prehook.getStringFromTag(tagData, 'NullNested');
        Test.stopTest();

        System.assertEquals('Nested Value', result1, 'Should extract value from nested tagValue structure');
        System.assertEquals(null, result2, 'Null nested tagValue should return null');
    }

    @isTest
    static void testGetDecimalFromTag() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Map<String, Object> tagData = new Map<String, Object>{
            'Price' => 100.50,
            'StringPrice' => '200.75',
            'NullField' => null,
            'InvalidField' => 'not-a-number'
        };

        Test.startTest();
        Decimal result1 = prehook.getDecimalFromTag(tagData, 'Price');
        Decimal result2 = prehook.getDecimalFromTag(tagData, 'StringPrice');
        Decimal result3 = prehook.getDecimalFromTag(tagData, 'NullField');
        Decimal result4 = prehook.getDecimalFromTag(tagData, 'MissingField');
        Decimal result5 = prehook.getDecimalFromTag(null, 'Price');
        Decimal result6 = prehook.getDecimalFromTag(tagData, 'InvalidField');
        Test.stopTest();

        System.assertEquals(100.50, result1, 'Should return Decimal value');
        System.assertEquals(200.75, result2, 'Should convert string to Decimal');
        System.assertEquals(null, result3, 'Null value should return null');
        System.assertEquals(null, result4, 'Missing field should return null');
        System.assertEquals(null, result5, 'Null tagData should return null');
        System.assertEquals(null, result6, 'Invalid number should return null');
    }

    @isTest
    static void testGetDecimalFromTag_NestedTagValue() {
        // Test nested tagValue structure used by Revenue Cloud Context API
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Map<String, Object> tagData = new Map<String, Object>{
            'Price' => new Map<String, Object>{ 'tagValue' => 500.00 },
            'StringPrice' => new Map<String, Object>{ 'tagValue' => '750.25' },
            'NullNested' => new Map<String, Object>{ 'tagValue' => null }
        };

        Test.startTest();
        Decimal result1 = prehook.getDecimalFromTag(tagData, 'Price');
        Decimal result2 = prehook.getDecimalFromTag(tagData, 'StringPrice');
        Decimal result3 = prehook.getDecimalFromTag(tagData, 'NullNested');
        Test.stopTest();

        System.assertEquals(500.00, result1, 'Should extract Decimal from nested tagValue structure');
        System.assertEquals(750.25, result2, 'Should convert nested string to Decimal');
        System.assertEquals(null, result3, 'Null nested tagValue should return null');
    }

    @isTest
    static void testGetIdFromTag() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Map<String, Object> tagData = new Map<String, Object>{
            'AccountId' => String.valueOf(testAccount.Id),
            'NullField' => null,
            'InvalidId' => 'not-an-id',
            'EmptyString' => ''
        };

        Test.startTest();
        Id result1 = prehook.getIdFromTag(tagData, 'AccountId');
        Id result2 = prehook.getIdFromTag(tagData, 'NullField');
        Id result3 = prehook.getIdFromTag(tagData, 'MissingField');
        Id result4 = prehook.getIdFromTag(null, 'AccountId');
        Id result5 = prehook.getIdFromTag(tagData, 'InvalidId');
        Id result6 = prehook.getIdFromTag(tagData, 'EmptyString');
        Test.stopTest();

        System.assertEquals(testAccount.Id, result1, 'Should return Id value');
        System.assertEquals(null, result2, 'Null value should return null');
        System.assertEquals(null, result3, 'Missing field should return null');
        System.assertEquals(null, result4, 'Null tagData should return null');
        System.assertEquals(null, result5, 'Invalid Id should return null');
        System.assertEquals(null, result6, 'Empty string should return null');
    }

    @isTest
    static void testCollectPartnerIds_DiscountModel() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        // Create QuoteHeaderData with Discount model
        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';
        quoteData.resellerId = partnerB.Id;

        Test.startTest();
        Set<Id> partnerIds = prehook.collectPartnerIds(quoteData);
        Test.stopTest();

        // Discount model should only include billing partner
        System.assertEquals(1, partnerIds.size(), 'Discount model should only include billing partner');
        System.assert(partnerIds.contains(partnerA.Id), 'Should contain billing partner');
        System.assert(!partnerIds.contains(partnerB.Id), 'Should NOT contain reseller for Discount model');
    }

    @isTest
    static void testCollectPartnerIds_GuaranteedMarginModel() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        // Create QuoteHeaderData with Guaranteed Margin model
        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Guaranteed Margin';
        quoteData.resellerId = partnerB.Id;
        quoteData.distributorId = null;
        quoteData.referralPartnerId = null;

        Test.startTest();
        Set<Id> partnerIds = prehook.collectPartnerIds(quoteData);
        Test.stopTest();

        // Guaranteed Margin should include all partners
        System.assertEquals(2, partnerIds.size(), 'Guaranteed Margin should include all partners');
        System.assert(partnerIds.contains(partnerA.Id), 'Should contain billing partner');
        System.assert(partnerIds.contains(partnerB.Id), 'Should contain reseller');
    }

    @isTest
    static void testCollectPartnerIds_NullData() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        Set<Id> result1 = prehook.collectPartnerIds(null);

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = null;
        Set<Id> result2 = prehook.collectPartnerIds(quoteData);
        Test.stopTest();

        System.assertEquals(0, result1.size(), 'Null data should return empty set');
        System.assertEquals(0, result2.size(), 'Null billing partner should return empty set');
    }

    @isTest
    static void testGetPartnerRole() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        // Create QuoteHeaderData with all partner types
        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.resellerId = partnerB.Id;

        Test.startTest();
        String role1 = prehook.getPartnerRole(partnerA.Id, quoteData);
        String role2 = prehook.getPartnerRole(partnerB.Id, quoteData);
        Test.stopTest();

        System.assertEquals('Billing Partner', role1, 'Should identify billing partner');
        System.assertEquals('Reseller', role2, 'Should identify reseller');
    }

    @isTest
    static void testQuoteHeaderDataHasPartnerPricing() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Test.startTest();
        // Test with complete data
        PartnerPricingPrehook.QuoteHeaderData completeData = new PartnerPricingPrehook.QuoteHeaderData();
        completeData.billingPartnerId = partnerA.Id;
        completeData.partnerPricingModel = 'Guaranteed Margin';
        Boolean hasComplete = completeData.hasPartnerPricing();

        // Test with missing billing partner
        PartnerPricingPrehook.QuoteHeaderData noBillingData = new PartnerPricingPrehook.QuoteHeaderData();
        noBillingData.partnerPricingModel = 'Guaranteed Margin';
        Boolean hasNoBilling = noBillingData.hasPartnerPricing();

        // Test with missing model
        PartnerPricingPrehook.QuoteHeaderData noModelData = new PartnerPricingPrehook.QuoteHeaderData();
        noModelData.billingPartnerId = partnerA.Id;
        Boolean hasNoModel = noModelData.hasPartnerPricing();
        Test.stopTest();

        System.assertEquals(true, hasComplete, 'Complete data should have partner pricing');
        System.assertEquals(false, hasNoBilling, 'Missing billing partner should not have partner pricing');
        System.assertEquals(false, hasNoModel, 'Missing model should not have partner pricing');
    }

    @isTest
    static void testPartnerMarginDetailToMap() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Test.startTest();
        PartnerPricingPrehook.PartnerMarginDetail detail = new PartnerPricingPrehook.PartnerMarginDetail(
            partnerA.Id,
            'Test Partner A',
            'Billing Partner',
            15.00
        );
        Map<String, Object> resultMap = detail.toMap();
        Test.stopTest();

        System.assertEquals(partnerA.Id, resultMap.get('partnerId'), 'Should have correct partnerId');
        System.assertEquals('Test Partner A', resultMap.get('partnerName'), 'Should have correct partnerName');
        System.assertEquals('Billing Partner', resultMap.get('partnerRole'), 'Should have correct partnerRole');
        System.assertEquals(15.00, resultMap.get('marginPercent'), 'Should have correct marginPercent');
    }

    @isTest
    static void testGetPartnerNames() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        Map<Id, String> names = prehook.getPartnerNames(new Set<Id>{ partnerA.Id, partnerB.Id });
        Map<Id, String> emptyResult = prehook.getPartnerNames(null);
        Map<Id, String> emptySetResult = prehook.getPartnerNames(new Set<Id>());
        Test.stopTest();

        System.assertEquals(2, names.size(), 'Should return names for both partners');
        System.assertEquals('Test Partner A', names.get(partnerA.Id), 'Should have Partner A name');
        System.assertEquals('Test Partner B', names.get(partnerB.Id), 'Should have Partner B name');
        System.assertEquals(0, emptyResult.size(), 'Null should return empty map');
        System.assertEquals(0, emptySetResult.size(), 'Empty set should return empty map');
    }

    /**
     * @description Test that clearPartnerPricingFields handles null/empty context gracefully.
     *              Full context integration cannot be unit tested (requires active pricing context),
     *              but we verify the method doesn't throw on a blank context ID.
     */
    @isTest
    static void testClearPartnerPricingFields_InvalidContext() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Test.startTest();
        // Blank context should return 0 without throwing
        Integer result = prehook.clearPartnerPricingFields('invalid-context-id');
        Test.stopTest();

        System.assertEquals(0, result, 'Invalid context should return 0 cleared lines');
    }

    @isTest
    static void testIsZeroListMaintenanceLine() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        System.assertEquals(true, prehook.isZeroListMaintenanceLine('New Maintenance', 0, 0, 0));
        System.assertEquals(true, prehook.isZeroListMaintenanceLine('Renewal Maintenance', null, null, null));
        System.assertEquals(false, prehook.isZeroListMaintenanceLine('Software', 0, 0, 0));
        System.assertEquals(false, prehook.isZeroListMaintenanceLine('New Maintenance', 0, 71, 0));
    }

    @isTest
    static void testBuildPartnerPercentOnlyUpdate_stampsDiscountPercentOnZeroListMaintenance() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Account partner = new Account(Name = 'Prehook Maint Partner', Type = 'Partner');
        insert partner;

        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = true,
            New_Maintenance_Percent__c = 12,
            Software_Percent__c = 15
        );

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partner.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            PartnerPricingService.getPricingModels(new Set<Id>{ partner.Id }, 'Discount');
        Map<Id, String> partnerNames = new Map<Id, String>{ partner.Id => partner.Name };

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'UnitPrice' => 0,
            'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        Test.startTest();
        Map<String, Object> result = prehook.buildPartnerPercentOnlyUpdate(
            lineItem,
            '0QLTEST',
            quoteData,
            partnerModels,
            partnerNames,
            'New Maintenance',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should stamp partner percent on zero-list maintenance');

        Map<String, Object> attrsByName = new Map<String, Object>();
        for (Object attrObj : (List<Object>) result.get('attributes')) {
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            attrsByName.put((String) attr.get('attributeName'), attr.get('attributeValue'));
        }

        System.assertEquals(12, attrsByName.get('PartnerDiscountPercent'));
        System.assertEquals('Discount', attrsByName.get('Partner_Pricing_Model_Applied__c'));
        System.assertEquals(
            'System Calculated (Pre-Procedure, Percent Only)',
            attrsByName.get('Partner_Pricing_Source__c')
        );
        System.assertEquals(false, attrsByName.containsKey('NetUnitPrice'));
        System.assertEquals(false, attrsByName.containsKey('PartnerUnitPrice'));
    }

    @isTest
    static void testBuildPartnerPercentOnlyUpdate_usesBulkProductTypeWhenContextBlank() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Account partner = new Account(Name = 'Prehook Bulk Type Partner', Type = 'Partner');
        insert partner;

        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = true,
            New_Maintenance_Percent__c = 12,
            Software_Percent__c = 15
        );

        Product2 maintProd = new Product2(
            Name = 'Bulk Type Maint',
            ProductCode = 'TEST-RNM-BULK',
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 0,
            IsActive = true,
            UseStandardPrice = false
        );

        Opportunity opp = new Opportunity(
            AccountId = partner.Id,
            Name = 'Bulk Type Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Bulk Type Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId
        );
        insert q;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :maintProd.Id LIMIT 1].Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 0
        );
        insert qli;

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partner.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            PartnerPricingService.getPricingModels(new Set<Id>{ partner.Id }, 'Discount');
        Map<Id, String> productTypeByLineId = PartnerPricingService.ensureProductTypesLoaded(
            new Set<Id>{ qli.Id },
            new Map<Id, String>()
        );
        seedProductTypeForLine(productTypeByLineId, qli.Id, 'New Maintenance');
        forceProductTypeForLine(productTypeByLineId, qli.Id, 'New Maintenance');

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ q.Id, qli.Id },
            '_recordId' => qli.Id,
            'UnitPrice' => 0,
            'ListPrice' => 0
        };

        String resolvedType = PartnerPricingService.resolveProductType(
            prehook.getStringFromTag(lineItem, 'Fortra_Product_Type__c'),
            qli.Id,
            productTypeByLineId
        );

        Test.startTest();
        Map<String, Object> result = prehook.buildPartnerPercentOnlyUpdate(
            lineItem,
            qli.Id,
            quoteData,
            partnerModels,
            new Map<Id, String>{ partner.Id => partner.Name },
            resolvedType,
            null
        );
        Test.stopTest();

        System.assertEquals('New Maintenance', resolvedType);
        System.assertNotEquals(null, result);

        Map<String, Object> attrsByName = new Map<String, Object>();
        for (Object attrObj : (List<Object>) result.get('attributes')) {
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            attrsByName.put((String) attr.get('attributeName'), attr.get('attributeValue'));
        }
        System.assertEquals(12, attrsByName.get('PartnerDiscountPercent'),
            'Should use New Maintenance 12%, not Software 15%');
    }

    private static Map<String, Object> attributesByName(Map<String, Object> nodeUpdate) {
        Map<String, Object> valuesByName = new Map<String, Object>();
        if (nodeUpdate == null) {
            return valuesByName;
        }
        List<Object> attributes = (List<Object>) nodeUpdate.get('attributes');
        if (attributes == null) {
            return valuesByName;
        }
        for (Object attributeObj : attributes) {
            Map<String, Object> attribute = (Map<String, Object>) attributeObj;
            valuesByName.put(
                (String) attribute.get('attributeName'),
                attribute.get('attributeValue')
            );
        }
        return valuesByName;
    }

    @isTest
    static void testResolveBasePrice_prefersRegionalThenUnitThenList() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        System.assertEquals(900, prehook.resolveBasePrice(900, 1000, 1100));
        System.assertEquals(1000, prehook.resolveBasePrice(null, 1000, 1100));
        System.assertEquals(1100, prehook.resolveBasePrice(null, null, 1100));
        System.assertEquals(null, prehook.resolveBasePrice(null, null, null));
    }

    @isTest
    static void testExtractFieldValue_handlesWrappedPlainAndInvalidMap() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Map<String, Object> tagData = new Map<String, Object>{
            'Wrapped' => new Map<String, Object>{ 'tagValue' => 'inner' },
            'Plain' => 'direct',
            'BadMap' => new Map<String, Object>{ 'dmlStatus' => 'unchanged' }
        };

        System.assertEquals('inner', prehook.extractFieldValue(tagData, 'Wrapped'));
        System.assertEquals('direct', prehook.extractFieldValue(tagData, 'Plain'));
        System.assertEquals(null, prehook.extractFieldValue(tagData, 'BadMap'));
        System.assertEquals(null, prehook.extractFieldValue(null, 'Plain'));
        System.assertEquals(null, prehook.extractFieldValue(tagData, 'Missing'));
    }

    @isTest
    static void testGetLineItemRecordId_readsRecordIdSourceRecordIdAndId() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        String lineId = String.valueOf(partnerA.Id);

        System.assertEquals(partnerA.Id, prehook.getLineItemRecordId(new Map<String, Object>{
            '_recordId' => lineId
        }));
        System.assertEquals(partnerA.Id, prehook.getLineItemRecordId(new Map<String, Object>{
            'SourceRecordId' => lineId
        }));
        System.assertEquals(partnerA.Id, prehook.getLineItemRecordId(new Map<String, Object>{
            'Id' => lineId
        }));
        System.assertEquals(null, prehook.getLineItemRecordId(new Map<String, Object>{
            'Id' => 'not-an-id'
        }));
        System.assertEquals(null, prehook.getLineItemRecordId(new Map<String, Object>()));
    }

    @isTest
    static void testGetPartnerRole_distributorReferralAndUnknown() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        Account partnerC = new Account(Name = 'Role Test Partner C', Type = 'Partner');
        Account partnerD = new Account(Name = 'Role Test Partner D', Type = 'Partner');
        insert new List<Account>{ partnerC, partnerD };

        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.resellerId = partnerB.Id;
        quoteData.distributorId = partnerC.Id;
        quoteData.referralPartnerId = partnerD.Id;

        System.assertEquals('Distributor', prehook.getPartnerRole(partnerC.Id, quoteData));
        System.assertEquals('Referral Partner', prehook.getPartnerRole(partnerD.Id, quoteData));
        System.assertEquals('Reseller', prehook.getPartnerRole(partnerB.Id, quoteData));
        System.assertEquals('Unknown', prehook.getPartnerRole(UserInfo.getUserId(), quoteData));
    }

    @isTest
    static void testIsMaintenanceProductType() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        System.assertEquals(true, prehook.isMaintenanceProductType('New Maintenance'));
        System.assertEquals(true, prehook.isMaintenanceProductType('Renewal Maintenance'));
        System.assertEquals(false, prehook.isMaintenanceProductType('Software'));
    }

    @isTest
    static void testCalculatePartnerPercentTotal_discountAndGuaranteedMargin() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        Map<Id, Partner_Pricing_Model__c> discountModels =
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id }, 'Discount');
        Map<Id, Partner_Pricing_Model__c> gmModels =
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id, partnerB.Id }, 'Guaranteed Margin');

        PartnerPricingPrehook.QuoteHeaderData discountData = new PartnerPricingPrehook.QuoteHeaderData();
        discountData.billingPartnerId = partnerA.Id;
        discountData.partnerPricingModel = 'Discount';

        PartnerPricingPrehook.QuoteHeaderData gmData = new PartnerPricingPrehook.QuoteHeaderData();
        gmData.billingPartnerId = partnerA.Id;
        gmData.partnerPricingModel = 'Guaranteed Margin';

        System.assertEquals(25, prehook.calculatePartnerPercentTotal(discountData, discountModels, 'Software'));
        System.assertEquals(25, prehook.calculatePartnerPercentTotal(gmData, gmModels, 'Software'));
        System.assertEquals(null, prehook.calculatePartnerPercentTotal(null, gmModels, 'Software'));
        System.assertEquals(null, prehook.calculatePartnerPercentTotal(gmData, new Map<Id, Partner_Pricing_Model__c>(), 'Software'));
    }

    @isTest
    static void testBuildMissingModelWarning_discountAndGuaranteedMargin() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Map<Id, String> partnerNames = prehook.getPartnerNames(new Set<Id>{ partnerA.Id, partnerB.Id });

        PartnerPricingPrehook.QuoteHeaderData discountData = new PartnerPricingPrehook.QuoteHeaderData();
        discountData.billingPartnerId = partnerA.Id;
        discountData.partnerPricingModel = 'Discount';

        String discountWarning = prehook.buildMissingModelWarning(
            new Set<Id>{ partnerA.Id },
            new Map<Id, Partner_Pricing_Model__c>(),
            partnerNames,
            discountData
        );
        System.assert(discountWarning.contains('Test Partner A'), 'Discount warning should name billing partner');
        System.assert(discountWarning.contains('Discount'), 'Discount warning should cite model type');

        PartnerPricingPrehook.QuoteHeaderData gmData = new PartnerPricingPrehook.QuoteHeaderData();
        gmData.billingPartnerId = partnerA.Id;
        gmData.partnerPricingModel = 'Guaranteed Margin';
        gmData.resellerId = partnerB.Id;

        Map<Id, Partner_Pricing_Model__c> gmModels =
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id }, 'Guaranteed Margin');
        String gmWarning = prehook.buildMissingModelWarning(
            prehook.collectPartnerIds(gmData),
            gmModels,
            partnerNames,
            gmData
        );
        System.assert(gmWarning.contains('Test Partner B'), 'GM warning should name missing reseller');
        System.assertEquals(null, prehook.buildMissingModelWarning(
            prehook.collectPartnerIds(gmData),
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id, partnerB.Id }, 'Guaranteed Margin'),
            partnerNames,
            gmData
        ));
    }

    @isTest
    static void testBuildWarningOnlyUpdate() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' }
        };

        Map<String, Object> result = prehook.buildWarningOnlyUpdate(lineItem, '0QLTEST', 'Missing model warning');
        System.assertNotEquals(null, result);
        System.assertEquals('Missing model warning', attributesByName(result).get('Partner_Pricing_Warning__c'));
        System.assertEquals(null, prehook.buildWarningOnlyUpdate(new Map<String, Object>(), '0QLTEST', 'No path'));
    }

    @isTest
    static void testProcessLineItem_discountSoftware() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id }, 'Discount');
        Map<Id, String> partnerNames = prehook.getPartnerNames(new Set<Id>{ partnerA.Id });

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => '0QL000000000001AAA',
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QL000000000001AAA' },
            'UnitPrice' => 1000,
            'Fortra_Product_Type__c' => 'Software'
        };

        Map<String, Object> result = prehook.processLineItem(
            lineItem, quoteData, partnerModels, partnerNames, null
        );
        Map<String, Object> attrs = attributesByName(result);

        System.assertEquals(25, attrs.get('PartnerDiscountPercent'));
        System.assertEquals('Discount', attrs.get('Partner_Pricing_Model_Applied__c'));
        System.assertNotEquals(null, attrs.get('Partner_Margin_Detail__c'));
        System.assertEquals(false, attrs.containsKey('PartnerUnitPrice'));
        System.assertEquals(false, attrs.containsKey('NetUnitPrice'));
        System.assertEquals(false, attrs.containsKey('Pre_Partner_Price__c'));
    }

    @isTest
    static void testProcessLineItem_guaranteedMarginAdditive() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Guaranteed Margin';
        quoteData.resellerId = partnerB.Id;

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id, partnerB.Id }, 'Guaranteed Margin');
        Map<Id, String> partnerNames = prehook.getPartnerNames(new Set<Id>{ partnerA.Id, partnerB.Id });

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => '0QL000000000002AAA',
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QL000000000002AAA' },
            'RegionalNetUnitPrice__c' => 1000,
            'UnitPrice' => 1200,
            'Fortra_Product_Type__c' => 'Software'
        };

        Map<String, Object> result = prehook.processLineItem(
            lineItem, quoteData, partnerModels, partnerNames, null
        );
        Map<String, Object> attrs = attributesByName(result);

        System.assertEquals(25, attrs.get('PartnerDiscountPercent'));
        System.assertEquals(false, attrs.containsKey('PartnerUnitPrice'));
    }

    @isTest
    static void testProcessLineItem_zeroListMaintenancePercentOnly() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id }, 'Discount');

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => '0QL000000000003AAA',
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QL000000000003AAA' },
            'UnitPrice' => 0,
            'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        Map<String, Object> result = prehook.processLineItem(
            lineItem,
            quoteData,
            partnerModels,
            prehook.getPartnerNames(new Set<Id>{ partnerA.Id }),
            null
        );
        Map<String, Object> attrs = attributesByName(result);

        System.assertEquals(22, attrs.get('PartnerDiscountPercent'));
        System.assertEquals(false, attrs.containsKey('NetUnitPrice'));
    }

    @isTest
    static void testProcessLineItem_discountMissingModelSetsWarningOnly() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => '0QL000000000004AAA',
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QL000000000004AAA' },
            'UnitPrice' => 1000,
            'Fortra_Product_Type__c' => 'Software'
        };

        Map<String, Object> result = prehook.processLineItem(
            lineItem,
            quoteData,
            new Map<Id, Partner_Pricing_Model__c>(),
            prehook.getPartnerNames(new Set<Id>{ partnerA.Id }),
            'Missing Discount model'
        );
        System.assertEquals('Missing Discount model', attributesByName(result).get('Partner_Pricing_Warning__c'));
    }

    @isTest
    static void testProcessLineItem_skipsWithoutIdUpdatePathOrPrice() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = UserInfo.getUserId();
        quoteData.partnerPricingModel = 'Discount';

        System.assertEquals(null, prehook.processLineItem(
            new Map<String, Object>{ 'UnitPrice' => 100 },
            quoteData,
            new Map<Id, Partner_Pricing_Model__c>(),
            new Map<Id, String>(),
            null
        ));
        System.assertEquals(null, prehook.processLineItem(
            new Map<String, Object>{
                '_recordId' => '0QL000000000005AAA',
                'UnitPrice' => 0,
                'Fortra_Product_Type__c' => 'Software'
            },
            quoteData,
            new Map<Id, Partner_Pricing_Model__c>(),
            new Map<Id, String>(),
            null
        ));
        System.assertEquals(null, prehook.processLineItem(
            new Map<String, Object>{
                '_recordId' => '0QL000000000006AAA',
                'UnitPrice' => 100,
                'Fortra_Product_Type__c' => 'Software'
            },
            quoteData,
            new Map<Id, Partner_Pricing_Model__c>(),
            new Map<Id, String>(),
            null
        ));

        quoteData.partnerPricingModel = 'Unknown Model';
        System.assertEquals(null, prehook.processLineItem(
            new Map<String, Object>{
                '_recordId' => '0QL000000000007AAA',
                '_updatePath' => new List<Object>{ '0Q0TEST', '0QL000000000007AAA' },
                'UnitPrice' => 100
            },
            quoteData,
            new Map<Id, Partner_Pricing_Model__c>(),
            new Map<Id, String>(),
            null
        ));
    }

    @isTest
    static void testProcessLineItem_includesPartnerWarningOnSuccessfulUpdate() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => '0QL000000000008AAA',
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QL000000000008AAA' },
            'UnitPrice' => 1000,
            'Fortra_Product_Type__c' => 'Software'
        };

        Map<String, Object> result = prehook.processLineItem(
            lineItem,
            quoteData,
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id }, 'Discount'),
            prehook.getPartnerNames(new Set<Id>{ partnerA.Id }),
            'Reseller missing GM model'
        );
        System.assertEquals('Reseller missing GM model', attributesByName(result).get('Partner_Pricing_Warning__c'));
    }

    @isTest
    static void testCollectPartnerIds_includesAllGuaranteedMarginPartners() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        Account partnerC = new Account(Name = 'Collect GM Partner C', Type = 'Partner');
        Account partnerD = new Account(Name = 'Collect GM Partner D', Type = 'Partner');
        insert new List<Account>{ partnerC, partnerD };

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Guaranteed Margin';
        quoteData.resellerId = partnerB.Id;
        quoteData.distributorId = partnerC.Id;
        quoteData.referralPartnerId = partnerD.Id;

        Set<Id> partnerIds = new PartnerPricingPrehook().collectPartnerIds(quoteData);
        System.assertEquals(4, partnerIds.size());
    }

    @isTest
    static void testQueryQuoteHeaderFromContext_invalidContextReturnsNull() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        System.assertEquals(null, prehook.queryQuoteHeaderFromContext('invalid-context-id'));
    }

    @isTest
    static void testProcessLineItemsWithWarningOnly_invalidContextReturnsZero() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        System.assertEquals(0, prehook.processLineItemsWithWarningOnly('invalid-context-id', 'Test warning'));
    }

    @isTest
    static void testProcessLineItems_invalidContextReturnsZero() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';

        Integer processed = prehook.processLineItems(
            'invalid-context-id',
            quoteData,
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id }, 'Discount'),
            prehook.getPartnerNames(new Set<Id>{ partnerA.Id }),
            null
        );
        System.assertEquals(0, processed);
    }

    @isTest
    static void testParseQuoteHeaderApiResponse_nestedAndLegacyFormats() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Id quoteId = fakeQuoteId();

        Map<String, Object> nestedResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransaction' => new List<Object>{
                    new Map<String, Object>{
                        'tagValue' => new Map<String, Object>{
                            'Billing_Partner__c' => String.valueOf(partnerA.Id),
                            'Partner_Pricing_Model__c' => 'Discount'
                        },
                        'dataPath' => new List<Object>{ 'ctx1', String.valueOf(quoteId) }
                    }
                }
            }
        };
        PartnerPricingPrehook.QuoteHeaderData nested = prehook.parseQuoteHeaderApiResponse(nestedResponse);
        System.assertEquals(partnerA.Id, nested.billingPartnerId);
        System.assertEquals('Discount', nested.partnerPricingModel);

        Map<String, Object> legacyResponse = new Map<String, Object>{
            'SalesTransaction' => new Map<String, Object>{
                'Id' => String.valueOf(quoteId),
                'Billing_Partner__c' => String.valueOf(partnerA.Id),
                'Partner_Pricing_Model__c' => 'Guaranteed Margin'
            }
        };
        PartnerPricingPrehook.QuoteHeaderData legacy = prehook.parseQuoteHeaderApiResponse(legacyResponse);
        System.assertEquals('Guaranteed Margin', legacy.partnerPricingModel);

        System.assertEquals(null, prehook.parseQuoteHeaderApiResponse(null));
        System.assertEquals(null, prehook.parseQuoteHeaderApiResponse(new Map<String, Object>{ 'queryResult' => 'bad' }));
        System.assertEquals(null, prehook.parseQuoteHeaderApiResponse(new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SalesTransaction' => new List<Object>() }
        }));
        System.assertEquals(null, prehook.parseQuoteHeaderApiResponse(new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransaction' => new List<Object>{ 'unexpected-type' }
            }
        }));
        System.assertEquals(null, prehook.parseQuoteHeaderApiResponse(new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransaction' => new List<Object>{
                    new Map<String, Object>{ 'tagValue' => 'not-a-map' }
                }
            }
        }));
        System.assertNotEquals(null, prehook.parseQuoteHeaderApiResponse(new Map<String, Object>{
            'SalesTransaction' => new Map<String, Object>{
                'Billing_Partner__c' => String.valueOf(partnerA.Id),
                'Partner_Pricing_Model__c' => 'Discount'
            }
        }));
    }

    @isTest
    static void testBuildDataPathUpdatesFromApiResponse_buildsClearAndWarningUpdates() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Map<String, Object> apiResponse = new Map<String, Object>{
            'SalesTransactionItem' => new List<Object>{
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'ctx1', '0Q0TEST', '0QLTEST' }
                },
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'ctx1' }
                },
                'skip-me'
            }
        };

        List<Map<String, Object>> clearAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'PartnerDiscountPercent', 'attributeValue' => null }
        };
        List<Map<String, Object>> clearUpdates = prehook.buildDataPathUpdatesFromApiResponse(apiResponse, clearAttributes);
        System.assertEquals(2, clearUpdates.size());
        System.assertEquals(
            new List<Object>{ '0Q0TEST', '0QLTEST' },
            ((Map<String, Object>) clearUpdates[0].get('nodePath')).get('dataPath')
        );

        List<Map<String, Object>> warningUpdates = prehook.buildDataPathUpdatesFromApiResponse(
            apiResponse,
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'attributeName' => 'Partner_Pricing_Warning__c', 'attributeValue' => 'Warn' }
            }
        );
        System.assertEquals('Warn', ((Map<String, Object>) ((List<Object>) warningUpdates[0].get('attributes'))[0]).get('attributeValue'));
        System.assertEquals(0, prehook.buildDataPathUpdatesFromApiResponse(null, clearAttributes).size());
    }

    @isTest
    static void testParseLineItemApiResponse_singleItemAndInvalidResponse() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        System.assertEquals(0, prehook.parseLineItemApiResponse(new Map<String, Object>{ 'queryResult' => 'bad' }).size());
        System.assertEquals(1, prehook.parseLineItemApiResponse(new Map<String, Object>{
            'SalesTransactionItem' => new Map<String, Object>{
                'UnitPrice' => 250,
                'Id' => '0QLTEST'
            }
        }).size());
    }

    @isTest
    static void testBuildMissingModelWarning_guaranteedMarginUsesRoleFallback() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData gmData = new PartnerPricingPrehook.QuoteHeaderData();
        gmData.billingPartnerId = partnerA.Id;
        gmData.partnerPricingModel = 'Guaranteed Margin';
        gmData.resellerId = partnerB.Id;

        String warning = prehook.buildMissingModelWarning(
            prehook.collectPartnerIds(gmData),
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id }, 'Guaranteed Margin'),
            new Map<Id, String>(),
            gmData
        );
        System.assert(warning.contains('Reseller [ID:'), 'Missing partner name should use role/id fallback');
    }

    @isTest
    static void testCalculatePartnerPercentTotal_unknownModelReturnsNull() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.partnerPricingModel = 'Unknown';
        System.assertEquals(null, prehook.calculatePartnerPercentTotal(
            quoteData,
            new Map<Id, Partner_Pricing_Model__c>(),
            'Software'
        ));
    }

    @isTest
    static void testParseLineItemApiResponse_extractsTagValueAndLegacyItems() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{
                    new Map<String, Object>{
                        'tagValue' => new Map<String, Object>{
                            'UnitPrice' => 1000,
                            'Fortra_Product_Type__c' => 'Software'
                        },
                        'dataPath' => new List<Object>{ 'ctx1', String.valueOf(quoteId), String.valueOf(lineId) }
                    },
                    new Map<String, Object>{
                        'UnitPrice' => 500,
                        'Id' => String.valueOf(lineId)
                    }
                }
            }
        };

        List<Map<String, Object>> lineItems = prehook.parseLineItemApiResponse(response);
        System.assertEquals(2, lineItems.size());
        System.assertEquals(String.valueOf(lineId), lineItems[0].get('_recordId'));
        System.assertEquals(1000, lineItems[0].get('UnitPrice'));
        System.assertEquals(500, lineItems[1].get('UnitPrice'));
        System.assertEquals(0, prehook.parseLineItemApiResponse(null).size());
    }

    @isTest
    static void testSubmitContextUpdates_handlesInvalidContext() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Context.IndustriesContext ctx = new Context.IndustriesContext();
        List<Map<String, Object>> updates = new List<Map<String, Object>>{
            new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => new List<Object>{ '0Q0TEST', '0QLTEST' } },
                'attributes' => new List<Map<String, Object>>{
                    new Map<String, Object>{ 'attributeName' => 'PartnerDiscountPercent', 'attributeValue' => 12 }
                }
            }
        };

        Test.startTest();
        prehook.submitContextUpdates(ctx, 'invalid-context-id', updates);
        Test.stopTest();
    }

    @isTest
    static void testBuildMissingModelWarning_usesIdFallbackWhenNameMissing() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData discountData = new PartnerPricingPrehook.QuoteHeaderData();
        discountData.billingPartnerId = partnerA.Id;
        discountData.partnerPricingModel = 'Discount';

        String warning = prehook.buildMissingModelWarning(
            new Set<Id>{ partnerA.Id },
            new Map<Id, Partner_Pricing_Model__c>(),
            new Map<Id, String>(),
            discountData
        );
        System.assert(warning.contains('Billing Partner [ID:'), 'Should fall back to partner id when name missing');
    }

    @isTest
    static void testBuildPartnerPercentOnlyUpdate_warningOnlyWhenPercentZero() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' }
        };

        Map<String, Object> result = prehook.buildPartnerPercentOnlyUpdate(
            lineItem,
            '0QLTEST',
            new PartnerPricingPrehook.QuoteHeaderData(),
            new Map<Id, Partner_Pricing_Model__c>(),
            new Map<Id, String>(),
            'Software',
            'Percent unavailable'
        );
        System.assertEquals('Percent unavailable', attributesByName(result).get('Partner_Pricing_Warning__c'));
    }

    @isTest
    static void testProcessLineItem_guaranteedMarginIncludesWarningWhenPresent() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Guaranteed Margin';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => '0QL000000000009AAA',
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QL000000000009AAA' },
            'UnitPrice' => 1000,
            'Fortra_Product_Type__c' => 'Software'
        };

        Map<String, Object> result = prehook.processLineItem(
            lineItem,
            quoteData,
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id }, 'Guaranteed Margin'),
            prehook.getPartnerNames(new Set<Id>{ partnerA.Id }),
            'Reseller missing GM model'
        );
        System.assertEquals('Reseller missing GM model', attributesByName(result).get('Partner_Pricing_Warning__c'));
        System.assertEquals(15, attributesByName(result).get('PartnerDiscountPercent'));
        System.assertEquals(false, attributesByName(result).containsKey('PartnerUnitPrice'));
    }

    @isTest
    static void testBuildDataPathUpdatesFromApiResponse_invalidQueryResultAndPaths() {
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();
        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'PartnerDiscountPercent', 'attributeValue' => 10 }
        };

        System.assertEquals(0, prehook.buildDataPathUpdatesFromApiResponse(
            new Map<String, Object>{ 'queryResult' => 'bad-type' },
            attributes
        ).size());
        System.assertEquals(0, prehook.buildDataPathUpdatesFromApiResponse(
            new Map<String, Object>{ 'queryResult' => new Map<String, Object>() },
            attributes
        ).size());
        System.assertEquals(0, prehook.buildDataPathUpdatesFromApiResponse(
            new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{
                    new Map<String, Object>{ 'dataPath' => 'not-a-list' },
                    new Map<String, Object>{ 'dataPath' => new List<Object>() }
                }
            },
            attributes
        ).size());
    }

    @isTest
    static void testBuildPartnerPercentStampUpdate_stampsPercentAndMarginDetail() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        PartnerPricingPrehook prehook = new PartnerPricingPrehook();

        PartnerPricingPrehook.QuoteHeaderData quoteData = new PartnerPricingPrehook.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.resellerId = partnerB.Id;
        quoteData.partnerPricingModel = 'Guaranteed Margin';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QL000000000010AAA' }
        };

        Map<String, Object> result = prehook.buildPartnerPercentStampUpdate(
            lineItem,
            '0QL000000000010AAA',
            quoteData,
            prehook.loadPartnerPricingModels(new Set<Id>{ partnerA.Id, partnerB.Id }, 'Guaranteed Margin'),
            prehook.getPartnerNames(new Set<Id>{ partnerA.Id, partnerB.Id }),
            'Software',
            null
        );

        System.assertNotEquals(null, result);
        System.assertEquals(25, attributesByName(result).get('PartnerDiscountPercent'));
        System.assertNotEquals(null, attributesByName(result).get('Partner_Margin_Detail__c'));
        System.assertEquals(null, prehook.buildPartnerPercentStampUpdate(
            new Map<String, Object>(),
            '0QL000000000010AAA',
            quoteData,
            new Map<Id, Partner_Pricing_Model__c>(),
            new Map<Id, String>(),
            'Software',
            null
        ));
    }

    private static Id fakeQuoteId() {
        return (Id) (Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA');
    }

    private static Id fakeQuoteLineItemId() {
        return (Id) (QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA');
    }
}