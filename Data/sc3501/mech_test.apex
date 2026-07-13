// Mechanism test: seed UnitPrice = prior net (SourceAsset.Price) on amend lines, then the reprice's
// AmendSeedNetUnit = IF(NetUnitPrice>0, NetUnitPrice, InputUnitPrice) should carry it to NetUnitPrice.
List<QuoteLineItem> lines = [
    SELECT Id, LineNumber, UnitPrice, NetUnitPrice, QuoteAction.SourceAsset.Price
    FROM QuoteLineItem WHERE QuoteId='0Q0WC000003J4m9' ORDER BY LineNumber];
for (QuoteLineItem l : lines) {
    Decimal prior = l.QuoteAction != null && l.QuoteAction.SourceAsset != null ? l.QuoteAction.SourceAsset.Price : null;
    System.debug('SEED '+l.LineNumber+' SourceAsset.Price='+prior+' (was UnitPrice='+l.UnitPrice+')');
    l.UnitPrice = prior;
}
update lines;
System.debug('seeded UnitPrice from SourceAsset.Price');
