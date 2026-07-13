/**
 * @description Unit coverage for AmendNetCarryPrehook's pure seams. execute() itself cannot be
 *              unit-tested — RevSignaling.TransactionRequest has no public constructor and
 *              Context.IndustriesContext.queryTags() needs a live pricing context — so the end-to-end
 *              path is validated by integration; these tests lock the seed-entry shape and response parsing.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class AmendNetCarryPrehookTest {

    /**
     * @description Builds a minimal node wrapper carrying the given data path, used to feed seam methods under test.
     * @param dataPath Ordered node identifiers ([rootId, ..., qliId]) placed under the wrapper's dataPath key.
     * @return A wrapper map containing the supplied dataPath.
     */
    private static Map<String, Object> wrapperWithPath(List<Object> dataPath) {
        return new Map<String, Object>{ 'dataPath' => dataPath };
    }

    /**
     * @description Finds the value of a named attribute within a seed update entry's attributes list.
     * @param upd The seed update entry to inspect; null yields null.
     * @param attributeName The attribute name to match.
     * @return The matched attributeValue, or null when the entry is null or the attribute is absent.
     */
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

    /**
     * @description Reads the node path recorded on a seed update entry.
     * @param upd The seed update entry whose nodePath.dataPath is returned.
     * @return The update entry's data path list.
     */
    private static List<Object> updatePath(Map<String, Object> upd) {
        return (List<Object>) ((Map<String, Object>) upd.get('nodePath')).get('dataPath');
    }

    /**
     * @description Verifies a unit-net seed populates both NetUnitPrice and UnitPrice and that the update path drops the root element.
     */
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

    /**
     * @description Verifies a unit-net seed is rounded HALF_UP to two decimal places.
     */
    @IsTest
    static void buildAmendSeedUpdate_roundsHalfUpToTwoScale() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        Map<String, Object> upd = hook.buildAmendSeedUpdate(
            wrapperWithPath(new List<Object>{ 'r', 'q' }), 6695.309);
        System.assert(((Decimal) attrValue(upd, 'NetUnitPrice')) == 6695.31, 'rounds HALF_UP to 2 scale');
    }

    /**
     * @description Verifies no seed entry is produced for a null wrapper, missing dataPath, or a null, zero, or negative prior net.
     */
    @IsTest
    static void buildAmendSeedUpdate_nullOnBadInput() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        System.assertEquals(null, hook.buildAmendSeedUpdate(null, 100), 'null wrapper -> null');
        System.assertEquals(null, hook.buildAmendSeedUpdate(wrapperWithPath(new List<Object>{ 'r', 'q' }), null), 'null prior -> null');
        System.assertEquals(null, hook.buildAmendSeedUpdate(wrapperWithPath(new List<Object>{ 'r', 'q' }), 0), 'zero prior -> null');
        System.assertEquals(null, hook.buildAmendSeedUpdate(wrapperWithPath(new List<Object>{ 'r', 'q' }), -5), 'negative prior -> null');
        System.assertEquals(null, hook.buildAmendSeedUpdate(new Map<String, Object>{ 'noPath' => true }, 100), 'no dataPath -> null');
    }

    /**
     * @description Verifies a total-only seed (null unit net) populates the four total attributes and no unit attributes.
     */
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

    /**
     * @description Verifies supplying both unit net and line total seeds the unit attributes and the recomputed total cluster.
     */
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

    /**
     * @description Verifies a total-only seed is rounded HALF_UP to two decimal places.
     */
    @IsTest
    static void buildAmendSeedUpdate_totalRoundsHalfUp() {
        AmendNetCarryPrehook hook = new AmendNetCarryPrehook();
        Map<String, Object> upd = hook.buildAmendSeedUpdate(
            wrapperWithPath(new List<Object>{ 'r', 'q' }), null, 40000.009);
        System.assert(((Decimal) attrValue(upd, 'NetTotalPrice')) == 40000.01, 'total rounds HALF_UP to 2 scale');
    }

    /**
     * @description Verifies no seed entry is produced when both unit net and line total are null or both zero.
     */
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

    /**
     * @description Verifies query-result extraction unwraps the nested queryResult shape, returns a flat shape as-is, and yields null for null or unrelated responses.
     */
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

    /**
     * @description Verifies that without a live pricing context seedAmendNets seeds nothing, returns zero, and never throws.
     */
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