/**
 * QuoteSyncQueueable
 * Queueable class to handle asynchronous syncing of quotes with opportunities
 * This is necessary because SyncedQuoteId cannot be set in the same transaction as Quote DML
 */
public with sharing class QuoteSyncQueueable implements Queueable {
    
    private Set<Id> quoteIds;
    private Map<Id, Id> quoteToOpportunityMap;
    
    /**
     * Constructor for the queueable
     * @param quoteIds Set of Quote IDs to sync
     */
    public QuoteSyncQueueable(Set<Id> quoteIds) {
        this.quoteIds = quoteIds;
        this.quoteToOpportunityMap = new Map<Id, Id>();
    }
    
    /**
     * Constructor with pre-mapped Quote to Opportunity IDs
     * @param quoteToOpportunityMap Map of Quote ID to Opportunity ID
     */
    public QuoteSyncQueueable(Map<Id, Id> quoteToOpportunityMap) {
        this.quoteToOpportunityMap = quoteToOpportunityMap;
        this.quoteIds = quoteToOpportunityMap.keySet();
    }
    
    /**
     * Execute method for the queueable
     * @param context QueueableContext
     */
    public void execute(QueueableContext context) {
        System.debug('=== QuoteSyncQueueable Started ===');
        System.debug('Processing ' + quoteIds.size() + ' quotes for syncing');
        
        try {
            // If we don't have the opportunity mapping, query for it
            if (quoteToOpportunityMap.isEmpty()) {
                List<Quote> quotes = [
                    SELECT Id, OpportunityId 
                    FROM Quote 
                    WHERE Id IN :quoteIds 
                    AND OpportunityId != null
                ];
                
                for (Quote q : quotes) {
                    quoteToOpportunityMap.put(q.Id, q.OpportunityId);
                }
            }
            
            // Build list of opportunities to update
            List<Opportunity> oppsToUpdate = new List<Opportunity>();
            
            for (Id quoteId : quoteToOpportunityMap.keySet()) {
                Id oppId = quoteToOpportunityMap.get(quoteId);
                System.debug('Setting Opportunity ' + oppId + ' SyncedQuoteId to Quote ' + quoteId);
                
                Opportunity opp = new Opportunity(
                    Id = oppId,
                    SyncedQuoteId = quoteId
                );
                oppsToUpdate.add(opp);
            }
            
            // Update opportunities if we have any
            if (!oppsToUpdate.isEmpty()) {
                update oppsToUpdate;
                System.debug('Successfully updated ' + oppsToUpdate.size() + ' opportunities with SyncedQuoteId');
                
                // Verify the sync status
                List<Quote> syncedQuotes = [
                    SELECT Id, IsSyncing 
                    FROM Quote 
                    WHERE Id IN :quoteIds
                ];
                
                for (Quote q : syncedQuotes) {
                    System.debug('Quote ' + q.Id + ' IsSyncing status: ' + q.IsSyncing);
                }
            } else {
                System.debug('No opportunities to update');
            }
            
        } catch (Exception e) {
            System.debug('Error in QuoteSyncQueueable: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // In production, you might want to send an email or create a custom object record
            // to track failed sync attempts
        }
    }
}