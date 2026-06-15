Id quoteId = '0Q0WC0000038aXd0AI';
System.debug('EXP-BEFORE quoteId=' + quoteId);
for (QuoteLineItem q : [SELECT Id, Product2.ProductCode, NetUnitPrice, UnitPrice, COLACalculatedPrice__c, QuoteActionId, Fortra_Product_Type__c FROM QuoteLineItem WHERE QuoteId=:quoteId AND Fortra_Product_Type__c='Renewal Maintenance']) {
    System.debug('EXP-BEFORE line=' + q.Id + ' PC=' + q.Product2.ProductCode + ' NET=' + q.NetUnitPrice + ' UNIT=' + q.UnitPrice + ' COLACalc=' + q.COLACalculatedPrice__c + ' QA=' + q.QuoteActionId);
}
try {
    RenewalMaintenancePricingService.finalizeRenewalMaintenanceAfterPricing(quoteId);
    System.debug('EXP-FINALIZE-OK');
} catch (Exception e) {
    System.debug('EXP-FINALIZE-ERR ' + e.getTypeName() + ': ' + e.getMessage() + ' | ' + e.getStackTraceString());
}
