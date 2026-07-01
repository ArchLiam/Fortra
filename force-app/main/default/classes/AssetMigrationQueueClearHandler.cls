/**
 * Handler for AssetMigrationQueueClearTrigger. Bounded to one extra SOQL on
 * AssetActionSource, one SOQL on Migration_Run_Detail__c, and one bulk update.
 * Defensively wrapped so any failure logs without breaking Asset creation.
 */
public with sharing class AssetMigrationQueueClearHandler {

    public static void handleAfterInsert(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) return;
        try {
            // Step 1: Find migration-created Contracts via AssetContractRelationship
            // (Asset has no direct ContractId; the ACR junction object is the link).
            // This trigger is defense-in-depth on top of the batch's per-Quote
            // auto-clear at AUA-success — both paths leave the queue correct.
            Set<Id> contractIds = new Set<Id>();
            for (AssetContractRelationship acr : [
                SELECT ContractId
                FROM AssetContractRelationship
                WHERE AssetId IN :assetIds
                AND Contract.Migration_Created__c = true
                AND ContractId != null
            ]) {
                contractIds.add(acr.ContractId);
            }
            if (contractIds.isEmpty()) return;

            // Step 2: Find Quote Ids for activated Orders on those Contracts.
            Set<Id> quoteIds = new Set<Id>();
            for (Order o : [
                SELECT QuoteId
                FROM Order
                WHERE ContractId IN :contractIds
                AND Status = 'Activated'
                AND QuoteId != null
            ]) {
                quoteIds.add(o.QuoteId);
            }
            if (quoteIds.isEmpty()) return;

            // Step 3: Clear In_Rerun_Queue__c on detail rows for those Quotes.
            List<Migration_Run_Detail__c> queued = [
                SELECT Id FROM Migration_Run_Detail__c
                WHERE Quote__c IN :quoteIds
                AND In_Rerun_Queue__c = true
                LIMIT 5000
            ];
            if (queued.isEmpty()) return;
            for (Migration_Run_Detail__c d : queued) {
                d.In_Rerun_Queue__c = false;
            }
            Database.update(queued, false);
            System.debug(LoggingLevel.INFO,
                'AssetMigrationQueueClearHandler: cleared ' + queued.size() +
                ' queue entries for ' + quoteIds.size() + ' migration Quotes');
        } catch (Exception e) {
            // Defensive: never break Asset creation. Log only.
            System.debug(LoggingLevel.ERROR,
                'AssetMigrationQueueClearHandler error: ' + e.getMessage() +
                ' | Stack: ' + e.getStackTraceString());
        }
    }
}