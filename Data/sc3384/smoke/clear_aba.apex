// Clear ABA_Raw_Net__c to null on the FcrF AAMP lines -> simulate fresh, un-stamped state.
update new List<QuoteLineItem>{
    new QuoteLineItem(Id='0QLWC000003kmG14AI', ABA_Raw_Net__c=null),
    new QuoteLineItem(Id='0QLWC000003kmG24AI', ABA_Raw_Net__c=null)
};
for (QuoteLineItem q : [SELECT Id, ABA_Raw_Net__c, NetUnitPrice FROM QuoteLineItem
                        WHERE Id IN ('0QLWC000003kmG14AI','0QLWC000003kmG24AI')]) {
    System.debug('CLEARED ' + q.Id + ' ABA_Raw_Net__c=' + q.ABA_Raw_Net__c + ' net=' + q.NetUnitPrice);
}
