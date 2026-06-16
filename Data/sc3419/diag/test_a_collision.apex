// SC-3419 AC5 Test A — re-confirm the deterministic optimistic-lock collision on 00095470 TODAY,
// name the contended Asset, then ROLL BACK (no mutation). Run with FINEST.
String ORDER_ID = '801WC00000kYmw8YAC';
Id ACCT     = '001WC00000XiZP4YAN';
Set<Id> PRODS = new Set<Id>{'01tWC00000DD1bsYAD','01tWC00000DD1btYAD','01tWC00000DD1fiYAD','01tWC00000DD17PYAT'};

Map<Id,Asset> before = new Map<Id,Asset>([SELECT Id, Name, Product2.ProductCode, Status, Quantity, SystemModstamp
    FROM Asset WHERE AccountId=:ACCT AND Product2Id IN :PRODS]);
for (Asset a : before.values())
    System.debug('SC3419_PREASSET '+a.Id+' '+a.Product2.ProductCode+' status='+a.Status+' qty='+a.Quantity+' modstamp='+a.SystemModstamp);
System.debug('SC3419_PREASSET_COUNT '+before.size());

Savepoint sp = Database.setSavepoint();
String outcome;
try {
    Invocable.Action act = Invocable.Action.createStandardAction('createOrUpdateAssetFromOrder');
    act.setInvocationParameter('orderId', ORDER_ID);
    Integer ok=0, bad=0; String errs='';
    for (Invocable.Action.Result r : act.invoke()) {
        if (r.isSuccess()) ok++; else { bad++; errs += String.valueOf(r.getErrors())+' || '; }
    }
    outcome = 'ok='+ok+' bad='+bad+' errs='+errs;
} catch (Exception e) {
    outcome = 'EX '+e.getTypeName()+': '+e.getMessage();
}
for (Asset a : [SELECT Id, Product2.ProductCode, SystemModstamp FROM Asset WHERE Id IN :before.keySet()]) {
    if (a.SystemModstamp != before.get(a.Id).SystemModstamp)
        System.debug('SC3419_CHANGED_ASSET '+a.Id+' '+a.Product2.ProductCode+' newmodstamp='+a.SystemModstamp);
}
System.debug('SC3419_OUTCOME '+outcome);
Database.rollback(sp);
System.debug('SC3419_ROLLED_BACK');
