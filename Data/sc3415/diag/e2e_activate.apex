Order o = [SELECT Id, Status FROM Order WHERE Id = '801WC00000kpR27YAE'];
o.Status = 'Activated';
try { update o; System.debug('SC3415E2E_ACTIVATED'); }
catch (Exception e) { System.debug('SC3415E2E_ACTIVATE_ERR ' + e.getMessage()); }
