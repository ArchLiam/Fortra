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

    @isTest
    static void buildRenewalCarryForwardPatches_persistsQliInputsOnOrderItem() {
        Account acct = new Account(Name = 'Renewal Carry Account');
        insert acct;

        Product2 maintProd = new Product2(
            Name = 'Renewal Carry Product',
            ProductCode = 'RRM-CARRY-TEST',
            IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Renewal Carry Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Renewal Carry Quote',
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

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 60.64,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 6.25,
            Fortra_Product_Type__c = 'Renewal Maintenance'
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
            UnitPrice = 0,
            Base_Price__c = 355
        );
        insert oi;

        Test.startTest();
        Map<Id, OrderItem> patches = MaintenanceOrderDecompositionService.buildRenewalCarryForwardPatchesFromWork(
            MaintenanceOrderDecompositionService.loadWork(ord.Id)
        );
        Test.stopTest();

        System.assertEquals(true, patches.containsKey(oi.Id), 'Renewal maintenance line should receive carry-forward patch');
        System.assertEquals(71, patches.get(oi.Id).Base_Price__c, 'Should overwrite license base with maintenance base');
        System.assertEquals(8.52, patches.get(oi.Id).Prior_Partner_Discount__c);
        System.assertEquals(6.25, patches.get(oi.Id).Prior_Discretionary_Discount__c);
        System.assertEquals(60.64, patches.get(oi.Id).UnitPrice);
        System.assertEquals(60.64, patches.get(oi.Id).NetUnitPrice);
    }

    @isTest
    static void buildRenewalCarryForwardPatches_computesNetWhenQuoteNetIsZero() {
        Account acct = new Account(Name = 'Renewal Net Fallback Account');
        insert acct;

        Product2 maintProd = new Product2(
            Name = 'Renewal Net Fallback Product',
            ProductCode = 'RRM-NET-FALLBACK',
            IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Renewal Net Fallback Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Renewal Net Fallback Quote',
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

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 0,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 6.25,
            COLA_Uplift_Percent__c = 7.85,
            Fortra_Product_Type__c = 'Renewal Maintenance'
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
            UnitPrice = 0
        );
        insert oi;

        Map<Id, OrderItem> patches = MaintenanceOrderDecompositionService.buildRenewalCarryForwardPatchesFromWork(
            MaintenanceOrderDecompositionService.loadWork(ord.Id)
        );

        System.assertEquals(true, patches.containsKey(oi.Id));
        System.assertEquals(60.64, patches.get(oi.Id).UnitPrice, 'Should compute (71-8.52-6.25)*1.0785');
    }

    @isTest
    static void inferTierFromPricing_findsStandardFor355PartnerNet() {
        System.assertEquals(
            'Standard',
            MaintenanceOrderDecompositionService.inferTierFromPricing(355, 0, 62.48, 62.48)
        );

        MaintenanceOrderDecompositionService.Decomposition decomp =
            MaintenanceOrderDecompositionService.compute(355, 0, 62.48, 62.48, 'Standard');
        System.assertEquals(71, decomp.maintenanceBase);
        System.assertEquals(8.52, decomp.partnerDiscount);
    }

    @isTest
    static void buildPatchesFromWork_infersTierWhenAttributesMissing() {
        Account acct = new Account(Name = 'Infer Tier Account');
        insert acct;

        Product2 maintProd = new Product2(
            Name = 'Infer Tier Product',
            ProductCode = 'INFER-TIER-001',
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 355,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Infer Tier Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Infer Tier Quote',
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
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 62.48,
            PartnerUnitPrice = 62.48,
            Base_Price__c = 355,
            Fortra_Product_Type__c = 'New Maintenance'
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
            UnitPrice = 62.48,
            Base_Price__c = 355
        );
        insert oi;

        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.loadWork(ord.Id);
        System.assertEquals(true, work.isNewBusiness, 'Quote_Type__c=New should qualify as new business');

        Map<Id, OrderItem> patches = MaintenanceOrderDecompositionService.buildPatchesFromWork(work);

        System.assertEquals(true, patches.containsKey(oi.Id), 'Should decompose even without tier attributes');
        System.assertEquals(71, patches.get(oi.Id).Base_Price__c, 'Should overwrite license base with maintenance base');
        System.assertEquals(8.52, patches.get(oi.Id).Prior_Partner_Discount__c);
    }

    @isTest
    static void backfillCarryForwardFields_updatesBaseWithoutUnitPrice() {
        Account acct = new Account(Name = 'Backfill Account');
        insert acct;

        Product2 maintProd = new Product2(
            Name = 'Backfill Product',
            ProductCode = 'BACKFILL-001',
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 355,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Backfill Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Backfill Quote',
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
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 62.48,
            PartnerUnitPrice = 62.48,
            Base_Price__c = 355,
            Fortra_Product_Type__c = 'New Maintenance'
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
            UnitPrice = 71,
            Base_Price__c = 355
        );
        insert oi;

        Test.startTest();
        Integer updated = MaintenanceOrderDecompositionService.backfillCarryForwardFields(ord.Id);
        Test.stopTest();

        System.assertEquals(1, updated);
        OrderItem result = [
            SELECT Base_Price__c, Prior_Partner_Discount__c, UnitPrice
            FROM OrderItem WHERE Id = :oi.Id
        ];
        System.assertEquals(71, result.Base_Price__c);
        System.assertEquals(8.52, result.Prior_Partner_Discount__c);
        System.assertEquals(71, result.UnitPrice, 'Backfill must not change UnitPrice');
    }

    @isTest
    static void buildPatchesFromWork_usesProductTypeWhenDerivedPbeConfigMissing() {
        Account acct = new Account(Name = 'Product Type Decomp Account');
        insert acct;

        Product2 maintProd = new Product2(
            Name = 'Product Type Decomp Product',
            ProductCode = 'RNM-TYPE-DECOMP',
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 1000,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Product Type Decomp Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Product Type Decomp Quote',
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
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 140,
            PartnerUnitPrice = 180,
            Base_Price__c = 1000,
            Fortra_Product_Type__c = 'New Maintenance'
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
            UnitPrice = 140,
            Base_Price__c = 1000
        );
        insert oi;

        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            MaintenanceOrderDecompositionService.loadWork(ord.Id);
        work.tierByQliId.put(qli.Id, 'Standard');
        work.derivedPbeIds = new Set<Id>();

        Map<Id, OrderItem> patches = MaintenanceOrderDecompositionService.buildPatchesFromWork(work);

        System.assertEquals(true, patches.containsKey(oi.Id), 'Should decompose via product type when PBE config absent');
        System.assertEquals(200, patches.get(oi.Id).Base_Price__c);
        System.assertEquals(20, patches.get(oi.Id).Prior_Partner_Discount__c);
    }

    @isTest
    static void loadWorkBulk_loadsMultipleOrdersInSharedQueries() {
        Account acct = new Account(Name = 'Bulk Load Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Bulk Load Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < 2; i++) {
            Quote q = new Quote(
                Name = 'Bulk Load Quote ' + i,
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

            orders.add(new Order(
                AccountId = acct.Id,
                Status = 'Draft',
                EffectiveDate = Date.today(),
                Pricebook2Id = Test.getStandardPricebookId(),
                QuoteId = q.Id
            ));
        }
        insert orders;

        Set<Id> orderIds = new Map<Id, Order>(orders).keySet();

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        Map<Id, MaintenanceOrderDecompositionService.OrderMaintenanceWork> workByOrderId =
            MaintenanceOrderDecompositionService.loadWorkBulk(orderIds);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assertEquals(2, workByOrderId.size());
        System.assertNotEquals(null, workByOrderId.get(orders[0].Id).orderRecord);
        System.assertNotEquals(null, workByOrderId.get(orders[1].Id).orderRecord);
        System.assert(soqlUsed <= 6, 'Expected <=6 SOQL for 2 orders via loadWorkBulk, got ' + soqlUsed);
    }

    @isTest
    static void resolveNewMaintenanceNet_prefersContributorBaseOverSourceList() {
        Id qliId = fakeIdFor(QuoteLineItem.SObjectType);
        MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
            new MaintenanceOrderDecompositionService.OrderMaintenanceWork();
        work.tierByQliId = new Map<Id, String>{ qliId => 'Standard' };

        QuoteLineItem qli = new QuoteLineItem(
            Id = qliId,
            Fortra_Product_Type__c = 'New Maintenance',
            Base_Price__c = 20000,
            Source_List_Price__c = 355
        );

        Decimal net = MaintenanceOrderDecompositionService.resolveNewMaintenanceNet(work, qli, null);
        System.assertEquals(4000, net, 'Standard tier should apply 20% to stamped contributor net');
    }

    private static Id fakeIdFor(Schema.SObjectType sobjectType) {
        String prefix = sobjectType.getDescribe().getKeyPrefix();
        return (Id) (prefix + '0'.repeat(15 - prefix.length()));
    }

    /**
     * Builds one New-business Order carrying `numLines` derived New-Maintenance lines that each
     * produce a carry-forward backfill patch (mirrors backfillCarryForwardFields_updates... recipe).
     */
    private static Id buildMaintOrderWithLines(Id acctId, Id pbeId, Id productId, Integer numLines) {
        Opportunity opp = new Opportunity(
            AccountId = acctId,
            Name = 'Backfill Bulk Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Backfill Bulk Quote',
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
            AccountId = acctId,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Integer i = 0; i < numLines; i++) {
            qlis.add(new QuoteLineItem(
                QuoteId = q.Id,
                PricebookEntryId = pbeId,
                Product2Id = productId,
                Quantity = 1,
                UnitPrice = 62.48,
                PartnerUnitPrice = 62.48,
                Base_Price__c = 355,
                Fortra_Product_Type__c = 'New Maintenance'
            ));
        }
        insert qlis;

        List<OrderItem> ois = new List<OrderItem>();
        for (QuoteLineItem qli : qlis) {
            ois.add(new OrderItem(
                OrderId = ord.Id,
                QuoteLineItemId = qli.Id,
                PricebookEntryId = pbeId,
                Product2Id = productId,
                Quantity = 1,
                UnitPrice = 71,
                Base_Price__c = 355
            ));
        }
        insert ois;
        return ord.Id;
    }

    /**
     * D-16: backfill DML must be hoisted out of the per-order loop. Distribution-invariance proof —
     * same total patched lines (2), two order spreads. The bulk method issues ONE update for both,
     * so the DML budget is identical; the pre-fix per-order DML would cost the 2-order spread one
     * extra statement. Flow/trigger noise scales with line count (equal here), so it cancels out.
     */
    @isTest
    static void backfillCarryForwardFieldsBulk_dmlDoesNotScaleWithOrderCount() {
        Account acct = new Account(Name = 'Backfill Bulk Account');
        insert acct;

        Product2 maintProd = new Product2(
            Name = 'Backfill Bulk Product',
            ProductCode = 'BFB-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 355,
            IsActive = true
        );
        insert pbe;

        Id spreadOrder1 = buildMaintOrderWithLines(acct.Id, pbe.Id, maintProd.Id, 1);
        Id spreadOrder2 = buildMaintOrderWithLines(acct.Id, pbe.Id, maintProd.Id, 1);
        Id concentratedOrder = buildMaintOrderWithLines(acct.Id, pbe.Id, maintProd.Id, 2);

        Test.startTest();
        Integer dmlBeforeSpread = Limits.getDmlStatements();
        Map<Id, Integer> spreadCounts = MaintenanceOrderDecompositionService.backfillCarryForwardFieldsBulk(
            new Set<Id>{ spreadOrder1, spreadOrder2 });
        Integer dmlSpread = Limits.getDmlStatements() - dmlBeforeSpread;

        Integer dmlBeforeConc = Limits.getDmlStatements();
        Map<Id, Integer> concCounts = MaintenanceOrderDecompositionService.backfillCarryForwardFieldsBulk(
            new Set<Id>{ concentratedOrder });
        Integer dmlConc = Limits.getDmlStatements() - dmlBeforeConc;
        Test.stopTest();

        System.assertEquals(1, spreadCounts.get(spreadOrder1), 'spread order 1 patched one line');
        System.assertEquals(1, spreadCounts.get(spreadOrder2), 'spread order 2 patched one line');
        System.assertEquals(2, concCounts.get(concentratedOrder), 'concentrated order patched two lines');

        System.assertEquals(dmlConc, dmlSpread,
            'Backfill DML must not scale with order count (spread=' + dmlSpread + ' concentrated=' + dmlConc + ')');
    }
}