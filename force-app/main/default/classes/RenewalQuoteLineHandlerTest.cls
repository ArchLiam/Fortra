@IsTest
private class RenewalQuoteLineHandlerTest {

    private static Quote createRenewalQuote() {
        Account account = new Account(Name = 'Renewal Handler Test Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Renewal Handler Test Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Renewal Handler Quote',
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
    static void removeNewMaintenanceCarryover_noOpWhenNullOrEmpty() {
        Test.startTest();
        RenewalQuoteLineHandler.removeNewMaintenanceCarryover(null);
        RenewalQuoteLineHandler.removeNewMaintenanceCarryover(new List<QuoteLineItem>());
        Test.stopTest();

        System.assert(true, 'Null and empty inputs should return without error');
    }

    @IsTest
    static void removeNewMaintenanceCarryover_noOpWhenNoRenewalQuotes() {
        Account account = new Account(Name = 'Renewal Handler Test Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Renewal Handler Test Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Non-Renew Quote',
            OpportunityId = opp.Id,
            Quote_Type__c = 'New'
        );
        insert quote;

        QuoteLineItem line = new QuoteLineItem(
            QuoteId = quote.Id,
            Quantity = 1,
            UnitPrice = 100
        );

        Test.startTest();
        RenewalQuoteLineHandler.removeNewMaintenanceCarryover(new List<QuoteLineItem>{ line });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id]);
    }

    @IsTest
    static void removeNewMaintenanceCarryover_deletesNewMaintenanceWhenRenewalPresentInBatch() {
        Quote quote = createRenewalQuote();
        PricebookEntry newMaintPbe = createMaintenancePbe(
            'RNM-TEST-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_NEW_MAINTENANCE
        );
        PricebookEntry renewalMaintPbe = createMaintenancePbe(
            'RRM-TEST-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );

        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = renewalMaintPbe.Id,
                Product2Id = renewalMaintPbe.Product2Id,
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

        Test.startTest();
        insert lines;
        Test.stopTest();

        List<QuoteLineItem> remaining = [
            SELECT Id, Product2.Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE QuoteId = :quote.Id
        ];
        System.assertEquals(1, remaining.size(), 'New Maintenance carryover should be removed');
        System.assertEquals(
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            remaining[0].Product2.Fortra_Product_Type__c
        );
    }

    @IsTest
    static void removeNewMaintenanceCarryover_deletesExistingNewMaintenanceAfterRenewalInsert() {
        Quote quote = createRenewalQuote();
        PricebookEntry newMaintPbe = createMaintenancePbe(
            'RNM-EXIST-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_NEW_MAINTENANCE
        );
        PricebookEntry renewalMaintPbe = createMaintenancePbe(
            'RRM-EXIST-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );

        insert new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = newMaintPbe.Id,
            Product2Id = newMaintPbe.Product2Id,
            Quantity = 1,
            UnitPrice = 71
        );

        Test.startTest();
        insert new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = renewalMaintPbe.Id,
            Product2Id = renewalMaintPbe.Product2Id,
            Quantity = 1,
            UnitPrice = 71
        );
        Test.stopTest();

        List<QuoteLineItem> remaining = [
            SELECT Id, Product2.Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE QuoteId = :quote.Id
        ];
        System.assertEquals(1, remaining.size(), 'Stale New Maintenance should be deleted via trigger');
        System.assertEquals(
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            remaining[0].Product2.Fortra_Product_Type__c
        );
    }

    @IsTest
    static void removeNewMaintenanceCarryover_deletesLicenseAndNewMaintWhenRenewalPresentInBatch() {
        Quote quote = createRenewalQuote();
        Product2 licenseProduct = new Product2(
            Name = 'LIC-TEST',
            ProductCode = 'LIC-TEST-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            Fortra_Product_Type__c = RenewalQuoteLineHandler.PRODUCT_TYPE_PERPETUAL
        );
        insert licenseProduct;

        PricebookEntry licensePbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = licenseProduct.Id,
            UnitPrice = 355,
            IsActive = true
        );
        insert licensePbe;

