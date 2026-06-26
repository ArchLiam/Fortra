/**
 * @description Tests for CancelLineNetSeedHandler (SC-3441).
 *
 *              THREE layers:
 *                1. PURE unit tests (in-memory SObjects, no DML) — resolveSeedNet
 *                   precedence, toDecimal coercion, the negative-qty gate, ListPrice
 *                   fallback, idempotency, empty-SOQL paths.
 *                2. REAL-DML trigger coverage — a positive QuoteLineItem insert drives
 *                   QuoteLineItemTrigger; a negative-qty OrderItem insert drives
 *                   OrderItemTrigger end-to-end (insert -> trigger -> handler -> stamp).
 *                3. REAL-DML asset-net resolution — Asset + AssetAction('Generate') +
 *                   AssetActionSource(NetUnitPrice) so the handler's three SOQL for-loops
 *                   (resolveActionAssets ORDER/QUOTE + resolveAssetNetByCurrency fold)
 *                   actually return rows and the cancel line is seeded with the asset NET.
 *
 *              ASSET-OBJECT NOTE: AssetAction / AssetActionSource describe as
 *              createable=false (platform-managed), but Apex TEST context bypasses that
 *              gate — proven by AssetContractLinkerActionTest, which inserts both with
 *              equally createable=false fields (AssetId, Type, AssetActionId, StartDate).
 *              We add NetUnitPrice + CurrencyIsoCode (plain Currency/Picklist, not
 *              calculated) which the handler's WHERE clause requires.
 */
@isTest
private class CancelLineNetSeedHandlerTest {

    private static final Id FAKE_ASSET = '02i000000000001AAA';
    private static final Decimal ASSET_NET = 3000;

    private static Map<Id, Map<String, Decimal>> netMap(Id assetId, Map<String, Decimal> byCur) {
        return new Map<Id, Map<String, Decimal>>{ assetId => byCur };
    }

    // ================================================================================
    // LAYER 1 — PURE unit tests (no DML)
    // ================================================================================

    @isTest
    static void resolveSeedNet_assetNetInLineCurrency_wins() {
        Map<Id, Map<String, Decimal>> m = netMap(FAKE_ASSET, new Map<String, Decimal>{ 'USD' => 3000 });
        System.assertEquals(3000, CancelLineNetSeedHandler.resolveSeedNet(FAKE_ASSET, 'USD', 9999, m));
    }

    @isTest
    static void resolveSeedNet_currencyMismatch_fallsBackToListPrice() {
        Map<Id, Map<String, Decimal>> m = netMap(FAKE_ASSET, new Map<String, Decimal>{ 'EUR' => 250 });
        System.assertEquals(350, CancelLineNetSeedHandler.resolveSeedNet(FAKE_ASSET, 'USD', 350, m));
    }

    @isTest
    static void resolveSeedNet_singleCurrencyAsset_noLineCurrency() {
        Map<Id, Map<String, Decimal>> m = netMap(FAKE_ASSET, new Map<String, Decimal>{ 'USD' => 1200 });
        System.assertEquals(1200, CancelLineNetSeedHandler.resolveSeedNet(FAKE_ASSET, null, 999, m));
    }

    @isTest
    static void resolveSeedNet_listPriceFallback_whenNoAsset() {
        System.assertEquals(350, CancelLineNetSeedHandler.resolveSeedNet(null, 'USD', 350,
            new Map<Id, Map<String, Decimal>>()));
    }

    @isTest
    static void resolveSeedNet_nullWhenNothingResolvable() {
        System.assertEquals(null, CancelLineNetSeedHandler.resolveSeedNet(null, 'USD', 0,
            new Map<Id, Map<String, Decimal>>()));
        System.assertEquals(null, CancelLineNetSeedHandler.resolveSeedNet(null, 'USD', null,
            new Map<Id, Map<String, Decimal>>()));
    }

    @isTest
    static void toDecimal_coercions() {
        System.assertEquals(null, CancelLineNetSeedHandler.toDecimal(null));
        System.assertEquals(-1, CancelLineNetSeedHandler.toDecimal(-1));
        System.assertEquals(3000, CancelLineNetSeedHandler.toDecimal((Decimal) 3000));
        System.assertEquals(null, CancelLineNetSeedHandler.toDecimal('not-a-number'));
    }

    @isTest
    static void resolveAssetNetByCurrency_emptyAndNoMatch() {
        System.assert(CancelLineNetSeedHandler.resolveAssetNetByCurrency(null).isEmpty());
        System.assert(CancelLineNetSeedHandler.resolveAssetNetByCurrency(new Set<Id>()).isEmpty());
        // a non-existent asset id => query returns nothing => empty map (exercises the SOQL)
        System.assert(
            CancelLineNetSeedHandler.resolveAssetNetByCurrency(new Set<Id>{ FAKE_ASSET }).isEmpty()
        );
    }

