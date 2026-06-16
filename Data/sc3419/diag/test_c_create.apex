// SC-3419 Test C — build two throwaway 1-line PIAP orders to runtime-prove V14 success-path AC4.
// Order C (clear): will be seeded "Assetization failed: ..."  -> expect V14 to CLEAR on success.
// Order N (no-clobber): will be seeded "Workday: ..."         -> expect V14 to LEAVE it on success.
Id acctId = '001WC00000kpGHxYAM';
Id contactId = [SELECT Id FROM Contact WHERE AccountId = :acctId LIMIT 1].Id;
Id pbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Id = '01uWC000004dT3RYAU'];

List<Order> orders = new List<Order>();
for (String tag : new List<String>{'SC3419TEST_CLEAR','SC3419TEST_NOCLOBBER'}) {
    orders.add(new Order(AccountId = acctId, EffectiveDate = Date.today(), Status = 'Draft',
        Pricebook2Id = pbId, BillToContactId = contactId, ShipToContactId = contactId, Description = tag));
}
insert orders;
for (Order o : orders) {
    insert new AppUsageAssignment(RecordId = o.Id, AppUsageType = 'RevenueLifecycleManagement');
    OrderAction oa = new OrderAction(OrderId = o.Id, Type = 'Add');
    insert oa;
    insert new OrderItem(OrderId = o.Id, OrderActionId = oa.Id, Product2Id = pbe.Product2Id,
        PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = pbe.UnitPrice, ServiceDate = Date.today());
    OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
    req.orderId = o.Id;
    for (OrderRepriceInvocable.Result r : OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req }))
        System.debug('SC3419_C_REPRICE '+o.Description+' '+o.Id+' ready='+r.pricingReady+' err='+r.errorMessage);
}
