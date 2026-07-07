@IsTest
private class ContextTagReaderTest {

    private static Map<String, Object> tag(Object value) {
        return new Map<String, Object>{ 'F' => new Map<String, Object>{ 'tagValue' => value } };
    }

    @IsTest
    static void extractFieldValue_unwrapsTagValueAndHandlesEdges() {
        System.assertEquals('x', ContextTagReader.extractFieldValue(tag('x'), 'F'));
        System.assertEquals(null, ContextTagReader.extractFieldValue(tag('x'), 'Missing'), 'Missing key -> null');
        System.assertEquals(null, ContextTagReader.extractFieldValue(null, 'F'), 'Null tagData -> null');
        System.assertEquals(42, ContextTagReader.extractFieldValue(new Map<String, Object>{ 'F' => 42 }, 'F'),
            'Non-wrapped value returned as-is');
        System.assertEquals(null,
            ContextTagReader.extractFieldValue(new Map<String, Object>{ 'F' => new Map<String, Object>{} }, 'F'),
            'Wrapper without tagValue -> null');
    }

    @IsTest
    static void getStringFromTag_stringifies() {
        System.assertEquals('5', ContextTagReader.getStringFromTag(tag(5), 'F'));
        System.assertEquals(null, ContextTagReader.getStringFromTag(tag(null), 'F'));
    }

    @IsTest
    static void getIdFromTag_parsesValidIdElseNull() {
        Id valid = '001000000000001AAA';
        System.assertEquals(valid, ContextTagReader.getIdFromTag(tag(String.valueOf(valid)), 'F'));
        System.assertEquals(null, ContextTagReader.getIdFromTag(tag('not-an-id'), 'F'), 'Malformed -> null');
        System.assertEquals(null, ContextTagReader.getIdFromTag(tag(''), 'F'), 'Blank -> null');
    }

    @IsTest
    static void getDecimalFromTag_parsesNumberElseNull() {
        System.assertEquals(12.50, ContextTagReader.getDecimalFromTag(tag('12.50'), 'F'), 'String number parsed');
        System.assertEquals(12.50, ContextTagReader.getDecimalFromTag(tag(12.50), 'F'), 'Decimal passthrough');
        System.assertEquals(null, ContextTagReader.getDecimalFromTag(tag('abc'), 'F'), 'Non-number -> null');
        System.assertEquals(null, ContextTagReader.getDecimalFromTag(tag(null), 'F'));
    }

    @IsTest
    static void getLineItemRecordId_prefersRecordIdThenTagsElseNull() {
        Id rid = '001000000000001AAA';
        // _recordId marker wins
        System.assertEquals(rid,
            ContextTagReader.getLineItemRecordId(new Map<String, Object>{ '_recordId' => String.valueOf(rid) }));
        // falls back to SourceRecordId tag
        System.assertEquals(rid,
            ContextTagReader.getLineItemRecordId(new Map<String, Object>{
                'SourceRecordId' => new Map<String, Object>{ 'tagValue' => String.valueOf(rid) } }));
        // falls back to Id tag
        System.assertEquals(rid,
            ContextTagReader.getLineItemRecordId(new Map<String, Object>{
                'Id' => new Map<String, Object>{ 'tagValue' => String.valueOf(rid) } }));
        // none present -> null
        System.assertEquals(null, ContextTagReader.getLineItemRecordId(new Map<String, Object>{ 'X' => 'y' }));
        // malformed -> null
        System.assertEquals(null,
            ContextTagReader.getLineItemRecordId(new Map<String, Object>{ '_recordId' => 'not-an-id' }));
    }
}
