// setupTieredConvertTestData.compact.apex
// Builds a B-07 (V21 validation) "Usage/tiered model on Quote-to-Order convert" CONVERT-READY QUOTE
// fixture in FortraUAT. B-07 tests: after converting a tiered (CalculationMatrix attribute-keyed)
// subscription line to an Order and running Reprice-All, does the matrix attribute
// (Number_of_Units + Attribute_Volume) hydrate on the OrderItem context via OrderEntitiesMapping and
// re-evaluate the SAME tier it resolved on the Quote (no $0 no-match from a missing order-side mapping)?
//
// Combines the B-03 tiered-attribute QLI with the I-02 convert preconditions:
//   Product : 01tWC00000DD1BUYA1  "Device Profiler Ev Express" (FIM-FIM-RSS-DPEEXS, Subscription)
//   PSM/PBE : 01uWC000005wrtuYAA  Fortra Price Book (active), USD, TermDefined "Term Based - Annual", list 325
//   Tier key: Number of Units = '1-50' (Attribute_Value__c), Unit Price mode, OverrideAmount
//   Ladder  : vol 1-25 -> 468 | 26-50 -> 400 | 51-100 -> 375 | 101-250 -> 330 ...
//   Attribute_Volume = 30 (range 26-50) -> ORACLE: NetUnitPrice = 400 (Unit Price mode), NOT list 325, NOT tier-1 468.
//   Opportunity : 006WC00000RPVp3YAH (Account has Places + Contact for convert).
//
// Eligibility: prehook gates on Has_Attribute_Adjustment__c = true (set on the QLI). It reads the
// 'Number_of_Units' QLIA for the tier key and the 'Attribute_Volume' QLIA for the range.
//
// Convert preconditions handled (same set as the I-02/SC-3441 fixtures): Quote.StartDate, BillTo/Quote
// Contact, Bill/Ship Place + Billing/Shipping address TEXT (all related to the Account), Account Type/DUNS.
// QuoteLineItemAttribute requires Database.insertImmediate (autonomous commit), incompatible with a
// savepoint around the Quote+QLI, so commit Quote+QLI first then insertImmediate the QLIAs.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupTieredConvertTestData.compact.apex
// Output: grep the debug log for the "TIER-CONVERT-QUOTE" marker (logged at ERROR level).

Id OPP     = '006WC00000RPVp3YAH';
Id PBE_ID  = '01uWC000005wrtuYAA';            // Device Profiler Ev Express, TermDefined Annual, USD, list 325
Id ADEF_NOU= '0tjWC000000096dYAA';            // Number of Units (Picklist)
Id ADEF_VOL= '0tjWC0000000tqvYAA';            // Unit Volume / Attribute_Volume (Number)
Id APV_NOU = '0v6WC0000000A7tYAE';            // AttributePicklistValue for '1-50'
String NOU_VALUE = '1-50';                    // tier Attribute_Value__c
Decimal VOL_VALUE = 30;                       // range 26-50 -> tier 400
Decimal EXPECTED_NET = 400;                   // oracle

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity oppRec = [SELECT Id, AccountId FROM Opportunity WHERE Id = :OPP];
Id ACCT = oppRec.AccountId;
PricebookEntry pbe = [SELECT Id, Pricebook2Id, Product2Id, Product2.Name, UnitPrice, CurrencyIsoCode
                      FROM PricebookEntry WHERE Id = :PBE_ID];

List<Places__c> places = [SELECT Id, Address__Street__s, Address__City__s, Address__StateCode__s,
                                 Address__PostalCode__s, Address__CountryCode__s
                          FROM Places__c WHERE Account__c = :ACCT LIMIT 1];
List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :ACCT LIMIT 1];
Places__c plc = places.isEmpty() ? null : places[0];
Id PLACE   = plc == null ? null : plc.Id;
Id CONTACT = contacts.isEmpty() ? null : contacts[0].Id;
String adrStreet  = plc == null ? null : plc.Address__Street__s;
String adrCity    = plc == null ? null : plc.Address__City__s;
String adrState   = plc == null ? null : plc.Address__StateCode__s;
String adrZip     = plc == null ? null : plc.Address__PostalCode__s;
String adrCountry = plc == null ? null : plc.Address__CountryCode__s;

Account acc = [SELECT Id, Type, DB_DUNS__c FROM Account WHERE Id = :ACCT];
Boolean accDirty = false;
if (acc.Type == null)               { acc.Type = 'Customer'; accDirty = true; }
if (String.isBlank(acc.DB_DUNS__c)) { acc.DB_DUNS__c = String.valueOf(Datetime.now().getTime()).right(9); accDirty = true; }
if (accDirty) { Database.update(acc, dml); }

