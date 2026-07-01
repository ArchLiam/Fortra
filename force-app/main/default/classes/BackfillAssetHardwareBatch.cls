/**
 * One-time backfill: populates Asset.Hardware__c on existing lifecycle-managed
 * Assets whose source OrderItem already carries a Hardware__c value but whose
 * Asset.Hardware__c was left blank by the prior (incorrect) assetization logic
 * that read OrderItem.Hardware_ID__c instead of OrderItem.Hardware__c.
 *
 * Traversal mirrors PopulateAssetLegacyFieldsAction:
 *   OrderItem (Hardware__c) -> AssetActionSource (ReferenceEntityItemId)
 *   -> AssetAction (Type='Generate', AssetId) -> Asset
 *
 * Only updates Assets that are currently missing Hardware__c, so manually-set
 * values are never overwritten. Uses partial-success DML so one bad row never
 * fails an entire batch.
 *
 * Run:  Database.executeBatch(new BackfillAssetHardwareBatch(), 200);
 */
public without sharing class BackfillAssetHardwareBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    @TestVisible private Integer updatedCount = 0;
    @TestVisible private Integer failedCount = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Drive from the (relatively small) set of order lines that actually
        // carry hardware, rather than scanning every Asset in the org.
        return Database.getQueryLocator([
            SELECT Id, Hardware__c
            FROM OrderItem
            WHERE Hardware__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<OrderItem> scope) {
        Map<Id, Id> orderItemToHardware = new Map<Id, Id>();
        for (OrderItem oi : scope) {
            if (oi.Hardware__c != null) {
                orderItemToHardware.put(oi.Id, oi.Hardware__c);
            }
        }
        if (orderItemToHardware.isEmpty()) return;

        // Map each generated Asset to the OrderItem that produced it.
        Map<Id, Id> assetToOrderItem = mapAssetsToOrderItems([
            SELECT AssetAction.AssetId, ReferenceEntityItemId
            FROM AssetActionSource
            WHERE ReferenceEntityItemId IN :orderItemToHardware.keySet()
              AND AssetAction.Type = 'Generate'
            ORDER BY CreatedDate DESC
        ]);
        if (assetToOrderItem.isEmpty()) return;

        // Only touch Assets that are currently missing hardware.
        Map<Id, Asset> assetsById = new Map<Id, Asset>([
            SELECT Id, Hardware__c
            FROM Asset
            WHERE Id IN :assetToOrderItem.keySet()
              AND Hardware__c = null
        ]);
        if (assetsById.isEmpty()) return;

        applyUpdates(buildBackfillUpdates(assetToOrderItem, orderItemToHardware, assetsById));
    }

    /**
     * Reduces AssetActionSource rows to assetId -> sourceOrderItemId, keeping the
     * first (most recent, per ORDER BY) match per Asset. Separated for testability
     * since AssetActionSource/AssetAction are system-managed.
     */
    @TestVisible
    static Map<Id, Id> mapAssetsToOrderItems(List<AssetActionSource> sources) {
        Map<Id, Id> assetToOrderItem = new Map<Id, Id>();
        for (AssetActionSource aas : sources) {
            Id assetId = (aas.AssetAction != null) ? aas.AssetAction.AssetId : null;
            if (assetId != null && !assetToOrderItem.containsKey(assetId)) {
                assetToOrderItem.put(assetId, aas.ReferenceEntityItemId);
            }
        }
        return assetToOrderItem;
    }

    /**
     * Pure mapping logic. Returns the Asset records that should be updated with
     * their hardware, skipping assets that already have hardware or have no
     * resolvable source hardware value.
     */
    @TestVisible
    static List<Asset> buildBackfillUpdates(
        Map<Id, Id> assetToOrderItem,
        Map<Id, Id> orderItemToHardware,
        Map<Id, Asset> assetsById
    ) {
        List<Asset> updates = new List<Asset>();
        for (Id assetId : assetToOrderItem.keySet()) {
            Asset a = assetsById.get(assetId);
            if (a == null || a.Hardware__c != null) continue; // not a candidate
            Id hardwareId = orderItemToHardware.get(assetToOrderItem.get(assetId));
            if (hardwareId == null) continue;
            updates.add(new Asset(Id = assetId, Hardware__c = hardwareId));
        }
        return updates;
    }

    /**
     * Applies the Asset updates with partial-success DML and tallies the
     * stateful success/failure counters.
     */
    @TestVisible
    void applyUpdates(List<Asset> updates) {
        if (updates == null || updates.isEmpty()) return;
        for (Database.SaveResult sr : Database.update(updates, false)) {
            if (sr.isSuccess()) {
                updatedCount++;
            } else {
                failedCount++;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            '[BackfillAssetHardwareBatch] Assets updated=' + updatedCount
            + ', failed=' + failedCount);
    }
}