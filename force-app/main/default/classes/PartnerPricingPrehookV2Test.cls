/**
 * @description Test class for PartnerPricingPrehookV2
 * @author Marc DeBrey
 * @date December 2025
 */
@isTest
private class PartnerPricingPrehookV2Test {

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

    /**
     * @description Test that the prehook class can be instantiated
     *              Note: execute() method requires RevSignaling.TransactionRequest which
     *              is a managed class without public constructor - cannot be unit tested.
     *              The execute() method must be tested via integration testing.
     */
    @isTest
    static void testClassInstantiation() {
        Test.startTest();
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();
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
        PartnerPricingPrehookV2 processor = new PartnerPricingPrehookV2();
        Test.stopTest();

        System.assertNotEquals(null, processor, 'Should be instantiable');
        System.assertEquals('PartnerPricingPrehookV2', String.valueOf(processor).substringBefore(':'), 'Should be correct type');
    }

    @isTest
    static void testLoadPartnerPricingModels() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();
        Set<Id> accountIds = new Set<Id>{ partnerA.Id, partnerB.Id };

        Test.startTest();
        Map<Id, List<Partner_Pricing_Model__c>> models = prehook.loadPartnerPricingModels(accountIds, 'Guaranteed Margin');
        Test.stopTest();

        System.assertEquals(2, models.size(), 'Should return models for both partners');
        System.assertEquals(1, models.get(partnerA.Id).size(), 'Should have Partner A candidate list');
        System.assertEquals(1, models.get(partnerB.Id).size(), 'Should have Partner B candidate list');
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
        // Use PartnerPricingServiceV2 - that's where these methods live
        Decimal softwareMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Software', null);
        Decimal subscriptionMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Subscription', null);
        Decimal servicesMargin = PartnerPricingServiceV2.getMarginForProductType(model, 'Services', null);
        Test.stopTest();

        System.assertEquals(15.00, softwareMargin, 'Software margin should be 15');
        System.assertEquals(18.00, subscriptionMargin, 'Subscription margin should be 18');
        System.assertEquals(20.00, servicesMargin, 'Services margin should be 20');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice() {
        Test.startTest();
        // Single margin: 1000 * (1 - 0.15) = 850
        Decimal singleMargin = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(1000.00, new List<Decimal>{ 15.00 });

        // ADDITIVE margins: 1000 * (1 - (0.15 + 0.10)) = 1000 * (1 - 0.25) = 750
        Decimal additiveMargins = PartnerPricingServiceV2.calculateGuaranteedMarginPrice(1000.00, new List<Decimal>{ 15.00, 10.00 });
        Test.stopTest();

        System.assertEquals(850.00, singleMargin, 'Single margin calculation incorrect');
        System.assertEquals(750.00, additiveMargins, 'ADDITIVE margin calculation incorrect');
    }

    @isTest
    static void testCalculateDiscountPrice() {
        Test.startTest();
        // 1000 * (1 - 0.25) = 750
        Decimal discountedPrice = PartnerPricingServiceV2.calculateDiscountPrice(1000.00, 25.00);
        Test.stopTest();

        System.assertEquals(750.00, discountedPrice, 'Discount calculation incorrect');
    }

