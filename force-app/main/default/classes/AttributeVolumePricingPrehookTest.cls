/**
 * @description Test class for AttributeVolumePricingPrehook v3.0
 *              Tests the attribute extraction, tier lookup map, composite-key matching,
 *              and explainer text generation.
 *
 * @author Marc DeBrey
 * @date February 2026
 * @version 3.0
 *
 * Note: The execute() method cannot be fully unit tested because:
 *   1. RevSignaling.TransactionRequest is a managed class with no public constructor
 *   2. Context.IndustriesContext.queryTags() requires a real pricing context
 *   Integration testing should be performed in the org via Quote pricing operations.
 *
 * v3.0 Improvement: Attribute_Tier_Pricing_Storage__c is a custom object, so we CAN
 * insert test data and verify actual query results (unlike the managed PriceAdjustmentTier).
 */
@IsTest
private class AttributeVolumePricingPrehookTest {

    // ========== Test Data Helpers ==========

    /**
     * @description Create test Attribute_Tier_Pricing_Storage__c records
     *              for use across multiple test methods.
     */
    @TestSetup
    static void setupTestData() {
        // We need Product2 and ProductSellingModel records for the lookup keys.
        // Create a minimal product for testing.
        Product2 testProduct = new Product2(
            Name = 'Test Attribute Pricing Product',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert testProduct;

        // Create a ProductSellingModel for the lookup field
        // Org validation requires Code__c and PricingTermUnit = 'Annual'
        ProductSellingModel psm = new ProductSellingModel(
            Name = 'Test PSM - Evergreen',
            SellingModelType = 'Evergreen',
            Status = 'Active',
            PricingTermUnit = 'Annual',
            PricingTerm = 1,
            Code__c = 'TEST_AVP'
        );
        insert psm;

        List<Attribute_Tier_Pricing_Storage__c> tiers = new List<Attribute_Tier_Pricing_Storage__c>{
            // Feature_Options = Platinum, volume 1-100, Unit Price mode
            new Attribute_Tier_Pricing_Storage__c(
                Product__c = testProduct.Id,
                Product_Selling_Model__c = psm.Id,
                Attribute_Name__c = 'Feature_Options',
                Attribute_Value__c = 'Platinum',
                Lower_Bound__c = 1,
                Upper_Bound__c = 100,
                Tier_Value__c = 1000,
                Price_Mode__c = 'Unit Price',
                Multiplier__c = null
            ),
            // Feature_Options = Platinum, volume 101-500, Calculated mode
            new Attribute_Tier_Pricing_Storage__c(
                Product__c = testProduct.Id,
                Product_Selling_Model__c = psm.Id,
                Attribute_Name__c = 'Feature_Options',
                Attribute_Value__c = 'Platinum',
                Lower_Bound__c = 101,
                Upper_Bound__c = 500,
                Tier_Value__c = 950,
                Price_Mode__c = 'Calculated',
                Multiplier__c = 0.95
            ),
            // Feature_Options = Ultimate, volume 1-100, Unit Price mode
            new Attribute_Tier_Pricing_Storage__c(
                Product__c = testProduct.Id,
                Product_Selling_Model__c = psm.Id,
                Attribute_Name__c = 'Feature_Options',
                Attribute_Value__c = 'Ultimate',
                Lower_Bound__c = 1,
                Upper_Bound__c = 100,
                Tier_Value__c = 880,
                Price_Mode__c = 'Unit Price',
                Multiplier__c = null
            ),
            // Support_Level = Premium, volume 1-999, Total Price mode
            new Attribute_Tier_Pricing_Storage__c(
                Product__c = testProduct.Id,
                Product_Selling_Model__c = psm.Id,
                Attribute_Name__c = 'Support_Level',
                Attribute_Value__c = 'Premium',
                Lower_Bound__c = 1,
                Upper_Bound__c = 999,
                Tier_Value__c = 8500,
                Price_Mode__c = 'Total Price',
                Multiplier__c = null
            )
        };
        insert tiers;
    }

    // ========== Class Instantiation ==========

    @IsTest
    static void testClassInstantiation() {
        Test.startTest();
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();
        Test.stopTest();

        System.assertNotEquals(null, hook, 'Hook should be instantiated');
    }

    // ========== getAttributeValue Tests (unchanged) ==========

    @IsTest
    static void testGetAttributeValue() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => 'Feature_Options',
                'AttributeValue' => 'Platinum'
            },
            new Map<String, Object>{
                'Attribute' => 'Some_Other_Attribute',
                'AttributeValue' => 'SomeValue'
            }
        };

        Test.startTest();
        String featureValue = hook.getAttributeValue(attributes, 'Feature_Options');
        String otherValue = hook.getAttributeValue(attributes, 'Some_Other_Attribute');
        String missingValue = hook.getAttributeValue(attributes, 'Non_Existent');
        Test.stopTest();

        System.assertEquals('Platinum', featureValue, 'Feature_Options should be Platinum');
        System.assertEquals('SomeValue', otherValue, 'Some_Other_Attribute should be SomeValue');
        System.assertEquals(null, missingValue, 'Non-existent attribute should return null');
    }

    @IsTest
    static void testGetAttributeValueWithNestedStructure() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => new Map<String, Object>{ 'tagValue' => 'Feature_Options' },
                'AttributeValue' => new Map<String, Object>{ 'tagValue' => 'Ultimate' }
            }
        };

        Test.startTest();
        String featureValue = hook.getAttributeValue(attributes, 'Feature_Options');
        Test.stopTest();

        System.assertNotEquals(null, featureValue, 'Attribute lookup should handle nested structures');
    }

    @IsTest
    static void testGetAttributeValueFromEmptyList() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();
        List<Map<String, Object>> emptyAttributes = new List<Map<String, Object>>();

        Test.startTest();
        String result = hook.getAttributeValue(emptyAttributes, 'Feature_Options');
        Test.stopTest();

        System.assertEquals(null, result, 'Empty attribute list should return null');
    }

    @IsTest
    static void testGetAttributeValueWithAttributeKeyNameFallback() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'AttributeKeyName' => 'Feature_Options',
                'AttributeValue' => 'Ultimate'
            }
        };

        Test.startTest();
        String featureValue = hook.getAttributeValue(attributes, 'Feature_Options');
        Test.stopTest();

        System.assertEquals('Ultimate', featureValue, 'Should fall back to AttributeKeyName');
    }

    @IsTest
    static void testGetAttributeValueWithNullMaps() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => null,
                'AttributeValue' => 'SomeValue'
            },
            new Map<String, Object>{
                'Attribute' => 'Feature_Options',
                'AttributeValue' => null
            }
        };

        Test.startTest();
        String nullAttrName = hook.getAttributeValue(attributes, null);
        String featureValue = hook.getAttributeValue(attributes, 'Feature_Options');
        Test.stopTest();

        System.assertEquals(null, nullAttrName, 'Null attribute name should return null');
        System.assertEquals(null, featureValue, 'Null attribute value should return null');
    }

    // ========== execute() Error Handling ==========

    @IsTest
    static void testExecuteWithInvalidContext() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        // RevSignaling.TransactionRequest is a managed class with no public constructor.
        // Integration testing required for full validation.
        Test.startTest();
        System.assertNotEquals(null, hook, 'Hook should be instantiated');
        Test.stopTest();
    }

    // ========== PricingTierResult Constructor (v3.0) ==========

    @IsTest
    static void testPricingTierResultConstructorV3() {
        // v3.0 uses 5-parameter constructor with attributeName and attributeValue
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        // We can't directly instantiate the private inner class from here,
        // but we can verify via lookupTierFromMap which returns PricingTierResult.
        // This test verifies the constructor indirectly through the lookup path.

        // Build a tier map with test data
        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
            AND Attribute_Value__c = 'Platinum'
            AND Lower_Bound__c = 1
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => 'Feature_Options',
                'AttributeValue' => 'Platinum'
            },
            new Map<String, Object>{
                'Attribute' => 'Attribute_Volume',
                'AttributeValue' => '50'
            }
        };

        Test.startTest();
        // lookupTierFromMap internally creates PricingTierResult with 5-param constructor
        Object result = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a PricingTierResult for matching tier');
    }

    // ========== buildTierLookupMap Tests ==========

    @IsTest
    static void testBuildTierLookupMap() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
        ];

        Test.startTest();
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);
        Test.stopTest();

        // We inserted 4 tiers: 2 for Platinum (different volume ranges), 1 for Ultimate, 1 for Support_Level
        // That means 3 unique composite keys (Platinum has 2 tiers under same key)
        System.assertEquals(3, tierMap.size(), 'Should have 3 unique composite keys');

        // Verify Platinum key has 2 tiers (volume 1-100 and 101-500)
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;
        String platinumKey = testProduct.Id + '|' + testPsmId + '|Feature_Options|Platinum';
        System.assert(tierMap.containsKey(platinumKey), 'Should contain Platinum key');
        System.assertEquals(2, tierMap.get(platinumKey).size(), 'Platinum should have 2 tier records');

        // Verify Ultimate key has 1 tier
        String ultimateKey = testProduct.Id + '|' + testPsmId + '|Feature_Options|Ultimate';
        System.assert(tierMap.containsKey(ultimateKey), 'Should contain Ultimate key');
        System.assertEquals(1, tierMap.get(ultimateKey).size(), 'Ultimate should have 1 tier record');
    }

    @IsTest
    static void testBuildTierLookupMapEmpty() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Test.startTest();
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap =
            hook.buildTierLookupMap(new List<Attribute_Tier_Pricing_Storage__c>());
        Test.stopTest();

        System.assertEquals(0, tierMap.size(), 'Empty input should produce empty map');
    }

    // ========== lookupTierFromMap Tests ==========

    @IsTest
    static void testLookupTierFromMap_MatchFound() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => 'Feature_Options',
                'AttributeValue' => 'Platinum'
            },
            new Map<String, Object>{
                'Attribute' => 'Attribute_Volume',
                'AttributeValue' => '50'
            }
        };

        Test.startTest();
        // Volume 50 should match Platinum 1-100 tier (Unit Price, $1000)
        Object result = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should find matching tier for Platinum vol=50');
    }

    @IsTest
    static void testLookupTierFromMap_CalculatedMode() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => 'Feature_Options',
                'AttributeValue' => 'Platinum'
            },
            new Map<String, Object>{
                'Attribute' => 'Attribute_Volume',
                'AttributeValue' => '250'
            }
        };

        Test.startTest();
        // Volume 250 should match Platinum 101-500 tier (Calculated, $950, 0.95x)
        Object result = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 250);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should find matching tier for Platinum vol=250 (Calculated mode)');
    }

    @IsTest
    static void testLookupTierFromMap_NoMatch() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        // Attribute value 'Gold' does not exist in test data
        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => 'Feature_Options',
                'AttributeValue' => 'Gold'
            },
            new Map<String, Object>{
                'Attribute' => 'Attribute_Volume',
                'AttributeValue' => '50'
            }
        };

        Test.startTest();
        Object result = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for non-matching attribute value');
    }

    @IsTest
    static void testLookupTierFromMap_VolumeOutOfRange() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => 'Feature_Options',
                'AttributeValue' => 'Platinum'
            },
            new Map<String, Object>{
                'Attribute' => 'Attribute_Volume',
                'AttributeValue' => '1000'
            }
        };

        Test.startTest();
        // Volume 1000 is outside both Platinum tiers (1-100, 101-500)
        Object result = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 1000);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when volume is outside all tier ranges');
    }

    @IsTest
    static void testLookupTierFromMap_MultipleAttributes() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        // Line item has multiple attributes; only Support_Level=Premium has a matching tier for vol 50
        // Feature_Options=Gold won't match (no Gold tier), but Support_Level=Premium will
        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Attribute' => 'Feature_Options',
                'AttributeValue' => 'Gold'
            },
            new Map<String, Object>{
                'Attribute' => 'Support_Level',
                'AttributeValue' => 'Premium'
            },
            new Map<String, Object>{
                'Attribute' => 'Attribute_Volume',
                'AttributeValue' => '50'
            }
        };

        Test.startTest();
        Object result = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should find matching tier via Support_Level=Premium');
    }

    @IsTest
    static void testLookupTierFromMap_NullInputs() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' }
        };

        Test.startTest();
        // Null tierMap
        Object nullMap = hook.lookupTierFromMap(null, 'prodId', 'psmId', lineAttributes, 50);
        // Blank productId
        Object blankProduct = hook.lookupTierFromMap(
            new Map<String, List<Attribute_Tier_Pricing_Storage__c>>(), '', 'psmId', lineAttributes, 50);
        // Blank psmId
        Object blankPsm = hook.lookupTierFromMap(
            new Map<String, List<Attribute_Tier_Pricing_Storage__c>>(), 'prodId', '', lineAttributes, 50);
        // Null attributes
        Object nullAttrs = hook.lookupTierFromMap(
            new Map<String, List<Attribute_Tier_Pricing_Storage__c>>(), 'prodId', 'psmId', null, 50);
        // Empty attributes
        Object emptyAttrs = hook.lookupTierFromMap(
            new Map<String, List<Attribute_Tier_Pricing_Storage__c>>(), 'prodId', 'psmId',
            new List<Map<String, Object>>(), 50);
        // Null volume
        Object nullVol = hook.lookupTierFromMap(
            new Map<String, List<Attribute_Tier_Pricing_Storage__c>>(), 'prodId', 'psmId', lineAttributes, null);
        Test.stopTest();

        System.assertEquals(null, nullMap, 'Null tierMap should return null');
        System.assertEquals(null, blankProduct, 'Blank productId should return null');
        System.assertEquals(null, blankPsm, 'Blank psmId should return null');
        System.assertEquals(null, nullAttrs, 'Null attributes should return null');
        System.assertEquals(null, emptyAttrs, 'Empty attributes should return null');
        System.assertEquals(null, nullVol, 'Null volume should return null');
    }

    // ========== buildAttributeExplainerText Tests (v3.0) ==========

    @IsTest
    static void testBuildAttributeExplainerTextV3_UnitPrice() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
            AND Attribute_Value__c = 'Platinum'
            AND Lower_Bound__c = 1
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' },
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '50' }
        };

        // Get a PricingTierResult via lookupTierFromMap
        Object tierResultObj = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);
        System.assertNotEquals(null, tierResultObj, 'Prerequisite: tier result must not be null');

        Test.startTest();
        String explainer = hook.getExplainerTextForTest(tierResultObj, 50);
        Test.stopTest();

        System.assert(explainer.contains('Feature_Options'), 'Explainer should contain attribute name');
        System.assert(explainer.contains('Platinum'), 'Explainer should contain attribute value');
        System.assert(explainer.contains('Vol: 50'), 'Explainer should contain volume');
        System.assert(explainer.contains('Unit: $1000.00'), 'Explainer should contain unit price');
    }

    @IsTest
    static void testBuildAttributeExplainerTextV3_Calculated() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
            AND Attribute_Value__c = 'Platinum'
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' },
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '250' }
        };

        // Volume 250 -> Calculated mode tier (101-500)
        Object tierResultObj = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 250);
        System.assertNotEquals(null, tierResultObj, 'Prerequisite: tier result must not be null');

        Test.startTest();
        String explainer = hook.getExplainerTextForTest(tierResultObj, 250);
        Test.stopTest();

        System.assert(explainer.contains('Feature_Options=Platinum'), 'Explainer should contain attr name=value');
        System.assert(explainer.contains('Vol: 250'), 'Explainer should contain volume');
        System.assert(explainer.contains('Base: $950.00'), 'Explainer should contain base price');
        System.assert(explainer.contains('x 0.95'), 'Explainer should contain multiplier');
    }

    @IsTest
    static void testBuildAttributeExplainerTextV3_TotalPrice() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
            AND Attribute_Name__c = 'Support_Level'
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Support_Level', 'AttributeValue' => 'Premium' },
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '100' }
        };

        Object tierResultObj = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 100);
        System.assertNotEquals(null, tierResultObj, 'Prerequisite: tier result must not be null');

        Test.startTest();
        String explainer = hook.getExplainerTextForTest(tierResultObj, 100);
        Test.stopTest();

        System.assert(explainer.contains('Support_Level=Premium'), 'Explainer should contain attr name=value');
        System.assert(explainer.contains('Total: $8500.00'), 'Explainer should contain total price');
    }

    // ========== Boundary and Edge Case Tests ==========

    @IsTest
    static void testLookupTierFromMap_BoundaryVolume() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
            AND Attribute_Value__c = 'Platinum'
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' },
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '1' }
        };

        Test.startTest();
        // Exact lower bound of first tier (vol=1)
        Object atLower = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 1);
        // Exact upper bound of first tier (vol=100)
        Object atUpper = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 100);
        // Exact lower bound of second tier (vol=101)
        Object atSecondLower = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 101);
        // Exact upper bound of second tier (vol=500)
        Object atSecondUpper = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 500);
        // Just beyond upper bound (vol=501)
        Object beyondUpper = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 501);
        Test.stopTest();

        System.assertNotEquals(null, atLower, 'Vol=1 should match first tier (lower bound)');
        System.assertNotEquals(null, atUpper, 'Vol=100 should match first tier (upper bound)');
        System.assertNotEquals(null, atSecondLower, 'Vol=101 should match second tier (lower bound)');
        System.assertNotEquals(null, atSecondUpper, 'Vol=500 should match second tier (upper bound)');
        System.assertEquals(null, beyondUpper, 'Vol=501 should not match any tier');
    }

    @IsTest
    static void testMultipleFeatureOptionsScenarios() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        // Scenario 1: Platinum feature
        List<Map<String, Object>> platinumAttrs = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' }
        };

        // Scenario 2: Ultimate feature
        List<Map<String, Object>> ultimateAttrs = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Ultimate' }
        };

        // Scenario 3: Missing Feature Options
        List<Map<String, Object>> missingFeature = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Other_Attribute', 'AttributeValue' => 'SomeValue' }
        };

        Test.startTest();
        String feature1 = hook.getAttributeValue(platinumAttrs, 'Feature_Options');
        String feature2 = hook.getAttributeValue(ultimateAttrs, 'Feature_Options');
        String feature3 = hook.getAttributeValue(missingFeature, 'Feature_Options');
        Test.stopTest();

        System.assertEquals('Platinum', feature1, 'Scenario 1: Feature should be Platinum');
        System.assertEquals('Ultimate', feature2, 'Scenario 2: Feature should be Ultimate');
        System.assertEquals(null, feature3, 'Scenario 3: Missing feature should be null');
    }

    // ========== getAttributeVolumeValue Tests ==========

    @IsTest
    static void testGetAttributeVolumeValue() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' },
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '500' }
        };

        Test.startTest();
        Decimal volume = hook.getAttributeVolumeValue(attributes);
        Test.stopTest();

        System.assertEquals(500, volume, 'Should extract volume from Attribute_Volume attribute');
    }

    @IsTest
    static void testGetAttributeVolumeValue_Missing() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' }
        };

        Test.startTest();
        Decimal volume = hook.getAttributeVolumeValue(attributes);
        Test.stopTest();

        System.assertEquals(null, volume, 'Should return null when Attribute_Volume is not present');
    }

    @IsTest
    static void testGetAttributeVolumeValue_NonNumeric() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => 'abc' }
        };

        Test.startTest();
        Decimal volume = hook.getAttributeVolumeValue(attributes);
        Test.stopTest();

        System.assertEquals(null, volume, 'Should return null for non-numeric volume');
    }

    @IsTest
    static void testLookupTierFromMap_AttributeVolumeSkipped() {
        // Verify that Attribute_Volume in lineAttributes does NOT create a false tier key match
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        List<Attribute_Tier_Pricing_Storage__c> tiers = [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :testProduct.Id
        ];

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(tiers);

        // lineAttributes includes Attribute_Volume BEFORE the real tier attribute
        // Attribute_Volume must be skipped so Feature_Options can match
        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '50' },
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' }
        };

        Test.startTest();
        Object result = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should match Feature_Options tier, skipping Attribute_Volume');
    }

    // =====================================================================
    // GROUP F: buildNodeUpdate() -- node assembly per price mode + dataPath guard
    // (added for the node-build / Pass-2 coverage gap)
    // =====================================================================

    /**
     * @description Scenario 1: buildNodeUpdate in Calculated mode. A Calculated-mode tier (Platinum
     *              vol 101-500: base 950, multiplier 0.95) produces THREE attributes including
     *              Attribute_Multiplier_Pct__c. Also verifies the dataPath clone/remove(0).
     */
    @IsTest
    static void testBuildNodeUpdate_CalculatedMode() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(allTiersForProduct(testProduct.Id));

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' },
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '250' }
        };

        // Volume 250 -> Calculated tier (base 950, multiplier 0.95)
        Object tierResultObj = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 250);
        System.assertNotEquals(null, tierResultObj, 'Prerequisite: Calculated tier result must not be null');

        Map<String, Object> itemNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>(),
            new List<Object>{ 'ctx', 'quote', 'LINE-CALC' }
        );

        Test.startTest();
        Map<String, Object> nodeUpdate = hook.buildNodeUpdateForTest(itemNode, tierResultObj, 250);
        Test.stopTest();

        System.assertNotEquals(null, nodeUpdate, 'Calculated-mode node update should not be null');

        List<Object> attrs = (List<Object>) nodeUpdate.get('attributes');
        System.assertEquals(3, attrs.size(), 'Calculated mode should output three attributes');
        System.assertEquals(950, findAttributeValue(attrs, 'Base_Price__c'),
            'Base_Price__c should be the tier value (950)');
        System.assertEquals('Calculated', findAttributeValue(attrs, 'Attribute_Price_Mode__c'),
            'Price mode should be Calculated');
        System.assertEquals(0.95, findAttributeValue(attrs, 'Attribute_Multiplier_Pct__c'),
            'Calculated mode should emit Attribute_Multiplier_Pct__c');

        // dataPath clone/remove(0): first segment dropped
        Map<String, Object> nodePath = (Map<String, Object>) nodeUpdate.get('nodePath');
        List<Object> updatePath = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(2, updatePath.size(), 'updatePath should drop the first dataPath element');
        System.assertEquals('quote', updatePath[0], 'First remaining segment should be quote');
    }

    /**
     * @description Scenario 2: buildNodeUpdate in Unit Price mode. A Unit-Price tier (Platinum vol
     *              1-100: base 1000, no multiplier) produces only TWO attributes -- the
     *              Attribute_Multiplier_Pct__c branch is skipped for non-Calculated modes.
     */
    @IsTest
    static void testBuildNodeUpdate_UnitPriceMode() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(allTiersForProduct(testProduct.Id));

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' },
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '50' }
        };

        // Volume 50 -> Unit Price tier (base 1000)
        Object unitResult = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);
        System.assertNotEquals(null, unitResult, 'Prerequisite: Unit Price tier result must not be null');

        Map<String, Object> itemNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>(),
            new List<Object>{ 'ctx', 'quote', 'LINE-UNIT' }
        );

        Test.startTest();
        Map<String, Object> nodeUpdate = hook.buildNodeUpdateForTest(itemNode, unitResult, 50);
        Test.stopTest();

        List<Object> attrs = (List<Object>) nodeUpdate.get('attributes');
        System.assertEquals(2, attrs.size(),
            'Unit Price mode should output two attributes (no multiplier)');
        System.assertEquals(1000, findAttributeValue(attrs, 'Base_Price__c'),
            'Base_Price__c should be the tier value (1000)');
        System.assertEquals('Unit Price', findAttributeValue(attrs, 'Attribute_Price_Mode__c'),
            'Price mode should be Unit Price');
        System.assertEquals(null, findAttributeValue(attrs, 'Attribute_Multiplier_Pct__c'),
            'Unit Price mode must NOT emit Attribute_Multiplier_Pct__c');
    }

    /**
     * @description Scenario 3: buildNodeUpdate empty-dataPath null guard. An item node with an empty
     *              dataPath returns null (the early guard) -- no update is produced.
     */
    @IsTest
    static void testBuildNodeUpdate_EmptyDataPathReturnsNull() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(allTiersForProduct(testProduct.Id));
        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' },
            new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '50' }
        };
        Object tierResultObj = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);

        // Item node with an EMPTY dataPath
        Map<String, Object> itemNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>(),
            new List<Object>()
        );

        Test.startTest();
        Map<String, Object> nodeUpdate = hook.buildNodeUpdateForTest(itemNode, tierResultObj, 50);
        Test.stopTest();

        System.assertEquals(null, nodeUpdate,
            'buildNodeUpdate must return null when dataPath is empty');
    }

    // =====================================================================
    // GROUP G: buildResetNodeUpdate() -- list-price reset path
    // =====================================================================

    /**
     * @description Scenario 4: buildResetNodeUpdate with ListPrice present. The reset writes
     *              Base_Price__c = the ListPrice tag value and Attribute_Price_Mode__c = 'Unit Price'.
     */
    @IsTest
    static void testBuildResetNodeUpdate_ListPricePresent() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ListPrice' => PricingPrehookTestFixtures.tag(1234.50)
        };
        Map<String, Object> itemNode = PricingPrehookTestFixtures.itemNode(
            tagMap, new List<Object>{ 'ctx', 'quote', 'LINE-RESET' }
        );

        Test.startTest();
        Map<String, Object> resetUpdate = hook.buildResetNodeUpdate(itemNode, tagMap);
        Test.stopTest();

        System.assertNotEquals(null, resetUpdate, 'Reset update should not be null');
        List<Object> attrs = (List<Object>) resetUpdate.get('attributes');
        System.assertEquals(1234.50, findAttributeValue(attrs, 'Base_Price__c'),
            'Reset Base_Price__c should equal the ListPrice tag value');
        System.assertEquals('Unit Price', findAttributeValue(attrs, 'Attribute_Price_Mode__c'),
            'Reset price mode should be Unit Price');

        Map<String, Object> nodePath = (Map<String, Object>) resetUpdate.get('nodePath');
        List<Object> updatePath = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(2, updatePath.size(), 'updatePath should drop the first dataPath element');
    }

    /**
     * @description Scenario 5: buildResetNodeUpdate with ListPrice absent. With no ListPrice tag the
     *              reset defaults Base_Price__c to 0.
     */
    @IsTest
    static void testBuildResetNodeUpdate_ListPriceAbsentDefaultsZero() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>();
        Map<String, Object> itemNode = PricingPrehookTestFixtures.itemNode(
            tagMap, new List<Object>{ 'ctx', 'quote', 'LINE-RESET-0' }
        );

        Test.startTest();
        Map<String, Object> resetUpdate = hook.buildResetNodeUpdate(itemNode, tagMap);
        Test.stopTest();

        List<Object> attrs = (List<Object>) resetUpdate.get('attributes');
        System.assertEquals(0, findAttributeValue(attrs, 'Base_Price__c'),
            'Reset Base_Price__c should default to 0 when ListPrice is absent');
        System.assertEquals('Unit Price', findAttributeValue(attrs, 'Attribute_Price_Mode__c'),
            'Reset price mode should be Unit Price');
    }

    /**
     * @description buildResetNodeUpdate with an empty dataPath returns null (null guard).
     */
    @IsTest
    static void testBuildResetNodeUpdate_EmptyDataPathReturnsNull() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ListPrice' => PricingPrehookTestFixtures.tag(500)
        };
        Map<String, Object> itemNode = PricingPrehookTestFixtures.itemNode(tagMap, new List<Object>());

        Test.startTest();
        Map<String, Object> resetUpdate = hook.buildResetNodeUpdate(itemNode, tagMap);
        Test.stopTest();

        System.assertEquals(null, resetUpdate,
            'buildResetNodeUpdate must return null when dataPath is empty');
    }

    // =====================================================================
    // GROUP H: buildItemNodeUpdates() -- Pass-1/Pass-2 loop seam
    // =====================================================================

    /**
     * @description Scenario 6: Pass-1/Pass-2 loop with four items exercising every branch:
     *              (a) eligible + matching tier -> a Base_Price node update (processed),
     *              (b) eligible + volume absent -> reset-to-list-price update (skipped),
     *              (c) eligible + no tier match -> reset-to-list-price update (skipped),
     *              (d) ineligible (Has_Attribute_Adjustment__c false) -> filtered out in Pass 1.
     *              Covers the eligibility filter, the bulk-SOQL guard, and both reset branches.
     */
    @IsTest
    static void testBuildItemNodeUpdates_PassOneAndTwo() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        // (a) eligible, matches Platinum vol-50 tier
        Map<String, Object> matchItem = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(true),
                'Product' => PricingPrehookTestFixtures.tag(testProduct.Id),
                'ProductSellingModel' => PricingPrehookTestFixtures.tag(testPsmId),
                'Name' => PricingPrehookTestFixtures.tag('Match Line'),
                'ListPrice' => PricingPrehookTestFixtures.tag(2000)
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-MATCH' }
        );
        // (b) eligible, no Attribute_Volume attribute -> reset path
        Map<String, Object> noVolItem = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(true),
                'Product' => PricingPrehookTestFixtures.tag(testProduct.Id),
                'ProductSellingModel' => PricingPrehookTestFixtures.tag(testPsmId),
                'ListPrice' => PricingPrehookTestFixtures.tag(700)
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-NOVOL' }
        );
        // (c) eligible, volume present but value 'Gold' has no tier -> reset path
        Map<String, Object> noMatchItem = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(true),
                'Product' => PricingPrehookTestFixtures.tag(testProduct.Id),
                'ProductSellingModel' => PricingPrehookTestFixtures.tag(testPsmId),
                'ListPrice' => PricingPrehookTestFixtures.tag(900)
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-NOMATCH' }
        );
        // (d) ineligible -> dropped in Pass 1
        Map<String, Object> ineligibleItem = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(false),
                'Product' => PricingPrehookTestFixtures.tag(testProduct.Id),
                'ProductSellingModel' => PricingPrehookTestFixtures.tag(testPsmId)
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-INELIGIBLE' }
        );

        List<Object> lineItemData = new List<Object>{ matchItem, noVolItem, noMatchItem, ineligibleItem };

        // Attributes keyed by line-item id (last dataPath segment)
        Map<String, List<Map<String, Object>>> attrsByLine = new Map<String, List<Map<String, Object>>>{
            'LINE-MATCH' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' },
                new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '50' }
            },
            // noVolItem has Feature_Options but NO Attribute_Volume -> volume null -> reset
            'LINE-NOVOL' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Platinum' }
            },
            // noMatchItem has a volume but value 'Gold' has no tier -> reset
            'LINE-NOMATCH' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Gold' },
                new Map<String, Object>{ 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '50' }
            }
        };

        Test.startTest();
        Object resultObj = hook.buildItemNodeUpdates(lineItemData, attrsByLine);
        Test.stopTest();

        // resultObj is the @TestVisible ItemUpdateResult inner type; read its fields reflectively
        // via JSON to avoid a private-inner-class variable declaration.
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(resultObj));
        List<Object> updates = (List<Object>) result.get('itemNodeUpdates');

        System.assertNotEquals(null, updates, 'Update list should not be null with eligible items present');
        // 1 match (Base_Price node) + 2 resets (no-vol, no-match) = 3 updates; ineligible dropped
        System.assertEquals(3, updates.size(),
            'One matched update plus two reset updates should be produced');
        System.assertEquals('1', String.valueOf(result.get('processedCount')),
            'Exactly one item should be processed (the matching tier)');
        // Pass-1 drops the ineligible item entirely (it is never entered in Pass-2), so only the
        // two reset paths (no-vol, no-match) increment skippedCount.
        System.assertEquals('2', String.valueOf(result.get('skippedCount')),
            'Two Pass-2 items should be counted as skipped (no-vol reset, no-match reset)');

        // Verify the matched update carries the tier base price (1000) and the resets carry list prices.
        // Numbers survive the JSON round-trip as Integer or Double, so compare by Decimal VALUE
        // (1000 == 1000.0) rather than by string form.
        Boolean sawMatchBase = false;
        Boolean sawResetSevenHundred = false;
        Boolean sawResetNineHundred = false;
        for (Object u : updates) {
            Map<String, Object> upd = (Map<String, Object>) u;
            List<Object> attrs = (List<Object>) upd.get('attributes');
            Object basePriceObj = findAttributeValue(attrs, 'Base_Price__c');
            String mode = (String) findAttributeValue(attrs, 'Attribute_Price_Mode__c');
            if (mode != 'Unit Price' || basePriceObj == null) {
                continue;
            }
            Decimal basePrice = Decimal.valueOf(String.valueOf(basePriceObj));
            if (basePrice == 1000) {
                sawMatchBase = true; // matched Platinum 1-100 Unit Price tier (base 1000)
            } else if (basePrice == 700) {
                sawResetSevenHundred = true; // no-vol reset to its ListPrice 700
            } else if (basePrice == 900) {
                sawResetNineHundred = true; // no-match reset to its ListPrice 900
            }
        }
        System.assert(sawMatchBase, 'Matched line should write tier Base_Price__c=1000');
        System.assert(sawResetSevenHundred, 'No-volume line should reset to its ListPrice (700)');
        System.assert(sawResetNineHundred, 'No-match line should reset to its ListPrice (900)');
    }

    /**
     * @description buildItemNodeUpdates short-circuit: when no items are eligible
     *              (Has_Attribute_Adjustment__c not true) the core returns a null update list and
     *              records the 'No eligible line items' message in earlyReturnMessage.
     */
    @IsTest
    static void testBuildItemNodeUpdates_NoEligibleItems() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Map<String, Object> ineligible = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(false)
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-NONE' }
        );

        Test.startTest();
        Object resultObj = hook.buildItemNodeUpdates(
            new List<Object>{ ineligible }, new Map<String, List<Map<String, Object>>>()
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(resultObj));
        System.assertEquals(null, result.get('itemNodeUpdates'),
            'No eligible items should yield a null update list');
        System.assertEquals('No eligible line items (Has_Attribute_Adjustment__c = true)',
            hook.earlyReturnMessage, 'earlyReturnMessage should carry the no-eligible-items string');
    }

    /**
     * @description buildItemNodeUpdates short-circuit: an eligible item whose Product/PSM have no
     *              tier rows yields the 'No matching Attribute_Tier_Pricing_Storage__c records' string.
     */
    @IsTest
    static void testBuildItemNodeUpdates_NoTierRecords() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        // A Product/PSM id pair that does NOT exist in the @TestSetup tier rows
        Map<String, Object> eligibleNoTiers = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(true),
                'Product' => PricingPrehookTestFixtures.tag('01t000000000000AAA'),
                'ProductSellingModel' => PricingPrehookTestFixtures.tag('0jP000000000000AAA')
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-NOTIER' }
        );

        Test.startTest();
        Object resultObj = hook.buildItemNodeUpdates(
            new List<Object>{ eligibleNoTiers }, new Map<String, List<Map<String, Object>>>()
        );
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(resultObj));
        System.assertEquals(null, result.get('itemNodeUpdates'),
            'An eligible item with no tier rows should yield a null update list');
        System.assertEquals('No matching Attribute_Tier_Pricing_Storage__c records found for eligible products',
            hook.earlyReturnMessage, 'earlyReturnMessage should carry the no-tier-records string');
    }

    // =====================================================================
    // GROUP I: queryLineItemAttributes grouping + getParentIdFromDataPath
    // =====================================================================

    /**
     * @description Scenario 7: attribute grouping. One attribute node carries ParentReference; a
     *              second resolves its parent from the dataPath parent segment. Both are grouped under
     *              their respective line-item ids, covering both parent-resolution branches and
     *              getParentIdFromDataPath.
     */
    @IsTest
    static void testGroupAttributesByLineItem_ParentResolution() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        // (1) attribute with an explicit ParentReference tag
        Map<String, Object> attrWithParentRef = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'ParentReference' => PricingPrehookTestFixtures.tag('LINE-A'),
                'Attribute' => PricingPrehookTestFixtures.tag('Feature_Options'),
                'AttributeValue' => PricingPrehookTestFixtures.tag('Platinum')
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-A', 'ATTR-1' }
        );
        // (2) attribute with NO ParentReference -> parent comes from dataPath (second-to-last = LINE-B)
        Map<String, Object> attrWithDataPathParent = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Attribute' => PricingPrehookTestFixtures.tag('Support_Level'),
                'AttributeValue' => PricingPrehookTestFixtures.tag('Premium')
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-B', 'ATTR-2' }
        );
        // (3) attribute with neither ParentReference nor a 2+ element dataPath -> dropped
        Map<String, Object> attrNoParent = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Attribute' => PricingPrehookTestFixtures.tag('Orphan')
            },
            new List<Object>{ 'ATTR-3' }
        );

        List<Object> attributeData = new List<Object>{
            attrWithParentRef, attrWithDataPathParent, attrNoParent
        };
        Map<String, List<Map<String, Object>>> out = new Map<String, List<Map<String, Object>>>();

        Test.startTest();
        hook.groupAttributesByLineItem(attributeData, out);
        Test.stopTest();

        System.assertEquals(2, out.size(),
            'Two attributes should group (one via ParentReference, one via dataPath parent); the orphan is dropped');
        System.assert(out.containsKey('LINE-A'), 'ParentReference attribute should group under LINE-A');
        System.assert(out.containsKey('LINE-B'), 'dataPath-parent attribute should group under LINE-B');
        System.assertEquals(1, out.get('LINE-A').size(), 'LINE-A should have one attribute');
        System.assertEquals(1, out.get('LINE-B').size(), 'LINE-B should have one attribute');
    }

    /**
     * @description getParentIdFromDataPath and getLineItemIdFromDataPath direct coverage, including
     *              the short-dataPath null guards.
     */
    @IsTest
    static void testDataPathHelpers() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Map<String, Object> childNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>(), new List<Object>{ 'ctx', 'LINE-X', 'ATTR-1' }
        );
        Map<String, Object> shortNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>(), new List<Object>{ 'ONLY-ONE' }
        );
        Map<String, Object> emptyNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>(), new List<Object>()
        );

        Test.startTest();
        String parentId = hook.getParentIdFromDataPath(childNode);
        String parentShort = hook.getParentIdFromDataPath(shortNode);
        String lineId = hook.getLineItemIdFromDataPath(childNode);
        String lineEmpty = hook.getLineItemIdFromDataPath(emptyNode);
        Test.stopTest();

        System.assertEquals('LINE-X', parentId, 'Parent id should be the second-to-last dataPath segment');
        System.assertEquals(null, parentShort, 'A single-element dataPath should yield a null parent id');
        System.assertEquals('ATTR-1', lineId, 'Line item id should be the last dataPath segment');
        System.assertEquals(null, lineEmpty, 'An empty dataPath should yield a null line item id');
    }

    // =====================================================================
    // GROUP J: submitContextUpdates() live-call catch + getBooleanFromTag
    // =====================================================================

    /**
     * @description submitContextUpdates against an unbound IndustriesContext with a bogus context id.
     *              updateContextAttributes throws; the catch inspects the message. A
     *              'not in updatable state' message returns the delete-skip string; any other message
     *              returns the 'Context update failed' string. Either outcome exercises the try/catch
     *              and message-detection branch (behavior-preserving).
     */
    @IsTest
    static void testSubmitContextUpdates_CatchOnBadContext() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();
        Context.IndustriesContext ctx = new Context.IndustriesContext();

        List<Map<String, Object>> updates = new List<Map<String, Object>>{
            new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => new List<Object>{ 'quote', 'LINE-1' } },
                'attributes' => new List<Object>{
                    new Map<String, Object>{ 'attributeName' => 'Base_Price__c', 'attributeValue' => 100 }
                }
            }
        };

        Test.startTest();
        String message;
        Boolean propagated = false;
        try {
            message = hook.submitContextUpdates(ctx, 'bogus-context-id', updates, 1, 0);
        } catch (Exception e) {
            // The class catches inside submitContextUpdates and returns a string rather than throwing,
            // so any propagation here would itself be a deviation; record it for the assert.
            propagated = true;
        }
        Test.stopTest();

        System.assertEquals(false, propagated,
            'submitContextUpdates must catch the update failure and return a status string, not throw');
        System.assertNotEquals(null, message,
            'submitContextUpdates should return a non-null status string from its catch branch');
    }

    /**
     * @description Scenario 8: getBooleanFromTag coercions. Covers Boolean true, the string values
     *              'true'/'1'/'yes', a false-y string, and the null (missing key) path.
     */
    @IsTest
    static void testGetBooleanFromTag_Coercions() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'BoolTrue' => PricingPrehookTestFixtures.tag(true),
            'StrTrue' => PricingPrehookTestFixtures.tag('true'),
            'StrOne' => PricingPrehookTestFixtures.tag('1'),
            'StrYes' => PricingPrehookTestFixtures.tag('YES'),
            'StrFalse' => PricingPrehookTestFixtures.tag('false'),
            'BoolFalse' => PricingPrehookTestFixtures.tag(false)
        };

        Test.startTest();
        Boolean boolTrue = hook.getBooleanFromTag(tagMap, 'BoolTrue');
        Boolean strTrue = hook.getBooleanFromTag(tagMap, 'StrTrue');
        Boolean strOne = hook.getBooleanFromTag(tagMap, 'StrOne');
        Boolean strYes = hook.getBooleanFromTag(tagMap, 'StrYes');
        Boolean strFalse = hook.getBooleanFromTag(tagMap, 'StrFalse');
        Boolean boolFalse = hook.getBooleanFromTag(tagMap, 'BoolFalse');
        Boolean missing = hook.getBooleanFromTag(tagMap, 'NotThere');
        Test.stopTest();

        System.assertEquals(true, boolTrue, 'Boolean true should coerce to true');
        System.assertEquals(true, strTrue, 'String "true" should coerce to true');
        System.assertEquals(true, strOne, 'String "1" should coerce to true');
        System.assertEquals(true, strYes, 'String "YES" should coerce to true (case-insensitive)');
        System.assertEquals(false, strFalse, 'String "false" should coerce to false');
        System.assertEquals(false, boolFalse, 'Boolean false should coerce to false');
        System.assertEquals(null, missing, 'A missing key should return null');
    }

    /**
     * @description queryLineItems / queryLineItemAttributes live-context wrappers against an unbound
     *              IndustriesContext with a bogus context id. queryLineItemAttributes SWALLOWS the
     *              failure and returns an empty map (degrade gracefully); queryLineItems does NOT wrap
     *              its queryTags call, so a failure there propagates. Both contracts are asserted to
     *              preserve the original behavior.
     */
    @IsTest
    static void testQueryWrappers_LiveContextContracts() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();
        Context.IndustriesContext ctx = new Context.IndustriesContext();

        Test.startTest();

        // queryLineItemAttributes: swallow-and-continue -> empty map (never throws)
        Map<String, List<Map<String, Object>>> attrs;
        Boolean attrsThrew = false;
        try {
            attrs = hook.queryLineItemAttributes(ctx, 'bogus-context-id');
        } catch (Exception e) {
            attrsThrew = true;
        }

        // queryLineItems: unwrapped -> queryTags failure propagates
        Boolean itemsThrew = false;
        try {
            hook.queryLineItems(ctx, 'bogus-context-id');
        } catch (Exception e) {
            itemsThrew = true;
        }

        Test.stopTest();

        System.assertEquals(false, attrsThrew,
            'queryLineItemAttributes must swallow a live failure and not throw');
        System.assertNotEquals(null, attrs,
            'queryLineItemAttributes should return a (possibly empty) map after swallowing');
        System.assert(attrs.isEmpty(),
            'A failed/empty attribute query should yield an empty grouping map');
        System.assertEquals(true, itemsThrew,
            'queryLineItems must let a queryTags failure propagate (no swallow)');
    }

    /**
     * @description Pass-2 defensive skip guards: an eligible item whose dataPath yields a blank
     *              line-item id, and an eligible item missing its Product context tag, are both
     *              skipped (not turned into updates). Covers the two early-continue branches in the
     *              Pass-2 loop without producing any node update.
     */
    @IsTest
    static void testBuildItemNodeUpdates_Pass2SkipGuards() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        // (a) eligible, but dataPath is empty -> getLineItemIdFromDataPath returns blank -> skip
        Map<String, Object> blankIdItem = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(true),
                'Product' => PricingPrehookTestFixtures.tag(testProduct.Id),
                'ProductSellingModel' => PricingPrehookTestFixtures.tag(testPsmId)
            },
            new List<Object>()
        );
        // (b) eligible, valid line id, but NO Product tag -> blank productId -> skip
        Map<String, Object> noProductItem = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(true),
                'ProductSellingModel' => PricingPrehookTestFixtures.tag(testPsmId)
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-NOPROD' }
        );
        // (c) eligible, valid line id, has Product/PSM, but no attributes mapped -> no-attributes skip
        Map<String, Object> noAttrsItem = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Has_Attribute_Adjustment__c' => PricingPrehookTestFixtures.tag(true),
                'Product' => PricingPrehookTestFixtures.tag(testProduct.Id),
                'ProductSellingModel' => PricingPrehookTestFixtures.tag(testPsmId)
            },
            new List<Object>{ 'ctx', 'quote', 'LINE-NOATTRS' }
        );

        List<Object> lineItemData = new List<Object>{ blankIdItem, noProductItem, noAttrsItem };
        // No attribute mappings provided for any line id.
        Map<String, List<Map<String, Object>>> attrsByLine = new Map<String, List<Map<String, Object>>>();

        Test.startTest();
        Object resultObj = hook.buildItemNodeUpdates(lineItemData, attrsByLine);
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(resultObj));
        List<Object> updates = (List<Object>) result.get('itemNodeUpdates');
        System.assertNotEquals(null, updates, 'Eligible items present -> non-null (empty) update list');
        System.assertEquals(0, updates.size(),
            'All three eligible items hit a Pass-2 skip guard -> no node updates produced');
        System.assertEquals('3', String.valueOf(result.get('skippedCount')),
            'Blank-id, missing-Product, and no-attributes items should all count as skipped');
    }

    /**
     * @description buildResetNodeUpdate with a non-numeric ListPrice tag. getDecimalFromTag fails to
     *              parse and returns null, so the reset defaults Base_Price__c to 0. Covers the
     *              getDecimalFromTag catch branch via the reset path.
     */
    @IsTest
    static void testBuildResetNodeUpdate_NonNumericListPriceDefaultsZero() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Map<String, Object> tagMap = new Map<String, Object>{
            'ListPrice' => PricingPrehookTestFixtures.tag('not-a-number')
        };
        Map<String, Object> itemNode = PricingPrehookTestFixtures.itemNode(
            tagMap, new List<Object>{ 'ctx', 'quote', 'LINE-BADPRICE' }
        );

        Test.startTest();
        Map<String, Object> resetUpdate = hook.buildResetNodeUpdate(itemNode, tagMap);
        Test.stopTest();

        List<Object> attrs = (List<Object>) resetUpdate.get('attributes');
        System.assertEquals(0, findAttributeValue(attrs, 'Base_Price__c'),
            'A non-numeric ListPrice should parse to null and default Base_Price__c to 0');
    }

    /**
     * @description lookupTierFromMap AttributeKeyName fallback + blank-attribute skip. An attribute
     *              that supplies its name only via AttributeKeyName (no 'Attribute') must still match,
     *              and a fully-blank attribute entry is skipped without error.
     */
    @IsTest
    static void testLookupTierFromMap_AttributeKeyNameFallbackAndBlankSkip() {
        AttributeVolumePricingPrehook hook = new AttributeVolumePricingPrehook();

        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Attribute Pricing Product' LIMIT 1];
        String testPsmId = [SELECT Product_Selling_Model__c FROM Attribute_Tier_Pricing_Storage__c LIMIT 1].Product_Selling_Model__c;

        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = hook.buildTierLookupMap(allTiersForProduct(testProduct.Id));

        List<Map<String, Object>> lineAttributes = new List<Map<String, Object>>{
            // blank attribute (both name keys missing) -> skipped
            new Map<String, Object>{ 'AttributeValue' => 'Platinum' },
            // name only via AttributeKeyName fallback
            new Map<String, Object>{ 'AttributeKeyName' => 'Feature_Options', 'AttributeValue' => 'Platinum' }
        };

        Test.startTest();
        Object result = hook.lookupTierFromMap(tierMap, testProduct.Id, testPsmId, lineAttributes, 50);
        Test.stopTest();

        System.assertNotEquals(null, result,
            'Should match via the AttributeKeyName fallback after skipping the blank attribute');
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    /**
     * @description Loads all @TestSetup tier rows for the given product, with the full field set
     *              needed by buildTierLookupMap / lookupTierFromMap.
     */
    private static List<Attribute_Tier_Pricing_Storage__c> allTiersForProduct(Id productId) {
        return [
            SELECT Id, Product__c, Product_Selling_Model__c,
                   Attribute_Name__c, Attribute_Value__c,
                   Lower_Bound__c, Upper_Bound__c,
                   Tier_Value__c, Multiplier__c, Price_Mode__c
            FROM Attribute_Tier_Pricing_Storage__c
            WHERE Product__c = :productId
        ];
    }

    /**
     * @description Finds the attributeValue for a given attributeName in a list of
     *              {attributeName, attributeValue} maps. Returns null when absent.
     */
    private static Object findAttributeValue(List<Object> attrs, String attributeName) {
        for (Object o : attrs) {
            Map<String, Object> attr = (Map<String, Object>) o;
            if (attributeName.equals(attr.get('attributeName'))) {
                return attr.get('attributeValue');
            }
        }
        return null;
    }
}