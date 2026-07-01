// K-11 smoke: RenewalAssetQuantityHandler normalizes a born-qty=0 New-Maintenance asset-copy line.
// Target line 0QLWC000003d2QR4AY (Draft quote 0Q0WC0000037rFZ0AY): qty=0, StartQty=1, action=No Change,
// NetUnitPrice=71 (correct), NetTotalPrice=0 (=0*71). Run handler synchronously inside a savepoint,
// observe normalized qty + recomputed NetTotalPrice, then ROLLBACK (no permanent mutation).
Id quoteId = '0Q0WC0000037rFZ0AY';
Id lineId  = '0QLWC000003d2QR4AY';

QuoteLineItem before = [SELECT Id, Quantity, StartQuantity, EndQuantity, QuoteActionId,
    QuoteAction.Type, NetUnitPrice, NetTotalPrice FROM QuoteLineItem WHERE Id = :lineId];
System.debug(LoggingLevel.ERROR, 'K-11 BEFORE :: qty=' + before.Quantity + ' startQty=' + before.StartQuantity
    + ' action=' + before.QuoteAction.Type + ' netUnit=' + before.NetUnitPrice + ' netTotal=' + before.NetTotalPrice);

Savepoint sp = Database.setSavepoint();
try {
    RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(new Set<Id>{ quoteId });

    QuoteLineItem after = [SELECT Id, Quantity, StartQuantity, EndQuantity, QuoteActionId,
        QuoteAction.Type, NetUnitPrice, NetTotalPrice FROM QuoteLineItem WHERE Id = :lineId];
    Decimal expectedTotal = (after.Quantity == null ? 0 : after.Quantity) * (after.NetUnitPrice == null ? 0 : after.NetUnitPrice);
    System.debug(LoggingLevel.ERROR, 'K-11 AFTER  :: qty=' + after.Quantity + ' startQty=' + after.StartQuantity
        + ' action=' + after.QuoteAction.Type + ' netUnit=' + after.NetUnitPrice + ' netTotal=' + after.NetTotalPrice
        + ' expectedTotal(qty*net)=' + expectedTotal);
    System.debug(LoggingLevel.ERROR, 'K-11 RESULT :: normalizedQtyToSourceAsset=' + (after.Quantity == 1)
        + ' startQtyZeroed=' + (after.StartQuantity == 0) + ' actionFlippedNoChangeToAmend=' + (after.QuoteAction.Type == 'Amend'));
} finally {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'K-11 ROLLED BACK (record untouched)');
}
