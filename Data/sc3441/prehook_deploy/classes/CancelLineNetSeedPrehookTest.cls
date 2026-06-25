/**
 * @description Test class for CancelLineNetSeedPrehook (SC-3441).
 *
 *              Covers, with hand-built context maps and synthetic AssetActionSource
 *              rows (no live pricing context required):
 *                - Order cancel  -> asset net resolved & seeded.
 *                - Quote cancel  -> asset net resolved & seeded.
 *                - ListPrice-0 asset-net case (asset-net path required; list fallback
 *                  would have produced no/zero credit).
 *                - Asset-net resolves to 0 + ListPrice>0 -> ListPrice fallback fires
 *                  (defect-#2 inverse: a zero-net Generate is excluded by the
 *                  NetUnitPrice>0 fold, so the undiscounted line is still credited).
 *                - Normal positive-qty line -> NO write (never enters cancel map).
 *                - Null-safety: missing asset / missing action / bad dataPath.
 *                - Currency: non-USD line never inherits a USD asset-net; a
 *                  matching-currency line seeds correctly; and a currency MISMATCH
 *                  with a positive line ListPrice falls back to the LINE-currency
 *                  ListPrice (never leaks the foreign asset net).
 *                - Lossy ListPrice fallback when asset-net is unavailable.
 *                - Zero/null-net Generate rejected by the NetUnitPrice>0 fold.
 *                - buildNodeUpdate / parse / scope / tag-extraction helpers.
 *                - Live-call swallow/re-throw contract (fetch + submit against a bogus
 *                  context); RegionalServices-style: "not in updatable state" swallowed,
 *                  any other error re-thrown to execute()'s outer catch.
 *
 *              Read-only relationship fields on AssetActionSource (AssetAction.AssetId
 *              / Type / CategoryEnum) are populated via JSON deserialization, the
 *              standard Apex pattern for setting parent-relationship fields without DML.
 *
 * @author 5S Infusion (SC-3441)
 * @date June 2026
 */
@IsTest
private class CancelLineNetSeedPrehookTest {

    // Stable synthetic Ids. 15-char literals are always valid (no check digit) and
    // Apex auto-expands them to the correct 18-char form; using the bad-check-digit
    // 18-char form (e.g. '0Q0...AAA') would fail Id.valueOf for the Quote/QLI prefixes.
    private static final Id ORDER_ID   = '801000000000001';
    private static final Id OI_ID      = '802000000000001';
    private static final Id QUOTE_ID   = '0Q0000000000001';
    private static final Id QLI_ID     = '0QL000000000001';
    private static final Id ASSET_ID   = '02i000000000001';
    private static final Id ASSET_ID_2 = '02i000000000002';

    // ============================================================
    // Local fixtures (self-contained — no external fixture class dependency)
    // ============================================================

    /** Wrap a scalar as a {tagValue: v} node, matching the live context shape. */
    private static Map<String, Object> tag(Object v) {
        return new Map<String, Object>{ 'tagValue' => v };
    }

    /** Build a SalesTransactionItem node {tagValue:{...}, dataPath:[...]}. */
    private static Map<String, Object> itemNode(Map<String, Object> tags, List<Object> dataPath) {
        return new Map<String, Object>{ 'tagValue' => tags, 'dataPath' => dataPath };
    }

    /** Build a synthetic AssetActionSource with its read-only parent fields set. */
    private static AssetActionSource aas(Id assetId, String type, String category, Decimal net, String currencyCode) {
        Map<String, Object> m = new Map<String, Object>{
            'NetUnitPrice' => net,
            'CurrencyIsoCode' => currencyCode,
            'AssetAction' => new Map<String, Object>{
                'AssetId' => assetId,
                'Type' => type,
                'CategoryEnum' => category
            }
        };
        return (AssetActionSource) JSON.deserialize(JSON.serialize(m), AssetActionSource.class);
    }

