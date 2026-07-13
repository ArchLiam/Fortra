/**
 * @description Unit tests for ContextTagReader, verifying extraction and coercion of values from Sales Transaction Context tag maps.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class ContextTagReaderTest {

    /**
     * @description Builds a single-field tag map that wraps the given value in the standard tagValue envelope.
     * @param value the value to wrap under the tagValue key
     * @return a tag map of the form { 'F' => { 'tagValue' => value } }
     */
    private static Map<String, Object> tag(Object value) {
        return new Map<String, Object>{ 'F' => new Map<String, Object>{ 'tagValue' => value } };
    }

    /**
     * @description Verifies extractFieldValue unwraps tagValue, returns null for missing keys, null tag data, and wrappers without tagValue, and passes non-wrapped values through as-is.
     */
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

    /**
     * @description Verifies getStringFromTag stringifies a numeric tag value and returns null for a null tag value.
     */
    @IsTest
    static void getStringFromTag_stringifies() {
        System.assertEquals('5', ContextTagReader.getStringFromTag(tag(5), 'F'));
        System.assertEquals(null, ContextTagReader.getStringFromTag(tag(null), 'F'));
    }

    /**
     * @description Verifies getIdFromTag parses a valid Id string and returns null for malformed or blank tag values.
     */
    @IsTest
    static void getIdFromTag_parsesValidIdElseNull() {
        Id valid = '001000000000001AAA';
        System.assertEquals(valid, ContextTagReader.getIdFromTag(tag(String.valueOf(valid)), 'F'));
        System.assertEquals(null, ContextTagReader.getIdFromTag(tag('not-an-id'), 'F'), 'Malformed -> null');
        System.assertEquals(null, ContextTagReader.getIdFromTag(tag(''), 'F'), 'Blank -> null');
    }

    /**
     * @description Verifies getDecimalFromTag parses numeric strings and Decimal values and returns null for non-numeric or null tag values.
     */
    @IsTest
    static void getDecimalFromTag_parsesNumberElseNull() {
        System.assertEquals(12.50, ContextTagReader.getDecimalFromTag(tag('12.50'), 'F'), 'String number parsed');
        System.assertEquals(12.50, ContextTagReader.getDecimalFromTag(tag(12.50), 'F'), 'Decimal passthrough');
        System.assertEquals(null, ContextTagReader.getDecimalFromTag(tag('abc'), 'F'), 'Non-number -> null');
        System.assertEquals(null, ContextTagReader.getDecimalFromTag(tag(null), 'F'));
    }

    /**
     * @description Verifies getLineItemRecordId prefers the _recordId marker, then falls back to the SourceRecordId and Id tags, and returns null when none are present or the value is malformed.
     */
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