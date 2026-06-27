/**
 * @description First test class for AssetContractQueryHelper.
 *
 * AssetContractRelationship CANNOT be inserted in a test on this org: the platform requires the
 * linked Asset to have HasLifecycleManagement=true, a platform-owned (createable=false) field set
 * only by the real order-to-asset pipeline, never by test DML. So the "relationship found -> query
 * contracts -> build wrappers" branch cannot be driven by a real ACR row. To cover it anyway the
 * helper exposes a @TestVisible buildResults(...) seam that performs the (pure, in-memory) wrapper
 * build from IN-MEMORY (uninserted) AssetContractRelationship rows plus real activated Contracts.
 * The live queryAssetContracts(...) path is still exercised for the guard + empty-result branches
 * (the SOQL line runs against an empty ACR table and returns an empty list). The runtime
 * relationship-found path works in production where renewal assets have Lifecycle Management on.
 *
 * @author Marc DeBrey
 */
@isTest
private class AssetContractQueryHelperTest {

    /**
     * Live path: null and empty input both short-circuit to an empty list (guard branch).
     */
    @isTest
    static void testQueryAssetContracts_NullAndEmptyGuard() {
        Test.startTest();
        List<AssetContractQueryHelper.AssetContractData> nullResult =
            AssetContractQueryHelper.queryAssetContracts(null);
        List<AssetContractQueryHelper.AssetContractData> emptyResult =
            AssetContractQueryHelper.queryAssetContracts(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, nullResult.size(), 'null assetIds should return an empty list');
        System.assertEquals(0, emptyResult.size(), 'empty assetIds should return an empty list');
    }

    /**
     * Live path: a real Asset Id with no AssetContractRelationship row (ACR is uninsertable in tests)
     * runs the dynamic ACR SOQL, hits the empty-relationships early return, and yields an empty list.
     * This covers the live query line + the empty-relationships branch without a real ACR.
     */
    @isTest
    static void testQueryAssetContracts_NoRelationshipRows() {
        Id assetId = PricingPrehookTestFixtures.assetWithActivatedContractOverride(5.0, null);

        Test.startTest();
        List<AssetContractQueryHelper.AssetContractData> result =
            AssetContractQueryHelper.queryAssetContracts(new Set<Id>{ assetId });
        Test.stopTest();

        // On this org the ACR link is not created (lastAcrLinked=false), so the live query finds
        // nothing and returns empty. If the platform ever did link it, the assert below documents
        // the expectation either way (the wrapper count equals the linked-row count).
        Integer expected = PricingPrehookTestFixtures.lastAcrLinked ? 1 : 0;
        System.assertEquals(expected, result.size(),
            'Live query returns one wrapper per linked ACR; zero when no ACR row exists');
    }

    /**
     * Build seam, contract-id collection: in-memory ACR rows are reduced to their unique, non-null
     * ContractId set (covers the collectContractIds loop + null guard).
     */
    @isTest
    static void testCollectContractIds() {
        Id assetId = PricingPrehookTestFixtures.assetWithActivatedContractOverride(4.0, null);
        Id contractId = PricingPrehookTestFixtures.lastContractId;

        AssetContractRelationship withContract = new AssetContractRelationship(
            AssetId = assetId, ContractId = contractId, StartDate = System.now());
        AssetContractRelationship withNullContract = new AssetContractRelationship(
            AssetId = assetId, StartDate = System.now());

        Test.startTest();
        Set<Id> ids = AssetContractQueryHelper.collectContractIds(
            new List<AssetContractRelationship>{ withContract, withNullContract });
        Set<Id> nullIds = AssetContractQueryHelper.collectContractIds(null);
        Test.stopTest();

        System.assertEquals(1, ids.size(), 'Only the non-null ContractId should be collected');
        System.assert(ids.contains(contractId), 'Collected set should contain the real contract id');
        System.assertEquals(0, nullIds.size(), 'Null relationships -> empty id set');
    }

