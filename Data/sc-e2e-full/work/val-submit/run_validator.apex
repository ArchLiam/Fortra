// Read-only: run OrderSubmissionValidator against populated + unpopulated orders. No DML, no platform events.
List<String> orderIds = new List<String>{ '801WC00000kcXn6YAE', '801WC00000khLgEYAU' };
for (String oid : orderIds) {
    OrderSubmissionValidator.ValidationRequest req = new OrderSubmissionValidator.ValidationRequest();
    req.orderId = oid;
    List<OrderSubmissionValidator.ValidationResult> results =
        OrderSubmissionValidator.validate(new List<OrderSubmissionValidator.ValidationRequest>{ req });
    OrderSubmissionValidator.ValidationResult r = results[0];
    System.debug('=== ORDER ' + oid + ' ===');
    System.debug('hasErrors=' + r.hasErrors + ' errorCount=' + r.errorCount);
    if (r.errorMessages != null) {
        for (String m : r.errorMessages) {
            System.debug('  ERR: ' + m);
        }
    }
}
