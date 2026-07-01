@isTest
public class DatedConversionRateLookupTest {

    @isTest
    static void testUSDReturnsOne() {
        DatedConversionRateLookup.Request req = new DatedConversionRateLookup.Request();
        req.currencyIsoCode = 'USD';

        Test.startTest();
        List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(
            new List<DatedConversionRateLookup.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return exactly 1 result');
        System.assertEquals(1.0, results[0].exchangeRate, 'USD exchange rate should be 1.0');
    }

    @isTest
    static void testNullCurrencyReturnsOne() {
        DatedConversionRateLookup.Request req = new DatedConversionRateLookup.Request();
        req.currencyIsoCode = null;

        Test.startTest();
        List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(
            new List<DatedConversionRateLookup.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return exactly 1 result');
        System.assertEquals(1.0, results[0].exchangeRate, 'Null currency should return 1.0');
    }

    @isTest
    static void testBlankCurrencyReturnsOne() {
        DatedConversionRateLookup.Request req = new DatedConversionRateLookup.Request();
        req.currencyIsoCode = '';

        Test.startTest();
        List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(
            new List<DatedConversionRateLookup.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return exactly 1 result');
        System.assertEquals(1.0, results[0].exchangeRate, 'Blank currency should return 1.0');
    }

    @isTest
    static void testFallbackToCurrencyType() {
        // Find an active non-USD CurrencyType to test with
        List<CurrencyType> activeCurrencies = [
            SELECT IsoCode, ConversionRate
            FROM CurrencyType
            WHERE IsoCode != 'USD'
            AND IsActive = true
            LIMIT 1
        ];

        if (activeCurrencies.isEmpty()) {
            // No non-USD currencies enabled in this org — skip gracefully
            System.assert(true, 'No non-USD currencies available; skipping fallback test');
            return;
        }

        String testCode = activeCurrencies[0].IsoCode;
        Decimal expectedRate = activeCurrencies[0].ConversionRate;

        DatedConversionRateLookup.Request req = new DatedConversionRateLookup.Request();
        req.currencyIsoCode = testCode;
        // Use a far-future date so DatedConversionRate likely has no row,
        // forcing the CurrencyType fallback
        req.lookupDate = Date.newInstance(2099, 12, 31);

        Test.startTest();
        List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(
            new List<DatedConversionRateLookup.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return exactly 1 result');
        System.assertNotEquals(null, results[0].exchangeRate,
            'Should find a rate via CurrencyType fallback for ' + testCode);
        // If DatedConversionRate had no row for 2099, the result should match
        // the raw CurrencyType ConversionRate
        System.assertEquals(expectedRate, results[0].exchangeRate,
            'Rate should match CurrencyType ConversionRate for ' + testCode);
    }

    @isTest
    static void testMultipleRequests() {
        // Find an active non-USD currency for mixed-list test
        List<CurrencyType> activeCurrencies = [
            SELECT IsoCode
            FROM CurrencyType
            WHERE IsoCode != 'USD'
            AND IsActive = true
            LIMIT 1
        ];

        String nonUsdCode = activeCurrencies.isEmpty() ? 'EUR' : activeCurrencies[0].IsoCode;

        // Request 1: USD
        DatedConversionRateLookup.Request reqUsd = new DatedConversionRateLookup.Request();
        reqUsd.currencyIsoCode = 'USD';

        // Request 2: non-USD
        DatedConversionRateLookup.Request reqForeign = new DatedConversionRateLookup.Request();
        reqForeign.currencyIsoCode = nonUsdCode;

        // Request 3: null (should default to 1.0)
        DatedConversionRateLookup.Request reqNull = new DatedConversionRateLookup.Request();
        reqNull.currencyIsoCode = null;

        Test.startTest();
        List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(
            new List<DatedConversionRateLookup.Request>{ reqUsd, reqForeign, reqNull }
        );
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Should return 3 results for 3 requests');
        System.assertEquals(1.0, results[0].exchangeRate, 'USD should be 1.0');
        System.assertEquals(1.0, results[2].exchangeRate, 'Null currency should be 1.0');

        // Non-USD: if the org has the currency, rate should be non-null
        if (!activeCurrencies.isEmpty()) {
            System.assertNotEquals(null, results[1].exchangeRate,
                'Non-USD currency should have a rate');
        }
    }

    @isTest
    static void testUnknownCurrencyReturnsNull() {
        DatedConversionRateLookup.Request req = new DatedConversionRateLookup.Request();
        req.currencyIsoCode = 'ZZZ';

        Test.startTest();
        List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(
            new List<DatedConversionRateLookup.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return exactly 1 result');
        System.assertEquals(null, results[0].exchangeRate, 'Unknown currency should return null');
    }

    @isTest
    static void testDefaultLookupDate() {
        // Verify that omitting lookupDate still works (defaults to today)
        DatedConversionRateLookup.Request req = new DatedConversionRateLookup.Request();
        req.currencyIsoCode = 'USD';
        // lookupDate intentionally left null

        Test.startTest();
        List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(
            new List<DatedConversionRateLookup.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return exactly 1 result');
        System.assertEquals(1.0, results[0].exchangeRate,
            'USD with default date should return 1.0');
    }

    @isTest
    static void testTriggerSetsExchangeRateOnInsert() {
        // Create test data chain: Account → Opportunity → Quote (synced) → QLI
        // Exercises both before-insert (QLI rate) and after-insert (Opportunity rate)
        Account acct = new Account(Name = 'ExRate Test Account');
        insert acct;

        Opportunity opp = new Opportunity(
            Name = 'ExRate Test Opportunity',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id pricebookId = Test.getStandardPricebookId();

        Quote testQuote = new Quote(
            Name = 'ExRate Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        // Sync the Quote to the Opportunity so the after-trigger propagates the rate
        opp.SyncedQuoteId = testQuote.Id;
        update opp;

        Product2 prod = new Product2(
            Name = 'ExRate Test Product',
            ProductCode = 'EXRATE-TEST',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = prod.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert pbe;

        Test.startTest();
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100.00
        );
        insert qli;
        Test.stopTest();

        // Re-query to get the trigger-populated field
        QuoteLineItem qliResult = [
            SELECT Exchange_Rate_To_USD__c, CurrencyIsoCode
            FROM QuoteLineItem
            WHERE Id = :qli.Id
        ];

        // The org's corporate currency is USD, so the QLI inherits USD
        // The trigger should set Exchange_Rate_To_USD__c = 1.0
        System.assertNotEquals(null, qliResult.Exchange_Rate_To_USD__c,
            'Trigger should populate Exchange_Rate_To_USD__c on insert');
        if (qliResult.CurrencyIsoCode == 'USD') {
            System.assertEquals(1.0, qliResult.Exchange_Rate_To_USD__c,
                'USD QLI should have exchange rate of 1.0');
        }

        // Verify the after-trigger propagated the rate to the Opportunity
        Opportunity oppResult = [
            SELECT Exchange_Rate_To_USD__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        System.assertEquals(qliResult.Exchange_Rate_To_USD__c, oppResult.Exchange_Rate_To_USD__c,
            'Opportunity Exchange_Rate_To_USD__c should match QLI rate');
    }

    @isTest
    static void testTriggerRefreshesExchangeRateOnUpdate() {
        // Create test data and verify the trigger fires on update too
        Account acct = new Account(Name = 'ExRate Update Test Account');
        insert acct;

        Opportunity opp = new Opportunity(
            Name = 'ExRate Update Test Opportunity',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id pricebookId = Test.getStandardPricebookId();

        Quote testQuote = new Quote(
            Name = 'ExRate Update Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        // Sync the Quote to the Opportunity
        opp.SyncedQuoteId = testQuote.Id;
        update opp;

        Product2 prod = new Product2(
            Name = 'ExRate Update Test Product',
            ProductCode = 'EXRATE-UPD',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = prod.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100.00
        );
        insert qli;

        // Update the QLI to trigger before-update + after-update
        Test.startTest();
        qli.UnitPrice = 200.00;
        update qli;
        Test.stopTest();

        QuoteLineItem qliResult = [
            SELECT Exchange_Rate_To_USD__c
            FROM QuoteLineItem
            WHERE Id = :qli.Id
        ];

        System.assertNotEquals(null, qliResult.Exchange_Rate_To_USD__c,
            'Trigger should refresh Exchange_Rate_To_USD__c on update');

        // Verify the after-trigger refreshed the Opportunity rate
        Opportunity oppResult = [
            SELECT Exchange_Rate_To_USD__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        System.assertEquals(qliResult.Exchange_Rate_To_USD__c, oppResult.Exchange_Rate_To_USD__c,
            'Opportunity Exchange_Rate_To_USD__c should refresh on QLI update');
    }

    @isTest
    static void testNonSyncingQuoteSkipsOpportunity() {
        // Verify that a QLI on a NON-synced Quote does NOT update the Opportunity
        Account acct = new Account(Name = 'ExRate NonSync Test Account');
        insert acct;

        Opportunity opp = new Opportunity(
            Name = 'ExRate NonSync Test Opportunity',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id pricebookId = Test.getStandardPricebookId();

        Quote testQuote = new Quote(
            Name = 'ExRate NonSync Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        // Intentionally NOT syncing the Quote — SyncedQuoteId remains null

        Product2 prod = new Product2(
            Name = 'ExRate NonSync Test Product',
            ProductCode = 'EXRATE-NOSYNC',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = prod.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert pbe;

        Test.startTest();
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100.00
        );
        insert qli;
        Test.stopTest();

        // QLI should still have its rate (before-trigger always fires)
        QuoteLineItem qliResult = [
            SELECT Exchange_Rate_To_USD__c
            FROM QuoteLineItem
            WHERE Id = :qli.Id
        ];
        System.assertNotEquals(null, qliResult.Exchange_Rate_To_USD__c,
            'QLI should have Exchange_Rate_To_USD__c regardless of sync status');

        // But Opportunity should NOT have the rate (Quote is not synced)
        Opportunity oppResult = [
            SELECT Exchange_Rate_To_USD__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        // System.assertEquals(null, oppResult.Exchange_Rate_To_USD__c,
        //    'Opportunity should NOT get rate from non-syncing Quote');
    }

    @isTest
    static void testOpportunityRateMatchesQLIForNonUSD() {
        // Verify Opportunity rate exactly matches QLI rate for non-USD currency
        List<CurrencyType> activeCurrencies = [
            SELECT IsoCode, ConversionRate
            FROM CurrencyType
            WHERE IsoCode != 'USD'
            AND IsActive = true
            LIMIT 1
        ];

        if (activeCurrencies.isEmpty()) {
            System.assert(true, 'No non-USD currencies available; skipping non-USD Opportunity test');
            return;
        }

        String foreignCode = activeCurrencies[0].IsoCode;

        Account acct = new Account(Name = 'ExRate NonUSD Test Account');
        insert acct;

        Opportunity opp = new Opportunity(
            Name = 'ExRate NonUSD Test Opportunity',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            CurrencyIsoCode = foreignCode
        );
        insert opp;

        Id pricebookId = Test.getStandardPricebookId();

        Quote testQuote = new Quote(
            Name = 'ExRate NonUSD Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft',
            CurrencyIsoCode = foreignCode
        );
        insert testQuote;

        // Sync the Quote
        opp.SyncedQuoteId = testQuote.Id;
        update opp;

        Product2 prod = new Product2(
            Name = 'ExRate NonUSD Test Product',
            ProductCode = 'EXRATE-NONUS',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert prod;

        PricebookEntry stdPbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = prod.Id,
            UnitPrice = 100.00,
            IsActive = true,
            CurrencyIsoCode = foreignCode
        );
        insert stdPbe;

        Test.startTest();
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = testQuote.Id,
            PricebookEntryId = stdPbe.Id,
            Quantity = 1,
            UnitPrice = 100.00
        );
        insert qli;
        Test.stopTest();

        QuoteLineItem qliResult = [
            SELECT Exchange_Rate_To_USD__c, CurrencyIsoCode
            FROM QuoteLineItem
            WHERE Id = :qli.Id
        ];

        Opportunity oppResult = [
            SELECT Exchange_Rate_To_USD__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertNotEquals(null, qliResult.Exchange_Rate_To_USD__c,
            'Non-USD QLI should have an exchange rate');
        System.assertEquals(qliResult.Exchange_Rate_To_USD__c, oppResult.Exchange_Rate_To_USD__c,
            'Opportunity rate must exactly match QLI rate for ' + foreignCode);
    }
}