MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
    MaintenanceOrderDecompositionService.loadWork('801WC00000knHDLYA2');
System.debug('isNewBusiness=' + work.isNewBusiness);
System.debug('orderItems=' + work.allOrderItems.size());
System.debug('tierByQliId=' + work.tierByQliId);
for (OrderItem oi : work.allOrderItems) {
    QuoteLineItem qli = work.qliById.get(oi.QuoteLineItemId);
    System.debug('OI ' + oi.Id + ' QLI=' + oi.QuoteLineItemId + ' srcLP=' + oi.Source_List_Price__c
        + ' | qli.Fortra=' + (qli!=null?qli.Fortra_Product_Type__c:'NULL')
        + ' qli.srcLP=' + (qli!=null?String.valueOf(qli.Source_List_Price__c):'NULL')
        + ' qli.net=' + (qli!=null?String.valueOf(qli.NetUnitPrice):'NULL'));
}
