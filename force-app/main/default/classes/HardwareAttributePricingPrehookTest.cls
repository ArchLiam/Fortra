/**
 * @description Test class for HardwareAttributePricingPrehook
 *              Tests pGroup, User Tier, and System Type pricing calculations
 *
 *              v2.0 - Updated for Hardware__c query-based design
 *
 * @author Marc DeBrey
 * @date January 2026
 */
@isTest
private class HardwareAttributePricingPrehookTest {

    /**
     * @description Create test Hardware__c record with attribute values
     *              Note: Name is auto-number, so we don't set it
     */
    private static Hardware__c createTestHardware(String pGroup, String serverType, Decimal usersPerPartition) {
        Account testAccount = new Account(Name = 'Test HW Acct ' + String.valueOf(Crypto.getRandomLong()).right(8));
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(testAccount, dml);

        Hardware__c hw = new Hardware__c(
            Account__c = testAccount.Id,
            P_Group_List__c = pGroup,
            Server_Type__c = serverType,
            Users_Per_Partition__c = usersPerPartition,
            Model_Number__c = 'TEST-MODEL',
            Serial_Number__c = 'TEST-SN-' + String.valueOf(Crypto.getRandomLong()).right(10)
        );
        insert hw;
        return hw;
    }

    /**
     * @description Test pGroup multiplier lookup - P30 tier
     */
    @isTest
    static void testPGroupMultiplier_P30() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal multiplier = hook.getPGroupMultiplier('P30');
        Test.stopTest();

