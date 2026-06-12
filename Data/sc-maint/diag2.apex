Product2 maintProd = new Product2(
    Name = 'DIAG Maint ZZ2', ProductCode = 'DIAG-MAINT-ZZ2',
    IsActive = true, Fortra_Product_Type__c = 'New Maintenance'
);
insert maintProd;
Pricebook2 std = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
PricebookEntry pbe = new PricebookEntry(Pricebook2Id = std.Id, Product2Id = maintProd.Id, UnitPrice = 100, IsActive = true);
insert pbe;
Account acct = new Account(Name = 'DIAG Acct ZZ2'); insert acct;
Opportunity opp = new Opportunity(AccountId = acct.Id, Name = 'DIAG Opp ZZ2', StageName = 'Pre-Qualified', CloseDate = Date.today().addDays(30)); insert opp;
Quote q = new Quote(Name = 'DIAG Quote ZZ2', OpportunityId = opp.Id, Pricebook2Id = std.Id); insert q;

// Case A: explicitly set line-level to New Maintenance
QuoteLineItem qliA = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = maintProd.Id, Quantity = 1, UnitPrice = 0, Fortra_Product_Type__c = 'New Maintenance');
insert qliA;
QuoteLineItem rA = [SELECT Fortra_Product_Type__c FROM QuoteLineItem WHERE Id = :qliA.Id];
System.debug('DIAG explicit-set line-level = [' + rA.Fortra_Product_Type__c + ']');

delete qliA; delete q; delete opp; delete acct; delete pbe; delete maintProd;
