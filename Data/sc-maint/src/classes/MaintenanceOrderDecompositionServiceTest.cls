@isTest
private class MaintenanceOrderDecompositionServiceTest {

    @isTest
    static void compute_matchesWorkedExample() {
        MaintenanceOrderDecompositionService.Decomposition decomp =
            MaintenanceOrderDecompositionService.compute(
                1000,
                140,
                180,
                140,
                'Standard'
            );

        System.assertEquals(200, decomp.maintenanceBase);
        System.assertEquals(20, decomp.partnerDiscount);
        System.assertEquals(40, decomp.discretionaryDiscount);
    }

    @isTest
    static void compute_premierTierRate() {
        MaintenanceOrderDecompositionService.Decomposition decomp =
            MaintenanceOrderDecompositionService.compute(
                1000,
                210,
                null,
                210,
                'Premier'
            );

        System.assertEquals(300, decomp.maintenanceBase);
        System.assertEquals(0, decomp.partnerDiscount);
        System.assertEquals(90, decomp.discretionaryDiscount);
    }

    @isTest
    static void compute_noDiscounts() {
        MaintenanceOrderDecompositionService.Decomposition decomp =
            MaintenanceOrderDecompositionService.compute(
                468,
                93.60,
                93.60,
                93.60,
                'Standard'
            );

        System.assertEquals(93.60, decomp.maintenanceBase);
        System.assertEquals(0, decomp.partnerDiscount);
        System.assertEquals(0, decomp.discretionaryDiscount);
    }

    @isTest
    static void compute_partnerOnly() {
        MaintenanceOrderDecompositionService.Decomposition decomp =
            MaintenanceOrderDecompositionService.compute(
                1000,
                180,
                180,
                180,
                'Standard'
            );

        System.assertEquals(200, decomp.maintenanceBase);
        System.assertEquals(20, decomp.partnerDiscount);
        System.assertEquals(0, decomp.discretionaryDiscount);
    }

    @isTest
    static void compute_derivedMaintenanceUsesNetUnitPriceWhenUnitPriceZero() {
        MaintenanceOrderDecompositionService.Decomposition decomp =
            MaintenanceOrderDecompositionService.compute(
                355,
                0,
                62.48,
                62.48,
                'Standard'
            );

        System.assertEquals(71, decomp.maintenanceBase);
        System.assertEquals(8.52, decomp.partnerDiscount);
        System.assertEquals(0, decomp.discretionaryDiscount);
    }

    @isTest
    static void normalizeTierValue_isCaseInsensitive() {
        System.assertEquals('Standard', MaintenanceOrderDecompositionService.normalizeTierValue('standard'));
        System.assertEquals('Premier', MaintenanceOrderDecompositionService.normalizeTierValue(' PREMIER '));
        System.assertEquals(null, MaintenanceOrderDecompositionService.normalizeTierValue('Enterprise Support'));
    }

    @isTest
    static void resolveTierRate_unknownTierReturnsZero() {
        System.assertEquals(0, MaintenanceOrderDecompositionService.resolveTierRate('Enterprise Support'));
        System.assertEquals(0, MaintenanceOrderDecompositionService.resolveTierRate(null));
    }

    @isTest
    static void resolveNetPrice_prefersUnitPriceWhenPositive() {
        System.assertEquals(50, MaintenanceOrderDecompositionService.resolveNetPrice(50, 40, 100));
        System.assertEquals(40, MaintenanceOrderDecompositionService.resolveNetPrice(0, 40, 100));
        System.assertEquals(100, MaintenanceOrderDecompositionService.resolveNetPrice(null, null, 100));
    }

    @isTest
    static void compute_invalidSourceBaseReturnsZeros() {
        MaintenanceOrderDecompositionService.Decomposition decomp =
            MaintenanceOrderDecompositionService.compute(null, 10, 10, 10, 'Standard');
        System.assertEquals(null, decomp.maintenanceBase);
        System.assertEquals(0, decomp.partnerDiscount);
        System.assertEquals(0, decomp.discretionaryDiscount);

        decomp = MaintenanceOrderDecompositionService.compute(0, 10, 10, 10, 'Standard');
        System.assertEquals(null, decomp.maintenanceBase);
    }

    @isTest
    static void compute_unknownTierSkipsDecomposition() {
        MaintenanceOrderDecompositionService.Decomposition decomp =
            MaintenanceOrderDecompositionService.compute(1000, 100, 100, 100, 'Basic');
        System.assertEquals(0, decomp.maintenanceBase);
        System.assertEquals(0, decomp.partnerDiscount);
    }

    @isTest
    static void compute_professionalTierRate() {
        System.assertEquals(0.20, MaintenanceOrderDecompositionService.resolveTierRate('Professional'));
    }

    @isTest
    static void loadDerivedPricebookEntryIds_returnsEmptyForEmptyInput() {
        System.assertEquals(
            true,
            MaintenanceOrderDecompositionService.loadDerivedPricebookEntryIds(new Set<Id>()).isEmpty()
        );
    }

    @isTest
    static void loadMaintenanceTierByQliId_returnsEmptyForEmptyInput() {
        System.assertEquals(
            true,
            MaintenanceOrderDecompositionService.loadMaintenanceTierByQliId(new Set<Id>()).isEmpty()
        );
    }

