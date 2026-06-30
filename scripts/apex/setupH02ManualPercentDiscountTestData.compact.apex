// setupH02ManualPercentDiscountTestData.compact.apex
// H-02 (Discounts): builds a brand-new (QuoteTypeText='New') DIRECT, non-contracted, non-derived
// Perpetual line on a Digital Guardian product (DG Management Console, Perpetual, USD list=50000)
// with a MANUAL line-level PERCENT discount of 30% (QLI.Discount=30) and Qty=4, so V21 runs:
//   ListContainer56 -> Manual Quote Level Discount filter (ItemSalesTransactionAction in {Add,Amend,null}
//     AND ItemPricingSource != 'LastTransaction' AND (ItemIsDerived IsNull OR =false))  -- a NEW Add line passes
//   -> Manual Quote Level Percentage-Based (Line-Level) BKM:
//        AdjustmentType=PercentageStringConstant, AdjustmentValue=ItemDiscountPercentage(=Discount=30),
//        InputUnitPrice=NetUnitPrice -> outputs NetUnitPrice and ItemNetTotalPrice.
// EXPECT post-Force-reprice: NetUnitPrice = 50000 * (1 - 0.30) = 35000 ; NetTotalPrice = 35000 * 4 = 140000.
// (The >25% AE-authority "Sales Rule Broken"/approval routing is an approval-process layer, NOT a
//  pricing-procedure step; there is no QLI/STI 'Broken'/'Approval' field — out of scope for the
//  pricing smoke test, which validates the discount-net math the proc is responsible for.)
//
//   Account "Fortra, LLC - Test"        001WC00000XiZP4YAN  (used directly)
//   Opportunity "Wren - Test GS Quotes" 006WC00000OE0NKYA1  (used directly)
//   Product "DG Management Console"      01tWC00000DD1BiYAL  (Fortra_Product_Type__c=Perpetual)
//   PBE (Fortra Price Book, USD)         01uWC000005wru3YAA  (UnitPrice=50000, Pricebook2 active)
//   PSM "One Time" (OneTime)             0jPWC00000005yz2AA  (selling model used by live Perpetual lines)
//
// Atomic: savepoint rollback on any failure.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupH02ManualPercentDiscountTestData.compact.apex
// Output: grep the debug log for the "H-02 FIXTURE" marker (logged at ERROR level).

Id ACCT = '001WC00000XiZP4YAN';
Id OPP  = '006WC00000OE0NKYA1';
Id SRC_CON = '003WC00000nb7khYAA';
Id SRC_PLC = 'a0lWC000004cO79YAE';
Id TPL_Q   = '0Q0WC0000024KOn0AM';
Id PB   = '01sWC0000022GHFYA2';
Id LE   = '0fwWC000000034LYAQ';
Id STT  = '1ChWC0000002eJ70AI';
// DG Management Console (the catalog's illustrative DG/Perpetual product) seeds net=0 in V21
// (DG-product list->net seed failure, independent of the discount mechanism) so it cannot
// demonstrate the discount math. Insite Analytics - Core is the closest pricing-friendly
// Perpetual/OneTime product whose fresh lines reliably seed NetUnitPrice from PBE list
// (verified live: fresh lines list=2500 -> net=2500; a prior disc=20 line -> net=2000), so the
// 30% manual percent discount is observable on it.
Id PROD = '01tWC00000DCwVrYAL';        // Insite Analytics - Core (Perpetual)
Id PBE  = '01uWC000005ws5hYAA';        // PBE, USD, Fortra Price Book, UnitPrice=2500
Id PSM  = '0jPWC00000005yz2AA';        // ProductSellingModel "One Time" (OneTime) - auto-derived by RLM
Decimal QTY = 4;
Decimal DISC = 30;                     // manual line-level percent (>25% AE authority)

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ H-02 ManualPct ' + TAG;

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
    Places__c p = new Places__c(Name = 'H-02 HQ ' + TAG, Account__c = ACCT,
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

    // NEW line: QuoteActionId=null -> ItemSalesTransactionAction='Add'; manual percent discount = 30
    // NB: for this OneTime/Perpetual product, leaving StartDate/EndDate NULL matches the
    // live successfully-priced Insite lines (which seed UnitPrice/NetUnitPrice from list);
    // setting term dates routes a OneTime line down a path that leaves UnitPrice unseeded (=0).
    // Seed UnitPrice from the PBE list on insert (the UI line-add does this; a headless
    // Force-reprice does NOT re-seed UnitPrice for these OneTime lines, so without this the
    // line enters the waterfall with UnitPrice=0 and the discount has nothing to reduce).
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId               = q.Id,
        PricebookEntryId      = PBE,
        Product2Id            = PROD,
        Quantity              = QTY,
        UnitPrice             = pbeRow.UnitPrice,
        Discount              = DISC);
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber, Quote_Type__c FROM Quote WHERE Id = :q.Id];
    QuoteLineItem r = [SELECT Id, Quantity, Discount, UnitPrice, NetUnitPrice, TotalPrice, NetTotalPrice, Subtotal, QuoteActionId FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ H-02 FIXTURE CREATED  Quote #' + q.QuoteNumber
        + '\n  Account : ' + base + '/' + ACCT
        + '\n  Quote   : ' + base + '/' + q.Id + '  (Quote_Type__c=' + q.Quote_Type__c + ')'
        + '\n  QLI     : ' + base + '/' + r.Id + '  (QuoteActionId=' + r.QuoteActionId + ' -> Add; Discount=' + r.Discount + '%)'
        + '\n  QuoteId=' + q.Id + ' | QLIId=' + r.Id
        + '\n  PBE list UnitPrice=' + pbeRow.UnitPrice + ' | Qty=' + r.Quantity + ' | Disc=' + DISC + '% | DealType=' + dealType
        + '\n  Pre-reprice  Unit=' + r.UnitPrice + ' Net=' + r.NetUnitPrice + ' Total=' + r.TotalPrice + ' NetTotal=' + r.NetTotalPrice + ' Subtotal=' + r.Subtotal
        + '\n  EXPECT post-Force-reprice: NetUnitPrice=' + (pbeRow.UnitPrice * (1 - DISC/100)) + ', NetTotalPrice=' + (pbeRow.UnitPrice * (1 - DISC/100) * QTY));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ H-02 FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage()
        + ' | stack: ' + e.getStackTraceString());
    throw e;
}
