// setupPowerConvertQuoteTestData.compact.apex
// Builds an SC-3447 "large-quantity Power" QUOTE test fixture in FortraUAT that is READY TO CONVERT:
// a fresh Draft Quote with a SINGLE high-quantity Power line (Solution_Group__c='Power', no
// Partition) and the convert-precondition fields populated (Start Date, Bill-To Contact, Bill/Ship
// Place + address text — all related to the Quote's Account).
//
// WHY: SC-3447 — Quote->Order convert used to CRASH (Apex CPU governor) on a high-qty Power line
// because PowerOrderSplittingService cloned ONE OrderItem per unit (qty 5000 -> 5000 lines). The P3
// fix gates the split on a genuine per-machine artifact (Partition / Hardware); a Power line with NO
// Partition is a seat/site-license count and now STAYS as a single Quantity=N OrderItem. This quote
// reproduces that case so you can convert it and confirm the line comes across as ONE line.
//
//   Opportunity (Quote hangs off it)  006WC00000RPVp3YAH   (Account derives from the Opp; reused from
//                                                           the SC-3441 fixture — has Places + Contact)
//   Power product + qty                auto-picked Power "Order Line Only" PBE; LARGE_QTY below
//
// TEST FLOW (the un-scriptable RLM steps are done by you in the UI after this runs):
//   1) Run this script            -> Draft Quote with a high-qty Power line, convert fields staged.
//   2) Open the Quote -> START SYNC (the convert requires the syncing quote).
//   3) REPRICE ALL (Transaction Line Editor) -> CalculationStatus = CompletedWithPricing.
//   4) Complete the Operations Checklist + set Status = Accepted.
//   5) CONVERT QUOTE TO ORDER -> confirm the Power line is ONE Quantity=N OrderItem (no split, no crash).
//
// CONVERT PRECONDITIONS handled here (same set as the SC-3441 fixture / sc3338 inventory + live VRs):
//   - Quote.StartDate set (-> Order.EffectiveDate, hard-required).
//   - BillToContactId + Bill/Ship Place + Billing/Shipping address TEXT, all RELATED TO THE ACCOUNT
//     (satisfies the Quote consistency VRs + the Bill/Ship -> Order carryover at convert).
//   - Account Type / D&B DUNS filled if blank.
//   The remaining gates (syncing, pricing complete, checklist, Accepted) are UI steps — see above.
//
// Atomic: savepoint rollback on any failure -> no orphan Quote/QuoteLineItem. On success the Quote is
// COMMITTED + openable.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupPowerConvertQuoteTestData.compact.apex
//       (NOTE: target FortraUAT, not the `uat` alias — that is 5sInfusion's org.)
// Output: grep the debug log for the "POWER-QUOTE" marker (logged at ERROR level).

// --- Config -----------------------------------------------------------------
Id OPP            = '006WC00000RPVp3YAH';   // Opportunity the Quote hangs off (Account derives from it)
Integer LARGE_QTY = 5000;                   // large seat/license count — would have been 4999 clones pre-P3
String  POWER_SPLIT_TYPE = 'Order Line Only'; // pick a Power product of this split type (no per-unit hardware)

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm');

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

// Account behind the Opportunity (Bill/Ship/Contact must all relate to it).
Opportunity oppRec = [SELECT Id, AccountId FROM Opportunity WHERE Id = :OPP];  // not 'opp' (case-insensitive collision with OPP)
Id ACCT = oppRec.AccountId;

// A high-qty-safe Power product + its active PBE. Solution_Group='Power' + the chosen split type, with
// NO partition on the line -> P3 keeps it as a single Quantity=N line. PARENT Pricebook2 must also be
// active (the "Standard Price Book" is inactive here; the live one is "Fortra Price Book").
PricebookEntry pbe = [SELECT Id, Pricebook2Id, Product2Id, Product2.Name, UnitPrice, CurrencyIsoCode
                      FROM PricebookEntry
                      WHERE Product2.Solution_Group__c = 'Power'
                        AND Product2.Power_Split_Type__c = :POWER_SPLIT_TYPE
                        AND IsActive = true AND Product2.IsActive = true AND Pricebook2.IsActive = true
                        AND CurrencyIsoCode = 'USD' AND UnitPrice > 0
                      LIMIT 1];

// Convert-precondition lookups — must be related to the Quote's Account (consistency VRs). Pull the
// Place's ADDRESS too: the custom "Convert Quote to Order" action requires the Quote's Billing/Shipping
// address TEXT fields populated (selecting the Place lookup alone is not enough under direct DML).
List<Places__c> places = [SELECT Id, Address__Street__s, Address__City__s, Address__StateCode__s,
                                 Address__PostalCode__s, Address__CountryCode__s
                          FROM Places__c WHERE Account__c = :ACCT LIMIT 1];
