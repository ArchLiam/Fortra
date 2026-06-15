// Any QLI-linked OI where source QLI has SLP but OI failed to carry it (the regression signal), and recency
Integer misses = [SELECT COUNT() FROM OrderItem WHERE QuoteLineItemId != null AND Source_List_Price__c = null
                  AND QuoteLineItemId IN (SELECT Id FROM QuoteLineItem WHERE Source_List_Price__c != null)];
System.debug('TOTAL carry-forward misses org-wide = '+misses);
// most recent QLI-linked maint OI with SLP set
for (OrderItem oi : [SELECT Id, Order.OrderNumber, Source_List_Price__c, QuoteLineItem.Source_List_Price__c, CreatedDate
                     FROM OrderItem WHERE QuoteLineItemId != null AND Source_List_Price__c != null
                     ORDER BY CreatedDate DESC LIMIT 3]) {
  System.debug('RECENT OI '+oi.Id+' ord='+oi.Order.OrderNumber+' OI.SLP='+oi.Source_List_Price__c
    +' QLI.SLP='+oi.QuoteLineItem.Source_List_Price__c+' created='+oi.CreatedDate);
}
