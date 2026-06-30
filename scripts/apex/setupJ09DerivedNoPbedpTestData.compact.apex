// J-09 Native derived pull requires contributing-product config (PBEDP) — SC-3372 / M5-PBEDP.
// Build a new-business quote with a priced license (Abstract, BI-ABS-NRPS-ABSTPE, list 2200)
// + its IsDerived NewMaintenance line (Abstract-NewMaintenance, BI-ABS-RNM-ABSTNE) whose
// maintenance PBE has NO PriceBookEntryDerivedPrice row (uncovered).
// On Force-reprice the native DerivedProductsNativePull/NonRenewal step must resolve the
// contributor via the missing PBEDP config -> expect hard-error "contributing products are
// missing" / maintenance NetUnitPrice stays NULL (NOT a clean derived value).
Id oppId       = '006WC00000RZUTVYA5';            // Train the Trainer - Derived Pricing (Fortra Price Book)
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book
Id licPbe  = '01uWC000005wrr9YAA';  Id licProd = '01tWC00000DD11EYAT'; // BI-ABS-NRPS-ABSTPE  list 2200
Id mntPbe  = '01uWC000005wsZFYAY';  Id mntProd = '01tWC00000DD11DYAT'; // BI-ABS-RNM-ABSTNE  IsDerived, NO PBEDP
String tag = 'J09-' + String.valueOf(Crypto.getRandomInteger()).right(5);
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' DERIVED NO-PBEDP (contributing-products-missing)',
        OpportunityId = oppId, Pricebook2Id = pricebookId, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    q.setOptions(dmo);
    Database.insert(q, dmo);
    QuoteLineItem lic = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=licPbe, Product2Id=licProd,
        Quantity=1, UnitPrice=2200, Fortra_Product_Type__c='Perpetual');
    QuoteLineItem mnt = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ lic, mnt };
    Database.insert(lines, dmo);
    System.debug(LoggingLevel.ERROR, 'J-09 MARKER quoteId=' + q.Id + ' lic=' + lic.Id + ' mnt=' + mnt.Id
        + ' quoteUrl=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'J-09 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
