// SC-3419 — replicate 00095470's EXACT 32-duplicate-line setup on the fresh quote account (0Q0WC000003A7D00AK / 001WC00000ktNCrYAM) and test.
Id ACCT='001WC00000ktNCrYAM';
Id PB  ='01sWC0000022GHFYA2';
Id CON ='003WC00000xUwmBYAS';
Date SVC =Date.newInstance(2026,6,11);
Date ENDD=Date.newInstance(2027,6,10);

Order o=new Order(AccountId=ACCT, EffectiveDate=SVC, Status='Draft', Pricebook2Id=PB,
  BillToContactId=CON, ShipToContactId=CON, CurrencyIsoCode='USD',
  Description='SC3419_QUOTETEST replicate 00095470 (32 dup lines) for quote 0Q0WC000003A7D00AK');
insert o;
insert new AppUsageAssignment(RecordId=o.Id, AppUsageType='RevenueLifecycleManagement');
OrderAction oa=new OrderAction(OrderId=o.Id, Type='Add');
insert oa;

List<OrderItem> ois=new List<OrderItem>();
for(Integer i=0;i<10;i++) ois.add(new OrderItem(OrderId=o.Id,OrderActionId=oa.Id,Product2Id='01tWC00000DD1btYAD',PricebookEntryId='01uWC000005ws8MYAQ',Quantity=1,UnitPrice=355));   // PIAP x10 OneTime
for(Integer i=0;i<10;i++) ois.add(new OrderItem(OrderId=o.Id,OrderActionId=oa.Id,Product2Id='01tWC00000DD1bsYAD',PricebookEntryId='01uWC000005wsbUYAQ',Quantity=1,UnitPrice=71));    // PIAMBK x10 OneTime maintenance
for(Integer i=0;i<6;i++)  ois.add(new OrderItem(OrderId=o.Id,OrderActionId=oa.Id,Product2Id='01tWC00000DD1fiYAD',PricebookEntryId='01uWC000005wsDwYAI',Quantity=1,UnitPrice=0,ServiceDate=SVC,EndDate=ENDD,PricingTermCount=1,SubscriptionTerm=1,PeriodBoundary='Anniversary')); // SEAW x6 TermDefined
for(Integer i=0;i<6;i++)  ois.add(new OrderItem(OrderId=o.Id,OrderActionId=oa.Id,Product2Id='01tWC00000DD17PYAT',PricebookEntryId='01uWC000005wrxtYAA',Quantity=1,UnitPrice=2180,ServiceDate=SVC,EndDate=ENDD,PricingTermCount=1,SubscriptionTerm=1,PeriodBoundary='Anniversary')); // CLSAAS x6 TermDefined
insert ois;
System.debug('SC3419_QT_LINES '+ois.size());

OrderRepriceInvocable.Request req=new OrderRepriceInvocable.Request();
req.orderId=o.Id;
for(OrderRepriceInvocable.Result r:OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{req}))
  System.debug('SC3419_QT_REPRICE ready='+r.pricingReady+' err='+r.errorMessage);
System.debug('SC3419_QT_ORDER '+o.Id);
