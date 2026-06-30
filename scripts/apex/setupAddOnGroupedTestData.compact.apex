// setupAddOnGroupedTestData.compact.apex
// C-06 (Product Type / Add-on modular feature priced separately but grouped):
// builds a clean DIRECT (no-partner) NEW USD subscription Quote holding TWO lines in the SAME quote:
//   (1) base    GoAnywhere Enterprise Bundle (Subscription)  01tWC00000DD1N9YAL  list 121141
//   (2) add-on  GoAnywhere Advanced Workflows (Subscription) 01tWC00000DD1M6YAL  list 5497.25
// Both TermDefined annual, USD, Fortra Price Book. Tests that the add-on is priced separately and
// ADDITIVELY (own list) alongside the base, with NO bundle override — because the single
// BundleBasedAdjustment override row in the org targets (Data Detection Engine / DCS Essentials
// Bundle), NOT this GoAnywhere pair, so V21 step 25 "Bundle Based Adjustment Entries" returns no
// adjustment and each line nets its catalog list.
//
//   Account "Fortra, LLC - Test"        001WC00000XiZP4YAN
//   Opportunity "Wren - Test GS Quotes" 006WC00000OE0NKYA1
//   Base PBE (USD,Fortra book)          01uWC000005ws3dYAA  (UnitPrice=121141)
//   Add-on PBE (USD,Fortra book)        01uWC000005ws33YAA  (UnitPrice=5497.25)
//   ProductSellingModel annual          0jPWC000000060b2AA  (TermDefined)
//
// NetUnitPrice is SEEDED = list on each line to neutralise the documented headless Apex-insert
// net-$0 artifact (the place API does not hydrate list->net on Apex-inserted lines the way the UI
// Add-Product path does). Force-reprice then proves V21 keeps each line at its own list additively.
//
// Atomic: savepoint rollback on any failure.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupAddOnGroupedTestData.compact.apex
// Output: grep the debug log for the "C-06 FIXTURE" marker (ERROR level).

Id ACCT = '001WC00000XiZP4YAN';
Id OPP  = '006WC00000OE0NKYA1';
Id SRC_CON = '003WC00000nb7khYAA';
Id SRC_PLC = 'a0lWC000004cO79YAE';
Id TPL_Q   = '0Q0WC0000024KOn0AM';
Id PB   = '01sWC0000022GHFYA2';
Id LE   = '0fwWC000000034LYAQ';
Id STT  = '1ChWC0000002eJ70AI';

Id BASE_PROD = '01tWC00000DD1N9YAL';   // GoAnywhere Enterprise Bundle (Subscription)
Id BASE_PBE  = '01uWC000005ws3dYAA';   // USD Fortra book, list 121141
Id ADDON_PROD= '01tWC00000DD1M6YAL';   // GoAnywhere Advanced Workflows (Subscription)
Id ADDON_PBE = '01uWC000005ws33YAA';   // USD Fortra book, list 5497.25
Id PSM = '0jPWC000000060b2AA';         // Term Based - Annual (TermDefined)

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ C-06 AddOnGrouped ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;
PricebookEntry basePbe  = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Id = :BASE_PBE];
PricebookEntry addonPbe = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Id = :ADDON_PBE];

Savepoint sp = Database.setSavepoint();
try {
    Contact c = ((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,
        Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,
        MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode
        FROM Contact WHERE Id = :SRC_CON]).clone(false, true, false, false);
    c.AccountId = ACCT;
    c.LastName  = LABEL;
    if (String.isBlank(c.Workday_Phone_Country_ISO_Code__c))       c.Workday_Phone_Country_ISO_Code__c = 'USA';
    if (String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c = 'USA';
    Database.insert(c, dml);

    Places__c srcPlace = [SELECT Address__Street__s,Address__City__s,Address__StateCode__s,
        Address__PostalCode__s,Address__CountryCode__s FROM Places__c WHERE Id = :SRC_PLC];
    Places__c p = new Places__c(Name = 'C-06 HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

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

    List<QuoteLineItem> lines = new List<QuoteLineItem>();
    QuoteLineItem baseLine = new QuoteLineItem(
        QuoteId = q.Id, PricebookEntryId = BASE_PBE, Product2Id = BASE_PROD, Quantity = 1,
        UnitPrice = basePbe.UnitPrice,
        BillingFrequency = 'Annual', StartDate = Date.today(), EndDate = Date.today().addYears(1));
    QuoteLineItem addonLine = new QuoteLineItem(
        QuoteId = q.Id, PricebookEntryId = ADDON_PBE, Product2Id = ADDON_PROD, Quantity = 1,
        UnitPrice = addonPbe.UnitPrice,
        BillingFrequency = 'Annual', StartDate = Date.today(), EndDate = Date.today().addYears(1));
    lines.add(baseLine);
    lines.add(addonLine);
    Database.insert(lines, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ C-06 FIXTURE CREATED  Quote #' + q.QuoteNumber
        + '\n  Account : ' + base + '/' + ACCT
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  BaseQLI : ' + base + '/' + baseLine.Id + '  (GoAnywhere Enterprise Bundle, list=' + basePbe.UnitPrice + ')'
        + '\n  AddOnQLI: ' + base + '/' + addonLine.Id + '  (GoAnywhere Advanced Workflows, list=' + addonPbe.UnitPrice + ')'
        + '\n  QuoteId=' + q.Id + ' | BaseQLIId=' + baseLine.Id + ' | AddOnQLIId=' + addonLine.Id
        + '\n  EXPECT post-Force-reprice (no bundle override for this pair): base Net=' + basePbe.UnitPrice
        + ', add-on Net=' + addonPbe.UnitPrice + ' (additive, each = own list)');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ C-06 FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage()
        + ' | stack: ' + e.getStackTraceString());
    throw e;
}
