// setupG02CurrencyAbaTestData.compact.apex
// G-02 (Multi-Currency / Regional): Configured pricing (ABA/server-type) ignores quote currency.
// SC-3384 / SC-3360. Builds a clean DIRECT (no-partner) NEW EUR Quote on the AAMP bundle
// GS-GSE-NRPS-AAMP (01tWC00000DD11YYAT) using the EUR PBE (01uWC000005wyIIYAY, list 2943.99 EUR
// = 3150 USD x 0.9346) and the 3-attribute ABA key (Feature x Deployment x ServerType).
//
// The AttributeBasedAdjustment table is 100% USD (13,073 rows, 0 non-USD). For AAMP the active
// Override rows = 1575 USD (220/22883); the 3150 row (219) is EXPIRED 2026-06-01. The ABA lookup
// has NO CurrencyIsoCode discriminator in the decision-table composite key (the defect).
//
//   L1 MATCH  {Remote Automation Agent, On Premise, Non-Production} -> matches active ABA row 220/22883
//             Override 1575.  CURRENCY-AWARE expected: EUR list 2943.99 (no EUR ABA row -> list) OR a
//             seeded EUR override. DEFECT signature: net = 1575 (raw USD override leaked into EUR line).
//   L2 CTRL   {SFTP Server, On Premise, Non-Production} -> matches NO active ABA row -> net = EUR list
//             2943.99 (proves base PBE currency-match works; isolates the ABA-only currency leak).
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupG02CurrencyAbaTestData.compact.apex
// Output: grep the debug log for the "G02-CURABA" marker (logged at ERROR level).

Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000QnybxYAB';        // "Wren - Test Currencies" (EUR Opp -> Quote inherits EUR)
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 (Fortra Price Book)
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PROD = '01tWC00000DD11YYAT';        // AAMP (Perpetual, configured/ABA)
Id PBE  = '01uWC000005wyIIYAY';        // AAMP PBE, EUR, Fortra Price Book, UnitPrice 2943.99
String CUR = 'EUR';
Decimal MULT = 0.9346;

// --- Attribute definition + picklist-value ids (3-attribute ABA key) -------
Id AD_FO = '0tjWC000000096ZYAQ';       // Feature Options
Id AD_DO = '0tjWC000000096YYAQ';       // Deployment Option
Id AD_ST = '0tjWC000000096jYAA';       // Server Type
Id PV_SFTP   = '0v6WC0000000A1hYAE';   // FO = SFTP Server
Id PV_RAA    = '0v6WC0000000A07YAE';   // FO = Remote Automation Agent
Id PV_ONPREM = '0v6WC00000009mjYAA';   // DO = On Premise
Id PV_NONPROD= '0v6WC0000000AJpYAM';   // ST = Non-Production

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'LJ G-02 CurrABA ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;
PricebookEntry pbeEur = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Id = :PBE];

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
    Places__c p = new Places__c(Name = 'G-02 HQ ' + TAG, Account__c = ACCT,
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

    QuoteLineItem l1 = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=PBE, Product2Id=PROD, Quantity=1, StartQuantity=1,
        StartDate=Date.today(), EndDate=Date.today().addYears(1));
    QuoteLineItem l2 = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=PBE, Product2Id=PROD, Quantity=1, StartQuantity=1,
        StartDate=Date.today(), EndDate=Date.today().addYears(1));
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ l1, l2 };
    Database.insert(lines, dml);

    List<QuoteLineItemAttribute> attrs = new List<QuoteLineItemAttribute>();
    // L1 MATCH: RAA / On Premise / Non-Production  (active ABA Override 1575 USD)
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l1.Id, AttributeDefinitionId=AD_FO, AttributeValue='Remote Automation Agent', AttributePicklistValueId=PV_RAA));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l1.Id, AttributeDefinitionId=AD_DO, AttributeValue='On Premise',     AttributePicklistValueId=PV_ONPREM));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l1.Id, AttributeDefinitionId=AD_ST, AttributeValue='Non-Production', AttributePicklistValueId=PV_NONPROD));
    // L2 CTRL: SFTP / On Premise / Non-Production  (no active ABA row -> EUR list 2943.99)
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l2.Id, AttributeDefinitionId=AD_FO, AttributeValue='SFTP Server',    AttributePicklistValueId=PV_SFTP));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l2.Id, AttributeDefinitionId=AD_DO, AttributeValue='On Premise',     AttributePicklistValueId=PV_ONPREM));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l2.Id, AttributeDefinitionId=AD_ST, AttributeValue='Non-Production', AttributePicklistValueId=PV_NONPROD));
    Database.insertImmediate(attrs);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, 'GG02-CURABA CREATED  Quote #' + q.QuoteNumber + ' currency=' + CUR
        + '\n  Quote : ' + base + '/' + q.Id
        + '\n  L1 MATCH {RAA,OnPrem,NonProd} : ' + base + '/' + l1.Id + '  (EUR list ' + pbeEur.UnitPrice + '; ABA active Override 1575 USD; DEFECT if net=1575)'
        + '\n  L2 CTRL  {SFTP,OnPrem,NonProd}: ' + base + '/' + l2.Id + '  (no ABA row -> expect net ' + pbeEur.UnitPrice + ' EUR)'
        + '\n  IDS l1=' + l1.Id + ' l2=' + l2.Id + ' quote=' + q.Id
        + '\n  EUR list=' + pbeEur.UnitPrice + ' | currency-aware expect net=' + pbeEur.UnitPrice + ' | USD-leak signature=1575 | EUR-of-override=' + (1575 * MULT).setScale(2)
        + '\n  NEXT  : Force-reprice this Quote, then read NetUnitPrice on each line.');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'GG02-CURABA FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage()
        + ' | stack: ' + e.getStackTraceString());
    throw e;
}
