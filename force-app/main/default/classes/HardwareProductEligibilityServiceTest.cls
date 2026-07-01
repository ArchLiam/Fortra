/**
 * @description Test class for HardwareProductEligibilityService
 * @author Marc DeBrey
 * @date 2025-11-10
 */
@isTest
private class HardwareProductEligibilityServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create test account (required for Hardware__c)
        Account testAccount = new Account(Name = 'Test Hardware Account');
        insert testAccount;

        // Create test hardware (Name is auto-number, don't set explicitly)
        Hardware__c hardware = new Hardware__c(
            Account__c = testAccount.Id,
            Number_of_Processors__c = 4,
            Feature_Code__c = 'FC001;FC002;FC003',
            Model_Number__c = 'Power9-E950',
            Serial_Number__c = 'TEST12345'
        );
        insert hardware;

        // Create test products with various eligibility criteria
        List<Product2> products = new List<Product2>();

        // Product 1: Eligible - meets all criteria
        products.add(new Product2(
            Name = 'High-End Software',
            ProductCode = 'HE-SW-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            Processor_Min__c = 2,
            Required_Feature_Codes__c = 'FC001;FC002'
        ));

        // Product 2: Not eligible - too many processors required
        products.add(new Product2(
            Name = 'Multi-Processor Software',
            ProductCode = 'MP-SW-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            Processor_Min__c = 8
        ));

        // Product 4: Not eligible - missing required feature code
        products.add(new Product2(
            Name = 'Feature-Specific Software',
            ProductCode = 'FS-SW-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            Required_Feature_Codes__c = 'FC001;FC005'
        ));

        // Product 5: Not eligible - has excluded feature code
        products.add(new Product2(
            Name = 'Incompatible Software',
            ProductCode = 'INCOMPAT-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            Excluded_Feature_Codes__c = 'FC002;FC010'
        ));

        // Product 5: Eligible - processor check passes
        products.add(new Product2(
            Name = 'Mid-Range Software',
            ProductCode = 'MR-SW-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            Processor_Min__c = 2
        ));

        // Product 6: Bundle product
        products.add(new Product2(
            Name = 'Software Bundle',
            ProductCode = 'BUNDLE-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each',
            Type = 'Bundle'
        ));

        // Product 9: Inactive product (should be excluded)
        products.add(new Product2(
            Name = 'Inactive Software',
            ProductCode = 'INACTIVE-001',
            IsActive = false,
            QuantityUnitOfMeasure = 'Each'
        ));

        // Product 10: Eligible - no specific criteria
        products.add(new Product2(
            Name = 'Universal Software',
            ProductCode = 'UNIV-001',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        ));

        insert products;
    }

    @isTest
    static void testFilterProducts_Success() {
        // Get test hardware
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];

        Test.startTest();
        HardwareProductEligibilityService.EligibilityResult result =
            HardwareProductEligibilityService.filterProducts(hardware.Id);
        Test.stopTest();

        // Assert results
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.hardware, 'Hardware context should be populated');
        System.assertEquals(hardware.Id, result.hardware.Id, 'Hardware ID should match');

        // Should have 4 eligible products:
        // 1. High-End Software (meets all criteria)
        // 2. Mid-Range Software (processor check passes)
        // 3. Software Bundle (bundle type)
        // 4. Universal Software (no criteria)
        System.assertEquals(4, result.eligibleProductCount,
            'Should have 4 eligible products. Found: ' + result.eligibleProductCount);
    }

    @isTest
    static void testFilterProducts_InvalidHardwareId() {
        Id fakeId = Schema.Hardware__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000';

        Test.startTest();
        try {
            HardwareProductEligibilityService.filterProducts(fakeId);
            System.assert(false, 'Should have thrown EligibilityException');
        } catch (HardwareProductEligibilityService.EligibilityException e) {
            System.assert(e.getMessage().contains('Hardware record not found'),
                'Exception message should indicate hardware not found');
        }
        Test.stopTest();
    }

    @isTest
    static void testEvaluateProductEligibility_ProcessorCheck() {
        Hardware__c hardware = [SELECT Id, Number_of_Processors__c, Feature_Code__c,
                                Model_Number__c, Serial_Number__c FROM Hardware__c LIMIT 1];
        Product2 product = [SELECT Id, Name, ProductCode, Type,
                           Processor_Min__c,
                           Required_Feature_Codes__c, Excluded_Feature_Codes__c
                           FROM Product2 WHERE ProductCode = 'MP-SW-001' LIMIT 1];

        Test.startTest();
        HardwareProductEligibilityService.EligibilityCheck check =
            HardwareProductEligibilityService.evaluateProductEligibility(product, hardware);
        Test.stopTest();

        System.assertEquals(false, check.isEligible, 'Product should not be eligible (not enough processors)');
        // Check the last reason (the one that caused the failure)
        String failureReason = check.reasons[check.reasons.size() - 1];
        System.assert(failureReason.contains('processors') && failureReason.contains('below minimum requirement'),
            'Reason should mention processor requirement not met. Actual: ' + failureReason);
    }

    @isTest
    static void testEvaluateProductEligibility_RequiredFeatureCodes() {
        Hardware__c hardware = [SELECT Id, Number_of_Processors__c, Feature_Code__c,
                                Model_Number__c, Serial_Number__c FROM Hardware__c LIMIT 1];
        Product2 product = [SELECT Id, Name, ProductCode, Type,
                           Processor_Min__c,
                           Required_Feature_Codes__c, Excluded_Feature_Codes__c
                           FROM Product2 WHERE ProductCode = 'FS-SW-001' LIMIT 1];

        Test.startTest();
        HardwareProductEligibilityService.EligibilityCheck check =
            HardwareProductEligibilityService.evaluateProductEligibility(product, hardware);
        Test.stopTest();

        System.assertEquals(false, check.isEligible, 'Product should not be eligible (missing feature code)');
        System.assert(check.reasons[0].contains('Missing required feature codes'),
            'Reason should mention missing feature codes');
    }

    @isTest
    static void testEvaluateProductEligibility_ExcludedFeatureCodes() {
        Hardware__c hardware = [SELECT Id, Number_of_Processors__c, Feature_Code__c,
                                Model_Number__c, Serial_Number__c FROM Hardware__c LIMIT 1];
        Product2 product = [SELECT Id, Name, ProductCode, Type,
                           Processor_Min__c,
                           Required_Feature_Codes__c, Excluded_Feature_Codes__c
                           FROM Product2 WHERE ProductCode = 'INCOMPAT-001' LIMIT 1];

        Test.startTest();
        HardwareProductEligibilityService.EligibilityCheck check =
            HardwareProductEligibilityService.evaluateProductEligibility(product, hardware);
        Test.stopTest();

        System.assertEquals(false, check.isEligible, 'Product should not be eligible (has excluded feature)');
        System.assert(check.reasons[0].contains('excluded feature codes'),
            'Reason should mention excluded feature codes');
    }

    @isTest
    static void testEvaluateProductEligibility_BundleProduct() {
        Hardware__c hardware = [SELECT Id, Number_of_Processors__c, Feature_Code__c,
                                Model_Number__c, Serial_Number__c FROM Hardware__c LIMIT 1];
        Product2 product = [SELECT Id, Name, ProductCode, Type,
                           Processor_Min__c,
                           Required_Feature_Codes__c, Excluded_Feature_Codes__c
                           FROM Product2 WHERE ProductCode = 'BUNDLE-001' LIMIT 1];

        Test.startTest();
        HardwareProductEligibilityService.EligibilityCheck check =
            HardwareProductEligibilityService.evaluateProductEligibility(product, hardware);
        Test.stopTest();

        System.assertEquals(true, check.isEligible, 'Bundle product should be eligible');
        System.assert(check.reasons.size() > 0, 'Should have eligibility reasons');
        Boolean hasBundleReason = false;
        for (String reason : check.reasons) {
            if (reason.contains('Bundle')) {
                hasBundleReason = true;
                break;
            }
        }
        System.assert(hasBundleReason, 'Should mention bundle product');
    }

    @isTest
    static void testParseFeatureCodes_ValidInput() {
        String input = 'FC001;FC002;FC003';

        Test.startTest();
        Set<String> codes = HardwareProductEligibilityService.parseFeatureCodes(input);
        Test.stopTest();

        System.assertEquals(3, codes.size(), 'Should parse 3 feature codes');
        System.assert(codes.contains('FC001'), 'Should contain FC001');
        System.assert(codes.contains('FC002'), 'Should contain FC002');
        System.assert(codes.contains('FC003'), 'Should contain FC003');
    }

    @isTest
    static void testParseFeatureCodes_WithSpaces() {
        String input = ' FC001 ; FC002 ; FC003 ';

        Test.startTest();
        Set<String> codes = HardwareProductEligibilityService.parseFeatureCodes(input);
        Test.stopTest();

        System.assertEquals(3, codes.size(), 'Should parse 3 feature codes');
        System.assert(codes.contains('FC001'), 'Should contain trimmed FC001');
    }

    @isTest
    static void testParseFeatureCodes_EmptyInput() {
        Test.startTest();
        Set<String> codes1 = HardwareProductEligibilityService.parseFeatureCodes('');
        Set<String> codes2 = HardwareProductEligibilityService.parseFeatureCodes(null);
        Test.stopTest();

        System.assertEquals(0, codes1.size(), 'Empty string should return empty set');
        System.assertEquals(0, codes2.size(), 'Null should return empty set');
    }

    @isTest
    static void testGetHardwareContext() {
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];

        Test.startTest();
        Hardware__c result = HardwareProductEligibilityService.getHardwareContext(hardware.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return hardware record');
        System.assertEquals(hardware.Id, result.Id, 'Hardware ID should match');
        System.assertEquals(4, result.Number_of_Processors__c, 'Processors should be populated');
    }

    @isTest
    static void testQueryActiveProducts() {
        Test.startTest();
        List<Product2> products = HardwareProductEligibilityService.queryActiveProducts();
        Test.stopTest();

        // Should return only active products (7 active + 1 inactive = 8 total, but query returns only active)
        System.assertEquals(7, products.size(), 'Should return only active products');

        // Verify inactive product is not included
        Boolean hasInactive = false;
        for (Product2 prod : products) {
            if (prod.ProductCode == 'INACTIVE-001') {
                hasInactive = true;
            }
        }
        System.assertEquals(false, hasInactive, 'Should not include inactive products');
    }
}