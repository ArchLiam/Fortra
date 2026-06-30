// setupRegionalServicesTestData.compact.apex  (G-04 — Regional services country multiplier)
// Builds a NON-US (Italy, multiplier 0.64) services quote so the V21 regional
// mechanism applies: RegionalServicesPricingPrehook writes UnitPrice (LIST channel)
// = CEILING(List x 0.64 / 5) x 5, and V21 step RegionalServicesPrice33 assigns
// RegionalNetUnitPrice__c -> InputUnitPrice (LIST only). NET stays catalog -> list != net.
//
// Standing test records used directly (NOT modified):
//   Account "Fortra, LLC - Test" 001WC00000XiZP4YAN ; Opportunity 006WC00000OE0NKYA1
// Fresh Contact -> Italy Place -> Italy Quote -> 1 Services line are created.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupRegionalServicesTestData.compact.apex
// Output: grep the debug log for the "FIXTURE" marker (logged at ERROR level).

Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes"
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote (header defaults)
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book, active)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
// Services line: EFT Expert Service Enterprise (OneTime, Allow_Regional_Pricing=true, list 55000)
Id PROD = '01tWC00000DD1ElYAL';
Id PBE  = '01uWC000005wrvgYAA';
Id PSM  = '0jPWC00000005yz2AA';
Decimal LISTP = 55000;

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ G04 Regional Italy ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;

Savepoint sp = Database.setSavepoint();
try {
    // Contact (under the existing account)
    Contact c = ((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,
        Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,
        MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode
        FROM Contact WHERE Id = :SRC_CON]).clone(false, true, false, false);
    c.AccountId = ACCT;
    c.LastName  = LABEL;
    if (String.isBlank(c.Workday_Phone_Country_ISO_Code__c))       c.Workday_Phone_Country_ISO_Code__c = 'ITA';
    if (String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c = 'ITA';
    Database.insert(c, dml);

    // Place — Italy address (drives ShipToPlace_Country__c in the pricing context)
    Places__c p = new Places__c(Name = 'Italy HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = 'Via Roma 1',
        Address__City__s        = 'Milano',
        Address__PostalCode__s  = '20121',
        Address__CountryCode__s = 'IT');
    Database.insert(p, dml);

    // Quote — Italy shipping/billing country so the prehook resolves multiplier 0.64
    Quote q = new Quote(
        OpportunityId = OPP, Name = LABEL, Status = 'Draft', ExpirationDate = Date.today().addDays(30),
        Pricebook2Id = PB, CurrencyIsoCode = 'USD', Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = netTerms, Deal_Type__c = dealType,
        Ship_To_Place__c = p.Id, Bill_To_Place__c = p.Id,
        BillingStreet = 'Via Roma 1', BillingCity = 'Milano', BillingPostalCode = '20121',
        BillingCountry = 'Italy', BillingCountryCode = 'IT',
        ShippingStreet = 'Via Roma 1', ShippingCity = 'Milano', ShippingPostalCode = '20121',
        ShippingCountry = 'Italy', ShippingCountryCode = 'IT');
    Database.insert(q, dml);

    // Services line — qty 1, regional flag true
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId = q.Id, Product2Id = PROD, PricebookEntryId = PBE,
        Quantity = 1, UnitPrice = LISTP,
        Allow_Regional_Pricing__c = true);
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ FIXTURE CREATED G-04  Quote #' + q.QuoteNumber
        + '  (Italy 0.64; expect list 55000 -> 35200, net stays 55000)'
        + '\n  Quote   : ' + base + '/' + q.Id
        + '\n  QLI     : ' + base + '/' + qli.Id
        + '\n  Place   : ' + base + '/' + p.Id
        + '\n  QUOTEID=' + q.Id + ' QLIID=' + qli.Id);
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
