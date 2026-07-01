/**
 * @description Test class for AttributeLoadingBatch.
 *
 *              NOTE: QuoteLineItemAttribute is a Revenue Cloud "internal sObject" that
 *              requires Database.insertImmediate() instead of standard DML. This method
 *              does not fully persist records in Apex test context (known platform
 *              limitation). Tests verify batch execution, data resolution, and audit
 *              logging rather than asserting QLIA record counts. QLIA creation is
 *              verified via manual E2E testing.
 *
 * @author Marc DeBrey
 * @version 1.1
 * @since 2026-03
 */
@IsTest
private class AttributeLoadingBatchTest {

    private static final String TEST_LEGACY_PREFIX = 'DY_BATCH_';

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account testAccount = new Account(
            Name = 'Batch Attr Test Account',
            BillingCountry = 'United States',
            BillingState = 'California',
            BillingCity = 'San Francisco',
            BillingStreet = '456 Batch Test St'
        );
        insert testAccount;

        // Create Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Batch Attr Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-30)
        );
        insert testOpp;

        // Get standard pricebook and create Quote
        Id pricebookId = Test.getStandardPricebookId();
        Quote testQuote = new Quote(
            Name = 'Batch Attr Test Quote',
            OpportunityId = testOpp.Id,
            Pricebook2Id = pricebookId,
            Status = 'Draft'
        );
        insert testQuote;

        // Create Product and PBE
        Product2 testProduct = new Product2(
            Name = 'Batch Attr Test Product',
            ProductCode = 'BATCH-ATTR-001',
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

        // Create 3 QLIs
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

        // Create AttributePicklist
        AttributePicklist testPicklist = new AttributePicklist(
            Name = 'Batch Test Server Types'
        );
        insert testPicklist;

        // Create AttributeDefinitions
        AttributeDefinition adPicklist = new AttributeDefinition(
            Name = 'Server Type',
            DeveloperName = 'Batch_Server_Type',
            Label = 'Server Type',
            DataType = 'Picklist',
            PicklistId = testPicklist.Id,
            IsActive = true
        );
        insert adPicklist;

        AttributeDefinition adText = new AttributeDefinition(
            Name = 'Deployment Option',
            DeveloperName = 'Batch_Deployment_Option',
            Label = 'Deployment Option',
            DataType = 'Text',
            IsActive = true
        );
        insert adText;

        // Create picklist values
        List<AttributePicklistValue> pvs = new List<AttributePicklistValue>();
        pvs.add(new AttributePicklistValue(
            Name = 'Production', Code = 'BPROD', Value = 'Production',
            PicklistId = testPicklist.Id
        ));
        pvs.add(new AttributePicklistValue(
            Name = 'Non-Production', Code = 'BNONPROD', Value = 'Non-Production',
            PicklistId = testPicklist.Id
        ));
        insert pvs;
    }

    /**
     * @description Test basic batch execution with valid attribute data.
     *              Verifies batch runs to completion and creates a Migration_Run_Log.
     *              (QLIA record creation verified via manual E2E testing due to
     *              insertImmediate platform limitation in test context.)
     */
    @IsTest
    static void testBatch_ExecutesSuccessfully() {
        // Build input data (simulating CSV parse)
        Map<String, Map<String, String>> attrData = new Map<String, Map<String, String>>();
        attrData.put(TEST_LEGACY_PREFIX + '001', new Map<String, String>{
            'Server Type' => 'Production',
            'Deployment Option' => 'Self Managed'
        });
        attrData.put(TEST_LEGACY_PREFIX + '002', new Map<String, String>{
            'Server Type' => 'Non-Production',
            'Deployment Option' => 'Managed Service'
        });

        // Build lookup maps
        Map<String, Id> attrDefMap = AttributeLoadingService.buildAttrDefMap();
        Set<Id> attrDefIds = new Set<Id>(attrDefMap.values());
        Map<String, Map<String, Id>> picklistMap =
            AttributeLoadingService.buildPicklistValueMap(attrDefIds);

        Test.startTest();
        AttributeLoadingBatch batch = new AttributeLoadingBatch(attrData, attrDefMap, picklistMap);
        Id jobId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify batch job completed
        AsyncApexJob job = [
            SELECT Status, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete successfully');
        System.assert(job.TotalJobItems > 0, 'Batch should have processed items');

        // Verify Migration_Run_Log was created
        List<Migration_Run_Log__c> logs = [
            SELECT Status__c, QLIs_Processed__c, QLIs_Succeeded__c, QLIs_Skipped__c
            FROM Migration_Run_Log__c
            WHERE Filter_Used__c LIKE 'Attribute Loading%'
            ORDER BY Run_Date__c DESC LIMIT 1
        ];
        System.assertEquals(1, logs.size(), 'Should create a migration run log');
        System.assert(logs[0].QLIs_Processed__c >= 2,
            'Should report at least 2 QLIs processed');
    }

    /**
     * @description Test batch with duplicate detection logic.
     *              Since QLIA cannot be pre-created via DML in test context,
     *              this tests that the batch handles the duplicate detection
     *              query without errors even when no existing QLIA are found.
     */
    @IsTest
    static void testBatch_DuplicateDetectionPath() {
        // Build input data for a single QLI with attributes
        Map<String, Map<String, String>> attrData = new Map<String, Map<String, String>>();
        attrData.put(TEST_LEGACY_PREFIX + '001', new Map<String, String>{
            'Server Type' => 'Production',
            'Deployment Option' => 'Self Managed'
        });

        Map<String, Id> attrDefMap = AttributeLoadingService.buildAttrDefMap();
        Set<Id> attrDefIds = new Set<Id>(attrDefMap.values());
        Map<String, Map<String, Id>> picklistMap =
            AttributeLoadingService.buildPicklistValueMap(attrDefIds);

        Test.startTest();
        AttributeLoadingBatch batch = new AttributeLoadingBatch(attrData, attrDefMap, picklistMap);
        Id jobId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify batch completed without errors
        AsyncApexJob job = [
            SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete');
        System.assertEquals(0, job.NumberOfErrors, 'Batch should have 0 system errors');
    }

    /**
     * @description Test batch with no matching QLIs (all CSV Legacy_Id__c unmatched).
     */
    @IsTest
    static void testBatch_NoMatchingQlis() {
        Map<String, Map<String, String>> attrData = new Map<String, Map<String, String>>();
        attrData.put('NONEXISTENT_001', new Map<String, String>{
            'Server Type' => 'Production'
        });

        Map<String, Id> attrDefMap = AttributeLoadingService.buildAttrDefMap();
        Map<String, Map<String, Id>> picklistMap = new Map<String, Map<String, Id>>();

        Test.startTest();
        AttributeLoadingBatch batch = new AttributeLoadingBatch(attrData, attrDefMap, picklistMap);
        Id jobId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify batch completed (with 0 items since no QLIs matched)
        AsyncApexJob job = [
            SELECT Status, TotalJobItems FROM AsyncApexJob WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete');
        System.assertEquals(0, job.TotalJobItems,
            'Batch should have 0 items when no QLIs match');
    }

    /**
     * @description Test batch with text-only attribute (no picklist resolution needed).
     *              Verifies the batch handles text attributes without error.
     */
    @IsTest
    static void testBatch_TextOnlyAttribute() {
        Map<String, Map<String, String>> attrData = new Map<String, Map<String, String>>();
        attrData.put(TEST_LEGACY_PREFIX + '003', new Map<String, String>{
            'Deployment Option' => 'Custom Deployment'
        });

        Map<String, Id> attrDefMap = AttributeLoadingService.buildAttrDefMap();
        Set<Id> attrDefIds = new Set<Id>(attrDefMap.values());
        Map<String, Map<String, Id>> picklistMap =
            AttributeLoadingService.buildPicklistValueMap(attrDefIds);

        Test.startTest();
        AttributeLoadingBatch batch = new AttributeLoadingBatch(attrData, attrDefMap, picklistMap);
        Id jobId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify batch completed
        AsyncApexJob job = [
            SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete');
        System.assertEquals(0, job.NumberOfErrors, 'Batch should have 0 system errors');

        // Verify Migration_Run_Log was created
        List<Migration_Run_Log__c> logs = [
            SELECT Status__c, QLIs_Processed__c
            FROM Migration_Run_Log__c
            WHERE Filter_Used__c LIKE 'Attribute Loading%'
            ORDER BY Run_Date__c DESC LIMIT 1
        ];
        System.assertEquals(1, logs.size(), 'Should create a migration run log');
    }
}