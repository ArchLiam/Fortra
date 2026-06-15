OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
req.orderId = '801WC00000knHDLYA2';
List<OrderRepriceInvocable.Result> results =
    OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req });
OrderRepriceInvocable.Result r = results[0];
System.debug('REPRICE_RESULT success=' + r.success
    + ' | calc=' + r.calculationStatus
    + ' | valid=' + r.validationResult
    + ' | pricingReady=' + r.pricingReady
    + ' | err=' + r.errorMessage);
