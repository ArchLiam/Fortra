// Compare the two lines: iXUo (failed to price) vs khwH (priced clean)
for (Id qliId : new List<Id>{'0QLWC000003iXUo4AM','0QLWC000003khwH4AQ'}) {
    QuoteLineItem q = [SELECT Id, Product2Id, Product2.Name, PricebookEntryId, ListPrice, UnitPrice,
                       NetUnitPrice, Quantity, CurrencyIsoCode FROM QuoteLineItem WHERE Id=:qliId];
    System.debug(LoggingLevel.ERROR, 'QLI ' + q.Id + ' prod=' + q.Product2.Name
        + ' PBEId=' + q.PricebookEntryId + ' List=' + q.ListPrice + ' Unit=' + q.UnitPrice
        + ' Net=' + q.NetUnitPrice + ' Curr=' + q.CurrencyIsoCode);
    // is there a live PBE for this product?
    List<PricebookEntry> pbes = [SELECT Id, UnitPrice, IsActive, Pricebook2.Name, Pricebook2.IsActive, CurrencyIsoCode
        FROM PricebookEntry WHERE Product2Id=:q.Product2Id AND CurrencyIsoCode=:q.CurrencyIsoCode];
    System.debug(LoggingLevel.ERROR, '  PBE_COUNT=' + pbes.size());
    for (PricebookEntry p : pbes) {
        System.debug(LoggingLevel.ERROR, '   PBE ' + p.Id + ' price=' + p.UnitPrice + ' active=' + p.IsActive
            + ' pb=' + p.Pricebook2.Name + ' pbActive=' + p.Pricebook2.IsActive + ' curr=' + p.CurrencyIsoCode);
    }
}
