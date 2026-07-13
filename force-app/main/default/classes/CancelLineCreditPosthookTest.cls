/**
 * @description Unit tests for CancelLineCreditPosthook. Exercises the pure
 *              @TestVisible seams (gating, credit math, node-update shape using the QLI
 *              field-API attribute names, response parsing, decimal coercion) and the
 *              process() early-exit / swallow paths.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class CancelLineCreditPosthookTest {

    /**
     * @description Builds a flat SalesTransactionItem node of shape {dataPath:[ctx,root,line], <tags>}
     *              for use as pure-seam test input.
     * @param ctxPath the context-path (first) dataPath element
     * @param rootId the root (order/quote) Id dataPath element
     * @param lineId the line Id (last) dataPath element
     * @param qty the LineItemQuantity tag value, omitted when null
     * @param cancelNet the CancelNetUnitPrice__c tag value, omitted when null
     * @return the assembled node map
     */
    private static Map<String, Object> node(String ctxPath, String rootId, String lineId, Object qty, Object cancelNet) {
        Map<String, Object> n = new Map<String, Object>{
            'dataPath' => new List<Object>{ ctxPath, rootId, lineId }
        };
        if (qty != null)       { n.put('LineItemQuantity', qty); }
        if (cancelNet != null) { n.put('CancelNetUnitPrice__c', cancelNet); }
        return n;
    }

    /**
     * @description Verifies a negative-quantity line with a staged CancelNetUnitPrice__c is credited:
     *              the context-path element is stripped from the path and the five QLI field-API
     *              attributes are written with a positive unit price and negative totals.
     */
    @isTest
    static void negativeLineWithStagedNet_isCredited() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', '0QLWC000002q2Sn4AI', -1, 15000)
        };

        List<Map<String, Object>> updates = h.buildCreditUpdates(nodes);

        System.assertEquals(1, updates.size(), 'one cancel line should be credited');
        Map<String, Object> u = updates[0];
        // nodePath = dataPath with the first (context-path) element removed => [root, line]
        Map<String, Object> np = (Map<String, Object>) u.get('nodePath');
        List<Object> path = (List<Object>) np.get('dataPath');
        System.assertEquals(2, path.size(), 'context-path element should be stripped, leaving [root, line]');
        System.assertEquals('0Q0WC000002VENJ0A4', String.valueOf(path[0]));
        System.assertEquals('0QLWC000002q2Sn4AI', String.valueOf(path[1]));

        Map<String, Decimal> w = flatten((List<Object>) u.get('attributes'));
        System.assertEquals(5, w.size(), 'five field-API attributes written');
        System.assertEquals(15000, w.get('NetUnitPrice'), 'unit price stays positive');
        System.assertEquals(-15000, w.get('NetTotalPrice'), 'net total = net * qty');
        System.assertEquals(-15000, w.get('TotalPrice'), 'total price negative (business need)');
        System.assertEquals(-15000, w.get('Subtotal'));
        System.assertEquals(-15000, w.get('TotalLineAmount'));
        // Must use field API names, NOT the internal Item* pricing tags.
        System.assert(!w.containsKey('ItemNetTotalPrice'), 'must not write internal Item* tags');
        System.assert(!w.containsKey('ItemTotalPrice'));
        System.assert(!w.containsKey('ItemSubtotal'));
    }

    /**
     * @description Verifies a positive-quantity line is never credited (produces no updates).
     */
    @isTest
    static void positiveQtyLine_isSkipped() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', '0QLpositive', 3, 15000)
        };
        System.assertEquals(0, h.buildCreditUpdates(nodes).size(), 'positive-qty line must not be touched');
    }

    /**
     * @description Verifies a negative-quantity line with no staged net (null or 0) is skipped.
     */
    @isTest
    static void negativeQty_butNoStagedNet_isSkipped() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', '0QLnonet', -1, null),
            node('CTXPATH', '0Q0WC000002VENJ0A4', '0QLzeronet', -1, 0)
        };
        System.assertEquals(0, h.buildCreditUpdates(nodes).size(), 'no staged net (null or 0) => skip');
    }

    /**
     * @description Verifies buildNodeUpdate emits the five QLI field-API attribute names.
     */
    @isTest
    static void buildNodeUpdate_writesFieldApiNames() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Map<String, Object> u = h.buildNodeUpdate(
            new List<Object>{ 'ctx', 'root', 'line' }, 15000, -15000
        );
        Map<String, Decimal> w = flatten((List<Object>) u.get('attributes'));
        System.assertEquals(5, w.size(), 'five attributes');
        for (String fld : new List<String>{ 'NetUnitPrice','NetTotalPrice','TotalPrice','Subtotal','TotalLineAmount' }) {
            System.assert(w.containsKey(fld), 'must write QLI field-API attribute ' + fld);
        }
    }

    /**
     * @description Verifies parseLineNodes handles nested, flat, and single-object response shapes
     *              and returns null for null or empty input.
     */
    @isTest
    static void parseLineNodes_handlesShapes() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Map<String, Object> nested = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ node('c', 'r', 'l', -1, 10) }
            }
        };
        System.assertEquals(1, h.parseLineNodes(nested).size());
        Map<String, Object> flat = new Map<String, Object>{
            'SalesTransactionItem' => new List<Object>{ node('c', 'r', 'l', -1, 10) }
        };
        System.assertEquals(1, h.parseLineNodes(flat).size());
        Map<String, Object> single = new Map<String, Object>{
            'SalesTransactionItem' => node('c', 'r', 'l', -1, 10)
        };
        System.assertEquals(1, h.parseLineNodes(single).size());
        System.assertEquals(null, h.parseLineNodes(null));
        System.assertEquals(null, h.parseLineNodes(new Map<String, Object>()));
    }

    /**
     * @description Verifies getDecimalFromTag coerces integer, decimal, and numeric-string tags and
     *              returns null for unparseable, null, or missing tags.
     */
    @isTest
    static void getDecimalFromTag_coercesTypes() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Map<String, Object> m = new Map<String, Object>{
            'a' => 15000, 'b' => -1.0, 'c' => '2500.50', 'd' => 'x', 'e' => null
        };
        System.assertEquals(15000, h.getDecimalFromTag(m, 'a'));
        System.assertEquals(-1, h.getDecimalFromTag(m, 'b'));
        System.assertEquals(2500.50, h.getDecimalFromTag(m, 'c'));
        System.assertEquals(null, h.getDecimalFromTag(m, 'd'), 'unparseable => null');
        System.assertEquals(null, h.getDecimalFromTag(m, 'e'));
        System.assertEquals(null, h.getDecimalFromTag(m, 'missing'));
    }

    /**
     * @description Verifies execute returns SUCCESS for a null request so the reprice never breaks.
     */
    @isTest
    static void execute_nullRequest_succeedsQuietly() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Test.startTest();
        RevSignaling.TransactionResponse resp = h.execute(null);
        Test.stopTest();
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, resp.status,
            'never break the reprice; null request => SUCCESS');
    }

    /**
     * @description Verifies process returns SUCCESS for null and blank context ids.
     */
    @isTest
    static void process_blankContext_succeedsQuietly() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, h.process(null).status);
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, h.process('').status);
    }

    /**
     * @description Verifies process swallows errors from an invalid context id and still returns SUCCESS.
     */
    @isTest
    static void process_fakeContext_swallowsAndSucceeds() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Test.startTest();
        RevSignaling.TransactionResponse resp = h.process('fakeCtx123');
        Test.stopTest();
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, resp.status);
    }

    /**
     * @description Verifies submitContextUpdates returns zero when the updates list is empty or null.
     */
    @isTest
    static void submit_emptyUpdates_returnsZero() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        System.assertEquals(0, h.submitContextUpdates(null, 'x', new List<Map<String, Object>>()));
        System.assertEquals(0, h.submitContextUpdates(null, 'x', null));
    }

    /**
     * @description Verifies submitContextUpdates does not let an exception from a fake context escape unhandled.
     */
    @isTest
    static void submit_withFakeContext_doesNotEscapeUnhandled() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Map<String, Object>> updates = new List<Map<String, Object>>{
            h.buildNodeUpdate(new List<Object>{ 'ctx', 'root', 'line' }, 100, -100)
        };
        try {
            h.submitContextUpdates(new Context.IndustriesContext(), 'fakeCtx123', updates);
        } catch (Exception e) {
            // expected for a fake context
        }
    }

    // ============================================================
    // v2.1 — asset-NET self-resolution (no seed prehook / no staging)
    // ============================================================

    private static final Id LINE_ID  = '0QLWC000003laPh4AI';   // Nir's cancel line shape
    private static final Id ASSET_ID  = '02iWC000008eKMnYAM';   // its source asset

    /**
     * @description Verifies an unseeded negative line is credited from the resolved asset net when
     *              no staged net is present.
     */
    @isTest
    static void negativeLine_noStagedNet_usesResolvedAssetNet() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', LINE_ID, -1, null)   // unseeded cancel line
        };
        Map<Id, Decimal> resolved = new Map<Id, Decimal>{ LINE_ID => 6695.30 };

        List<Map<String, Object>> updates = h.buildCreditUpdates(nodes, resolved);

        System.assertEquals(1, updates.size(), 'unseeded cancel line credited from resolved asset net');
        Map<String, Decimal> w = flatten((List<Object>) updates[0].get('attributes'));
        System.assertEquals(6695.30, w.get('NetUnitPrice'), 'per-unit net stays positive');
        System.assertEquals(-6695.30, w.get('TotalPrice'), 'total = net * qty (negative)');
        System.assertEquals(-6695.30, w.get('NetTotalPrice'));
        System.assertEquals(-6695.30, w.get('Subtotal'));
        System.assertEquals(-6695.30, w.get('TotalLineAmount'));
    }

    /**
     * @description Verifies a staged context net wins over a resolved asset net.
     */
    @isTest
    static void stagedNet_winsOverResolved() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', LINE_ID, -1, 15000)   // already seeded
        };
        Map<Id, Decimal> resolved = new Map<Id, Decimal>{ LINE_ID => 6695.30 };

        Map<String, Decimal> w = flatten((List<Object>) h.buildCreditUpdates(nodes, resolved)[0].get('attributes'));
        System.assertEquals(15000, w.get('NetUnitPrice'), 'staged context value wins over resolved');
        System.assertEquals(-15000, w.get('TotalPrice'));
    }

    /**
     * @description Verifies a line with neither staged nor resolved net is skipped (no zero/garbage credit).
     */
    @isTest
    static void noStagedNet_noResolved_isSkipped() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', LINE_ID, -1, null)
        };
        System.assertEquals(0, h.buildCreditUpdates(nodes, new Map<Id, Decimal>()).size(),
            'no staged and nothing resolved => skip (no zero/garbage credit)');
    }

    /**
     * @description Verifies collectUnseededCancelLines returns only the negative, unseeded lines.
     */
    @isTest
    static void collectUnseeded_onlyNegativeUnseeded() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('c', '0Q0x', LINE_ID, -1, null),                       // unseeded cancel -> pending
            node('c', '0Q0x', '0QLWC000002q2Sn4AI', -1, 15000),         // seeded -> excluded
            node('c', '0Q0x', '0QLWC000003jbhd4AA', 2, null)            // positive -> excluded
        };
        List<CancelLineCreditPosthook.PendingLine> pend = h.collectUnseededCancelLines(nodes);
        System.assertEquals(1, pend.size(), 'only the negative unseeded line is pending');
        System.assertEquals(LINE_ID, pend[0].lineId);
    }

    /**
     * @description Verifies resolveScope derives Quote/Order/null from the line Id (last dataPath element).
     */
    @isTest
    static void resolveScope_byLineIdType() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        // scope comes from the LINE Id (last dataPath element), not the root element.
        System.assertEquals('Quote', h.resolveScope(new List<Object>{ node('c', 'root', LINE_ID, -1, null) }));
        System.assertEquals('Order', h.resolveScope(new List<Object>{ node('c', 'root', '802WC00000OugI7YAJ', -1, null) }));
        System.assertEquals(null, h.resolveScope(new List<Object>{ node('c', 'root', 'notAnId', -1, null) }));
        System.assertEquals(null, h.resolveScope(null));
    }

    /**
     * @description Verifies lineIdFromDataPath returns the last element when it is a valid Id, else null.
     */
    @isTest
    static void lineIdFromDataPath_lastElement() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        System.assertEquals(LINE_ID,
            h.lineIdFromDataPath(new List<Object>{ 'ctx', '0Q0root', LINE_ID }));
        System.assertEquals(null, h.lineIdFromDataPath(new List<Object>{ 'ctx', 'root', 'notAnId' }));
        System.assertEquals(null, h.lineIdFromDataPath(new List<Object>()));
        System.assertEquals(null, h.lineIdFromDataPath(null));
    }

    /**
     * @description Verifies resolveSeedNet matches by currency, falls back to a single-currency asset
     *              or lossy ListPrice, and returns null when nothing is resolvable.
     */
    @isTest
    static void resolveSeedNet_currencyAwareAndFallback() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Map<Id, Map<String, Decimal>> byCur = new Map<Id, Map<String, Decimal>>{
            ASSET_ID => new Map<String, Decimal>{ 'USD' => 6695.30 }
        };
        System.assertEquals(6695.30, h.resolveSeedNet(ASSET_ID, 'USD', 0, byCur), 'currency match');
        System.assertEquals(6695.30, h.resolveSeedNet(ASSET_ID, null, 0, byCur), 'no tag + single-currency asset');
        System.assertEquals(999, h.resolveSeedNet(ASSET_ID, 'EUR', 999, byCur), 'mismatch -> lossy ListPrice');
        System.assertEquals(null, h.resolveSeedNet(ASSET_ID, 'EUR', 0, byCur), 'mismatch + no list -> null');
        System.assertEquals(500, h.resolveSeedNet(null, 'USD', 500, byCur), 'no asset -> ListPrice');
        System.assertEquals(null, h.resolveSeedNet(null, 'USD', 0, byCur), 'nothing resolvable -> null');
    }

    /**
     * @description Verifies applyAssetNetSource lets a Generate source win and stay locked, ignores
     *              zero nets, and keeps currencies isolated.
     */
    @isTest
    static void applyAssetNetSource_generateWinsAndSticks() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Map<Id, Map<String, Decimal>> m = new Map<Id, Map<String, Decimal>>();
        h.applyAssetNetSource(m, aas(ASSET_ID, 'Change', 'USD', 1000));      // older non-Generate first
        System.assertEquals(1000, m.get(ASSET_ID).get('USD'));
        h.applyAssetNetSource(m, aas(ASSET_ID, 'Generate', 'USD', 6695.30)); // Generate wins
        System.assertEquals(6695.30, m.get(ASSET_ID).get('USD'), 'Generate wins');
        h.applyAssetNetSource(m, aas(ASSET_ID, 'Change', 'USD', 2000));      // later non-Generate can't replace
        System.assertEquals(6695.30, m.get(ASSET_ID).get('USD'), 'Generate stays locked');
        h.applyAssetNetSource(m, aas(ASSET_ID, 'Generate', 'USD', 0));       // zero net never folds
        System.assertEquals(6695.30, m.get(ASSET_ID).get('USD'));
        // currency isolation: a EUR row does not touch the USD value
        h.applyAssetNetSource(m, aas(ASSET_ID, 'Generate', 'EUR', 5000));
        System.assertEquals(6695.30, m.get(ASSET_ID).get('USD'));
        System.assertEquals(5000, m.get(ASSET_ID).get('EUR'));
    }

    /**
     * @description Verifies getStringFromTag coerces string and numeric tags and returns null for
     *              null or missing tags.
     */
    @isTest
    static void getStringFromTag_coerces() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Map<String, Object> m = new Map<String, Object>{ 'a' => 'USD', 'b' => 123, 'c' => null };
        System.assertEquals('USD', h.getStringFromTag(m, 'a'));
        System.assertEquals('123', h.getStringFromTag(m, 'b'));
        System.assertEquals(null, h.getStringFromTag(m, 'c'));
        System.assertEquals(null, h.getStringFromTag(m, 'missing'));
    }

    /**
     * @description Verifies resolveSourceAssetIds runs its SOQL and returns no rows for fake ids or empty/null input.
     */
    @isTest
    static void resolveSourceAssetIds_runsSoql_noRowsForFakeIds() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        System.assertEquals(0, h.resolveSourceAssetIds('Quote', new Set<Id>{ LINE_ID }).size());
        System.assertEquals(0, h.resolveSourceAssetIds('Order', new Set<Id>{ '802WC00000OugI7YAJ' }).size());
        System.assertEquals(0, h.resolveSourceAssetIds('Quote', new Set<Id>()).size());
        System.assertEquals(0, h.resolveSourceAssetIds(null, null).size());
    }

    /**
     * @description Verifies resolveAssetNetByCurrency runs its SOQL and returns no rows for fake ids or empty/null input.
     */
    @isTest
    static void resolveAssetNetByCurrency_runsSoql_noRowsForFakeIds() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        System.assertEquals(0, h.resolveAssetNetByCurrency(new Set<Id>{ ASSET_ID }).size());
        System.assertEquals(0, h.resolveAssetNetByCurrency(new Set<Id>()).size());
        System.assertEquals(0, h.resolveAssetNetByCurrency(null).size());
    }

    /**
     * @description Verifies resolveAssetNetsForUnseededLines returns empty when no source asset exists
     *              and never queries for an all-seeded set.
     */
    @isTest
    static void resolveAssetNets_endToEnd_noMatchingData_returnsEmpty() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', LINE_ID, -1, null)   // valid shape, non-existent record
        };
        Test.startTest();
        Map<Id, Decimal> r = h.resolveAssetNetsForUnseededLines(nodes);
        Test.stopTest();
        System.assertEquals(0, r.size(), 'no source asset for a non-existent line => nothing resolved');
        // an all-seeded set never queries
        System.assertEquals(0, h.resolveAssetNetsForUnseededLines(new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', LINE_ID, -1, 15000)
        }).size());
    }

    /**
     * @description Builds an in-memory AssetActionSource (with its AssetAction parent) for pure-seam tests.
     * @param assetId the parent AssetAction's AssetId
     * @param type the parent AssetAction's Type (e.g. Generate/Change)
     * @param cur the source's CurrencyIsoCode
     * @param net the source's NetUnitPrice
     * @return the deserialized AssetActionSource
     */
    private static AssetActionSource aas(Id assetId, String type, String cur, Decimal net) {
        return (AssetActionSource) JSON.deserialize(
            '{"NetUnitPrice":' + net + ',"CurrencyIsoCode":"' + cur + '",' +
            '"AssetAction":{"AssetId":"' + assetId + '","Type":"' + type + '"}}',
            AssetActionSource.class);
    }

    /**
     * @description Flattens an attribute list of {attributeName, attributeValue} maps into a
     *              name-to-decimal map for assertions.
     * @param attrs the list of attribute maps
     * @return a map of attribute name to decimal value
     */
    private static Map<String, Decimal> flatten(List<Object> attrs) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            out.put(String.valueOf(a.get('attributeName')), (Decimal) a.get('attributeValue'));
        }
        return out;
    }
}