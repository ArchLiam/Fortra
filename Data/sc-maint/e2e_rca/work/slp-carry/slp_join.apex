// Compare every QLI-linked maintenance OrderItem.Source_List_Price__c to its source QLI.Source_List_Price__c
List<OrderItem> ois = [
    SELECT Id, OrderId, Order.OrderNumber, QuoteLineItemId, Source_List_Price__c, Base_Price__c, Fortra_Product_Type__c,
           Product2.ProductCode
    FROM OrderItem
    WHERE QuoteLineItemId != null AND Source_List_Price__c != null
    ORDER BY CreatedDate DESC
];
Set<Id> qliIds = new Set<Id>();
for (OrderItem oi : ois) qliIds.add(oi.QuoteLineItemId);
Map<Id, QuoteLineItem> qliMap = new Map<Id, QuoteLineItem>([
    SELECT Id, Source_List_Price__c FROM QuoteLineItem WHERE Id IN :qliIds
]);
Integer total=0, match=0, mismatch=0, qliNull=0;
List<String> mism = new List<String>();
for (OrderItem oi : ois) {
    total++;
    QuoteLineItem q = qliMap.get(oi.QuoteLineItemId);
    if (q == null) continue;
    if (q.Source_List_Price__c == null) { qliNull++; continue; }
    if (q.Source_List_Price__c == oi.Source_List_Price__c) match++;
    else { mismatch++; mism.add(oi.Id + ' OI='+oi.Source_List_Price__c+' QLI='+q.Source_List_Price__c+' ('+oi.Order.OrderNumber+')'); }
}
// also: carry-forward MISSES = QLI has SLP but OI null
Integer misses = [SELECT COUNT() FROM OrderItem oi WHERE QuoteLineItemId != null AND Source_List_Price__c = null
                  AND QuoteLineItemId IN (SELECT Id FROM QuoteLineItem WHERE Source_List_Price__c != null)];
System.debug('SLP-CARRY total='+total+' MATCH='+match+' MISMATCH='+mismatch+' QLInull='+qliNull);
System.debug('CARRY-FORWARD MISSES (QLI has SLP, OI null)='+misses);
for (String s : mism) System.debug('MISMATCH: '+s);
// distinct SLP values
Map<Decimal,Integer> dist = new Map<Decimal,Integer>();
for (OrderItem oi : ois) { Decimal v=oi.Source_List_Price__c; dist.put(v, dist.containsKey(v)? dist.get(v)+1 : 1); }
System.debug('SLP value distribution: '+dist);
