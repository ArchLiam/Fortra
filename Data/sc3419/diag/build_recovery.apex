// SC-3419 AC5 recovery — rebuild 00095470 as 4 Quantity-based lines on the same account (de-dup fix).
Id ACCT = '001WC00000XiZP4YAN';
Id PB   = '01sWC0000022GHFYA2';
Id BILLSHIP = '003WC00000nc6g5YAA';
Date SVC  = Date.newInstance(2026,6,11);
Date ENDD = Date.newInstance(2027,6,10);

Order o = new Order(AccountId=ACCT, EffectiveDate=SVC, Status='Draft', Pricebook2Id=PB,
    BillToContactId=BILLSHIP, ShipToContactId=BILLSHIP, CurrencyIsoCode='USD',
    Description='SC3419_RECOVERY_00095470');
insert o;
insert new AppUsageAssignment(RecordId=o.Id, AppUsageType='RevenueLifecycleManagement');
OrderAction oa = new OrderAction(OrderId=o.Id, Type='Add');
insert oa;

List<OrderItem> ois = new List<OrderItem>{
    new OrderItem(OrderId=o.Id, OrderActionId=oa.Id, Product2Id='01tWC00000DD1btYAD',
        PricebookEntryId='01uWC000005ws8MYAQ', Quantity=10, UnitPrice=355),            // PIAP OneTime
    new OrderItem(OrderId=o.Id, OrderActionId=oa.Id, Product2Id='01tWC00000DD1bsYAD',
        PricebookEntryId='01uWC000005wsbUYAQ', Quantity=10, UnitPrice=71),             // PIAMBK OneTime maintenance
    new OrderItem(OrderId=o.Id, OrderActionId=oa.Id, Product2Id='01tWC00000DD1fiYAD',
        PricebookEntryId='01uWC000005wsDwYAI', Quantity=6, UnitPrice=0,
        ServiceDate=SVC, EndDate=ENDD, PricingTermCount=1, SubscriptionTerm=1, PeriodBoundary='Anniversary'),  // SEAW TermDefined
    new OrderItem(OrderId=o.Id, OrderActionId=oa.Id, Product2Id='01tWC00000DD17PYAT',
        PricebookEntryId='01uWC000005wrxtYAA', Quantity=6, UnitPrice=2180,
        ServiceDate=SVC, EndDate=ENDD, PricingTermCount=1, SubscriptionTerm=1, PeriodBoundary='Anniversary') // CLSAAS TermDefined
};
insert ois;

OrderRepriceInvocable.Request req = new OrderRepriceInvocable.Request();
req.orderId = o.Id;
for (OrderRepriceInvocable.Result r : OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ req }))
    System.debug('SC3419_RECOVERY_REPRICE ready='+r.pricingReady+' err='+r.errorMessage);
System.debug('SC3419_RECOVERY_ORDER '+o.Id);
