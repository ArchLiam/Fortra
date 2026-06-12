// Reproduce the test setup minimally and inspect what loadProductTypesForLines returns
Account partner = new Account(Name = 'DIAG Partner', Type = 'Partner');
insert partner;

Product2 maintProd = new Product2(
    Name = 'DIAG Maint Product Type Test',
    ProductCode = 'DIAG-MAINT-TYPE-TEST',
    IsActive = true,
    Fortra_Product_Type__c = 'New Maintenance'
);
insert maintProd;

Id stdPBId = Test.getStandardPricebookId();