    @isTest
    static void handleOrderItems_inMemory_listPriceFallback() {
        // fake OrderActionId => OrderAction SOQL returns no asset => ListPrice fallback.
        OrderItem oi = (OrderItem) JSON.deserialize(
            '{"attributes":{"type":"OrderItem"},"Quantity":-1,"ListPrice":350,"CurrencyIsoCode":"USD","OrderActionId":"8OA000000000001"}',
            OrderItem.class
        );
        CancelLineNetSeedHandler.handleOrderItems(new List<OrderItem>{ oi });
        System.assertEquals(350, oi.get('CancelNetUnitPrice__c'),
            'negative-qty line should be seeded from ListPrice when no asset net exists');
    }

    @isTest
    static void handleOrderItems_positiveQty_untouched() {
        OrderItem oi = (OrderItem) JSON.deserialize(
            '{"attributes":{"type":"OrderItem"},"Quantity":1,"ListPrice":350,"CurrencyIsoCode":"USD"}',
            OrderItem.class
        );
        CancelLineNetSeedHandler.handleOrderItems(new List<OrderItem>{ oi });
        System.assertEquals(null, oi.get('CancelNetUnitPrice__c'),
            'positive-qty line must never be touched');
    }

    @isTest
    static void handleQuoteLines_inMemory_listPriceFallback() {
        QuoteLineItem qli = (QuoteLineItem) JSON.deserialize(
            '{"attributes":{"type":"QuoteLineItem"},"Quantity":-1,"ListPrice":350,"CurrencyIsoCode":"USD","QuoteActionId":"7oc000000000001"}',
            QuoteLineItem.class
        );
        CancelLineNetSeedHandler.handleQuoteLines(new List<QuoteLineItem>{ qli });
        System.assertEquals(350, qli.get('CancelNetUnitPrice__c'));
    }

    @isTest
    static void handlers_nullAndEmpty_safe() {
        CancelLineNetSeedHandler.handleOrderItems(null);
        CancelLineNetSeedHandler.handleOrderItems(new List<OrderItem>());
        CancelLineNetSeedHandler.handleQuoteLines(null);
        CancelLineNetSeedHandler.handleQuoteLines(new List<QuoteLineItem>());
        System.assert(true, 'no exception on null/empty input');
    }

    @isTest
    static void handleOrderItems_idempotent_noChurnAndZeroListSkipped() {
        OrderItem zero = (OrderItem) JSON.deserialize(
            '{"attributes":{"type":"OrderItem"},"Quantity":-1,"ListPrice":0,"CurrencyIsoCode":"USD"}',
            OrderItem.class
        );
        CancelLineNetSeedHandler.handleOrderItems(new List<OrderItem>{ zero });
        System.assertEquals(null, zero.get('CancelNetUnitPrice__c'),
            'a 0 ListPrice with no asset net must NOT be seeded with 0');

        OrderItem seeded = (OrderItem) JSON.deserialize(
            '{"attributes":{"type":"OrderItem"},"Quantity":-1,"ListPrice":350,"CurrencyIsoCode":"USD","CancelNetUnitPrice__c":350}',
            OrderItem.class
        );
        CancelLineNetSeedHandler.handleOrderItems(new List<OrderItem>{ seeded });
        System.assertEquals(350, seeded.get('CancelNetUnitPrice__c'));
    }

    // ================================================================================
    // LAYER 2 + 3 — REAL DML: triggers fire + asset-net SOQL folds resolve a real net
    // ================================================================================

    /**
     * ORDER end-to-end: insert a Quantity=-1 OrderItem whose OrderAction.SourceAssetId
     * resolves an AssetActionSource Generate row (NetUnitPrice=3000). Drives
     * OrderItemTrigger -> handleOrderItems -> resolveActionAssets(ORDER) ->
     * resolveAssetNetByCurrency(fold) -> stamps CancelNetUnitPrice__c = 3000.
     */
    @isTest
    static void orderCancel_realChain_stampsAssetNet() {
        Account acct = buildAccount();
        Product2 prod = buildProduct();
        PricebookEntry pbe = buildPbe(prod.Id);
        Id assetId = buildAssetWithNet(acct.Id, prod.Id, ASSET_NET);

        Order ord = new Order(
            AccountId = acct.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        OrderAction oa = new OrderAction(OrderId = ord.Id, Type = 'Amend', SourceAssetId = assetId);
        insert oa;

        // StartQuantity must be nonzero for an Amend-linked Order Product (RLM rule);
        // this mirrors a real cancellation line (StartQuantity=1, Quantity=-1).
        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            OrderActionId = oa.Id,
            PricebookEntryId = pbe.Id,
            StartQuantity = 1,
            Quantity = -1,
            UnitPrice = ASSET_NET
        );

        Test.startTest();
        insert oi; // before-insert OrderItemTrigger seeds CancelNetUnitPrice__c
        Test.stopTest();

        OrderItem reloaded = [SELECT CancelNetUnitPrice__c, NetUnitPrice FROM OrderItem WHERE Id = :oi.Id];
        System.assertEquals(ASSET_NET, reloaded.CancelNetUnitPrice__c,
            'cancel order line should be seeded with the asset NET via the before-save trigger');
        System.assertEquals(ASSET_NET, reloaded.NetUnitPrice,
            'order cancel line should also get NetUnitPrice stamped directly (writeable on OrderItem)');
    }

