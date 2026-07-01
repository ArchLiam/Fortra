/**
 * @description Test class for HardwarePreConfigInvocable
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-01
 */
@isTest
private class HardwarePreConfigInvocableTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account first (required for Hardware__c)
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        // Create test Hardware__c records (Name is auto-number, use Hardware_Name__c)
        // Status__c = 'Quoting' to avoid validation rule requiring Serial_Number__c for Active hardware
        Hardware__c hardware1 = new Hardware__c(
            Hardware_Name__c = 'Test Hardware P30',
            P_Group_List__c = 'P30',
            Server_Type__c = 'Production',
            Users_Per_Partition__c = 100,
            Status__c = 'Quoting',
            Account__c = testAccount.Id
        );
        insert hardware1;

        Hardware__c hardware2 = new Hardware__c(
            Hardware_Name__c = 'Test Hardware P05',
            P_Group_List__c = 'P05',
            Server_Type__c = 'Non-Production',
            Users_Per_Partition__c = 50,
            Status__c = 'Quoting',
            Account__c = testAccount.Id
        );
        insert hardware2;

        // Create test Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        // Create test Quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = testOpp.Id
        );
        insert testQuote;

        // Create test QuoteLineGroup with hardware
        QuoteLineGroup qlg1 = new QuoteLineGroup(
            Name = 'Test Group with Hardware',
            QuoteId = testQuote.Id,
            Hardware__c = hardware1.Id
        );
        insert qlg1;

        // Create test QuoteLineGroup without hardware
        QuoteLineGroup qlg2 = new QuoteLineGroup(
            Name = 'Test Group without Hardware',
            QuoteId = testQuote.Id
        );
        insert qlg2;
    }

    @isTest
    static void testGetHardwareAttributes_ByHardwareId() {
        Hardware__c hardware = [SELECT Id FROM Hardware__c WHERE Hardware_Name__c = 'Test Hardware P30' LIMIT 1];

        HardwarePreConfigInvocable.HardwareAttributeRequest request =
            new HardwarePreConfigInvocable.HardwareAttributeRequest();
        request.hardwareId = hardware.Id;

        Test.startTest();
        List<HardwarePreConfigInvocable.HardwareAttributeResult> results =
            HardwarePreConfigInvocable.getHardwareAttributes(
                new List<HardwarePreConfigInvocable.HardwareAttributeRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        HardwarePreConfigInvocable.HardwareAttributeResult result = results[0];

        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(true, result.hasHardware, 'Should have hardware');
        System.assertEquals('P30', result.pGroupValue, 'pGroup should be P30');
        System.assertEquals('P30', result.pGroupRawValue, 'Raw pGroup should be P30');
        System.assertEquals('Production', result.serverType, 'Server type should be Production');
        System.assertEquals(100, result.usersPerPartition, 'Users should be 100');
        System.assertNotEquals(null, result.hardwareDisplayText, 'Display text should not be null');
        System.assertNotEquals(null, result.jsonContext, 'JSON context should not be null');
    }

    @isTest
    static void testGetHardwareAttributes_ByQuoteLineGroupId() {
        QuoteLineGroup qlg = [
            SELECT Id, Hardware__c
            FROM QuoteLineGroup
            WHERE Name = 'Test Group with Hardware'
            LIMIT 1
        ];

        HardwarePreConfigInvocable.HardwareAttributeRequest request =
            new HardwarePreConfigInvocable.HardwareAttributeRequest();
        request.quoteLineGroupId = qlg.Id;

        Test.startTest();
        List<HardwarePreConfigInvocable.HardwareAttributeResult> results =
            HardwarePreConfigInvocable.getHardwareAttributes(
                new List<HardwarePreConfigInvocable.HardwareAttributeRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        HardwarePreConfigInvocable.HardwareAttributeResult result = results[0];

        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(true, result.hasHardware, 'Should have hardware');
        System.assertEquals('P30', result.pGroupValue, 'pGroup should be P30');
    }

    @isTest
    static void testGetHardwareAttributes_ByQuoteId() {
        Quote quote = [SELECT Id FROM Quote WHERE Name = 'Test Quote' LIMIT 1];

        HardwarePreConfigInvocable.HardwareAttributeRequest request =
            new HardwarePreConfigInvocable.HardwareAttributeRequest();
        request.quoteId = quote.Id;

        Test.startTest();
        List<HardwarePreConfigInvocable.HardwareAttributeResult> results =
            HardwarePreConfigInvocable.getHardwareAttributes(
                new List<HardwarePreConfigInvocable.HardwareAttributeRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        HardwarePreConfigInvocable.HardwareAttributeResult result = results[0];

        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(true, result.hasHardware, 'Should have hardware from first group');
    }

    @isTest
    static void testGetHardwareAttributes_NoHardware() {
        QuoteLineGroup qlg = [
            SELECT Id
            FROM QuoteLineGroup
            WHERE Name = 'Test Group without Hardware'
            LIMIT 1
        ];

        HardwarePreConfigInvocable.HardwareAttributeRequest request =
            new HardwarePreConfigInvocable.HardwareAttributeRequest();
        request.quoteLineGroupId = qlg.Id;

        Test.startTest();
        List<HardwarePreConfigInvocable.HardwareAttributeResult> results =
            HardwarePreConfigInvocable.getHardwareAttributes(
                new List<HardwarePreConfigInvocable.HardwareAttributeRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        HardwarePreConfigInvocable.HardwareAttributeResult result = results[0];

        System.assertEquals(true, result.success, 'Should succeed even without hardware');
        System.assertEquals(false, result.hasHardware, 'Should not have hardware');
        System.assertEquals('No hardware selected', result.hardwareDisplayText, 'Should show no hardware message');
    }

    @isTest
    static void testGetHardwareAttributes_NullInput() {
        HardwarePreConfigInvocable.HardwareAttributeRequest request =
            new HardwarePreConfigInvocable.HardwareAttributeRequest();
        // All fields are null

        Test.startTest();
        List<HardwarePreConfigInvocable.HardwareAttributeResult> results =
            HardwarePreConfigInvocable.getHardwareAttributes(
                new List<HardwarePreConfigInvocable.HardwareAttributeRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        HardwarePreConfigInvocable.HardwareAttributeResult result = results[0];

        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(false, result.hasHardware, 'Should not have hardware');
    }

    @isTest
    static void testNormalizePGroupValue() {
        // Test P05 → P5 conversion
        System.assertEquals('P5', HardwarePreConfigInvocable.normalizePGroupValue('P05'),
            'P05 should normalize to P5');

        // Test other values pass through unchanged
        System.assertEquals('P10', HardwarePreConfigInvocable.normalizePGroupValue('P10'),
            'P10 should remain P10');
        System.assertEquals('P30', HardwarePreConfigInvocable.normalizePGroupValue('P30'),
            'P30 should remain P30');
        System.assertEquals('P60', HardwarePreConfigInvocable.normalizePGroupValue('P60'),
            'P60 should remain P60');

        // Test null/blank handling
        System.assertEquals(null, HardwarePreConfigInvocable.normalizePGroupValue(null),
            'Null should return null');
        System.assertEquals(null, HardwarePreConfigInvocable.normalizePGroupValue(''),
            'Empty string should return null');
    }

    @isTest
    static void testP05Normalization() {
        Hardware__c hardware = [SELECT Id FROM Hardware__c WHERE Hardware_Name__c = 'Test Hardware P05' LIMIT 1];

        HardwarePreConfigInvocable.HardwareAttributeRequest request =
            new HardwarePreConfigInvocable.HardwareAttributeRequest();
        request.hardwareId = hardware.Id;

        Test.startTest();
        List<HardwarePreConfigInvocable.HardwareAttributeResult> results =
            HardwarePreConfigInvocable.getHardwareAttributes(
                new List<HardwarePreConfigInvocable.HardwareAttributeRequest>{ request }
            );
        Test.stopTest();

        HardwarePreConfigInvocable.HardwareAttributeResult result = results[0];

        System.assertEquals('P05', result.pGroupRawValue, 'Raw value should be P05');
        System.assertEquals('P5', result.pGroupValue, 'Normalized value should be P5');
    }

    @isTest
    static void testGetHardwareAttributesForLWC() {
        QuoteLineGroup qlg = [
            SELECT Id
            FROM QuoteLineGroup
            WHERE Name = 'Test Group with Hardware'
            LIMIT 1
        ];

        Test.startTest();
        Map<String, Object> result = HardwarePreConfigInvocable.getHardwareAttributesForLWC(qlg.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        System.assertEquals(true, result.get('hasHardware'), 'Should have hardware');
        System.assertEquals('P30', result.get('pGroupValue'), 'pGroup should be P30');
        System.assertEquals('Production', result.get('serverType'), 'Server type should be Production');
        System.assertEquals(100.0, result.get('usersPerPartition'), 'Users should be 100');
    }

    @isTest
    static void testGetHardwareAttributesForQuote() {
        Quote quote = [SELECT Id FROM Quote WHERE Name = 'Test Quote' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = HardwarePreConfigInvocable.getHardwareAttributesForQuote(quote.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        System.assertEquals(true, result.get('hasHardware'), 'Should have hardware');
    }

    @isTest
    static void testJsonContextStructure() {
        Hardware__c hardware = [SELECT Id FROM Hardware__c WHERE Hardware_Name__c = 'Test Hardware P30' LIMIT 1];

        HardwarePreConfigInvocable.HardwareAttributeRequest request =
            new HardwarePreConfigInvocable.HardwareAttributeRequest();
        request.hardwareId = hardware.Id;

        Test.startTest();
        List<HardwarePreConfigInvocable.HardwareAttributeResult> results =
            HardwarePreConfigInvocable.getHardwareAttributes(
                new List<HardwarePreConfigInvocable.HardwareAttributeRequest>{ request }
            );
        Test.stopTest();

        String jsonContext = results[0].jsonContext;
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonContext);

        System.assertEquals(true, parsed.get('hasHardware'), 'JSON should indicate hasHardware');
        System.assertEquals(true, parsed.get('showWarningsOnChange'), 'JSON should have showWarningsOnChange');

        Map<String, Object> defaults = (Map<String, Object>) parsed.get('hardwareDefaults');
        System.assertNotEquals(null, defaults, 'Should have hardwareDefaults');
        System.assertEquals('P30', defaults.get('pGroup'), 'Defaults should have pGroup');
        System.assertEquals('Production', defaults.get('serverType'), 'Defaults should have serverType');
    }
}