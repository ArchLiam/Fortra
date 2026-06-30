// setupAttrServerTypeTestData.compact.apex
// D-03 fixture: Attribute server-type discount config completeness (3-attribute key).
// SC-3360. Proves the AttributeBasedAdjustment 3-attribute key (Feature x Deployment x ServerType)
// on the Advanced Authentication Modes bundle GS-GSE-NRPS-AAMP (01tWC00000DD11YYAT, list $3,150).
//
// Builds ONE Draft quote with THREE AAMP lines, each carrying the 3 price-impacting attributes:
//   L1 TEST     {SFTP Server, On Premise, Non-Production} -> matches NO ABA row -> net stays $3,150 (list)
//   L2 CTRL-A   {SFTP Server, On Premise, Production}     -> ABA row 219 Override 3150 -> net $3,150
//   L3 CTRL-B   {Remote Automation Agent, On Premise, Non-Production} -> ABA row 220 Override 1575 -> net $1,575
// L3 is the proof the ABA branch IS firing (changes net 3150->1575); so L1 staying $3,150 means
// "no matching row" (the SC-3360 gap), not a dead branch. After REPRICE ALL / Force place, read net.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupAttrServerTypeTestData.compact.apex
//       (NOTE: target FortraUAT, not the `uat` alias.)
// Output: grep the debug log for the "D03-ATTR" marker (logged at ERROR level).

// --- Existing records used directly (not modified) --------------------------
Id ACCT = '001WC00000XiZP4YAN';        // "Fortra, LLC - Test"
Id OPP  = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes" (on the account above)
Id SRC_CON = '003WC00000nb7khYAA';     // template Contact (clone for required fields)
Id SRC_PLC = 'a0lWC000004cO79YAE';     // template Place (address source)
Id TPL_Q   = '0Q0WC0000024KOn0AM';     // template Quote (header defaults)
Id PB   = '01sWC0000022GHFYA2';        // Pricebook2 ("Fortra Price Book")
Id LE   = '0fwWC000000034LYAQ';        // Legal Entity
Id STT  = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PBE  = '01uWC000005wrrNYAQ';        // AAMP PBE, Fortra Price Book, USD, UnitPrice 3150

// --- Attribute definition + picklist-value ids (D-03 3-attribute key) -------
Id AD_FO = '0tjWC000000096ZYAQ';       // Feature Options
Id AD_DO = '0tjWC000000096YYAQ';       // Deployment Option
Id AD_ST = '0tjWC000000096jYAA';       // Server Type
Id PV_SFTP   = '0v6WC0000000A1hYAE';   // FO = SFTP Server
Id PV_RAA    = '0v6WC0000000A07YAE';   // FO = Remote Automation Agent
Id PV_ONPREM = '0v6WC00000009mjYAA';   // DO = On Premise
Id PV_PROD   = '0v6WC0000000AJrYAM';   // ST = Production
Id PV_NONPROD= '0v6WC0000000AJpYAM';   // ST = Non-Production

String TAG   = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
String LABEL = 'D03 AttrServerType ' + TAG;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;

