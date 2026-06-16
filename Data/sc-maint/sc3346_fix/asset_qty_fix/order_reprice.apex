OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
req.orderId = '801WC00000knHDLYA2';
List<OrderRepriceInvocable.Result> res = OrderRepriceInvocable.reprice(
    new List<OrderRepriceInvocable.Request>{ req });
System.debug('REPRICE success=' + res[0].success + ' calc=' + res[0].calculationStatus
    + ' val=' + res[0].validationResult + ' err=' + res[0].errorMessage);
