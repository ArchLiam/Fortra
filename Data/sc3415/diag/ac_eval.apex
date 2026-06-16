// SC-3415 AC evaluation across 10 real activated subscription orders
List<Id> orderIds = new List<Id>{
    '801WC00000kYmw8YAC','801WC00000k2pjwYAA','801WC00000ko5HqYAI','801WC00000kDQokYAG','801WC00000kaGBpYAM',
    '801WC00000kE3DLYA0','801WC00000kJ5EcYAK','801WC00000k3NfDYAU','801WC00000kZEFQYA4','801WC00000kDFEsYAO'
};
Map<Id, Order> orders = new Map<Id, Order>([
    SELECT Id, OrderNumber, Status, StatusCode FROM Order WHERE Id IN :orderIds
]);
System.debug('ACHDR order | lines termed ptcPop assetizable future AAS | status');
for (Id oid : orderIds) {
    List<OrderItem> ois = [
        SELECT Id, PricingTermCount, SubscriptionTerm, ServiceDate, Product2.IsAssetizable
        FROM OrderItem WHERE OrderId = :oid
    ];
    Integer termed = 0, ptcPop = 0, assetizable = 0, future = 0;
    Set<Id> oiIds = new Set<Id>();
    for (OrderItem oi : ois) {
        oiIds.add(oi.Id);
        if (oi.SubscriptionTerm != null) { termed++; if (oi.PricingTermCount != null) ptcPop++; }
        if (oi.Product2.IsAssetizable) assetizable++;
        if (oi.ServiceDate != null && oi.ServiceDate > Date.today()) future++;
    }
    Integer aas = [SELECT COUNT() FROM AssetActionSource WHERE ReferenceEntityItemId IN :oiIds];
    Order o = orders.get(oid);
    System.debug('ACROW ' + o.OrderNumber + ' | ' + ois.size() + ' ' + termed + ' ' + ptcPop + ' '
        + assetizable + ' ' + future + ' ' + aas + ' | ' + o.Status);
}
