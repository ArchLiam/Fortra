Id acctId = '001WC00000kpGHxYAM';
Id contactId = [SELECT Id FROM Contact WHERE AccountId = :acctId LIMIT 1].Id;
Id pbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Id = '01uWC000004dT3RYAU'];

Order big = new Order(AccountId = acctId, EffectiveDate = Date.today(), Status = 'Draft',
    Pricebook2Id = pbId, BillToContactId = contactId, ShipToContactId = contactId, Description = 'SC3415TEST_BIG');
insert big;
insert new AppUsageAssignment(RecordId = big.Id, AppUsageType = 'RevenueLifecycleManagement');
OrderAction oa = new OrderAction(OrderId = big.Id, Type = 'Add');
insert oa;

List<OrderItem> ois = new List<OrderItem>();
for (Integer i = 0; i < 12; i++) {
    ois.add(new OrderItem(OrderId = big.Id, OrderActionId = oa.Id, Product2Id = pbe.Product2Id,
        PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = pbe.UnitPrice, ServiceDate = Date.today()));
}
insert ois;

OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
req.orderId = big.Id;
for (OrderRepriceInvocable.Result r : OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req })) {
    System.debug('SC3415_BIG_REPRICE ready=' + r.pricingReady + ' err=' + r.errorMessage);
}
System.debug('SC3415_BIG_CREATED ' + big.Id);