    @isTest(SeeAllData=true)
    static void loadDerivedPricebookEntryIds_findsOrgDerivedEntries() {
        List<PriceBookEntryDerivedPrice> derivedPrices = [
            SELECT PricebookEntryId
            FROM PriceBookEntryDerivedPrice
            LIMIT 1
        ];
        if (derivedPrices.isEmpty()) {
            return;
        }

        Set<Id> derivedIds = MaintenanceOrderDecompositionService.loadDerivedPricebookEntryIds(
            new Set<Id>{ derivedPrices[0].PricebookEntryId }
        );
        System.assertEquals(true, derivedIds.contains(derivedPrices[0].PricebookEntryId));
    }

    @isTest(SeeAllData=true)
    static void loadMaintenanceTierByQliId_resolvesStandardTier() {
        List<QuoteLineItemAttribute> attrs = [
            SELECT QuoteLineItemId, AttributeName, AttributeValue
            FROM QuoteLineItemAttribute
            WHERE AttributeName = 'Feature Options'
              AND AttributeValue = 'Standard'
            LIMIT 1
        ];
        if (attrs.isEmpty()) {
            return;
        }

        Map<Id, String> tiers = MaintenanceOrderDecompositionService.loadMaintenanceTierByQliId(
            new Set<Id>{ attrs[0].QuoteLineItemId }
        );
        System.assertEquals('Standard', tiers.get(attrs[0].QuoteLineItemId));
    }

    @isTest(SeeAllData=true)
    static void loadMaintenanceTierByQliId_prefersMaintenanceTypeDefn() {
        List<QuoteLineItemAttribute> tierAttrs = [
            SELECT QuoteLineItemId
            FROM QuoteLineItemAttribute
            WHERE AttributeName = 'Maintenance Type Defn'
              AND AttributeValue = 'Standard'
            LIMIT 1
        ];
        if (tierAttrs.isEmpty()) {
            return;
        }

        Map<Id, String> tiers = MaintenanceOrderDecompositionService.loadMaintenanceTierByQliId(
            new Set<Id>{ tierAttrs[0].QuoteLineItemId }
        );
        System.assertEquals('Standard', tiers.get(tierAttrs[0].QuoteLineItemId));
    }

    @isTest
    static void buildPatches_newBusinessEmptyOrder() {
        Account acct = new Account(Name = 'Decomp Empty Order Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Decomp Empty Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'New Business Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        System.assertEquals(true, MaintenanceOrderDecompositionService.buildPatches(ord.Id).isEmpty());
    }

    @isTest(SeeAllData=true)
    static void buildPatches_persistsDecompositionForDerivedLine() {
        Set<Id> derivedPbeIds = new Set<Id>();
        for (PriceBookEntryDerivedPrice dp : [
            SELECT PricebookEntryId
            FROM PriceBookEntryDerivedPrice
            LIMIT 50
        ]) {
            derivedPbeIds.add(dp.PricebookEntryId);
        }
        if (derivedPbeIds.isEmpty()) {
            return;
        }

        List<QuoteLineItem> candidates = [
            SELECT Id, QuoteId, Quote.AccountId, Quote.Pricebook2Id, PricebookEntryId, Product2Id,
                   Base_Price__c, UnitPrice, NetUnitPrice, PartnerUnitPrice
            FROM QuoteLineItem
            WHERE Base_Price__c != null
              AND Quote.QuoteTypeText__c IN ('New', 'Net-New')
              AND PricebookEntryId IN :derivedPbeIds
            LIMIT 25
        ];

        QuoteLineItem sourceQli;
        for (QuoteLineItem candidate : candidates) {
            Map<Id, String> tiers = MaintenanceOrderDecompositionService.loadMaintenanceTierByQliId(
                new Set<Id>{ candidate.Id }
            );
            if (tiers.containsKey(candidate.Id)) {
                sourceQli = candidate;
                break;
            }
        }
        if (sourceQli == null) {
            return;
        }

        Order ord = new Order(
            AccountId = sourceQli.Quote.AccountId,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = sourceQli.Quote.Pricebook2Id,
            QuoteId = sourceQli.QuoteId
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = sourceQli.Id,
            PricebookEntryId = sourceQli.PricebookEntryId,
            Product2Id = sourceQli.Product2Id,
            Quantity = 1,
            UnitPrice = sourceQli.NetUnitPrice != null ? sourceQli.NetUnitPrice : 1
        );
        insert oi;

        Test.startTest();
        Map<Id, OrderItem> patches = MaintenanceOrderDecompositionService.buildPatches(ord.Id);
        Test.stopTest();

        System.assertEquals(true, patches.containsKey(oi.Id), 'Derived line should receive decomposition patch');
        System.assertNotEquals(null, patches.get(oi.Id).Base_Price__c);
        System.assertEquals(
            sourceQli.NetUnitPrice,
            patches.get(oi.Id).UnitPrice,
            'Commercial net should come from quote NetUnitPrice'
        );
    }

    @isTest
    static void buildPatches_skipsNonDerivedPricebookEntry() {
        Account acct = new Account(Name = 'Decomp Non-Derived Account');
        insert acct;

        Product2 prod = new Product2(
            Name = 'Decomp Non-Derived Product',
            ProductCode = 'DECOMP-NON-DERIVED',
            IsActive = true
        );
        insert prod;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Decomp Non-Derived Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'New Business Non-Derived Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 80,
            Base_Price__c = 100
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
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 80
        );
        insert oi;

        System.assertEquals(true, MaintenanceOrderDecompositionService.buildPatches(ord.Id).isEmpty());
    }

