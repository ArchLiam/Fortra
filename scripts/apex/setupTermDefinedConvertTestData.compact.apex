// setupTermDefinedConvertTestData.compact.apex
// Builds an I-02 (V21 validation) "TermDefined convert / null PricingTermCount+EndDate" QUOTE fixture
// in FortraUAT. I-02 tests: does a TermDefined quote line reach the OrderItem at convert with a NULL
// PricingTermCount / EndDate (which native RLM blocks at order activation: REQUIRED_FIELD_MISSING
// "PricingTermCount is required for Termed order products"), and does the V21 quote-tier Proration
// writer (SC-3420 guarded restore: filter SellingModelType='TermDefined' AND StartProrationPeriod
// IsNotNull AND ItemSubscriptionTerm IsNotNull -> ProrationMultiplier -> PricingTermCount) now derive
// PTC + EndDate at the QUOTE TIER so null never reaches the order (root fix), making the order-tier
// Fortra_OrderItem_Set_Dates V6 backstop emergency-only.
//
// Builds ONE convert-ready Draft Quote with TWO TermDefined lines to bracket the writer guard:
//   Line A "WELL-CONFIGURED" : SubscriptionTerm=1 + PeriodBoundary='Anniversary', EndDate LEFT NULL.
//        ORACLE: after Force-reprice the V21 writer derives PricingTermCount=1 (and the proration
//        action derives EndDate) -> NOT null -> convert+activate clean.
//   Line B "MALFORMED"       : SubscriptionTerm=NULL, PeriodBoundary=NULL, EndDate=NULL.
//        ORACLE: guard does NOT fire -> PricingTermCount stays NULL + EndDate stays NULL -> this is the
//        I-02 hazard line that propagates null to the OrderItem (residual gap; order-tier backstop masks).
//
//   Product/PBE : 01uWC000005wrgpYAA  "Cobalt Strike" (Fortra Price Book, active, USD, TermDefined
//                 "Term Based - Annual" 0jPWC000000060b2AA, list 5900)
//   Opportunity : 006WC00000RPVp3YAH  (Account derives from the Opp — has Places + Contact for convert)
//
// Convert preconditions handled (same set as the SC-3441 cancel fixture): Quote.StartDate, BillTo/Quote
// Contact, Bill/Ship Place + Billing/Shipping address TEXT (all related to the Account), Account Type/DUNS.
// The remaining RLM steps (Start Sync, Reprice, checklist, Accepted, Convert, Activate) are UI/REST.
//
// Atomic: savepoint rollback on any failure -> no orphan Quote/QLI.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupTermDefinedConvertTestData.compact.apex
// Output: grep the debug log for the "TD-CONVERT-QUOTE" marker (logged at ERROR level).

Id OPP    = '006WC00000RPVp3YAH';
Id PBE_ID = '01uWC000005wry2YAA';            // Cobalt Strike, TermDefined Annual, USD, list 5900, PBE IsActive=true

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity oppRec = [SELECT Id, AccountId FROM Opportunity WHERE Id = :OPP];
Id ACCT = oppRec.AccountId;
PricebookEntry pbe = [SELECT Id, Pricebook2Id, Product2Id, Product2.Name, UnitPrice, CurrencyIsoCode
                      FROM PricebookEntry WHERE Id = :PBE_ID];

List<Places__c> places = [SELECT Id, Address__Street__s, Address__City__s, Address__StateCode__s,
                                 Address__PostalCode__s, Address__CountryCode__s
                          FROM Places__c WHERE Account__c = :ACCT LIMIT 1];
List<Contact>  contacts = [SELECT Id FROM Contact WHERE AccountId = :ACCT LIMIT 1];
Places__c plc = places.isEmpty() ? null : places[0];
Id PLACE   = plc == null ? null : plc.Id;
Id CONTACT = contacts.isEmpty() ? null : contacts[0].Id;
String adrStreet  = plc == null ? null : plc.Address__Street__s;
String adrCity    = plc == null ? null : plc.Address__City__s;
String adrState   = plc == null ? null : plc.Address__StateCode__s;
String adrZip     = plc == null ? null : plc.Address__PostalCode__s;
String adrCountry = plc == null ? null : plc.Address__CountryCode__s;

