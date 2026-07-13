/**
 * @description Defers renewal maintenance quantity normalization until after Place Sales
 *              Transaction completes during Asset Renew.
 */
public with sharing class RenewalAssetQuantityQueueable implements Queueable {

    private final Set<Id> quoteIds;

    public RenewalAssetQuantityQueueable(Set<Id> quoteIds) {
        this.quoteIds = quoteIds == null ? new Set<Id>() : quoteIds.clone();
    }

    public void execute(QueueableContext context) {
        RenewalAssetQuantityHandler.applyAssetQuantitiesForQuotes(quoteIds);
        // Chain the maintenance provisioner in this same async transaction rather than enqueue a
        // competing queueable — the asset-renewal context permits only one queued job.
        RenewalMaintenanceProvisionService.provision(quoteIds);
    }
}