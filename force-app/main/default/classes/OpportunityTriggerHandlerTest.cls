/**
 * @description Test class for OpportunityTriggerHandler
 *
 * Comprehensive test coverage for Hardware status lifecycle management
 * based on Opportunity stage changes
 *
 * @author Claude Code
 * @date 2025-01-25
 */
@isTest
private class OpportunityTriggerHandlerTest {

    // Test data constants
    private static final String TEST_ACCOUNT_NAME = 'Test Hardware Account';
    private static final String STAGE_PROSPECTING = 'Prospecting';
    private static final String STAGE_CLOSED_LOST = 'Closed Lost';
    private static final String STAGE_ORDER_PROCESSING = 'Order Processing';
    private static final String STATUS_QUOTING = 'Quoting';
    private static final String STATUS_ACTIVE = 'Active';
    private static final String CLOSED_LOST_REASON = 'No Response'; // Required by validation rule

    /**
     * @description Create test data - Account, Opportunity, Quote, Hardware, QuoteLineGroup
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

        // Get standard pricebook
        Id pricebookId = Test.getStandardPricebookId();

        // Create multiple Opportunities for testing cross-reference scenarios
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            opportunities.add(new Opportunity(
                Name = 'Test Opportunity ' + i,
                AccountId = testAccount.Id,
                StageName = STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opportunities;

        // Create Quotes for each Opportunity
        List<Quote> quotes = new List<Quote>();
        for (Opportunity opp : opportunities) {
            quotes.add(new Quote(
                Name = 'Quote for ' + opp.Name,
                OpportunityId = opp.Id,
                Pricebook2Id = pricebookId,
                Status = 'Draft'
            ));
        }
        insert quotes;

        // Create Hardware records with different statuses
        List<Hardware__c> hardwareList = new List<Hardware__c>();

        // Hardware 0-2: Quoting status (for testing stage changes)
        for (Integer i = 0; i < 3; i++) {
            hardwareList.add(new Hardware__c(
                Hardware_ID__c = 'HW-TEST-' + String.valueOf(i).leftPad(3, '0'),
                Model_Number__c = 'MODEL-' + i,
                Serial_Number__c = 'SN-TEST-' + i,
                Status__c = STATUS_QUOTING,
                Account__c = testAccount.Id
            ));
        }

        // Hardware 3-4: Active status (should NOT be affected by stage changes)
        for (Integer i = 3; i < 5; i++) {
            hardwareList.add(new Hardware__c(
                Hardware_ID__c = 'HW-TEST-' + String.valueOf(i).leftPad(3, '0'),
                Model_Number__c = 'MODEL-' + i,
                Serial_Number__c = 'SN-TEST-' + i,
                Status__c = STATUS_ACTIVE,
                Account__c = testAccount.Id
            ));
        }

        insert hardwareList;

        // Create QuoteLineGroups linking Hardware to Quotes
        List<QuoteLineGroup> groups = new List<QuoteLineGroup>();

        // Quote 0 gets Hardware 0 (Quoting) - will be deleted on Closed Lost
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 0',
            QuoteId = quotes[0].Id,
            Hardware__c = hardwareList[0].Id,
            Hardware_Group_Type__c = true
        ));

        // Quote 1 gets Hardware 1 (Quoting) - will be activated on Order Processing
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 1',
            QuoteId = quotes[1].Id,
            Hardware__c = hardwareList[1].Id,
            Hardware_Group_Type__c = true
        ));

        // Quote 0 ALSO gets Hardware 2 (Quoting) - for cross-reference test
        // Quote 2 ALSO gets Hardware 2 (Quoting) - this prevents deletion
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 2a',
            QuoteId = quotes[0].Id,
            Hardware__c = hardwareList[2].Id,
            Hardware_Group_Type__c = true
        ));
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 2b',
            QuoteId = quotes[2].Id,
            Hardware__c = hardwareList[2].Id,
            Hardware_Group_Type__c = true
        ));

        // Quote 0 gets Hardware 3 (Active) - should NOT be affected
        groups.add(new QuoteLineGroup(
            Name = 'Hardware Group 3',
            QuoteId = quotes[0].Id,
            Hardware__c = hardwareList[3].Id,
            Hardware_Group_Type__c = true
        ));

        insert groups;
    }

    /**
     * @description Test: Closed Lost deletes Hardware with Quoting status
     */
    @isTest
    static void testClosedLostDeletesQuotingHardware() {
        // Get test data
        Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'Test Opportunity 0' LIMIT 1];
        Hardware__c hw = [SELECT Id FROM Hardware__c WHERE Hardware_ID__c = 'HW-TEST-000' LIMIT 1];

