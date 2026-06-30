// setupDirectFortraOriginatedQuoteTestData.compact.apex
// E-01: Direct sale - no partner discount (Fortra Originated).
// Builds a DIRECT Fortra-Originated quote (NO partner account, NO partner pricing
// model) with a single Cyber-software Perpetual line, Qty=5, on the standing test
// Account "Fortra, LLC - Test" 001WC00000XiZP4YAN + Opp 006WC00000OE0NKYA1.
// Cloned-from-known-good Contact + Place so required/custom fields are populated.
// Atomic: any failure rolls back via savepoint.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupDirectFortraOriginatedQuoteTestData.compact.apex
// Output: grep the debug log for the "FIXTURE" marker (ERROR level).

Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes"
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote (header defaults)
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book, active)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
// E-01 line: CCM Management Server, Perpetual/OneTime, list $34750 (known-good
// standalone SKU that prices to list in existing direct quote 00781194).
Id PBE  = '01uWC000005wrxMYAQ';
Id PROD = '01tWC00000DD16MYAT';
Id PSM  = '0jPWC00000005yz2AA';        // OneTime selling model
Decimal QTY = 5;
Decimal LISTUP = 34750;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));
String LABEL = 'LJ E-01 Direct Fortra Originated ' + TAG;

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
    Places__c p = new Places__c(Name = 'E01 HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    Quote tq = [SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c
        FROM Quote WHERE Id = :TPL_Q];
    // DIRECT deal: NO PartnerAccountId, NO Billing_Partner__c, NO Partner_Pricing_Model__c.
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
    System.debug(LoggingLevel.ERROR, 'FIXTURE CREATED E-01  Quote #' + q.QuoteNumber
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
