Order o = [SELECT Id, Status FROM Order WHERE Id='801WC00000kswTSYAY'];
o.Status='Activated';
try { update o; System.debug('SC3419_RECOVERY_ACTIVATED ok -> async V14 assetize flow scheduled'); }
catch(Exception e){ System.debug('SC3419_RECOVERY_ACTIVATE_ERR '+e.getTypeName()+': '+e.getMessage()); }
