// SC-3415 E2E fault scenario: order with 6 lines of the SAME TermDefined subscription product (SEAW),
// reproducing 00095470's duplicate-subscription-line condition. Throwaway; cleaned up after.
Account a = new Account(Name = 'SC3415 E2E Fault DELETE');
insert a;
Contact c = new Contact(FirstName = 'SC3415', LastName = 'E2E', AccountId = a.Id, Email = 'sc3415e2e@example.invalid');
insert c;
Id pbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Id = '01uWC000004dTAUYA2']; // HRM-HRM-RSL-SEAW (TermDefined)

Order o = new Order(AccountId = a.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = pbId,
    BillToContactId = c.Id, ShipToContactId = c.Id, Description = 'SC3415E2E_FAULT');
insert o;
insert new AppUsageAssignment(RecordId = o.Id, AppUsageType = 'RevenueLifecycleManagement');
OrderAction oa = new OrderAction(OrderId = o.Id, Type = 'Add');
insert oa;

Date sd = Date.today();
Date ed = sd.addYears(1).addDays(-1);
List<OrderItem> ois = new List<OrderItem>();
for (Integer i = 0; i < 6; i++) {
    ois.add(new OrderItem(OrderId = o.Id, OrderActionId = oa.Id, Product2Id = pbe.Product2Id, PricebookEntryId = pbe.Id,
        Quantity = 1, UnitPrice = pbe.UnitPrice, ServiceDate = sd, EndDate = ed, PricingTermCount = 1,
        SubscriptionTerm = 1, PeriodBoundary = 'Anniversary'));
}
insert ois;

OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
req.orderId = o.Id;
for (OrderRepriceInvocable.Result r : OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req })) {
    System.debug('SC3415E2E_REPRICE ready=' + r.pricingReady + ' err=' + r.errorMessage);
}
System.debug('SC3415E2E_FAULT_ORDER ' + o.Id + ' acct=' + a.Id);