        System.assertEquals(1.5, multiplier, 'P30 should return 1.5x multiplier');
    }

    /**
     * @description Test pGroup multiplier lookup - all tiers (including P60)
     */
    @isTest
    static void testPGroupMultiplier_AllTiers() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        System.assertEquals(0.5, hook.getPGroupMultiplier('P05'), 'P05 should return 0.5x');
        System.assertEquals(0.75, hook.getPGroupMultiplier('P10'), 'P10 should return 0.75x');
        System.assertEquals(1.0, hook.getPGroupMultiplier('P20'), 'P20 should return 1.0x');
        System.assertEquals(1.5, hook.getPGroupMultiplier('P30'), 'P30 should return 1.5x');
        System.assertEquals(2.0, hook.getPGroupMultiplier('P40'), 'P40 should return 2.0x');
        System.assertEquals(3.0, hook.getPGroupMultiplier('P50'), 'P50 should return 3.0x');
        System.assertEquals(4.0, hook.getPGroupMultiplier('P60'), 'P60 should return 4.0x');
        Test.stopTest();
    }

    /**
     * @description Test pGroup multiplier with null value
     */
    @isTest
    static void testPGroupMultiplier_Null() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal multiplier = hook.getPGroupMultiplier(null);
        Test.stopTest();

        System.assertEquals(1.0, multiplier, 'Null pGroup should return default 1.0x');
    }

    /**
     * @description Test pGroup multiplier with unknown value
     */
    @isTest
    static void testPGroupMultiplier_Unknown() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal multiplier = hook.getPGroupMultiplier('P99');
        Test.stopTest();

        System.assertEquals(1.0, multiplier, 'Unknown pGroup should return default 1.0x');
    }

    /**
     * @description Test user tier multiplier - 75 users (51-100 range)
     */
    @isTest
    static void testUserTierMultiplier_75Users() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal multiplier = hook.getUserTierMultiplier(75);
        Test.stopTest();

        System.assertEquals(1.5, multiplier, '75 users should return 1.5x multiplier');
    }

    /**
     * @description Test user tier multiplier - all tiers
     */
    @isTest
    static void testUserTierMultiplier_AllTiers() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        // 1-10 users = 1.0x
        System.assertEquals(1.0, hook.getUserTierMultiplier(1), '1 user should return 1.0x');
        System.assertEquals(1.0, hook.getUserTierMultiplier(10), '10 users should return 1.0x');

        // 11-50 users = 1.25x
        System.assertEquals(1.25, hook.getUserTierMultiplier(11), '11 users should return 1.25x');
        System.assertEquals(1.25, hook.getUserTierMultiplier(50), '50 users should return 1.25x');

        // 51-100 users = 1.5x
        System.assertEquals(1.5, hook.getUserTierMultiplier(51), '51 users should return 1.5x');
        System.assertEquals(1.5, hook.getUserTierMultiplier(100), '100 users should return 1.5x');

        // 101-250 users = 2.0x
        System.assertEquals(2.0, hook.getUserTierMultiplier(101), '101 users should return 2.0x');
        System.assertEquals(2.0, hook.getUserTierMultiplier(250), '250 users should return 2.0x');

        // 251-500 users = 2.5x
        System.assertEquals(2.5, hook.getUserTierMultiplier(251), '251 users should return 2.5x');
        System.assertEquals(2.5, hook.getUserTierMultiplier(500), '500 users should return 2.5x');

        // 501+ users = 3.0x
        System.assertEquals(3.0, hook.getUserTierMultiplier(501), '501 users should return 3.0x');
        System.assertEquals(3.0, hook.getUserTierMultiplier(10000), '10000 users should return 3.0x');
        Test.stopTest();
    }

    /**
     * @description Test user tier multiplier with null value
     */
    @isTest
    static void testUserTierMultiplier_Null() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal multiplier = hook.getUserTierMultiplier(null);
        Test.stopTest();

        System.assertEquals(1.0, multiplier, 'Null users should return default 1.0x');
    }

    /**
     * @description Test user tier multiplier with zero value
     */
    @isTest
    static void testUserTierMultiplier_Zero() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal multiplier = hook.getUserTierMultiplier(0);
        Test.stopTest();

        System.assertEquals(1.0, multiplier, 'Zero users should return default 1.0x');
    }

    /**
     * @description Test system type discount - Production
     */
    @isTest
    static void testSystemTypeDiscount_Production() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal discount = hook.getSystemTypeDiscount('Production');
        Test.stopTest();

        System.assertEquals(0.0, discount, 'Production should return 0% discount');
    }

    /**
     * @description Test system type discount - Staging
     */
    @isTest
    static void testSystemTypeDiscount_Staging() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal discount = hook.getSystemTypeDiscount('Staging');
        Test.stopTest();

        System.assertEquals(25.0, discount, 'Staging should return 25% discount');
    }

    /**
     * @description Test system type discount - Test
     */
    @isTest
    static void testSystemTypeDiscount_Test() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal discount = hook.getSystemTypeDiscount('Test');
        Test.stopTest();

        System.assertEquals(50.0, discount, 'Test should return 50% discount');
    }

    /**
     * @description Test system type discount - null value
     */
    @isTest
    static void testSystemTypeDiscount_Null() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal discount = hook.getSystemTypeDiscount(null);
        Test.stopTest();

        System.assertEquals(0.0, discount, 'Null system type should return 0% discount');
    }

    /**
     * @description Test system type discount - unknown value
     */
    @isTest
    static void testSystemTypeDiscount_Unknown() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Decimal discount = hook.getSystemTypeDiscount('Development');
        Test.stopTest();

        System.assertEquals(0.0, discount, 'Unknown system type should return 0% discount');
    }

    /**
     * @description Test combined pricing calculation scenario 1:
     *              P30 (1.5x) + 75 users (1.5x) + Production (0%) = 2.25x
     */
    @isTest
    static void testCombinedPricing_Scenario1() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Decimal listPrice = 10000;
        String pGroup = 'P30';
        Decimal users = 75;
        String systemType = 'Production';

        Test.startTest();
        Decimal pGroupMult = hook.getPGroupMultiplier(pGroup);
        Decimal userMult = hook.getUserTierMultiplier(users);
        Decimal discount = hook.getSystemTypeDiscount(systemType);

        // Combined: 1.5 * 1.5 * (1 - 0/100) = 2.25
        Decimal combinedMult = pGroupMult * userMult * (1 - discount / 100);
        Decimal adjustedPrice = listPrice * combinedMult;
        Test.stopTest();

        System.assertEquals(1.5, pGroupMult, 'P30 = 1.5x');
        System.assertEquals(1.5, userMult, '75 users = 1.5x');
        System.assertEquals(0.0, discount, 'Production = 0%');
        System.assertEquals(2.25, combinedMult, 'Combined = 2.25x');
        System.assertEquals(22500, adjustedPrice, 'Adjusted price = $22,500');
    }

    /**
     * @description Test combined pricing calculation scenario 2:
     *              P10 (0.75x) + 25 users (1.25x) + Test (50%) = 0.46875x
     */
    @isTest
    static void testCombinedPricing_Scenario2() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Decimal listPrice = 10000;
        String pGroup = 'P10';
        Decimal users = 25;
        String systemType = 'Test';

        Test.startTest();
        Decimal pGroupMult = hook.getPGroupMultiplier(pGroup);
        Decimal userMult = hook.getUserTierMultiplier(users);
        Decimal discount = hook.getSystemTypeDiscount(systemType);

        // Combined: 0.75 * 1.25 * (1 - 50/100) = 0.46875
        Decimal combinedMult = pGroupMult * userMult * (1 - discount / 100);
        Decimal adjustedPrice = listPrice * combinedMult;
        Test.stopTest();

        System.assertEquals(0.75, pGroupMult, 'P10 = 0.75x');
        System.assertEquals(1.25, userMult, '25 users = 1.25x');
        System.assertEquals(50.0, discount, 'Test = 50%');
        System.assertEquals(0.46875, combinedMult, 'Combined = 0.46875x');
        System.assertEquals(4687.50, adjustedPrice, 'Adjusted price = $4,687.50');
    }

    /**
     * @description Test that the prehook class can be instantiated
     *              Note: execute() method requires RevSignaling.TransactionRequest which
     *              is a managed class without public constructor - cannot be unit tested.
     *              The execute() method must be tested via integration testing.
     */
    @isTest
    static void testClassInstantiation() {
        Test.startTest();
        HardwareAttributePricingPrehook prehook = new HardwareAttributePricingPrehook();
        Test.stopTest();

        System.assertNotEquals(null, prehook, 'Prehook should be instantiated');
    }

    /**
     * @description Test that the prehook can be cast to the interface type
     *              This validates the interface implementation at compile-time
     */
    @isTest
    static void testInterfaceImplementation() {
        Test.startTest();
        // Create an instance and assign to interface type
        // This validates the interface implementation at compile-time
        RevSignaling.SignalingApexProcessor processor = new HardwareAttributePricingPrehook();
        Test.stopTest();

        System.assertNotEquals(null, processor, 'Should be assignable to interface type');
    }

    /**
     * @description Test that static multiplier maps are properly initialized
     */
    @isTest
    static void testStaticMapsInitialization() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        // Test pGroup multipliers through calculation
        Decimal p05Mult = hook.getPGroupMultiplier('P05');
        Decimal p50Mult = hook.getPGroupMultiplier('P50');

        // Test system type discounts
        Decimal prodDisc = hook.getSystemTypeDiscount('Production');
        Decimal testDisc = hook.getSystemTypeDiscount('Test');
        Test.stopTest();

        System.assertEquals(0.5, p05Mult, 'P05 multiplier should be 0.5');
        System.assertEquals(3.0, p50Mult, 'P50 multiplier should be 3.0');
        System.assertEquals(0.0, prodDisc, 'Production discount should be 0%');
        System.assertEquals(50.0, testDisc, 'Test discount should be 50%');
    }

    /**
     * @description Test processLineItem with no hardware reference - should skip (v2.0)
     */
    @isTest
    static void testProcessLineItem_NoHardware() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-001',
            'ListPrice' => 1000
            // No Hardware_Id__c
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line1' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>();

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, null);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no hardware reference');
    }

    /**
     * @description Test processLineItem with hardware attributes - should process (v2.0)
     */
    @isTest
    static void testProcessLineItem_WithHardware() {
        // Create Hardware__c record with attributes
        Hardware__c hw = createTestHardware('P30', 'Production', 75);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-001',
            'ListPrice' => 10000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line1' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update when hardware record found');
        System.assert(result.containsKey('nodePath'), 'Should have nodePath');
        System.assert(result.containsKey('attributes'), 'Should have attributes');
    }

    /**
     * @description Test processLineItem with no price - should skip (v2.0)
     */
    @isTest
    static void testProcessLineItem_NoPrice() {
        Hardware__c hw = createTestHardware('P30', 'Production', 75);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-001',
            'Hardware_Id__c' => hw.Id
            // No price
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line1' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, null);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no price');
    }

    /**
     * @description Test processLineItem with invalid hardware ID - should skip
     */
    @isTest
    static void testProcessLineItem_InvalidHardwareId() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-001',
            'ListPrice' => 10000,
            'Hardware_Id__c' => 'invalid-id'
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line1' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>();

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, null);
        Test.stopTest();

        // v3.0: Non-blank hardware ID triggers system defaults even if ID is invalid
        System.assertNotEquals(null, result, 'v3.0 applies system defaults when hardware ID is non-blank');
        System.assert(result.containsKey('attributes'), 'Should have attributes with system defaults');
    }

    /**
     * @description Test processLineItem with hardware ID not in map - should skip
     */
    @isTest
    static void testProcessLineItem_HardwareNotFound() {
        Hardware__c hw = createTestHardware('P30', 'Production', 75);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-001',
            'ListPrice' => 10000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line1' };
        // Empty map - hardware not found
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>();

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, null);
        Test.stopTest();

        // v3.0: Valid hardware ID triggers system defaults even if not in map
        System.assertNotEquals(null, result, 'v3.0 applies system defaults when hardware ID is valid but not in map');
        System.assert(result.containsKey('attributes'), 'Should have attributes with system defaults');
    }

    /**
     * @description Test queryHardwareRecords with empty set
     */
    @isTest
    static void testQueryHardwareRecords_Empty() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Map<Id, Hardware__c> result = hook.queryHardwareRecords(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty map for empty input');
    }

    /**
     * @description Test queryHardwareRecords with valid IDs
     */
    @isTest
    static void testQueryHardwareRecords_WithIds() {
        Hardware__c hw1 = createTestHardware('P30', 'Production', 75);
        Hardware__c hw2 = createTestHardware('P20', 'Staging', 25);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        Map<Id, Hardware__c> result = hook.queryHardwareRecords(new Set<Id>{ hw1.Id, hw2.Id });
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should return 2 hardware records');
        System.assertEquals('P30', result.get(hw1.Id).P_Group_List__c, 'First hardware should have P30');
        System.assertEquals('P20', result.get(hw2.Id).P_Group_List__c, 'Second hardware should have P20');
    }

    /**
     * @description Test edge case: boundary user counts (10, 11, 50, 51, etc.)
     */
    @isTest
    static void testUserTierMultiplier_Boundaries() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        // Exact boundaries
        System.assertEquals(1.0, hook.getUserTierMultiplier(10), '10 users = top of tier 1');
        System.assertEquals(1.25, hook.getUserTierMultiplier(11), '11 users = bottom of tier 2');
        System.assertEquals(1.25, hook.getUserTierMultiplier(50), '50 users = top of tier 2');
        System.assertEquals(1.5, hook.getUserTierMultiplier(51), '51 users = bottom of tier 3');
        System.assertEquals(1.5, hook.getUserTierMultiplier(100), '100 users = top of tier 3');
        System.assertEquals(2.0, hook.getUserTierMultiplier(101), '101 users = bottom of tier 4');
        System.assertEquals(2.0, hook.getUserTierMultiplier(250), '250 users = top of tier 4');
        System.assertEquals(2.5, hook.getUserTierMultiplier(251), '251 users = bottom of tier 5');
        System.assertEquals(2.5, hook.getUserTierMultiplier(500), '500 users = top of tier 5');
        System.assertEquals(3.0, hook.getUserTierMultiplier(501), '501 users = bottom of tier 6');
        Test.stopTest();
    }

    // =====================================================================
    // GROUP A: processLineItem() Branch Coverage
    // =====================================================================

    /**
     * @description Test processLineItem with User Override pGroup from configuredAttrs
     */
    @isTest
    static void testProcessLineItem_UserOverridePGroup() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-001',
            'ListPrice' => 10000,
            'Hardware_Id__c' => 'not-a-real-id-but-non-blank'
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line1' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>();
        Map<String, String> configuredAttrs = new Map<String, String>{
            'Pgroup' => 'P40'
        };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, configuredAttrs);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update with user override');
        List<Object> attrs = (List<Object>) result.get('attributes');
        // Find Hardware_Pricing_Source__c
        String dominantSource = findAttributeValue(attrs, 'Hardware_Pricing_Source__c');
        System.assertEquals('Configurator', dominantSource, 'SDD §8 Rule 5: Configurator override tier won');
        // Find pGroup_Applied__c
        String pGroupApplied = findAttributeValue(attrs, 'pGroup_Applied__c');
        System.assertEquals('P40', pGroupApplied, 'pGroup should be P40 from user override');
    }

    /**
     * @description SDD §8 Rule 5: Hardware_Pricing_Source__c must record which override tier won,
     *              using EXACTLY one of the three canonical values Configurator | Hardware Default |
     *              System Default — never the legacy 'User Override'. Covers all three tiers so the
     *              resolved tier is mapped (not hardcoded).
     */
    @isTest
    static void testProcessLineItem_sourceLabel_rule5_allTiers() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();
        List<Object> dataPath = new List<Object>{ 'ctx', 'quote', 'lineR5' };

        // Tier 1 — Configurator override present => 'Configurator'
        Map<String, Object> cfgTag = new Map<String, Object>{
            'ProductId' => 'PROD-R5-CFG', 'ListPrice' => 10000, 'Hardware_Id__c' => 'non-blank'
        };
        Map<String, Object> cfgResult = hook.processLineItem(
            cfgTag, dataPath, new Map<Id, Hardware__c>(), new Map<String, String>{ 'Pgroup' => 'P40' });
        System.assertEquals('Configurator',
            findAttributeValue((List<Object>) cfgResult.get('attributes'), 'Hardware_Pricing_Source__c'),
            'Configurator tier must stamp Configurator, not User Override');

        // Tier 2 — no configurator, hardware defaults present => 'Hardware Default'
        Hardware__c hw = createTestHardware('P30', 'Test', 100);
        Map<String, Object> hwTag = new Map<String, Object>{
            'ProductId' => 'PROD-R5-HW', 'ListPrice' => 8000, 'Hardware_Id__c' => hw.Id
        };
        Map<String, Object> hwResult = hook.processLineItem(
            hwTag, dataPath, new Map<Id, Hardware__c>{ hw.Id => hw }, new Map<String, String>());
        System.assertEquals('Hardware Default',
            findAttributeValue((List<Object>) hwResult.get('attributes'), 'Hardware_Pricing_Source__c'),
            'Hardware-defaults tier must stamp Hardware Default');

        // Tier 3 — hardware link present but record absent/empty => 'System Default'
        Map<String, Object> sysTag = new Map<String, Object>{
            'ProductId' => 'PROD-R5-SYS', 'ListPrice' => 5000, 'Hardware_Id__c' => 'non-blank'
        };
        Map<String, Object> sysResult = hook.processLineItem(
            sysTag, dataPath, new Map<Id, Hardware__c>(), new Map<String, String>());
        System.assertEquals('System Default',
            findAttributeValue((List<Object>) sysResult.get('attributes'), 'Hardware_Pricing_Source__c'),
            'System-defaults tier must stamp System Default');
    }

    /**
     * @description Test processLineItem with all 3 attributes from configuredAttrs
     */
    @isTest
    static void testProcessLineItem_UserOverrideAllAttributes() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-002',
            'ListPrice' => 5000,
            'Hardware_Id__c' => 'non-blank'
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line2' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>();
        Map<String, String> configuredAttrs = new Map<String, String>{
            'Pgroup' => 'P50',
            'Server_Type' => 'Staging',
            'Users' => '200'
        };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, configuredAttrs);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update');
        List<Object> attrs = (List<Object>) result.get('attributes');
        System.assertEquals('Configurator', findAttributeValue(attrs, 'Hardware_Pricing_Source__c'));
        System.assertEquals('P50', findAttributeValue(attrs, 'pGroup_Applied__c'));
        System.assertEquals('Staging', findAttributeValue(attrs, 'System_Type_Applied__c'));
        System.assertEquals(200, findAttributeDecimal(attrs, 'Users_Per_Partition_Applied__c'));
    }

    /**
     * @description Test processLineItem with Hardware Default fallback
     */
    @isTest
    static void testProcessLineItem_HardwareDefaultFallback() {
        Hardware__c hw = createTestHardware('P30', 'Test', 100);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-003',
            'ListPrice' => 8000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line3' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };
        // Empty configured attrs -> falls to Hardware Default
        Map<String, String> configuredAttrs = new Map<String, String>();

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, configuredAttrs);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update');
        List<Object> attrs = (List<Object>) result.get('attributes');
        System.assertEquals('Hardware Default', findAttributeValue(attrs, 'Hardware_Pricing_Source__c'));
        System.assertEquals('P30', findAttributeValue(attrs, 'pGroup_Applied__c'));
        System.assertEquals('Test', findAttributeValue(attrs, 'System_Type_Applied__c'));
    }

    /**
     * @description Test processLineItem with mixed sources: User pGroup + Hardware systemType + System default users
     */
    @isTest
    static void testProcessLineItem_MixedSources() {
        Hardware__c hw = createTestHardware(null, 'Staging', null);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-004',
            'ListPrice' => 6000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line4' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };
        Map<String, String> configuredAttrs = new Map<String, String>{
            'Pgroup' => 'P60'
            // No Server_Type or Users -> fall to hardware/system defaults
        };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, configuredAttrs);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update');
        List<Object> attrs = (List<Object>) result.get('attributes');
        // pGroup = Configurator, systemType = Hardware Default, users = System Default
        // Dominant should be Configurator (highest-priority tier present) per SDD §8 Rule 5
        System.assertEquals('Configurator', findAttributeValue(attrs, 'Hardware_Pricing_Source__c'));
        System.assertEquals('P60', findAttributeValue(attrs, 'pGroup_Applied__c'));
        System.assertEquals('Staging', findAttributeValue(attrs, 'System_Type_Applied__c'));
    }

    /**
     * @description Test processLineItem when configured Users value is non-numeric -> parse error fallback
     */
    @isTest
    static void testProcessLineItem_UsersParseFails() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-005',
            'ListPrice' => 3000,
            'Hardware_Id__c' => 'non-blank'
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line5' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>();
        Map<String, String> configuredAttrs = new Map<String, String>{
            'Users' => 'abc'
        };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, configuredAttrs);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update with parse fallback');
        List<Object> attrs = (List<Object>) result.get('attributes');
        // Users should fall to System Default (parse error) = 1
        System.assertEquals(1, findAttributeDecimal(attrs, 'Users_Per_Partition_Applied__c'));
    }

    /**
     * @description Test processLineItem uses UnitPrice when ListPrice not in tagMap
     */
    @isTest
    static void testProcessLineItem_UnitPriceFallback() {
        Hardware__c hw = createTestHardware('P20', 'Production', 1);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-006',
            'UnitPrice' => 7500,   // No ListPrice key
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line6' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, new Map<String, String>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should use UnitPrice when ListPrice absent');
        List<Object> attrs = (List<Object>) result.get('attributes');
        // P20=1.0, 1 user=1.0, Production=0% -> multiplier=1.0 -> price stays 7500
        Decimal preHwPrice = findAttributeDecimal(attrs, 'Pre_Hardware_Price__c');
        System.assertEquals(7500, preHwPrice, 'Pre_Hardware_Price should be 7500 from UnitPrice');
    }

    /**
     * @description Test processLineItem returns null when price is zero
     */
    @isTest
    static void testProcessLineItem_ZeroPrice() {
        Hardware__c hw = createTestHardware('P30', 'Production', 1);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-007',
            'ListPrice' => 0,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line7' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, new Map<String, String>());
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when price is zero');
    }

    /**
     * @description Test processLineItem with Staging system type -> 25% discount correctly applied
     */
    @isTest
    static void testProcessLineItem_StagingDiscount() {
        Hardware__c hw = createTestHardware('P20', 'Staging', 1);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-008',
            'ListPrice' => 10000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line8' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, new Map<String, String>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update');
        List<Object> attrs = (List<Object>) result.get('attributes');
        // P20=1.0, 1 user=1.0, Staging=25% -> multiplier = 1.0 * 1.0 * (1-0.25) = 0.75
        Decimal multiplier = findAttributeDecimal(attrs, 'Hardware_Price_Multiplier__c');
        System.assertEquals(0.75, multiplier, 'Combined multiplier should be 0.75 with Staging discount');
        Decimal adjustedPrice = findAttributeDecimal(attrs, 'UnitPrice');
        System.assertEquals(7500.00, adjustedPrice, 'Adjusted price should be 7500');
    }

    /**
     * @description Test processLineItem produces all 11 output attributes
     */
    @isTest
    static void testProcessLineItem_AllOutputAttributes() {
        Hardware__c hw = createTestHardware('P30', 'Production', 50);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-009',
            'ListPrice' => 10000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line9' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, new Map<String, String>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update');
        List<Object> attrs = (List<Object>) result.get('attributes');

        // Verify all 11 expected attributes are present
        Set<String> expectedNames = new Set<String>{
            'UnitPrice', 'Pre_Hardware_Price__c', 'Hardware_Price_Multiplier__c',
            'Hardware_Pricing_Applied__c', 'Hardware_Pricing_Source__c',
            'pGroup_Applied__c', 'System_Type_Applied__c', 'Users_Per_Partition_Applied__c',
            'Hardware_Pricing_Detail__c', 'HardwareCalculatedPrice__c', 'HardwarePricingExplainer__c'
        };

        Set<String> actualNames = new Set<String>();
        for (Object attrObj : attrs) {
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            actualNames.add((String) attr.get('attributeName'));
        }

        for (String expected : expectedNames) {
            System.assert(actualNames.contains(expected), 'Missing attribute: ' + expected);
        }
        System.assertEquals(11, attrs.size(), 'Should have exactly 11 attributes');
    }

    /**
     * @description Test processLineItem with empty dataPath -> updatePath is empty
     */
    @isTest
    static void testProcessLineItem_EmptyDataPath() {
        Hardware__c hw = createTestHardware('P20', 'Production', 1);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-010',
            'ListPrice' => 5000,
            'Hardware_Id__c' => hw.Id
        };
        // Empty dataPath
        List<Object> dataPath = new List<Object>();
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, new Map<String, String>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update even with empty dataPath');
        Map<String, Object> nodePath = (Map<String, Object>) result.get('nodePath');
        List<Object> updatePath = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(0, updatePath.size(), 'Update path should be empty');
    }

    // =====================================================================
    // GROUP B: Helper Method Tests (getStringFromTag, getDecimalFromTag, buildHardwareExplainerText)
    // =====================================================================

    /**
     * @description Test getStringFromTag with various input patterns
     */
    @isTest
    static void testGetStringFromTag_Variations() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();

        // Null map
        System.assertEquals(null, hook.getStringFromTag(null, 'key'), 'Null map should return null');

        // Missing key
        Map<String, Object> tagMap = new Map<String, Object>{ 'other' => 'value' };
        System.assertEquals(null, hook.getStringFromTag(tagMap, 'missing'), 'Missing key should return null');

        // Direct string value
        tagMap = new Map<String, Object>{ 'Name' => 'TestValue' };
        System.assertEquals('TestValue', hook.getStringFromTag(tagMap, 'Name'), 'Direct string should return as-is');

        // Nested {tagValue: x} structure (Revenue Cloud context format)
        Map<String, Object> nested = new Map<String, Object>{ 'tagValue' => 'NestedValue' };
        tagMap = new Map<String, Object>{ 'Attr' => nested };
        System.assertEquals('NestedValue', hook.getStringFromTag(tagMap, 'Attr'), 'Nested tagValue should be extracted');

        // Nested with null tagValue
        Map<String, Object> nestedNull = new Map<String, Object>{ 'tagValue' => null };
        tagMap = new Map<String, Object>{ 'Attr' => nestedNull };
        System.assertEquals(null, hook.getStringFromTag(tagMap, 'Attr'), 'Null nested tagValue should return null');

        // Direct null value
        tagMap = new Map<String, Object>{ 'Attr' => null };
        System.assertEquals(null, hook.getStringFromTag(tagMap, 'Attr'), 'Null value should return null');

        Test.stopTest();
    }

    /**
     * @description Test getDecimalFromTag with various input patterns
     */
    @isTest
    static void testGetDecimalFromTag_Variations() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();

        // Null map
        System.assertEquals(null, hook.getDecimalFromTag(null, 'key'), 'Null map should return null');

        // Missing key
        Map<String, Object> tagMap = new Map<String, Object>{ 'other' => 100 };
        System.assertEquals(null, hook.getDecimalFromTag(tagMap, 'missing'), 'Missing key should return null');

        // Direct numeric value
        tagMap = new Map<String, Object>{ 'Price' => 1500 };
        System.assertEquals(1500, hook.getDecimalFromTag(tagMap, 'Price'), 'Direct number should parse');

        // String numeric value
        tagMap = new Map<String, Object>{ 'Price' => '2500.50' };
        System.assertEquals(2500.50, hook.getDecimalFromTag(tagMap, 'Price'), 'String number should parse');

        // Nested {tagValue: x} numeric
        Map<String, Object> nested = new Map<String, Object>{ 'tagValue' => 3000 };
        tagMap = new Map<String, Object>{ 'Price' => nested };
        System.assertEquals(3000, hook.getDecimalFromTag(tagMap, 'Price'), 'Nested tagValue should parse');

        // Non-numeric string -> catch branch
        tagMap = new Map<String, Object>{ 'Price' => 'not-a-number' };
        System.assertEquals(null, hook.getDecimalFromTag(tagMap, 'Price'), 'Non-numeric should return null');

        // Null value
        tagMap = new Map<String, Object>{ 'Price' => null };
        System.assertEquals(null, hook.getDecimalFromTag(tagMap, 'Price'), 'Null value should return null');

        Test.stopTest();
    }

    /**
     * @description Test buildHardwareExplainerText with various scenarios
     */
    @isTest
    static void testBuildHardwareExplainerText_Scenarios() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();

        // Production system type (omitted from text) with non-1.0 multiplier
        String result1 = hook.buildHardwareExplainerText('P30', 'Production', 75, 2.25);
        System.assert(result1.contains('Group: P30'), 'Should contain pGroup');
        System.assert(!result1.contains('System:'), 'Production should NOT show System:');
        System.assert(result1.contains('75 Users'), 'Should contain user count');
        System.assert(result1.contains('Mult: 2.25'), 'Should contain multiplier');

        // Staging system type (included in text)
        String result2 = hook.buildHardwareExplainerText('P20', 'Staging', 10, 0.75);
        System.assert(result2.contains('System: Staging'), 'Staging should show System:');

        // Multiplier = 1.0 (omitted from text)
        String result3 = hook.buildHardwareExplainerText('P20', 'Production', 5, 1.0);
        System.assert(!result3.contains('Mult:'), 'Multiplier 1.0 should NOT show Mult:');

        // All empty/null -> fallback text
        String result4 = hook.buildHardwareExplainerText(null, null, null, null);
        System.assertEquals('Hardware Attribute Pricing Applied', result4, 'All null should return fallback');

        // Blank strings
        String result5 = hook.buildHardwareExplainerText('', '', 0, 1.0);
        System.assertEquals('Hardware Attribute Pricing Applied', result5, 'All blank/zero/1.0 should return fallback');

        Test.stopTest();
    }

    // =====================================================================
    // GROUP C: HardwarePricingDetail.toMap() Tests
    // =====================================================================

    /**
     * @description Test HardwarePricingDetail.toMap() with all fields populated
     */
    @isTest
    static void testHardwarePricingDetail_ToMap_Full() {
        HardwareAttributePricingPrehook.HardwarePricingDetail detail =
            new HardwareAttributePricingPrehook.HardwarePricingDetail();
        detail.pGroup = 'P30';
        detail.pGroupSource = 'Configurator';
        detail.model = 'MODEL-X';
        detail.systemType = 'Staging';
        detail.systemTypeSource = 'Hardware Default';
        detail.usersPerPartition = 75;
        detail.usersSource = 'System Default';
        detail.hardwareId = '001000000000001';
        detail.pGroupMultiplier = 1.5;
        detail.userTierMultiplier = 1.5;
        detail.systemTypeDiscount = 25.0;
        detail.combinedMultiplier = 1.6875;
        detail.listPrice = 10000;
        detail.hardwareAdjustedPrice = 16875;
        detail.source = 'Pre-Hook v3.0';
        detail.pricingTimestamp = Datetime.newInstanceGmt(2026, 3, 15, 12, 0, 0);

        Test.startTest();
        Map<String, Object> result = detail.toMap();
        Test.stopTest();

        System.assertEquals('v3.0', result.get('version'));
        System.assertEquals('001000000000001', result.get('hardwareId'));
        System.assertEquals('Pre-Hook v3.0', result.get('source'));
        System.assertNotEquals(null, result.get('pricingTimestamp'), 'Timestamp should be formatted');

        Map<String, Object> attrs = (Map<String, Object>) result.get('attributes');
        Map<String, Object> pGroupAttr = (Map<String, Object>) attrs.get('pGroup');
        System.assertEquals('P30', pGroupAttr.get('value'));
        System.assertEquals('Configurator', pGroupAttr.get('source'));

        Map<String, Object> multipliers = (Map<String, Object>) result.get('multipliers');
        System.assertEquals(1.5, multipliers.get('pGroupMultiplier'));
        System.assertEquals(1.6875, multipliers.get('combinedMultiplier'));

        Map<String, Object> priceCalc = (Map<String, Object>) result.get('priceCalculation');
        System.assertEquals(10000, priceCalc.get('listPrice'));
        System.assertEquals(16875, priceCalc.get('hardwareAdjustedPrice'));
    }

    /**
     * @description Test HardwarePricingDetail.toMap() with null pricingTimestamp
     */
    @isTest
    static void testHardwarePricingDetail_ToMap_NullTimestamp() {
        HardwareAttributePricingPrehook.HardwarePricingDetail detail =
            new HardwareAttributePricingPrehook.HardwarePricingDetail();
        detail.pGroup = 'P20';
        detail.pricingTimestamp = null;

        Test.startTest();
        Map<String, Object> result = detail.toMap();
        Test.stopTest();

        System.assertEquals(null, result.get('pricingTimestamp'), 'Null timestamp should remain null');
    }

    // =====================================================================
    // GROUP D: Additional processLineItem Edge Cases
    // =====================================================================

    /**
     * @description Test processLineItem with empty string values in configuredAttrs -> fall through to hardware
     */
    @isTest
    static void testProcessLineItem_ConfiguredAttrsEmptyStrings() {
        Hardware__c hw = createTestHardware('P40', 'Test', 200);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-011',
            'ListPrice' => 12000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line11' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };
        // Empty strings should fall through to hardware defaults
        Map<String, String> configuredAttrs = new Map<String, String>{
            'Pgroup' => '',
            'Server_Type' => '',
            'Users' => ''
        };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, configuredAttrs);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return update');
        List<Object> attrs = (List<Object>) result.get('attributes');
        System.assertEquals('Hardware Default', findAttributeValue(attrs, 'Hardware_Pricing_Source__c'));
        System.assertEquals('P40', findAttributeValue(attrs, 'pGroup_Applied__c'));
    }

    /**
     * @description Test processLineItem with tag values wrapped in {tagValue: x} maps (RC context format)
     */
    @isTest
    static void testProcessLineItem_NestedTagValues() {
        Hardware__c hw = createTestHardware('P30', 'Production', 50);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        // Simulate Revenue Cloud context format where values are nested in tagValue maps
        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => new Map<String, Object>{ 'tagValue' => 'PROD-012' },
            'ListPrice' => new Map<String, Object>{ 'tagValue' => 10000 },
            'Hardware_Id__c' => new Map<String, Object>{ 'tagValue' => String.valueOf(hw.Id) }
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line12' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, new Map<String, String>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should handle nested tagValue format');
        List<Object> attrs = (List<Object>) result.get('attributes');
        System.assertEquals('Hardware Default', findAttributeValue(attrs, 'Hardware_Pricing_Source__c'));
    }

    /**
     * @description Test processLineItem with null configuredAttrs (not empty map)
     */
    @isTest
    static void testProcessLineItem_NullConfiguredAttrs() {
        Hardware__c hw = createTestHardware('P20', 'Production', 25);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ProductId' => 'PROD-013',
            'ListPrice' => 4000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> dataPath = new List<Object>{ 'ctx1', 'quote1', 'line13' };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        // Pass null (not empty map) for configuredAttrs
        Map<String, Object> result = hook.processLineItem(tagMap, dataPath, hardwareMap, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should handle null configuredAttrs');
        List<Object> attrs = (List<Object>) result.get('attributes');
        // With null configuredAttrs and valid hardware, should use Hardware Default
        System.assertEquals('Hardware Default', findAttributeValue(attrs, 'Hardware_Pricing_Source__c'));
    }

    // =====================================================================
    // GROUP E: parseConfiguredAttributes() -- SalesTransactionItemAttribute parse
    // =====================================================================

    /**
     * @description Build a single SalesTransactionItemAttribute node in the queryTags shape:
     *              { tagValue: {Attribute, AttributeValue, ParentReference}, dataPath: [...] }
     */
    private static Map<String, Object> attrNode(
        String attrKey, String attrName, String attrValue, String parentRef, List<Object> dataPath
    ) {
        Map<String, Object> tagValues = new Map<String, Object>();
        if (attrKey != null) {
            tagValues.put(attrKey, attrName);
        }
        if (attrValue != null) {
            tagValues.put('AttributeValue', attrValue);
        }
        if (parentRef != null) {
            tagValues.put('ParentReference', parentRef);
        }
        return new Map<String, Object>{ 'tagValue' => tagValues, 'dataPath' => dataPath };
    }

    /**
     * @description parseConfiguredAttributes: ParentReference resolves the parent line id,
     *              and the 'Attribute' key is used for the attribute name. List-shaped response.
     */
    @isTest
    static void testParseConfiguredAttributes_ParentReferenceAndAttribute() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        List<Object> attrs = new List<Object>{
            attrNode('Attribute', 'Pgroup', 'P40', 'LINE-A', new List<Object>{ 'ctx', 'quote', 'LINE-A', 'attr1' }),
            attrNode('Attribute', 'Server_Type', 'Staging', 'LINE-A', new List<Object>{ 'ctx', 'quote', 'LINE-A', 'attr2' })
        };
        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SalesTransactionItemAttribute' => attrs }
        };

        Test.startTest();
        Map<String, Map<String, String>> result = hook.parseConfiguredAttributes(response);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'One parent line item should be present');
        Map<String, String> lineAttrs = result.get('LINE-A');
        System.assertNotEquals(null, lineAttrs, 'LINE-A attributes should be present');
        System.assertEquals('P40', lineAttrs.get('Pgroup'), 'Pgroup should map to P40');
        System.assertEquals('Staging', lineAttrs.get('Server_Type'), 'Server_Type should map to Staging');
    }

    /**
     * @description parseConfiguredAttributes: when ParentReference is blank, the parent id is
     *              derived from the second-to-last dataPath element. Direct (no queryResult wrapper).
     */
    @isTest
    static void testParseConfiguredAttributes_DataPathParent() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        // No ParentReference -> parent comes from dataPath[size-2] = 'LINE-B'
        List<Object> attrs = new List<Object>{
            attrNode('Attribute', 'Users', '200', null, new List<Object>{ 'ctx', 'quote', 'LINE-B', 'attrX' })
        };
        Map<String, Object> response = new Map<String, Object>{
            'SalesTransactionItemAttribute' => attrs
        };

        Test.startTest();
        Map<String, Map<String, String>> result = hook.parseConfiguredAttributes(response);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'One parent line should be derived from dataPath');
        System.assertEquals('200', result.get('LINE-B').get('Users'), 'Users should map to 200 under LINE-B');
    }

    /**
     * @description parseConfiguredAttributes: when 'Attribute' is blank/absent, falls back to
     *              'AttributeKeyName' for the attribute name. Single-object (not list) response shape.
     */
    @isTest
    static void testParseConfiguredAttributes_AttributeKeyNameFallback() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        // Use AttributeKeyName key instead of Attribute
        Map<String, Object> single = attrNode(
            'AttributeKeyName', 'Pgroup', 'P50', 'LINE-C', new List<Object>{ 'ctx', 'quote', 'LINE-C', 'attrY' }
        );
        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SalesTransactionItemAttribute' => single }
        };

        Test.startTest();
        Map<String, Map<String, String>> result = hook.parseConfiguredAttributes(response);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Single-object shape should be normalized to one entry');
        System.assertEquals('P50', result.get('LINE-C').get('Pgroup'),
            'AttributeKeyName fallback should populate Pgroup=P50');
    }

    /**
     * @description parseConfiguredAttributes: nodes that cannot resolve a parent (no ParentReference,
     *              dataPath too short) or lack name/value are skipped without error.
     */
    @isTest
    static void testParseConfiguredAttributes_SkippedNodes() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        List<Object> attrs = new List<Object>{
            // No parent reference, dataPath too short (<2) -> skipped
            attrNode('Attribute', 'Pgroup', 'P30', null, new List<Object>{ 'onlyOne' }),
            // Has parent but blank value -> skipped
            attrNode('Attribute', 'Server_Type', null, 'LINE-D', new List<Object>{ 'ctx', 'LINE-D', 'a' }),
            // Null node -> skipped
            null,
            // Non-map node -> skipped
            'not-a-map'
        };
        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SalesTransactionItemAttribute' => attrs }
        };

        Test.startTest();
        Map<String, Map<String, String>> result = hook.parseConfiguredAttributes(response);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'All nodes should be skipped -> empty result');
    }

    /**
     * @description parseConfiguredAttributes: defensive empty/null response shapes return empty map.
     */
    @isTest
    static void testParseConfiguredAttributes_EmptyResponses() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        // Null response
        System.assertEquals(0, hook.parseConfiguredAttributes(null).size(), 'Null response -> empty');
        // queryResult not a map
        System.assertEquals(0,
            hook.parseConfiguredAttributes(new Map<String, Object>{ 'queryResult' => 'x' }).size(),
            'Non-map queryResult -> empty');
        // No SalesTransactionItemAttribute key
        System.assertEquals(0,
            hook.parseConfiguredAttributes(new Map<String, Object>{ 'other' => 'y' }).size(),
            'No attribute key -> empty');
        // SalesTransactionItemAttribute present but null
        System.assertEquals(0,
            hook.parseConfiguredAttributes(
                new Map<String, Object>{ 'SalesTransactionItemAttribute' => null }).size(),
            'Null attribute value -> empty');
        Test.stopTest();
    }

    // =====================================================================
    // GROUP F: normalizeLineItems() -- queryTags response-shape handling
    // =====================================================================

    /**
     * @description normalizeLineItems: nested {queryResult:{SalesTransactionItem:[...]}} list shape.
     */
    @isTest
    static void testNormalizeLineItems_NestedList() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        List<Object> items = new List<Object>{
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'ProductId' => 'P1' } },
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'ProductId' => 'P2' } }
        };
        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SalesTransactionItem' => items }
        };

        Test.startTest();
        List<Object> result = hook.normalizeLineItems(response);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Nested list should normalize to a list');
        System.assertEquals(2, result.size(), 'Should return both items');
    }

    /**
     * @description normalizeLineItems: direct {SalesTransactionItem:{...}} single-object shape.
     */
    @isTest
    static void testNormalizeLineItems_DirectSingleObject() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        // Single object (not a list) at SalesTransactionItem, no queryResult wrapper
        Map<String, Object> response = new Map<String, Object>{
            'SalesTransactionItem' => new Map<String, Object>{
                'tagValue' => new Map<String, Object>{ 'ProductId' => 'P-single' }
            }
        };

        Test.startTest();
        List<Object> result = hook.normalizeLineItems(response);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Single object should be wrapped into a list');
        System.assertEquals(1, result.size(), 'Single object should yield a one-element list');
    }

    /**
     * @description normalizeLineItems: empty/invalid shapes return null (treated as 0 items).
     */
    @isTest
    static void testNormalizeLineItems_EmptyShapes() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        Test.startTest();
        // queryResult not a Map
        System.assertEquals(null,
            hook.normalizeLineItems(new Map<String, Object>{ 'queryResult' => 'not-a-map' }),
            'Non-map queryResult -> null');
        // No SalesTransactionItem key anywhere
        System.assertEquals(null,
            hook.normalizeLineItems(new Map<String, Object>{ 'unrelated' => 'x' }),
            'No SalesTransactionItem -> null');
        // queryResult is a Map but lacks SalesTransactionItem
        System.assertEquals(null,
            hook.normalizeLineItems(
                new Map<String, Object>{ 'queryResult' => new Map<String, Object>{ 'other' => 'y' } }),
            'queryResult without SalesTransactionItem -> null');
        Test.stopTest();
    }

    // =====================================================================
    // GROUP G: collectHardwareIds() + buildItemUpdates() -- the two-pass loop
    // =====================================================================

    /**
     * @description collectHardwareIds: extracts valid Hardware ids, skips blank and invalid ids,
     *              and handles both nested-tagValue and flat node shapes.
     */
    @isTest
    static void testCollectHardwareIds_ValidBlankAndInvalid() {
        Hardware__c hw = createTestHardware('P30', 'Production', 50);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        List<Object> items = new List<Object>{
            // Nested-tagValue node with valid hardware id
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'Hardware_Id__c' => hw.Id } },
            // Flat node (no tagValue wrapper) with valid hardware id (same id)
            new Map<String, Object>{ 'Hardware_Id__c' => hw.Id },
            // Blank hardware id -> skipped
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'Hardware_Id__c' => '' } },
            // Invalid hardware id -> Id.valueOf throws, caught & skipped
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'Hardware_Id__c' => 'not-an-id' } },
            // No hardware id key at all
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'ProductId' => 'P9' } }
        };

        Test.startTest();
        Set<Id> result = hook.collectHardwareIds(items);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Only the one valid (deduped) hardware id should be collected');
        System.assert(result.contains(hw.Id), 'Collected set should contain the valid hardware id');
    }

    /**
     * @description buildItemUpdates: end-to-end second pass. One line produces an update (valid
     *              hardware + price), one is skipped (no hardware, no configured attrs). Verifies
     *              configured-attribute lookup by line id (from dataPath last element).
     */
    @isTest
    static void testBuildItemUpdates_ProducesUpdatesAndSkips() {
        Hardware__c hw = createTestHardware('P30', 'Production', 50);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        // Line 1: valid hardware + price -> update built
        Map<String, Object> line1 = new Map<String, Object>{
            'tagValue' => new Map<String, Object>{
                'ProductId' => 'PROD-A',
                'ListPrice' => 10000,
                'Hardware_Id__c' => hw.Id
            },
            'dataPath' => new List<Object>{ 'ctx', 'quote', 'LINE-1' }
        };
        // Line 2: no hardware, no configured attrs -> skipped (null from processLineItem)
        Map<String, Object> line2 = new Map<String, Object>{
            'tagValue' => new Map<String, Object>{
                'ProductId' => 'PROD-B',
                'ListPrice' => 5000
            },
            'dataPath' => new List<Object>{ 'ctx', 'quote', 'LINE-2' }
        };
        List<Object> rawItems = new List<Object>{ line1, line2 };

        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };
        // Configured attrs keyed by line id (last dataPath element) -> LINE-1 gets a user override
        Map<String, Map<String, String>> configuredByLine = new Map<String, Map<String, String>>{
            'LINE-1' => new Map<String, String>{ 'Pgroup' => 'P60' }
        };

        Test.startTest();
        List<Map<String, Object>> updates = hook.buildItemUpdates(rawItems, configuredByLine, hardwareMap);
        Test.stopTest();

        System.assertEquals(1, updates.size(), 'Only line 1 should produce an update');
        List<Object> attrs = (List<Object>) updates[0].get('attributes');
        // LINE-1 had a configurator Pgroup of P60 -> dominant source = Configurator (SDD §8 Rule 5)
        System.assertEquals('Configurator', findAttributeValue(attrs, 'Hardware_Pricing_Source__c'),
            'Configured attribute lookup by line id should drive Configurator source');
        System.assertEquals('P60', findAttributeValue(attrs, 'pGroup_Applied__c'),
            'pGroup should be the configured P60');
    }

    /**
     * @description buildItemUpdates: flat node shape (no tagValue wrapper -> empty dataPath) still
     *              processes and builds an update when hardware + price are present.
     */
    @isTest
    static void testBuildItemUpdates_FlatNodeShape() {
        Hardware__c hw = createTestHardware('P20', 'Production', 1);

        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();

        // Flat node: tagMap is the node itself, dataPath becomes empty
        Map<String, Object> flat = new Map<String, Object>{
            'ProductId' => 'PROD-FLAT',
            'ListPrice' => 4000,
            'Hardware_Id__c' => hw.Id
        };
        List<Object> rawItems = new List<Object>{ flat };
        Map<Id, Hardware__c> hardwareMap = new Map<Id, Hardware__c>{ hw.Id => hw };

        Test.startTest();
        List<Map<String, Object>> updates = hook.buildItemUpdates(
            rawItems, new Map<String, Map<String, String>>(), hardwareMap
        );
        Test.stopTest();

        System.assertEquals(1, updates.size(), 'Flat node with hardware + price should produce an update');
        Map<String, Object> nodePath = (Map<String, Object>) updates[0].get('nodePath');
        List<Object> updatePath = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(0, updatePath.size(), 'Flat node -> empty dataPath -> empty updatePath');
    }

    // =====================================================================
    // GROUP H: submitContextUpdates() -- empty short-circuit + live-call catch
    // =====================================================================

    /**
     * @description submitContextUpdates: exercises the try/catch. With a real (unbound)
     *              IndustriesContext and a bogus context id, updateContextAttributes throws and
     *              is swallowed by the catch -- the method must not propagate the exception.
     */
    @isTest
    static void testSubmitContextUpdates_CatchOnBadContext() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();
        Context.IndustriesContext ctx = new Context.IndustriesContext();

        List<Map<String, Object>> updates = new List<Map<String, Object>>{
            new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => new List<Object>() },
                'attributes' => new List<Object>{
                    new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => 100 }
                }
            }
        };

        Test.startTest();
        Boolean threw = false;
        try {
            // Non-empty list against a bogus context id -> updateContextAttributes throws internally
            hook.submitContextUpdates(ctx, 'bogus-context-id', updates);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'submitContextUpdates must swallow context errors, not propagate them');
    }

    /**
     * @description submitContextUpdates: empty list still runs the try body without error.
     */
    @isTest
    static void testSubmitContextUpdates_EmptyList() {
        HardwareAttributePricingPrehook hook = new HardwareAttributePricingPrehook();
        Context.IndustriesContext ctx = new Context.IndustriesContext();

        Test.startTest();
        Boolean threw = false;
        try {
            hook.submitContextUpdates(ctx, 'bogus-context-id', new List<Map<String, Object>>());
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'Empty-list submit should not throw');
    }

    // =====================================================================
    // Helper methods for test assertions
    // =====================================================================

    /**
     * @description Find a string attribute value from the attributes list by name
     */
    private static String findAttributeValue(List<Object> attrs, String attributeName) {
        for (Object attrObj : attrs) {
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            if (attr.get('attributeName') == attributeName) {
                Object val = attr.get('attributeValue');
                return val != null ? String.valueOf(val) : null;
            }
        }
        return null;
    }

    /**
     * @description Find a decimal attribute value from the attributes list by name
     */
    private static Decimal findAttributeDecimal(List<Object> attrs, String attributeName) {
        for (Object attrObj : attrs) {
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            if (attr.get('attributeName') == attributeName) {
                Object val = attr.get('attributeValue');
                if (val instanceof Decimal) return (Decimal) val;
                if (val != null) return Decimal.valueOf(String.valueOf(val));
                return null;
            }
        }
        return null;
    }
}