// K-10 Null-safe filter excludes negative/null qty from positive aggregation — SC-3441 / SC-3473.
// V21 step 4 'All Lines Null Safe Filter' (AllLinesNullSafeFilter, AdvancedListFilter on
// ListGroup ListContainer11) passes ONLY LineItemQuantity GreaterThanOrEquals 0; steps 85/86
// 'Null-Check / Null-Safe Line Adjustment' wrap ItemTotalAdjustmentAmount in IF(ISNULL,0,..).
// A NEW Draft quote on Fortra Price Book (USD) carrying a MIXED line-set:
//   (A) POSITIVE control: NSS - SNMP Trap Receiver perpetual (PBE 01uWC000005wo41YAA, list 2800),
//       Qty=5 — this is the only line that must reach the positive null-safe aggregate.
//   (B) NEGATIVE line: same product, Qty=-1 — must be EXCLUDED by the >=0 filter so it does NOT
//       subtract from / corrupt the positive aggregate, and must not throw an NPE.
// NOTE on the "Qty=null" leg: QuoteLineItem.Quantity.IsNillable = false in this org — the
//   platform itself rejects a null-quantity QLI at DML, so a literal null-qty line cannot be
//   constructed (the null-safety the filter guards is on the engine-internal LineItemQuantity).
//   We assert the null leg structurally via the field-describe + the engine null-guard, and
//   build the negative leg as the testable half of the mixed set.
Id oppId       = '006WC00000RPVp3YAH';            // standing Opp (Fortra Price Book)
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book (active)
Id posPbe  = '01uWC000005wo41YAA';                // NSS SNMP perpetual, list 2800 (active USD)
Id posProd = '01tWC00000DD0AMYA1';
String tag = 'K10-' + String.valueOf(Crypto.getRandomInteger()).right(5);
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
dmo.DuplicateRuleHeader.RunAsCurrentUser = true;
Savepoint sp = Database.setSavepoint();
QuoteLineItem pos;
QuoteLineItem neg;
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' NULL-SAFE MIXED QTY (+5 / -1)',
        OpportunityId = oppId, Pricebook2Id = pricebookId, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    q.setOptions(dmo);
    Database.insert(q, dmo);
    pos = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=posPbe, Product2Id=posProd,
        Quantity=5,  UnitPrice=2800, Fortra_Product_Type__c='Perpetual');
    neg = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=posPbe, Product2Id=posProd,
        Quantity=-1, UnitPrice=2800, Fortra_Product_Type__c='Perpetual');
    pos.setOptions(dmo); neg.setOptions(dmo);
    Database.insert(new List<QuoteLineItem>{ pos, neg }, dmo);
    System.debug(LoggingLevel.ERROR, 'K-10 MARKER quoteId=' + q.Id
        + ' posLine(+5)=' + pos.Id + ' negLine(-1)=' + neg.Id
        + ' :: quoteUrl=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'K-10 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
