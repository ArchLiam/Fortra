// READ-ONLY PROBE: attempt Status=Activated inside a savepoint, capture ALL errors, then ROLL BACK.
// No net data change is committed.
Id orderId = '801WC00000knHDLYA2';
Savepoint sp = Database.setSavepoint();
Boolean rolledBack = false;
try {
    Order o = new Order(Id = orderId, Status = 'Activated');
    Database.SaveResult sr = Database.update(o, false); // allOrNone=false -> collect all errors
    if (sr.isSuccess()) {
        System.debug('PROBE_RESULT: UPDATE SUCCEEDED (no blockers). Rolling back.');
    } else {
        System.debug('PROBE_RESULT: UPDATE FAILED with ' + sr.getErrors().size() + ' error(s):');
        Integer i = 0;
        for (Database.Error e : sr.getErrors()) {
            i++;
            System.debug('PROBE_ERR[' + i + '] statusCode=' + e.getStatusCode()
                + ' | fields=' + e.getFields()
                + ' | message=' + e.getMessage());
        }
    }
} catch (Exception ex) {
    System.debug('PROBE_EXCEPTION: ' + ex.getTypeName() + ' :: ' + ex.getMessage());
} finally {
    Database.rollback(sp);
    rolledBack = true;
    System.debug('PROBE_ROLLBACK_DONE: ' + rolledBack);
}
