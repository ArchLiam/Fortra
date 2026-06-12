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
    static void enqueueQuantityNormalization_noOpWhenLinesHaveNoQuoteId() {
        // Non-empty list whose lines all lack QuoteId -> collected quoteIds set is empty
        // -> the second guard returns before any enqueue/normalization.
        Test.startTest();
        RenewalAssetQuantityHandler.enqueueQuantityNormalization(
            new List<QuoteLineItem>{ new QuoteLineItem(), new QuoteLineItem() }
        );
        Test.stopTest();

        System.assert(true, 'Lines without QuoteId yield an empty quote-id set and return');
    }

    @IsTest
    static void applyAssetQuantitiesForQuotes_noOpWhenNullOrEmpty() {
        Test.startTest();
        RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(null);
        RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(new Set<Id>());
        Test.stopTest();

        System.assert(true, 'Null and empty quote-id sets return without error');
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

    // -----------------------------------------------------------------------
    // resolveSourceQuantity guard branches
    // -----------------------------------------------------------------------

    @IsTest
    static void resolveSourceQuantity_nullLineReturnsNull() {
        System.assertEquals(
            null,
            RenewalAssetQuantityHandler.resolveSourceQuantity((QuoteLineItem) null),
            'A null line resolves to a null source quantity'
        );
    }

    @IsTest
    static void resolveSourceQuantity_allNullOrNonPositiveReturnsNull() {
        // asset null, end null/0, start null/0 -> falls through every branch to null
        System.assertEquals(
            null,
            RenewalAssetQuantityHandler.resolveSourceQuantity(null, null, null)
        );
        System.assertEquals(
            null,
            RenewalAssetQuantityHandler.resolveSourceQuantity(0, 0, 0)
        );
    }

    // -----------------------------------------------------------------------
    // needsQuantityNormalization guard branches
    // -----------------------------------------------------------------------

    @IsTest
    static void needsQuantityNormalization_falseForNullLineOrSource() {
        // null qli -> false
        System.assertEquals(
            false,
            RenewalAssetQuantityHandler.needsQuantityNormalization(null, 2)
        );
        // null source quantity -> false
        QuoteLineItem qli = new QuoteLineItem(
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            QuoteActionId = fakeQuoteActionId(),
            Quantity = 0
        );
        System.assertEquals(
            false,
            RenewalAssetQuantityHandler.needsQuantityNormalization(qli, null)
        );
        // non-positive source quantity -> false
        System.assertEquals(
            false,
            RenewalAssetQuantityHandler.needsQuantityNormalization(qli, 0)
        );
    }

    @IsTest
    static void needsQuantityNormalization_falseForWrongProductType() {
        QuoteLineItem qli = new QuoteLineItem(
            Fortra_Product_Type__c = 'Perpetual',
            QuoteActionId = fakeQuoteActionId(),
            Quantity = 0
        );
        System.assertEquals(
            false,
            RenewalAssetQuantityHandler.needsQuantityNormalization(qli, 2),
            'Only Renewal Maintenance lines are normalized'
        );
    }

    // -----------------------------------------------------------------------
    // buildNormalizationUpdates guard / continue branches
    // -----------------------------------------------------------------------

    @IsTest
    static void buildNormalizationUpdates_nullAndEmptyReturnEmptyUpdates() {
        RenewalAssetQuantityHandler.NormalizationUpdates nullUpdates =
            RenewalAssetQuantityHandler.buildNormalizationUpdates(null);
        System.assertEquals(0, nullUpdates.quoteActionsById.size());
        System.assertEquals(0, nullUpdates.linesToUpdate.size());

        RenewalAssetQuantityHandler.NormalizationUpdates emptyUpdates =
            RenewalAssetQuantityHandler.buildNormalizationUpdates(new List<QuoteLineItem>());
        System.assertEquals(0, emptyUpdates.quoteActionsById.size());
        System.assertEquals(0, emptyUpdates.linesToUpdate.size());
    }

    @IsTest
    static void buildNormalizationUpdates_skipsLineThatDoesNotNeedNormalization() {
        // Renewal Maintenance line with a QuoteAction but NO resolvable source quantity
        // (asset/end/start all null) -> resolveSourceQuantity null -> needs check false -> continue.
        Id quoteActionId = fakeQuoteActionId();
        QuoteLineItem candidate = new QuoteLineItem(
            Id = fakeQuoteLineItemId(),
            QuoteActionId = quoteActionId,
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            Quantity = 0,
            QuoteAction = new QuoteAction(
                Id = quoteActionId,
                Type = RenewalAssetQuantityHandler.QUOTE_ACTION_NO_CHANGE
            )
        );

        RenewalAssetQuantityHandler.NormalizationUpdates updates =
            RenewalAssetQuantityHandler.buildNormalizationUpdates(
                new List<QuoteLineItem>{ candidate }
            );

        System.assertEquals(0, updates.quoteActionsById.size(),
            'No source quantity -> line is skipped, no QuoteAction flip');
        System.assertEquals(0, updates.linesToUpdate.size());
    }

    // -----------------------------------------------------------------------
    // applyAssetQuantitiesForQuotes — full DML happy path (No Change -> Renew flip)
    // -----------------------------------------------------------------------

    @IsTest
    static void applyAssetQuantitiesForQuotes_normalizesZeroQtyRenewalLineFromAsset() {
        RenewalLineFixture fixture = createRenewalQuoteWithZeroQtyMaintenanceLine(
            RenewalAssetQuantityHandler.QUOTE_ACTION_NO_CHANGE,
            5 // SourceAsset.Quantity
        );

        Test.startTest();
        RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(
            new Set<Id>{ fixture.quoteId }
        );
        Test.stopTest();

        QuoteLineItem updatedLine = [
            SELECT Id, Quantity, StartQuantity FROM QuoteLineItem WHERE Id = :fixture.lineId
        ];
        System.assertEquals(5, updatedLine.Quantity,
            'Billing Quantity is normalized to the source asset quantity');
        System.assertEquals(0, updatedLine.StartQuantity,
            'StartQuantity is zeroed during normalization');

        QuoteAction updatedAction = [
            SELECT Id, Type FROM QuoteAction WHERE Id = :fixture.quoteActionId
        ];
        System.assertEquals(
            RenewalAssetQuantityHandler.QUOTE_ACTION_RENEW,
            updatedAction.Type,
            'A No Change action that gained billing quantity is flipped to Renew'
        );
    }

    @IsTest
    static void applyAssetQuantitiesForQuotes_normalizesRenewLineWithoutActionFlip() {
        // Action already Renew -> line quantity updated, no QuoteAction flip recorded.
        RenewalLineFixture fixture = createRenewalQuoteWithZeroQtyMaintenanceLine(
            RenewalAssetQuantityHandler.QUOTE_ACTION_RENEW,
            4
        );

        Test.startTest();
        RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(
            new Set<Id>{ fixture.quoteId }
        );
        Test.stopTest();

        QuoteLineItem updatedLine = [
            SELECT Id, Quantity FROM QuoteLineItem WHERE Id = :fixture.lineId
        ];
        System.assertEquals(4, updatedLine.Quantity,
            'Renew line billing quantity is normalized to the asset quantity');

        QuoteAction action = [SELECT Id, Type FROM QuoteAction WHERE Id = :fixture.quoteActionId];
        System.assertEquals(
            RenewalAssetQuantityHandler.QUOTE_ACTION_RENEW,
            action.Type,
            'An already-Renew action is left unchanged'
        );
    }

    @IsTest
    static void applyAssetQuantitiesForQuotes_noOpWhenNoZeroQtyCandidates() {
        // Renewal quote whose Renewal Maintenance line already has a positive Quantity:
        // the candidate query (Quantity <= 0) returns empty -> early return, no DML.
        RenewalLineFixture fixture = createRenewalQuoteWithZeroQtyMaintenanceLine(
            RenewalAssetQuantityHandler.QUOTE_ACTION_RENEW,
            4
        );
        update new QuoteLineItem(Id = fixture.lineId, Quantity = 3);

        Test.startTest();
        RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(
            new Set<Id>{ fixture.quoteId }
        );
        Test.stopTest();

        QuoteLineItem line = [SELECT Id, Quantity FROM QuoteLineItem WHERE Id = :fixture.lineId];
        System.assertEquals(3, line.Quantity,
            'A line that already has positive quantity is not a candidate and is untouched');
    }

    // -----------------------------------------------------------------------
    // Fixtures / helpers
    // -----------------------------------------------------------------------

    private class RenewalLineFixture {
        Id quoteId;
        Id lineId;
        Id quoteActionId;
    }

    /**
     * Builds a real Renewal Quote with a single zero-quantity Renewal Maintenance QLI
     * tied to a QuoteAction (the asset-renew "both assets" path). The QuoteAction carries
     * a SourceAsset so resolveSourceQuantity returns the asset quantity.
     */
    private static RenewalLineFixture createRenewalQuoteWithZeroQtyMaintenanceLine(
        String quoteActionType,
        Decimal assetQuantity
    ) {
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
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        insert quote;

        Asset sourceAsset = new Asset(
            Name = 'Renewed Asset',
            AccountId = account.Id,
            Quantity = assetQuantity
        );
        insert sourceAsset;

        QuoteAction quoteAction = new QuoteAction(
            QuoteId = quote.Id,
            Type = quoteActionType,
            SourceAssetId = sourceAsset.Id
        );
        insert quoteAction;

        Product2 product = new Product2(
            Name = 'Renewal Maint Product',
            ProductCode = 'RAQH-RM-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );
        insert product;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 71,
            IsActive = true
        );
        insert pbe;

        // The platform rejects a positive Start Quantity on a Renew-action line
        // ("Specify null or 0 in Start Quantity ... action of type Renew"). Only the
        // No Change action permits a non-zero seed; the source quantity for Renew lines
        // comes from the SourceAsset.
        Decimal startQty =
            quoteActionType == RenewalAssetQuantityHandler.QUOTE_ACTION_NO_CHANGE ? 2 : 0;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = product.Id,
            Quantity = 0,
            StartQuantity = startQty,
            UnitPrice = 71,
            QuoteActionId = quoteAction.Id,
            Fortra_Product_Type__c = RenewalAssetQuantityHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );
        insert qli;

        RenewalLineFixture fixture = new RenewalLineFixture();
        fixture.quoteId = quote.Id;
        fixture.lineId = qli.Id;
        fixture.quoteActionId = quoteAction.Id;
        return fixture;
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