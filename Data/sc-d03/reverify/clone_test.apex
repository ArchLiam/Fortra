// D-03 reverify: clone the PASSING RAA control quote's line-creation EXACTLY, but build TWO
// quotes - one RAA (positive control) and one SFTP+NonProd - using the SAME insert path,
// then we reprice both. If SFTP hydrates UnitPrice=3150 base (then resolves via ABA) it's config;
// if SFTP nets $0/null base while RAA hydrates, it's the Apex-insert hydration artifact.
Id ACCT='001WC00000XiZP4YAN'; Id OPP='006WC00000OE0NKYA1'; Id PB='01sWC0000022GHFYA2';
Id LE='0fwWC000000034LYAQ'; Id STT='1ChWC0000002eJ70AI'; Id PBE='01uWC000005wrrNYAQ';
Id SRC_CON='003WC00000nb7khYAA'; Id SRC_PLC='a0lWC000004cO79YAE'; Id TPL_Q='0Q0WC0000024KOn0AM';
Id AD_FO='0tjWC000000096ZYAQ'; Id AD_DO='0tjWC000000096YYAQ'; Id AD_ST='0tjWC000000096jYAA';
Id PV_SFTP='0v6WC0000000A1hYAE'; Id PV_RAA='0v6WC0000000A07YAE';
Id PV_ONPREM='0v6WC00000009mjYAA'; Id PV_NONPROD='0v6WC0000000AJpYAM';
String TAG=Datetime.now().format('yyyy-MM-dd HH:mm:ss');
Database.DMLOptions dml=new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave=true; dml.DuplicateRuleHeader.RunAsCurrentUser=true;
Quote tq=[SELECT Header_Discount_Type__c,Payment_Portal__c,Disable_Export_Control__c,Language__c FROM Quote WHERE Id=:TPL_Q];
Places__c srcP=[SELECT Address__Street__s,Address__City__s,Address__StateCode__s,Address__PostalCode__s,Address__CountryCode__s FROM Places__c WHERE Id=:SRC_PLC];
Savepoint sp=Database.setSavepoint();
try{
 Contact c=((Contact)[SELECT FirstName,LastName,Email,Phone,MobilePhone,Title,CurrencyIsoCode,Workday_Phone_Country_ISO_Code__c,Workday_MobilePhone_Country_ISO_Code__c,MailingStreet,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingCountryCode,MailingStateCode FROM Contact WHERE Id=:SRC_CON]).clone(false,true,false,false);
 c.AccountId=ACCT; c.LastName='D03 REV '+TAG;
 if(String.isBlank(c.Workday_Phone_Country_ISO_Code__c)) c.Workday_Phone_Country_ISO_Code__c='USA';
 if(String.isBlank(c.Workday_MobilePhone_Country_ISO_Code__c)) c.Workday_MobilePhone_Country_ISO_Code__c='USA';
 Database.insert(c,dml);
 Places__c p=new Places__c(Name='D03 REV HQ '+TAG,Account__c=ACCT,Address__Street__s=srcP.Address__Street__s,Address__City__s=srcP.Address__City__s,Address__StateCode__s=srcP.Address__StateCode__s,Address__PostalCode__s=srcP.Address__PostalCode__s,Address__CountryCode__s=srcP.Address__CountryCode__s);
 Database.insert(p,dml);
 List<Quote> qs=new List<Quote>();
 for(String sfx:new List<String>{'SFTP','RAA'}){
  qs.add(new Quote(OpportunityId=OPP,Name='D03-REV-'+sfx+' '+TAG,Status='Draft',ExpirationDate=Date.today().addDays(30),StartDate=Date.today(),Pricebook2Id=PB,CurrencyIsoCode='USD',Quote_Type__c='New',LegalEntityId=LE,QuoteAccountId=ACCT,ContactId=c.Id,BillToContactId=c.Id,SalesTransactionTypeId=STT,Language__c=tq.Language__c!=null?tq.Language__c:'English',Deal_Type__c='Fortra Originated',Header_Discount_Type__c=tq.Header_Discount_Type__c!=null?tq.Header_Discount_Type__c:'Amount',Payment_Portal__c=tq.Payment_Portal__c!=null?tq.Payment_Portal__c:'Fortra (default)',Disable_Export_Control__c=tq.Disable_Export_Control__c!=null?tq.Disable_Export_Control__c:false,Ship_To_Place__c=p.Id,Bill_To_Place__c=p.Id,BillingStreet=p.Address__Street__s,BillingCity=p.Address__City__s,BillingStateCode=p.Address__StateCode__s,BillingPostalCode=p.Address__PostalCode__s,BillingCountryCode=p.Address__CountryCode__s,ShippingStreet=p.Address__Street__s,ShippingCity=p.Address__City__s,ShippingStateCode=p.Address__StateCode__s,ShippingPostalCode=p.Address__PostalCode__s,ShippingCountryCode=p.Address__CountryCode__s));
 }
 Database.insert(qs,dml);
 Quote qSftp=qs[0], qRaa=qs[1];
 QuoteLineItem lS=new QuoteLineItem(QuoteId=qSftp.Id,PricebookEntryId=PBE,Quantity=1,StartQuantity=1,StartDate=Date.today(),EndDate=Date.today().addYears(1));
 QuoteLineItem lR=new QuoteLineItem(QuoteId=qRaa.Id,PricebookEntryId=PBE,Quantity=1,StartQuantity=1,StartDate=Date.today(),EndDate=Date.today().addYears(1));
 Database.insert(new List<QuoteLineItem>{lS,lR},dml);
 List<QuoteLineItemAttribute> attrs=new List<QuoteLineItemAttribute>();
 attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lS.Id,AttributeDefinitionId=AD_FO,AttributeValue='SFTP Server',AttributePicklistValueId=PV_SFTP));
 attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lS.Id,AttributeDefinitionId=AD_DO,AttributeValue='On Premise',AttributePicklistValueId=PV_ONPREM));
 attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lS.Id,AttributeDefinitionId=AD_ST,AttributeValue='Non-Production',AttributePicklistValueId=PV_NONPROD));
 attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lR.Id,AttributeDefinitionId=AD_FO,AttributeValue='Remote Automation Agent',AttributePicklistValueId=PV_RAA));
 attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lR.Id,AttributeDefinitionId=AD_DO,AttributeValue='On Premise',AttributePicklistValueId=PV_ONPREM));
 attrs.add(new QuoteLineItemAttribute(QuoteLineItemId=lR.Id,AttributeDefinitionId=AD_ST,AttributeValue='Non-Production',AttributePicklistValueId=PV_NONPROD));
 Database.insertImmediate(attrs);
 System.debug(LoggingLevel.ERROR,'D03-REV CREATED qSFTP='+qSftp.Id+' qRAA='+qRaa.Id+' lS='+lS.Id+' lR='+lR.Id);
}catch(Exception e){Database.rollback(sp);System.debug(LoggingLevel.ERROR,'D03-REV FAILED '+e.getMessage());throw e;}