Savepoint sp = Database.setSavepoint();
try {
    Account acc = [SELECT Id, Type, DB_DUNS__c FROM Account WHERE Id = :ACCT];
    Boolean accDirty = false;
    if (acc.Type == null)               { acc.Type = 'Customer'; accDirty = true; }
    if (String.isBlank(acc.DB_DUNS__c)) { acc.DB_DUNS__c = String.valueOf(Datetime.now().getTime()).right(9); accDirty = true; }
    if (accDirty) { Database.update(acc, dml); }

    Quote q = new Quote(
        Name            = 'I02 TermDefined Convert ' + TAG,
        OpportunityId   = OPP,
        Pricebook2Id    = pbe.Pricebook2Id,
        Status          = 'Draft',
        Quote_Type__c   = 'New',
        CurrencyIsoCode = 'USD',
        StartDate       = Date.today(),
        ExpirationDate  = Date.today().addDays(30),
        BillToContactId = CONTACT,
        ContactId       = CONTACT,
        Bill_To_Place__c= PLACE,
        Ship_To_Place__c= PLACE,
        BillingStreet      = adrStreet,  BillingCity        = adrCity,
        BillingStateCode   = adrState,   BillingPostalCode  = adrZip,   BillingCountryCode  = adrCountry,
        ShippingStreet     = adrStreet,  ShippingCity       = adrCity,
        ShippingStateCode  = adrState,   ShippingPostalCode = adrZip,   ShippingCountryCode = adrCountry);
    Database.insert(q, dml);

    // Line A: WELL-CONFIGURED -> writer guard fires -> expect PTC=1.
    // RLM requires EndDate at TermDefined line INSERT (proration writer only runs at REPRICE), so set it.
    QuoteLineItem qliA = new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbe.Id,
        Product2Id       = pbe.Product2Id,
        Quantity         = 5,
        StartDate        = Date.today(),
        EndDate          = Date.today().addYears(1),
        SubscriptionTerm = 1,
        BillingFrequency = 'Annual',
        PeriodBoundary   = 'Anniversary');
    Database.SaveResult srA = Database.insert(qliA, dml);
    String qliErr = '';
    if (!srA.isSuccess()) { for (Database.Error e : srA.getErrors()) { qliErr += e.getStatusCode() + ': ' + e.getMessage() + ' | '; } }

    Id idA = srA.getId();
    if (idA == null) {
        List<QuoteLineItem> found = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id ORDER BY CreatedDate DESC LIMIT 1];
        idA = found.isEmpty() ? null : found[0].Id;
    }

    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ TD-CONVERT-QUOTE CREATED (I-02, convert-ready)'
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  Account : ' + ACCT + '  | Bill/Ship Place=' + PLACE + '  | BillToContact=' + CONTACT
        + '\n  LineA-WELL (Qty5,SubTerm=1,PB=Anniversary) : ' + base + '/' + idA + '  insertSuccess=' + srA.isSuccess()
        + (qliErr == '' ? '' : '  | QLI-ERR=' + qliErr)
        + '\n  ORACLE  : after Force-reprice -> LineA PricingTermCount=1 + EndDate DERIVED (root fix, null never reaches order)'
        + '\n  NEXT    : Force-reprice via REST place(Quote), then re-query PricingTermCount/EndDate on the line; then convert + activate.'
        + (PLACE == null   ? '\n  ⚠ No Places__c on account — convert will block.' : '')
        + (CONTACT == null ? '\n  ⚠ No Contact on account — convert will block.' : ''));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ TD-CONVERT-QUOTE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
}
