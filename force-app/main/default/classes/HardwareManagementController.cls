/**
 * @description Controller for Hardware Management functionality in the Transaction Line Editor
 * @date 2025
 */
public with sharing class HardwareManagementController {

    /**
     * @description Result wrapper class for API responses
     */
    public class HardwareResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String error;
        @AuraEnabled public List<QuoteLineItem> lines;

        public HardwareResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }

        public HardwareResult(Boolean success, String message, String error) {
            this.success = success;
            this.message = message;
            this.error = error;
        }
    }

    /**
     * @description Get all quote lines for a quote (fallback when selection detection fails)
     * @param quoteId The Quote record ID
     * @return HardwareResult with all quote lines
     */
    @AuraEnabled(cacheable=false)
    public static HardwareResult getAllQuoteLines(Id quoteId) {
        try {
            if (quoteId == null) {
                return new HardwareResult(false, 'No quote ID provided');
            }

            // Build dynamic query to handle field permissions
            String query = 'SELECT Id';

            // Check field accessibility before adding to query
            Schema.SObjectType quoteLineType = QuoteLineItem.sObjectType;
            Map<String, Schema.SObjectField> fieldMap = quoteLineType.getDescribe().fields.getMap();

            // Add Product fields if accessible
            if (fieldMap.get('Product2Id') != null && fieldMap.get('Product2Id').getDescribe().isAccessible()) {
                query += ', Product2Id, Product2.Name, Product2.ProductCode, Product2.Hardware_ID__c';
            }

            // Add Quantity if accessible
            if (fieldMap.get('Quantity') != null && fieldMap.get('Quantity').getDescribe().isAccessible()) {
                query += ', Quantity';
            }

            // Add LineNumber if accessible
            if (fieldMap.get('LineNumber') != null && fieldMap.get('LineNumber').getDescribe().isAccessible()) {
                query += ', LineNumber';
            }

            // Add custom fields if they exist and are accessible
            if (fieldMap.containsKey('Hardware_Reference__c') &&
                fieldMap.get('Hardware_Reference__c').getDescribe().isAccessible()) {
                query += ', Hardware_Reference__c, Hardware_Reference__r.Name';
            }

            if (fieldMap.containsKey('Requires_New_Hardware__c') &&
                fieldMap.get('Requires_New_Hardware__c').getDescribe().isAccessible()) {
                query += ', Requires_New_Hardware__c';
            }

            if (fieldMap.containsKey('Hardware_Notes__c') &&
                fieldMap.get('Hardware_Notes__c').getDescribe().isAccessible()) {
                query += ', Hardware_Notes__c';
            }

            // Add QuoteId field check
            if (fieldMap.get('QuoteId') != null && fieldMap.get('QuoteId').getDescribe().isAccessible()) {
                query += ', QuoteId';
            }

            query += ' FROM QuoteLineItem WHERE QuoteId = :quoteId AND Product2.Hardware_ID__c = true ORDER BY LineNumber, Id';

            List<QuoteLineItem> lines = Database.query(query);

            HardwareResult result = new HardwareResult(true, 'All quote lines retrieved');
            result.lines = lines;
            return result;

        } catch (Exception e) {
            System.debug('Error in getAllQuoteLines: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return new HardwareResult(false, 'Error retrieving quote lines', e.getMessage());
        }
    }

    /**
     * @description Get selected quote lines with their hardware references
     * @param quoteLineIds List of quote line IDs to retrieve
     * @return HardwareResult with quote lines and their hardware references
     */
    @AuraEnabled(cacheable=false)
    public static HardwareResult getSelectedQuoteLines(List<Id> quoteLineIds) {
        try {
            if (quoteLineIds == null || quoteLineIds.isEmpty()) {
                return new HardwareResult(false, 'No quote lines provided');
            }

            // Build dynamic query to handle field permissions
            String query = 'SELECT Id';

            // Check field accessibility before adding to query
            Schema.SObjectType quoteLineType = QuoteLineItem.sObjectType;
            Map<String, Schema.SObjectField> fieldMap = quoteLineType.getDescribe().fields.getMap();

            // Add Product fields if accessible
            if (fieldMap.get('Product2Id') != null && fieldMap.get('Product2Id').getDescribe().isAccessible()) {
                query += ', Product2Id, Product2.Name, Product2.ProductCode, Product2.Hardware_ID__c';
            }

            // Add Quantity if accessible
            if (fieldMap.get('Quantity') != null && fieldMap.get('Quantity').getDescribe().isAccessible()) {
                query += ', Quantity';
            }

            // Add custom fields if they exist and are accessible
            if (fieldMap.containsKey('Hardware_Reference__c') &&
                fieldMap.get('Hardware_Reference__c').getDescribe().isAccessible()) {
                query += ', Hardware_Reference__c, Hardware_Reference__r.Name';
            }

            if (fieldMap.containsKey('Requires_New_Hardware__c') &&
                fieldMap.get('Requires_New_Hardware__c').getDescribe().isAccessible()) {
                query += ', Requires_New_Hardware__c';
            }

            if (fieldMap.containsKey('Hardware_Notes__c') &&
                fieldMap.get('Hardware_Notes__c').getDescribe().isAccessible()) {
                query += ', Hardware_Notes__c';
            }

            query += ' FROM QuoteLineItem WHERE Id IN :quoteLineIds AND Product2.Hardware_ID__c = true ORDER BY Id';

            List<QuoteLineItem> lines = Database.query(query);

            HardwareResult result = new HardwareResult(true, 'Lines retrieved successfully');
            result.lines = lines;
            return result;

        } catch (Exception e) {
            System.debug('Error in getSelectedQuoteLines: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return new HardwareResult(false, 'Error retrieving quote lines', e.getMessage());
        }
    }

    /**
     * @description Search for hardware records based on criteria
     * @param accountId The account ID to filter hardware records
     * @param productIds List of Product IDs from the selected quote lines
     * @param searchTerm Search term for name, serial number, or model
     * @param status Hardware status filter
     * @param category Hardware category filter
     * @param environment Hardware environment filter
     * @return List of matching sObject records (empty if Hardware__c doesn't exist)
     */
    @AuraEnabled(cacheable=true)
    public static List<sObject> searchHardware(Id accountId, List<Id> productIds, String searchTerm,
                                              String status, String category, String environment) {
        try {
            // Debug logging
            System.debug('=== searchHardware called ===');
            System.debug('accountId: ' + accountId);
            System.debug('productIds: ' + productIds);
            System.debug('status: ' + status);

            // Check if Hardware__c object exists
            Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
            if (!schemaMap.containsKey('Hardware__c')) {
                System.debug('Hardware__c object does not exist');
                // Hardware object doesn't exist, return empty list
                return new List<sObject>();
            }

            // Get Hardware__c field map to check which fields exist
            Schema.SObjectType hardwareType = schemaMap.get('Hardware__c');
            Map<String, Schema.SObjectField> fieldMap = hardwareType.getDescribe().fields.getMap();

            // Debug available fields
            System.debug('=== Available Hardware__c fields ===');
            for(String fieldName : fieldMap.keySet()) {
                if(fieldName.containsIgnoreCase('product') ||
                   fieldName.containsIgnoreCase('account') ||
                   fieldName.containsIgnoreCase('status')) {
                    System.debug('Field: ' + fieldName);
                }
            }

            // Build dynamic query with available fields
            String query = 'SELECT Id, Name';

            // Add optional fields if they exist
            if (fieldMap.containsKey('Serial_Number__c') &&
                fieldMap.get('Serial_Number__c').getDescribe().isAccessible()) {
                query += ', Serial_Number__c';
            }

            if (fieldMap.containsKey('Model_Number__c') &&
                fieldMap.get('Model_Number__c').getDescribe().isAccessible()) {
                query += ', Model_Number__c';
            }

            if (fieldMap.containsKey('Manufacturer__c') &&
                fieldMap.get('Manufacturer__c').getDescribe().isAccessible()) {
                query += ', Manufacturer__c';
            }

            if (fieldMap.containsKey('Status__c') &&
                fieldMap.get('Status__c').getDescribe().isAccessible()) {
                query += ', Status__c';
            }

            if (fieldMap.containsKey('Hardware_Category__c') &&
                fieldMap.get('Hardware_Category__c').getDescribe().isAccessible()) {
                query += ', Hardware_Category__c';
            }

            if (fieldMap.containsKey('Environment__c') &&
                fieldMap.get('Environment__c').getDescribe().isAccessible()) {
                query += ', Environment__c';
            }

            if (fieldMap.containsKey('Location__r') &&
                fieldMap.get('Location__c').getDescribe().isAccessible()) {
                query += ', Location__r.Name';
            }

            // Add Hardware Type, Hardware Value, and Product fields (lowercase field names in fieldMap)
            if (fieldMap.containsKey('hardware_type__c') &&
                fieldMap.get('hardware_type__c').getDescribe().isAccessible()) {
                query += ', Hardware_Type__c';
            }

            if (fieldMap.containsKey('hardware_value__c') &&
                fieldMap.get('hardware_value__c').getDescribe().isAccessible()) {
                query += ', Hardware_Value__c';
            }

            if (fieldMap.containsKey('product__c') &&
                fieldMap.get('product__c').getDescribe().isAccessible()) {
                query += ', Product__c, Product__r.Name, Product__r.ProductCode';
            }

            query += ' FROM Hardware__c';

            // Build WHERE clause dynamically
            List<String> whereClauses = new List<String>();

            // Always filter by Account (field names are lowercase in the field map)
            if (fieldMap.containsKey('account__c') && accountId != null) {
                whereClauses.add('Account__c = :accountId');
            }

            // Filter by Product if the field exists and productIds provided
            // Check for different possible field names (case-insensitive keys in fieldMap)
            Boolean hasProductFilter = false;
            if (productIds != null && !productIds.isEmpty()) {
                // Field names are lowercase in the field map
                if (fieldMap.containsKey('product__c')) {
                    whereClauses.add('Product__c IN :productIds');
                    hasProductFilter = true;
                    System.debug('Filtering by Product__c field');
                } else if (fieldMap.containsKey('product2__c')) {
                    whereClauses.add('Product2__c IN :productIds');
                    hasProductFilter = true;
                    System.debug('Filtering by Product2__c field');
                } else if (fieldMap.containsKey('related_product__c')) {
                    whereClauses.add('Related_Product__c IN :productIds');
                    hasProductFilter = true;
                    System.debug('Filtering by Related_Product__c field');
                } else {
                    System.debug('WARNING: No product field found on Hardware__c. Checked: product__c, product2__c, related_product__c');
                    System.debug('Available product-related fields:');
                    for(String fieldName : fieldMap.keySet()) {
                        if(fieldName.containsIgnoreCase('product')) {
                            System.debug('  - ' + fieldName);
                        }
                    }
                }
            }

            // Always filter by Active status unless explicitly specified otherwise (lowercase field names)
            if (fieldMap.containsKey('status__c')) {
                if (String.isNotBlank(status)) {
                    whereClauses.add('Status__c = :status');
                } else {
                    // Default to Active status
                    status = 'Active';
                    whereClauses.add('Status__c = :status');
                }
            }

            // Add category filter if specified (lowercase field names)
            if (String.isNotBlank(category) && fieldMap.containsKey('hardware_category__c')) {
                whereClauses.add('Hardware_Category__c = :category');
            }

            // Add environment filter if specified (lowercase field names)
            if (String.isNotBlank(environment) && fieldMap.containsKey('environment__c')) {
                whereClauses.add('Environment__c = :environment');
            }

            // Add search term filter
            if (String.isNotBlank(searchTerm)) {
                String searchPattern = '%' + searchTerm + '%';
                List<String> searchClauses = new List<String>();
                searchClauses.add('Name LIKE :searchPattern');

                if (fieldMap.containsKey('Serial_Number__c')) {
                    searchClauses.add('Serial_Number__c LIKE :searchPattern');
                }

                if (fieldMap.containsKey('Model_Number__c')) {
                    searchClauses.add('Model_Number__c LIKE :searchPattern');
                }

                if (!searchClauses.isEmpty()) {
                    whereClauses.add('(' + String.join(searchClauses, ' OR ') + ')');
                }
            }

            // Build final WHERE clause
            if (!whereClauses.isEmpty()) {
                query += ' WHERE ' + String.join(whereClauses, ' AND ');
            }

            query += ' ORDER BY Name LIMIT 100';

            System.debug('Final query: ' + query);
            List<sObject> results = Database.query(query);
            System.debug('Results found: ' + results.size());

            return results;

        } catch (Exception e) {
            // Return empty list if there's an error
            System.debug('Hardware search error: ' + e.getMessage());
            return new List<sObject>();
        }
    }

    /**
     * @description Link hardware records to quote lines
     * @param quoteLineIds List of quote line IDs to update
     * @param hardwareIds List of hardware IDs to link
     * @return HardwareResult with operation status
     */
    @AuraEnabled
    public static HardwareResult linkHardwareToLines(List<Id> quoteLineIds, List<Id> hardwareIds) {
        try {
            if (quoteLineIds == null || quoteLineIds.isEmpty()) {
                return new HardwareResult(false, 'No quote lines provided');
            }

            if (hardwareIds == null || hardwareIds.isEmpty()) {
                return new HardwareResult(false, 'No hardware selected');
            }

            // Get quote lines with accessible fields only
            Schema.SObjectType quoteLineType = QuoteLineItem.sObjectType;
            Map<String, Schema.SObjectField> fieldMap = quoteLineType.getDescribe().fields.getMap();

            String query = 'SELECT Id';

            // Add custom fields if they exist and are accessible
            if (fieldMap.containsKey('Hardware_Reference__c') &&
                fieldMap.get('Hardware_Reference__c').getDescribe().isAccessible()) {
                query += ', Hardware_Reference__c, Hardware_Reference__r.Name';
            }

            if (fieldMap.containsKey('Requires_New_Hardware__c') &&
                fieldMap.get('Requires_New_Hardware__c').getDescribe().isAccessible()) {
                query += ', Requires_New_Hardware__c';
            }

            if (fieldMap.containsKey('Hardware_Notes__c') &&
                fieldMap.get('Hardware_Notes__c').getDescribe().isAccessible()) {
                query += ', Hardware_Notes__c';
            }

            query += ' FROM QuoteLineItem WHERE Id IN :quoteLineIds FOR UPDATE';

            List<QuoteLineItem> linesToUpdate = Database.query(query);

            // Check which fields are accessible for update
            Boolean hasHardwareRef = fieldMap.containsKey('Hardware_Reference__c') &&
                                    fieldMap.get('Hardware_Reference__c').getDescribe().isAccessible();
            Boolean hasRequiresNew = fieldMap.containsKey('Requires_New_Hardware__c') &&
                                    fieldMap.get('Requires_New_Hardware__c').getDescribe().isAccessible();
            Boolean hasNotes = fieldMap.containsKey('Hardware_Notes__c') &&
                                fieldMap.get('Hardware_Notes__c').getDescribe().isAccessible();

            // For simplicity, link the first hardware ID to all selected lines
            // In a real scenario, you might want more complex logic
            Id hardwareId = hardwareIds[0];

            for (QuoteLineItem line : linesToUpdate) {
                if (hasHardwareRef) {
                    line.Hardware_Reference__c = hardwareId;
                }
                if (hasRequiresNew) {
                    line.Requires_New_Hardware__c = false;
                }
                if (hasNotes) {
                    line.Hardware_Notes__c = null;
                }
            }

            update linesToUpdate;

            Integer updateCount = linesToUpdate.size();
            String message = 'Successfully linked hardware to ' + updateCount + ' quote line' +
                           (updateCount != 1 ? 's' : '');

            return new HardwareResult(true, message);

        } catch (Exception e) {
            return new HardwareResult(false, 'Error linking hardware', e.getMessage());
        }
    }

    /**
     * @description Flag quote lines as requiring new hardware
     * @param quoteLineIds List of quote line IDs to flag
     * @param notes Notes for the order management team
     * @return HardwareResult with operation status
     */
    @AuraEnabled
    public static HardwareResult flagLinesAsRequiringNewHardware(List<Id> quoteLineIds, String notes) {
        try {
            if (quoteLineIds == null || quoteLineIds.isEmpty()) {
                return new HardwareResult(false, 'No quote lines provided');
            }

            // Get quote lines with accessible fields only
            Schema.SObjectType quoteLineType = QuoteLineItem.sObjectType;
            Map<String, Schema.SObjectField> fieldMap = quoteLineType.getDescribe().fields.getMap();

            String query = 'SELECT Id';
            Boolean hasHardwareRef = false;
            Boolean hasRequiresNew = false;
            Boolean hasNotes = false;

            // Add custom fields if they exist and are accessible
            if (fieldMap.containsKey('Hardware_Reference__c') &&
                fieldMap.get('Hardware_Reference__c').getDescribe().isAccessible()) {
                query += ', Hardware_Reference__c';
                hasHardwareRef = true;
            }

            if (fieldMap.containsKey('Requires_New_Hardware__c') &&
                fieldMap.get('Requires_New_Hardware__c').getDescribe().isAccessible()) {
                query += ', Requires_New_Hardware__c';
                hasRequiresNew = true;
            }

            if (fieldMap.containsKey('Hardware_Notes__c') &&
                fieldMap.get('Hardware_Notes__c').getDescribe().isAccessible()) {
                query += ', Hardware_Notes__c';
                hasNotes = true;
            }

            query += ' FROM QuoteLineItem WHERE Id IN :quoteLineIds FOR UPDATE';

            List<QuoteLineItem> linesToUpdate = Database.query(query);

            for (QuoteLineItem line : linesToUpdate) {
                if (hasHardwareRef) {
                    line.Hardware_Reference__c = null;
                }
                if (hasRequiresNew) {
                    line.Requires_New_Hardware__c = true;
                }
                if (hasNotes) {
                    line.Hardware_Notes__c = notes;
                }
            }

            update linesToUpdate;

            Integer updateCount = linesToUpdate.size();
            String message = 'Successfully flagged ' + updateCount + ' quote line' +
                           (updateCount != 1 ? 's' : '') + ' as requiring new hardware';

            return new HardwareResult(true, message);

        } catch (Exception e) {
            return new HardwareResult(false, 'Error flagging lines', e.getMessage());
        }
    }

    /**
     * @description Clear hardware references from quote lines
     * @param quoteLineIds List of quote line IDs to clear
     * @return HardwareResult with operation status
     */
    @AuraEnabled
    public static HardwareResult clearHardwareReferences(List<Id> quoteLineIds) {
        try {
            if (quoteLineIds == null || quoteLineIds.isEmpty()) {
                return new HardwareResult(false, 'No quote lines provided');
            }

            // Get quote lines with accessible fields only
            Schema.SObjectType quoteLineType = QuoteLineItem.sObjectType;
            Map<String, Schema.SObjectField> fieldMap = quoteLineType.getDescribe().fields.getMap();

            String query = 'SELECT Id';
            Boolean hasHardwareRef = false;
            Boolean hasRequiresNew = false;
            Boolean hasNotes = false;

            // Add custom fields if they exist and are accessible
            if (fieldMap.containsKey('Hardware_Reference__c') &&
                fieldMap.get('Hardware_Reference__c').getDescribe().isAccessible()) {
                query += ', Hardware_Reference__c';
                hasHardwareRef = true;
            }

            if (fieldMap.containsKey('Requires_New_Hardware__c') &&
                fieldMap.get('Requires_New_Hardware__c').getDescribe().isAccessible()) {
                query += ', Requires_New_Hardware__c';
                hasRequiresNew = true;
            }

            if (fieldMap.containsKey('Hardware_Notes__c') &&
                fieldMap.get('Hardware_Notes__c').getDescribe().isAccessible()) {
                query += ', Hardware_Notes__c';
                hasNotes = true;
            }

            query += ' FROM QuoteLineItem WHERE Id IN :quoteLineIds FOR UPDATE';

            List<QuoteLineItem> linesToUpdate = Database.query(query);

            for (QuoteLineItem line : linesToUpdate) {
                if (hasHardwareRef) {
                    line.Hardware_Reference__c = null;
                }
                if (hasRequiresNew) {
                    line.Requires_New_Hardware__c = false;
                }
                if (hasNotes) {
                    line.Hardware_Notes__c = null;
                }
            }

            update linesToUpdate;

            Integer updateCount = linesToUpdate.size();
            String message = 'Successfully cleared hardware references from ' + updateCount +
                           ' quote line' + (updateCount != 1 ? 's' : '');

            return new HardwareResult(true, message);

        } catch (Exception e) {
            return new HardwareResult(false, 'Error clearing references', e.getMessage());
        }
    }
}