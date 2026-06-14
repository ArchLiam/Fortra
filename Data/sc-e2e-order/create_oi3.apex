PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Id='01uWC000005wrr5YAA' LIMIT 1];
OrderItem oi = new OrderItem(
  OrderId = '801WC00000kfVDVYA2',
  PricebookEntryId = pbe.Id,
  Product2Id = pbe.Product2Id,
  Quantity = 1,
  UnitPrice = pbe.UnitPrice,
  Description = 'ZZ_E2E_RCA_20260613 OrderItem'
);
List<Database.SaveResult> srs = Database.insertImmediate(new List<OrderItem>{oi});
for(Database.SaveResult sr : srs){
  System.debug('OI_SUCCESS=' + sr.isSuccess() + ' OI_ID=' + sr.getId());
  if(!sr.isSuccess()){ for(Database.Error e: sr.getErrors()) System.debug('OI_ERR=' + e.getMessage()); }
}
