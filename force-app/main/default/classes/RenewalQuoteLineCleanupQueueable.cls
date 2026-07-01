/**
 * @description Defers carryover line cleanup until after Place Sales Transaction
 *              completes. Synchronous deletes in after insert break TLE Configure + Save.
 */
public with sharing class RenewalQuoteLineCleanupQueueable implements Queueable {

    private final Set<Id> quoteIds;

    public RenewalQuoteLineCleanupQueueable(Set<Id> quoteIds) {
        this.quoteIds = quoteIds == null ? new Set<Id>() : quoteIds.clone();
    }

    public void execute(QueueableContext context) {
        RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes(quoteIds);
    }
}