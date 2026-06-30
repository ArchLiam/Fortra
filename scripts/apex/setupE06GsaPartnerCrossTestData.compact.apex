// setupE06GsaPartnerCrossTestData.compact.apex
// E-06 (Deal / Customer Type): GSA (GSW__c=true) CROSSED with a partner deal.
// Tests whether a line that is BOTH GSW__c=true AND on a partner Deal_Type stacks the
// partner discount on top of the GSA 50% halving, or applies GSA only / partner only.
//
// V21 mechanism crossed:
//   GSAPricing   (AdvancedListFilter, gate)   : GSW__c Equals true          (Quote-header flag)
//   GSAPricing36 (FormulaBasedPricing)        : InputUnitPrice = ListPrice * 0.5   (seq 12 container)
//   PartnerDiscount   (AdvancedListFilter)    : Deal_Type__c != 'Fortra Originated' AND ItemIsDerived in (null,false)
//                                               -- NOTE: gate does NOT check GSW__c
//   PartnerDiscount55 (ManualDiscount)        : InputUnitPrice<-NetUnitPrice, %=PartnerDiscountPercent,
//                                               NetUnitPrice = NetUnitPrice * (1 - pct/100)   (seq 19 container)
//
// Build: clone E-02's clean-netting partner setup (AB Test Partner, Channel Originated,
// Discount model, Software 15%) but set GSW__c=true on the header. One clean Software line
// (Cobalt Strike, list 20500, Qty=2) with UnitPrice=ListPrice stamped so ListPrice==base
// (GSA's ListPrice*0.5 and the partner % then act on the SAME 20500 base -> the stacking
// question is unambiguous).
//
//   GSA-only (catalog expects) : Net = 20500 * 0.5            = 10250
//   partner-only              : Net = 20500 * (1-0.15)        = 17425
//   STACKED (suspected defect): Net = 20500 * 0.5 * (1-0.15)  = 8712.5
//
//   Account "Fortra, LLC - Test"        001WC00000XiZP4YAN
//   Opportunity "Wren - Test GS Quotes" 006WC00000OE0NKYA1
//   AB Test Partner Account             001WC00000ZtazZYAR  (Channel Originated, Discount, SW 15%)
//   Product "Cobalt Strike"             01tWC00000DD2SlYAL  (Software)
//   PBE (Fortra Price Book, USD)        01uWC000005wrqnYAA  (UnitPrice/ListPrice=20500, active PB)
//   ProductSellingModel "Term Based - Annual" 0jPWC000000060b2AA  (TermDefined; nets cleanly on E-02)
//
// Atomic: single savepoint, rollback on any failure.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupE06GsaPartnerCrossTestData.compact.apex
// Output: grep the debug log for "E06-FIXTURE" (ERROR level).

Id ACCT = '001WC00000XiZP4YAN';
Id OPP  = '006WC00000OE0NKYA1';
Id SRC_CON = '003WC00000nb7khYAA';
Id SRC_PLC = 'a0lWC000004cO79YAE';
Id TPL_Q   = '0Q0WC0000024KOn0AM';
Id PB   = '01sWC0000022GHFYA2';
Id LE   = '0fwWC000000034LYAQ';
Id STT  = '1ChWC0000002eJ70AI';
Id PART = '001WC00000ZtazZYAR';     // AB Test Partner Account
Id PBE  = '01uWC000005wrqnYAA';
Id P2   = '01tWC00000DD2SlYAL';
Decimal LISTPRICE = 20500;
Integer QTY = 2;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm');
String LABEL = 'LJ E06 GSA x Partner ' + TAG + ' ' + String.valueOf(Crypto.getRandomInteger()).right(5);

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
    Places__c p = new Places__c(Name = 'E06 HQ ' + TAG, Account__c = ACCT,
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
        StartDate = Date.today(),
        Pricebook2Id = PB, CurrencyIsoCode = 'USD', Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = 'Net_30',
        Language__c = tq.Language__c != null ? tq.Language__c : 'English',
        Deal_Type__c = 'Channel Originated', PartnerAccountId = PART, Billing_Partner__c = PART,
        Partner_Pricing_Model__c = 'Discount', Show_Hide_Discounts__c = 'Show',
        GSW__c = true,
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

    q = [SELECT Id, QuoteNumber, GSW__c FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ E06-FIXTURE CREATED  Quote #' + q.QuoteNumber
        + ' GSW__c=' + q.GSW__c + ' Deal=Channel Originated partner=' + PART
        + ' (Discount SW 15%) list=' + LISTPRICE + ' qty=' + QTY
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QLI     : ' + base + '/' + qli.Id
        + '\n  QuoteId=' + q.Id + ' | QLIId=' + qli.Id
        + '\n  EXPECT (catalog GSA-only) Net=10250 | partner-only Net=17425 | STACKED Net=8712.5');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ E06-FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
