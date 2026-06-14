Order o = [SELECT Id, Description FROM Order WHERE Id='801WC00000kfVDVYA2'];
o.Description = 'ZZ_E2E_RCA_20260613 - EDITED ' + Datetime.now().format();
update o;
Order check = [SELECT Id, Description, Status FROM Order WHERE Id='801WC00000kfVDVYA2'];
System.debug('EDITED_DESC=' + check.Description);
