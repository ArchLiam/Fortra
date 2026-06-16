Order o = [SELECT Id, Status FROM Order WHERE Id = '801WC00000kp4okYAA'];
o.Status = 'Activated';
try { update o; System.debug('SC3415_BIG_ACTIVATED'); }
catch (Exception e) { System.debug('SC3415_BIG_ACTIVATE_ERR ' + e.getMessage()); }
