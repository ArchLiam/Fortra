// setupD03IsolatedTestData.compact.apex
// D-03 ISOLATION fixture: one SINGLE-LINE quote PER attribute combination, to separate the
// ABA 3-attribute-key match from the multi-identical-line $0 collapse (SC-3360 defect #2).
// Same AAMP product GS-GSE-NRPS-AAMP (01tWC00000DD11YYAT, list $3,150) as setupAttrServerType.
//   QA {SFTP, On Premise, Non-Production} -> ABA row 00022883 Override 1575 -> expect net 1575 (List x 0.5)
//   QB {SFTP, On Premise, Production}      -> ABA row 00000219 Override 3150 -> expect net 3150
//   QC {Remote Automation Agent, On Premise, Non-Production} -> ABA row 00000220 Override 1575 -> expect net 1575
// Each on its OWN quote so each AAMP line is the FIRST/only line in its container.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupD03IsolatedTestData.compact.apex
// Output: grep the debug log for "D03-ISO" (ERROR level).

Id ACCT = '001WC00000XiZP4YAN';
Id OPP  = '006WC00000OE0NKYA1';
Id SRC_CON = '003WC00000nb7khYAA';
Id SRC_PLC = 'a0lWC000004cO79YAE';
Id TPL_Q   = '0Q0WC0000024KOn0AM';
Id PB   = '01sWC0000022GHFYA2';
Id LE   = '0fwWC000000034LYAQ';
Id STT  = '1ChWC0000002eJ70AI';
Id PBE  = '01uWC000005wrrNYAQ';

Id AD_FO = '0tjWC000000096ZYAQ';   // Feature Options
Id AD_DO = '0tjWC000000096YYAQ';   // Deployment Option
Id AD_ST = '0tjWC000000096jYAA';   // Server Type
Id PV_SFTP   = '0v6WC0000000A1hYAE';
Id PV_RAA    = '0v6WC0000000A07YAE';
Id PV_ONPREM = '0v6WC00000009mjYAA';
Id PV_PROD   = '0v6WC0000000AJrYAM';
Id PV_NONPROD= '0v6WC0000000AJpYAM';

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity oppRow = [SELECT Id, Deal_Origin__c FROM Opportunity WHERE Id = :OPP];
String dealType = String.isBlank(oppRow.Deal_Origin__c) ? 'Fortra Originated' : oppRow.Deal_Origin__c;

Quote tq = [SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c FROM Quote WHERE Id = :TPL_Q];
Places__c srcPlace = [SELECT Address__Street__s,Address__City__s,Address__StateCode__s,Address__PostalCode__s,Address__CountryCode__s FROM Places__c WHERE Id = :SRC_PLC];

