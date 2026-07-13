// Directly build a context + run the prehook to isolate: does the seed logic work?
// We can't easily build a live pricing context here, so instead verify the SOQL the prehook uses.
for (QuoteLineItem q : [SELECT Id, LineNumber, NetUnitPrice, QuoteAction.Type, QuoteAction.SourceAsset.Price
                        FROM QuoteLineItem WHERE QuoteId='0Q0WC000003J4m9' AND QuoteAction.Type='Amend']) {
    System.debug('AMENDLINE '+q.LineNumber+' type='+q.QuoteAction.Type+' priorNet='+q.QuoteAction.SourceAsset.Price+' net='+q.NetUnitPrice);
}
