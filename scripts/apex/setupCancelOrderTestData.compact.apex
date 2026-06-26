// setupCancelOrderTestData.compact.apex
// Builds an SC-3441 cancellation-ORDER test fixture in FortraUAT: a fresh Draft Order on
// the standing test account with a single Quantity = -1 cancellation line tied to an
// existing asset.
//
//   Account "Fortra, LLC - Test"   001WC00000XiZP4YAN  (referenced only, not modified)
//   Asset  (configurable below)    02iWC000008Wiz0YAC  "Advanced Authentication Modes"
//
// WHAT IT PROVES: on insert, the SC-3441 before-insert trigger (CancelLineNetSeedHandler)
// resolves the asset's original NET (via OrderAction.SourceAssetId -> AssetActionSource)
// and stamps it onto OrderItem.NetUnitPrice. Because OrderItem.NetUnitPrice is writeable
// ONLY before OrderItemDetail records exist, this fresh-insert path is exactly where the
// order-side fix applies — and TotalPrice then computes to the correct NEGATIVE amount
// (net * -1) with no reprice. The cancelled asset MUST have a positive 'Generate' net or
// the trigger has nothing to stamp (TotalPrice stays 0).
//
// Atomic: any failure rolls back via a savepoint, so a partial run never leaves an orphan
// Order / OrderAction / OrderItem behind. On success the Order is COMMITTED so it can be
// opened in the UI.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupCancelOrderTestData.compact.apex
//       (NOTE: target FortraUAT, not the `uat` alias — that is 5sInfusion's org.)
// Output: grep the debug log for the "CANCEL-ORDER" marker (logged at ERROR level).

// --- Config -----------------------------------------------------------------
Id ACCT  = '001WC00000XiZP4YAN';     // "Fortra, LLC - Test" (existing)
Id ASSET = '02iWC000008Wiz0YAC';     // asset to cancel — MUST have a positive Generate net

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm');

// Bypass duplicate rules consistently on every insert below.
Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

// Resolve the product + an active price book entry from the asset (the OrderItem needs a
// PricebookEntry; the Order must sit on that same Pricebook2).
Asset ast = [SELECT Id, Product2Id, CurrencyIsoCode FROM Asset WHERE Id = :ASSET];
PricebookEntry pbe = [SELECT Id, Pricebook2Id, UnitPrice FROM PricebookEntry
                      WHERE Product2Id = :ast.Product2Id AND IsActive = true LIMIT 1];

Savepoint sp = Database.setSavepoint();
try {
    // --- Draft Order (on the existing account) ------------------------------
    Order ord = new Order(
        AccountId       = ACCT,
        EffectiveDate   = Date.today(),
        Status          = 'Draft',
        Pricebook2Id    = pbe.Pricebook2Id,
        CurrencyIsoCode = 'USD',
        Description     = 'SC3441 Cancel Order Test ' + TAG);
    Database.insert(ord, dml);

    // --- OrderAction carrying the SourceAsset (lets the trigger resolve the net) ---
    OrderAction oa = new OrderAction(OrderId = ord.Id, Type = 'Amend', SourceAssetId = ASSET);
    Database.insert(oa, dml);

    // --- Cancellation line: Quantity -1 fires the SC-3441 before-insert trigger ---
    OrderItem oi = new OrderItem(
        OrderId          = ord.Id,
        OrderActionId    = oa.Id,
        PricebookEntryId = pbe.Id,
        Quantity         = -1,
        StartQuantity    = 1,            // an Amend-linked line needs a nonzero start qty
        ServiceDate      = Date.today(), // line Start Date — without it Reprice All throws
        EndDate          = Date.today().addYears(1), //   "startDate is null" in the formula engine
        UnitPrice        = pbe.UnitPrice);
    Database.insert(oi, dml);

    // --- Verify what the trigger produced -----------------------------------
    OrderItem r = [SELECT Id, Order.OrderNumber, Quantity, CancelNetUnitPrice__c,
                          NetUnitPrice, ListPrice, TotalPrice FROM OrderItem WHERE Id = :oi.Id];
    Boolean fixed = r.TotalPrice != null && r.TotalPrice < 0;
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ CANCEL-ORDER CREATED  Order #' + r.Order.OrderNumber
        + '\n  Order        : ' + base + '/' + ord.Id
        + '\n  Cancel line  : Qty ' + r.Quantity
        + '  | List=' + r.ListPrice
        + '  | CancelNetUnitPrice__c=' + r.CancelNetUnitPrice__c
        + '  | NetUnitPrice=' + r.NetUnitPrice
        + '  | TotalPrice=' + r.TotalPrice
        + '\n  RESULT       : ' + (fixed
            ? 'FIX WORKS — TotalPrice is negative (net * -1)'
            : 'NOT fixed — NetUnitPrice not stamped (does the asset have a positive Generate net?)'));
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ CANCEL-ORDER FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;   // non-zero CLI exit
}
