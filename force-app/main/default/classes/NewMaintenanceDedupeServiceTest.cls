/**
 * @description Verifies NewMaintenanceDedupeService removes Add-Assets amend-carryover New
 *              Maintenance duplicates on new-business quotes while preserving the native-derived
 *              keeper, and stays out of scope on renewal quotes and when no keeper is present.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class NewMaintenanceDedupeServiceTest {

    private class Ctx {
        Quote quote;
        Id accountId;
    }

    private static Ctx createQuote(String quoteType) {
        Account account = new Account(Name = 'Dedupe Test Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Dedupe Test Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Dedupe Quote ' + quoteType,
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = quoteType
        );
        insert quote;

        Ctx ctx = new Ctx();
        ctx.quote = quote;
        ctx.accountId = account.Id;
        return ctx;
    }

    private static PricebookEntry createNewMaintPbe() {
        Product2 product = new Product2(
            Name = 'RNM-DEDUPE',
            ProductCode = 'RNM-DEDUPE-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert product;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 4000,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }

    private static QuoteAction createAmendAction(Id quoteId, Id accountId, Id product2Id, Decimal qty) {
        Asset sourceAsset = new Asset(
            Name = 'Prior Maint Asset',
            AccountId = accountId,
            Product2Id = product2Id,
            Price = 710,
            Quantity = qty,
            Status = 'Installed'
        );
        insert sourceAsset;

        QuoteAction amendAction = new QuoteAction(
            QuoteId = quoteId,
            Type = 'Amend',
            SourceAssetId = sourceAsset.Id
        );
        insert amendAction;
        return amendAction;
    }

    // Inserts a native-derived keeper (no QuoteAction) + an Amend carryover duplicate of the same
    // product. Both lines exist after this (the trigger's synchronous test-path runs only the
    // renewal cleanup, which is a no-op for a New quote).
    private static Id seedKeeperAndAmendDuplicate(String quoteType) {
        Ctx ctx = createQuote(quoteType);
        PricebookEntry pbe = createNewMaintPbe();

        insert new QuoteLineItem(
            QuoteId = ctx.quote.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = pbe.Product2Id,
            Quantity = 1,
            UnitPrice = 4000
        );

        QuoteAction amendAction = createAmendAction(ctx.quote.Id, ctx.accountId, pbe.Product2Id, 10);
        insert new QuoteLineItem(
            QuoteId = ctx.quote.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = pbe.Product2Id,
            QuoteActionId = amendAction.Id,
            Quantity = 10,
            StartQuantity = 10,
            UnitPrice = 0
        );

        return ctx.quote.Id;
    }

    @IsTest
    static void dedupeRemovesAmendCarryoverWhenNativeKeeperExists() {
        Id quoteId = seedKeeperAndAmendDuplicate('New');

        Test.startTest();
        NewMaintenanceDedupeService.dedupeForQuotes(new Set<Id>{ quoteId });
        Test.stopTest();

        List<QuoteLineItem> remaining = [
            SELECT Id, QuoteActionId FROM QuoteLineItem WHERE QuoteId = :quoteId
        ];
        Assert.areEqual(1, remaining.size(), 'Only the native-derived keeper should remain');
        Assert.isNull(remaining[0].QuoteActionId, 'Keeper is the no-QuoteAction line');
    }

    @IsTest
    static void dedupeRunsViaCleanupQueueable() {
        Id quoteId = seedKeeperAndAmendDuplicate('Net-New');

        Test.startTest();
        new RenewalQuoteLineCleanupQueueable(new Set<Id>{ quoteId }).execute(null);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quoteId],
            'Queueable should dedupe Net-New carryover to a single line'
        );
    }

    @IsTest
    static void dedupeKeepsBothWhenNoNativeKeeper() {
        Ctx ctx = createQuote('New');
        PricebookEntry pbe = createNewMaintPbe();

        QuoteAction a1 = createAmendAction(ctx.quote.Id, ctx.accountId, pbe.Product2Id, 10);
        QuoteAction a2 = createAmendAction(ctx.quote.Id, ctx.accountId, pbe.Product2Id, 1);
        insert new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = ctx.quote.Id, PricebookEntryId = pbe.Id,
                Product2Id = pbe.Product2Id, QuoteActionId = a1.Id, Quantity = 10,
                StartQuantity = 10, UnitPrice = 71),
            new QuoteLineItem(QuoteId = ctx.quote.Id, PricebookEntryId = pbe.Id,
                Product2Id = pbe.Product2Id, QuoteActionId = a2.Id, Quantity = 1,
                StartQuantity = 1, UnitPrice = 71)
        };

        Test.startTest();
        NewMaintenanceDedupeService.dedupeForQuotes(new Set<Id>{ ctx.quote.Id });
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :ctx.quote.Id],
            'Without a native keeper the guard must not delete either Amend line'
        );
    }

    @IsTest
    static void dedupeNoOpOnRenewalQuote() {
        Id quoteId = seedKeeperAndAmendDuplicate('Renewal');

        Test.startTest();
        NewMaintenanceDedupeService.dedupeForQuotes(new Set<Id>{ quoteId });
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quoteId],
            'Renewal quotes are out of scope — no dedupe'
        );
    }

    @IsTest
    static void dedupeNoOpOnNullOrEmpty() {
        Test.startTest();
        NewMaintenanceDedupeService.dedupeForQuotes(null);
        NewMaintenanceDedupeService.dedupeForQuotes(new Set<Id>());
        Integer dmlUsed = Limits.getDmlStatements();
        Test.stopTest();
        Assert.areEqual(0, dmlUsed, 'Null / empty inputs perform no DML');
    }

    @IsTest
    static void dedupeDegradesAndLogsOnFailure() {
        Id quoteId = seedKeeperAndAmendDuplicate('New');

        Test.startTest();
        NewMaintenanceDedupeService.throwOnDeleteForTest = true;
        NewMaintenanceDedupeService.dedupeForQuotes(new Set<Id>{ quoteId });
        NewMaintenanceDedupeService.throwOnDeleteForTest = false;
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quoteId],
            'A dedupe failure is caught and logged; the lines are left intact for a later event'
        );
    }

    // Bulk: 20 distinct maintenance products on one New quote, each with a native keeper + an Amend
    // carryover duplicate (40 lines). Dedupe must remove all 20 duplicates and keep all 20 keepers.
    @IsTest
    static void dedupeBulkRemovesCarryoverAcrossManyProducts() {
        Ctx ctx = createQuote('New');
        Integer productCount = 20;

        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < productCount; i++) {
            products.add(new Product2(
                Name = 'RNM-BULK-' + i,
                ProductCode = 'RNM-BULK-' + i + '-' + String.valueOf(Crypto.getRandomInteger()),
                IsActive = true,
                Fortra_Product_Type__c = 'New Maintenance'
            ));
        }
        insert products;

        List<PricebookEntry> pbes = new List<PricebookEntry>();
        List<Asset> assets = new List<Asset>();
        for (Product2 product : products) {
            pbes.add(new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 4000,
                IsActive = true
            ));
            assets.add(new Asset(
                Name = 'Prior ' + product.Name,
                AccountId = ctx.accountId,
                Product2Id = product.Id,
                Price = 710,
                Quantity = 10,
                Status = 'Installed'
            ));
        }
        insert pbes;
        insert assets;

        Map<Id, Id> pbeByProduct = new Map<Id, Id>();
        for (PricebookEntry pbe : pbes) {
            pbeByProduct.put(pbe.Product2Id, pbe.Id);
        }
        List<QuoteAction> amendActions = new List<QuoteAction>();
        for (Asset asset : assets) {
            amendActions.add(new QuoteAction(
                QuoteId = ctx.quote.Id,
                Type = 'Amend',
                SourceAssetId = asset.Id
            ));
        }
        insert amendActions;
        Map<Id, Id> actionByProduct = new Map<Id, Id>();
        Map<Id, Id> productByAsset = new Map<Id, Id>();
        for (Asset asset : assets) {
            productByAsset.put(asset.Id, asset.Product2Id);
        }
        for (QuoteAction action : amendActions) {
            actionByProduct.put(productByAsset.get(action.SourceAssetId), action.Id);
        }

        List<QuoteLineItem> lines = new List<QuoteLineItem>();
        for (Product2 product : products) {
            lines.add(new QuoteLineItem(
                QuoteId = ctx.quote.Id,
                PricebookEntryId = pbeByProduct.get(product.Id),
                Product2Id = product.Id,
                Quantity = 1,
                UnitPrice = 4000
            ));
            lines.add(new QuoteLineItem(
                QuoteId = ctx.quote.Id,
                PricebookEntryId = pbeByProduct.get(product.Id),
                Product2Id = product.Id,
                QuoteActionId = actionByProduct.get(product.Id),
                Quantity = 10,
                StartQuantity = 10,
                UnitPrice = 0
            ));
        }
        insert lines;

        Test.startTest();
        NewMaintenanceDedupeService.dedupeForQuotes(new Set<Id>{ ctx.quote.Id });
        Test.stopTest();

        List<QuoteLineItem> remaining = [
            SELECT Id, QuoteActionId FROM QuoteLineItem WHERE QuoteId = :ctx.quote.Id
        ];
        Assert.areEqual(productCount, remaining.size(),
            'Every native-derived keeper should remain and every Amend duplicate should be removed');
        for (QuoteLineItem line : remaining) {
            Assert.isNull(line.QuoteActionId, 'Only native-derived keepers remain after bulk dedupe');
        }
    }
}
