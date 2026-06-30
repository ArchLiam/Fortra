// setupCurrencyEurCatalogTestData.compact.apex
// G-01 (Multi-Currency / Regional): builds a clean DIRECT (no-partner) NEW EUR Quote with a single
// non-contracted, non-derived, non-attribute Software/Subscription line so the ONLY mechanism under
// test is the V21 "Currency Conversion - Net Total / Subtotal / Net Unit Price / Total Line Amount /
// Unit Price Display" steps (nested IF on STICurrencyIsoCode) over a currency-matched EUR PBE.
//
//   Account "Fortra, LLC - Test"        001WC00000XiZP4YAN  (used directly)
//   Opportunity "Wren - Test GS Quotes" 006WC00000OE0NKYA1  (used directly)
//   Product "Cobalt Strike"             01tWC00000DD2SlYAL  (Fortra_Product_Type__c=Software)
//   PBE (Fortra Price Book, EUR)        01uWC000005wywxYAA  (UnitPrice=19159.30 = USD 20500 x 0.9346)
//   USD reference PBE                   01uWC000005wrqnYAA  (UnitPrice=20500)
//   ProductSellingModel "Term Based - Annual" 0jPWC000000060b2AA
//
// DIRECT scenario: NO PartnerAccountId, NO Partner_Pricing_Model__c -> Partner Discount steps skipped,
// line nets straight off the EUR PBE list price (no downstream discount). Qty=2, EUR, IsContracted=null,
// no attributes -> ItemPricingSource != 'LastTransaction'.
//
// EXPECTED post-Force-reprice (G-01 PASS):
//   UnitPrice     = 19159.30  (EUR PBE list, currency-matched, NOT 20500 USD, NOT double-applied 17906.28)
//   NetUnitPrice  = 19159.30  (direct, no discount)
//   NetTotalPrice = 38318.60  (19159.30 x 2)
//   Subtotal      = 38318.60
//
// Atomic: savepoint rollback on any failure.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupCurrencyEurCatalogTestData.compact.apex
// Output: grep the debug log for the "G-01 FIXTURE" marker (logged at ERROR level).

Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000QnybxYAB';        // "Wren - Test Currencies" (EUR Opp -> Quote inherits EUR)
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PROD = '01tWC00000DD2SlYAL';        // Cobalt Strike (Software)
Id PBE  = '01uWC000005wywxYAA';        // PBE, EUR, Fortra Price Book, UnitPrice=19159.30
Id PBE_USD = '01uWC000005wrqnYAA';     // USD reference PBE, UnitPrice=20500
String CUR = 'EUR';
Decimal MULT = 0.9346;                 // authoritative EUR multiplier
Decimal QTY = 2;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ G-01 CurrEUR ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;
PricebookEntry pbeEur = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Id = :PBE];
PricebookEntry pbeUsd = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Id = :PBE_USD];

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
    Places__c p = new Places__c(Name = 'G-01 HQ ' + TAG, Account__c = ACCT,
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
        Pricebook2Id = PB, CurrencyIsoCode = CUR, Quote_Type__c = 'New', LegalEntityId = LE,
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
    Quote qChk = [SELECT Id, CurrencyIsoCode, Pricebook2Id FROM Quote WHERE Id = :q.Id];
    System.debug(LoggingLevel.ERROR, 'G-01 Quote actual currency=' + qChk.CurrencyIsoCode + ' pb=' + qChk.Pricebook2Id);

    QuoteLineItem qli = new QuoteLineItem(
        QuoteId               = q.Id,
        PricebookEntryId      = PBE,
        Product2Id            = PROD,
        Quantity              = QTY,
        BillingFrequency      = 'Annual',
        StartDate             = Date.today(),
        EndDate               = Date.today().addYears(1));
    Database.SaveResult sr = Database.insert(qli, dml);
    System.debug(LoggingLevel.ERROR, 'G-01 QLI insert success=' + sr.isSuccess() + ' id=' + sr.getId()
        + ' errs=' + sr.getErrors());
    Integer cnt = [SELECT COUNT() FROM QuoteLineItem WHERE QuoteId = :q.Id];
    System.debug(LoggingLevel.ERROR, 'G-01 QLI count on quote=' + cnt);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    QuoteLineItem r = [SELECT Id, Quantity, UnitPrice, NetUnitPrice, TotalPrice, NetTotalPrice, Subtotal, CurrencyIsoCode FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ G-01 FIXTURE CREATED  Quote #' + q.QuoteNumber
        + '\n  Account : ' + base + '/' + ACCT
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QLI     : ' + base + '/' + r.Id
        + '\n  QuoteId=' + q.Id + ' | QLIId=' + r.Id
        + '\n  Currency=' + r.CurrencyIsoCode + ' | EUR PBE list=' + pbeEur.UnitPrice + ' | USD ref list=' + pbeUsd.UnitPrice + ' | Qty=' + r.Quantity
        + '\n  Pre-reprice  Unit=' + r.UnitPrice + ' Net=' + r.NetUnitPrice + ' Total=' + r.TotalPrice + ' NetTotal=' + r.NetTotalPrice + ' Subtotal=' + r.Subtotal
        + '\n  EXPECT post-Force-reprice: NetUnitPrice=' + pbeEur.UnitPrice + ' (EUR list), NetTotalPrice=' + (pbeEur.UnitPrice * QTY)
        + '\n  DEFECT signatures: USD-leak Net=' + pbeUsd.UnitPrice + ' ; double-apply Net=' + (pbeEur.UnitPrice * MULT).setScale(2));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ G-01 FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage()
        + ' | stack: ' + e.getStackTraceString());
}
