/**
 * @description Service class for loading QuoteLineItemAttribute records from CSV data.
 *              Handles CSV parsing, validation against AttributeDefinition and
 *              AttributePicklistValue records, and lookup resolution for batch processing.
 *
 *              CSV Format (row-per-QLI):
 *              Legacy_Id__c,Server Type,Number of Units,Deployment Option
 *              DY_12345,Non-Production,100+,Managed Service
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-03
 */
public with sharing class AttributeLoadingService {

    /**
     * @description Preview result returned to the LWC before executing the batch
     */
    public class AttributePreview {
        @AuraEnabled public Integer rowCount;
        @AuraEnabled public Integer attributeCount;
        @AuraEnabled public Integer existingCount;
        @AuraEnabled public Integer unmatchedQliCount;
        @AuraEnabled public List<String> attributeNames;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public List<String> errors;
    }

    // ── CSV Parsing ──────────────────────────────────────────────────

    /**
     * @description Parse CSV content into a map of Legacy_Id__c -> (AttrName -> AttrValue).
     *              Handles quoted values and ignores empty cells.
     * @param csvContent Raw CSV text from the uploaded file
     * @return Map keyed by Legacy_Id__c containing attribute name-value pairs
     */
    public static Map<String, Map<String, String>> buildAttributeMap(String csvContent) {
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();

        List<String> lines = csvContent.split('\n');
        if (lines.isEmpty()) {
            return result;
        }

        // Parse header row
        List<String> headers = parseCsvLine(lines[0]);
        if (headers.isEmpty()) {
            return result;
        }

        // First column must be Legacy_Id__c (case-insensitive match)
        String firstHeader = headers[0].trim();
        if (!firstHeader.equalsIgnoreCase('Legacy_Id__c')) {
            return result;
        }

        // Parse data rows
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) {
                continue;
            }

            List<String> cells = parseCsvLine(line);
            if (cells.isEmpty()) {
                continue;
            }

            String legacyId = cells[0].trim();
            if (String.isBlank(legacyId)) {
                continue;
            }

            Map<String, String> attrMap = new Map<String, String>();
            for (Integer col = 1; col < headers.size() && col < cells.size(); col++) {
                String attrName = headers[col].trim();
                String attrValue = cells[col].trim();
                if (String.isNotBlank(attrName) && String.isNotBlank(attrValue)) {
                    attrMap.put(attrName, attrValue);
                }
            }

            if (!attrMap.isEmpty()) {
                result.put(legacyId, attrMap);
            }
        }

        return result;
    }

    /**
     * @description Extract attribute column names from CSV header row
     * @param csvContent Raw CSV text
     * @return List of attribute names (excludes the Legacy_Id__c column)
     */
    public static List<String> extractAttributeNames(String csvContent) {
        List<String> names = new List<String>();
        List<String> lines = csvContent.split('\n');
        if (lines.isEmpty()) {
            return names;
        }

        List<String> headers = parseCsvLine(lines[0]);
        for (Integer i = 1; i < headers.size(); i++) {
            String name = headers[i].trim();
            if (String.isNotBlank(name)) {
                names.add(name);
            }
        }
        return names;
    }

    /**
     * @description Parse a single CSV line handling quoted values with embedded commas.
     * @param line A single CSV row
     * @return List of cell values with quotes stripped
     */
    @TestVisible
    private static List<String> parseCsvLine(String line) {
        List<String> cells = new List<String>();
        if (String.isBlank(line)) {
            return cells;
        }

        // Remove trailing carriage return if present (Windows line endings)
        if (line.endsWith('\r')) {
            line = line.substring(0, line.length() - 1);
        }

        Boolean inQuotes = false;
        String currentCell = '';

        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);

            if (ch == '"') {
                // Check for escaped quote ""
                if (inQuotes && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    currentCell += '"';
                    i++; // skip next quote
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (ch == ',' && !inQuotes) {
                cells.add(currentCell);
                currentCell = '';
            } else {
                currentCell += ch;
            }
        }
        // Add last cell
        cells.add(currentCell);

        return cells;
    }

    // ── Lookup Resolution ────────────────────────────────────────────

    /**
     * @description Build a map of AttributeDefinition Name -> Id for all active definitions.
     * @return Map of attribute name to AttributeDefinition Id
     */
    public static Map<String, Id> buildAttrDefMap() {
        Map<String, Id> attrDefMap = new Map<String, Id>();
        for (AttributeDefinition ad : [
            SELECT Id, Name FROM AttributeDefinition WHERE IsActive = true
        ]) {
            attrDefMap.put(ad.Name, ad.Id);
        }
        return attrDefMap;
    }

    /**
     * @description Build a map of AttributeDefinition Name -> (PicklistValue.Value -> PicklistValue.Id)
     *              for picklist-type attributes. Joins through AttributePicklist.
     * @param attrDefIds Set of AttributeDefinition Ids to resolve picklist values for
     * @return Nested map: AttrDef Name -> (Picklist Value string -> AttributePicklistValue Id)
     */
    public static Map<String, Map<String, Id>> buildPicklistValueMap(Set<Id> attrDefIds) {
        Map<String, Map<String, Id>> result = new Map<String, Map<String, Id>>();

        if (attrDefIds == null || attrDefIds.isEmpty()) {
            return result;
        }

        // Step 1: Get PicklistId for each AttributeDefinition
        Map<Id, String> picklistIdToAttrName = new Map<Id, String>();
        Map<String, Id> attrNameToPicklistId = new Map<String, Id>();

        for (AttributeDefinition ad : [
            SELECT Id, Name, PicklistId
            FROM AttributeDefinition
            WHERE Id IN :attrDefIds AND PicklistId != null
        ]) {
            if (ad.PicklistId != null) {
                picklistIdToAttrName.put(ad.PicklistId, ad.Name);
                attrNameToPicklistId.put(ad.Name, ad.PicklistId);
            }
        }

        if (picklistIdToAttrName.isEmpty()) {
            return result;
        }

        // Step 2: Query AttributePicklistValue for those picklists
        Set<Id> picklistIds = picklistIdToAttrName.keySet();
        for (AttributePicklistValue apv : [
            SELECT Id, Value, PicklistId
            FROM AttributePicklistValue
            WHERE PicklistId IN :picklistIds
        ]) {
            String attrName = picklistIdToAttrName.get(apv.PicklistId);
            if (attrName != null) {
                if (!result.containsKey(attrName)) {
                    result.put(attrName, new Map<String, Id>());
                }
                result.get(attrName).put(apv.Value, apv.Id);
            }
        }

        return result;
    }

    // ── Preview ──────────────────────────────────────────────────────

    /**
     * @description Generate a preview of what the attribute load will do,
     *              without actually inserting any records.
     * @param csvContent Raw CSV text from the uploaded file
     * @return AttributePreview with counts, attribute names, warnings, and errors
     */
    public static AttributePreview previewLoad(String csvContent) {
        AttributePreview preview = new AttributePreview();
        preview.warnings = new List<String>();
        preview.errors = new List<String>();
        preview.attributeNames = new List<String>();
        preview.rowCount = 0;
        preview.attributeCount = 0;
        preview.existingCount = 0;
        preview.unmatchedQliCount = 0;

        // Parse CSV
        Map<String, Map<String, String>> attrByLegacyId = buildAttributeMap(csvContent);
        if (attrByLegacyId.isEmpty()) {
            preview.errors.add('No valid data rows found in CSV. Ensure first column header is "Legacy_Id__c".');
            return preview;
        }

        preview.rowCount = attrByLegacyId.size();

        // Extract attribute names from headers
        List<String> csvAttrNames = extractAttributeNames(csvContent);
        preview.attributeNames = csvAttrNames;

        // Validate attribute names against org's AttributeDefinition records
        Map<String, Id> attrDefMap = buildAttrDefMap();
        for (String attrName : csvAttrNames) {
            if (!attrDefMap.containsKey(attrName)) {
                preview.errors.add('Attribute "' + attrName + '" does not match any active AttributeDefinition.');
            }
        }

        // If there are blocking errors, return early
        if (!preview.errors.isEmpty()) {
            return preview;
        }

        // Validate picklist values
        Set<Id> relevantAttrDefIds = new Set<Id>();
        for (String attrName : csvAttrNames) {
            if (attrDefMap.containsKey(attrName)) {
                relevantAttrDefIds.add(attrDefMap.get(attrName));
            }
        }
        Map<String, Map<String, Id>> picklistMap = buildPicklistValueMap(relevantAttrDefIds);

        // Check each value against picklist options (warn, don't block)
        Set<String> warnedValues = new Set<String>();
        for (String legacyId : attrByLegacyId.keySet()) {
            Map<String, String> attrs = attrByLegacyId.get(legacyId);
            for (String attrName : attrs.keySet()) {
                if (picklistMap.containsKey(attrName)) {
                    String value = attrs.get(attrName);
                    Map<String, Id> validValues = picklistMap.get(attrName);
                    if (!validValues.containsKey(value)) {
                        String warnKey = attrName + ':' + value;
                        if (!warnedValues.contains(warnKey)) {
                            preview.warnings.add(
                                'Value "' + value + '" for attribute "' + attrName +
                                '" does not match any AttributePicklistValue. ' +
                                'It will be loaded as text only (no PicklistValueId).'
                            );
                            warnedValues.add(warnKey);
                        }
                    }
                }
            }
        }

        // Count total attributes to create
        Integer totalAttrs = 0;
        for (Map<String, String> attrs : attrByLegacyId.values()) {
            totalAttrs += attrs.size();
        }
        preview.attributeCount = totalAttrs;

        // Check which Legacy_Id__c values actually match QLIs in the org
        Set<String> legacyIds = attrByLegacyId.keySet();
        Set<String> matchedLegacyIds = new Set<String>();
        for (QuoteLineItem qli : [
            SELECT Legacy_Id__c FROM QuoteLineItem WHERE Legacy_Id__c IN :legacyIds
        ]) {
            matchedLegacyIds.add(qli.Legacy_Id__c);
        }
        Integer unmatchedCount = 0;
        for (String lid : legacyIds) {
            if (!matchedLegacyIds.contains(lid)) {
                unmatchedCount++;
            }
        }
        preview.unmatchedQliCount = unmatchedCount;
        if (unmatchedCount > 0) {
            preview.warnings.add(unmatchedCount + ' Legacy_Id__c value(s) in the CSV do not match any QuoteLineItem in the org.');
        }

        // Count existing QLIA records (will be skipped as duplicates)
        List<Id> matchedQliIds = new List<Id>();
        for (QuoteLineItem qli : [
            SELECT Id FROM QuoteLineItem WHERE Legacy_Id__c IN :legacyIds
        ]) {
            matchedQliIds.add(qli.Id);
        }
        if (!matchedQliIds.isEmpty()) {
            Integer existingCount = [
                SELECT COUNT()
                FROM QuoteLineItemAttribute
                WHERE QuoteLineItemId IN :matchedQliIds
            ];
            preview.existingCount = existingCount;
            if (existingCount > 0) {
                preview.warnings.add(existingCount + ' existing QuoteLineItemAttribute record(s) found. Duplicates will be skipped.');
            }
        }

        return preview;
    }
}