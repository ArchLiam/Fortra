/**
 * @description Test class for HardwareProductSelectorController
 * @author Marc DeBrey
 * @date 2025-11-10
 */
@isTest
private class HardwareProductSelectorControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        // Create test hardware
        Hardware__c hardware = new Hardware__c(
            Account__c = testAccount.Id,
            Number_of_Processors__c = 4,
            Feature_Code__c = 'FC001;FC002',
            Model_Number__c = 'Power9-E950',
            Serial_Number__c = 'TEST12345'
        );
        insert hardware;

        // Create test products
        List<Product2> products = new List<Product2>();

        // Eligible product
        products.add(new Product2(
            Name = 'Eligible Software',
            ProductCode = 'ELI-SW-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            Processor_Min__c = 2
        ));

        // Not eligible product
        products.add(new Product2(
            Name = 'High-End Software',
            ProductCode = 'HE-SW-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            Processor_Min__c = 8
        ));

        insert products;

        // Create standard pricebook entry (required for test)
        Id standardPricebookId = Test.getStandardPricebookId();

        List<PricebookEntry> stdPbes = new List<PricebookEntry>();
        for (Product2 prod : products) {
            stdPbes.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = prod.Id,
                UnitPrice = 1000,
                IsActive = true
            ));
        }
        insert stdPbes;

        // Create quote with standard pricebook
        Quote testQuote = new Quote(
            Name = 'Test Quote',
            OpportunityId = null, // Can be null for test
            Pricebook2Id = standardPricebookId
        );
        insert testQuote;
    }

    @isTest
    static void testGetEligibleProducts_Success() {
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];

        Test.startTest();
        HardwareProductSelectorController.EligibilityResultWrapper result =
            HardwareProductSelectorController.getEligibleProducts(hardware.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.hardwareContext, 'Hardware context should be populated');
        System.assertEquals(hardware.Id, result.hardwareContext.hardwareId, 'Hardware ID should match');
        System.assert(result.eligibleProductCount > 0, 'Should have at least one eligible product');
    }

    @isTest
    static void testGetEligibleProducts_InvalidHardwareId() {
        Id fakeId = Schema.Hardware__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000';

        Test.startTest();
        try {
            HardwareProductSelectorController.getEligibleProducts(fakeId);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            // Exception was thrown as expected
            System.assertNotEquals(null, e, 'AuraHandledException should be thrown');
        }
        Test.stopTest();
    }

    @isTest
    static void testAddProductsToQuote_Success() {
        Quote testQuote = [SELECT Id, Pricebook2Id FROM Quote LIMIT 1];
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'ELI-SW-001' LIMIT 1];

        Test.startTest();
        String result = HardwareProductSelectorController.addProductsToQuote(
            testQuote.Id,
            new List<Id>{ product.Id },
            hardware.Id
        );
        Test.stopTest();

        System.assert(result.contains('Successfully added'), 'Should return success message');

        // Verify quote line item was created
        List<QuoteLineItem> qlis = [SELECT Id, QuoteId, Product2Id, Hardware__c
                                    FROM QuoteLineItem
                                    WHERE QuoteId = :testQuote.Id];
        System.assertEquals(1, qlis.size(), 'Should have created 1 quote line item');
        System.assertEquals(product.Id, qlis[0].Product2Id, 'Product should match');
        System.assertEquals(hardware.Id, qlis[0].Hardware__c, 'Hardware should match');
    }

    @isTest
    static void testAddProductsToQuote_NullQuoteId() {
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];

        Test.startTest();
        try {
            HardwareProductSelectorController.addProductsToQuote(
                null,
                new List<Id>{ product.Id },
                hardware.Id
            );
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            // Exception was thrown as expected
            System.assertNotEquals(null, e, 'AuraHandledException should be thrown');
        }
        Test.stopTest();
    }

    @isTest
    static void testAddProductsToQuote_EmptyProductList() {
        Quote testQuote = [SELECT Id FROM Quote LIMIT 1];
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];

        Test.startTest();
        try {
            HardwareProductSelectorController.addProductsToQuote(
                testQuote.Id,
                new List<Id>(),
                hardware.Id
            );
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            // Exception was thrown as expected
            System.assertNotEquals(null, e, 'AuraHandledException should be thrown');
        }
        Test.stopTest();
    }

    @isTest
    static void testAddProductsToQuote_NoPricebookEntry() {
        // Create a quote with a custom pricebook that doesn't have entries
        Pricebook2 customPb = new Pricebook2(
            Name = 'Custom Pricebook',
            IsActive = true
        );
        insert customPb;

        Quote testQuote = new Quote(
            Name = 'Test Quote No PBE',
            OpportunityId = null,
            Pricebook2Id = customPb.Id
        );
        insert testQuote;

        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];

        Test.startTest();
        try {
            HardwareProductSelectorController.addProductsToQuote(
                testQuote.Id,
                new List<Id>{ product.Id },
                hardware.Id
            );
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            // Exception was thrown as expected
            System.assertNotEquals(null, e, 'AuraHandledException should be thrown');
        }
        Test.stopTest();
    }

    @isTest
    static void testEligibilityResultWrapper() {
        Hardware__c hardware = [SELECT Id, Name, Number_of_Processors__c,
                                Model_Number__c, Serial_Number__c, Feature_Code__c
                                FROM Hardware__c LIMIT 1];

        HardwareProductEligibilityService.EligibilityResult serviceResult =
            HardwareProductEligibilityService.filterProducts(hardware.Id);

        Test.startTest();
        HardwareProductSelectorController.EligibilityResultWrapper wrapper =
            new HardwareProductSelectorController.EligibilityResultWrapper(serviceResult);
        Test.stopTest();

        System.assertNotEquals(null, wrapper.hardwareContext, 'Hardware context should be set');
        System.assertEquals(hardware.Id, wrapper.hardwareContext.hardwareId, 'Hardware ID should match');
        System.assertNotEquals(null, wrapper.eligibleProducts, 'Eligible products list should be set');
    }
}