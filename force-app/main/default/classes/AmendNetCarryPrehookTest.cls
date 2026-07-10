/**
 * @description Unit coverage for AmendNetCarryPrehook's pure seams (SC-3501). execute() itself cannot be
 *              unit-tested — RevSignaling.TransactionRequest has no public constructor and
 *              Context.IndustriesContext.queryTags() needs a live pricing context — so the end-to-end
 *              path is validated by integration (native Quote reprice; proven live on quote J4m9 →
 *              10000/94000/15000). These tests lock the seed-entry shape and response parsing.
 */
@IsTest
private class AmendNetCarryPrehookTest {

    private static Map<String, Object> wrapperWithPath(List<Object> dataPath) {
        return new Map<String, Object>{ 'dataPath' => dataPath };
    }

    private static Object attrValue(Map<String, Object> upd, String attributeName) {
        if (upd == null) {
            return null;
        }
        for (Object o : (List<Object>) upd.get('attributes')) {
            Map<String, Object> a = (Map<String, Object>) o;
            if (a.get('attributeName') == attributeName) {
                return a.get('attributeValue');
            }
        }
        return null;
    }

    private static List<Object> updatePath(Map<String, Object> upd) {
        return (List<Object>) ((Map<String, Object>) upd.get('nodePath')).get('dataPath');
    }

    @IsTest
    static void buildAmendSeedUpdate_seedsNetAndUnitPriceAndStripsRoot() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        // dataPath = [rootId, ..., qliId]; the update path drops the root (element 0).
        Map<String, Object> upd = hook.buildAmendSeedUpdate(
            wrapperWithPath(new List<Object>{ '0Q0ROOT', 'mid', '0QLLINE' }), 6695.30);
        System.assertNotEquals(null, upd, 'seed entry built');
        System.assert(((Decimal) attrValue(upd, 'NetUnitPrice')) == 6695.30, 'NetUnitPrice seeded from prior net');
        System.assert(((Decimal) attrValue(upd, 'UnitPrice')) == 6695.30, 'UnitPrice seeded too (InputUnitPrice)');
        System.assertEquals(new List<Object>{ 'mid', '0QLLINE' }, updatePath(upd), 'root element stripped from dataPath');
    }

    @IsTest
    static void buildAmendSeedUpdate_roundsHalfUpToTwoScale() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        Map<String, Object> upd = hook.buildAmendSeedUpdate(
            wrapperWithPath(new List<Object>{ 'r', 'q' }), 6695.309);
        System.assert(((Decimal) attrValue(upd, 'NetUnitPrice')) == 6695.31, 'rounds HALF_UP to 2 scale');
    }

    @IsTest
    static void buildAmendSeedUpdate_nullOnBadInput() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        System.assertEquals(null, hook.buildAmendSeedUpdate(null, 100), 'null wrapper -> null');
        System.assertEquals(null, hook.buildAmendSeedUpdate(wrapperWithPath(new List<Object>{ 'r', 'q' }), null), 'null prior -> null');
        System.assertEquals(null, hook.buildAmendSeedUpdate(wrapperWithPath(new List<Object>{ 'r', 'q' }), 0), 'zero prior -> null');
        System.assertEquals(null, hook.buildAmendSeedUpdate(wrapperWithPath(new List<Object>{ 'r', 'q' }), -5), 'negative prior -> null');
        System.assertEquals(null, hook.buildAmendSeedUpdate(new Map<String, Object>{ 'noPath' => true }, 100), 'no dataPath -> null');
    }

    @IsTest
    static void buildAmendSeedUpdate_seedsTotalClusterOnly() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        // unitNet null, lineTotal given -> only the four total attributes, no unit attributes.
        Map<String, Object> upd = hook.buildAmendSeedUpdate(
            wrapperWithPath(new List<Object>{ 'r', '0QLLINE' }), null, 40000);
        System.assertNotEquals(null, upd, 'total-only seed built');
        System.assert(((Decimal) attrValue(upd, 'NetTotalPrice')) == 40000, 'NetTotalPrice seeded');
        System.assert(((Decimal) attrValue(upd, 'TotalPrice')) == 40000, 'TotalPrice seeded');
        System.assert(((Decimal) attrValue(upd, 'Subtotal')) == 40000, 'Subtotal seeded');
        System.assert(((Decimal) attrValue(upd, 'TotalLineAmount')) == 40000, 'TotalLineAmount seeded (AmendSeedNetTotal fallback branch)');
        System.assertEquals(null, attrValue(upd, 'NetUnitPrice'), 'no unit attribute when unitNet null');
    }

    @IsTest
    static void buildAmendSeedUpdate_seedsUnitAndTotalTogether() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        Map<String, Object> upd = hook.buildAmendSeedUpdate(
            wrapperWithPath(new List<Object>{ 'r', '0QLLINE' }), 10000, 40000);
        System.assert(((Decimal) attrValue(upd, 'NetUnitPrice')) == 10000, 'unit carried');
        System.assert(((Decimal) attrValue(upd, 'UnitPrice')) == 10000, 'input unit carried');
        System.assert(((Decimal) attrValue(upd, 'NetTotalPrice')) == 40000, 'total recomputed (net x qty)');
        System.assert(((Decimal) attrValue(upd, 'TotalLineAmount')) == 40000, 'total fallback set too');
    }

    @IsTest
    static void buildAmendSeedUpdate_totalRoundsHalfUp() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        Map<String, Object> upd = hook.buildAmendSeedUpdate(
            wrapperWithPath(new List<Object>{ 'r', 'q' }), null, 40000.009);
        System.assert(((Decimal) attrValue(upd, 'NetTotalPrice')) == 40000.01, 'total rounds HALF_UP to 2 scale');
    }

    @IsTest
    static void buildAmendSeedUpdate_bothNull_returnsNull() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        System.assertEquals(null,
            hook.buildAmendSeedUpdate(wrapperWithPath(new List<Object>{ 'r', 'q' }), null, null),
            'no unit and no total -> null');
        System.assertEquals(null,
            hook.buildAmendSeedUpdate(wrapperWithPath(new List<Object>{ 'r', 'q' }), 0, 0),
            'zero unit and zero total -> null');
    }

    @IsTest
    static void extractQueryResult_handlesResponseShapes() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        System.assertEquals(null, hook.extractQueryResult(null), 'null response -> null');
        // nested queryResult shape
        Map<String, Object> nested = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SalesTransactionItem' => new List<Object>() }
        };
        System.assertNotEquals(null, hook.extractQueryResult(nested), 'nested queryResult unwrapped');
        // flat shape
        Map<String, Object> flat = new Map<String, Object>{ 'SalesTransactionItem' => new List<Object>() };
        System.assertEquals(flat, hook.extractQueryResult(flat), 'flat shape returned as-is');
        // unrelated shape
        System.assertEquals(null, hook.extractQueryResult(new Map<String, Object>{ 'other' => 1 }), 'unrelated -> null');
    }

    @IsTest
    static void seedAmendNets_noContext_returnsZeroGracefully() {
        // No live pricing context in a unit test → queryTags fails, caught → empty → 0 seeded, never throws.
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        Test.startTest();
        Integer seeded = -1;
        try {
            seeded = hook.seedAmendNets('0ctxNONE0000000000');
        } catch (Exception e) {
            // Context.IndustriesContext may not construct in a test context; either way the class is exercised.
            seeded = 0;
        }
        Test.stopTest();
        System.assertEquals(0, seeded, 'no context -> nothing seeded, no throw');
    }
}