    /** Find the attributeValue for a name in a list of {attributeName,attributeValue} maps. */
    private static Object attrValue(Map<String, Object> nodeUpdate, String name) {
        List<Object> attrs = (List<Object>) nodeUpdate.get('attributes');
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            if (name.equals(a.get('attributeName'))) {
                return a.get('attributeValue');
            }
        }
        return null;
    }

    private static List<Object> updatePathOf(Map<String, Object> nodeUpdate) {
        Map<String, Object> np = (Map<String, Object>) nodeUpdate.get('nodePath');
        return (List<Object>) np.get('dataPath');
    }

    // ============================================================
    // 1. ORDER cancel — asset net resolved & seeded (the headline case)
    // ============================================================

    @IsTest
    static void testOrderCancel_AssetNetSeeded() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        // Cancel line: qty -1, USD, ListPrice 3000 (undiscounted sale).
        Map<String, Object> node = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'SalesTransactionActionType' => tag('Cancel'),
                'SalesTransactionSourceAsset' => tag(ASSET_ID),
                'ListPrice' => tag(3000),
                'STICurrencyIsoCode' => tag('USD')
            },
            new List<Object>{ ORDER_ID, OI_ID }
        );

        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ node });
        System.assertEquals(1, cancels.size(), 'The negative-qty line should be collected');

        // Asset net resolved from a Generate / Initial Sale row at 3000 USD.
        Map<Id, Id> lineToAsset = new Map<Id, Id>{ OI_ID => ASSET_ID };
        Map<Id, Map<String, Decimal>> netMap = new Map<Id, Map<String, Decimal>>();
        hook.applyAssetNetSource(netMap, aas(ASSET_ID, 'Generate', 'Initial Sale', 3000, 'USD'));

        Test.startTest();
        List<Map<String, Object>> updates = hook.buildSeedUpdates(cancels, lineToAsset, netMap);
        Test.stopTest();

        System.assertEquals(1, updates.size(), 'One seed update for the order cancel line');
        System.assertEquals(3000, attrValue(updates[0], 'CancelNetUnitPrice__c'),
            'Seeded per-unit net should be the asset NET (3000), not a sign-flipped or list value');
        // dataPath first element (the Order root) is dropped.
        List<Object> up = updatePathOf(updates[0]);
        System.assertEquals(1, up.size(), 'Root entity Id should be dropped from the node path');
        System.assertEquals(OI_ID, up[0], 'Remaining segment is the OrderItem Id');
    }

    // ============================================================
    // 2. QUOTE cancel — asset net resolved & seeded
    // ============================================================

    @IsTest
    static void testQuoteCancel_AssetNetSeeded() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        Map<String, Object> node = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'SalesTransactionActionType' => tag('Cancel'),
                'SalesTransactionSourceAsset' => tag(ASSET_ID),
                'ListPrice' => tag(3000),
                'STICurrencyIsoCode' => tag('USD')
            },
            new List<Object>{ QUOTE_ID, QLI_ID }
        );

        // Scope should resolve to Quote.
        String scope = hook.resolveScope(new List<Object>{ node });
        System.assertEquals('Quote', scope, 'Quote root prefix should resolve Quote scope');

        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ node });

        Map<Id, Id> lineToAsset = new Map<Id, Id>{ QLI_ID => ASSET_ID };
        Map<Id, Map<String, Decimal>> netMap = new Map<Id, Map<String, Decimal>>();
        hook.applyAssetNetSource(netMap, aas(ASSET_ID, 'Generate', 'Initial Sale', 3000, 'USD'));

        Test.startTest();
        List<Map<String, Object>> updates = hook.buildSeedUpdates(cancels, lineToAsset, netMap);
        Test.stopTest();

        System.assertEquals(1, updates.size(), 'One seed update for the quote cancel line');
        System.assertEquals(3000, attrValue(updates[0], 'CancelNetUnitPrice__c'),
            'Quote cancel should seed the asset NET');
        System.assertEquals(QLI_ID, updatePathOf(updates[0])[0], 'Remaining segment is the QLI Id');
    }

    // ============================================================
    // 3. ListPrice-0 asset-net case — asset-net path REQUIRED
    // ============================================================

    @IsTest
    static void testListPriceZero_AssetNetWins() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        // beSECURE-style broken line: ListPrice 0 but the asset sold at a real net.
        Map<String, Object> node = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'SalesTransactionActionType' => tag('Cancel'),
                'SalesTransactionSourceAsset' => tag(ASSET_ID),
                'ListPrice' => tag(0),
                'STICurrencyIsoCode' => tag('USD')
            },
            new List<Object>{ ORDER_ID, OI_ID }
        );

        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ node });

        Map<Id, Id> lineToAsset = new Map<Id, Id>{ OI_ID => ASSET_ID };
        Map<Id, Map<String, Decimal>> netMap = new Map<Id, Map<String, Decimal>>();
        // Asset net 4250 even though catalog ListPrice is 0.
        hook.applyAssetNetSource(netMap, aas(ASSET_ID, 'Generate', 'Initial Sale', 4250, 'USD'));

        Test.startTest();
        List<Map<String, Object>> updates = hook.buildSeedUpdates(cancels, lineToAsset, netMap);
        Test.stopTest();

        System.assertEquals(1, updates.size(), 'ListPrice-0 cancel still seeds via the asset-net path');
        System.assertEquals(4250, attrValue(updates[0], 'CancelNetUnitPrice__c'),
            'Asset NET (4250) must be used; the LossyListPrice-0 fallback would have produced nothing');
    }

    // ============================================================
    // 4. Normal POSITIVE-qty line — NO write
    // ============================================================

    @IsTest
    static void testPositiveLine_NoWrite() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        Map<String, Object> positive = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(2),
                'SalesTransactionActionType' => tag('Add'),
                'ListPrice' => tag(500),
                'STICurrencyIsoCode' => tag('USD')
            },
            new List<Object>{ ORDER_ID, '802000000000099' }
        );
        Map<String, Object> zeroQty = itemNode(
            new Map<String, Object>{ 'Quantity' => tag(0), 'ListPrice' => tag(500) },
            new List<Object>{ ORDER_ID, '802000000000098' }
        );

        Test.startTest();
        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ positive, zeroQty });
        // Even if forced through buildSeedUpdates, an empty cancel map yields no updates.
        List<Map<String, Object>> updates = hook.buildSeedUpdates(
            cancels, new Map<Id, Id>(), new Map<Id, Map<String, Decimal>>());
        Test.stopTest();

        System.assertEquals(0, cancels.size(), 'Positive and zero qty lines must NOT be collected as cancels');
        System.assertEquals(0, updates.size(), 'No node update may be emitted for normal lines');
    }

    // ============================================================
    // 5. Null-safety — missing asset / missing action / bad dataPath
    // ============================================================

    @IsTest
    static void testNullSafety_MissingAssetAndAction() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        // Cancel line with NO source asset and ListPrice 0 -> nothing resolvable -> skip.
        Map<String, Object> noAsset = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'ListPrice' => tag(0),
                'STICurrencyIsoCode' => tag('USD')
            },
            new List<Object>{ ORDER_ID, OI_ID }
        );
        // Cancel line whose dataPath last element is not an Id -> dropped in collect.
        Map<String, Object> badPath = itemNode(
            new Map<String, Object>{ 'Quantity' => tag(-1), 'ListPrice' => tag(100) },
            new List<Object>{ ORDER_ID, 'NOT-AN-ID' }
        );

        Test.startTest();
        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ noAsset, badPath });
        // Only the well-formed (noAsset) line is collected; lineToAsset is empty so
        // asset-net is unavailable, and ListPrice 0 disqualifies the lossy fallback.
        List<Map<String, Object>> updates = hook.buildSeedUpdates(
            cancels, new Map<Id, Id>(), new Map<Id, Map<String, Decimal>>());
        Test.stopTest();

        System.assertEquals(1, cancels.size(), 'Bad-dataPath line dropped; well-formed cancel kept');
        System.assertEquals(0, updates.size(),
            'No asset, ListPrice 0 -> nothing safe to seed -> no write (no zero/garbage credit)');

        // resolveSeedNet null inputs are all null-safe.
        System.assertEquals(null, hook.resolveSeedNet(null, null, null),
            'resolveSeedNet must be null-safe on a null line');
    }

    // ============================================================
    // 6. Currency — non-USD line never inherits USD asset-net
    // ============================================================

    @IsTest
    static void testCurrency_NoUsdMisCredit() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        // EUR cancel line; asset has a USD net only -> must NOT seed the USD value,
        // and (ListPrice 0) -> no fallback -> skip.
        Map<String, Object> eurNode = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'SalesTransactionActionType' => tag('Cancel'),
                'SalesTransactionSourceAsset' => tag(ASSET_ID),
                'ListPrice' => tag(0),
                'STICurrencyIsoCode' => tag('EUR')
            },
            new List<Object>{ ORDER_ID, OI_ID }
        );

        Map<Id, CancelLineNetSeedPrehook.CancelLine> eurCancels =
            hook.collectCancelLines(new List<Object>{ eurNode });
        Map<Id, Id> lineToAsset = new Map<Id, Id>{ OI_ID => ASSET_ID };

        // Asset net is USD only.
        Map<Id, Map<String, Decimal>> usdOnly = new Map<Id, Map<String, Decimal>>();
        hook.applyAssetNetSource(usdOnly, aas(ASSET_ID, 'Generate', 'Initial Sale', 3000, 'USD'));

        Test.startTest();
        List<Map<String, Object>> mismatch = hook.buildSeedUpdates(eurCancels, lineToAsset, usdOnly);

        // Now the SAME asset also has a matching EUR net -> it IS seeded in EUR.
        Map<Id, Map<String, Decimal>> bothCur = new Map<Id, Map<String, Decimal>>();
        hook.applyAssetNetSource(bothCur, aas(ASSET_ID, 'Generate', 'Initial Sale', 3000, 'USD'));
        hook.applyAssetNetSource(bothCur, aas(ASSET_ID, 'Generate', 'Initial Sale', 2600, 'EUR'));
        List<Map<String, Object>> matched = hook.buildSeedUpdates(eurCancels, lineToAsset, bothCur);
        Test.stopTest();

        System.assertEquals(0, mismatch.size(),
            'A USD-only asset net must NOT be seeded onto a EUR line (no USD mis-credit)');
        System.assertEquals(1, matched.size(), 'The matching EUR net should be seeded');
        System.assertEquals(2600, attrValue(matched[0], 'CancelNetUnitPrice__c'),
            'EUR line must seed the EUR asset net (2600), never the USD 3000');
    }

    // ============================================================
    // 7. Lossy ListPrice fallback (asset-net unavailable, ListPrice > 0)
    // ============================================================

    @IsTest
    static void testListPriceFallback_WhenAssetNetUnavailable() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        Map<String, Object> node = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'SalesTransactionActionType' => tag('Cancel'),
                'ListPrice' => tag(1800),
                'STICurrencyIsoCode' => tag('USD')
            },
            new List<Object>{ ORDER_ID, OI_ID }
        );
        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ node });

        Test.startTest();
        // No asset mapping and no asset-net map -> lossy ListPrice fallback (1800).
        List<Map<String, Object>> updates = hook.buildSeedUpdates(
            cancels, new Map<Id, Id>(), new Map<Id, Map<String, Decimal>>());
        Test.stopTest();

        System.assertEquals(1, updates.size(), 'ListPrice>0 fallback should seed when asset-net is unavailable');
        System.assertEquals(1800, attrValue(updates[0], 'CancelNetUnitPrice__c'),
            'Lossy fallback seeds the catalog ListPrice');
    }

    // ============================================================
    // 8. applyAssetNetSource selection precedence (Generate sticky, currency split)
    // ============================================================

    @IsTest
    static void testApplyAssetNetSource_Precedence() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();
        Map<Id, Map<String, Decimal>> netMap = new Map<Id, Map<String, Decimal>>();

        Test.startTest();
        // Folded oldest -> newest. A non-Generate is set first, then Generate locks it,
        // and a later non-Generate must NOT override the Generate value.
        hook.applyAssetNetSource(netMap, aas(ASSET_ID, 'Change', 'Renewals', 999, 'USD'));   // initial
        hook.applyAssetNetSource(netMap, aas(ASSET_ID, 'Generate', 'Initial Sale', 3000, 'USD')); // locks
        hook.applyAssetNetSource(netMap, aas(ASSET_ID, 'Cancel', 'Cancellations', 111, 'USD'));   // ignored

        // Different asset, different currency, null/zero net + blank currency ignored.
        hook.applyAssetNetSource(netMap, aas(ASSET_ID_2, 'Generate', 'Initial Sale', 700, 'GBP'));
        hook.applyAssetNetSource(netMap, aas(ASSET_ID_2, 'Generate', 'Initial Sale', null, 'USD'));   // null net ignored
        hook.applyAssetNetSource(netMap, aas(ASSET_ID_2, 'Generate', 'Initial Sale', 0, 'USD'));      // ZERO net ignored
        hook.applyAssetNetSource(netMap, aas(ASSET_ID_2, 'Generate', 'Initial Sale', 500, ''));       // blank cur ignored
        hook.applyAssetNetSource(netMap, null);                                                       // null row ignored
        Test.stopTest();

        System.assertEquals(3000, netMap.get(ASSET_ID).get('USD'),
            'Generate row must win and stay locked against later non-Generate rows');
        System.assertEquals(700, netMap.get(ASSET_ID_2).get('GBP'), 'Second asset GBP net retained');
        System.assertEquals(false, netMap.get(ASSET_ID_2).containsKey('USD'),
            'Null-net AND zero-net Generate must not create a USD entry (NetUnitPrice > 0 filter)');
    }

    // ============================================================
    // 8b. Asset-net resolves to 0 with ListPrice > 0 -> ListPrice fallback
    //     (defect #2 inverse: an undiscounted line whose Generate net is 0 due to
    //      data quality must still be credited from its own catalog ListPrice).
    //     With the NetUnitPrice > 0 fold, a zero-net Generate never enters the map,
    //     so asset-net is "unavailable" for this asset and the fallback fires.
    // ============================================================

    @IsTest
    static void testAssetNetZero_ListPriceFallbackSeeds() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        Map<String, Object> node = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'SalesTransactionActionType' => tag('Cancel'),
                'SalesTransactionSourceAsset' => tag(ASSET_ID),
                'ListPrice' => tag(1800),
                'STICurrencyIsoCode' => tag('USD')
            },
            new List<Object>{ ORDER_ID, OI_ID }
        );
        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ node });
        Map<Id, Id> lineToAsset = new Map<Id, Id>{ OI_ID => ASSET_ID };

        // Fold a ZERO-net Generate -> it is rejected by applyAssetNetSource, so the
        // asset has NO entry in the net map (asset-net effectively unavailable).
        Map<Id, Map<String, Decimal>> netMap = new Map<Id, Map<String, Decimal>>();
        hook.applyAssetNetSource(netMap, aas(ASSET_ID, 'Generate', 'Initial Sale', 0, 'USD'));

        Test.startTest();
        List<Map<String, Object>> updates = hook.buildSeedUpdates(cancels, lineToAsset, netMap);
        Test.stopTest();

        System.assertEquals(false, netMap.containsKey(ASSET_ID),
            'A zero-net Generate must not register the asset in the net map');
        System.assertEquals(1, updates.size(),
            'Zero asset-net + ListPrice>0 must fall through to the lossy ListPrice fallback');
        System.assertEquals(1800, attrValue(updates[0], 'CancelNetUnitPrice__c'),
            'The line ListPrice (1800) credits the undiscounted line when no positive asset-net exists');
    }

    // ============================================================
    // 8c. Currency MISMATCH with a positive line ListPrice -> lossy fallback in
    //     the LINE currency (proves a USD-only asset net is never leaked onto a EUR
    //     line; the EUR line is instead credited from its own EUR ListPrice).
    // ============================================================

    @IsTest
    static void testCurrencyMismatch_FallsBackToLineListPrice() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        // EUR cancel line WITH a positive ListPrice; asset has a USD net only.
        Map<String, Object> eurNode = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'SalesTransactionActionType' => tag('Cancel'),
                'SalesTransactionSourceAsset' => tag(ASSET_ID),
                'ListPrice' => tag(1500),
                'STICurrencyIsoCode' => tag('EUR')
            },
            new List<Object>{ ORDER_ID, OI_ID }
        );
        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ eurNode });
        Map<Id, Id> lineToAsset = new Map<Id, Id>{ OI_ID => ASSET_ID };

        // Asset net USD only (3000) -> mismatch for the EUR line.
        Map<Id, Map<String, Decimal>> usdOnly = new Map<Id, Map<String, Decimal>>();
        hook.applyAssetNetSource(usdOnly, aas(ASSET_ID, 'Generate', 'Initial Sale', 3000, 'USD'));

        Test.startTest();
        List<Map<String, Object>> updates = hook.buildSeedUpdates(cancels, lineToAsset, usdOnly);
        Test.stopTest();

        System.assertEquals(1, updates.size(),
            'Currency mismatch must fall back to the line ListPrice (not skip a line that has a list)');
        System.assertEquals(1500, attrValue(updates[0], 'CancelNetUnitPrice__c'),
            'EUR line must seed its OWN EUR ListPrice (1500), never the USD asset net (3000)');
    }

    // ============================================================
    // 9. Single-currency asset, line currency tag missing -> safe use
    // ============================================================

    @IsTest
    static void testSingleCurrencyAsset_LineCurrencyMissing() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        // Cancel line with NO STICurrencyIsoCode tag, asset has exactly one currency.
        Map<String, Object> node = itemNode(
            new Map<String, Object>{
                'Quantity' => tag(-1),
                'SalesTransactionActionType' => tag('Cancel'),
                'SalesTransactionSourceAsset' => tag(ASSET_ID),
                'ListPrice' => tag(0)
            },
            new List<Object>{ ORDER_ID, OI_ID }
        );
        Map<Id, CancelLineNetSeedPrehook.CancelLine> cancels =
            hook.collectCancelLines(new List<Object>{ node });
        Map<Id, Id> lineToAsset = new Map<Id, Id>{ OI_ID => ASSET_ID };
        Map<Id, Map<String, Decimal>> netMap = new Map<Id, Map<String, Decimal>>();
        hook.applyAssetNetSource(netMap, aas(ASSET_ID, 'Generate', 'Initial Sale', 1234, 'USD'));

        Test.startTest();
        List<Map<String, Object>> updates = hook.buildSeedUpdates(cancels, lineToAsset, netMap);
        Test.stopTest();

        System.assertEquals(1, updates.size(), 'Single-currency asset is unambiguous even without a line currency tag');
        System.assertEquals(1234, attrValue(updates[0], 'CancelNetUnitPrice__c'),
            'The sole asset-currency net is safe to use');
    }

    // ============================================================
    // 10. buildNodeUpdate / dataPath guard
    // ============================================================

    @IsTest
    static void testBuildNodeUpdate_DataPathGuard() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        Test.startTest();
        Map<String, Object> withPath = hook.buildNodeUpdate(
            new List<Object>{ ORDER_ID, OI_ID }, 3000);
        Map<String, Object> emptyPath = hook.buildNodeUpdate(new List<Object>(), 50);
        Map<String, Object> nullPath = hook.buildNodeUpdate(null, 75);
        Test.stopTest();

        System.assertEquals(1, updatePathOf(withPath).size(), 'First element dropped');
        System.assertEquals(OI_ID, updatePathOf(withPath)[0], 'Line Id remains');
        System.assertEquals(3000, attrValue(withPath, 'CancelNetUnitPrice__c'), 'Seed value carried');
        System.assertEquals(0, updatePathOf(emptyPath).size(), 'Empty path stays empty (no remove)');
        System.assertEquals(0, updatePathOf(nullPath).size(), 'Null path becomes empty');
    }

    // ============================================================
    // 11. parseLineNodes — nested / flat / single-object / null shapes
    // ============================================================

    @IsTest
    static void testParseLineNodes_Shapes() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();
        Map<String, Object> one = itemNode(new Map<String, Object>{ 'Quantity' => tag(-1) },
            new List<Object>{ ORDER_ID, OI_ID });

        Test.startTest();
        // Nested {queryResult:{SalesTransactionItem:[...]}}
        List<Object> nested = hook.parseLineNodes(new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SalesTransactionItem' => new List<Object>{ one } }
        });
        // Flat {SalesTransactionItem:[...]}
        List<Object> flat = hook.parseLineNodes(new Map<String, Object>{
            'SalesTransactionItem' => new List<Object>{ one }
        });
        // Single object (not a list)
        List<Object> single = hook.parseLineNodes(new Map<String, Object>{
            'SalesTransactionItem' => one
        });
        // Null / missing
        List<Object> none = hook.parseLineNodes(null);
        List<Object> missing = hook.parseLineNodes(new Map<String, Object>{ 'x' => 'y' });
        Test.stopTest();

        System.assertEquals(1, nested.size(), 'Nested shape parsed');
        System.assertEquals(1, flat.size(), 'Flat shape parsed');
        System.assertEquals(1, single.size(), 'Single object wrapped into a list');
        System.assertEquals(null, none, 'Null response -> null');
        System.assertEquals(null, missing, 'Missing key -> null');
    }

    // ============================================================
    // 12. resolveScope — Order / Quote / neither
    // ============================================================

    @IsTest
    static void testResolveScope_Variants() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        Map<String, Object> orderNode = itemNode(new Map<String, Object>(), new List<Object>{ ORDER_ID, OI_ID });
        Map<String, Object> quoteNode = itemNode(new Map<String, Object>(), new List<Object>{ QUOTE_ID, QLI_ID });
        Map<String, Object> alienNode = itemNode(new Map<String, Object>(), new List<Object>{ '001000000000001' });

        Test.startTest();
        System.assertEquals('Order', hook.resolveScope(new List<Object>{ orderNode }));
        System.assertEquals('Quote', hook.resolveScope(new List<Object>{ quoteNode }));
        System.assertEquals(null, hook.resolveScope(new List<Object>{ alienNode }), 'Neither prefix -> null');
        System.assertEquals(null, hook.resolveScope(new List<Object>()), 'Empty list -> null');
        System.assertEquals(null, hook.resolveScope(null), 'Null list -> null');
        Test.stopTest();
    }

    // ============================================================
    // 13. tag-extraction helpers (nested/flat/typed/bad)
    // ============================================================

    @IsTest
    static void testTagHelpers() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        Test.startTest();
        // getDecimalFromTag
        System.assertEquals(null, hook.getDecimalFromTag(null, 'Quantity'), 'Null map -> null');
        System.assertEquals(null, hook.getDecimalFromTag(new Map<String, Object>(), 'Quantity'), 'Missing -> null');
        System.assertEquals(-1, hook.getDecimalFromTag(new Map<String, Object>{ 'Quantity' => tag(-1) }, 'Quantity'),
            'Nested tagValue integer parsed');
        System.assertEquals(3000.50, hook.getDecimalFromTag(new Map<String, Object>{ 'P' => tag('3000.50') }, 'P'),
            'Nested numeric string parsed');
        System.assertEquals(42, hook.getDecimalFromTag(new Map<String, Object>{ 'P' => 42 }, 'P'),
            'Flat number parsed');
        System.assertEquals(null, hook.getDecimalFromTag(new Map<String, Object>{ 'P' => tag('abc') }, 'P'),
            'Non-numeric -> null via catch');

        // getStringFromTag
        System.assertEquals(null, hook.getStringFromTag(null, 'k'), 'Null map -> null');
        System.assertEquals('Cancel',
            hook.getStringFromTag(new Map<String, Object>{ 'SalesTransactionActionType' => tag('Cancel') }, 'SalesTransactionActionType'),
            'Nested string parsed');
        System.assertEquals('USD',
            hook.getStringFromTag(new Map<String, Object>{ 'STICurrencyIsoCode' => 'USD' }, 'STICurrencyIsoCode'),
            'Flat string parsed');

        // lineIdFromDataPath
        System.assertEquals(OI_ID, hook.lineIdFromDataPath(new List<Object>{ ORDER_ID, OI_ID }), 'Last element Id');
        System.assertEquals(null, hook.lineIdFromDataPath(new List<Object>{ 'x' }), 'Bad Id -> null');
        System.assertEquals(null, hook.lineIdFromDataPath(new List<Object>()), 'Empty -> null');
        System.assertEquals(null, hook.lineIdFromDataPath(null), 'Null -> null');

        // extractTagMap (flat node passthrough)
        Map<String, Object> flat = new Map<String, Object>{ 'Quantity' => tag(-1) };
        System.assertEquals(flat, hook.extractTagMap(flat), 'Flat node returns itself');
        Test.stopTest();
    }

    // ============================================================
    // 14. Live-call swallow contracts (fetch + submit against a bogus context)
    // ============================================================

    @IsTest
    static void testLiveCalls_SwallowOnBogusContext() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();
        Context.IndustriesContext ctx = new Context.IndustriesContext();

        Test.startTest();
        // fetch swallows a live failure -> null (degrade gracefully, never throws).
        List<Object> fetched = hook.fetchSalesTransactionItems(ctx, 'bogus-context-id');

        // submit against a bogus context: by the deliberate RegionalServices-style
        // contract, a "not in updatable state" failure is swallowed (returns 0), but
        // ANY OTHER failure is RE-THROWN so execute()'s outer try/catch can report it.
        // A bogus context id may produce either, so we tolerate both outcomes here and
        // assert the REAL invariant (the prehook never breaks the reprice) via
        // execute() in testExecute_Paths. The only guarantee asserted directly is that
        // submit either swallows-to-0 or throws a managed exception — it never returns
        // a partial/garbage count.
        List<Map<String, Object>> updates = new List<Map<String, Object>>{
            hook.buildNodeUpdate(new List<Object>{ ORDER_ID, OI_ID }, 3000)
        };
        Integer submitted = -1;
        Boolean threwManaged = false;
        try {
            submitted = hook.submitContextUpdates(ctx, 'bogus-context-id', updates);
        } catch (Exception e) {
            threwManaged = true; // re-thrown non-"updatable state" error (acceptable)
        }

        // Empty/null update lists short-circuit to 0 BEFORE any live call (always safe).
        Integer emptySubmit = hook.submitContextUpdates(ctx, 'bogus-context-id', new List<Map<String, Object>>());
        Test.stopTest();

        System.assertEquals(null, fetched, 'A failed queryTags must be swallowed -> null');
        System.assert(threwManaged || submitted == 0,
            'submit must either swallow the not-updatable path (0) or re-throw a managed error; never a partial count');
        System.assertEquals(0, emptySubmit, 'Empty update list returns 0 without any live call');
    }

    // ============================================================
    // 15. execute() end-to-end paths (recursion guard, blank ctx, error swallow)
    // ============================================================

    @IsTest
    static void testExecute_Paths() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();

        Test.startTest();
        // RevSignaling.TransactionRequest has no public no-arg constructor; build it
        // via JSON deserialization (verified seam) to set ctxInstanceId.
        // Blank context id -> SUCCESS, no-op.
        RevSignaling.TransactionRequest blankReq = (RevSignaling.TransactionRequest)
            JSON.deserialize('{"ctxInstanceId":null}', RevSignaling.TransactionRequest.class);
        RevSignaling.TransactionResponse blankResp = hook.execute(blankReq);

        // Bogus context id -> the live queryTags fails, swallowed, SUCCESS with a
        // "nothing to seed" or "warnings" message (never a failure status).
        RevSignaling.TransactionRequest bogusReq = (RevSignaling.TransactionRequest)
            JSON.deserialize('{"ctxInstanceId":"bogus-context-id"}', RevSignaling.TransactionRequest.class);
        RevSignaling.TransactionResponse bogusResp = hook.execute(bogusReq);
        Test.stopTest();

        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, blankResp.status,
            'Blank context must succeed quietly');
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, bogusResp.status,
            'Bogus context must never break the reprice (SUCCESS)');
    }

    // ============================================================
    // 16. resolveSourceAssetIds — guard branches (empty / blank scope)
    // ============================================================

    @IsTest
    static void testResolveSourceAssetIds_Guards() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();
        Test.startTest();
        System.assertEquals(0, hook.resolveSourceAssetIds(null, new Set<Id>{ OI_ID }).size(),
            'Null scope -> empty');
        System.assertEquals(0, hook.resolveSourceAssetIds('Order', new Set<Id>()).size(),
            'Empty ids -> empty');
        // Live query path with a non-existent OrderItem Id (no rows) — exercises SOQL, returns empty.
        System.assertEquals(0, hook.resolveSourceAssetIds('Order', new Set<Id>{ OI_ID }).size(),
            'No matching OrderItem -> empty');
        System.assertEquals(0, hook.resolveSourceAssetIds('Quote', new Set<Id>{ QLI_ID }).size(),
            'No matching QuoteLineItem -> empty');
        Test.stopTest();
    }

    // ============================================================
    // 17. resolveAssetNetByCurrency — live SOQL guard (empty set)
    // ============================================================

    @IsTest
    static void testResolveAssetNetByCurrency_EmptyAndQuery() {
        CancelLineNetSeedPrehook hook = new CancelLineNetSeedPrehook();
        Test.startTest();
        System.assertEquals(0, hook.resolveAssetNetByCurrency(null).size(), 'Null -> empty');
        System.assertEquals(0, hook.resolveAssetNetByCurrency(new Set<Id>{ null }).size(),
            'Only-null set -> empty (nulls stripped)');
        // Live query path with a synthetic asset Id (no rows expected) — exercises SOQL.
        System.assertEquals(0, hook.resolveAssetNetByCurrency(new Set<Id>{ ASSET_ID }).size(),
            'No AssetActionSource rows -> empty map');
        Test.stopTest();
    }
}
