/**
 * @description Apex Before Hook for Revenue Cloud pricing that applies hardware attribute-based
 *              pricing adjustments for Power products. Uses pGroup, Model, System Type, and
 *              Users Per Partition to calculate pricing multipliers.
 *
 *              Pricing Formula:
 *              Hardware_Price = List_Price × pGroup_Multiplier × UserCount_Multiplier × (1 - SystemType_Discount)
 *
 *              v3.0 Design - Override Priority:
 *              1. QuoteLineItemAttribute (user configured in Product Configurator)
 *              2. Hardware__c defaults (from linked Hardware record)
 *              3. System defaults (P20, Production, 1)
 *
 *              This allows users to override hardware defaults in the configurator while
 *              still using hardware values as fallback when attributes aren't configured.
 *
 *              Reads: ListPrice or UnitPrice, Hardware_Reference__c, SalesTransactionItemAttribute
 *              Writes: UnitPrice, Pre_Hardware_Price__c, Hardware_Price_Multiplier__c,
 *                      Hardware_Pricing_Applied__c, Hardware_Pricing_Detail__c,
 *                      pGroup_Applied__c, System_Type_Applied__c, Users_Per_Partition_Applied__c
 *
 * @author Marc DeBrey
 * @date January 2026
 *
 * @note Executes AFTER List Price lookup and BEFORE Regional/Partner Pricing in the waterfall.
 * @note Only applies to Power products or products with hardware linkage.
 *
 * @version 3.0 - Read QuoteLineItemAttribute for user overrides, fallback to Hardware__c
 */
