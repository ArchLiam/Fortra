@IsTest
private class RenewalAssetQuantityHandlerTest {

    @IsTest
    static void resolveSourceQuantity_prefersAssetQuantity() {
        QuoteLineItem qli = new QuoteLineItem(
            StartQuantity = 2,
            QuoteAction = new QuoteAction(SourceAsset = new Asset(Quantity = 5))
        );

        System.assertEquals(5, RenewalAssetQuantityHandler.resolveSourceQuantity(qli));
    }

    @IsTest
    static void resolveSourceQuantity_fallsBackToEndThenStart() {
        System.assertEquals(
            4,
            RenewalAssetQuantityHandler.resolveSourceQuantity(null, 4, 2)
        );
        System.assertEquals(
            3,
            RenewalAssetQuantityHandler.resolveSourceQuantity(null, null, 3)
        );
    }

    @IsTest
    static void needsQuantityNormalization_trueForZeroQtyRenewalMaintenance() {
        QuoteLineItem qli = new QuoteLineItem(
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            QuoteActionId = fakeQuoteActionId(),
            Quantity = 0
        );

        System.assertEquals(
            true,
            RenewalAssetQuantityHandler.needsQuantityNormalization(qli, 2)
        );
    }

    @IsTest
    static void needsQuantityNormalization_falseWhenQuantityAlreadySet() {
        QuoteLineItem qli = new QuoteLineItem(
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            QuoteActionId = fakeQuoteActionId(),
            Quantity = 1
        );

        System.assertEquals(
            false,
            RenewalAssetQuantityHandler.needsQuantityNormalization(qli, 2)
        );
    }

    @IsTest
    static void needsQuantityNormalization_falseWithoutQuoteAction() {
        QuoteLineItem qli = new QuoteLineItem(
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            Quantity = 0
        );

        System.assertEquals(
            false,
            RenewalAssetQuantityHandler.needsQuantityNormalization(qli, 2)
        );
    }

    @IsTest
    static void buildNormalizationUpdates_flipsNoChangeAndCopiesAssetQuantity() {
        Id quoteActionId = fakeQuoteActionId();
        Id lineId = fakeQuoteLineItemId();

        QuoteLineItem candidate = new QuoteLineItem(
            Id = lineId,
            QuoteActionId = quoteActionId,
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            Quantity = 0,
            QuoteAction = new QuoteAction(
                Id = quoteActionId,
                Type = RenewalAssetQuantityHandler.QUOTE_ACTION_NO_CHANGE,
                SourceAsset = new Asset(Quantity = 3)
            )
        );

        RenewalAssetQuantityHandler.NormalizationUpdates updates =
            RenewalAssetQuantityHandler.buildNormalizationUpdates(
                new List<QuoteLineItem>{ candidate }
            );

        System.assertEquals(1, updates.quoteActionsById.size());
        System.assertEquals(
            RenewalAssetQuantityHandler.QUOTE_ACTION_RENEW,
            updates.quoteActionsById.get(quoteActionId).Type
        );
        System.assertEquals(1, updates.linesToUpdate.size());
        System.assertEquals(3, updates.linesToUpdate[0].Quantity);
        System.assertEquals(0, updates.linesToUpdate[0].StartQuantity);
    }

    @IsTest
    static void buildNormalizationUpdates_updatesRenewLineWithoutQuoteActionChange() {
        Id quoteActionId = fakeQuoteActionId();
        Id lineId = fakeQuoteLineItemId();

        QuoteLineItem candidate = new QuoteLineItem(
            Id = lineId,
            QuoteActionId = quoteActionId,
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            Quantity = 0,
            StartQuantity = 1,
            QuoteAction = new QuoteAction(
                Id = quoteActionId,
                Type = RenewalAssetQuantityHandler.QUOTE_ACTION_RENEW,
                SourceAsset = new Asset(Quantity = 2)
            )
        );

        RenewalAssetQuantityHandler.NormalizationUpdates updates =
            RenewalAssetQuantityHandler.buildNormalizationUpdates(
                new List<QuoteLineItem>{ candidate }
            );

        System.assertEquals(0, updates.quoteActionsById.size());
        System.assertEquals(1, updates.linesToUpdate.size());
        System.assertEquals(2, updates.linesToUpdate[0].Quantity);
    }

