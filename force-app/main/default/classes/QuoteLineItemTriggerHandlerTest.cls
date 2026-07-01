/**
 * Test class for QuoteLineItemTriggerHandler
 *
 * Tests automatic hardware assignment when quote lines are added to or removed from groups
 *
 * @author Claude Code
 * @date 2025-01-23
 */
@isTest
private class QuoteLineItemTriggerHandlerTest {

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
        for (Integer i = 0; i < 5; i++) {
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
        for (Integer i = 0; i < 3; i++) {
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
            Hardware_Group_Type__c = false
        ));
        insert groups;

        // Store group and product data for tests (using custom settings or static resource)
        // Note: Test data will be queried in each test method
    }

    /**
     * Test automatic hardware assignment when inserting quote line with group
     */
    @isTest
    static void testInsertQuoteLineWithGroup() {
        // Get test data
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        QuoteLineGroup hwGroup = [SELECT Id, Hardware__c FROM QuoteLineGroup WHERE Name = 'Hardware Group 1' LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1];

        System.assertNotEquals(null, hwGroup.Hardware__c, 'Test group should have hardware assigned');

        // Create quote line with group assigned
        QuoteLineItem newLine = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = product.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 10,
            UnitPrice = 1000.00,
            QuoteLineGroupId = hwGroup.Id
        );

        Test.startTest();
        insert newLine;
        Test.stopTest();

        // Verify hardware was auto-assigned
        QuoteLineItem insertedLine = [
            SELECT Id, QuoteLineGroupId, Hardware__c
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];

        System.assertEquals(hwGroup.Id, insertedLine.QuoteLineGroupId, 'Group should be assigned');
        System.assertEquals(hwGroup.Hardware__c, insertedLine.Hardware__c, 'Hardware should be auto-assigned from group');
    }

    /**
     * Test bulk insert of quote lines with groups
     */
    @isTest
    static void testBulkInsertQuoteLinesWithGroups() {
        // Get test data
        Quote testQuote = [SELECT Id, Pricebook2Id FROM Quote LIMIT 1];
        QuoteLineGroup hwGroup = [SELECT Id, Hardware__c FROM QuoteLineGroup WHERE Name = 'Hardware Group 1' LIMIT 1];
        List<Product2> products = [SELECT Id FROM Product2 WHERE Name LIKE 'Test Product%' ORDER BY Name LIMIT 5];

        // Build map with Product2Id as key
        Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id FROM PricebookEntry
            WHERE Product2Id IN :products AND Pricebook2Id = :testQuote.Pricebook2Id
        ]) {
            pbeMap.put(pbe.Product2Id, pbe);
        }

        // Create 50 quote lines (test bulk processing without hitting org Flow limits)
        List<QuoteLineItem> newLines = new List<QuoteLineItem>();
        for (Integer i = 0; i < 50; i++) {
            Product2 prod = products[Math.mod(i, products.size())];
            newLines.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = prod.Id,
                PricebookEntryId = pbeMap.get(prod.Id).Id,
                Quantity = 1,
                UnitPrice = 100.00,
                QuoteLineGroupId = hwGroup.Id
            ));
        }

        Test.startTest();
        insert newLines;
        Test.stopTest();

        // Verify all lines have hardware assigned
        List<QuoteLineItem> insertedLines = [
            SELECT Id, Hardware__c
            FROM QuoteLineItem
            WHERE Id IN :newLines
        ];

        System.assertEquals(50, insertedLines.size(), 'All lines should be inserted');

        for (QuoteLineItem line : insertedLines) {
            System.assertEquals(hwGroup.Hardware__c, line.Hardware__c,
                'All lines should have hardware auto-assigned');
        }
    }

    /**
     * Test updating quote line to add to hardware group
     */
    @isTest
    static void testUpdateQuoteLineAddToGroup() {
        // Get test data
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        QuoteLineGroup hwGroup = [SELECT Id, Hardware__c FROM QuoteLineGroup WHERE Name = 'Hardware Group 2' LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1];

        // Create quote line WITHOUT group
        QuoteLineItem newLine = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = product.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 5,
            UnitPrice = 500.00
        );
        insert newLine;

        // Verify no hardware initially
        QuoteLineItem lineBeforeUpdate = [
            SELECT Id, QuoteLineGroupId, Hardware__c
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];
        System.assertEquals(null, lineBeforeUpdate.QuoteLineGroupId, 'Should not be in group initially');
        System.assertEquals(null, lineBeforeUpdate.Hardware__c, 'Should not have hardware initially');

        // Update to add to hardware group
        newLine.QuoteLineGroupId = hwGroup.Id;

        Test.startTest();
        update newLine;
        Test.stopTest();

        // Verify hardware was auto-assigned
        QuoteLineItem lineAfterUpdate = [
            SELECT Id, QuoteLineGroupId, Hardware__c
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];

        System.assertEquals(hwGroup.Id, lineAfterUpdate.QuoteLineGroupId, 'Should be in group');
        System.assertEquals(hwGroup.Hardware__c, lineAfterUpdate.Hardware__c,
            'Hardware should be auto-assigned when added to group');
    }

    /**
     * Test updating quote line to remove from hardware group
     */
    @isTest
    static void testUpdateQuoteLineRemoveFromGroup() {
        // Get test data
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        QuoteLineGroup hwGroup = [SELECT Id, Hardware__c FROM QuoteLineGroup WHERE Name = 'Hardware Group 1' LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1];

        // Create quote line WITH group
        QuoteLineItem newLine = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = product.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 5,
            UnitPrice = 500.00,
            QuoteLineGroupId = hwGroup.Id
        );
        insert newLine;

        // Verify hardware is assigned
        QuoteLineItem lineBeforeUpdate = [
            SELECT Id, QuoteLineGroupId, Hardware__c
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];
        System.assertEquals(hwGroup.Id, lineBeforeUpdate.QuoteLineGroupId, 'Should be in group');
        System.assertEquals(hwGroup.Hardware__c, lineBeforeUpdate.Hardware__c, 'Should have hardware');

        // Update to remove from group
        newLine.QuoteLineGroupId = null;

        Test.startTest();
        update newLine;
        Test.stopTest();

        // Verify hardware was cleared
        QuoteLineItem lineAfterUpdate = [
            SELECT Id, QuoteLineGroupId, Hardware__c
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];

        System.assertEquals(null, lineAfterUpdate.QuoteLineGroupId, 'Should not be in group');
        System.assertEquals(null, lineAfterUpdate.Hardware__c,
            'Hardware should be cleared when removed from group');
    }

    /**
     * Test moving quote line between hardware groups
     */
    @isTest
    static void testMoveQuoteLineBetweenGroups() {
        // Get test data
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineGroup> hwGroups = [
            SELECT Id, Hardware__c
            FROM QuoteLineGroup
            WHERE Hardware_Group_Type__c = true
            ORDER BY Name
            LIMIT 2
        ];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1];

        System.assertEquals(2, hwGroups.size(), 'Should have 2 hardware groups');
        System.assertNotEquals(hwGroups[0].Hardware__c, hwGroups[1].Hardware__c,
            'Groups should have different hardware');

        // Create quote line in first group
        QuoteLineItem newLine = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = product.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 5,
            UnitPrice = 500.00,
            QuoteLineGroupId = hwGroups[0].Id
        );
        insert newLine;

        // Verify initial hardware assignment
        QuoteLineItem lineBeforeMove = [
            SELECT Id, Hardware__c
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];
        System.assertEquals(hwGroups[0].Hardware__c, lineBeforeMove.Hardware__c,
            'Should have first group hardware');

        // Move to second group
        newLine.QuoteLineGroupId = hwGroups[1].Id;

        Test.startTest();
        update newLine;
        Test.stopTest();

        // Verify hardware was updated to second group's hardware
        QuoteLineItem lineAfterMove = [
            SELECT Id, QuoteLineGroupId, Hardware__c
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];

        System.assertEquals(hwGroups[1].Id, lineAfterMove.QuoteLineGroupId, 'Should be in second group');
        System.assertEquals(hwGroups[1].Hardware__c, lineAfterMove.Hardware__c,
            'Hardware should be updated to second group hardware');
    }

    /**
     * Test quote line in group without hardware
     */
    @isTest
    static void testQuoteLineInGroupWithoutHardware() {
        // Get test data
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        QuoteLineGroup emptyGroup = [SELECT Id, Hardware__c FROM QuoteLineGroup WHERE Name = 'Empty Group' LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1];

        System.assertEquals(null, emptyGroup.Hardware__c, 'Test group should not have hardware');

        // Create quote line in group without hardware
        QuoteLineItem newLine = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = product.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 5,
            UnitPrice = 500.00,
            QuoteLineGroupId = emptyGroup.Id
        );

        Test.startTest();
        insert newLine;
        Test.stopTest();

        // Verify hardware is NOT assigned
        QuoteLineItem insertedLine = [
            SELECT Id, QuoteLineGroupId, Hardware__c
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];

        System.assertEquals(emptyGroup.Id, insertedLine.QuoteLineGroupId, 'Should be in group');
        System.assertEquals(null, insertedLine.Hardware__c,
            'Hardware should be null when group has no hardware');
    }

    /**
     * Test bulk update moving multiple lines to hardware group
     */
    @isTest
    static void testBulkUpdateMovingLinesToGroup() {
        // Get test data
        Quote testQuote = [SELECT Id, Pricebook2Id FROM Quote LIMIT 1];
        QuoteLineGroup hwGroup = [SELECT Id, Hardware__c FROM QuoteLineGroup WHERE Name = 'Hardware Group 1' LIMIT 1];
        List<Product2> products = [SELECT Id FROM Product2 WHERE Name LIKE 'Test Product%' ORDER BY Name LIMIT 5];

        // Build map with Product2Id as key
        Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id FROM PricebookEntry
            WHERE Product2Id IN :products AND Pricebook2Id = :testQuote.Pricebook2Id
        ]) {
            pbeMap.put(pbe.Product2Id, pbe);
        }

        // Create quote lines WITHOUT groups
        List<QuoteLineItem> newLines = new List<QuoteLineItem>();
        for (Integer i = 0; i < 100; i++) {
            Product2 prod = products[Math.mod(i, products.size())];
            newLines.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = prod.Id,
                PricebookEntryId = pbeMap.get(prod.Id).Id,
                Quantity = 1,
                UnitPrice = 100.00
            ));
        }
        insert newLines;

        // Verify no hardware initially
        for (QuoteLineItem line : [SELECT Hardware__c FROM QuoteLineItem WHERE Id IN :newLines]) {
            System.assertEquals(null, line.Hardware__c, 'Should not have hardware initially');
        }

        // Update all to add to hardware group
        for (QuoteLineItem line : newLines) {
            line.QuoteLineGroupId = hwGroup.Id;
        }

        Test.startTest();
        update newLines;
        Test.stopTest();

        // Verify all lines have hardware assigned
        List<QuoteLineItem> updatedLines = [
            SELECT Id, Hardware__c
            FROM QuoteLineItem
            WHERE Id IN :newLines
        ];

        for (QuoteLineItem line : updatedLines) {
            System.assertEquals(hwGroup.Hardware__c, line.Hardware__c,
                'All lines should have hardware auto-assigned');
        }
    }

    /**
     * Test that non-group changes don't affect hardware assignment
     */
    @isTest
    static void testNonGroupUpdateDoesNotAffectHardware() {
        // Get test data
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        QuoteLineGroup hwGroup = [SELECT Id, Hardware__c FROM QuoteLineGroup WHERE Name = 'Hardware Group 1' LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :product.Id LIMIT 1];

        // Create quote line with group
        QuoteLineItem newLine = new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = product.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 5,
            UnitPrice = 500.00,
            QuoteLineGroupId = hwGroup.Id
        );
        insert newLine;

        // Verify hardware is assigned
        QuoteLineItem lineBeforeUpdate = [
            SELECT Id, Hardware__c, Quantity
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];
        System.assertEquals(hwGroup.Hardware__c, lineBeforeUpdate.Hardware__c, 'Should have hardware');

        // Update quantity (non-group field)
        newLine.Quantity = 10;

        Test.startTest();
        update newLine;
        Test.stopTest();

        // Verify hardware remains the same
        QuoteLineItem lineAfterUpdate = [
            SELECT Id, Hardware__c, Quantity
            FROM QuoteLineItem
            WHERE Id = :newLine.Id
        ];

        System.assertEquals(10, lineAfterUpdate.Quantity, 'Quantity should be updated');
        System.assertEquals(hwGroup.Hardware__c, lineAfterUpdate.Hardware__c,
            'Hardware should remain unchanged when updating non-group fields');
    }
}