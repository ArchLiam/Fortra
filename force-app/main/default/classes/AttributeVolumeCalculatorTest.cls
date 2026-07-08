/**
 * @description Unit tests for AttributeVolumeCalculator (SC-3390 / Wave-2 decomposition, round 2).
 *              Exercises the pure seams extracted verbatim from AttributeVolumePricingPrehook —
 *              composite-key tier map + volume->tier resolution (range checks, first-match, key
 *              normalization, Attribute_Volume skip, AttributeKeyName fallback), matched-tier node
 *              shaping across the three price modes, the SC-3390 / D-17 reset-to-list payload,
 *              explainer text, attribute/volume reads, dataPath id extraction, attribute grouping,
 *              and the tag helpers (flat + nested {tagValue} wrapper). No SOQL/DML — all pure; tier
 *              records are built in memory (15-char reference Ids, no checksum).
 */
@isTest
private class AttributeVolumeCalculatorTest {

    // 18-char reference Ids with the correct key prefixes. NOTE: a reference field pads a 15-char
    // Id to 18 on read, so the tier map key (built from tier.Product__c) must be compared against
    // the SAME 18-char form the lookup receives — using 18-char literals here keeps both sides equal.
    private static final String PRODUCT_ID = '01t000000000001AAA';   // Product2
    private static final String PSM_ID     = '0jP000000000001EAA';   // ProductSellingModel

    // ---- builders -------------------------------------------------------------

    private static Attribute_Tier_Pricing_Storage__c tier(
        String attrName, String attrValue, Decimal lower, Decimal upper,
        Decimal tierValue, Decimal mult, String mode
    ) {
        return new Attribute_Tier_Pricing_Storage__c(
            Product__c = PRODUCT_ID,
            Product_Selling_Model__c = PSM_ID,
            Attribute_Name__c = attrName,
            Attribute_Value__c = attrValue,
            Lower_Bound__c = lower,
            Upper_Bound__c = upper,
            Tier_Value__c = tierValue,
            Multiplier__c = mult,
            Price_Mode__c = mode
        );
    }

    private static Map<String, Object> attrMap(String name, String value) {
        return new Map<String, Object>{ 'Attribute' => name, 'AttributeValue' => value };
    }

    private static Map<String, Object> itemNode(List<Object> dataPath, Map<String, Object> tagMap) {
        return new Map<String, Object>{ 'dataPath' => dataPath, 'tagValue' => tagMap };
    }

