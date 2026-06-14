PricebookEntry pbe = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Id='01uWC000005wrr5YAA' LIMIT 1];
OrderItem oi = new OrderItem(
  OrderId = '801WC00000kfVDVYA2',
  PricebookEntryId = pbe.Id,
  Product2Id = pbe.Product2Id,
  Quantity = 1,
  UnitPrice = pbe.UnitPrice,
  Description = 'ZZ_E2E_RCA_20260613 OrderItem'
);
insert oi;
System.debug('CREATED_OI_ID=' + oi.Id);

OrderItemAttribute oia = new OrderItemAttribute(
  OrderItemId = oi.Id,
  AttributeDefinitionId = '0tjWC000000096hYAA',
  AttributeValue = 'Per Brand',
  ExternalId = 'ZZ_E2E_RCA_20260613'
);
insert oia;
System.debug('CREATED_OIA_ID=' + oia.Id);
