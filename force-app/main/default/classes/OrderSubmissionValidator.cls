/**
 * OrderSubmissionValidator
 *
 * Bulk, metadata-driven "required field is populated" validation for the Order
 * submission path (Update Status -> Order Complete, via the Fortra | Order | Submission
 * Check screen flow).
 *
 * Replaces the per-field FieldPopulatedCheck invocations the flow previously made from
 * inside nested loops (one Apex SOQL per field, per record, per line -> 20 + 5*N queries
 * on an N-line order, which breached the 100-SOQL governor limit on ~16+ line orders --
 * see SC-3366). This action is invoked ONCE with an Order Id and returns every
 * blank-required-field error in CONSTANT SOQL:
 *
 *   1 x Order query + 1 x OrderItem query + 1 query per distinct related object
 *   (e.g. Account, Contact). Validation rules come from custom metadata (no SOQL).
 *   Total is independent of order line count and of the number of rules.
 *
 * Rules live in Order_Submit_Validation__mdt:
 *   Object_API_Name__c             - object the field lives on (Order | OrderItem | Account | Contact | ...)
 *   Field_API_Name__c              - field that must be populated
 *   Relationship_Field_API_Name__c - field ON THE ORDER that resolves the target record:
 *                                      'Id'      -> the Order itself
 *                                      'OrderId' -> per-line OrderItem check (every line)
 *                                      e.g. 'AccountId' / 'BillToContactId' / 'ShipToContactId'
 *                                                -> a related record reached from the Order
 *   Error_Message__c               - message shown when the field is blank
 *
 * "Populated" semantics are preserved from the original FieldPopulatedCheck:
 *   - Boolean false counts as populated (an intentional value)
 *   - text-based types must be non-blank
 *   - all other types must be non-null
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

    @TestVisible
    private static Boolean isFieldPopulated(SObject record, String objName, String fieldName) {
        if (record == null) {
            return false; // no resolvable record == required value missing
        }
        Object rawValue = record.get(fieldName);
        return isValuePopulated(rawValue, getFieldType(objName, fieldName));
    }

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

    private static Schema.DescribeSObjectResult describeObject(String objName) {
        String key = objName.toLowerCase();
        if (!objectDescribes.containsKey(key)) {
            Schema.SObjectType ot = Schema.getGlobalDescribe().get(objName);
            objectDescribes.put(key, (ot == null) ? null : ot.getDescribe());
        }
        return objectDescribes.get(key);
    }

    private static Boolean fieldExists(String objName, String fieldName) {
        if (String.isBlank(objName) || String.isBlank(fieldName)) {
            return false;
        }
        Schema.DescribeSObjectResult d = describeObject(objName);
        return d != null && d.fields.getMap().containsKey(fieldName.toLowerCase());
    }

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
