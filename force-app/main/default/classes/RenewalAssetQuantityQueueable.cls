/**
 * @description Defers renewal maintenance quantity normalization until after Place Sales
 *              Transaction completes during Asset Renew.
 */
public with sharing class RenewalAssetQuantityQueueable implements Queueable {

    private static final Integer MSG_MAX = 30000;

    private final Set<Id> quoteIds;

    public RenewalAssetQuantityQueueable(Set<Id> quoteIds) {
        this.quoteIds = quoteIds == null ? new Set<Id>() : quoteIds.clone();
    }

    public void execute(QueueableContext context) {
        // SC-3346 reliability: this async job previously had no try/catch, so any throw in either step
        // dropped the maintenance provision silently and left the renewal maintenance line at $0
        // (unrecoverable by reprice). Guard each step independently and surface failures loudly via
        // Pricing_Exception__e, so a quantity-normalization failure never prevents the net-committing
        // provision step from running, and no drop is silent.
        try {
            RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(quoteIds);
        } catch (Exception e) {
            publishFailure('applyAssetQuantities', e);
        }
        // Chain the maintenance provisioner in this same async transaction rather than enqueue a
        // competing queueable — the asset-renewal context permits only one queued job.
        try {
            RenewalMaintenanceProvisionService.provision(quoteIds);
        } catch (Exception e) {
            publishFailure('provision', e);
        }
    }

    /**
     * @description Surfaces an async post-persist step failure as a Pricing_Exception__e Error so the
     *              silent $0-drop class becomes visible in Exception_Log__c. Never throws.
     * @param step The failing step name (applyAssetQuantities | provision).
     * @param e The caught exception.
     */
    @TestVisible
    private void publishFailure(String step, Exception e) {
        String contextId = quoteIds != null && !quoteIds.isEmpty()
            ? String.valueOf(new List<Id>(quoteIds)[0]) : null;
        ExceptionLogger.safePublish(new Pricing_Exception__e(
            Source__c         = 'RenewalAssetQuantityQueueable',
            Severity__c       = 'Error',
            Exception_Type__c = e.getTypeName(),
            Hook_Phase__c     = 'async-renewal-' + step,
            Context_Id__c     = contextId,
            Message__c        = truncate('SC-3346 renewal post-persist ' + step + ' failed for '
                + (quoteIds == null ? 0 : quoteIds.size()) + ' quote(s): ' + e.getMessage(), MSG_MAX),
            Stack_Trace__c    = truncate(e.getStackTraceString(), MSG_MAX),
            Occurred_At__c    = System.now()
        ));
    }

    private static String truncate(String value, Integer max) {
        return value != null && value.length() > max ? value.substring(0, max) : value;
    }
}