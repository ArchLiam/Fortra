// setupColaUatTestData.compact.apex
// Builds a COLA/DPP test fixture in FortraUAT on the standing test records:
//   Account "Fortra, LLC - Test"      001WC00000XiZP4YAN  (used directly)
//   Opportunity "Wren - Test GS Quotes" 006WC00000OE0NKYA1 (used directly)
// and creates a fresh Contact -> Place -> Quote hung off them. The Account and
// Opportunity are NOT created or modified — the fixture only references them.
// The Contact/Place are cloned from known-good source records so every
// required + custom field is populated.
//
// Atomic: any failure rolls the newly-created records back via a savepoint,
// so a partial run never leaves orphan Contacts/Places/Quotes behind.
// Compact form: read from file (not inlined) to avoid HTTP 431 on large payloads.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupColaUatTestData.compact.apex
//       (NOTE: target FortraUAT, not the `uat` alias — that is 5sInfusion's org.)
// Output: grep the debug log for the "FIXTURE" marker (logged at ERROR level).

// --- Existing records used directly (not cloned) ----------------------------
Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes" (on the account above)
// --- Source records to clone (UAT 18-char Ids) ------------------------------
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place (address source)
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote (header defaults)
// --- Fixed config Ids -------------------------------------------------------
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PART = '001WC00000ZtazZYAR';        // Partner Account

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm');
String LABEL = 'LJ Cancellation Test ' + TAG;

// Bypass duplicate rules consistently on every insert below.
Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

// Read (don't modify) the existing account + opportunity for the values the Quote needs.
// NB: local names differ from the ACCT/OPP Id constants — Apex identifiers are
// case-insensitive, so `acct`/`opp` would collide with `ACCT`/`OPP`.
Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c, Referral_Partner__c, Cross_Sale_Type__c
    FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;

Savepoint sp = Database.setSavepoint();
try {
    // --- Contact (under the existing account) -------------------------------
    Contact c = ((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,
        Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,
        MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode
        FROM Contact WHERE Id = :SRC_CON]).clone(false, true, false, false);
    c.AccountId = ACCT;
    c.LastName  = LABEL;
    if (String.isBlank(c.Workday_Phone_Country_ISO_Code__c))       c.Workday_Phone_Country_ISO_Code__c = 'USA';
    if (String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c = 'USA';
    Database.insert(c, dml);

    // --- Place (cloned address, under the existing account) -----------------
    Places__c srcPlace = [SELECT Address__Street__s,Address__City__s,Address__StateCode__s,
        Address__PostalCode__s,Address__CountryCode__s FROM Places__c WHERE Id = :SRC_PLC];
    Places__c p = new Places__c(Name = 'DPP HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    // --- Quote (on the existing opportunity + account) ----------------------
    Quote tq = [SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c
        FROM Quote WHERE Id = :TPL_Q];
    Quote q = new Quote(
        OpportunityId = OPP, Name = LABEL, Status = 'Draft', ExpirationDate = Date.today().addDays(30),
        Pricebook2Id = PB, CurrencyIsoCode = 'USD', Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = netTerms,
        Language__c = tq.Language__c != null ? tq.Language__c : 'English',
        Deal_Type__c = dealType, PartnerAccountId = PART, Billing_Partner__c = PART,
        Referral_Partner__c = oppRow.Referral_Partner__c, Cross_Sale_Type__c = oppRow.Cross_Sale_Type__c,
        Partner_Pricing_Model__c = 'Discount', Show_Hide_Discounts__c = 'Show',
        Header_Discount_Type__c   = tq.Header_Discount_Type__c   != null ? tq.Header_Discount_Type__c   : 'Amount',
        Payment_Portal__c         = tq.Payment_Portal__c         != null ? tq.Payment_Portal__c         : 'Fortra (default)',
        Disable_Export_Control__c = tq.Disable_Export_Control__c != null ? tq.Disable_Export_Control__c : false,
        Ship_To_Place__c = p.Id, Bill_To_Place__c = p.Id,
        BillingStreet = p.Address__Street__s, BillingCity = p.Address__City__s, BillingStateCode = p.Address__StateCode__s,
        BillingPostalCode = p.Address__PostalCode__s, BillingCountryCode = p.Address__CountryCode__s,
        ShippingStreet = p.Address__Street__s, ShippingCity = p.Address__City__s, ShippingStateCode = p.Address__StateCode__s,
        ShippingPostalCode = p.Address__PostalCode__s, ShippingCountryCode = p.Address__CountryCode__s);
    Database.insert(q, dml);
    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];

    // --- Summary (clickable record links) -----------------------------------
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ FIXTURE CREATED  Quote #' + q.QuoteNumber
        + '\n  Account : ' + base + '/' + ACCT  + '  (Fortra, LLC - Test, existing)'
        + '\n  Opp     : ' + base + '/' + OPP   + '  (Wren - Test GS Quotes, existing)'
        + '\n  Contact : ' + base + '/' + c.Id
        + '\n  Place   : ' + base + '/' + p.Id
        + '\n  Quote   : ' + base + '/' + q.Id);
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;   // non-zero CLI exit
}
