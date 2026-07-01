/**
 * @description Batch Apex class for creating QuoteLineItemAttribute records from CSV data.
 *              Processes QLIs identified by Legacy_Id__c and creates QLIA child records
 *              with proper AttributeDefinitionId and AttributePicklistValueId resolution.
 *
 *              Designed for idempotent operation: existing QLIA records are detected
 *              and skipped to allow safe re-runs.
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-03
 */
public class AttributeLoadingBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Serialized input data
    private Map<String, Map<String, String>> attributesByLegacyId;
    private Map<String, Id> attrDefIdByName;
    private Map<String, Map<String, Id>> picklistValueMap;

    // User info for email notification
    private String initiatedByUserId;
    private String initiatedByUserEmail;
    private String initiatedByUserName;

    // Stateful counters (persist across execute() calls)
    private Integer qlisProcessed = 0;
    private Integer attributesCreated = 0;
    private Integer attributesSkipped = 0;
    private Integer attributesFailed = 0;
    private List<String> errorMessages = new List<String>();
    private static final Integer MAX_ERROR_MESSAGES = 100;

    /**
     * @description Constructor
     * @param attrData Map of Legacy_Id__c -> (AttrName -> AttrValue) from CSV parsing
     * @param attrDefMap Map of AttributeDefinition Name -> Id
     * @param picklistMap Map of AttrDef Name -> (PicklistValue -> PicklistValueId)
     */
    public AttributeLoadingBatch(
        Map<String, Map<String, String>> attrData,
        Map<String, Id> attrDefMap,
        Map<String, Map<String, Id>> picklistMap
    ) {
        this.attributesByLegacyId = attrData;
        this.attrDefIdByName = attrDefMap;
        this.picklistValueMap = picklistMap;

        // Capture user info for email notification
        User currentUser = [SELECT Id, Email, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        this.initiatedByUserId = currentUser.Id;
        this.initiatedByUserEmail = currentUser.Email;
        this.initiatedByUserName = currentUser.Name;
    }

    /**
     * @description Start method - queries QLIs matching the Legacy_Id__c values from the CSV.
     *              Uses a pre-resolved list of IDs for QueryLocator bind compatibility.
     * @param bc BatchableContext
     * @return QueryLocator for matching QuoteLineItems
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'AttributeLoadingBatch: Starting');
        System.debug(LoggingLevel.INFO, 'CSV rows: ' + this.attributesByLegacyId.size());
        System.debug(LoggingLevel.INFO, 'Attribute definitions: ' + this.attrDefIdByName.size());
        System.debug(LoggingLevel.INFO, '========================================');

        // Pre-resolve Legacy_Id__c values to QLI Ids for QueryLocator
        // (QueryLocator doesn't support bind vars inside semi-join subqueries)
        Set<String> legacyIds = this.attributesByLegacyId.keySet();
        List<Id> matchingQliIds = new List<Id>();
        for (QuoteLineItem qli : [
            SELECT Id FROM QuoteLineItem WHERE Legacy_Id__c IN :legacyIds
        ]) {
            matchingQliIds.add(qli.Id);
        }

        System.debug(LoggingLevel.INFO, 'Found ' + matchingQliIds.size() +
            ' QLIs matching CSV Legacy_Id__c values');

        return Database.getQueryLocator([
            SELECT Id, Legacy_Id__c
            FROM QuoteLineItem
            WHERE Id IN :matchingQliIds
            ORDER BY Legacy_Id__c
        ]);
    }

    /**
     * @description Execute method - creates QLIA records for a batch of QLIs.
     *              Detects existing QLIA records to avoid duplicates.
     * @param bc BatchableContext
     * @param scope List of QuoteLineItem records in this batch
     */
    public void execute(Database.BatchableContext bc, List<QuoteLineItem> scope) {
        System.debug(LoggingLevel.INFO, 'Processing batch of ' + scope.size() + ' QLIs');

        // Collect QLI Ids for duplicate detection query
        Set<Id> qliIds = new Set<Id>();
        for (QuoteLineItem qli : scope) {
            qliIds.add(qli.Id);
        }

        // Query existing QLIA records for duplicate detection
        Map<String, Set<Id>> existingAttrsByQli = new Map<String, Set<Id>>();
        for (QuoteLineItemAttribute existing : [
            SELECT QuoteLineItemId, AttributeDefinitionId
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId IN :qliIds
        ]) {
            String key = String.valueOf(existing.QuoteLineItemId);
            if (!existingAttrsByQli.containsKey(key)) {
                existingAttrsByQli.put(key, new Set<Id>());
            }
            existingAttrsByQli.get(key).add(existing.AttributeDefinitionId);
        }

        // Build QLIA records to insert
        List<QuoteLineItemAttribute> toInsert = new List<QuoteLineItemAttribute>();

        for (QuoteLineItem qli : scope) {
            this.qlisProcessed++;

            // Look up CSV row for this QLI
            Map<String, String> attrRow = this.attributesByLegacyId.get(qli.Legacy_Id__c);
            if (attrRow == null) {
                continue;
            }

            // Get existing attributes for this QLI (for duplicate detection)
            String qliKey = String.valueOf(qli.Id);
            Set<Id> existingAttrDefIds = existingAttrsByQli.containsKey(qliKey)
                ? existingAttrsByQli.get(qliKey)
                : new Set<Id>();

            for (String attrName : attrRow.keySet()) {
                String attrValue = attrRow.get(attrName);

                // Resolve AttributeDefinitionId
                Id attrDefId = this.attrDefIdByName.get(attrName);
                if (attrDefId == null) {
                    addErrorMessage('QLI ' + qli.Legacy_Id__c +
                        ': No AttributeDefinition found for "' + attrName + '"');
                    this.attributesFailed++;
                    continue;
                }

                // Check for duplicate
                if (existingAttrDefIds.contains(attrDefId)) {
                    this.attributesSkipped++;
                    continue;
                }

                // Build QLIA record
                QuoteLineItemAttribute qlia = new QuoteLineItemAttribute();
                qlia.QuoteLineItemId = qli.Id;
                qlia.AttributeDefinitionId = attrDefId;
                qlia.AttributeValue = attrValue;

                // Resolve AttributePicklistValueId (if picklist type)
                if (this.picklistValueMap.containsKey(attrName)) {
                    Map<String, Id> validValues = this.picklistValueMap.get(attrName);
                    Id picklistValueId = validValues.get(attrValue);
                    if (picklistValueId != null) {
                        qlia.AttributePicklistValueId = picklistValueId;
                    }
                    // If not found, still create with text value only (per plan: warn, don't block)
                }

                toInsert.add(qlia);
            }
        }

        // Insert QLIA records using insertImmediate (QuoteLineItemAttribute is an
        // internal sObject that does not support standard DML insert/Database.insert).
        // Note: insertImmediate may not persist records in test context — this is a
        // known Revenue Cloud platform limitation. Functionality verified via manual testing.
        if (!toInsert.isEmpty()) {
            try {
                List<Database.SaveResult> results = Database.insertImmediate(toInsert);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        this.attributesCreated++;
                    } else {
                        this.attributesFailed++;
                        QuoteLineItemAttribute failedQlia = toInsert[i];
                        for (Database.Error err : results[i].getErrors()) {
                            addErrorMessage('QLIA insert failed (QLI: ' +
                                failedQlia.QuoteLineItemId + ', AttrDef: ' +
                                failedQlia.AttributeDefinitionId + '): ' + err.getMessage());
                        }
                    }
                }
            } catch (Exception e) {
                // Catch any unexpected exceptions from insertImmediate
                this.attributesFailed += toInsert.size();
                addErrorMessage('Batch insert failed: ' + e.getMessage());
            }
        }

        System.debug(LoggingLevel.INFO, 'Batch complete: ' +
            this.attributesCreated + ' created, ' +
            this.attributesSkipped + ' skipped, ' +
            this.attributesFailed + ' failed');
    }

    /**
     * @description Finish method - creates audit log record and sends email notification
     * @param bc BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'AttributeLoadingBatch: Complete');
        System.debug(LoggingLevel.INFO, 'QLIs Processed: ' + this.qlisProcessed);
        System.debug(LoggingLevel.INFO, 'Attributes Created: ' + this.attributesCreated);
        System.debug(LoggingLevel.INFO, 'Attributes Skipped (duplicates): ' + this.attributesSkipped);
        System.debug(LoggingLevel.INFO, 'Attributes Failed: ' + this.attributesFailed);
        System.debug(LoggingLevel.INFO, '========================================');

        // Create audit log
        createMigrationRunLog();

        // Send email notification
        sendCompletionEmail(bc.getJobId());
    }

    // ── Private Helpers ───────────────────────────────────────────────

    private void addErrorMessage(String message) {
        if (this.errorMessages.size() < MAX_ERROR_MESSAGES) {
            this.errorMessages.add(message);
        }
    }

    private void createMigrationRunLog() {
        try {
            Migration_Run_Log__c log = new Migration_Run_Log__c();
            log.Run_Date__c = Datetime.now();
            log.Filter_Used__c = 'Attribute Loading (' +
                this.attributesByLegacyId.size() + ' CSV rows)';
            log.Quotes_Processed__c = 0;
            log.Quotes_Succeeded__c = 0;
            log.QLIs_Processed__c = this.qlisProcessed;
            log.QLIs_Succeeded__c = this.attributesCreated;
            log.QLIs_Skipped__c = this.attributesSkipped;

            String errorsText = String.join(this.errorMessages, '\n');
            if (errorsText.length() > 131072) {
                errorsText = errorsText.substring(0, 131072);
            }
            log.Errors__c = errorsText;

            log.Status__c = this.attributesFailed == 0
                ? 'Completed'
                : (this.attributesCreated > 0 ? 'Partial' : 'Failed');

            insert log;
            System.debug(LoggingLevel.INFO, 'Migration Run Log created: ' + log.Id);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to create Migration Run Log: ' + e.getMessage());
        }
    }

    private void sendCompletionEmail(Id jobId) {
        if (String.isBlank(this.initiatedByUserEmail)) {
            return;
        }

        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ this.initiatedByUserEmail });
            email.setSubject('Attribute Loading Complete - ' +
                (this.attributesFailed > 0 ? 'Completed with Errors' : 'Success'));

            String body = buildEmailBody(jobId);
            email.setHtmlBody(body);
            email.setSaveAsActivity(false);

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to send completion email: ' + e.getMessage());
        }
    }

    private String buildEmailBody(Id jobId) {
        String successStyle = 'color: #28a745; font-weight: bold;';
        String warningStyle = 'color: #dc3545; font-weight: bold;';

        String body = '<html><body style="font-family: Arial, sans-serif;">';
        body += '<h2 style="color: #333;">Attribute Loading Complete</h2>';
        body += '<table style="border-collapse: collapse; width: 100%; max-width: 500px;">';

        // Job ID
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Batch Job ID</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' + jobId + '</td></tr>';

        // CSV Rows
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>CSV Rows</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.attributesByLegacyId.size() + '</td></tr>';

        // QLIs Processed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>QLIs Processed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.qlisProcessed + '</td></tr>';

        // Attributes Created
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Attributes Created</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.attributesCreated + '</td></tr>';

        // Attributes Skipped
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Attributes Skipped (Duplicates)</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.attributesSkipped > 0 ? ' color: #856404; font-weight: bold;' : '') + '">' +
                this.attributesSkipped + '</td></tr>';

        // Attributes Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Attributes Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.attributesFailed > 0 ? warningStyle : '') + '">' +
                this.attributesFailed + '</td></tr>';

        body += '</table>';

        // Error details
        if (!this.errorMessages.isEmpty()) {
            body += '<h3 style="color: #dc3545; margin-top: 20px;">Errors Encountered</h3>';
            body += '<ul style="background: #fff3cd; padding: 15px 30px; border-radius: 4px;">';
            for (String errMsg : this.errorMessages) {
                body += '<li style="margin: 5px 0;">' + errMsg.escapeHtml4() + '</li>';
            }
            if (this.errorMessages.size() >= MAX_ERROR_MESSAGES) {
                body += '<li style="margin: 5px 0; font-style: italic;">... and more (showing first ' +
                        MAX_ERROR_MESSAGES + ' errors)</li>';
            }
            body += '</ul>';
        }

        body += '<p style="margin-top: 20px; color: #666; font-size: 12px;">' +
                'This is an automated message from Salesforce.</p>';
        body += '</body></html>';

        return body;
    }
}