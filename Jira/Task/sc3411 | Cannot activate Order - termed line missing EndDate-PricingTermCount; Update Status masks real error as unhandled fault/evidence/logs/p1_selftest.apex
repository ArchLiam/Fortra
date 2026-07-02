// Null the term fields on the termed line; the before-save backstop (Set Dates V6) should re-populate them in the same DML.
OrderItem oi = new OrderItem(Id='802WC00000OpopoYAB', EndDate=null, PricingTermCount=null);
update oi;
OrderItem after = [SELECT EndDate, PricingTermCount, ProductSellingModel.SellingModelType FROM OrderItem WHERE Id='802WC00000OpopoYAB'];
System.debug('P1_SELFTEST type=' + after.ProductSellingModel.SellingModelType + ' EndDate=' + after.EndDate + ' PricingTermCount=' + after.PricingTermCount);
