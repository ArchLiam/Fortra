// setupH01ManualAmountDiscountTestData.compact.apex
// Builds the H-01 (Manual quote-level AMOUNT-based / line-level discount) smoke-test fixture in
// FortraUAT: a fresh Draft "New" Quote with a SINGLE non-derived line that has a manual fixed-amount
// discount entered at the line (QuoteLineItem.DiscountAmount, per-unit). This exercises V21 step
// "Manual Quote Level Amount-Based (Line-Level)" (gated by "Manual Quote Level Discount":
// ItemPricingSource != 'LastTransaction' AND (Amend OR Add OR action IsNull) AND ItemIsDerived
// null/false). After a Force-reprice the step should set NetUnitPrice = list - DiscountAmount and
// ItemNetTotalPrice (NetTotalPrice/TotalLineAmount) = NetUnitPrice * Qty.
//
// Chosen line:  Product "DG Management Console" (Perpetual, OneTime selling model) -> no proration,
//   list $50,000, active "Fortra Price Book" PBE 01uWC000005wru3YAA. Qty = 2, DiscountAmount = 5000.
//   EXPECTED after reprice:  NetUnitPrice = 45000 ;  NetTotalPrice = TotalLineAmount = 90000.
//   (UnitPrice/ListPrice stay 50000.)
//
// Reuses the standing test Account 001WC00000XiZP4YAN ("Fortra, LLC - Test") and its Opportunity
// 006WC00000OE0NKYA1 ("Wren - Test GS Quotes"). Clones a known-good Contact/Place so required fields
// are populated. Atomic: any failure rolls back via a savepoint (no orphan Quote/Contact/Place/QLI).
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupH01ManualAmountDiscountTestData.compact.apex
//       (NOTE: target FortraUAT, not the `uat` alias — that is 5sInfusion's org.)
// Output: grep the debug log for the "H01-FIXTURE" marker (logged at ERROR level).

// --- Existing records used directly (not cloned) ----------------------------
Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes" (on the account above)
// --- Source records to clone (UAT 18-char Ids) ------------------------------
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place (address source)
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote (header defaults)
// --- Fixed config Ids -------------------------------------------------------
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
// --- H-01 line config -------------------------------------------------------
Id PBE_ID = '01uWC000005wru3YAA';      // DG Management Console, Perpetual OneTime, $50,000, Fortra Price Book
Decimal QTY        = 2;
Decimal DISC_AMT   = 5000;             // per-unit manual amount discount ($5k off $50k)

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));
String LABEL = 'LJ H01 ManualAmtDiscount ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

// PBE -> pricebook + product + selling model + list price (QLI/Quote must share this Pricebook2).
PricebookEntry pbe = [SELECT Id, Pricebook2Id, Product2Id, UnitPrice, ProductSellingModelId,
                             CurrencyIsoCode, Pricebook2.IsActive
                      FROM PricebookEntry WHERE Id = :PBE_ID];

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c, Referral_Partner__c, Cross_Sale_Type__c
    FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;

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
    Places__c p = new Places__c(Name = 'H01 HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    // --- Quote (New, on the existing opportunity + account, same Pricebook as the PBE) ---
    Quote tq = [SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c
        FROM Quote WHERE Id = :TPL_Q];
    Quote q = new Quote(
        OpportunityId = OPP, Name = LABEL, Status = 'Draft', ExpirationDate = Date.today().addDays(30),
        StartDate = Date.today(),
        Pricebook2Id = pbe.Pricebook2Id, CurrencyIsoCode = pbe.CurrencyIsoCode,
        Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = netTerms,
        Language__c = tq.Language__c != null ? tq.Language__c : 'English',
        Deal_Type__c = dealType,
        Header_Discount_Type__c   = 'Amount',
        Payment_Portal__c         = tq.Payment_Portal__c         != null ? tq.Payment_Portal__c         : 'Fortra (default)',
        Disable_Export_Control__c = tq.Disable_Export_Control__c != null ? tq.Disable_Export_Control__c : false,
        Show_Hide_Discounts__c = 'Show',
        Ship_To_Place__c = p.Id, Bill_To_Place__c = p.Id,
        BillingStreet = p.Address__Street__s, BillingCity = p.Address__City__s, BillingStateCode = p.Address__StateCode__s,
        BillingPostalCode = p.Address__PostalCode__s, BillingCountryCode = p.Address__CountryCode__s,
        ShippingStreet = p.Address__Street__s, ShippingCity = p.Address__City__s, ShippingStateCode = p.Address__StateCode__s,
        ShippingPostalCode = p.Address__PostalCode__s, ShippingCountryCode = p.Address__CountryCode__s);
    Database.insert(q, dml);

    // --- Single non-derived line: Qty 2, manual per-unit amount discount $5,000 ---
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId              = q.Id,
        PricebookEntryId     = pbe.Id,
        Product2Id           = pbe.Product2Id,
        Quantity             = QTY,
        StartQuantity        = QTY,
        UnitPrice            = pbe.UnitPrice,        // seed list; reprice will recompute net
        DiscountAmount       = DISC_AMT,             // <-- the manual amount-based discount (per unit)
        PeriodBoundary       = 'Anniversary',
        StartDate            = Date.today(),
        SubscriptionTerm     = 1);
    Database.insert(qli, dml);

    QuoteLineItem r = [SELECT Id, Quote.QuoteNumber, Quantity, ListPrice, UnitPrice, NetUnitPrice,
                              DiscountAmount, NetTotalPrice, TotalLineAmount
                       FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ H01-FIXTURE CREATED  Quote #' + r.Quote.QuoteNumber
        + '\n  Account : ' + base + '/' + ACCT  + '  (Fortra, LLC - Test, existing)'
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QLI     : ' + base + '/' + r.Id
        + '\n  PRE-REPRICE  Qty=' + r.Quantity + ' List=' + r.ListPrice + ' Unit=' + r.UnitPrice
        + ' DiscAmt(per-unit)=' + r.DiscountAmount + ' Net=' + r.NetUnitPrice
        + ' NetTotal=' + r.NetTotalPrice + ' TotalLineAmount=' + r.TotalLineAmount
        + '\n  EXPECTED after Force-reprice:  NetUnitPrice=45000  NetTotalPrice=90000  TotalLineAmount=90000'
        + '\n  NEXT: Force-reprice the Quote via REST, then re-query the QLI.');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ H01-FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;   // non-zero CLI exit
}
