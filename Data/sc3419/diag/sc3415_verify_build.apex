// SC-3415 PARENT verification E2E — normal TermDefined order, PricingTermCount LEFT NULL (rep can't type it),
// incl. a FUTURE-dated line, on a fresh account. Tests AC1 (activates w/o "required" error, w/o typing PTC) + AC2 (assets incl future-dated).
Account a = new Account(Name='SC3415_VERIFY 2026-06-16', CurrencyIsoCode='USD');
insert a;
Contact c = new Contact(FirstName='SC3415', LastName='Verify', AccountId=a.Id, Email='sc3415verify@example.com');
insert c;
Id PB='01sWC0000022GHFYA2';
Date T   = Date.newInstance(2026,6,16);
Date END1= T.addYears(1).addDays(-1);
Date FUT = T.addDays(60);
Date ENDF= FUT.addYears(1).addDays(-1);

Order o=new Order(AccountId=a.Id, EffectiveDate=T, Status='Draft', Pricebook2Id=PB,
  BillToContactId=c.Id, ShipToContactId=c.Id, CurrencyIsoCode='USD', Description='SC3415_VERIFY PTC-null E2E');
insert o;
insert new AppUsageAssignment(RecordId=o.Id, AppUsageType='RevenueLifecycleManagement');
OrderAction oa=new OrderAction(OrderId=o.Id, Type='Add');
insert oa;

// PricingTermCount intentionally NOT set (rep can't type it). EndDate + SubscriptionTerm set (rep can).
List<OrderItem> ois = new List<OrderItem>{
  new OrderItem(OrderId=o.Id,OrderActionId=oa.Id,Product2Id='01tWC00000DD1fiYAD',PricebookEntryId='01uWC000005wsDwYAI',Quantity=2,UnitPrice=0,   ServiceDate=T,  EndDate=END1,SubscriptionTerm=1,PeriodBoundary='Anniversary'), // SEAW present
  new OrderItem(OrderId=o.Id,OrderActionId=oa.Id,Product2Id='01tWC00000DD17PYAT',PricebookEntryId='01uWC000005wrxtYAA',Quantity=2,UnitPrice=2180,ServiceDate=T,  EndDate=END1,SubscriptionTerm=1,PeriodBoundary='Anniversary'), // CLSAAS present
  new OrderItem(OrderId=o.Id,OrderActionId=oa.Id,Product2Id='01tWC00000DD1fiYAD',PricebookEntryId='01uWC000005wsDwYAI',Quantity=1,UnitPrice=0,   ServiceDate=FUT,EndDate=ENDF,SubscriptionTerm=1,PeriodBoundary='Anniversary')  // SEAW FUTURE-dated
};
insert ois;

// Did the RecordBeforeSave backstop fill PTC on insert (without the rep typing it)?
for(OrderItem oi : [SELECT Product2.ProductCode, ServiceDate, EndDate, PricingTermCount, SubscriptionTerm FROM OrderItem WHERE OrderId=:o.Id ORDER BY ServiceDate])
  System.debug('SC3415V_AFTERINSERT '+oi.Product2.ProductCode+' svc='+oi.ServiceDate+' end='+oi.EndDate+' PTC='+oi.PricingTermCount+' subterm='+oi.SubscriptionTerm);

OrderRepriceInvocable.Request req=new OrderRepriceInvocable.Request(); req.orderId=o.Id;
for(OrderRepriceInvocable.Result r:OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{req}))
  System.debug('SC3415V_REPRICE ready='+r.pricingReady+' err='+r.errorMessage);
System.debug('SC3415V_ORDER '+o.Id+' ACCT '+a.Id);
