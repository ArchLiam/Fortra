// SC-3346 Phase-0 (born-net): insert the RRM Term-Based-Annual maintenance line onto the renewal quote.
// The before-insert QuoteLineItemTrigger now runs RenewalQuoteActionStamp (Fix Path B), which should mint a
// Type='Renew' QuoteAction sourcing the owned RNM asset and set QLI.QuoteActionId born-net (before COLA prices it).
// We do NOT create the QuoteAction here — the wired trigger must, to prove the born-net path works.

Id Q = '0Q0WC000003JiBh0AK';                 // Renewal Quote (Quote_Type__c='Renewal', BoKS account)
Id RRM_PBE = '01uWC000005wsbVYAQ';           // PIA-PIA-RRM-PIAM  Fortra-book  Term-Based-Annual (TermDefined)  USD
PricebookEntry pbe = [SELECT Product2Id, ProductSellingModel.SellingModelType FROM PricebookEntry WHERE Id=:RRM_PBE];

try {
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId = Q, PricebookEntryId = RRM_PBE, Product2Id = pbe.Product2Id, Quantity = 1);
    insert qli;

    QuoteLineItem chk = [
        SELECT Id, Product2.ProductCode, QuoteActionId, QuoteAction.Type,
               QuoteAction.SourceAsset.Product2.ProductCode, NetUnitPrice, UnitPrice
        FROM QuoteLineItem WHERE Id = :qli.Id];
    System.debug(LoggingLevel.ERROR, '========================================'
        + '\nSC-3346 RRM line inserted ('+pbe.ProductSellingModel.SellingModelType+')'
        + '\n  QLI Id       : ' + chk.Id
        + '\n  Product      : ' + chk.Product2.ProductCode
        + '\n  QuoteActionId: ' + chk.QuoteActionId + '   <-- born-net QA? (should be non-null)'
        + '\n  QA Type      : ' + chk.QuoteAction.Type + '   <-- should be Renew'
        + '\n  QA SourceAsst: ' + chk.QuoteAction.SourceAsset.Product2.ProductCode + '   <-- should be ...-RNM-...'
        + '\n  NetUnitPrice : ' + chk.NetUnitPrice
        + '\n  UnitPrice    : ' + chk.UnitPrice
        + '\n========================================');
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, 'FAIL ['+e.getTypeName()+' L'+e.getLineNumber()+']: '+e.getMessage());
}
