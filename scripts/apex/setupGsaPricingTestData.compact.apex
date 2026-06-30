// setupGsaPricingTestData.compact.apex
// D-04 (Pricing Mode): GSA pricing — GSW__c=true line prices at ListPrice * 0.5; GSW__c=false line
// is excluded from GSA halving and retains catalog/attribute price.
//
// V21 mechanism:
//   GSAPricing  (AdvancedListFilter, gate)  : GSW__c Equals true
//   GSAPricing7 (FormulaBasedPricing)       : InputUnitPrice = ListPrice * 0.5  -> flows to NetUnitPrice
//   negative branch (GSW false/null)        : GSA step skipped, catalog list price retained
//
// GSW__c is a Quote-header checkbox (NOT a line field) -> the gate is keyed off the quote-level flag,
// so we build TWO quotes: (A) GSW=true and (B) GSW=false, each a single DIRECT (no-partner)
// Cobalt Strike (Software) line, Qty=2, USD, IsContracted=null, no attributes.
//
//   Account "Fortra, LLC - Test"        001WC00000XiZP4YAN
//   Opportunity "Wren - Test GS Quotes" 006WC00000OE0NKYA1
//   Product "Cobalt Strike"             01tWC00000DD2SlYAL  (Software)
//   PBE (Fortra Price Book, USD)        01uWC000005wrqnYAA  (UnitPrice/ListPrice=20500, active PB)
//   ProductSellingModel "Term Based - Annual" 0jPWC000000060b2AA
//
// EXPECT post-Force-reprice:
//   (A) GSW=true : NetUnitPrice = 20500*0.5 = 10250 ; NetTotalPrice = 10250*2 = 20500
//   (B) GSW=false: NetUnitPrice = 20500 (list)       ; NetTotalPrice = 20500*2 = 41000
//
// Atomic: single savepoint, rollback on any failure.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupGsaPricingTestData.compact.apex
// Output: grep the debug log for the "D-04 FIXTURE" marker (logged at ERROR level).

Id ACCT = '001WC00000XiZP4YAN';
Id OPP  = '006WC00000OE0NKYA1';
Id SRC_CON = '003WC00000nb7khYAA';
Id SRC_PLC = 'a0lWC000004cO79YAE';
Id TPL_Q   = '0Q0WC0000024KOn0AM';
Id PB   = '01sWC0000022GHFYA2';
Id LE   = '0fwWC000000034LYAQ';
Id STT  = '1ChWC0000002eJ70AI';
// Additional Threat Assessments — One-Time line whose standard waterfall nets cleanly to list
// (no attribute adjustment, net=list), so GSW=true -> net=list*0.5 and GSW=false -> net=list are
// both directly observable. (5250 Integrator nets $0 product-side, masking the GSA result.)
Id PROD = '01tWC00000DD11SYAT';        // Additional Threat Assessments (OneTime, net=list)
Id PBE  = '01uWC000005wrrIYAQ';        // PBE, USD, Fortra Price Book, UnitPrice/ListPrice=10000
Decimal QTY = 1;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;
PricebookEntry pbeRow = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Id = :PBE];
Quote tq = [SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c FROM Quote WHERE Id = :TPL_Q];

