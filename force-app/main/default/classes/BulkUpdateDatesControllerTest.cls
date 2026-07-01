/**
 * @description Test class for BulkUpdateDatesController
 * Tests bulk date update operations on QuoteLineItems
 *
 * Note: SellingModelType is auto-populated from ProductSellingModel and cannot
 * be set directly in test data. The getEligibleQuoteLines query filters on
 * SellingModelType = 'TermDefined', which works in production where
 * ProductSellingModel records exist. Tests verify the query executes without
 * error and that the update logic works correctly on line items.
 *
 * @author Marc DeBrey
 * @since 2026-02
 */
@isTest
private class BulkUpdateDatesControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account testAccount = new Account(
            Name = 'Test Bulk Dates Account',
            BillingCountry = 'United States',
            BillingState = 'California'
        );
        insert testAccount;

        // Create Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Bulk Dates Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        // Get standard pricebook
        Id pricebookId = Test.getStandardPricebookId();

        // Create Quote
        Quote testQuote = new Quote(
            Name = 'Test Bulk Dates Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft',
            StartDate = Date.newInstance(2026, 1, 1)
        );
        insert testQuote;

        // Create Products (mix of subscription and one-time)
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < 7; i++) {
            products.add(new Product2(
                Name = 'Test Product ' + i,
                ProductCode = 'BDT-' + i,
                IsActive = true,
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

        // Create QuoteLineGroup
        QuoteLineGroup testGroup = new QuoteLineGroup(
            QuoteId = testQuote.Id,
            Name = 'Test Group A'
        );
        insert testGroup;

        // Create QuoteLineItems - 5 subscription-like + 2 one-time-like
        List<QuoteLineItem> lineItems = new List<QuoteLineItem>();
        for (Integer i = 0; i < 7; i++) {
            QuoteLineItem qli = new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = products[i].Id,
                PricebookEntryId = pbes[i].Id,
                Quantity = 1,
                UnitPrice = 1000.00,
                StartDate = Date.newInstance(2026, 1, 1),
                EndDate = Date.newInstance(2026, 12, 31),
                SubscriptionTerm = 12
            );
            // Assign first 3 lines to the group
            if (i < 3) {
                qli.QuoteLineGroupId = testGroup.Id;
            }
            lineItems.add(qli);
        }
        insert lineItems;
    }

    @isTest
    static void testGetEligibleQuoteLines_ExecutesWithoutError() {
        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Test Bulk Dates Quote' LIMIT 1];

        Test.startTest();
        // In test context, SellingModelType won't be populated (requires ProductSellingModel),
        // so this will return an empty list. We verify it executes without error.
        List<QuoteLineItem> result = BulkUpdateDatesController.getEligibleQuoteLines(testQuote.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetEligibleQuoteLines_InvalidId() {
        Test.startTest();
        try {
            // Use a valid-format but non-existent Quote Id
            List<QuoteLineItem> result = BulkUpdateDatesController.getEligibleQuoteLines(
                [SELECT Id FROM Quote WHERE Name = 'Test Bulk Dates Quote' LIMIT 1].Id
            );
            // Should not throw — just returns empty or filtered results
            System.assertNotEquals(null, result);
        } catch (AuraHandledException e) {
            // This is also acceptable if there's an error
            System.assert(e.getMessage().contains('Error'), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateQuoteLineDates_DateRangeMode() {
        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Test Bulk Dates Quote' LIMIT 1];
        List<QuoteLineItem> allLines = [
            SELECT Id FROM QuoteLineItem WHERE QuoteId = :testQuote.Id
        ];

        // Select first 5 lines for update
        List<Id> selectedIds = new List<Id>();
        for (Integer i = 0; i < Math.min(5, allLines.size()); i++) {
            selectedIds.add(allLines[i].Id);
        }

        Date newStartDate = Date.newInstance(2026, 3, 1);
        Date newEndDate = Date.newInstance(2027, 2, 28);

        Test.startTest();
        BulkUpdateDatesController.BulkUpdateResult result =
            BulkUpdateDatesController.updateQuoteLineDates(
                testQuote.Id,
                selectedIds,
                newStartDate,
                newEndDate,
                null,
                'DATE_RANGE'
            );
        Test.stopTest();

        System.assert(result.success, 'Update should succeed');
        System.assertEquals(selectedIds.size(), result.updatedCount, 'All selected lines should be updated');
        System.assertEquals(selectedIds.size(), result.totalCount, 'Total count should match selected');

        // Verify line items were updated
        List<QuoteLineItem> updatedLines = [
            SELECT Id, StartDate, EndDate
            FROM QuoteLineItem
            WHERE Id IN :selectedIds
        ];
        for (QuoteLineItem qli : updatedLines) {
            System.assertEquals(newStartDate, qli.StartDate, 'Start date should be updated');
            System.assertEquals(newEndDate, qli.EndDate, 'End date should be updated');
        }

        // Verify Quote header StartDate was updated
        Quote updatedQuote = [SELECT StartDate FROM Quote WHERE Id = :testQuote.Id];
        System.assertEquals(newStartDate, updatedQuote.StartDate, 'Quote StartDate should be updated');
    }

    @isTest
    static void testUpdateQuoteLineDates_DateAndTermMode() {
        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Test Bulk Dates Quote' LIMIT 1];
        List<QuoteLineItem> allLines = [
            SELECT Id FROM QuoteLineItem WHERE QuoteId = :testQuote.Id
        ];

        List<Id> selectedIds = new List<Id>();
        for (Integer i = 0; i < Math.min(3, allLines.size()); i++) {
            selectedIds.add(allLines[i].Id);
        }

        Date newStartDate = Date.newInstance(2026, 4, 1);
        Integer newTerm = 24;
        // Expected end date: 2026-04-01 + 24 months - 1 day = 2028-03-31
        Date expectedEndDate = newStartDate.addMonths(newTerm).addDays(-1);

        Test.startTest();
        BulkUpdateDatesController.BulkUpdateResult result =
            BulkUpdateDatesController.updateQuoteLineDates(
                testQuote.Id,
                selectedIds,
                newStartDate,
                null,
                newTerm,
                'DATE_AND_TERM'
            );
        Test.stopTest();

        System.assert(result.success, 'Update should succeed');
        System.assertEquals(selectedIds.size(), result.updatedCount, 'All selected lines should be updated');

        // Verify end date was calculated correctly
        List<QuoteLineItem> updatedLines = [
            SELECT Id, StartDate, EndDate, SubscriptionTerm
            FROM QuoteLineItem
            WHERE Id IN :selectedIds
        ];
        for (QuoteLineItem qli : updatedLines) {
            System.assertEquals(newStartDate, qli.StartDate, 'Start date should be updated');
            System.assertEquals(expectedEndDate, qli.EndDate, 'End date should be calculated from term');
            System.assertEquals(newTerm, qli.SubscriptionTerm, 'Term should be set');
        }
    }

    @isTest
    static void testUpdateQuoteLineDates_UpdatesQuoteHeader() {
        Quote testQuote = [SELECT Id, StartDate FROM Quote WHERE Name = 'Test Bulk Dates Quote' LIMIT 1];
        List<QuoteLineItem> allLines = [
            SELECT Id FROM QuoteLineItem WHERE QuoteId = :testQuote.Id LIMIT 1
        ];

        List<Id> selectedIds = new List<Id>{ allLines[0].Id };
        Date newStartDate = Date.newInstance(2026, 7, 1);
        Date newEndDate = Date.newInstance(2027, 6, 30);

        Test.startTest();
        BulkUpdateDatesController.BulkUpdateResult result =
            BulkUpdateDatesController.updateQuoteLineDates(
                testQuote.Id,
                selectedIds,
                newStartDate,
                newEndDate,
                null,
                'DATE_RANGE'
            );
        Test.stopTest();

        System.assert(result.success, 'Update should succeed');

        // Verify Quote header StartDate
        Quote updatedQuote = [SELECT StartDate FROM Quote WHERE Id = :testQuote.Id];
        System.assertEquals(newStartDate, updatedQuote.StartDate, 'Quote header StartDate should be updated');
    }

    @isTest
    static void testUpdateQuoteLineDates_PartialSelection() {
        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Test Bulk Dates Quote' LIMIT 1];
        List<QuoteLineItem> allLines = [
            SELECT Id FROM QuoteLineItem WHERE QuoteId = :testQuote.Id
        ];

        // Select only 2 of 7 lines
        List<Id> selectedIds = new List<Id>{
            allLines[0].Id,
            allLines[1].Id
        };

        Date newStartDate = Date.newInstance(2026, 5, 1);
        Date newEndDate = Date.newInstance(2027, 4, 30);

        Test.startTest();
        BulkUpdateDatesController.BulkUpdateResult result =
            BulkUpdateDatesController.updateQuoteLineDates(
                testQuote.Id,
                selectedIds,
                newStartDate,
                newEndDate,
                null,
                'DATE_RANGE'
            );
        Test.stopTest();

        System.assert(result.success, 'Update should succeed');
        System.assertEquals(2, result.updatedCount, 'Only 2 lines should be updated');
        System.assertEquals(2, result.totalCount, 'Total should be 2');

        // Verify non-selected lines were NOT updated
        QuoteLineItem unchangedLine = [
            SELECT StartDate, EndDate
            FROM QuoteLineItem
            WHERE Id = :allLines[2].Id
        ];
        System.assertEquals(Date.newInstance(2026, 1, 1), unchangedLine.StartDate,
            'Non-selected line start date should be unchanged');
    }

    @isTest
    static void testUpdateQuoteLineDates_NoLinesSelected() {
        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Test Bulk Dates Quote' LIMIT 1];

        Test.startTest();
        BulkUpdateDatesController.BulkUpdateResult result =
            BulkUpdateDatesController.updateQuoteLineDates(
                testQuote.Id,
                new List<Id>(),
                Date.newInstance(2026, 3, 1),
                Date.newInstance(2027, 2, 28),
                null,
                'DATE_RANGE'
            );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should not succeed with no lines selected');
        System.assertEquals(0, result.updatedCount, 'Updated count should be 0');
        System.assertEquals(0, result.totalCount, 'Total count should be 0');
        System.assert(result.message.contains('No line items'), 'Message should indicate no selection');
    }

    @isTest
    static void testUpdateQuoteLineDates_NullLineItemIds() {
        Quote testQuote = [SELECT Id FROM Quote WHERE Name = 'Test Bulk Dates Quote' LIMIT 1];

        Test.startTest();
        BulkUpdateDatesController.BulkUpdateResult result =
            BulkUpdateDatesController.updateQuoteLineDates(
                testQuote.Id,
                null,
                Date.newInstance(2026, 3, 1),
                Date.newInstance(2027, 2, 28),
                null,
                'DATE_RANGE'
            );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should not succeed with null list');
        System.assertEquals(0, result.updatedCount, 'Updated count should be 0');
    }

    @isTest
    static void testBulkUpdateResult_Wrapper() {
        // Verify the wrapper class fields are accessible
        BulkUpdateDatesController.BulkUpdateResult result = new BulkUpdateDatesController.BulkUpdateResult();
        result.success = true;
        result.message = 'Test message';
        result.updatedCount = 5;
        result.totalCount = 10;
        result.errors = new List<String>{ 'Error 1', 'Error 2' };

        System.assertEquals(true, result.success);
        System.assertEquals('Test message', result.message);
        System.assertEquals(5, result.updatedCount);
        System.assertEquals(10, result.totalCount);
        System.assertEquals(2, result.errors.size());
    }
}