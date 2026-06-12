RevSignaling.TransactionRequest req = new RevSignaling.TransactionRequest();
System.debug('DIAGREV created TransactionRequest. ctxInstanceId=' + req.ctxInstanceId);
req.ctxInstanceId = 'someCtx';
System.debug('DIAGREV set ctxInstanceId=' + req.ctxInstanceId);

PartnerNetPricePosthook hook = new PartnerNetPricePosthook();
// Test blank-ctx skip path (set blank)
RevSignaling.TransactionRequest blankReq = new RevSignaling.TransactionRequest();
RevSignaling.TransactionResponse resp = hook.execute(blankReq);
System.debug('DIAGREV blank-ctx response message=' + resp.message + ' status=' + resp.status);
