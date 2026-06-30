// K-07 Co-owned version churn: V21 Derived Pricing Formula reverted to 3-tier.
// Build a BoKS derived-pricing quote with a DROPPED-tier maintenance line (Basic, 0.15)
// + a KEPT-tier control (Standard, 0.20). Under 7-tier: Basic=53.25, Standard=71.
// Under active V21 3-tier (Premier/Standard/Professional only): Basic -> 0 (REGRESSION).
String TAG = 'K07-' + String.valueOf(Crypto.getRandomInteger()).right(6);
Id oppId       = '006WC00000RZUTVYA5';            // Train the Trainer - Derived Pricing
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book (active)
Id licPbe  = '01uWC000005ws8MYAQ';  Id licProd = '01tWC00000DD1btYAD'; // PIA-PIA-NRPS-PIAP  list 355
Id mntPbe  = '01uWC000005wsbUYAQ';  Id mntProd = '01tWC00000DD1bsYAD'; // PIA-PIA-RNM-PIAMBK derived
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-K07 DERIVED 3TIER REGRESSION ' + TAG,
        OpportunityId = oppId, Pricebook2Id = pricebookId, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    Database.insert(q, dmo);
    QuoteLineItem lic = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=licPbe, Product2Id=licProd,
        Quantity=1, UnitPrice=355, Fortra_Product_Type__c='Perpetual');
    QuoteLineItem mntBasic = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    QuoteLineItem mntStd = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ lic, mntBasic, mntStd };
    Database.insert(lines, dmo);
    System.debug(LoggingLevel.ERROR, 'K07_RESULT quoteId=' + q.Id
        + ' licQLI=' + lic.Id + ' mntBasicQLI=' + mntBasic.Id + ' mntStdQLI=' + mntStd.Id
        + ' URL=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'K07_ERROR ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
