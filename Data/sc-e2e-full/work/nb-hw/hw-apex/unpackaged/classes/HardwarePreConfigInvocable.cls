/**
 * @description Invocable action to query Hardware__c attributes for pre-configuration display.
 *              Used by flows and LWCs to show hardware defaults before/during product configuration.
 *
 * Architecture Notes:
 * - Revenue Cloud's Product Configurator reads static defaults from AttributeDefinition
 * - This class queries Hardware__c to provide dynamic defaults based on selected hardware
 * - The configurator displays these as recommended values; users can override
 * - Actual pricing uses: QuoteLineItemAttribute > Hardware__c > System Default (prehook v3.0)
 *
 * Value Format Mapping:
 * - Hardware__c.P_Group_List__c uses P05, P10, P20, etc.
 * - AttributeDefinition.PGroup uses P5, P10, P20, etc.
 * - This class normalizes P05 → P5 for configurator compatibility
 *
 * @author Marc DeBrey
 * @version 1.1
 * @since 2026-01
 */
public with sharing class HardwarePreConfigInvocable {

    /**
     * @description Input wrapper for the invocable action
     */
    public class HardwareAttributeRequest {
        @InvocableVariable(label='Quote ID' description='The Quote record ID')
        public Id quoteId;

        @InvocableVariable(label='Quote Line Group ID' description='The QuoteLineGroup record ID')
        public Id quoteLineGroupId;

        @InvocableVariable(label='Hardware ID' description='Direct Hardware__c record ID (optional)')
        public Id hardwareId;
    }

    /**
     * @description Output wrapper containing hardware attributes
     */
    public class HardwareAttributeResult {
        @InvocableVariable(label='Success' description='Whether attributes were successfully retrieved')
        public Boolean success;

        @InvocableVariable(label='Error Message' description='Error message if retrieval failed')
        public String errorMessage;

        @InvocableVariable(label='Hardware ID' description='The Hardware__c record ID')
        public Id hardwareId;

        @InvocableVariable(label='Hardware Name' description='The Hardware__c record name')
        public String hardwareName;

        @InvocableVariable(label='PGroup Value' description='The pGroup value (normalized for configurator)')
        public String pGroupValue;

        @InvocableVariable(label='PGroup Raw Value' description='The raw pGroup value from Hardware__c')
        public String pGroupRawValue;

        @InvocableVariable(label='Server Type' description='The server type value')
        public String serverType;

        @InvocableVariable(label='Users Per Partition' description='The users per partition value')
        public Decimal usersPerPartition;

        @InvocableVariable(label='Has Hardware' description='Whether hardware was found')
        public Boolean hasHardware;

        @InvocableVariable(label='Hardware Display Text' description='Formatted display text for UI')
        public String hardwareDisplayText;

        @InvocableVariable(label='JSON Context' description='JSON-formatted context for advanced usage')
        public String jsonContext;
    }

    /**
     * @description Main invocable method to retrieve hardware attributes
     * @param requests List of attribute requests
     * @return List of attribute results
     */
    @InvocableMethod(
        label='Get Hardware Attributes for Configuration'
        description='Retrieves hardware attributes (pGroup, Server Type, Users Per Partition) for product configuration defaults'
        category='Hardware Configuration'
    )
    public static List<HardwareAttributeResult> getHardwareAttributes(List<HardwareAttributeRequest> requests) {
        List<HardwareAttributeResult> results = new List<HardwareAttributeResult>();

        for (HardwareAttributeRequest request : requests) {
            results.add(processRequest(request));
        }

        return results;
    }

    /**
     * @description Process a single hardware attribute request
     * @param request The input request
     * @return The attribute result
     */
    private static HardwareAttributeResult processRequest(HardwareAttributeRequest request) {
        HardwareAttributeResult result = new HardwareAttributeResult();
        result.success = false;
        result.hasHardware = false;

        try {
            Id targetHardwareId = resolveHardwareId(request);

            if (targetHardwareId == null) {
                result.success = true;
                result.hasHardware = false;
                result.hardwareDisplayText = 'No hardware selected';
                result.jsonContext = buildJsonContext(null, null, null, null, null);
                return result;
            }

            Hardware__c hardware = queryHardware(targetHardwareId);

            if (hardware == null) {
                result.success = true;
                result.hasHardware = false;
                result.hardwareDisplayText = 'Hardware record not found';
                result.jsonContext = buildJsonContext(null, null, null, null, null);
                return result;
            }

            result.success = true;
            result.hasHardware = true;
            result.hardwareId = hardware.Id;
            result.hardwareName = hardware.Name;
            result.pGroupRawValue = hardware.P_Group_List__c;
            result.pGroupValue = normalizePGroupValue(hardware.P_Group_List__c);
            result.serverType = hardware.Server_Type__c;
            result.usersPerPartition = hardware.Users_Per_Partition__c;
            result.hardwareDisplayText = buildDisplayText(hardware);
            result.jsonContext = buildJsonContext(
                hardware.Id,
                result.pGroupValue,
                hardware.Server_Type__c,
                hardware.Users_Per_Partition__c,
                hardware.Name
            );

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error retrieving hardware attributes: ' + e.getMessage();
            result.hasHardware = false;
        }

        return result;
    }

    /**
     * @description Resolve the Hardware__c ID from various input sources
     * @param request The input request with potential ID sources
     * @return The resolved Hardware__c ID, or null if not found
     */
    private static Id resolveHardwareId(HardwareAttributeRequest request) {
        // Priority 1: Direct hardware ID
        if (request.hardwareId != null) {
            return request.hardwareId;
        }

        // Priority 2: From QuoteLineGroup
        if (request.quoteLineGroupId != null) {
            List<QuoteLineGroup> groups = [
                SELECT Hardware__c
                FROM QuoteLineGroup
                WHERE Id = :request.quoteLineGroupId
                LIMIT 1
            ];
            if (!groups.isEmpty() && groups[0].Hardware__c != null) {
                return groups[0].Hardware__c;
            }
        }

        // Priority 3: From Quote (find first group with hardware)
        if (request.quoteId != null) {
            List<QuoteLineGroup> groups = [
                SELECT Hardware__c
                FROM QuoteLineGroup
                WHERE QuoteId = :request.quoteId
                AND Hardware__c != NULL
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!groups.isEmpty()) {
                return groups[0].Hardware__c;
            }
        }

        return null;
    }

    /**
     * @description Query the Hardware__c record with required fields
     * @param hardwareId The Hardware__c record ID
     * @return The Hardware__c record, or null if not found
     */
    private static Hardware__c queryHardware(Id hardwareId) {
        List<Hardware__c> hardwareList = [
            SELECT Id, Name, P_Group_List__c, Server_Type__c, Users_Per_Partition__c
            FROM Hardware__c
            WHERE Id = :hardwareId
            LIMIT 1
        ];

        return hardwareList.isEmpty() ? null : hardwareList[0];
    }

    /**
     * @description Normalize pGroup value from Hardware__c format to AttributeDefinition format
     *              Hardware__c uses P05, P10, etc. AttributeDefinition uses P5, P10, etc.
     * @param rawValue The raw pGroup value from Hardware__c
     * @return The normalized value for configurator compatibility
     */
    @TestVisible
    private static String normalizePGroupValue(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }

        // Convert P05 → P5 format (AttributeDefinition uses P5, not P05)
        if (rawValue == 'P05') {
            return 'P5';
        }

        return rawValue;
    }

    /**
     * @description Build formatted display text for UI presentation
     * @param hardware The Hardware__c record
     * @return Formatted display string
     */
    private static String buildDisplayText(Hardware__c hardware) {
        List<String> parts = new List<String>();

        if (String.isNotBlank(hardware.P_Group_List__c)) {
            parts.add('pGroup: ' + hardware.P_Group_List__c);
        }
        if (String.isNotBlank(hardware.Server_Type__c)) {
            parts.add('Type: ' + hardware.Server_Type__c);
        }
        if (hardware.Users_Per_Partition__c != null) {
            parts.add('Users: ' + hardware.Users_Per_Partition__c.intValue());
        }

        return parts.isEmpty() ? 'No attributes defined' : String.join(parts, ' | ');
    }

    /**
     * @description Build JSON context for advanced component usage
     * @param hardwareId The hardware record ID
     * @param pGroup The normalized pGroup value
     * @param serverType The server type value
     * @param usersPerPartition The users per partition value
     * @param hardwareName The hardware name
     * @return JSON string with hardware context
     */
    private static String buildJsonContext(Id hardwareId, String pGroup, String serverType, Decimal usersPerPartition, String hardwareName) {
        Map<String, Object> context = new Map<String, Object>{
            'hasHardware' => hardwareId != null,
            'hardwareId' => hardwareId,
            'hardwareName' => hardwareName,
            'hardwareDefaults' => new Map<String, Object>{
                'pGroup' => pGroup,
                'serverType' => serverType,
                'usersPerPartition' => usersPerPartition
            },
            'showWarningsOnChange' => true,
            'timestamp' => System.now().getTime()
        };

        return JSON.serialize(context);
    }

    /**
     * @description LWC-callable method to get hardware attributes directly
     *              For use in hardwareGroupManager and similar components
     * @param quoteLineGroupId The QuoteLineGroup ID
     * @return Map of hardware attributes
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getHardwareAttributesForLWC(Id quoteLineGroupId) {
        HardwareAttributeRequest request = new HardwareAttributeRequest();
        request.quoteLineGroupId = quoteLineGroupId;

        HardwareAttributeResult result = processRequest(request);

        Map<String, Object> response = new Map<String, Object>{
            'success' => result.success,
            'hasHardware' => result.hasHardware,
            'hardwareId' => result.hardwareId,
            'hardwareName' => result.hardwareName,
            'pGroupValue' => result.pGroupValue,
            'pGroupRawValue' => result.pGroupRawValue,
            'serverType' => result.serverType,
            'usersPerPartition' => result.usersPerPartition,
            'displayText' => result.hardwareDisplayText,
            'errorMessage' => result.errorMessage
        };

        return response;
    }

    /**
     * @description LWC-callable method to get hardware attributes by Quote ID
     * @param quoteId The Quote ID
     * @return Map of hardware attributes from the first group with hardware
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getHardwareAttributesForQuote(Id quoteId) {
        HardwareAttributeRequest request = new HardwareAttributeRequest();
        request.quoteId = quoteId;

        HardwareAttributeResult result = processRequest(request);

        Map<String, Object> response = new Map<String, Object>{
            'success' => result.success,
            'hasHardware' => result.hasHardware,
            'hardwareId' => result.hardwareId,
            'hardwareName' => result.hardwareName,
            'pGroupValue' => result.pGroupValue,
            'pGroupRawValue' => result.pGroupRawValue,
            'serverType' => result.serverType,
            'usersPerPartition' => result.usersPerPartition,
            'displayText' => result.hardwareDisplayText,
            'errorMessage' => result.errorMessage
        };

        return response;
    }

    /**
     * @description Check if a product is applicable for hardware pricing
     *              Hardware pricing only applies to products in the Tech catalog / Power category
     *              This checks both direct category assignment and parent category hierarchy
     * @param productId The Product2 ID being configured
     * @return Map with 'isApplicable' boolean and category/catalog details
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> isProductHardwarePricingApplicable(Id productId) {
        Map<String, Object> response = new Map<String, Object>{
            'isApplicable' => false,
            'catalogName' => null,
            'categoryName' => null,
            'parentCategoryName' => null,
            'reason' => null
        };

        if (productId == null) {
            response.put('reason', 'No product ID provided');
            return response;
        }

        try {
            // Query ProductCategoryProduct with parent category info
            List<ProductCategoryProduct> categoryProducts = [
                SELECT Id,
                       ProductCategory.Id,
                       ProductCategory.Name,
                       ProductCategory.ParentCategoryId,
                       ProductCategory.ParentCategory.Name,
                       ProductCategory.CatalogId,
                       ProductCategory.Catalog.Name
                FROM ProductCategoryProduct
                WHERE ProductId = :productId
                LIMIT 20
            ];

            if (categoryProducts.isEmpty()) {
                response.put('reason', 'Product not assigned to any category');
                return response;
            }

            // Collect category IDs to potentially check higher levels of hierarchy
            Set<Id> categoryIdsToCheck = new Set<Id>();
            Map<Id, ProductCategoryProduct> pcpByCategoryId = new Map<Id, ProductCategoryProduct>();

            for (ProductCategoryProduct pcp : categoryProducts) {
                categoryIdsToCheck.add(pcp.ProductCategory.Id);
                pcpByCategoryId.put(pcp.ProductCategory.Id, pcp);
            }

            // Check each category assignment for Tech catalog + Power category (or child of Power)
            for (ProductCategoryProduct pcp : categoryProducts) {
                String catalogName = pcp.ProductCategory.Catalog?.Name;
                String categoryName = pcp.ProductCategory?.Name;
                String parentCategoryName = pcp.ProductCategory.ParentCategory?.Name;

                // Store first found catalog/category for debugging
                if (response.get('catalogName') == null) {
                    response.put('catalogName', catalogName);
                    response.put('categoryName', categoryName);
                    response.put('parentCategoryName', parentCategoryName);
                }

                // Check for Tech catalog (case-insensitive)
                Boolean isTechCatalog = String.isNotBlank(catalogName) &&
                                        catalogName.toLowerCase().contains('tech');

                if (!isTechCatalog) {
                    continue; // Skip non-Tech catalog categories
                }

                // Check if direct category is Power or parent category is Power
                Boolean isPowerCategory = String.isNotBlank(categoryName) &&
                                          categoryName.equalsIgnoreCase('power');
                Boolean isChildOfPower = String.isNotBlank(parentCategoryName) &&
                                         parentCategoryName.equalsIgnoreCase('power');

                if (isPowerCategory || isChildOfPower) {
                    response.put('isApplicable', true);
                    response.put('catalogName', catalogName);
                    response.put('categoryName', categoryName);
                    response.put('parentCategoryName', parentCategoryName);
                    String reason = isPowerCategory
                        ? 'Product is in Tech catalog / Power category'
                        : 'Product is in Tech catalog / ' + categoryName + ' (child of Power)';
                    response.put('reason', reason);
                    return response;
                }
            }

            // If not found at first level, check grandparent level (Power -> Cybersecurity -> Powertech*)
            // Query parent categories to check if they have Power as grandparent
            Set<Id> parentCategoryIds = new Set<Id>();
            for (ProductCategoryProduct pcp : categoryProducts) {
                if (pcp.ProductCategory.ParentCategoryId != null) {
                    parentCategoryIds.add(pcp.ProductCategory.ParentCategoryId);
                }
            }

            if (!parentCategoryIds.isEmpty()) {
                List<ProductCategory> parentCategories = [
                    SELECT Id, Name, ParentCategoryId, ParentCategory.Name, Catalog.Name
                    FROM ProductCategory
                    WHERE Id IN :parentCategoryIds
                ];

                for (ProductCategory pc : parentCategories) {
                    String catalogName = pc.Catalog?.Name;
                    String grandparentName = pc.ParentCategory?.Name;

                    Boolean isTechCatalog = String.isNotBlank(catalogName) &&
                                            catalogName.toLowerCase().contains('tech');
                    Boolean isGrandchildOfPower = String.isNotBlank(grandparentName) &&
                                                  grandparentName.equalsIgnoreCase('power');

                    if (isTechCatalog && isGrandchildOfPower) {
                        // Find the original category name
                        String originalCategoryName = null;
                        for (ProductCategoryProduct pcp : categoryProducts) {
                            if (pcp.ProductCategory.ParentCategoryId == pc.Id) {
                                originalCategoryName = pcp.ProductCategory.Name;
                                break;
                            }
                        }

                        response.put('isApplicable', true);
                        response.put('catalogName', catalogName);
                        response.put('categoryName', originalCategoryName);
                        response.put('parentCategoryName', pc.Name);
                        response.put('reason', 'Product is in Tech catalog / ' + originalCategoryName +
                            ' (grandchild of Power via ' + pc.Name + ')');
                        return response;
                    }
                }
            }

            // Not found in Tech/Power hierarchy
            response.put('reason', 'Product is not in Tech catalog / Power category hierarchy');
            return response;

        } catch (Exception e) {
            response.put('reason', 'Error checking product category: ' + e.getMessage());
            return response;
        }
    }

    /**
     * @description Get which hardware-related attributes are applicable for a product
     *              Queries ProductAttributeDefinition → AttributeDefinition
     *              to determine which of our target attributes (PGroup, Server_Type, Users) exist
     * @param productId The Product2 ID being configured
     * @return Map with boolean flags for each attribute and list of all attribute names
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getProductApplicableAttributes(Id productId) {
        Map<String, Object> response = new Map<String, Object>{
            'success' => false,
            'hasPGroup' => false,
            'hasServerType' => false,
            'hasUsers' => false,
            'attributeCount' => 0,
            'allAttributeNames' => new List<String>(),
            'errorMessage' => null
        };

        if (productId == null) {
            response.put('errorMessage', 'No product ID provided');
            return response;
        }

        try {
            // Query ProductAttributeDefinition which links Product2 to AttributeDefinition
            // Product2Id references the product
            // AttributeDefinitionId references the attribute definition with DeveloperName
            List<ProductAttributeDefinition> productAttrs = [
                SELECT Id, Name,
                       AttributeDefinitionId,
                       AttributeDefinition.DeveloperName,
                       AttributeDefinition.Name
                FROM ProductAttributeDefinition
                WHERE Product2Id = :productId
            ];

            if (productAttrs.isEmpty()) {
                response.put('success', true);
                response.put('errorMessage', 'Product has no attribute definitions');
                return response;
            }

            // Check for our target attributes
            List<String> allAttributeNames = new List<String>();
            Boolean hasPGroup = false;
            Boolean hasServerType = false;
            Boolean hasUsers = false;

            for (ProductAttributeDefinition pad : productAttrs) {
                String devName = pad.AttributeDefinition?.DeveloperName;
                String displayName = pad.AttributeDefinition?.Name;

                if (String.isNotBlank(displayName)) {
                    allAttributeNames.add(displayName);
                }

                if (String.isNotBlank(devName)) {
                    // Check for PGroup attribute (DeveloperName: Pgroup)
                    if (devName.equalsIgnoreCase('Pgroup') || devName.equalsIgnoreCase('PGroup') ||
                        devName.equalsIgnoreCase('P_Group')) {
                        hasPGroup = true;
                    }
                    // Check for Server Type attribute (DeveloperName: Server_Type)
                    if (devName.equalsIgnoreCase('Server_Type') || devName.equalsIgnoreCase('ServerType') ||
                        devName.equalsIgnoreCase('System_Type')) {
                        hasServerType = true;
                    }
                    // Check for Users attribute (DeveloperName: Users)
                    if (devName.equalsIgnoreCase('Users') || devName.equalsIgnoreCase('Users_Per_Partition') ||
                        devName.equalsIgnoreCase('UsersPerPartition')) {
                        hasUsers = true;
                    }
                }
            }

            response.put('success', true);
            response.put('hasPGroup', hasPGroup);
            response.put('hasServerType', hasServerType);
            response.put('hasUsers', hasUsers);
            response.put('attributeCount', productAttrs.size());
            response.put('allAttributeNames', allAttributeNames);

        } catch (Exception e) {
            response.put('success', false);
            response.put('errorMessage', 'Error querying product attributes: ' + e.getMessage());
        }

        return response;
    }
}