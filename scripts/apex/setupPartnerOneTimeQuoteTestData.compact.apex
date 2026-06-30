// setupPartnerOneTimeQuoteTestData.compact.apex   (E-03 fixture)
// Builds a Channel-Originated, Discount-model PARTNER quote with a single
// One-Time/Perpetual line (CCM Limited Scan Engine, list 2008) on the standing
// test Account "Fortra, LLC - Test" 001WC00000XiZP4YAN.
//
// Purpose: validate V21 scenario E-03 (SC-3359) — partner discount % must be
// applied to the FINAL net of a One-Time/Perpetual line and NOT overwritten by
// the One-Time SubscriptionPricing branch. Partner "AB Test Partner Account"
// (Software_Percent__c = 15%) -> expected NetUnitPrice = 2008 * 0.85 = 1706.8.
//
// Atomic: savepoint rollback on any failure -> no orphan Contact/Place/Quote/QLI.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupPartnerOneTimeQuoteTestData.compact.apex
// Output: grep the debug log for the "E-03 FIXTURE" marker (logged at ERROR level).

// --- Existing records used directly (not cloned) ----------------------------
Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes" (on the account above)
Id PART = '001WC00000ZtazZYAR';        // Partner Account "AB Test Partner Account" (Software_Percent__c=15)
// --- Source records to clone (UAT 18-char Ids) ------------------------------
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place (address source)
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote (header defaults)
// --- Fixed config Ids -------------------------------------------------------
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PBE_CCM = '01uWC000005wrxKYAQ';     // PBE: CCM Limited Scan Engine Perpetual, Fortra Price Book, OneTime, UnitPrice 2008

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));
String LABEL = 'LJ E-03 Partner OneTime ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;

// Confirm the PBE parent pricebook is active and grab the list price.
PricebookEntry pbe = [SELECT Id, Pricebook2Id, UnitPrice, Product2Id, ProductSellingModelId, Pricebook2.IsActive
                      FROM PricebookEntry WHERE Id = :PBE_CCM];

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
    Places__c p = new Places__c(Name = 'E-03 HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    // --- Quote: Channel-Originated PARTNER, Discount model ------------------
    Quote tq = [SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c
        FROM Quote WHERE Id = :TPL_Q];
    Quote q = new Quote(
        OpportunityId = OPP, Name = LABEL, Status = 'Draft', ExpirationDate = Date.today().addDays(30),
        Pricebook2Id = PB, CurrencyIsoCode = 'USD', Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = netTerms,
        Language__c = tq.Language__c != null ? tq.Language__c : 'English',
        Deal_Type__c = 'Channel Originated', PartnerAccountId = PART, Billing_Partner__c = PART,
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

    // --- One-Time / Perpetual line: CCM Limited Scan Engine, list 2008 ------
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbe.Id,
        Product2Id       = pbe.Product2Id,
        Quantity         = 1,
        UnitPrice        = pbe.UnitPrice,
        StartDate        = Date.today());
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ E-03 FIXTURE CREATED  Quote #' + q.QuoteNumber
        + '  (Channel Originated / Discount / partner AB Test 15% SW)'
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QLI     : ' + base + '/' + qli.Id + '  (CCM Limited Scan Engine Perpetual, list ' + pbe.UnitPrice + ', qty 1)'
        + '\n  Account : ' + base + '/' + ACCT
        + '\n  Contact : ' + base + '/' + c.Id
        + '\n  Place   : ' + base + '/' + p.Id
        + '\n  EXPECT after Force-reprice: NetUnitPrice = 1706.8 ( = 2008 * (1 - 0.15) ), NetTotalPrice 1706.8');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ E-03 FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
