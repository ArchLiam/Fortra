Order o=[SELECT Id,Status FROM Order WHERE Id='801WC00000ktRukYAE'];
o.Status='Activated';
try{ update o; System.debug('SC3419_QT_ACTIVATED ok -> async V14 assetize scheduled'); }
catch(Exception e){ System.debug('SC3419_QT_ACTIVATE_ERR '+e.getTypeName()+': '+e.getMessage()); }
