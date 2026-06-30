// J-06 Partner discount on DERIVED MAINTENANCE (non-renewal, applied once) smoke-test.
// V21 step "Partner Discount - Derived Maintenance" (steps 89-91) + Stamp Partner Unit Price -
// Derived Maintenance + PartnerNetPricePosthook. Gate = ItemIsDerived=true AND
// Deal_Type__c NotEquals 'Fortra Originated' AND ItemPricingSource NotEquals 'LastTransaction'
// AND QuoteTypeText NotEquals 'Renewal'.
//
// Clean BoKS derived recipe on a PARTNER (Channel Originated, Discount model) NEW quote:
//   license  PIA-PIA-NRPS-PIAP  (PBE 01uWC000005ws8MYAQ) list 355  -> contributor Pre_Partner base
//   maint    PIA-PIA-RNM-PIAMBK (PBE 01uWC000005wsbUYAQ) UnitPrice 0 -> ItemIsDerived, tier 0.20
// QLIAs (license Feature Options=Standard; maint Maintenance Type Defn=Standard) added via REST
// AFTER this run (Apex DML rejected on QLIA managed sobject), then Force-reprice.
//
// EXPECT (no double discount): derived list net = 355 * 0.20 = 71 (from license PRE-partner base);
//   partner New_Maintenance % applied ONCE -> maint NetUnitPrice = 71 * (1 - newMaint%/100).
//   With 12% -> 62.48 ; with 10% -> 63.90. NOT 71*(1-p)^2 (double) and NOT plain 71.
//
// Atomic: savepoint rollback on any failure.
// Run: sf apex run --target-org FortraUAT -f scripts/apex/setupJ06PartnerDerivedMaintTestData.compact.apex
// Output: grep the debug log for the "J-06 MARKER" ERROR-level line.

Id ACCT  = '001WC00000XiZP4YAN';        // Fortra, LLC - Test
Id OPP   = '006WC00000RZUTVYA5';        // Train the Trainer - Derived Pricing
Id PB    = '01sWC0000022GHFYA2';        // Fortra Price Book (active)
Id LE    = '0fwWC000000034LYAQ';        // Legal Entity
Id STT   = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PART  = '001WC00000ZtazZYAR';        // Partner Account (AB Test Partner Account)

Id licPbe  = '01uWC000005ws8MYAQ';  Id licProd = '01tWC00000DD1btYAD'; // PIA-PIA-NRPS-PIAP  355
Id mntPbe  = '01uWC000005wsbUYAQ';  Id mntProd = '01tWC00000DD1bsYAD'; // PIA-PIA-RNM-PIAMBK derived

String tag = 'J06-' + String.valueOf(Crypto.getRandomInteger()).right(5);

Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
dmo.DuplicateRuleHeader.RunAsCurrentUser = true;

Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' PARTNER DERIVED MAINT (non-renewal)',
        OpportunityId = OPP, Pricebook2Id = PB, CurrencyIsoCode = 'USD',
        Status = 'Draft', Quote_Type__c = 'New',
        QuoteAccountId = ACCT, SalesTransactionTypeId = STT, LegalEntityId = LE,
        Deal_Type__c = 'Channel Originated',
        Partner_Pricing_Model__c = 'Discount', PartnerAccountId = PART, Billing_Partner__c = PART,
        Show_Hide_Discounts__c = 'Show',
        ExpirationDate = Date.today().addDays(30));
    q.setOptions(dmo);
    Database.insert(q, dmo);

    QuoteLineItem lic = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=licPbe, Product2Id=licProd,
        Quantity=1, UnitPrice=355, Fortra_Product_Type__c='Perpetual');
    QuoteLineItem mnt = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=mntPbe, Product2Id=mntProd,
        Quantity=1, UnitPrice=0, Fortra_Product_Type__c='New Maintenance');
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ lic, mnt };
    Database.insert(lines, dmo);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, 'J-06 MARKER Quote#' + q.QuoteNumber
        + ' quoteId=' + q.Id + ' licQLI=' + lic.Id + ' mntQLI=' + mnt.Id
        + ' quoteUrl=' + base + '/lightning/r/Quote/' + q.Id + '/view'
        + ' | NEXT: REST add QLIA (lic Feature Options=Standard, mnt Maintenance Type Defn=Standard) then Force-reprice'
        + ' | EXPECT derived list net 71=355*0.20, partner New_Maint% applied ONCE');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'J-06 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
    throw e;
}
