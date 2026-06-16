// AC2: QuoteLineItem.PricingTermCount on the source quotes of the 10 test orders
List<Id> orderIds = new List<Id>{
    '801WC00000kYmw8YAC','801WC00000k2pjwYAA','801WC00000ko5HqYAI','801WC00000kDQokYAG','801WC00000kaGBpYAM',
    '801WC00000kE3DLYA0','801WC00000kJ5EcYAK','801WC00000k3NfDYAU','801WC00000kZEFQYA4','801WC00000kDFEsYAO'
};
for (Order o : [SELECT Id, OrderNumber, QuoteId FROM Order WHERE Id IN :orderIds]) {
    if (o.QuoteId == null) { System.debug('AC2Q ' + o.OrderNumber + ' | no source quote'); continue; }
    Integer termed = 0, ptcPop = 0;
    for (QuoteLineItem q : [SELECT PricingTermCount, SubscriptionTerm, EndDate FROM QuoteLineItem
                            WHERE QuoteId = :o.QuoteId AND SellingModelType = 'TermDefined']) {
        termed++;
        if (q.PricingTermCount != null) ptcPop++;
    }
    System.debug('AC2Q ' + o.OrderNumber + ' | quoteTermedLines=' + termed + ' ptcPopulated=' + ptcPop);
}
