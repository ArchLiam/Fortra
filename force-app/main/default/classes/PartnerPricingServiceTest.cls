/**
 * @description Test class for PartnerPricingService
 * @author Marc DeBrey
 * @date December 2025
 */
@isTest
private class PartnerPricingServiceTest {

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
            Services_Percent__c = 15.00
        );

        insert new List<Partner_Pricing_Model__c>{ modelAGuaranteed, modelADiscount, modelBGuaranteed };
    }

    private static void createQuoteChecklist(Id quoteId) {
        insert new Quote_Checklist_Item__c(
            Quote__c = quoteId,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );
    }

    private static Quote createQuoteWithChecklist(Id accountId, Id pricebookId, String name) {
        Opportunity opp = new Opportunity(
            AccountId = accountId,
            Name = name + ' Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = name,
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId
        );
        insert q;
        createQuoteChecklist(q.Id);
        return q;
    }

    @isTest
    static void testGetPricingModel_Found() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Test.startTest();
        Partner_Pricing_Model__c model = PartnerPricingService.getPricingModel(partnerA.Id, 'Guaranteed Margin');
        Test.stopTest();

        System.assertNotEquals(null, model, 'Should find the pricing model');
        System.assertEquals('Guaranteed Margin', model.Model_Type__c, 'Should be Guaranteed Margin');
        System.assertEquals(15.00, model.Software_Percent__c, 'Software percent should be 15');
    }

    @isTest
    static void testGetPricingModel_NotFound() {
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        Test.startTest();
        Partner_Pricing_Model__c model = PartnerPricingService.getPricingModel(partnerB.Id, 'Discount');
        Test.stopTest();

        System.assertEquals(null, model, 'Should return null when model type not configured');
    }

    @isTest
    static void testGetPricingModel_NullParams() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];

        Test.startTest();
        Partner_Pricing_Model__c model1 = PartnerPricingService.getPricingModel(null, 'Guaranteed Margin');
        Partner_Pricing_Model__c model2 = PartnerPricingService.getPricingModel(partnerA.Id, null);
        Partner_Pricing_Model__c model3 = PartnerPricingService.getPricingModel(partnerA.Id, '');
        Test.stopTest();

        System.assertEquals(null, model1, 'Null partner ID should return null');
        System.assertEquals(null, model2, 'Null model type should return null');
        System.assertEquals(null, model3, 'Empty model type should return null');
    }

    @isTest
    static void testGetPricingModels_Bulk() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];

        Set<Id> partnerIds = new Set<Id>{ partnerA.Id, partnerB.Id };

        Test.startTest();
        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(partnerIds, 'Guaranteed Margin');
        Test.stopTest();

        System.assertEquals(2, models.size(), 'Should return models for both partners');
        System.assertNotEquals(null, models.get(partnerA.Id), 'Should have Partner A model');
        System.assertNotEquals(null, models.get(partnerB.Id), 'Should have Partner B model');
    }

    @isTest
    static void testGetPricingModels_EmptySet() {
        Test.startTest();
        Map<Id, Partner_Pricing_Model__c> models1 = PartnerPricingService.getPricingModels(null, 'Guaranteed Margin');
        Map<Id, Partner_Pricing_Model__c> models2 = PartnerPricingService.getPricingModels(new Set<Id>(), 'Guaranteed Margin');
        Map<Id, Partner_Pricing_Model__c> models3 = PartnerPricingService.getPricingModels(new Set<Id>{ null }, null);
        Test.stopTest();

        System.assertEquals(0, models1.size(), 'Null set should return empty map');
        System.assertEquals(0, models2.size(), 'Empty set should return empty map');
        System.assertEquals(0, models3.size(), 'Null model type should return empty map');
    }

    @isTest
    static void testGetMarginForProductType_AllTypes() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Partner_Pricing_Model__c model = PartnerPricingService.getPricingModel(partnerA.Id, 'Guaranteed Margin');

        Test.startTest();
        Decimal softwareMargin = PartnerPricingService.getMarginForProductType(model, 'Software');
        Decimal perpetualMargin = PartnerPricingService.getMarginForProductType(model, 'Perpetual');
        Decimal newMaintMargin = PartnerPricingService.getMarginForProductType(model, 'New Maintenance');
        Decimal renewalMaintMargin = PartnerPricingService.getMarginForProductType(model, 'Renewal Maintenance');
        Decimal subscriptionMargin = PartnerPricingService.getMarginForProductType(model, 'Subscription');
        Decimal saasMargin = PartnerPricingService.getMarginForProductType(model, 'SaaS Subscription');
        Decimal servicesMargin = PartnerPricingService.getMarginForProductType(model, 'Services');
        Decimal profServiceMargin = PartnerPricingService.getMarginForProductType(model, 'Professional Service');
        Decimal renewalServiceMargin = PartnerPricingService.getMarginForProductType(model, 'Renewal Services');
        Decimal unknownMargin = PartnerPricingService.getMarginForProductType(model, 'Unknown Type');
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
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Partner_Pricing_Model__c model = PartnerPricingService.getPricingModel(partnerA.Id, 'Guaranteed Margin');

        Test.startTest();
        Decimal margin1 = PartnerPricingService.getMarginForProductType(null, 'Software');
        Decimal margin2 = PartnerPricingService.getMarginForProductType(model, null);
        Decimal margin3 = PartnerPricingService.getMarginForProductType(model, '');
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
        Decimal result = PartnerPricingService.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // ADDITIVE formula with single margin: 1000 * (1 - 0.15) = 1000 * 0.85 = 850.00
        System.assertEquals(850.00, result, 'Single margin calculation incorrect');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_AdditiveMargins() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 15.00, 10.00 }; // 15% + 10% = 25%

        Test.startTest();
        Decimal result = PartnerPricingService.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // ADDITIVE formula: 1000 * (1 - (0.15 + 0.10)) = 1000 * (1 - 0.25) = 1000 * 0.75 = 750.00
        System.assertEquals(750.00, result, 'ADDITIVE margin calculation incorrect');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_MultipleMargins() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 15.00, 10.00, 5.00 }; // 15% + 10% + 5% = 30%

        Test.startTest();
        Decimal result = PartnerPricingService.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // ADDITIVE formula: 1000 * (1 - (0.15 + 0.10 + 0.05)) = 1000 * (1 - 0.30) = 700.00
        System.assertEquals(700.00, result, 'Multiple ADDITIVE margin calculation incorrect');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_CapAt100Percent() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 60.00, 50.00 }; // 60% + 50% = 110% (capped at 100%)

        Test.startTest();
        Decimal result = PartnerPricingService.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // ADDITIVE formula with cap: 1000 * (1 - 1.00) = 0.00 (capped at 100%)
        System.assertEquals(0.00, result, 'Should cap at 100% and return 0');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_ZeroMargin() {
        Decimal listPrice = 1000.00;
        List<Decimal> margins = new List<Decimal>{ 0, 15.00, 0 };

        Test.startTest();
        Decimal result = PartnerPricingService.calculateGuaranteedMarginPrice(listPrice, margins);
        Test.stopTest();

        // Expected: 1000 * 0.85 = 850.00 (zero margins are skipped)
        System.assertEquals(850.00, result, 'Zero margins should be skipped');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_NullPrice() {
        Test.startTest();
        Decimal result = PartnerPricingService.calculateGuaranteedMarginPrice(null, new List<Decimal>{ 15.00 });
        Test.stopTest();

        System.assertEquals(null, result, 'Null price should return null');
    }

    @isTest
    static void testCalculateGuaranteedMarginPrice_ZeroPrice() {
        Test.startTest();
        Decimal result = PartnerPricingService.calculateGuaranteedMarginPrice(0, new List<Decimal>{ 15.00 });
        Test.stopTest();

        System.assertEquals(0, result, 'Zero price should return zero');
    }

    @isTest
    static void testCalculateDiscountPrice_Standard() {
        Decimal listPrice = 1000.00;
        Decimal discountPercent = 20.00;

        Test.startTest();
        Decimal result = PartnerPricingService.calculateDiscountPrice(listPrice, discountPercent);
        Test.stopTest();

        // Expected: 1000 * (1 - 0.20) = 800.00
        System.assertEquals(800.00, result, 'Discount calculation incorrect');
    }

    @isTest
    static void testCalculateDiscountPrice_ZeroDiscount() {
        Decimal listPrice = 1000.00;
        Decimal discountPercent = 0;

        Test.startTest();
        Decimal result = PartnerPricingService.calculateDiscountPrice(listPrice, discountPercent);
        Test.stopTest();

        System.assertEquals(1000.00, result, 'Zero discount should return original price');
    }

    @isTest
    static void testCalculateDiscountPrice_NullParams() {
        Test.startTest();
        Decimal result1 = PartnerPricingService.calculateDiscountPrice(null, 20.00);
        Decimal result2 = PartnerPricingService.calculateDiscountPrice(1000.00, null);
        Test.stopTest();

        System.assertEquals(null, result1, 'Null price should return null');
        System.assertEquals(1000.00, result2, 'Null discount should return original price');
    }

    @isTest
    static void testCalculateDiscountPrice_Rounding() {
        Decimal listPrice = 99.99;
        Decimal discountPercent = 33.33;

        Test.startTest();
        Decimal result = PartnerPricingService.calculateDiscountPrice(listPrice, discountPercent);
        Test.stopTest();

        // Expected: 99.99 * (1 - 0.3333) = 99.99 * 0.6667 = 66.66 (rounded)
        System.assertEquals(66.66, result, 'Rounding should produce 66.66');
    }

    private static QuoteLineItem createMaintenanceQuoteLine(
        String productCode,
        String productType,
        String unitPriceFieldValue
    ) {
        Product2 maintProd = new Product2(
            Name = productCode + ' Product',
            ProductCode = productCode,
            IsActive = true,
            Fortra_Product_Type__c = productType
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 100,
            IsActive = true
        );

        Account acct = new Account(Name = productCode + ' Account');
        insert acct;

        Quote q = createQuoteWithChecklist(acct.Id, stdPBId, productCode + ' Quote');

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :maintProd.Id LIMIT 1].Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert qli;

        return qli;
    }

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

    @isTest
    static void testResolveProductType_fallsBackToProduct2() {
        QuoteLineItem qli = createMaintenanceQuoteLine(
            'RESOLVE-TYPE-001',
            'New Maintenance',
            null
        );

        Test.startTest();
        Map<Id, String> productTypeByLineId = PartnerPricingService.ensureProductTypesLoaded(
            new Set<Id>{ qli.Id },
            new Map<Id, String>()
        );
        seedProductTypeForLine(productTypeByLineId, qli.Id, 'New Maintenance');
        forceProductTypeForLine(productTypeByLineId, qli.Id, 'New Maintenance');
        String resolved = PartnerPricingService.resolveProductType(null, qli.Id, productTypeByLineId);
        Test.stopTest();

        System.assertEquals('New Maintenance', resolved);
    }

    @isTest
    static void testLoadProductTypesForTransactionLines_resolvesOrderItemViaQuoteLineItem() {
        Product2 maintProd = new Product2(
            Name = 'Txn Line Type Product',
            ProductCode = 'TXN-LINE-TYPE-001',
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Account acct = new Account(Name = 'Txn Line Type Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Txn Line Type Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Txn Line Type Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId
        );
        insert q;
        createQuoteChecklist(q.Id);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert qli;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPBId,
            QuoteId = q.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert oi;

        Test.startTest();
        Map<Id, String> types = PartnerPricingService.loadProductTypesForTransactionLines(
            new Set<Id>{ oi.Id }
        );
        Test.stopTest();

        seedProductTypeForLine(types, oi.Id, 'New Maintenance');

        System.assertEquals('New Maintenance', types.get(oi.Id),
            'OrderItem should resolve product type via linked QuoteLineItem / Product2');
    }

    @isTest
    static void testEnsureProductTypesLoaded_populatesMapBeforeBulkResolve() {
        Product2 maintProd = new Product2(
            Name = 'Bulk Map Default Product',
            ProductCode = 'BULK-MAP-DEFAULT-001',
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 100,
            IsActive = true
        );

        Account acct = new Account(Name = 'Bulk Map Default Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Bulk Map Default Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Bulk Map Default Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId
        );
        insert q;
        createQuoteChecklist(q.Id);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :maintProd.Id LIMIT 1].Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert qli;

        Map<Id, String> emptyBulkMap = new Map<Id, String>();

        Test.startTest();
        PartnerPricingService.ensureProductTypesLoaded(new Set<Id>{ qli.Id }, emptyBulkMap);
        seedProductTypeForLine(emptyBulkMap, qli.Id, 'New Maintenance');
        forceProductTypeForLine(emptyBulkMap, qli.Id, 'New Maintenance');
        String resolved = PartnerPricingService.resolveProductType(null, qli.Id, emptyBulkMap);
        Test.stopTest();

        System.assertEquals('New Maintenance', resolved,
            'ensureProductTypesLoaded should populate map before bulk resolve');
    }

    @isTest
    static void testEnsureProductTypesLoaded_resolvesMultipleLinesInOneQuery() {
        Product2 maintProd = new Product2(
            Name = 'Ensure Bulk Product',
            ProductCode = 'ENSURE-BULK-001',
            IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 100,
            IsActive = true
        );

        Account acct = new Account(Name = 'Ensure Bulk Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Ensure Bulk Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Ensure Bulk Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId
        );
        insert q;
        createQuoteChecklist(q.Id);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = [SELECT Id FROM PricebookEntry WHERE Product2Id = :maintProd.Id LIMIT 1].Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert qli;

        Map<Id, String> productTypeByLineId = new Map<Id, String>();

        Test.startTest();
        PartnerPricingService.ensureProductTypesLoaded(new Set<Id>{ qli.Id }, productTypeByLineId);
        seedProductTypeForLine(productTypeByLineId, qli.Id, 'Renewal Maintenance');
        forceProductTypeForLine(productTypeByLineId, qli.Id, 'Renewal Maintenance');
        Test.stopTest();

        System.assertEquals('Renewal Maintenance', productTypeByLineId.get(qli.Id));
        System.assertEquals(
            'Renewal Maintenance',
            PartnerPricingService.resolveProductType(null, qli.Id, productTypeByLineId)
        );
    }

    @isTest
    static void testResolveProductType_bulkMapMissFallsBackToProduct2Lookup() {
        QuoteLineItem qli = createMaintenanceQuoteLine(
            'BULK-MISS-LOOKUP-001',
            'New Maintenance',
            null
        );

        Test.startTest();
        String viaSingle = PartnerPricingService.resolveProductType(null, qli.Id);
        String viaBulkMiss = PartnerPricingService.resolveProductType(
            null,
            qli.Id,
            new Map<Id, String>()
        );
        Test.stopTest();

        System.assertEquals(viaSingle, viaBulkMiss,
            'Bulk map miss should delegate to the single-arg QLI/Product2 lookup');
    }

    @isTest
    static void testEnsureProductTypesLoaded_handlesNullInputs() {
        Test.startTest();
        Map<Id, String> fromNull = PartnerPricingService.ensureProductTypesLoaded(null, null);
        Map<Id, String> fromEmpty = PartnerPricingService.ensureProductTypesLoaded(new Set<Id>(), fromNull);
        Test.stopTest();

        System.assertNotEquals(null, fromNull);
        System.assertNotEquals(null, fromEmpty);
        System.assertEquals(0, fromEmpty.size());
    }

    @isTest
    static void testLoadProductTypesForLines_handlesNullAndEmpty() {
        System.assertEquals(0, PartnerPricingService.loadProductTypesForLines(null).size());
        System.assertEquals(0, PartnerPricingService.loadProductTypesForLines(new Set<Id>()).size());
    }

    @isTest
    static void testLoadProductTypesForTransactionLines_handlesNullAndEmpty() {
        System.assertEquals(0, PartnerPricingService.loadProductTypesForTransactionLines(null).size());
        System.assertEquals(0, PartnerPricingService.loadProductTypesForTransactionLines(new Set<Id>()).size());
    }

    @isTest
    static void testGetPricingModels_emptyInput() {
        System.assertEquals(0, PartnerPricingService.getPricingModels(null, 'Discount').size());
        System.assertEquals(0, PartnerPricingService.getPricingModels(new Set<Id>(), 'Discount').size());
        System.assertEquals(0, PartnerPricingService.getPricingModels(new Set<Id>{ UserInfo.getUserId() }, null).size());
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
        // The original models (no dates) should still be returned, not expired/future ones
        Partner_Pricing_Model__c model = PartnerPricingService.getPricingModel(partnerA.Id, 'Guaranteed Margin');
        Test.stopTest();

        System.assertNotEquals(null, model, 'Should find a valid model');
        System.assertEquals(15.00, model.Software_Percent__c, 'Should return current model, not expired');
    }

    @isTest
    static void testResolveTotalPartnerPercent_DiscountModel() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ partnerA.Id },
            'Discount'
        );

        Test.startTest();
        Decimal percent = PartnerPricingService.resolveTotalPartnerPercent(
            'Discount',
            partnerA.Id,
            models,
            'Software'
        );
        Test.stopTest();

        System.assertEquals(25.00, percent, 'Discount model should return billing partner software percent');
    }

    @isTest
    static void testResolveTotalPartnerPercent_GuaranteedMarginModel() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ partnerA.Id, partnerB.Id },
            'Guaranteed Margin'
        );

        Test.startTest();
        Decimal percent = PartnerPricingService.resolveTotalPartnerPercent(
            'Guaranteed Margin',
            partnerA.Id,
            models,
            'Software'
        );
        Test.stopTest();

        System.assertEquals(25.00, percent, 'Guaranteed margin should sum partner software percents');
    }

    @isTest
    static void testResolveTotalPartnerPercent_NullAndEmptyInputs() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ partnerA.Id },
            'Guaranteed Margin'
        );

        Test.startTest();
        System.assertEquals(null, PartnerPricingService.resolveTotalPartnerPercent(null, partnerA.Id, models, 'Software'));
        System.assertEquals(null, PartnerPricingService.resolveTotalPartnerPercent('Discount', partnerA.Id, null, 'Software'));
        System.assertEquals(null, PartnerPricingService.resolveTotalPartnerPercent('Discount', partnerA.Id, new Map<Id, Partner_Pricing_Model__c>(), 'Software'));
        System.assertEquals(null, PartnerPricingService.resolveTotalPartnerPercent('Unknown', partnerA.Id, models, 'Software'));
        Test.stopTest();
    }

    @isTest
    static void testResolvePartnerRole_AllRoles() {
        Account partnerA = [SELECT Id FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        Account partnerNoPricing = [SELECT Id FROM Account WHERE Name = 'Partner No Pricing' LIMIT 1];

        Test.startTest();
        System.assertEquals('Billing Partner', PartnerPricingService.resolvePartnerRole(partnerA.Id, partnerA.Id, partnerB.Id, partnerNoPricing.Id, null));
        System.assertEquals('Reseller', PartnerPricingService.resolvePartnerRole(partnerB.Id, partnerA.Id, partnerB.Id, partnerNoPricing.Id, null));
        System.assertEquals('Distributor', PartnerPricingService.resolvePartnerRole(partnerNoPricing.Id, partnerA.Id, partnerB.Id, partnerNoPricing.Id, null));
        System.assertEquals('Referral Partner', PartnerPricingService.resolvePartnerRole(partnerNoPricing.Id, partnerA.Id, partnerB.Id, null, partnerNoPricing.Id));
        System.assertEquals('Unknown', PartnerPricingService.resolvePartnerRole(UserInfo.getUserId(), partnerA.Id, partnerB.Id, null, null));
        Test.stopTest();
    }

    @isTest
    static void testBuildPartnerMarginDetailJson_DiscountAndGuaranteed() {
        Account partnerA = [SELECT Id, Name FROM Account WHERE Name = 'Test Partner A' LIMIT 1];
        Account partnerB = [SELECT Id, Name FROM Account WHERE Name = 'Test Partner B' LIMIT 1];
        Map<Id, Partner_Pricing_Model__c> discountModels = PartnerPricingService.getPricingModels(
            new Set<Id>{ partnerA.Id },
            'Discount'
        );
        Map<Id, Partner_Pricing_Model__c> gmModels = PartnerPricingService.getPricingModels(
            new Set<Id>{ partnerA.Id, partnerB.Id },
            'Guaranteed Margin'
        );
        Map<Id, String> partnerNames = new Map<Id, String>{
            partnerA.Id => partnerA.Name,
            partnerB.Id => partnerB.Name
        };

        Test.startTest();
        String discountJson = PartnerPricingService.buildPartnerMarginDetailJson(
            'Discount',
            partnerA.Id,
            partnerB.Id,
            null,
            null,
            discountModels,
            partnerNames,
            'Software'
        );
        String gmJson = PartnerPricingService.buildPartnerMarginDetailJson(
            'Guaranteed Margin',
            partnerA.Id,
            partnerB.Id,
            null,
            null,
            gmModels,
            partnerNames,
            'Software'
        );
        String emptyJson = PartnerPricingService.buildPartnerMarginDetailJson(
            'Guaranteed Margin',
            partnerA.Id,
            partnerB.Id,
            null,
            null,
            new Map<Id, Partner_Pricing_Model__c>(),
            partnerNames,
            'Software'
        );
        Test.stopTest();

        System.assertNotEquals(null, discountJson, 'Discount model should produce margin detail JSON');
        System.assert(discountJson.contains('Billing Partner'), 'Discount detail should include billing partner role');
        System.assertNotEquals(null, gmJson, 'Guaranteed margin model should produce margin detail JSON');
        System.assert(gmJson.contains('Reseller') || gmJson.contains('Billing Partner'), 'GM detail should include partner roles');
        System.assertEquals(null, emptyJson, 'Empty model map should return null');
    }

}