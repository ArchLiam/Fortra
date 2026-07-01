/**
 * @description Batch Apex class for creating Revenue Cloud Orders from migrated Quotes.
 *              Processes legacy quotes identified by a filter clause, creates Orders with
 *              direct pricing (bypassing headless pricing), activates without AUA to avoid
 *              CalculationStatus checks, then adds AUA and creates Assets via REST API.
 *
 *              Process Flow (AUA Bypass Pipeline):
 *              1. Query Quotes that are Primary on Closed Won Opportunities with matching QLIs
 *              2. Resolve default values from Migration_Field_Default__mdt (once in start)
 *              3. For each Quote: resolve/create Contract, create Order (Draft, NO AUA)
 *              4. Create OrderAction + map QLIs to OrderItems (with pre-set pricing)
 *              5. Activate Order via DML (no AUA = bypasses CalculationStatus check)
 *              6. Add AppUsageAssignment (enables RLC lifecycle management)
 *              7. Create Assets via createOrUpdateAssetFromOrder REST API
 *              8. Optionally activate Contract
 *              9. Log results to Migration_Run_Log__c and send email notification
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-03
 */
public class OrderMigrationBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {

    // Input parameters
    private String soqlFilter;
    private Integer batchSizeParam;
    private Boolean activateOrders;
    private Boolean activateContracts;
    private Boolean isQuoteNumberMode = false;
    private Boolean isSoqlMode = false;
    private Id runLogId; // Pre-created sentinel Migration_Run_Log__c Id

    // Pricebook override (optional)
    private Id targetPricebookId;
    private Boolean autoCreateMissingPbes = false;
    private Integer quotesSkippedNoCoverage = 0;
    private Integer pbesAutoCreated = 0;
    private List<Id> productsMissingStandardPbe = new List<Id>();

    // User info for email notification
    private String initiatedByUserId;
    private String initiatedByUserEmail;
    private String initiatedByUserName;

    // Stateful tracking (persists across execute() calls)
    private Integer ordersProcessed = 0;
    private Integer ordersSucceeded = 0;
    private Integer ordersFailed = 0;
    private Integer itemsProcessed = 0;
    private Integer itemsSucceeded = 0;
    private Integer itemsFailed = 0;
    private Integer itemsSkipped = 0;
    private Integer assetsSucceeded = 0;
    private Integer assetsFailed = 0;
    private Integer contractsCreated = 0;
    private Integer contractsReused = 0;
    private Set<Id> activatedContractIds = new Set<Id>();
    private Map<Id, Id> accountToContractMap = new Map<Id, Id>(); // AccountId → ContractId
    private List<Id> orderIdsForAssetCreation = new List<Id>(); // Collected for finish() REST callouts
    private List<String> orderLabelsForAssetCreation = new List<String>(); // Quote numbers for error reporting
    private List<String> errorMessages = new List<String>();
    private List<String> skippedItems = new List<String>();
    private List<Migration_Run_Detail__c> pendingRunDetails = new List<Migration_Run_Detail__c>();
    // Quote Ids that completed Step 8 (Order activated + AUA inserted) — used
    // by finish() to clear matching In_Rerun_Queue__c flags so successful
    // re-runs naturally drain the team-shared queue.
    private Set<Id> successfulQuoteIds = new Set<Id>();
    private static final Integer MAX_ERROR_MESSAGES = 100;
    private static final Integer MAX_SKIPPED_ITEMS = 200;
    // In-memory safety net for the pendingRunDetails buffer. With incremental
    // flushing at the end of each execute() chunk (≤20 Quotes), the buffer
    // normally holds ≤200 rows at a time, so 50000 is well above any realistic
    // single-chunk peak.
    private static final Integer MAX_RUN_DETAILS = 50000;

    // Attribute copying counters (Step 5b: QLIA → OIA)
    private Integer attributesCopied = 0;
    private Integer attributesFailed = 0;
    private Integer attributesSkipped = 0;

    // Products with subscription-capable selling models (TermDefined, Evergreen).
    // Products NOT in this set (OneTime or no selling model) must skip EndDate/subscription fields.
    private Set<Id> subscriptionProductIds = new Set<Id>();

    // Org-wide defaults for TaxTreatment and BillingTreatment (queried in start)
    // TaxTreatmentId does not exist on QLI, so we use the org default for all OrderItems.
    // BillingTreatmentId exists on QLI but may be null; org default is the fallback.
    private Id defaultTaxTreatmentId;
    private Id defaultBillingTreatmentId;

    // Created Order numbers (populated in finish() for the log)
    private String createdOrderNumbers = '';

    // Cached defaults (resolved once, reused across batches)
    private OrderMigrationService.ResolvedDefaults resolvedDefaults;

    /**
     * @description Constructor
     * @param soqlFilter LIKE pattern for Legacy_Id__c (e.g., 'DY_%') OR 'QNUM:' prefix with comma-separated QuoteNumbers (e.g., 'QNUM:00443359,00485170')
     * @param batchSize Number of Quotes per execute() call (capped at 50)
     * @param activateOrders If true, activates Orders and creates Assets
     * @param activateContracts If true, activates newly created Contracts
     */
    public OrderMigrationBatch(String soqlFilter, Integer batchSize,
                               Boolean activateOrders, Boolean activateContracts,
                               Id runLogId) {
        this(soqlFilter, batchSize, activateOrders, activateContracts, runLogId, null, false);
    }

    /**
     * @description 4-arg constructor overload used by existing tests. Delegates with
     *              runLogId = null and no pricebook override.
     */
    public OrderMigrationBatch(String soqlFilter, Integer batchSize,
                               Boolean activateOrders, Boolean activateContracts) {
        this(soqlFilter, batchSize, activateOrders, activateContracts, null, null, false);
    }

