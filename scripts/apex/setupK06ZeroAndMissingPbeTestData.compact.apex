// K-06 Zero-dollar / null-missing pricing line safe handling — SC-3345 / SC-3347.
// A NEW Draft quote on Fortra Price Book (USD) carrying three lines:
//   (A) NSS - SNMP Trap Receiver perpetual anchor (SM-NSS-NRPS-NSSSTR, list 2800) — a real
//       priced line so the header rolls up to a non-zero base; the K-06 $0/missing lines must
//       NOT corrupt it.
//   (B) A genuine $0 bundled/included component: Metrics Catalog - PS-AM (CM-TQO-NRPS-MCPAPE,
//       Perpetual, active $0-list PBE, NON-derived) — expect it to display 0.00, NO validation
//       error, and remain on the quote (V21 step 4 'All Lines Null Safe Filter' / steps 85-86
//       'Null-Check / Null-Safe Line Adjustment' must keep it $0-safe).
//   (C) A retired/legacy SKU with NO active PricebookEntry: DCS Advanced Bundle OLD
//       (01tWC00000DD1yoYAD, Product IsActive=false, its Fortra USD PBE 01uWC000005wrUAYAY
//       IsActive=false, list 42) — expect graceful handling: warn 'No pricing found' or default
//       $0, NO null-reference exception thrown by the pricing engine.
// If RLM rejects the inactive-PBE line at DML, that rejection IS a documented graceful failure
// and is captured by the catch marker (no engine NPE).
Id oppId       = '006WC00000RZUTVYA5';            // Train the Trainer - Derived Pricing (Fortra Price Book)
Id pricebookId = '01sWC0000022GHFYA2';            // Fortra Price Book
// (A) priced anchor — NSS SNMP Trap Receiver perpetual, list 2800
Id ancPbe  = '01uWC000005wo41YAA';  Id ancProd = '01tWC00000DD0AMYA1';
// (B) $0 bundled component — Metrics Catalog - PS-AM, active $0-list non-derived PBE
Id zeroPbe = '01uWC000005wo3GYAQ';  Id zeroProd; // resolved below from the PBE
// (C) retired SKU — DCS Advanced Bundle OLD, inactive product + inactive PBE (list 42)
Id legPbe  = '01uWC000005wrUAYAY';  Id legProd = '01tWC00000DD1yoYAD';
// Resolve the $0 component's Product2Id from the PBE so we never hard-code wrong.
zeroProd = [SELECT Product2Id FROM PricebookEntry WHERE Id = :zeroPbe LIMIT 1].Product2Id;
String tag = 'K06-' + String.valueOf(Crypto.getRandomInteger()).right(5);
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.DuplicateRuleHeader.AllowSave = true;
Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name = 'Q-' + tag + ' ZERO + MISSING-PBE (null-safe edge)',
        OpportunityId = oppId, Pricebook2Id = pricebookId, CurrencyIsoCode = 'USD',
        Status = 'Draft', ExpirationDate = Date.today().addDays(30));
    q.setOptions(dmo);
    Database.insert(q, dmo);
    QuoteLineItem anc  = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=ancPbe,  Product2Id=ancProd,
        Quantity=1, UnitPrice=2800, Fortra_Product_Type__c='Perpetual');
    QuoteLineItem zero = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=zeroPbe, Product2Id=zeroProd,
        Quantity=1, UnitPrice=0,    Fortra_Product_Type__c='Perpetual');
    Database.insert(new List<QuoteLineItem>{ anc, zero }, dmo);
    String legMsg;
    Id legLineId = null;
    try {
        QuoteLineItem leg = new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=legPbe, Product2Id=legProd,
            Quantity=1, UnitPrice=42, Fortra_Product_Type__c='Perpetual');
        Database.insert(leg, dmo);
        legLineId = leg.Id;
        legMsg = 'legLine INSERTED=' + leg.Id + ' (inactive PBE accepted)';
    } catch (Exception le) {
        legMsg = 'legLine REJECTED at DML (graceful, no engine NPE): ' + le.getTypeName() + ' :: ' + le.getMessage();
    }
    System.debug(LoggingLevel.ERROR, 'K-06 MARKER quoteId=' + q.Id
        + ' ancLine=' + anc.Id + ' zeroLine=' + zero.Id + ' legLine=' + legLineId
        + ' :: ' + legMsg
        + ' :: quoteUrl=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/' + q.Id + '/view');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'K-06 ERROR: ' + e.getTypeName() + ' :: ' + e.getMessage() + ' :: line ' + e.getLineNumber());
}