global class HardwareAttributePricingPrehook implements RevSignaling.SignalingApexProcessor {

    // Default values when no matching attribute found
    private static final Decimal DEFAULT_MULTIPLIER = 1.0;
    private static final Decimal DEFAULT_DISCOUNT = 0.0;

    // System defaults when neither user config nor hardware provides values
    private static final String DEFAULT_PGROUP = 'P20';
    private static final String DEFAULT_SYSTEM_TYPE = 'Production';
    private static final Decimal DEFAULT_USERS = 1;

    // Attribute names as they appear in Product Configurator (SalesTransactionItemAttribute)
    // These match the AttributeDefinition.DeveloperName values
    private static final String ATTR_PGROUP = 'Pgroup';
    private static final String ATTR_SERVER_TYPE = 'Server_Type';
    private static final String ATTR_USERS = 'Users';

    // pGroup multiplier mappings (P05 through P60)
    private static final Map<String, Decimal> PGROUP_MULTIPLIERS = new Map<String, Decimal>{
        'P05' => 0.5,
        'P10' => 0.75,
        'P20' => 1.0,
        'P30' => 1.5,
        'P40' => 2.0,
        'P50' => 3.0,
        'P60' => 4.0
    };

    // User tier multiplier ranges
    private static final List<UserTierRange> USER_TIER_RANGES = new List<UserTierRange>{
        new UserTierRange(1, 10, 1.0),
        new UserTierRange(11, 50, 1.25),
        new UserTierRange(51, 100, 1.5),
        new UserTierRange(101, 250, 2.0),
        new UserTierRange(251, 500, 2.5),
        new UserTierRange(501, 999999, 3.0)
    };

    // System type discount mappings
    private static final Map<String, Decimal> SYSTEM_TYPE_DISCOUNTS = new Map<String, Decimal>{
        'Production' => 0.0,
        'Staging' => 25.0,
        'Test' => 50.0
    };

    /**
     * @description Inner class to represent user tier ranges
     */
    private class UserTierRange {
        public Integer minUsers;
        public Integer maxUsers;
        public Decimal multiplier;

        public UserTierRange(Integer min, Integer max, Decimal mult) {
            this.minUsers = min;
            this.maxUsers = max;
            this.multiplier = mult;
        }
    }

    /**
     * @description Inner class to hold hardware pricing calculation details
     *              v3.0: Added source tracking for each attribute
     */
    @TestVisible
    private class HardwarePricingDetail {
        public String pGroup;
        public String pGroupSource;
        public String model;
        public String systemType;
        public String systemTypeSource;
        public Integer usersPerPartition;
        public String usersSource;
        public String hardwareId;
        public Decimal pGroupMultiplier;
        public Decimal userTierMultiplier;
        public Decimal systemTypeDiscount;
        public Decimal combinedMultiplier;
        public Decimal listPrice;
        public Decimal hardwareAdjustedPrice;
        public String source;
        public Datetime pricingTimestamp;

        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'pricingTimestamp' => this.pricingTimestamp != null ? this.pricingTimestamp.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null,
                'hardwareId' => this.hardwareId,
                'version' => 'v3.0',
                'attributes' => new Map<String, Object>{
                    'pGroup' => new Map<String, Object>{
                        'value' => this.pGroup,
                        'source' => this.pGroupSource
                    },
                    'model' => this.model,
                    'systemType' => new Map<String, Object>{
                        'value' => this.systemType,
                        'source' => this.systemTypeSource
                    },
                    'usersPerPartition' => new Map<String, Object>{
                        'value' => this.usersPerPartition,
                        'source' => this.usersSource
                    }
                },
                'multipliers' => new Map<String, Object>{
                    'pGroupMultiplier' => this.pGroupMultiplier,
                    'userTierMultiplier' => this.userTierMultiplier,
                    'systemTypeDiscount' => this.systemTypeDiscount,
                    'combinedMultiplier' => this.combinedMultiplier
                },
                'priceCalculation' => new Map<String, Object>{
                    'listPrice' => this.listPrice,
                    'hardwareAdjustedPrice' => this.hardwareAdjustedPrice
                },
                'source' => this.source
            };
        }
    }

    /**
     * @description Execute method called by Revenue Cloud pricing orchestration
     * @param request The transaction request containing pricing context
     * @return TransactionResponse indicating success or failure
     */
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        System.debug(LoggingLevel.INFO, '==========================================================');
        System.debug(LoggingLevel.INFO, '=== HardwareAttributePricingPrehook v3.0 START ===');
        System.debug(LoggingLevel.INFO, '=== Priority: User Config > Hardware > System Default ===');
        System.debug(LoggingLevel.INFO, '==========================================================');

        String contextId = request.ctxInstanceId;
        System.debug(LoggingLevel.INFO, 'Context ID: ' + contextId);

        String message = '';
        Integer updatedCount = 0;

        try {
            // Create Context API instance
            Context.IndustriesContext industriesContext = new Context.IndustriesContext();

            // Query line items and process hardware pricing
            updatedCount = processLineItems(industriesContext, contextId);
            message = updatedCount + ' items updated with hardware attribute pricing';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            message = 'Hardware pricing completed with warnings: ' + e.getMessage();
        }

        System.debug(LoggingLevel.INFO, '=== HardwareAttributePricingPrehook v3.0 END ===');
        System.debug(LoggingLevel.INFO, 'Result: ' + message);

        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = RevSignaling.TransactionStatus.SUCCESS;
        response.message = message;
        return response;
    }

    /**
     * @description Process line items and apply hardware attribute pricing
     *              v3.0: Queries SalesTransactionItemAttribute for user overrides,
     *                    falls back to Hardware__c defaults, then system defaults
     * @param industriesContext Context API instance
     * @param contextId Context instance ID
     * @return Number of items updated
     */
    @TestVisible
    private Integer processLineItems(Context.IndustriesContext industriesContext, String contextId) {
        // Query for SalesTransactionItem (Quote Line Items)
        Map<String, Object> queryInput = new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{ 'SalesTransactionItem' }
        };

        Map<String, Object> queryOutput = industriesContext.queryTags(queryInput);

        // Handle nested response structure
        List<Object> rawLineItems = normalizeLineItems(queryOutput);
        if (rawLineItems == null) {
            return 0;
        }

        System.debug(LoggingLevel.INFO, 'Found ' + rawLineItems.size() + ' line items');

        // v3.0: Query configured attributes from SalesTransactionItemAttribute
        Map<String, Map<String, String>> configuredAttributesByLineItem = queryConfiguredAttributes(industriesContext, contextId);
        System.debug(LoggingLevel.INFO, 'Found configured attributes for ' + configuredAttributesByLineItem.size() + ' line items');

        // First pass - collect all Hardware IDs
        Set<Id> hardwareIds = collectHardwareIds(rawLineItems);

        // Query Hardware__c records for attribute values (fallback)
        Map<Id, Hardware__c> hardwareMap = queryHardwareRecords(hardwareIds);
        System.debug(LoggingLevel.INFO, 'Queried ' + hardwareMap.size() + ' Hardware__c records');

        // Second pass - process line items with override priority
        List<Map<String, Object>> itemNodeUpdates = buildItemUpdates(
            rawLineItems, configuredAttributesByLineItem, hardwareMap
        );

        // Submit context updates
        if (!itemNodeUpdates.isEmpty()) {
            submitContextUpdates(industriesContext, contextId, itemNodeUpdates);
        }

        return itemNodeUpdates.size();
    }

    /**
     * @description Normalize the queryTags response into a flat list of line-item nodes.
     *              Handles {queryResult:{SalesTransactionItem:[...]}}, {SalesTransactionItem:...},
     *              and the single-object-not-list shape. Returns null when no items are present
     *              (caller treats this as "0 items updated").
     * @param queryOutput Raw response map from queryTags
     * @return List of line-item node objects, or null if none found
     */
    @TestVisible
    private List<Object> normalizeLineItems(Map<String, Object> queryOutput) {
        Map<String, Object> queryResult;
        if (queryOutput.containsKey('queryResult')) {
            Object qrObj = queryOutput.get('queryResult');
            if (qrObj instanceof Map<String, Object>) {
                queryResult = (Map<String, Object>) qrObj;
            } else {
                System.debug(LoggingLevel.INFO, 'queryResult is not a Map');
                return null;
            }
        } else if (queryOutput.containsKey('SalesTransactionItem')) {
            queryResult = queryOutput;
        } else {
            System.debug(LoggingLevel.INFO, 'No SalesTransactionItem in response');
            return null;
        }

        if (!queryResult.containsKey('SalesTransactionItem')) {
            System.debug(LoggingLevel.INFO, 'No line items found');
            return null;
        }

        Object itemsObj = queryResult.get('SalesTransactionItem');
        List<Object> rawLineItems;
        if (itemsObj instanceof List<Object>) {
            rawLineItems = (List<Object>) itemsObj;
        } else {
            rawLineItems = new List<Object>{ itemsObj };
        }

        return rawLineItems;
    }

    /**
     * @description First pass - collect all Hardware__c IDs referenced by the line items.
     * @param rawLineItems Normalized list of line-item nodes
     * @return Set of Hardware__c record IDs
     */
    @TestVisible
    private Set<Id> collectHardwareIds(List<Object> rawLineItems) {
        Set<Id> hardwareIds = new Set<Id>();
        for (Object itemObj : rawLineItems) {
            Map<String, Object> itemNode = (Map<String, Object>) itemObj;
            Map<String, Object> tagMap;
            if (itemNode.containsKey('tagValue')) {
                tagMap = (Map<String, Object>) itemNode.get('tagValue');
            } else {
                tagMap = itemNode;
            }

            String hardwareIdStr = getStringFromTag(tagMap, 'Hardware_Id__c');
            if (String.isNotBlank(hardwareIdStr)) {
                try {
                    hardwareIds.add(Id.valueOf(hardwareIdStr));
                } catch (Exception e) {
                    System.debug(LoggingLevel.DEBUG, 'Invalid Hardware ID: ' + hardwareIdStr);
                }
            }
        }
        return hardwareIds;
    }

    /**
     * @description Second pass - process each line item with override priority and build the
     *              list of context node updates. Pure of any live-context dependency.
     * @param rawLineItems Normalized list of line-item nodes
     * @param configuredAttributesByLineItem Configured attributes keyed by line-item id
     * @param hardwareMap Map of Hardware__c records by ID (fallback values)
     * @return List of node-update maps (one per line item that produced an update)
     */
    @TestVisible
    private List<Map<String, Object>> buildItemUpdates(
        List<Object> rawLineItems,
        Map<String, Map<String, String>> configuredAttributesByLineItem,
        Map<Id, Hardware__c> hardwareMap
    ) {
        List<Map<String, Object>> itemNodeUpdates = new List<Map<String, Object>>();

        for (Object itemObj : rawLineItems) {
            Map<String, Object> itemNode = (Map<String, Object>) itemObj;

            // Extract tagValue and dataPath
            Map<String, Object> tagMap;
            List<Object> dataPath;

            if (itemNode.containsKey('tagValue')) {
                tagMap = (Map<String, Object>) itemNode.get('tagValue');
                dataPath = (List<Object>) itemNode.get('dataPath');
            } else {
                tagMap = itemNode;
                dataPath = new List<Object>();
            }

            // Get line item ID for attribute lookup
            String lineItemId = getLineItemIdFromDataPath(dataPath);

            // Get configured attributes for this line (may be empty)
            Map<String, String> lineConfiguredAttrs = configuredAttributesByLineItem.get(lineItemId);
            if (lineConfiguredAttrs == null) {
                lineConfiguredAttrs = new Map<String, String>();
            }

            // Process the line item with override priority
            Map<String, Object> fieldUpdate = processLineItem(tagMap, dataPath, hardwareMap, lineConfiguredAttrs);
            if (fieldUpdate != null) {
                itemNodeUpdates.add(fieldUpdate);
            }
        }

        return itemNodeUpdates;
    }

    /**
     * @description Extract line item ID from dataPath
     * @param dataPath The dataPath list from context
     * @return Line item ID or null
     */
    private String getLineItemIdFromDataPath(List<Object> dataPath) {
        if (dataPath == null || dataPath.isEmpty()) {
            return null;
        }
        // Line item ID is typically the last element
        return String.valueOf(dataPath[dataPath.size() - 1]);
    }

    /**
     * @description Query configured attributes from SalesTransactionItemAttribute
     *              Returns a map of lineItemId -> (attributeName -> attributeValue)
     * @param industriesContext Context API instance
     * @param contextId Context instance ID
     * @return Map of configured attributes by line item
     */
    private Map<String, Map<String, String>> queryConfiguredAttributes(
        Context.IndustriesContext industriesContext,
        String contextId
    ) {
        // The live queryTags call (and the parse delegation) must stay inside this try/catch so that
        // any failure swallows-and-continues with an empty map, letting processLineItems fall back to
        // Hardware/system-default pricing rather than aborting the whole interaction in execute().
        try {
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => contextId,
                'tags' => new List<String>{ 'SalesTransactionItemAttribute' }
            };

            Map<String, Object> queryOutput = industriesContext.queryTags(queryInput);
            return parseConfiguredAttributes(queryOutput);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error querying configured attributes: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return new Map<String, Map<String, String>>();
        }
    }

    /**
     * @description Parse the queryTags response for SalesTransactionItemAttribute into a map of
     *              lineItemId -> (attributeName -> attributeValue). Split from queryConfiguredAttributes
     *              so the parse logic can be unit-tested with a hand-built response map (the live
     *              queryTags call cannot be exercised in a unit test).
     * @param queryOutput Raw response map from queryTags
     * @return Map of configured attributes by line item
     */
    @TestVisible
    private Map<String, Map<String, String>> parseConfiguredAttributes(Map<String, Object> queryOutput) {
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();

        try {
            // Defensive null check for queryOutput
            if (queryOutput == null) {
                System.debug(LoggingLevel.INFO, 'queryTags returned null for SalesTransactionItemAttribute');
                return result;
            }

            // Try to get queryResult - may be nested or direct
            Map<String, Object> queryResult = null;
            if (queryOutput.containsKey('queryResult')) {
                Object qrObj = queryOutput.get('queryResult');
                if (qrObj instanceof Map<String, Object>) {
                    queryResult = (Map<String, Object>) qrObj;
                }
            } else if (queryOutput.containsKey('SalesTransactionItemAttribute')) {
                // Direct response without queryResult wrapper
                queryResult = queryOutput;
            }

            if (queryResult == null) {
                System.debug(LoggingLevel.INFO, 'No queryResult for SalesTransactionItemAttribute');
                return result;
            }

            Object attrObj = queryResult.get('SalesTransactionItemAttribute');
            if (attrObj == null) {
                System.debug(LoggingLevel.INFO, 'No SalesTransactionItemAttribute in result');
                return result;
            }

            List<Object> attributeData;
            if (attrObj instanceof List<Object>) {
                attributeData = (List<Object>) attrObj;
            } else {
                attributeData = new List<Object>{ attrObj };
            }

            System.debug(LoggingLevel.INFO, 'Processing ' + attributeData.size() + ' attribute records');

            for (Object attr : attributeData) {
                if (attr == null || !(attr instanceof Map<String, Object>)) {
                    continue;
                }

                Map<String, Object> attrNode = (Map<String, Object>) attr;
                Map<String, Object> tagMap = null;
                List<Object> dataPath = null;

                if (attrNode.containsKey('tagValue')) {
                    Object tvObj = attrNode.get('tagValue');
                    if (tvObj instanceof Map<String, Object>) {
                        tagMap = (Map<String, Object>) tvObj;
                    }
                    Object dpObj = attrNode.get('dataPath');
                    if (dpObj instanceof List<Object>) {
                        dataPath = (List<Object>) dpObj;
                    }
                } else {
                    tagMap = attrNode;
                    dataPath = new List<Object>();
                }

                if (tagMap == null) {
                    continue;
                }

                // Get parent line item ID from ParentReference or dataPath
                String parentLineItemId = getStringFromTag(tagMap, 'ParentReference');
                if (String.isBlank(parentLineItemId) && dataPath != null && dataPath.size() >= 2) {
                    // Parent ID is second-to-last element in dataPath
                    parentLineItemId = String.valueOf(dataPath[dataPath.size() - 2]);
                }

                if (String.isBlank(parentLineItemId)) {
                    continue;
                }

                // Get attribute name and value
                String attrName = getStringFromTag(tagMap, 'Attribute');
                if (String.isBlank(attrName)) {
                    attrName = getStringFromTag(tagMap, 'AttributeKeyName');
                }
                String attrValue = getStringFromTag(tagMap, 'AttributeValue');

                if (String.isNotBlank(attrName) && String.isNotBlank(attrValue)) {
                    if (!result.containsKey(parentLineItemId)) {
                        result.put(parentLineItemId, new Map<String, String>());
                    }
                    result.get(parentLineItemId).put(attrName, attrValue);

                    System.debug(LoggingLevel.DEBUG, 'Attribute: ' + parentLineItemId + ' -> ' + attrName + ' = ' + attrValue);
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error querying configured attributes: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * @description Query Hardware__c records for attribute values
     * @param hardwareIds Set of Hardware__c record IDs
     * @return Map of Hardware__c records by ID
     */
    @TestVisible
    private Map<Id, Hardware__c> queryHardwareRecords(Set<Id> hardwareIds) {
        if (hardwareIds.isEmpty()) {
            return new Map<Id, Hardware__c>();
        }

        List<Hardware__c> hardwareRecords = [
            SELECT Id,
                   Name,
                   P_Group_List__c,
                   Server_Type__c,
                   Users_Per_Partition__c,
                   Model_Number__c
            FROM Hardware__c
            WHERE Id IN :hardwareIds
        ];

        return new Map<Id, Hardware__c>(hardwareRecords);
    }

    /**
     * @description Process a single line item and calculate hardware pricing
     *              v3.0: Priority - User Configured > Hardware Default > System Default
     * @param tagMap Line item data from context
     * @param dataPath Path for context update
     * @param hardwareMap Map of Hardware__c records by ID
     * @param configuredAttrs User-configured attributes from SalesTransactionItemAttribute
     * @return Map of field updates or null if not applicable
     */
    @TestVisible
    private Map<String, Object> processLineItem(
        Map<String, Object> tagMap,
        List<Object> dataPath,
        Map<Id, Hardware__c> hardwareMap,
        Map<String, String> configuredAttrs
    ) {
        // Get Hardware ID from context (this is a lookup field value)
        String hardwareIdStr = getStringFromTag(tagMap, 'Hardware_Id__c');
        String productId = getStringFromTag(tagMap, 'ProductId');

        // Check if hardware pricing should apply (need either hardware link or configured attributes)
        if (String.isBlank(hardwareIdStr) && (configuredAttrs == null || configuredAttrs.isEmpty())) {
            System.debug(LoggingLevel.INFO, 'Product ' + productId + ': No hardware linkage and no configured attributes - skipping');
            return null;
        }

        // Get Hardware__c record if available (for fallback values)
        Hardware__c hardware = null;
        Id hardwareId = null;
        if (String.isNotBlank(hardwareIdStr)) {
            try {
                hardwareId = Id.valueOf(hardwareIdStr);
                hardware = hardwareMap.get(hardwareId);
            } catch (Exception e) {
                System.debug(LoggingLevel.DEBUG, 'Invalid Hardware ID: ' + hardwareIdStr);
            }
        }

        // v3.0: Apply override priority for each attribute
        // Priority: User Configured > Hardware Default > System Default
        String pGroup;
        String pGroupSource;
        String systemType;
        String systemTypeSource;
        Decimal usersPerPartition;
        String usersSource;

        // pGroup: Check configured, then hardware, then system default
        String configuredPGroup = configuredAttrs != null ? configuredAttrs.get(ATTR_PGROUP) : null;
        if (String.isNotBlank(configuredPGroup)) {
            pGroup = configuredPGroup;
            pGroupSource = 'User Override';
        } else if (hardware != null && String.isNotBlank(hardware.P_Group_List__c)) {
            pGroup = hardware.P_Group_List__c;
            pGroupSource = 'Hardware Default';
        } else {
            pGroup = DEFAULT_PGROUP;
            pGroupSource = 'System Default';
        }

        // Server Type: Check configured, then hardware, then system default
        String configuredServerType = configuredAttrs != null ? configuredAttrs.get(ATTR_SERVER_TYPE) : null;
        if (String.isNotBlank(configuredServerType)) {
            systemType = configuredServerType;
            systemTypeSource = 'User Override';
        } else if (hardware != null && String.isNotBlank(hardware.Server_Type__c)) {
            systemType = hardware.Server_Type__c;
            systemTypeSource = 'Hardware Default';
        } else {
            systemType = DEFAULT_SYSTEM_TYPE;
            systemTypeSource = 'System Default';
        }

        // Users Per Partition: Check configured, then hardware, then system default
        String configuredUsers = configuredAttrs != null ? configuredAttrs.get(ATTR_USERS) : null;
        if (String.isNotBlank(configuredUsers)) {
            try {
                usersPerPartition = Decimal.valueOf(configuredUsers);
                usersSource = 'User Override';
            } catch (Exception e) {
                usersPerPartition = DEFAULT_USERS;
                usersSource = 'System Default (parse error)';
            }
        } else if (hardware != null && hardware.Users_Per_Partition__c != null) {
            usersPerPartition = hardware.Users_Per_Partition__c;
            usersSource = 'Hardware Default';
        } else {
            usersPerPartition = DEFAULT_USERS;
            usersSource = 'System Default';
        }

        String model = hardware != null ? hardware.Model_Number__c : null;

        System.debug(LoggingLevel.INFO, '--- Processing Product ' + productId + ' ---');
        System.debug(LoggingLevel.INFO, '  pGroup: ' + pGroup + ' (' + pGroupSource + ')');
        System.debug(LoggingLevel.INFO, '  Server Type: ' + systemType + ' (' + systemTypeSource + ')');
        System.debug(LoggingLevel.INFO, '  Users: ' + usersPerPartition + ' (' + usersSource + ')');
        if (hardware != null) {
            System.debug(LoggingLevel.INFO, '  Hardware: ' + hardware.Name);
        }

        // Get current price from context
        Decimal listPrice = getDecimalFromTag(tagMap, 'ListPrice');
        Decimal unitPrice = getDecimalFromTag(tagMap, 'UnitPrice');
        Decimal currentPrice = listPrice != null ? listPrice : unitPrice;

        if (currentPrice == null || currentPrice <= 0) {
            System.debug(LoggingLevel.INFO, 'Product ' + productId + ': No valid price - skipping');
            return null;
        }

        System.debug(LoggingLevel.INFO, '  Price: ' + currentPrice);

        // Calculate multipliers
        Decimal pGroupMultiplier = getPGroupMultiplier(pGroup);
        Decimal userTierMultiplier = getUserTierMultiplier(usersPerPartition);
        Decimal systemTypeDiscount = getSystemTypeDiscount(systemType);

        // Calculate combined multiplier and adjusted price
        // Formula: ListPrice × pGroupMult × userTierMult × (1 - systemTypeDiscount/100)
        Decimal combinedMultiplier = pGroupMultiplier * userTierMultiplier * (1 - systemTypeDiscount / 100);
        Decimal adjustedPrice = currentPrice * combinedMultiplier;

        // Round to 2 decimal places
        adjustedPrice = adjustedPrice.setScale(2, System.RoundingMode.HALF_UP);

        System.debug(LoggingLevel.INFO, '  pGroup Multiplier: ' + pGroupMultiplier);
        System.debug(LoggingLevel.INFO, '  User Tier Multiplier: ' + userTierMultiplier);
        System.debug(LoggingLevel.INFO, '  System Type Discount: ' + systemTypeDiscount + '%');
        System.debug(LoggingLevel.INFO, '  Combined Multiplier: ' + combinedMultiplier);
        System.debug(LoggingLevel.INFO, '  Adjusted Price: ' + adjustedPrice);

        // Build audit trail with v3.0 source tracking
        HardwarePricingDetail detail = new HardwarePricingDetail();
        detail.pGroup = pGroup;
        detail.pGroupSource = pGroupSource;
        detail.model = model;
        detail.systemType = systemType;
        detail.systemTypeSource = systemTypeSource;
        detail.usersPerPartition = usersPerPartition != null ? usersPerPartition.intValue() : null;
        detail.usersSource = usersSource;
        detail.hardwareId = hardwareId != null ? String.valueOf(hardwareId) : null;
        detail.pGroupMultiplier = pGroupMultiplier;
        detail.userTierMultiplier = userTierMultiplier;
        detail.systemTypeDiscount = systemTypeDiscount;
        detail.combinedMultiplier = combinedMultiplier;
        detail.listPrice = currentPrice;
        detail.hardwareAdjustedPrice = adjustedPrice;
        detail.source = 'Pre-Hook v3.0';
        detail.pricingTimestamp = Datetime.now();

        // Build update path (dataPath minus first element)
        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }

        // Build attributes for context update
        List<Object> attributes = new List<Object>();

        // UnitPrice - the adjusted price for downstream pricing steps
        attributes.add(new Map<String, Object>{
            'attributeName' => 'UnitPrice',
            'attributeValue' => adjustedPrice
        });

        // Pre_Hardware_Price__c - capture original price
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Pre_Hardware_Price__c',
            'attributeValue' => currentPrice
        });

        // Hardware_Price_Multiplier__c - combined multiplier
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Hardware_Price_Multiplier__c',
            'attributeValue' => combinedMultiplier
        });

        // Hardware_Pricing_Applied__c - flag
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Hardware_Pricing_Applied__c',
            'attributeValue' => true
        });

        // Hardware_Pricing_Source__c - dominant source (User Override > Hardware Default > System Default)
        String dominantSource = 'System Default';
        if (pGroupSource == 'User Override' || systemTypeSource == 'User Override' || usersSource == 'User Override') {
            dominantSource = 'User Override';
        } else if (pGroupSource == 'Hardware Default' || systemTypeSource == 'Hardware Default' || usersSource == 'Hardware Default') {
            dominantSource = 'Hardware Default';
        }
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Hardware_Pricing_Source__c',
            'attributeValue' => dominantSource
        });

        // pGroup_Applied__c - pGroup value used
        attributes.add(new Map<String, Object>{
            'attributeName' => 'pGroup_Applied__c',
            'attributeValue' => pGroup
        });

        // System_Type_Applied__c - system type value used
        attributes.add(new Map<String, Object>{
            'attributeName' => 'System_Type_Applied__c',
            'attributeValue' => systemType
        });

        // Users_Per_Partition_Applied__c - user count used
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Users_Per_Partition_Applied__c',
            'attributeValue' => usersPerPartition
        });

        // Hardware_Pricing_Detail__c - JSON audit trail
        attributes.add(new Map<String, Object>{
            'attributeName' => 'Hardware_Pricing_Detail__c',
            'attributeValue' => JSON.serialize(detail.toMap())
        });

        // === Pricing Procedure Waterfall Visibility Tags ===

        // HardwareCalculatedPrice__c - calculated price for Assignment element
        // This is the primary value consumed by the Pricing Procedure Assignment element
        attributes.add(new Map<String, Object>{
            'attributeName' => 'HardwareCalculatedPrice__c',
            'attributeValue' => adjustedPrice
        });

        // HardwarePricingExplainer__c - human-readable text for waterfall display
        // Shows in Calculation Details when shouldShowExplExternally=true
        String explainerText = buildHardwareExplainerText(pGroup, systemType, usersPerPartition, combinedMultiplier);
        attributes.add(new Map<String, Object>{
            'attributeName' => 'HardwarePricingExplainer__c',
            'attributeValue' => explainerText
        });

        // Build node update
        Map<String, Object> nodeUpdate = new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };

        return nodeUpdate;
    }

    /**
     * @description Get pGroup multiplier from static map
     * @param pGroup The pGroup value (e.g., 'P30')
     * @return Multiplier value or default 1.0
     */
    @TestVisible
    public Decimal getPGroupMultiplier(String pGroup) {
        if (String.isBlank(pGroup)) {
            return DEFAULT_MULTIPLIER;
        }
        return PGROUP_MULTIPLIERS.containsKey(pGroup) ? PGROUP_MULTIPLIERS.get(pGroup) : DEFAULT_MULTIPLIER;
    }

    /**
     * @description Get user tier multiplier based on user count
     * @param usersPerPartition Number of users
     * @return Multiplier value or default 1.0
     */
    @TestVisible
    public Decimal getUserTierMultiplier(Decimal usersPerPartition) {
        if (usersPerPartition == null || usersPerPartition <= 0) {
            return DEFAULT_MULTIPLIER;
        }

        Integer users = usersPerPartition.intValue();
        for (UserTierRange range : USER_TIER_RANGES) {
            if (users >= range.minUsers && users <= range.maxUsers) {
                return range.multiplier;
            }
        }

        return DEFAULT_MULTIPLIER;
    }

    /**
     * @description Get system type discount percentage
     * @param systemType The system type (Production, Staging, Test)
     * @return Discount percentage or default 0
     */
    @TestVisible
    public Decimal getSystemTypeDiscount(String systemType) {
        if (String.isBlank(systemType)) {
            return DEFAULT_DISCOUNT;
        }
        return SYSTEM_TYPE_DISCOUNTS.containsKey(systemType) ? SYSTEM_TYPE_DISCOUNTS.get(systemType) : DEFAULT_DISCOUNT;
    }

    /**
     * @description Submit context attribute updates
     * @param ctx Context API instance
     * @param contextId Context instance ID
     * @param itemUpdates List of item updates
     */
    @TestVisible
    private void submitContextUpdates(
        Context.IndustriesContext ctx,
        String contextId,
        List<Map<String, Object>> itemUpdates
    ) {
        try {
            Map<String, Object> updateInput = new Map<String, Object>{
                'contextId' => contextId,
                'nodePathAndAttributes' => itemUpdates
            };

            System.debug(LoggingLevel.INFO, 'Submitting ' + itemUpdates.size() + ' context updates');
            Map<String, Object> updateResult = ctx.updateContextAttributes(updateInput);
            System.debug(LoggingLevel.INFO, 'Update result: ' + JSON.serializePretty(updateResult));

        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().containsIgnoreCase('not in updatable state')) {
                System.debug(LoggingLevel.INFO, 'Context not in updatable state - skipping updates');
            } else {
                System.debug(LoggingLevel.ERROR, 'Error updating context: ' + e.getMessage());
            }
        }
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

    /**
     * @description Build human-readable explainer text for pricing waterfall display
     * @param pGroup The hardware group (e.g., 'P30', 'P60')
     * @param systemType The system type (Production, Staging, Test)
     * @param usersPerPartition Number of users per partition
     * @param combinedMultiplier The combined multiplier applied
     * @return Formatted explainer string for Calculation Details
     */
    @TestVisible
    private String buildHardwareExplainerText(
        String pGroup,
        String systemType,
        Decimal usersPerPartition,
        Decimal combinedMultiplier
    ) {
        List<String> parts = new List<String>();

        // Add pGroup if present
        if (String.isNotBlank(pGroup)) {
            parts.add('Group: ' + pGroup);
        }

        // Add system type if not Production (default)
        if (String.isNotBlank(systemType) && systemType != 'Production') {
            parts.add('System: ' + systemType);
        }

        // Add users per partition
        if (usersPerPartition != null && usersPerPartition > 0) {
            parts.add(usersPerPartition.setScale(0).intValue() + ' Users');
        }

        // Add multiplier if not 1.0
        if (combinedMultiplier != null && combinedMultiplier != 1.0) {
            parts.add('Mult: ' + combinedMultiplier.setScale(2));
        }

        // Build final string
        if (parts.isEmpty()) {
            return 'Hardware Attribute Pricing Applied';
        }

        return 'Hardware: ' + String.join(parts, ', ');
    }
}