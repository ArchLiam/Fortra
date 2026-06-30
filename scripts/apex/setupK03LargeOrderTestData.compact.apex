// setupK03LargeOrderTestData.compact.apex
// Builds a K-03 "large-order governor safety" ORDER fixture in FortraUAT: a Draft Order with 30+ line
// items INCLUDING one high-quantity Power line (Solution_Group__c='Power', Order Line Only, NO Partition
// -> P3 keeps it as one Quantity=N line). Purpose: smoke-test Reprice-All (whole pricing procedure on
// order context) WITHIN Apex CPU/SOQL/DML governor limits — the SC-3366 (SOQL:101 on large orders) and
// SC-3447 (CPU on high-qty Power) regression surface.
//
//   Account 001WC00000XiZP4YAN ('Fortra, LLC - Test') — canonical reusable test account.
//   ~35 OrderItems: 1 high-qty Power (qty LARGE_QTY) + 34 general priceable lines from the active
//   Fortra Price Book (USD). Draft status -> repriceable with NO Workday / activation side-effects.
//
// Atomic: savepoint rollback on any failure. On success the Order is COMMITTED + openable, and the
// fixture is left in place for a Force-reprice via the REST place action.
//
// Run:  sf apex run --target-org FortraUAT -f scripts/apex/setupK03LargeOrderTestData.compact.apex
// Output: grep the debug log for the "K03-ORDER" marker (logged at ERROR level).

Integer NUM_GENERAL = 34;       // general lines (+1 Power = 35 total, > the 30-line K-03 threshold)
Integer LARGE_QTY   = 5000;     // high-qty Power seat/license count (would have been 4999 clones pre-P3)
Id ACCT             = '001WC00000XiZP4YAN';
Id PRICEBOOK        = '01sWC0000022GHFYA2';  // 'Fortra Price Book' (active)

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Math.round(Math.random()*9999));

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

// High-qty Power PBE (Order Line Only, USD, active Fortra pricebook) -> stays one Quantity=N line.
PricebookEntry powerPbe = [SELECT Id, Product2.Name, UnitPrice FROM PricebookEntry
                           WHERE Product2.Solution_Group__c = 'Power'
                             AND Product2.Power_Split_Type__c = 'Order Line Only'
                             AND IsActive = true AND Product2.IsActive = true AND Pricebook2.IsActive = true
                             AND Pricebook2Id = :PRICEBOOK AND CurrencyIsoCode = 'USD' AND UnitPrice > 0
                           LIMIT 1];

// A spread of general priceable lines (distinct products -> the O(2L) per-original flow surface + bulk
// pricing matrices the K-03 scenario stresses). Exclude the Power product to keep it the only Power line.
List<PricebookEntry> generalPbes = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry
                                    WHERE IsActive = true AND Product2.IsActive = true AND Pricebook2.IsActive = true
                                      AND Pricebook2Id = :PRICEBOOK AND CurrencyIsoCode = 'USD' AND UnitPrice > 0
                                      AND Product2Id != :powerPbe.Product2Id
                                    LIMIT :NUM_GENERAL];

Savepoint sp = Database.setSavepoint();
try {
    Order ord = new Order(
        AccountId       = ACCT,
        Pricebook2Id    = PRICEBOOK,
        Status          = 'Draft',
        EffectiveDate   = Date.today(),
        CurrencyIsoCode = 'USD',
        Name            = 'K03 Large Order ' + TAG);
    Database.insert(ord, dml);

    List<OrderItem> items = new List<OrderItem>();
    // 1 high-qty Power line.
    items.add(new OrderItem(OrderId = ord.Id, PricebookEntryId = powerPbe.Id, Product2Id = powerPbe.Product2Id,
                            Quantity = LARGE_QTY, UnitPrice = powerPbe.UnitPrice, ServiceDate = Date.today()));
    // 34 general lines.
    OrderItem oi;
    for (PricebookEntry p : generalPbes) {
        oi = new OrderItem(OrderId = ord.Id, PricebookEntryId = p.Id, Product2Id = p.Product2Id,
                           Quantity = 1, UnitPrice = p.UnitPrice, ServiceDate = Date.today());
        items.add(oi);
    }
    Database.insert(items, dml);

    Integer total = [SELECT COUNT() FROM OrderItem WHERE OrderId = :ord.Id];
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ K03-ORDER CREATED  ' + ord.Name
        + '\n  Order        : ' + base + '/' + ord.Id + '  (Id=' + ord.Id + ')'
        + '\n  Lines        : ' + total + ' OrderItems (1 high-qty Power + ' + generalPbes.size() + ' general)'
        + '\n  Power line   : ' + powerPbe.Product2.Name + '  | Qty ' + LARGE_QTY + '  (NO Partition -> P3 keeps it ONE line)'
        + '\n  NEXT         : Force-reprice via REST place action (Order type, id=' + ord.Id + '); confirm NO'
        + ' SOQL:101 / CPU / too-many-DML governor error.');
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ K03-ORDER FAILED (rolled back) ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
