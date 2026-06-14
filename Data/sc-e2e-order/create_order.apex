// Create a tagged Draft Order on the BoKS IAM Test Account
Account acct = [SELECT Id FROM Account WHERE Id='001WC00000kTYyNYAW' LIMIT 1];
PricebookEntry pbe = [SELECT Pricebook2Id FROM PricebookEntry WHERE Id='01uWC000005wrr5YAA' LIMIT 1];
Order o = new Order(
  Name = 'ZZ_E2E_RCA_20260613 Order CRUD test',
  AccountId = acct.Id,
  EffectiveDate = Date.today(),
  Status = 'Draft',
  Pricebook2Id = pbe.Pricebook2Id,
  Description = 'ZZ_E2E_RCA_20260613 - cluster ORDER+CONVERT api test'
);
insert o;
System.debug('CREATED_ORDER_ID=' + o.Id);
