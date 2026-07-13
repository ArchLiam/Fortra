String qId = '0Q0WC000003IKeT0AO';
for (QuoteLineItem q : [SELECT Product2.Name, NetUnitPrice, UnitPrice, ListPrice, Base_Price__c, Source_List_Price__c, Pre_Partner_Price__c, PartnerDiscountPercent
                        FROM QuoteLineItem WHERE QuoteId = :qId ORDER BY Product2.Name]) {
    System.debug('IKET| BEFORE ' + (q.Product2!=null?q.Product2.Name:'') + ' | Net=' + q.NetUnitPrice + ' Unit=' + q.UnitPrice + ' List=' + q.ListPrice
        + ' Base=' + q.Base_Price__c + ' SrcList=' + q.Source_List_Price__c + ' PrePartner=' + q.Pre_Partner_Price__c + ' P%=' + q.PartnerDiscountPercent);
}
try {
    Flow.Interview f = Flow.Interview.createInterview('Fortra_Quote_Reprice', new Map<String,Object>{ 'QuoteId' => qId });
    f.start();
    System.debug('IKET| reprice invoked');
} catch (Exception e) { System.debug('IKET| INVOKE FAILED: ' + e.getMessage()); }
for (QuoteLineItem q : [SELECT Product2.Name, NetUnitPrice, Pre_Partner_Price__c FROM QuoteLineItem WHERE QuoteId = :qId ORDER BY Product2.Name]) {
    System.debug('IKET| AFTER  ' + (q.Product2!=null?q.Product2.Name:'') + ' | Net=' + q.NetUnitPrice + ' PrePartner=' + q.Pre_Partner_Price__c);
}
