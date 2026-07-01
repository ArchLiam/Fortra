/**
 * @description Batch Apex class for populating Revenue Cloud fields on migrated Quotes and QuoteLineItems.
 *              Processes legacy quotes identified by a filter clause, calculates subscription terms,
 *              applies default values from Custom Metadata, and preserves customer-accepted prices.
 *
 *              Process Flow:
 *              1. Query Quotes that are Primary on Closed Won Opportunities with matching QLIs
 *              2. Resolve default values from Migration_Field_Default__mdt (once in start)
 *              3. For each Quote: update header fields, then process child QLIs
 *              4. For each QLI: capture prices → calculate fields → restore prices → update
 *              5. Optionally set Quote Status to Accepted for Q2O readiness
 *              6. Log results to Migration_Run_Log__c and send email notification
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-02
 */
public class QuoteMigrationBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {

    // Input parameters
    private String soqlFilter;
    private Boolean prepareForQ2O;
    private Integer batchSizeParam;
    private Boolean includeReprice;

    // User info for email notification
    private String initiatedByUserId;
    private String initiatedByUserEmail;
    private String initiatedByUserName;

    // Stateful tracking (persists across execute() calls)
    private Integer quotesProcessed = 0;
    private Integer quotesSucceeded = 0;
    private Integer quotesFailed = 0;
    private Integer quotesRepriced = 0;
    private Integer quotesRepriceFailed = 0;
    private Integer qlisProcessed = 0;
    private Integer qlisSucceeded = 0;
    private Integer qlisFailed = 0;
    private Integer qlisSkipped = 0;
    private Integer qlisPriceRestored = 0;
    private Set<Id> successfulQuoteIds = new Set<Id>();
    private Integer checklistItemsCreated = 0;
    private Integer checklistQuotesSkipped = 0;
    private List<String> errorMessages = new List<String>();
    private List<String> skippedItems = new List<String>();
    private static final Integer MAX_ERROR_MESSAGES = 100;
    private static final Integer MAX_SKIPPED_ITEMS = 200;

    // Cached defaults (resolved once, reused across batches)
    private QuoteMigrationService.ResolvedDefaults resolvedDefaults;

