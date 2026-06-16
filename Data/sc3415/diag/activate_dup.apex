// Activate ONLY the duplicate-product order (the fault-path test).
Order o = [SELECT Id, Status FROM Order WHERE Id = '801WC00000kpGHyYAM'];
o.Status = 'Activated';
try {
    update o;
    System.debug('SC3415_DUP_ACTIVATED');
} catch (Exception e) {
    System.debug('SC3415_DUP_ACTIVATE_ERR ' + e.getMessage());
}
