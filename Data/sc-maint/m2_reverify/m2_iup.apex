List<QuoteLineItem> qlis = [
  SELECT Id, Product2.Name, NetUnitPrice, UnitPrice, ListPrice, Source_List_Price__c, Base_Price__c,
         Fortra_Product_Type__c, Allow_Regional_Pricing__c
  FROM QuoteLineItem
  WHERE Product2.Fortra_Product_Type__c='New Maintenance' AND NetUnitPrice != null
  ORDER BY CreatedDate DESC LIMIT 5];
for (QuoteLineItem q : qlis)
  System.debug('IUPROW|'+q.Id+'|Net='+q.NetUnitPrice+'|Unit='+q.UnitPrice+'|List='+q.ListPrice+'|Src='+q.Source_List_Price__c);
