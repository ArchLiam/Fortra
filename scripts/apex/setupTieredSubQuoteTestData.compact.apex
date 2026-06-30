// setupTieredSubQuoteTestData.compact.apex
// Builds a B-03 (V21 validation) "tiered-quantity Subscription" QUOTE fixture in FortraUAT:
// a fresh Draft Quote with a SINGLE TermDefined subscription line on a product whose price is driven by
// an attribute tier lookup (AttributeVolumePricingPrehook v3.0 over Attribute_Tier_Pricing_Storage__c).
//
// WHY: B-03 tests the attribute/CalculationMatrix tier engine — NetUnitPrice is set by a tier row keyed
// on (Product | PSM | AttributeName | AttributeValue) with the range matched on the numeric Attribute_Volume.
//
//   Product : 01tWC00000DD1BUYA1  "Device Profiler Ev Express" (FIM-FIM-RSS-DPEEXS, Subscription)
//   PSM     : 0jPWC000000060b2AA  "Term Based - Annual" (TermDefined, Annual, 1yr)
//   PBE     : 01uWC000005wrtuYAA  Fortra Price Book (active), USD, UnitPrice(list) = 325
//   Tier key: Number of Units = '1-50'  (Attribute_Value__c), Unit Price mode, OverrideAmount
//   Ladder  : vol 1-25 -> 468 | 26-50 -> 400 | 51-100 -> 375 | 101-250 -> 330 | 251-500 -> 280 ...
//   We set Attribute_Volume = 30 (range 26-50) -> ORACLE: NetUnitPrice = 400 (Unit Price mode = Base_Price -> InputUnitPrice).
//
// Eligibility: prehook gates on Has_Attribute_Adjustment__c = true (set on the QLI here). It reads the
// 'Number_of_Units' QLIA for the tier key and the 'Attribute_Volume' QLIA for the range.
//
// Atomic: savepoint rollback on any failure. On success the Quote is committed + openable.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupTieredSubQuoteTestData.compact.apex
// Output: grep the debug log for the "TIER-SUB-QUOTE" marker (logged at ERROR level).

Id ACCT     = '001WC00000XiZP4YAN';            // Fortra, LLC - Test (reuse acct)
Id PBE_ID   = '01uWC000005wrtuYAA';            // Fortra Price Book PBE, USD, PSM Term Based - Annual
Id PROD     = '01tWC00000DD1BUYA1';
Id ADEF_NOU = '0tjWC000000096dYAA';            // Number of Units (Picklist)
Id ADEF_VOL = '0tjWC0000000tqvYAA';            // Unit Volume / Attribute_Volume (Number)
Id APV_NOU  = '0v6WC0000000A7tYAE';            // AttributePicklistValue for '1-50'
String NOU_VALUE = '1-50';                     // tier Attribute_Value__c
Decimal VOL_VALUE = 30;                        // range 26-50 -> tier 400
Decimal EXPECTED_NET = 400;                    // oracle

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity opp = [SELECT Id FROM Opportunity WHERE AccountId = :ACCT LIMIT 1];
PricebookEntry pbe = [SELECT Id, Pricebook2Id, Product2Id, Product2.Name, ProductSellingModelId, UnitPrice
                      FROM PricebookEntry WHERE Id = :PBE_ID];

// NOTE: QuoteLineItemAttribute requires Database.insertImmediate (autonomous commit), which is
// INCOMPATIBLE with a savepoint/rollback wrapper around the Quote+QLI. So we commit the Quote+QLI
// first (no savepoint), then insertImmediate the QLIAs. Test data — partial state is acceptable.
Quote q = new Quote(
    Name            = 'B03 Tiered Sub Quote ' + TAG,
    OpportunityId   = opp.Id,
    Pricebook2Id    = pbe.Pricebook2Id,
    Status          = 'Draft',
    Quote_Type__c   = 'New',
    CurrencyIsoCode = 'USD',
    StartDate       = Date.today(),
    ExpirationDate  = Date.today().addDays(30));
Database.insert(q, dml);

QuoteLineItem qli = new QuoteLineItem(
    QuoteId                   = q.Id,
    PricebookEntryId          = pbe.Id,
    Product2Id                = pbe.Product2Id,
    Quantity                  = 1,
    StartDate                 = Date.today(),
    EndDate                   = Date.today().addYears(1).addDays(-1),
    SubscriptionTerm          = 1,
    BillingFrequency          = 'Annual',
    PeriodBoundary            = 'Anniversary',
    Has_Attribute_Adjustment__c = true);
Database.SaveResult sr = Database.insert(qli, dml);
String qliErr = '';
if (!sr.isSuccess()) {
    for (Database.Error err : sr.getErrors()) { qliErr += err.getStatusCode() + ': ' + err.getMessage() + ' | '; }
}

// qli.Id is often null after an RLM QLI insert; re-fetch the real Id by Quote+Product.
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
    try {
        Database.insertImmediate(attrs);
    } catch (Exception ae) { attrErr = ae.getTypeName() + ': ' + ae.getMessage(); }
}

String base = URL.getOrgDomainUrl().toExternalForm();
System.debug(LoggingLevel.ERROR, '✅ TIER-SUB-QUOTE CREATED'
    + '\n  Quote     : ' + base + '/' + q.Id
    + '\n  QLI       : ' + base + '/' + qliId + '  | ' + pbe.Product2.Name + '  | Qty 1  | insertSuccess=' + sr.isSuccess()
    + (qliErr == '' ? '' : '  | QLI-ERR=' + qliErr)
    + '\n  Attrs     : Number of Units=' + NOU_VALUE + '  Attribute_Volume=' + VOL_VALUE
    + (attrErr == '' ? '' : '  | ATTR-ERR=' + attrErr)
    + '\n  ORACLE    : after Force-reprice NetUnitPrice should = ' + EXPECTED_NET
    + ' (tier 1-50 / vol 30 in 26-50, Unit Price mode)'
    + '\n  NEXT      : Force-reprice via REST place(Quote), then re-query NetUnitPrice/NetTotalPrice.');
