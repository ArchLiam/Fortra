Id acctId = '001WC00000kpGHxYAM';
List<Order> orders = [SELECT Id FROM Order WHERE AccountId = :acctId];
Set<Id> oIds = (new Map<Id, Order>(orders)).keySet();
List<OrderItem> ois = [SELECT Id FROM OrderItem WHERE OrderId IN :oIds];
Set<Id> oiIds = (new Map<Id, OrderItem>(ois)).keySet();

void rpt(String lbl, List<Database.DeleteResult> rs) {
    Integer ok = 0, bad = 0; String e = '';
    for (Database.DeleteResult r : rs) { if (r.isSuccess()) ok++; else { bad++; if (e=='') e = String.valueOf(r.getErrors()); } }
    System.debug('SC3415_CF ' + lbl + ' ok=' + ok + ' fail=' + bad + (bad>0 ? ' :: ' + e.left(160) : ''));
}

rpt('CPAR', Database.delete([SELECT Id FROM Contact_Product_Account_Relationship__c WHERE Account__c = :acctId], false));
rpt('OrderItem', Database.delete(ois, false));
rpt('OrderAction', Database.delete([SELECT Id FROM OrderAction WHERE OrderId IN :oIds], false));
rpt('Order', Database.delete(orders, false));
rpt('Contact', Database.delete([SELECT Id FROM Contact WHERE AccountId = :acctId], false));
rpt('Account', Database.delete(new List<Account>{ new Account(Id = acctId) }, false));
