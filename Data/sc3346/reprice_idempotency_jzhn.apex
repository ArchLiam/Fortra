// Nir #5 read-only re-verify — reprice JzHN once, snapshot before/after. Run repeatedly to test idempotency.
String qId = '0Q0WC000003JzHN0A0';
List<String> before = new List<String>();
for (QuoteLineItem q : [SELECT Product2.Name, NetUnitPrice, UnitPrice, Base_Price__c, Pre_Partner_Price__c, PartnerDiscountPercent
                        FROM QuoteLineItem WHERE QuoteId = :qId ORDER BY Product2.Name]) {
    before.add('  ' + (q.Product2 != null ? q.Product2.Name : '') + ' | Net=' + q.NetUnitPrice + ' Unit=' + q.UnitPrice
        + ' Base=' + q.Base_Price__c + ' PrePartner=' + q.Pre_Partner_Price__c + ' Partner%=' + q.PartnerDiscountPercent);
}
System.debug('REPRICE| ===== BEFORE =====');
for (String s : before) System.debug('REPRICE|' + s);

try {
    Flow.Interview f = Flow.Interview.createInterview('Fortra_Quote_Reprice', new Map<String, Object>{ 'QuoteId' => qId });
    f.start();
    System.debug('REPRICE| reprice invoked OK');
} catch (Exception e) {
    System.debug('REPRICE| INVOKE FAILED: ' + e.getTypeName() + ': ' + e.getMessage());
}

List<String> after = new List<String>();
for (QuoteLineItem q : [SELECT Product2.Name, NetUnitPrice, UnitPrice, Base_Price__c, Pre_Partner_Price__c, PartnerDiscountPercent
                        FROM QuoteLineItem WHERE QuoteId = :qId ORDER BY Product2.Name]) {
    after.add('  ' + (q.Product2 != null ? q.Product2.Name : '') + ' | Net=' + q.NetUnitPrice + ' Unit=' + q.UnitPrice
        + ' Base=' + q.Base_Price__c + ' PrePartner=' + q.Pre_Partner_Price__c + ' Partner%=' + q.PartnerDiscountPercent);
}
System.debug('REPRICE| ===== AFTER =====');
for (String s : after) System.debug('REPRICE|' + s);
