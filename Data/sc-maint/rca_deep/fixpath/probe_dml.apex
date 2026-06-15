// RLM Quote-DML lock probe — savepoint + rollback (NOTHING persists)
Savepoint sp = Database.setSavepoint();
String r = '';
try {
    QuoteAction qa = new QuoteAction(QuoteId='0Q0WC0000038aXd0AI', Type='Renew', SourceAssetId='02iWC000008DmS1YAK');
    insert qa;
    r += 'QuoteAction.INSERT=OK(id='+qa.Id+') ';
    try {
        update new QuoteLineItem(Id='0QLWC000003e2Sn4AI', QuoteActionId=qa.Id);
        r += '| QLI.QuoteActionId.UPDATE=OK';
    } catch (Exception e2) {
        r += '| QLI.UPDATE=BLOCKED :: '+e2.getTypeName()+' :: '+e2.getMessage();
    }
} catch (Exception e1) {
    r += 'QuoteAction.INSERT=BLOCKED :: '+e1.getTypeName()+' :: '+e1.getMessage();
}
Database.rollback(sp);
System.debug('PROBE-RESULT >>> ' + r);
