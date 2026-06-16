// SC-3415 diagnostic: invoke createOrUpdateAssetFromOrder on 00095470 (801WC00000kYmw8YAC)
// SAFE: everything is rolled back at the end — no persistence. Pure mechanism probe.
Savepoint sp = Database.setSavepoint();
Integer q0 = Limits.getQueries(), d0 = Limits.getDmlStatements();
String outcome;
try {
    Invocable.Action a = Invocable.Action.createStandardAction('createOrUpdateAssetFromOrder');
    a.setInvocationParameter('orderId', '801WC00000kYmw8YAC');
    List<Invocable.Action.Result> rs = a.invoke();
    Integer ok = 0, bad = 0; String errs = '';
    for (Invocable.Action.Result r : rs) {
        if (r.isSuccess()) { ok++; }
        else { bad++; errs += String.valueOf(r.getErrors()) + ' || '; }
    }
    outcome = 'INVOKED results=' + rs.size() + ' success=' + ok + ' fail=' + bad + ' errs=' + errs;
} catch (Exception e) {
    outcome = 'EXCEPTION ' + e.getTypeName() + ': ' + e.getMessage();
}
Integer aas = [SELECT COUNT() FROM AssetActionSource WHERE ReferenceEntityItemId IN (SELECT Id FROM OrderItem WHERE OrderId='801WC00000kYmw8YAC')];
System.debug('=== SC3415 ASSETIZE DIAG ===');
System.debug(outcome);
System.debug('SOQL by action ~ ' + (Limits.getQueries()-q0) + '  DML stmts ~ ' + (Limits.getDmlStatements()-d0));
System.debug('SOQL total ' + Limits.getQueries() + '/' + Limits.getLimitQueries() + '  CPU ' + Limits.getCpuTime() + '/' + Limits.getLimitCpuTime());
System.debug('AssetActionSource for order (pre-rollback) = ' + aas);
Database.rollback(sp);
System.debug('ROLLED BACK — no persistence');
