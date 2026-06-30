// setupK08DerivedCancelTestData.compact.apex
// K-08 (SC-3441 / SC-3346 cross): Cancellation of a DERIVED maintenance line must credit the
// maintenance asset's OWN NET (the derived value), NOT the parent license net and NOT list.
// Builds a Draft "Cancellation" Quote with a single Qty=-1 cancel line on the DERIVED maintenance
// product PIA-PIA-RNM-PIAMBK, QuoteAction(Type='Cancel').SourceAsset = the owned maint asset,
// and CancelNetUnitPrice__c seeded from the MAINTENANCE AssetActionSource NetUnitPrice (derived 71),
// NOT the license net and NOT list (the derived PBE list is 0).
//
//   Opportunity (Quote hangs off it)  006WC00000RPVp3YAH
//   DERIVED maint asset to cancel      02iWC000008N46eYAC  (Price 71, AAS Generate NetUnitPrice 71)
//   Derived PBE (USD, Fortra book)     01uWC000005wsbUYAQ  (IsDerived=true, list 0)
//
// Expected after Reprice/posthook: NetUnitPrice=71 (maint asset net), TotalPrice/NetTotalPrice/
// Subtotal/TotalLineAmount = -71 ; NOT -(license net 355*...) and NOT -(tier%*list).
//
// Run: sf apex run --target-org FortraUAT -f scripts/apex/setupK08DerivedCancelTestData.compact.apex
// Output: grep the debug log for the "K08-DERIVED-CANCEL" marker (ERROR level).

Id OPP   = '006WC00000RPVp3YAH';     // Quote hangs off this Opp
Id ASSET = '02iWC000008N46eYAC';     // DERIVED maintenance asset (derived net 71)
Id DPBE  = '01uWC000005wsbUYAQ';     // derived USD PBE on Fortra Price Book (IsDerived=true)

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity oppRec = [SELECT Id, AccountId FROM Opportunity WHERE Id = :OPP];
Id ACCT = oppRec.AccountId;

Asset ast = [SELECT Id, Product2Id, CurrencyIsoCode, Price FROM Asset WHERE Id = :ASSET];
PricebookEntry pbe = [SELECT Id, Pricebook2Id, UnitPrice FROM PricebookEntry WHERE Id = :DPBE];

// CancelNetUnitPrice__c = the MAINTENANCE asset's own NET (derived), via its AssetActionSource.
// Prefer a Generate/Initial-Sale row, currency-matched, positive NetUnitPrice. This MUST be the
// derived maintenance net (71), NOT the license net and NOT the (0) derived list.
Decimal cancelNet;
for (AssetActionSource s : [SELECT NetUnitPrice, AssetAction.Type FROM AssetActionSource
                            WHERE AssetAction.AssetId = :ASSET AND NetUnitPrice > 0
                              AND CurrencyIsoCode = :ast.CurrencyIsoCode
                            ORDER BY CreatedDate ASC]) {
    cancelNet = s.NetUnitPrice;
    if (s.AssetAction.Type == 'Generate') { break; }
}
if (cancelNet == null || cancelNet <= 0) { cancelNet = ast.Price; }   // fall back to asset net (derived 71)

// Convert-precondition lookups (related to the Quote's Account).
List<Places__c> places = [SELECT Id, Address__Street__s, Address__City__s, Address__StateCode__s,
                                 Address__PostalCode__s, Address__CountryCode__s
                          FROM Places__c WHERE Account__c = :ACCT LIMIT 1];
List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :ACCT LIMIT 1];
Places__c plc = places.isEmpty() ? null : places[0];
Id PLACEID = plc == null ? null : plc.Id;
Id CONTACT = contacts.isEmpty() ? null : contacts[0].Id;
String adrStreet  = plc == null ? null : plc.Address__Street__s;
String adrCity    = plc == null ? null : plc.Address__City__s;
String adrState   = plc == null ? null : plc.Address__StateCode__s;
String adrZip     = plc == null ? null : plc.Address__PostalCode__s;
String adrCountry = plc == null ? null : plc.Address__CountryCode__s;

Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name            = 'K08 Derived Cancel ' + TAG,
        OpportunityId   = OPP,
        Pricebook2Id    = pbe.Pricebook2Id,
        Status          = 'Draft',
        Quote_Type__c   = 'Cancellation',
        CurrencyIsoCode = 'USD',
        StartDate       = Date.today(),
        ExpirationDate  = Date.today().addDays(30),
        BillToContactId = CONTACT,
        ContactId       = CONTACT,
        Bill_To_Place__c= PLACEID,
        Ship_To_Place__c= PLACEID,
        BillingStreet      = adrStreet,  BillingCity        = adrCity,
        BillingStateCode   = adrState,   BillingPostalCode  = adrZip,   BillingCountryCode  = adrCountry,
        ShippingStreet     = adrStreet,  ShippingCity       = adrCity,
        ShippingStateCode  = adrState,   ShippingPostalCode = adrZip,   ShippingCountryCode = adrCountry);
    Database.insert(q, dml);

    QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = 'Cancel', SourceAssetId = ASSET);
    Database.insert(qa, dml);

    QuoteLineItem qli = new QuoteLineItem(
        QuoteId               = q.Id,
        QuoteActionId         = qa.Id,
        PricebookEntryId      = pbe.Id,
        Quantity              = -1,
        StartQuantity         = 1,
        CancelNetUnitPrice__c = cancelNet,
        PeriodBoundary        = 'Anniversary',
        StartDate             = Date.today(),
        EndDate               = Date.today().addYears(1));
    Database.insert(qli, dml);

    QuoteLineItem r = [SELECT Id, Quote.Name, Quantity, CancelNetUnitPrice__c, NetUnitPrice, TotalPrice,
                              PricebookEntry.Product2.ProductCode
                       FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ K08-DERIVED-CANCEL CREATED  ' + r.Quote.Name
        + '\n  Quote        : ' + base + '/' + q.Id
        + '\n  QuoteId      : ' + q.Id + '  | QLI=' + r.Id + '  | QA=' + qa.Id
        + '\n  Product      : ' + r.PricebookEntry.Product2.ProductCode + ' (DERIVED maint, PBE ' + DPBE + ')'
        + '\n  Cancel line  : Qty ' + r.Quantity + '  | CancelNetUnitPrice__c=' + r.CancelNetUnitPrice__c
        + ' (=MAINT asset derived NET; license net & list 0 NOT used)'
        + '\n  NetUnitPrice(now)=' + r.NetUnitPrice + '  TotalPrice(now)=' + r.TotalPrice + '  (0/null until repriced)'
        + '\n  EXPECT after V21 reprice: NetUnitPrice=' + cancelNet + ', TotalPrice/NetTotalPrice/Subtotal=' + (cancelNet * -1));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ K08-DERIVED-CANCEL FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