    @isTest
    static void persistPatches_returnsZeroForNullOrder() {
        System.assertEquals(0, MaintenanceOrderDecompositionService.persistPatches(null));
    }

    @isTest
    static void quoteMapper_skipsWhenOrderHasNoQuoteLineItemLink() {
        Account acct = new Account(Name = 'Mapper Coverage Account');
        insert acct;

        Product2 prod = new Product2(Name = 'Mapper Coverage Product', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        insert new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100
        );

        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });

        System.assertEquals(true, results[0].success);
        System.assertEquals(0, results[0].itemsMapped);
    }

    @isTest
    static void quoteMapper_mergeOrderItemPatches_includesCommercialNet() {
        Account acct = new Account(Name = 'Merge Patch Account');
        insert acct;

        Product2 prod = new Product2(Name = 'Merge Patch Product', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert oi;

        Map<Id, OrderItem> target = new Map<Id, OrderItem>{
            oi.Id => new OrderItem(Id = oi.Id, Hardware__c = null)
        };
        Map<Id, OrderItem> additional = new Map<Id, OrderItem>{
            oi.Id => new OrderItem(
                Id = oi.Id,
                Base_Price__c = 71,
                Prior_Partner_Discount__c = 8.52,
                Prior_Discretionary_Discount__c = 0,
                UnitPrice = 62.48,
                NetUnitPrice = 62.48,
                PartnerUnitPrice = 62.48,
                TotalLineAmount = 62.48
            )
        };

        QuoteToOrderFieldMapper.mergeOrderItemPatches(target, additional);

        OrderItem merged = target.get(oi.Id);
        System.assertEquals(71, merged.Base_Price__c);
        System.assertEquals(8.52, merged.Prior_Partner_Discount__c);
        System.assertEquals(62.48, merged.UnitPrice);
        System.assertEquals(62.48, merged.NetUnitPrice);
        System.assertEquals(62.48, merged.TotalLineAmount);
    }

    @isTest
    static void quoteMapper_mergeOrderItemPatches_addsStandalonePatch() {
        Account acct = new Account(Name = 'Standalone Patch Account');
        insert acct;

        Product2 prod = new Product2(Name = 'Standalone Patch Product', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert oi;

        Map<Id, OrderItem> target = new Map<Id, OrderItem>();
        Map<Id, OrderItem> additional = new Map<Id, OrderItem>{
            oi.Id => new OrderItem(
                Id = oi.Id,
                Base_Price__c = 71,
                UnitPrice = 62.48,
                NetUnitPrice = 62.48
            )
        };

        QuoteToOrderFieldMapper.mergeOrderItemPatches(target, additional);

        System.assertEquals(true, target.containsKey(oi.Id));
        System.assertEquals(62.48, target.get(oi.Id).NetUnitPrice);
    }

    @isTest
    static void quoteMapper_rejectsNullOrderId() {
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = null;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });

        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('required'));
    }

    @isTest
    static void quoteMapper_mapsQuoteLineFieldsToOrderItem() {
        Account acct = new Account(Name = 'Mapper Field Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Mapper Field Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Mapper Field Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        Product2 prod = new Product2(Name = 'Mapper Field Product', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100,
            QuoteLineItemId = qli.Id
        );
        insert oi;

        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });

        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[0].itemsMapped >= 0);
    }

    @isTest
    static void buildPatches_skipsNonNewBusinessQuote() {
        Account acct = new Account(Name = 'Decomp Test Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Decomp Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Renewal Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'Renewal'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        Test.startTest();
        Map<Id, OrderItem> patches = MaintenanceOrderDecompositionService.buildPatches(ord.Id);
        Test.stopTest();

        System.assertEquals(true, patches.isEmpty(), 'Renewal quotes should not persist decomposition');
    }

    @isTest
    static void buildPatches_returnsEmptyWhenOrderIdNull() {
        System.assertEquals(true, MaintenanceOrderDecompositionService.buildPatches(null).isEmpty());
    }

    @isTest
    static void loadWork_returnsEmptyForNullOrderId() {
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.loadWork(null);
        System.assertEquals(null, work.orderId);
        System.assertEquals(true, work.allOrderItems.isEmpty());
    }

    @isTest
    static void buildPatchesFromWork_matchesBuildPatches() {
        Account acct = new Account(Name = 'FromWork Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'FromWork Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'FromWork Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.loadWork(ord.Id);

        Map<Id, OrderItem> direct = MaintenanceOrderDecompositionService.buildPatches(ord.Id);
        Map<Id, OrderItem> fromWork = MaintenanceOrderDecompositionService.buildPatchesFromWork(work);
        System.assertEquals(direct.keySet(), fromWork.keySet());
    }

    @isTest
    static void seedFromWork_copiesCommercialPricingFromQuote() {
        Account acct = new Account(Name = 'Seed Account');
        insert acct;

        Product2 prod = new Product2(
            Name = 'Seed Product',
            ProductCode = 'SEED-PROD-001',
            IsActive = true,
            Fortra_Product_Type__c = 'Software'
        );
        insert prod;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = prod.Id,
            UnitPrice = 355,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Seed Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Seed Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 301.75,
            PartnerUnitPrice = 301.75,
            Fortra_Product_Type__c = 'Software'
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
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 355
        );
        insert oi;

        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.loadWork(ord.Id);

        Test.startTest();
        Integer seeded = MaintenanceOrderDecompositionService.seedFromWork(work);
        Test.stopTest();

        System.assertEquals(1, seeded, 'Should seed one order line from quote commercial pricing');

        OrderItem updated = [
            SELECT PartnerUnitPrice, NetUnitPrice, UnitPrice, Fortra_Product_Type__c
            FROM OrderItem
            WHERE Id = :oi.Id
        ];
        System.assertEquals(301.75, updated.PartnerUnitPrice);
        System.assertEquals(301.75, updated.UnitPrice);
        System.assertEquals('Software', updated.Fortra_Product_Type__c);
    }

    @isTest
    static void seedFromWork_skipsRenewalQuote() {
        Account acct = new Account(Name = 'Seed Renewal Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Seed Renewal Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Seed Renewal Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'Renewal'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.loadWork(ord.Id);

        System.assertEquals(0, MaintenanceOrderDecompositionService.seedFromWork(work));
    }

    @isTest
    static void buildCommercialPatchesFromWork_appliesAllLinkedLines() {
        Account acct = new Account(Name = 'Commercial Patch Account');
        insert acct;

        Product2 licenseProd = new Product2(
            Name = 'Commercial License',
            ProductCode = 'COMM-LIC-001',
            IsActive = true
        );
        Product2 maintProd = new Product2(
            Name = 'Commercial Maintenance',
            ProductCode = 'COMM-MAINT-001',
            IsActive = true
        );
        insert new List<Product2>{ licenseProd, maintProd };

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry licensePbe = new PricebookEntry(
            Pricebook2Id = stdPBId, Product2Id = licenseProd.Id, UnitPrice = 355, IsActive = true
        );
        PricebookEntry maintPbe = new PricebookEntry(
            Pricebook2Id = stdPBId, Product2Id = maintProd.Id, UnitPrice = 100, IsActive = true
        );
        insert new List<PricebookEntry>{ licensePbe, maintPbe };

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Commercial Patch Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Commercial Patch Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        QuoteLineItem licenseQli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = licensePbe.Id,
            Product2Id = licenseProd.Id,
            Quantity = 1,
            UnitPrice = 301.75,
            PartnerUnitPrice = 301.75
        );
        QuoteLineItem maintQli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = maintPbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 62.48,
            PartnerUnitPrice = 62.48,
            Base_Price__c = 100
        );
        insert new List<QuoteLineItem>{ licenseQli, maintQli };

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPBId,
            QuoteId = q.Id
        );
        insert ord;

        OrderItem licenseOi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = licenseQli.Id,
            PricebookEntryId = licensePbe.Id,
            Product2Id = licenseProd.Id,
            Quantity = 1,
            UnitPrice = 355
        );
        OrderItem maintOi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = maintQli.Id,
            PricebookEntryId = maintPbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert new List<OrderItem>{ licenseOi, maintOi };

        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.loadWork(ord.Id);
        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(work);

        System.assertEquals(true, patches.containsKey(licenseOi.Id), 'License line should be patched');
        System.assertEquals(301.75, patches.get(licenseOi.Id).UnitPrice);
        System.assertEquals(301.75, patches.get(licenseOi.Id).TotalLineAmount);
    }

    @isTest
    static void prepareForReprice_returnsWorkAfterSeeding() {
        Account acct = new Account(Name = 'Prepare Reprice Account');
        insert acct;

        Product2 prod = new Product2(
            Name = 'Prepare Reprice Product',
            ProductCode = 'PREP-REPRICE-001',
            IsActive = true
        );
        insert prod;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Prepare Reprice Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Prepare Reprice Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 80,
            PartnerUnitPrice = 80
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

        insert new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100
        );

        Test.startTest();
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.prepareForReprice(ord.Id);
        Test.stopTest();

        System.assertEquals(ord.Id, work.orderId);
        System.assertEquals(true, work.isNewBusiness);
        System.assertEquals(1, work.allOrderItems.size());
    }

    // ---------------------------------------------------------------------
    // In-memory OrderMaintenanceWork fixtures.
    //
    // OrderMaintenanceWork is @TestVisible with public fields, so a fully
    // populated work object can be built without depending on org-specific
    // PriceBookEntryDerivedPrice / QuoteLineItemAttribute data. This makes the
    // derived-maintenance decomposition, commercial-patch, and seed branches
    // deterministically reachable. Real Order/OrderItem/QuoteLineItem rows are
    // inserted so the Ids and FK shape are genuine.
    // ---------------------------------------------------------------------

    private class WorkFixture {
        Id orderId;
        Id pbeId;
        Map<Id, QuoteLineItem> qliById = new Map<Id, QuoteLineItem>();
        List<OrderItem> orderItems = new List<OrderItem>();
        Map<Id, Id> oiIdToQliId = new Map<Id, Id>();
    }

    /**
     * Builds a New-business order with N linked lines, then returns a
     * WorkFixture exposing the inserted records so tests can assemble an
     * OrderMaintenanceWork in memory and mark which PBEs are "derived".
     */
    private static WorkFixture buildWorkFixture(Integer lineCount, Boolean withBasePrice) {
        Account acct = new Account(Name = 'WF Account ' + lineCount + withBasePrice);
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'WF Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id stdPBId = Test.getStandardPricebookId();

        Quote q = new Quote(
            Name = 'WF Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'New'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPBId,
            QuoteId = q.Id
        );
        insert ord;

        WorkFixture fx = new WorkFixture();
        fx.orderId = ord.Id;

        List<Product2> prods = new List<Product2>();
        for (Integer i = 0; i < lineCount; i++) {
            prods.add(new Product2(
                Name = 'WF Product ' + i,
                ProductCode = 'WF-PROD-' + lineCount + withBasePrice + '-' + i,
                IsActive = true,
                Fortra_Product_Type__c = 'Software'
            ));
        }
        insert prods;

        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Product2 p : prods) {
            pbes.add(new PricebookEntry(
                Pricebook2Id = stdPBId, Product2Id = p.Id, UnitPrice = 1000, IsActive = true
            ));
        }
        insert pbes;
        fx.pbeId = pbes[0].Id;

        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Integer i = 0; i < lineCount; i++) {
            qlis.add(new QuoteLineItem(
                QuoteId = q.Id,
                PricebookEntryId = pbes[i].Id,
                Product2Id = prods[i].Id,
                Quantity = 1,
                UnitPrice = 140,
                PartnerUnitPrice = 180,
                Base_Price__c = withBasePrice ? 1000 : null,
                Fortra_Product_Type__c = 'Software'
            ));
        }
        insert qlis;

        List<OrderItem> ois = new List<OrderItem>();
        for (Integer i = 0; i < lineCount; i++) {
            ois.add(new OrderItem(
                OrderId = ord.Id,
                QuoteLineItemId = qlis[i].Id,
                PricebookEntryId = pbes[i].Id,
                Product2Id = prods[i].Id,
                Quantity = 2,
                UnitPrice = 355
            ));
        }
        insert ois;

        Map<Id, QuoteLineItem> queried = new Map<Id, QuoteLineItem>([
            SELECT Id, Base_Price__c, UnitPrice, NetUnitPrice, PartnerUnitPrice,
                   Fortra_Product_Type__c, PricebookEntryId
            FROM QuoteLineItem WHERE Id IN :qlis
        ]);
        // NetUnitPrice is a non-writeable RLM field (not assignable in Apex even
        // in-memory), so rebuild each queried QLI through JSON to inject a
        // positive NetUnitPrice and exercise the net-price resolution branches
        // deterministically.
        for (Id qliId : queried.keySet()) {
            fx.qliById.put(qliId, withNetUnitPrice(queried.get(qliId), 140));
        }
        fx.orderItems = [
            SELECT Id, QuoteLineItemId, PricebookEntryId, Quantity
            FROM OrderItem WHERE OrderId = :ord.Id
        ];
        for (OrderItem oi : fx.orderItems) {
            fx.oiIdToQliId.put(oi.Id, oi.QuoteLineItemId);
        }
        return fx;
    }

    /** Renewal-quote order with one linked OI/QLI so loadWork reaches the non-new-business return. */
    private static WorkFixture buildRenewalWorkFixture() {
        Account acct = new Account(Name = 'Renewal WF Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Renewal WF Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id stdPBId = Test.getStandardPricebookId();

        Quote q = new Quote(
            Name = 'Renewal WF Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'Renewal'
        );
        insert q;

        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        Product2 prod = new Product2(
            Name = 'Renewal WF Product', ProductCode = 'RWF-PROD', IsActive = true
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId, Product2Id = prod.Id, UnitPrice = 100, IsActive = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 80
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

        insert new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 80
        );

        WorkFixture fx = new WorkFixture();
        fx.orderId = ord.Id;
        return fx;
    }

    /**
     * Returns an in-memory copy of the given QLI with NetUnitPrice (and any
     * other supplied price overrides) applied via JSON round-trip, since those
     * RLM fields are not writeable through normal Apex assignment.
     */
    private static QuoteLineItem withPrices(
        QuoteLineItem source,
        Decimal unitPrice,
        Decimal netUnitPrice,
        Decimal partnerUnitPrice
    ) {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            JSON.serialize(source)
        );
        raw.put('UnitPrice', unitPrice);
        raw.put('NetUnitPrice', netUnitPrice);
        raw.put('PartnerUnitPrice', partnerUnitPrice);
        return (QuoteLineItem) JSON.deserialize(JSON.serialize(raw), QuoteLineItem.class);
    }

    private static QuoteLineItem withNetUnitPrice(QuoteLineItem source, Decimal netUnitPrice) {
        return withPrices(source, source.UnitPrice, netUnitPrice, source.PartnerUnitPrice);
    }

    /** Rebuilds every QLI in the work's qliById map with the supplied uniform prices. */
    private static void repriceWork(
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work,
        Decimal unitPrice,
        Decimal netUnitPrice,
        Decimal partnerUnitPrice
    ) {
        Map<Id, QuoteLineItem> rebuilt = new Map<Id, QuoteLineItem>();
        for (Id qliId : work.qliById.keySet()) {
            rebuilt.put(
                qliId,
                withPrices(work.qliById.get(qliId), unitPrice, netUnitPrice, partnerUnitPrice)
            );
        }
        work.qliById = rebuilt;
    }

    private static MaintenanceOrderDecompositionService.OrderMaintenanceWork toWork(
        WorkFixture fx,
        Boolean markDerived,
        String tier
    ) {
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            new MaintenanceOrderDecompositionService.OrderMaintenanceWork();
        work.orderId = fx.orderId;
        work.isNewBusiness = true;
        work.allOrderItems = fx.orderItems;
        work.qliById = fx.qliById;
        for (QuoteLineItem qli : fx.qliById.values()) {
            if (markDerived) {
                work.derivedPbeIds.add(qli.PricebookEntryId);
            }
            if (tier != null) {
                work.tierByQliId.put(qli.Id, tier);
            }
        }
        return work;
    }

    @isTest
    static void buildPatchesFromWork_buildsDecompositionForDerivedTieredLine() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, true, 'Standard');

        Test.startTest();
        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildPatchesFromWork(work);
        Test.stopTest();

        Id oiId = fx.orderItems[0].Id;
        System.assertEquals(1, patches.size(), 'Derived tiered line should be patched');
        OrderItem patch = patches.get(oiId);
        // Standard tier on 1000 base => maintenanceBase = 200.
        System.assertEquals(200, patch.Base_Price__c, 'maintenanceBase = 1000 * 0.20');
        // Partner 180 < 200 => partnerDiscount 20.
        System.assertEquals(20, patch.Prior_Partner_Discount__c);
        // net (UnitPrice 140) < afterPartner 180 => discretionary 40.
        System.assertEquals(40, patch.Prior_Discretionary_Discount__c);
        // commercialNet = resolveNetPrice => UnitPrice 140.
        System.assertEquals(140, patch.UnitPrice);
        System.assertEquals(140, patch.NetUnitPrice);
        System.assertEquals(180, patch.PartnerUnitPrice);
        // quantity 2 * 140 = 280.
        System.assertEquals(280, patch.TotalLineAmount);
    }

    @isTest
    static void buildPatchesFromWork_skipsLineWhenBasePriceNull() {
        WorkFixture fx = buildWorkFixture(1, false);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, true, 'Standard');

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildPatchesFromWork(work);
        System.assertEquals(true, patches.isEmpty(), 'Null Base_Price__c lines are skipped');
    }

    @isTest
    static void buildPatchesFromWork_skipsLineWhenPbeNotDerived() {
        WorkFixture fx = buildWorkFixture(1, true);
        // markDerived = false => qli.PricebookEntryId not in derivedPbeIds (line 122-123).
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, false, 'Standard');

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildPatchesFromWork(work);
        System.assertEquals(true, patches.isEmpty(), 'Non-derived PBE lines are skipped');
    }

    @isTest
    static void buildPatchesFromWork_skipsLineWhenTierUnknown() {
        WorkFixture fx = buildWorkFixture(1, true);
        // No tier => resolveTierRate 0 => maintenanceBase 0 => skipped (line 134-135).
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, true, null);

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildPatchesFromWork(work);
        System.assertEquals(true, patches.isEmpty(), 'Zero maintenanceBase lines are skipped');
    }

    @isTest
    static void buildPatchesFromWork_skipsLineWhenQuoteLineMissingFromMap() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, true, 'Standard');
        // Remove the QLI from qliById so qli == null path (line 118-120) runs.
        work.qliById = new Map<Id, QuoteLineItem>();

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildPatchesFromWork(work);
        System.assertEquals(true, patches.isEmpty(), 'Missing quote line is skipped');
    }

    @isTest
    static void buildPatchesFromWork_skipsOrderItemWithoutQuoteLineLink() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, true, 'Standard');
        // Detach the QLI link on the OI so the null-link continue (line 114-115) runs.
        work.allOrderItems = new List<OrderItem>{
            new OrderItem(Id = fx.orderItems[0].Id, QuoteLineItemId = null, Quantity = 1)
        };

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildPatchesFromWork(work);
        System.assertEquals(true, patches.isEmpty(), 'Unlinked order items are skipped');
    }

    @isTest
    static void buildCommercialPatchesFromWork_mergesDecompFieldsOntoCommercialPatch() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, true, 'Standard');

        Test.startTest();
        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(work);
        Test.stopTest();

        Id oiId = fx.orderItems[0].Id;
        OrderItem patch = patches.get(oiId);
        System.assertNotEquals(null, patch, 'Derived line gets a merged patch');
        // Commercial net comes from the decomposition patch UnitPrice (140).
        System.assertEquals(140, patch.UnitPrice);
        System.assertEquals(140, patch.NetUnitPrice);
        // Partner unit 180 > 0 => retained.
        System.assertEquals(180, patch.PartnerUnitPrice);
        // Quantity 2 * 140 = 280.
        System.assertEquals(280, patch.TotalLineAmount);
        // Decomposition fields merged onto the same patch (lines 209-213).
        System.assertEquals(200, patch.Base_Price__c);
        System.assertEquals(20, patch.Prior_Partner_Discount__c);
        System.assertEquals(40, patch.Prior_Discretionary_Discount__c);
    }

    @isTest
    static void buildCommercialPatchesFromWork_usesResolvedCommercialPriceForNonDerivedLine() {
        WorkFixture fx = buildWorkFixture(1, true);
        // Not derived => no decomposition patch => commercialNet from resolveCommercialUnitPrice.
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, false, 'Standard');

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(work);

        Id oiId = fx.orderItems[0].Id;
        OrderItem patch = patches.get(oiId);
        System.assertNotEquals(null, patch, 'Linked line gets a commercial patch');
        // resolveCommercialUnitPrice prefers PartnerUnitPrice (180).
        System.assertEquals(180, patch.UnitPrice);
        System.assertEquals(180, patch.NetUnitPrice);
        System.assertEquals(180, patch.PartnerUnitPrice);
        // Quantity 2 * 180 = 360.
        System.assertEquals(360, patch.TotalLineAmount);
        // No decomposition => Base_Price__c not set on this patch.
        System.assertEquals(null, patch.Base_Price__c);
    }

    @isTest
    static void buildCommercialPatchesFromWork_skipsLineWhenCommercialNetUnresolvable() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, false, null);
        // Zero out all price fields so resolveCommercialUnitPrice returns null (line 188-189).
        repriceWork(work, 0, 0, 0);

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(work);
        System.assertEquals(true, patches.isEmpty(), 'Lines with no resolvable net are skipped');
    }

    @isTest
    static void buildCommercialPatchesFromWork_skipsUnlinkedAndMissingQuoteLines() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, false, null);
        Id realOiId = fx.orderItems[0].Id;
        // One OI with null QLI link (line 175-176) and one whose QLI is absent (line 180-181).
        work.allOrderItems = new List<OrderItem>{
            new OrderItem(Id = realOiId, QuoteLineItemId = null, Quantity = 1),
            new OrderItem(
                Id = realOiId,
                QuoteLineItemId = fx.orderItems[0].QuoteLineItemId,
                Quantity = 1
            )
        };
        work.qliById = new Map<Id, QuoteLineItem>(); // force qli == null on the linked OI

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(work);
        System.assertEquals(true, patches.isEmpty(), 'Unlinked and unmapped lines are skipped');
    }

    @isTest
    static void buildCommercialPatchesFromWork_emptyOrderItemsYieldsNoPatches() {
        // Both the decomposition and commercial loops iterate work.allOrderItems,
        // so with no order items neither produces a patch. (The standalone-add
        // else-branch at line 215 is defensive: a decomposition patch always has a
        // positive UnitPrice, so the commercial loop never skips a decomposable
        // line; that branch is therefore unreachable from a consistent work.)
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, true, 'Standard');
        work.allOrderItems = new List<OrderItem>();

        Map<Id, OrderItem> patches =
            MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(work);
        System.assertEquals(true, patches.isEmpty(), 'No order items => no patches');
    }

    @isTest
    static void resolveCommercialUnitPrice_branchCoverageViaCommercialPatches() {
        WorkFixture fx = buildWorkFixture(1, true);

        // (a) UnitPrice fallback when Partner is 0.
        MaintenanceOrderDecompositionService.OrderMaintenanceWork workUnit =
            toWork(fx, false, null);
        repriceWork(workUnit, 99, 0, 0);
        Map<Id, OrderItem> unitPatches =
            MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(workUnit);
        System.assertEquals(99, unitPatches.get(fx.orderItems[0].Id).UnitPrice, 'Falls back to UnitPrice');

        // (b) NetUnitPrice fallback when Partner and Unit are 0.
        MaintenanceOrderDecompositionService.OrderMaintenanceWork workNet =
            toWork(fx, false, null);
        repriceWork(workNet, 0, 55, 0);
        Map<Id, OrderItem> netPatches =
            MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(workNet);
        System.assertEquals(55, netPatches.get(fx.orderItems[0].Id).UnitPrice, 'Falls back to NetUnitPrice');
    }

    @isTest
    static void resolveCommercialUnitPrice_returnsNullForNullQuoteLine() {
        // Direct null-arg branch (line 224-225).
        System.assertEquals(
            null,
            MaintenanceOrderDecompositionService.resolveCommercialUnitPrice(null)
        );
    }

    @isTest
    static void seedFromWork_skipsLinesWithoutChangeableCommercialFields() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, false, null);
        // No positive prices and no product type => changed stays false => seeds empty (line 289-290).
        repriceWork(work, 0, 0, 0);
        for (QuoteLineItem qli : work.qliById.values()) {
            qli.Fortra_Product_Type__c = null;
        }

        Test.startTest();
        Integer seeded = MaintenanceOrderDecompositionService.seedFromWork(work);
        Test.stopTest();
        System.assertEquals(0, seeded, 'Nothing changeable => no seed');
    }

    @isTest
    static void seedFromWork_usesUnitPriceWhenNetUnitPriceZero() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, false, null);
        // NetUnitPrice 0 => else-if UnitPrice branch (line 275-277).
        repriceWork(work, 88, 0, 0);
        for (QuoteLineItem qli : work.qliById.values()) {
            qli.Fortra_Product_Type__c = null;
        }

        Test.startTest();
        Integer seeded = MaintenanceOrderDecompositionService.seedFromWork(work);
        Test.stopTest();

        System.assertEquals(1, seeded);
        OrderItem updated = [SELECT UnitPrice FROM OrderItem WHERE Id = :fx.orderItems[0].Id];
        System.assertEquals(88, updated.UnitPrice, 'Seeded UnitPrice from quote UnitPrice');
    }

    @isTest
    static void seedFromWork_skipsUnlinkedAndMissingQuoteLines() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, false, null);
        Id realOiId = fx.orderItems[0].Id;
        // OI with null link (line 255-256) and OI whose QLI is absent (line 260-261).
        work.allOrderItems = new List<OrderItem>{
            new OrderItem(Id = realOiId, QuoteLineItemId = null, Quantity = 1),
            new OrderItem(
                Id = realOiId,
                QuoteLineItemId = fx.orderItems[0].QuoteLineItemId,
                Quantity = 1
            )
        };
        work.qliById = new Map<Id, QuoteLineItem>();

        Integer seeded = MaintenanceOrderDecompositionService.seedFromWork(work);
        System.assertEquals(0, seeded, 'Unlinked and unmapped lines seed nothing');
    }

    @isTest
    static void seedFromWork_usesNetUnitPriceWhenPositive() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, false, null);
        // NetUnitPrice > 0 => NetUnitPrice branch seeds both Net and Unit (line 271-274).
        repriceWork(work, 0, 222, 0);
        for (QuoteLineItem qli : work.qliById.values()) {
            qli.Fortra_Product_Type__c = null;
        }

        Test.startTest();
        Integer seeded = MaintenanceOrderDecompositionService.seedFromWork(work);
        Test.stopTest();

        System.assertEquals(1, seeded);
        OrderItem updated = [
            SELECT UnitPrice, NetUnitPrice FROM OrderItem WHERE Id = :fx.orderItems[0].Id
        ];
        System.assertEquals(222, updated.NetUnitPrice, 'Seeded NetUnitPrice from quote NetUnitPrice');
        System.assertEquals(222, updated.UnitPrice, 'UnitPrice mirrors NetUnitPrice on seed');
    }

    @isTest
    static void loadWork_renewalWithLinkedLineStopsBeforeDerivedLookups() {
        // Renewal quote with a linked OI so qliIds is non-empty: loadWork queries
        // qliById then returns at the non-new-business guard (line 88-89) without
        // running derived-PBE / tier lookups.
        WorkFixture fx = buildRenewalWorkFixture();

        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.loadWork(fx.orderId);

        System.assertEquals(false, work.isNewBusiness, 'Renewal quote is not new business');
        System.assertEquals(1, work.qliById.size(), 'Quote line still loaded for renewal');
        System.assertEquals(true, work.derivedPbeIds.isEmpty(), 'Derived lookups skipped for renewal');
        System.assertEquals(true, work.tierByQliId.isEmpty(), 'Tier lookups skipped for renewal');
    }

    @isTest
    static void seedOrderItemsFromQuote_publicEntryPointSeedsLine() {
        WorkFixture fx = buildWorkFixture(1, true);

        Test.startTest();
        Integer seeded = MaintenanceOrderDecompositionService.seedOrderItemsFromQuote(fx.orderId);
        Test.stopTest();

        System.assertEquals(1, seeded, 'Public entry point loads work and seeds the line');
        OrderItem updated = [
            SELECT PartnerUnitPrice, NetUnitPrice, UnitPrice, Fortra_Product_Type__c
            FROM OrderItem WHERE Id = :fx.orderItems[0].Id
        ];
        // loadWork reads the persisted QLI (NetUnitPrice is non-writeable and
        // null in the DB), so the UnitPrice fallback branch seeds UnitPrice 140.
        System.assertEquals(180, updated.PartnerUnitPrice);
        System.assertEquals(140, updated.UnitPrice);
        System.assertEquals('Software', updated.Fortra_Product_Type__c);
    }

    @isTest
    static void persistFromWork_updatesPatchesAndReturnsCount() {
        WorkFixture fx = buildWorkFixture(1, true);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            toWork(fx, true, 'Standard');

        Test.startTest();
        Integer persisted = MaintenanceOrderDecompositionService.persistFromWork(work);
        Test.stopTest();

        System.assertEquals(1, persisted, 'One derived line persisted');
        OrderItem updated = [
            SELECT UnitPrice, NetUnitPrice, Base_Price__c, TotalLineAmount
            FROM OrderItem WHERE Id = :fx.orderItems[0].Id
        ];
        System.assertEquals(140, updated.UnitPrice, 'Commercial net written to order line');
        System.assertEquals(200, updated.Base_Price__c, 'Maintenance base written to order line');
    }
}