        PricebookEntry newMaintPbe = createMaintenancePbe(
            'RNM-LIC-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_NEW_MAINTENANCE
        );
        PricebookEntry renewalMaintPbe = createMaintenancePbe(
            'RRM-LIC-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );

        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = renewalMaintPbe.Id,
                Product2Id = renewalMaintPbe.Product2Id,
                Quantity = 1,
                UnitPrice = 71
            ),
            new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = licensePbe.Id,
                Product2Id = licensePbe.Product2Id,
                Quantity = 1,
                UnitPrice = 355
            ),
            new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = newMaintPbe.Id,
                Product2Id = newMaintPbe.Product2Id,
                Quantity = 1,
                UnitPrice = 71
            )
        };

        Test.startTest();
        insert lines;
        Test.stopTest();

        List<QuoteLineItem> remaining = [
            SELECT Id, Product2.Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE QuoteId = :quote.Id
        ];
        System.assertEquals(1, remaining.size(), 'Only Renewal Maintenance should remain');
        System.assertEquals(
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            remaining[0].Product2.Fortra_Product_Type__c
        );
    }

    @IsTest
    static void isCarryoverProductType_identifiesPerpetualAndNewMaintenance() {
        System.assertEquals(true, RenewalQuoteLineHandler.isCarryoverProductType('Perpetual'));
        System.assertEquals(true, RenewalQuoteLineHandler.isCarryoverProductType('New Maintenance'));
        System.assertEquals(false, RenewalQuoteLineHandler.isCarryoverProductType('Renewal Maintenance'));
    }

    @IsTest
    static void findQuotesWithRenewalMaintenance_emptyWhenNoRenewalLines() {
        Quote quote = createRenewalQuote();
        Set<Id> renewalQuoteIds = new Set<Id>{ quote.Id };
        QuoteLineItem stubLine = new QuoteLineItem(QuoteId = quote.Id);

        Test.startTest();
        Set<Id> guarded = RenewalQuoteLineHandler.findQuotesWithRenewalMaintenance(
            renewalQuoteIds,
            new List<QuoteLineItem>{ stubLine }
        );
        Test.stopTest();

        System.assertEquals(true, guarded.isEmpty(), 'Guard should block until Renewal Maintenance exists');
    }

    @IsTest
    static void findQuotesWithRenewalMaintenance_ignoresProgrammaticAddRrm() {
        Quote quote = createRenewalQuote();
        PricebookEntry renewalMaintPbe = createMaintenancePbe(
            'RRM-ADD-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );

        QuoteAction programmaticAdd = new QuoteAction(
            QuoteId = quote.Id,
            Type = RenewalQuoteLineHandler.PROGRAMMATIC_RRM_QUOTE_ACTION_TYPE
        );
        insert programmaticAdd;

        QuoteLineItem orphanRrm = new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = renewalMaintPbe.Id,
            Product2Id = renewalMaintPbe.Product2Id,
            QuoteActionId = programmaticAdd.Id,
            Quantity = 1,
            UnitPrice = 71
        );
        insert orphanRrm;

        Test.startTest();
        Set<Id> guarded = RenewalQuoteLineHandler.findQuotesWithRenewalMaintenance(
            new Set<Id>{ quote.Id },
            new List<QuoteLineItem>{ orphanRrm }
        );
        RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes(new Set<Id>{ quote.Id });
        Test.stopTest();

        System.assertEquals(true, guarded.isEmpty(), 'Programmatic Add RRM should not unlock cleanup');
        System.assertEquals(1, [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id]);
    }

    @IsTest
    static void resolveRenewalQuoteIds_includesRenewalQuoteType() {
        Account account = new Account(Name = 'Renewal Resolve Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Renewal Resolve Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote renewalQuote = new Quote(
            Name = 'Renewal Resolve Quote',
            OpportunityId = opp.Id,
            Quote_Type__c = 'Renewal'
        );
        insert renewalQuote;

        Quote newQuote = new Quote(
            Name = 'New Resolve Quote',
            OpportunityId = opp.Id,
            Quote_Type__c = 'New'
        );
        insert newQuote;

        Test.startTest();
        Set<Id> resolved = RenewalQuoteLineHandler.resolveRenewalQuoteIds(
            new Set<Id>{ renewalQuote.Id, newQuote.Id }
        );
        Test.stopTest();

        System.assertEquals(true, resolved.contains(renewalQuote.Id));
        System.assertEquals(false, resolved.contains(newQuote.Id));
    }
}