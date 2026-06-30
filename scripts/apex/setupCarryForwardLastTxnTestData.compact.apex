// setupCarryForwardLastTxnTestData.compact.apex   (V21 scenario A-02)
// Builds a LastTransaction CARRY-FORWARD test fixture in FortraUAT: an Amend quote line tied
// to an existing asset whose prior-transaction NET is DELIBERATELY DIFFERENT from catalog list,
// so a clean PASS/FAIL is observable on Reprice All.
//
//   Asset (configurable)  02iWC000008dekCYAQ  "beSECURE - Cloud-Based"  (Subscription)
//     - prior-transaction NET (AssetActionSource Generate) = 6695.30   <-- carry-forward value
//     - catalog list (active PBE, USD)                      = 0.00      <-- value a WRONG re-derive yields
//   Account derives from the asset (001WC00000ltm01YAA) so asset/account stay consistent.
//
// WHY THIS PROVES A-02:
//   The line is sourced from the prior transaction (QuoteAction Amend + SourceAsset), so the V21
//   engine should set ItemPricingSource='LastTransaction' and route the line through the
//   carry-forward branch (ListOperation 'Equals LastTransaction'), SKIPPING Price Book Entries,
//   Attribute Pricing Filter, Quantity*Price, Manual/Partner/Volume discount (all gated
//   'ItemPricingSource NotEquals LastTransaction'). The prior NET (6695.30) must be PRESERVED.
//   If the engine wrongly re-derived from catalog, NetUnitPrice would collapse to 0.00 (the PBE
//   list). 6695.30 vs 0.00 is unambiguous.
//
// Qty = 2 per the A-02 test_setup. Expected after Reprice All:
//   NetUnitPrice = 6695.30 ; UnitPrice = 6695.30 ; TotalLineAmount/NetTotalPrice = 13390.60.
//
// Atomic: savepoint rollback on any failure -> no orphan Quote/QuoteAction/QuoteLineItem.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupCarryForwardLastTxnTestData.compact.apex
// Output: grep the debug log for the "A-02 CARRY-FWD" marker (logged at ERROR level).

// --- Config -----------------------------------------------------------------
Id ASSET = '02iWC000008dekCYAQ';     // beSECURE asset; prior NET 6695.30, catalog list 0.00
Integer QTY = 2;

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

// Asset -> Account + Product; the quote rides the asset's own account so the renewal/amend
// linkage is internally consistent.
Asset ast = [SELECT Id, Product2Id, AccountId, Price, CurrencyIsoCode FROM Asset WHERE Id = :ASSET];
Id ACCT = ast.AccountId;

// Active PBE on an ACTIVE pricebook (Fortra Price Book); the quote sits on that Pricebook2.
PricebookEntry pbe = [SELECT Id, Pricebook2Id, UnitPrice FROM PricebookEntry
                      WHERE Product2Id = :ast.Product2Id AND IsActive = true
                        AND Pricebook2.IsActive = true AND CurrencyIsoCode = :ast.CurrencyIsoCode
                      LIMIT 1];

// Prior-transaction NET = the carry-forward value the engine must preserve.
Decimal priorNet = null;
for (AssetActionSource s : [SELECT NetUnitPrice, AssetAction.Type FROM AssetActionSource
                            WHERE AssetAction.AssetId = :ASSET AND NetUnitPrice > 0
                              AND CurrencyIsoCode = :ast.CurrencyIsoCode
                            ORDER BY CreatedDate ASC]) {
    priorNet = s.NetUnitPrice;
    if (s.AssetAction.Type == 'Generate') { break; }
}
if (priorNet == null) { priorNet = ast.Price; }   // Asset.Price is the same carried net here

// Need an Opportunity for the Quote; reuse one on the account or create one.
List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId = :ACCT ORDER BY CreatedDate DESC LIMIT 1];

Savepoint sp = Database.setSavepoint();
try {
    Id oppId;
    if (opps.isEmpty()) {
        Opportunity o = new Opportunity(Name = 'A-02 CarryFwd Opp ' + TAG, AccountId = ACCT,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30), CurrencyIsoCode = ast.CurrencyIsoCode);
        Database.insert(o, dml);
        oppId = o.Id;
    } else {
        oppId = opps[0].Id;
    }

    // Amend quote on the asset's account, on the active pricebook.
    Quote q = new Quote(
        Name            = 'A-02 CarryFwd Quote ' + TAG,
        OpportunityId   = oppId,
        Pricebook2Id    = pbe.Pricebook2Id,
        Status          = 'Draft',
        CurrencyIsoCode = ast.CurrencyIsoCode,
        StartDate       = Date.today(),
        ExpirationDate  = Date.today().addDays(30));
    Database.insert(q, dml);

    // QuoteAction Amend + SourceAsset: drives ItemPricingSource='LastTransaction' for the line.
    QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = 'Amend', SourceAssetId = ASSET);
    Database.insert(qa, dml);

    // Line: Qty=2, seed UnitPrice/NetUnitPrice from the prior transaction NET (carry-forward seed).
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId          = q.Id,
        QuoteActionId    = qa.Id,
        PricebookEntryId = pbe.Id,
        Quantity         = QTY,
        StartQuantity    = QTY,
        UnitPrice        = priorNet,   // NetUnitPrice is RLM-managed (not writeable on insert); engine carries it forward
        StartDate        = Date.today(),
        EndDate          = Date.today().addYears(1));
    Database.insert(qli, dml);

    QuoteLineItem r = [SELECT Id, Quote.Name, Quantity, UnitPrice, NetUnitPrice, ListPrice, TotalPrice
                       FROM QuoteLineItem WHERE Id = :qli.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, 'A-02 CARRY-FWD CREATED  ' + r.Quote.Name
        + '\n  Quote        : ' + base + '/' + q.Id
        + '\n  QuoteId      : ' + q.Id
        + '\n  Account      : ' + ACCT
        + '\n  Asset        : ' + ASSET + '  (prior NET seed = ' + priorNet + ')'
        + '\n  Catalog list : PBE.UnitPrice=' + pbe.UnitPrice + '  (value a WRONG re-derive would yield)'
        + '\n  Line (pre-reprice): Qty=' + r.Quantity + ' UnitPrice=' + r.UnitPrice
        + ' NetUnitPrice=' + r.NetUnitPrice + ' TotalPrice=' + r.TotalPrice
        + '\n  EXPECT after Force-reprice: NetUnitPrice=' + priorNet
        + ' TotalLineAmount=' + (priorNet * QTY) + ' (carry-forward; NOT catalog ' + pbe.UnitPrice + ')');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'A-02 CARRY-FWD FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
