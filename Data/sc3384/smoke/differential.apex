// Prove applyCurrencyCorrection uses per-line ABA_Raw_Net__c: seed kmG14AI=1000 (artificial),
// leave kmG24AI=1575 (real). Same product, same currency -> different provenance -> different net.
QuoteLineItem a = [SELECT Id, ABA_Raw_Net__c FROM QuoteLineItem WHERE Id='0QLWC000003kmG14AI'];
a.ABA_Raw_Net__c = 1000;
update a;
System.debug('SMOKE: kmG14AI ABA_Raw_Net__c set to 1000 (expect Net 934.60 after reprice)');
