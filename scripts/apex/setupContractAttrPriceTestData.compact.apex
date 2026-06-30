// setupContractAttrPriceTestData.compact.apex
// D-06 fixture: Attribute-Based Price CONTRACTED branch (V21 ListContainer / AttributeBasedPrice,
//   gated AttributePricingFilter = ItemContractAttributePasId IsNotNull AND ItemPricingSource != 'LastTransaction'
//   AND DerivedPricingAttribute IsNotNull AND =false). LookUpApiName=Attribute_Based_Adjustment_Decision_Table,
//   IsContractEnabled=true. catalog twin = AttributeDiscountEntries (ListContainer7, non-contracted).
//
// Builds ONE Draft quote with TWO AAMP lines (01tWC00000DD11YYAT, list $3,150, Fortra Price Book PBE):
//   L1 CONTRACTED  PricingContractId=800WC00000SFn6jYAD + {RAA, On Premise, Non-Production}
//                  -> tests whether platform hydrates ItemContractAttributePasId so the CONTRACTED
//                     AttributeBasedPrice branch (D-06) fires.
//   L2 CATALOG     no PricingContractId + same {RAA, On Premise, Non-Production}
//                  -> catalog AttributeDiscountEntries branch (D-03 control) -> net 1575.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupContractAttrPriceTestData.compact.apex
// Output: grep the debug log for "D06-CONTRACT" (ERROR level).

Id ACCT   = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP    = '006WC00000OE0NKYA1';
Id SRC_CON= '003WC00000nb7khYAA';
Id SRC_PLC= 'a0lWC000004cO79YAE';
Id TPL_Q  = '0Q0WC0000024KOn0AM';
Id PB     = '01sWC0000022GHFYA2';        // Fortra Price Book
Id LE     = '0fwWC000000034LYAQ';
Id STT    = '1ChWC0000002eJ70AI';
Id PBE    = '01uWC000005wrrNYAQ';        // AAMP PBE, Fortra Price Book, USD, 3150
Id CONTRACT = '800WC00000SFn6jYAD';      // the org's single contracted-pricing Contract

Id AD_FO  = '0tjWC000000096ZYAQ';        // Feature Options
Id AD_DO  = '0tjWC000000096YYAQ';        // Deployment Option
Id AD_ST  = '0tjWC000000096jYAA';        // Server Type
Id PV_RAA = '0v6WC0000000A07YAE';        // FO = Remote Automation Agent
Id PV_ONPREM='0v6WC00000009mjYAA';       // DO = On Premise
Id PV_NONPROD='0v6WC0000000AJpYAM';      // ST = Non-Production

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'D06 ContractAttr ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;

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
    Places__c p = new Places__c(Name = 'D06 HQ ' + TAG, Account__c = ACCT,
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
        Language__c = tq.Language__c != null ? tq.Language__c : 'English',
        Deal_Type__c = dealType,
        Header_Discount_Type__c   = tq.Header_Discount_Type__c   != null ? tq.Header_Discount_Type__c   : 'Amount',
        Payment_Portal__c         = tq.Payment_Portal__c         != null ? tq.Payment_Portal__c         : 'Fortra (default)',
        Disable_Export_Control__c = tq.Disable_Export_Control__c != null ? tq.Disable_Export_Control__c : false,
        Ship_To_Place__c = p.Id, Bill_To_Place__c = p.Id,
        BillingStreet = p.Address__Street__s, BillingCity = p.Address__City__s, BillingStateCode = p.Address__StateCode__s,
        BillingPostalCode = p.Address__PostalCode__s, BillingCountryCode = p.Address__CountryCode__s,
        ShippingStreet = p.Address__Street__s, ShippingCity = p.Address__City__s, ShippingStateCode = p.Address__StateCode__s,
        ShippingPostalCode = p.Address__PostalCode__s, ShippingCountryCode = p.Address__CountryCode__s);
    Database.insert(q, dml);

    // L1 CONTRACTED (PricingContractId set), L2 CATALOG (no contract)
    QuoteLineItem l1 = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=PBE, Quantity=1, StartQuantity=1,
        StartDate=Date.today(), EndDate=Date.today().addYears(1), PricingContractId=CONTRACT);
    QuoteLineItem l2 = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=PBE, Quantity=1, StartQuantity=1,
        StartDate=Date.today(), EndDate=Date.today().addYears(1));
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ l1, l2 };
    Database.insert(lines, dml);

    String base = URL.getOrgDomainUrl().toExternalForm();
    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    System.debug(LoggingLevel.ERROR, '✅ D06-CONTRACT CREATED  Quote #' + q.QuoteNumber
        + '  QuoteId=' + q.Id
        + '  L1(contracted)=' + l1.Id + '  L2(catalog)=' + l2.Id
        + '  ' + base + '/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ D06-CONTRACT FAILED: ' + e.getMessage() + ' | ' + e.getStackTraceString());
    throw e;
}
