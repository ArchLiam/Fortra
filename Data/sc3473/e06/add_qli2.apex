QuoteLineItem qli = new QuoteLineItem(
    QuoteId = '0Q0WC000003Fafl0AC',
    PricebookEntryId = '01uWC000005wrqnYAA',
    Product2Id = '01tWC00000DD2SlYAL',
    ProductSellingModelId = '0jPWC000000060b2AA',
    Quantity = 2, UnitPrice = 20500, Fortra_Product_Type__c = 'Software',
    SubscriptionTerm = 12, BillingFrequency = 'Annual',
    StartDate = Date.today(), EndDate = Date.today().addMonths(12).addDays(-1));
Database.SaveResult sr = Database.insert(qli, false);
System.debug(LoggingLevel.ERROR, 'E06-ADDQLI2 success=' + sr.isSuccess() + ' id=' + sr.getId()
  + ' errors=' + sr.getErrors());
