// J-03 Derived renewal-carry / non-renewal-reset smoke-test (BoKS proven recipe).
// NON-RENEWAL HALF: license (PIAP 355) + derived New-Maintenance line (PIAMBK).
//   After QLIA Maintenance Type Defn = Standard + Force-reprice, the
//   "Derived Pricing - NetUnitPrice Value Reset" (IF Renewal then Net else 0) must
//   clear any context net to 0, then "Derived Pricing Formula" non-renewal branch
//   (0.20 x Base 355 = 71) re-seeds NetUnitPrice. Expect maintenance net = 71.
// (RENEWAL HALF is validated on live canary 0QLWC000003dEW24AM where the formula's
//  IF(QuoteTypeText__c='Renewal', NetUnitPrice, ...) carries prior net unchanged.)
Id oppId       = '006WC00000RZUTVYA5';            // Train the Trainer - Derived Pricing
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book (IsActive)
Id licPbe  = '01uWC000005ws8MYAQ';  Id licProd = '01tWC00000DD1btYAD'; // PIA-PIA-NRPS-PIAP 355
Id mntPbe  = '01uWC000005wsbUYAQ';  Id mntProd = '01tWC00000DD1bsYAD'; // PIA-PIA-RNM-PIAMBK derived
String tag = 'J03-' + String.valueOf(Crypto.getRandomInteger()).right(5);
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' DERIVED NON-RENEWAL RESET',
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
    System.debug(LoggingLevel.ERROR, 'J-03 MARKER quoteId=' + q.Id + ' lic=' + lic.Id + ' mnt=' + mnt.Id
        + ' quoteUrl=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'J-03 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