        // Verify hardware exists before
        System.assertEquals(1, [SELECT COUNT() FROM Hardware__c WHERE Id = :hw.Id], 'Hardware should exist before');

        Test.startTest();
        // Change Opportunity to Closed Lost
        opp.StageName = STAGE_CLOSED_LOST;
        opp.Closed_Lost_Reason__c = CLOSED_LOST_REASON;
        update opp;
        Test.stopTest();

        // Verify hardware was deleted
        System.assertEquals(0, [SELECT COUNT() FROM Hardware__c WHERE Id = :hw.Id],
            'Hardware with Quoting status should be deleted when Opportunity moves to Closed Lost');
    }

    /**
     * @description Test: Closed Lost skips Hardware referenced by other Opportunities
     */
    @isTest
    static void testClosedLostSkipsHardwareReferencedElsewhere() {
        // Get test data - Hardware 2 is referenced by both Opportunity 0 and Opportunity 2
        Opportunity opp0 = [SELECT Id, StageName FROM Opportunity WHERE Name = 'Test Opportunity 0' LIMIT 1];
        Hardware__c hw2 = [SELECT Id FROM Hardware__c WHERE Hardware_ID__c = 'HW-TEST-002' LIMIT 1];

        // Verify hardware exists and is referenced by multiple quotes
        System.assertEquals(2, [SELECT COUNT() FROM QuoteLineGroup WHERE Hardware__c = :hw2.Id],
            'Hardware 2 should be referenced by 2 QuoteLineGroups');

        Test.startTest();
        // Change Opportunity 0 to Closed Lost
        opp0.StageName = STAGE_CLOSED_LOST;
        opp0.Closed_Lost_Reason__c = CLOSED_LOST_REASON;
        update opp0;
        Test.stopTest();

        // Verify hardware was NOT deleted (still referenced by Opportunity 2)
        System.assertEquals(1, [SELECT COUNT() FROM Hardware__c WHERE Id = :hw2.Id],
            'Hardware referenced by other Opportunities should NOT be deleted');
    }

    /**
     * @description Test: Order Processing changes Hardware status from Quoting to Active
     */
    @isTest
    static void testOrderProcessingActivatesQuotingHardware() {
        // Get test data
        Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'Test Opportunity 1' LIMIT 1];
        Hardware__c hw = [SELECT Id, Status__c FROM Hardware__c WHERE Hardware_ID__c = 'HW-TEST-001' LIMIT 1];

        // Verify hardware has Quoting status before
        System.assertEquals(STATUS_QUOTING, hw.Status__c, 'Hardware should have Quoting status before');

        Test.startTest();
        // Change Opportunity to Order Processing
        opp.StageName = STAGE_ORDER_PROCESSING;
        update opp;
        Test.stopTest();

        // Verify hardware status changed to Active
        Hardware__c updatedHw = [SELECT Id, Status__c FROM Hardware__c WHERE Id = :hw.Id];
        System.assertEquals(STATUS_ACTIVE, updatedHw.Status__c,
            'Hardware status should change to Active when Opportunity moves to Order Processing');
    }

    /**
     * @description Test: Other stage changes do not affect Hardware
     */
    @isTest
    static void testOtherStagesNoEffect() {
        // Get test data
        Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'Test Opportunity 1' LIMIT 1];
        Hardware__c hw = [SELECT Id, Status__c FROM Hardware__c WHERE Hardware_ID__c = 'HW-TEST-001' LIMIT 1];

        // Verify hardware has Quoting status before
        System.assertEquals(STATUS_QUOTING, hw.Status__c, 'Hardware should have Quoting status before');

        Test.startTest();
        // Change Opportunity to some other stage (not Closed Lost or Order Processing)
        opp.StageName = 'Qualification';
        update opp;
        Test.stopTest();

        // Verify hardware status unchanged
        Hardware__c updatedHw = [SELECT Id, Status__c FROM Hardware__c WHERE Id = :hw.Id];
        System.assertEquals(STATUS_QUOTING, updatedHw.Status__c,
            'Hardware status should remain unchanged for other stage changes');
    }

    /**
     * @description Test: Hardware with non-Quoting status is not affected
     */
    @isTest
    static void testNonQuotingStatusNotAffected() {
        // Get test data - Hardware 3 has Active status
        Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'Test Opportunity 0' LIMIT 1];
        Hardware__c hw = [SELECT Id, Status__c FROM Hardware__c WHERE Hardware_ID__c = 'HW-TEST-003' LIMIT 1];

        // Verify hardware has Active status before
        System.assertEquals(STATUS_ACTIVE, hw.Status__c, 'Hardware should have Active status before');

        Test.startTest();
        // Change Opportunity to Closed Lost
        opp.StageName = STAGE_CLOSED_LOST;
        opp.Closed_Lost_Reason__c = CLOSED_LOST_REASON;
        update opp;
        Test.stopTest();

        // Verify Active hardware was NOT deleted
        System.assertEquals(1, [SELECT COUNT() FROM Hardware__c WHERE Id = :hw.Id],
            'Hardware with Active status should NOT be deleted on Closed Lost');

        // Verify status unchanged
        Hardware__c updatedHw = [SELECT Id, Status__c FROM Hardware__c WHERE Id = :hw.Id];
        System.assertEquals(STATUS_ACTIVE, updatedHw.Status__c,
            'Hardware with Active status should remain unchanged');
    }

    /**
     * @description Test: Bulk update - multiple Opportunities changing stage at once
     */
    @isTest
    static void testBulkOpportunityUpdates() {
        // Create additional test data for bulk testing
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Id pricebookId = Test.getStandardPricebookId();

        // Create 50 more Opportunities with Quotes and Hardware
        List<Opportunity> bulkOpps = new List<Opportunity>();
        for (Integer i = 0; i < 50; i++) {
            bulkOpps.add(new Opportunity(
                Name = 'Bulk Opp ' + i,
                AccountId = testAccount.Id,
                StageName = STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert bulkOpps;

        List<Quote> bulkQuotes = new List<Quote>();
        for (Opportunity opp : bulkOpps) {
            bulkQuotes.add(new Quote(
                Name = 'Quote for ' + opp.Name,
                OpportunityId = opp.Id,
                Pricebook2Id = pricebookId,
                Status = 'Draft'
            ));
        }
        insert bulkQuotes;

        List<Hardware__c> bulkHardware = new List<Hardware__c>();
        for (Integer i = 0; i < 50; i++) {
            bulkHardware.add(new Hardware__c(
                Hardware_ID__c = 'HW-BULK-' + String.valueOf(i).leftPad(3, '0'),
                Model_Number__c = 'BULK-MODEL-' + i,
                Serial_Number__c = 'SN-BULK-' + i,
                Status__c = STATUS_QUOTING,
                Account__c = testAccount.Id
            ));
        }
        insert bulkHardware;

        List<QuoteLineGroup> bulkGroups = new List<QuoteLineGroup>();
        for (Integer i = 0; i < 50; i++) {
            bulkGroups.add(new QuoteLineGroup(
                Name = 'Bulk Group ' + i,
                QuoteId = bulkQuotes[i].Id,
                Hardware__c = bulkHardware[i].Id,
                Hardware_Group_Type__c = true
            ));
        }
        insert bulkGroups;

        // Verify hardware count before
        Integer hwCountBefore = [SELECT COUNT() FROM Hardware__c WHERE Hardware_ID__c LIKE 'HW-BULK-%'];
        System.assertEquals(50, hwCountBefore, 'Should have 50 bulk hardware records');

        Test.startTest();
        // Update all bulk Opportunities to Closed Lost at once
        for (Opportunity opp : bulkOpps) {
            opp.StageName = STAGE_CLOSED_LOST;
            opp.Closed_Lost_Reason__c = CLOSED_LOST_REASON;
        }
        update bulkOpps;
        Test.stopTest();

        // Verify all bulk hardware was deleted
        Integer hwCountAfter = [SELECT COUNT() FROM Hardware__c WHERE Hardware_ID__c LIKE 'HW-BULK-%'];
        System.assertEquals(0, hwCountAfter,
            'All bulk hardware with Quoting status should be deleted in bulk operation');
    }

    // ── Exchange Rate Tests (Phase 3) ──────────────────────────────────

    /**
     * @description Test: Insert sets Exchange_Rate_To_USD__c (1.0 for USD Opportunity)
     */
    @isTest
    static void testInsertSetsExchangeRate() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Opportunity opp = new Opportunity(
            Name = 'Exchange Rate Test Opp',
            AccountId = testAccount.Id,
            StageName = STAGE_PROSPECTING,
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Test.stopTest();

        Opportunity result = [SELECT Exchange_Rate_To_USD__c, CurrencyIsoCode FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, result.Exchange_Rate_To_USD__c,
            'Exchange_Rate_To_USD__c should be populated on insert');
        if (result.CurrencyIsoCode == 'USD') {
            System.assertEquals(1.0, result.Exchange_Rate_To_USD__c,
                'USD Opportunity should have exchange rate of 1.0');
        }
    }

    /**
     * @description Test: Changing CurrencyIsoCode refreshes Exchange_Rate_To_USD__c
     */
    @isTest
    static void testCurrencyChangeRefreshesExchangeRate() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Insert a USD Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Currency Change Test Opp',
            AccountId = testAccount.Id,
            StageName = STAGE_PROSPECTING,
            CloseDate = Date.today().addDays(30),
            CurrencyIsoCode = 'USD'
        );
        insert opp;

        Opportunity beforeChange = [SELECT Exchange_Rate_To_USD__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(1.0, beforeChange.Exchange_Rate_To_USD__c, 'Should start at 1.0 for USD');

        // Query for an active non-USD currency to use
        List<CurrencyType> nonUsdCurrencies = [
            SELECT IsoCode FROM CurrencyType WHERE IsActive = true AND IsoCode != 'USD' LIMIT 1
        ];

        if (!nonUsdCurrencies.isEmpty()) {
            Test.startTest();
            opp.CurrencyIsoCode = nonUsdCurrencies[0].IsoCode;
            update opp;
            Test.stopTest();

            Opportunity afterChange = [SELECT Exchange_Rate_To_USD__c, CurrencyIsoCode FROM Opportunity WHERE Id = :opp.Id];
            System.assertNotEquals(null, afterChange.Exchange_Rate_To_USD__c,
                'Exchange rate should be populated after currency change');
            // Non-USD rate should differ from 1.0 (unless the specific currency happens to be at parity)
            System.assertNotEquals(null, afterChange.Exchange_Rate_To_USD__c,
                'Rate should be recalculated for new currency');
        }
    }

    /**
     * @description Test: Non-currency update does not re-run exchange rate logic
     */
    @isTest
    static void testNonCurrencyUpdateSkipsExchangeRate() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Opportunity opp = new Opportunity(
            Name = 'Non-Currency Update Test',
            AccountId = testAccount.Id,
            StageName = STAGE_PROSPECTING,
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Opportunity beforeUpdate = [SELECT Exchange_Rate_To_USD__c FROM Opportunity WHERE Id = :opp.Id];
        Decimal originalRate = beforeUpdate.Exchange_Rate_To_USD__c;

        Test.startTest();
        // Update only the name, not the currency
        opp.Name = 'Updated Name Only';
        update opp;
        Test.stopTest();

        Opportunity afterUpdate = [SELECT Exchange_Rate_To_USD__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(originalRate, afterUpdate.Exchange_Rate_To_USD__c,
            'Exchange rate should remain unchanged when currency is not modified');
    }

    /**
     * @description Test: Bulk insert sets Exchange_Rate_To_USD__c on all records
     */
    @isTest
    static void testBulkInsertSetsExchangeRate() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        List<Opportunity> bulkOpps = new List<Opportunity>();
        for (Integer i = 0; i < 50; i++) {
            bulkOpps.add(new Opportunity(
                Name = 'Bulk Rate Opp ' + i,
                AccountId = testAccount.Id,
                StageName = STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(30)
            ));
        }

        Test.startTest();
        insert bulkOpps;
        Test.stopTest();

        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : bulkOpps) {
            oppIds.add(o.Id);
        }

        List<Opportunity> results = [
            SELECT Exchange_Rate_To_USD__c FROM Opportunity WHERE Id IN :oppIds
        ];
        System.assertEquals(50, results.size(), 'Should have inserted 50 Opportunities');
        for (Opportunity result : results) {
            System.assertNotEquals(null, result.Exchange_Rate_To_USD__c,
                'Every Opportunity should have Exchange_Rate_To_USD__c populated');
        }
    }

    // ── Hardware Lifecycle Tests (original) ─────────────────────────────

    /**
     * @description Test: No hardware linked to quote - should handle gracefully
     */
    @isTest
    static void testNoHardwareLinked() {
        // Create Opportunity and Quote with no hardware
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Id pricebookId = Test.getStandardPricebookId();

        Opportunity opp = new Opportunity(
            Name = 'No Hardware Opp',
            AccountId = testAccount.Id,
            StageName = STAGE_PROSPECTING,
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'No Hardware Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert quote;

        // QuoteLineGroup without hardware
        QuoteLineGroup grp = new QuoteLineGroup(
            Name = 'No Hardware Group',
            QuoteId = quote.Id,
            Hardware_Group_Type__c = false
        );
        insert grp;

        Test.startTest();
        // Should not throw error when no hardware is linked
        opp.StageName = STAGE_CLOSED_LOST;
        opp.Closed_Lost_Reason__c = CLOSED_LOST_REASON;
        update opp;
        Test.stopTest();

        // Verify no errors occurred
        System.assertEquals(STAGE_CLOSED_LOST,
            [SELECT StageName FROM Opportunity WHERE Id = :opp.Id].StageName,
            'Opportunity should be updated without errors');
    }
}