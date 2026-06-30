// J-07 New-Maintenance net posthook fallback smoke-test (BoKS proven DPP recipe).
// 1 perpetual license (PIAP, list 355) + 1 derived New-Maintenance line (PIAMBK, UnitPrice 0).
// Maintenance line gets Maintenance Type Defn = Standard (rate 0.20) via REST QLIA afterward.
// Expect: license net 355, maintenance NetUnitPrice = 0.20 * 355 = 71 (no partner) populated by
// PartnerNetPricePosthook when the procedure leaves NetUnitPrice at $0. SC-3412 / SC-3410.
Id oppId       = '006WC00000RZUTVYA5';            // Train the Trainer - Derived Pricing
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book (IsActive=true)
Id licPbe  = '01uWC000005ws8MYAQ';  Id licProd = '01tWC00000DD1btYAD'; // PIA-PIA-NRPS-PIAP  355
Id mntPbe  = '01uWC000005wsbUYAQ';  Id mntProd = '01tWC00000DD1bsYAD'; // PIA-PIA-RNM-PIAMBK derived
String tag = 'J07-' + String.valueOf(Crypto.getRandomInteger()).right(5);
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' NEW-MAINT POSTHOOK FALLBACK',
        OpportunityId = oppId, Pricebook2Id = pricebookId, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    q.setOptions(dmo);
    Database.insert(q, dmo);
    QuoteLineItem lic = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=licPbe, Product2Id=licProd,
        Quantity=1, UnitPrice=355, Fortra_Product_Type__c='Perpetual');
    QuoteLineItem mnt = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ lic, mnt };
    Database.insert(lines, dmo);
    System.debug(LoggingLevel.ERROR, 'J-07 MARKER quoteId=' + q.Id + ' lic=' + lic.Id + ' mnt=' + mnt.Id
        + ' quoteUrl=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'J-07 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