Savepoint sp = Database.setSavepoint();
try {
    // shared Contact + Place
    Contact c = ((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,
        Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,
        MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode
        FROM Contact WHERE Id = :SRC_CON]).clone(false, true, false, false);
    c.AccountId = ACCT;
    c.LastName  = 'LJ D-04 GSA ' + TAG;
    if (String.isBlank(c.Workday_Phone_Country_ISO_Code__c))       c.Workday_Phone_Country_ISO_Code__c = 'USA';
    if (String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c = 'USA';
    Database.insert(c, dml);

    Places__c srcPlace = [SELECT Address__Street__s,Address__City__s,Address__StateCode__s,
        Address__PostalCode__s,Address__CountryCode__s FROM Places__c WHERE Id = :SRC_PLC];
    Places__c p = new Places__c(Name = 'D-04 HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    // two quotes: A (GSW=true), B (GSW=false control)
    List<Quote> quotes = new List<Quote>();
    for (Boolean gsw : new List<Boolean>{ true, false }) {
        Quote q = new Quote(
            OpportunityId = OPP, Name = 'LJ D-04 GSA ' + (gsw ? 'GSWtrue' : 'GSWfalse') + ' ' + TAG,
            Status = 'Draft', ExpirationDate = Date.today().addDays(30), StartDate = Date.today(),
            Pricebook2Id = PB, CurrencyIsoCode = 'USD', Quote_Type__c = 'New', LegalEntityId = LE,
            QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
            Net_Terms__c = netTerms,
            Language__c = tq.Language__c != null ? tq.Language__c : 'English',
            Deal_Type__c = dealType,
            GSW__c = gsw,
            Show_Hide_Discounts__c = 'Show',
            Header_Discount_Type__c   = tq.Header_Discount_Type__c   != null ? tq.Header_Discount_Type__c   : 'Amount',
            Payment_Portal__c         = tq.Payment_Portal__c         != null ? tq.Payment_Portal__c         : 'Fortra (default)',
            Disable_Export_Control__c = tq.Disable_Export_Control__c != null ? tq.Disable_Export_Control__c : false,
            Ship_To_Place__c = p.Id, Bill_To_Place__c = p.Id,
            BillingStreet = p.Address__Street__s, BillingCity = p.Address__City__s, BillingStateCode = p.Address__StateCode__s,
            BillingPostalCode = p.Address__PostalCode__s, BillingCountryCode = p.Address__CountryCode__s,
            ShippingStreet = p.Address__Street__s, ShippingCity = p.Address__City__s, ShippingStateCode = p.Address__StateCode__s,
            ShippingPostalCode = p.Address__PostalCode__s, ShippingCountryCode = p.Address__CountryCode__s);
        quotes.add(q);
    }
    Database.insert(quotes, dml);

    List<QuoteLineItem> qlis = new List<QuoteLineItem>();
    for (Quote q : quotes) {
        // OneTime line: leave StartDate/EndDate null (matches the clean-netting reference line;
        // setting term dates on a OneTime line suppressed the net waterfall in earlier runs).
        qlis.add(new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = PBE, Product2Id = PROD, Quantity = QTY));
    }
    Database.insert(qlis, dml);

    Map<Id,Quote> qById = new Map<Id,Quote>([SELECT Id, QuoteNumber, GSW__c FROM Quote WHERE Id IN :quotes]);
    Map<Id,QuoteLineItem> rById = new Map<Id,QuoteLineItem>([SELECT Id, QuoteId, Quantity, UnitPrice, NetUnitPrice, TotalPrice, NetTotalPrice, Subtotal FROM QuoteLineItem WHERE Id IN :qlis]);
    String base = URL.getOrgDomainUrl().toExternalForm();

    String msg = '✅ D-04 FIXTURE CREATED (GSA pricing)  PBE ListPrice=' + pbeRow.UnitPrice + ' Qty=' + QTY
        + '\n  Account : ' + base + '/' + ACCT;
    for (QuoteLineItem r : rById.values()) {
        Quote q = qById.get(r.QuoteId);
        Boolean gsw = q.GSW__c;
        Decimal expNet = gsw ? (pbeRow.UnitPrice * 0.5) : pbeRow.UnitPrice;
        msg += '\n  --- Quote #' + q.QuoteNumber + ' GSW__c=' + gsw + ' ---'
            + '\n    Quote : ' + base + '/' + q.Id
            + '\n    QLI   : ' + base + '/' + r.Id
            + '\n    QuoteId=' + q.Id + ' | QLIId=' + r.Id
            + '\n    Pre-reprice Unit=' + r.UnitPrice + ' Net=' + r.NetUnitPrice + ' NetTotal=' + r.NetTotalPrice
            + '\n    EXPECT Force-reprice: NetUnitPrice=' + expNet + ', NetTotalPrice=' + (expNet * QTY);
    }
    System.debug(LoggingLevel.ERROR, msg);
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ D-04 FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