Quote q = new Quote(
    Name            = 'B07 Tiered Convert ' + TAG,
    OpportunityId   = OPP,
    Pricebook2Id    = pbe.Pricebook2Id,
    Status          = 'Draft',
    Quote_Type__c   = 'New',
    CurrencyIsoCode = 'USD',
    StartDate       = Date.today(),
    ExpirationDate  = Date.today().addDays(30),
    BillToContactId = CONTACT,
    ContactId       = CONTACT,
    Bill_To_Place__c= PLACE,
    Ship_To_Place__c= PLACE,
    BillingStreet      = adrStreet,  BillingCity        = adrCity,
    BillingStateCode   = adrState,   BillingPostalCode  = adrZip,   BillingCountryCode  = adrCountry,
    ShippingStreet     = adrStreet,  ShippingCity       = adrCity,
    ShippingStateCode  = adrState,   ShippingPostalCode = adrZip,   ShippingCountryCode = adrCountry);
Database.insert(q, dml);

QuoteLineItem qli = new QuoteLineItem(
    QuoteId                     = q.Id,
    PricebookEntryId            = pbe.Id,
    Product2Id                  = pbe.Product2Id,
    Quantity                    = 1,
    StartDate                   = Date.today(),
    EndDate                     = Date.today().addYears(1),
    SubscriptionTerm            = 1,
    BillingFrequency            = 'Annual',
    PeriodBoundary              = 'Anniversary',
    Has_Attribute_Adjustment__c = true);
Database.SaveResult sr = Database.insert(qli, dml);
String qliErr = '';
if (!sr.isSuccess()) { for (Database.Error e : sr.getErrors()) { qliErr += e.getStatusCode() + ': ' + e.getMessage() + ' | '; } }

Id qliId = sr.getId();
if (qliId == null) {
    List<QuoteLineItem> found = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id AND Product2Id = :pbe.Product2Id ORDER BY CreatedDate DESC LIMIT 1];
    qliId = found.isEmpty() ? null : found[0].Id;
}

String attrErr = '';
if (qliId != null) {
    List<QuoteLineItemAttribute> attrs = new List<QuoteLineItemAttribute>{
        new QuoteLineItemAttribute(QuoteLineItemId = qliId, AttributeDefinitionId = ADEF_NOU,
            AttributePicklistValueId = APV_NOU, AttributeValue = NOU_VALUE),
        new QuoteLineItemAttribute(QuoteLineItemId = qliId, AttributeDefinitionId = ADEF_VOL,
            AttributeValue = String.valueOf(VOL_VALUE.setScale(0)))
    };
    try { Database.insertImmediate(attrs); } catch (Exception ae) { attrErr = ae.getTypeName() + ': ' + ae.getMessage(); }
}

String base = URL.getOrgDomainUrl().toExternalForm();
System.debug(LoggingLevel.ERROR, '✅ TIER-CONVERT-QUOTE CREATED (B-07, convert-ready)'
    + '\n  Quote   : ' + base + '/' + q.Id
    + '\n  Account : ' + ACCT + '  | Bill/Ship Place=' + PLACE + '  | BillToContact=' + CONTACT
    + '\n  QLI     : ' + base + '/' + qliId + '  | ' + pbe.Product2.Name + '  | Qty 1  | insertSuccess=' + sr.isSuccess()
    + (qliErr == '' ? '' : '  | QLI-ERR=' + qliErr)
    + '\n  Attrs   : Number of Units=' + NOU_VALUE + '  Attribute_Volume=' + VOL_VALUE
    + (attrErr == '' ? '' : '  | ATTR-ERR=' + attrErr)
    + '\n  ORACLE  : Quote Force-reprice NetUnitPrice=' + EXPECTED_NET + '; after convert+Reprice-All the OrderItem'
    + ' tier must RE-EVALUATE to the SAME ' + EXPECTED_NET + ' (Number_of_Units+Attribute_Volume hydrated on OrderItem).'
    + '\n  NEXT    : (1) Force-reprice Quote; (2) convert to Order (reprice BEFORE Activate); (3) Force-reprice Order; re-query OrderItem.NetUnitPrice + OrderItemAttribute.'
    + (PLACE == null   ? '\n  ⚠ No Places__c on account — convert will block.' : '')
    + (CONTACT == null ? '\n  ⚠ No Contact on account — convert will block.' : ''));