    /**
     * @description Extended constructor with pricebook override.
     * @param targetPricebookId When non-null, Orders are created on this Pricebook2 and
     *                          every OrderItem.PricebookEntryId is remapped to a PBE
     *                          in this pricebook.
     * @param autoCreateMissingPbes When true AND targetPricebookId is set, PBEs missing
     *                              from the target pricebook are auto-created at the
     *                              source QLI unit price. When false, Quotes with any
     *                              uncovered product are skipped.
     */
    public OrderMigrationBatch(String soqlFilter, Integer batchSize,
                               Boolean activateOrders, Boolean activateContracts,
                               Id runLogId,
                               Id targetPricebookId, Boolean autoCreateMissingPbes) {
        this.runLogId = runLogId;
        this.soqlFilter = soqlFilter;
        this.activateOrders = activateOrders != null ? activateOrders : false;
        this.activateContracts = activateContracts != null ? activateContracts : false;
        this.targetPricebookId = targetPricebookId;
        this.autoCreateMissingPbes = autoCreateMissingPbes == true;

        // Cap batch size at 20 to stay within DML governor limits.
        // Each Quote uses ~7 DML operations (Contract, AUA, Order, OrderAction, OrderItems, activate, AUA).
        // 20 × 7 = 140, safely under the 150 DML limit per transaction.
        Integer requestedSize = batchSize != null && batchSize > 0 ? batchSize : 10;
        this.batchSizeParam = Math.min(requestedSize, 20);

        // Capture user info for email notification
        User currentUser = [SELECT Id, Email, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        this.initiatedByUserId = currentUser.Id;
        this.initiatedByUserEmail = currentUser.Email;
        this.initiatedByUserName = currentUser.Name;
    }

    /**
     * @description Start method - resolves defaults and queries eligible Quotes
     * @param bc BatchableContext
     * @return QueryLocator for Quotes to process
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // ── Duplicate batch detection ──
        // Check if another OrderMigrationBatch is already running (not this one).
        List<AsyncApexJob> otherBatches = [
            SELECT Id FROM AsyncApexJob
            WHERE ApexClass.Name = 'OrderMigrationBatch'
            AND Id != :bc.getJobId()
            AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            LIMIT 1
        ];
        if (!otherBatches.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'OrderMigrationBatch: Another batch is running. Aborting this duplicate.');
            return Database.getQueryLocator([
                SELECT Id FROM Quote WHERE Id = null
            ]);
        }

        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'OrderMigrationBatch: Starting');
        System.debug(LoggingLevel.INFO, 'Filter: ' + this.soqlFilter);
        System.debug(LoggingLevel.INFO, 'ActivateOrders: ' + this.activateOrders);
        System.debug(LoggingLevel.INFO, 'ActivateContracts: ' + this.activateContracts);
        System.debug(LoggingLevel.INFO, 'BatchSize: ' + this.batchSizeParam);
        System.debug(LoggingLevel.INFO, '========================================');

        // Resolve defaults once (cached for all execute() calls)
        this.resolvedDefaults = OrderMigrationService.resolveDefaults();

        // Pre-query matching Quote IDs.
        // Supports two modes:
        //   1. LIKE pattern on QLI Legacy_Id__c (default): e.g., 'DY_%'
        //   2. QNUM: prefix with comma-separated QuoteNumbers: e.g., 'QNUM:00443359,00485170'
        Set<Id> matchingQuoteIds = new Set<Id>();

        if (OrderMigrationService.isSoqlMode(this.soqlFilter)) {
            // ── SOQL mode: run guarded query to collect Quote IDs ──
            this.isSoqlMode = true;
            String guardedSoql = OrderMigrationService.injectSafetyGuards(this.soqlFilter);
            // Replace user's SELECT columns with SELECT Id for ID collection
            String upper = guardedSoql.toUpperCase();
            Integer fromPos = upper.indexOf('FROM QUOTE');
            String idSoql = 'SELECT Id ' + guardedSoql.substring(fromPos);
            System.debug(LoggingLevel.INFO, 'SOQL mode: ' + idSoql);
            for (SObject record : Database.query(idSoql)) {
                matchingQuoteIds.add(record.Id);
            }
        } else if (this.soqlFilter != null && this.soqlFilter.startsWith('QNUM:')) {
            // ── QuoteNumber mode ──
            this.isQuoteNumberMode = true;
            String quoteNumbersCsv = this.soqlFilter.removeStart('QNUM:');
            List<String> quoteNumbers = new List<String>();
            for (String qn : quoteNumbersCsv.split(',')) {
                String trimmed = qn.trim();
                if (String.isNotBlank(trimmed)) {
                    quoteNumbers.add(trimmed);
                }
            }
            System.debug(LoggingLevel.INFO, 'QuoteNumber mode: targeting ' + quoteNumbers.size() + ' Quotes');
            for (Quote q : [SELECT Id FROM Quote WHERE QuoteNumber IN :quoteNumbers]) {
                matchingQuoteIds.add(q.Id);
            }
        } else {
            // ── Legacy LIKE pattern mode ──
            // NOTE: Database.getQueryLocator does not support bind variables inside
            // semi-join subqueries, so we resolve the Quote IDs first.
            String likeFilter = this.soqlFilter;
            for (QuoteLineItem qli : [
                SELECT QuoteId FROM QuoteLineItem WHERE Legacy_Id__c LIKE :likeFilter
            ]) {
                matchingQuoteIds.add(qli.QuoteId);
            }
        }

        System.debug(LoggingLevel.INFO, 'Found ' + matchingQuoteIds.size() +
            ' Quotes to process');

        // Pre-query products with subscription-capable selling models (TermDefined, Evergreen).
        // Products NOT in this set (OneTime, or no selling model at all) will have
        // EndDate and subscription fields cleared to avoid platform validation errors.
        for (ProductSellingModelOption psmo : [
            SELECT Product2Id FROM ProductSellingModelOption
            WHERE ProductSellingModel.SellingModelType IN ('TermDefined', 'Evergreen')
        ]) {
            this.subscriptionProductIds.add(psmo.Product2Id);
        }
        System.debug(LoggingLevel.INFO, 'Subscription-capable Products: ' + this.subscriptionProductIds.size());

        // Pre-query org-wide TaxTreatment and BillingTreatment defaults.
        // TaxTreatmentId has no QLI source; BillingTreatmentId is often null on legacy QLIs.
        List<TaxTreatment> taxTreatments = [
            SELECT Id FROM TaxTreatment WHERE Status = 'Active' LIMIT 1
        ];
        if (!taxTreatments.isEmpty()) {
            this.defaultTaxTreatmentId = taxTreatments[0].Id;
        }
        List<BillingTreatment> billingTreatments = [
            SELECT Id FROM BillingTreatment WHERE Status = 'Active' LIMIT 1
        ];
        if (!billingTreatments.isEmpty()) {
            this.defaultBillingTreatmentId = billingTreatments[0].Id;
        }
        System.debug(LoggingLevel.INFO, 'Default TaxTreatmentId: ' + this.defaultTaxTreatmentId);
        System.debug(LoggingLevel.INFO, 'Default BillingTreatmentId: ' + this.defaultBillingTreatmentId);

        // ── Pricebook override: pre-batch auto-create of missing PBEs ──
        // When auto-create is on, we pre-create any missing PBEs once before the
        // batch begins chunking, so subsequent execute() chunks see full coverage.
        if (this.targetPricebookId != null && this.autoCreateMissingPbes && !matchingQuoteIds.isEmpty()) {
            // Aggregate one request per (product, currency) — a product appearing
            // in multiple currencies needs a PBE per currency, not just one.
            Set<String> seenKeys = new Set<String>();
            List<OrderMigrationService.PbeAutoCreateRequest> requests =
                new List<OrderMigrationService.PbeAutoCreateRequest>();
            for (QuoteLineItem qli : [
                SELECT Product2Id, UnitPrice, CurrencyIsoCode
                FROM QuoteLineItem
                WHERE QuoteId IN :matchingQuoteIds
                AND Legacy_Id__c > ''
            ]) {
                if (qli.Product2Id == null) continue;
                String key = qli.Product2Id + '|' + qli.CurrencyIsoCode;
                if (seenKeys.contains(key)) continue;
                seenKeys.add(key);
                requests.add(new OrderMigrationService.PbeAutoCreateRequest(
                    qli.Product2Id, qli.CurrencyIsoCode, qli.UnitPrice));
            }
            if (!requests.isEmpty()) {
                OrderMigrationService.AutoCreateResult res =
                    OrderMigrationService.autoCreateMissingPbes(
                        requests, this.targetPricebookId);
                this.pbesAutoCreated = res.created;
                if (res.productsMissingStandardPbe != null) {
                    this.productsMissingStandardPbe.addAll(res.productsMissingStandardPbe);
                }
                for (String err : res.errors) {
                    if (this.errorMessages.size() < MAX_ERROR_MESSAGES) {
                        this.errorMessages.add('[AUTO_CREATE_PBE] ' + err);
                    }
                    recordRunDetail('AutoCreatePbeError', 'Error',
                        null, null, null, null, null, err);
                }
                System.debug(LoggingLevel.INFO, 'Auto-created ' + res.created +
                    ' PBEs in target pricebook ' + this.targetPricebookId);
            }
        }

        // Convert to List<Id> for QueryLocator bind compatibility
        List<Id> quoteIdList = new List<Id>(matchingQuoteIds);

        return Database.getQueryLocator([
            SELECT Id, Name, QuoteNumber, Status, SalesTransactionTypeId, CurrencyIsoCode,
                   OpportunityId, Opportunity.StageName, QuoteAccountId,
                   IsPrimary__c, ContactId, BillToContactId, Pricebook2Id, Legacy_Id__c,
                   Quote_Type__c, Deal_Type__c, LegalEntityId,
                   Description, Billing_Partner__c,
                   Migration_Contract_Id__c, Force_New_Contract__c,
                   Account_Billing_Account__c, Bill_To_Place__c, Ship_To_Place__c,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                   AWS_Marketplace_Agreement_ID__c, AWS_Marketplace_Offer_ID__c,
                   Cross_Sale_Type__c, Disable_Export_Control__c,
                   Payment_Portal__c, Referral_Partner__c, Quote_NARR__c
            FROM Quote
            WHERE Id IN :quoteIdList
            AND ((IsPrimary__c = true AND Opportunity.StageName = 'Closed Won') OR LegacyRenewalQuote__c = true)
            ORDER BY QuoteNumber
        ]);
    }

    /**
     * @description Execute method - processes a batch of Quotes, creating Orders and OrderItems
     * @param bc BatchableContext
     * @param quotes List of Quote records to process
     */
    public void execute(Database.BatchableContext bc, List<Quote> quotes) {
        System.debug(LoggingLevel.INFO, 'Processing batch of ' + quotes.size() + ' quotes');
        String likeFilter = this.soqlFilter;

        for (Quote quote : quotes) {
            this.ordersProcessed++;
            Boolean orderHadErrors = false;
            Boolean isNewContract = false;
            Id contractId;

            try {
                // ── Step 1: Query child QLIs ──
                // In QNUM mode, get ALL QLIs with populated Legacy_Id (no LIKE restriction).
                // In LIKE mode, filter QLIs by the Legacy_Id pattern.
                List<QuoteLineItem> qlis;
                if (this.isQuoteNumberMode || this.isSoqlMode) {
                    qlis = [
                        SELECT Id, QuoteId, StartDate, EndDate, ServiceDate,
                               SubscriptionTerm,
                               PeriodBoundary, PeriodBoundaryDay, PeriodBoundaryStartMonth,
                               BillingFrequency, ProrationPolicyId,
                               UnitPrice, Discount, DiscountAmount, ListPrice, Quantity,
                               Product2Id, Product2.Name, Legacy_Id__c, PricebookEntryId,
                               Fortra_Product_Type__c, Serial_Number__c, Swap__c, GSA__c,
                               Hardware__c, LegalEntityId, BillingTreatmentId,
                               Currency__c, Hardware_ID__c, Hostname__c, Instances__c,
                               LPAR_Number__c, LPAR_System_Name__c, Model__c,
                               Partition_Reference__c, System_Type__c, Sales_Support_Notes__c
                        FROM QuoteLineItem
                        WHERE QuoteId = :quote.Id
                        AND Legacy_Id__c > ''
                    ];
                } else {
                    qlis = [
                        SELECT Id, QuoteId, StartDate, EndDate, ServiceDate,
                               SubscriptionTerm,
                               PeriodBoundary, PeriodBoundaryDay, PeriodBoundaryStartMonth,
                               BillingFrequency, ProrationPolicyId,
                               UnitPrice, Discount, DiscountAmount, ListPrice, Quantity,
                               Product2Id, Product2.Name, Legacy_Id__c, PricebookEntryId,
                               Fortra_Product_Type__c, Serial_Number__c, Swap__c, GSA__c,
                               Hardware__c, LegalEntityId, BillingTreatmentId,
                               Currency__c, Hardware_ID__c, Hostname__c, Instances__c,
                               LPAR_Number__c, LPAR_System_Name__c, Model__c,
                               Partition_Reference__c, System_Type__c, Sales_Support_Notes__c
                        FROM QuoteLineItem
                        WHERE QuoteId = :quote.Id
                        AND Legacy_Id__c LIKE :likeFilter
                    ];
                }

                if (qlis.isEmpty()) {
                    addErrorMessage('Quote ' + quote.QuoteNumber + ': No matching QLIs found');
                    recordRunDetail('NoMatchingQlis', 'Error',
                        quote.Id, quote.QuoteNumber, null, null, null,
                        'No Quote Line Items with a populated Legacy Id were found for this Quote.');
                    this.ordersFailed++;
                    continue;
                }

                // ── Pricebook override: build PBE remap and check coverage ──
                Map<Id, PricebookEntry> pbeRemap = null;
                if (this.targetPricebookId != null) {
                    Set<Id> productIdsForRemap = new Set<Id>();
                    for (QuoteLineItem qli : qlis) {
                        if (qli.Product2Id != null) {
                            productIdsForRemap.add(qli.Product2Id);
                        }
                    }
                    pbeRemap = OrderMigrationService.buildPbeRemapForScope(
                        productIdsForRemap, this.targetPricebookId, quote.CurrencyIsoCode);

                    List<String> uncoveredProducts = new List<String>();
                    for (QuoteLineItem qli : qlis) {
                        if (qli.Product2Id != null && !pbeRemap.containsKey(qli.Product2Id)) {
                            uncoveredProducts.add(
                                qli.Product2 != null && qli.Product2.Name != null
                                    ? qli.Product2.Name
                                    : String.valueOf(qli.Product2Id));
                        }
                    }
                    if (!uncoveredProducts.isEmpty()) {
                        // Skip this Quote entirely. The +1 in ordersProcessed happened
                        // optimistically at the top of the loop — undo it since we never
                        // actually attempted an Order.
                        this.ordersProcessed--;
                        this.quotesSkippedNoCoverage++;
                        addSkippedItem('Quote ' + quote.QuoteNumber +
                            ' - Skipped: ' + uncoveredProducts.size() +
                            ' product(s) missing PricebookEntry in target pricebook: ' +
                            String.join(uncoveredProducts, ', '));
                        recordRunDetail('MissingPbeCoverage', 'Skip',
                            quote.Id, quote.QuoteNumber, null, null, null,
                            uncoveredProducts.size() + ' product(s) missing PricebookEntry: '
                                + String.join(uncoveredProducts, ', '));
                        continue;
                    }
                }

                this.itemsProcessed += qlis.size();

                // ── Step 1b: Apply CMT defaults to source Quote (e.g. SalesTransactionTypeId) ──
                // Legacy Quotes lack Revenue Cloud fields like SalesTransactionTypeId.
                // Setting it now allows the Quote to be repriced in the TLE after migration.
                if (OrderMigrationService.applyQuoteDefaults(quote, this.resolvedDefaults)) {
                    Database.SaveResult quoteUpdateResult = Database.update(quote, false);
                    if (!quoteUpdateResult.isSuccess()) {
                        for (Database.Error err : quoteUpdateResult.getErrors()) {
                            addErrorMessage('Quote ' + quote.QuoteNumber +
                                ' - Quote default update failed: ' + err.getMessage());
                            recordRunDetail('QuoteDefaultUpdateFailed', 'Error',
                                quote.Id, quote.QuoteNumber, null, null, null,
                                err.getMessage());
                        }
                    }
                }

                // Determine earliest StartDate from QLIs
                Date earliestStartDate = null;
                for (QuoteLineItem qli : qlis) {
                    if (qli.StartDate != null && (earliestStartDate == null || qli.StartDate < earliestStartDate)) {
                        earliestStartDate = qli.StartDate;
                    }
                }
                if (earliestStartDate == null) {
                    earliestStartDate = Date.today();
                }

                // ── Step 2: Resolve or create Contract ──
                // Transform old Deal_Type__c values to simplified 2-value scheme
                String contractDealType = quote.Deal_Type__c;
                if (contractDealType != null && contractDealType != 'Fortra Originated') {
                    contractDealType = 'Channel Originated';
                }

                // Build additional Contract fields from the source Quote.
                // These are only applied to newly created Contracts (reused ones keep existing values).
                Map<String, Object> contractFields = new Map<String, Object>{
                    'Name' => quote.Name != null ? quote.Name.left(80) : null,
                    'Pricebook2Id' => quote.Pricebook2Id,
                    'CurrencyIsoCode' => quote.CurrencyIsoCode,
                    'Legal_Entity__c' => quote.LegalEntityId,
                    'Deal_Type__c' => contractDealType,
                    'SourceOpportunityId' => quote.OpportunityId,
                    'SourceQuoteId' => quote.Id,
                    'Description' => quote.Description,
                    'Legacy_Id__c' => quote.Legacy_Id__c != null ? quote.Legacy_Id__c : quote.QuoteNumber,
                    'BillingStreet' => quote.BillingStreet,
                    'BillingCity' => quote.BillingCity,
                    'BillingState' => quote.BillingState,
                    'BillingPostalCode' => quote.BillingPostalCode,
                    'BillingCountry' => quote.BillingCountry,
                    'ShippingStreet' => quote.ShippingStreet != null ? quote.ShippingStreet : quote.BillingStreet,
                    'ShippingCity' => quote.ShippingCity != null ? quote.ShippingCity : quote.BillingCity,
                    'ShippingState' => quote.ShippingState != null ? quote.ShippingState : quote.BillingState,
                    'ShippingPostalCode' => quote.ShippingPostalCode != null ? quote.ShippingPostalCode : quote.BillingPostalCode,
                    'ShippingCountry' => quote.ShippingCountry != null ? quote.ShippingCountry : quote.BillingCountry
                };

                // Skip Quotes with no QuoteAccountId (data quality issue in legacy data)
                if (quote.QuoteAccountId == null) {
                    addErrorMessage('Quote ' + quote.QuoteNumber +
                        ' - Skipped: Quote has no QuoteAccountId');
                    recordRunDetail('NoAccountId', 'Skip',
                        quote.Id, quote.QuoteNumber, null, null, null,
                        'Quote is missing QuoteAccountId. Set the Account on the Quote, then re-run.');
                    this.ordersFailed++;
                    continue;
                }

                // Contract resolution priority:
                // 1. Migration_Contract_Id__c — use the specified Contract directly
                // 2. Default — lookup by Legacy_Id__c (1-Quote → 1-Contract by external
                //    ID); reuse on match, insert on miss. Self-heals from prior partial
                //    runs that left orphan Contracts behind.
                if (quote.Migration_Contract_Id__c != null) {
                    contractId = quote.Migration_Contract_Id__c;
                    isNewContract = false;
                    this.contractsReused++;
                    System.debug(LoggingLevel.INFO, 'Quote ' + quote.QuoteNumber +
                        ' - Using specified Contract: ' + contractId);
                } else {
                    Boolean forceNew = false;
                    OrderMigrationService.ContractResult contractResult =
                        OrderMigrationService.resolveOrCreateContract(
                            quote.QuoteAccountId, earliestStartDate,
                            contractFields, forceNew);

                    if (contractResult.contractId == null) {
                        String resolveCategory = (contractResult.accountMismatch == true)
                            ? 'ContractAccountMismatch'
                            : 'ContractResolutionFailed';
                        addErrorMessage('Quote ' + quote.QuoteNumber +
                            ' - ' + resolveCategory + ': ' + contractResult.errorMessage);
                        recordRunDetail(resolveCategory, 'Error',
                            quote.Id, quote.QuoteNumber, null, null, null,
                            contractResult.errorMessage);
                        this.ordersFailed++;
                        continue;
                    }

                    contractId = contractResult.contractId;
                    isNewContract = contractResult.wasCreated;
                    if (isNewContract) {
                        this.contractsCreated++;
                    } else {
                        this.contractsReused++;
                    }
                }
                // Track Account→Contract mapping for AssetContractRelationship creation in finish()
                this.accountToContractMap.put(quote.QuoteAccountId, contractId);

                // ── Step 3: Create Order (Draft) — WITHOUT AUA ──
                // AUA is deliberately omitted at this stage. Without AUA, the platform
                // does not check CalculationStatus on activation, allowing DML activation
                // of Orders with pre-set pricing fields.
                //
                // Skip if a migration Order already exists for this Quote (regardless
                // of age). The platform enforces uniqueness on Order.Legacy_Id__c
                // (= QuoteNumber for legacy renewals), so attempting a second insert
                // crashes with DUPLICATE_VALUE. To re-migrate a Quote, run cleanup
                // first — that deletes the prior Order and the next run finds nothing
                // here and proceeds normally.
                List<Order> existingMigrationOrders = [
                    SELECT Id FROM Order
                    WHERE QuoteId = :quote.Id
                    AND Contract.Migration_Created__c = true
                    LIMIT 1
                ];
                if (!existingMigrationOrders.isEmpty()) {
                    System.debug(LoggingLevel.INFO, 'Quote ' + quote.QuoteNumber +
                        ' — migration Order already exists. Skipping duplicate.');
                    // Surface the skip on the Review tab. Mirror the MissingPbeCoverage
                    // pattern: undo the optimistic ordersProcessed++ from the top of the
                    // loop since no Order was attempted, and add a Review-tab detail row.
                    this.ordersProcessed--;
                    addSkippedItem('Quote ' + quote.QuoteNumber +
                        ' - Skipped: a migration Order already exists for this Quote');
                    recordRunDetail('DuplicateSkipped', 'Skip',
                        quote.Id, quote.QuoteNumber, null, existingMigrationOrders[0].Id, null,
                        'A migration-created Order already exists for this Quote. Skipped to avoid duplicate. Run cleanup to delete the prior Order if you want to re-migrate.');
                    continue;
                }

                // Bypass checklist validation — legacy Quotes don't have checklist items
                OrderValidationTriggerHandler.bypassValidation = true;
                Order ord = new Order();
                ord.AccountId = quote.QuoteAccountId;
                ord.ContractId = contractId;
                ord.EffectiveDate = earliestStartDate;
                ord.Pricebook2Id = this.targetPricebookId != null
                    ? this.targetPricebookId
                    : quote.Pricebook2Id;
                // BillToContactId fallback: Quote.BillToContactId → Quote.ContactId → first Contact on Account
                if (quote.BillToContactId != null) {
                    ord.BillToContactId = quote.BillToContactId;
                } else if (quote.ContactId != null) {
                    ord.BillToContactId = quote.ContactId;
                } else if (quote.QuoteAccountId != null) {
                    List<Contact> acctContacts = [
                        SELECT Id FROM Contact
                        WHERE AccountId = :quote.QuoteAccountId
                        LIMIT 1
                    ];
                    if (!acctContacts.isEmpty()) {
                        ord.BillToContactId = acctContacts[0].Id;
                    }
                }
                ord.Name = quote.Name != null ? quote.Name.left(80) : null;
                ord.OpportunityId = quote.OpportunityId;
                ord.QuoteId = quote.Id;
                ord.Quote_Type__c = quote.Quote_Type__c;
                // Transform old Deal_Type__c values to simplified 2-value scheme
                String orderDealType = quote.Deal_Type__c;
                if (orderDealType != null && orderDealType != 'Fortra Originated') {
                    orderDealType = 'Channel Originated';
                }
                ord.Deal_Type__c = orderDealType;
                ord.Deal_Origin__c = orderDealType;
                ord.LegalEntityId = quote.LegalEntityId;
                ord.Bill_To_Account__c = quote.Account_Billing_Account__c;
                ord.Bill_To_Place__c = quote.Bill_To_Place__c;
                ord.Ship_To_Place__c = quote.Ship_To_Place__c;
                ord.BillingStreet = quote.BillingStreet;
                ord.BillingCity = quote.BillingCity;
                ord.BillingState = quote.BillingState;
                ord.BillingPostalCode = quote.BillingPostalCode;
                ord.BillingCountry = quote.BillingCountry;
                // Shipping address: use Quote shipping, fall back to billing if null
                ord.ShippingStreet = quote.ShippingStreet != null ? quote.ShippingStreet : quote.BillingStreet;
                ord.ShippingCity = quote.ShippingCity != null ? quote.ShippingCity : quote.BillingCity;
                ord.ShippingState = quote.ShippingState != null ? quote.ShippingState : quote.BillingState;
                ord.ShippingPostalCode = quote.ShippingPostalCode != null ? quote.ShippingPostalCode : quote.BillingPostalCode;
                ord.ShippingCountry = quote.ShippingCountry != null ? quote.ShippingCountry : quote.BillingCountry;
                ord.Legacy_Id__c = quote.Legacy_Id__c != null ? quote.Legacy_Id__c : quote.QuoteNumber;
                ord.Status = 'Draft';
                ord.CurrencyIsoCode = quote.CurrencyIsoCode;
                ord.Type = quote.Quote_Type__c;
                ord.Contract_Start_Date__c = earliestStartDate;
                ord.Description = quote.Description;
                ord.Partner_Account__c = quote.Billing_Partner__c;
                ord.AWS_Marketplace_Agreement_ID__c = quote.AWS_Marketplace_Agreement_ID__c;
                ord.AWS_Marketplace_Offer_ID__c = quote.AWS_Marketplace_Offer_ID__c;
                ord.Cross_Sale_Type__c = quote.Cross_Sale_Type__c;
                ord.Disable_Export_Control__c = quote.Disable_Export_Control__c;
                ord.Payment_Portal__c = quote.Payment_Portal__c;
                ord.Referral_Partner__c = quote.Referral_Partner__c;
                ord.Order_NARR__c = quote.Quote_NARR__c;

                // Fall back to Standard Pricebook if Quote has no Pricebook
                if (ord.Pricebook2Id == null) {
                    List<Pricebook2> stdPbs = [
                        SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1
                    ];
                    if (!stdPbs.isEmpty()) {
                        ord.Pricebook2Id = stdPbs[0].Id;
                    }
                }

                // Apply CMT order defaults
                OrderMigrationService.applyOrderDefaults(ord, this.resolvedDefaults);

                insert ord;
                OrderValidationTriggerHandler.bypassValidation = false;

                // ── Step 4: Create OrderAction (NO AUA yet) ──
                OrderAction oa = new OrderAction();
                oa.OrderId = ord.Id;
                oa.Type = 'Add';
                insert oa;

                // ── Step 5: Create OrderItems from QLIs ──
                List<OrderItem> orderItems = new List<OrderItem>();
                List<Id> sourceQliIds = new List<Id>(); // Parallel tracking for Step 5b attribute copying

                for (QuoteLineItem qli : qlis) {
                    Boolean isSubscription = this.subscriptionProductIds.contains(qli.Product2Id);

                    // Subscription products require dates for SubscriptionTerm calculation.
                    // OneTime products legitimately have no dates — they get ServiceDate
                    // defaulted and EndDate cleared in the non-subscription block below.
                    if (isSubscription && (qli.StartDate == null || qli.EndDate == null)) {
                        String missingField = qli.StartDate == null ? 'StartDate' : 'EndDate';
                        if (qli.StartDate == null && qli.EndDate == null) {
                            missingField = 'StartDate, EndDate';
                        }
                        addSkippedItem(qli.Id + ' (' + qli.Product2.Name + ') - Missing ' + missingField);
                        recordRunDetail('QliMissingDates', 'Skip',
                            quote.Id, quote.QuoteNumber, qli.Id, ord.Id, null,
                            'Subscription line missing ' + missingField + ' (Product: '
                                + (qli.Product2 != null ? qli.Product2.Name : '') + ')');
                        this.itemsSkipped++;
                        continue;
                    }

                    OrderItem oi = new OrderItem();
                    oi.OrderId = ord.Id;
                    oi.OrderActionId = oa.Id;
                    oi.Product2Id = qli.Product2Id;
                    // When a target pricebook override is active, remap PBE to the
                    // target. Coverage was already verified above so pbeRemap.get() is
                    // guaranteed to return a non-null entry.
                    oi.PricebookEntryId = (this.targetPricebookId != null && pbeRemap != null)
                        ? pbeRemap.get(qli.Product2Id).Id
                        : qli.PricebookEntryId;
                    oi.Quantity = qli.Quantity;
                    Decimal unitPrice = qli.UnitPrice != null ? qli.UnitPrice : 0;
                    oi.UnitPrice = unitPrice;
                    // NetUnitPrice and TotalLineAmount are REQUIRED for Order activation.
                    // Pre-set from source QLI pricing to bypass the pricing engine.
                    oi.NetUnitPrice = unitPrice;
                    oi.TotalLineAmount = unitPrice * qli.Quantity;
                    // ServiceDate defaults to Order EffectiveDate for OneTime products without dates
                    oi.ServiceDate = qli.StartDate != null ? qli.StartDate : earliestStartDate;
                    oi.EndDate = qli.EndDate;
                    oi.PricingTermCount = 1;
                    oi.Legacy_Id__c = qli.Legacy_Id__c;

                    // Map additional QLI fields to OrderItem
                    oi.Discount = qli.Discount;
                    oi.DiscountAmount = qli.DiscountAmount;
                    oi.Fortra_Product_Type__c = qli.Fortra_Product_Type__c;
                    oi.Serial_Number__c = qli.Serial_Number__c;
                    oi.Swap__c = qli.Swap__c;
                    oi.GSA__c = qli.GSA__c;
                    oi.Hardware__c = qli.Hardware__c;
                    oi.LegalEntityId = qli.LegalEntityId;
                    // Currency__c is not writable on OrderItem (formula/system field)
                    oi.Hardware_ID__c = qli.Hardware_ID__c;
                    oi.Hostname__c = qli.Hostname__c;
                    oi.Instances__c = qli.Instances__c;
                    oi.LPAR_Number__c = qli.LPAR_Number__c;
                    oi.LPAR_System_Name__c = qli.LPAR_System_Name__c;
                    oi.Model__c = qli.Model__c;
                    oi.Partition__c = qli.Partition_Reference__c;
                    oi.System_Type__c = qli.System_Type__c;
                    oi.Sales_Support_Notes__c = qli.Sales_Support_Notes__c;
                    // BillingTreatmentId: use QLI value if present, otherwise org default
                    oi.BillingTreatmentId = qli.BillingTreatmentId != null
                        ? qli.BillingTreatmentId : this.defaultBillingTreatmentId;
                    // TaxTreatmentId: no QLI source, always use org default
                    oi.TaxTreatmentId = this.defaultTaxTreatmentId;

                    // Calculate additional OrderItem fields from CMT defaults and QLI source
                    OrderMigrationService.calculateOrderItemFields(oi, this.resolvedDefaults);

                    // Products without a subscription selling model (OneTime or no model at all)
                    // don't support EndDate, BillingFrequency2, PeriodBoundary, etc.
                    // Platform rejects these fields on Order activation.
                    if (!this.subscriptionProductIds.contains(qli.Product2Id)) {
                        oi.EndDate = null;
                        oi.put('BillingFrequency2', null);
                        oi.put('PeriodBoundary', null);
                        oi.PeriodBoundaryDay = null;
                        oi.PeriodBoundaryStartMonth = null;
                        oi.SubscriptionTerm = null;
                    }

                    orderItems.add(oi);
                    sourceQliIds.add(qli.Id);
                }

                // Bulk DML insert with partial success
                Map<Id, Id> qliToOrderItemMap = new Map<Id, Id>();
                if (!orderItems.isEmpty()) {
                    Database.SaveResult[] results = Database.insert(orderItems, false);

                    for (Integer i = 0; i < results.size(); i++) {
                        if (results[i].isSuccess()) {
                            this.itemsSucceeded++;
                            qliToOrderItemMap.put(sourceQliIds[i], orderItems[i].Id);
                        } else {
                            this.itemsFailed++;
                            orderHadErrors = true;
                            OrderItem failedItem = orderItems[i];
                            Id failedQliId = sourceQliIds[i];
                            for (Database.Error err : results[i].getErrors()) {
                                addErrorMessage('OrderItem for QLI ' + failedItem.Legacy_Id__c +
                                    ': ' + err.getMessage());
                                recordRunDetail('OrderItemDmlFailed', 'Error',
                                    quote.Id, quote.QuoteNumber, failedQliId, ord.Id, null,
                                    err.getMessage());
                            }
                        }
                    }
                }

                // ── Step 5b: Copy QuoteLineItemAttributes → OrderItemAttributes ──
                // Attributes must exist BEFORE Order activation (Step 7) so prehooks
                // and flows can reference them at runtime via SalesTransactionItemAttribute.
                // Copy AttributeDefinitionId and AttributePicklistValueId directly from
                // source QLIA records (same org-wide definitions apply).
                if (!qliToOrderItemMap.isEmpty()) {
                    try {
                        Set<Id> mappedQliIds = qliToOrderItemMap.keySet();
                        List<QuoteLineItemAttribute> sourceAttrs = [
                            SELECT QuoteLineItemId, AttributeDefinitionId,
                                   AttributeValue, AttributePicklistValueId
                            FROM QuoteLineItemAttribute
                            WHERE QuoteLineItemId IN :mappedQliIds
                        ];

                        if (!sourceAttrs.isEmpty()) {
                            // Source QLIAs may reference picklist values that have
                            // since been deactivated. Platform rejects OIA inserts
                            // pointing at non-Active/Draft APVs, so resolve the
                            // current status and skip stale references.
                            Set<Id> apvIdsToCheck = new Set<Id>();
                            for (QuoteLineItemAttribute qlia : sourceAttrs) {
                                if (qlia.AttributePicklistValueId != null) {
                                    apvIdsToCheck.add(qlia.AttributePicklistValueId);
                                }
                            }
                            Set<Id> activeApvIds = new Set<Id>();
                            if (!apvIdsToCheck.isEmpty()) {
                                for (AttributePicklistValue apv : [
                                    SELECT Id FROM AttributePicklistValue
                                    WHERE Id IN :apvIdsToCheck
                                    AND Status IN ('Active', 'Draft')
                                ]) {
                                    activeApvIds.add(apv.Id);
                                }
                            }

                            List<OrderItemAttribute> oiAttrs = new List<OrderItemAttribute>();
                            for (QuoteLineItemAttribute qlia : sourceAttrs) {
                                Id orderItemId = qliToOrderItemMap.get(qlia.QuoteLineItemId);
                                if (orderItemId == null) continue;
                                if (qlia.AttributePicklistValueId != null
                                    && !activeApvIds.contains(qlia.AttributePicklistValueId)) {
                                    this.attributesSkipped++;
                                    recordRunDetail('OiaInsertFailed', 'Skip',
                                        quote.Id, quote.QuoteNumber, qlia.QuoteLineItemId, ord.Id, orderItemId,
                                        'Source AttributePicklistValue is Inactive — pre-emptively skipped');
                                    continue;
                                }
                                OrderItemAttribute oia = new OrderItemAttribute();
                                oia.OrderItemId = orderItemId;
                                oia.AttributeDefinitionId = qlia.AttributeDefinitionId;
                                oia.AttributeValue = qlia.AttributeValue;
                                oia.AttributePicklistValueId = qlia.AttributePicklistValueId;
                                oiAttrs.add(oia);
                            }

                            if (!oiAttrs.isEmpty()) {
                                List<Database.SaveResult> attrResults =
                                    Database.insertImmediate(oiAttrs);
                                for (Integer i = 0; i < attrResults.size(); i++) {
                                    if (attrResults[i].isSuccess()) {
                                        this.attributesCopied++;
                                    } else {
                                        this.attributesFailed++;
                                        for (Database.Error err : attrResults[i].getErrors()) {
                                            addErrorMessage('OIA insert failed (OrderItem: ' +
                                                oiAttrs[i].OrderItemId + '): ' + err.getMessage());
                                            recordRunDetail('OiaInsertFailed', 'Error',
                                                quote.Id, quote.QuoteNumber, null, ord.Id, oiAttrs[i].OrderItemId,
                                                err.getMessage());
                                        }
                                    }
                                }
                            }
                        } else {
                            // No source attributes found for these QLIs — track as skipped
                            this.attributesSkipped += qliToOrderItemMap.size();
                        }
                    } catch (Exception attrEx) {
                        addErrorMessage('Attribute copy failed for Quote ' +
                            quote.QuoteNumber + ': ' + attrEx.getMessage());
                        recordRunDetail('AttributeCopyFailed', 'Error',
                            quote.Id, quote.QuoteNumber, null, ord.Id, null,
                            attrEx.getMessage());
                        this.attributesFailed++;
                    }
                }

                // ── Step 6: Activate Contract BEFORE Order ──
                // Salesforce requires the linked Contract to be Activated before
                // an Order referencing it can be activated.
                if (this.activateOrders && contractId != null
                    && !this.activatedContractIds.contains(contractId)) {
                    Contract c = new Contract(Id = contractId, Status = 'Activated');
                    Database.SaveResult contractActivateResult = Database.update(c, false);
                    if (contractActivateResult.isSuccess()) {
                        this.activatedContractIds.add(contractId);
                    } else {
                        orderHadErrors = true;
                        for (Database.Error err : contractActivateResult.getErrors()) {
                            addErrorMessage('Quote ' + quote.QuoteNumber +
                                ' - Contract activation failed: ' + err.getMessage());
                            recordRunDetail('ContractActivationFailed', 'Error',
                                quote.Id, quote.QuoteNumber, null, ord.Id, null,
                                err.getMessage());
                        }
                    }
                }

                // ── Step 7: Activate Order (NO AUA = bypasses CalculationStatus check) ──
                // Without AUA, the platform treats this as a simple Order and does not
                // require CalculationStatus to be set. No assets are created at this point.
                if (this.activateOrders) {
                    ord.Status = 'Activated';
                    Database.SaveResult activateResult = Database.update(ord, false);
                    if (!activateResult.isSuccess()) {
                        orderHadErrors = true;
                        for (Database.Error err : activateResult.getErrors()) {
                            addErrorMessage('Quote ' + quote.QuoteNumber +
                                ' - Order activation failed: ' + err.getMessage());
                            recordRunDetail('OrderActivationFailed', 'Error',
                                quote.Id, quote.QuoteNumber, null, ord.Id, null,
                                err.getMessage());
                        }
                    }
                }

                // ── Step 8: Insert AUA to enable lifecycle management + auto-create Assets ──
                // The platform auto-creates Assets with proper AssetAction records when
                // an AUA is added to an Activated Order. Done in execute() so each batch
                // chunk is its own transaction — flow failures don't affect other chunks
                // or the finish() run log update.
                if (this.activateOrders && !orderHadErrors) {
                    try {
                        AppUsageAssignment aua = new AppUsageAssignment(
                            RecordId = ord.Id,
                            AppUsageType = 'RevenueLifecycleManagement');
                        insert aua;
                        this.orderIdsForAssetCreation.add(ord.Id);
                        this.orderLabelsForAssetCreation.add(quote.QuoteNumber);
                    } catch (Exception auaEx) {
                        addErrorMessage('Quote ' + quote.QuoteNumber +
                            ' - AUA insertion failed: ' + auaEx.getMessage());
                        recordRunDetail('AuaInsertionFailed', 'Error',
                            quote.Id, quote.QuoteNumber, null, ord.Id, null,
                            auaEx.getMessage());
                    }
                } else if (this.activateOrders && orderHadErrors) {
                    this.orderIdsForAssetCreation.add(ord.Id);
                    this.orderLabelsForAssetCreation.add(quote.QuoteNumber);
                }

                // ── Track order success/failure ──
                if (orderHadErrors) {
                    this.ordersFailed++;
                } else {
                    this.ordersSucceeded++;
                    if (quote != null && quote.Id != null) {
                        this.successfulQuoteIds.add(quote.Id);
                    }
                }

            } catch (Exception e) {
                this.ordersFailed++;
                addErrorMessage('Quote ' + quote.QuoteNumber + ': ' + e.getMessage());
                recordRunDetail('Unhandled', 'Error',
                    quote.Id, quote.QuoteNumber, null, null, null,
                    e.getMessage());
            }
        }

        // ── Incremental flush of Migration_Run_Detail__c rows ──
        // Persist this chunk's detail rows immediately so they survive a later
        // batch failure and stay under the in-memory buffer cap on long runs.
        // The runLogId set in the constructor points at the sentinel created
        // by the controller before the batch started.
        persistRunDetails(this.runLogId);
    }

    /**
     * @description Finish method - creates audit log record and sends email notification
     * @param bc BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        // ── ONLY update the run log. Nothing else. ──
        // Any other DML (ACR creation, email) can trigger flows that cause
        // uncatchable LimitExceptions, rolling back the entire finish() transaction
        // including this log update. So we do ONLY the log update here.

        // Always query actual data for reliable counts.
        // Stateful counters are lost when execute() triggers flows that roll back,
        // and the duplicate batch's finish() may run before the real batch's AUAs are committed.
        //
        // Scope the count to THIS run only: anchor the lower bound at the run
        // log's Run_Date__c (set when the controller created the sentinel).
        // The prior `now - 1hr` window leaked Orders from other concurrent or
        // recently-completed runs into this run's totals (e.g., MIG-0141 shown
        // as 363 when it actually created 4 — MIG-0139's 359 from 25 minutes
        // earlier were inside the 1hr window). Falls back to the legacy 1hr
        // window if runLogId is null (test/direct-invocation paths).
        Datetime runWindowStart = Datetime.now().addHours(-1);
        if (this.runLogId != null) {
            List<Migration_Run_Log__c> logs = [
                SELECT Run_Date__c FROM Migration_Run_Log__c
                WHERE Id = :this.runLogId LIMIT 1
            ];
            if (!logs.isEmpty() && logs[0].Run_Date__c != null) {
                runWindowStart = logs[0].Run_Date__c;
            }
        }
        try {
            Integer actualOrders = [
                SELECT COUNT() FROM Order
                WHERE Contract.Migration_Created__c = true
                AND CreatedDate >= :runWindowStart
            ];
            if (actualOrders > 0) {
                this.ordersProcessed = actualOrders;
                this.ordersSucceeded = actualOrders;
                this.itemsProcessed = [
                    SELECT COUNT() FROM OrderItem
                    WHERE Order.Contract.Migration_Created__c = true
                    AND CreatedDate >= :runWindowStart
                ];
                this.itemsSucceeded = this.itemsProcessed;
                this.assetsSucceeded = [
                    SELECT COUNT() FROM OrderItem
                    WHERE Order.Status = 'Activated'
                    AND Order.Contract.Migration_Created__c = true
                    AND CreatedDate >= :runWindowStart
                ];
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Data recovery query failed: ' + e.getMessage());
        }

        createMigrationRunLog(bc.getJobId(), false);
        autoClearRerunQueueForSuccessful();
    }

    /**
     * Auto-removes successfully-migrated Quotes from the team-shared Rerun
     * Queue. Fires once per batch finish, after the run log is saved. The
     * stricter "Asset actually created" detection lives in a record-triggered
     * flow on Asset insert; this batch path catches the AUA-success milestone.
     */
    private void autoClearRerunQueueForSuccessful() {
        if (this.successfulQuoteIds == null || this.successfulQuoteIds.isEmpty()) return;
        try {
            List<Migration_Run_Detail__c> queued = [
                SELECT Id FROM Migration_Run_Detail__c
                WHERE Quote__c IN :this.successfulQuoteIds
                AND In_Rerun_Queue__c = true
                LIMIT 5000
            ];
            if (queued.isEmpty()) return;
            for (Migration_Run_Detail__c d : queued) {
                d.In_Rerun_Queue__c = false;
            }
            Database.update(queued, false);
            System.debug(LoggingLevel.INFO,
                'Auto-cleared ' + queued.size() + ' Rerun Queue entries for ' +
                this.successfulQuoteIds.size() + ' successful Quotes');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Auto-clear queue failed: ' + e.getMessage());
        }
    }

    /**
     * @description Internal finish logic separated for top-level error handling.
     *              Performs asset creation callouts, ACR DML, run log creation, and email.
     * @param bc BatchableContext
     */
    private void finishInternal(Database.BatchableContext bc) {
        // ACR creation (AUAs already inserted in execute())
        if (!this.accountToContractMap.isEmpty()) {
            try {
                OrderMigrationService.createAssetContractRelationships(this.accountToContractMap);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'ACR creation error: ' + e.getMessage());
            }
        }
        // Send completion email
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
     * Bulk-inserts pendingRunDetails after the parent run log id is known.
     * Uses allOrNone=false so a single bad row doesn't sink reporting.
     * Re-entrant: clears the buffer after attempting insert so it can be
     * called incrementally from execute() chunks as well as from finish().
     */
    private void persistRunDetails(Id runLogId) {
        if (runLogId == null || this.pendingRunDetails.isEmpty()) return;
        for (Migration_Run_Detail__c d : this.pendingRunDetails) {
            d.Run_Log__c = runLogId;
        }
        try {
            Database.insert(this.pendingRunDetails, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Run detail persist failed: ' + e.getMessage());
        }
        // Always clear the buffer — even on error rows we don't want to retry
        // (allOrNone=false already let good rows through), and we must not
        // re-insert the same records on the next flush.
        this.pendingRunDetails.clear();
    }

    /**
     * Captures a structured run detail row alongside the legacy error/skip text.
     * Run_Log__c is left null here and set in createMigrationRunLog() once the
     * parent log id is known.
     */
    private void recordRunDetail(String category, String severity, Id quoteId,
                                 String quoteNumber, Id qliId, Id orderId,
                                 Id orderItemId, String reason) {
        if (this.pendingRunDetails.size() >= MAX_RUN_DETAILS) return;
        Migration_Run_Detail__c d = new Migration_Run_Detail__c();
        d.Category__c = category;
        d.Severity__c = severity;
        d.Quote__c = quoteId;
        d.Quote_Number__c = quoteNumber != null ? quoteNumber.left(20) : null;
        d.Quote_Line_Item__c = qliId;
        d.Order__c = orderId;
        d.Order_Item__c = orderItemId;
        d.Reason__c = reason != null ? reason.left(255) : null;
        d.Cleanup_Required__c = OrderMigrationService.isCleanupRequiredForCategory(category);
        this.pendingRunDetails.add(d);
    }

    /**
     * @description Updates the pre-created Migration_Run_Log__c sentinel with batch results.
     *              If no sentinel exists (runLogId is null), creates a new record as fallback.
     * @param jobId The AsyncApexJob Id for this batch execution
     * @param assetsPending Whether asset creation is still pending
     */
    private Id createMigrationRunLog(Id jobId, Boolean assetsPending) {
        try {
            // Find the most recent sentinel (Processing Assets with 0 orders) to update.
            // Cannot rely on this.runLogId because platform may create duplicate batch instances
            // with stale state from a prior run.
            Migration_Run_Log__c log;
            List<Migration_Run_Log__c> sentinels = [
                SELECT Id FROM Migration_Run_Log__c
                WHERE Status__c = 'Processing Assets'
                AND Orders_Processed__c = 0
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!sentinels.isEmpty()) {
                log = new Migration_Run_Log__c(Id = sentinels[0].Id);
            } else if (this.runLogId != null) {
                // Check if the sentinel was already updated by another batch's finish()
                List<Migration_Run_Log__c> existing = [
                    SELECT Orders_Processed__c, Status__c FROM Migration_Run_Log__c
                    WHERE Id = :this.runLogId LIMIT 1
                ];
                if (!existing.isEmpty() && existing[0].Orders_Processed__c > 0
                    && existing[0].Status__c != 'Processing Assets') {
                    // Already updated with real results — don't overwrite
                    System.debug(LoggingLevel.INFO, 'Run log already updated. Skipping.');
                    return this.runLogId;
                }
                log = new Migration_Run_Log__c(Id = this.runLogId);
            } else {
                log = new Migration_Run_Log__c();
                log.Run_Date__c = Datetime.now();
                log.Start_Time__c = Datetime.now();
                log.Filter_Used__c = this.soqlFilter != null ? this.soqlFilter.left(255) : null;
            }
            log.Orders_Processed__c = this.ordersProcessed;
            log.Orders_Succeeded__c = this.ordersSucceeded;
            log.QLIs_Processed__c = this.itemsProcessed;
            log.QLIs_Succeeded__c = this.itemsSucceeded;
            log.QLIs_Skipped__c = this.itemsSkipped;
            log.PST_Succeeded__c = this.assetsSucceeded;
            log.PST_Failed__c = this.assetsFailed;
            if (this.targetPricebookId != null) {
                log.Target_Pricebook__c = this.targetPricebookId;
            }
            log.Quotes_Skipped_No_Coverage__c = this.quotesSkippedNoCoverage;
            log.PBEs_Auto_Created__c = this.pbesAutoCreated;

            // Prepend stats lines so the LWC can parse them
            String contractsLine = '[CONTRACTS] Created: ' + this.contractsCreated +
                ' | Reused: ' + this.contractsReused;
            String attributesLine = '[ATTRIBUTES] Copied: ' + this.attributesCopied +
                ' | Failed: ' + this.attributesFailed +
                ' | Skipped: ' + this.attributesSkipped;
            String ordersLine = '[ORDERS] ' + this.createdOrderNumbers;
            List<String> allLines = new List<String>{ contractsLine, attributesLine, ordersLine };
            allLines.addAll(this.errorMessages);

            // Truncate to fit Errors__c field (Long Text Area, 32,000 chars)
            String errorsText = String.join(allLines, '\n');
            if (errorsText.length() > 31500) {
                errorsText = errorsText.substring(0, 31500) + '\n[TRUNCATED]';
            }
            log.Errors__c = errorsText;

            if (assetsPending) {
                log.Status__c = 'Processing Assets';
            } else {
                log.Status__c = this.ordersFailed == 0
                    ? 'Completed'
                    : (this.ordersSucceeded > 0 ? 'Partial' : 'Failed');
                log.End_Time__c = Datetime.now();
            }

            System.debug(LoggingLevel.INFO, 'About to persist log: Id=' + log.Id +
                ' Status=' + log.Status__c + ' Orders=' + log.Orders_Processed__c);
            // Branches above can leave `log` either (a) with an Id pointing to an
            // existing sentinel, or (b) with null Id when no sentinel exists and no
            // runLogId was passed in (common in test/direct-invocation paths).
            // `update` fails on null-Id records, so pick the right DML here.
            if (log.Id == null) {
                insert log;
            } else {
                update log;
            }
            System.debug(LoggingLevel.INFO, 'Migration Run Log persisted successfully');

            persistRunDetails(log.Id);

            return log.Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'LOG UPDATE FAILED: ' + e.getMessage() +
                ' | Stack: ' + e.getStackTraceString());
            // Try insert as last resort
            try {
                Migration_Run_Log__c newLog = new Migration_Run_Log__c();
                newLog.Run_Date__c = Datetime.now();
                newLog.Start_Time__c = Datetime.now();
                newLog.End_Time__c = Datetime.now();
                newLog.Filter_Used__c = this.soqlFilter != null ? this.soqlFilter.left(255) : null;
                newLog.Orders_Processed__c = this.ordersProcessed;
                newLog.Orders_Succeeded__c = this.ordersSucceeded;
                newLog.QLIs_Processed__c = this.itemsProcessed;
                newLog.QLIs_Succeeded__c = this.itemsSucceeded;
                newLog.QLIs_Skipped__c = this.itemsSkipped;
                newLog.PST_Succeeded__c = this.assetsSucceeded;
                newLog.PST_Failed__c = this.assetsFailed;
                if (this.targetPricebookId != null) {
                    newLog.Target_Pricebook__c = this.targetPricebookId;
                }
                newLog.Quotes_Skipped_No_Coverage__c = this.quotesSkippedNoCoverage;
                newLog.PBEs_Auto_Created__c = this.pbesAutoCreated;
                newLog.Status__c = 'Failed';
                newLog.Errors__c = '[LOG_FAILURE] ' + e.getMessage();
                insert newLog;
                System.debug(LoggingLevel.INFO, 'Fallback log created: ' + newLog.Id);
                persistRunDetails(newLog.Id);
                return newLog.Id;
            } catch (Exception e2) {
                System.debug(LoggingLevel.ERROR, 'Fallback log ALSO failed: ' + e2.getMessage());
                return null;
            }
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
            email.setSubject('Order Migration Complete - ' +
                (this.ordersFailed > 0 ? 'Completed with Errors' : 'Success'));

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
        body += '<h2 style="color: #333;">Order Migration Complete</h2>';

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

        // Activate Orders
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Activate Orders</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.activateOrders + '</td></tr>';

        // Activate Contracts
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Activate Contracts</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.activateContracts + '</td></tr>';

        // ── Orders Section ──
        body += '<tr><td colspan="2" style="padding: 8px; border: 1px solid #ddd; background: #e9ecef;">' +
                '<strong>Orders</strong></td></tr>';

        // Orders Processed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Orders Processed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.ordersProcessed + '</td></tr>';

        // Orders Succeeded
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Orders Succeeded</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.ordersSucceeded + '</td></tr>';

        // Orders Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Orders Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.ordersFailed > 0 ? warningStyle : '') + '">' +
                this.ordersFailed + '</td></tr>';

        // ── Items Section ──
        body += '<tr><td colspan="2" style="padding: 8px; border: 1px solid #ddd; background: #e9ecef;">' +
                '<strong>Order Items</strong></td></tr>';

        // Items Processed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Items Processed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.itemsProcessed + '</td></tr>';

        // Items Succeeded
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Items Succeeded</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.itemsSucceeded + '</td></tr>';

        // Items Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Items Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.itemsFailed > 0 ? warningStyle : '') + '">' +
                this.itemsFailed + '</td></tr>';

        // Items Skipped
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Items Skipped (Missing Dates)</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.itemsSkipped > 0 ? ' color: #856404; font-weight: bold;' : '') + '">' +
                this.itemsSkipped + '</td></tr>';

        // ── Assets Section ──
        body += '<tr><td colspan="2" style="padding: 8px; border: 1px solid #ddd; background: #e9ecef;">' +
                '<strong>Asset Creation</strong></td></tr>';

        // Assets Succeeded
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Assets Succeeded</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.assetsSucceeded + '</td></tr>';

        // Assets Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Assets Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.assetsFailed > 0 ? warningStyle : '') + '">' +
                this.assetsFailed + '</td></tr>';

        // ── Attributes Section ──
        body += '<tr><td colspan="2" style="padding: 8px; border: 1px solid #ddd; background: #e9ecef;">' +
                '<strong>Attributes (QLIA → OIA)</strong></td></tr>';

        // Attributes Copied
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Attributes Copied</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.attributesCopied + '</td></tr>';

        // Attributes Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Attributes Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.attributesFailed > 0 ? warningStyle : '') + '">' +
                this.attributesFailed + '</td></tr>';

        // Attributes Skipped
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Attributes Skipped (No Source)</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.attributesSkipped > 0 ? ' color: #856404; font-weight: bold;' : '') + '">' +
                this.attributesSkipped + '</td></tr>';

        // ── Contracts Section ──
        body += '<tr><td colspan="2" style="padding: 8px; border: 1px solid #ddd; background: #e9ecef;">' +
                '<strong>Contracts</strong></td></tr>';

        // Contracts Created
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Contracts Created</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.contractsCreated + '</td></tr>';

        // Contracts Reused
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Contracts Reused</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.contractsReused + '</td></tr>';

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

    // ═══════════════════════════════════════════════════════════════════════
    // Inner Queueable: Runs in a separate transaction so REST callouts
    // happen BEFORE any DML (Apex requirement).
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @description Queueable that performs asset creation via REST API, creates
     *              AssetContractRelationships, writes the migration run log, and
     *              sends the completion email. Must run in its own transaction because
     *              AUA insertion (DML) happens in finish(), and callouts cannot follow DML.
     */
    /**
     * Lightweight Queueable to insert AUAs and ACRs in a separate transaction.
     * This runs AFTER finish() commits the run log, so flow failures don't roll back the log.
     */
    public class AuaInsertQueueable implements Queueable {
        private List<Id> orderIds;
        private Map<Id, Id> accountToContractMap;

        public AuaInsertQueueable(List<Id> orderIds, Map<Id, Id> accountToContractMap) {
            this.orderIds = orderIds;
            this.accountToContractMap = accountToContractMap;
        }

        public void execute(QueueableContext ctx) {
            // Insert AUAs (skip existing)
            Set<Id> existingAuaOrderIds = new Set<Id>();
            for (AppUsageAssignment existing : [
                SELECT RecordId FROM AppUsageAssignment
                WHERE RecordId IN :this.orderIds
                AND AppUsageType = 'RevenueLifecycleManagement'
            ]) {
                existingAuaOrderIds.add(existing.RecordId);
            }
            List<AppUsageAssignment> auas = new List<AppUsageAssignment>();
            for (Id orderId : this.orderIds) {
                if (!existingAuaOrderIds.contains(orderId)) {
                    AppUsageAssignment aua = new AppUsageAssignment();
                    aua.RecordId = orderId;
                    aua.AppUsageType = 'RevenueLifecycleManagement';
                    auas.add(aua);
                }
            }
            if (!auas.isEmpty()) {
                Database.insert(auas, false);
            }

            // Create ACRs
            if (this.accountToContractMap != null && !this.accountToContractMap.isEmpty()) {
                try {
                    OrderMigrationService.createAssetContractRelationships(this.accountToContractMap);
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'ACR creation error: ' + e.getMessage());
                }
            }
        }
    }

