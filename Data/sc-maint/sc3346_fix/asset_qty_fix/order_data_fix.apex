Id oiId = '802WC00000OpopqYAB';
OrderItem oi = [SELECT Id, Quantity, Source_List_Price__c, PartnerDiscountPercent, Fortra_Product_Type__c
                FROM OrderItem WHERE Id = :oiId];
// Resolve maintenance tier from the OrderItemAttribute, then the rate from Maintenance_Rate__mdt
String tier;
for (OrderItemAttribute a : [SELECT AttributeValue FROM OrderItemAttribute
        WHERE OrderItemId = :oiId AND AttributeName = 'Maintenance Type Defn']) {
    tier = a.AttributeValue;
}
Decimal rate;
for (Maintenance_Rate__mdt r : [SELECT Rate__c FROM Maintenance_Rate__mdt WHERE MaintenanceType__c = :tier]) {
    rate = r.Rate__c;
}
Decimal net = (oi.Source_List_Price__c * rate).setScale(2, RoundingMode.HALF_UP);
Decimal partnerPct = oi.PartnerDiscountPercent != null ? oi.PartnerDiscountPercent : 0;
if (partnerPct > 0) net = (net * (1 - partnerPct/100)).setScale(2, RoundingMode.HALF_UP);
Decimal qty = (oi.Quantity != null && oi.Quantity > 0) ? oi.Quantity : 1;
Decimal total = (net * qty).setScale(2, RoundingMode.HALF_UP);
System.debug('COMPUTED: tier=' + tier + ' rate=' + rate + ' partner%=' + partnerPct
    + ' net=' + net + ' total=' + total);
update new OrderItem(Id = oiId, NetUnitPrice = net, NetTotalPrice = total,
    TotalLineAmount = total, PartnerUnitPrice = net);
System.debug('ORDER LINE UPDATED OK');
