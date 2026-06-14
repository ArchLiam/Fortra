List<Id> ids = new List<Id>{'801WC00000kcXn6YAE','801WC00000khLgEYAU'};
for (Id oid : ids) {
    OrderSubmissionValidator.ValidationRequest req = new OrderSubmissionValidator.ValidationRequest();
    req.orderId = oid;
    List<OrderSubmissionValidator.ValidationResult> r =
        OrderSubmissionValidator.validate(new List<OrderSubmissionValidator.ValidationRequest>{req});
    System.debug('ORDER ' + oid + ' hasErrors=' + r[0].hasErrors + ' count=' + r[0].errorCount);
    for (String m : r[0].errorMessages) {
        System.debug('   ' + m.replaceAll('<[^>]+>','').replace('• ',''));
    }
}
