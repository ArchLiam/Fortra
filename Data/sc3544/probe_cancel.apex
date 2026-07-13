try {
    Integer n = PartnerNetPricePosthook.stampAttributeListPricesForQuote('0Q0WC000002VENJ');
    System.debug('STAMP rows=' + n);
    for (QuoteLineItem l : [SELECT LineNumber,UnitPrice,NetUnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000002VENJ' ORDER BY LineNumber])
        System.debug('LINE '+l.LineNumber+' UnitPrice='+l.UnitPrice+' Net='+l.NetUnitPrice);
} catch (Exception e) {
    System.debug('STAMP FAILED: ' + e.getTypeName() + ': ' + e.getMessage());
}
