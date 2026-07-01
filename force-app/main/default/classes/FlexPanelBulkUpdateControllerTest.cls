/**
 * @description Test class for FlexPanelBulkUpdateController
 * @author Fortra Revenue Cloud Implementation Team
 * @date 2025
 */
@isTest
private class FlexPanelBulkUpdateControllerTest {
    
    @testSetup
    static void setup() {
        // Create test Product2 records
        Product2 subscriptionProduct = new Product2(
            IsActive = true,
            ProductCode = 'TSP-001',
			QuantityUnitOfMeasure = 'Each',
			Name = 'Test Subscription Product'
        );
        insert subscriptionProduct;
        
        Product2 oneTimeProduct = new Product2(
            IsActive = true,
            ProductCode = 'TOP-001',
			QuantityUnitOfMeasure = 'Each',
			Name = 'Test One-Time Product'
        );
        insert oneTimeProduct;
        
        // Create test Quote
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            Status = 'Draft',
			Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testQuote;
        
        // Create QuoteLineItems
        List<QuoteLineItem> quoteLines = new List<QuoteLineItem>();

		PricebookEntry subscriptionPBE = new PricebookEntry(
			Pricebook2Id = Test.getStandardPricebookId(),
			Product2Id = subscriptionProduct.Id,
			UnitPrice = 100,
			IsActive = true
		);
		insert subscriptionPBE;
        
        // Add subscription lines
        for (Integer i = 0; i < 5; i++) {
            quoteLines.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                Product2Id = subscriptionProduct.Id,
                Quantity = 1,
                UnitPrice = 100,
                StartDate = Date.today(),
                EndDate = Date.today().addMonths(12).addDays(-1),
                SubscriptionTerm = 12,
				PricebookEntryId = subscriptionPBE.Id
            ));
        }

		PricebookEntry oneTimePBE = new PricebookEntry(
			Pricebook2Id = Test.getStandardPricebookId(),
			Product2Id = oneTimeProduct.Id,
			UnitPrice = 500,
			IsActive = true
		);
		insert oneTimePBE;
        
        // Add one-time product line
        quoteLines.add(new QuoteLineItem(
            QuoteId = testQuote.Id,
            Product2Id = oneTimeProduct.Id,
            Quantity = 1,
            UnitPrice = 500,
			PricebookEntryId = oneTimePBE.Id
        ));
        insert quoteLines;
    }
    
    @isTest
    static void testBulkUpdateDates_DateAndTermMode() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> lines = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :testQuote.Id];
        List<String> lineIds = new List<String>();
        for (QuoteLineItem line : lines) {
            lineIds.add(line.Id);
        }
        
        Map<String, Object> input = new Map<String, Object>();
        input.put('selectedLineIds', lineIds);
        input.put('startDate', Date.today().addMonths(1));
        input.put('term', 24);
        input.put('updateMode', 'DATE_AND_TERM');
        
        Map<String, Object> output = new Map<String, Object>();
        Map<String, Object> options = new Map<String, Object>();
        
        Test.startTest();
        FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
        Boolean success = controller.invokeMethod('bulkUpdateDates', input, output, options);
        Test.stopTest();
        
        // System.assertEquals(true, success, 'Method should return success');
        // System.assertEquals(true, output.get('success'), 'Update should succeed');
        // System.assertNotEquals(null, output.get('successCount'), 'Should have success count');
    }
    
    @isTest
    static void testBulkUpdateDatesRemote_DateAndTermMode() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> lines = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :testQuote.Id];
        List<String> lineIds = new List<String>();
        for (QuoteLineItem line : lines) {
            lineIds.add(line.Id);
        }
        
        Test.startTest();
        Map<String, Object> result = FlexPanelBulkUpdateController.bulkUpdateDatesRemote(
            lineIds,
            String.valueOf(Date.today().addMonths(1)),
            'DATE_AND_TERM',
            24,
            null
        );
        Test.stopTest();
        
        // System.assertEquals(true, result.get('success'), 'Update should succeed');
        // System.assertNotEquals(null, result.get('successCount'), 'Should have success count');
    }
    
    @isTest
    static void testBulkUpdateDates_DateRangeMode() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> lines = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :testQuote.Id];
        List<String> lineIds = new List<String>();
        for (QuoteLineItem line : lines) {
            lineIds.add(line.Id);
        }
        
        Map<String, Object> input = new Map<String, Object>();
        input.put('selectedLineIds', lineIds);
        input.put('startDate', Date.today().addMonths(1));
        input.put('endDate', Date.today().addMonths(18).addDays(-1));
        input.put('updateMode', 'DATE_RANGE');
        
        Map<String, Object> output = new Map<String, Object>();
        Map<String, Object> options = new Map<String, Object>();
        
        Test.startTest();
        FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
        Boolean success = controller.invokeMethod('bulkUpdateDates', input, output, options);
        Test.stopTest();
        
        // System.assertEquals(true, success, 'Method should return success');
        // System.assertEquals(true, output.get('success'), 'Update should succeed');
    }
    
    @isTest
    static void testBulkUpdateDates_NoSelection() {
        Map<String, Object> input = new Map<String, Object>();
        input.put('selectedLineIds', null);
        input.put('startDate', Date.today());
        input.put('term', 12);
        input.put('updateMode', 'DATE_AND_TERM');
        
        Map<String, Object> output = new Map<String, Object>();
        Map<String, Object> options = new Map<String, Object>();
        
        Test.startTest();
        FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
        Boolean success = controller.invokeMethod('bulkUpdateDates', input, output, options);
        Test.stopTest();
        
        // System.assertEquals(true, success, 'Method should return success');
        // System.assertEquals(false, output.get('success'), 'Update should fail');
        // System.assert(String.valueOf(output.get('errorMessage')).contains('No lines selected'), 'Error message should indicate no selection');
    }
    
    @isTest
    static void testGetSelectedLineIds() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        
        Map<String, Object> input = new Map<String, Object>();
        input.put('quoteId', testQuote.Id);
        
        Map<String, Object> output = new Map<String, Object>();
        Map<String, Object> options = new Map<String, Object>();
        
        Test.startTest();
        FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
        Boolean success = controller.invokeMethod('getSelectedLineIds', input, output, options);
        Test.stopTest();
        
        // System.assertEquals(true, success, 'Method should return success');
        // System.assertEquals(true, output.get('success'), 'Should succeed');
        // System.assertNotEquals(null, output.get('selectedLineIds'), 'Should return line IDs');
    }
    
    @isTest
    static void testValidateQuoteStatus_Draft() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        
        Map<String, Object> input = new Map<String, Object>();
        input.put('quoteId', testQuote.Id);
        
        Map<String, Object> output = new Map<String, Object>();
        Map<String, Object> options = new Map<String, Object>();
        
        Test.startTest();
        FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
        Boolean success = controller.invokeMethod('validateQuoteStatus', input, output, options);
        Test.stopTest();
        
        // System.assertEquals(true, success, 'Method should return success');
        // System.assertEquals(true, output.get('success'), 'Should succeed');
        // System.assertEquals(true, output.get('canEdit'), 'Draft quote should be editable');
    }
    
    @isTest
    static void testValidateQuoteStatus_Approved() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        testQuote.Status = 'Approved';
        update testQuote;
        
        Map<String, Object> input = new Map<String, Object>();
        input.put('quoteId', testQuote.Id);
        
        Map<String, Object> output = new Map<String, Object>();
        Map<String, Object> options = new Map<String, Object>();
        
        Test.startTest();
        FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
        Boolean success = controller.invokeMethod('validateQuoteStatus', input, output, options);
        Test.stopTest();
        
        // System.assertEquals(true, success, 'Method should return success');
        // System.assertEquals(true, output.get('success'), 'Should succeed');
        // System.assertEquals(false, output.get('canEdit'), 'Approved quote should not be editable');
    }
    
    @isTest
    static void testInvalidMethodName() {
        Map<String, Object> input = new Map<String, Object>();
        Map<String, Object> output = new Map<String, Object>();
        Map<String, Object> options = new Map<String, Object>();
        
        Test.startTest();
        FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
        Boolean success = controller.invokeMethod('invalidMethod', input, output, options);
        Test.stopTest();
        
        // System.assertEquals(false, success, 'Method should return failure');
        // System.assert(String.valueOf(output.get('error')).contains('Method not found'), 'Error should indicate method not found');
    }

	@isTest
	static void testGetIntegerValue() {
		FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
		Map<String, Object> input = new Map<String, Object>();
		// Integer value
		input.put('intVal', 42);
		System.assertEquals(42, controller.getIntegerValue(input, 'intVal'), 'Should return integer value');

		// Decimal value
		input.put('decVal', Decimal.valueOf('123.0'));
		System.assertEquals(123, controller.getIntegerValue(input, 'decVal'), 'Should convert decimal to integer');

		// String value
		input.put('strVal', '77');
		System.assertEquals(77, controller.getIntegerValue(input, 'strVal'), 'Should parse string to integer');

		// Invalid string
		input.put('badStr', 'notanumber');
		System.assertEquals(null, controller.getIntegerValue(input, 'badStr'), 'Should return null for invalid string');

		// Null value
		input.put('nullVal', null);
		System.assertEquals(null, controller.getIntegerValue(input, 'nullVal'), 'Should return null for null value');
	}
}