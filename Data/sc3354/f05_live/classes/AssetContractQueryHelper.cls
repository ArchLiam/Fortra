/**
 * @description Helper class to query AssetContractRelationship and Contract records.
 *              This is necessary because Revenue Cloud objects like AssetContractRelationship
 *              may not be accessible via dynamic SOQL in trigger context with sharing,
 *              and relationship traversal may not work properly with dynamic SOQL.
 * @author Marc DeBrey
 * @date January 2026
 */
public without sharing class AssetContractQueryHelper {

    /**
     * @description Wrapper class to hold AssetContractRelationship data with Contract info
     */
    public class AssetContractData {
        public Id assetId;
        public Id contractId;
        public Decimal colaOverridePercent;
        public Date colaPersistUntil;
        public String contractStatus;
    }

    /**
     * @description Queries AssetContractRelationship records and related Contracts for given Asset IDs
     * @param assetIds Set of Asset IDs to query
     * @return List of AssetContractData wrappers with Contract fields
     */
    public static List<AssetContractData> queryAssetContracts(Set<Id> assetIds) {
        List<AssetContractData> results = new List<AssetContractData>();

        if (assetIds == null || assetIds.isEmpty()) {
            return results;
        }

        try {
            // Query AssetContractRelationship separately (without relationship traversal)
            String acrQuery = 'SELECT Id, AssetId, ContractId ' +
                              'FROM AssetContractRelationship ' +
                              'WHERE AssetId IN :assetIds';
            List<SObject> relationships = Database.query(acrQuery);

            if (relationships.isEmpty()) {
                return results;
            }

            // Collect the Contract IDs referenced by the relationships (pure transform; @TestVisible).
            Set<Id> contractIds = collectContractIds(relationships);

            // Query Contracts separately with COLA override fields
            List<Contract> contracts = [
                SELECT Id, Status, COLA_Override_Percent__c, COLA_Override_Persist_Until__c
                FROM Contract
                WHERE Id IN :contractIds
                AND Status = 'Activated'
            ];

            // Build result wrappers from the queried relationships + activated contracts.
            results = buildResults(relationships, contracts);
        } catch (Exception e) {
            // AssetContractRelationship may not be available in all orgs
            // Fall back to CMDT lookup only (no Contract override capability)
            System.debug('AssetContractRelationship query failed: ' + e.getMessage());
        }

        return results;
    }

    /**
     * @description Builds the AssetContractData wrappers from AssetContractRelationship rows and
     *              the (already Status='Activated'-filtered) Contracts. Pure in-memory transform with
     *              no SOQL/DML, so it can be exercised directly in tests where AssetContractRelationship
     *              rows cannot be inserted (the platform requires the linked Asset to have Lifecycle
     *              Management enabled, a field test DML cannot set). The live query path delegates here.
     * @param relationships AssetContractRelationship rows (AssetId + ContractId) -- queried or in-memory
     * @param activatedContracts Contracts already filtered to Status='Activated' with COLA override fields
     * @return List of AssetContractData wrappers, one per activated Contract that an ACR points at
     */
    @TestVisible
    private static Set<Id> collectContractIds(List<SObject> relationships) {
        Set<Id> contractIds = new Set<Id>();
        if (relationships == null) {
            return contractIds;
        }
        for (SObject acr : relationships) {
            Id contractId = (Id)acr.get('ContractId');
            if (contractId != null) {
                contractIds.add(contractId);
            }
        }
        return contractIds;
    }

    @TestVisible
    private static List<AssetContractData> buildResults(
        List<SObject> relationships,
        List<Contract> activatedContracts
    ) {
        List<AssetContractData> results = new List<AssetContractData>();
        if (relationships == null || relationships.isEmpty()
                || activatedContracts == null || activatedContracts.isEmpty()) {
            return results;
        }

        // Map each ContractId to the Asset its relationship points at.
        Map<Id, Id> contractToAssetMap = new Map<Id, Id>();
        for (SObject acr : relationships) {
            contractToAssetMap.put((Id)acr.get('ContractId'), (Id)acr.get('AssetId'));
        }

        for (Contract c : activatedContracts) {
            // Only contracts that an incoming relationship references get a wrapper.
            if (!contractToAssetMap.containsKey(c.Id)) {
                continue;
            }
            AssetContractData data = new AssetContractData();
            data.assetId = contractToAssetMap.get(c.Id);
            data.contractId = c.Id;
            data.colaOverridePercent = c.COLA_Override_Percent__c;
            data.colaPersistUntil = c.COLA_Override_Persist_Until__c;
            data.contractStatus = c.Status;
            results.add(data);
        }
        return results;
    }
}