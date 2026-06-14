/**
 * @description Apex Hook for Revenue Cloud pricing that applies attribute
 *              and volume-based pricing adjustments with three price modes.
 *              Dynamically matches product attributes against Attribute_Tier_Pricing_Storage__c
 *              records using a bulk two-pass pattern (Product, PSM, Attribute Name/Value, volume range).
 *              Writes pricing outputs (Base_Price__c, Attribute_Price_Mode__c,
 *              Attribute_Multiplier_Pct__c) to context.
 *
 * @author Marc DeBrey
 * @date February 2026
 * @version 3.0
 *
 * Technical Flow:
 *   1. Query SalesTransactionItem for line items
 *   2. Filter by Has_Attribute_Adjustment__c = true
 *   3. Pass 1: Collect Product and PSM IDs from eligible items
 *   4. Bulk SOQL: Query Attribute_Tier_Pricing_Storage__c for all collected IDs
 *   5. Build composite-key map (ProductId|PSMId|AttrName|AttrValue -> tiers)
 *   6. Pass 2: For each eligible item, extract Attribute_Volume, iterate attributes, lookup tier from map + volume range check
 *   7. Write Base_Price__c, Attribute_Price_Mode__c, and Attribute_Multiplier_Pct__c to context
 *
 * Price Modes:
 *   - Unit Price: Base_Price__c -> InputUnitPrice
 *   - Calculated: Base_Price__c * Attribute_Multiplier_Pct__c -> ItemNetTotalPrice
 *   - Total Price: Base_Price__c -> ItemNetTotalPrice
 */