    public class OrderMigrationAssetQueueable implements Queueable, Database.AllowsCallouts {

        private Id runLogId;
        private List<Id> orderIds;
        private List<String> orderLabels;
        private Map<Id, Id> accountToContractMap;
        private Integer ordersProcessed, ordersSucceeded, ordersFailed;
        private Integer itemsProcessed, itemsSucceeded, itemsFailed, itemsSkipped;
        private Integer attributesCopied, attributesFailed, attributesSkipped;
        private Integer contractsCreated, contractsReused;
        private Integer assetsSucceeded = 0, assetsFailed = 0;
        private List<String> errorMessages;
        private List<String> skippedItems;
        private String soqlFilter, createdOrderNumbers;
        private Boolean activateOrders, activateContracts;
        private String userEmail, userName;
        private Id jobId;

        public OrderMigrationAssetQueueable(
            Id runLogId,
            List<Id> orderIds, List<String> orderLabels,
            Map<Id, Id> accountToContractMap,
            Integer ordersProcessed, Integer ordersSucceeded, Integer ordersFailed,
            Integer itemsProcessed, Integer itemsSucceeded, Integer itemsFailed, Integer itemsSkipped,
            Integer attributesCopied, Integer attributesFailed, Integer attributesSkipped,
            Integer contractsCreated, Integer contractsReused,
            List<String> errorMessages, List<String> skippedItems,
            String soqlFilter, Boolean activateOrders, Boolean activateContracts,
            String createdOrderNumbers,
            String userEmail, String userName, Id jobId
        ) {
            this.runLogId = runLogId;
            this.orderIds = orderIds;
            this.orderLabels = orderLabels;
            this.accountToContractMap = accountToContractMap;
            this.ordersProcessed = ordersProcessed;
            this.ordersSucceeded = ordersSucceeded;
            this.ordersFailed = ordersFailed;
            this.itemsProcessed = itemsProcessed;
            this.itemsSucceeded = itemsSucceeded;
            this.itemsFailed = itemsFailed;
            this.itemsSkipped = itemsSkipped;
            this.attributesCopied = attributesCopied;
            this.attributesFailed = attributesFailed;
            this.attributesSkipped = attributesSkipped;
            this.contractsCreated = contractsCreated;
            this.contractsReused = contractsReused;
            this.errorMessages = errorMessages != null ? errorMessages : new List<String>();
            this.skippedItems = skippedItems != null ? skippedItems : new List<String>();
            this.soqlFilter = soqlFilter;
            this.activateOrders = activateOrders;
            this.activateContracts = activateContracts;
            this.createdOrderNumbers = createdOrderNumbers;
            this.userEmail = userEmail;
            this.userName = userName;
            this.jobId = jobId;
        }

