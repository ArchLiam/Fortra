String qId = '0Q0WC0000028Czm0AE';
for (QuoteLineItem q : [SELECT Product2.ProductCode, NetUnitPrice, COLACalculatedPrice__c, COLA_Uplift_Percent__c, Base_Price__c
                        FROM QuoteLineItem WHERE QuoteId=:qId AND Fortra_Product_Type__c LIKE '%Maintenance%']) {
    System.debug('TRACE| BEFORE ' + q.Product2.ProductCode + ' Net=' + q.NetUnitPrice + ' COLACalc=' + q.COLACalculatedPrice__c + ' COLA%=' + q.COLA_Uplift_Percent__c + ' Base=' + q.Base_Price__c);
}
try {
    Flow.Interview f = Flow.Interview.createInterview('Fortra_Quote_Reprice', new Map<String,Object>{'QuoteId'=>qId});
    f.start();
    System.debug('TRACE| reprice invoked OK');
} catch (Exception e) { System.debug('TRACE| INVOKE FAILED: ' + e.getMessage()); }
for (QuoteLineItem q : [SELECT Product2.ProductCode, NetUnitPrice, COLACalculatedPrice__c FROM QuoteLineItem WHERE QuoteId=:qId AND Fortra_Product_Type__c LIKE '%Maintenance%']) {
    System.debug('TRACE| AFTER  ' + q.Product2.ProductCode + ' Net=' + q.NetUnitPrice + ' COLACalc=' + q.COLACalculatedPrice__c);
}
