/**
 * @description Controller for the Order Migration LWC tool.
 *              Provides AuraEnabled methods for previewing, analyzing,
 *              and executing order migrations.
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-03
 */
public with sharing class OrderMigrationController {

    /**
     * @description Get record counts for orders and OrderItems matching the filter
     * @param filter LIKE filter applied to OrderItem.Legacy_Id__c
     * @return MigrationPreview with order and item counts
     */
    @AuraEnabled(cacheable=true)
    public static OrderMigrationService.OrderMigrationPreview getRecordCounts(String filter) {
        try {
            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }
            return OrderMigrationService.getRecordCounts(filter);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * @description Analyze field gaps for OrderItems matching the filter.
     *              Returns information about null or missing values in
     *              fields that are required for order activation.
     * @param filter LIKE filter applied to OrderItem.Legacy_Id__c
     * @return List of FieldGapInfo records describing field readiness
     */
    @AuraEnabled(cacheable=true)
    public static List<OrderMigrationService.FieldGapInfo> getFieldGapAnalysis(String filter) {
        try {
            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }
            return OrderMigrationService.getFieldGapAnalysis(filter);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * @description Start the migration batch job for orders matching the filter
     * @param filter LIKE filter applied to OrderItem.Legacy_Id__c
     * @param batchSize Number of orders to process per batch chunk (default 50)
     * @param activateOrders Whether to activate orders and create assets
     * @param activateContracts Whether to activate contracts linked to migrated orders
     * @return The AsyncApexJob Id as a String
     */
    @AuraEnabled
    public static String startMigration(String filter, Integer batchSize, Boolean activateOrders, Boolean activateContracts,
                                        Id targetPricebookId, Boolean autoCreateMissingPbes) {
        try {
            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }

            // Guard: check for sentinel created in last 30 seconds (blocks Aura framework retries)
            Datetime recentWindow = Datetime.now().addSeconds(-30);
            List<Migration_Run_Log__c> recentSentinels = [
                SELECT Id FROM Migration_Run_Log__c
                WHERE Status__c = 'Processing Assets'
                AND Orders_Processed__c = 0
                AND Run_Date__c >= :recentWindow
                LIMIT 1
            ];
            if (!recentSentinels.isEmpty()) {
                AuraHandledException ahe = new AuraHandledException(
                    'A migration batch is already starting. Please wait.');
                ahe.setMessage('A migration batch is already starting. Please wait.');
                throw ahe;
            }

            // Also check for running batches
            List<AsyncApexJob> runningJobs = [
                SELECT Id FROM AsyncApexJob
                WHERE ApexClass.Name = 'OrderMigrationBatch'
                AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
                LIMIT 1
            ];
            if (!runningJobs.isEmpty()) {
                AuraHandledException ahe = new AuraHandledException(
                    'A migration batch is already running. Please wait for it to complete.');
                ahe.setMessage('A migration batch is already running. Please wait for it to complete.');
                throw ahe;
            }

            // Create sentinel run log before launching batch.
            Migration_Run_Log__c sentinel = new Migration_Run_Log__c();
            sentinel.Run_Date__c = Datetime.now();
            sentinel.Start_Time__c = Datetime.now();
            sentinel.Filter_Used__c = filter != null ? filter.left(255) : null;
            sentinel.Status__c = 'Processing Assets';
            sentinel.Orders_Processed__c = 0;
            sentinel.Orders_Succeeded__c = 0;
            sentinel.QLIs_Processed__c = 0;
            sentinel.QLIs_Succeeded__c = 0;
            sentinel.QLIs_Skipped__c = 0;
            sentinel.PST_Succeeded__c = 0;
            sentinel.PST_Failed__c = 0;
            sentinel.Target_Pricebook__c = targetPricebookId;
            sentinel.Quotes_Skipped_No_Coverage__c = 0;
            sentinel.PBEs_Auto_Created__c = 0;
            insert sentinel;

            Integer size = (batchSize != null && batchSize > 0) ? batchSize : 50;
            Boolean doActivateOrders = activateOrders != null ? activateOrders : true;
            Boolean doActivateContracts = activateContracts != null ? activateContracts : true;
            Boolean doAutoCreate = autoCreateMissingPbes == true;

            OrderMigrationBatch batch = new OrderMigrationBatch(
                filter, size, doActivateOrders, doActivateContracts, sentinel.Id,
                targetPricebookId, doAutoCreate);
            Id jobId = Database.executeBatch(batch, size);

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
     * @description Abort an in-flight migration batch job. Salesforce drains any
     *              currently-executing batch (it cannot kill mid-DML transactions),
     *              then marks the job Status='Aborted'. Caller should follow up with
     *              startCleanupByFilter if partial Orders/Contracts were created.
     * @param jobId The AsyncApexJob Id to abort
     */
    @AuraEnabled
    public static void abortMigration(String jobId) {
        try {
            if (String.isBlank(jobId)) {
                AuraHandledException ahe = new AuraHandledException('Job ID is required');
                ahe.setMessage('Job ID is required');
                throw ahe;
            }
            List<AsyncApexJob> jobs = [
                SELECT Id, Status FROM AsyncApexJob WHERE Id = :jobId LIMIT 1
            ];
            if (jobs.isEmpty()) {
                AuraHandledException ahe = new AuraHandledException('Job not found: ' + jobId);
                ahe.setMessage('Job not found: ' + jobId);
                throw ahe;
            }
            String currentStatus = jobs[0].Status;
            if (currentStatus == 'Completed' || currentStatus == 'Failed' || currentStatus == 'Aborted') {
                return;
            }
            System.abortJob(jobId);
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
     *              Migration_Run_Log__c record for detailed results including
     *              order-specific fields.
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

            // If complete, get the migration log for this batch job.
            if (job.Status == 'Completed' || job.Status == 'Failed' || job.Status == 'Aborted') {
                // Sentinel run log is created seconds before the batch job,
                // so look back 60 seconds from the job's CreatedDate.
                Datetime logWindow = job.CreatedDate.addSeconds(-60);
                List<Migration_Run_Log__c> logs = [
                    SELECT Id, Name, Run_Date__c, Filter_Used__c,
                           Orders_Processed__c, Orders_Succeeded__c,
                           QLIs_Processed__c, QLIs_Succeeded__c, QLIs_Skipped__c,
                           PST_Succeeded__c, PST_Failed__c,
                           Errors__c, Status__c
                    FROM Migration_Run_Log__c
                    WHERE Run_Date__c >= :logWindow
                    ORDER BY Run_Date__c DESC
                    LIMIT 1
                ];
                if (!logs.isEmpty()) {
                    Migration_Run_Log__c log = logs[0];
                    status.put('runLogId', log.Id);
                    status.put('ordersProcessed', log.Orders_Processed__c);
                    status.put('ordersSucceeded', log.Orders_Succeeded__c);
                    status.put('qlisProcessed', log.QLIs_Processed__c);
                    status.put('qlisSucceeded', log.QLIs_Succeeded__c);
                    status.put('qlisSkipped', log.QLIs_Skipped__c);
                    status.put('assetsSucceeded', log.PST_Succeeded__c);
                    status.put('assetsFailed', log.PST_Failed__c);
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
     * @description Execute a SOQL query in SOQL mode and return preview results.
     *              Safety guards (IsPrimary__c, Closed Won) are auto-injected.
     * @param filter The user-provided SOQL SELECT statement targeting Quote
     * @return Map with columns (List<String>), rows (List<Map<String,Object>>), totalRows (Integer)
     */
    @AuraEnabled
    public static Map<String, Object> getSoqlPreviewResults(String filter) {
        try {
            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }

            List<Map<String, Object>> rows = OrderMigrationService.executeSoqlPreview(filter);

            // Extract column names from first row (or empty list)
            List<String> columns = new List<String>();
            if (!rows.isEmpty()) {
                columns.addAll(rows[0].keySet());
                columns.sort();
            }

            return new Map<String, Object>{
                'columns' => columns,
                'rows' => rows,
                'totalRows' => rows.size()
            };
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
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

    /**
     * @description Start a cleanup batch to delete Orders (and optionally Contracts/Assets)
     *              created by a previous migration run. Identifies orders by parsing the
     *              [ORDERS] line from a Migration_Run_Log__c record, or by re-running
     *              the same filter to find matching Orders.
     * @param runLogId The Migration_Run_Log__c Id to clean up (uses [ORDERS] line)
     * @param deleteContracts Whether to also delete migration-created Contracts
     * @return The AsyncApexJob Id as a String
     */
    @AuraEnabled
    public static String startCleanup(String runLogId, Boolean deleteContracts) {
        try {
            guardAgainstRunningCleanup();

            if (String.isBlank(runLogId)) {
                AuraHandledException ahe = new AuraHandledException('Run Log ID is required');
                ahe.setMessage('Run Log ID is required');
                throw ahe;
            }

            // Parse Order numbers from the run log's Errors__c field
            Migration_Run_Log__c log = [
                SELECT Id, Errors__c, Filter_Used__c, Run_Date__c
                FROM Migration_Run_Log__c
                WHERE Id = :runLogId
                LIMIT 1
            ];

            Set<String> orderNumbers = new Set<String>();
            if (log.Errors__c != null) {
                for (String line : log.Errors__c.split('\n')) {
                    if (line.startsWith('[ORDERS]')) {
                        String numsCsv = line.substring('[ORDERS] '.length()).trim();
                        for (String num : numsCsv.split(',')) {
                            String trimmed = num.trim();
                            if (String.isNotBlank(trimmed)) {
                                orderNumbers.add(trimmed);
                            }
                        }
                    }
                }
            }

            // Resolve OrderNumbers to Ids when the [ORDERS] line was emitted
            Set<Id> orderIds = new Set<Id>();
            if (!orderNumbers.isEmpty()) {
                for (Order o : [SELECT Id FROM Order WHERE OrderNumber IN :orderNumbers]) {
                    orderIds.add(o.Id);
                }
            }

            // Fallback: Migration_Run_Detail__c rows linked to this run log
            // (newer runs persist Order Id directly there). Used when the
            // [ORDERS] line is missing OR when the orders were already deleted.
            if (orderIds.isEmpty()) {
                for (Migration_Run_Detail__c d : [
                    SELECT Order__c FROM Migration_Run_Detail__c
                    WHERE Run_Log__c = :runLogId AND Order__c != null
                ]) {
                    orderIds.add(d.Order__c);
                }
            }

            // Final fallback: use the run's saved filter + a date window around
            // Run_Date__c to find Orders. We can drop the migration-flag safety
            // because we KNOW this run was a migration (we have the run log) —
            // the date window itself is the safety constraint. This catches
            // failed-mid-migration Orders that never got their Legacy_Id__c or
            // Migration_Created__c contract flag populated.
            if (orderIds.isEmpty()) {
                if (String.isNotBlank(log.Filter_Used__c) && log.Run_Date__c != null) {
                    Set<Id> quoteIds = resolveQuoteIdsFromFilter(log.Filter_Used__c);
                    if (!quoteIds.isEmpty()) {
                        Datetime windowStart = log.Run_Date__c.addMinutes(-2);
                        Datetime windowEnd   = log.Run_Date__c.addHours(8);
                        for (Order o : [
                            SELECT Id FROM Order
                            WHERE QuoteId IN :quoteIds
                            AND CreatedDate >= :windowStart
                            AND CreatedDate <= :windowEnd
                            LIMIT 10000
                        ]) {
                            orderIds.add(o.Id);
                        }
                    }
                }
                if (orderIds.isEmpty()) {
                    AuraHandledException ahe = new AuraHandledException(
                        'No Orders found for run log ' + log.Id +
                        ' (filter: ' + (log.Filter_Used__c != null ? log.Filter_Used__c : '(none)') +
                        '). They may already be deleted, or the run did not create any Orders.');
                    ahe.setMessage('No Orders found for this run. They may have already been ' +
                        'deleted, or the run did not create any Orders.');
                    throw ahe;
                }
            }

            Boolean doDeleteContracts = deleteContracts != null ? deleteContracts : false;
            OrderMigrationCleanupBatch batch = new OrderMigrationCleanupBatch(orderIds, doDeleteContracts);
            Id jobId = Database.executeBatch(batch, 10);

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
     * @description Start a cleanup batch by finding Orders that were created from
     *              Quotes matching the given filter. Uses the same filter logic as
     *              the migration (LIKE, QNUM, or SOQL) to find source Quotes,
     *              then finds Orders linked via QuoteId.
     * @param filter The same filter string used for migration
     * @param deleteContracts Whether to also delete migration-created Contracts
     * @return The AsyncApexJob Id as a String
     */
    /**
     * @description Start a cleanup batch by finding migration-created Orders
     *              linked to Quotes matching the given filter. Queries Orders
     *              directly (joined to migration Contracts) to stay within
     *              governor limits on large datasets.
     * @param filter The same filter string used for migration
     * @param deleteContracts Whether to also delete migration-created Contracts
     * @return The AsyncApexJob Id as a String
     */
    @AuraEnabled
    public static String startCleanupByFilter(String filter, Boolean deleteContracts) {
        try {
            guardAgainstRunningCleanup();

            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }

            // Find Quote IDs using the same logic as migration, but with LIMIT
            Set<Id> quoteIds = resolveQuoteIdsFromFilter(filter);

            if (quoteIds.isEmpty()) {
                AuraHandledException ahe = new AuraHandledException('No matching Quotes found for the given filter.');
                ahe.setMessage('No matching Quotes found for the given filter.');
                throw ahe;
            }

            // Find migration-created Orders linked to these Quotes.
            // An Order counts as migration-created if EITHER its Contract is
            // flagged Migration_Created__c=true (current scheme) OR the Order
            // itself has a Legacy_Id__c (older runs that reused existing
            // Contracts still set Legacy_Id__c on the Order during migration).
            Set<Id> orderIds = new Set<Id>();
            for (Order o : [
                SELECT Id FROM Order
                WHERE QuoteId IN :quoteIds
                AND (Contract.Migration_Created__c = true OR Legacy_Id__c != null)
                LIMIT 10000
            ]) {
                orderIds.add(o.Id);
            }

            if (orderIds.isEmpty()) {
                AuraHandledException ahe = new AuraHandledException(
                    'No migration-created Orders found for the ' + quoteIds.size() +
                    ' matching Quotes. They may not have been migrated or already cleaned up.');
                ahe.setMessage('No migration-created Orders found for the matching Quotes.');
                throw ahe;
            }

            Boolean doDeleteContracts = deleteContracts != null ? deleteContracts : false;
            OrderMigrationCleanupBatch batch = new OrderMigrationCleanupBatch(orderIds, doDeleteContracts);
            Id jobId = Database.executeBatch(batch, 10);

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
     * @description Start a cleanup batch that deletes ALL migration-created Orders
     *              (identified by Contract.Migration_Created__c = true).
     *              This is the most reliable cleanup method — no filter or run log parsing needed.
     * @param deleteContracts Whether to also delete migration-created Contracts
     * @return The AsyncApexJob Id as a String
     */
    @AuraEnabled
    public static String startCleanupAll(Boolean deleteContracts) {
        try {
            guardAgainstRunningCleanup();

            Set<Id> orderIds = new Set<Id>();
            for (Order o : [
                SELECT Id FROM Order
                WHERE Contract.Migration_Created__c = true
                LIMIT 10000
            ]) {
                orderIds.add(o.Id);
            }

            // Also check for orphan migration Contracts (Orders already deleted but Contracts remain)
            Integer orphanContracts = [
                SELECT COUNT() FROM Contract WHERE Migration_Created__c = true
            ];

            if (orderIds.isEmpty() && orphanContracts == 0) {
                AuraHandledException ahe = new AuraHandledException(
                    'No migration-created Orders or Contracts found.');
                ahe.setMessage('No migration-created Orders or Contracts found.');
                throw ahe;
            }

            if (orderIds.isEmpty() && orphanContracts > 0) {
                // Only orphan Contracts — pass a dummy set so the batch runs
                // and the Contract cleanup in execute() or a direct cleanup handles them.
                // Use a dedicated orphan-contract cleanup since the batch iterates Orders.
                cleanupOrphanContracts();
                AuraHandledException ahe = new AuraHandledException(
                    'Cleaned up ' + orphanContracts + ' orphan migration Contracts (no Orders to delete).');
                ahe.setMessage('Cleaned up ' + orphanContracts + ' orphan migration Contracts.');
                throw ahe;
            }

            Boolean doDeleteContracts = deleteContracts != null ? deleteContracts : false;
            OrderMigrationCleanupBatch batch = new OrderMigrationCleanupBatch(orderIds, doDeleteContracts);
            Id jobId = Database.executeBatch(batch, 10);

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
     * @description Get recent Migration Run Log records for the cleanup picker.
     * @return List of recent run logs with key fields
     */
    @AuraEnabled
    public static List<Migration_Run_Log__c> getRecentRunLogs() {
        try {
            return [
                SELECT Id, Name, Run_Date__c, Filter_Used__c,
                       Orders_Processed__c, Orders_Succeeded__c, Status__c
                FROM Migration_Run_Log__c
                ORDER BY Run_Date__c DESC
                LIMIT 20
            ];
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    public class HistoryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Datetime runDate;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String filterUsed;
        @AuraEnabled public String status;
        @AuraEnabled public Integer ordersProcessed;
        @AuraEnabled public Integer ordersSucceeded;
        @AuraEnabled public Integer detailCount;   // total Migration_Run_Detail__c rows for this run
        @AuraEnabled public Integer queuedCount;   // detail rows currently in the Rerun Queue
        @AuraEnabled public Integer remainingOrders; // Run-Detail rows whose Order__c is still non-null
    }

    /**
     * Returns the History tab feed: recent run logs enriched with detail-row
     * counts for the "Errors" and "Queued" columns. 3 SOQL queries total
     * (logs + group-by-runlog detail count + group-by-runlog queued count).
     *
     * NOT cacheable — the History tab needs to reflect new runs immediately.
     * The prior cacheable=true caused fresh runs (e.g., MIG-0140/MIG-0141 on
     * 2026-05-08) to stay invisible for the cache TTL even after a browser
     * hard-refresh.
     */
    @AuraEnabled
    public static List<HistoryRow> getHistoryRows(Integer maxRows) {
        try {
            Integer lim = (maxRows != null && maxRows > 0) ? maxRows : 50;
            List<Migration_Run_Log__c> logs = [
                SELECT Id, Name, Run_Date__c, Start_Time__c, End_Time__c,
                       Filter_Used__c, Status__c,
                       Orders_Processed__c, Orders_Succeeded__c
                FROM Migration_Run_Log__c
                ORDER BY Run_Date__c DESC NULLS LAST
                LIMIT :lim
            ];
            if (logs.isEmpty()) return new List<HistoryRow>();

            Set<Id> logIds = new Set<Id>();
            for (Migration_Run_Log__c l : logs) logIds.add(l.Id);

            Map<Id, Integer> errorCounts = new Map<Id, Integer>();
            Map<Id, Integer> queuedCounts = new Map<Id, Integer>();
            Map<Id, Integer> remainingCounts = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Run_Log__c rl, COUNT(Id) cnt
                FROM Migration_Run_Detail__c
                WHERE Run_Log__c IN :logIds
                GROUP BY Run_Log__c
            ]) {
                errorCounts.put((Id) ar.get('rl'), (Integer) ar.get('cnt'));
            }
            for (AggregateResult ar : [
                SELECT Run_Log__c rl, COUNT(Id) cnt
                FROM Migration_Run_Detail__c
                WHERE Run_Log__c IN :logIds
                AND In_Rerun_Queue__c = true
                GROUP BY Run_Log__c
            ]) {
                queuedCounts.put((Id) ar.get('rl'), (Integer) ar.get('cnt'));
            }
            // "Remaining": Run-Detail rows whose Order__c lookup is still
            // non-null. When an Order is deleted, Salesforce nulls the
            // lookup (or cascade-deletes the detail row), so this count is
            // a fast, no-N+1 proxy for "Orders this run created that still
            // exist in the org". Older runs without Run-Detail rows show 0.
            for (AggregateResult ar : [
                SELECT Run_Log__c rl, COUNT(Id) cnt
                FROM Migration_Run_Detail__c
                WHERE Run_Log__c IN :logIds
                AND Order__c != null
                GROUP BY Run_Log__c
            ]) {
                remainingCounts.put((Id) ar.get('rl'), (Integer) ar.get('cnt'));
            }

            List<HistoryRow> rows = new List<HistoryRow>();
            for (Migration_Run_Log__c l : logs) {
                HistoryRow r = new HistoryRow();
                r.id = l.Id;
                r.name = l.Name;
                r.runDate = l.Run_Date__c;
                r.startTime = l.Start_Time__c;
                r.endTime = l.End_Time__c;
                r.filterUsed = l.Filter_Used__c;
                r.status = l.Status__c;
                r.ordersProcessed = (l.Orders_Processed__c != null) ? l.Orders_Processed__c.intValue() : 0;
                r.ordersSucceeded = (l.Orders_Succeeded__c != null) ? l.Orders_Succeeded__c.intValue() : 0;
                r.detailCount = errorCounts.containsKey(l.Id) ? errorCounts.get(l.Id) : 0;
                r.queuedCount = queuedCounts.containsKey(l.Id) ? queuedCounts.get(l.Id) : 0;
                r.remainingOrders = remainingCounts.containsKey(l.Id) ? remainingCounts.get(l.Id) : 0;
                rows.add(r);
            }
            return rows;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    // One-time backfill helper for Start_Time__c / End_Time__c on legacy
    // run logs created before 2026-05-06. Stored-Apex path so it bypasses
    // the anonymous-compile schema-cache lag that bit the inline script.
    public static Integer backfillRunLogTimes(Boolean dryRun) {
        List<Migration_Run_Log__c> all = [
            SELECT Id, Name, CreatedDate, LastModifiedDate, Start_Time__c
            FROM Migration_Run_Log__c
            WHERE Start_Time__c = null
            LIMIT 10000
        ];
        if (all.isEmpty()) return 0;
        if (dryRun) return all.size();
        for (Migration_Run_Log__c r : all) {
            r.Start_Time__c = r.CreatedDate;
            r.End_Time__c = r.LastModifiedDate;
        }
        Database.SaveResult[] results = Database.update(all, false);
        Integer ok = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) ok++;
        }
        return ok;
    }

    /**
     * @description Guard against duplicate cleanup batch submissions.
     *              Checks for running cleanup batches.
     */
    // Resolve a filter string (LIKE pattern, QNUM:csv, or SOQL) to a set of
    // Quote IDs using the same rules as the migration. Shared by startCleanup
    // and startCleanupByFilter so the two cleanup paths agree on what
    // "matching Quotes" means.
    private static Set<Id> resolveQuoteIdsFromFilter(String filter) {
        Set<Id> quoteIds = new Set<Id>();
        if (String.isBlank(filter)) return quoteIds;

        if (OrderMigrationService.isSoqlMode(filter)) {
            String guardedSoql = OrderMigrationService.injectSafetyGuards(filter);
            String upper = guardedSoql.toUpperCase();
            Integer fromPos = upper.indexOf('FROM QUOTE');
            String idSoql = 'SELECT Id ' + guardedSoql.substring(fromPos);
            if (!idSoql.toUpperCase().contains(' LIMIT ')) {
                idSoql += ' LIMIT 10000';
            }
            for (SObject rec : Database.query(idSoql)) {
                quoteIds.add(rec.Id);
            }
        } else if (filter.startsWith('QNUM:')) {
            String csv = filter.removeStart('QNUM:');
            Set<String> nums = new Set<String>();
            for (String n : csv.split(',')) {
                String t = n.trim();
                if (String.isNotBlank(t)) nums.add(t);
            }
            for (Quote q : [SELECT Id FROM Quote WHERE QuoteNumber IN :nums]) {
                quoteIds.add(q.Id);
            }
        } else {
            for (Quote q : [
                SELECT Id FROM Quote
                WHERE Id IN (SELECT QuoteId FROM QuoteLineItem WHERE Legacy_Id__c LIKE :filter)
                LIMIT 10000
            ]) {
                quoteIds.add(q.Id);
            }
        }
        return quoteIds;
    }

    private static void guardAgainstRunningCleanup() {
        List<AsyncApexJob> running = [
            SELECT Id FROM AsyncApexJob
            WHERE ApexClass.Name = 'OrderMigrationCleanupBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            LIMIT 1
        ];
        if (!running.isEmpty()) {
            AuraHandledException ahe = new AuraHandledException(
                'A cleanup batch is already running. Please wait for it to complete.');
            ahe.setMessage('A cleanup batch is already running. Please wait for it to complete.');
            throw ahe;
        }
    }

    /**
     * @description Synchronously deletes orphan migration Contracts (no linked Orders).
     *              Handles AUAs, deactivation, and FLSRs.
     */
    private static void cleanupOrphanContracts() {
        List<Contract> contracts = [
            SELECT Id, Status FROM Contract WHERE Migration_Created__c = true LIMIT 200
        ];
        if (contracts.isEmpty()) return;

        Set<Id> cIds = new Set<Id>();
        for (Contract c : contracts) cIds.add(c.Id);

        Database.delete([SELECT Id FROM AppUsageAssignment WHERE RecordId IN :cIds], false);

        List<Contract> toDeactivate = new List<Contract>();
        for (Contract c : contracts) {
            if (c.Status == 'Activated') {
                toDeactivate.add(new Contract(Id = c.Id, Status = 'Draft'));
            }
        }
        if (!toDeactivate.isEmpty()) {
            Database.update(toDeactivate, false);
        }

        Database.delete(contracts, false);
    }

    // ══════════════════════════════════════════════════════════════════
    // ── PRICEBOOK SELECTOR + SERVER PRESETS ───────────────────────────
    // ══════════════════════════════════════════════════════════════════

    @AuraEnabled(cacheable=true)
    public static List<Pricebook2> getAvailablePricebooks() {
        try {
            return OrderMigrationService.getAvailablePricebooks();
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static OrderMigrationService.CoverageAnalysis getCoverageAnalysis(
        String filter, Id targetPricebookId
    ) {
        try {
            if (String.isBlank(filter)) {
                AuraHandledException ahe = new AuraHandledException('Filter is required');
                ahe.setMessage('Filter is required');
                throw ahe;
            }
            return OrderMigrationService.analyzeCoverage(filter, targetPricebookId);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Migration_Saved_Filter__c> listSavedFilters() {
        try {
            return OrderMigrationService.listSavedFilters();
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static Migration_Saved_Filter__c saveFilter(
        Id recordId, String name, String filterMode,
        String filterValue, String description
    ) {
        try {
            if (String.isBlank(name)) {
                AuraHandledException ahe = new AuraHandledException('Preset name is required');
                ahe.setMessage('Preset name is required');
                throw ahe;
            }
            return OrderMigrationService.saveFilter(recordId, name, filterMode, filterValue, description);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static void deleteSavedFilter(Id recordId) {
        try {
            OrderMigrationService.deleteSavedFilter(recordId);
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static void touchSavedFilter(Id recordId) {
        try {
            OrderMigrationService.touchSavedFilter(recordId);
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Migration_Saved_Pricebook_Preset__c> listSavedPricebookPresets() {
        try {
            return OrderMigrationService.listSavedPricebookPresets();
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static Migration_Saved_Pricebook_Preset__c savePricebookPreset(
        Id recordId, String name, Id pricebookId,
        Boolean autoCreate, String description
    ) {
        try {
            if (String.isBlank(name)) {
                AuraHandledException ahe = new AuraHandledException('Preset name is required');
                ahe.setMessage('Preset name is required');
                throw ahe;
            }
            if (pricebookId == null) {
                AuraHandledException ahe = new AuraHandledException('Pricebook is required');
                ahe.setMessage('Pricebook is required');
                throw ahe;
            }
            return OrderMigrationService.savePricebookPreset(
                recordId, name, pricebookId, autoCreate, description);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static void deleteSavedPricebookPreset(Id recordId) {
        try {
            OrderMigrationService.deleteSavedPricebookPreset(recordId);
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static void touchSavedPricebookPreset(Id recordId) {
        try {
            OrderMigrationService.touchSavedPricebookPreset(recordId);
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static Integer migrateLocalStorageFilters(List<Map<String, Object>> entries) {
        try {
            return OrderMigrationService.migrateLocalStorageFilters(entries);
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // ── RUN REPORT BUCKET AGGREGATOR ──────────────────────────────────
    // ══════════════════════════════════════════════════════════════════

    public class BucketSummary {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String meaning;
        @AuraEnabled public Boolean cleanupRequired;
        @AuraEnabled public Integer count;
        @AuraEnabled public Integer quoteCount;
        @AuraEnabled public List<String> quoteNumbers;
    }

    /**
     * Returns one BucketSummary per category that has at least one detail row
     * for the given run log. Quote numbers are deduplicated. Buckets are sorted
     * by category label for stable LWC rendering.
     */
    @AuraEnabled(cacheable=true)
    public static List<BucketSummary> getRunDetailBuckets(Id runLogId) {
        try {
            if (runLogId == null) return new List<BucketSummary>();
            Map<String, OrderMigrationService.CategoryMetadata> catalog =
                OrderMigrationService.getCategoryCatalog();
            Map<String, BucketSummary> buckets = new Map<String, BucketSummary>();
            Map<String, Set<String>> qNumsByCategory = new Map<String, Set<String>>();

            for (Migration_Run_Detail__c d : [
                SELECT Category__c, Quote_Number__c, Quote__c
                FROM Migration_Run_Detail__c
                WHERE Run_Log__c = :runLogId
            ]) {
                String cat = d.Category__c;
                BucketSummary b = buckets.get(cat);
                if (b == null) {
                    b = new BucketSummary();
                    b.apiName = cat;
                    OrderMigrationService.CategoryMetadata m = catalog.get(cat);
                    b.label = (m != null) ? m.label : cat;
                    b.meaning = (m != null) ? m.meaning : '';
                    b.cleanupRequired = (m != null) && m.cleanupRequired == true;
                    b.count = 0;
                    buckets.put(cat, b);
                    qNumsByCategory.put(cat, new Set<String>());
                }
                b.count++;
                if (String.isNotBlank(d.Quote_Number__c)) {
                    qNumsByCategory.get(cat).add(d.Quote_Number__c);
                }
            }

            List<BucketSummary> result = new List<BucketSummary>();
            for (String cat : buckets.keySet()) {
                BucketSummary b = buckets.get(cat);
                Set<String> qs = qNumsByCategory.get(cat);
                List<String> qList = new List<String>(qs);
                qList.sort();
                b.quoteNumbers = qList;
                b.quoteCount = qList.size();
                result.add(b);
            }
            // Stable order by label
            result.sort(new BucketSummaryComparator());
            return result;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Returns full detail rows for a single category within a run log.
     * Capped at 1000 rows to protect LWC payload size.
     */
    @AuraEnabled(cacheable=true)
    public static List<Migration_Run_Detail__c> getRunDetailRows(Id runLogId, String category) {
        try {
            if (runLogId == null || String.isBlank(category)) {
                return new List<Migration_Run_Detail__c>();
            }
            return [
                SELECT Id, Name, Category__c, Severity__c,
                       Quote__c, Quote_Number__c, Quote_Line_Item__c,
                       Order__c, Order_Item__c, Reason__c,
                       Cleanup_Required__c, CreatedDate
                FROM Migration_Run_Detail__c
                WHERE Run_Log__c = :runLogId
                AND Category__c = :category
                ORDER BY CreatedDate ASC
                LIMIT 1000
            ];
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Comparator for stable bucket ordering by display label.
     */
    private class BucketSummaryComparator implements System.Comparator<BucketSummary> {
        public Integer compare(BucketSummary a, BucketSummary b) {
            String al = a.label != null ? a.label : '';
            String bl = b.label != null ? b.label : '';
            if (al == bl) return 0;
            return al < bl ? -1 : 1;
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // ── RERUN QUEUE (team-shared, persistent) ─────────────────────────
    // ══════════════════════════════════════════════════════════════════

    public class RerunQueueSummary {
        @AuraEnabled public Integer totalDistinctQuotes;
        @AuraEnabled public List<BucketSummary> buckets;
    }

    /**
     * Adds every detail row matching (runLogId, category) to the team-shared
     * Rerun Queue. Stamps Queued_Date__c and Queued_By__c. Returns the count
     * of rows affected (some may already have been queued — those are still
     * counted; the flag is idempotent).
     */
    @AuraEnabled
    public static Integer addBucketToQueue(Id runLogId, String category) {
        try {
            if (runLogId == null || String.isBlank(category)) return 0;
            List<Migration_Run_Detail__c> rows = [
                SELECT Id FROM Migration_Run_Detail__c
                WHERE Run_Log__c = :runLogId
                AND Category__c = :category
            ];
            if (rows.isEmpty()) return 0;
            Datetime now = Datetime.now();
            Id userId = UserInfo.getUserId();
            for (Migration_Run_Detail__c d : rows) {
                d.In_Rerun_Queue__c = true;
                d.Queued_Date__c = now;
                d.Queued_By__c = userId;
            }
            Database.update(rows, false);
            return rows.size();
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Returns the categorized queue (mirrors getRunDetailBuckets but spans
     * all run logs, filtered by In_Rerun_Queue__c = true). Includes a top-
     * level totalDistinctQuotes so the panel header can show one number
     * even when the same Quote appears in multiple categories.
     *
     * Intentionally NOT cacheable — the queue is mutated by addBucketToQueue,
     * removeFromQueue, clearQueue, and the batch's auto-clear. A stale cache
     * masks those mutations from the LWC.
     */
    @AuraEnabled
    public static RerunQueueSummary getRerunQueueBuckets() {
        try {
            RerunQueueSummary summary = new RerunQueueSummary();
            summary.buckets = new List<BucketSummary>();
            summary.totalDistinctQuotes = 0;

            Map<String, OrderMigrationService.CategoryMetadata> catalog =
                OrderMigrationService.getCategoryCatalog();
            Map<String, BucketSummary> buckets = new Map<String, BucketSummary>();
            Map<String, Set<String>> qNumsByCategory = new Map<String, Set<String>>();
            Set<String> allQuoteNumbers = new Set<String>();

            for (Migration_Run_Detail__c d : [
                SELECT Category__c, Quote_Number__c, Quote__c
                FROM Migration_Run_Detail__c
                WHERE In_Rerun_Queue__c = true
            ]) {
                String cat = d.Category__c;
                BucketSummary b = buckets.get(cat);
                if (b == null) {
                    b = new BucketSummary();
                    b.apiName = cat;
                    OrderMigrationService.CategoryMetadata m = catalog.get(cat);
                    b.label = (m != null) ? m.label : cat;
                    b.meaning = (m != null) ? m.meaning : '';
                    b.cleanupRequired = (m != null) && m.cleanupRequired == true;
                    b.count = 0;
                    buckets.put(cat, b);
                    qNumsByCategory.put(cat, new Set<String>());
                }
                b.count++;
                if (String.isNotBlank(d.Quote_Number__c)) {
                    qNumsByCategory.get(cat).add(d.Quote_Number__c);
                    allQuoteNumbers.add(d.Quote_Number__c);
                }
            }

            for (String cat : buckets.keySet()) {
                BucketSummary b = buckets.get(cat);
                List<String> qList = new List<String>(qNumsByCategory.get(cat));
                qList.sort();
                b.quoteNumbers = qList;
                b.quoteCount = qList.size();
                summary.buckets.add(b);
            }
            summary.buckets.sort(new BucketSummaryComparator());
            summary.totalDistinctQuotes = allQuoteNumbers.size();
            return summary;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Manual remove. If category is null, clears the flag for ALL queued rows
     * matching the Quote numbers. If category is provided, scopes to that
     * bucket. Returns the count of rows updated.
     */
    @AuraEnabled
    public static Integer removeFromQueue(List<String> quoteNumbers, String category) {
        try {
            if (quoteNumbers == null || quoteNumbers.isEmpty()) return 0;
            List<Migration_Run_Detail__c> rows;
            if (String.isBlank(category)) {
                rows = [
                    SELECT Id FROM Migration_Run_Detail__c
                    WHERE In_Rerun_Queue__c = true
                    AND Quote_Number__c IN :quoteNumbers
                ];
            } else {
                rows = [
                    SELECT Id FROM Migration_Run_Detail__c
                    WHERE In_Rerun_Queue__c = true
                    AND Quote_Number__c IN :quoteNumbers
                    AND Category__c = :category
                ];
            }
            if (rows.isEmpty()) return 0;
            for (Migration_Run_Detail__c d : rows) {
                d.In_Rerun_Queue__c = false;
            }
            Database.update(rows, false);
            return rows.size();
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Bulk-clears the queue. Leaves Queued_Date/By intact for audit purposes;
     * only the membership flag is reset.
     */
    @AuraEnabled
    public static Integer clearQueue() {
        try {
            List<Migration_Run_Detail__c> rows = [
                SELECT Id FROM Migration_Run_Detail__c
                WHERE In_Rerun_Queue__c = true
            ];
            if (rows.isEmpty()) return 0;
            for (Migration_Run_Detail__c d : rows) {
                d.In_Rerun_Queue__c = false;
            }
            Database.update(rows, false);
            return rows.size();
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }
}