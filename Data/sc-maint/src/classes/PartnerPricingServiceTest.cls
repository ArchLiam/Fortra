/**
 * @description Behavioral coverage for PartnerPricingService (SC-3346 Maintenance/Derived Pricing).
 *              Exercises pricing-model lookup, product-type resolution (context / line / product /
 *              bulk-map / OrderItem fallback), margin selection per product type, and the additive
 *              guaranteed-margin / discount price math including all guard and cap branches.
 */
@IsTest
private class PartnerPricingServiceTest {

    // ---- helpers -------------------------------------------------------

    private static Account newPartner(String name) {
        Account partner = new Account(Name = name, Type = 'Partner');
        insert partner;
        return partner;
    }

    private static Partner_Pricing_Model__c newModel(Id partnerId, String modelType) {
        Partner_Pricing_Model__c model = new Partner_Pricing_Model__c(
            Account__c = partnerId,
            Model_Type__c = modelType,
            Is_Active__c = true,
            Is_Default__c = true,
            Software_Percent__c = 15,
            New_Maintenance_Percent__c = 12,
            Renewal_Maintenance_Percent__c = 10,
            Subscription_Percent__c = 20,
            Services_Percent__c = 25
        );
        insert model;
        return model;
    }

    private static Product2 newProduct(String code, String fortraType) {
        Product2 prod = new Product2(
            Name = code,
            ProductCode = code,
            IsActive = true,
            Fortra_Product_Type__c = fortraType
        );
        insert prod;
        return prod;
    }

    private static PricebookEntry newPbe(Id productId) {
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productId,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }

    private static Quote newQuote() {
        Account acct = new Account(Name = 'PPS Acct');
        insert acct;
        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'PPS Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Quote q = new Quote(
            Name = 'PPS Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert q;
        return q;
    }

    // ---- getPricingModel ----------------------------------------------

    @IsTest
    static void getPricingModel_nullAndBlankReturnNull() {
        System.assertEquals(null, PartnerPricingService.getPricingModel(null, 'Discount'),
            'Null partner id returns null');
        System.assertEquals(null, PartnerPricingService.getPricingModel(UserInfo.getUserId(), '  '),
            'Blank model type returns null');
    }

    @IsTest
    static void getPricingModel_returnsActiveMatch() {
        Account partner = newPartner('GPM Partner');
        newModel(partner.Id, 'Discount');

        Test.startTest();
        Partner_Pricing_Model__c found = PartnerPricingService.getPricingModel(partner.Id, 'Discount');
        Partner_Pricing_Model__c miss = PartnerPricingService.getPricingModel(partner.Id, 'Guaranteed Margin');
        Test.stopTest();

        System.assertNotEquals(null, found, 'Active matching model is returned');
        System.assertEquals(partner.Id, found.Account__c);
        System.assertEquals(12, found.New_Maintenance_Percent__c);
        System.assertEquals(null, miss, 'No model for the other model type returns null');
    }

    // ---- getPricingModels (bulk) --------------------------------------

    @IsTest
    static void getPricingModels_nullEmptyBlankReturnEmpty() {
        System.assertEquals(true,
            PartnerPricingService.getPricingModels(null, 'Discount').isEmpty());
        System.assertEquals(true,
            PartnerPricingService.getPricingModels(new Set<Id>(), 'Discount').isEmpty());
        System.assertEquals(true,
            PartnerPricingService.getPricingModels(new Set<Id>{ UserInfo.getUserId() }, '').isEmpty());
    }

