/**
 * @description Bulk, metadata-driven validation that every required field on an Order, its lines,
 * and its related records is populated for the Order submission path. Evaluates all active
 * Order_Submit_Validation__mdt rules in constant SOQL (one Order query, one OrderItem query, and
 * one query per distinct related object) regardless of order line count, preserving the original
 * FieldPopulatedCheck "populated" semantics: Boolean false counts as populated, text types must be
 * non-blank, and all other types must be non-null.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class OrderSubmissionValidator {

    private static final String BULLET = '• ';

    // -----------------------------------------------------------------
    // Invocable request / result
    // -----------------------------------------------------------------

    public class ValidationRequest {
        @InvocableVariable(label='Order Id' description='Id of the Order to validate.' required=true)
        public Id orderId;
    }

    public class ValidationResult {
        @InvocableVariable(label='Has Errors' description='True if any required field is blank.')
        public Boolean hasErrors = false;

        @InvocableVariable(label='Error Count' description='Number of validation errors.')
        public Integer errorCount = 0;

        @InvocableVariable(label='Error Messages' description='Formatted error messages, one per blank field.')
        public List<String> errorMessages = new List<String>();

        @InvocableVariable(label='Error Display' description='All error messages concatenated for screen display.')
        public String errorDisplay = '';
    }

    // -----------------------------------------------------------------
    // Invocable entry point
    // -----------------------------------------------------------------

    /**
     * @description Validates all active Order_Submit_Validation__mdt required-field rules for each
     * requested Order, its OrderItem lines, and its related records in constant SOQL, returning the
     * blank-field errors.
     * @param requests Invocable requests, each carrying the Id of an Order to validate.
     * @return One ValidationResult per request, in the same order, holding the blank-field errors.
     */
    @InvocableMethod(
        label='Validate Order Submission'
        description='Validates all active Order_Submit_Validation__mdt required fields for an Order, its lines, and its related records in constant SOQL. Returns the blank-field errors.'
        category='Order'
    )
    public static List<ValidationResult> validate(List<ValidationRequest> requests) {
        List<ValidationResult> results = new List<ValidationResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        // 1. Collect order ids
        Set<Id> orderIds = new Set<Id>();
        for (ValidationRequest req : requests) {
            if (req != null && req.orderId != null) {
                orderIds.add(req.orderId);
            }
        }

        // 2. Load active rules (custom metadata; a single fixed query regardless of order size)
        List<Order_Submit_Validation__mdt> rules = [
            SELECT Object_API_Name__c, Field_API_Name__c,
                   Relationship_Field_API_Name__c, Error_Message__c
            FROM Order_Submit_Validation__mdt
            WHERE Active__c = true
        ];

        // 3. Plan the queries: which fields per object, and which Order FK fields resolve related records.
        //    Invalid object/field config is skipped (keeps one bad rule from breaking the whole run).
        Set<String> orderFields = new Set<String>{ 'Id' };
        Set<String> itemFields  = new Set<String>{ 'Id', 'OrderId' };
        Map<String, Set<String>> relatedFieldsByObject = new Map<String, Set<String>>();   // Account -> {fields}
        Map<String, Set<String>> relatedRelFieldsByObject = new Map<String, Set<String>>(); // Account -> {AccountId}

        List<Order_Submit_Validation__mdt> validRules = new List<Order_Submit_Validation__mdt>();
        for (Order_Submit_Validation__mdt r : rules) {
            String obj = (r.Object_API_Name__c == null) ? '' : r.Object_API_Name__c.trim();
            String fld = (r.Field_API_Name__c == null)  ? '' : r.Field_API_Name__c.trim();
            if (!fieldExists(obj, fld)) {
                continue;
            }
            if (obj == 'Order') {
                orderFields.add(fld);
            } else if (obj == 'OrderItem') {
                itemFields.add(fld);
            } else {
                String relF = (r.Relationship_Field_API_Name__c == null) ? '' : r.Relationship_Field_API_Name__c.trim();
                if (!fieldExists('Order', relF)) {
                    continue; // can't resolve the related record without a valid Order FK field
                }
                orderFields.add(relF);
                if (!relatedFieldsByObject.containsKey(obj)) {
                    relatedFieldsByObject.put(obj, new Set<String>{ 'Id' });
                    relatedRelFieldsByObject.put(obj, new Set<String>());
                }
                relatedFieldsByObject.get(obj).add(fld);
                relatedRelFieldsByObject.get(obj).add(relF);
            }
            validRules.add(r);
        }

        // 4. Query Orders (1 SOQL) and OrderItems (1 SOQL)
        Map<Id, SObject> ordersById = new Map<Id, SObject>(
            Database.query(
                'SELECT ' + String.join(new List<String>(orderFields), ', ') +
                ' FROM Order WHERE Id IN :orderIds'
            )
        );

        Map<Id, List<SObject>> itemsByOrder = new Map<Id, List<SObject>>();
        for (SObject oi : Database.query(
                'SELECT ' + String.join(new List<String>(itemFields), ', ') +
                ' FROM OrderItem WHERE OrderId IN :orderIds')) {
            Id parent = (Id) oi.get('OrderId');
            if (!itemsByOrder.containsKey(parent)) {
                itemsByOrder.put(parent, new List<SObject>());
            }
            itemsByOrder.get(parent).add(oi);
        }

        // 5. Query each distinct related object once (1 SOQL per object) for all referenced ids
        Map<String, Map<Id, SObject>> relatedRecords = new Map<String, Map<Id, SObject>>();
        for (String obj : relatedFieldsByObject.keySet()) {
            Set<Id> ids = new Set<Id>();
            for (SObject ord : ordersById.values()) {
                for (String relF : relatedRelFieldsByObject.get(obj)) {
                    Id v = (Id) ord.get(relF);
                    if (v != null) {
                        ids.add(v);
                    }
                }
            }
            Map<Id, SObject> recs = new Map<Id, SObject>();
            if (!ids.isEmpty()) {
                Set<String> flds = relatedFieldsByObject.get(obj);
                recs = new Map<Id, SObject>(
                    Database.query(
                        'SELECT ' + String.join(new List<String>(flds), ', ') +
                        ' FROM ' + obj + ' WHERE Id IN :ids'
                    )
                );
            }
            relatedRecords.put(obj, recs);
        }

        // 6. Evaluate every rule for every requested order
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        for (ValidationRequest req : requests) {
            ValidationResult res = new ValidationResult();
            Id oid = (req == null) ? null : req.orderId;
            SObject ord = (oid == null) ? null : ordersById.get(oid);

            if (ord != null) {
                List<SObject> lines = itemsByOrder.containsKey(oid)
                                    ? itemsByOrder.get(oid) : new List<SObject>();
                for (Order_Submit_Validation__mdt r : validRules) {
                    try {
                        evaluateRule(res, baseUrl, r, ord, lines, relatedRecords);
                    } catch (Exception e) {
                        ExceptionLogger.log('OrderSubmissionValidator', oid, new OrderSubmissionException('validate failed', e));
                        System.debug(LoggingLevel.ERROR, 'OrderSubmissionValidator rule error ['
                            + r.Object_API_Name__c + '.' + r.Field_API_Name__c + ']: ' + e.getMessage());
                    }
                }
            }

            res.errorCount   = res.errorMessages.size();
            res.hasErrors    = res.errorCount > 0;
            res.errorDisplay = String.join(res.errorMessages, '');
            results.add(res);
        }

        return results;
    }

    // -----------------------------------------------------------------
    // Rule evaluation
    // -----------------------------------------------------------------

    /**
     * @description Evaluates a single validation rule against the resolved Order, its lines, or the
     * related record it points to, adding a formatted error when the required field is blank.
     * @param res The result accumulator to append any error message to.
     * @param baseUrl The org base URL used to build a record link in the error message.
     * @param r The validation rule (object, field, relationship field, and error message).
     * @param ord The Order record being validated.
     * @param lines The OrderItem lines of the Order, evaluated when the rule targets OrderItem.
     * @param relatedRecords Related records keyed by object API name then record Id.
     */
    private static void evaluateRule(
            ValidationResult res, String baseUrl, Order_Submit_Validation__mdt r,
            SObject ord, List<SObject> lines, Map<String, Map<Id, SObject>> relatedRecords) {

        String obj = r.Object_API_Name__c.trim();
        String fld = r.Field_API_Name__c.trim();

        if (obj == 'Order') {
            if (!isFieldPopulated(ord, obj, fld)) {
                addError(res, baseUrl, obj, (Id) ord.get('Id'), r.Error_Message__c);
            }
        } else if (obj == 'OrderItem') {
            for (SObject line : lines) {
                if (!isFieldPopulated(line, obj, fld)) {
                    addError(res, baseUrl, obj, (Id) line.get('Id'), r.Error_Message__c);
                }
            }
        } else {
            Id relId = (Id) ord.get(r.Relationship_Field_API_Name__c.trim());
            SObject relRec = (relId == null) ? null : relatedRecords.get(obj).get(relId);
            if (!isFieldPopulated(relRec, obj, fld)) {
                addError(res, baseUrl, obj, relId, r.Error_Message__c);
            }
        }
    }

    /**
     * @description Builds a formatted, bulleted error message with an optional record link and adds
     * it to the result's error list.
     * @param res The result accumulator to append the message to.
     * @param baseUrl The org base URL used to build the record link.
     * @param objName The API name of the object the error record belongs to.
     * @param recordId The Id of the offending record, or null to omit the link.
     * @param message The error message text, defaulted when blank.
     */
    private static void addError(ValidationResult res, String baseUrl,
                                 String objName, Id recordId, String message) {
        String text = String.isBlank(message) ? 'Required field is missing.' : message;
        String formatted = BULLET + text;
        if (recordId != null) {
            formatted += '  <a href="' + baseUrl + '/lightning/r/' + objName + '/'
                       + recordId + '/view">Link to Record</a>';
        }
        formatted += '<br>';
        res.errorMessages.add(formatted);
    }

    // -----------------------------------------------------------------
    // "Is populated?" evaluation (preserves FieldPopulatedCheck semantics)
    // -----------------------------------------------------------------

    /**
     * @description Determines whether the given field on a record holds a populated value, treating
     * a missing record as not populated.
     * @param record The record to inspect, or null when no record resolved.
     * @param objName The API name of the object, used to resolve the field type.
     * @param fieldName The API name of the field to check.
     * @return True when the record exists and the field value counts as populated.
     */
    @TestVisible
    private static Boolean isFieldPopulated(SObject record, String objName, String fieldName) {
        if (record == null) {
            return false; // no resolvable record == required value missing
        }
        Object rawValue = record.get(fieldName);
        return isValuePopulated(rawValue, getFieldType(objName, fieldName));
    }

    /**
     * @description Applies the FieldPopulatedCheck "is populated" semantics to a raw value given its
     * display type: Boolean false counts as populated, text types must be non-blank, and all other
     * types must be non-null.
     * @param rawValue The field value to evaluate.
     * @param dt The Schema display type of the field.
     * @return True when the value counts as populated for its type.
     */
    @TestVisible
    private static Boolean isValuePopulated(Object rawValue, Schema.DisplayType dt) {
        if (rawValue == null) {
            return false;
        }
        if (dt == Schema.DisplayType.BOOLEAN) {
            return true; // false is a valid, intentional value
        }
        if (isTextType(dt)) {
            return String.isNotBlank(String.valueOf(rawValue));
        }
        return true; // Date, Number, Currency, Reference, etc. -> populated when non-null
    }

    /**
     * @description Reports whether the given display type is one of the text-based types whose
     * populated check requires a non-blank string.
     * @param dt The Schema display type to classify.
     * @return True when the type is text-based.
     */
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

    // -----------------------------------------------------------------
    // Schema describe helpers (cached per transaction; injection-safe planning)
    // -----------------------------------------------------------------

    private static Map<String, Schema.DescribeSObjectResult> objectDescribes =
        new Map<String, Schema.DescribeSObjectResult>();
    private static Map<String, Schema.DisplayType> fieldTypeCache =
        new Map<String, Schema.DisplayType>();

    /**
     * @description Returns the describe result for the named object, caching it per transaction.
     * @param objName The API name of the object to describe.
     * @return The DescribeSObjectResult, or null when the object does not exist.
     */
    private static Schema.DescribeSObjectResult describeObject(String objName) {
        String key = objName.toLowerCase();
        if (!objectDescribes.containsKey(key)) {
            Schema.SObjectType ot = Schema.getGlobalDescribe().get(objName);
            objectDescribes.put(key, (ot == null) ? null : ot.getDescribe());
        }
        return objectDescribes.get(key);
    }

    /**
     * @description Checks whether the named field exists on the named object.
     * @param objName The API name of the object.
     * @param fieldName The API name of the field.
     * @return True when both are non-blank and the field exists on the object.
     */
    private static Boolean fieldExists(String objName, String fieldName) {
        if (String.isBlank(objName) || String.isBlank(fieldName)) {
            return false;
        }
        Schema.DescribeSObjectResult d = describeObject(objName);
        return d != null && d.fields.getMap().containsKey(fieldName.toLowerCase());
    }

    /**
     * @description Returns the display type of the named field, caching it per transaction and
     * defaulting to STRING when the object or field cannot be resolved.
     * @param objName The API name of the object.
     * @param fieldName The API name of the field.
     * @return The Schema display type of the field.
     */
    private static Schema.DisplayType getFieldType(String objName, String fieldName) {
        String key = objName.toLowerCase() + '.' + fieldName.toLowerCase();
        if (!fieldTypeCache.containsKey(key)) {
            Schema.DescribeSObjectResult d = describeObject(objName);
            Schema.SObjectField f = (d == null) ? null : d.fields.getMap().get(fieldName.toLowerCase());
            fieldTypeCache.put(key, (f == null) ? Schema.DisplayType.STRING : f.getDescribe().getType());
        }
        return fieldTypeCache.get(key);
    }
}