    @isTest
    static void testProcessLineItem_DiscountNoMatchLeavesPriceUnchanged() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();
        PartnerPricingPrehookV2.QuoteHeaderData quoteData = new PartnerPricingPrehookV2.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf(partnerA.Id),
            '_updatePath' => new List<Object>{ 'QuoteId', String.valueOf(partnerA.Id) },
            'UnitPrice' => 1000.00
        };

        Partner_Pricing_Model__c categoryOnlyModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Solution_Category__c = 'Email Security',
            Software_Percent__c = 25.00
        );

        Map<Id, List<Partner_Pricing_Model__c>> partnerModels = new Map<Id, List<Partner_Pricing_Model__c>>{
            partnerA.Id => new List<Partner_Pricing_Model__c>{ categoryOnlyModel }
        };

        Map<Id, String> partnerNames = new Map<Id, String>{ partnerA.Id => 'Test Partner A' };

        PartnerPricingPrehookV2.LineItemContextData lineData = new PartnerPricingPrehookV2.LineItemContextData();
        lineData.lineItemId = partnerA.Id;
        lineData.productType = 'Software';
        lineData.solutionCategory = 'No Match';

        Test.startTest();
        Map<String, Object> result = prehook.processLineItem(
            lineItem,
            quoteData,
            partnerModels,
            partnerNames,
            new Map<Id, PartnerPricingPrehookV2.LineItemContextData>{ partnerA.Id => lineData }
        );
        Test.stopTest();

        Map<String, Object> attributeMap = attributesByName(result);
        System.assertEquals(1000.00, attributeMap.get('Partner_Adjusted_Price__c'), 'No applicable model should leave the price unchanged');
        System.assertEquals(0, attributeMap.get('PartnerDiscountPercent'), 'No applicable model should contribute zero discount');
        System.assertEquals(null, attributeMap.get('Partner_Margin_Detail__c'), 'No applicable model should not create margin detail');
        System.assertEquals(null, attributeMap.get('NetUnitPrice'), 'Zero discount should not overwrite NetUnitPrice');
        System.assertEquals(null, attributeMap.get('UnitPrice'), 'Zero discount should not overwrite UnitPrice');
    }

    @isTest
    static void testProcessLineItem_DiscountFortraOriginatedUsesNonOriginatingFields() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();
        PartnerPricingPrehookV2.QuoteHeaderData quoteData = new PartnerPricingPrehookV2.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';
        quoteData.dealType = 'Fortra Originated';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf(partnerA.Id),
            '_updatePath' => new List<Object>{ 'QuoteId', String.valueOf(partnerA.Id) },
            'UnitPrice' => 1000.00
        };

        Partner_Pricing_Model__c categoryModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Solution_Category__c = 'Backup',
            Software_Percent__c = 25.00,
            Non_Orig_Software_Pct__c = 10.00
        );

        Map<Id, List<Partner_Pricing_Model__c>> partnerModels = new Map<Id, List<Partner_Pricing_Model__c>>{
            partnerA.Id => new List<Partner_Pricing_Model__c>{ categoryModel }
        };

        Map<Id, String> partnerNames = new Map<Id, String>{ partnerA.Id => 'Test Partner A' };

        PartnerPricingPrehookV2.LineItemContextData lineData = new PartnerPricingPrehookV2.LineItemContextData();
        lineData.lineItemId = partnerA.Id;
        lineData.productType = 'Software';
        lineData.solutionCategory = 'Backup';

        Test.startTest();
        Map<String, Object> result = prehook.processLineItem(
            lineItem,
            quoteData,
            partnerModels,
            partnerNames,
            new Map<Id, PartnerPricingPrehookV2.LineItemContextData>{ partnerA.Id => lineData }
        );
        Test.stopTest();

        Map<String, Object> attributeMap = attributesByName(result);
        System.assertEquals(900.00, attributeMap.get('Partner_Adjusted_Price__c'), 'Fortra Originated should use the non-originating discount set');
        System.assertEquals(10.00, attributeMap.get('PartnerDiscountPercent'), 'Fortra Originated should use the non-originating percent');
    }

    @isTest
    static void testBuildLineItemContextData_UsesContextHierarchyValues() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf(partnerA.Id),
            'Fortra_Product_Type__c' => 'Software',
            'Unit__c' => 'Cybersecurity',
            'Solution_Group__c' => 'Data Protection',
            'Solution_Category__c' => 'Backup'
        };

        Test.startTest();
        PartnerPricingPrehookV2.LineItemContextData lineData = prehook.buildLineItemContextData(lineItem);
        Test.stopTest();

        System.assertNotEquals(null, lineData, 'Context line data should be created');
        System.assertEquals(partnerA.Id, lineData.lineItemId, 'Line item Id should come from the context payload');
        System.assertEquals('Software', lineData.productType, 'Product type should come from SalesTransactionItem');
        System.assertEquals('Cybersecurity', lineData.unit, 'Unit should come from SalesTransactionItem');
        System.assertEquals('Data Protection', lineData.solutionGroup, 'Solution Group should come from SalesTransactionItem');
        System.assertEquals('Backup', lineData.solutionCategory, 'Solution Category should come from SalesTransactionItem');
    }

    @isTest
    static void testProcessLineItem_DiscountUsesContextHierarchyWithoutSupplementalMap() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();
        PartnerPricingPrehookV2.QuoteHeaderData quoteData = new PartnerPricingPrehookV2.QuoteHeaderData();
        quoteData.billingPartnerId = partnerA.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf(partnerA.Id),
            '_updatePath' => new List<Object>{ 'QuoteId', String.valueOf(partnerA.Id) },
            'UnitPrice' => 1000.00,
            'Fortra_Product_Type__c' => 'Software',
            'Solution_Category__c' => 'Backup'
        };

        Partner_Pricing_Model__c categoryModel = new Partner_Pricing_Model__c(
            Account__c = partnerA.Id,
            Model_Type__c = 'Discount',
            Solution_Category__c = 'Backup',
            Software_Percent__c = 25.00
        );

        Map<Id, List<Partner_Pricing_Model__c>> partnerModels = new Map<Id, List<Partner_Pricing_Model__c>>{
            partnerA.Id => new List<Partner_Pricing_Model__c>{ categoryModel }
        };

        Map<Id, String> partnerNames = new Map<Id, String>{ partnerA.Id => 'Test Partner A' };

        Test.startTest();
        Map<String, Object> result = prehook.processLineItem(
            lineItem,
            quoteData,
            partnerModels,
            partnerNames,
            new Map<Id, PartnerPricingPrehookV2.LineItemContextData>()
        );
        Test.stopTest();

        Map<String, Object> attributeMap = attributesByName(result);
        System.assertEquals(750.00, attributeMap.get('Partner_Adjusted_Price__c'), 'Context hierarchy values should drive line-level model selection');
        System.assertEquals(25.00, attributeMap.get('PartnerDiscountPercent'), 'Context hierarchy values should produce the matching discount');
        System.assertEquals(750.00, attributeMap.get('NetUnitPrice'), 'Partner discount should propagate to NetUnitPrice');
        System.assertEquals(750.00, attributeMap.get('UnitPrice'), 'Partner discount should propagate to UnitPrice');
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
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

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
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

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
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

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
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

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
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

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

        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

        // Create QuoteHeaderData with Discount model
        PartnerPricingPrehookV2.QuoteHeaderData quoteData = new PartnerPricingPrehookV2.QuoteHeaderData();
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

        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

        // Create QuoteHeaderData with Guaranteed Margin model
        PartnerPricingPrehookV2.QuoteHeaderData quoteData = new PartnerPricingPrehookV2.QuoteHeaderData();
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
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

        Test.startTest();
        Set<Id> result1 = prehook.collectPartnerIds(null);

        PartnerPricingPrehookV2.QuoteHeaderData quoteData = new PartnerPricingPrehookV2.QuoteHeaderData();
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

        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

        // Create QuoteHeaderData with all partner types
        PartnerPricingPrehookV2.QuoteHeaderData quoteData = new PartnerPricingPrehookV2.QuoteHeaderData();
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
        PartnerPricingPrehookV2.QuoteHeaderData completeData = new PartnerPricingPrehookV2.QuoteHeaderData();
        completeData.billingPartnerId = partnerA.Id;
        completeData.partnerPricingModel = 'Guaranteed Margin';
        Boolean hasComplete = completeData.hasPartnerPricing();

        // Test with missing billing partner
        PartnerPricingPrehookV2.QuoteHeaderData noBillingData = new PartnerPricingPrehookV2.QuoteHeaderData();
        noBillingData.partnerPricingModel = 'Guaranteed Margin';
        Boolean hasNoBilling = noBillingData.hasPartnerPricing();

        // Test with missing model
        PartnerPricingPrehookV2.QuoteHeaderData noModelData = new PartnerPricingPrehookV2.QuoteHeaderData();
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
        PartnerPricingPrehookV2.PartnerMarginDetail detail = new PartnerPricingPrehookV2.PartnerMarginDetail(
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

        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

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
        PartnerPricingPrehookV2 prehook = new PartnerPricingPrehookV2();

        Test.startTest();
        // Blank context should return 0 without throwing
        Integer result = prehook.clearPartnerPricingFields('invalid-context-id');
        Test.stopTest();

        System.assertEquals(0, result, 'Invalid context should return 0 cleared lines');
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
}