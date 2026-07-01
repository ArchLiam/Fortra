/**
 * @description Unit tests for AmendNetSeedPosthook. Exercises the pure @TestVisible seams
 *              (amend gating, asset-net seed math, node-update shape using the QLI field-API
 *              attribute names, response parsing, coercion) and process() early-exit paths.
 */
@isTest
private class AmendNetSeedPosthookTest {

    // Flat SalesTransactionItem node: {dataPath:[ctx,root,line], <tags>}
    private static Map<String, Object> node(String lineId, Object action, Object qty,
                                            Object curNet, Object derived, Object assetNet) {
        Map<String, Object> n = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTXPATH', '0Q0WC000002VENJ0A4', lineId }
        };
        if (action != null)   { n.put('ItemSalesTransactionAction', action); }
        if (qty != null)      { n.put('LineItemQuantity', qty); }
        if (curNet != null)   { n.put('NetUnitPrice', curNet); }
        if (derived != null)  { n.put('DerivedPricingAttribute', derived); }
        if (assetNet != null) { n.put('AssetActionSourceNetUnitPrice', assetNet); }
        return n;
    }

    private static Map<String, Decimal> flatten(List<Object> attrs) {
        Map<String, Decimal> m = new Map<String, Decimal>();
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            m.put(String.valueOf(a.get('attributeName')), (Decimal) a.get('attributeValue'));
        }
        return m;
    }

    @isTest
    static void amendLine_netZero_isSeededFromAssetNet() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        // amend, qty 2, current net 0, non-derived, asset net 2021.25
        List<Object> nodes = new List<Object>{
            node('0QLamend', 'Amend', 2, 0, false, 2021.25)
        };
        List<Map<String, Object>> updates = h.buildSeedUpdates(nodes);

        System.assertEquals(1, updates.size(), 'one amend line should be seeded');
        Map<String, Object> u = updates[0];
        Map<String, Object> np = (Map<String, Object>) u.get('nodePath');
        List<Object> path = (List<Object>) np.get('dataPath');
        System.assertEquals(2, path.size(), 'context-path element stripped => [root, line]');
        System.assertEquals('0Q0WC000002VENJ0A4', String.valueOf(path[0]));
        System.assertEquals('0QLamend', String.valueOf(path[1]));

        Map<String, Decimal> w = flatten((List<Object>) u.get('attributes'));
        System.assertEquals(5, w.size(), 'five field-API attributes written');
        System.assertEquals(2021.25, w.get('NetUnitPrice'), 'net unit = asset net');
        System.assertEquals(4042.50, w.get('NetTotalPrice'), 'net total = asset net * qty');
        System.assertEquals(4042.50, w.get('TotalPrice'));
        System.assertEquals(4042.50, w.get('Subtotal'));
        System.assertEquals(4042.50, w.get('TotalLineAmount'));
        // Must use field API names, NOT the internal Item* tags.
        System.assert(!w.containsKey('ItemNetTotalPrice'), 'must not write internal Item* tags');
        System.assert(!w.containsKey('ItemTotalPrice'));
    }

    @isTest
    static void newSaleLine_isSkipped() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        // action New (not Amend) -> skipped even with asset net
        List<Object> nodes = new List<Object>{
            node('0QLnew', 'New', 1, 0, false, 999)
        };
        System.assertEquals(0, h.buildSeedUpdates(nodes).size(), 'non-amend action must be skipped');
    }

    @isTest
    static void renewalLine_isSkipped() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        List<Object> nodes = new List<Object>{
            node('0QLrenew', 'Renew', 1, 0, false, 999)
        };
        System.assertEquals(0, h.buildSeedUpdates(nodes).size(), 'renewal action must be skipped');
    }

    @isTest
    static void derivedAmend_isSkipped() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        // amend but derived=true -> skip (tier net left alone)
        List<Object> nodes = new List<Object>{
            node('0QLderiv', 'Amend', 1, 0, true, 500)
        };
        System.assertEquals(0, h.buildSeedUpdates(nodes).size(), 'derived-maintenance amend must be skipped');
    }

    @isTest
    static void amendWithExistingNet_isNotClobbered() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        // current net already > 0 -> leave it
        List<Object> nodes = new List<Object>{
            node('0QLhasnet', 'Amend', 1, 1500, false, 2021.25)
        };
        System.assertEquals(0, h.buildSeedUpdates(nodes).size(), 'a real net must never be overwritten');
    }

    @isTest
    static void amend_noAssetNet_isSkipped() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        List<Object> nodes = new List<Object>{
            node('0QLnoasset', 'Amend', 1, 0, false, null),
            node('0QLzeroasset', 'Amend', 1, 0, false, 0)
        };
        System.assertEquals(0, h.buildSeedUpdates(nodes).size(), 'no asset net (null or 0) => skip');
    }

    @isTest
    static void negativeQtyAmend_isSkipped() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        // cancellation (handled by CancelLineCreditPosthook) -> skip
        List<Object> nodes = new List<Object>{
            node('0QLcancel', 'Amend', -1, 0, false, 2021.25)
        };
        System.assertEquals(0, h.buildSeedUpdates(nodes).size(), 'negative-qty line must be skipped');
    }

    @isTest
    static void buildNodeUpdate_writesFieldApiNames() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        Map<String, Object> u = h.buildNodeUpdate(new List<Object>{ 'ctx', 'root', 'line' }, 2021.25, 4042.50);
        Map<String, Decimal> w = flatten((List<Object>) u.get('attributes'));
        System.assertEquals(5, w.size());
        for (String fld : new List<String>{ 'NetUnitPrice','NetTotalPrice','TotalPrice','Subtotal','TotalLineAmount' }) {
            System.assert(w.containsKey(fld), 'must write QLI field-API attribute ' + fld);
        }
    }

    @isTest
    static void parseLineNodes_handlesShapes() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        Map<String, Object> nested = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ node('l', 'Amend', 1, 0, false, 10) }
            }
        };
        System.assertEquals(1, h.parseLineNodes(nested).size(), 'nested queryResult shape');
        Map<String, Object> flat = new Map<String, Object>{
            'SalesTransactionItem' => node('l', 'Amend', 1, 0, false, 10)
        };
        System.assertEquals(1, h.parseLineNodes(flat).size(), 'flat single-object shape');
        System.assertEquals(null, h.parseLineNodes(null), 'null in => null out');
        System.assertEquals(null, h.parseLineNodes(new Map<String, Object>{ 'x' => 1 }), 'no item key => null');
    }

    @isTest
    static void coercionHelpers_areRobust() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        Map<String, Object> tags = new Map<String, Object>{
            'd' => 12.5, 'i' => 3, 's' => 'Amend', 'b' => true,
            'wrapped' => new Map<String, Object>{ 'tagValue' => 7 }
        };
        System.assertEquals(12.5, h.getDecimalFromTag(tags, 'd'));
        System.assertEquals(3, h.getDecimalFromTag(tags, 'i'));
        System.assertEquals(7, h.getDecimalFromTag(tags, 'wrapped'));
        System.assertEquals(null, h.getDecimalFromTag(tags, 'missing'));
        System.assertEquals('Amend', h.getStringFromTag(tags, 's'));
        System.assertEquals(true, h.getBooleanFromTag(tags, 'b'));
        System.assertEquals(null, h.getBooleanFromTag(tags, 'missing'));
    }

    @isTest
    static void process_earlyExits() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        RevSignaling.TransactionResponse r1 = h.process(null);
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, r1.status, 'blank ctx => SUCCESS');
        // execute() with null request also returns SUCCESS (no throw)
        RevSignaling.TransactionResponse r2 = h.execute(null);
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, r2.status, 'null request => SUCCESS');
    }

    @isTest
    static void buildSeedUpdates_nullAndNonMapSafe() {
        AmendNetSeedPosthook h = new AmendNetSeedPosthook();
        System.assertEquals(0, h.buildSeedUpdates(null).size());
        System.assertEquals(0, h.buildSeedUpdates(new List<Object>{ 'not-a-map', null }).size());
        // node with no dataPath => skip
        System.assertEquals(0, h.buildSeedUpdates(new List<Object>{
            new Map<String, Object>{ 'ItemSalesTransactionAction' => 'Amend' }
        }).size());
    }
}
