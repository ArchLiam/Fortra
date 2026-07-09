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
 * @version 3.1
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
 *
 * WAVE-2 DECOMPOSITION (behavior-preserving, round 2): all PURE attribute-volume tier-pricing
 * math + context-node shaping was extracted VERBATIM into AttributeVolumeCalculator (composite-key
 * tier map, volume->tier resolution, matched/reset node updates, explainer, attribute reads, tag
 * helpers). This class remains the thin adapter — it owns the two queryTags reads, the bulk
 * Attribute_Tier_Pricing_Storage__c SOQL, the Pass-1/Pass-2 orchestration, and the context submit,
 * and delegates the pure seams to the calculator. Every @TestVisible seam below keeps its original
 * signature so AttributeVolumePricingPrehookTest is unaffected. The SC-3390 / D-17 silent
 * reset-to-list behavior is preserved EXACTLY (the reset trigger stays in the Pass-2 loop; the reset
 * payload is AttributeVolumeCalculator.buildResetNodeUpdate — moved unchanged, NOT fixed).
 */
global class AttributeVolumePricingPrehook implements RevSignaling.SignalingApexProcessor {

    // Static flag to prevent recursive execution
    private static Boolean isUpdating = false;

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
            // D-18: surface the swallowed degrade (fire-and-forget; never throws; status unchanged).
            PricingHookLogger.logPrehook('AttributeVolumePricingPrehook', contextId, e);
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
     * @description Two-pass build over ALREADY-PARSED line-item + attribute data. Performs the
     *              eligibility filter (Has_Attribute_Adjustment__c), the bulk Attribute_Tier_Pricing_Storage__c
     *              SOQL (the one seam that MUST stay in the hook), the composite-key map build, and
     *              Pass-2 per-item tier lookup / reset, returning the assembled node-update list and
     *              processed/skipped counters. The pure sub-steps (tag reads, tier map, volume->tier
     *              lookup, matched/reset node shaping) delegate to AttributeVolumeCalculator, so this
     *              stays the thin SOQL+orchestration seam. When an early-return short-circuit applies
     *              (no eligible items, no tiers) it returns a result whose itemNodeUpdates is null and
     *              sets earlyReturnMessage to the original string.
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
        Set<String> currencies = new Set<String>();   // SC-3384: line currencies to scope the tier query per currency
        List<Map<String, Object>> eligibleItems = new List<Map<String, Object>>();

        for (Object itemObj : lineItemData) {
            Map<String, Object> itemNode = (Map<String, Object>) itemObj;
            Map<String, Object> tagMap = (Map<String, Object>) itemNode.get('tagValue');

            Boolean hasAttributeAdjustment = AttributeVolumeCalculator.getBooleanFromTag(tagMap, 'Has_Attribute_Adjustment__c');
            if (hasAttributeAdjustment != true) {
                continue;
            }

            String productId = AttributeVolumeCalculator.getStringFromTag(tagMap, 'Product');
            String psmId = AttributeVolumeCalculator.getStringFromTag(tagMap, 'ProductSellingModel');

            if (String.isNotBlank(productId)) {
                productIds.add(productId);
            }
            if (String.isNotBlank(psmId)) {
                psmIds.add(psmId);
            }
            // SC-3384: capture the line currency (STICurrencyIsoCode item tag) so the bulk query only loads
            // tier rows matching the quote's currency(ies) -- previously all currencies loaded and a EUR/GBP
            // line matched USD tier rows.
            String itemCurrency = AttributeVolumeCalculator.getStringFromTag(tagMap, 'STICurrencyIsoCode');
            if (String.isNotBlank(itemCurrency)) {
                currencies.add(itemCurrency);
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
                    Tier_Value__c, Multiplier__c, Price_Mode__c, CurrencyIsoCode
                FROM Attribute_Tier_Pricing_Storage__c
                WHERE Product__c IN :productIds
                AND Product_Selling_Model__c IN :psmIds
                AND CurrencyIsoCode IN :currencies
            ];
        }

        System.debug(LoggingLevel.INFO, 'Bulk SOQL returned ' + allTiers.size() + ' tier records');

        if (allTiers.isEmpty()) {
            earlyReturnMessage = 'No matching Attribute_Tier_Pricing_Storage__c records found for eligible products';
            return new ItemUpdateResult(null, 0, 0);
        }

        // Build composite-key lookup map
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(allTiers);

        // ===== PASS 2: Process each eligible line item =====
        List<Map<String, Object>> itemNodeUpdates = new List<Map<String, Object>>();
        Integer processedCount = 0;
        Integer skippedCount = 0;

        for (Map<String, Object> itemNode : eligibleItems) {
            Map<String, Object> tagMap = (Map<String, Object>) itemNode.get('tagValue');

            String lineItemId = AttributeVolumeCalculator.getLineItemIdFromDataPath(itemNode);
            List<Object> dataPath = (List<Object>) itemNode.get('dataPath');

            // Debug logging
            String productName = AttributeVolumeCalculator.getStringFromTag(tagMap, 'Name');
            String productId = AttributeVolumeCalculator.getStringFromTag(tagMap, 'Product');
            String psmId = AttributeVolumeCalculator.getStringFromTag(tagMap, 'ProductSellingModel');
            Boolean isBundle = AttributeVolumeCalculator.getBooleanFromTag(tagMap, 'HasBundleConfiguration');
            String bundleParentId = AttributeVolumeCalculator.getStringFromTag(tagMap, 'BundleLineItemId');

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
            Decimal volume = AttributeVolumeCalculator.getAttributeVolumeValue(lineAttributes);
            System.debug(LoggingLevel.INFO, 'Attribute_Volume: ' + volume);

            if (volume == null) {
                System.debug(LoggingLevel.INFO, 'RESET: Attribute_Volume not set — resetting to list price');
                Map<String, Object> resetUpdate = AttributeVolumeCalculator.buildResetNodeUpdate(itemNode, tagMap);
                if (resetUpdate != null) {
                    itemNodeUpdates.add(resetUpdate);
                }
                skippedCount++;
                continue;
            }

            // Look up pricing tier from the bulk-loaded map (SC-3384: scoped to the line's currency)
            String lineCurrency = AttributeVolumeCalculator.getStringFromTag(tagMap, 'STICurrencyIsoCode');
            AttributeVolumeCalculator.PricingTierResult tierResult = AttributeVolumeCalculator.lookupTierFromMap(tierMap, productId, psmId, lineAttributes, volume, lineCurrency);
            if (tierResult == null) {
                System.debug(LoggingLevel.WARN, 'RESET: No matching tier for Product=' + productId +
                    ', PSM=' + psmId + ', Volume=' + volume + ' — resetting to list price');
                Map<String, Object> resetUpdate = AttributeVolumeCalculator.buildResetNodeUpdate(itemNode, tagMap);
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
            Map<String, Object> nodeUpdate = AttributeVolumeCalculator.buildNodeUpdate(itemNode, tierResult, volume);
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
        // is extractable; the grouping itself is exercised via AttributeVolumeCalculator.groupAttributesByLineItem()
        // with a hand-built attributeData list, but the swallow-and-continue contract is preserved here.
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

            AttributeVolumeCalculator.groupAttributesByLineItem(attributeData, attributesByLineItem);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error querying line item attributes: ' + e.getMessage());
        }

        return attributesByLineItem;
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

    // ============================================================
    // DELEGATING SEAMS — thin adapters over AttributeVolumeCalculator.
    // Signatures + @TestVisible preserved verbatim so call sites (incl. the hook's own test) are
    // unchanged; all real math/lookup/shaping logic lives in the calculator.
    // ============================================================

    @TestVisible
    private Map<String, List<Attribute_Tier_Pricing_Storage__c>> buildTierLookupMap(
        List<Attribute_Tier_Pricing_Storage__c> tiers
    ) {
        return AttributeVolumeCalculator.buildTierLookupMap(tiers);
    }

    @TestVisible
    private AttributeVolumeCalculator.PricingTierResult lookupTierFromMap(
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap,
        String productId,
        String psmId,
        List<Map<String, Object>> lineAttributes,
        Decimal volume,
        String currencyIso
    ) {
        return AttributeVolumeCalculator.lookupTierFromMap(tierMap, productId, psmId, lineAttributes, volume, currencyIso);
    }

    @TestVisible
    private Map<String, Object> buildResetNodeUpdate(Map<String, Object> itemNode, Map<String, Object> tagMap) {
        return AttributeVolumeCalculator.buildResetNodeUpdate(itemNode, tagMap);
    }

    /**
     * @description Test-accessible wrapper that accepts the tier result as Object and casts to the
     *              PricingTierResult type, then delegates to the calculator's explainer. Required
     *              because a test class in a different compilation unit cannot declare a variable of a
     *              private inner class type. Behavior is identical to calling the calculator directly.
     * @param tierResultObj The tier result as Object (must be AttributeVolumeCalculator.PricingTierResult)
     * @param volume The attribute volume value
     * @return Human-readable explainer text
     */
    @TestVisible
    private String getExplainerTextForTest(Object tierResultObj, Decimal volume) {
        return AttributeVolumeCalculator.buildAttributeExplainerText(
            (AttributeVolumeCalculator.PricingTierResult) tierResultObj, volume);
    }

    /**
     * @description Test-accessible wrapper that accepts the tier result as Object and casts to the
     *              PricingTierResult type, then delegates to the calculator's buildNodeUpdate().
     *              Required because a test class in a different compilation unit cannot declare a
     *              variable of a private inner class type to pass as the typed parameter.
     * @param itemNode The item node from context
     * @param tierResultObj The tier result as Object (must be AttributeVolumeCalculator.PricingTierResult)
     * @param volume The attribute volume value
     * @return Node update map for Context API
     */
    @TestVisible
    private Map<String, Object> buildNodeUpdateForTest(Map<String, Object> itemNode, Object tierResultObj, Decimal volume) {
        return AttributeVolumeCalculator.buildNodeUpdate(
            itemNode, (AttributeVolumeCalculator.PricingTierResult) tierResultObj, volume);
    }

    @TestVisible
    private void groupAttributesByLineItem(
        List<Object> attributeData,
        Map<String, List<Map<String, Object>>> attributesByLineItem
    ) {
        AttributeVolumeCalculator.groupAttributesByLineItem(attributeData, attributesByLineItem);
    }

    @TestVisible
    private String getLineItemIdFromDataPath(Map<String, Object> itemNode) {
        return AttributeVolumeCalculator.getLineItemIdFromDataPath(itemNode);
    }

    @TestVisible
    private String getParentIdFromDataPath(Map<String, Object> attrNode) {
        return AttributeVolumeCalculator.getParentIdFromDataPath(attrNode);
    }

    @TestVisible
    private Decimal getAttributeVolumeValue(List<Map<String, Object>> attributes) {
        return AttributeVolumeCalculator.getAttributeVolumeValue(attributes);
    }

    @TestVisible
    private String getAttributeValue(List<Map<String, Object>> attributes, String attributeName) {
        return AttributeVolumeCalculator.getAttributeValue(attributes, attributeName);
    }

    @TestVisible
    private Boolean getBooleanFromTag(Map<String, Object> tagMap, String attributeName) {
        return AttributeVolumeCalculator.getBooleanFromTag(tagMap, attributeName);
    }
}
