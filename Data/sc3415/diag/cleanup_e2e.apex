// Light cleanup of the SEAW E2E throwaway account (immutable AssetActionSource will block order/account delete).
Id acctId = '001WC00000kpR26YAE';
void rpt(String lbl, List<Database.DeleteResult> rs) {
    Integer ok = 0, bad = 0; String e = '';
    for (Database.DeleteResult r : rs) { if (r.isSuccess()) ok++; else { bad++; if (e=='') e = String.valueOf(r.getErrors()); } }
    System.debug('SC3415_E2E_CLEAN ' + lbl + ' ok=' + ok + ' fail=' + bad + (bad>0 ? ' :: ' + e.left(110) : ''));
}
rpt('Asset', Database.delete([SELECT Id FROM Asset WHERE AccountId = :acctId], false));
rpt('FulfillmentAsset', Database.delete([SELECT Id FROM FulfillmentAsset WHERE AccountId = :acctId], false));
rpt('CPAR', Database.delete([SELECT Id FROM Contact_Product_Account_Relationship__c WHERE Account__c = :acctId], false));
List<Order> os = [SELECT Id, Status FROM Order WHERE AccountId = :acctId];
for (Order o : os) o.Status = 'Draft';
Database.update(os, false);
rpt('OrderAction', Database.delete([SELECT Id FROM OrderAction WHERE OrderId IN :os], false));
System.debug('SC3415_E2E_CLEAN residual: account ' + acctId + ' + draft order(s) blocked by immutable AssetActionSource');
