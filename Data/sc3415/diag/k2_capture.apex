// Keystone-2 sync capture: invoke createOrUpdateAssetFromOrder on 00095470, name the contended asset, ROLL BACK.
Map<Id,Asset> before = new Map<Id,Asset>([SELECT Id, Name, Product2.ProductCode, Status, SystemModstamp
  FROM Asset WHERE AccountId='001WC00000XiZP4YAN'
  AND Product2Id IN ('01tWC00000DD1bsYAD','01tWC00000DD1btYAD','01tWC00000DD1fiYAD','01tWC00000DD17PYAT')]);
for (Asset a : before.values()) System.debug('K2_PREASSET '+a.Id+' '+a.Product2.ProductCode+' status='+a.Status+' modstamp='+a.SystemModstamp);
System.debug('K2_PREASSET_COUNT '+before.size());

Savepoint sp = Database.setSavepoint();
String outcome;
try {
    Invocable.Action act = Invocable.Action.createStandardAction('createOrUpdateAssetFromOrder');
    act.setInvocationParameter('orderId','801WC00000kYmw8YAC');
    Integer ok=0, bad=0; String errs='';
    for (Invocable.Action.Result r : act.invoke()) {
        if (r.isSuccess()) ok++; else { bad++; errs += String.valueOf(r.getErrors())+' || '; }
    }
    outcome = 'ok='+ok+' bad='+bad+' errs='+errs;
} catch (Exception e) {
    outcome = 'EX '+e.getTypeName()+': '+e.getMessage();
}
// did any asset's modstamp change (the contended one) before rollback?
for (Asset a : [SELECT Id, Product2.ProductCode, SystemModstamp FROM Asset WHERE Id IN :before.keySet()]) {
    if (a.SystemModstamp != before.get(a.Id).SystemModstamp)
        System.debug('K2_CHANGED_ASSET '+a.Id+' '+a.Product2.ProductCode+' newmodstamp='+a.SystemModstamp);
}
System.debug('K2_OUTCOME '+outcome);
Database.rollback(sp);
System.debug('K2_ROLLED_BACK');
