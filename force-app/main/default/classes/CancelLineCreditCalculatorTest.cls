/**
 * @description Unit tests for CancelLineCreditCalculator (SC-3441 Wave-2 decomposition).
 *              Exercises the pure seams that were extracted verbatim from
 *              CancelLineCreditPosthook — gating, credit math, the QLI field-API node-update
 *              shape, response parsing, decimal/string coercion (flat + nested {tagValue}
 *              wrapper), scope-by-line-Id-type, currency-aware asset-net pick + lossy fallback,
 *              the Generate-wins-and-sticks fold (incl. per-instance state), and the
 *              unseeded-cancel-line collector. No SOQL/DML — all pure.
 */
@isTest
private class CancelLineCreditCalculatorTest {

    private static final Id LINE_ID  = '0QLWC000003laPh4AI';   // a QuoteLineItem Id
    private static final Id ORDER_ITEM_ID = '802WC00000OugI7YAJ'; // an OrderItem Id
    private static final Id ASSET_ID = '02iWC000008eKMnYAM';    // a source Asset Id
    private static final Id ROOT_ID  = '0Q0WC000002VENJ0A4';    // a Quote (root) Id

    // Build a FLAT SalesTransactionItem node: {dataPath:[ctx,root,line], <tags>}
    private static Map<String, Object> node(String ctxPath, String rootId, String lineId, Object qty, Object cancelNet) {
        Map<String, Object> n = new Map<String, Object>{
            'dataPath' => new List<Object>{ ctxPath, rootId, lineId }
        };
        if (qty != null)       { n.put('LineItemQuantity', qty); }
        if (cancelNet != null) { n.put('CancelNetUnitPrice__c', cancelNet); }
        return n;
    }

    // Build a NESTED {tagValue:{field:{tagValue:val}}} node to exercise extractTagMap +
    // extractFieldValue wrapper branches.
    private static Map<String, Object> wrappedNode(String lineId, Object qty, Object cancelNet) {
        Map<String, Object> tags = new Map<String, Object>{
            'LineItemQuantity'      => new Map<String, Object>{ 'tagValue' => qty },
            'CancelNetUnitPrice__c' => new Map<String, Object>{ 'tagValue' => cancelNet }
        };
        return new Map<String, Object>{
            'dataPath' => new List<Object>{ 'ctx', ROOT_ID, lineId },
            'tagValue' => tags
        };
    }

    // In-memory AssetActionSource (with parent AssetAction) — calculated fields via JSON.
    private static AssetActionSource aas(Id assetId, String type, String cur, Decimal net) {
        return (AssetActionSource) JSON.deserialize(
            '{"NetUnitPrice":' + net + ',"CurrencyIsoCode":"' + cur + '",' +
            '"AssetAction":{"AssetId":"' + assetId + '","Type":"' + type + '"}}',
            AssetActionSource.class);
    }

