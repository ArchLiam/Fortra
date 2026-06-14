// READ-ONLY: run OrderSubmissionValidator.validate against test orders.
// No DML, no status change, no platform event. Mirrors flow v13 pre-submit check.
Map<String,String> orders = new Map<String,String>{
  '00095493 (populated, expect PASS)'  => '801WC00000keQrFYAU',
  '00095497 (Phone+DUNS missing)'      => '801WC00000khLgEYAU',
  '00095494 (heavily unpopulated)'     => '801WC00000kfVDVYA2'
};
for (String label : orders.keySet()) {
  String oid = orders.get(label);
  OrderSubmissionValidator.ValidationRequest req = new OrderSubmissionValidator.ValidationRequest();
  req.orderId = oid;
  List<OrderSubmissionValidator.ValidationResult> res =
     OrderSubmissionValidator.validate(new List<OrderSubmissionValidator.ValidationRequest>{req});
  OrderSubmissionValidator.ValidationResult r = res[0];
  System.debug('===== ' + label + ' =====');
  System.debug('hasErrors=' + r.hasErrors + ' errorCount=' + r.errorCount);
  if (r.errorMessages != null) {
    for (String m : r.errorMessages) System.debug('  ERR: ' + m);
  }
}
