// SC-3384 smoke: seed ABA_Raw_Net__c = raw USD (simulating the proc provenance stamp) on
// the clean EUR AAMP lines of quote 0Q0WC000003FcrF0AS.
List<QuoteLineItem> qlis = [
    SELECT Id, CurrencyIsoCode, Base_Price__c, UnitPrice, NetUnitPrice, ABA_Raw_Net__c
    FROM QuoteLineItem
    WHERE Id IN ('0QLWC000003kmG14AI','0QLWC000003kmG24AI')
];
for (QuoteLineItem q : qlis) {
    q.ABA_Raw_Net__c = q.Base_Price__c;   // 1575 raw USD
}
update qlis;
for (QuoteLineItem q : [SELECT Id, CurrencyIsoCode, Base_Price__c, UnitPrice, NetUnitPrice, ABA_Raw_Net__c
                        FROM QuoteLineItem WHERE Id IN ('0QLWC000003kmG14AI','0QLWC000003kmG24AI')]) {
    System.debug('SEEDED ' + q.Id + ' cur=' + q.CurrencyIsoCode + ' ABA_Raw_Net__c=' + q.ABA_Raw_Net__c
        + ' UnitPrice=' + q.UnitPrice + ' Net=' + q.NetUnitPrice);
}
