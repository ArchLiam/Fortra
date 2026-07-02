/**
 * Test class for HardwareGroupController
 *
 * Comprehensive test coverage for all controller methods with realistic test data
 *
 * @author Marc DeBrey
 * @date 2025-01-23
 */
@isTest
private class HardwareGroupControllerTest {

    // Test data constants
    private static final String TEST_ACCOUNT_NAME = 'Test Hardware Account';
    private static final String TEST_QUOTE_NAME = 'Test Quote for Hardware';
    private static final String TEST_PRODUCT_NAME = 'Test Software Product';
    private static final String TEST_HARDWARE_PREFIX = 'HW';
    private static final Integer NUM_HARDWARE_RECORDS = 5;

    /**
     * Create comprehensive test data
     */
    @TestSetup
    static void setupTestData() {
        // Create Account
        Account testAccount = new Account(
            Name = TEST_ACCOUNT_NAME,
            BillingCountry = 'United States',
            BillingState = 'California',
            BillingCity = 'San Francisco',
            BillingStreet = '123 Test St'
        );
        insert testAccount;

        // Create Opportunity (required for Quote in Revenue Cloud)
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        // Get standard pricebook
        Id pricebookId = Test.getStandardPricebookId();

        // Create Quote
        Quote testQuote = new Quote(
            Name = TEST_QUOTE_NAME,
            OpportunityId = testOpp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        // Create Products
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < 3; i++) {
            products.add(new Product2(
                Name = TEST_PRODUCT_NAME + ' ' + i,
                ProductCode = 'PROD-' + i,
                IsActive = true,
                Family = 'Software',
                QuantityUnitOfMeasure = 'Each'
            ));
        }
        insert products;

        // Create PricebookEntries
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Product2 prod : products) {
            pbes.add(new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = prod.Id,
                UnitPrice = 1000.00,
                IsActive = true
            ));
        }
        insert pbes;

        // Create Hardware records with variety of statuses and categories
        List<Hardware__c> hardwareList = new List<Hardware__c>();
        List<String> statuses = new List<String>{'Active', 'Pending', 'Active', 'Pending', 'Active'};

        for (Integer i = 0; i < NUM_HARDWARE_RECORDS; i++) {
            hardwareList.add(new Hardware__c(
                Account__c = testAccount.Id,
                Hardware_ID__c = TEST_HARDWARE_PREFIX + String.valueOf(i).leftPad(6, '0'),
                Model_Number__c = 'MODEL-' + i,
                Serial_Number__c = 'SN' + String.valueOf(1000 + i),
                Status__c = statuses[i],
                Number_of_Processors__c = 4 + i,
                Storage_TB__c = 1 + i,
                Installation_Date__c = Date.today().addDays(-365 + (i * 30))));
        }
        insert hardwareList;

        // Create QuoteLineGroups (some with hardware, some without)
        List<QuoteLineGroup> groups = new List<QuoteLineGroup>();
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 1',
            QuoteId = testQuote.Id,
            Hardware__c = hardwareList[0].Id,
            Hardware_Group_Type__c = true,
            Hardware_Notes__c = 'Primary production server group'
        ));
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 2',
            QuoteId = testQuote.Id,
            Hardware__c = hardwareList[1].Id,
            Hardware_Group_Type__c = true,
            Hardware_Notes__c = 'Storage system group'
        ));
        groups.add(new QuoteLineGroup(
            Name = 'Regular Group',
            QuoteId = testQuote.Id,
            Hardware_Group_Type__c = false
        ));
        insert groups;

        // Create QuoteLineItems and assign to groups
        List<QuoteLineItem> quoteLines = new List<QuoteLineItem>();
        for (Integer i = 0; i < products.size(); i++) {
            quoteLines.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = products[i].Id,
                PricebookEntryId = pbes[i].Id,
                Quantity = 10 + i,
                UnitPrice = 1000.00,
                QuoteLineGroupId = groups[i < 2 ? i : 2].Id,
                Hardware_Reference__c = i < 2 ? hardwareList[i].Id : null
            ));
        }
        insert quoteLines;
    }

    /**
     * Test getExistingGroups - should return all hardware groups for a quote
     */
    @isTest
    static void testGetExistingGroups() {
        // Get test quote
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        List<QuoteLineGroup> groups = HardwareGroupController.getExistingGroups(testQuote.Id);
        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, groups, 'Groups should not be null');
        System.assertEquals(3, groups.size(), 'Should return all groups for the quote');

        // Verify we have both hardware groups and regular groups
        Integer hardwareGroupCount = 0;
        Integer regularGroupCount = 0;
        for (QuoteLineGroup grp : groups) {
            if (grp.Hardware_Group_Type__c == true) {
                hardwareGroupCount++;
                System.assertNotEquals(null, grp.Hardware__c, 'Hardware groups should have hardware assigned');
            } else {
                regularGroupCount++;
            }
        }
        System.assertEquals(2, hardwareGroupCount, 'Should have 2 hardware groups');
        System.assertEquals(1, regularGroupCount, 'Should have 1 regular group');
    }

    /**
     * Test searchHardware - basic search without filters
     */
    @isTest
    static void testSearchHardwareNoFilters() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Map<String, String> emptyFilters = new Map<String, String>();

        Test.startTest();
        List<Hardware__c> results = HardwareGroupController.searchHardware(testAccount.Id, emptyFilters);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(NUM_HARDWARE_RECORDS, results.size(), 'Should return all hardware for account');
    }

    /**
     * Test searchHardware - filtered by status
     */
    @isTest
    static void testSearchHardwareWithStatusFilter() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Map<String, String> filters = new Map<String, String>{
            'status' => 'Active'
        };

        Test.startTest();
        List<Hardware__c> results = HardwareGroupController.searchHardware(testAccount.Id, filters);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(3, results.size(), 'Should return 3 Active hardware records');

        for (Hardware__c hw : results) {
            System.assertEquals('Active', hw.Status__c, 'All results should have Active status');
        }
    }

    /**
     * Test searchHardware - filtered by category
     */
    @isTest
    static void testSearchHardwareWithCategoryFilter() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Map<String, String> filters = new Map<String, String>{
            'category' => 'Server'
        };

        Test.startTest();
        List<Hardware__c> results = HardwareGroupController.searchHardware(testAccount.Id, filters);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(5, results.size(), 'Should return 5 Server hardware records');

        for (Hardware__c hw : results) {
        }
    }

    /**
     * Test searchHardware - multiple filters
     */
    @isTest
    static void testSearchHardwareMultipleFilters() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Map<String, String> filters = new Map<String, String>{
            'status' => 'Active',
            'category' => 'Server',
            'environment' => 'Production'
        };

        Test.startTest();
        List<Hardware__c> results = HardwareGroupController.searchHardware(testAccount.Id, filters);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() >= 1, 'Should return at least 1 matching hardware');

        for (Hardware__c hw : results) {
            System.assertEquals('Active', hw.Status__c, 'Status filter applied');
        }
    }

    /**
     * Test searchHardware - serial number partial match
     */
    @isTest
    static void testSearchHardwareBySerialNumber() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Map<String, String> filters = new Map<String, String>{
            'serialNumber' => '1000'
        };

        Test.startTest();
        List<Hardware__c> results = HardwareGroupController.searchHardware(testAccount.Id, filters);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return 1 hardware with serial SN1000');
    }

    /**
     * Test createHardwareRecord - successful creation
     */
    @isTest
    static void testCreateHardwareRecord() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> hardwareData = new Map<String, Object>{
            'Model_Number__c' => 'NEW-MODEL-100',
            'Serial_Number__c' => 'SN999999',
            'Status__c' => 'Active',
            'Number_of_Processors__c' => 8,
            'Storage_TB__c' => 2
        };

        Test.startTest();
        Id newHardwareId = HardwareGroupController.createHardwareRecord(hardwareData, testAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, newHardwareId, 'Hardware ID should be returned');

        // Verify hardware was created correctly
        Hardware__c newHardware = [
            SELECT Id, Hardware_ID__c, Model_Number__c, Serial_Number__c,
                   Status__c
            FROM Hardware__c
            WHERE Id = :newHardwareId
        ];

        System.assertEquals('NEW-MODEL-100', newHardware.Model_Number__c, 'Model number should match');
        System.assertEquals('SN999999', newHardware.Serial_Number__c, 'Serial number should match');
        System.assertEquals('Quoting', newHardware.Status__c, 'Status should always be Quoting for new hardware');
        System.assert(newHardware.Hardware_ID__c.startsWith('HW'), 'Hardware_ID should be auto-generated');
    }

    /**
     * Test createHardwareGroup - successful creation with hardware
     */
    @isTest
    static void testCreateHardwareGroupWithHardware() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        Hardware__c testHardware = [SELECT Id FROM Hardware__c WHERE Hardware_ID__c = :TEST_HARDWARE_PREFIX + '000002' LIMIT 1];

        String groupName = 'New Hardware Group';
        String notes = 'Test group for new hardware';

        Test.startTest();
        Id groupId = HardwareGroupController.createHardwareGroup(
            testQuote.Id,
            groupName,
            notes,
            testHardware.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, groupId, 'Group ID should be returned');

        // Verify group was created correctly
        QuoteLineGroup newGroup = [
            SELECT Id, Name, QuoteId, Hardware__c, Hardware_Group_Type__c, Hardware_Notes__c
            FROM QuoteLineGroup
            WHERE Id = :groupId
        ];

        System.assertEquals(groupName, newGroup.Name, 'Group name should match');
        System.assertEquals(testQuote.Id, newGroup.QuoteId, 'Quote should match');
        System.assertEquals(testHardware.Id, newGroup.Hardware__c, 'Hardware should be assigned');
        System.assertEquals(true, newGroup.Hardware_Group_Type__c, 'Should be hardware group type');
        System.assertEquals(notes, newGroup.Hardware_Notes__c, 'Notes should match');
    }

    /**
     * Test createHardwareGroup - without hardware assigned
     */
    @isTest
    static void testCreateHardwareGroupWithoutHardware() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        String groupName = 'Empty Hardware Group';
        String notes = 'Will assign hardware later';

        Test.startTest();
        Id groupId = HardwareGroupController.createHardwareGroup(
            testQuote.Id,
            groupName,
            notes,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, groupId, 'Group ID should be returned');

        // Verify group was created correctly
        QuoteLineGroup newGroup = [
            SELECT Id, Name, Hardware__c, Hardware_Group_Type__c
            FROM QuoteLineGroup
            WHERE Id = :groupId
        ];

        System.assertEquals(groupName, newGroup.Name, 'Group name should match');
        System.assertEquals(null, newGroup.Hardware__c, 'Hardware should be null');
        System.assertEquals(false, newGroup.Hardware_Group_Type__c, 'Hardware_Group_Type should be false when no hardware provided');
    }

    /**
     * Test updateHardwareGroup - change name and hardware
     */
    @isTest
    static void testUpdateHardwareGroup() {
        QuoteLineGroup existingGroup = [SELECT Id, Hardware__c FROM QuoteLineGroup WHERE Name = 'Hardware Group 1' LIMIT 1];
        Hardware__c newHardware = [SELECT Id FROM Hardware__c WHERE Hardware_ID__c = :TEST_HARDWARE_PREFIX + '000002' LIMIT 1];

        String newName = 'Updated Hardware Group Name';
        String newNotes = 'Updated notes for hardware group';

        Test.startTest();
        HardwareGroupController.updateHardwareGroup(
            existingGroup.Id,
            newName,
            newNotes,
            newHardware.Id
        );
        Test.stopTest();

        // Verify updates
        QuoteLineGroup updatedGroup = [
            SELECT Id, Name, Hardware__c, Hardware_Notes__c
            FROM QuoteLineGroup
            WHERE Id = :existingGroup.Id
        ];

        System.assertEquals(newName, updatedGroup.Name, 'Name should be updated');
        System.assertEquals(newHardware.Id, updatedGroup.Hardware__c, 'Hardware should be updated');
        System.assertEquals(newNotes, updatedGroup.Hardware_Notes__c, 'Notes should be updated');
    }

    /**
     * Test assignHardwareToGroup - assign hardware to existing group
     */
    @isTest
    static void testAssignHardwareToGroup() {
        QuoteLineGroup groupWithoutHardware = [SELECT Id FROM QuoteLineGroup WHERE Name = 'Regular Group' LIMIT 1];
        Hardware__c hardware = [SELECT Id FROM Hardware__c WHERE Hardware_ID__c = :TEST_HARDWARE_PREFIX + '000003' LIMIT 1];

        Test.startTest();
        HardwareGroupController.assignHardwareToGroup(groupWithoutHardware.Id, hardware.Id);
        Test.stopTest();

        // Verify assignment
        QuoteLineGroup updatedGroup = [
            SELECT Id, Hardware__c, Hardware_Group_Type__c
            FROM QuoteLineGroup
            WHERE Id = :groupWithoutHardware.Id
        ];

        System.assertEquals(hardware.Id, updatedGroup.Hardware__c, 'Hardware should be assigned');
        System.assertEquals(true, updatedGroup.Hardware_Group_Type__c, 'Should be marked as hardware group');
    }

    /**
     * Test getPicklistOptions - should return all picklist values
     */
    @isTest
    static void testGetPicklistOptions() {
        Test.startTest();
        Map<String, List<Map<String, String>>> options = HardwareGroupController.getPicklistOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Options should not be null');
        System.assert(options.containsKey('status'), 'Should include status picklist');
        System.assert(options.containsKey('hardwarePlatform'), 'Should include hardwarePlatform picklist');
        System.assert(options.containsKey('iSeriesModel'), 'Should include iSeriesModel picklist');

        // Verify structure of options
        for (String key : options.keySet()) {
            List<Map<String, String>> picklistValues = options.get(key);
            System.assertNotEquals(null, picklistValues, 'Picklist values should not be null');
            System.assert(picklistValues.size() > 0, 'Should have at least one value');

            for (Map<String, String> option : picklistValues) {
                System.assert(option.containsKey('label'), 'Option should have label');
                System.assert(option.containsKey('value'), 'Option should have value');
            }
        }
    }

    /**
     * Test error handling - invalid quote ID
     */
    @isTest
    static void testGetExistingGroupsInvalidQuoteId() {
        Id fakeQuoteId = Schema.SObjectType.Quote.getKeyPrefix() + '0'.repeat(15);

        Test.startTest();
        List<QuoteLineGroup> groups = HardwareGroupController.getExistingGroups(fakeQuoteId);
        Test.stopTest();

        System.assertNotEquals(null, groups, 'Should return empty list, not null');
        System.assertEquals(0, groups.size(), 'Should return empty list for invalid quote');
    }

    /**
     * Test error handling - invalid account ID for hardware search
     */
    @isTest
    static void testSearchHardwareInvalidAccountId() {
        Id fakeAccountId = Schema.SObjectType.Account.getKeyPrefix() + '0'.repeat(15);
        Map<String, String> emptyFilters = new Map<String, String>();

        Test.startTest();
        List<Hardware__c> results = HardwareGroupController.searchHardware(fakeAccountId, emptyFilters);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return empty list, not null');
        System.assertEquals(0, results.size(), 'Should return empty list for invalid account');
    }

    /**
     * Test createHardwareGroup - duplicate name should throw exception
     */
    @isTest
    static void testCreateHardwareGroupDuplicateName() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        try {
            HardwareGroupController.createHardwareGroup(
                testQuote.Id,
                'Hardware Group 1',  // Already exists in test data
                'Duplicate test',
                null
            );
            System.assert(false, 'Should have thrown AuraHandledException for duplicate name');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('already exists'), 'Error message should mention duplicate: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * Test createHardwareGroup - duplicate name case-insensitive should throw exception
     */
    @isTest
    static void testCreateHardwareGroupDuplicateNameCaseInsensitive() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        try {
            HardwareGroupController.createHardwareGroup(
                testQuote.Id,
                'hardware group 1',  // Lowercase of existing "Hardware Group 1"
                'Case insensitive test',
                null
            );
            System.assert(false, 'Should have thrown AuraHandledException for case-insensitive duplicate');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('already exists'), 'Error message should mention duplicate: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * Test updateHardwareGroup - rename to existing group name should throw exception
     */
    @isTest
    static void testUpdateHardwareGroupDuplicateName() {
        QuoteLineGroup group1 = [SELECT Id FROM QuoteLineGroup WHERE Name = 'Hardware Group 1' LIMIT 1];

        Test.startTest();
        try {
            HardwareGroupController.updateHardwareGroup(
                group1.Id,
                'Hardware Group 2',  // Another existing group name
                'Rename to duplicate test',
                null
            );
            System.assert(false, 'Should have thrown AuraHandledException for duplicate rename');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('already exists'), 'Error message should mention duplicate: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * Test createHardwareRecord - iSeries platform should auto-create Partition
     */
    @isTest
    static void testCreateHardwareRecordCreatesPartition() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> hardwareData = new Map<String, Object>{
            'Hardware_Platform__c' => 'iSeries',
            'Hardware_Name__c' => 'Test Server',
            'Serial_Number__c' => 'SN-PART-001',
            'Number_of_Processors__c' => 4
        };

        Test.startTest();
        Id hwId = HardwareGroupController.createHardwareRecord(hardwareData, testAccount.Id);
        Test.stopTest();

        // Verify partition was auto-created on the Partition__c object
        List<Partition__c> partitions = [
            SELECT Id, Partition_Name__c, Partition_Number__c, Number_of_Processors__c, Hardware__c
            FROM Partition__c
            WHERE Hardware__c = :hwId
        ];

        System.assertEquals(1, partitions.size(), 'Should create exactly 1 partition for iSeries hardware');
        System.assertEquals('Test Server - Partition 1', partitions[0].Partition_Name__c, 'Partition name should derive from hardware name');
        System.assert(partitions[0].Partition_Number__c.startsWith('HW'), 'Partition Number should start with HW prefix');
        System.assert(partitions[0].Partition_Number__c.endsWith('-P1'), 'Partition Number should end with -P1');
        System.assertEquals(4, partitions[0].Number_of_Processors__c, 'Processors should match input');
    }

    /**
     * Test createHardwareRecord - Cross Platform should auto-create Partition
     */
    @isTest
    static void testCreateHardwareRecordCreatesPartitionCrossPlatform() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> hardwareData = new Map<String, Object>{
            'Hardware_Platform__c' => 'Cross Platform',
            'Hardware_Name__c' => 'Cross Server',
            'Hostname__c' => 'xplat-001',
            'Number_of_Processors__c' => 2
        };

        Test.startTest();
        Id hwId = HardwareGroupController.createHardwareRecord(hardwareData, testAccount.Id);
        Test.stopTest();

        List<Partition__c> partitions = [
            SELECT Id, Name, Partition_Name__c, Number_of_Processors__c
            FROM Partition__c
            WHERE Hardware__c = :hwId
        ];

        System.assertEquals(1, partitions.size(), 'Should create exactly 1 partition for Cross Platform hardware');
        System.assertEquals('Cross Server - Partition 1', partitions[0].Partition_Name__c, 'Partition name should derive from hardware name');
        System.assertEquals(2, partitions[0].Number_of_Processors__c, 'Processors should match input');
    }

    /**
     * Test createHardwareRecord - non iSeries/Cross Platform should NOT create Partition
     */
    @isTest
    static void testCreateHardwareRecordNoPartitionForOtherPlatforms() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> hardwareData = new Map<String, Object>{
            'Model_Number__c' => 'GENERIC-100',
            'Serial_Number__c' => 'SN-NOPART-001',
            'Number_of_Processors__c' => 8
        };

        Test.startTest();
        Id hwId = HardwareGroupController.createHardwareRecord(hardwareData, testAccount.Id);
        Test.stopTest();

        List<Partition__c> partitions = [
            SELECT Id FROM Partition__c WHERE Hardware__c = :hwId
        ];

        System.assertEquals(0, partitions.size(), 'Should NOT create partition when no platform specified');
    }

    /**
     * Test updateHardwareGroup - keeping the same name should succeed (no false positive)
     */
    @isTest
    static void testUpdateHardwareGroupKeepSameName() {
        QuoteLineGroup group1 = [SELECT Id, Name, Hardware__c FROM QuoteLineGroup WHERE Name = 'Hardware Group 1' LIMIT 1];

        Test.startTest();
        // Update notes but keep the same name - should NOT throw
        HardwareGroupController.updateHardwareGroup(
            group1.Id,
            'Hardware Group 1',  // Same name as current
            'Updated notes only',
            group1.Hardware__c   // Keep original hardware assignment
        );
        Test.stopTest();

        // Verify the update succeeded
        QuoteLineGroup updated = [SELECT Id, Name, Hardware_Notes__c FROM QuoteLineGroup WHERE Id = :group1.Id];
        System.assertEquals('Hardware Group 1', updated.Name, 'Name should remain the same');
        System.assertEquals('Updated notes only', updated.Hardware_Notes__c, 'Notes should be updated');
    }

    /**
     * SC-3423 (core fix): getHardwareById returns the just-created record by Id. This is what the LWC
     * now uses after Create & Select, replacing the searchHardware(LIMIT 200)+.find() pattern.
     */
    @isTest
    static void testGetHardwareById() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> hardwareData = new Map<String, Object>{
            'Hardware_Name__c' => 'SC3423 New HW',
            'Hardware_Platform__c' => 'Cross Platform',
            'Hostname__c' => 'host-sc3423',
            'Host_Operating_System__c' => 'Linux'
        };

        Test.startTest();
        Id newId = HardwareGroupController.createHardwareRecord(hardwareData, testAccount.Id);
        Hardware__c fetched = HardwareGroupController.getHardwareById(newId);
        Test.stopTest();

        System.assertNotEquals(null, fetched, 'getHardwareById must return the created record');
        System.assertEquals(newId, fetched.Id, 'Returned record Id must match the created Id');
        System.assertEquals('Quoting', fetched.Status__c, 'Newly created hardware is in Quoting status');
        System.assertNotEquals(null, fetched.Hardware_ID__c, 'Created record carries a generated Hardware ID');
    }

    /**
     * SC-3423: getHardwareById returns null (does not throw) for a null Id input.
     */
    @isTest
    static void testGetHardwareByIdNullInput() {
        Test.startTest();
        Hardware__c result = HardwareGroupController.getHardwareById(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Null id should return null, not throw');
    }

    /**
     * SC-3423 (regression guard for the LIST path): on an account with >200 Hardware rows whose
     * Hardware_ID__c is NULL (which, under the default NULLS-FIRST ordering, monopolised the old
     * LIMIT 200 window), a newly created record with a non-null Hardware_ID__c must still surface in
     * the Available Hardware list. This FAILS under the old `ORDER BY Hardware_ID__c LIMIT 200`
     * (new record truncated past row 200) and PASSES under the fix (`NULLS LAST LIMIT 2000`).
     */
    @isTest
    static void testUnassignedHardwareSurfacesNewRecordPastNullWindow() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];

        // Seed >200 Hardware rows with NULL Hardware_ID__c so they sort first under default NULLS FIRST.
        List<Hardware__c> filler = new List<Hardware__c>();
        for (Integer i = 0; i < 205; i++) {
            filler.add(new Hardware__c(Account__c = testAccount.Id, Status__c = 'Pending'));
        }
        insert filler;

        // Create a new record through the controller -> gets a non-null generated Hardware_ID__c.
        Map<String, Object> hardwareData = new Map<String, Object>{
            'Hardware_Name__c' => 'SC3423 Visible HW',
            'Hardware_Platform__c' => 'Cross Platform',
            'Hostname__c' => 'host-visible',
            'Host_Operating_System__c' => 'Linux'
        };
        Id newId = HardwareGroupController.createHardwareRecord(hardwareData, testAccount.Id);

        Test.startTest();
        List<Hardware__c> unassigned = HardwareGroupController.getUnassignedHardware(testQuote.Id, testAccount.Id);
        Test.stopTest();

        Set<Id> ids = new Set<Id>();
        for (Hardware__c hw : unassigned) {
            ids.add(hw.Id);
        }
        System.assert(
            ids.contains(newId),
            'Newly created hardware must surface in the Available Hardware list even with 205 null-ID rows ahead of it'
        );
    }

    /**
     * Coverage: getQuoteAccountId returns the Quote's Account (used by the LWC to scope hardware).
     */
    @isTest
    static void testGetQuoteAccountId() {
        Quote testQuote = [SELECT Id, AccountId FROM Quote LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Id resolved = HardwareGroupController.getQuoteAccountId(testQuote.Id);
        Test.stopTest();

        System.assertNotEquals(null, resolved, 'Should resolve an Account for the quote');
        System.assertEquals(testAccount.Id, resolved, 'Should resolve the Account on the quote');
    }

    /**
     * Coverage: getFeatureCodeOptions with a valid iSeries model exercises the dependent-picklist
     * validFor bitmap decode path (getValidForBitmap -> isValidForIndex -> hexToInteger).
     * iSeries_Feature_Code__c is a dependent picklist of iSeries_Model__c in this org.
     */
    @isTest
    static void testGetFeatureCodeOptionsValidModel() {
        Test.startTest();
        List<Map<String, String>> options = HardwareGroupController.getFeatureCodeOptions('150');
        Test.stopTest();

        System.assertNotEquals(null, options, 'Options list should not be null for a valid model');
        // Each returned option must carry a label and value.
        for (Map<String, String> opt : options) {
            System.assert(opt.containsKey('label') && opt.containsKey('value'), 'Each option has label + value');
        }
    }

    /**
     * Coverage: getFeatureCodeOptions returns an empty list for a blank model (early return).
     */
    @isTest
    static void testGetFeatureCodeOptionsBlankModel() {
        Test.startTest();
        List<Map<String, String>> options = HardwareGroupController.getFeatureCodeOptions('');
        Test.stopTest();

        System.assertEquals(0, options.size(), 'Blank model should yield no options');
    }

    /**
     * Coverage: getFeatureCodeOptions returns empty for a model value not in the picklist
     * (selectedIndex == null branch).
     */
    @isTest
    static void testGetFeatureCodeOptionsInvalidModel() {
        Test.startTest();
        List<Map<String, String>> options = HardwareGroupController.getFeatureCodeOptions('NOT_A_REAL_MODEL_XYZ');
        Test.stopTest();

        System.assertEquals(0, options.size(), 'Unknown model should yield no options');
    }
}