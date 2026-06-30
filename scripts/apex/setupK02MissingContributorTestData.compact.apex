// K-02 No-priced-node / missing-contributor derived line smoke-test.
// A single DERIVED maintenance line (PIA-PIA-RNM-PIAMBK, Fortra Price Book derived PBE,
// IsDerived=true) on a NEW Draft quote with NO license contributor on the cart.
// Because the contributing license (PIA-PIA-NRPS-PIAP) is absent, the derived line
// has no priced contributor node -> Stamp Contributor Base finds nothing -> the
// Derived Pricing Formula fallback chain (Base_Price__c>0 ? ... : Pre_Partner ? ... :
// InputUnitPrice ? ... : 0) bottoms out at 0. Expected: net=0 surfaced as a missing
// contributor (ValidationResult), NOT silently accepted as a valid $0 price.
// QLIAs are not needed for this scenario.
Id ACCT      = '001WC00000XiZP4YAN';                 // Fortra, LLC - Test
Id OPP       = '006WC00000RZUTVYA5';                 // Train the Trainer - Derived Pricing (used by J-02)
Id PB        = '01sWC0000022GHFYA2';                 // Fortra Price Book
Id mntPbe    = '01uWC000005wsbUYAQ';                 // PIA-PIA-RNM-PIAMBK derived PBE (Fortra PB, IsDerived=true)
Id mntProd   = '01tWC00000DD1bsYAD';                 // PIA-PIA-RNM-PIAMBK (derived maintenance)
String tag = 'K02-' + String.valueOf(Crypto.getRandomInteger()).right(5);
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' MISSING CONTRIBUTOR (maint-only, no license)',
        OpportunityId = OPP, Pricebook2Id = PB, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    q.setOptions(dmo);
    Database.insert(q, dmo);
    // Lone derived maintenance line, no contributor license on the cart.
    QuoteLineItem mnt = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    Database.insert(mnt, dmo);
    System.debug(LoggingLevel.ERROR, 'K-02 MARKER quoteId=' + q.Id + ' mntLine=' + mnt.Id
        + ' quoteUrl=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'K-02 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
