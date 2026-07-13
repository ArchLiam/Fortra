// setupHrmClsaasEurRepro.apex
// SC-3384 Workstream C live-confirmation (L4). Creates a CLEAN, EMPTY, EUR, New-type Quote so you
// can add the attribute-tier SKU HRM-HRM-RSL-CLSAAS ("Click and Launch Security Awareness Training -
// All Star", Product2 01tWC00000DD17PYAT) in the UI TLE, configure it "Self Managed" at volume 50-99,
// and Reprice via the TLE/UI path (NOT the Fortra_Quote_Reprice flow — that doesn't re-run the prehook).
// EXPECT after the C fix: the attribute-volume tier resolves to the EUR tier (~2,373.60), NOT the USD
// tier (2,580.00). Any other value (2,580 or a bare list fallthrough) => STICurrencyIsoCode tag not
// reaching AttributeVolumePricingPrehook.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupHrmClsaasEurRepro.apex
// Output: grep the debug log for "HRM-REPRO" (ERROR level) -> the Quote URL.

Id ACCT   = '001WC00000XiZP4YAN';     // "Fortra, LLC - Test"
Id OPP    = '006WC00000QnybxYAB';     // "Wren - Test Currencies" (EUR Opp)
Id SRC_CON= '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC= 'a0lWC000004cO79YAE';     // template Place
Id TPL_Q  = '0Q0WC0000024KOn0AM';     // template Quote (defaults)
Id PB     = '01sWC0000022GHFYA2';     // Pricebook2 (Fortra Price Book)
Id LE     = '0fwWC000000034LYAQ';     // Legal Entity
Id STT    = '1ChWC0000002eJ70AI';     // SalesTransactionType
String CUR = 'EUR';

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ HRM-CLSAAS Tier EUR ' + TAG;

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
    Places__c p = new Places__c(Name = 'HRM Repro HQ ' + TAG, Account__c = ACCT,
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

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, 'HRM-REPRO CREATED  Quote #' + q.QuoteNumber + ' currency=' + CUR + ' type=New (EMPTY)'
        + '\n  Quote : ' + base + '/' + q.Id
        + '\n  STEP  : open TLE -> ADD HRM-HRM-RSL-CLSAAS -> configure "Self Managed", volume 50-99 -> Reprice (TLE/UI path)'
        + '\n  EXPECT: attribute-volume tier = EUR ~2,373.60 (NOT USD 2,580.00)'
        + '\n  IDS   : quote=' + q.Id);
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'HRM-REPRO FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
