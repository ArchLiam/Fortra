// Derived Pricing DEMO quote - BoKS (sanctioned, working DPP product). Step 1: header + 2 lines.
Id oppId       = '006WC00000RZUTVYA5';            // Train the Trainer - Derived Pricing
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book
Id licPbe  = '01uWC000005ws8MYAQ';  Id licProd = '01tWC00000DD1btYAD'; // PIA-PIA-NRPS-PIAP  355
Id mntPbe  = '01uWC000005wsbUYAQ';  Id mntProd = '01tWC00000DD1bsYAD'; // PIA-PIA-RNM-PIAMBK derived

try {
    Quote q = new Quote(
        Name = 'Q-DERIVED PRICING DEMO (BoKS) - 2026-06-29',
        OpportunityId = oppId, Pricebook2Id = pricebookId, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    insert q;
    QuoteLineItem lic = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=licPbe, Product2Id=licProd,
        Quantity=1, UnitPrice=355, Fortra_Product_Type__c='Perpetual');
    QuoteLineItem mnt = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    insert new List<QuoteLineItem>{ lic, mnt };
    System.debug('RESULT quoteId=' + q.Id + ' lic=' + lic.Id + ' mnt=' + mnt.Id);
} catch (Exception e) {
    System.debug('ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
