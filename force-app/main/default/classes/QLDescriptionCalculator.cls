/**
 * @description Pure line-description assembly logic extracted from QLDescriptionGeneratorPrehook
 *              (Wave-2 hook-thinning, finishes Wave 2). Plain-input / plain-output — NO SOQL, DML,
 *              or RCA-context. Contains the description-string builders (buildDescription,
 *              computeUnitTypeSegment, resolveUnitQuantity), the context-update payload builders
 *              (buildContextUpdate/buildContextUpdates), and the queryTags-response parsers
 *              (parseConfiguredAttributes, parseLineItemDataPaths). The hook retains all context
 *              I/O (queryTags/updateContextAttributes), the SOQL (Product2.Name, MDT config), the
 *              ResolvedConfig type + config-building (defaultConfig/buildResolvedConfig/loadConfig),
 *              and delegates the pure pieces here via thin @TestVisible seams. Method bodies are
 *              moved byte-verbatim so the live path and the unit tests can never diverge.
 *
 *              The format constants below mirror the hook's single-source-of-truth spec constants
 *              (QLDescriptionGeneratorPrehook: SEPARATOR/TRUNCATION_MARKER/DESCRIPTION_MAX_LENGTH/
 *              CONTEXT_DESCRIPTION_ATTR) so this calculator is self-contained.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class QLDescriptionCalculator {

    /** Separator between non-empty segments. */
    @TestVisible private static final String SEPARATOR = ' | ';
    /** Truncation marker appended when the joined string exceeds the Description Text(4000) limit. */
    @TestVisible private static final String TRUNCATION_MARKER = ' | [truncated]';
    @TestVisible private static final Integer DESCRIPTION_MAX_LENGTH = 4000;
    /** Hydration-mapped context attribute name that writes back to QuoteLineItem.Description. */
    @TestVisible private static final String CONTEXT_DESCRIPTION_ATTR = 'SalesTrxnItemDescription';

    // ============================================================
    // DESCRIPTION BUILDING
    // ============================================================

    /**
     * @description Build the pipe-separated Description for one line. Product Name is always the
     *              leading segment; attribute segments are appended only when the line has attributes.
     *              Returns null only when there is neither a product name nor any attribute segment.
     * @param productName Product Name used as the leading segment; skipped when blank.
     * @param attrs Attribute name-to-value map for the line; null/empty yields product name only.
     * @param cfg Resolved configuration supplying segment and unit-type attribute names.
     * @return Pipe-separated description (truncated to the max length), or null when no segments exist.
     */
    public static String buildDescription(String productName, Map<String, String> attrs, QLDescriptionGeneratorPrehook.ResolvedConfig cfg) {
        List<String> segments = new List<String>();

        // Product Name is always the leading segment, even for lines with no
        // configured attributes (e.g. flat license fees). Attribute segments
        // are appended only when the line has attributes.
        if (String.isNotBlank(productName)) {
            segments.add(productName);
        }

        if (attrs != null && !attrs.isEmpty()) {
            String unitTypeSegment = computeUnitTypeSegment(attrs, cfg);
            if (String.isNotBlank(unitTypeSegment)) {
                segments.add(unitTypeSegment);
            }

            Set<String> seenSegmentValues = new Set<String>();
            for (String attrName : cfg.segmentNames) {
                String val = attrs.get(attrName);
                if (String.isBlank(val) || seenSegmentValues.contains(val)) {
                    continue;
                }
                seenSegmentValues.add(val);
                segments.add(val);
            }
        }

        if (segments.isEmpty()) {
            return null;
        }

        String joined = String.join(segments, SEPARATOR);
        if (joined.length() > DESCRIPTION_MAX_LENGTH) {
            Integer cutoff = DESCRIPTION_MAX_LENGTH - TRUNCATION_MARKER.length();
            if (cutoff < 0) {
                cutoff = 0;
            }
            joined = joined.substring(0, cutoff) + TRUNCATION_MARKER;
        }
        return joined;
    }

    /**
     * @description Compute the leading Unit Type segment. Returns null when the segment should be
     *              omitted. The Unit Quantity is read from the configuration attribute map for ANY
     *              Unit Type value — never from the standard QuoteLineItem.Quantity field.
     * @param attrs Attribute name-to-value map for the line.
     * @param cfg Resolved configuration supplying the unit-type attribute name and trigger value.
     * @return Formatted Unit Type segment, or null when it should be omitted.
     */
    public static String computeUnitTypeSegment(Map<String, String> attrs, QLDescriptionGeneratorPrehook.ResolvedConfig cfg) {
        if (attrs == null) {
            return null;
        }
        String unitType = attrs.get(cfg.unitTypeAttr);
        if (String.isBlank(unitType)) {
            return null;
        }
        String trimmedQty = resolveUnitQuantity(attrs, cfg);
        Boolean hasQty = trimmedQty != null;

        if (unitType == cfg.unitTypeTrigger) {
            return hasQty ? 'Users: ' + trimmedQty : 'Per User';
        }
        return hasQty ? unitType + ': ' + trimmedQty : unitType;
    }

    /**
     * @description Resolve the unit count for the Unit Type segment. Attribute_Volume (primary)
     *              wins when present; otherwise the fallback attribute.
     * @param attrs Attribute name-to-value map for the line.
     * @param cfg Resolved configuration supplying the primary and fallback quantity attribute names.
     * @return Trimmed quantity string, or null when neither attribute has a value.
     */
    public static String resolveUnitQuantity(Map<String, String> attrs, QLDescriptionGeneratorPrehook.ResolvedConfig cfg) {
        if (attrs == null) {
            return null;
        }
        String volume = attrs.get(cfg.unitQtyPrimary);
        if (String.isNotBlank(volume)) {
            return volume.trim();
        }
        if (String.isNotBlank(cfg.unitQtyFallback)) {
            String numberOfUnits = attrs.get(cfg.unitQtyFallback);
            if (String.isNotBlank(numberOfUnits)) {
                return numberOfUnits.trim();
            }
        }
        return null;
    }

    // ============================================================
    // CONTEXT UPDATE PAYLOAD BUILDERS
    // ============================================================

    /**
     * @description Build the full list of per-line context update payloads. For each line: skips
     *              lines absent from the dataPath map, builds the Description via
     *              buildDescription(name, attrs, cfg), skips lines whose description is null, and
     *              emits a context-update payload for the rest.
     * @param attrsByLineId Map of line-item Id to its attribute name-to-value map.
     * @param dataPathByLineId Map of line-item Id to its context dataPath.
     * @param productNameByLineId Map of line-item Id to its product name.
     * @param cfg Resolved configuration passed through to buildDescription.
     * @return List of context-update payloads, one per line that produced a non-null description.
     */
    public static List<Map<String, Object>> buildContextUpdates(
        Map<Id, Map<String, String>> attrsByLineId,
        Map<Id, List<Object>> dataPathByLineId,
        Map<Id, String> productNameByLineId,
        QLDescriptionGeneratorPrehook.ResolvedConfig cfg
    ) {
        List<Map<String, Object>> contextUpdates = new List<Map<String, Object>>();
        // Iterate ALL lines in scope (not only lines that have attributes) so
        // attribute-less products still receive a product-name description.
        // attrsByLineId.get(lineId) is null for such lines — buildDescription
        // handles a null/empty attribute map and emits the product name alone.
        for (Id lineId : dataPathByLineId.keySet()) {
            List<Object> dataPath = dataPathByLineId.get(lineId);
            if (dataPath == null) {
                continue;
            }
            String descriptionText = buildDescription(
                productNameByLineId.get(lineId),
                attrsByLineId.get(lineId),
                cfg
            );
            if (descriptionText == null) {
                continue;
            }
            contextUpdates.add(buildContextUpdate(dataPath, descriptionText));
        }
        return contextUpdates;
    }

    /**
     * @description Build a single line's update payload for updateContextAttributes. The nodePath
     *              is the line's dataPath with the FIRST element removed (the root entity Id).
     * @param dataPath The line's context dataPath, including the leading root entity Id.
     * @param description The Description text to write to the context attribute.
     * @return Context-update payload map with nodePath and attributes entries.
     */
    public static Map<String, Object> buildContextUpdate(List<Object> dataPath, String description) {
        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'attributeName' => CONTEXT_DESCRIPTION_ATTR,
                    'attributeValue' => description
                }
            }
        };
    }

    // ============================================================
    // queryTags RESPONSE PARSERS (pure of live-context dependency)
    // ============================================================

    /**
     * @description Parse a queryTags(SalesTransactionItemAttribute) response into a map of
     *              line-item Id -> (attribute name -> attribute value). Handles the nested
     *              {queryResult:{...}} and flat shapes, nested-tagValue vs flat node layouts,
     *              ParentReference vs dataPath-parent resolution, the Attribute vs AttributeKeyName
     *              fallback, and the bad-id Id.valueOf guard.
     * @param apiResponse The queryTags(SalesTransactionItemAttribute) response map.
     * @return Map of line-item Id to (attribute name -> attribute value).
     */
    public static Map<Id, Map<String, String>> parseConfiguredAttributes(Map<String, Object> apiResponse) {
        Map<Id, Map<String, String>> result = new Map<Id, Map<String, String>>();
        if (apiResponse == null) {
            return result;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            queryResult = (qrObj instanceof Map<String, Object>) ? (Map<String, Object>) qrObj : null;
        } else if (apiResponse.containsKey('SalesTransactionItemAttribute')) {
            queryResult = apiResponse;
        }
        if (queryResult == null || !queryResult.containsKey('SalesTransactionItemAttribute')) {
            return result;
        }

        Object attrObj = queryResult.get('SalesTransactionItemAttribute');
        List<Object> attributeData = (attrObj instanceof List<Object>)
            ? (List<Object>) attrObj
            : new List<Object>{ attrObj };

        for (Object rawAttr : attributeData) {
            if (rawAttr == null || !(rawAttr instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> attrNode = (Map<String, Object>) rawAttr;
            Map<String, Object> tagMap;
            List<Object> dataPath;

            if (attrNode.containsKey('tagValue')) {
                Object tv = attrNode.get('tagValue');
                tagMap = (tv instanceof Map<String, Object>) ? (Map<String, Object>) tv : null;
                Object dp = attrNode.get('dataPath');
                dataPath = (dp instanceof List<Object>) ? (List<Object>) dp : null;
            } else {
                tagMap = attrNode;
                dataPath = new List<Object>();
            }
            if (tagMap == null) {
                continue;
            }

            String parentRef = getStringFromTag(tagMap, 'ParentReference');
            if (String.isBlank(parentRef) && dataPath != null && dataPath.size() >= 2) {
                parentRef = String.valueOf(dataPath[dataPath.size() - 2]);
            }
            if (String.isBlank(parentRef)) {
                continue;
            }

            Id parentId;
            try {
                parentId = Id.valueOf(parentRef);
            } catch (Exception e) {
                ExceptionLogger.log('QLDescriptionCalculator', null, new DescriptionGenerationException('parseConfiguredAttributes failed', e));
                continue;
            }

            String attrName = getStringFromTag(tagMap, 'Attribute');
            if (String.isBlank(attrName)) {
                attrName = getStringFromTag(tagMap, 'AttributeKeyName');
            }
            String attrValue = getStringFromTag(tagMap, 'AttributeValue');

            if (String.isNotBlank(attrName) && attrValue != null) {
                if (!result.containsKey(parentId)) {
                    result.put(parentId, new Map<String, String>());
                }
                result.get(parentId).put(attrName, attrValue);
            }
        }
        return result;
    }

    /**
     * @description Parse a queryTags(SalesTransactionItem) response into a map of line-item Id ->
     *              dataPath. Handles the nested vs flat response shapes, the single-object-not-list
     *              case, and the Id.valueOf guard on the dataPath's last element.
     * @param apiResponse The queryTags(SalesTransactionItem) response map.
     * @return Map of line-item Id to its dataPath.
     */
    public static Map<Id, List<Object>> parseLineItemDataPaths(Map<String, Object> apiResponse) {
        Map<Id, List<Object>> result = new Map<Id, List<Object>>();
        if (apiResponse == null) {
            return result;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            queryResult = (qrObj instanceof Map<String, Object>) ? (Map<String, Object>) qrObj : null;
        } else if (apiResponse.containsKey('SalesTransactionItem')) {
            queryResult = apiResponse;
        }
        if (queryResult == null || !queryResult.containsKey('SalesTransactionItem')) {
            return result;
        }

        Object itemsObj = queryResult.get('SalesTransactionItem');
        List<Object> rawItems = (itemsObj instanceof List<Object>)
            ? (List<Object>) itemsObj
            : new List<Object>{ itemsObj };

        for (Object rawItem : rawItems) {
            if (rawItem == null || !(rawItem instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> itemNode = (Map<String, Object>) rawItem;
            Object dpObj = itemNode.get('dataPath');
            if (!(dpObj instanceof List<Object>)) {
                continue;
            }
            List<Object> dataPath = (List<Object>) dpObj;
            if (dataPath.isEmpty()) {
                continue;
            }
            try {
                Id lineId = Id.valueOf(String.valueOf(dataPath[dataPath.size() - 1]));
                result.put(lineId, dataPath);
            } catch (Exception e) {
                ExceptionLogger.log('QLDescriptionCalculator', null, new DescriptionGenerationException('parseLineItemDataPaths failed', e));
                // dataPath last element wasn't a valid Id — skip
            }
        }
        return result;
    }

    // ============================================================
    // CONTEXT TAG HELPERS (calculator-local; mirror the hook's private helpers)
    // ============================================================

    /**
     * @description Extract a tag field's value and coerce it to a String.
     * @param tagData The tag/attribute node map to read from.
     * @param fieldName The field name to extract.
     * @return String value of the field, or null when absent or null.
     */
    private static String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        return val != null ? String.valueOf(val) : null;
    }

    /**
     * @description Extract a field's raw value from a tag node, unwrapping the nested
     *              {tagValue:...} wrapper shape when present.
     * @param tagData The tag/attribute node map to read from.
     * @param fieldName The field name to extract.
     * @return Raw field value (or unwrapped tagValue), or null when absent, null, or unrecognized.
     */
    private static Object extractFieldValue(Map<String, Object> tagData, String fieldName) {
        if (tagData == null || !tagData.containsKey(fieldName)) {
            return null;
        }
        Object fieldObj = tagData.get(fieldName);
        if (fieldObj == null) {
            return null;
        }
        if (fieldObj instanceof Map<String, Object>) {
            Map<String, Object> wrapper = (Map<String, Object>) fieldObj;
            if (wrapper.containsKey('tagValue')) {
                return wrapper.get('tagValue');
            }
            return null;
        }
        return fieldObj;
    }
}