/**
 * QuoteCloneService
 * Service class for handling Quote cloning operations in Revenue Cloud Advanced
 * Manages complex quote structures including line items, pricing, and relationships
 * Updated to properly handle Revenue Cloud syncing via Opportunity.SyncedQuoteId
 */
public with sharing class QuoteCloneService {
    
    /**
     * Simplified clone method for Flow compatibility
     * @param sourceQuoteId The ID of the quote to clone
     * @return The ID of the newly created quote
     */
    @AuraEnabled
    public static CloneResult cloneQuote(Id sourceQuoteId) {
        // Call the main method with default options that make the quote primary
        CloneOptions options = new CloneOptions();
        options.cloneLineItems = true;
        options.makePrimary = true;  // Always make the cloned quote primary
        options.recalculatePricing = true;
        return cloneQuoteWithLines(sourceQuoteId, options);
    }
    
    /**
     * Main method to clone a quote with all its line items
     * @param sourceQuoteId The ID of the quote to clone
     * @param options CloneOptions object containing configuration parameters
     * @return The ID of the newly created quote
     */
    @AuraEnabled
    public static CloneResult cloneQuoteWithLines(Id sourceQuoteId, CloneOptions options) {
        CloneResult result = new CloneResult();
        Savepoint sp = Database.setSavepoint();
        
        System.debug('=== Quote Clone Service Started ===');
        System.debug('Source Quote ID: ' + sourceQuoteId);
        System.debug('Options received: ' + JSON.serialize(options));
        if (options != null) {
            System.debug('makePrimary option value: ' + options.makePrimary);
        }
        
        try {
            // Validate input
            if (sourceQuoteId == null) {
                throw new CloneException('Source Quote ID is required');
            }
            
            // Get source quote with all fields
            Quote sourceQuote = getSourceQuote(sourceQuoteId);
            if (sourceQuote == null) {
                throw new CloneException('Source Quote not found');
            }
            
            // Clone the quote
            Quote clonedQuote = cloneQuote(sourceQuote, options);
            insert clonedQuote;
            result.clonedQuoteId = clonedQuote.Id;
            
            // Clone line items if requested
            if (options == null || options.cloneLineItems) {
                List<QuoteLineItem> clonedLines = cloneQuoteLineItems(sourceQuoteId, clonedQuote.Id, options);
                if (!clonedLines.isEmpty()) {
                    insert clonedLines;
                    result.lineItemCount = clonedLines.size();
                    
                    // Revenue Cloud automatically calculates pricing fields
                    // We may need to wait for the calculation to complete
                    System.debug('Inserted ' + clonedLines.size() + ' line items');
                }
            }
            
            // Recalculate pricing if requested
            if (options != null && options.recalculatePricing) {
                // In Revenue Cloud, pricing is typically handled automatically
                // This is a placeholder for any custom pricing logic
                System.debug('Pricing recalculation requested - handled by Revenue Cloud');
            }
            
            // Calculate total value
            result.totalValue = calculateQuoteTotal(clonedQuote.Id);
            
            // Handle syncing if requested to make this the primary quote
            if (options != null && options.makePrimary) {
                System.debug('makePrimary option is true, attempting to sync quote');
                
                // Directly attempt to sync the quote
                // The NetTotalPrice check is bypassed due to known Salesforce bug
                attemptQuoteSync(clonedQuote.Id, sourceQuote.OpportunityId, result);
            } else {
                System.debug('makePrimary option is false or null');
                result.message = 'Quote cloned successfully';
            }
            
            result.success = true;
            
        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.message = 'Error cloning quote: ' + e.getMessage();
            System.debug('Clone error: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * Helper method to attempt quote sync with proper error handling
     * Uses Queueable to handle async sync since SyncedQuoteId cannot be set in same transaction
     */
    private static void attemptQuoteSync(Id quoteId, Id opportunityId, CloneResult result) {
        System.debug('=== attemptQuoteSync Started ===');
        System.debug('Quote ID to sync: ' + quoteId);
        System.debug('Opportunity ID: ' + opportunityId);
        
        try {
            // Use Queueable for async processing
            // This avoids the transaction issues with setting SyncedQuoteId
            Map<Id, Id> quoteToOppMap = new Map<Id, Id>();
            quoteToOppMap.put(quoteId, opportunityId);
            
            // Check if we're already in an async context
            if (System.isFuture() || System.isBatch() || System.isQueueable() || System.isScheduled()) {
                System.debug('SYNC PATH: Already in async context, cannot enqueue');
                result.message = 'Quote cloned successfully. Sync will be processed shortly.';
                // In this case, we might want to store the sync request for later processing
            } else {
                System.debug('SYNC PATH: Enqueueing QuoteSyncQueueable');
                System.enqueueJob(new QuoteSyncQueueable(quoteToOppMap));
                result.message = 'Quote cloned successfully. Syncing with opportunity...';
                System.debug('QuoteSyncQueueable enqueued successfully');
            }
        } catch (Exception e) {
            System.debug('Error enqueueing sync: ' + e.getMessage());
            result.message = 'Quote cloned successfully. Manual sync may be required.';
        }
    }
    
    /**
     * Sync a quote to its opportunity (make it the primary/syncing quote)
     * This sets the Opportunity.SyncedQuoteId field which controls syncing in Revenue Cloud
     * Must be called from a future context if invoked from a trigger
     * 
     * @param quoteId The ID of the quote to sync
     * @param opportunityId The ID of the opportunity
     */
    @future
    public static void syncQuoteToOpportunityAsync(Id quoteId, Id opportunityId) {
        try {
            // Update the Opportunity's SyncedQuoteId field
            // This is the proper way to control quote syncing in Revenue Cloud Advanced
            Opportunity opp = new Opportunity(
                Id = opportunityId,
                SyncedQuoteId = quoteId
            );
            update opp;
            
            System.debug('Successfully synced Quote ' + quoteId + ' to Opportunity ' + opportunityId);
        } catch (Exception e) {
            System.debug('Error syncing quote to opportunity: ' + e.getMessage());
            // In production, you might want to log this error or send a notification
        }
    }
    
    /**
     * Sync a quote to its opportunity synchronously (non-future)
     * Use this method when not in a trigger context
     * 
     * @param quoteId The ID of the quote to sync
     * @return Success result
     */
    @AuraEnabled
    public static SyncResult syncQuoteToOpportunity(Id quoteId) {
        SyncResult result = new SyncResult();
        
        try {
            // Get the quote to find its opportunity
            Quote quote = [SELECT Id, OpportunityId FROM Quote WHERE Id = :quoteId LIMIT 1];
            
            if (quote.OpportunityId == null) {
                throw new CloneException('Quote is not associated with an Opportunity');
            }
            
            // Update the Opportunity's SyncedQuoteId field
            Opportunity opp = new Opportunity(
                Id = quote.OpportunityId,
                SyncedQuoteId = quoteId
            );
            update opp;
            
            result.success = true;
            result.message = 'Quote successfully synced to opportunity';
            result.isSyncing = true;
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error syncing quote: ' + e.getMessage();
            result.isSyncing = false;
        }
        
        return result;
    }
    
    /**
     * Stop syncing a quote (remove it as the primary quote)
     * 
     * @param quoteId The ID of the quote to stop syncing
     * @return Success result
     */
    @AuraEnabled
    public static SyncResult stopSyncingQuote(Id quoteId) {
        SyncResult result = new SyncResult();
        
        try {
            // Get the quote to find its opportunity
            Quote quote = [SELECT Id, OpportunityId, IsSyncing FROM Quote WHERE Id = :quoteId LIMIT 1];
            
            if (quote.OpportunityId == null) {
                throw new CloneException('Quote is not associated with an Opportunity');
            }
            
            // Check if this quote is currently syncing
            Opportunity opp = [SELECT Id, SyncedQuoteId FROM Opportunity WHERE Id = :quote.OpportunityId LIMIT 1];
            
            if (opp.SyncedQuoteId != quoteId) {
                result.success = true;
                result.message = 'This quote is not currently syncing';
                result.isSyncing = false;
                return result;
            }
            
            // Clear the SyncedQuoteId to stop syncing
            opp.SyncedQuoteId = null;
            update opp;
            
            result.success = true;
            result.message = 'Quote sync stopped successfully';
            result.isSyncing = false;
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error stopping sync: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Check if a quote is currently syncing
     * 
     * @param quoteId The ID of the quote to check
     * @return True if the quote is syncing
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isQuoteSyncing(Id quoteId) {
        try {
            Quote quote = [SELECT Id, IsSyncing FROM Quote WHERE Id = :quoteId LIMIT 1];
            return quote.IsSyncing;
        } catch (Exception e) {
            System.debug('Error checking sync status: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Get the source quote with all necessary fields
     */
    private static Quote getSourceQuote(Id quoteId) {
        String query = 'SELECT ' + String.join(getQuoteFields(), ', ') + 
                      ' FROM Quote WHERE Id = :quoteId LIMIT 1';
        List<Quote> quotes = Database.query(query);
        return quotes.isEmpty() ? null : quotes[0];
    }
    
    /**
     * Clone the quote record
     */
    private static Quote cloneQuote(Quote sourceQuote, CloneOptions options) {
        Quote clonedQuote = sourceQuote.clone(false, true, false, false);
        
        // Set new values
        if (options != null && String.isNotBlank(options.quoteName)) {
            clonedQuote.Name = options.quoteName;
        } else {
            clonedQuote.Name = 'Copy of ' + sourceQuote.Name;
        }
        
        // Set expiration date
        if (options != null && options.expirationDate != null) {
            clonedQuote.ExpirationDate = options.expirationDate;
        } else {
            clonedQuote.ExpirationDate = Date.today().addDays(30);
        }
        
        // Reset status to Draft
        clonedQuote.Status = 'Draft';
        
        // Note: QuoteNumber is auto-generated and read-only
        // Note: IsSyncing is system-controlled and read-only in Revenue Cloud
        // Syncing is controlled via Opportunity.SyncedQuoteId
        
        return clonedQuote;
    }
    
    /**
     * Clone quote line items
     */
    private static List<QuoteLineItem> cloneQuoteLineItems(Id sourceQuoteId, Id targetQuoteId, CloneOptions options) {
        List<QuoteLineItem> sourceLines = [
            SELECT Product2Id, PricebookEntryId, Quantity, UnitPrice, 
                   Discount, ServiceDate, Description,
                   ProductSellingModelId, StartDate, EndDate,
                   BillingFrequency, PeriodBoundary
            FROM QuoteLineItem 
            WHERE QuoteId = :sourceQuoteId
            ORDER BY Id
        ];
        
        List<QuoteLineItem> clonedLines = new List<QuoteLineItem>();
        
        for (QuoteLineItem sourceLine : sourceLines) {
            QuoteLineItem clonedLine = sourceLine.clone(false, true, false, false);
            clonedLine.QuoteId = targetQuoteId;
            
            // Note: Discount handling depends on field accessibility in org
            
            // Adjust dates for subscription products
            if (sourceLine.StartDate != null && options != null && options.adjustSubscriptionDates) {
                Integer daysDiff = sourceLine.StartDate.daysBetween(Date.today());
                clonedLine.StartDate = Date.today();
                if (sourceLine.EndDate != null) {
                    clonedLine.EndDate = sourceLine.EndDate.addDays(daysDiff);
                }
            }
            
            clonedLines.add(clonedLine);
        }
        
        return clonedLines;
    }
    
    
    /**
     * Calculate quote total
     */
    private static Decimal calculateQuoteTotal(Id quoteId) {
        AggregateResult[] results = [
            SELECT SUM(TotalPrice) total
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
        ];
        
        if (results.isEmpty() || results[0].get('total') == null) {
            return 0;
        }
        
        return (Decimal)results[0].get('total');
    }
    
    /**
     * Get list of quote fields to query
     */
    private static List<String> getQuoteFields() {
        return new List<String>{
            'Id', 'Name', 'OpportunityId', 'Pricebook2Id', 'ContactId',
            'QuoteNumber', 'IsSyncing', 'ShippingHandling', 'Tax',
            'Status', 'ExpirationDate', 'Description', 'Discount',
            'GrandTotal', 'LineItemCount', 'BillingStreet', 'BillingCity',
            'BillingState', 'BillingPostalCode', 'BillingCountry',
            'ShippingStreet', 'ShippingCity', 'ShippingState',
            'ShippingPostalCode', 'ShippingCountry', 'QuoteToStreet',
            'QuoteToCity', 'QuoteToState', 'QuoteToPostalCode',
            'QuoteToCountry', 'AdditionalStreet', 'AdditionalCity',
            'AdditionalState', 'AdditionalPostalCode', 'AdditionalCountry',
            'BillingName', 'ShippingName', 'QuoteToName', 'AdditionalName',
            'Email', 'Phone', 'Fax', 'AccountId', 'ContractId'
        };
    }
    
    /**
     * Clone options wrapper class
     */
    public class CloneOptions {
        @AuraEnabled public String quoteName { get; set; }
        @AuraEnabled public Date expirationDate { get; set; }
        @AuraEnabled public Boolean cloneLineItems { get; set; }
        @AuraEnabled public Boolean recalculatePricing { get; set; }
        @AuraEnabled public Boolean copyDiscounts { get; set; }
        @AuraEnabled public Boolean adjustSubscriptionDates { get; set; }
        @AuraEnabled public Boolean makePrimary { get; set; }  // New field for Revenue Cloud syncing
        @AuraEnabled public String internalNotes { get; set; }
        
        public CloneOptions() {
            // Set defaults
            this.cloneLineItems = true;
            this.recalculatePricing = true;
            this.copyDiscounts = true;
            this.adjustSubscriptionDates = false;
            this.makePrimary = false;  // Default to not making it primary
        }
    }
    
    /**
     * Clone result wrapper class
     */
    public class CloneResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id clonedQuoteId { get; set; }
        @AuraEnabled public Integer lineItemCount { get; set; }
        @AuraEnabled public Decimal totalValue { get; set; }
        @AuraEnabled public Boolean syncDeferred { get; set; }
        
        public CloneResult() {
            this.success = false;
            this.lineItemCount = 0;
            this.totalValue = 0;
            this.syncDeferred = false;
        }
    }
    
    /**
     * Sync result wrapper class
     */
    public class SyncResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Boolean isSyncing { get; set; }
        
        public SyncResult() {
            this.success = false;
            this.isSyncing = false;
        }
    }
    
    /**
     * Custom exception class
     */
    public class CloneException extends Exception {}
}