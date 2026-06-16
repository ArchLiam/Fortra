// SC-3419 Test C (clear) — seed an "Assetization failed" message, then activate; V14 success path should CLEAR it.
Id oid = '801WC00000kt4GfYAI';
Order o = [SELECT Id, Status, Order_Integration_Error_Messages__c FROM Order WHERE Id=:oid];
o.Order_Integration_Error_Messages__c = 'Assetization failed: SC3419-SEED (pre-activation)';
update o;
System.debug('SC3419_C_SEEDED err='+o.Order_Integration_Error_Messages__c);
o.Status = 'Activated';
try {
    update o;
    System.debug('SC3419_C_ACTIVATED ok -> async assetize flow scheduled');
} catch (Exception e) {
    System.debug('SC3419_C_ACTIVATE_ERR '+e.getTypeName()+': '+e.getMessage());
}