global class AttributeVolumePricingPrehook implements RevSignaling.SignalingApexProcessor {

    // Static flag to prevent recursive execution
    private static Boolean isUpdating = false;

    // Attribute name for the volume dimension used in tier range matching
    private static final String ATTR_VOLUME_NAME = 'Attribute_Volume';

    /**
     * @description Wrapper class to hold pricing tier lookup results
     */
    @TestVisible
    private class PricingTierResult {
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
     * @description Execute method called by Revenue Cloud pricing orchestration
     * @param request The transaction request containing pricing context
     * @return TransactionResponse indicating success or failure
     */
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        System.debug(LoggingLevel.INFO, '=== AttributeVolumePricingPrehook v3.0 START ===');
        String contextId = request.ctxInstanceId;

        // Recursion prevention
        if (isUpdating) {
            return createResponse(RevSignaling.TransactionStatus.SUCCESS, 'Skipping recursive execution');
        }

        String message = '';

        try {
            isUpdating = true;
            message = processAttributeVolumePricing(contextId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Attribute volume pricing error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            message = 'Attribute volume pricing error: ' + e.getMessage();
        } finally {
            isUpdating = false;
        }

        System.debug(LoggingLevel.INFO, '=== AttributeVolumePricingPrehook v3.0 END ===');
        return createResponse(RevSignaling.TransactionStatus.SUCCESS, message);
    }

    /**
     * @description Lightweight result holder for the pure two-pass build. Carries the node-update
     *              list plus the processed/skipped counters so the wrapper can format the exact
     *              same status message the original single method produced.
     */
    @TestVisible
    private class ItemUpdateResult {
        public List<Map<String, Object>> itemNodeUpdates;
        public Integer processedCount;
        public Integer skippedCount;

        public ItemUpdateResult(List<Map<String, Object>> updates, Integer processed, Integer skipped) {
            this.itemNodeUpdates = updates;
            this.processedCount = processed;
            this.skippedCount = skipped;
        }
    }

    /**
     * @description Process attribute and volume-based pricing logic using two-pass bulk pattern.
     *              Thin context-only wrapper: performs the two live queryTags reads, delegates the
     *              eligibility filter + bulk-SOQL + Pass-1/Pass-2 build to the @TestVisible core
     *              buildItemNodeUpdates(), then submits via submitContextUpdates(). Splitting the
     *              parse/build into a core that takes ALREADY-PARSED items keeps it unit-testable
     *              without a live pricing context, while every early-return short-circuit string and
     *              the submit path remain byte-for-byte equivalent to the original.
     * @param contextId The context instance ID
     * @return Status message describing the result
     */
    private String processAttributeVolumePricing(String contextId) {
        Context.IndustriesContext industriesContext = new Context.IndustriesContext();

        // Query line items from context
        // NOTE: queryLineItems wraps the live queryTags call. The original implementation does NOT
        // catch a failure here, so it propagates to execute()'s outer try/catch (message =
        // 'Attribute volume pricing error: ...'). That propagation contract is preserved.
        List<Object> lineItemData = queryLineItems(industriesContext, contextId);
        if (lineItemData == null || lineItemData.isEmpty()) {
            return 'No line items to process';
        }

        // Query line item attributes from context
        // NOTE: queryLineItemAttributes has its OWN try/catch that swallows a queryTags failure and
        // returns an empty map (degrade gracefully). That swallow-and-continue contract is preserved.
        Map<String, List<Map<String, Object>>> attributesByLineItem = queryLineItemAttributes(industriesContext, contextId);

        // Build node updates from the already-parsed items (eligibility filter + bulk SOQL +
        // two-pass loop). Returns a null update list when an early-return short-circuit applies;
        // the exact original status string is then carried in earlyReturnMessage.
        ItemUpdateResult buildResult = buildItemNodeUpdates(lineItemData, attributesByLineItem);
        if (buildResult.itemNodeUpdates == null) {
            return earlyReturnMessage;
        }

        if (buildResult.itemNodeUpdates.isEmpty()) {
            return 'No attribute-based updates needed (processed=' + buildResult.processedCount +
                ', skipped=' + buildResult.skippedCount + ')';
        }

        // Write to context via Context API
        return submitContextUpdates(industriesContext, contextId, buildResult.itemNodeUpdates,
            buildResult.processedCount, buildResult.skippedCount);
    }

    // Holds the short-circuit status string produced by buildItemNodeUpdates() when it returns a
    // null update list (no eligible items / no tier records). Set by the core, read by the wrapper.
    @TestVisible
    private String earlyReturnMessage;

    /**
     * @description Pure two-pass build over ALREADY-PARSED line-item + attribute data. Performs the
     *              eligibility filter (Has_Attribute_Adjustment__c), the bulk Attribute_Tier_Pricing_Storage__c
     *              SOQL, the composite-key map build, and Pass-2 per-item tier lookup / reset, returning
     *              the assembled node-update list and processed/skipped counters. No live-context
     *              dependency, so it is unit-testable with hand-built {tagValue, dataPath} maps. When an
     *              early-return short-circuit applies (no eligible items, no tiers) it returns a result
     *              whose itemNodeUpdates is null and sets earlyReturnMessage to the original string.
     * @param lineItemData Parsed SalesTransactionItem node list (each a {tagValue, dataPath} map)
     * @param attributesByLineItem Map of line-item id to its parsed attribute tag maps
     * @return ItemUpdateResult carrying the node-update list (or null) plus counters
     */
    @TestVisible
    private ItemUpdateResult buildItemNodeUpdates(
        List<Object> lineItemData,
        Map<String, List<Map<String, Object>>> attributesByLineItem
    ) {
        earlyReturnMessage = null;

        // ===== PASS 1: Collect Product and PSM IDs from eligible line items =====
        Set<String> productIds = new Set<String>();
        Set<String> psmIds = new Set<String>();
        List<Map<String, Object>> eligibleItems = new List<Map<String, Object>>();

        for (Object itemObj : lineItemData) {
            Map<String, Object> itemNode = (Map<String, Object>) itemObj;
            Map<String, Object> tagMap = (Map<String, Object>) itemNode.get('tagValue');

            Boolean hasAttributeAdjustment = getBooleanFromTag(tagMap, 'Has_Attribute_Adjustment__c');
            if (hasAttributeAdjustment != true) {
                continue;
            }

            String productId = getStringFromTag(tagMap, 'Product');
            String psmId = getStringFromTag(tagMap, 'ProductSellingModel');

            if (String.isNotBlank(productId)) {
                productIds.add(productId);
            }
            if (String.isNotBlank(psmId)) {
                psmIds.add(psmId);
            }

            eligibleItems.add(itemNode);
        }

        if (eligibleItems.isEmpty()) {
            earlyReturnMessage = 'No eligible line items (Has_Attribute_Adjustment__c = true)';
            return new ItemUpdateResult(null, 0, 0);
        }

        System.debug(LoggingLevel.INFO, 'Pass 1 complete: ' + eligibleItems.size() + ' eligible items, ' +
            productIds.size() + ' products, ' + psmIds.size() + ' PSMs');

        // ===== BULK SOQL: Query all matching tiers in one query =====
        List<Attribute_Tier_Pricing_Storage__c> allTiers = new List<Attribute_Tier_Pricing_Storage__c>();
        if (!productIds.isEmpty() && !psmIds.isEmpty()) {
            allTiers = [
                SELECT Id, Product__c, Product_Selling_Model__c,
                       Attribute_Name__c, Attribute_Value__c,
                       Lower_Bound__c, Upper_Bound__c,
                       Tier_Value__c, Multiplier__c, Price_Mode__c
                FROM Attribute_Tier_Pricing_Storage__c
                WHERE Product__c IN :productIds
                AND Product_Selling_Model__c IN :psmIds
            ];
        }

        System.debug(LoggingLevel.INFO, 'Bulk SOQL returned ' + allTiers.size() + ' tier records');

        if (allTiers.isEmpty()) {
            earlyReturnMessage = 'No matching Attribute_Tier_Pricing_Storage__c records found for eligible products';
            return new ItemUpdateResult(null, 0, 0);
        }

        // Build composite-key lookup map
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = buildTierLookupMap(allTiers);

        // ===== PASS 2: Process each eligible line item =====
        List<Map<String, Object>> itemNodeUpdates = new List<Map<String, Object>>();
        Integer processedCount = 0;
        Integer skippedCount = 0;

        for (Map<String, Object> itemNode : eligibleItems) {
            Map<String, Object> tagMap = (Map<String, Object>) itemNode.get('tagValue');

            String lineItemId = getLineItemIdFromDataPath(itemNode);
            List<Object> dataPath = (List<Object>) itemNode.get('dataPath');

            // Debug logging
            String productName = getStringFromTag(tagMap, 'Name');
            String productId = getStringFromTag(tagMap, 'Product');
            String psmId = getStringFromTag(tagMap, 'ProductSellingModel');
            Boolean isBundle = getBooleanFromTag(tagMap, 'HasBundleConfiguration');
            String bundleParentId = getStringFromTag(tagMap, 'BundleLineItemId');

            System.debug(LoggingLevel.INFO, '--- LINE ITEM: ' + lineItemId + ' ---');
            System.debug(LoggingLevel.INFO, 'Product: ' + productName + ' (Id: ' + productId + ')');
            System.debug(LoggingLevel.INFO, 'PSM: ' + psmId);
            System.debug(LoggingLevel.INFO, 'dataPath: ' + dataPath);
            System.debug(LoggingLevel.INFO, 'IsBundle: ' + isBundle + ', BundleParentId: ' + bundleParentId);

            if (String.isBlank(lineItemId)) {
                System.debug(LoggingLevel.WARN, 'SKIP: Could not determine line item ID from dataPath');
                skippedCount++;
                continue;
            }

            if (String.isBlank(productId) || String.isBlank(psmId)) {
                System.debug(LoggingLevel.WARN, 'SKIP: Missing Product or PSM context tag');
                skippedCount++;
                continue;
            }

            // Get attributes for this line item
            List<Map<String, Object>> lineAttributes = attributesByLineItem.get(lineItemId);
            System.debug(LoggingLevel.INFO, 'Attributes found: ' + (lineAttributes != null ? lineAttributes.size() : 0));

            if (lineAttributes == null || lineAttributes.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'SKIP: No attributes on line item');
                skippedCount++;
                continue;
            }

            // Get volume from Attribute_Volume attribute (entered by rep in Product Configurator)
            Decimal volume = getAttributeVolumeValue(lineAttributes);
            System.debug(LoggingLevel.INFO, 'Attribute_Volume: ' + volume);

            if (volume == null) {
                System.debug(LoggingLevel.INFO, 'RESET: Attribute_Volume not set — resetting to list price');
                Map<String, Object> resetUpdate = buildResetNodeUpdate(itemNode, tagMap);
                if (resetUpdate != null) {
                    itemNodeUpdates.add(resetUpdate);
                }
                skippedCount++;
                continue;
            }

            // Look up pricing tier from the bulk-loaded map
            PricingTierResult tierResult = lookupTierFromMap(tierMap, productId, psmId, lineAttributes, volume);
            if (tierResult == null) {
                System.debug(LoggingLevel.WARN, 'RESET: No matching tier for Product=' + productId +
                    ', PSM=' + psmId + ', Volume=' + volume + ' — resetting to list price');
                Map<String, Object> resetUpdate = buildResetNodeUpdate(itemNode, tagMap);
                if (resetUpdate != null) {
                    itemNodeUpdates.add(resetUpdate);
                }
                skippedCount++;
                continue;
            }

            System.debug(LoggingLevel.INFO, 'MATCH: Attr=' + tierResult.attributeName + ':' + tierResult.attributeValue +
                ', Volume=' + volume + ', PriceMode=' + tierResult.priceMode +
                ', BasePrice=' + tierResult.basePrice + ', Multiplier=' + tierResult.multiplier);

            // Build context update
            Map<String, Object> nodeUpdate = buildNodeUpdate(itemNode, tierResult, volume);
            if (nodeUpdate != null) {
                itemNodeUpdates.add(nodeUpdate);
                processedCount++;
            }
        }

        // Hand the assembled updates + counters back to the wrapper, which formats the empty-list
        // status string and performs the live context submit. Keeping submission out of this core
        // is what makes the Pass-1/Pass-2 build unit-testable without a live pricing context.
        return new ItemUpdateResult(itemNodeUpdates, processedCount, skippedCount);
    }

    /**
     * @description Build a composite-key lookup map from a list of tier records.
     *              Key format: ProductId|PSMId|AttributeName|AttributeValue
     *              Value: List of tier records (different volume ranges for same key)
     * @param tiers List of Attribute_Tier_Pricing_Storage__c records
     * @return Composite-key map for O(1) attribute lookups
     */
    @TestVisible
    private Map<String, List<Attribute_Tier_Pricing_Storage__c>> buildTierLookupMap(
        List<Attribute_Tier_Pricing_Storage__c> tiers
    ) {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = new Map<String, List<Attribute_Tier_Pricing_Storage__c>>();

        for (Attribute_Tier_Pricing_Storage__c tier : tiers) {
            String key = buildCompositeKey(tier.Product__c, tier.Product_Selling_Model__c,
                tier.Attribute_Name__c, tier.Attribute_Value__c);

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
    private String buildCompositeKey(String productId, String psmId, String attrName, String attrValue) {
        // Normalize attribute name: context uses underscores (Feature_Options),
        // tier data uses spaces (Feature Options) - standardize to underscores
        String normalizedName = attrName != null ? attrName.replaceAll(' ', '_') : attrName;
        return productId + '|' + psmId + '|' + normalizedName + '|' + attrValue;
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
    @TestVisible
    private PricingTierResult lookupTierFromMap(
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap,
        String productId,
        String psmId,
        List<Map<String, Object>> lineAttributes,
        Decimal volume
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

            String key = buildCompositeKey(productId, psmId, attrName, attrValue);
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
    @TestVisible
    private Map<String, Object> buildNodeUpdate(
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
    @TestVisible
    private Map<String, Object> buildResetNodeUpdate(Map<String, Object> itemNode, Map<String, Object> tagMap) {
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
     * @description Test-accessible wrapper that accepts Object and casts to PricingTierResult.
     *              Required because test classes cannot declare variables of a private inner class type.
     * @param tierResultObj The tier result as Object (must be PricingTierResult)
     * @param volume The attribute volume value
     * @return Human-readable explainer text
     */
    @TestVisible
    private String getExplainerTextForTest(Object tierResultObj, Decimal volume) {
        return buildAttributeExplainerText((PricingTierResult) tierResultObj, volume);
    }

    /**
     * @description Test-accessible wrapper that accepts the tier result as Object and casts to the
     *              private PricingTierResult inner type, then delegates to buildNodeUpdate(). Required
     *              because a test class in a different compilation unit cannot declare a variable of a
     *              private inner class type to pass as the typed parameter. Behavior is identical to
     *              calling buildNodeUpdate() directly.
     * @param itemNode The item node from context
     * @param tierResultObj The tier result as Object (must be PricingTierResult)
     * @param volume The attribute volume value
     * @return Node update map for Context API
     */
    @TestVisible
    private Map<String, Object> buildNodeUpdateForTest(Map<String, Object> itemNode, Object tierResultObj, Decimal volume) {
        return buildNodeUpdate(itemNode, (PricingTierResult) tierResultObj, volume);
    }

    /**
     * @description Build explainer text for pricing waterfall display
     * @param tierResult The pricing tier result (includes attribute name/value)
     * @param volume The attribute volume value
     * @return Human-readable explainer text
     */
    private String buildAttributeExplainerText(PricingTierResult tierResult, Decimal volume) {
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
     * @description Submit context updates via Context API
     * @param industriesContext The context service instance
     * @param contextId The context instance ID
     * @param itemNodeUpdates The list of updates to submit
     * @param processedCount Number of processed items
     * @param skippedCount Number of skipped items
     * @return Status message
     */
    @TestVisible
    private String submitContextUpdates(
        Context.IndustriesContext industriesContext,
        String contextId,
        List<Map<String, Object>> itemNodeUpdates,
        Integer processedCount,
        Integer skippedCount
    ) {
        Map<String, Object> updateInput = new Map<String, Object>{
            'contextId' => contextId,
            'nodePathAndAttributes' => itemNodeUpdates
        };

        try {
            Map<String, Object> updateResult = industriesContext.updateContextAttributes(updateInput);
            System.debug(LoggingLevel.INFO, 'Update result: ' + JSON.serializePretty(updateResult));
            return processedCount + ' items updated with pricing attributes via Context API (skipped=' + skippedCount + ')';
        } catch (Exception updateEx) {
            String errorMsg = updateEx.getMessage();
            if (errorMsg != null && errorMsg.containsIgnoreCase('not in updatable state')) {
                return 'Skipped - context not updatable (delete operation)';
            }
            System.debug(LoggingLevel.ERROR, 'Context update failed: ' + errorMsg);
            return 'Context update failed: ' + errorMsg;
        }
    }

    /**
     * @description Query line items from context
     * @param industriesContext The context service instance
     * @param contextId The context instance ID
     * @return List of line item data objects
     */
    @TestVisible
    private List<Object> queryLineItems(Context.IndustriesContext industriesContext, String contextId) {
        Map<String, Object> queryInput = new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{ 'SalesTransactionItem' }
        };

        // NOTE: this queryTags call is intentionally NOT wrapped in a try/catch -- the original
        // implementation let a failure here propagate to the caller (processAttributeVolumePricing,
        // whose only catch is execute()'s outer try/catch that sets the error message). That
        // propagation contract is preserved.
        Map<String, Object> queryOutput = industriesContext.queryTags(queryInput);
        Map<String, Object> queryResult = (Map<String, Object>) queryOutput.get('queryResult');

        if (queryResult == null) {
            return null;
        }
        return (List<Object>) queryResult.get('SalesTransactionItem');
    }

    /**
     * @description Query line item attributes from context
     * @param industriesContext The context service instance
     * @param contextId The context instance ID
     * @return Map of line item ID to list of attribute maps
     */
    @TestVisible
    private Map<String, List<Map<String, Object>>> queryLineItemAttributes(
        Context.IndustriesContext industriesContext,
        String contextId
    ) {
        Map<String, List<Map<String, Object>>> attributesByLineItem = new Map<String, List<Map<String, Object>>>();

        // NOTE: the live queryTags call below MUST stay inside this try/catch. The original behavior
        // swallows any queryTags failure and returns the (possibly empty) map built so far -- the
        // caller then proceeds with zero attributes (degrade gracefully). Only the parsing/grouping
        // is extractable; the grouping itself is exercised via groupAttributesByLineItem() with a
        // hand-built attributeData list, but the swallow-and-continue contract is preserved here.
        try {
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => contextId,
                'tags' => new List<String>{ 'SalesTransactionItemAttribute' }
            };

            Map<String, Object> queryOutput = industriesContext.queryTags(queryInput);
            Map<String, Object> queryResult = (Map<String, Object>) queryOutput.get('queryResult');

            if (queryResult == null) {
                return attributesByLineItem;
            }

            List<Object> attributeData = (List<Object>) queryResult.get('SalesTransactionItemAttribute');
            if (attributeData == null || attributeData.isEmpty()) {
                return attributesByLineItem;
            }

            groupAttributesByLineItem(attributeData, attributesByLineItem);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error querying line item attributes: ' + e.getMessage());
        }

        return attributesByLineItem;
    }

    /**
     * @description Group already-parsed attribute nodes by their parent line-item id. Reads
     *              ParentReference first, falling back to the dataPath parent segment. Pure of any
     *              live-context dependency, so it is unit-testable with hand-built attribute nodes;
     *              extracting it does not change queryLineItemAttributes() behavior.
     * @param attributeData Parsed SalesTransactionItemAttribute node list
     * @param attributesByLineItem Output map (mutated in place) of line-item id to attribute tag maps
     */
    @TestVisible
    private void groupAttributesByLineItem(
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
    @TestVisible
    private String getLineItemIdFromDataPath(Map<String, Object> itemNode) {
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
    @TestVisible
    private String getParentIdFromDataPath(Map<String, Object> attrNode) {
        List<Object> dataPath = (List<Object>) attrNode.get('dataPath');
        if (dataPath == null || dataPath.size() < 2) {
            return null;
        }
        // Parent line item ID is the second-to-last element for child nodes
        return String.valueOf(dataPath[dataPath.size() - 2]);
    }

    /**
     * @description Get attribute value by name from list of attributes
     * @param attributes List of attribute tag maps
     * @param attributeName The attribute name to find
     * @return The attribute value as string
     */
    /**
     * @description Extract the Attribute_Volume numeric value from line item attributes.
     *              Reads the string attribute value and parses to Decimal.
     * @param attributes List of attribute tag maps for the line item
     * @return The volume as Decimal, or null if not found or not parseable
     */
    @TestVisible
    private Decimal getAttributeVolumeValue(List<Map<String, Object>> attributes) {
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

    @TestVisible
    private String getAttributeValue(List<Map<String, Object>> attributes, String attributeName) {
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

    /**
     * @description Create a transaction response with the given status and message
     * @param status The transaction status
     * @param message The response message
     * @return Configured TransactionResponse
     */
    private RevSignaling.TransactionResponse createResponse(RevSignaling.TransactionStatus status, String message) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = status;
        response.message = message;
        return response;
    }

    // ========== Helper Methods for Tag Value Extraction ==========

    /**
     * @description Extract raw value from nested tag structure
     *              Handles both direct values and nested {tagValue: x} structures
     * @param tagMap The tag map to extract from
     * @param attributeName The attribute name to extract
     * @return The raw value or null
     */
    private Object getValueFromTag(Map<String, Object> tagMap, String attributeName) {
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
    private String getStringFromTag(Map<String, Object> tagMap, String attributeName) {
        Object value = getValueFromTag(tagMap, attributeName);
        return value != null ? String.valueOf(value) : null;
    }

    /**
     * @description Extract decimal value from nested tag structure
     */
    private Decimal getDecimalFromTag(Map<String, Object> tagMap, String attributeName) {
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
    @TestVisible
    private Boolean getBooleanFromTag(Map<String, Object> tagMap, String attributeName) {
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