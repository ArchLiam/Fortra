// J-02 Derived tier completeness smoke-test (BoKS proven recipe).
// 1 license (PIAP, list 355) + 2 derived maintenance lines (PIAMBK):
//   - mntStd  -> Maintenance Type Defn = Standard (kept tier, expect 0.20*355 = 71)
//   - mntExp  -> Maintenance Type Defn = Expert   (dropped tier in 3-tier V21, expect $0 if defect present, 0.35*355=124.25 if 7-tier)
// QLIAs added via REST afterward (Apex DML rejected on QLIA managed sobject).
Id oppId       = '006WC00000RZUTVYA5';            // Train the Trainer - Derived Pricing
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book
Id licPbe  = '01uWC000005ws8MYAQ';  Id licProd = '01tWC00000DD1btYAD'; // PIA-PIA-NRPS-PIAP  355
Id mntPbe  = '01uWC000005wsbUYAQ';  Id mntProd = '01tWC00000DD1bsYAD'; // PIA-PIA-RNM-PIAMBK derived
String tag = 'J02-' + String.valueOf(Crypto.getRandomInteger()).right(5);
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' DERIVED TIER (Expert vs Standard)',
        OpportunityId = oppId, Pricebook2Id = pricebookId, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    q.setOptions(dmo);
    Database.insert(q, dmo);
    QuoteLineItem lic = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=licPbe, Product2Id=licProd,
        Quantity=1, UnitPrice=355, Fortra_Product_Type__c='Perpetual');
    QuoteLineItem mntStd = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    QuoteLineItem mntExp = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ lic, mntStd, mntExp };
    Database.insert(lines, dmo);
    System.debug(LoggingLevel.ERROR, 'J-02 MARKER quoteId=' + q.Id + ' lic=' + lic.Id + ' mntStd=' + mntStd.Id + ' mntExp=' + mntExp.Id
        + ' quoteUrl=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'J-02 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
