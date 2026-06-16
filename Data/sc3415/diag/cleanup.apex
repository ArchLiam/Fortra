Id acctId = '001WC00000kpGHxYAM';

List<Asset> assets   = [SELECT Id FROM Asset    WHERE AccountId = :acctId];
List<Order> orders   = [SELECT Id, Status FROM Order WHERE AccountId = :acctId];
List<Contract> ctrs  = [SELECT Id, Status FROM Contract WHERE AccountId = :acctId];
List<Contact> cons   = [SELECT Id FROM Contact  WHERE AccountId = :acctId];
List<AppUsageAssignment> aua = [SELECT Id FROM AppUsageAssignment WHERE RecordId IN (SELECT Id FROM Order WHERE AccountId = :acctId)];
System.debug('SC3415_CLEANUP before: assets=' + assets.size() + ' orders=' + orders.size()
    + ' contracts=' + ctrs.size() + ' contacts=' + cons.size() + ' aua=' + aua.size());

void tryDel(String lbl, List<SObject> rows) {
    if (rows.isEmpty()) return;
    Database.DeleteResult[] rs = Database.delete(rows, false);
    Integer ok = 0, bad = 0; String firstErr = '';
    for (Database.DeleteResult r : rs) { if (r.isSuccess()) ok++; else { bad++; if (firstErr=='') firstErr = String.valueOf(r.getErrors()); } }
    System.debug('SC3415_CLEANUP del ' + lbl + ' ok=' + ok + ' fail=' + bad + (bad>0 ? ' err=' + firstErr : ''));
}

tryDel('AppUsageAssignment', aua);
tryDel('Asset', assets);
tryDel('Contract', ctrs);
// orders must be de-activated before delete in some configs; try direct delete first
tryDel('Order', orders);
tryDel('Contact', cons);
Database.DeleteResult ar = Database.delete(new Account(Id = acctId), false);
System.debug('SC3415_CLEANUP del Account success=' + ar.isSuccess() + (ar.isSuccess() ? '' : ' err=' + ar.getErrors()));
