// Find candidate COLA renewal lines: Renew-typed, COLA fields set
List<QuoteLineItem> qlis = [
    SELECT Id, QuoteId, Quote.Name, Quote.Quote_Type__c, Quote.Status,
           Product2.Name, Product2.Solution_Category__c, Fortra_Product_Type__c,
           SellingModelType, COLA_Uplift_Percent__c, COLACalculatedPrice__c,
           Pre_COLA_Price__c, COLA_Source__c, COLA_Solution_Category__c,
           UnitPrice, NetUnitPrice, NetTotalPrice, TotalPrice, ListPrice,
           DerivedFromId, CurrencyIsoCode, LastModifiedDate
    FROM QuoteLineItem
    WHERE COLACalculatedPrice__c != null
      AND Quote.Quote_Type__c = 'Renewal'
    ORDER BY LastModifiedDate DESC
    LIMIT 40
];
System.debug(LoggingLevel.ERROR, 'COUNT=' + qlis.size());
for (QuoteLineItem q : qlis) {
    System.debug(LoggingLevel.ERROR, 'QLI ' + q.Id
        + ' | ' + q.Product2.Name
        + ' | FPT=' + q.Fortra_Product_Type__c
        + ' | SMT=' + q.SellingModelType
        + ' | SolCat=' + q.Product2.Solution_Category__c
        + ' | COLA%=' + q.COLA_Uplift_Percent__c
        + ' | COLACalc=' + q.COLACalculatedPrice__c
        + ' | PreCOLA=' + q.Pre_COLA_Price__c
        + ' | Unit=' + q.UnitPrice
        + ' | Net=' + q.NetUnitPrice
        + ' | NetTot=' + q.NetTotalPrice
        + ' | TotPr=' + q.TotalPrice
        + ' | Src=' + q.COLA_Source__c
        + ' | Derived=' + (q.DerivedFromId!=null)
        + ' | Q=' + q.QuoteId);
}