    /**
     * QUOTE asset-net resolution: a REAL QuoteAction with SourceAssetId, resolved through
     * an in-memory Quantity=-1 line (no risky negative-qty QLI DML). Covers
     * resolveActionAssets(QUOTE) + the asset-net fold and asserts the stamped net.
     */
    @isTest
    static void quoteCancel_realQuoteAction_stampsAssetNet() {
        Account acct = buildAccount();
        Product2 prod = buildProduct();
        Id assetId = buildAssetWithNet(acct.Id, prod.Id, ASSET_NET);

        Opportunity opp = new Opportunity(
            Name = 'SC3441 Opp', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Quote q = new Quote(
            Name = 'SC3441 Quote', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(), Status = 'Draft'
        );
        insert q;
        QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = 'Cancel', SourceAssetId = assetId);
        insert qa;

        QuoteLineItem qli = (QuoteLineItem) JSON.deserialize(
            '{"attributes":{"type":"QuoteLineItem"},"Quantity":-1,"QuoteActionId":"' + qa.Id + '"}',
            QuoteLineItem.class
        );

        Test.startTest();
        CancelLineNetSeedHandler.handleQuoteLines(new List<QuoteLineItem>{ qli });
        Test.stopTest();

        System.assertEquals(ASSET_NET, qli.get('CancelNetUnitPrice__c'),
            'cancel quote line should resolve the asset NET via its QuoteAction');
    }

    /**
     * QuoteLineItemTrigger body coverage via a proven positive-qty QLI insert (mirrors
     * QuoteLineItemTriggerHandlerTest). The SC-3441 handler call gates out on a positive
     * line; this just exercises the trigger path.
     */
    @isTest
    static void quoteTrigger_positiveLine_coverage() {
        Account acct = buildAccount();
        Product2 prod = buildProduct();
        PricebookEntry pbe = buildPbe(prod.Id);

        Opportunity opp = new Opportunity(
            Name = 'SC3441 Opp2', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Quote q = new Quote(
            Name = 'SC3441 Quote2', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(), Status = 'Draft'
        );
        insert q;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, Product2Id = prod.Id, PricebookEntryId = pbe.Id,
            Quantity = 10, UnitPrice = 1000
        );

        Test.startTest();
        insert qli; // fires QuoteLineItemTrigger (incl. the gated-out SC-3441 handler)
        Test.stopTest();

        System.assertNotEquals(null, qli.Id, 'positive QLI inserts; trigger runs without error');
        QuoteLineItem reloaded = [SELECT CancelNetUnitPrice__c FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(null, reloaded.CancelNetUnitPrice__c,
            'positive-qty line is never seeded');
    }

    // ================================================================================
    // DML helpers (RLM-proven minimal recipes)
    // ================================================================================

    private static Account buildAccount() {
        Account a = new Account(
            Name = 'SC3441 Acct',
            BillingCountry = 'United States',
            BillingState = 'California'
        );
        insert a;
        return a;
    }

    private static Product2 buildProduct() {
        Product2 p = new Product2(
            Name = 'SC3441 Prod',
            ProductCode = 'SC3441-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert p;
        return p;
    }

    private static PricebookEntry buildPbe(Id productId) {
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = productId,
            UnitPrice = ASSET_NET,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }

    /**
     * Asset + AssetAction('Generate'/'Initial Sale') + AssetActionSource(NetUnitPrice,
     * CurrencyIsoCode='USD'). Mirrors AssetContractLinkerActionTest; adds the NET so the
     * handler's `WHERE NetUnitPrice > 0` query returns the row. Returns the Asset Id.
     */
    private static Id buildAssetWithNet(Id accountId, Id productId, Decimal net) {
        Asset ast = new Asset(
            Name = 'SC3441 Asset',
            AccountId = accountId,
            Product2Id = productId,
            CurrentQuantity = 1
        );
        insert ast;

        AssetAction aa = new AssetAction(
            AssetId = ast.Id,
            Type = 'Generate',
            CategoryEnum = 'Initial Sale',
            ActionDate = DateTime.now(),
            Amount = net,
            QuantityChange = 1,
            MrrChange = 0
        );
        insert aa;

        // CurrencyIsoCode is NOT writeable on AssetActionSource (platform-managed); it
        // defaults to the corporate currency (USD), which is what the handler keys on.
        AssetActionSource aas = new AssetActionSource(
            AssetActionId = aa.Id,
            NetUnitPrice = net
        );
        insert aas;

        return ast.Id;
    }
}
