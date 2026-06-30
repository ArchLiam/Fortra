// setupOneTimeNoProrationTestData.compact.apex
// B-08: One-Time/Perpetual line (SellingModelType neither Evergreen nor TermDefined)
// excluded from BOTH proration line filters -> one-time treatment (no proration).
// Builds a DIRECT Fortra-Originated quote with a single Abstract Perpetual line,
// PSM "One Time" / SMT=OneTime, Qty=3, list $2200 (UI-priced to NUP 2200 on the
// known-good B-01 control quote 0Q0WC000003FN970AG). Standing Account
// "Fortra, LLC - Test" 001WC00000XiZP4YAN + Opp 006WC00000OE0NKYA1.
// Cloned-from-known-good Contact + Place so required/custom fields are populated.
// Atomic: any failure rolls back via savepoint.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupOneTimeNoProrationTestData.compact.apex
// Output: grep the debug log for the "FIXTURE" marker (ERROR level).

Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes"
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote (header defaults)
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book, active)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
// B-08 line: Abstract, Perpetual / PSM "One Time" (SMT=OneTime), list $2200.
Id PBE  = '01uWC000005wrr9YAA';        // Abstract USD PBE, Fortra Price Book, active
Id PROD = '01tWC00000DD11EYAT';        // Abstract (Perpetual)
Id PSM  = '0jPWC00000005yz2AA';        // One Time selling model (SMT=OneTime)
Decimal QTY = 3;
Decimal LISTUP = 2200;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));
String LABEL = 'LJ B-08 OneTime NoProration ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;

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
    Places__c p = new Places__c(Name = 'B08 HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    Quote tq = [SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c
        FROM Quote WHERE Id = :TPL_Q];
    Quote q = new Quote(
        OpportunityId = OPP, Name = LABEL, Status = 'Draft', ExpirationDate = Date.today().addDays(30),
        Pricebook2Id = PB, CurrencyIsoCode = 'USD', Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = netTerms,
        Language__c = tq.Language__c != null ? tq.Language__c : 'English',
        Deal_Type__c = 'Fortra Originated',
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

    QuoteLineItem qli = new QuoteLineItem(
        QuoteId = q.Id, PricebookEntryId = PBE, Product2Id = PROD,
        Quantity = QTY, UnitPrice = LISTUP);
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, 'FIXTURE CREATED B-08  Quote #' + q.QuoteNumber
        + '\n  Account : ' + base + '/' + ACCT
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QuoteId=' + q.Id
        + '\n  QLI     : ' + base + '/' + qli.Id
        + '\n  QLIId='  + qli.Id);
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
