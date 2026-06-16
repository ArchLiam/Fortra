// SC-3415 V13 verification — create two throwaway test orders (deleted afterward).
// DUP = 2 lines of the same assetizable product (reproduce collision -> expect Failed stamp).
// OK  = 1 line (expect Success stamp).
Account a = new Account(Name = 'SC3415 Assetize Test DELETE');
insert a;
Id pbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Id = '01uWC000004dT3RYAU']; // PIA-PIA-NRPS-PIAP (OneTime, assetizable)

Order dup = new Order(AccountId = a.Id, EffectiveDate = Date.today(), Status = 'Draft',
                      Pricebook2Id = pbId, Description = 'SC3415TEST_DUP');
Order ok  = new Order(AccountId = a.Id, EffectiveDate = Date.today(), Status = 'Draft',
                      Pricebook2Id = pbId, Description = 'SC3415TEST_OK');
insert new List<Order>{ dup, ok };

insert new List<AppUsageAssignment>{
    new AppUsageAssignment(RecordId = dup.Id, AppUsageType = 'RevenueLifecycleManagement'),
    new AppUsageAssignment(RecordId = ok.Id,  AppUsageType = 'RevenueLifecycleManagement')
};

OrderAction oaDup = new OrderAction(OrderId = dup.Id, Type = 'Add');
OrderAction oaOk  = new OrderAction(OrderId = ok.Id,  Type = 'Add');
insert new List<OrderAction>{ oaDup, oaOk };

Date sd = Date.today();
List<OrderItem> ois = new List<OrderItem>{
    new OrderItem(OrderId = dup.Id, OrderActionId = oaDup.Id, Product2Id = pbe.Product2Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = pbe.UnitPrice, ServiceDate = sd),
    new OrderItem(OrderId = dup.Id, OrderActionId = oaDup.Id, Product2Id = pbe.Product2Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = pbe.UnitPrice, ServiceDate = sd),
    new OrderItem(OrderId = ok.Id,  OrderActionId = oaOk.Id,  Product2Id = pbe.Product2Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = pbe.UnitPrice, ServiceDate = sd)
};
insert ois;
System.debug('SC3415TEST_CREATED acct=' + a.Id + ' dup=' + dup.Id + ' ok=' + ok.Id);
