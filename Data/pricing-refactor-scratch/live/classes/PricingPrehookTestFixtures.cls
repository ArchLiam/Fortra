/**
 * @description Shared test fixtures for the Fortra pricing-prehook test suite.
 * @author Marc DeBrey
 */
@isTest
public class PricingPrehookTestFixtures {

    public static Account account(String name) {
        Account a = new Account(Name = name + ' ' + String.valueOf(Crypto.getRandomLong()).right(8));
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(a, dml);
        return a;
    }

    public static Hardware__c hardware(String pGroup, String serverType, Decimal users) {
        Hardware__c hw = new Hardware__c(
            Account__c = account('HW Acct').Id,
            P_Group_List__c = pGroup, Server_Type__c = serverType,
            Users_Per_Partition__c = users, Model_Number__c = 'TEST-MODEL',
            Serial_Number__c = 'SN-' + String.valueOf(Crypto.getRandomLong()).right(10));
        insert hw;
        return hw;
    }

    public static Map<String, Object> tag(Object v) {
        return new Map<String, Object>{ 'tagValue' => v };
    }

    public static Map<String, Object> itemNode(Map<String, Object> tagValues, List<Object> dataPath) {
        return new Map<String, Object>{ 'tagValue' => tagValues, 'dataPath' => dataPath };
    }

    /**
     * Most recent contract created by assetWithActivatedContractOverride(). Lets callers assert on /
     * re-query the activated Contract (COLA override fields) directly, since the AssetContractRelationship
     * link is NOT reliably insertable on this org (see below).
     */
    public static Id lastContractId { get; private set; }

    /**
     * True iff the AssetContractRelationship link row was successfully inserted by the most recent call to
     * assetWithActivatedContractOverride(). On Revenue Cloud orgs this is typically FALSE: the link requires
     * an Asset with HasLifecycleManagement=true, which is a platform-owned (createable=false, updateable=false)
     * field that direct test DML cannot set. The Account + activated Contract + COLA override + Asset are
     * always created; only the ACR link is best-effort. Downstream code (AssetContractQueryHelper) already
     * tolerates an absent ACR via try/catch + CMDT fallback, so this fixture mirrors that contract.
     */
    public static Boolean lastAcrLinked { get; private set; }

    /**
     * @description Builds the Asset + Activated Contract (with COLA override) data graph used by the COLA
     *              uplift tests and asset-contract query helper. Returns the Asset Id.
     *
     * Contract: inserted Draft (the org's only RecordType is ContractLifecycleManagement, so we do NOT
     * specify a RecordType) then promoted to Status='Activated' via update -- this transition is permitted;
     * only POST-activation Status writes are platform-blocked.
     *
     * AssetContractRelationship: attempted best-effort and wrapped in try/catch. The platform requires the
     * related Asset to have Lifecycle Management enabled (HasLifecycleManagement=true), which is set only by
     * the order-to-asset pipeline and cannot be set by direct DML. When the link cannot be created the method
     * still returns a valid Asset Id and sets lastAcrLinked=false; callers needing the Contract should read
     * lastContractId. NOTE: StartDate is required on AssetContractRelationship -- omitting it turns the DML
     * error into an uncatchable platform UNKNOWN_EXCEPTION, so it is always supplied.
     */
    public static Id assetWithActivatedContractOverride(Decimal overridePercent, Date persistUntil) {
        Account acct = account('Contract Acct');
        Contract c = new Contract(AccountId = acct.Id, Status = 'Draft',
            StartDate = Date.today().addMonths(-1), ContractTerm = 12,
            COLA_Override_Percent__c = overridePercent, COLA_Override_Persist_Until__c = persistUntil);
        insert c;
        c.Status = 'Activated';
        update c;
        lastContractId = c.Id;

        Asset a = new Asset(Name = 'Test Asset', AccountId = acct.Id,
            Price = 1000, Quantity = 1, Status = 'Installed');
        insert a;

        lastAcrLinked = false;
        try {
            AssetContractRelationship acr = new AssetContractRelationship(
                AssetId = a.Id, ContractId = c.Id, StartDate = System.now());
            insert acr;
            lastAcrLinked = true;
        } catch (Exception e) {
            // Expected on Revenue Cloud orgs: "Asset must have Lifecycle Management enabled."
            // The Asset's HasLifecycleManagement flag is platform-owned and not settable via test DML.
            System.debug(LoggingLevel.WARN,
                'AssetContractRelationship link not created (expected on RC orgs): ' + e.getMessage());
        }
        return a.Id;
    }

    /**
     * @description Self-test proving the asset-contract fixture executes. Downstream tasks depend on it.
     *              Asserts the reliably-creatable graph (Asset + Activated Contract + COLA override); the
     *              AssetContractRelationship link is best-effort and asserted only when lastAcrLinked is true,
     *              matching how AssetContractQueryHelper tolerates an absent ACR.
     */
    @isTest
    static void testAssetWithActivatedContractOverride() {
        Test.startTest();
        Id assetId = assetWithActivatedContractOverride(7.5, null);
        Test.stopTest();

        System.assertNotEquals(null, assetId, 'Fixture should return a non-null Asset Id');
        System.assertNotEquals(null, lastContractId, 'Fixture should record the Contract Id');

        Asset a = [SELECT Id, AccountId FROM Asset WHERE Id = :assetId];
        System.assertEquals(assetId, a.Id, 'Asset row should exist');

        Contract c = [
            SELECT Id, Status, COLA_Override_Percent__c
            FROM Contract WHERE Id = :lastContractId
        ];
        System.assertEquals('Activated', c.Status, 'Contract should be Activated');
        System.assertEquals(7.5, c.COLA_Override_Percent__c, 'COLA override percent should be persisted');

        // ACR link is best-effort: assert it only when it actually got created.
        if (lastAcrLinked) {
            List<AssetContractRelationship> acrs = [
                SELECT Id, AssetId, ContractId FROM AssetContractRelationship WHERE AssetId = :assetId
            ];
            System.assertEquals(1, acrs.size(),
                'When lastAcrLinked is true exactly one AssetContractRelationship row should exist');
            System.assertEquals(lastContractId, acrs[0].ContractId, 'ACR should point at the activated Contract');
        }
    }
}