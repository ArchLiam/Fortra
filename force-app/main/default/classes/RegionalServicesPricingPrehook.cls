/**
 * @description Apex Hook for Revenue Cloud pricing that applies regional
 *              pricing adjustments based on country multipliers.
 *
 *              Reads: ListPrice or UnitPrice from context
 *              Writes: UnitPrice (regional-adjusted base price)
 *                      RegionalNetUnitPrice__c (audit field for TLE display)
 *
 * @author Marc DeBrey
 * @date January 2026
 *
 * @version 13.3 - Independent hook (no direct dependencies on other hooks)
 */
global class RegionalServicesPricingPrehook implements RevSignaling.SignalingApexProcessor {

    // Recursion guard (normalized to the other prehooks): prevents re-entrant execution.
    private static Boolean isProcessing = false;

    // Default multiplier when no matching regional pricing found
    private static final Decimal DEFAULT_MULTIPLIER = 1.0;

    /**
     * @description Execute method called by Revenue Cloud pricing orchestration
     * @param request The transaction request containing pricing context
     * @return TransactionResponse indicating success or failure
     */
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        System.debug(LoggingLevel.INFO, '==========================================================');
        System.debug(LoggingLevel.INFO, '=== RegionalServicesPricingPrehook v13.3 START ===');
        System.debug(LoggingLevel.INFO, '=== Applies regional pricing multipliers ===');
        System.debug(LoggingLevel.INFO, '==========================================================');

        String contextId = request.ctxInstanceId;
        System.debug(LoggingLevel.INFO, 'Context ID: ' + contextId);

        String message = '';
        Integer updatedCount = 0;

        // Skip on re-entry so a context write that re-triggers pricing cannot recurse.
        if (isProcessing) {
            RevSignaling.TransactionResponse skip = new RevSignaling.TransactionResponse();
            skip.status = RevSignaling.TransactionStatus.SUCCESS;
            skip.message = 'Regional pricing skipped (re-entrant call)';
            return skip;
        }
        isProcessing = true;

        try {
            // Step 1: Load regional pricing multipliers from Custom Metadata
            Map<String, Decimal> countryMultipliers = loadRegionalPricingMultipliers();
            System.debug(LoggingLevel.INFO, 'Loaded ' + countryMultipliers.size() + ' regional pricing records');

            if (countryMultipliers.isEmpty()) {
                message = 'No regional pricing multipliers configured';
            } else {
                // Step 2: Create Context API instance
                Context.IndustriesContext industriesContext = new Context.IndustriesContext();

                // Step 3: Query for SalesTransaction (Quote header) to get country
                String country = getShippingCountry(industriesContext, contextId);
                System.debug(LoggingLevel.INFO, 'Shipping country: ' + country);

                if (String.isBlank(country)) {
                    message = 'No shipping country found';
                } else {
                    // Step 4: Get multiplier for country
                    Decimal multiplier = getMultiplierForCountry(countryMultipliers, country);
                    System.debug(LoggingLevel.INFO, 'Multiplier for ' + country + ': ' + multiplier);

                    if (multiplier == DEFAULT_MULTIPLIER) {
                        message = 'Country ' + country + ' uses default multiplier (1.0)';
                    } else {
                        // Step 5: Query line items and apply regional pricing
                        updatedCount = processLineItems(industriesContext, contextId, multiplier, country);
                        message = updatedCount + ' items updated with regional pricing (multiplier=' + multiplier + ')';
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            message = 'Error: ' + e.getMessage();
            // D-18: surface the swallowed degrade (fire-and-forget; never throws; status unchanged).
            PricingHookLogger.logPrehook('RegionalServicesPricingPrehook', contextId, e);
        } finally {
            isProcessing = false;
        }

        System.debug(LoggingLevel.INFO, '=== RegionalServicesPricingPrehook v13.3 END ===');
        System.debug(LoggingLevel.INFO, 'Result: ' + message);

        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = RevSignaling.TransactionStatus.SUCCESS;
        response.message = message;
        return response;
    }

    /**
     * @description Load regional pricing multipliers from Custom Metadata Type
     * @return Map of country name/code to multiplier
     */
    public Map<String, Decimal> loadRegionalPricingMultipliers() {
        Map<String, Decimal> multipliers = new Map<String, Decimal>();

        // SDD Rule 14 / BR-007: honor effective dating in ADDITION to Is_Active__c ("Only load ACTIVE
        // multipliers" + "Support effective dating"). CMDT SOQL rejects OR disjunctions, so the
        // null-safe start/end window is evaluated in memory via RegionalPricingCalculator.isEffectiveOn
        // (this also keeps the date rule unit-testable — __mdt rows cannot be inserted in a test).
        // Rows with null start AND null end have no time bound and always load (prior behavior).
        Date today = Date.today();

        for (Services_Regional_Pricing__mdt record : [
            SELECT Country__c, Country_Code__c, Multiplier__c,
                Effective_Start_Date__c, Effective_End_Date__c
            FROM Services_Regional_Pricing__mdt
            WHERE Is_Active__c = true
        ]) {
            if (!RegionalPricingCalculator.isEffectiveOn(record.Effective_Start_Date__c, record.Effective_End_Date__c, today)) {
                continue;
            }
            if (record.Country__c != null) {
                multipliers.put(record.Country__c, record.Multiplier__c);
            }
            if (record.Country_Code__c != null) {
                multipliers.put(record.Country_Code__c, record.Multiplier__c);
            }
        }

        return multipliers;
    }

    // Wave-2: implementation moved to RegionalPricingCalculator; thin wrapper preserves the existing test API.
    public Decimal getMultiplierForCountry(Map<String, Decimal> multipliers, String country) {
        return RegionalPricingCalculator.getMultiplierForCountry(multipliers, country);
    }

    /**
     * @description Get shipping country from SalesTransaction context
     * @param industriesContext Context API instance
     * @param contextId Context instance ID
     * @return Country name or null
     */
    @TestVisible
    private String getShippingCountry(Context.IndustriesContext industriesContext, String contextId) {
        // NOTE: the live queryTags call MUST stay inside this try/catch. The original behavior
        // swallows any queryTags failure and returns null (callers then short-circuit to
        // "No shipping country found"). The parse logic is extracted to parseShippingCountry()
        // so it can be unit-tested with a hand-built response, but the swallow-and-continue
        // contract is preserved byte-for-byte.
        try {
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => contextId,
                'tags' => new List<String>{ 'SalesTransaction' }
            };

            Map<String, Object> queryOutput = industriesContext.queryTags(queryInput);
            return parseShippingCountry(queryOutput);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting shipping country: ' + e.getMessage());
        }
        return null;
    }

    /**
     * @description Parse the shipping country out of a queryTags(SalesTransaction) response.
     *              Tries ShipToPlace_Country__c first, then falls back to ShippingCountry.
     * @param queryOutput Raw response map from queryTags
     * @return Country name or null
     */
    @TestVisible
    private String parseShippingCountry(Map<String, Object> queryOutput) {
        Map<String, Object> queryResult = (Map<String, Object>) queryOutput.get('queryResult');

        if (queryResult != null) {
            List<Object> transactionData = (List<Object>) queryResult.get('SalesTransaction');
            if (transactionData != null && !transactionData.isEmpty()) {
                Map<String, Object> transNode = (Map<String, Object>) transactionData[0];
                Map<String, Object> tagMap = (Map<String, Object>) transNode.get('tagValue');

                // Try ShipToPlace_Country__c first
                String country = getStringFromTag(tagMap, 'ShipToPlace_Country__c');
                if (String.isNotBlank(country)) {
                    return country;
                }

                // Fall back to ShippingCountry
                return getStringFromTag(tagMap, 'ShippingCountry');
            }
        }
        return null;
    }

    /**
     * @description Process line items and write regional price to context
     * @param industriesContext Context API instance
     * @param contextId Context instance ID
     * @param multiplier Regional pricing multiplier
     * @param country The shipping country for explainer text
     * @return Number of items updated
     */
    @TestVisible
    private Integer processLineItems(Context.IndustriesContext industriesContext, String contextId, Decimal multiplier, String country) {
        // Query for SalesTransactionItem (Quote Line Items)
        Map<String, Object> queryInput = new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{ 'SalesTransactionItem' }
        };

        // NOTE: this queryTags call is intentionally NOT wrapped in a try/catch -- the original
        // implementation let a queryTags failure propagate up to execute()'s outer try/catch
        // (which sets message = 'Error: ...'). That behavior is preserved: only the parse +
        // build loop is extracted to buildItemUpdates(), and the submit retains its own
        // try/catch in submitContextUpdates().
        Map<String, Object> queryOutput = industriesContext.queryTags(queryInput);
        Map<String, Object> queryResult = (Map<String, Object>) queryOutput.get('queryResult');

        if (queryResult == null) {
            System.debug(LoggingLevel.INFO, 'No queryResult in response');
            return 0;
        }

        List<Object> lineItemData = (List<Object>) queryResult.get('SalesTransactionItem');
        if (lineItemData == null || lineItemData.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'No line items found');
            return 0;
        }

        System.debug(LoggingLevel.INFO, 'Found ' + lineItemData.size() + ' line items');

        List<Map<String, Object>> itemNodeUpdates = buildItemUpdates(lineItemData, multiplier, country);

        // Submit context update
        if (!itemNodeUpdates.isEmpty()) {
            submitContextUpdates(industriesContext, contextId, itemNodeUpdates);
        }

        return itemNodeUpdates.size();
    }

    /**
     * @description Build the list of context node updates for a list of already-parsed line-item
     *              nodes. Pure of any live-context dependency, so it can be unit-tested with
     *              hand-built {tagValue, dataPath} maps. Lines with no valid price (null or <= 0)
     *              are skipped. For each kept line a node update is built via buildNodeUpdate().
     * @param lineItemData Parsed SalesTransactionItem node list (each a {tagValue, dataPath} map)
     * @param multiplier Regional pricing multiplier
     * @param country The shipping country for explainer text
     * @return List of node-update maps (one per line item that produced an update)
     */
    @TestVisible
    private List<Map<String, Object>> buildItemUpdates(List<Object> lineItemData, Decimal multiplier, String country) {
        List<Map<String, Object>> itemNodeUpdates = new List<Map<String, Object>>();

        for (Object itemObj : lineItemData) {
            Map<String, Object> itemNode = (Map<String, Object>) itemObj;
            List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
            Map<String, Object> tagMap = (Map<String, Object>) itemNode.get('tagValue');

            // Get current price (ListPrice or UnitPrice)
            Decimal listPrice = getDecimalFromTag(tagMap, 'ListPrice');
            Decimal unitPrice = getDecimalFromTag(tagMap, 'UnitPrice');
            Decimal currentPrice = listPrice != null ? listPrice : unitPrice;

            String productId = getStringFromTag(tagMap, 'ProductId');
            System.debug(LoggingLevel.INFO, 'Item: ProductId=' + productId + ', Price=' + currentPrice);

            if (currentPrice == null || currentPrice <= 0) {
                System.debug(LoggingLevel.INFO, '  Skipping - no valid price');
                continue;
            }

            itemNodeUpdates.add(buildNodeUpdate(dataPath, currentPrice, multiplier, country));
        }

        return itemNodeUpdates;
    }

    /**
     * @description Build a single context node-update map for one priced line item.
     *              Clones dataPath and drops its first element (the context-root segment) so the
     *              update path is relative; an empty dataPath is left empty (no remove).
     * @param dataPath The line-item node's dataPath
     * @param currentPrice Resolved pre-regional price (ListPrice or UnitPrice)
     * @param multiplier Regional pricing multiplier
     * @param country The shipping country for explainer text
     * @return Node-update map with nodePath + attributes
     */
    @TestVisible
    private Map<String, Object> buildNodeUpdate(List<Object> dataPath, Decimal currentPrice, Decimal multiplier, String country) {
        // Calculate regional price
        Decimal regionalPrice = calculateAdjustedPrice(currentPrice, multiplier);
        System.debug(LoggingLevel.INFO, '  Regional price: ' + currentPrice + ' x ' + multiplier + ' = ' + regionalPrice);

        // Build update path
        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }

        // Create attribute updates for context
        List<Object> attributes = new List<Object>();

        // UnitPrice - regional-adjusted base price
        // Available to subsequent pricing steps in the waterfall
        attributes.add(new Map<String, Object>{
            'attributeName' => 'UnitPrice',
            'attributeValue' => regionalPrice
        });

        // RegionalNetUnitPrice__c - audit field for TLE display
        attributes.add(new Map<String, Object>{
            'attributeName' => 'RegionalNetUnitPrice__c',
            'attributeValue' => regionalPrice
        });

        // === Pricing Procedure Waterfall Visibility Tags ===

        // PrehookRSNetUnitPrice__c - calculated price for Assignment element
        attributes.add(new Map<String, Object>{
            'attributeName' => 'PrehookRSNetUnitPrice__c',
            'attributeValue' => regionalPrice
        });

        // RegionalPricingExplainer__c - human-readable text for waterfall display
        String explainerText = 'Regional Services Multiplier: ' + multiplier.setScale(2) + ' (' + country + ')';
        attributes.add(new Map<String, Object>{
            'attributeName' => 'RegionalPricingExplainer__c',
            'attributeValue' => explainerText
        });

        // RegionalPricingApplied__c - flag for conditional Assignment element
        attributes.add(new Map<String, Object>{
            'attributeName' => 'RegionalPricingApplied__c',
            'attributeValue' => true
        });

        // Pre_Regional_Price__c - original price before regional adjustment
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Pre_Regional_Price__c',
            'attributeValue' => currentPrice
        });

        // Regional_Multiplier__c - the multiplier applied
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Regional_Multiplier__c',
            'attributeValue' => multiplier
        });

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    /**
     * @description Submit context attribute updates. Preserves the original swallow contract:
     *              a "not in updatable state" failure is swallowed (degrade gracefully); any
     *              other failure is re-thrown so execute()'s outer try/catch reports it.
     * @param industriesContext Context API instance
     * @param contextId Context instance ID
     * @param itemNodeUpdates List of node-update maps to submit
     */
    @TestVisible
    private void submitContextUpdates(Context.IndustriesContext industriesContext, String contextId, List<Map<String, Object>> itemNodeUpdates) {
        System.debug(LoggingLevel.INFO, 'Submitting ' + itemNodeUpdates.size() + ' updates');

        Map<String, Object> updateInput = new Map<String, Object>{
            'contextId' => contextId,
            'nodePathAndAttributes' => itemNodeUpdates
        };

        try {
            Map<String, Object> updateResult = industriesContext.updateContextAttributes(updateInput);
            System.debug(LoggingLevel.INFO, 'Update result: ' + JSON.serializePretty(updateResult));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Update error: ' + e.getMessage());
            if (!e.getMessage().containsIgnoreCase('not in updatable state')) {
                throw e;
            }
        }
    }

    // Wave-2: implementation moved to RegionalPricingCalculator; thin wrapper preserves the existing test API.
    public Decimal calculateAdjustedPrice(Decimal listPrice, Decimal multiplier) {
        return RegionalPricingCalculator.calculateAdjustedPrice(listPrice, multiplier);
    }

    /**
     * @description Extract string value from tag map
     */
    @TestVisible
    private String getStringFromTag(Map<String, Object> tagMap, String attributeName) {
        if (tagMap == null || !tagMap.containsKey(attributeName)) {
            return null;
        }

        Object attrObj = tagMap.get(attributeName);

        if (attrObj instanceof Map<String, Object>) {
            Map<String, Object> attrMap = (Map<String, Object>) attrObj;
            if (attrMap.containsKey('tagValue')) {
                Object value = attrMap.get('tagValue');
                return value != null ? String.valueOf(value) : null;
            }
        }

        return attrObj != null ? String.valueOf(attrObj) : null;
    }

    /**
     * @description Extract decimal value from tag map
     */
    @TestVisible
    private Decimal getDecimalFromTag(Map<String, Object> tagMap, String attributeName) {
        if (tagMap == null || !tagMap.containsKey(attributeName)) {
            return null;
        }

        try {
            Object attrObj = tagMap.get(attributeName);

            if (attrObj instanceof Map<String, Object>) {
                Map<String, Object> attrMap = (Map<String, Object>) attrObj;
                if (attrMap.containsKey('tagValue')) {
                    Object value = attrMap.get('tagValue');
                    if (value != null) {
                        return Decimal.valueOf(String.valueOf(value));
                    }
                }
            }

            if (attrObj != null) {
                return Decimal.valueOf(String.valueOf(attrObj));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.DEBUG, 'Could not parse decimal: ' + e.getMessage());
        }

        return null;
    }
}