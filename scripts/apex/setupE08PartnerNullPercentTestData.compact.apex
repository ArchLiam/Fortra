// setupE08PartnerNullPercentTestData.compact.apex
// E-08: Partner deal where resolved PartnerDiscountPercent is NULL (partner pricing model has no
//       bucket for the product type) -> Partner Percent Resolved Filter
//       (Deal_Type!='Fortra Originated' AND PartnerDiscountPercent IsNotNull AND >0) NEGATIVE
//       branch -> NO discount applied, net stays at list.
//
// Builds TWO single-line Subscription quotes with a CLEAN-HYDRATING product
// (Automate Professional, PBE 01uWC000005wrt9YAA, Fortra Price Book, list 2400 USD, Term Based Annual)
// that re-derives Pre_Partner_Price in-procedure (proven on quote 00780845):
//   (A) NEGATIVE  billing partner = BoKS IAM Test (001WC00000kTYyNYAW), Discount PPM-00029
//                 Subscription_Percent__c = NULL  -> expect pct=NULL, net=2400=list.
//   (B) POSITIVE  billing partner = AB Test Partner (001WC00000ZtazZYAR), Discount PPM-00028
//                 Subscription_Percent__c = 18    -> expect pct=18, net=1968=2400*0.82 (control).
// Both Channel Originated / Partner_Pricing_Model__c='Discount'.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupE08PartnerNullPercentTestData.compact.apex
// Output: grep the debug log for the "E08-FIXTURE" marker (logged at ERROR level).

Id SRC_Q  = '0Q0WC000003FO1u0AG';        // template Quote header defaults (E-02 control)
Id OPP    = '006WC00000OE0NKYA1';        // "Wren - Test GS Quotes"
Id NULLPART = '001WC00000kTYyNYAW';      // BoKS IAM — Discount PPM-00029 Subscription%=NULL
Id ABPART   = '001WC00000ZtazZYAR';      // AB Test Partner — Discount PPM-00028 Subscription%=18
Id P2  = '01tWC00000DD14lYAD';           // Automate Professional
Id PBE = '01uWC000005wrt9YAA';           // Fortra Price Book, list 2400 USD
Decimal LISTP = 2400;

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm');

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Savepoint sp = Database.setSavepoint();
try {
    Quote src = [SELECT Pricebook2Id, CurrencyIsoCode, Quote_Type__c, LegalEntityId, QuoteAccountId,
        ContactId, BillToContactId, SalesTransactionTypeId, Show_Hide_Discounts__c, Ship_To_Place__c,
        Bill_To_Place__c, Net_Terms__c, Header_Discount_Type__c, Payment_Portal__c, Disable_Export_Control__c,
        Language__c, BillingStreet, BillingCity, BillingStateCode, BillingPostalCode, BillingCountryCode,
        ShippingStreet, ShippingCity, ShippingStateCode, ShippingPostalCode, ShippingCountryCode
        FROM Quote WHERE Id = :SRC_Q];

    Map<String,Id> partners = new Map<String,Id>{'NEG'=>NULLPART, 'POS'=>ABPART};
    Map<String,Id> qids = new Map<String,Id>();
    Quote q;
    QuoteLineItem qli;
    for (String k : new List<String>{'NEG','POS'}) {
        q = new Quote(OpportunityId = OPP,
            Name = 'LJ E08 ' + k + ' ' + TAG + ' ' + String.valueOf(Crypto.getRandomInteger()).right(5),
            Status = 'Draft', ExpirationDate = Date.today().addDays(30),
            Pricebook2Id = src.Pricebook2Id, CurrencyIsoCode = src.CurrencyIsoCode, Quote_Type__c = src.Quote_Type__c,
            LegalEntityId = src.LegalEntityId, QuoteAccountId = src.QuoteAccountId, ContactId = src.ContactId,
            BillToContactId = src.BillToContactId, SalesTransactionTypeId = src.SalesTransactionTypeId,
            Net_Terms__c = src.Net_Terms__c, Language__c = src.Language__c,
            Deal_Type__c = 'Channel Originated', PartnerAccountId = partners.get(k),
            Billing_Partner__c = partners.get(k), Partner_Pricing_Model__c = 'Discount',
            Show_Hide_Discounts__c = src.Show_Hide_Discounts__c, Header_Discount_Type__c = src.Header_Discount_Type__c,
            Payment_Portal__c = src.Payment_Portal__c, Disable_Export_Control__c = src.Disable_Export_Control__c,
            Ship_To_Place__c = src.Ship_To_Place__c, Bill_To_Place__c = src.Bill_To_Place__c,
            BillingStreet = src.BillingStreet, BillingCity = src.BillingCity, BillingStateCode = src.BillingStateCode,
            BillingPostalCode = src.BillingPostalCode, BillingCountryCode = src.BillingCountryCode,
            ShippingStreet = src.ShippingStreet, ShippingCity = src.ShippingCity, ShippingStateCode = src.ShippingStateCode,
            ShippingPostalCode = src.ShippingPostalCode, ShippingCountryCode = src.ShippingCountryCode);
        Database.insert(q, dml);
        qids.put(k, q.Id);

        qli = new QuoteLineItem(QuoteId = q.Id, Product2Id = P2, PricebookEntryId = PBE,
            Quantity = 1, UnitPrice = LISTP, Fortra_Product_Type__c = 'Subscription', SubscriptionTerm = 1,
            StartDate = Date.today(), EndDate = Date.today().addMonths(12).addDays(-1));
        Database.insert(qli, dml);
    }

    Quote qn = [SELECT QuoteNumber FROM Quote WHERE Id = :qids.get('NEG')];
    Quote qp = [SELECT QuoteNumber FROM Quote WHERE Id = :qids.get('POS')];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ E08-FIXTURE CREATED'
        + '\n  NEG (null pct) Quote #' + qn.QuoteNumber + ' = ' + base + '/' + qids.get('NEG') + '  expect pct=NULL net=2400=list'
        + '\n  POS (18% ctrl) Quote #' + qp.QuoteNumber + ' = ' + base + '/' + qids.get('POS') + '  expect pct=18 net=1968'
        + '\n  NEG_ID=' + qids.get('NEG') + ' POS_ID=' + qids.get('POS'));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ E08-FIXTURE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
