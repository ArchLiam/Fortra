// K-09 Stale category totals when group empty — builds a USD quote with ONE Services line
// (EFT Cutover Basic, PBE 01uWC000005woEBYAY, Fortra_Product_Type__c='Services', list 2750)
// so Total_Services__c becomes non-zero on reprice; the test then deletes the line, reprices,
// and checks whether Total_Services__c resets to 0 (fixed) or stays stale (defect). SC-3345 / K-09.
Savepoint sp = Database.setSavepoint();
try {
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.AllowSave = true;
    dml.DuplicateRuleHeader.RunAsCurrentUser = true;

    String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));
    Id ACCT = '001WC00000XiZP4YAN';            // Fortra, LLC - Test
    Id OPP  = '006WC00000RPVp3YAH';            // standing Opp
    Id PB   = '01sWC0000022GHFYA2';            // Fortra Price Book (active)
    Id SVC_PBE = '01uWC000005woEBYAY';         // EFT Cutover Basic Services, list 2750 USD
    Id SVC_PROD = '01tWC00000FBbiGYAT';

    Quote q = new Quote();
    q.Name = 'K-09 Stale Category Total ' + TAG;
    q.OpportunityId = OPP;
    q.Pricebook2Id = PB;
    q.CurrencyIsoCode = 'USD';
    q.Status = 'Draft';
    q.ExpirationDate = Date.today().addDays(30);
    q.setOptions(dml);
    insert q;

    QuoteLineItem svc = new QuoteLineItem();
    svc.QuoteId = q.Id;
    svc.PricebookEntryId = SVC_PBE;
    svc.Product2Id = SVC_PROD;
    svc.Quantity = 1;
    svc.UnitPrice = 2750;
    svc.setOptions(dml);
    insert svc;

    System.debug(LoggingLevel.ERROR, 'K09_MARKER quoteId=' + q.Id
        + ' servicesLineId=' + svc.Id
        + ' url=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'K09_ERROR ' + e.getTypeName() + ': ' + e.getMessage() + ' @ ' + e.getStackTraceString());
    throw e;
}