    private static Map<String, Decimal> flatten(List<Object> attrs) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            out.put(String.valueOf(a.get('attributeName')), (Decimal) a.get('attributeValue'));
        }
        return out;
    }

    // ============================================================
    // buildCreditUpdates — gating + credit math + node shape
    // ============================================================

    @isTest
    static void negativeLineWithStagedNet_isCredited() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        List<Object> nodes = new List<Object>{ node('CTXPATH', ROOT_ID, LINE_ID, -1, 15000) };

        List<Map<String, Object>> updates = calc.buildCreditUpdates(nodes);

        System.assertEquals(1, updates.size(), 'one cancel line should be credited');
        Map<String, Object> np = (Map<String, Object>) updates[0].get('nodePath');
        List<Object> path = (List<Object>) np.get('dataPath');
        System.assertEquals(2, path.size(), 'context-path element stripped, leaving [root, line]');
        System.assertEquals(ROOT_ID, String.valueOf(path[0]));
        System.assertEquals(LINE_ID, String.valueOf(path[1]));

        Map<String, Decimal> w = flatten((List<Object>) updates[0].get('attributes'));
        System.assertEquals(5, w.size(), 'five field-API attributes written');
        System.assertEquals(15000, w.get('NetUnitPrice'), 'unit price stays positive');
        System.assertEquals(-15000, w.get('NetTotalPrice'), 'net total = net * qty');
        System.assertEquals(-15000, w.get('TotalPrice'), 'total price negative (business need)');
        System.assertEquals(-15000, w.get('Subtotal'));
        System.assertEquals(-15000, w.get('TotalLineAmount'));
        System.assert(!w.containsKey('ItemNetTotalPrice'), 'must not write internal Item* tags');
        System.assert(!w.containsKey('ItemTotalPrice'));
        System.assert(!w.containsKey('ItemSubtotal'));
    }

    @isTest
    static void positiveQtyLine_isSkipped() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        List<Object> nodes = new List<Object>{ node('CTXPATH', ROOT_ID, LINE_ID, 3, 15000) };
        System.assertEquals(0, calc.buildCreditUpdates(nodes).size(), 'positive-qty line must not be touched');
    }

    @isTest
    static void negativeQty_butNoStagedNet_isSkipped() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', ROOT_ID, LINE_ID, -1, null),
            node('CTXPATH', ROOT_ID, '0QLWC000002q2Sn4AI', -1, 0)
        };
        System.assertEquals(0, calc.buildCreditUpdates(nodes).size(), 'no staged net (null or 0) => skip');
    }

    @isTest
    static void nullLineNodes_returnsEmpty() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        System.assertEquals(0, calc.buildCreditUpdates(null).size(), 'null nodes => empty, no NPE');
        System.assertEquals(0, calc.buildCreditUpdates(null, null).size(), 'null nodes + null resolved => empty');
    }

    @isTest
    static void fractionalCredit_roundsHalfUp() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        // net 6695.305 * -1 => -6695.305 -> HALF_UP scale(2) => -6695.31 (guards the rounding seam)
        List<Object> nodes = new List<Object>{ node('c', ROOT_ID, LINE_ID, -1, 6695.305) };
        Map<String, Decimal> w = flatten((List<Object>) calc.buildCreditUpdates(nodes)[0].get('attributes'));
        System.assertEquals(-6695.31, w.get('TotalPrice'), 'credit rounds HALF_UP to 2dp');
    }

    @isTest
    static void wrappedTagShape_isCredited() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        // nested {tagValue:{field:{tagValue:val}}} shape exercises extractTagMap + extractFieldValue
        List<Object> nodes = new List<Object>{ wrappedNode(LINE_ID, -2, 100) };
        Map<String, Decimal> w = flatten((List<Object>) calc.buildCreditUpdates(nodes)[0].get('attributes'));
        System.assertEquals(100, w.get('NetUnitPrice'));
        System.assertEquals(-200, w.get('TotalPrice'), 'net * qty from nested tagValue wrapper');
    }

    // ============================================================
    // buildCreditUpdates(2-arg) — resolved asset net path
    // ============================================================

    @isTest
    static void negativeLine_noStagedNet_usesResolvedAssetNet() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        List<Object> nodes = new List<Object>{ node('CTXPATH', ROOT_ID, LINE_ID, -1, null) };
        Map<Id, Decimal> resolved = new Map<Id, Decimal>{ LINE_ID => 6695.30 };

        List<Map<String, Object>> updates = calc.buildCreditUpdates(nodes, resolved);

        System.assertEquals(1, updates.size(), 'unseeded cancel line credited from resolved asset net');
        Map<String, Decimal> w = flatten((List<Object>) updates[0].get('attributes'));
        System.assertEquals(6695.30, w.get('NetUnitPrice'), 'per-unit net stays positive');
        System.assertEquals(-6695.30, w.get('TotalPrice'), 'total = net * qty (negative)');
        System.assertEquals(-6695.30, w.get('NetTotalPrice'));
        System.assertEquals(-6695.30, w.get('Subtotal'));
        System.assertEquals(-6695.30, w.get('TotalLineAmount'));
    }

    @isTest
    static void stagedNet_winsOverResolved() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        List<Object> nodes = new List<Object>{ node('CTXPATH', ROOT_ID, LINE_ID, -1, 15000) };
        Map<Id, Decimal> resolved = new Map<Id, Decimal>{ LINE_ID => 6695.30 };

        Map<String, Decimal> w = flatten((List<Object>) calc.buildCreditUpdates(nodes, resolved)[0].get('attributes'));
        System.assertEquals(15000, w.get('NetUnitPrice'), 'staged context value wins over resolved');
        System.assertEquals(-15000, w.get('TotalPrice'));
    }

    @isTest
    static void noStagedNet_noResolved_isSkipped() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        List<Object> nodes = new List<Object>{ node('CTXPATH', ROOT_ID, LINE_ID, -1, null) };
        System.assertEquals(0, calc.buildCreditUpdates(nodes, new Map<Id, Decimal>()).size(),
            'no staged and nothing resolved => skip (no zero/garbage credit)');
    }

    // ============================================================
    // buildNodeUpdate — pure shape
    // ============================================================

    @isTest
    static void buildNodeUpdate_writesFieldApiNames_andStripsContextPath() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        Map<String, Object> u = calc.buildNodeUpdate(new List<Object>{ 'ctx', 'root', 'line' }, 15000, -15000);
        Map<String, Object> np = (Map<String, Object>) u.get('nodePath');
        List<Object> path = (List<Object>) np.get('dataPath');
        System.assertEquals(2, path.size(), 'first (context-path) element removed');
        System.assertEquals('root', String.valueOf(path[0]));
        System.assertEquals('line', String.valueOf(path[1]));

        Map<String, Decimal> w = flatten((List<Object>) u.get('attributes'));
        System.assertEquals(5, w.size(), 'five attributes');
        for (String fld : new List<String>{ 'NetUnitPrice','NetTotalPrice','TotalPrice','Subtotal','TotalLineAmount' }) {
            System.assert(w.containsKey(fld), 'must write QLI field-API attribute ' + fld);
        }
    }

    // ============================================================
    // parseLineNodes — response shapes
    // ============================================================

    @isTest
    static void parseLineNodes_handlesShapes() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        Map<String, Object> nested = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ node('c', 'r', 'l', -1, 10) }
            }
        };
        System.assertEquals(1, calc.parseLineNodes(nested).size(), 'nested queryResult list');
        Map<String, Object> flat = new Map<String, Object>{
            'SalesTransactionItem' => new List<Object>{ node('c', 'r', 'l', -1, 10) }
        };
        System.assertEquals(1, calc.parseLineNodes(flat).size(), 'flat list');
        Map<String, Object> single = new Map<String, Object>{
            'SalesTransactionItem' => node('c', 'r', 'l', -1, 10)
        };
        System.assertEquals(1, calc.parseLineNodes(single).size(), 'single object wrapped');
        System.assertEquals(null, calc.parseLineNodes(null), 'null response => null');
        System.assertEquals(null, calc.parseLineNodes(new Map<String, Object>()), 'no key => null');
        Map<String, Object> qrNotMap = new Map<String, Object>{ 'queryResult' => 'nope' };
        System.assertEquals(null, calc.parseLineNodes(qrNotMap), 'queryResult not a map => null');
    }

    // ============================================================
    // coercion helpers
    // ============================================================

    @isTest
    static void getDecimalFromTag_coercesTypes() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        Map<String, Object> m = new Map<String, Object>{
            'a' => 15000, 'b' => -1.0, 'c' => '2500.50', 'd' => 'x', 'e' => null,
            'f' => new Map<String, Object>{ 'tagValue' => 42 }
        };
        System.assertEquals(15000, calc.getDecimalFromTag(m, 'a'));
        System.assertEquals(-1, calc.getDecimalFromTag(m, 'b'));
        System.assertEquals(2500.50, calc.getDecimalFromTag(m, 'c'));
        System.assertEquals(null, calc.getDecimalFromTag(m, 'd'), 'unparseable => null');
        System.assertEquals(null, calc.getDecimalFromTag(m, 'e'));
        System.assertEquals(null, calc.getDecimalFromTag(m, 'missing'));
        System.assertEquals(42, calc.getDecimalFromTag(m, 'f'), 'nested {tagValue} wrapper unwrapped');
    }

    @isTest
    static void getStringFromTag_coerces() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        Map<String, Object> m = new Map<String, Object>{ 'a' => 'USD', 'b' => 123, 'c' => null };
        System.assertEquals('USD', calc.getStringFromTag(m, 'a'));
        System.assertEquals('123', calc.getStringFromTag(m, 'b'));
        System.assertEquals(null, calc.getStringFromTag(m, 'c'));
        System.assertEquals(null, calc.getStringFromTag(m, 'missing'));
    }

    @isTest
    static void lineIdFromDataPath_lastElement() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        System.assertEquals(LINE_ID, calc.lineIdFromDataPath(new List<Object>{ 'ctx', '0Q0root', LINE_ID }));
        System.assertEquals(null, calc.lineIdFromDataPath(new List<Object>{ 'ctx', 'root', 'notAnId' }));
        System.assertEquals(null, calc.lineIdFromDataPath(new List<Object>()));
        System.assertEquals(null, calc.lineIdFromDataPath(null));
    }

    // ============================================================
    // resolveScope — Quote vs Order from line Id type
    // ============================================================

    @isTest
    static void resolveScope_byLineIdType() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        System.assertEquals('Quote', calc.resolveScope(new List<Object>{ node('c', 'root', LINE_ID, -1, null) }));
        System.assertEquals('Order', calc.resolveScope(new List<Object>{ node('c', 'root', ORDER_ITEM_ID, -1, null) }));
        System.assertEquals(null, calc.resolveScope(new List<Object>{ node('c', 'root', 'notAnId', -1, null) }));
        System.assertEquals(null, calc.resolveScope(null));
    }

    // ============================================================
    // resolveSeedNet — currency-aware pick + lossy fallback
    // ============================================================

    @isTest
    static void resolveSeedNet_currencyAwareAndFallback() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        Map<Id, Map<String, Decimal>> byCur = new Map<Id, Map<String, Decimal>>{
            ASSET_ID => new Map<String, Decimal>{ 'USD' => 6695.30 }
        };
        System.assertEquals(6695.30, calc.resolveSeedNet(ASSET_ID, 'USD', 0, byCur), 'currency match');
        System.assertEquals(6695.30, calc.resolveSeedNet(ASSET_ID, null, 0, byCur), 'no tag + single-currency asset');
        System.assertEquals(999, calc.resolveSeedNet(ASSET_ID, 'EUR', 999, byCur), 'mismatch -> lossy ListPrice');
        System.assertEquals(null, calc.resolveSeedNet(ASSET_ID, 'EUR', 0, byCur), 'mismatch + no list -> null');
        System.assertEquals(500, calc.resolveSeedNet(null, 'USD', 500, byCur), 'no asset -> ListPrice');
        System.assertEquals(null, calc.resolveSeedNet(null, 'USD', 0, byCur), 'nothing resolvable -> null');
        System.assertEquals(null, calc.resolveSeedNet(ASSET_ID, null, 0,
            new Map<Id, Map<String, Decimal>>{ ASSET_ID => new Map<String, Decimal>{ 'USD' => 1, 'EUR' => 2 } }),
            'no tag + multi-currency asset -> no ambiguous pick, null');
    }

    // ============================================================
    // applyAssetNetSource — Generate-wins-and-sticks + per-instance state
    // ============================================================

    @isTest
    static void applyAssetNetSource_generateWinsAndSticks() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        Map<Id, Map<String, Decimal>> m = new Map<Id, Map<String, Decimal>>();
        calc.applyAssetNetSource(m, aas(ASSET_ID, 'Change', 'USD', 1000));      // older non-Generate first
        System.assertEquals(1000, m.get(ASSET_ID).get('USD'));
        calc.applyAssetNetSource(m, aas(ASSET_ID, 'Generate', 'USD', 6695.30)); // Generate wins
        System.assertEquals(6695.30, m.get(ASSET_ID).get('USD'), 'Generate wins');
        calc.applyAssetNetSource(m, aas(ASSET_ID, 'Change', 'USD', 2000));      // later non-Generate can't replace
        System.assertEquals(6695.30, m.get(ASSET_ID).get('USD'), 'Generate stays locked (per-instance state)');
        calc.applyAssetNetSource(m, aas(ASSET_ID, 'Generate', 'USD', 0));       // zero net never folds
        System.assertEquals(6695.30, m.get(ASSET_ID).get('USD'));
        // currency isolation: a EUR row does not touch the USD value
        calc.applyAssetNetSource(m, aas(ASSET_ID, 'Generate', 'EUR', 5000));
        System.assertEquals(6695.30, m.get(ASSET_ID).get('USD'));
        System.assertEquals(5000, m.get(ASSET_ID).get('EUR'));
    }

    @isTest
    static void applyAssetNetSource_nullAndBlankGuards() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        Map<Id, Map<String, Decimal>> m = new Map<Id, Map<String, Decimal>>();
        calc.applyAssetNetSource(m, null);                                  // null source
        calc.applyAssetNetSource(m, aas(ASSET_ID, 'Generate', 'USD', -5));  // non-positive net
        calc.applyAssetNetSource(m, aas(ASSET_ID, 'Generate', '', 100));    // blank currency
        System.assertEquals(0, m.size(), 'guards drop null/non-positive/blank-currency rows');
    }

    // ============================================================
    // collectUnseededCancelLines — only negative + unseeded, PendingLine fields
    // ============================================================

    @isTest
    static void collectUnseeded_onlyNegativeUnseeded() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        List<Object> nodes = new List<Object>{
            node('c', '0Q0x', LINE_ID, -1, null),                       // unseeded cancel -> pending
            node('c', '0Q0x', '0QLWC000002q2Sn4AI', -1, 15000),         // seeded -> excluded
            node('c', '0Q0x', '0QLWC000003jbhd4AA', 2, null)            // positive -> excluded
        };
        List<CancelLineCreditCalculator.PendingLine> pend = calc.collectUnseededCancelLines(nodes);
        System.assertEquals(1, pend.size(), 'only the negative unseeded line is pending');
        System.assertEquals(LINE_ID, pend[0].lineId);
        System.assertEquals(0, calc.collectUnseededCancelLines(null).size(), 'null nodes => empty');
    }

    @isTest
    static void collectUnseeded_capturesCurrencyAndListPrice() {
        CancelLineCreditCalculator calc = new CancelLineCreditCalculator();
        Map<String, Object> n = node('c', '0Q0x', LINE_ID, -1, null);
        n.put('STICurrencyIsoCode', 'EUR');
        n.put('ListPrice', 1234.56);
        List<CancelLineCreditCalculator.PendingLine> pend =
            calc.collectUnseededCancelLines(new List<Object>{ n });
        System.assertEquals(1, pend.size());
        System.assertEquals('EUR', pend[0].currencyIso, 'currency tag captured for the currency-aware pick');
        System.assertEquals(1234.56, pend[0].listPrice, 'ListPrice tag captured for the lossy fallback');
    }
}
