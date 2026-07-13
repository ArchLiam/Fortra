// Is NetUnitPrice / Subtotal / TotalPrice DML-settable on QuoteLineItem (RLM)?
QuoteLineItem q = [SELECT Id, NetUnitPrice, Subtotal, TotalPrice FROM QuoteLineItem WHERE Id='0QLWC000003kmG14AI'];
System.debug('BEFORE Net=' + q.NetUnitPrice + ' Sub=' + q.Subtotal + ' Tot=' + q.TotalPrice);
try {
    QuoteLineItem u = new QuoteLineItem(Id=q.Id, NetUnitPrice=934.60, TotalPrice=934.60);
    update u;
    System.debug('DML-OK NetUnitPrice+TotalPrice settable');
} catch (Exception e) {
    System.debug('DML-FAIL: ' + e.getMessage());
}
QuoteLineItem after = [SELECT Id, NetUnitPrice, TotalPrice FROM QuoteLineItem WHERE Id='0QLWC000003kmG14AI'];
System.debug('AFTER Net=' + after.NetUnitPrice + ' Tot=' + after.TotalPrice);
