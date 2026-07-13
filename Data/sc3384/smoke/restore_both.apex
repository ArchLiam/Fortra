// Restore both AAMP lines to the real ABA override (1575). Next reprice -> both localize to 1471.995.
update new List<QuoteLineItem>{
    new QuoteLineItem(Id='0QLWC000003kmG14AI', ABA_Raw_Net__c=1575),
    new QuoteLineItem(Id='0QLWC000003kmG24AI', ABA_Raw_Net__c=1575)
};
System.debug('RESTORED both AAMP lines to ABA_Raw_Net__c=1575');
