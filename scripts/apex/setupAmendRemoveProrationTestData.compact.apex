// setupAmendRemoveProrationTestData.compact.apex
// Scenario F-12 — Amend mid-term REMOVE/downgrade should produce a PRORATED negative delta
// (removed_qty x net x remaining-term-fraction), distinct from a full Qty=-1 cancellation (K-01)
// and from an add-amend (F-11).
//
// Builds a Draft "Amendment" Quote in FortraUAT with an Amend-type QuoteAction (SourceAsset = a
// real multi-quantity TermDefined asset) and a single amend-REMOVE line:
//   - Quantity = -REMOVE_QTY  (partial downgrade: remove 50000 of the asset's 100000 seats)
//   - StartQuantity = asset qty (100000)
//   - net seeded from the asset NET (Price/Quantity) into CancelNetUnitPrice__c (the only seed path
//     this org has for a negative-delta line; there is NO distinct amend-remove seed)
//   - StartDate = 6 months into the asset's 12-month term, EndDate = asset term end (anchor)
//     => a date window of ~6 remaining months -> a fractional PricingTermCount (~0.5) IS expected
//
// EXPECTED (F-12): after Force-reprice, NetUnitPrice = asset net (1.5), Quantity = -50000,
//   PricingTermCount ~ 0.5, TotalPrice = -50000 x 1.5 x 0.5 = -37500 (prorated half-term credit).
// CONTRAST: if it full-credits (-50000 x 1.5 = -75000, PTC=1 or 0) it is treated as a cancellation,
//   NOT a prorated amend-remove. If it aborts at StampBaseFilter / nets $0, the seed path is the
//   K-01 blocker re-exposed.
//
//   Standing Opportunity (Quote hangs off it)  006WC00000RPVp3YAH
//   Source Asset (DMARC Protection, TermDefined Annual, Qty 100000, Price 150000 -> net 1.5)
//                                               02iWC000007ms1MYAQ
//
// Atomic: savepoint rollback on any failure -> no orphan Quote/QuoteAction/QuoteLineItem.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupAmendRemoveProrationTestData.compact.apex
//       (target FortraUAT, NOT the `uat` alias.)
// Output: grep the debug log for the "AMEND-REMOVE" marker (logged at ERROR level).

// --- Config -----------------------------------------------------------------
Id OPP       = '006WC00000RPVp3YAH';   // Opportunity the Quote hangs off (Account derives from it)
Id ASSET     = '02iWC000007ms1MYAQ';   // DMARC Protection, TermDefined Annual, Qty 100000, Price 150000
Decimal REMOVE_QTY = 50000;            // remove half the seats

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Opportunity oppRec = [SELECT Id, AccountId FROM Opportunity WHERE Id = :OPP];
Id ACCT = oppRec.AccountId;

Asset ast = [SELECT Id, Product2Id, CurrencyIsoCode, Quantity, Price,
                    LifecycleStartDate, LifecycleEndDate
             FROM Asset WHERE Id = :ASSET];
PricebookEntry pbe = [SELECT Id, Pricebook2Id, UnitPrice FROM PricebookEntry
                      WHERE Product2Id = :ast.Product2Id AND IsActive = true
                        AND Pricebook2.IsActive = true AND CurrencyIsoCode = :ast.CurrencyIsoCode
                      LIMIT 1];

// Asset NET per seat = Price / Quantity (DMARC 150000 / 100000 = 1.5). Prefer an AssetActionSource
// positive net if present; else derive from asset Price/Qty; else fall back to PBE list (lossy).
Decimal assetNet;
for (AssetActionSource s : [SELECT NetUnitPrice FROM AssetActionSource
                            WHERE AssetAction.AssetId = :ASSET AND NetUnitPrice > 0
                              AND CurrencyIsoCode = :ast.CurrencyIsoCode
                            ORDER BY CreatedDate ASC LIMIT 1]) {
    assetNet = s.NetUnitPrice;
}
if (assetNet == null || assetNet <= 0) {
    assetNet = (ast.Quantity != null && ast.Quantity > 0 && ast.Price != null)
               ? (ast.Price / ast.Quantity) : pbe.UnitPrice;
}

// Term window: asset is a 12-month term. Put the amend 6 months into the term so ~6 months remain.
Date termEnd   = (ast.LifecycleEndDate != null) ? ast.LifecycleEndDate.date() : Date.today().addMonths(6);
Date amendStart = termEnd.addMonths(-6);   // 6 months remaining to the anchor end-date

Savepoint sp = Database.setSavepoint();
try {
    Quote q = new Quote(
        Name            = 'F-12 AmendRemove Quote ' + TAG,
        OpportunityId   = OPP,
        Pricebook2Id    = pbe.Pricebook2Id,
        Status          = 'Draft',
        Quote_Type__c   = 'Amendment',
        CurrencyIsoCode = ast.CurrencyIsoCode,
        StartDate       = amendStart,
        ExpirationDate  = Date.today().addDays(30));
    Database.insert(q, dml);

    // Amend-type QuoteAction carrying the SourceAsset (this is the discriminator vs Cancel)
    QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = 'Amend', SourceAssetId = ASSET);
    Database.insert(qa, dml);

    // Amend-REMOVE line: partial negative quantity (NOT -1), seeded net, mid-term date window.
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId               = q.Id,
        QuoteActionId         = qa.Id,
        PricebookEntryId      = pbe.Id,
        Quantity              = -REMOVE_QTY,
        StartQuantity         = ast.Quantity,
        CancelNetUnitPrice__c = assetNet,
        PeriodBoundary        = 'Anniversary',
        StartDate             = amendStart,
        EndDate               = termEnd);
    Database.insert(qli, dml);

    QuoteLineItem r = [SELECT Id, Quote.Name, Quantity, CancelNetUnitPrice__c, NetUnitPrice,
                              TotalPrice, PricingTermCount, StartDate, EndDate
                       FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ AMEND-REMOVE CREATED (F-12)  ' + r.Quote.Name
        + '\n  Quote            : ' + base + '/' + q.Id
        + '\n  QuoteLineItem    : ' + base + '/' + qli.Id
        + '\n  QuoteAction      : ' + qa.Id + '  Type=Amend  SourceAsset=' + ASSET
        + '\n  Asset            : Qty=' + ast.Quantity + ' Price=' + ast.Price + ' -> net/seat=' + assetNet
        + '\n  Amend line       : Qty=' + r.Quantity + ' (remove ' + REMOVE_QTY + ' of ' + ast.Quantity + ')'
        + '  CancelNetUnitPrice__c=' + r.CancelNetUnitPrice__c
        + '\n  Date window      : ' + r.StartDate + ' -> ' + r.EndDate + ' (~6mo remaining of 12mo term)'
        + '\n  Pre-reprice      : NetUnitPrice=' + r.NetUnitPrice + ' TotalPrice=' + r.TotalPrice
        + ' PricingTermCount=' + r.PricingTermCount
        + '\n  EXPECTED (F-12)  : prorated credit = -' + REMOVE_QTY + ' x ' + assetNet + ' x 0.5 = '
        + (-REMOVE_QTY * assetNet * 0.5)
        + '\n  CONTRAST full    : full credit = -' + REMOVE_QTY + ' x ' + assetNet + ' = '
        + (-REMOVE_QTY * assetNet) + ' (= treated as cancellation, NOT prorated)'
        + '\n  NEXT: Force-reprice via REST place, then query NetUnitPrice/PricingTermCount/TotalPrice.');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ AMEND-REMOVE FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
