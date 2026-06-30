// setupAttrCalcQuoteTestData.compact.apex
// D-01 fixture: Attribute Value Pricing - CALCULATED MODE smoke test for V21.
// Builds a fresh Draft Quote with a single line on the only org product wired for
// Calculated attribute pricing (Fortra PCI Scanning, VM-BSL-RSL-FPSS, list 935 USD),
// and stamps the Calculated-mode inputs the V21 ListContainer6 steps read:
//   Has_Attribute_Adjustment__c = true
//   Attribute_Price_Mode__c     = 'Calculated'
//   Base_Price__c               = BASE   (the per-tier base price)
//   AttributeMultiplierPct__c   = MULT   (Percent field -> context Attribute_Multiplier_Pct__c)
// V21 ListContainer6 then computes:  InputUnitPrice = Base_Price__c * Attribute_Multiplier_Pct__c
//   Net Bridge: NetUnitPrice = IF(NetUnitPrice>0, NetUnitPrice, IF(Base_Price__c>0, Base_Price__c, InputUnitPrice))
//   Base Bridge: Base_Price__c = IF(Base_Price__c>0, Base_Price__c, NetUnitPrice)
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupAttrCalcQuoteTestData.compact.apex
// Output: grep the debug log for the "ATTR-CALC-D01" marker (logged at ERROR level).

Id ACCT  = '001WC00000XiZP4YAN';            // Fortra, LLC - Test (reference account)
Id PROD  = '01tWC00000DD10xYAD';            // Fortra PCI Scanning (Calculated-mode product)
Decimal BASE = 100.00;                       // Base_Price__c (per-tier base)
Decimal MULT = 50.00;                        // AttributeMultiplierPct__c (Percent field = 50%)
Integer QTY  = 1;

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Savepoint sp = Database.setSavepoint();
try {
    // Active price book entry (parent Pricebook2 must be active too).
    PricebookEntry pbe = [SELECT Id, Pricebook2Id, UnitPrice, CurrencyIsoCode FROM PricebookEntry
                          WHERE Product2Id = :PROD AND IsActive = true
                            AND Pricebook2.IsActive = true AND Pricebook2.Name = 'Fortra Price Book'
                            AND CurrencyIsoCode = 'USD' LIMIT 1];

    Opportunity opp = new Opportunity(
        Name = 'D01 Attr-Calc ' + TAG, AccountId = ACCT, StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30), CurrencyIsoCode = 'USD');
    Database.insert(opp, dml);

    Quote q = new Quote(
        Name = 'D01-AttrCalc ' + TAG, OpportunityId = opp.Id, Pricebook2Id = pbe.Pricebook2Id,
        Status = 'Draft', CurrencyIsoCode = 'USD', ExpirationDate = Date.today().addDays(30));
    Database.insert(q, dml);

    // RLM requires every QuoteLineItem to hang off a QuoteAction (the transaction grouping).
    // A direct QLI insert with no QuoteActionId silently no-ops under Subscription Management.
    QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = 'Add');
    Database.insert(qa, dml);

    // Fortra PCI Scanning is a TermDefined subscription -> BillingFrequency / SubscriptionTerm /
    // ProductSellingModel are required (FIELD_INTEGRITY_EXCEPTION otherwise). Mirror the existing
    // Calculated line (0QLWC000002Lo2H4AS): Annual, 12-month term, PricingTermCount=1, Anniversary.
    // ProductSellingModelId is system-managed (not writeable) — it derives from the PSMO on insert.
    Date sd = Date.today();
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId = q.Id, QuoteActionId = qa.Id, PricebookEntryId = pbe.Id, Product2Id = PROD,
        Quantity = QTY, UnitPrice = pbe.UnitPrice,
        BillingFrequency = 'Annual',
        SubscriptionTerm = 12, PeriodBoundary = 'Anniversary',
        StartDate = sd, EndDate = sd.addMonths(12).addDays(-1),
        Has_Attribute_Adjustment__c = true,
        Attribute_Price_Mode__c = 'Calculated',
        Base_Price__c = BASE,
        AttributeMultiplierPct__c = MULT);
    Database.insert(qli, dml);

    String orgUrl = URL.getOrgDomainUrl().toExternalForm();
    Decimal expFrac = BASE * (MULT / 100);
    Decimal expRaw  = BASE * MULT;
    System.debug(LoggingLevel.ERROR,
        '\n==== ATTR-CALC-D01 ====' +
        '\nTAG=' + TAG +
        '\nBASE_PRICE=' + BASE + '  MULT_PCT=' + MULT + '  QTY=' + QTY +
        '\nEXPECTED InputUnitPrice = Base*Mult (frac=' + expFrac + ' | raw=' + expRaw + ')' +
        '\nQuoteId=' + q.Id +
        '\nQuoteUrl=' + orgUrl + '/lightning/r/Quote/' + q.Id + '/view' +
        '\nQLIId=' + qli.Id +
        '\nQLIUrl=' + orgUrl + '/lightning/r/QuoteLineItem/' + qli.Id + '/view' +
        '\n=======================');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '==== ATTR-CALC-D01 FAILED ==== ' + e.getTypeName() + ': ' + e.getMessage() + ' | line ' + e.getLineNumber());
    throw e;
}