Savepoint sp = Database.setSavepoint();
try {
    Contact c = ((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,
        Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,
        MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode
        FROM Contact WHERE Id = :SRC_CON]).clone(false, true, false, false);
    c.AccountId = ACCT; c.LastName = 'D03 ISO ' + TAG;
    if (String.isBlank(c.Workday_Phone_Country_ISO_Code__c))       c.Workday_Phone_Country_ISO_Code__c = 'USA';
    if (String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c = 'USA';
    Database.insert(c, dml);

    Places__c p = new Places__c(Name='D03 ISO HQ '+TAG, Account__c=ACCT,
        Address__Street__s=srcPlace.Address__Street__s, Address__City__s=srcPlace.Address__City__s,
        Address__StateCode__s=srcPlace.Address__StateCode__s, Address__PostalCode__s=srcPlace.Address__PostalCode__s,
        Address__CountryCode__s=srcPlace.Address__CountryCode__s);
    Database.insert(p, dml);

    List<Quote> quotes = new List<Quote>();
    for (String sfx : new List<String>{'A','B','C'}) {
        quotes.add(new Quote(OpportunityId=OPP, Name='D03-ISO-'+sfx+' '+TAG, Status='Draft',
            ExpirationDate=Date.today().addDays(30), StartDate=Date.today(),
            Pricebook2Id=PB, CurrencyIsoCode='USD', Quote_Type__c='New', LegalEntityId=LE,
            QuoteAccountId=ACCT, ContactId=c.Id, BillToContactId=c.Id, SalesTransactionTypeId=STT,
            Language__c = tq.Language__c!=null?tq.Language__c:'English', Deal_Type__c=dealType,
            Header_Discount_Type__c = tq.Header_Discount_Type__c!=null?tq.Header_Discount_Type__c:'Amount',
            Payment_Portal__c = tq.Payment_Portal__c!=null?tq.Payment_Portal__c:'Fortra (default)',
            Disable_Export_Control__c = tq.Disable_Export_Control__c!=null?tq.Disable_Export_Control__c:false,
            Ship_To_Place__c=p.Id, Bill_To_Place__c=p.Id,
            BillingStreet=p.Address__Street__s, BillingCity=p.Address__City__s, BillingStateCode=p.Address__StateCode__s,
            BillingPostalCode=p.Address__PostalCode__s, BillingCountryCode=p.Address__CountryCode__s,
            ShippingStreet=p.Address__Street__s, ShippingCity=p.Address__City__s, ShippingStateCode=p.Address__StateCode__s,
            ShippingPostalCode=p.Address__PostalCode__s, ShippingCountryCode=p.Address__CountryCode__s));
    }
    Database.insert(quotes, dml);
    Quote qA = quotes[0], qB = quotes[1], qC = quotes[2];

    QuoteLineItem la = new QuoteLineItem(QuoteId=qA.Id, PricebookEntryId=PBE, Quantity=1, StartQuantity=1, StartDate=Date.today(), EndDate=Date.today().addYears(1));
    QuoteLineItem lb = new QuoteLineItem(QuoteId=qB.Id, PricebookEntryId=PBE, Quantity=1, StartQuantity=1, StartDate=Date.today(), EndDate=Date.today().addYears(1));
    QuoteLineItem lc = new QuoteLineItem(QuoteId=qC.Id, PricebookEntryId=PBE, Quantity=1, StartQuantity=1, StartDate=Date.today(), EndDate=Date.today().addYears(1));
    Database.insert(new List<QuoteLineItem>{la, lb, lc}, dml);

    List<QuoteLineItemAttribute> attrs = new List<QuoteLineItemAttribute>();
    // A: SFTP / On Premise / Non-Production  (expect 1575 via ABA 00022883)
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=la.Id, AttributeDefinitionId=AD_FO, AttributeValue='SFTP Server',    AttributePicklistValueId=PV_SFTP));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=la.Id, AttributeDefinitionId=AD_DO, AttributeValue='On Premise',     AttributePicklistValueId=PV_ONPREM));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=la.Id, AttributeDefinitionId=AD_ST, AttributeValue='Non-Production', AttributePicklistValueId=PV_NONPROD));
    // B: SFTP / On Premise / Production  (expect 3150 via ABA 00000219)
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lb.Id, AttributeDefinitionId=AD_FO, AttributeValue='SFTP Server',    AttributePicklistValueId=PV_SFTP));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lb.Id, AttributeDefinitionId=AD_DO, AttributeValue='On Premise',     AttributePicklistValueId=PV_ONPREM));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lb.Id, AttributeDefinitionId=AD_ST, AttributeValue='Production',     AttributePicklistValueId=PV_PROD));
    // C: RAA / On Premise / Non-Production  (expect 1575 via ABA 00000220)
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lc.Id, AttributeDefinitionId=AD_FO, AttributeValue='Remote Automation Agent', AttributePicklistValueId=PV_RAA));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lc.Id, AttributeDefinitionId=AD_DO, AttributeValue='On Premise',     AttributePicklistValueId=PV_ONPREM));
    attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lc.Id, AttributeDefinitionId=AD_ST, AttributeValue='Non-Production', AttributePicklistValueId=PV_NONPROD));
    Database.insertImmediate(attrs);

    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, 'D03-ISO CREATED'
        + '\n  QA {SFTP,OnPrem,NonProd} expect 1575 : ' + base + '/' + qA.Id + ' QLI=' + la.Id
        + '\n  QB {SFTP,OnPrem,Prod}    expect 3150 : ' + base + '/' + qB.Id + ' QLI=' + lb.Id
        + '\n  QC {RAA,OnPrem,NonProd}  expect 1575 : ' + base + '/' + qC.Id + ' QLI=' + lc.Id
        + '\n  IDS qA=' + qA.Id + ' qB=' + qB.Id + ' qC=' + qC.Id
        + '\n  QLIS la=' + la.Id + ' lb=' + lb.Id + ' lc=' + lc.Id);
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'D03-ISO FAILED (rolled back) [' + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
