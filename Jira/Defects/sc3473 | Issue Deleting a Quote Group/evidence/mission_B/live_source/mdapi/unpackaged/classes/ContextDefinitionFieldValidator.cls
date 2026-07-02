/**
 * @description Validates field updateability for Context Definition dependency management.
 *              This class checks whether key fields can be updated via DML.
 *
 * Schema (Revenue Cloud):
 * - ContextDefinition → ExpressionSetDefinitionContextDefinition (junction)
 *   → ExpressionSetDefinition → ExpressionSet → ExpressionSetVersion
 * - ExpressionSetVersion.IsActive is a boolean field (updateable)
 *
 * @usage Execute via Anonymous Apex or as part of dependency management flow
 */
public with sharing class ContextDefinitionFieldValidator {

    /**
     * @description Wrapper class to hold field validation results
     */
    public class FieldValidationResult {
        @AuraEnabled public String objectName { get; set; }
        @AuraEnabled public String fieldName { get; set; }
        @AuraEnabled public Boolean exists { get; set; }
        @AuraEnabled public Boolean isUpdateable { get; set; }
        @AuraEnabled public Boolean isCreateable { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public List<String> picklistValues { get; set; }
        @AuraEnabled public String message { get; set; }

        public FieldValidationResult() {
            this.picklistValues = new List<String>();
        }
    }

    /**
     * @description Master validation result containing all field checks
     */
    public class ValidationReport {
        @AuraEnabled public List<FieldValidationResult> results { get; set; }
        @AuraEnabled public Boolean allFieldsUpdateable { get; set; }
        @AuraEnabled public Boolean requiresMetadataApi { get; set; }
        @AuraEnabled public String summary { get; set; }
        @AuraEnabled public Datetime validatedAt { get; set; }

        public ValidationReport() {
            this.results = new List<FieldValidationResult>();
            this.allFieldsUpdateable = true;
            this.requiresMetadataApi = false;
            this.validatedAt = Datetime.now();
        }
    }

    /**
     * @description Main validation method - checks all relevant fields for dependency management
     * @return ValidationReport containing results for all checked fields
     */
    @AuraEnabled(cacheable=true)
    public static ValidationReport validateAllFields() {
        ValidationReport report = new ValidationReport();

        // Check ExpressionSetVersion.IsActive (primary field for deactivation)
        report.results.add(validateField('ExpressionSetVersion', 'IsActive'));

        // Check ExpressionSetVersion.ExpressionSetId (relationship field)
        report.results.add(validateField('ExpressionSetVersion', 'ExpressionSetId'));

        // Check ExpressionSet.ExpressionSetDefinitionId
        report.results.add(validateField('ExpressionSet', 'ExpressionSetDefinitionId'));

        // Check junction object fields
        report.results.add(validateField('ExpressionSetDefinitionContextDefinition', 'ContextDefinitionId'));
        report.results.add(validateField('ExpressionSetDefinitionContextDefinition', 'ExpressionSetDefinitionId'));

        // Check ContextDefinition fields
        report.results.add(validateField('ContextDefinition', 'DeveloperName'));
        report.results.add(validateField('ContextDefinition', 'MasterLabel'));

        // Analyze results and build summary
        List<String> nonUpdateableFields = new List<String>();
        Boolean isActiveUpdateable = false;

        for (FieldValidationResult result : report.results) {
            // We specifically care if IsActive is updateable
            if (result.objectName == 'ExpressionSetVersion' && result.fieldName == 'IsActive') {
                isActiveUpdateable = result.isUpdateable;
            }

            if (result.exists && !result.isUpdateable &&
                result.objectName == 'ExpressionSetVersion' && result.fieldName == 'IsActive') {
                report.allFieldsUpdateable = false;
                nonUpdateableFields.add(result.objectName + '.' + result.fieldName);
            }
        }

        if (!isActiveUpdateable) {
            report.requiresMetadataApi = true;
            report.summary = 'ExpressionSetVersion.IsActive is NOT updateable via DML. ' +
                            'Metadata API may be required for deactivation.';
        } else {
            report.summary = 'ExpressionSetVersion.IsActive is updateable via DML. ' +
                            'Direct updates can be used for activation/deactivation.';
        }

        return report;
    }

    /**
     * @description Validates a specific field on a given object
     * @param objectName The API name of the SObject
     * @param fieldName The API name of the field
     * @return FieldValidationResult with details about the field
     */
    @AuraEnabled(cacheable=true)
    public static FieldValidationResult validateField(String objectName, String fieldName) {
        FieldValidationResult result = new FieldValidationResult();
        result.objectName = objectName;
        result.fieldName = fieldName;

        try {
            // Check if object exists
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType == null) {
                result.exists = false;
                result.isUpdateable = false;
                result.isCreateable = false;
                result.message = 'Object ' + objectName + ' does not exist in this org';
                return result;
            }

            // Get field describe
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

            if (!fieldMap.containsKey(fieldName.toLowerCase())) {
                result.exists = false;
                result.isUpdateable = false;
                result.isCreateable = false;
                result.message = 'Field ' + fieldName + ' does not exist on ' + objectName;
                return result;
            }

            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName.toLowerCase()).getDescribe();

            result.exists = true;
            result.isUpdateable = fieldDescribe.isUpdateable();
            result.isCreateable = fieldDescribe.isCreateable();
            result.fieldType = String.valueOf(fieldDescribe.getType());

            // Get picklist values if applicable
            if (fieldDescribe.getType() == Schema.DisplayType.PICKLIST) {
                for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                    if (entry.isActive()) {
                        result.picklistValues.add(entry.getValue());
                    }
                }
            }

            // Build message
            if (result.isUpdateable) {
                result.message = 'Field is updateable via DML';
            } else {
                result.message = 'Field is NOT updateable via DML';
            }

        } catch (Exception e) {
            result.exists = false;
            result.isUpdateable = false;
            result.message = 'Error validating field: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Checks if an SObject exists in the org
     * @param objectName The API name of the SObject
     * @return True if the object exists
     */
    public static Boolean objectExists(String objectName) {
        return Schema.getGlobalDescribe().containsKey(objectName);
    }

    /**
     * @description Generates a text-based report for console output
     * @return Formatted string report
     */
    public static String generateTextReport() {
        ValidationReport report = validateAllFields();

        String output = '\n========================================\n';
        output += 'CONTEXT DEFINITION FIELD VALIDATION REPORT\n';
        output += 'Generated: ' + report.validatedAt.format() + '\n';
        output += '========================================\n\n';

        for (FieldValidationResult result : report.results) {
            output += 'Object: ' + result.objectName + '\n';
            output += 'Field:  ' + result.fieldName + '\n';
            output += 'Exists: ' + result.exists + '\n';

            if (result.exists) {
                output += 'Type:       ' + result.fieldType + '\n';
                output += 'Updateable: ' + result.isUpdateable + '\n';
                output += 'Createable: ' + result.isCreateable + '\n';

                if (!result.picklistValues.isEmpty()) {
                    output += 'Values:     ' + String.join(result.picklistValues, ', ') + '\n';
                }
            }

            output += 'Status: ' + result.message + '\n';
            output += '----------------------------------------\n';
        }

        output += '\nSUMMARY\n';
        output += '-------\n';
        output += 'All Fields Updateable: ' + report.allFieldsUpdateable + '\n';
        output += 'Requires Metadata API: ' + report.requiresMetadataApi + '\n';
        output += report.summary + '\n';
        output += '========================================\n';

        return output;
    }
}