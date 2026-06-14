List<QuoteLineItem> qlis = [
  SELECT Id, QuoteId, Product2.Name, Product2.Fortra_Product_Type__c,
         Base_Price__c, Source_List_Price__c, NetUnitPrice, ListPrice, UnitPrice,
         Quote.QuoteTypeText__c
  FROM QuoteLineItem
  WHERE Product2.Fortra_Product_Type__c = 'New Maintenance'
  ORDER BY CreatedDate DESC LIMIT 8];
System.debug('NEWMAINT_COUNT='+qlis.size());
Set<Id> qliIds = new Set<Id>();
for (QuoteLineItem q : qlis) {
  qliIds.add(q.Id);
  System.debug('QLIROW|'+q.Id+'|prod='+q.Product2.Name+'|QType='+q.Quote.QuoteTypeText__c
    +'|Base='+q.Base_Price__c+'|SrcList='+q.Source_List_Price__c+'|Net='+q.NetUnitPrice+'|List='+q.ListPrice+'|Unit='+q.UnitPrice);
}
if (!qliIds.isEmpty()) {
  List<QuoteLineItemAttribute> attrs = [SELECT Id, QuoteLineItemId, AttributeDefinitionId, AttributeDefinition.Code, AttributeValue FROM QuoteLineItemAttribute WHERE QuoteLineItemId IN :qliIds];
  System.debug('ATTR_COUNT='+attrs.size());
  for (QuoteLineItemAttribute a : attrs) System.debug('ATTRROW|QLI='+a.QuoteLineItemId+'|Code='+a.AttributeDefinition.Code+'|Val='+a.AttributeValue);
}