    /**
     * @description Constructor
     * @param soqlFilter LIKE pattern for Legacy_Id__c (e.g., 'DY_%')
     * @param prepareForQ2O If true, also sets Status=Accepted after successful processing
     * @param batchSize Number of Quotes per execute() call
     * @param includeReprice If true, invokes Revenue Cloud pricing engine after field
     *        population and restores original prices afterward. Forces batchSize=1.
     */
    public QuoteMigrationBatch(String soqlFilter, Boolean prepareForQ2O, Integer batchSize, Boolean includeReprice) {
        this.soqlFilter = soqlFilter;
        this.prepareForQ2O = prepareForQ2O != null ? prepareForQ2O : false;
        this.includeReprice = includeReprice != null ? includeReprice : false;

        // When repricing is enabled, force batch size to 1 Quote per execute()
        // because the pricing engine is heavyweight (runs all prehooks, expression sets)
        if (this.includeReprice) {
            this.batchSizeParam = 1;
        } else {
            this.batchSizeParam = batchSize != null && batchSize > 0 ? batchSize : 10;
        }

        // Capture user info for email notification
        User currentUser = [SELECT Id, Email, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        this.initiatedByUserId = currentUser.Id;
        this.initiatedByUserEmail = currentUser.Email;
        this.initiatedByUserName = currentUser.Name;
    }

    /**
     * @description Backwards-compatible constructor (without includeReprice)
     */
    public QuoteMigrationBatch(String soqlFilter, Boolean prepareForQ2O, Integer batchSize) {
        this(soqlFilter, prepareForQ2O, batchSize, false);
    }

    /**
     * @description Start method - resolves defaults and queries eligible Quotes
     * @param bc BatchableContext
     * @return QueryLocator for Quotes to process
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'QuoteMigrationBatch: Starting');
        System.debug(LoggingLevel.INFO, 'Filter: ' + this.soqlFilter);
        System.debug(LoggingLevel.INFO, 'PrepareForQ2O: ' + this.prepareForQ2O);
        System.debug(LoggingLevel.INFO, 'IncludeReprice: ' + this.includeReprice);
        System.debug(LoggingLevel.INFO, 'BatchSize: ' + this.batchSizeParam);
        System.debug(LoggingLevel.INFO, '========================================');

        // Resolve defaults once (cached for all execute() calls)
        this.resolvedDefaults = QuoteMigrationService.resolveDefaults();

        // Pre-query matching Quote IDs from child QLIs.
        // NOTE: Database.getQueryLocator does not support bind variables inside
        // semi-join subqueries, so we resolve the Quote IDs first.
        String likeFilter = this.soqlFilter;
        Set<Id> matchingQuoteIds = new Set<Id>();
        for (QuoteLineItem qli : [
            SELECT QuoteId FROM QuoteLineItem WHERE Legacy_Id__c LIKE :likeFilter
        ]) {
            matchingQuoteIds.add(qli.QuoteId);
        }

        System.debug(LoggingLevel.INFO, 'Found ' + matchingQuoteIds.size() +
            ' Quotes with matching QLIs');

        // Convert to List<Id> for QueryLocator bind compatibility
        List<Id> quoteIdList = new List<Id>(matchingQuoteIds);

        return Database.getQueryLocator([
            SELECT Id, Name, QuoteNumber, Status, SalesTransactionTypeId,
                   OpportunityId, Opportunity.StageName, IsPrimary__c
            FROM Quote
            WHERE Id IN :quoteIdList
            AND IsPrimary__c = true
            AND Opportunity.StageName = 'Closed Won'
            ORDER BY QuoteNumber
        ]);
    }

    /**
     * @description Execute method - processes a batch of Quotes and their child QLIs
     * @param bc BatchableContext
     * @param quotes List of Quote records to process
     */
    public void execute(Database.BatchableContext bc, List<Quote> quotes) {
        System.debug(LoggingLevel.INFO, 'Processing batch of ' + quotes.size() + ' quotes');
        String likeFilter = this.soqlFilter;

        for (Quote quote : quotes) {
            this.quotesProcessed++;
            Boolean quoteHadErrors = false;

            try {
                // ── Step 1: Update Quote header fields ──
                QuoteMigrationService.calculateQuoteFields(quote, this.resolvedDefaults);
                Database.SaveResult quoteResult = Database.update(quote, false);
                if (!quoteResult.isSuccess()) {
                    quoteHadErrors = true;
                    for (Database.Error err : quoteResult.getErrors()) {
                        addErrorMessage('Quote ' + quote.QuoteNumber + ': ' + err.getMessage());
                    }
                }

                // ── Step 2: Query child QLIs ──
                List<QuoteLineItem> qlis = [
                    SELECT Id, QuoteId, StartDate, EndDate, ServiceDate,
                           SubscriptionTerm, SubscriptionTermUnit, PricingTermCount,
                           PeriodBoundary, PeriodBoundaryDay, PeriodBoundaryStartMonth, BillingFrequency, ProrationPolicyId,
                           UnitPrice, Discount, ListPrice, Subtotal, TotalPrice,
                           Quantity, Product2Id, Product2.Name, Legacy_Id__c
                    FROM QuoteLineItem
                    WHERE QuoteId = :quote.Id
                    AND Legacy_Id__c LIKE :likeFilter
                ];

                this.qlisProcessed += qlis.size();

                // ── Step 3: Capture original prices BEFORE any modifications ──
                // Store QLI Id → price snapshot so we can restore after repricing
                Map<Id, Map<String, Object>> pricesByQliId = new Map<Id, Map<String, Object>>();

                // ── Step 4: Process each QLI ──
                List<QuoteLineItem> qlisToUpdate = new List<QuoteLineItem>();

                for (QuoteLineItem qli : qlis) {
                    // Skip QLIs with missing date fields
                    if (qli.StartDate == null || qli.EndDate == null) {
                        String missingField = qli.StartDate == null ? 'StartDate' : 'EndDate';
                        if (qli.StartDate == null && qli.EndDate == null) {
                            missingField = 'StartDate, EndDate';
                        }
                        addSkippedItem(qli.Id + ' (' + qli.Product2.Name + ') - Missing ' + missingField);
                        this.qlisSkipped++;
                        continue;
                    }

                    // Capture prices before transformation
                    Map<String, Object> prices = QuoteMigrationService.capturePriceFields(qli);
                    pricesByQliId.put(qli.Id, prices);

                    // Calculate migration fields
                    QuoteMigrationService.calculateQLIFields(qli, this.resolvedDefaults);

                    // Restore original prices (so the initial DML preserves them)
                    QuoteMigrationService.restorePriceFields(qli, prices);

                    qlisToUpdate.add(qli);
                }

                // ── Step 5: DML update QLIs with partial success ──
                if (!qlisToUpdate.isEmpty()) {
                    Database.SaveResult[] results = Database.update(qlisToUpdate, false);

                    for (Integer i = 0; i < results.size(); i++) {
                        if (results[i].isSuccess()) {
                            this.qlisSucceeded++;
                        } else {
                            this.qlisFailed++;
                            quoteHadErrors = true;
                            QuoteLineItem failedQli = qlisToUpdate[i];
                            for (Database.Error err : results[i].getErrors()) {
                                addErrorMessage('QLI ' + failedQli.Id +
                                    ' (' + failedQli.Product2.Name + '): ' + err.getMessage());
                            }
                        }
                    }
                }

                // ── Step 6: Reprice the Quote (if enabled and no errors so far) ──
                if (this.includeReprice && !quoteHadErrors) {
                    QuoteMigrationService.RepricingResult repriceResult =
                        QuoteMigrationService.repriceQuote(quote.Id);

                    if (repriceResult.isSuccess) {
                        this.quotesRepriced++;
                        System.debug(LoggingLevel.INFO,
                            'Quote ' + quote.QuoteNumber + ' repriced successfully. ' +
                            'ExecutionId: ' + repriceResult.executionId);

                        // ── Step 7: Re-query QLIs and restore ONLY if prices changed ──
                        // IMPORTANT: Any DML after repricing re-stales the pricing state,
                        // causing the "prices aren't updated" banner. Since the reprice Flow
                        // uses isSkipWaterfall=true, UnitPrice/Discount are typically preserved.
                        // We only DML-update QLIs whose prices actually changed to avoid
                        // unnecessarily re-staling the Quote.
                        List<QuoteLineItem> repricedQlis = [
                            SELECT Id, UnitPrice, Discount
                            FROM QuoteLineItem
                            WHERE QuoteId = :quote.Id
                            AND Id IN :pricesByQliId.keySet()
                        ];

                        List<QuoteLineItem> qlisToRestore = new List<QuoteLineItem>();
                        Integer qlisUnchanged = 0;
                        for (QuoteLineItem rqli : repricedQlis) {
                            Map<String, Object> originalPrices = pricesByQliId.get(rqli.Id);
                            if (originalPrices != null) {
                                Decimal origUP = (Decimal) originalPrices.get('UnitPrice');
                                Decimal origDisc = (Decimal) originalPrices.get('Discount');
                                Boolean priceChanged =
                                    (rqli.UnitPrice != origUP) ||
                                    (rqli.Discount != origDisc);

                                if (priceChanged) {
                                    QuoteMigrationService.restorePriceFields(rqli, originalPrices);
                                    qlisToRestore.add(rqli);
                                } else {
                                    qlisUnchanged++;
                                }
                            }
                        }

                        System.debug(LoggingLevel.INFO,
                            'Quote ' + quote.QuoteNumber + ': ' +
                            qlisUnchanged + ' QLIs prices unchanged (no DML needed), ' +
                            qlisToRestore.size() + ' QLIs need price restoration');

                        if (!qlisToRestore.isEmpty()) {
                            Database.SaveResult[] restoreResults = Database.update(qlisToRestore, false);
                            for (Integer i = 0; i < restoreResults.size(); i++) {
                                if (restoreResults[i].isSuccess()) {
                                    this.qlisPriceRestored++;
                                } else {
                                    quoteHadErrors = true;
                                    for (Database.Error err : restoreResults[i].getErrors()) {
                                        addErrorMessage('Quote ' + quote.QuoteNumber +
                                            ' - Price restore failed for QLI ' +
                                            qlisToRestore[i].Id + ': ' + err.getMessage());
                                    }
                                }
                            }
                        }
                    } else {
                        this.quotesRepriceFailed++;
                        quoteHadErrors = true;
                        addErrorMessage('Quote ' + quote.QuoteNumber +
                            ' - Repricing failed: ' + repriceResult.errorMessage);
                    }
                }

                // ── Step 8: Track quote success/failure ──
                if (quoteHadErrors) {
                    this.quotesFailed++;
                } else {
                    this.quotesSucceeded++;

                    // ── Step 9: If prepareForQ2O, set Status to Accepted ──
                    if (this.prepareForQ2O) {
                        try {
                            quote.Status = 'Accepted';
                            update quote;
                            this.successfulQuoteIds.add(quote.Id);
                        } catch (Exception statusEx) {
                            addErrorMessage('Quote ' + quote.QuoteNumber +
                                ' - Failed to set Status=Accepted: ' + statusEx.getMessage());
                        }
                    }
                }

            } catch (Exception e) {
                this.quotesFailed++;
                addErrorMessage('Quote ' + quote.QuoteNumber + ': ' + e.getMessage());
            }
        }
    }

    /**
     * @description Finish method - creates audit log record and sends email notification
     * @param bc BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'QuoteMigrationBatch: Complete');
        System.debug(LoggingLevel.INFO, 'Quotes Processed: ' + this.quotesProcessed);
        System.debug(LoggingLevel.INFO, 'Quotes Succeeded: ' + this.quotesSucceeded);
        System.debug(LoggingLevel.INFO, 'Quotes Failed: ' + this.quotesFailed);
        System.debug(LoggingLevel.INFO, 'Quotes Repriced: ' + this.quotesRepriced);
        System.debug(LoggingLevel.INFO, 'Quotes Reprice Failed: ' + this.quotesRepriceFailed);
        System.debug(LoggingLevel.INFO, 'QLIs Processed: ' + this.qlisProcessed);
        System.debug(LoggingLevel.INFO, 'QLIs Succeeded: ' + this.qlisSucceeded);
        System.debug(LoggingLevel.INFO, 'QLIs Failed: ' + this.qlisFailed);
        System.debug(LoggingLevel.INFO, 'QLIs Skipped: ' + this.qlisSkipped);
        System.debug(LoggingLevel.INFO, 'QLIs Price Restored: ' + this.qlisPriceRestored);
        System.debug(LoggingLevel.INFO, '========================================');

        // Create pre-checked checklist items for all successfully prepared Quotes
        if (this.prepareForQ2O && !this.successfulQuoteIds.isEmpty()) {
            try {
                QuoteMigrationService.ChecklistResult checklistResult =
                    QuoteMigrationService.createPreCheckedChecklistItems(this.successfulQuoteIds);
                this.checklistItemsCreated = checklistResult.itemsCreated;
                this.checklistQuotesSkipped = checklistResult.quotesSkipped;
                for (String err : checklistResult.errors) {
                    addErrorMessage(err);
                }
                System.debug(LoggingLevel.INFO, 'Checklist items created: ' + checklistResult.itemsCreated +
                    ', Quotes skipped (already had items): ' + checklistResult.quotesSkipped);
            } catch (Exception e) {
                addErrorMessage('Checklist creation failed: ' + e.getMessage());
            }
        }

        // Prepend checklist summary to error messages for LWC consumption
        if (this.prepareForQ2O) {
            String checklistSummary = '[CHECKLIST] Created: ' + this.checklistItemsCreated +
                ' items | Skipped: ' + this.checklistQuotesSkipped + ' quotes (already had items)';
            // Apex List.add(0, item) throws on empty lists, unlike Java
            if (this.errorMessages.isEmpty()) {
                this.errorMessages.add(checklistSummary);
            } else {
                this.errorMessages.add(0, checklistSummary);
            }
        }

        // Create audit log record
        createMigrationRunLog();

        // Send email notification
        sendCompletionEmail(bc.getJobId());
    }

    // ── Private Helpers ───────────────────────────────────────────────

    /**
     * @description Add error message to tracking list (up to MAX limit)
     * @param message Error message to add
     */
    private void addErrorMessage(String message) {
        if (this.errorMessages.size() < MAX_ERROR_MESSAGES) {
            this.errorMessages.add(message);
        }
    }

    /**
     * @description Add skipped item to tracking list (up to MAX limit)
     * @param item Description of skipped item
     */
    private void addSkippedItem(String item) {
        if (this.skippedItems.size() < MAX_SKIPPED_ITEMS) {
            this.skippedItems.add(item);
        }
    }

    /**
     * @description Creates a Migration_Run_Log__c record with batch results
     */
    private void createMigrationRunLog() {
        try {
            Migration_Run_Log__c log = new Migration_Run_Log__c();
            log.Run_Date__c = Datetime.now();
            log.Filter_Used__c = this.soqlFilter;
            log.Quotes_Processed__c = this.quotesProcessed;
            log.Quotes_Succeeded__c = this.quotesSucceeded;
            log.QLIs_Processed__c = this.qlisProcessed;
            log.QLIs_Succeeded__c = this.qlisSucceeded;
            log.QLIs_Skipped__c = this.qlisSkipped;

            // Truncate error messages to fit LongTextArea field (131,072 chars max)
            String errorsText = String.join(this.errorMessages, '\n');
            if (errorsText.length() > 131072) {
                errorsText = errorsText.substring(0, 131072);
            }
            log.Errors__c = errorsText;

            log.Status__c = this.quotesFailed == 0
                ? 'Completed'
                : (this.quotesSucceeded > 0 ? 'Partial' : 'Failed');

            insert log;
            System.debug(LoggingLevel.INFO, 'Migration Run Log created: ' + log.Id);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to create Migration Run Log: ' + e.getMessage());
        }
    }

    /**
     * @description Send completion email to the user who initiated the batch
     * @param jobId The batch job ID
     */
    private void sendCompletionEmail(Id jobId) {
        if (String.isBlank(this.initiatedByUserEmail)) {
            System.debug(LoggingLevel.WARN, 'No email address available for notification');
            return;
        }

        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ this.initiatedByUserEmail });
            email.setSubject('Quote Migration Complete - ' +
                (this.quotesFailed > 0 ? 'Completed with Errors' : 'Success'));

