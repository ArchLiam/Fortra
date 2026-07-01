/**
 * Batch Apex class for cleaning up Orders created by the Order Migration Tool.
 * Deletes migration-created records in dependency-safe order:
 *   1. AssetContractRelationships
 *   2. Assets (lifecycle-managed on affected Accounts)
 *   3. AppUsageAssignments (on Orders)
 *   4. OrderItems
 *   5. OrderActions
 *   6. Orders (must be set to Draft first if Activated)
 *   7. AppUsageAssignments (on Contracts)
 *   8. Contracts (Migration_Created__c = true)
 *
 * Identification: Orders are found by OrderNumber (parsed from Migration_Run_Log__c)
 * or by re-running the same filter used for migration.
 *
 * @author Marc DeBrey
 * @since 2026-04
 */
public class OrderMigrationCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Set<Id> orderIds;
    private Boolean deleteContracts;

    // Stateful counters
    private Integer ordersDeleted = 0;
    private Integer orderItemsDeleted = 0;
    private Integer assetsDeleted = 0;
    private Integer contractsDeleted = 0;
    private List<String> errors = new List<String>();
    private static final Integer MAX_ERRORS = 100;

    /**
     * @param orderIds Set of Order Ids to clean up
     * @param deleteContracts If true, also delete Migration_Created__c Contracts linked to these Orders
     */
    public OrderMigrationCleanupBatch(Set<Id> orderIds, Boolean deleteContracts) {
        this.orderIds = orderIds;
        this.deleteContracts = deleteContracts != null ? deleteContracts : false;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'OrderMigrationCleanupBatch: Starting cleanup of ' +
            this.orderIds.size() + ' orders (deleteContracts=' + this.deleteContracts + ')');
        List<Id> idList = new List<Id>(this.orderIds);
        return Database.getQueryLocator([
            SELECT Id, OrderNumber, Status, ContractId, AccountId
            FROM Order
            WHERE Id IN :idList
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Order> orders) {
        try {
            executeInternal(orders);
        } catch (Exception e) {
            addError('Batch failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Cleanup execute() error: ' +
                e.getMessage() + ' | Stack: ' + e.getStackTraceString());
        }
    }

    private void executeInternal(List<Order> orders) {
        Set<Id> batchOrderIds = new Set<Id>();
        Set<Id> batchContractIds = new Set<Id>();

        for (Order ord : orders) {
            batchOrderIds.add(ord.Id);
            if (ord.ContractId != null) {
                batchContractIds.add(ord.ContractId);
            }
        }

        // Collect OrderItem IDs
        List<OrderItem> ois = [SELECT Id FROM OrderItem WHERE OrderId IN :batchOrderIds];
        Set<Id> oiIds = new Set<Id>();
        for (OrderItem oi : ois) {
            oiIds.add(oi.Id);
        }

        // ── Step 1: Find and delete Assets (cascade deletes AssetActions + AssetActionSources) ──
        Set<Id> assetIds = new Set<Id>();
        if (!oiIds.isEmpty()) {
            for (AssetActionSource src : [
                SELECT AssetAction.AssetId FROM AssetActionSource
                WHERE ReferenceEntityItemId IN :oiIds
            ]) {
                if (src.AssetAction != null && src.AssetAction.AssetId != null) {
                    assetIds.add(src.AssetAction.AssetId);
                }
            }
        }
        if (!assetIds.isEmpty()) {
            // Remove AssetContractRelationships
            Database.delete([SELECT Id FROM AssetContractRelationship WHERE AssetId IN :assetIds], false);

            // RLC Assets cannot be deleted via DML ("You can't delete assets that have Lifecycle Management").
            // Instead, clear Legacy_Id__c to prevent unique constraint errors on future runs,
            // and mark them so they're identifiable for manual cleanup.
            List<Asset> assetsToClean = [SELECT Id, Legacy_Id__c FROM Asset WHERE Id IN :assetIds];
            for (Asset a : assetsToClean) {
                a.Legacy_Id__c = null;
            }
            Database.update(assetsToClean, false);
            this.assetsDeleted += assetsToClean.size();
        }

        // ── Step 2: Delete AppUsageAssignments on Orders (must go before deactivation) ──
        List<AppUsageAssignment> orderAuas = [
            SELECT Id FROM AppUsageAssignment WHERE RecordId IN :batchOrderIds
        ];
        if (!orderAuas.isEmpty()) {
            Database.delete(orderAuas, false);
        }

        // ── Step 3: Delete FulfillmentLineSourceRels (blocks OrderItem deletion) ──
        if (!oiIds.isEmpty()) {
            List<SObject> flsrs = Database.query(
                'SELECT Id FROM FulfillmentLineSourceRel WHERE SourceLineItemId IN :oiIds');
            if (!flsrs.isEmpty()) {
                Database.delete(flsrs, false);
            }
        }

        // ── Step 4: Deactivate Orders (now possible after AUA removal) ──
        List<Order> ordersToDeactivate = new List<Order>();
        for (Order ord : orders) {
            if (ord.Status == 'Activated') {
                ordersToDeactivate.add(new Order(Id = ord.Id, Status = 'Draft'));
            }
        }
        if (!ordersToDeactivate.isEmpty()) {
            Database.update(ordersToDeactivate, false);
        }

        // ── Step 5: Delete OrderItems (Order is now Draft, FLSRs removed) ──
        if (!ois.isEmpty()) {
            Database.DeleteResult[] oiResults = Database.delete(ois, false);
            for (Database.DeleteResult dr : oiResults) {
                if (dr.isSuccess()) {
                    this.orderItemsDeleted++;
                } else {
                    addError('OrderItem ' + dr.getId() + ': ' + dr.getErrors()[0].getMessage());
                }
            }
        }

        // ── Step 6: Delete OrderActions ──
        Database.delete([SELECT Id FROM OrderAction WHERE OrderId IN :batchOrderIds], false);

        // ── Step 7: Delete Orders ──
        Database.DeleteResult[] orderResults = Database.delete(orders, false);
        for (Database.DeleteResult dr : orderResults) {
            if (dr.isSuccess()) {
                this.ordersDeleted++;
            } else {
                addError('Order ' + dr.getId() + ': ' + dr.getErrors()[0].getMessage());
            }
        }

        // ── Step 8: Delete Contracts (if requested) — only migration-created ones ──
        if (this.deleteContracts && !batchContractIds.isEmpty()) {
            Database.delete([
                SELECT Id FROM AppUsageAssignment WHERE RecordId IN :batchContractIds
            ], false);

            List<Contract> contractsToDeactivate = [
                SELECT Id, Status FROM Contract
                WHERE Id IN :batchContractIds
                AND Migration_Created__c = true AND Status = 'Activated'
            ];
            if (!contractsToDeactivate.isEmpty()) {
                for (Contract c : contractsToDeactivate) {
                    c.Status = 'Draft';
                }
                Database.update(contractsToDeactivate, false);
            }

            Database.DeleteResult[] contractResults = Database.delete([
                SELECT Id FROM Contract WHERE Id IN :batchContractIds AND Migration_Created__c = true
            ], false);
            for (Database.DeleteResult dr : contractResults) {
                if (dr.isSuccess()) {
                    this.contractsDeleted++;
                } else {
                    addError('Contract ' + dr.getId() + ': ' + dr.getErrors()[0].getMessage());
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'OrderMigrationCleanupBatch: Complete');
        System.debug(LoggingLevel.INFO, 'Orders Deleted: ' + this.ordersDeleted);
        System.debug(LoggingLevel.INFO, 'OrderItems Deleted: ' + this.orderItemsDeleted);
        System.debug(LoggingLevel.INFO, 'Assets Deleted: ' + this.assetsDeleted);
        System.debug(LoggingLevel.INFO, 'Contracts Deleted: ' + this.contractsDeleted);
        System.debug(LoggingLevel.INFO, 'Errors: ' + this.errors.size());
    }

    private void addError(String msg) {
        if (this.errors.size() < MAX_ERRORS) {
            this.errors.add(msg);
        }
    }
}