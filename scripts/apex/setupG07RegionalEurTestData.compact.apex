// setupG07RegionalEurTestData.compact.apex  (G-07 — Regional services line in NON-USD (EUR) currency)
// Builds an EUR Italy (multiplier 0.64) services quote so V21 applies BOTH the country
// regional multiplier AND the EUR currency conversion together, without one negating or
// double-applying the other.
//   Regional prehook reads the line ListPrice (EUR PBE = 51403 = 55000 x 0.9346 pre-built)
//   and computes RegionalNetUnitPrice__c = CEILING(ListPrice x 0.64 / 5) x 5.
//   V21 step RegionalServicesPrice assigns RegionalNetUnitPrice__c -> InputUnitPrice (LIST only).
//   NET stays catalog EUR list -> structural list != net, both in EUR.
//
// Expected (no double-FX): LIST/TotalLineAmount = CEILING(51403*0.64/5)*5 = 32900 EUR;
//                          NET/NetTotalPrice = 51403 EUR (catalog EUR). list(32900) < net(51403).
//   (USD-frame cross-check: regional-in-USD 35200 x 0.9346 = 32900.32 ~ 32900; converges.)
//
// Same product as G-04 (USD) but EUR: EFT Expert Service Enterprise GS-GSE-NRST-EESE, Fortra_Product_Type=Services.
//
// Standing test records used directly (NOT modified):
//   Account "Fortra, LLC - Test" 001WC00000XiZP4YAN ; EUR Opportunity 006WC00000QnybxYAB ("Wren - Test Currencies")
// Fresh Contact -> Italy Place -> EUR Italy Quote -> 1 Services line are created.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupG07RegionalEurTestData.compact.apex
// Output: grep the debug log for the "FIXTURE" marker (logged at ERROR level).

Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000QnybxYAB';        // EUR Opportunity "Wren - Test Currencies"
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book, active)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
// Services line: EFT Expert Service Enterprise (OneTime, Allow_Regional_Pricing=true)
Id PROD = '01tWC00000DD1ElYAL';
Id PBE  = '01uWC000005woEQYAY';        // EUR PBE on Fortra Price Book (UnitPrice 51403)
Decimal LISTP = 51403;                 // EUR catalog list (= 55000 USD x 0.9346)

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ G07 Regional EUR Italy ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Account acctRow = [SELECT Id, Net_Terms__c FROM Account WHERE Id = :ACCT];
Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String netTerms = String.isBlank(acctRow.Net_Terms__c) ? 'Net_30' : acctRow.Net_Terms__c;
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;

Savepoint sp = Database.setSavepoint();
try {
    // Contact (under the existing account), EUR currency
    Contact c = ((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,
        Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,
        MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode
        FROM Contact WHERE Id = :SRC_CON]).clone(false, true, false, false);
    c.AccountId = ACCT;
    c.LastName  = LABEL;
    c.CurrencyIsoCode = 'EUR';
    if (String.isBlank(c.Workday_Phone_Country_ISO_Code__c))       c.Workday_Phone_Country_ISO_Code__c = 'ITA';
    if (String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c = 'ITA';
    Database.insert(c, dml);

    // Place — Italy address (drives ShipToPlace_Country__c in the pricing context)
    Places__c p = new Places__c(Name = 'Italy HQ G07 ' + TAG, Account__c = ACCT,
        Address__Street__s      = 'Via Roma 1',
        Address__City__s        = 'Milano',
        Address__PostalCode__s  = '20121',
        Address__CountryCode__s = 'IT');
    Database.insert(p, dml);

    // Quote — EUR + Italy shipping/billing country so the prehook resolves multiplier 0.64
    Quote q = new Quote(
        OpportunityId = OPP, Name = LABEL, Status = 'Draft', ExpirationDate = Date.today().addDays(30),
        Pricebook2Id = PB, CurrencyIsoCode = 'EUR', Quote_Type__c = 'New', LegalEntityId = LE,
        QuoteAccountId = ACCT, ContactId = c.Id, BillToContactId = c.Id, SalesTransactionTypeId = STT,
        Net_Terms__c = netTerms, Deal_Type__c = dealType,
        Ship_To_Place__c = p.Id, Bill_To_Place__c = p.Id,
        BillingStreet = 'Via Roma 1', BillingCity = 'Milano', BillingPostalCode = '20121',
        BillingCountry = 'Italy', BillingCountryCode = 'IT',
        ShippingStreet = 'Via Roma 1', ShippingCity = 'Milano', ShippingPostalCode = '20121',
        ShippingCountry = 'Italy', ShippingCountryCode = 'IT');
    Database.insert(q, dml);

    // Services line — qty 1, regional flag true, EUR list
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId = q.Id, Product2Id = PROD, PricebookEntryId = PBE,
        Quantity = 1, UnitPrice = LISTP,
        Allow_Regional_Pricing__c = true);
    Database.insert(qli, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ FIXTURE CREATED G-07  Quote #' + q.QuoteNumber
        + '  (EUR; Italy 0.64; expect list 51403 -> 32900, net stays 51403 EUR)'
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
