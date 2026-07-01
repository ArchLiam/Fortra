/**
 * @description Batch Apex class for bulk multi-currency price updates.
 *              Processes products filtered by Solution Category and creates/updates
 *              PricebookEntries for all active currencies defined in Currency_Conversion_Formula__mdt.
 *
 *              Process Flow:
 *              1. Query products by Solution Category with their existing PricebookEntries
 *              2. Find USD price from Standard Pricebook for each product
 *              3. Calculate converted prices for each currency using Fortra_CurrencyConversionService
 *              4. Create/Update PricebookEntries for each pricebook + currency combination
 *              5. Send email summary on completion
 *
 *              Revenue Cloud Consideration:
 *              - Products may have multiple ProductSellingModels (e.g., "One Time", "Term Based")
 *              - Each selling model has its own set of PricebookEntries
 *              - PBE uniqueness: Product + Pricebook + Currency + SellingModel
 *              - Standard PBEs must be committed before Custom PBEs (separate DML)
 *
 *              Governor Limits Consideration:
 *              - Batch size 50 products
 *              - Each product may have ~2 selling models x 6 pricebooks x 5 currencies = 60 PBEs
 *              - 50 products x 60 PBEs = 3,000 DML rows (within 10,000 limit)
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-01
 */
public class Fortra_BulkPriceUpdateBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Input parameters — exactly one of solutionCategories or productIds must be set
    private Set<String> solutionCategories;
    private Set<Id> productIds;
    private Set<Id> selectedPricebookIds;
    private String initiatedByUserId;
    private String initiatedByUserEmail;
    private String initiatedByUserName;

    // Derived in start(): true when standardPricebookId is present in selectedPricebookIds
    private Boolean standardSelected = false;

    // Stateful tracking for finish() email
    private Integer totalProductsProcessed = 0;
    private Integer totalProductsSucceeded = 0;
    private Integer totalProductsFailed = 0;
    private Integer totalPBEsCreated = 0;
    private Integer totalPBEsUpdated = 0;
    private Integer totalPBEsFailed = 0;
    private List<String> errorMessages = new List<String>();
    private static final Integer MAX_ERROR_MESSAGES = 100;

    // Cached data loaded once in start()
    private Map<Id, Pricebook2> activePricebooks;
    private Map<String, Currency_Conversion_Formula__mdt> currencyFormulas;
    private Id standardPricebookId;

    /**
     * @description Constructor
     * @param solutionCategories Set of Solution Category values to filter products
     * @param selectedPricebookIds Set of Pricebook2 IDs to update; must be non-empty
     * @param initiatedByUserId ID of user who initiated the batch
     */
    public Fortra_BulkPriceUpdateBatch(
        Set<String> solutionCategories,
        Set<Id> selectedPricebookIds,
        Id initiatedByUserId
    ) {
        if (selectedPricebookIds == null || selectedPricebookIds.isEmpty()) {
            throw new IllegalArgumentException('At least one Pricebook is required');
        }
        if (solutionCategories == null || solutionCategories.isEmpty()) {
            throw new IllegalArgumentException('At least one Solution Category is required');
        }
        this.solutionCategories = solutionCategories;
        this.selectedPricebookIds = new Set<Id>(selectedPricebookIds);
        initInitiator(initiatedByUserId);
    }

    /**
     * @description Constructor for explicit product scope (no Solution Category filter/update).
     * @param productIds Product2 IDs to process
     * @param selectedPricebookIds Set of Pricebook2 IDs to update; must be non-empty
     * @param initiatedByUserId ID of user who initiated the batch
     */
    public Fortra_BulkPriceUpdateBatch(
        Set<Id> productIds,
        Set<Id> selectedPricebookIds,
        Id initiatedByUserId
    ) {
        if (selectedPricebookIds == null || selectedPricebookIds.isEmpty()) {
            throw new IllegalArgumentException('At least one Pricebook is required');
        }
        if (productIds == null || productIds.isEmpty()) {
            throw new IllegalArgumentException('At least one Product Id is required');
        }
        this.productIds = new Set<Id>(productIds);
        this.selectedPricebookIds = new Set<Id>(selectedPricebookIds);
        initInitiator(initiatedByUserId);
    }

    private void initInitiator(Id initiatedByUserId) {
        if (initiatedByUserId != null) {
            List<User> users = [SELECT Id, Email, Name FROM User WHERE Id = :initiatedByUserId LIMIT 1];
            if (!users.isEmpty()) {
                this.initiatedByUserId = users[0].Id;
                this.initiatedByUserEmail = users[0].Email;
                this.initiatedByUserName = users[0].Name;
            }
        }
    }

    /**
     * @description Start method - queries products filtered by Solution Category
     * @param bc BatchableContext
     * @return QueryLocator for products to process
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'Fortra_BulkPriceUpdateBatch: Starting');
        if (this.productIds != null) {
            System.debug(LoggingLevel.INFO, 'Product Id scope: ' + this.productIds.size() + ' product(s)');
        } else {
            System.debug(LoggingLevel.INFO, 'Solution Categories: ' + this.solutionCategories);
        }
        System.debug(LoggingLevel.INFO, '========================================');

        // Load currency formulas (cached in service)
        this.currencyFormulas = Fortra_CurrencyConversionService.getActiveFormulas();
        System.debug(LoggingLevel.INFO, 'Loaded ' + this.currencyFormulas.size() + ' currency formulas');

        // Always discover the Standard Pricebook ID — getUSDStandardPBEs() reads from it
        // even when the user excludes Standard from the selection. Use a dedicated query
        // because the selection filter below could otherwise hide it.
        for (Pricebook2 sp : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1]) {
            this.standardPricebookId = sp.Id;
        }

        // Load only the user-selected active pricebooks for WRITES
        this.activePricebooks = new Map<Id, Pricebook2>();
        for (Pricebook2 pb : [
            SELECT Id, Name, IsStandard, IsActive
            FROM Pricebook2
            WHERE IsActive = true
            AND Id IN :this.selectedPricebookIds
        ]) {
            this.activePricebooks.put(pb.Id, pb);
        }
        this.standardSelected = this.standardPricebookId != null
            && this.activePricebooks.containsKey(this.standardPricebookId);

        System.debug(LoggingLevel.INFO, 'Loaded ' + this.activePricebooks.size() + ' selected active pricebooks');
        System.debug(LoggingLevel.INFO, 'Standard Pricebook ID: ' + this.standardPricebookId
            + ' (selected: ' + this.standardSelected + ')');

        // Query products with their existing PricebookEntries (including ProductSellingModelId
        // for Revenue Cloud compatibility)
        if (this.productIds != null) {
            return Database.getQueryLocator([
                SELECT Id, Name, ProductCode, Solution_Category__c, IsActive,
                       (SELECT Id, Pricebook2Id, Pricebook2.Name, Pricebook2.IsStandard,
                               UnitPrice, CurrencyIsoCode, IsActive, ProductSellingModelId
                        FROM PricebookEntries
                        WHERE IsActive = true)
                FROM Product2
                WHERE Id IN :this.productIds
                AND IsActive = true
                ORDER BY Name
            ]);
        }

        return Database.getQueryLocator([
            SELECT Id, Name, ProductCode, Solution_Category__c, IsActive,
                   (SELECT Id, Pricebook2Id, Pricebook2.Name, Pricebook2.IsStandard,
                           UnitPrice, CurrencyIsoCode, IsActive, ProductSellingModelId
                    FROM PricebookEntries
                    WHERE IsActive = true)
            FROM Product2
            WHERE Solution_Category__c IN :this.solutionCategories
            AND IsActive = true
            ORDER BY Name
        ]);
    }

    /**
     * @description Execute method - processes a batch of products
     * @param bc BatchableContext
     * @param products List of Product2 records to process
     */
    public void execute(Database.BatchableContext bc, List<Product2> products) {
        System.debug(LoggingLevel.INFO, 'Processing batch of ' + products.size() + ' products');

        // Build map of existing PBEs by Product + Pricebook + Currency + SellingModel
        // Key format: ProductId-PricebookId-CurrencyCode-SellingModelId
        Map<String, PricebookEntry> existingPBEMap = buildExistingPBEMap(products);

        // Collect PBEs separately: Standard PBEs must be committed before Custom PBEs
        // because Salesforce requires a Standard PBE to exist for a Product + Currency +
        // SellingModel before a Custom PBE can be created for that same combination.
        List<PricebookEntry> standardPBEsToUpsert = new List<PricebookEntry>();
        List<PricebookEntry> customPBEsToUpsert = new List<PricebookEntry>();

        for (Product2 product : products) {
            this.totalProductsProcessed++;

            try {
                // Get all USD Standard PBEs (one per selling model)
                List<PricebookEntry> usdStandardPBEs = getUSDStandardPBEs(product);

                if (usdStandardPBEs.isEmpty()) {
                    addErrorMessage('Product "' + product.Name + '" (' + product.ProductCode +
                        '): No USD price found in Standard Pricebook');
                    this.totalProductsFailed++;
                    continue;
                }

                // Process each selling model independently
                for (PricebookEntry usdPBE : usdStandardPBEs) {
                    Decimal usdPrice = usdPBE.UnitPrice;
                    Id sellingModelId = usdPBE.ProductSellingModelId;

                    System.debug(LoggingLevel.INFO, 'Product: ' + product.Name +
                        ' | USD Price: ' + usdPrice +
                        ' | SellingModel: ' + sellingModelId);

                    // Phase 1: Standard PBEs for non-USD currencies (with same selling model)
                    // Only run when the Standard Pricebook is part of the user's selection.
                    // If excluded, preview already verified Standard PBEs exist for source-of-truth reads.
                    if (this.standardSelected) {
                        for (String currencyCode : this.currencyFormulas.keySet()) {
                            if (currencyCode == 'USD') {
                                continue; // USD Standard PBE already exists with selling model
                            }

                            String pbeKey = buildPBEKey(product.Id, this.standardPricebookId, currencyCode, sellingModelId);
                            PricebookEntry existingPBE = existingPBEMap.get(pbeKey);

                            Decimal convertedPrice = Fortra_CurrencyConversionService.convertPrice(
                                usdPrice, currencyCode);

                            if (convertedPrice == null) {
                                addErrorMessage('Product "' + product.Name + '": Failed to convert price to ' +
                                    currencyCode);
                                continue;
                            }

                            PricebookEntry pbe = createPricebookEntry(
                                product.Id, this.standardPricebookId, currencyCode, convertedPrice,
                                existingPBE, sellingModelId);

                            if (pbe != null) {
                                standardPBEsToUpsert.add(pbe);
                                existingPBEMap.put(pbeKey, pbe);
                            }
                        }
                    }

                    // Phase 2: Custom PBEs for ALL currencies (with same selling model)
                    for (Pricebook2 pricebook : this.activePricebooks.values()) {
                        if (pricebook.IsStandard) {
                            continue;
                        }

                        for (String currencyCode : this.currencyFormulas.keySet()) {
                            String pbeKey = buildPBEKey(product.Id, pricebook.Id, currencyCode, sellingModelId);
                            PricebookEntry existingPBE = existingPBEMap.get(pbeKey);

                            Decimal convertedPrice;
                            if (currencyCode == 'USD') {
                                convertedPrice = usdPrice;
                            } else {
                                convertedPrice = Fortra_CurrencyConversionService.convertPrice(
                                    usdPrice, currencyCode);
                            }

                            if (convertedPrice == null) {
                                continue;
                            }

                            PricebookEntry pbe = createPricebookEntry(
                                product.Id, pricebook.Id, currencyCode, convertedPrice,
                                existingPBE, sellingModelId);

                            if (pbe != null) {
                                customPBEsToUpsert.add(pbe);
                                existingPBEMap.put(pbeKey, pbe);
                            }
                        }
                    }
                }

                this.totalProductsSucceeded++;

            } catch (Exception e) {
                this.totalProductsFailed++;
                addErrorMessage('Product "' + product.Name + '": ' + e.getMessage());
            }
        }

        // Upsert Standard PBEs first - they must be committed before Custom PBEs
        if (!standardPBEsToUpsert.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'Upserting ' + standardPBEsToUpsert.size() + ' Standard PricebookEntries');
            upsertPricebookEntries(standardPBEsToUpsert);
        }

        // Then upsert Custom PBEs (Standard PBEs now exist in the database)
        if (!customPBEsToUpsert.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'Upserting ' + customPBEsToUpsert.size() + ' Custom PricebookEntries');
            upsertPricebookEntries(customPBEsToUpsert);
        }
    }

    /**
     * @description Finish method - sends email notification with results
     * @param bc BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'Fortra_BulkPriceUpdateBatch: Complete');
        System.debug(LoggingLevel.INFO, 'Products Processed: ' + this.totalProductsProcessed);
        System.debug(LoggingLevel.INFO, 'Products Succeeded: ' + this.totalProductsSucceeded);
        System.debug(LoggingLevel.INFO, 'Products Failed: ' + this.totalProductsFailed);
        System.debug(LoggingLevel.INFO, 'PBEs Created: ' + this.totalPBEsCreated);
        System.debug(LoggingLevel.INFO, 'PBEs Updated: ' + this.totalPBEsUpdated);
        System.debug(LoggingLevel.INFO, 'PBEs Failed: ' + this.totalPBEsFailed);
        System.debug(LoggingLevel.INFO, '========================================');

        // Send email notification
        sendCompletionEmail(bc.getJobId());
    }

    /**
     * @description Build a map of existing PricebookEntries for quick lookup
     * @param products List of products with their PricebookEntries
     * @return Map keyed by ProductId-PricebookId-CurrencyCode-SellingModelId
     */
    private Map<String, PricebookEntry> buildExistingPBEMap(List<Product2> products) {
        Map<String, PricebookEntry> pbeMap = new Map<String, PricebookEntry>();

        for (Product2 product : products) {
            if (product.PricebookEntries != null) {
                for (PricebookEntry pbe : product.PricebookEntries) {
                    String key = buildPBEKey(product.Id, pbe.Pricebook2Id,
                        pbe.CurrencyIsoCode, pbe.ProductSellingModelId);
                    pbeMap.put(key, pbe);
                }
            }
        }

        return pbeMap;
    }

    /**
     * @description Build a unique key for PBE lookup (includes SellingModel for Revenue Cloud)
     * @param productId Product2 ID
     * @param pricebookId Pricebook2 ID
     * @param currencyCode Currency ISO code
     * @param sellingModelId ProductSellingModel ID (may be null)
     * @return Composite key string
     */
    private String buildPBEKey(Id productId, Id pricebookId, String currencyCode, Id sellingModelId) {
        return productId + '-' + pricebookId + '-' + currencyCode + '-' + sellingModelId;
    }

    /**
     * @description Get all USD Standard Pricebook entries for a product (one per selling model)
     * @param product Product2 with PricebookEntries
     * @return List of USD Standard PBEs (empty if none found)
     */
    private List<PricebookEntry> getUSDStandardPBEs(Product2 product) {
        List<PricebookEntry> usdPBEs = new List<PricebookEntry>();

        if (product.PricebookEntries == null) {
            return usdPBEs;
        }

        for (PricebookEntry pbe : product.PricebookEntries) {
            if (pbe.Pricebook2.IsStandard && pbe.CurrencyIsoCode == 'USD') {
                usdPBEs.add(pbe);
            }
        }

        return usdPBEs;
    }

    /**
     * @description Create or prepare update for a PricebookEntry (Revenue Cloud aware)
     * @param productId Product2 ID
     * @param pricebookId Pricebook2 ID
     * @param currencyCode Currency ISO code
     * @param unitPrice Calculated unit price
     * @param existingPBE Existing PBE to update (or null for new)
     * @param sellingModelId ProductSellingModel ID to associate (may be null)
     * @return PricebookEntry to upsert
     */
    private PricebookEntry createPricebookEntry(
        Id productId,
        Id pricebookId,
        String currencyCode,
        Decimal unitPrice,
        PricebookEntry existingPBE,
        Id sellingModelId
    ) {
        PricebookEntry pbe;

        if (existingPBE != null) {
            // Update existing - only if price has changed
            if (existingPBE.UnitPrice != unitPrice) {
                pbe = new PricebookEntry(
                    Id = existingPBE.Id,
                    UnitPrice = unitPrice,
                    IsActive = true
                );
            }
        } else {
            // Create new (with ProductSellingModelId for Revenue Cloud)
            pbe = new PricebookEntry(
                Product2Id = productId,
                Pricebook2Id = pricebookId,
                CurrencyIsoCode = currencyCode,
                UnitPrice = unitPrice,
                IsActive = true
            );
            // Set selling model if available (Revenue Cloud)
            if (sellingModelId != null) {
                pbe.ProductSellingModelId = sellingModelId;
            }
        }

        return pbe;
    }

    /**
     * @description Upsert PricebookEntries with partial success handling
     * @param pbesToUpsert List of PricebookEntries to upsert
     */
    private void upsertPricebookEntries(List<PricebookEntry> pbesToUpsert) {
        System.debug(LoggingLevel.INFO, 'Upserting ' + pbesToUpsert.size() + ' PricebookEntries');

        // Separate into inserts and updates
        List<PricebookEntry> toInsert = new List<PricebookEntry>();
        List<PricebookEntry> toUpdate = new List<PricebookEntry>();

        for (PricebookEntry pbe : pbesToUpsert) {
            if (pbe.Id != null) {
                toUpdate.add(pbe);
            } else {
                toInsert.add(pbe);
            }
        }

        // Process inserts
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(toInsert, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (insertResults[i].isSuccess()) {
                    this.totalPBEsCreated++;
                } else {
                    this.totalPBEsFailed++;
                    for (Database.Error err : insertResults[i].getErrors()) {
                        addErrorMessage('PBE Insert Error: ' + err.getMessage());
                    }
                }
            }
        }

        // Process updates
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(toUpdate, false);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (updateResults[i].isSuccess()) {
                    this.totalPBEsUpdated++;
                } else {
                    this.totalPBEsFailed++;
                    for (Database.Error err : updateResults[i].getErrors()) {
                        addErrorMessage('PBE Update Error: ' + err.getMessage());
                    }
                }
            }
        }
    }

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
            email.setSubject('Bulk Price Update Complete - ' +
                (this.totalProductsFailed > 0 ? 'Completed with Errors' : 'Success'));

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
        body += '<h2 style="color: #333;">Bulk Multi-Currency Price Update Complete</h2>';

        // Summary table
        body += '<table style="border-collapse: collapse; width: 100%; max-width: 500px;">';

        // Job ID
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Batch Job ID</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' + jobId + '</td></tr>';

        // Scope
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Product Scope</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                (this.productIds != null
                    ? this.productIds.size() + ' explicit product(s) (no Solution Category filter)'
                    : String.join(new List<String>(this.solutionCategories), ', ')) +
                '</td></tr>';

        // Pricebooks Updated
        List<String> pricebookLabels = new List<String>();
        if (this.activePricebooks != null) {
            for (Pricebook2 pb : this.activePricebooks.values()) {
                pricebookLabels.add(pb.Name + (pb.IsStandard ? ' (Standard)' : ''));
            }
            pricebookLabels.sort();
        }
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Pricebooks Updated</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                (pricebookLabels.isEmpty() ? '(none)' : String.join(pricebookLabels, ', ')) +
                '</td></tr>';

        // Products Processed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Products Processed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.totalProductsProcessed + '</td></tr>';

        // Products Succeeded
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Products Succeeded</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd; ' + successStyle + '">' +
                this.totalProductsSucceeded + '</td></tr>';

        // Products Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Products Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.totalProductsFailed > 0 ? warningStyle : '') + '">' +
                this.totalProductsFailed + '</td></tr>';

        // PBEs Created
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Price Book Entries Created</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.totalPBEsCreated + '</td></tr>';

        // PBEs Updated
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Price Book Entries Updated</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;">' +
                this.totalPBEsUpdated + '</td></tr>';

        // PBEs Failed
        body += '<tr><td style="padding: 8px; border: 1px solid #ddd; background: #f8f9fa;">' +
                '<strong>Price Book Entries Failed</strong></td>';
        body += '<td style="padding: 8px; border: 1px solid #ddd;' +
                (this.totalPBEsFailed > 0 ? warningStyle : '') + '">' +
                this.totalPBEsFailed + '</td></tr>';

        body += '</table>';

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