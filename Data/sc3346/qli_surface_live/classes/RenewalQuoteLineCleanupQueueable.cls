/**
 * @description Defers post-persist quote-line cleanup until after Place Sales Transaction completes,
 *              because synchronous deletes during after-insert break TLE Configure + Save. Runs the
 *              renewal carryover cleanup and the new-business maintenance dedupe for the given quotes.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class RenewalQuoteLineCleanupQueueable implements Queueable {

    private final Set<Id> quoteIds;

    /**
     * @description Captures the quotes to clean up, defensively copying the incoming set.
     * @param quoteIds The quotes whose lines should be reconciled after persistence.
     */
    public RenewalQuoteLineCleanupQueueable(Set<Id> quoteIds) {
        this.quoteIds = quoteIds == null ? new Set<Id>() : quoteIds.clone();
    }

    /**
     * @description Runs renewal carryover cleanup, then removes Add-Assets amend-carryover New
     *              Maintenance duplicates on new-business quotes (a no-op on renewal quotes).
     * @param context The queueable execution context.
     */
    public void execute(QueueableContext context) {
        RenewalQuoteLineHandler.removeNewMaintenanceCarryoverForQuotes(quoteIds);
        NewMaintenanceDedupeService.dedupeForQuotes(quoteIds);
    }
}