    @IsTest
    static void buildNormalizationUpdates_skipsUnsupportedQuoteActionTypes() {
        Id quoteActionId = fakeQuoteActionId();

        QuoteLineItem candidate = new QuoteLineItem(
            Id = fakeQuoteLineItemId(),
            QuoteActionId = quoteActionId,
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            Quantity = 0,
            QuoteAction = new QuoteAction(
                Id = quoteActionId,
                Type = 'Cancel',
                SourceAsset = new Asset(Quantity = 2)
            )
        );

        RenewalAssetQuantityHandler.NormalizationUpdates updates =
            RenewalAssetQuantityHandler.buildNormalizationUpdates(
                new List<QuoteLineItem>{ candidate }
            );

        System.assertEquals(0, updates.quoteActionsById.size());
        System.assertEquals(0, updates.linesToUpdate.size());
    }

    @IsTest
    static void enqueueQuantityNormalization_noOpWhenNullOrEmpty() {
        Test.startTest();
        RenewalAssetQuantityHandler.enqueueQuantityNormalization(null);
        RenewalAssetQuantityHandler.enqueueQuantityNormalization(new List<QuoteLineItem>());
        Test.stopTest();

        System.assert(true, 'Null and empty inputs should return without error');
    }

    @IsTest
    static void applyAssetQuantitiesForQuotes_noOpWhenNotRenewalQuote() {
        Account account = new Account(Name = 'Asset Qty Test Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Asset Qty Test Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'New Business Quote',
            OpportunityId = opp.Id,
            Quote_Type__c = 'New'
        );
        insert quote;

        Test.startTest();
        RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(new Set<Id>{ quote.Id });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id]);
    }

    @IsTest
    static void resolveRenewalQuoteIds_includesRenewalQuotes() {
        Account account = new Account(Name = 'Asset Qty Test Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Asset Qty Test Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote renewalQuote = new Quote(
            Name = 'Renewal Quote',
            OpportunityId = opp.Id,
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        insert renewalQuote;

        Set<Id> renewalIds = RenewalAssetQuantityHandler.resolveRenewalQuoteIds(
            new Set<Id>{ renewalQuote.Id }
        );

        System.assertEquals(1, renewalIds.size());
        System.assert(renewalIds.contains(renewalQuote.Id));
    }

    @IsTest
    static void enqueueQuantityNormalization_runsForRenewalQuoteInTestContext() {
        Quote quote = createRenewalQuote();

        Test.startTest();
        RenewalAssetQuantityHandler.enqueueQuantityNormalization(
            new List<QuoteLineItem>{ new QuoteLineItem(QuoteId = quote.Id) }
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id]);
    }

    @IsTest
    static void queueable_executesHandler() {
        Quote quote = createRenewalQuote();

        Test.startTest();
        System.enqueueJob(new RenewalAssetQuantityQueueable(new Set<Id>{ quote.Id }));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id]);
    }

    private static Quote createRenewalQuote() {
        Account account = new Account(Name = 'Asset Qty Test Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Asset Qty Test Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Renewal Quote',
            OpportunityId = opp.Id,
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        insert quote;
        return quote;
    }

    private static Id fakeQuoteActionId() {
        return fakeIdFor(QuoteAction.SObjectType);
    }

    private static Id fakeQuoteLineItemId() {
        return fakeIdFor(QuoteLineItem.SObjectType);
    }

    private static Id fakeIdFor(Schema.SObjectType sobjectType) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        return (Id) (keyPrefix + '000000000001AAA');
    }
}