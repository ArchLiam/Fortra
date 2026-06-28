// setupCancelQuoteTestData.compact.apex
// Builds an SC-3441 cancellation-QUOTE test fixture in FortraUAT that is READY TO CONVERT:
// a fresh Draft "Cancellation" Quote with a single Quantity = -1 cancellation line tied to an
// existing asset, the SC-3441 staging field CancelNetUnitPrice__c pre-populated from the asset's
// original NET, and the convert-precondition fields populated (Start Date, Bill-To Contact,
// Bill/Ship Place — all related to the Quote's Account).
//
//   Opportunity (Quote hangs off it)  006WC00000RPVp3YAH   (Account derives from the Opp)
//   Asset (configurable below)        02iWC000006Z5e5YAC   (must have a positive Generate net)
//
// WHAT IT PROVES / TEST FLOW:
//   1) Run this script  -> Draft Cancellation Quote staged (TotalPrice still 0 until repriced).
//   2) Open the Quote, click REPRICE ALL  -> the SC-3441 POSTHOOK (CancelLineCreditPosthook,
//      a POST section on the Fortra_Pricing_PreHook plan) reads CancelNetUnitPrice__c and writes
//      the QLI field-API attributes so TotalPrice / NetTotalPrice / Subtotal go NEGATIVE (net*qty).
//   3) Click CONVERT QUOTE TO ORDER  -> the negative carries to the Order (verify, then Workday).
//
// CONVERT PRECONDITIONS handled here (from the sc3338 inventory + live Quote VRs):
//   - Quote.StartDate set            (-> Order.EffectiveDate, which is nillable=false / hard-required)
//   - BillToContactId + Bill/Ship Place set, all RELATED TO THE ACCOUNT (satisfies the two active
//     Quote consistency VRs Quote_BillToContactAcct_Equal_QuoteAcct / Quote_BillToPlacceAcct_Equal_QuoteAcct
//     and feeds the Bill/Ship -> Order account carryover at convert).
//   - The remaining "Order Complete" required fields (Account DB_DUNS__c / Type / Phone, Contact
//     Workday mobile attrs) are enforced LATER on the Order, not at convert — see notes in output.
//
// SOURCE OF THE CREDIT = the custom field CancelNetUnitPrice__c (NOT QuoteLineDetail — the QLD is 0
// in this org). The script resolves the asset's Generate/Initial-Sale net; falls back to list price.
//
// Atomic: savepoint rollback on any failure -> no orphan Quote/QuoteAction/QuoteLineItem. On success
// the Quote is COMMITTED + openable.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupCancelQuoteTestData.compact.apex
//       (NOTE: target FortraUAT, not the `uat` alias — that is 5sInfusion's org.)
// Output: grep the debug log for the "CANCEL-QUOTE" marker (logged at ERROR level).

// --- Config -----------------------------------------------------------------
Id OPP   = '006WC00000RPVp3YAH';     // Opportunity the Quote hangs off (Account derives from it)
Id ASSET = '02iWC000006Z5e5YAC';     // asset to cancel — MUST have a positive Generate net

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm');

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

// Account behind the Opportunity (Bill/Ship/Contact must all relate to it).
Opportunity oppRec = [SELECT Id, AccountId FROM Opportunity WHERE Id = :OPP];  // note: Apex is case-insensitive, so this var must not be named 'opp' (collides with OPP)
Id ACCT = oppRec.AccountId;

// Product + active price book entry from the asset (QLI needs a PBE; Quote sits on that Pricebook2).
// IMPORTANT: PricebookEntry.IsActive=true is NOT enough — the PARENT Pricebook2 must also be active,
// or the quote can't be synced/repriced ("inactive or archived price book"). The "Standard Price
// Book" is INACTIVE here; the live one is "Fortra Price Book". Filter on Pricebook2.IsActive=true.
Asset ast = [SELECT Id, Product2Id, CurrencyIsoCode FROM Asset WHERE Id = :ASSET];
PricebookEntry pbe = [SELECT Id, Pricebook2Id, UnitPrice FROM PricebookEntry
                      WHERE Product2Id = :ast.Product2Id AND IsActive = true
                        AND Pricebook2.IsActive = true LIMIT 1];

// Convert-precondition lookups — must be related to the Quote's Account (consistency VRs).
// Pull the Place's ADDRESS too: the custom "Convert Quote to Order" action requires the Quote's
// Billing/Shipping address TEXT fields to be populated (selecting a Bill To Place lookup is NOT
// enough — the UI normally copies the Place address onto the Quote; direct DML must do it here).
List<Places__c> places = [SELECT Id, Address__Street__s, Address__City__s, Address__StateCode__s,
                                 Address__PostalCode__s, Address__CountryCode__s
                          FROM Places__c WHERE Account__c = :ACCT LIMIT 1];
List<Contact>  contacts = [SELECT Id FROM Contact WHERE AccountId = :ACCT LIMIT 1];
Places__c place = places.isEmpty() ? null : places[0];
Id PLACE   = place == null ? null : place.Id;
Id CONTACT = contacts.isEmpty() ? null : contacts[0].Id;
// Null-safe address components copied to both Billing and Shipping on the Quote.
String adrStreet  = place == null ? null : place.Address__Street__s;
String adrCity    = place == null ? null : place.Address__City__s;
String adrState   = place == null ? null : place.Address__StateCode__s;     // State/Country PICKLISTS -> set the *Code fields
String adrZip     = place == null ? null : place.Address__PostalCode__s;
String adrCountry = place == null ? null : place.Address__CountryCode__s;

