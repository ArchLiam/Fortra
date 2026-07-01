// Broad: any QLI with COLACalculatedPrice set
List<QuoteLineItem> qlis = [
    SELECT Id, QuoteId, Quote.Name, Quote.Quote_Type__c, Quote.Status,
           Product2.Name, Product2.Solution_Category__c, Fortra_Product_Type__c,
           SellingModelType, COLA_Uplift_Percent__c, COLACalculatedPrice__c,
           Pre_COLA_Price__c, COLA_Source__c,
           UnitPrice, NetUnitPrice, NetTotalPrice, TotalPrice, ListPrice,
           CurrencyIsoCode, LastModifiedDate
    FROM QuoteLineItem
    WHERE COLACalculatedPrice__c != null
    ORDER BY LastModifiedDate DESC
    LIMIT 30
];
System.debug(LoggingLevel.ERROR, 'COLACalc_COUNT=' + qlis.size());
for (QuoteLineItem q : qlis) {
    System.debug(LoggingLevel.ERROR, 'A ' + q.Id + ' | QT=' + q.Quote.Quote_Type__c
        + ' | ' + q.Product2.Name + ' | FPT=' + q.Fortra_Product_Type__c
        + ' | SMT=' + q.SellingModelType + ' | COLA%=' + q.COLA_Uplift_Percent__c
        + ' | Calc=' + q.COLACalculatedPrice__c + ' | Pre=' + q.Pre_COLA_Price__c
        + ' | Unit=' + q.UnitPrice + ' | Net=' + q.NetUnitPrice + ' | TotPr=' + q.TotalPrice
        + ' | Src=' + q.COLA_Source__c + ' | Q=' + q.QuoteId + ' | LM=' + q.LastModifiedDate);
}
// Also: COLA_Uplift_Percent set, derived
List<QuoteLineItem> der = [
    SELECT Id, QuoteId, Quote.Quote_Type__c, Product2.Name, Fortra_Product_Type__c,
           COLA_Uplift_Percent__c, COLACalculatedPrice__c, NetUnitPrice, UnitPrice, TotalPrice
    FROM QuoteLineItem
    WHERE COLA_Uplift_Percent__c != null AND COLA_Uplift_Percent__c > 0
    ORDER BY LastModifiedDate DESC LIMIT 15];
System.debug(LoggingLevel.ERROR, 'COLApct_COUNT=' + der.size());
for (QuoteLineItem q : der) {
    System.debug(LoggingLevel.ERROR, 'B ' + q.Id + ' | QT=' + q.Quote.Quote_Type__c
        + ' | ' + q.Product2.Name + ' | FPT=' + q.Fortra_Product_Type__c
        + ' | COLA%=' + q.COLA_Uplift_Percent__c + ' | Calc=' + q.COLACalculatedPrice__c
        + ' | Net=' + q.NetUnitPrice + ' | Unit=' + q.UnitPrice + ' | TotPr=' + q.TotalPrice);
}
