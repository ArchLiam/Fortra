/**
 * @description Tests for QuoteLineItemCurrencyCorrectionHandler (SC-3384).
 * @author Claude Code
 * @date 2026-07-09
 *
 * Proves the before-insert guard re-points a mis-currencied PricebookEntry to the Quote-currency
 * sibling. Each "corrects" test inserts a QuoteLineItem whose PBE is USD onto a EUR Quote — an
 * insert that WOULD throw the native "price book entry currency code is different" error without the
 * guard — so a successful insert with the EUR PBE is itself the proof the fix ran.
 */
@isTest
private class QuoteLineItemCurrencyCorrectionTest {

    private static final String PROD_DUAL = 'PROD-DUAL';   // has both USD + EUR PBEs
    private static final String PROD_USD_ONLY = 'PROD-USDONLY'; // USD PBE only (data-gap case)

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'SC3384 Currency Acct', CurrencyIsoCode = 'EUR');
        insert acct;

        Opportunity opp = new Opportunity(
            Name = 'SC3384 Currency Opp',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            CurrencyIsoCode = 'EUR'
        );
        insert opp;

        Id stdBook = Test.getStandardPricebookId();

        Quote eurQuote = new Quote(
            Name = 'SC3384 EUR Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdBook,
            Status = 'Draft',
            CurrencyIsoCode = 'EUR'
        );
        insert eurQuote;

        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Dual Currency Product', ProductCode = PROD_DUAL, IsActive = true, Family = 'Software', QuantityUnitOfMeasure = 'Each'),
            new Product2(Name = 'USD Only Product', ProductCode = PROD_USD_ONLY, IsActive = true, Family = 'Software', QuantityUnitOfMeasure = 'Each')
        };
        insert products;

        Map<String, Id> prodByCode = new Map<String, Id>();
        Product2 p;
        Integer i;
        for (i = 0; i < products.size(); i++) {
            p = products[i];
            prodByCode.put(p.ProductCode, p.Id);
        }

        // Dual product: USD + EUR PBE in the same book. USD-only product: USD PBE only.
        List<PricebookEntry> pbes = new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = stdBook, Product2Id = prodByCode.get(PROD_DUAL),     CurrencyIsoCode = 'USD', UnitPrice = 1000, IsActive = true),
            new PricebookEntry(Pricebook2Id = stdBook, Product2Id = prodByCode.get(PROD_DUAL),     CurrencyIsoCode = 'EUR', UnitPrice = 920,  IsActive = true),
            new PricebookEntry(Pricebook2Id = stdBook, Product2Id = prodByCode.get(PROD_USD_ONLY), CurrencyIsoCode = 'USD', UnitPrice = 1000, IsActive = true)
        };
        insert pbes;
    }

    private static Quote eurQuote() {
        return [SELECT Id, CurrencyIsoCode FROM Quote WHERE Name = 'SC3384 EUR Quote' LIMIT 1];
    }

    private static PricebookEntry pbeFor(String productCode, String currencyIso) {
        return [
            SELECT Id, Product2Id, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Product2.ProductCode = :productCode AND CurrencyIsoCode = :currencyIso
            LIMIT 1
        ];
    }

    @isTest
    static void correctsUsdPbeToEurOnInsert() {
        Quote q = eurQuote();
        PricebookEntry usdPbe = pbeFor(PROD_DUAL, 'USD');
        PricebookEntry eurPbe = pbeFor(PROD_DUAL, 'EUR');

        // A USD PBE on a EUR quote — without the guard this insert throws the native currency error.
        QuoteLineItem line = new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = usdPbe.Product2Id,
            PricebookEntryId = usdPbe.Id,
            Quantity = 5,
            UnitPrice = 920
        );

        Test.startTest();
        insert line;
        Test.stopTest();

        QuoteLineItem saved = [SELECT Id, PricebookEntryId, CurrencyIsoCode FROM QuoteLineItem WHERE Id = :line.Id];
        System.assertEquals(eurPbe.Id, saved.PricebookEntryId, 'PBE should be re-pointed to the EUR sibling');
        System.assertEquals('EUR', saved.CurrencyIsoCode, 'Line should be EUR (inherited from the quote)');
    }

    @isTest
    static void leavesMatchingCurrencyPbeUntouched() {
        Quote q = eurQuote();
        PricebookEntry eurPbe = pbeFor(PROD_DUAL, 'EUR');

        // Happy path: PBE currency already matches the quote — the guard must be a no-op.
        QuoteLineItem line = new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = eurPbe.Product2Id,
            PricebookEntryId = eurPbe.Id,
            Quantity = 3,
            UnitPrice = 920
        );

        Test.startTest();
        insert line;
        Test.stopTest();

        QuoteLineItem saved = [SELECT Id, PricebookEntryId FROM QuoteLineItem WHERE Id = :line.Id];
        System.assertEquals(eurPbe.Id, saved.PricebookEntryId, 'Matching-currency PBE must be left untouched');
    }

    @isTest
    static void dataGapNoEurPbeSurfacesNativeError() {
        Quote q = eurQuote();
        PricebookEntry usdOnlyPbe = pbeFor(PROD_USD_ONLY, 'USD');

        // No EUR sibling exists — the guard leaves the line and the native validation must still fire.
        QuoteLineItem line = new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = usdOnlyPbe.Product2Id,
            PricebookEntryId = usdOnlyPbe.Id,
            Quantity = 1,
            UnitPrice = 1000
        );

        Boolean threw = false;
        Test.startTest();
        try {
            insert line;
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage().containsIgnoreCase('currency'),
                'Expected the native price-book-entry currency validation, got: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assert(threw, 'Insert must still fail when no matching-currency PBE exists (data gap not masked)');
    }
}