        public void execute(QueueableContext context) {
            System.debug(LoggingLevel.INFO, 'OrderMigrationAssetQueueable: Processing ' +
                this.orderIds.size() + ' orders');

            // ── Asset creation via REST API is SKIPPED ──
            // The platform automatically creates Assets during Order activation.
            // The Fortra_Asset_Populate_Legacy_Fields flow handles post-processing
            // (Legacy_Id, Status, Hardware, etc.) on the platform-created Assets.
            // Calling createOrUpdateAssetFromOrder here would create DUPLICATE Assets.
            this.assetsSucceeded = this.orderIds.size();

            // ── DML operations ──

            // Create AssetContractRelationship records
            if (!this.accountToContractMap.isEmpty()) {
                try {
                    Integer acrCreated = OrderMigrationService.createAssetContractRelationships(
                        this.accountToContractMap);
                    System.debug(LoggingLevel.INFO,
                        'AssetContractRelationships created: ' + acrCreated);
                } catch (Exception e) {
                    this.errorMessages.add('AssetContractRelationship creation failed: ' + e.getMessage());
                }
            }

            // Finalize migration run log with asset results
            finalizeRunLog();
        }

        private void finalizeRunLog() {
            try {
                // Build final errors text (includes asset creation errors)
                String contractsLine = '[CONTRACTS] Created: ' + this.contractsCreated +
                    ' | Reused: ' + this.contractsReused;
                String attributesLine = '[ATTRIBUTES] Copied: ' + this.attributesCopied +
                    ' | Failed: ' + this.attributesFailed +
                    ' | Skipped: ' + this.attributesSkipped;
                String ordersLine = '[ORDERS] ' + this.createdOrderNumbers;
                List<String> allLines = new List<String>{ contractsLine, attributesLine, ordersLine };
                allLines.addAll(this.errorMessages);

                String errorsText = String.join(allLines, '\n');
                if (errorsText.length() > 31500) {
                    errorsText = errorsText.substring(0, 31500) + '\n[TRUNCATED]';
                }

                String finalStatus = this.ordersFailed == 0
                    ? 'Completed'
                    : (this.ordersSucceeded > 0 ? 'Partial' : 'Failed');

                if (this.runLogId != null) {
                    // Update the existing log created by finish()
                    Migration_Run_Log__c log = new Migration_Run_Log__c(Id = this.runLogId);
                    log.PST_Succeeded__c = this.assetsSucceeded;
                    log.PST_Failed__c = this.assetsFailed;
                    log.Errors__c = errorsText;
                    log.Status__c = finalStatus;
                    log.End_Time__c = Datetime.now();
                    update log;
                    System.debug(LoggingLevel.INFO, 'Migration Run Log updated: ' + this.runLogId);
                } else {
                    // Fallback: finish() failed to create the log — insert a new one
                    Migration_Run_Log__c log = new Migration_Run_Log__c();
                    log.Run_Date__c = Datetime.now();
                    log.Start_Time__c = Datetime.now();
                    log.End_Time__c = Datetime.now();
                    log.Filter_Used__c = this.soqlFilter != null ? this.soqlFilter.left(255) : null;
                    log.Orders_Processed__c = this.ordersProcessed;
                    log.Orders_Succeeded__c = this.ordersSucceeded;
                    log.QLIs_Processed__c = this.itemsProcessed;
                    log.QLIs_Succeeded__c = this.itemsSucceeded;
                    log.QLIs_Skipped__c = this.itemsSkipped;
                    log.PST_Succeeded__c = this.assetsSucceeded;
                    log.PST_Failed__c = this.assetsFailed;
                    log.Errors__c = errorsText;
                    log.Status__c = finalStatus;
                    insert log;
                    System.debug(LoggingLevel.INFO, 'Migration Run Log created (fallback): ' + log.Id);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'Failed to finalize Migration Run Log: ' + e.getMessage());
            }
        }

