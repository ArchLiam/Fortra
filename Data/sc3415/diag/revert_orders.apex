List<Order> os = [SELECT Id, Status FROM Order WHERE AccountId='001WC00000kpGHxYAM'];
for (Order o : os) { o.Status = 'Draft'; }
Database.SaveResult[] rs = Database.update(os, false);
for (Database.SaveResult r : rs) System.debug('SC3415_REVERT success=' + r.isSuccess() + (r.isSuccess()?'':' err='+r.getErrors()));
