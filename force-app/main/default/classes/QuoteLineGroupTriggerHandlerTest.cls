/**
 * Test class for QuoteLineGroupTriggerHandler
 *
 * Tests automatic hardware reference updates on quote lines when group hardware changes
 *
 * @author Claude Code
 * @date 2025-01-23
 */
@isTest
private class QuoteLineGroupTriggerHandlerTest {

    // Test data constants
    private static final String TEST_ACCOUNT_NAME = 'Test Hardware Account';
    private static final String TEST_HARDWARE_PREFIX = 'HW';

    /**
     * Create comprehensive test data
     */
    @TestSetup
    static void setupTestData() {
        // Create Account
        Account testAccount = new Account(
            Name = TEST_ACCOUNT_NAME,
            BillingCountry = 'United States',
            BillingState = 'California'
        );
        insert testAccount;

        // Create Opportunity
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
            Name = 'Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        // Create Products
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < 10; i++) {
            products.add(new Product2(
                Name = 'Test Product ' + i,
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

        // Create Hardware records
        List<Hardware__c> hardwareList = new List<Hardware__c>();
        for (Integer i = 0; i < 5; i++) {
            hardwareList.add(new Hardware__c(
                Hardware_ID__c = TEST_HARDWARE_PREFIX + String.valueOf(i).leftPad(6, '0'),
                Model_Number__c = 'MODEL-' + i,
                Serial_Number__c = 'SN' + String.valueOf(1000 + i),
                Status__c = 'Active',
                Number_of_Processors__c = 4,
                Account__c = testAccount.Id
            ));
        }
        insert hardwareList;

        // Create QuoteLineGroups with hardware assigned
        List<QuoteLineGroup> groups = new List<QuoteLineGroup>();
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 1',
            QuoteId = testQuote.Id,
            Hardware__c = hardwareList[0].Id,
            Hardware_Group_Type__c = true,
            Hardware_Notes__c = 'Primary server group'
        ));
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 2',
            QuoteId = testQuote.Id,
            Hardware__c = hardwareList[1].Id,
            Hardware_Group_Type__c = true,
            Hardware_Notes__c = 'Secondary server group'
        ));
        groups.add(new QuoteLineGroup(
            Name = 'Empty Group',
            QuoteId = testQuote.Id,
            Hardware__c = hardwareList[2].Id,
            Hardware_Group_Type__c = true
        ));
        insert groups;

        // Create QuoteLineItems in the groups
        List<QuoteLineItem> quoteLines = new List<QuoteLineItem>();

        // Group 1: 5 quote lines
        for (Integer i = 0; i < 5; i++) {
            quoteLines.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = products[i].Id,
                PricebookEntryId = pbes[i].Id,
                Quantity = 10,
                UnitPrice = 1000.00,
                QuoteLineGroupId = groups[0].Id,
                Hardware_Reference__c = hardwareList[0].Id
            ));
        }

        // Group 2: 3 quote lines
        for (Integer i = 5; i < 8; i++) {
            quoteLines.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = products[i].Id,
                PricebookEntryId = pbes[i].Id,
                Quantity = 5,
                UnitPrice = 500.00,
                QuoteLineGroupId = groups[1].Id,
                Hardware_Reference__c = hardwareList[1].Id
            ));
        }

        // Empty Group: no quote lines (intentional)

        insert quoteLines;
    }

    /**
     * Test updating hardware on a group updates all quote lines in that group
     */
    @isTest
    static void testUpdateGroupHardwareUpdatesAllLines() {
        // Get test data
        QuoteLineGroup hwGroup = [
            SELECT Id, Hardware__c,
                (SELECT Id, Hardware_Reference__c FROM QuoteLineItems)
            FROM QuoteLineGroup
            WHERE Name = 'Hardware Group 1'
            LIMIT 1
        ];
        Hardware__c newHardware = [
            SELECT Id
            FROM Hardware__c
            WHERE Hardware_ID__c = :TEST_HARDWARE_PREFIX + '000003'
            LIMIT 1
        ];

        // Verify initial state
        System.assertEquals(5, hwGroup.QuoteLineItems.size(), 'Group should have 5 quote lines');
        Id oldHardwareId = hwGroup.Hardware__c;
        for (QuoteLineItem line : hwGroup.QuoteLineItems) {
            System.assertEquals(oldHardwareId, line.Hardware_Reference__c,
                'All lines should have old hardware initially');
        }

        // Update group hardware
        hwGroup.Hardware__c = newHardware.Id;

        Test.startTest();
        update hwGroup;
        Test.stopTest();

        // Verify all quote lines were updated
        List<QuoteLineItem> updatedLines = [
            SELECT Id, Hardware_Reference__c
            FROM QuoteLineItem
            WHERE QuoteLineGroupId = :hwGroup.Id
        ];

        System.assertEquals(5, updatedLines.size(), 'Should still have 5 quote lines');
        for (QuoteLineItem line : updatedLines) {
            System.assertEquals(newHardware.Id, line.Hardware_Reference__c,
                'All lines should have new hardware after group update');
        }
    }

    /**
     * Test clearing hardware from a group clears hardware from all quote lines
     */
    @isTest
    static void testClearGroupHardwareClearsAllLines() {
        // Get test data
        QuoteLineGroup hwGroup = [
            SELECT Id, Hardware__c,
                (SELECT Id, Hardware_Reference__c FROM QuoteLineItems)
            FROM QuoteLineGroup
            WHERE Name = 'Hardware Group 2'
            LIMIT 1
        ];

        // Verify initial state
        System.assertEquals(3, hwGroup.QuoteLineItems.size(), 'Group should have 3 quote lines');
        System.assertNotEquals(null, hwGroup.Hardware__c, 'Group should have hardware initially');
        for (QuoteLineItem line : hwGroup.QuoteLineItems) {
            System.assertNotEquals(null, line.Hardware_Reference__c,
                'All lines should have hardware initially');
        }

        // Clear group hardware and unmark as hardware group
        hwGroup.Hardware__c = null;
        hwGroup.Hardware_Group_Type__c = false;

        Test.startTest();
        update hwGroup;
        Test.stopTest();

        // Verify all quote lines hardware was cleared
        List<QuoteLineItem> updatedLines = [
            SELECT Id, Hardware_Reference__c
            FROM QuoteLineItem
            WHERE QuoteLineGroupId = :hwGroup.Id
        ];

        System.assertEquals(3, updatedLines.size(), 'Should still have 3 quote lines');
        for (QuoteLineItem line : updatedLines) {
            System.assertEquals(null, line.Hardware_Reference__c,
                'All lines should have hardware cleared after group update');
        }
    }

    /**
     * Test bulk update of multiple groups with hardware changes
     */
    @isTest
    static void testBulkUpdateMultipleGroups() {
        // Get test data
        List<QuoteLineGroup> hwGroups = [
            SELECT Id, Hardware__c,
                (SELECT Id FROM QuoteLineItems)
            FROM QuoteLineGroup
            WHERE Hardware_Group_Type__c = true
            ORDER BY Name
            LIMIT 2
        ];
        List<Hardware__c> newHardware = [
            SELECT Id
            FROM Hardware__c
            WHERE Hardware_ID__c IN (:TEST_HARDWARE_PREFIX + '000003', :TEST_HARDWARE_PREFIX + '000004')
            ORDER BY Hardware_ID__c
        ];

        System.assertEquals(2, hwGroups.size(), 'Should have 2 hardware groups');
        System.assertEquals(2, newHardware.size(), 'Should have 2 new hardware records');

        // Update both groups to different hardware
        hwGroups[0].Hardware__c = newHardware[0].Id;
        hwGroups[1].Hardware__c = newHardware[1].Id;

        Test.startTest();
        update hwGroups;
        Test.stopTest();

        // Verify all quote lines in both groups were updated
        Map<Id, QuoteLineGroup> updatedGroupsMap = new Map<Id, QuoteLineGroup>([
            SELECT Id, Hardware__c,
                (SELECT Id, Hardware_Reference__c FROM QuoteLineItems)
            FROM QuoteLineGroup
            WHERE Id IN :hwGroups
        ]);

        for (Integer i = 0; i < hwGroups.size(); i++) {
            QuoteLineGroup grp = updatedGroupsMap.get(hwGroups[i].Id);
            System.assertEquals(newHardware[i].Id, grp.Hardware__c,
                'Group ' + i + ' hardware should be updated');

            for (QuoteLineItem line : grp.QuoteLineItems) {
                System.assertEquals(newHardware[i].Id, line.Hardware_Reference__c,
                    'All lines in group ' + i + ' should have new hardware');
            }
        }
    }

    /**
     * Test updating group with no quote lines (should not error)
     */
    @isTest
    static void testUpdateGroupWithNoQuoteLines() {
        // Get test data
        QuoteLineGroup emptyGroup = [
            SELECT Id, Hardware__c,
                (SELECT Id FROM QuoteLineItems)
            FROM QuoteLineGroup
            WHERE Name = 'Empty Group'
            LIMIT 1
        ];
        Hardware__c newHardware = [
            SELECT Id
            FROM Hardware__c
            WHERE Hardware_ID__c = :TEST_HARDWARE_PREFIX + '000004'
            LIMIT 1
        ];

        // Verify group is empty
        System.assertEquals(0, emptyGroup.QuoteLineItems.size(), 'Group should have no quote lines');

        // Update hardware on empty group
        emptyGroup.Hardware__c = newHardware.Id;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            update emptyGroup;
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        // Verify no exception and update succeeded
        System.assertEquals(false, exceptionThrown, 'Should not throw exception for empty group');

        QuoteLineGroup updatedGroup = [
            SELECT Id, Hardware__c
            FROM QuoteLineGroup
            WHERE Id = :emptyGroup.Id
        ];
        System.assertEquals(newHardware.Id, updatedGroup.Hardware__c, 'Hardware should be updated');
    }

    /**
     * Test updating group with many quote lines (bulk processing)
     */
    @isTest
    static void testUpdateGroupWithManyQuoteLines() {
        // Get test data
        Quote testQuote = [SELECT Id, Pricebook2Id FROM Quote LIMIT 1];
        List<Product2> products = [SELECT Id FROM Product2 WHERE Name LIKE 'Test Product%' ORDER BY Name LIMIT 5];

        // Build map with Product2Id as key
        Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id FROM PricebookEntry
            WHERE Product2Id IN :products AND Pricebook2Id = :testQuote.Pricebook2Id
        ]) {
            pbeMap.put(pbe.Product2Id, pbe);
        }

        Hardware__c hardware1 = [
            SELECT Id
            FROM Hardware__c
            WHERE Hardware_ID__c = :TEST_HARDWARE_PREFIX + '000000'
            LIMIT 1
        ];
        Hardware__c hardware2 = [
            SELECT Id
            FROM Hardware__c
            WHERE Hardware_ID__c = :TEST_HARDWARE_PREFIX + '000004'
            LIMIT 1
        ];

        // Create group with initial hardware
        QuoteLineGroup largeGroup = new QuoteLineGroup(
            Name = 'Large Hardware Group',
            QuoteId = testQuote.Id,
            Hardware__c = hardware1.Id,
            Hardware_Group_Type__c = true
        );
        insert largeGroup;

        // Create 50 quote lines in this group (avoid hitting org Flow limits)
        List<QuoteLineItem> quoteLines = new List<QuoteLineItem>();
        for (Integer i = 0; i < 50; i++) {
            Product2 prod = products[Math.mod(i, products.size())];
            quoteLines.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = prod.Id,
                PricebookEntryId = pbeMap.get(prod.Id).Id,
                Quantity = 1,
                UnitPrice = 100.00,
                QuoteLineGroupId = largeGroup.Id,
                Hardware_Reference__c = hardware1.Id
            ));
        }
        insert quoteLines;

        // Verify all lines have initial hardware
        List<QuoteLineItem> initialLines = [
            SELECT Id, Hardware_Reference__c
            FROM QuoteLineItem
            WHERE QuoteLineGroupId = :largeGroup.Id
        ];
        System.assertEquals(50, initialLines.size(), 'Should have 50 quote lines');
        for (QuoteLineItem line : initialLines) {
            System.assertEquals(hardware1.Id, line.Hardware_Reference__c, 'Should have initial hardware');
        }

        // Update group hardware
        largeGroup.Hardware__c = hardware2.Id;

        Test.startTest();
        update largeGroup;
        Test.stopTest();

        // Verify all 50 lines were updated
        List<QuoteLineItem> updatedLines = [
            SELECT Id, Hardware_Reference__c
            FROM QuoteLineItem
            WHERE QuoteLineGroupId = :largeGroup.Id
        ];

        System.assertEquals(50, updatedLines.size(), 'Should still have 50 quote lines');
        for (QuoteLineItem line : updatedLines) {
            System.assertEquals(hardware2.Id, line.Hardware_Reference__c,
                'All 50 lines should have new hardware');
        }
    }

    /**
     * Test updating group name (non-hardware field) does not affect quote lines
     */
    @isTest
    static void testUpdateGroupNameDoesNotAffectLines() {
        // Get test data
        QuoteLineGroup hwGroup = [
            SELECT Id, Name, Hardware__c,
                (SELECT Id, Hardware_Reference__c FROM QuoteLineItems)
            FROM QuoteLineGroup
            WHERE Name = 'Hardware Group 1'
            LIMIT 1
        ];

        Id initialHardwareId = hwGroup.Hardware__c;
        System.assertEquals(5, hwGroup.QuoteLineItems.size(), 'Group should have 5 quote lines');

        // Update group name only (not hardware)
        hwGroup.Name = 'Updated Group Name';

        Test.startTest();
        update hwGroup;
        Test.stopTest();

        // Verify quote lines hardware remains unchanged
        List<QuoteLineItem> linesAfterUpdate = [
            SELECT Id, Hardware_Reference__c
            FROM QuoteLineItem
            WHERE QuoteLineGroupId = :hwGroup.Id
        ];

        System.assertEquals(5, linesAfterUpdate.size(), 'Should still have 5 quote lines');
        for (QuoteLineItem line : linesAfterUpdate) {
            System.assertEquals(initialHardwareId, line.Hardware_Reference__c,
                'Hardware should remain unchanged when updating non-hardware fields');
        }
    }

    /**
     * Test swapping hardware between two groups
     */
    @isTest
    static void testSwapHardwareBetweenGroups() {
        // Get test data
        List<QuoteLineGroup> hwGroups = [
            SELECT Id, Name, Hardware__c,
                (SELECT Id, Hardware_Reference__c FROM QuoteLineItems)
            FROM QuoteLineGroup
            WHERE Name IN ('Hardware Group 1', 'Hardware Group 2')
            ORDER BY Name
        ];

        System.assertEquals(2, hwGroups.size(), 'Should have 2 groups');

        QuoteLineGroup group1 = hwGroups[0];
        QuoteLineGroup group2 = hwGroups[1];
        Id hardware1 = group1.Hardware__c;
        Id hardware2 = group2.Hardware__c;

        System.assertEquals(5, group1.QuoteLineItems.size(), 'Group 1 should have 5 lines');
        System.assertEquals(3, group2.QuoteLineItems.size(), 'Group 2 should have 3 lines');

        // Swap hardware
        group1.Hardware__c = hardware2;
        group2.Hardware__c = hardware1;

        Test.startTest();
        update new List<QuoteLineGroup>{ group1, group2 };
        Test.stopTest();

        // Verify all quote lines in both groups were swapped
        Map<Id, QuoteLineGroup> updatedGroupsMap = new Map<Id, QuoteLineGroup>([
            SELECT Id, Hardware__c,
                (SELECT Id, Hardware_Reference__c FROM QuoteLineItems)
            FROM QuoteLineGroup
            WHERE Id IN :hwGroups
        ]);

        QuoteLineGroup updatedGroup1 = updatedGroupsMap.get(group1.Id);
        QuoteLineGroup updatedGroup2 = updatedGroupsMap.get(group2.Id);

        System.assertEquals(hardware2, updatedGroup1.Hardware__c, 'Group 1 should have hardware 2');
        System.assertEquals(hardware1, updatedGroup2.Hardware__c, 'Group 2 should have hardware 1');

        for (QuoteLineItem line : updatedGroup1.QuoteLineItems) {
            System.assertEquals(hardware2, line.Hardware_Reference__c,
                'Group 1 lines should have hardware 2');
        }

        for (QuoteLineItem line : updatedGroup2.QuoteLineItems) {
            System.assertEquals(hardware1, line.Hardware_Reference__c,
                'Group 2 lines should have hardware 1');
        }
    }

    /**
     * Test that insert of new group does not trigger update logic
     */
    @isTest
    static void testInsertNewGroupDoesNotTriggerUpdateLogic() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        Hardware__c hardware = [
            SELECT Id
            FROM Hardware__c
            WHERE Hardware_ID__c = :TEST_HARDWARE_PREFIX + '000003'
            LIMIT 1
        ];

        // Create new group with hardware
        QuoteLineGroup newGroup = new QuoteLineGroup(
            Name = 'New Group on Insert',
            QuoteId = testQuote.Id,
            Hardware__c = hardware.Id,
            Hardware_Group_Type__c = true
        );

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            insert newGroup;
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        // Verify no exception (insert should work fine)
        System.assertEquals(false, exceptionThrown, 'Should not throw exception on insert');
        System.assertNotEquals(null, newGroup.Id, 'Group should be inserted successfully');
    }
}