List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :ACCT LIMIT 1];
Places__c placeRec = places.isEmpty() ? null : places[0];
Id placeId   = placeRec == null ? null : placeRec.Id;
Id contactId = contacts.isEmpty() ? null : contacts[0].Id;
String adrStreet  = placeRec == null ? null : placeRec.Address__Street__s;
String adrCity    = placeRec == null ? null : placeRec.Address__City__s;
String adrState   = placeRec == null ? null : placeRec.Address__StateCode__s;   // State/Country PICKLISTS -> set *Code fields
String adrZip     = placeRec == null ? null : placeRec.Address__PostalCode__s;
String adrCountry = placeRec == null ? null : placeRec.Address__CountryCode__s;

Savepoint sp = Database.setSavepoint();
try {
    // --- Account required-fields-check: Type + D&B DUNS (only if blank) ------
    Account acc = [SELECT Id, Type, DB_DUNS__c FROM Account WHERE Id = :ACCT];
    Boolean accDirty = false;
    if (acc.Type == null)               { acc.Type = 'Customer'; accDirty = true; }
    if (String.isBlank(acc.DB_DUNS__c)) { acc.DB_DUNS__c = String.valueOf(Datetime.now().getTime()).right(9); accDirty = true; }
    if (accDirty) { Database.update(acc, dml); }

    // --- Draft New Quote (convert-precondition fields populated) -------------
    Quote q = new Quote(
        Name            = 'SC3447 Power Convert Quote ' + TAG,
        OpportunityId   = OPP,
        Pricebook2Id    = pbe.Pricebook2Id,
        Status          = 'Draft',
        Quote_Type__c   = 'New',
        CurrencyIsoCode = 'USD',
        StartDate       = Date.today(),                 // -> Order.EffectiveDate (hard-required)
        ExpirationDate  = Date.today().addDays(30),
        BillToContactId = contactId,                      // Bill To Contact (related to ACCT)
        ContactId       = contactId,                      // Quote Contact = Ship To Contact (required-fields-check)
        Bill_To_Place__c= placeId,                        // -> Order Bill_To_Account__c carryover
        Ship_To_Place__c= placeId,                        // -> Order Ship_To_Account__c carryover
        BillingStreet      = adrStreet,  BillingCity        = adrCity,
        BillingStateCode   = adrState,   BillingPostalCode  = adrZip,   BillingCountryCode  = adrCountry,
        ShippingStreet     = adrStreet,  ShippingCity       = adrCity,
        ShippingStateCode  = adrState,   ShippingPostalCode = adrZip,   ShippingCountryCode = adrCountry);
    Database.insert(q, dml);

    // --- The high-qty Power line (positive qty, NO Partition -> P3 keeps it one line) ---
    // NOTE: do NOT set EndDate / PeriodBoundary here. The Power products this script picks use a
    // ONE-TIME selling model, and createOrderFromQuote rejects EndDate on one-time products
    // ("You can't specify EndDate for one-time order products"). Term fields (EndDate/PeriodBoundary/
    // SubscriptionTerm) only apply to a SUBSCRIPTION/termed product — add them only in that case.
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbe.Id,
        Quantity         = LARGE_QTY,
        StartDate        = Date.today());
    Database.insert(qli, dml);

    QuoteLineItem r = [SELECT Id, Quote.Name, Product2.Name, Quantity, TotalPrice
                       FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ POWER-QUOTE CREATED (convert-ready)  ' + r.Quote.Name
        + '\n  Quote        : ' + base + '/' + q.Id
        + '\n  Account      : ' + ACCT + '  | Bill/Ship Place=' + placeId + '  | BillToContact=' + contactId
        + '\n  Power line   : ' + r.Product2.Name + '  | Qty ' + r.Quantity + '  (NO Partition -> P3 keeps it ONE line)'
        + '  | TotalPrice(now)=' + r.TotalPrice + '  (0 until repriced)'
        + '\n  CONVERT-READY: Quote Contact, Bill/Ship Place + Billing/Shipping address, Start Date,'
        + ' Account Type/DUNS all set.'
        + '\n  NEXT (UI)    : 1) START SYNC  2) REPRICE ALL  3) complete Operations Checklist + set Status=Accepted'
        + '\n                 4) CONVERT QUOTE TO ORDER -> confirm the Power line is ONE Quantity=' + r.Quantity
        + ' OrderItem (no split / no CPU crash). Pre-P3 this convert would have failed.'
        + (placeId == null ? '\n  ⚠ No Places__c on the account — Bill/Ship Place + address left blank (convert will block).' : '')
        + (contactId == null ? '\n  ⚠ No Contact on the account — Bill To/Quote Contact left blank (convert will block).' : ''));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ POWER-QUOTE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;   // non-zero CLI exit
}
