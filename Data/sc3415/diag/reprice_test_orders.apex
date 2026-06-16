List<String> ids = new List<String>{ '801WC00000kpGHyYAM', '801WC00000kpGHzYAM' };
List<OrderRepriceInvocable.Request> reqs = new List<OrderRepriceInvocable.Request>();
for (String i : ids) {
    OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
    req.orderId = i;
    reqs.add(req);
}
List<OrderRepriceInvocable.Result> results = OrderRepriceInvocable.reprice(reqs);
for (OrderRepriceInvocable.Result r : results) {
    System.debug('SC3415_REPRICE success=' + r.success + ' calc=' + r.calculationStatus
        + ' valid=' + r.validationResult + ' pricingReady=' + r.pricingReady + ' err=' + r.errorMessage);
}
