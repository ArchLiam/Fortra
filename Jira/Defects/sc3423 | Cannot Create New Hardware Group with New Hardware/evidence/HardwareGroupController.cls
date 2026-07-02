/**
 * @description Controller for Hardware Groups management in Revenue Cloud
 * @author Marc DeBrey
 * @version 1.1 - Added hardware attribute fields to queries for configuration defaults display
 * @since 2025-01
 *
 * This controller handles all server-side operations for the hardwareGroupManager LWC component:
 * - Querying existing hardware groups
 * - Searching for hardware records
 * - Creating new hardware records
 * - Creating and managing hardware groups
 * - Assigning hardware to groups
 */
public with sharing class HardwareGroupController {

    /**
     * @description Get the Account ID associated with a Quote
     * @param quoteId The Quote ID
     * @return Id of the Account
     */
    @AuraEnabled(cacheable=true)
    public static Id getQuoteAccountId(Id quoteId) {
        try {
            Quote quote = [
                SELECT Id, AccountId, Opportunity.AccountId
                FROM Quote
                WHERE Id = :quoteId
                LIMIT 1
            ];
            // Prefer direct AccountId on Quote, fallback to Opportunity.AccountId
            Id accountId = quote.AccountId != null ? quote.AccountId : quote.Opportunity?.AccountId;
            if (accountId == null) {
                throw new AuraHandledException('No Account found for this Quote. Please ensure the Quote or its Opportunity has an Account assigned.');
            }
            return accountId;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving quote account: ' + e.getMessage());
        }
    }

    /**
     * @description Get all existing hardware groups for a quote
     * @param quoteId The Quote ID
     * @return List of QuoteLineGroup records with hardware details and line counts
     */
    @AuraEnabled(cacheable=true)
    public static List<QuoteLineGroup> getExistingGroups(Id quoteId) {
        try {
            // Query all groups and filter client-side for those with hardware notes or hardware assigned
            // We can't filter Hardware_Notes__c in SOQL as it's not indexed
            // Include hardware attribute fields for configuration defaults display
            List<QuoteLineGroup> allGroups = [
                SELECT Id, Name, QuoteId,
                       Hardware__c,
                       Hardware__r.Hardware_ID__c,
                       Hardware__r.Model_Number__c,
                       Hardware__r.Serial_Number__c,
                       Hardware__r.Status__c,
                       Hardware__r.P_Group_List__c,
                       Hardware__r.Server_Type__c,
                       Hardware__r.Users_Per_Partition__c,
                       Hardware_Notes__c,
                       Hardware_Group_Type__c,
                       Description,
                       (SELECT Id FROM QuoteLineItems)
                FROM QuoteLineGroup
                WHERE QuoteId = :quoteId
                ORDER BY Name
            ];

            // Return all groups - let user see and select from all available groups
            // This allows assigning hardware to any group, not just those already marked as hardware groups
            return allGroups;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving hardware groups: ' + e.getMessage());
        }
    }

    /**
     * @description Search for hardware records with optional filters
     * @param accountId The Account ID to scope the search
     * @param filters Map of filter criteria (status, category, environment, serialNumber, model)
     * @return List of Hardware__c records matching the search criteria
     */
    @AuraEnabled(cacheable=true)
    public static List<Hardware__c> searchHardware(Id accountId, Map<String, String> filters) {
        try {
            // Build dynamic WHERE clause
            String whereClause = 'Account__c = :accountId';

            // Add filters if provided
            if (filters != null && !filters.isEmpty()) {
                if (filters.containsKey('status') && String.isNotBlank(filters.get('status'))) {
                    whereClause += ' AND Status__c = :statusFilter';
                }
                if (filters.containsKey('serialNumber') && String.isNotBlank(filters.get('serialNumber'))) {
                    whereClause += ' AND Serial_Number__c LIKE :serialNumberFilter';
                }
                if (filters.containsKey('model') && String.isNotBlank(filters.get('model'))) {
                    whereClause += ' AND Model_Number__c LIKE :modelFilter';
                }
            }

            // Prepare filter variables for binding
            String statusFilter = filters != null ? filters.get('status') : null;
            String serialNumberFilter = filters != null && String.isNotBlank(filters.get('serialNumber'))
                ? '%' + filters.get('serialNumber') + '%' : null;
            String modelFilter = filters != null && String.isNotBlank(filters.get('model'))
                ? '%' + filters.get('model') + '%' : null;

            // Build and execute query
            // Include hardware attribute fields for configuration defaults display
            String query = 'SELECT Id, Hardware_ID__c, Model_Number__c, Serial_Number__c, ' +
                          'Status__c, ' +
                          'Number_of_Processors__c, Storage_TB__c, Installation_Date__c, ' +
                          'P_Group_List__c, Server_Type__c, Users_Per_Partition__c ' +
                          'FROM Hardware__c ' +
                          'WHERE ' + whereClause + ' ' +
                          'ORDER BY Hardware_ID__c ' +
                          'LIMIT 200';

            return Database.query(query);

        } catch (Exception e) {
            throw new AuraHandledException('Error searching hardware: ' + e.getMessage());
        }
    }

    /**
     * @description Create a new Hardware__c record
     * @param hardwareData Map containing hardware field values
     * @param accountId The Account ID to link the hardware to
     * @return Id of the newly created Hardware__c record
     */
    @AuraEnabled
    public static Id createHardwareRecord(Map<String, Object> hardwareData, Id accountId) {
        try {
            // Validate required accountId parameter
            if (accountId == null) {
                AuraHandledException ahe = new AuraHandledException('Account ID is required to create hardware. Please ensure the Quote has an associated Account.');
                ahe.setMessage('Account ID is required to create hardware. Please ensure the Quote has an associated Account.');
                throw ahe;
            }

            // Create new hardware record
            Hardware__c newHardware = new Hardware__c();
            newHardware.Account__c = accountId;
            newHardware.Hardware_ID__c = generateHardwareId();

            // Always set status to 'Quoting' for newly created hardware
            // This status will change to 'Active' when Opportunity moves to 'Order Processing'
            // or the record will be deleted if Opportunity moves to 'Closed Lost'
            newHardware.Status__c = 'Quoting';

            // Map fields from hardwareData - Hardware Name and Platform
            if (hardwareData.containsKey('Hardware_Name__c')) {
                newHardware.Hardware_Name__c = (String) hardwareData.get('Hardware_Name__c');
            }
            if (hardwareData.containsKey('Hardware_Platform__c')) {
                newHardware.Hardware_Platform__c = (String) hardwareData.get('Hardware_Platform__c');
            }

            // iSeries-specific fields
            if (hardwareData.containsKey('Serial_Number__c')) {
                newHardware.Serial_Number__c = (String) hardwareData.get('Serial_Number__c');
            }
            if (hardwareData.containsKey('iSeries_Model__c')) {
                newHardware.iSeries_Model__c = (String) hardwareData.get('iSeries_Model__c');
            }
            if (hardwareData.containsKey('iSeries_Feature_Code__c')) {
                newHardware.iSeries_Feature_Code__c = (String) hardwareData.get('iSeries_Feature_Code__c');
            }
            if (hardwareData.containsKey('Number_of_Processors__c')) {
                newHardware.Number_of_Processors__c = (Decimal) hardwareData.get('Number_of_Processors__c');
            }
            if (hardwareData.containsKey('P_Group_List__c')) {
                newHardware.P_Group_List__c = (String) hardwareData.get('P_Group_List__c');
            }

            // Cross Platform-specific fields
            if (hardwareData.containsKey('Hostname__c')) {
                newHardware.Hostname__c = (String) hardwareData.get('Hostname__c');
            }
            if (hardwareData.containsKey('Hardware_ID__c')) {
                // Override auto-generated ID if user provides one
                newHardware.Hardware_ID__c = (String) hardwareData.get('Hardware_ID__c');
            }
            if (hardwareData.containsKey('Host_Operating_System__c')) {
                newHardware.Host_Operating_System__c = (String) hardwareData.get('Host_Operating_System__c');
            }

            // Common configuration attributes (shared across platforms)
            if (hardwareData.containsKey('Server_Type__c')) {
                newHardware.Server_Type__c = (String) hardwareData.get('Server_Type__c');
            }
            if (hardwareData.containsKey('Users_Per_Partition__c')) {
                newHardware.Users_Per_Partition__c = (Decimal) hardwareData.get('Users_Per_Partition__c');
            }

            // Legacy fields (kept for backward compatibility)
            if (hardwareData.containsKey('Model_Number__c')) {
                newHardware.Model_Number__c = (String) hardwareData.get('Model_Number__c');
            }
            // Note: Status__c is always set to 'Quoting' above - do not allow override from hardwareData
            if (hardwareData.containsKey('Storage_TB__c')) {
                newHardware.Storage_TB__c = (Decimal) hardwareData.get('Storage_TB__c');
            }
            if (hardwareData.containsKey('Installation_Date__c')) {
                newHardware.Installation_Date__c = (Date) hardwareData.get('Installation_Date__c');
            }

            insert newHardware;

            // Auto-create Partition record for iSeries and Cross Platform hardware
            String platform = (String) hardwareData.get('Hardware_Platform__c');
            if (platform == 'iSeries' || platform == 'Cross Platform') {
                Partition__c partition = new Partition__c();
                partition.Hardware__c = newHardware.Id;
                // partition.Account__c = accountId;

                // Partition Name = Hardware Name + " - Partition 1"
                String hwName = hardwareData.containsKey('Hardware_Name__c')
                    ? (String) hardwareData.get('Hardware_Name__c')
                    : '';
                partition.Partition_Name__c = String.isNotBlank(hwName)
                    ? hwName.trim() + ' - Partition 1'
                    : 'Partition 1';

                // Partition Number (LPAR) derived from Hardware ID
                partition.Partition_Number__c = newHardware.Hardware_ID__c + '-P1';

                // Number of Processors from user input
                if (hardwareData.containsKey('Number_of_Processors__c')) {
                    partition.Number_of_Processors__c = (Decimal) hardwareData.get('Number_of_Processors__c');
                }

                insert partition;
            }

            return newHardware.Id;

        } catch (Exception e) {
            throw new AuraHandledException('Error creating hardware record: ' + e.getMessage());
        }
    }

    /**
     * @description Create a new hardware group
     * @param quoteId The Quote ID
     * @param groupName The name for the new group
     * @param notes Hardware notes for Order Management team
     * @param hardwareId The Hardware__c ID to assign to the group (optional)
     * @return Id of the newly created QuoteLineGroup record
     */
    @AuraEnabled
    public static Id createHardwareGroup(Id quoteId, String groupName, String notes, Id hardwareId) {
        try {
            // Create new QuoteLineGroup
            QuoteLineGroup newGroup = new QuoteLineGroup();
            newGroup.QuoteId = quoteId;
            newGroup.Name = groupName;
            newGroup.Hardware_Notes__c = notes;

            // Copy hardware notes to Description for UI visibility
            newGroup.Description = notes;

            // Validate group name uniqueness
            validateUniqueGroupName(quoteId, groupName, null);

            // Only set Hardware_Group_Type__c = true when hardware is assigned
            // This avoids validation rule error on creation
            if (hardwareId != null) {
                newGroup.Hardware__c = hardwareId;
                newGroup.Hardware_Group_Type__c = true;
            }

            insert newGroup;
            return newGroup.Id;

        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating hardware group: ' + e.getMessage());
        }
    }

    /**
     * @description Update an existing hardware group
     * @param groupId The QuoteLineGroup ID to update
     * @param groupName Updated group name
     * @param notes Updated hardware notes
     * @param hardwareId Updated Hardware__c ID (can be null to clear)
     */
    @AuraEnabled
    public static void updateHardwareGroup(Id groupId, String groupName, String notes, Id hardwareId) {
        try {
            // Query existing group
            QuoteLineGroup existingGroup = [
                SELECT Id, Name, Hardware_Notes__c, Hardware__c, Hardware_Group_Type__c, Description, QuoteId
                FROM QuoteLineGroup
                WHERE Id = :groupId
                LIMIT 1
            ];

            // Update fields
            existingGroup.Name = groupName;
            existingGroup.Hardware_Notes__c = notes;
            existingGroup.Hardware__c = hardwareId;

            // Copy hardware notes to Description for UI visibility
            existingGroup.Description = notes;

            // Validate group name uniqueness (exclude current group from check)
            validateUniqueGroupName(existingGroup.QuoteId, groupName, groupId);

            // Set Hardware_Group_Type__c = true when hardware is assigned
            if (hardwareId != null) {
                existingGroup.Hardware_Group_Type__c = true;
            }

            update existingGroup;

            // Note: QuoteLineGroupTrigger will handle updating Hardware_Reference__c on quote lines

        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating hardware group: ' + e.getMessage());
        }
    }

    /**
     * @description Assign hardware to an existing group
     * @param groupId The QuoteLineGroup ID
     * @param hardwareId The Hardware__c ID to assign
     */
    @AuraEnabled
    public static void assignHardwareToGroup(Id groupId, Id hardwareId) {
        try {
            // Query existing group
            QuoteLineGroup existingGroup = [
                SELECT Id, Hardware__c, Hardware_Group_Type__c, Hardware_Notes__c, Description
                FROM QuoteLineGroup
                WHERE Id = :groupId
                LIMIT 1
            ];

            // Update hardware assignment
            existingGroup.Hardware__c = hardwareId;
            existingGroup.Hardware_Group_Type__c = true;

            // Copy hardware notes to Description if not already set
            if (String.isNotBlank(existingGroup.Hardware_Notes__c) && String.isBlank(existingGroup.Description)) {
                existingGroup.Description = existingGroup.Hardware_Notes__c;
            }

            update existingGroup;

            // Note: QuoteLineGroupTrigger will handle updating Hardware_Reference__c on quote lines

        } catch (Exception e) {
            throw new AuraHandledException('Error assigning hardware to group: ' + e.getMessage());
        }
    }

    /**
     * @description Get unassigned hardware records for a quote's account
     * Hardware is considered "unassigned" if it's not linked to any QuoteLineGroup on this quote
     * @param quoteId The Quote ID
     * @param accountId The Account ID
     * @return List of Hardware__c records not assigned to any group on this quote
     */
    @AuraEnabled
    public static List<Hardware__c> getUnassignedHardware(Id quoteId, Id accountId) {
        try {
            // Get all Hardware IDs already assigned to groups on this quote
            Set<Id> assignedHardwareIds = new Set<Id>();
            List<QuoteLineGroup> groupsWithHardware = [
                SELECT Hardware__c
                FROM QuoteLineGroup
                WHERE QuoteId = :quoteId
                  AND Hardware__c != null
            ];

            for (QuoteLineGroup grp : groupsWithHardware) {
                assignedHardwareIds.add(grp.Hardware__c);
            }

            // Query all hardware for the account that is NOT already assigned
            // Include hardware attribute fields for configuration defaults display
            List<Hardware__c> unassignedHardware = [
                SELECT Id, Hardware_ID__c, Model_Number__c, Serial_Number__c,
                       Status__c,
                       Number_of_Processors__c, Storage_TB__c, Installation_Date__c,
                       P_Group_List__c, Server_Type__c, Users_Per_Partition__c
                FROM Hardware__c
                WHERE Account__c = :accountId
                  AND Id NOT IN :assignedHardwareIds
                ORDER BY Hardware_ID__c
                LIMIT 200
            ];

            return unassignedHardware;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving unassigned hardware: ' + e.getMessage());
        }
    }

    /**
     * @description Get picklist options for hardware search filters and creation form
     * @return Map of picklist field names to their available values
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getPicklistOptions() {
        try {
            Map<String, List<Map<String, String>>> picklistOptions = new Map<String, List<Map<String, String>>>();

            // Get Hardware__c object describe
            Schema.DescribeSObjectResult hardwareDescribe = Hardware__c.SObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = hardwareDescribe.fields.getMap();

            // Get Status__c picklist values
            if (fieldMap.containsKey('Status__c')) {
                picklistOptions.put('status', getPicklistValues(fieldMap.get('Status__c')));
            }

            // Get Hardware_Platform__c picklist values (iSeries / Cross Platform)
            if (fieldMap.containsKey('Hardware_Platform__c')) {
                picklistOptions.put('hardwarePlatform', getPicklistValues(fieldMap.get('Hardware_Platform__c')));
            }

            // Get iSeries_Model__c picklist values
            if (fieldMap.containsKey('iSeries_Model__c')) {
                picklistOptions.put('iSeriesModel', getPicklistValues(fieldMap.get('iSeries_Model__c')));
            }

            // Get P_Group_List__c picklist values
            if (fieldMap.containsKey('P_Group_List__c')) {
                picklistOptions.put('pGroup', getPicklistValues(fieldMap.get('P_Group_List__c')));
            }

            // Get Host_Operating_System__c picklist values (for Cross Platform)
            if (fieldMap.containsKey('Host_Operating_System__c')) {
                picklistOptions.put('operatingSystem', getPicklistValues(fieldMap.get('Host_Operating_System__c')));
            }

            // Get Server_Type__c picklist values (common configuration attribute)
            if (fieldMap.containsKey('Server_Type__c')) {
                picklistOptions.put('serverType', getPicklistValues(fieldMap.get('Server_Type__c')));
            }

            return picklistOptions;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving picklist options: ' + e.getMessage());
        }
    }

    /**
     * @description Get dependent picklist values for iSeries Feature Code based on selected Model
     * @param modelValue The selected iSeries Model value
     * @return List of feature code options valid for the selected model
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getFeatureCodeOptions(String modelValue) {
        try {
            List<Map<String, String>> options = new List<Map<String, String>>();

            if (String.isBlank(modelValue)) {
                return options;
            }

            // Get Hardware__c object describe
            Schema.DescribeSObjectResult hardwareDescribe = Hardware__c.SObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = hardwareDescribe.fields.getMap();

            if (!fieldMap.containsKey('iSeries_Feature_Code__c')) {
                return options;
            }

            // Get the dependent picklist values
            Schema.SObjectField controllingField = fieldMap.get('iSeries_Model__c');
            Schema.SObjectField dependentField = fieldMap.get('iSeries_Feature_Code__c');

            // Get all picklist entries for the dependent field
            Schema.DescribeFieldResult dependentDescribe = dependentField.getDescribe();
            Schema.DescribeFieldResult controllingDescribe = controllingField.getDescribe();

            List<Schema.PicklistEntry> controllingEntries = controllingDescribe.getPicklistValues();
            List<Schema.PicklistEntry> dependentEntries = dependentDescribe.getPicklistValues();

            // Build map of controlling values to their indices
            Map<String, Integer> controllingIndexMap = new Map<String, Integer>();
            Integer idx = 0;
            for (Schema.PicklistEntry entry : controllingEntries) {
                controllingIndexMap.put(entry.getValue(), idx);
                idx++;
            }

            // Get the index of the selected model
            Integer selectedIndex = controllingIndexMap.get(modelValue);
            if (selectedIndex == null) {
                return options;
            }

            // Check each dependent entry to see if it's valid for the controlling value
            for (Schema.PicklistEntry entry : dependentEntries) {
                if (entry.isActive()) {
                    // Get the validFor bitmap from the dependent picklist entry
                    // This is base64 encoded in the metadata
                    String validForBase64 = getValidForBitmap(entry);
                    if (validForBase64 != null) {
                        // Check if this dependent value is valid for the selected controlling index
                        if (isValidForIndex(validForBase64, selectedIndex)) {
                            Map<String, String> option = new Map<String, String>();
                            option.put('label', entry.getLabel());
                            option.put('value', entry.getValue());
                            options.add(option);
                        }
                    }
                }
            }

            return options;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving feature code options: ' + e.getMessage());
        }
    }

    /**
     * @description Extract validFor bitmap from picklist entry using serialization
     * @param entry The picklist entry
     * @return Base64 encoded validFor bitmap string
     */
    private static String getValidForBitmap(Schema.PicklistEntry entry) {
        // Serialize the picklist entry to get the validFor property
        String serialized = JSON.serialize(entry);
        Map<String, Object> entryMap = (Map<String, Object>) JSON.deserializeUntyped(serialized);

        if (entryMap.containsKey('validFor')) {
            return (String) entryMap.get('validFor');
        }
        return null;
    }

    /**
     * @description Check if a dependent value is valid for a given controlling index
     * @param validForBase64 The base64 encoded validFor bitmap
     * @param controllingIndex The index of the controlling picklist value
     * @return True if the dependent value is valid for the controlling index
     */
    private static Boolean isValidForIndex(String validForBase64, Integer controllingIndex) {
        // Decode base64 to bytes
        Blob validForBlob = EncodingUtil.base64Decode(validForBase64);
        String validForHex = EncodingUtil.convertToHex(validForBlob);

        // Calculate byte and bit position
        Integer byteIndex = controllingIndex / 8;
        Integer bitIndex = 7 - Math.mod(controllingIndex, 8);

        // Check if we have enough bytes
        if (byteIndex * 2 + 2 > validForHex.length()) {
            return false;
        }

        // Get the relevant byte and convert hex to integer
        String byteHex = validForHex.substring(byteIndex * 2, byteIndex * 2 + 2);
        Integer byteValue = hexToInteger(byteHex);

        // Check if the bit is set
        return ((byteValue >> bitIndex) & 1) == 1;
    }

    /**
     * @description Helper method to convert a hex string to an integer
     * @param hexStr The hex string to convert (e.g., 'FF', '0A')
     * @return The integer value
     */
    private static Integer hexToInteger(String hexStr) {
        String chars = '0123456789abcdef';
        hexStr = hexStr.toLowerCase();
        Integer result = 0;
        for (Integer i = 0; i < hexStr.length(); i++) {
            Integer charIndex = chars.indexOf(hexStr.substring(i, i + 1));
            if (charIndex < 0) {
                return 0; // Invalid hex character
            }
            result = result * 16 + charIndex;
        }
        return result;
    }

    /**
     * @description Helper method to extract picklist values from a field
     * @param field The Schema.SObjectField to extract picklist values from
     * @return List of maps containing label and value for each picklist option
     */
    private static List<Map<String, String>> getPicklistValues(Schema.SObjectField field) {
        List<Map<String, String>> options = new List<Map<String, String>>();

        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldDescribe.getPicklistValues();

        for (Schema.PicklistEntry entry : picklistValues) {
            if (entry.isActive()) {
                Map<String, String> option = new Map<String, String>();
                option.put('label', entry.getLabel());
                option.put('value', entry.getValue());
                options.add(option);
            }
        }

        return options;
    }

    /**
     * @description Validate that a group name is unique within a quote (case-insensitive)
     * @param quoteId The Quote ID
     * @param groupName The proposed group name
     * @param excludeGroupId Group ID to exclude from check (for edit scenarios), can be null
     * @throws AuraHandledException if a duplicate name is found
     */
    private static void validateUniqueGroupName(Id quoteId, String groupName, Id excludeGroupId) {
        if (String.isBlank(groupName)) return;

        String normalizedName = groupName.trim().toLowerCase();

        List<QuoteLineGroup> existingGroups = [
            SELECT Id, Name
            FROM QuoteLineGroup
            WHERE QuoteId = :quoteId
        ];

        for (QuoteLineGroup grp : existingGroups) {
            if (grp.Name != null
                && grp.Name.trim().toLowerCase() == normalizedName
                && (excludeGroupId == null || grp.Id != excludeGroupId)) {
                String errorMsg = 'A group named "' + groupName.trim() + '" already exists on this quote. Please choose a different name.';
                AuraHandledException ahe = new AuraHandledException(errorMsg);
                ahe.setMessage(errorMsg);
                throw ahe;
            }
        }
    }

    /**
     * @description Generate a unique Hardware ID
     * @return String in format HW-{timestamp}-{random}
     */
    private static String generateHardwareId() {
        // Query for existing Hardware IDs to ensure uniqueness
        Integer maxSequence = 0;
        List<AggregateResult> results = [
            SELECT COUNT(Id) cnt
            FROM Hardware__c
            WHERE Hardware_ID__c LIKE 'HW%'
        ];

        if (!results.isEmpty()) {
            maxSequence = (Integer) results[0].get('cnt');
        }

        // Generate new ID with sequential number
        String newId = 'HW' + String.valueOf(maxSequence + 1).leftPad(6, '0');

        return newId;
    }
}