            String htmlBody = buildEmailBody(jobId);
            email.setHtmlBody(htmlBody);
            email.setSaveAsActivity(false);

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            System.debug(LoggingLevel.INFO, 'Completion email sent to: ' + this.initiatedByUserEmail);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to send completion email: ' + e.getMessage());
        }
    }

    /**
     * @description Build HTML email body with results summary
     * @param jobId The batch job ID
     * @return HTML formatted email body
     */
    private String buildEmailBody(Id jobId) {
        String successStyle = 'color: #28a745; font-weight: bold;';
        String warningStyle = 'color: #dc3545; font-weight: bold;';

        String body = '<html><body style="font-family: Arial, sans-serif;">';

        // Header
        body += '<h2 style="color: #333;">Quote Migration Complete</h2>';

        // Summary table
        body += '<table style="border-collapse: collapse; width: 100%; max-width: 500px;">';

        // Batch Job ID
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Batch Job ID</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' + jobId + '</td></tr>';

        // Filter
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Filter</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                String.valueOf(this.soqlFilter).escapeHtml4() + '</td></tr>';

        // Prepare for Q2O
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Prepare for Q2O</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.prepareForQ2O + '</td></tr>';

        // Include Repricing
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Include Repricing</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.includeReprice + '</td></tr>';

        // Quotes Processed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Quotes Processed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.quotesProcessed + '</td></tr>';

        // Quotes Succeeded
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Quotes Succeeded</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.quotesSucceeded + '</td></tr>';

        // Quotes Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Quotes Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.quotesFailed > 0 ? warningStyle : '') + '">' +
                this.quotesFailed + '</td></tr>';

        // Checklist stats (only show if prepareForQ2O was enabled)
        if (this.prepareForQ2O) {
            body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                    '<strong>Checklist Items Created</strong></td>';
            body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                    this.checklistItemsCreated + '</td></tr>';

            body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                    '<strong>Checklist Quotes Skipped (Already Existed)</strong></td>';
            body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                    this.checklistQuotesSkipped + '</td></tr>';
        }

        // Repricing stats (only show if repricing was enabled)
        if (this.includeReprice) {
            body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                    '<strong>Quotes Repriced</strong></td>';
            body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                    this.quotesRepriced + '</td></tr>';

            body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                    '<strong>Quotes Reprice Failed</strong></td>';
            body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                    (this.quotesRepriceFailed > 0 ? warningStyle : '') + '">' +
                    this.quotesRepriceFailed + '</td></tr>';
        }

        // QLIs Processed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>QLIs Processed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.qlisProcessed + '</td></tr>';

        // QLIs Succeeded
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>QLIs Succeeded</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.qlisSucceeded + '</td></tr>';

        // QLIs Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>QLIs Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.qlisFailed > 0 ? warningStyle : '') + '">' +
                this.qlisFailed + '</td></tr>';

        // QLIs Skipped
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>QLIs Skipped (Missing Dates)</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.qlisSkipped > 0 ? ' color: #856404; font-weight: bold;' : '') + '">' +
                this.qlisSkipped + '</td></tr>';

        // QLIs Price Restored (only show if repricing was enabled)
        if (this.includeReprice) {
            body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                    '<strong>QLIs Price Restored</strong></td>';
            body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                    this.qlisPriceRestored + '</td></tr>';
        }

        body += '</table>';

        // Skipped items details if any
        if (!this.skippedItems.isEmpty()) {
            body += '<h3 style="color: #856404; margin-top: 20px;">Skipped Items (Missing Dates)</h3>';
            body += '<ul style="background: #fff3cd; padding: 15px 30px; border-radius: 4px;">';
            for (String skipMsg : this.skippedItems) {
                body += '<li style="margin: 5px 0;">' + skipMsg.escapeHtml4() + '</li>';
            }
            if (this.skippedItems.size() >= MAX_SKIPPED_ITEMS) {
                body += '<li style="margin: 5px 0; font-style: italic;">... and more (showing first ' +
                        MAX_SKIPPED_ITEMS + ' items)</li>';
            }
            body += '</ul>';
        }

        // Error details if any
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

        // Footer
        body += '<p style="margin-top: 20px; color: #666; font-size: 12px;">' +
                'This is an automated message from Salesforce.</p>';

        body += '</body></html>';

        return body;
    }
}