Account partner = new Account(Name = 'DIAG Partner ZZZ', Type = 'Partner');
insert partner;

Product2 maintProd = new Product2(
    Name = 'DIAG Maint ZZZ',
    ProductCode = 'DIAG-MAINT-ZZZ',
    IsActive = true,
    Fortra_Product_Type__c = 'New Maintenance'
);
insert maintProd;

Pricebook2 std = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
PricebookEntry pbe = new PricebookEntry(
    Pricebook2Id = std.Id,
    Product2Id = maintProd.Id,
    UnitPrice = 100,
    IsActive = true
);
insert pbe;

Account acct = new Account(Name = 'DIAG Acct ZZZ');
insert acct;

Opportunity opp = new Opportunity(
    AccountId = acct.Id,
    Name = 'DIAG Opp ZZZ',
    StageName = 'Pre-Qualified',
    CloseDate = Date.today().addDays(30)
);
insert opp;

Quote q = new Quote(
    Name = 'DIAG Quote ZZZ',
    OpportunityId = opp.Id,
    Pricebook2Id = std.Id
);
insert q;

QuoteLineItem qli = new QuoteLineItem(
    QuoteId = q.Id,
    PricebookEntryId = pbe.Id,
    Product2Id = maintProd.Id,
    Quantity = 1,
    UnitPrice = 0
);
insert qli;

QuoteLineItem reloaded = [SELECT Id, Fortra_Product_Type__c, Product2.Fortra_Product_Type__c FROM QuoteLineItem WHERE Id = :qli.Id];
System.debug('DIAG line-level Fortra_Product_Type__c = [' + reloaded.Fortra_Product_Type__c + ']');
System.debug('DIAG product-level Fortra_Product_Type__c = [' + reloaded.Product2.Fortra_Product_Type__c + ']');

Map<Id, String> m = PartnerPricingService.loadProductTypesForLines(new Set<Id>{ qli.Id });
System.debug('DIAG loadProductTypesForLines = ' + m);

// cleanup
delete qli; delete q; delete opp; delete acct; delete pbe; delete maintProd; delete partner;