    /**
     * Build seam, happy path: an in-memory ACR pointing at a REAL activated Contract (with COLA
     * override fields) produces exactly one AssetContractData carrying the override + 'Activated'.
     */
    @isTest
    static void testBuildResults_ActivatedContractWithOverride() {
        Id assetId = PricingPrehookTestFixtures.assetWithActivatedContractOverride(7.5, Date.today().addYears(1));
        Id contractId = PricingPrehookTestFixtures.lastContractId;

        Contract activated = [
            SELECT Id, Status, COLA_Override_Percent__c, COLA_Override_Persist_Until__c
            FROM Contract WHERE Id = :contractId
        ];

        // IN-MEMORY ACR (never inserted) linking a fake asset to the real activated Contract.
        AssetContractRelationship acr = new AssetContractRelationship(
            AssetId = assetId, ContractId = contractId, StartDate = System.now());

        Test.startTest();
        List<AssetContractQueryHelper.AssetContractData> results =
            AssetContractQueryHelper.buildResults(
                new List<AssetContractRelationship>{ acr },
                new List<Contract>{ activated });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One activated contract -> one wrapper');
        AssetContractQueryHelper.AssetContractData data = results[0];
        System.assertEquals(assetId, data.assetId, 'Wrapper assetId should come from the ACR');
        System.assertEquals(contractId, data.contractId, 'Wrapper contractId should be the activated contract');
        System.assertEquals(7.5, data.colaOverridePercent, 'COLA override percent should be carried through');
        System.assertEquals(Date.today().addYears(1), data.colaPersistUntil, 'Persist-until date should be carried through');
        System.assertEquals('Activated', data.contractStatus, 'contractStatus should be Activated');
    }

    /**
     * Build seam: a relationship whose ContractId has NO matching contract in the activated map is
     * skipped (covers the containsKey skip / no-matching-contract branch).
     */
    @isTest
    static void testBuildResults_RelationshipWithoutMatchingContract() {
        Id assetId = PricingPrehookTestFixtures.assetWithActivatedContractOverride(3.0, null);
        Id realContractId = PricingPrehookTestFixtures.lastContractId;

        Contract activated = [
            SELECT Id, Status, COLA_Override_Percent__c, COLA_Override_Persist_Until__c
            FROM Contract WHERE Id = :realContractId
        ];

        // ACR points at a DIFFERENT (fake) contract id than the one in the activated list.
        Id unmatchedContractId = '800000000000000AAA';
        AssetContractRelationship acr = new AssetContractRelationship(
            AssetId = assetId, ContractId = unmatchedContractId, StartDate = System.now());

        Test.startTest();
        List<AssetContractQueryHelper.AssetContractData> results =
            AssetContractQueryHelper.buildResults(
                new List<AssetContractRelationship>{ acr },
                new List<Contract>{ activated });
        Test.stopTest();

        System.assertEquals(0, results.size(),
            'Relationship referencing a contract not in the activated list yields no wrapper');
    }

    /**
     * Build seam: a non-Activated (Draft) contract is the live query's responsibility to exclude.
     * Here we model that exclusion by passing an EMPTY activated-contracts list (the live SOQL
     * filters Status='Activated', so a Draft contract never reaches buildResults) -> empty result,
     * covering the empty-contracts guard branch.
     */
    @isTest
    static void testBuildResults_NoActivatedContracts() {
        Id assetId = PricingPrehookTestFixtures.assetWithActivatedContractOverride(2.0, null);
        Id contractId = PricingPrehookTestFixtures.lastContractId;

        AssetContractRelationship acr = new AssetContractRelationship(
            AssetId = assetId, ContractId = contractId, StartDate = System.now());

        Test.startTest();
        // Empty contracts (mirrors the live Status='Activated' filter excluding a Draft contract).
        List<AssetContractQueryHelper.AssetContractData> emptyContracts =
            AssetContractQueryHelper.buildResults(
                new List<AssetContractRelationship>{ acr }, new List<Contract>());
        // Empty relationships guard.
        List<AssetContractQueryHelper.AssetContractData> emptyRels =
            AssetContractQueryHelper.buildResults(
                new List<AssetContractRelationship>(), new List<Contract>{ });
        // Null guards.
        List<AssetContractQueryHelper.AssetContractData> nullRels =
            AssetContractQueryHelper.buildResults(null, new List<Contract>());
        List<AssetContractQueryHelper.AssetContractData> nullContracts =
            AssetContractQueryHelper.buildResults(new List<AssetContractRelationship>{ acr }, null);
        Test.stopTest();

        System.assertEquals(0, emptyContracts.size(), 'No activated contracts -> empty result');
        System.assertEquals(0, emptyRels.size(), 'No relationships -> empty result');
        System.assertEquals(0, nullRels.size(), 'Null relationships -> empty result');
        System.assertEquals(0, nullContracts.size(), 'Null contracts -> empty result');
    }
}