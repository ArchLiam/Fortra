/**
 * FieldPopulatedCheck
 *
 * Invocable Action for use in Salesforce Flow.
 * Dynamically checks whether a field is populated on any SObject record
 * and returns both a Boolean flag and the field value as a String.
 *
 * Inputs  (all required):
 *   - recordId   : The 18-char ID of the record to evaluate
 *   - objectName : SObject API name  (e.g. "Account", "My_Object__c")
 *   - fieldName  : Field API name    (e.g. "Phone", "Close_Date__c")
 *
 * Outputs:
 *   - isPopulated : Boolean — true if the field has a non-null / non-blank value
 *   - fieldValue  : String  — the field value serialised to text, or null if empty
 *
 * Notes:
 *   - Field data type is resolved automatically via Schema — no input needed.
 *   - SOQL injection is prevented by validating inputs against Schema metadata
 *     before any query is executed.
 *   - Errors are caught per-record; a bad request returns isPopulated=false
 *     rather than failing the entire Flow interview.
 */
public with sharing class FieldPopulatedCheck {

    // ─────────────────────────────────────────────────────────────
    // Request / Response Wrappers
    // ─────────────────────────────────────────────────────────────

    public class ActionRequest {

        @InvocableVariable(
            label='Record ID'
            description='The ID of the record to evaluate.'
            required=true
        )
        public Id recordId;

        @InvocableVariable(
            label='Object API Name'
            description='API name of the SObject (e.g. Account, My_Custom_Object__c).'
            required=true
        )
        public String objectName;

        @InvocableVariable(
            label='Field API Name'
            description='API name of the field to check (e.g. Phone, My_Field__c).'
            required=true
        )
        public String fieldName;
    }

    public class ActionResult {

        @InvocableVariable(
            label='Is Populated'
            description='True if the field contains a value; false if null or blank.'
        )
        public Boolean isPopulated;

        @InvocableVariable(
            label='Field Value'
            description='The value of the field serialised as text. Null if the field is empty.'
        )
        public String fieldValue;
    }

    // ─────────────────────────────────────────────────────────────
    // Invocable Entry Point
    // ─────────────────────────────────────────────────────────────

    @InvocableMethod(
        label='Check If Field Is Populated'
        description='Checks whether a field has a value on any SObject. Returns isPopulated (Boolean) and fieldValue (Text).'
        category='Utilities'
    )
    public static List<ActionResult> checkFieldPopulated(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();

        for (ActionRequest req : requests) {
            ActionResult result = new ActionResult();
            result.isPopulated = false;
            result.fieldValue  = null;

            try {
                // ── 1. Validate inputs are present ───────────────
                if (req.recordId == null
                        || String.isBlank(req.objectName)
                        || String.isBlank(req.fieldName)) {
                    results.add(result);
                    continue;
                }

                String objName   = req.objectName.trim();
                String fieldName = req.fieldName.trim();

                // ── 2. Validate object + field exist via Schema ───
                //    This is the injection-safe alternative to
                //    escapeSingleQuotes on dynamic identifiers.
                Schema.SObjectType objType = Schema.getGlobalDescribe().get(objName);
                if (objType == null) {
                    System.debug(LoggingLevel.WARN,
                        'FieldPopulatedCheck: Unknown object "' + objName + '"');
                    results.add(result);
                    continue;
                }

                Map<String, Schema.SObjectField> fieldMap =
                    objType.getDescribe().fields.getMap();

                Schema.SObjectField sField = fieldMap.get(fieldName.toLowerCase());
                if (sField == null) {
                    System.debug(LoggingLevel.WARN,
                        'FieldPopulatedCheck: Unknown field "' + fieldName
                        + '" on object "' + objName + '"');
                    results.add(result);
                    continue;
                }

                // Resolve the canonical API name from Schema (preserves case correctly)
                String canonicalField = sField.getDescribe().getName();
                Schema.DisplayType displayType = sField.getDescribe().getType();

                // ── 3. Dynamic SOQL — safe because identifiers are
                //    sourced from Schema, not raw user input ────────
                String recIdStr = String.valueOf(req.recordId);
                String query = 'SELECT ' + canonicalField
                             + ' FROM '  + objName
                             + ' WHERE Id = \'' + recIdStr + '\''
                             + ' LIMIT 1';

                List<SObject> records = Database.query(query);

                if (records.isEmpty()) {
                    results.add(result);
                    continue;
                }

                // ── 4. Evaluate and serialise ────────────────────
                SObject record = records[0];
                Object rawValue = record.get(canonicalField);

                result.isPopulated = isValuePopulated(rawValue, displayType);
                result.fieldValue  = result.isPopulated
                                   ? serialiseValue(rawValue, displayType)
                                   : null;

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'FieldPopulatedCheck error [' + req.fieldName + ']: '
                    + e.getMessage() + '\n' + e.getStackTraceString());
                result.isPopulated = false;
                result.fieldValue  = null;
            }

            results.add(result);
        }

        return results;
    }

    // ─────────────────────────────────────────────────────────────
    // Evaluation — is the raw value considered "populated"?
    // ─────────────────────────────────────────────────────────────

    private static Boolean isValuePopulated(Object rawValue, Schema.DisplayType dt) {
        if (rawValue == null) {
            return false;
        }

        // Checkbox: false is a valid, intentional value → always populated when non-null
        if (dt == Schema.DisplayType.BOOLEAN) {
            return true;
        }

        // Text-based types: populated only when non-blank
        if (isTextType(dt)) {
            return String.isNotBlank(String.valueOf(rawValue));
        }

        // Everything else (Date, DateTime, Number, Currency, Reference, etc.)
        // is populated as long as it is non-null, which we already checked above.
        return true;
    }

    // ─────────────────────────────────────────────────────────────
    // Serialisation — convert raw value → human-readable String
    // ─────────────────────────────────────────────────────────────

    private static String serialiseValue(Object rawValue, Schema.DisplayType dt) {
        if (rawValue == null) {
            return null;
        }

        if (dt == Schema.DisplayType.DATE) {
            return String.valueOf((Date) rawValue);               // YYYY-MM-DD
        }

        if (dt == Schema.DisplayType.DATETIME) {
            Datetime dtVal = (Datetime) rawValue;
            return dtVal.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''); // ISO-8601 UTC
        }

        if (dt == Schema.DisplayType.BOOLEAN) {
            return String.valueOf((Boolean) rawValue);            // "true" / "false"
        }

        if (dt == Schema.DisplayType.DOUBLE
                || dt == Schema.DisplayType.CURRENCY
                || dt == Schema.DisplayType.PERCENT) {
            return String.valueOf((Double) rawValue);
        }

        if (dt == Schema.DisplayType.INTEGER) {
            return String.valueOf((Integer) rawValue);
        }

        // ID / Reference
        if (dt == Schema.DisplayType.REFERENCE || dt == Schema.DisplayType.ID) {
            return String.valueOf(rawValue);
        }

        // Compound types (Address, Location) — JSON-style via standard toString
        if (dt == Schema.DisplayType.ADDRESS || dt == Schema.DisplayType.LOCATION) {
            return String.valueOf(rawValue);
        }

        // Default: all text-based types and any unrecognised type
        return String.valueOf(rawValue);
    }

    // ─────────────────────────────────────────────────────────────
    // Helper — is this display type text-based?
    // ─────────────────────────────────────────────────────────────

    private static Boolean isTextType(Schema.DisplayType dt) {
        return dt == Schema.DisplayType.STRING
            || dt == Schema.DisplayType.EMAIL
            || dt == Schema.DisplayType.PHONE
            || dt == Schema.DisplayType.URL
            || dt == Schema.DisplayType.PICKLIST
            || dt == Schema.DisplayType.MULTIPICKLIST
            || dt == Schema.DisplayType.TEXTAREA
            || dt == Schema.DisplayType.ENCRYPTEDSTRING
            || dt == Schema.DisplayType.COMBOBOX;
    }
}