Id orderId = '801WC00000knHDLYA2';
List<commerceorders.RecordWithReferenceRequest> records = new List<commerceorders.RecordWithReferenceRequest>();
records.add(new commerceorders.RecordWithReferenceRequest('refOrder',
    new commerceorders.RecordResource(Order.getSObjectType(), 'PATCH', orderId)));
Integer i = 0;
for (OrderItem oi : [SELECT Id FROM OrderItem WHERE OrderId = :orderId]) {
    records.add(new commerceorders.RecordWithReferenceRequest('refOI' + (i++),
        new commerceorders.RecordResource(OrderItem.getSObjectType(), 'PATCH', oi.Id)));
}
commerceorders.GraphRequest graph = new commerceorders.GraphRequest('SC3412_Reprice', records);
commerceorders.PlaceOrderResult r = commerceorders.PlaceOrderExecutor.execute(
    graph, commerceorders.PricingPreferenceEnum.Force,
    commerceorders.ConfigurationInputEnum.Skip, new commerceorders.ConfigurationOptionsInput());
System.debug('PlaceOrder success=' + (r != null ? r.success : null) + ' err=' + (r != null ? String.valueOf(r.responseError) : 'n/a'));
