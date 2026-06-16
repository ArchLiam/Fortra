Id acctId = '001WC00000kpGHxYAM';
List<String> ids = new List<String>{ '801WC00000kpGHyYAM', '801WC00000kpGHzYAM' };

Contact c = new Contact(FirstName = 'SC3415', LastName = 'Test', AccountId = acctId, Email = 'sc3415test@example.invalid');
insert c;

List<Order> os = [SELECT Id FROM Order WHERE Id IN :ids];
for (Order o : os) { o.BillToContactId = c.Id; o.ShipToContactId = c.Id; }
update os;

List<OrderRepriceInvocable.Request> reqs = new List<OrderRepriceInvocable.Request>();
for (String i : ids) {
    OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
    req.orderId = i;
    reqs.add(req);
}
for (OrderRepriceInvocable.Result r : OrderRepriceInvocable.reprice(reqs)) {
    System.debug('SC3415_REPRICE success=' + r.success + ' pricingReady=' + r.pricingReady + ' err=' + r.errorMessage);
}
System.debug('SC3415_CONTACT_SET ' + c.Id);
