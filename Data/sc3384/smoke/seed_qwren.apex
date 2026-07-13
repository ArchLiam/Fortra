// Seed ABA raw-net provenance on the clean ABA lines of Q-Wren (BESEPB + VLM), simulating the proc stamp.
// Expected after Reprice All: BESEPB 824 -> 770.11 ; VLM 500 -> 467.30.
update new List<QuoteLineItem>{
    new QuoteLineItem(Id='0QLWC000003kX7J4AU', ABA_Raw_Net__c=824),   // BESEPB
    new QuoteLineItem(Id='0QLWC000003cAr34AE', ABA_Raw_Net__c=824),   // BESEPB
    new QuoteLineItem(Id='0QLWC000003cAEM4A2', ABA_Raw_Net__c=500)    // VLM
};
for (QuoteLineItem q : [SELECT Id, Product2.Name, ABA_Raw_Net__c, ListPrice, NetUnitPrice
                        FROM QuoteLineItem WHERE Id IN ('0QLWC000003kX7J4AU','0QLWC000003cAr34AE','0QLWC000003cAEM4A2')]) {
    System.debug('SEEDED ' + q.Product2.Name + ' raw=' + q.ABA_Raw_Net__c + ' list=' + q.ListPrice + ' net(now)=' + q.NetUnitPrice);
}
