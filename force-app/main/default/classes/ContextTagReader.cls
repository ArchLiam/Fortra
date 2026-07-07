/**
 * @description Shared reader for RCA pricing-context tag maps (the `{fieldName: {tagValue: ...}}`
 *              shape), extracted verbatim from PartnerNetPricePosthook (Wave-2 decomposition,
 *              increment 7). The same 4 helpers are copy-pasted across ~9 pricing hooks; this is the
 *              canonical implementation. Pure map parsing — no SOQL, no RCA context — so unit-testable.
 *              Other hooks can migrate to it incrementally (getStringFromTag/getDecimalFromTag are
 *              already identical across them; getIdFromTag/extractFieldValue vary, so verify per class
 *              before repointing).
 */
public with sharing class ContextTagReader {

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

    public static String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        return val != null ? String.valueOf(val) : null;
    }

    public static Id getIdFromTag(Map<String, Object> tagData, String fieldName) {
        String val = getStringFromTag(tagData, fieldName);
        if (String.isBlank(val)) {
            return null;
        }
        try {
            return Id.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

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
            return null;
        }
    }

    /**
     * @description Resolve the source record Id for a context line map. Prefers the
     *              `_recordId` marker, then the SourceRecordId tag, then the Id tag.
     *              Verbatim from PartnerNetPricePosthook (Wave-2 decomposition, increment 11).
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
            return null;
        }
    }
}
