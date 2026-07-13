// SMOKE TEST — QuoteLineItem trigger merge (SC3346). Real UAT catalog data, savepoint→rollback (zero residue).
Savepoint sp = Database.setSavepoint();
List<String> log = new List<String>();
Id HW_ID = 'a0nWC000001R0eTYAS';
try {
    Id pb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    PricebookEntry usdPbe = [SELECT Id, Product2Id FROM PricebookEntry
        WHERE Pricebook2Id = :pb AND CurrencyIsoCode = 'USD' AND IsActive = true AND Product2Id IN (SELECT Product2Id FROM ProductSellingModelOption WHERE ProductSellingModel.SellingModelType = 'OneTime') LIMIT 1];
    PricebookEntry eurPbe = [SELECT Id, Product2Id FROM PricebookEntry
        WHERE Pricebook2Id = :pb AND CurrencyIsoCode = 'EUR' AND IsActive = true AND Product2Id IN (SELECT Product2Id FROM ProductSellingModelOption WHERE ProductSellingModel.SellingModelType = 'OneTime') LIMIT 1];

    Account a = new Account(Name = 'SMOKE SC3346 QLI merge'); insert a;

    // ===================== USD opp/quote: hardware linking + FX(USD) + re-link + propagation =====================
    Opportunity usdOpp = new Opportunity(Name = 'SMOKE USD Opp', AccountId = a.Id,
        StageName = 'Prospecting', CloseDate = Date.today().addDays(30)); insert usdOpp;
    Quote usdQ = new Quote(Name = 'SMOKE USD Quote', OpportunityId = usdOpp.Id, Pricebook2Id = pb); insert usdQ;
    QuoteLineGroup grp = new QuoteLineGroup(Name = 'SMOKE HW Group', QuoteId = usdQ.Id,
        Hardware__c = HW_ID, Hardware_Group_Type__c = true); insert grp;

    // T1/T2: bulk 20 USD lines, first 10 in the hardware group
    List<QuoteLineItem> usdLines = new List<QuoteLineItem>();
    for (Integer i = 0; i < 20; i++) {
        usdLines.add(new QuoteLineItem(QuoteId = usdQ.Id, Product2Id = usdPbe.Product2Id,
            PricebookEntryId = usdPbe.Id, Quantity = 1, UnitPrice = 100,
            QuoteLineGroupId = (i < 10 ? grp.Id : null)));
    }
    insert usdLines;
    Integer rate1 = 0, hwSet = 0, hwNull = 0;
    for (QuoteLineItem q : [SELECT Exchange_Rate_To_USD__c, Hardware__c, QuoteLineGroupId
                            FROM QuoteLineItem WHERE Id IN :usdLines]) {
        if (q.Exchange_Rate_To_USD__c == 1.0) rate1++;
        if (q.QuoteLineGroupId != null && q.Hardware__c == HW_ID) hwSet++;
        if (q.QuoteLineGroupId == null && q.Hardware__c == null) hwNull++;
    }
    log.add('T1 FX-stamp USD=1.0 (bulk 20): ' + rate1 + '/20 ' + (rate1 == 20 ? 'PASS' : 'FAIL'));
    log.add('T2 hardware linked (grouped 10): ' + hwSet + '/10 ' + (hwSet == 10 ? 'PASS' : 'FAIL'));
    log.add('T2b hardware null (ungrouped 10): ' + hwNull + '/10 ' + (hwNull == 10 ? 'PASS' : 'FAIL'));

    // T3: before-update re-link — move an ungrouped line into the hardware group
    QuoteLineItem mover = [SELECT Id FROM QuoteLineItem WHERE Id IN :usdLines AND QuoteLineGroupId = null LIMIT 1];
    mover.QuoteLineGroupId = grp.Id; update mover;
    QuoteLineItem moved = [SELECT Hardware__c FROM QuoteLineItem WHERE Id = :mover.Id];
    log.add('T3 before-update re-link: ' + (moved.Hardware__c == HW_ID ? 'PASS' : 'FAIL'));

    // T5-USD: propagation to synced opp (USD => 1.0)
    update new Opportunity(Id = usdOpp.Id, SyncedQuoteId = usdQ.Id);
    insert new QuoteLineItem(QuoteId = usdQ.Id, Product2Id = usdPbe.Product2Id,
        PricebookEntryId = usdPbe.Id, Quantity = 1, UnitPrice = 50);
    Opportunity usdOppAfter = [SELECT Exchange_Rate_To_USD__c FROM Opportunity WHERE Id = :usdOpp.Id];
    log.add('T5 USD propagation to synced opp: opp.rate=' + usdOppAfter.Exchange_Rate_To_USD__c
        + ' ' + (usdOppAfter.Exchange_Rate_To_USD__c == 1.0 ? 'PASS' : 'FAIL'));

    // ===================== EUR opp/quote: FX(EUR) stamp == lookup + EUR propagation =====================
    Opportunity eurOpp = new Opportunity(Name = 'SMOKE EUR Opp', AccountId = a.Id,
        StageName = 'Prospecting', CloseDate = Date.today().addDays(30), CurrencyIsoCode = 'EUR'); insert eurOpp;
    Quote eurQ = new Quote(Name = 'SMOKE EUR Quote', OpportunityId = eurOpp.Id, Pricebook2Id = pb,
        CurrencyIsoCode = 'EUR'); insert eurQ;

    DatedConversionRateLookup.Request rq = new DatedConversionRateLookup.Request(); rq.currencyIsoCode = 'EUR';
    Decimal expectedEur = DatedConversionRateLookup.getExchangeRates(
        new List<DatedConversionRateLookup.Request>{ rq })[0].exchangeRate;

    QuoteLineItem eurLine = new QuoteLineItem(QuoteId = eurQ.Id, Product2Id = eurPbe.Product2Id,
        PricebookEntryId = eurPbe.Id, Quantity = 1, UnitPrice = 100); insert eurLine;
    QuoteLineItem eurReloaded = [SELECT Exchange_Rate_To_USD__c, CurrencyIsoCode
        FROM QuoteLineItem WHERE Id = :eurLine.Id];
    log.add('T4 FX-stamp EUR (cur=' + eurReloaded.CurrencyIsoCode + '): got='
        + eurReloaded.Exchange_Rate_To_USD__c + ' lookup=' + expectedEur + ' '
        + (eurReloaded.Exchange_Rate_To_USD__c == expectedEur && expectedEur != null ? 'PASS' : 'FAIL'));

    // T6: EUR propagation — opp rate becomes the EUR rate (distinct from USD 1.0), proving the copy
    update new Opportunity(Id = eurOpp.Id, SyncedQuoteId = eurQ.Id);
    insert new QuoteLineItem(QuoteId = eurQ.Id, Product2Id = eurPbe.Product2Id,
        PricebookEntryId = eurPbe.Id, Quantity = 1, UnitPrice = 55);
    Opportunity eurOppAfter = [SELECT Exchange_Rate_To_USD__c FROM Opportunity WHERE Id = :eurOpp.Id];
    log.add('T6 EUR propagation to synced opp: opp.rate=' + eurOppAfter.Exchange_Rate_To_USD__c
        + ' expected=' + expectedEur + ' '
        + (eurOppAfter.Exchange_Rate_To_USD__c == expectedEur ? 'PASS' : 'FAIL'));

    log.add('RESULT: all merged paths executed with NO exception');
} catch (Exception e) {
    log.add('EXCEPTION ' + e.getTypeName() + ': ' + e.getMessage());
    log.add('STACK: ' + e.getStackTraceString());
} finally {
    Database.rollback(sp);
}
for (String s : log) System.debug('SMOKE| ' + s);
