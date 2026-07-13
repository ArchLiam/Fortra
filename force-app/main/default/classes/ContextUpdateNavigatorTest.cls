/**
 * @description Unit tests for ContextUpdateNavigator, verifying the helpers that index
 *              context lines by record Id, extract and compare update data paths, and resolve
 *              the renewal maintenance update path.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class ContextUpdateNavigatorTest {

    /**
     * @description Builds a minimal update payload map carrying the given dataPath under nodePath,
     *              used as test fixture input for the navigator helpers.
     * @param dataPath the dataPath value to embed in the payload's nodePath
     * @return an update payload map with the supplied dataPath and an empty attributes list
     */
    private static Map<String, Object> updateWithPath(String dataPath) {
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => dataPath },
            'attributes' => new List<Object>()
        };
    }

    /**
     * @description Verifies that indexContextLinesById keys lines by their _recordId, skips lines
     *              without a record Id, and returns an empty map when given a null list.
     */
    @IsTest
    static void indexContextLinesById_keysByRecordIdAndSkipsIdless() {
        Id rid = '001000000000001AAA';
        List<Map<String, Object>> lines = new List<Map<String, Object>>{
            new Map<String, Object>{ '_recordId' => String.valueOf(rid) },
            new Map<String, Object>{ 'noId' => true }
        };
        Map<Id, Map<String, Object>> byId = ContextUpdateNavigator.indexContextLinesById(lines);
        System.assertEquals(1, byId.size(), 'Only the line with a record Id is indexed');
        System.assert(byId.containsKey(rid), 'Indexed by _recordId');
        System.assertEquals(0, ContextUpdateNavigator.indexContextLinesById(null).size(), 'Null list -> empty map');
    }

    /**
     * @description Verifies that extractUpdatePath returns the nested nodePath dataPath when present
     *              and returns null when nodePath is absent, not a map, or the payload is null.
     */
    @IsTest
    static void extractUpdatePath_readsDataPathElseNull() {
        System.assertEquals('a/b/c', ContextUpdateNavigator.extractUpdatePath(updateWithPath('a/b/c')));
        System.assertEquals(null, ContextUpdateNavigator.extractUpdatePath(new Map<String, Object>{ 'x' => 'y' }),
            'No nodePath -> null');
        System.assertEquals(null,
            ContextUpdateNavigator.extractUpdatePath(new Map<String, Object>{ 'nodePath' => 'not-a-map' }),
            'nodePath not a map -> null');
        System.assertEquals(null, ContextUpdateNavigator.extractUpdatePath(null), 'Null payload -> null');
    }

    /**
     * @description Verifies that containsEquivalentUpdate matches a candidate against existing updates
     *              by dataPath, returning false when the paths differ, the list is null, or the
     *              candidate has no dataPath.
     */
    @IsTest
    static void containsEquivalentUpdate_matchesByDataPath() {
        List<Map<String, Object>> updates = new List<Map<String, Object>>{ updateWithPath('p1'), updateWithPath('p2') };
        System.assert(ContextUpdateNavigator.containsEquivalentUpdate(updates, updateWithPath('p2')),
            'Same dataPath -> equivalent');
        System.assert(!ContextUpdateNavigator.containsEquivalentUpdate(updates, updateWithPath('p9')),
            'Different dataPath -> not equivalent');
        System.assert(!ContextUpdateNavigator.containsEquivalentUpdate(null, updateWithPath('p1')),
            'Null updates -> false');
        System.assert(!ContextUpdateNavigator.containsEquivalentUpdate(updates, new Map<String, Object>{ 'x' => 'y' }),
            'Candidate without dataPath -> false');
    }

    /**
     * @description Verifies that resolveRenewalMaintenanceUpdatePath returns an existing _updatePath
     *              verbatim, otherwise builds a [quoteId, lineItemId] path from both ids, and returns
     *              null when either id is missing.
     */
    @IsTest
    static void resolveRenewalMaintenanceUpdatePath_prefersUpdatePathElseBuildsList() {
        // _updatePath present -> returned verbatim
        Object existing = new List<Object>{ 'a', 'b' };
        System.assertEquals(existing, ContextUpdateNavigator.resolveRenewalMaintenanceUpdatePath(
            new Map<String, Object>{ '_updatePath' => existing }, '001000000000001AAA', '001000000000002AAA'));
        // no _updatePath, both ids present -> [quoteId, lineItemId]
        Id lineId = '001000000000001AAA';
        Id quoteId = '001000000000002AAA';
        List<Object> built = (List<Object>) ContextUpdateNavigator.resolveRenewalMaintenanceUpdatePath(
            new Map<String, Object>{}, lineId, quoteId);
        System.assertEquals(String.valueOf(quoteId), built[0], 'path[0] = quoteId');
        System.assertEquals(String.valueOf(lineId), built[1], 'path[1] = lineItemId');
        // missing an id -> null
        System.assertEquals(null, ContextUpdateNavigator.resolveRenewalMaintenanceUpdatePath(
            new Map<String, Object>{}, null, quoteId), 'null lineItemId -> null');
    }
}