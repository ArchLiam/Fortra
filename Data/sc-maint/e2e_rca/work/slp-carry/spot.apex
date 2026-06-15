// Spot the non-355 carry-forward pairs to confirm per-record fidelity across the value range
List<OrderItem> ois = [
  SELECT Id, Order.OrderNumber, QuoteLineItemId, QuoteLineItem.Source_List_Price__c, Source_List_Price__c,
         Product2.ProductCode, Fortra_Product_Type__c, CreatedDate
  FROM OrderItem
  WHERE QuoteLineItemId != null AND Source_List_Price__c != null
    AND Source_List_Price__c IN (33, 325, 2008, 34750, 275000)
  ORDER BY Source_List_Price__c
];
for (OrderItem oi : ois) {
  System.debug('OI '+oi.Id+' ord='+oi.Order.OrderNumber+' code='+oi.Product2.ProductCode
    +' type='+oi.Fortra_Product_Type__c+' OI.SLP='+oi.Source_List_Price__c
    +' QLI.SLP='+oi.QuoteLineItem.Source_List_Price__c+' created='+oi.CreatedDate);
}