// Asset NET to seed CancelNetUnitPrice__c: prefer a Generate/Initial-Sale row (currency-matched,
// positive); else most-recent positive priced source; else the catalog list price (lossy).
Decimal cancelNet;
Boolean gotGenerate = false;
for (AssetActionSource s : [SELECT NetUnitPrice, AssetAction.Type FROM AssetActionSource
                            WHERE AssetAction.AssetId = :ASSET AND NetUnitPrice > 0
                              AND CurrencyIsoCode = :ast.CurrencyIsoCode
                            ORDER BY CreatedDate ASC]) {
    if (gotGenerate) { break; }
    cancelNet = s.NetUnitPrice;
    if (s.AssetAction.Type == 'Generate') { gotGenerate = true; }
}
if (cancelNet == null || cancelNet <= 0) { cancelNet = pbe.UnitPrice; }

Savepoint sp = Database.setSavepoint();
try {
    // --- Account required-fields-check: Type + D&B DUNS (only if blank) ------
    // DB_DUNS__c is a UNIQUE field, so generate a unique 9-digit value; only write when blank
    // so re-runs don't collide. Account Phone is assumed already set.
    Account acc = [SELECT Id, Type, DB_DUNS__c FROM Account WHERE Id = :ACCT];
    Boolean accDirty = false;
    if (acc.Type == null)                  { acc.Type = 'Customer'; accDirty = true; }
    if (String.isBlank(acc.DB_DUNS__c))    { acc.DB_DUNS__c = String.valueOf(Datetime.now().getTime()).right(9); accDirty = true; }
    if (accDirty) { Database.update(acc, dml); }

    // --- Draft Cancellation Quote (convert-precondition fields populated) ----
    Quote q = new Quote(
        Name            = 'SC3441 Cancel Quote ' + TAG,
        OpportunityId   = OPP,
        Pricebook2Id    = pbe.Pricebook2Id,
        Status          = 'Draft',
        Quote_Type__c   = 'Cancellation',
        CurrencyIsoCode = 'USD',
        StartDate       = Date.today(),                 // -> Order.EffectiveDate (hard-required)
        ExpirationDate  = Date.today().addDays(30),
        BillToContactId = CONTACT,                      // Bill To Contact (related to ACCT)
        ContactId       = CONTACT,                      // Quote Contact = Ship To Contact (required-fields-check)
        Bill_To_Place__c= PLACE,                        // -> Order Bill_To_Account__c carryover
        Ship_To_Place__c= PLACE,                        // -> Order Ship_To_Account__c carryover
        // Address TEXT copied from the Place (required by Convert Quote to Order). State/Country
        // are picklists here, so set the *Code fields; BillingState/BillingCountry auto-derive.
        BillingStreet      = adrStreet,  BillingCity        = adrCity,
        BillingStateCode   = adrState,   BillingPostalCode  = adrZip,   BillingCountryCode  = adrCountry,
        ShippingStreet     = adrStreet,  ShippingCity       = adrCity,
        ShippingStateCode  = adrState,   ShippingPostalCode = adrZip,   ShippingCountryCode = adrCountry);
    Database.insert(q, dml);

    // --- QuoteAction carrying the SourceAsset (Cancel) ----------------------
    QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = 'Cancel', SourceAssetId = ASSET);
    Database.insert(qa, dml);

    // --- Cancellation line: Quantity -1, CancelNetUnitPrice__c staged for the posthook ---
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId               = q.Id,
        QuoteActionId         = qa.Id,
        PricebookEntryId      = pbe.Id,
        Quantity              = -1,
        StartQuantity         = 1,
        CancelNetUnitPrice__c = cancelNet,
        PeriodBoundary        = 'Anniversary',          // required by Convert ("Period Boundary"); dominant value here
        StartDate             = Date.today(),
        EndDate               = Date.today().addYears(1));
    Database.insert(qli, dml);

    QuoteLineItem r = [SELECT Id, Quote.Name, Quantity, CancelNetUnitPrice__c, TotalPrice
                       FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ CANCEL-QUOTE CREATED (convert-ready)  ' + r.Quote.Name
        + '\n  Quote        : ' + base + '/' + q.Id
        + '\n  Account      : ' + ACCT + '  | Bill/Ship Place=' + PLACE + '  | BillToContact=' + CONTACT
        + '\n  Cancel line  : Qty ' + r.Quantity + '  | CancelNetUnitPrice__c=' + r.CancelNetUnitPrice__c
        + '  | TotalPrice(now)=' + r.TotalPrice + '  (0 until repriced)'
        + '\n  CONVERT-READY: Quote Contact, Bill/Ship Place + Billing/Shipping address, Start Date,'
        + ' Account Type/DUNS all set (Required Fields Check should pass).'
        + '\n  NEXT         : 1) REPRICE ALL  -> posthook sets TotalPrice = ' + (cancelNet * -1) + ' (net*qty)'
        + '\n                 2) Required Fields Check (should be all green) -> 3) CONVERT QUOTE TO ORDER'
        + '\n                 -> verify the negative carries to the Order, then Workday.'
        + (PLACE == null ? '\n  ⚠ No Places__c on the account — Bill/Ship Place + address left blank (convert will block).' : '')
        + (CONTACT == null ? '\n  ⚠ No Contact on the account — Bill To/Quote Contact left blank (convert will block).' : ''));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ CANCEL-QUOTE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;   // non-zero CLI exit
}
