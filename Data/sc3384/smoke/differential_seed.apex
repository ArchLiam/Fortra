// Differential seed for the native TLE Reprice-All verification.
// kmG14AI -> 1000 (expect localized 934.60);  kmG24AI -> 1575 (expect localized 1471.995).
List<QuoteLineItem> ups = new List<QuoteLineItem>{
    new QuoteLineItem(Id='0QLWC000003kmG14AI', ABA_Raw_Net__c=1000),
    new QuoteLineItem(Id='0QLWC000003kmG24AI', ABA_Raw_Net__c=1575)
};
update ups;
for (QuoteLineItem q : [SELECT Id, CurrencyIsoCode, ABA_Raw_Net__c, UnitPrice, NetUnitPrice
                        FROM QuoteLineItem WHERE Id IN ('0QLWC000003kmG14AI','0QLWC000003kmG24AI') ORDER BY Id]) {
    System.debug('PRE-REPRICE ' + q.Id + ' ABA_Raw_Net__c=' + q.ABA_Raw_Net__c
        + ' UnitPrice=' + q.UnitPrice + ' Net=' + q.NetUnitPrice);
}
