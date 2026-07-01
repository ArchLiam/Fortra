/**
 * @description Controller for the Quote Migration LWC tool.
 *              Provides AuraEnabled methods for previewing, analyzing,
 *              executing quote proration migrations, and loading
 *              QuoteLineItemAttribute records from CSV.
 * @author Marc DeBrey
 * @version 1.1
 * @since 2026-02
 */
public with sharing class QuoteMigrationController {

    /**
     * @description Get record counts for quotes and QLIs matching the filter
     * @param filter LIKE filter applied to QuoteLineItem.Legacy_Id__c
     * @return MigrationPreview with quote and QLI counts
     */
    @AuraEnabled(cacheable=true)
    public static QuoteMigrationService.MigrationPreview getRecordCounts(String filter) {
        try {
            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }
            return QuoteMigrationService.getRecordCounts(filter);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * @description Analyze field gaps for QLIs matching the filter.
     *              Returns information about null or missing values in
     *              fields that are required for Q2O conversion.
     * @param filter LIKE filter applied to QuoteLineItem.Legacy_Id__c
     * @return List of FieldGapInfo records describing field readiness
     */
    @AuraEnabled(cacheable=true)
    public static List<QuoteMigrationService.FieldGapInfo> getFieldGapAnalysis(String filter) {
        try {
            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }
            return QuoteMigrationService.getFieldGapAnalysis(filter);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * @description Start the migration batch job for quotes matching the filter
     * @param filter LIKE filter applied to QuoteLineItem.Legacy_Id__c
     * @param prepareForQ2O Whether to set Q2O-required fields (BillToContact, etc.)
     * @param batchSize Number of quotes to process per batch chunk (default 10)
     * @param includeReprice Whether to invoke Revenue Cloud pricing after field population
     *        and restore original prices. When true, batchSize is forced to 1.
     * @return The AsyncApexJob Id as a String
     */
    @AuraEnabled
    public static String startMigration(String filter, Boolean prepareForQ2O, Integer batchSize, Boolean includeReprice) {
        try {
            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }

            Integer size = (batchSize != null && batchSize > 0) ? batchSize : 10;
            Boolean doReprice = includeReprice != null ? includeReprice : false;

            QuoteMigrationBatch batch = new QuoteMigrationBatch(filter, prepareForQ2O, size, doReprice);
            // When repricing, force batch size = 1 (the constructor already does this,
            // but we also pass 1 to Database.executeBatch for the QueryLocator chunk size)
            Integer executeBatchSize = doReprice ? 1 : size;
            Id jobId = Database.executeBatch(batch, executeBatchSize);

            return String.valueOf(jobId);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * @description Get the current status of a running or completed batch job.
     *              When the job is complete, also retrieves the most recent
     *              Migration_Run_Log__c record for detailed results.
     * @param jobId The AsyncApexJob Id returned by startMigration
     * @return Map of status fields including progress, counts, and errors
     */
    @AuraEnabled
    public static Map<String, Object> getBatchStatus(String jobId) {
        try {
            if (String.isBlank(jobId)) {
                return new Map<String, Object>{ 'error' => 'Job ID is required' };
            }

            AsyncApexJob job = [
                SELECT Id, Status, JobItemsProcessed, TotalJobItems,
                       NumberOfErrors, CreatedDate, CompletedDate,
                       ExtendedStatus
                FROM AsyncApexJob
                WHERE Id = :jobId
                LIMIT 1
            ];

            Map<String, Object> status = new Map<String, Object>();
            status.put('status', job.Status);
            status.put('itemsProcessed', job.JobItemsProcessed);
            status.put('totalItems', job.TotalJobItems);
            status.put('errors', job.NumberOfErrors);
            status.put('completedDate', job.CompletedDate);

            // Calculate progress percentage
            Integer progress = 0;
            if (job.TotalJobItems != null && job.TotalJobItems > 0) {
                progress = (job.JobItemsProcessed * 100) / job.TotalJobItems;
            }
            status.put('progressPercent', progress);
            status.put('isComplete', job.Status == 'Completed' || job.Status == 'Failed' || job.Status == 'Aborted');

            // If complete, get the most recent migration log for detailed results
            if (job.Status == 'Completed' || job.Status == 'Failed' || job.Status == 'Aborted') {
                List<Migration_Run_Log__c> logs = [
                    SELECT Id, Name, Run_Date__c, Filter_Used__c,
                           Quotes_Processed__c, Quotes_Succeeded__c,
                           QLIs_Processed__c, QLIs_Succeeded__c, QLIs_Skipped__c,
                           Errors__c, Status__c
                    FROM Migration_Run_Log__c
                    ORDER BY Run_Date__c DESC
                    LIMIT 1
                ];
                if (!logs.isEmpty()) {
                    Migration_Run_Log__c log = logs[0];
                    status.put('quotesProcessed', log.Quotes_Processed__c);
                    status.put('quotesSucceeded', log.Quotes_Succeeded__c);
                    status.put('qlisProcessed', log.QLIs_Processed__c);
                    status.put('qlisSucceeded', log.QLIs_Succeeded__c);
                    status.put('qlisSkipped', log.QLIs_Skipped__c);
                    status.put('migrationErrors', log.Errors__c);
                    status.put('migrationStatus', log.Status__c);
                }
            }

            return status;
        } catch (Exception e) {
            return new Map<String, Object>{ 'error' => e.getMessage() };
        }
    }

    /**
     * @description Get active Migration Field Default custom metadata records.
     *              These define default values to apply during migration
     *              for fields that lack source data.
     * @return List of active Migration_Field_Default__mdt records
     */
    @AuraEnabled(cacheable=true)
    public static List<Migration_Field_Default__mdt> getMigrationDefaults() {
        try {
            return [
                SELECT DeveloperName, MasterLabel, Target_Object__c, Target_Field__c,
                       Default_Value__c, Lookup_Object__c, Lookup_Name_Filter__c,
                       Is_Active__c, Description__c
                FROM Migration_Field_Default__mdt
                WHERE Is_Active__c = true
                ORDER BY Target_Object__c, Target_Field__c
            ];
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    // ── Attribute Loading Methods ─────────────────────────────────────

    /**
     * @description Preview what the attribute CSV load will do, without inserting records.
     *              Validates attribute names against AttributeDefinition, checks picklist
     *              values, counts existing QLIA records that would be skipped.
     * @param csvContent Raw CSV text from the uploaded file
     * @return AttributePreview with counts, attribute names, warnings, and errors
     */
    @AuraEnabled
    public static AttributeLoadingService.AttributePreview previewAttributeLoad(String csvContent) {
        try {
            if (String.isBlank(csvContent)) {
                AuraHandledException ahe = new AuraHandledException('CSV content is required');
                ahe.setMessage('CSV content is required');
                throw ahe;
            }
            return AttributeLoadingService.previewLoad(csvContent);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * @description Start the attribute loading batch job.
     *              Parses the CSV, builds lookup maps, and launches the batch.
     * @param csvContent Raw CSV text from the uploaded file
     * @return The AsyncApexJob Id as a String
     */
    @AuraEnabled
    public static String startAttributeLoad(String csvContent) {
        try {
            if (String.isBlank(csvContent)) {
                AuraHandledException ahe = new AuraHandledException('CSV content is required');
                ahe.setMessage('CSV content is required');
                throw ahe;
            }

            // Parse CSV
            Map<String, Map<String, String>> attrData =
                AttributeLoadingService.buildAttributeMap(csvContent);

            if (attrData.isEmpty()) {
                AuraHandledException ahe = new AuraHandledException(
                    'No valid data found in CSV');
                ahe.setMessage('No valid data found in CSV');
                throw ahe;
            }

            // Build lookup maps (resolved once, passed to batch)
            Map<String, Id> attrDefMap = AttributeLoadingService.buildAttrDefMap();
            Set<Id> attrDefIds = new Set<Id>(attrDefMap.values());
            Map<String, Map<String, Id>> picklistMap =
                AttributeLoadingService.buildPicklistValueMap(attrDefIds);

            // Execute batch (200 QLIs per chunk)
            AttributeLoadingBatch batch = new AttributeLoadingBatch(
                attrData, attrDefMap, picklistMap);
            Id jobId = Database.executeBatch(batch, 200);

            return String.valueOf(jobId);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * @description Get the current status of a running or completed attribute loading batch.
     *              Reuses the same AsyncApexJob + Migration_Run_Log pattern as getBatchStatus.
     * @param jobId The AsyncApexJob Id returned by startAttributeLoad
     * @return Map of status fields including progress, counts, and errors
     */
    @AuraEnabled
    public static Map<String, Object> getAttributeLoadStatus(String jobId) {
        // Reuse the existing batch status method — same AsyncApexJob + log pattern
        return getBatchStatus(jobId);
    }
}