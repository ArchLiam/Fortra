/**
 * @description Test class for AttributeLoadingService
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-03
 */
@IsTest
private class AttributeLoadingServiceTest {

    private static final String TEST_LEGACY_PREFIX = 'DY_ATTR_';

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account testAccount = new Account(
            Name = 'Attr Test Account',
            BillingCountry = 'United States',
            BillingState = 'California',
            BillingCity = 'San Francisco',
            BillingStreet = '123 Test St'
        );
        insert testAccount;

        // Create Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Attr Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-30)
        );
        insert testOpp;

        // Get standard pricebook and create Quote
        Id pricebookId = Test.getStandardPricebookId();
        Quote testQuote = new Quote(
            Name = 'Attr Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        // Create Product and PBE
        Product2 testProduct = new Product2(
            Name = 'Attr Test Product',
            ProductCode = 'ATTR-PROD-001',
            IsActive = true
        );
        insert testProduct;

        PricebookEntry testPbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 5000.00,
            IsActive = true
        );
        insert testPbe;

        // Create 3 QLIs with Legacy_Id__c
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Integer i = 1; i <= 3; i++) {
            qlis.add(new QuoteLineItem(
                QuoteId = testQuote.Id,
                PricebookEntryId = testPbe.Id,
                Product2Id = testProduct.Id,
                Quantity = 1,
                UnitPrice = 5000.00,
                Legacy_Id__c = TEST_LEGACY_PREFIX + String.valueOf(i).leftPad(3, '0'),
                ServiceDate = Date.today(),
                EndDate = Date.today().addMonths(12)
            ));
        }
        insert qlis;

        // Create AttributePicklist (parent for picklist values)
        AttributePicklist testPicklist = new AttributePicklist(
            Name = 'Test Server Types'
        );
        insert testPicklist;

        // Create AttributeDefinitions
        // 1. Picklist type (with associated picklist values)
        AttributeDefinition adPicklist = new AttributeDefinition(
            Name = 'Server Type',
            DeveloperName = 'Server_Type',
            Label = 'Server Type',
            DataType = 'Picklist',
            PicklistId = testPicklist.Id,
            IsActive = true
        );
        insert adPicklist;

        // 2. Text type (no picklist)
        AttributeDefinition adText = new AttributeDefinition(
            Name = 'Deployment Option',
            DeveloperName = 'Deployment_Option',
            Label = 'Deployment Option',
            DataType = 'Text',
            IsActive = true
        );
        insert adText;

        // Create AttributePicklistValues for Server Type
        List<AttributePicklistValue> picklistValues = new List<AttributePicklistValue>();
        picklistValues.add(new AttributePicklistValue(
            Name = 'Production',
            Code = 'PROD',
            Value = 'Production',
            PicklistId = testPicklist.Id
        ));
        picklistValues.add(new AttributePicklistValue(
            Name = 'Non-Production',
            Code = 'NONPROD',
            Value = 'Non-Production',
            PicklistId = testPicklist.Id
        ));
        insert picklistValues;
    }

    // ── CSV Parsing Tests ────────────────────────────────────────────

    @IsTest
    static void testParseCsvLine_Simple() {
        List<String> result = AttributeLoadingService.parseCsvLine('a,b,c');
        System.assertEquals(3, result.size(), 'Should parse 3 cells');
        System.assertEquals('a', result[0]);
        System.assertEquals('b', result[1]);
        System.assertEquals('c', result[2]);
    }

    @IsTest
    static void testParseCsvLine_QuotedValues() {
        List<String> result = AttributeLoadingService.parseCsvLine('a,"b,c",d');
        System.assertEquals(3, result.size(), 'Quoted comma should not split');
        System.assertEquals('a', result[0]);
        System.assertEquals('b,c', result[1]);
        System.assertEquals('d', result[2]);
    }

    @IsTest
    static void testParseCsvLine_EscapedQuotes() {
        List<String> result = AttributeLoadingService.parseCsvLine('a,"say ""hello""",c');
        System.assertEquals(3, result.size());
        System.assertEquals('say "hello"', result[1], 'Escaped quotes should be unescaped');
    }

    @IsTest
    static void testParseCsvLine_EmptyLine() {
        List<String> result = AttributeLoadingService.parseCsvLine('');
        System.assertEquals(0, result.size(), 'Empty line should return empty list');
    }

    @IsTest
    static void testParseCsvLine_WindowsLineEnding() {
        List<String> result = AttributeLoadingService.parseCsvLine('a,b,c\r');
        System.assertEquals(3, result.size(), 'Should strip carriage return');
        System.assertEquals('c', result[2]);
    }

    // ── buildAttributeMap Tests ──────────────────────────────────────

    @IsTest
    static void testBuildAttributeMap_ValidCsv() {
        String csv = 'Legacy_Id__c,Server Type,Deployment Option\n' +
                      TEST_LEGACY_PREFIX + '001,Production,Self Managed\n' +
                      TEST_LEGACY_PREFIX + '002,Non-Production,Managed Service';

        Map<String, Map<String, String>> result =
            AttributeLoadingService.buildAttributeMap(csv);

        System.assertEquals(2, result.size(), 'Should parse 2 data rows');
        System.assert(result.containsKey(TEST_LEGACY_PREFIX + '001'));
        System.assertEquals('Production', result.get(TEST_LEGACY_PREFIX + '001').get('Server Type'));
        System.assertEquals('Self Managed', result.get(TEST_LEGACY_PREFIX + '001').get('Deployment Option'));
    }

    @IsTest
    static void testBuildAttributeMap_EmptyCells() {
        String csv = 'Legacy_Id__c,Server Type,Deployment Option\n' +
                      TEST_LEGACY_PREFIX + '001,,Self Managed';

        Map<String, Map<String, String>> result =
            AttributeLoadingService.buildAttributeMap(csv);

        System.assertEquals(1, result.size());
        Map<String, String> attrs = result.get(TEST_LEGACY_PREFIX + '001');
        System.assertEquals(1, attrs.size(), 'Empty cell should be skipped');
        System.assert(!attrs.containsKey('Server Type'), 'Empty value should not be in map');
        System.assertEquals('Self Managed', attrs.get('Deployment Option'));
    }

    @IsTest
    static void testBuildAttributeMap_WrongHeader() {
        String csv = 'SomeOtherField,Server Type\n' +
                      'ABC,Production';

        Map<String, Map<String, String>> result =
            AttributeLoadingService.buildAttributeMap(csv);

        System.assertEquals(0, result.size(), 'Should return empty when first column is not Legacy_Id__c');
    }

    @IsTest
    static void testBuildAttributeMap_EmptyContent() {
        Map<String, Map<String, String>> result =
            AttributeLoadingService.buildAttributeMap('');

        System.assertEquals(0, result.size());
    }

    // ── extractAttributeNames Tests ──────────────────────────────────

    @IsTest
    static void testExtractAttributeNames() {
        String csv = 'Legacy_Id__c,Server Type,Deployment Option\n' +
                      TEST_LEGACY_PREFIX + '001,Production,Self Managed';

        List<String> names = AttributeLoadingService.extractAttributeNames(csv);

        System.assertEquals(2, names.size());
        System.assertEquals('Server Type', names[0]);
        System.assertEquals('Deployment Option', names[1]);
    }

    // ── Lookup Resolution Tests ──────────────────────────────────────

    @IsTest
    static void testBuildAttrDefMap() {
        Test.startTest();
        Map<String, Id> attrDefMap = AttributeLoadingService.buildAttrDefMap();
        Test.stopTest();

        System.assert(attrDefMap.containsKey('Server Type'),
            'Should find Server Type AttributeDefinition');
        System.assert(attrDefMap.containsKey('Deployment Option'),
            'Should find Deployment Option AttributeDefinition');
    }

    @IsTest
    static void testBuildPicklistValueMap() {
        Map<String, Id> attrDefMap = AttributeLoadingService.buildAttrDefMap();
        Set<Id> attrDefIds = new Set<Id>(attrDefMap.values());

        Test.startTest();
        Map<String, Map<String, Id>> picklistMap =
            AttributeLoadingService.buildPicklistValueMap(attrDefIds);
        Test.stopTest();

        System.assert(picklistMap.containsKey('Server Type'),
            'Server Type should have picklist values');
        Map<String, Id> serverTypeValues = picklistMap.get('Server Type');
        System.assert(serverTypeValues.containsKey('Production'),
            'Should find Production picklist value');
        System.assert(serverTypeValues.containsKey('Non-Production'),
            'Should find Non-Production picklist value');

        // Deployment Option is Text type, should not have picklist values
        System.assert(!picklistMap.containsKey('Deployment Option'),
            'Text-type attribute should not have picklist values');
    }

    @IsTest
    static void testBuildPicklistValueMap_EmptyInput() {
        Map<String, Map<String, Id>> result =
            AttributeLoadingService.buildPicklistValueMap(new Set<Id>());

        System.assert(result.isEmpty(), 'Empty input should return empty map');
    }

    // ── Preview Tests ────────────────────────────────────────────────

    @IsTest
    static void testPreviewLoad_ValidCsv() {
        String csv = 'Legacy_Id__c,Server Type,Deployment Option\n' +
                      TEST_LEGACY_PREFIX + '001,Production,Self Managed\n' +
                      TEST_LEGACY_PREFIX + '002,Non-Production,Managed Service';

        Test.startTest();
        AttributeLoadingService.AttributePreview preview =
            AttributeLoadingService.previewLoad(csv);
        Test.stopTest();

        System.assertEquals(2, preview.rowCount, 'Should count 2 CSV rows');
        System.assertEquals(4, preview.attributeCount, 'Should count 4 total attributes (2 rows x 2 attrs)');
        System.assertEquals(0, preview.unmatchedQliCount, 'All Legacy_Id__c values should match QLIs');
        System.assert(preview.errors.isEmpty(), 'Should have no errors');
        System.assertEquals(2, preview.attributeNames.size(), 'Should find 2 attribute names');
    }

    @IsTest
    static void testPreviewLoad_InvalidAttributeName() {
        String csv = 'Legacy_Id__c,Nonexistent Attribute\n' +
                      TEST_LEGACY_PREFIX + '001,SomeValue';

        Test.startTest();
        AttributeLoadingService.AttributePreview preview =
            AttributeLoadingService.previewLoad(csv);
        Test.stopTest();

        System.assert(!preview.errors.isEmpty(), 'Should have error for invalid attribute name');
        System.assert(preview.errors[0].contains('Nonexistent Attribute'),
            'Error should mention the invalid attribute name');
    }

    @IsTest
    static void testPreviewLoad_InvalidPicklistValue() {
        String csv = 'Legacy_Id__c,Server Type\n' +
                      TEST_LEGACY_PREFIX + '001,InvalidServerType';

        Test.startTest();
        AttributeLoadingService.AttributePreview preview =
            AttributeLoadingService.previewLoad(csv);
        Test.stopTest();

        // Invalid picklist values should generate warnings, not errors
        System.assert(preview.errors.isEmpty(), 'Should have no blocking errors');
        System.assert(!preview.warnings.isEmpty(), 'Should have warning for invalid picklist value');
    }

    @IsTest
    static void testPreviewLoad_UnmatchedLegacyId() {
        String csv = 'Legacy_Id__c,Server Type\n' +
                      'NONEXISTENT_001,Production';

        Test.startTest();
        AttributeLoadingService.AttributePreview preview =
            AttributeLoadingService.previewLoad(csv);
        Test.stopTest();

        System.assertEquals(1, preview.unmatchedQliCount,
            'Should detect 1 unmatched Legacy_Id__c');
        System.assert(!preview.warnings.isEmpty(),
            'Should have warning about unmatched Legacy_Id__c');
    }

    @IsTest
    static void testPreviewLoad_EmptyCsv() {
        Test.startTest();
        AttributeLoadingService.AttributePreview preview =
            AttributeLoadingService.previewLoad('');
        Test.stopTest();

        System.assert(!preview.errors.isEmpty(), 'Should have error for empty CSV');
    }

    /**
     * @description Test previewLoad existing QLIA detection code path.
     *              Note: QuoteLineItemAttribute is an internal sObject that cannot be
     *              created via standard DML in test context. This test verifies the
     *              preview runs correctly when no existing QLIA are found (existingCount = 0).
     *              Full duplicate detection is verified via manual E2E testing.
     */
    @IsTest
    static void testPreviewLoad_ExistingQliaPath() {
        String csv = 'Legacy_Id__c,Server Type\n' +
                      TEST_LEGACY_PREFIX + '001,Production';

        Test.startTest();
        AttributeLoadingService.AttributePreview preview =
            AttributeLoadingService.previewLoad(csv);
        Test.stopTest();

        // With no pre-existing QLIA records (can't create in test context),
        // existingCount should be 0
        System.assertEquals(0, preview.existingCount,
            'Should report 0 existing QLIA in test context');
        System.assertEquals(1, preview.rowCount,
            'Should count 1 CSV row');
        System.assertEquals(1, preview.attributeCount,
            'Should count 1 attribute to create');
    }
}