Savepoint sp = Database.setSavepoint();
try {
    // --- Contact (required for header consistency) --------------------------
    Contact c = ((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,
        Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,
        MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode
        FROM Contact WHERE Id = :SRC_CON]).clone(false, true, false, false);
    c.AccountId = ACCT;
    c.LastName  = LABEL;
    if (String.isBlank(c.Workday_Phone_Country_ISO_Code__c))       c.Workday_Phone_Country_ISO_Code__c = 'USA';
    if (String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c = 'USA';
    Database.insert(c, dml);

    // --- Place (address source) ---------------------------------------------
    Places__c srcPlace = [SELECT Address__Street__s,Address__City__s,Address__StateCode__s,
        Address__PostalCode__s,Address__CountryCode__s FROM Places__c WHERE Id = :SRC_PLC];
    Places__c p = new Places__c(Name = 'D03 HQ ' + TAG, Account__c = ACCT,
        Address__Street__s      = srcPlace.Address__Street__s,
        Address__City__s        = srcPlace.Address__City__s,
        Address__StateCode__s   = srcPlace.Address__StateCode__s,
        Address__PostalCode__s  = srcPlace.Address__PostalCode__s,
        Address__CountryCode__s = srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    // --- Quote (Direct/Fortra-Originated so partner discount doesn't confound) ---
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

    // --- Three AAMP lines ----------------------------------------------------
    QuoteLineItem l1 = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=PBE, Quantity=1, StartQuantity=1,
        StartDate=Date.today(), EndDate=Date.today().addYears(1));
    QuoteLineItem l2 = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=PBE, Quantity=1, StartQuantity=1,
        StartDate=Date.today(), EndDate=Date.today().addYears(1));
    QuoteLineItem l3 = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=PBE, Quantity=1, StartQuantity=1,
        StartDate=Date.today(), EndDate=Date.today().addYears(1));
    List<QuoteLineItem> lines = new List<QuoteLineItem>{ l1, l2, l3 };
    Database.insert(lines, dml);

    // --- Attribute rows (price-impacting) for each line ---------------------
    List<QuoteLineItemAttribute> attrs = new List<QuoteLineItemAttribute>();
    // L1 TEST: SFTP / On Premise / Non-Production  (no ABA row -> expect net 3150)
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l1.Id, AttributeDefinitionId=AD_FO,   AttributeValue='SFTP Server',     AttributePicklistValueId=PV_SFTP));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l1.Id, AttributeDefinitionId=AD_DO, AttributeValue='On Premise',      AttributePicklistValueId=PV_ONPREM));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l1.Id, AttributeDefinitionId=AD_ST,       AttributeValue='Non-Production',  AttributePicklistValueId=PV_NONPROD));
    // L2 CTRL-A: SFTP / On Premise / Production  (ABA row 219 Override 3150)
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l2.Id, AttributeDefinitionId=AD_FO,   AttributeValue='SFTP Server',     AttributePicklistValueId=PV_SFTP));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l2.Id, AttributeDefinitionId=AD_DO, AttributeValue='On Premise',      AttributePicklistValueId=PV_ONPREM));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l2.Id, AttributeDefinitionId=AD_ST,       AttributeValue='Production',      AttributePicklistValueId=PV_PROD));
    // L3 CTRL-B: Remote Automation Agent / On Premise / Non-Production  (ABA row 220 Override 1575)
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l3.Id, AttributeDefinitionId=AD_FO,   AttributeValue='Remote Automation Agent', AttributePicklistValueId=PV_RAA));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l3.Id, AttributeDefinitionId=AD_DO, AttributeValue='On Premise',      AttributePicklistValueId=PV_ONPREM));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=l3.Id, AttributeDefinitionId=AD_ST,       AttributeValue='Non-Production',  AttributePicklistValueId=PV_NONPROD));
    Database.insertImmediate(attrs);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ D03-ATTR CREATED  Quote #' + q.QuoteNumber
        + '\n  Quote : ' + base + '/' + q.Id
        + '\n  L1 TEST   {SFTP,OnPrem,NonProd}  : ' + base + '/' + l1.Id + '  (expect net 3150 = list, NO ABA match)'
        + '\n  L2 CTRL-A {SFTP,OnPrem,Prod}     : ' + base + '/' + l2.Id + '  (expect net 3150, ABA row 219)'
        + '\n  L3 CTRL-B {RAA,OnPrem,NonProd}   : ' + base + '/' + l3.Id + '  (expect net 1575, ABA row 220)'
        + '\n  IDS l1=' + l1.Id + ' l2=' + l2.Id + ' l3=' + l3.Id + ' quote=' + q.Id
        + '\n  NEXT  : Force-reprice this Quote, then read NetUnitPrice on each line.');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ D03-ATTR FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
