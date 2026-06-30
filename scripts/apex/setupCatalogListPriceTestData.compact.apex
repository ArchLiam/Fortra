// setupCatalogListPriceTestData.compact.apex
// A-01 (Pricing Source / Channel): builds a clean DIRECT (no-partner) NEW Quote with a single
// non-contracted, non-derived Cyber-brand Software line so V21 prices it straight from the
// catalog PricebookEntry list price (NOT from a prior transaction).
//
//   Account "Fortra, LLC - Test"        001WC00000XiZP4YAN  (used directly)
//   Opportunity "Wren - Test GS Quotes" 006WC00000OE0NKYA1  (used directly)
//   Product "Cobalt Strike"             01tWC00000DD2SlYAL  (Fortra_Product_Type__c=Software)
//   PBE (Fortra Price Book, USD)        01uWC000005wrqnYAA  (UnitPrice=20500, Pricebook2 active)
//   ProductSellingModel "Term Based - Annual" 0jPWC000000060b2AA (TermDefined — the only SM for
//                                         Cyber sw in UAT; A-01 is selling-model agnostic, the
//                                         list-price mechanism is what's under test)
//
// DIRECT scenario: NO PartnerAccountId, NO Partner_Pricing_Model__c -> Partner Discount steps are
// skipped, so the line nets straight off the PBE list price (no downstream discount). Qty=5, USD,
// IsContracted=null, no attributes -> ItemPricingSource != 'LastTransaction'.
//
// Atomic: savepoint rollback on any failure -> no orphan Contact/Place/Quote/QLI.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupCatalogListPriceTestData.compact.apex
//       (NOTE: target FortraUAT, not the `uat` alias.)
// Output: grep the debug log for the "A-01 FIXTURE" marker (logged at ERROR level).

// --- Existing records used directly -----------------------------------------
Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes"
// --- Source records to clone ------------------------------------------------
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place (address source)
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote (header defaults)
// --- Fixed config Ids -------------------------------------------------------
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
// --- A-01 catalog line ------------------------------------------------------
Id PROD = '01tWC00000DD2SlYAL';        // Cobalt Strike (Software)
Id PBE  = '01uWC000005wrqnYAA';        // PBE, USD, Fortra Price Book, UnitPrice=20500
Id PSM  = '0jPWC000000060b2AA';        // ProductSellingModel "Term Based - Annual"
Decimal QTY = 5;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ A-01 CatalogList ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c, Referral_Partner__c, Cross_Sale_Type__c FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;
PricebookEntry pbeRow = [SELECT Id, UnitPrice, Pricebook2Id FROM PricebookEntry WHERE Id = :PBE];

Savepoint sp = Database.setSavepoint();
try {
    // --- Contact ------------------------------------------------------------
    Contact c = ((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,
        Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,
        MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode
        FROM Contact WHERE Id = :SRC_CON]).clone(false, true, false, false);
    c.AccountId = ACCT;
    c.LastName  = LABEL;
    if (String.isBlank(c.Workday_Phone_Country_ISO_Code__c))       c.Workday_Phone_Country_ISO_Code__c = 'USA';
    if (String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c = 'USA';
    Database.insert(c, dml);

    // --- Place --------------------------------------------------------------
    Places__c srcPlace = [SELECT Address__Street__s,Address__City__s,Address__StateCode__s,
        Address__PostalCode__s,Address__CountryCode__s FROM Places__c WHERE Id = :SRC_PLC];
    Places__c p = new Places__c(Name = 'A-01 HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    // --- Quote: DIRECT, NEW (no partner / no partner pricing model) ---------
    Quote tq = [SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c FROM Quote WHERE Id = :TPL_Q];
    Quote q = new Quote(
        OpportunityId = OPP, Name = LABEL, Status = 'Draft', ExpirationDate = Date.today().addDays(30),
        StartDate = Date.today(),
        Pricebook2Id = PB, CurrencyIsoCode = 'USD', Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = netTerms,
        Language__c = tq.Language__c != null ? tq.Language__c : 'English',
        Deal_Type__c = dealType,
        Show_Hide_Discounts__c = 'Show',
        Header_Discount_Type__c   = tq.Header_Discount_Type__c   != null ? tq.Header_Discount_Type__c   : 'Amount',
        Payment_Portal__c         = tq.Payment_Portal__c         != null ? tq.Payment_Portal__c         : 'Fortra (default)',
        Disable_Export_Control__c = tq.Disable_Export_Control__c != null ? tq.Disable_Export_Control__c : false,
        Ship_To_Place__c = p.Id, Bill_To_Place__c = p.Id,
        BillingStreet = p.Address__Street__s, BillingCity = p.Address__City__s, BillingStateCode = p.Address__StateCode__s,
        BillingPostalCode = p.Address__PostalCode__s, BillingCountryCode = p.Address__CountryCode__s,
        ShippingStreet = p.Address__Street__s, ShippingCity = p.Address__City__s, ShippingStateCode = p.Address__StateCode__s,
        ShippingPostalCode = p.Address__PostalCode__s, ShippingCountryCode = p.Address__CountryCode__s);
    Database.insert(q, dml);

    // --- Catalog line: Cobalt Strike, Qty=5, no attributes, non-contracted --
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId               = q.Id,
        PricebookEntryId      = PBE,
        Product2Id            = PROD,
        Quantity              = QTY,
        BillingFrequency      = 'Annual',   // required: SellingModelType=TermDefined
        StartDate             = Date.today(),
        EndDate               = Date.today().addYears(1));
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    QuoteLineItem r = [SELECT Id, Quantity, UnitPrice, NetUnitPrice, TotalPrice, NetTotalPrice, Subtotal FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ A-01 FIXTURE CREATED  Quote #' + q.QuoteNumber
        + '\n  Account : ' + base + '/' + ACCT
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QLI     : ' + base + '/' + r.Id
        + '\n  QuoteId=' + q.Id + ' | QLIId=' + r.Id
        + '\n  PBE list UnitPrice=' + pbeRow.UnitPrice + ' | Qty=' + r.Quantity
        + '\n  Pre-reprice  Unit=' + r.UnitPrice + ' Net=' + r.NetUnitPrice + ' Total=' + r.TotalPrice + ' NetTotal=' + r.NetTotalPrice + ' Subtotal=' + r.Subtotal
        + '\n  EXPECT post-Force-reprice: NetUnitPrice=' + pbeRow.UnitPrice + ', NetTotalPrice=' + (pbeRow.UnitPrice * QTY));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ A-01 FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage()
        + ' | stack: ' + e.getStackTraceString());
    throw e;
}