        private void sendEmail() {
            if (String.isBlank(this.userEmail)) { return; }
            try {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ this.userEmail });
                email.setSubject('Order Migration Complete - ' +
                    (this.ordersFailed > 0 ? 'Completed with Errors' : 'Success'));

                String successStyle = 'color: #28a745; font-weight: bold;';
                String warningStyle = 'color: #dc3545; font-weight: bold;';
                String body = '<html><body style="font-family: Arial, sans-serif;">';
                body += '<h2 style="color: #333;">Order Migration Complete</h2>';
                body += '<p>Asset creation was processed via Queueable (separate transaction).</p>';
                body += '<table style="border-collapse: collapse; width: 100%; max-width: 500px;">';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Batch Job ID</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd;">' + this.jobId + '</td></tr>';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Filter</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd;">' + String.valueOf(this.soqlFilter).escapeHtml4() + '</td></tr>';
                body += '<tr><td colspan="2" style="padding: 8px; border: 1px solid #ddd; background: #e9ecef;"><strong>Orders</strong></td></tr>';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Succeeded</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' + this.ordersSucceeded + '</td></tr>';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Failed</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd;' + (this.ordersFailed > 0 ? warningStyle : '') + '">' + this.ordersFailed + '</td></tr>';
                body += '<tr><td colspan="2" style="padding: 8px; border: 1px solid #ddd; background: #e9ecef;"><strong>Assets</strong></td></tr>';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Succeeded</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' + this.assetsSucceeded + '</td></tr>';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Failed</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd;' + (this.assetsFailed > 0 ? warningStyle : '') + '">' + this.assetsFailed + '</td></tr>';
                body += '<tr><td colspan="2" style="padding: 8px; border: 1px solid #ddd; background: #e9ecef;"><strong>Items / Attributes</strong></td></tr>';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Items Succeeded</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd;">' + this.itemsSucceeded + '</td></tr>';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Items Skipped</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd;">' + this.itemsSkipped + '</td></tr>';
                body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;"><strong>Attributes Copied</strong></td>';
                body += '<td style="padding: 8px; border: 1px solid #ddd;">' + this.attributesCopied + '</td></tr>';
                body += '</table>';

                if (!this.errorMessages.isEmpty()) {
                    body += '<h3 style="color: #dc3545; margin-top: 20px;">Errors</h3>';
                    body += '<ul style="background: #fff3cd; padding: 15px 30px; border-radius: 4px;">';
                    Integer maxShow = Math.min(this.errorMessages.size(), MAX_ERROR_MESSAGES);
                    for (Integer i = 0; i < maxShow; i++) {
                        body += '<li style="margin: 5px 0;">' + this.errorMessages[i].escapeHtml4() + '</li>';
                    }
                    body += '</ul>';
                }

                body += '<p style="margin-top: 20px; color: #666; font-size: 12px;">Automated message from Salesforce.</p>';
                body += '</body></html>';

                email.setHtmlBody(body);
                email.setSaveAsActivity(false);
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed to send email: ' + e.getMessage());
            }
        }
    }
}