// SC-3419 Test N (no-clobber) — seed a NON-assetization (Workday) error, then activate;
// V14 success path must NOT clear it (StartsWith "Assetization failed" gate fails -> default "No" path ends).
Id oid = '801WC00000kt4GgYAI';
OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
req.orderId = oid;
Boolean ready = false;
for (OrderRepriceInvocable.Result r : OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req })) {
    ready = r.pricingReady;
    System.debug('SC3419_N_REPRICE ready='+r.pricingReady+' err='+r.errorMessage);
}
Order o = [SELECT Id, Status, Order_Integration_Error_Messages__c FROM Order WHERE Id=:oid];
o.Order_Integration_Error_Messages__c = 'Workday: SC3419-WD-ERR (pre-existing integration error)';
update o;
System.debug('SC3419_N_SEEDED err='+o.Order_Integration_Error_Messages__c);
if (ready) {
    o.Status = 'Activated';
    try { update o; System.debug('SC3419_N_ACTIVATED ok -> async assetize flow scheduled'); }
    catch (Exception e) { System.debug('SC3419_N_ACTIVATE_ERR '+e.getTypeName()+': '+e.getMessage()); }
} else {
    System.debug('SC3419_N_NOT_READY - skip activate');
}
