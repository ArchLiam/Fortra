/**
 * @description Shared, canonical reader for RCA pricing-context tag maps (the
 *              `{fieldName: {tagValue: ...}}` shape). Provides pure, unit-testable
 *              map-parsing helpers to extract String, Id, and Decimal values from
 *              context tag data, with no SOQL or RCA context dependencies.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class ContextTagReader {

    /**
     * @description Resolves the raw value for a field within a context tag map, unwrapping
     *              the nested `tagValue` when the field is stored as a `{tagValue: ...}` map.
     * @param tagData The context tag map keyed by field name
     * @param fieldName The field name to look up
     * @return The unwrapped field value, or null if absent
     */
    public static Object extractFieldValue(Map<String, Object> tagData, String fieldName) {
        if (tagData == null || !tagData.containsKey(fieldName)) {
            return null;
        }

        Object fieldObj = tagData.get(fieldName);
        if (fieldObj == null) {
            return null;
        }

        if (fieldObj instanceof Map<String, Object>) {
            Map<String, Object> fieldWrapper = (Map<String, Object>) fieldObj;
            if (fieldWrapper.containsKey('tagValue')) {
                return fieldWrapper.get('tagValue');
            }
            return null;
        }

        return fieldObj;
    }

    /**
     * @description Extracts a field value from a context tag map as a String.
     * @param tagData The context tag map keyed by field name
     * @param fieldName The field name to look up
     * @return The value as a String, or null if absent
     */
    public static String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        return val != null ? String.valueOf(val) : null;
    }

    /**
     * @description Extracts a field value from a context tag map as an Id, returning
     *              null when the value is blank or not a valid Id.
     * @param tagData The context tag map keyed by field name
     * @param fieldName The field name to look up
     * @return The value as an Id, or null if absent or invalid
     */
    public static Id getIdFromTag(Map<String, Object> tagData, String fieldName) {
        String val = getStringFromTag(tagData, fieldName);
        if (String.isBlank(val)) {
            return null;
        }
        try {
            return Id.valueOf(val);
        } catch (Exception e) {
            ExceptionLogger.log('ContextTagReader', null, new PricingContextException('getIdFromTag failed', e));
            return null;
        }
    }

    /**
     * @description Extracts a field value from a context tag map as a Decimal, returning
     *              null when the value is null or cannot be parsed as a Decimal.
     * @param tagData The context tag map keyed by field name
     * @param fieldName The field name to look up
     * @return The value as a Decimal, or null if absent or unparseable
     */
    public static Decimal getDecimalFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        if (val == null) {
            return null;
        }
        if (val instanceof Decimal) {
            return (Decimal) val;
        }
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            ExceptionLogger.log('ContextTagReader', null, new PricingContextException('getDecimalFromTag failed', e));
            return null;
        }
    }

    /**
     * @description Resolves the source record Id for a context line map, preferring the
     *              `_recordId` marker, then the SourceRecordId tag, then the Id tag.
     * @param lineItem The context line map to resolve the record Id from
     * @return The resolved record Id, or null if none is present or valid
     */
    public static Id getLineItemRecordId(Map<String, Object> lineItem) {
        String lineItemId = (String) lineItem.get('_recordId');
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'SourceRecordId');
        }
        if (String.isBlank(lineItemId)) {
            lineItemId = getStringFromTag(lineItem, 'Id');
        }
        if (String.isBlank(lineItemId)) {
            return null;
        }
        try {
            return Id.valueOf(lineItemId);
        } catch (Exception e) {
            ExceptionLogger.log('ContextTagReader', null, new PricingContextException('getLineItemRecordId failed', e));
            return null;
        }
    }
}