// LEAN EUR smoke — before-UPDATE FX re-stamp (where CurrencyIsoCode is populated). Savepoint→rollback.
Savepoint sp = Database.setSavepoint();
List<String> log = new List<String>();
try {
    Id pb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    PricebookEntry eurPbe = [SELECT Id, Product2Id FROM PricebookEntry
        WHERE Pricebook2Id = :pb AND CurrencyIsoCode = 'EUR' AND IsActive = true
        AND Product2Id IN (SELECT Product2Id FROM ProductSellingModelOption
                           WHERE ProductSellingModel.SellingModelType = 'OneTime') LIMIT 1];

    Account a = new Account(Name = 'SMOKE EUR'); insert a;
    Opportunity o = new Opportunity(Name = 'SMOKE EUR Opp', AccountId = a.Id,
        StageName = 'Prospecting', CloseDate = Date.today().addDays(30), CurrencyIsoCode = 'EUR'); insert o;
    Quote q = new Quote(Name = 'SMOKE EUR Q', OpportunityId = o.Id, Pricebook2Id = pb,
        CurrencyIsoCode = 'EUR'); insert q;

    QuoteLineItem line = new QuoteLineItem(QuoteId = q.Id, Product2Id = eurPbe.Product2Id,
        PricebookEntryId = eurPbe.Id, Quantity = 1, UnitPrice = 100); insert line;
    QuoteLineItem afterInsert = [SELECT CurrencyIsoCode, Exchange_Rate_To_USD__c FROM QuoteLineItem WHERE Id = :line.Id];
    log.add('EUR after-insert: cur=' + afterInsert.CurrencyIsoCode + ' rate=' + afterInsert.Exchange_Rate_To_USD__c);

    // Now CurrencyIsoCode is EUR — a before-UPDATE re-stamps with the EUR rate.
    update new QuoteLineItem(Id = line.Id, Quantity = 2);
    QuoteLineItem afterUpdate = [SELECT CurrencyIsoCode, Exchange_Rate_To_USD__c FROM QuoteLineItem WHERE Id = :line.Id];

    DatedConversionRateLookup.Request rq = new DatedConversionRateLookup.Request(); rq.currencyIsoCode = 'EUR';
    Decimal expectedEur = DatedConversionRateLookup.getExchangeRates(
        new List<DatedConversionRateLookup.Request>{ rq })[0].exchangeRate;

    log.add('EUR after-update: cur=' + afterUpdate.CurrencyIsoCode + ' rate=' + afterUpdate.Exchange_Rate_To_USD__c
        + ' lookup=' + expectedEur + ' '
        + (afterUpdate.Exchange_Rate_To_USD__c == expectedEur && expectedEur != null ? 'PASS' : 'FAIL'));
} catch (Exception e) {
    log.add('EXCEPTION ' + e.getTypeName() + ': ' + e.getMessage());
} finally {
    Database.rollback(sp);
}
for (String s : log) System.debug('SMOKE| ' + s);
