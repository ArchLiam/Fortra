// setupG03PartnerNonUsdOneTimeTestData.compact.apex
// G-03 (clean cell): Partner DISCOUNT on a non-USD (EUR) ONE-TIME/Perpetual Software line.
// The original setupG03PartnerNonUsdTestData used a TermDefined product (Cobalt Strike) which routes
// into the Subscription/Proration path and (with null PricingTermCount) zeroes the net - entangling the
// partner x currency cell with the SC-3420 PTC/TermDefined defect. This fixture uses the EUR One-Time
// equivalent of the passing E-02 product (CCM Limited Scan Engine, OneTime) so the smoke test isolates
// ordering of partner% vs FX multiply: net = list x currencyMult x (1 - partner%).
// Partner: AB Test Partner 001WC00000ZtazZYAR, active Discount PPM Software_Percent__c=15.
// Inputs: EUR quote, UnitPrice(list input)=100000, Qty=3, OneTime CCM EUR PBE in active Fortra Price Book.
// Expected after V21 Force-reprice:
//   EUR mult=0.9346, Software partner%=15  ->  NetUnitPrice=100000*0.9346*0.85=79441.00
//   NetTotalPrice=238323.00 (qty 3) ; TotalLineAmount(list FX)=100000*0.9346*3=280380.00
//
// Atomic: any failure rolls newly-created records back via a savepoint.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupG03PartnerNonUsdOneTimeTestData.compact.apex
// Output: grep the debug log for the "G03OT-FIXTURE" marker (logged at ERROR level).

Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test" (quote account)
Id OPP  = '006WC00000QnybxYAB';        // "Wren - Test Currencies" (EUR opp; Quote currency follows Opp)
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote header defaults
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book, active)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PART = '001WC00000ZtazZYAR';        // AB Test Partner Account (active Discount PPM Software=15)
// Software line: CCM Limited Scan Engine (Fortra_Product_Type=Software), OneTime/Perpetual, EUR PBE
Id PBE  = '01uWC000005wwgaYAA';        // EUR OneTime PBE in active Fortra Price Book (catalog 1876.6768 EUR)
Id P2   = '01tWC00000DD16IYAT';
Decimal LISTPRICE = 100000;            // USD-basis list per G-03 test_setup; V21 applies FX + partner%
Integer QTY = 3;
String CUR = 'EUR';

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm');
String LABEL = 'LJ G03 Partner EUR OneTime ' + TAG + ' ' + String.valueOf(Crypto.getRandomInteger()).right(5);

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

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
    Places__c p = new Places__c(Name = 'G03OT HQ ' + TAG, Account__c = ACCT,
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
        Pricebook2Id = PB, CurrencyIsoCode = CUR, Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = 'Net_30',
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

    QuoteLineItem qli = new QuoteLineItem(
        QuoteId = q.Id, PricebookEntryId = PBE, Product2Id = P2,
        Quantity = QTY, UnitPrice = LISTPRICE, Fortra_Product_Type__c = 'Software',
        StartDate = Date.today(), EndDate = Date.today().addmonths(12).addDays(-1));
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ G03OT-FIXTURE CREATED  Quote #' + q.QuoteNumber
        + ' QuoteId=' + q.Id + ' QLI=' + qli.Id + ' CUR=' + CUR
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QLI     : ' + base + '/' + qli.Id
        + '\n  Partner : ' + PART + ' (Channel Originated, Discount, Software 15%) list=' + LISTPRICE + ' qty=' + QTY
        + '\n  Expect  : Net=100000*0.9346*0.85=79441 NetTotal=238323 TLA=280380 (OneTime/Perpetual, no PTC path)');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ G03OT-FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
