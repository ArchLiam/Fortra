@IsTest
private class RenewalQuoteLineHandlerCoverageTest {

    private static Quote createRenewalQuote() {
        Account account = new Account(Name = 'Handler Coverage Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Handler Coverage Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Handler Renewal Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        insert quote;
        return quote;
    }

    private static PricebookEntry createMaintenancePbe(String productCode, String productType) {
        Product2 product = new Product2(
            Name = productCode,
            ProductCode = productCode,
            IsActive = true,
            Fortra_Product_Type__c = productType
        );
        insert product;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 71,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }

    @IsTest
    static void resolveRenewalQuoteIds_includesRenewalQuoteType() {
        Account account = new Account(Name = 'Handler Resolve Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Handler Resolve Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote renewalQuote = new Quote(
            Name = 'Handler Renewal Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        Quote newQuote = new Quote(
            Name = 'Handler New Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'New'
        );
        insert new List<Quote>{ renewalQuote, newQuote };

        Test.startTest();
        Set<Id> resolved = RenewalQuoteLineHandler.resolveRenewalQuoteIds(
            new Set<Id>{ renewalQuote.Id, newQuote.Id }
        );
        RenewalQuoteLineHandler.enqueueCarryoverCleanup(null);
        RenewalQuoteLineHandler.enqueueCarryoverCleanup(new List<QuoteLineItem>());
        RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes(null);
        RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes(new Set<Id>());
        RenewalQuoteLineHandler.removeNewMaintenanceCarryover(null);
        RenewalQuoteLineHandler.removeNewMaintenanceCarryover(new List<QuoteLineItem>());
        Test.stopTest();

        System.assertEquals(true, resolved.contains(renewalQuote.Id));
        System.assertEquals(false, resolved.contains(newQuote.Id));
    }

    @IsTest
    static void removeCarryover_deletesNewMaintenanceWhenRenewalPresent() {
        Quote quote = createRenewalQuote();
        PricebookEntry newMaintPbe = createMaintenancePbe(
            'RNM-COV-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_NEW_MAINTENANCE
        );
        PricebookEntry renewalPbe = createMaintenancePbe(
            'RRM-COV-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );

        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = renewalPbe.Id,
                Product2Id = renewalPbe.Product2Id,
                Quantity = 1,
                UnitPrice = 71
            ),
            new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = newMaintPbe.Id,
                Product2Id = newMaintPbe.Product2Id,
                Quantity = 1,
                UnitPrice = 71
            )
        };
        insert lines;

        Test.startTest();
        RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes(
            new Set<Id>{ quote.Id },
            lines
        );
        Test.stopTest();

        List<QuoteLineItem> remaining = [
            SELECT Product2.Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE QuoteId = :quote.Id
        ];
        System.assertEquals(1, remaining.size());
        System.assertEquals(
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            remaining[0].Product2.Fortra_Product_Type__c
        );
    }

    @IsTest
    static void removeCarryover_noOpUntilRenewalMaintenanceExists() {
        Quote quote = createRenewalQuote();
        PricebookEntry newMaintPbe = createMaintenancePbe(
            'RNM-GUARD-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_NEW_MAINTENANCE
        );

        QuoteLineItem carryoverLine = new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = newMaintPbe.Id,
            Product2Id = newMaintPbe.Product2Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert carryoverLine;

        Test.startTest();
        RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes(
            new Set<Id>{ quote.Id },
            new List<QuoteLineItem>{ carryoverLine }
        );
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id],
            'Carryover should remain until Renewal Maintenance is present'
        );
    }

    @IsTest
    static void enqueueCarryoverCleanup_noOpForNonRenewalQuote() {
        Account account = new Account(Name = 'Handler NonRenew Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Handler NonRenew Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Handler NonRenew Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'New'
        );
        insert quote;

        Test.startTest();
        RenewalQuoteLineHandler.enqueueCarryoverCleanup(new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = quote.Id, Quantity = 1, UnitPrice = 10)
        });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id]);
    }
}