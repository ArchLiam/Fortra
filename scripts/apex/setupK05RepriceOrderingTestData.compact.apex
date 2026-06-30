// setupK05RepriceOrderingTestData.compact.apex
// K-05 (Edge Cases): "Order-tier reprice BEFORE Activate vs Convert+Auto-Activate race".
// Builds a FRESH Draft Order (owned by this run) carrying one PRICED, TERM-DEFINED subscription
// line so the order is a meaningful convert-equivalent — NOT a $0 junk order. The order is left
// in the pre-reprice state (CalculationStatus null / not CompletedWithPricing) so the validation
// gate is engaged, exactly as a freshly-converted order is before the convert flow's order-level
// Reprice-All runs.
//
// K-05 invariant under test: the order must be order-tier repriced (-> CompletedWithPricing +
// contributor base + term fields stamped) BEFORE native Activate; activating a not-yet-repriced
// order throws INVALID_INPUT ("prices aren't updated") = the SC-3308 race symptom. The SC-3308
// fix (OrderRepriceInvocable, called by Fortra_Quote_to_Order_Conversion before BOTH activate
// nodes) enforces reprice-before-activate.
//
// This script ONLY creates the order (so we own it). The reprice (place REST API) + the two
// activation probes are run as separate steps so each result is captured cleanly.
//
//   Account  001WC00000XiZP4YAN  "Fortra, LLC - Test"  (referenced, not modified)
//   PBE      01uWC000005wo3PYAQ  Monitor (Subscription, $3431.60, Fortra Price Book, active)
//
// Atomic: savepoint rollback on any failure -> no orphan Order/OrderItem. On success COMMITTED.
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupK05RepriceOrderingTestData.compact.apex
// Output: grep the debug log for the "K05-ORDER" marker (ERROR level).

Id ACCT = '001WC00000XiZP4YAN';
Id PBEID = '01uWC000005wo3PYAQ';   // Monitor subscription, priced, active Fortra Price Book

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

PricebookEntry pbe = [SELECT Id, Pricebook2Id, Product2Id, Product2.Name, UnitPrice, CurrencyIsoCode
                      FROM PricebookEntry WHERE Id = :PBEID];

Savepoint sp = Database.setSavepoint();
try {
    Order ord = new Order(
        AccountId       = ACCT,
        EffectiveDate   = Date.today(),
        Status          = 'Draft',
        Pricebook2Id    = pbe.Pricebook2Id,
        CurrencyIsoCode = pbe.CurrencyIsoCode,
        Description     = 'K05 Reprice-Ordering Test ' + TAG);
    Database.insert(ord, dml);

    // Term-defined subscription line: term fields populated so order-tier reprice has a real
    // PricingTermCount/EndDate to stamp (the "contributor base + term fields" the invariant names).
    OrderItem oi = new OrderItem(
        OrderId          = ord.Id,
        PricebookEntryId = pbe.Id,
        Quantity         = 4,
        ServiceDate      = Date.today(),
        EndDate          = Date.today().addYears(1),
        UnitPrice        = pbe.UnitPrice);
    Database.insert(oi, dml);

    Order r = [SELECT Id, OrderNumber, Status, CalculationStatus, ValidationResult,
                      (SELECT Id, Quantity, UnitPrice, TotalLineAmount, PricingTermCount, EndDate FROM OrderItems)
               FROM Order WHERE Id = :ord.Id];
    OrderItem ri = r.OrderItems[0];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ K05-ORDER CREATED (pre-reprice)  #' + r.OrderNumber
        + '\n  OrderId      : ' + ord.Id
        + '\n  Order URL    : ' + base + '/lightning/r/Order/' + ord.Id + '/view'
        + '\n  Status       : ' + r.Status + '  | Calc=' + r.CalculationStatus + '  | Validation=' + r.ValidationResult
        + '\n  OrderItemId  : ' + ri.Id
        + '\n  Line         : ' + pbe.Product2.Name + '  | Qty=' + ri.Quantity + '  | UnitPrice=' + ri.UnitPrice
        + '  | TotalLineAmount=' + ri.TotalLineAmount + '  | PTC=' + ri.PricingTermCount + '  | EndDate=' + ri.EndDate
        + '\n  NEXT: (1) reprice via /connect/rev/sales-transaction/actions/place (Force/Skip) -> expect CompletedWithPricing'
        + '  (2) Activate AFTER reprice -> expect success / no INVALID_INPUT.');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ K05-ORDER FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