    @IsTest
    static void getPricingModels_mapsByPartner() {
        Account p1 = newPartner('GPMs Partner 1');
        Account p2 = newPartner('GPMs Partner 2');
        newModel(p1.Id, 'Guaranteed Margin');
        newModel(p2.Id, 'Guaranteed Margin');

        Test.startTest();
        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ p1.Id, p2.Id }, 'Guaranteed Margin'
        );
        Test.stopTest();

        System.assertEquals(2, models.size(), 'Both partners resolved');
        System.assertEquals(p1.Id, models.get(p1.Id).Account__c);
        System.assertEquals(p2.Id, models.get(p2.Id).Account__c);
    }

    // ---- resolveProductType (2-arg, SOQL) -----------------------------

    @IsTest
    static void resolveProductType_contextWins() {
        System.assertEquals('Subscription',
            PartnerPricingService.resolveProductType('Subscription', null),
            'Non-blank context type short-circuits');
    }

    @IsTest
    static void resolveProductType_nullLineDefaultsSoftware() {
        System.assertEquals('Software',
            PartnerPricingService.resolveProductType('', null),
            'Blank context + null line id defaults to Software');
    }

    @IsTest
    static void resolveProductType_usesLineLevelWhenPresent() {
        Product2 prod = newProduct('PPS-RPT-PROD', 'Subscription');
        PricebookEntry pbe = newPbe(prod.Id);
        Quote q = newQuote();

        QuoteLineItem lineLevelSet = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = prod.Id,
            Quantity = 1, UnitPrice = 50, Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert lineLevelSet;

        Test.startTest();
        String resolved = PartnerPricingService.resolveProductType('', lineLevelSet.Id);
        Test.stopTest();

        // Line-level value (Renewal Maintenance) is authoritative when present.
        System.assertEquals('Renewal Maintenance', resolved);
    }

    @IsTest
    static void resolveProductType_fallsBackToProductLevel() {
        // Product-level type populated; line-level genuinely blank. The org flow
        // defaults a blank line-level type to 'Software' ON INSERT, but a post-insert
        // update-to-null sticks, leaving the line-level field empty so the Product2
        // fallback branch is exercised.
        Product2 prod = newProduct('PPS-RPT-P2', 'New Maintenance');
        PricebookEntry pbe = newPbe(prod.Id);
        Quote q = newQuote();

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = prod.Id,
            Quantity = 1, UnitPrice = 50
        );
        insert qli;
        qli.Fortra_Product_Type__c = null;
        update qli;

        QuoteLineItem reloaded = [
            SELECT Fortra_Product_Type__c FROM QuoteLineItem WHERE Id = :qli.Id
        ];
        System.assertEquals(null, reloaded.Fortra_Product_Type__c,
            'Precondition: line-level type is blank so the Product2 fallback runs');

        Test.startTest();
        String resolved = PartnerPricingService.resolveProductType('', qli.Id);
        Test.stopTest();

        System.assertEquals('New Maintenance', resolved,
            'Blank line-level type falls back to Product2.Fortra_Product_Type__c');
    }

    // ---- resolveProductType (3-arg, bulk map) -------------------------

    @IsTest
    static void resolveProductType_bulkContextWins() {
        System.assertEquals('Services',
            PartnerPricingService.resolveProductType('Services', null, new Map<Id, String>()),
            'Context type wins in bulk overload too');
    }

    @IsTest
    static void resolveProductType_bulkMapHitAndMiss() {
        String prefix = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix();
        Id qliId = Id.valueOf(prefix + '000000000001');
        Id otherId = Id.valueOf(prefix + '000000000002');
        Map<Id, String> typeByLineId = new Map<Id, String>{ qliId => 'New Maintenance' };

        System.assertEquals('New Maintenance',
            PartnerPricingService.resolveProductType('', qliId, typeByLineId),
            'Map hit returns the mapped type');

        System.assertEquals('Software',
            PartnerPricingService.resolveProductType('', otherId, typeByLineId),
            'Map miss (with non-null map and id) defaults to Software');
    }

    @IsTest
    static void resolveProductType_bulkNullMapDelegatesToSoql() {
        Product2 prod = newProduct('PPS-RPT-DELEG', 'Subscription');
        PricebookEntry pbe = newPbe(prod.Id);
        Quote q = newQuote();
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = prod.Id,
            Quantity = 1, UnitPrice = 50, Fortra_Product_Type__c = 'Services'
        );
        insert qli;

        Test.startTest();
        String resolved = PartnerPricingService.resolveProductType('', qli.Id, null);
        Test.stopTest();

        System.assertEquals('Services', resolved,
            'Null bulk map falls back to the SOQL overload');
    }

    // ---- loadProductTypesForLines -------------------------------------

    @IsTest
    static void loadProductTypesForLines_nullEmpty() {
        System.assertEquals(true, PartnerPricingService.loadProductTypesForLines(null).isEmpty());
        System.assertEquals(true, PartnerPricingService.loadProductTypesForLines(new Set<Id>()).isEmpty());
    }

    @IsTest
    static void loadProductTypesForLines_lineAndProductLevel() {
        Product2 prodTyped = newProduct('PPS-LPTL-A', 'Subscription');
        Product2 prodForP2 = newProduct('PPS-LPTL-B', 'Services');
        PricebookEntry pbeA = newPbe(prodTyped.Id);
        PricebookEntry pbeB = newPbe(prodForP2.Id);
        Quote q = newQuote();

        // lineA carries an explicit line-level type (preferred path).
        QuoteLineItem lineA = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbeA.Id, Product2Id = prodTyped.Id,
            Quantity = 1, UnitPrice = 10, Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        // lineB will have its line-level type cleared so it resolves via Product2 (Services).
        QuoteLineItem lineB = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbeB.Id, Product2Id = prodForP2.Id,
            Quantity = 1, UnitPrice = 10
        );
        insert new List<QuoteLineItem>{ lineA, lineB };

        lineB.Fortra_Product_Type__c = null;
        update lineB;

        Test.startTest();
        Map<Id, String> result = PartnerPricingService.loadProductTypesForLines(
            new Set<Id>{ lineA.Id, lineB.Id }
        );
        Test.stopTest();

        System.assertEquals('Renewal Maintenance', result.get(lineA.Id),
            'Line-level type wins when present');
        System.assertEquals('Services', result.get(lineB.Id),
            'Blank line-level type falls back to Product2 type');
    }

    // ---- loadProductTypesForTransactionLines --------------------------

    @IsTest
    static void loadProductTypesForTransactionLines_nullEmpty() {
        System.assertEquals(true,
            PartnerPricingService.loadProductTypesForTransactionLines(null).isEmpty());
        System.assertEquals(true,
            PartnerPricingService.loadProductTypesForTransactionLines(new Set<Id>()).isEmpty());
    }

    @IsTest
    static void loadProductTypesForTransactionLines_qliAndOrderItem() {
        Product2 prod = newProduct('PPS-TXN-PROD', 'Subscription');
        PricebookEntry pbe = newPbe(prod.Id);
        Quote q = newQuote();

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = prod.Id,
            Quantity = 1, UnitPrice = 50, Fortra_Product_Type__c = 'Subscription'
        );
        insert qli;

        Order ord = new Order(
            AccountId = [SELECT AccountId FROM Quote WHERE Id = :q.Id].AccountId,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        // OrderItem whose own/product type resolves directly.
        OrderItem oiDirect = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 60,
            Fortra_Product_Type__c = 'Services'
        );
        insert oiDirect;

        Test.startTest();
        Map<Id, String> result = PartnerPricingService.loadProductTypesForTransactionLines(
            new Set<Id>{ qli.Id, oiDirect.Id }
        );
        Test.stopTest();

        System.assertEquals('Subscription', result.get(qli.Id), 'QLI resolved directly');
        System.assertEquals('Services', result.get(oiDirect.Id), 'OrderItem resolved directly');
    }

    @IsTest
    static void loadProductTypesForTransactionLines_allResolvedByQliShortCircuits() {
        // When every transaction line is a QLI that resolves up front, there are no
        // unresolved OrderItem ids and the method returns early without the OI query.
        Product2 prod = newProduct('PPS-TXN-ALLQLI', 'Subscription');
        PricebookEntry pbe = newPbe(prod.Id);
        Quote q = newQuote();
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = prod.Id,
            Quantity = 1, UnitPrice = 50, Fortra_Product_Type__c = 'Subscription'
        );
        insert qli;

        Test.startTest();
        Map<Id, String> result = PartnerPricingService.loadProductTypesForTransactionLines(
            new Set<Id>{ qli.Id }
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Single fully-resolved QLI');
        System.assertEquals('Subscription', result.get(qli.Id));
    }

    @IsTest
    static void loadProductTypesForTransactionLines_orderItemFallsBackToQli() {
        // OrderItem with no line/product type, but linked QLI carries the type.
        Product2 prodBlank = newProduct('PPS-TXN-BLANK', null);
        PricebookEntry pbe = newPbe(prodBlank.Id);
        Quote q = newQuote();

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = prodBlank.Id,
            Quantity = 1, UnitPrice = 50, Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert qli;

        // Order must reference the Quote so the OrderItem can link to a QLI on that Quote.
        // The Quote needs a checklist item to satisfy the org "No checklist items" VR.
        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id, Item_Name__c = 'Checklist Item', Sort_Order__c = 1, Is_Checked__c = true
        );

        Order ord = new Order(
            AccountId = [SELECT AccountId FROM Quote WHERE Id = :q.Id].AccountId,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prodBlank.Id,
            Quantity = 1,
            UnitPrice = 60
        );
        insert oi;

        // Null out the OrderItem line-level type so it must fall back to the QLI.
        OrderItem reloaded = [SELECT Id, Fortra_Product_Type__c FROM OrderItem WHERE Id = :oi.Id];
        if (reloaded.Fortra_Product_Type__c != null) {
            reloaded.Fortra_Product_Type__c = null;
            update reloaded;
        }

        Test.startTest();
        Map<Id, String> result = PartnerPricingService.loadProductTypesForTransactionLines(
            new Set<Id>{ oi.Id }
        );
        Test.stopTest();

        System.assertEquals('Renewal Maintenance', result.get(oi.Id),
            'OrderItem with blank type falls back to its source QuoteLineItem type');
    }

    // ---- getMarginForProductType --------------------------------------

    @IsTest
    static void getMarginForProductType_guards() {
        Partner_Pricing_Model__c model = new Partner_Pricing_Model__c(Software_Percent__c = 15);
        System.assertEquals(0, PartnerPricingService.getMarginForProductType(null, 'Software'),
            'Null model returns 0');
        System.assertEquals(0, PartnerPricingService.getMarginForProductType(model, ''),
            'Blank product type returns 0');
        System.assertEquals(0, PartnerPricingService.getMarginForProductType(model, 'Unknown Type'),
            'Unmapped product type returns 0');
    }

    @IsTest
    static void getMarginForProductType_allMappedTypes() {
        Partner_Pricing_Model__c model = new Partner_Pricing_Model__c(
            Software_Percent__c = 15,
            New_Maintenance_Percent__c = 12,
            Renewal_Maintenance_Percent__c = 10,
            Subscription_Percent__c = 20,
            Services_Percent__c = 25
        );

        System.assertEquals(15, PartnerPricingService.getMarginForProductType(model, 'Software'));
        System.assertEquals(15, PartnerPricingService.getMarginForProductType(model, 'Perpetual'));
        System.assertEquals(12, PartnerPricingService.getMarginForProductType(model, 'New Maintenance'));
        System.assertEquals(10, PartnerPricingService.getMarginForProductType(model, 'Renewal Maintenance'));
        System.assertEquals(20, PartnerPricingService.getMarginForProductType(model, 'Subscription'));
        System.assertEquals(20, PartnerPricingService.getMarginForProductType(model, 'SaaS Subscription'));
        System.assertEquals(25, PartnerPricingService.getMarginForProductType(model, 'Services'));
        System.assertEquals(25, PartnerPricingService.getMarginForProductType(model, 'Professional Service'));
        System.assertEquals(25, PartnerPricingService.getMarginForProductType(model, 'Renewal Services'));
    }

    @IsTest
    static void getMarginForProductType_nullPercentDefaultsZero() {
        // Every mapped percent null -> each branch returns 0 via its null-guard.
        Partner_Pricing_Model__c empty = new Partner_Pricing_Model__c();
        System.assertEquals(0, PartnerPricingService.getMarginForProductType(empty, 'Software'));
        System.assertEquals(0, PartnerPricingService.getMarginForProductType(empty, 'New Maintenance'));
        System.assertEquals(0, PartnerPricingService.getMarginForProductType(empty, 'Renewal Maintenance'));
        System.assertEquals(0, PartnerPricingService.getMarginForProductType(empty, 'Subscription'));
        System.assertEquals(0, PartnerPricingService.getMarginForProductType(empty, 'Services'));
    }

    // ---- calculateGuaranteedMarginPrice -------------------------------

    @IsTest
    static void calculateGuaranteedMarginPrice_guards() {
        System.assertEquals(null,
            PartnerPricingService.calculateGuaranteedMarginPrice(null, new List<Decimal>{ 10 }),
            'Null list price returns null');
        System.assertEquals(0,
            PartnerPricingService.calculateGuaranteedMarginPrice(0, new List<Decimal>{ 10 }),
            'Zero list price returns zero');
        System.assertEquals(1000,
            PartnerPricingService.calculateGuaranteedMarginPrice(1000, null),
            'Null margins returns list price');
        System.assertEquals(1000,
            PartnerPricingService.calculateGuaranteedMarginPrice(1000, new List<Decimal>()),
            'Empty margins returns list price');
    }

    @IsTest
    static void calculateGuaranteedMarginPrice_additiveAndIgnoresNonPositive() {
        // [15, 10] additive => 1000 * (1 - 0.25) = 750. Null/zero/negative margins ignored.
        Decimal price = PartnerPricingService.calculateGuaranteedMarginPrice(
            1000, new List<Decimal>{ 15, 10, null, 0, -5 }
        );
        System.assertEquals(750.00, price);
    }

    @IsTest
    static void calculateGuaranteedMarginPrice_capsAtHundred() {
        // 80 + 50 = 130 -> capped at 100 -> multiplier 0 -> price 0.
        Decimal price = PartnerPricingService.calculateGuaranteedMarginPrice(
            1000, new List<Decimal>{ 80, 50 }
        );
        System.assertEquals(0.00, price);
    }

    // ---- calculateDiscountPrice ---------------------------------------

    @IsTest
    static void calculateDiscountPrice_guards() {
        System.assertEquals(null, PartnerPricingService.calculateDiscountPrice(null, 20),
            'Null list price returns null');
        System.assertEquals(0, PartnerPricingService.calculateDiscountPrice(0, 20),
            'Zero list price returns zero');
        System.assertEquals(1000, PartnerPricingService.calculateDiscountPrice(1000, null),
            'Null discount returns list price');
        System.assertEquals(1000, PartnerPricingService.calculateDiscountPrice(1000, 0),
            'Zero discount returns list price');
        System.assertEquals(1000, PartnerPricingService.calculateDiscountPrice(1000, -5),
            'Negative discount returns list price');
    }

    @IsTest
    static void calculateDiscountPrice_appliesPercent() {
        System.assertEquals(800.00, PartnerPricingService.calculateDiscountPrice(1000, 20));
        System.assertEquals(62.48, PartnerPricingService.calculateDiscountPrice(71, 12));
    }
}