    private static Map<String, Decimal> flattenDec(List<Object> attrs) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            Object v = a.get('attributeValue');
            if (v instanceof Decimal || v instanceof Integer) {
                out.put(String.valueOf(a.get('attributeName')), (Decimal) v);
            }
        }
        return out;
    }

    private static Map<String, String> flattenStr(List<Object> attrs) {
        Map<String, String> out = new Map<String, String>();
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            out.put(String.valueOf(a.get('attributeName')), String.valueOf(a.get('attributeValue')));
        }
        return out;
    }

    // ---- buildTierLookupMap + lookupTierFromMap -------------------------------

    @isTest
    static void lookupTier_matchWithinRange_calculated() {
        List<Attribute_Tier_Pricing_Storage__c> tiers = new List<Attribute_Tier_Pricing_Storage__c>{
            tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated'),
            tier('Feature_Options', 'Gold', 101, 500, 400, 1.10, 'Calculated')
        };
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(tiers);
        System.assertEquals(1, tierMap.size(), 'same key folds the two volume ranges into one entry');

        List<Map<String, Object>> attrs = new List<Map<String, Object>>{
            attrMap('Feature_Options', 'Gold'),
            attrMap('Attribute_Volume', '50')
        };
        AttributeVolumeCalculator.PricingTierResult r =
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50);
        System.assertNotEquals(null, r, 'volume 50 is in [0,100]');
        System.assertEquals(500, r.basePrice);
        System.assertEquals(1.25, r.multiplier);
        System.assertEquals('Calculated', r.priceMode);
        System.assertEquals('Feature_Options', r.attributeName);
        System.assertEquals('Gold', r.attributeValue);
    }

    @isTest
    static void lookupTier_secondRange_matches() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated'),
                tier('Feature_Options', 'Gold', 101, 500, 400, 1.10, 'Calculated')
            });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        AttributeVolumeCalculator.PricingTierResult r =
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 250);
        System.assertEquals(400, r.basePrice, 'volume 250 falls in the [101,500] range');
    }

    @isTest
    static void lookupTier_openUpperBound_matchesAnyAboveLower() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature_Options', 'Gold', 100, null, 300, null, 'Unit Price')
            });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertNotEquals(null,
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 99999),
            'null upper bound is open-ended');
        System.assertEquals(null,
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50),
            'below lower bound => no match');
    }

    @isTest
    static void lookupTier_outOfRange_null() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated')
            });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertEquals(null,
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 101),
            'volume above the only range => no tier');
    }

    @isTest
    static void lookupTier_keyNormalization_spaceToUnderscore() {
        // tier stored with a SPACE in the attribute name; context uses an UNDERSCORE -> must match
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature Options', 'Gold', 0, 100, 500, 1.25, 'Calculated')
            });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertNotEquals(null,
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50),
            'space/underscore normalization aligns tier and context keys');
    }

    @isTest
    static void lookupTier_skipsAttributeVolumeAndBlanks_usesKeyName() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated')
            });
        // Attribute_Volume is skipped; a blank-value attr is skipped; AttributeKeyName is the fallback name
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{
            attrMap('Attribute_Volume', '50'),
            new Map<String, Object>{ 'Attribute' => 'Blank_Attr', 'AttributeValue' => '' },
            new Map<String, Object>{ 'AttributeKeyName' => 'Feature_Options', 'AttributeValue' => 'Gold' }
        };
        AttributeVolumeCalculator.PricingTierResult r =
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50);
        System.assertNotEquals(null, r, 'AttributeKeyName fallback resolves the tier key');
        System.assertEquals('Feature_Options', r.attributeName);
    }

    @isTest
    static void lookupTier_guardClauses_returnNull() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{ tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated') });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(null, PRODUCT_ID, PSM_ID, attrs, 50), 'null map');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, '', PSM_ID, attrs, 50), 'blank product');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, '', attrs, 50), 'blank psm');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, null, 50), 'null attrs');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, new List<Map<String, Object>>(), 50), 'empty attrs');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, null), 'null volume');
    }

    // ---- buildNodeUpdate ------------------------------------------------------

    @isTest
    static void buildNodeUpdate_calculated_writesThreeAttrsAndStripsPath() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, new Map<String, Object>());
        AttributeVolumeCalculator.PricingTierResult r =
            new AttributeVolumeCalculator.PricingTierResult(1.25, 'Calculated', 500, 'Feature_Options', 'Gold');
        Map<String, Object> u = AttributeVolumeCalculator.buildNodeUpdate(node, r, 50);

        Map<String, Object> np = (Map<String, Object>) u.get('nodePath');
        List<Object> path = (List<Object>) np.get('dataPath');
        System.assertEquals(2, path.size(), 'context-path element stripped');
        System.assertEquals('root', String.valueOf(path[0]));
        System.assertEquals('line', String.valueOf(path[1]));

        List<Object> attrs = (List<Object>) u.get('attributes');
        System.assertEquals(3, attrs.size(), 'Calculated w/ multiplier => 3 attributes');
        Map<String, Decimal> dec = flattenDec(attrs);
        Map<String, String> str = flattenStr(attrs);
        System.assertEquals(500, dec.get('Base_Price__c'));
        System.assertEquals('Calculated', str.get('Attribute_Price_Mode__c'));
        System.assertEquals(1.25, dec.get('Attribute_Multiplier_Pct__c'));
    }

    @isTest
    static void buildNodeUpdate_unitPrice_noMultiplier() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, new Map<String, Object>());
        AttributeVolumeCalculator.PricingTierResult r =
            new AttributeVolumeCalculator.PricingTierResult(null, 'Unit Price', 300, 'Feature_Options', 'Gold');
        List<Object> attrs = (List<Object>) AttributeVolumeCalculator.buildNodeUpdate(node, r, 50).get('attributes');
        System.assertEquals(2, attrs.size(), 'Unit Price => 2 attributes (no multiplier)');
        System.assert(!flattenDec(attrs).containsKey('Attribute_Multiplier_Pct__c'));
    }

    @isTest
    static void buildNodeUpdate_calculatedNullMultiplier_noMultiplierAttr() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, new Map<String, Object>());
        AttributeVolumeCalculator.PricingTierResult r =
            new AttributeVolumeCalculator.PricingTierResult(null, 'Calculated', 500, 'Feature_Options', 'Gold');
        List<Object> attrs = (List<Object>) AttributeVolumeCalculator.buildNodeUpdate(node, r, 50).get('attributes');
        System.assertEquals(2, attrs.size(), 'Calculated but null multiplier => no multiplier attr written');
    }

    @isTest
    static void buildNodeUpdate_nullDataPath_returnsNull() {
        Map<String, Object> node = itemNode(new List<Object>(), new Map<String, Object>());
        AttributeVolumeCalculator.PricingTierResult r =
            new AttributeVolumeCalculator.PricingTierResult(1.25, 'Calculated', 500, 'Feature_Options', 'Gold');
        System.assertEquals(null, AttributeVolumeCalculator.buildNodeUpdate(node, r, 50), 'empty dataPath => null');
    }

    // ---- buildResetNodeUpdate (SC-3390 / D-17) --------------------------------

    @isTest
    static void buildResetNodeUpdate_writesListPriceAsUnitPrice() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, null);
        Map<String, Object> tagMap = new Map<String, Object>{ 'ListPrice' => 2600 };
        Map<String, Object> u = AttributeVolumeCalculator.buildResetNodeUpdate(node, tagMap);

        List<Object> path = (List<Object>) ((Map<String, Object>) u.get('nodePath')).get('dataPath');
        System.assertEquals(2, path.size(), 'context-path element stripped');

        List<Object> attrs = (List<Object>) u.get('attributes');
        System.assertEquals(2, attrs.size());
        System.assertEquals(2600, flattenDec(attrs).get('Base_Price__c'), 'ListPrice reset onto Base_Price__c');
        System.assertEquals('Unit Price', flattenStr(attrs).get('Attribute_Price_Mode__c'), 'reset mode is Unit Price');
    }

    @isTest
    static void buildResetNodeUpdate_nullListPrice_zero() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, null);
        List<Object> attrs = (List<Object>) AttributeVolumeCalculator.buildResetNodeUpdate(node, new Map<String, Object>()).get('attributes');
        System.assertEquals(0, flattenDec(attrs).get('Base_Price__c'), 'missing ListPrice => 0');
    }

    @isTest
    static void buildResetNodeUpdate_nullDataPath_null() {
        Map<String, Object> node = itemNode(new List<Object>(), null);
        System.assertEquals(null, AttributeVolumeCalculator.buildResetNodeUpdate(node, new Map<String, Object>{ 'ListPrice' => 100 }));
    }

    // ---- buildAttributeExplainerText ------------------------------------------

    @isTest
    static void explainer_allThreeModes() {
        AttributeVolumeCalculator.PricingTierResult calc =
            new AttributeVolumeCalculator.PricingTierResult(1.25, 'Calculated', 500, 'Feature_Options', 'Gold');
        System.assert(AttributeVolumeCalculator.buildAttributeExplainerText(calc, 50).contains('Base: $500.00 x 1.25'),
            'Calculated explainer shows base x multiplier');
        AttributeVolumeCalculator.PricingTierResult unit =
            new AttributeVolumeCalculator.PricingTierResult(null, 'Unit Price', 300, 'Feature_Options', 'Gold');
        System.assert(AttributeVolumeCalculator.buildAttributeExplainerText(unit, 50).contains('Unit: $300.00'));
        AttributeVolumeCalculator.PricingTierResult tot =
            new AttributeVolumeCalculator.PricingTierResult(null, 'Total Price', 999, 'Feature_Options', 'Gold');
        System.assert(AttributeVolumeCalculator.buildAttributeExplainerText(tot, 50).contains('Total: $999.00'));
    }

    // ---- getAttributeVolumeValue / getAttributeValue --------------------------

    @isTest
    static void getAttributeVolumeValue_parseBlankAndUnparseable() {
        System.assertEquals(50, AttributeVolumeCalculator.getAttributeVolumeValue(
            new List<Map<String, Object>>{ attrMap('Attribute_Volume', '50') }));
        System.assertEquals(null, AttributeVolumeCalculator.getAttributeVolumeValue(
            new List<Map<String, Object>>{ attrMap('Attribute_Volume', '') }), 'blank => null');
        System.assertEquals(null, AttributeVolumeCalculator.getAttributeVolumeValue(
            new List<Map<String, Object>>{ attrMap('Attribute_Volume', 'abc') }), 'unparseable => null');
        System.assertEquals(null, AttributeVolumeCalculator.getAttributeVolumeValue(
            new List<Map<String, Object>>{ attrMap('Other', '50') }), 'not present => null');
    }

    @isTest
    static void getAttributeValue_nameAndKeyNameFallback() {
        System.assertEquals('Gold', AttributeVolumeCalculator.getAttributeValue(
            new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') }, 'Feature_Options'));
        System.assertEquals('Silver', AttributeVolumeCalculator.getAttributeValue(
            new List<Map<String, Object>>{ new Map<String, Object>{ 'AttributeKeyName' => 'Tier', 'AttributeValue' => 'Silver' } }, 'Tier'),
            'AttributeKeyName fallback');
        System.assertEquals(null, AttributeVolumeCalculator.getAttributeValue(
            new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') }, 'Missing'));
        System.assertEquals(null, AttributeVolumeCalculator.getAttributeValue(null, 'Feature_Options'), 'null attrs');
    }

    // ---- dataPath id extraction -----------------------------------------------

    @isTest
    static void getLineItemIdFromDataPath_lastElement() {
        System.assertEquals('line', AttributeVolumeCalculator.getLineItemIdFromDataPath(
            itemNode(new List<Object>{ 'ctx', 'root', 'line' }, null)));
        System.assertEquals(null, AttributeVolumeCalculator.getLineItemIdFromDataPath(
            itemNode(new List<Object>(), null)), 'empty => null');
    }

    @isTest
    static void getParentIdFromDataPath_secondToLast() {
        System.assertEquals('parent', AttributeVolumeCalculator.getParentIdFromDataPath(
            itemNode(new List<Object>{ 'ctx', 'parent', 'child' }, null)));
        System.assertEquals(null, AttributeVolumeCalculator.getParentIdFromDataPath(
            itemNode(new List<Object>{ 'onlyOne' }, null)), 'size<2 => null');
    }

    // ---- groupAttributesByLineItem --------------------------------------------

    @isTest
    static void groupAttributes_parentReferenceAndDataPathFallback() {
        List<Object> attributeData = new List<Object>{
            // grouped by ParentReference tag
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'ParentReference' => 'LINE-A', 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Gold' } },
            // no ParentReference -> falls back to dataPath second-to-last
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'Attribute' => 'Feature_Options', 'AttributeValue' => 'Silver' },
                                     'dataPath' => new List<Object>{ 'ctx', 'LINE-B', 'attr' } },
            // no parent resolvable -> dropped
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'Attribute' => 'X', 'AttributeValue' => 'Y' } }
        };
        Map<String, List<Map<String, Object>>> out = new Map<String, List<Map<String, Object>>>();
        AttributeVolumeCalculator.groupAttributesByLineItem(attributeData, out);
        System.assertEquals(2, out.size(), 'two resolvable parents (tag + dataPath); the unresolvable one is dropped');
        System.assertEquals(1, out.get('LINE-A').size());
        System.assertEquals(1, out.get('LINE-B').size());
    }

    // ---- tag helpers ----------------------------------------------------------

    @isTest
    static void getBooleanFromTag_variants() {
        Map<String, Object> m = new Map<String, Object>{
            'realBool' => true, 'strTrue' => 'true', 'one' => '1', 'yes' => 'YES',
            'strFalse' => 'false', 'nul' => null,
            'wrapped' => new Map<String, Object>{ 'tagValue' => true }
        };
        System.assertEquals(true, AttributeVolumeCalculator.getBooleanFromTag(m, 'realBool'));
        System.assertEquals(true, AttributeVolumeCalculator.getBooleanFromTag(m, 'strTrue'));
        System.assertEquals(true, AttributeVolumeCalculator.getBooleanFromTag(m, 'one'));
        System.assertEquals(true, AttributeVolumeCalculator.getBooleanFromTag(m, 'yes'));
        System.assertEquals(false, AttributeVolumeCalculator.getBooleanFromTag(m, 'strFalse'));
        System.assertEquals(null, AttributeVolumeCalculator.getBooleanFromTag(m, 'nul'));
        System.assertEquals(null, AttributeVolumeCalculator.getBooleanFromTag(m, 'missing'));
        System.assertEquals(true, AttributeVolumeCalculator.getBooleanFromTag(m, 'wrapped'), 'nested {tagValue} wrapper unwrapped');
    }

    @isTest
    static void getStringFromTag_flatAndWrapped() {
        Map<String, Object> m = new Map<String, Object>{
            'flat' => 'Gold',
            'num' => 42,
            'wrapped' => new Map<String, Object>{ 'tagValue' => 'Wrapped' },
            'nul' => null
        };
        System.assertEquals('Gold', AttributeVolumeCalculator.getStringFromTag(m, 'flat'));
        System.assertEquals('42', AttributeVolumeCalculator.getStringFromTag(m, 'num'));
        System.assertEquals('Wrapped', AttributeVolumeCalculator.getStringFromTag(m, 'wrapped'), 'nested wrapper');
        System.assertEquals(null, AttributeVolumeCalculator.getStringFromTag(m, 'nul'));
        System.assertEquals(null, AttributeVolumeCalculator.getStringFromTag(m, 'missing'));
    }
}
