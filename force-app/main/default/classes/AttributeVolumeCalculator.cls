/**
 * @description Pure attribute-volume tier-pricing math + context-node shaping, extracted VERBATIM
 *              from AttributeVolumePricingPrehook (Wave-2 hook-thinning, round 2). No SOQL, no DML,
 *              no RCA context API — every method operates only on already-parsed context tag maps
 *              ({tagValue, dataPath}) and already-queried Attribute_Tier_Pricing_Storage__c records,
 *              so it is fully unit-testable. The prehook stays the thin adapter: it does the two
 *              queryTags reads, the bulk tier SOQL, and the context submit, and delegates the pure
 *              math/lookup/node-shaping below.
 *
 *              WHAT LIVES HERE (pure):
 *                - buildTierLookupMap / buildCompositeKey — composite-key tier map
 *                - lookupTierFromMap                      — volume -> tier resolution + range check
 *                - buildNodeUpdate                        — matched-tier context node update
 *                - buildResetNodeUpdate                   — SC-3390 / D-17 reset-to-list payload
 *                                                            (behavior preserved EXACTLY, not fixed)
 *                - buildAttributeExplainerText            — waterfall explainer string
 *                - getAttributeVolumeValue / getAttributeValue — Attribute_Volume + named-attr reads
 *                - getLineItemIdFromDataPath / getParentIdFromDataPath / groupAttributesByLineItem
 *                - tag helpers: getValueFromTag / getStringFromTag / getDecimalFromTag / getBooleanFromTag
 *
 *              Stateless — all methods are static (no per-execution state).
 *
 * @see AttributeVolumePricingPrehook (the adapter/seam owner; holds the queryTags reads, the bulk
 *      Attribute_Tier_Pricing_Storage__c SOQL, the Pass-1/Pass-2 orchestration, and the submit)
 * @author Marc DeBrey (original) / Wave-2 decomposition (extracted verbatim, behavior-preserving)
 * @date July 2026
 */
