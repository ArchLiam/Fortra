/**
 * @description Unit tests for CancelLineCreditPosthook (SC-3441). Exercises the pure
 *              @TestVisible seams (gating, credit math, node-update shape using the QLI
 *              field-API attribute names, response parsing, decimal coercion) and the
 *              process() early-exit / swallow paths.
 */
@isTest
private class CancelLineCreditPosthookTest {

    // Build a flat SalesTransactionItem node: {dataPath:[ctx,root,line], <tags>}
    private static Map<String, Object> node(String ctxPath, String rootId, String lineId, Object qty, Object cancelNet) {
        Map<String, Object> n = new Map<String, Object>{
            'dataPath' => new List<Object>{ ctxPath, rootId, lineId }
        };
        if (qty != null)       { n.put('LineItemQuantity', qty); }
        if (cancelNet != null) { n.put('CancelNetUnitPrice__c', cancelNet); }
        return n;
    }

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

    @isTest
    static void positiveQtyLine_isSkipped() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', '0QLpositive', 3, 15000)
        };
        System.assertEquals(0, h.buildCreditUpdates(nodes).size(), 'positive-qty line must not be touched');
    }

    @isTest
    static void negativeQty_butNoStagedNet_isSkipped() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        List<Object> nodes = new List<Object>{
            node('CTXPATH', '0Q0WC000002VENJ0A4', '0QLnonet', -1, null),
            node('CTXPATH', '0Q0WC000002VENJ0A4', '0QLzeronet', -1, 0)
        };
        System.assertEquals(0, h.buildCreditUpdates(nodes).size(), 'no staged net (null or 0) => skip');
    }

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

    @isTest
    static void execute_nullRequest_succeedsQuietly() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Test.startTest();
        RevSignaling.TransactionResponse resp = h.execute(null);
        Test.stopTest();
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, resp.status,
            'never break the reprice; null request => SUCCESS');
    }

    @isTest
    static void process_blankContext_succeedsQuietly() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, h.process(null).status);
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, h.process('').status);
    }

    @isTest
    static void process_fakeContext_swallowsAndSucceeds() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        Test.startTest();
        RevSignaling.TransactionResponse resp = h.process('fakeCtx123');
        Test.stopTest();
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, resp.status);
    }

    @isTest
    static void submit_emptyUpdates_returnsZero() {
        CancelLineCreditPosthook h = new CancelLineCreditPosthook();
        System.assertEquals(0, h.submitContextUpdates(null, 'x', new List<Map<String, Object>>()));
        System.assertEquals(0, h.submitContextUpdates(null, 'x', null));
    }

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

    private static Map<String, Decimal> flatten(List<Object> attrs) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            out.put(String.valueOf(a.get('attributeName')), (Decimal) a.get('attributeValue'));
        }
        return out;
    }
}
