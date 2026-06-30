// J-11 Zero-price contributing product -> $0 derived maintenance (SC-3372 secondary / zero-list).
// Build a NEW-business quote with the canonical $0-list contributor EFT 8 Continuum
// (GS-GSE-NRPS-E8CP, 01tWC00000DD1DxYAL, list $0 in ALL 20 PBEs) + its IsDerived
// New-Maintenance line EFT 8 Continuum-NewMaintenance (GS-GSE-RNM-EFT8, 01tWC00000DD1DwYAL,
// Fortra USD PBE 01uWC000005wsZnYAI IsDerived=true, PBEDP 182WC000000HEPxYAO present so the
// native pull RESOLVES the contributor -> no "contributing products missing" hard-error).
// Maint gets Maintenance Type Defn=Standard (tier 0.20) so a VALID non-zero tier multiplies the
// $0 contributor base -> expect derived NetUnitPrice = 0.20 x 0 = $0 regardless of tier.
Id oppId       = '006WC00000RZUTVYA5';            // Train the Trainer - Derived Pricing (Fortra Price Book)
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book
Id licPbe  = '01uWC000005wrvHYAQ';  Id licProd = '01tWC00000DD1DxYAL'; // EFT 8 Continuum  Fortra USD  list 0
Id mntPbe  = '01uWC000005wsZnYAI';  Id mntProd = '01tWC00000DD1DwYAL'; // EFT 8 Continuum-NewMaintenance IsDerived, PBEDP present
String tag = 'J11-' + String.valueOf(Crypto.getRandomInteger()).right(5);
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
dmo.DuplicateRuleHeader.RunAsCurrentUser = true;
Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' ZERO-PRICE CONTRIBUTOR (J-11)',
        OpportunityId = oppId, Pricebook2Id = pricebookId, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    q.setOptions(dmo);
    Database.insert(q, dmo);
    QuoteLineItem lic = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=licPbe, Product2Id=licProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='Perpetual');
    QuoteLineItem mnt = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ lic, mnt };
    Database.insert(lines, dmo);
    System.debug(LoggingLevel.ERROR, 'J-11 MARKER quoteId=' + q.Id + ' lic=' + lic.Id + ' mnt=' + mnt.Id
        + ' quoteUrl=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'J-11 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
