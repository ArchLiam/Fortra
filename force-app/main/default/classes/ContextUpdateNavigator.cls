/**
 * @description Pure navigation helpers for RCA pricing-context line/update maps. Index context lines
 *              by source record Id, read an update payload's dataPath, and dedup updates by dataPath.
 *              No SOQL, no DML, no RCA context — pure map plumbing, so unit-testable.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class ContextUpdateNavigator {

    /**
     * @description Index context line maps by their source record Id (skips lines without one).
     * @param lineItems Context line maps to index; null yields an empty map.
     * @return Map of source record Id to its context line map.
     */
    public static Map<Id, Map<String, Object>> indexContextLinesById(List<Map<String, Object>> lineItems) {
        Map<Id, Map<String, Object>> byId = new Map<Id, Map<String, Object>>();
        if (lineItems == null) {
            return byId;
        }
        for (Map<String, Object> lineItem : lineItems) {
            Id lineItemId = ContextTagReader.getLineItemRecordId(lineItem);
            if (lineItemId != null) {
                byId.put(lineItemId, lineItem);
            }
        }
        return byId;
    }

    /**
     * @description The `nodePath.dataPath` of an update payload, or null if absent/malformed.
     * @param updatePayload Update payload expected to hold a `nodePath` map.
     * @return The `dataPath` value, or null when absent or malformed.
     */
    public static Object extractUpdatePath(Map<String, Object> updatePayload) {
        if (updatePayload == null || !updatePayload.containsKey('nodePath')) {
            return null;
        }
        Object nodePath = updatePayload.get('nodePath');
        if (!(nodePath instanceof Map<String, Object>)) {
            return null;
        }
        return ((Map<String, Object>) nodePath).get('dataPath');
    }

    /**
     * @description True when `updates` already holds an update for the candidate's dataPath.
     * @param updates Existing update payloads to scan.
     * @param candidate Update payload whose dataPath is compared against the existing ones.
     * @return True when an update with an equivalent dataPath already exists.
     */
    public static Boolean containsEquivalentUpdate(
        List<Map<String, Object>> updates,
        Map<String, Object> candidate
    ) {
        if (updates == null || updates.isEmpty() || candidate == null) {
            return false;
        }

        Object candidatePath = extractUpdatePath(candidate);
        if (candidatePath == null) {
            return false;
        }

        for (Map<String, Object> existing : updates) {
            if (candidatePath == extractUpdatePath(existing)
                || String.valueOf(candidatePath).equals(String.valueOf(extractUpdatePath(existing)))) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Resolve the context update dataPath for a renewal-maintenance line: the line's
     *              own `_updatePath` when present, else a [quoteId, lineItemId] path; null when
     *              neither is available.
     * @param lineItem Context line map that may carry an `_updatePath`.
     * @param lineItemId Source record Id used to build the fallback path.
     * @param quoteId Quote Id used to build the fallback path.
     * @return The resolved dataPath, or null when neither source is available.
     */
    public static Object resolveRenewalMaintenanceUpdatePath(
        Map<String, Object> lineItem,
        Id lineItemId,
        Id quoteId
    ) {
        Object updatePath = lineItem.get('_updatePath');
        if (updatePath != null) {
            return updatePath;
        }
        if (quoteId == null || lineItemId == null) {
            return null;
        }
        return new List<Object>{ String.valueOf(quoteId), String.valueOf(lineItemId) };
    }
}