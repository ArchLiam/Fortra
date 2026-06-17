Order o=[SELECT Id,Status FROM Order WHERE Id='801WC00000ktREuYAM'];
o.Status='Activated';
try{ update o; System.debug('SC3415V_ACTIVATED ok - no required-field error'); }
catch(Exception e){ System.debug('SC3415V_ACTIVATE_ERR '+e.getMessage()); }
