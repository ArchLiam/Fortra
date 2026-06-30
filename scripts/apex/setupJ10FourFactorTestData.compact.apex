// setupJ10FourFactorTestData.compact.apex   (V21 scenario J-10)
// Four-factor maximal-interaction cell: DERIVED maintenance RENEWAL line that is
// simultaneously partner-discounted (Channel Originated, prior-netted), COLA-uplifted,
// AND non-USD (EUR). Builds a EUR Renewal quote on the BoKS proven derived recipe:
//   license  PIA-PIA-NRPS-PIAP  (EUR PBE 01uWC000005wzWsYAI)
//   maint    PIA-PIA-RNM-PIAMBK (EUR PBE 01uWC000005wzX8YAI) -> ItemIsDerived
// The derived maint line is SEED with a prior-netted base (partner 12% already in it),
// COLA 7.85, partner 12, so the engine should apply COLA once, NOT re-discount partner,
// and FX to EUR once (V21 Currency Conversion Net Unit Price = NetUnitPrice * 0.9346).
//
// QLIA attributes (Maintenance Type Defn=Standard on maint; Feature Options+MTDefn on
// license) are added via REST AFTER this run (Apex DML rejected on QLIA managed sobject).
//
// EXPECTED derived maint NetUnitPrice (EUR) once each factor applied:
//   priorNet(EUR-already? NO: seeded as USD base) -> tier(0.20)*base * (1+COLA) * partnerSkip * 0.9346
// We seed Base_Price__c so the math is observable; see marker for the per-factor expectation.
//
// Atomic: savepoint rollback on any failure.
// Run: sf apex run --target-org FortraUAT -f scripts/apex/setupJ10FourFactorTestData.compact.apex
// Output: grep the debug log for the "J-10" ERROR-level marker.

Id ACCT  = '001WC00000XiZP4YAN';        // Fortra, LLC - Test
Id OPP   = '006WC00000RZUTVYA5';        // Train the Trainer - Derived Pricing (Channel Originated capable)
Id PB    = '01sWC0000022GHFYA2';        // Fortra Price Book (active)
Id LE    = '0fwWC000000034LYAQ';        // Legal Entity
Id STT   = '1ChWC0000002eJ70AI';        // SalesTransactionType
Id PART  = '001WC00000ZtazZYAR';        // Partner Account

Id licPbe  = '01uWC000005wzWsYAI';  Id licProd = '01tWC00000DD1btYAD';  // PIAP  EUR
Id mntPbe  = '01uWC000005wzX8YAI';  Id mntProd = '01tWC00000DD1bsYAD';  // PIAMBK EUR (derived)

Decimal PRIOR_NET = 3400;   // prior-netted base (partner 12% already inside)
Decimal COLA_PCT  = 7.85;
Decimal PART_PCT  = 12;     // prior-netted Channel Originated

String TAG = 'J10-' + Datetime.now().format('yyyyMMdd-HHmm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Savepoint sp = Database.setSavepoint();
try {
    // NB: NO OpportunityId — a Quote on an Opp inherits the Opp currency (USD here),
    // silently overriding EUR. The standing EUR renewal quotes are all opp-less.
    Quote q = new Quote(
        Name = 'Q-' + TAG + ' J10 4FACTOR (derived+partner+COLA+EUR)',
        Pricebook2Id = PB, CurrencyIsoCode = 'EUR',
        Status = 'Draft', Quote_Type__c = 'Renewal',
        QuoteAccountId = ACCT, SalesTransactionTypeId = STT, LegalEntityId = LE,
        Deal_Type__c = 'Channel Originated',
        Partner_Pricing_Model__c = 'Discount', PartnerAccountId = PART, Billing_Partner__c = PART,
        Show_Hide_Discounts__c = 'Show',
        ExpirationDate = Date.today().addDays(30));
    Database.insert(q, dml);

    QuoteLineItem lic = new QuoteLineItem(
        QuoteId = q.Id, PricebookEntryId = licPbe, Product2Id = licProd,
        Quantity = 1, UnitPrice = 331.783, Fortra_Product_Type__c = 'Perpetual',
        PartnerDiscountPercent = PART_PCT);

    QuoteLineItem mnt = new QuoteLineItem(
        QuoteId = q.Id, PricebookEntryId = mntPbe, Product2Id = mntProd,
        Quantity = 1, UnitPrice = 0, Fortra_Product_Type__c = 'New Maintenance',
        COLA_Uplift_Percent__c = COLA_PCT, PartnerDiscountPercent = PART_PCT,
        Base_Price__c = PRIOR_NET, Pre_Partner_Price__c = PRIOR_NET);

    List<QuoteLineItem> lines = new List<QuoteLineItem>{ lic, mnt };
    Database.insert(lines, dml);

    q = [SELECT Id, QuoteNumber FROM Quote WHERE Id = :q.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, 'J-10 MARKER Quote#' + q.QuoteNumber
        + ' quoteId=' + q.Id
        + ' licId=' + lic.Id + ' mntId=' + mnt.Id
        + ' quoteUrl=' + base + '/lightning/r/Quote/' + q.Id + '/view'
        + ' | SEED base=' + PRIOR_NET + ' COLA=' + COLA_PCT + ' partner=' + PART_PCT + ' cur=EUR'
        + ' | EXPECT derived NetUnitPrice = tier(0.20)*base*1.0785*partnerSkip*0.9346');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'J-10 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
    throw e;
}