public with sharing class AttributeVolumeCalculator {

    // Attribute name for the volume dimension used in tier range matching
    private static final String ATTR_VOLUME_NAME = 'Attribute_Volume';

    /**
     * @description Wrapper class to hold pricing tier lookup results. PUBLIC (was a prehook-private
     *              inner) so the adapter hook can carry the value this calculator returns.
     */
    public class PricingTierResult {
        public Decimal multiplier;      // From Multiplier__c (nullable)
        public String priceMode;        // From Price_Mode__c
        public Decimal basePrice;       // From Tier_Value__c
        public String attributeName;    // Matched attribute name
        public String attributeValue;   // Matched attribute value

        public PricingTierResult(Decimal mult, String mode, Decimal base, String attrName, String attrVal) {
            this.multiplier = mult;
            this.priceMode = mode;
            this.basePrice = base;
            this.attributeName = attrName;
            this.attributeValue = attrVal;
        }
    }

    /**
     * @description Build a composite-key lookup map from a list of tier records.
     *              Key format: ProductId|PSMId|AttributeName|AttributeValue
     *              Value: List of tier records (different volume ranges for same key)
     * @param tiers List of Attribute_Tier_Pricing_Storage__c records
     * @return Composite-key map for O(1) attribute lookups
     */
    public static Map<String, List<Attribute_Tier_Pricing_Storage__c>> buildTierLookupMap(
        List<Attribute_Tier_Pricing_Storage__c> tiers
    ) {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = new Map<String, List<Attribute_Tier_Pricing_Storage__c>>();

        for (Attribute_Tier_Pricing_Storage__c tier : tiers) {
            String key = buildCompositeKey(tier.Product__c, tier.Product_Selling_Model__c,
                tier.Attribute_Name__c, tier.Attribute_Value__c, tier.CurrencyIsoCode);

            if (!tierMap.containsKey(key)) {
                tierMap.put(key, new List<Attribute_Tier_Pricing_Storage__c>());
            }
            tierMap.get(key).add(tier);
        }

        System.debug(LoggingLevel.INFO, 'Tier lookup map built with ' + tierMap.size() + ' unique keys');
        return tierMap;
    }

    /**
     * @description Build a composite key string from the four matching dimensions
     * @param productId Product2 Id
     * @param psmId ProductSellingModel Id
     * @param attrName Attribute name
     * @param attrValue Attribute value
     * @return Pipe-delimited composite key
     */
    private static String buildCompositeKey(String productId, String psmId, String attrName, String attrValue, String currencyIso) {
        // Normalize attribute name: context uses underscores (Feature_Options),
        // tier data uses spaces (Feature Options) - standardize to underscores
        String normalizedName = attrName != null ? attrName.replaceAll(' ', '_') : attrName;
        // SC-3384: currency is the 5th key segment so a non-USD line only matches its OWN-currency tier row.
        // Previously currency-blind -> a EUR/GBP line matched USD tier rows and priced from the USD tier value.
        return productId + '|' + psmId + '|' + normalizedName + '|' + attrValue + '|' + currencyIso;
    }

    /**
     * @description Look up a matching pricing tier from the pre-built map.
     *              Iterates through ALL attributes on the line item, builds a composite key
     *              for each, checks if the map has entries, then verifies volume is within range.
     *              Returns the first match found.
     * @param tierMap The pre-built composite-key map
     * @param productId Product2 Id from context
     * @param psmId ProductSellingModel Id from context
     * @param lineAttributes List of attribute tag maps for this line item
     * @param volume Attribute volume value for tier range matching
     * @return PricingTierResult if a match is found, null otherwise
     */
    public static PricingTierResult lookupTierFromMap(
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap,
        String productId,
        String psmId,
        List<Map<String, Object>> lineAttributes,
        Decimal volume,
        String currencyIso
    ) {
        if (tierMap == null || String.isBlank(productId) || String.isBlank(psmId) ||
            lineAttributes == null || lineAttributes.isEmpty() || volume == null) {
            return null;
        }

        for (Map<String, Object> attr : lineAttributes) {
            // Get attribute name (try 'Attribute' first, fall back to 'AttributeKeyName')
            String attrName = getStringFromTag(attr, 'Attribute');
            if (String.isBlank(attrName)) {
                attrName = getStringFromTag(attr, 'AttributeKeyName');
            }

            // Skip Attribute_Volume — it drives range matching, not tier key lookup
            if (ATTR_VOLUME_NAME.equals(attrName)) {
                continue;
            }

            String attrValue = getStringFromTag(attr, 'AttributeValue');

            if (String.isBlank(attrName) || String.isBlank(attrValue)) {
                System.debug(LoggingLevel.DEBUG, 'lookupTier: Skipping blank attr - name=' + attrName + ', value=' + attrValue);
                continue;
            }

            String key = buildCompositeKey(productId, psmId, attrName, attrValue, currencyIso);
            System.debug(LoggingLevel.DEBUG, 'lookupTier: Checking key=' + key + ' (attr=' + attrName + '=' + attrValue + ')');

            if (!tierMap.containsKey(key)) {
                continue;
            }

            // Check volume range for each tier with this key
            for (Attribute_Tier_Pricing_Storage__c tier : tierMap.get(key)) {
                Decimal lower = tier.Lower_Bound__c != null ? tier.Lower_Bound__c : 0;
                Decimal upper = tier.Upper_Bound__c;

                if (volume >= lower && (upper == null || volume <= upper)) {
                    return new PricingTierResult(
                        tier.Multiplier__c,
                        tier.Price_Mode__c,
                        tier.Tier_Value__c,
                        attrName,
                        attrValue
                    );
                }
            }
        }

        return null;
    }

    /**
     * @description Build a node update map for a line item with pricing tier results
     * @param itemNode The item node from context
     * @param tierResult The pricing tier lookup results
     * @param volume The attribute volume value for explainer
     * @return Node update map for Context API
     */
    public static Map<String, Object> buildNodeUpdate(
        Map<String, Object> itemNode,
        PricingTierResult tierResult,
        Decimal volume
    ) {
        List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
        if (dataPath == null || dataPath.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'buildNodeUpdate: dataPath is null or empty');
            return null;
        }

        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }

        System.debug(LoggingLevel.INFO, 'buildNodeUpdate: Original dataPath: ' + dataPath);
        System.debug(LoggingLevel.INFO, 'buildNodeUpdate: updatePath (minus contextId): ' + updatePath);

        // Build attributes list - Context API requires List<Object>, NOT List<Map<String, Object>>
        // (Apex generics are not covariant; wrong runtime type causes silent rejection)
        List<Object> attributes = new List<Object>();

        // Always output Base_Price__c (from Tier_Value__c)
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Base_Price__c',
            'attributeValue' => tierResult.basePrice
        });

        // Always output Attribute_Price_Mode__c
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Attribute_Price_Mode__c',
            'attributeValue' => tierResult.priceMode
        });

        // Only output Attribute_Multiplier_Pct__c for Calculated mode
        // NOTE: Context Definition attribute name is Attribute_Multiplier_Pct__c (with underscores)
        if (tierResult.priceMode == 'Calculated' && tierResult.multiplier != null) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Attribute_Multiplier_Pct__c',
                'attributeValue' => tierResult.multiplier
            });
        }

        // NOTE: AttributePricingApplied__c removed from context writes.
        // The QLI field does not exist, and writing a context attribute that maps
        // to a non-existent source field may cause the entire node update to silently fail.

        // Log explainer info for debug/waterfall visibility (not written to context)
        String explainerText = buildAttributeExplainerText(tierResult, volume);
        System.debug(LoggingLevel.INFO, 'Explainer: ' + explainerText);
        System.debug(LoggingLevel.INFO, 'Feature: ' + tierResult.attributeName + ': ' + tierResult.attributeValue);
        System.debug(LoggingLevel.INFO, 'Volume: ' + volume);

        System.debug(LoggingLevel.INFO, 'buildNodeUpdate: Writing ' + attributes.size() + ' attributes: ' +
            JSON.serialize(attributes));

        Map<String, Object> result = new Map<String, Object>();
        result.put('nodePath', new Map<String, Object>{ 'dataPath' => updatePath });
        result.put('attributes', attributes);

        return result;
    }

    /**
     * @description Build a node update that resets pricing to list price when no tier matches.
     *              Reads ListPrice from context tags and writes it as Base_Price__c with 'Unit Price' mode.
     *              This ensures the Pricing Procedure resets the line to list price instead of
     *              retaining stale values from a previous pricing run.
     * @param itemNode The item node from context
     * @param tagMap The tag map for this line item (contains ListPrice)
     * @return Node update map for Context API, or null if dataPath is missing
     */
    public static Map<String, Object> buildResetNodeUpdate(Map<String, Object> itemNode, Map<String, Object> tagMap) {
        List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
        if (dataPath == null || dataPath.isEmpty()) {
            return null;
        }

        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }

        Decimal listPrice = getDecimalFromTag(tagMap, 'ListPrice');
        if (listPrice == null) {
            listPrice = 0;
        }
        System.debug(LoggingLevel.INFO, 'buildResetNodeUpdate: Resetting to ListPrice=' + listPrice + ' for path: ' + updatePath);

        List<Object> attributes = new List<Object>();
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Base_Price__c',
            'attributeValue' => listPrice
        });
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Attribute_Price_Mode__c',
            'attributeValue' => 'Unit Price'
        });

        Map<String, Object> result = new Map<String, Object>();
        result.put('nodePath', new Map<String, Object>{ 'dataPath' => updatePath });
        result.put('attributes', attributes);
        return result;
    }

    /**
     * @description Build explainer text for pricing waterfall display
     * @param tierResult The pricing tier result (includes attribute name/value)
     * @param volume The attribute volume value
     * @return Human-readable explainer text
     */
    public static String buildAttributeExplainerText(PricingTierResult tierResult, Decimal volume) {
        String explainer = 'Attr: ' + tierResult.attributeName + '=' + tierResult.attributeValue +
            ', Vol: ' + volume.setScale(0).intValue();

        if (tierResult.priceMode == 'Calculated' && tierResult.multiplier != null) {
            explainer += ', Base: $' + tierResult.basePrice.setScale(2) + ' x ' + tierResult.multiplier.setScale(2);
        } else if (tierResult.priceMode == 'Unit Price') {
            explainer += ', Unit: $' + tierResult.basePrice.setScale(2);
        } else if (tierResult.priceMode == 'Total Price') {
            explainer += ', Total: $' + tierResult.basePrice.setScale(2);
        }

        return explainer;
    }

    /**
     * @description Group already-parsed attribute nodes by their parent line-item id. Reads
     *              ParentReference first, falling back to the dataPath parent segment. Pure of any
     *              live-context dependency, so it is unit-testable with hand-built attribute nodes.
     * @param attributeData Parsed SalesTransactionItemAttribute node list
     * @param attributesByLineItem Output map (mutated in place) of line-item id to attribute tag maps
     */
    public static void groupAttributesByLineItem(
        List<Object> attributeData,
        Map<String, List<Map<String, Object>>> attributesByLineItem
    ) {
        // Group attributes by parent line item ID
        for (Object attrObj : attributeData) {
            Map<String, Object> attrNode = (Map<String, Object>) attrObj;
            Map<String, Object> tagMap = (Map<String, Object>) attrNode.get('tagValue');

            // Get parent reference (line item ID) from attribute
            String parentLineItemId = getStringFromTag(tagMap, 'ParentReference');
            if (String.isBlank(parentLineItemId)) {
                // Try to extract from dataPath
                parentLineItemId = getParentIdFromDataPath(attrNode);
            }

            if (String.isNotBlank(parentLineItemId)) {
                if (!attributesByLineItem.containsKey(parentLineItemId)) {
                    attributesByLineItem.put(parentLineItemId, new List<Map<String, Object>>());
                }
                attributesByLineItem.get(parentLineItemId).add(tagMap);
            }
        }
    }

    /**
     * @description Get the line item ID from the dataPath array
     * @param itemNode The item node from context
     * @return Line item ID (last element of dataPath)
     */
    public static String getLineItemIdFromDataPath(Map<String, Object> itemNode) {
        List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
        if (dataPath == null || dataPath.isEmpty()) {
            return null;
        }
        // Line item ID is the last element in dataPath
        return String.valueOf(dataPath[dataPath.size() - 1]);
    }

    /**
     * @description Get the parent line item ID from attribute's dataPath
     * @param attrNode The attribute node from context
     * @return Parent line item ID
     */
    public static String getParentIdFromDataPath(Map<String, Object> attrNode) {
        List<Object> dataPath = (List<Object>) attrNode.get('dataPath');
        if (dataPath == null || dataPath.size() < 2) {
            return null;
        }
        // Parent line item ID is the second-to-last element for child nodes
        return String.valueOf(dataPath[dataPath.size() - 2]);
    }

    /**
     * @description Extract the Attribute_Volume numeric value from line item attributes.
     *              Reads the string attribute value and parses to Decimal.
     * @param attributes List of attribute tag maps for the line item
     * @return The volume as Decimal, or null if not found or not parseable
     */
    public static Decimal getAttributeVolumeValue(List<Map<String, Object>> attributes) {
        String volumeStr = getAttributeValue(attributes, ATTR_VOLUME_NAME);
        if (String.isBlank(volumeStr)) {
            return null;
        }
        try {
            return Decimal.valueOf(volumeStr);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not parse Attribute_Volume value: ' + volumeStr);
            return null;
        }
    }

    /**
     * @description Get attribute value by name from list of attributes
     * @param attributes List of attribute tag maps
     * @param attributeName The attribute name to find
     * @return The attribute value as string
     */
    public static String getAttributeValue(List<Map<String, Object>> attributes, String attributeName) {
        if (attributes == null || String.isBlank(attributeName)) {
            return null;
        }
        for (Map<String, Object> attr : attributes) {
            // Context API uses 'Attribute' for the name, not 'AttributeName'
            String name = getStringFromTag(attr, 'Attribute');
            // Fallback to AttributeKeyName if Attribute is null
            if (String.isBlank(name)) {
                name = getStringFromTag(attr, 'AttributeKeyName');
            }
            if (attributeName.equals(name)) {
                return getStringFromTag(attr, 'AttributeValue');
            }
        }
        return null;
    }

    // ========== Helper Methods for Tag Value Extraction ==========

    /**
     * @description Extract raw value from nested tag structure
     *              Handles both direct values and nested {tagValue: x} structures
     * @param tagMap The tag map to extract from
     * @param attributeName The attribute name to extract
     * @return The raw value or null
     */
    private static Object getValueFromTag(Map<String, Object> tagMap, String attributeName) {
        if (tagMap == null || !tagMap.containsKey(attributeName)) {
            return null;
        }

        Object attrObj = tagMap.get(attributeName);

        if (attrObj instanceof Map<String, Object>) {
            Map<String, Object> attrMap = (Map<String, Object>) attrObj;
            if (attrMap.containsKey('tagValue')) {
                return attrMap.get('tagValue');
            }
        }

        return attrObj;
    }

    /**
     * @description Extract string value from nested tag structure
     */
    public static String getStringFromTag(Map<String, Object> tagMap, String attributeName) {
        Object value = getValueFromTag(tagMap, attributeName);
        return value != null ? String.valueOf(value) : null;
    }

    /**
     * @description Extract decimal value from nested tag structure
     */
    private static Decimal getDecimalFromTag(Map<String, Object> tagMap, String attributeName) {
        Object value = getValueFromTag(tagMap, attributeName);
        if (value == null) {
            return null;
        }

        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Extract boolean value from nested tag structure
     */
    public static Boolean getBooleanFromTag(Map<String, Object> tagMap, String attributeName) {
        Object value = getValueFromTag(tagMap, attributeName);
        if (value == null) {
            return null;
        }

        if (value instanceof Boolean) {
            return (Boolean) value;
        }

        String strValue = String.valueOf(value).toLowerCase();
        return strValue == 'true' || strValue == '1' || strValue == 'yes';
    }
}
