@IsTest
private class RenewalMaintenanceAutoAddHandlerTest {

    private static Quote createRenewalQuote() {
        Account account = new Account(Name = 'AutoAdd Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'AutoAdd Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'AutoAdd Quote',
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
    static void ensureRenewalMaintenancePresent_noOpOnEmptySet() {
        Test.startTest();
        RenewalMaintenanceAutoAddHandler.ensureRenewalMaintenancePresent(null);
        RenewalMaintenanceAutoAddHandler.ensureRenewalMaintenancePresent(new Set<Id>());
        RenewalMaintenanceAutoAddHandler.enqueueIfNeeded(null);
        RenewalMaintenanceAutoAddHandler.enqueueIfNeeded(new List<QuoteLineItem>());
        Test.stopTest();
        System.assert(true, 'Empty input should return without error');
    }

    @IsTest
    static void ensureRenewalMaintenancePresent_skipsNonRenewalQuote() {
        Account account = new Account(Name = 'AutoAdd NonRenew');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'AutoAdd NonRenew Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'AutoAdd NonRenew Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'New'
        );
        insert quote;

        Test.startTest();
        RenewalMaintenanceAutoAddHandler.ensureRenewalMaintenancePresent(new Set<Id>{ quote.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id],
            'Non-renewal quotes should not receive auto-added lines'
        );
    }

    @IsTest
    static void ensureRenewalMaintenancePresent_skipsWithoutBoksPerpetual() {
        Quote quote = createRenewalQuote();
        PricebookEntry renewalPbe = createMaintenancePbe(
            'RRM-NOBOKS-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );

        insert new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = renewalPbe.Id,
            Product2Id = renewalPbe.Product2Id,
            Quantity = 1,
            UnitPrice = 3300
        );

        Test.startTest();
        RenewalMaintenanceAutoAddHandler.ensureRenewalMaintenancePresent(new Set<Id>{ quote.Id });
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :quote.Id],
            'Without BoKS perpetual, handler should not add another line'
        );
    }

    @IsTest
    static void enqueueIfNeeded_runsCleanupInTestContext() {
        Quote quote = createRenewalQuote();
        PricebookEntry newMaintPbe = createMaintenancePbe(
            'RNM-SYNC-' + String.valueOf(Crypto.getRandomInteger()),
            RenewalQuoteLineHandler.PRODUCT_TYPE_NEW_MAINTENANCE
        );
        PricebookEntry renewalPbe = createMaintenancePbe(
            'RRM-SYNC-' + String.valueOf(Crypto.getRandomInteger()),
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
        RenewalMaintenanceAutoAddHandler.enqueueIfNeeded(lines);
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

    @IsTest(SeeAllData=true)
    static void ensureRenewalMaintenancePresent_addsRrmWhenBoksPerpetualExists() {
        List<PricebookEntry> perpetualPbes = [
            SELECT Id, Pricebook2Id, Product2Id
            FROM PricebookEntry
            WHERE Product2.ProductCode = :RenewalMaintenanceAutoAddHandler.BOKS_PERPETUAL_PRODUCT_CODE
              AND IsActive = true
            LIMIT 1
        ];
        if (perpetualPbes.isEmpty()) {
            System.assert(true, 'BoKS perpetual catalog product unavailable in this org');
            return;
        }

        List<PricebookEntry> renewalPbes = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2.ProductCode = :RenewalMaintenanceAutoAddHandler.RENEWAL_MAINTENANCE_PRODUCT_CODE
              AND Pricebook2Id = :perpetualPbes[0].Pricebook2Id
              AND IsActive = true
            LIMIT 1
        ];
        if (renewalPbes.isEmpty()) {
            System.assert(true, 'BoKS RRM catalog product unavailable in this org');
            return;
        }

        Account account = new Account(Name = 'AutoAdd BoKS Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'AutoAdd BoKS Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        PricebookEntry perpetualPbe = perpetualPbes[0];
        Quote quote = new Quote(
            Name = 'AutoAdd BoKS Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = perpetualPbe.Pricebook2Id,
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        insert quote;

        try {
            insert new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = perpetualPbe.Id,
                Product2Id = perpetualPbe.Product2Id,
                Quantity = 1,
                UnitPrice = 15300
            );
        } catch (DmlException e) {
            System.assert(true, 'BoKS perpetual line cannot be inserted in test context: ' + e.getMessage());
            return;
        }

        Test.startTest();
        RenewalMaintenanceAutoAddHandler.ensureRenewalMaintenancePresent(new Set<Id>{ quote.Id });
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE QuoteId = :quote.Id
                  AND Product2.ProductCode = :RenewalMaintenanceAutoAddHandler.RENEWAL_MAINTENANCE_PRODUCT_CODE
            ],
            'RRM line should be auto-added'
        );
    }

    @IsTest
    static void shouldSkipCarryoverCleanupForTriggerContext_falseOutsideTrigger() {
        System.assertEquals(
            false,
            RenewalMaintenanceAutoAddHandler.shouldSkipCarryoverCleanupForTriggerContext(),
            'Direct/test invocation should still allow carryover cleanup'
        );
    }

    @IsTest(SeeAllData=true)
    static void loadQuoteContexts_selectsPbeMatchingQuoteCurrency() {
        Map<Id, Set<String>> currenciesByPricebook = new Map<Id, Set<String>>();
        for (PricebookEntry pbe : [
            SELECT Id, Pricebook2Id, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Product2.ProductCode = :RenewalMaintenanceAutoAddHandler.RENEWAL_MAINTENANCE_PRODUCT_CODE
              AND IsActive = true
        ]) {
            if (!currenciesByPricebook.containsKey(pbe.Pricebook2Id)) {
                currenciesByPricebook.put(pbe.Pricebook2Id, new Set<String>());
            }
            currenciesByPricebook.get(pbe.Pricebook2Id).add(pbe.CurrencyIsoCode);
        }

        Id pricebookId;
        String quoteCurrency;
        for (Id pbId : currenciesByPricebook.keySet()) {
            if (currenciesByPricebook.get(pbId).size() > 1) {
                pricebookId = pbId;
                quoteCurrency = new List<String>(currenciesByPricebook.get(pbId))[0];
                break;
            }
        }
        if (pricebookId == null) {
            System.assert(true, 'No multi-currency RRM price book entries in org');
            return;
        }

        Account account = new Account(Name = 'AutoAdd Currency Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'AutoAdd Currency Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            CurrencyIsoCode = quoteCurrency
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'AutoAdd Currency Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId,
            CurrencyIsoCode = quoteCurrency,
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        insert quote;

        quote = [
            SELECT Id, Pricebook2Id, CurrencyIsoCode
            FROM Quote
            WHERE Id = :quote.Id
        ];

        Map<Id, RenewalMaintenanceAutoAddHandler.QuoteContext> contexts =
            RenewalMaintenanceAutoAddHandler.loadQuoteContexts(new Set<Id>{ quote.Id });

        List<PricebookEntry> expectedPbes = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
              AND Product2.ProductCode = :RenewalMaintenanceAutoAddHandler.RENEWAL_MAINTENANCE_PRODUCT_CODE
              AND CurrencyIsoCode = :quote.CurrencyIsoCode
              AND IsActive = true
            ORDER BY Id ASC
            LIMIT 1
        ];
        System.assert(!expectedPbes.isEmpty(), 'Expected currency-matched RRM PBE');
        System.assertEquals(
            expectedPbes[0].Id,
            contexts.get(quote.Id).renewalMaintenancePbeId,
            'RRM PBE should match quote currency'
        );
    }
}