@IsTest
private class ContextUpdateNavigatorTest {

    private static Map<String, Object> updateWithPath(String dataPath) {
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => dataPath },
            'attributes' => new List<Object>()
        };
    }

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
}
