// SC-3419 Test B1 — re-fire 00095470 via Apex update (the SC-3415 E2E method) to drive the async V14 flow.
// Wrapped in try/catch so an orchestration failure is reported, not thrown.
Order o = [SELECT Id, Status, Order_Integration_Error_Messages__c FROM Order WHERE Id='801WC00000kYmw8YAC'];
System.debug('SC3419_B_BEFORE status='+o.Status+' err='+o.Order_Integration_Error_Messages__c);
o.Status = 'Activated';
try {
    update o;
    System.debug('SC3419_B_UPDATE_OK -> Status=Activated; AsyncAfterCommit assetize flow scheduled');
} catch (Exception e) {
    System.debug('SC3419_B_UPDATE_ERR '+e.getTypeName()+': '+e.getMessage());
}
