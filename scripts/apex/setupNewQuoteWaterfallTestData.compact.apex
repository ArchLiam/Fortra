// setupNewQuoteWaterfallTestData.compact.apex
// F-01 (Transaction Type): builds a brand-new (QuoteTypeText='New') DIRECT (no-partner),
// non-contracted, non-derived Software line so V21 runs the FULL catalog+attribute+discount
// waterfall, stamps the contributor base, and (Stamp Base Filter: QuoteTypeText != 'Renewal')
// is NOT routed into any renewal/COLA/derived branch.
//
// Distinguishing F-01 (vs A-01 catalog-source): F-01 verifies the TRANSACTION-TYPE dimension —
// a NEW line (ItemSalesTransactionAction defaults to 'Add' because QuoteActionId is null;
// QuoteTypeText='New') passes the Manual Quote Level Discount (Add OR IsNull) AND non-derived
// gate and the Stamp Base Filter (QuoteTypeText NotEquals 'Renewal'), so:
//   - the full waterfall runs and NetUnitPrice resolves from PBE list (Direct => no discount),
//   - the contributor base (Pre_Partner_Price__c / Base_Price__c) is STAMPED (not null, not 0),
//   - no Asset inheritance / no COLA / no NetUnitPrice-Value-Reset.
//
//   Account "Fortra, LLC - Test"        001WC00000XiZP4YAN  (used directly)
//   Opportunity "Wren - Test GS Quotes" 006WC00000OE0NKYA1  (used directly)
//   Product "Cobalt Strike"             01tWC00000DD2SlYAL  (Fortra_Product_Type__c=Software)
//   PBE (Fortra Price Book, USD)        01uWC000005wrqnYAA  (UnitPrice=20500, Pricebook2 active)
//
// DIRECT: NO PartnerAccountId, NO Partner_Pricing_Model__c -> Partner Discount steps skipped, so
// net = PBE list (20500) with no downstream discount. Qty=5, USD, IsContracted=null, no attrs,
// QuoteActionId=null -> ItemSalesTransactionAction='Add' (NEW), QuoteTypeText='New'.
//
// NOTE: Cobalt Strike's only ProductSellingModelOption is "Term Based - Annual" (TermDefined),
// so the line is TermDefined. ProductSellingModelId is NOT writeable on QuoteLineItem in this org
// (auto-assigned from the product's single PSM option). SubscriptionTerm=12 is set so the
// TermDefined proration path can compute a single annual term (PricingTermCount=1).
//
// Atomic: savepoint rollback on any failure.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupNewQuoteWaterfallTestData.compact.apex
// Output: grep the debug log for the "F-01 FIXTURE" marker (logged at ERROR level).

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
// --- F-01 NEW waterfall line ------------------------------------------------
Id PROD = '01tWC00000DD2SlYAL';        // Cobalt Strike (Software)
Id PBE  = '01uWC000005wrqnYAA';        // PBE, USD, Fortra Price Book, UnitPrice=20500
Decimal QTY = 5;
Decimal LISTUP = 20500;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ F-01 NewWaterfall ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;
PricebookEntry pbeRow = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Id = :PBE];

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
    Places__c p = new Places__c(Name = 'F-01 HQ ' + TAG, Account__c = ACCT,
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

    // NEW line: QuoteActionId=null -> ItemSalesTransactionAction='Add', non-derived, non-contracted.
    // ProductSellingModelId auto-assigned (single TermDefined option). UnitPrice + SubscriptionTerm
    // set on insert so TermDefined proration computes a single annual term.
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId               = q.Id,
        PricebookEntryId      = PBE,
        Product2Id            = PROD,
        Quantity              = QTY,
        UnitPrice             = LISTUP,
        SubscriptionTerm      = 1,
        BillingFrequency      = 'Annual',
        StartDate             = Date.today(),
        EndDate               = Date.today().addYears(1));
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber, Quote_Type__c FROM Quote WHERE Id = :q.Id];
    QuoteLineItem r = [SELECT Id, Quantity, UnitPrice, NetUnitPrice, TotalPrice, NetTotalPrice, Subtotal,
        SellingModelType, PricingTermCount, SubscriptionTerm, Base_Price__c, Pre_Partner_Price__c, QuoteActionId
        FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, 'F-01 FIXTURE CREATED  Quote #' + q.QuoteNumber
        + '\n  Account : ' + base + '/' + ACCT
        + '\n  Quote   : ' + base + '/' + q.Id + '  (Quote_Type__c=' + q.Quote_Type__c + ')'
        + '\n  QLI     : ' + base + '/' + r.Id + '  (QuoteActionId=' + r.QuoteActionId + ' -> Add)'
        + '\n  QuoteId=' + q.Id + ' | QLIId=' + r.Id
        + '\n  PBE list UnitPrice=' + pbeRow.UnitPrice + ' | Qty=' + r.Quantity + ' | DealType=' + dealType + ' | SMT=' + r.SellingModelType
        + '\n  Pre-reprice  Unit=' + r.UnitPrice + ' Net=' + r.NetUnitPrice + ' Total=' + r.TotalPrice + ' NetTotal=' + r.NetTotalPrice + ' Subtotal=' + r.Subtotal + ' PTC=' + r.PricingTermCount
        + '\n  EXPECT post-Force-reprice: NetUnitPrice=' + pbeRow.UnitPrice + ', NetTotalPrice=' + (pbeRow.UnitPrice * QTY) + ', Pre_Partner_Price__c/Base_Price__c STAMPED (contributor base)');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'F-01 FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage()
        + ' | stack: ' + e.getStackTraceString());
    throw e;
}
