// Backfill: normalize qty=0 New-Maintenance asset-copy lines via the deployed handler.
// Per-quote try/catch so a failure on one (e.g. Joe's Accepted quote) can't block the rest.
Set<Id> quoteIds = new Set<Id>();
for (QuoteLineItem q : [
    SELECT QuoteId FROM QuoteLineItem
    WHERE Product2.Fortra_Product_Type__c = 'New Maintenance'
      AND PricebookEntry.IsDerived = true
      AND Source_List_Price__c > 0
      AND NetTotalPrice = 0
      AND Quantity = 0
]) {
    quoteIds.add(q.QuoteId);
}
System.debug('Quotes to backfill (' + quoteIds.size() + '): ' + quoteIds);

Integer ok = 0, fail = 0;
for (Id qid : quoteIds) {
    try {
        RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(new Set<Id>{ qid });
        System.debug('OK   ' + qid);
        ok++;
    } catch (Exception e) {
        System.debug('FAIL ' + qid + ' :: ' + e.getMessage());
        fail++;
    }
}
System.debug('BACKFILL SUMMARY  ok=' + ok + '  fail=' + fail);
