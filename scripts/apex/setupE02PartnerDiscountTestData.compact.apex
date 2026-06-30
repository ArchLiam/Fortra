// setupE02PartnerDiscountTestData.compact.apex
// E-02: Channel/Reseller partner DISCOUNT on a standard non-derived Software line.
// Builds a fresh Contact -> Place -> Quote (Channel Originated, Discount model) on the
// standing test Account "AB Test Partner Account" (001WC00000ZtazZYAR) as the billing
// partner, then adds ONE clean Software line (Cobalt Strike, list 20500, Qty=3).
// Expected after V21 Force-reprice: NetUnitPrice = 20500 * (1-0.15) = 17425 (Software 15%),
// net != list, NetTotalPrice = 52275, TotalLineAmount(list) = 61500.
//
// Atomic: any failure rolls newly-created records back via a savepoint.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupE02PartnerDiscountTestData.compact.apex
// Output: grep the debug log for the "E02-FIXTURE" marker (logged at ERROR level).

Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test" (quote account)
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes"
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote header defaults
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PART = '001WC00000ZtazZYAR';        // AB Test Partner Account (billing partner; active Discount PPM-00028 SW=15)
// Software line: Cobalt Strike (Fortra_Product_Type=Software), Term Based - Annual
Id PBE  = '01uWC000005wrqnYAA';
Id P2   = '01tWC00000DD2SlYAL';
Id PSM  = '0jPWC000000060b2AA';        // Term Based - Annual (TermDefined)
Decimal LISTPRICE = 20500;
Integer QTY = 3;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm');
String LABEL = 'LJ E02 Partner Discount ' + TAG + ' ' + String.valueOf(Crypto.getRandomInteger()).right(5);

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
    Places__c p = new Places__c(Name = 'E02 HQ ' + TAG, Account__c = ACCT,
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
        SubscriptionTerm = 12,
        StartDate = Date.today(), EndDate = Date.today().addmonths(12).addDays(-1));
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ E02-FIXTURE CREATED  Quote #' + q.QuoteNumber
        + ' QuoteId=' + q.Id + ' QLI=' + qli.Id
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QLI     : ' + base + '/' + qli.Id
        + '\n  Partner : ' + PART + ' (Channel Originated, Discount, Software 15%) list=' + LISTPRICE + ' qty=' + QTY);
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ E02-FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
