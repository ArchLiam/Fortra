/**
 * @description Unit tests for AttributeVolumeCalculator.
 *              Exercises the pure seams extracted verbatim from AttributeVolumePricingPrehook —
 *              composite-key tier map + volume->tier resolution (range checks, first-match, key
 *              normalization, Attribute_Volume skip, AttributeKeyName fallback), matched-tier node
 *              shaping across the three price modes, the reset-to-list payload,
 *              explainer text, attribute/volume reads, dataPath id extraction, attribute grouping,
 *              and the tag helpers (flat + nested {tagValue} wrapper). No SOQL/DML — all pure; tier
 *              records are built in memory (15-char reference Ids, no checksum).
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class AttributeVolumeCalculatorTest {

    // 18-char reference Ids with the correct key prefixes. NOTE: a reference field pads a 15-char
    // Id to 18 on read, so the tier map key (built from tier.Product__c) must be compared against
    // the SAME 18-char form the lookup receives — using 18-char literals here keeps both sides equal.
    private static final String PRODUCT_ID = '01t000000000001AAA';   // Product2
    private static final String PSM_ID     = '0jP000000000001EAA';   // ProductSellingModel

    // ---- builders -------------------------------------------------------------

    /**
     * @description Builds an in-memory Attribute_Tier_Pricing_Storage__c record (USD, fixed reference
     *              Product/PSM ids) for wiring up tier-lookup fixtures.
     * @param attrName Attribute name stored on the tier row.
     * @param attrValue Attribute value stored on the tier row.
     * @param lower Lower volume bound for the tier.
     * @param upper Upper volume bound for the tier.
     * @param tierValue Tier value (base price) for the tier.
     * @param mult Multiplier applied under Calculated mode.
     * @param mode Price mode (Calculated / Unit Price / Total Price).
     * @return The constructed tier storage record.
     */
    private static Attribute_Tier_Pricing_Storage__c tier(
        String attrName, String attrValue, Decimal lower, Decimal upper,
        Decimal tierValue, Decimal mult, String mode
    ) {
        return new Attribute_Tier_Pricing_Storage__c(CurrencyIsoCode = 'USD', 
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

    /**
     * @description Builds a single attribute map entry keyed by 'Attribute' / 'AttributeValue'.
     * @param name Attribute name.
     * @param value Attribute value.
     * @return A map representing one attribute node.
     */
    private static Map<String, Object> attrMap(String name, String value) {
        return new Map<String, Object>{ 'Attribute' => name, 'AttributeValue' => value };
    }

    /**
     * @description Builds an item node map carrying a 'dataPath' list and a 'tagValue' map.
     * @param dataPath The context/data path elements.
     * @param tagMap The tag-value map for the node.
     * @return A map representing an item node.
     */
    private static Map<String, Object> itemNode(List<Object> dataPath, Map<String, Object> tagMap) {
        return new Map<String, Object>{ 'dataPath' => dataPath, 'tagValue' => tagMap };
    }

    /**
     * @description Flattens a list of attribute maps into a name->Decimal map, keeping only numeric values.
     * @param attrs List of attribute maps produced by buildNodeUpdate/buildResetNodeUpdate.
     * @return Map of attributeName to its Decimal attributeValue.
     */
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

    /**
     * @description Flattens a list of attribute maps into a name->String map (every value coerced to String).
     * @param attrs List of attribute maps produced by buildNodeUpdate/buildResetNodeUpdate.
     * @return Map of attributeName to its String attributeValue.
     */
    private static Map<String, String> flattenStr(List<Object> attrs) {
        Map<String, String> out = new Map<String, String>();
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            out.put(String.valueOf(a.get('attributeName')), String.valueOf(a.get('attributeValue')));
        }
        return out;
    }

    // ---- buildTierLookupMap + lookupTierFromMap -------------------------------

    /**
     * @description Verifies that two same-key volume ranges fold into one tier-map entry and that a
     *              volume inside the first range resolves the Calculated tier with base/multiplier/mode.
     */
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
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'USD');
        System.assertNotEquals(null, r, 'volume 50 is in [0,100]');
        System.assertEquals(500, r.basePrice);
        System.assertEquals(1.25, r.multiplier);
        System.assertEquals('Calculated', r.priceMode);
        System.assertEquals('Feature_Options', r.attributeName);
        System.assertEquals('Gold', r.attributeValue);
    }

    // SC-3384 — the composite key is currency-scoped: a non-USD line matches ONLY its own-currency
    // tier row (not the USD row), and falls to no-match when no row exists in its currency.
    /**
     * @description Verifies the currency-scoped composite key: a line matches only its own-currency tier
     *              (USD->USD, EUR->EUR, never the USD value) and yields no match when its currency is absent.
     */
    @isTest
    static void lookupTier_currencyScoped_sc3384() {
        Attribute_Tier_Pricing_Storage__c usdTier = tier('Feature_Options', 'Gold', 0, 100, 500, 1.0, 'Total Price');
        Attribute_Tier_Pricing_Storage__c eurTier = new Attribute_Tier_Pricing_Storage__c(CurrencyIsoCode = 'EUR',
            Product__c = PRODUCT_ID, Product_Selling_Model__c = PSM_ID,
            Attribute_Name__c = 'Feature_Options', Attribute_Value__c = 'Gold',
            Lower_Bound__c = 0, Upper_Bound__c = 100, Tier_Value__c = 467.30, Multiplier__c = 1.0, Price_Mode__c = 'Total Price');
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{ usdTier, eurTier });

        List<Map<String, Object>> attrs = new List<Map<String, Object>>{
            attrMap('Feature_Options', 'Gold'), attrMap('Attribute_Volume', '50') };

        AttributeVolumeCalculator.PricingTierResult usd = AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'USD');
        System.assertNotEquals(null, usd, 'USD line matches USD tier');
        System.assertEquals(500, usd.basePrice, 'USD tier value');

        AttributeVolumeCalculator.PricingTierResult eur = AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'EUR');
        System.assertNotEquals(null, eur, 'EUR line matches its OWN EUR tier');
        System.assertEquals(467.30, eur.basePrice, 'EUR tier value, NOT the USD 500 (the SC-3384 bug)');

        AttributeVolumeCalculator.PricingTierResult gbp = AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'GBP');
        System.assertEquals(null, gbp, 'no GBP tier -> no match (data-first: falls to reset-to-list)');
    }

    /**
     * @description Verifies a volume that falls outside the first range resolves the second range's tier value.
     */
    @isTest
    static void lookupTier_secondRange_matches() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated'),
                tier('Feature_Options', 'Gold', 101, 500, 400, 1.10, 'Calculated')
            });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        AttributeVolumeCalculator.PricingTierResult r =
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 250, 'USD');
        System.assertEquals(400, r.basePrice, 'volume 250 falls in the [101,500] range');
    }

    /**
     * @description Verifies a null upper bound is open-ended (matches any volume at/above the lower bound)
     *              while a volume below the lower bound still yields no match.
     */
    @isTest
    static void lookupTier_openUpperBound_matchesAnyAboveLower() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature_Options', 'Gold', 100, null, 300, null, 'Unit Price')
            });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertNotEquals(null,
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 99999, 'USD'),
            'null upper bound is open-ended');
        System.assertEquals(null,
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'USD'),
            'below lower bound => no match');
    }

    /**
     * @description Verifies a volume above the only defined range resolves to no tier (null).
     */
    @isTest
    static void lookupTier_outOfRange_null() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated')
            });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertEquals(null,
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 101, 'USD'),
            'volume above the only range => no tier');
    }

    /**
     * @description Verifies key normalization: a tier stored with a space in its attribute name still
     *              matches a context attribute that uses the underscore form.
     */
    @isTest
    static void lookupTier_keyNormalization_spaceToUnderscore() {
        // tier stored with a SPACE in the attribute name; context uses an UNDERSCORE -> must match
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{
                tier('Feature Options', 'Gold', 0, 100, 500, 1.25, 'Calculated')
            });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertNotEquals(null,
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'USD'),
            'space/underscore normalization aligns tier and context keys');
    }

    /**
     * @description Verifies the lookup skips the Attribute_Volume entry and blank-valued attributes, and
     *              resolves the tier via the AttributeKeyName fallback name.
     */
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
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'USD');
        System.assertNotEquals(null, r, 'AttributeKeyName fallback resolves the tier key');
        System.assertEquals('Feature_Options', r.attributeName);
    }

    /**
     * @description Verifies each guard clause returns null: null map, blank product, blank psm, null attrs,
     *              empty attrs, and null volume.
     */
    @isTest
    static void lookupTier_guardClauses_returnNull() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{ tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated') });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(null, PRODUCT_ID, PSM_ID, attrs, 50, 'USD'), 'null map');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, '', PSM_ID, attrs, 50, 'USD'), 'blank product');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, '', attrs, 50, 'USD'), 'blank psm');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, null, 50, 'USD'), 'null attrs');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, new List<Map<String, Object>>(), 50, 'USD'), 'empty attrs');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, null, 'USD'), 'null volume');
    }

    // ---- buildNodeUpdate ------------------------------------------------------

    /**
     * @description Verifies a Calculated tier with a multiplier writes three attributes (base price, mode,
     *              multiplier) and strips the leading context element from the node's data path.
     */
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

    /**
     * @description Verifies a Unit Price tier writes only two attributes and omits the multiplier attribute.
     */
    @isTest
    static void buildNodeUpdate_unitPrice_noMultiplier() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, new Map<String, Object>());
        AttributeVolumeCalculator.PricingTierResult r =
            new AttributeVolumeCalculator.PricingTierResult(null, 'Unit Price', 300, 'Feature_Options', 'Gold');
        List<Object> attrs = (List<Object>) AttributeVolumeCalculator.buildNodeUpdate(node, r, 50).get('attributes');
        System.assertEquals(2, attrs.size(), 'Unit Price => 2 attributes (no multiplier)');
        System.assert(!flattenDec(attrs).containsKey('Attribute_Multiplier_Pct__c'));
    }

    /**
     * @description Verifies a Calculated tier with a null multiplier omits the multiplier attribute (two attrs).
     */
    @isTest
    static void buildNodeUpdate_calculatedNullMultiplier_noMultiplierAttr() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, new Map<String, Object>());
        AttributeVolumeCalculator.PricingTierResult r =
            new AttributeVolumeCalculator.PricingTierResult(null, 'Calculated', 500, 'Feature_Options', 'Gold');
        List<Object> attrs = (List<Object>) AttributeVolumeCalculator.buildNodeUpdate(node, r, 50).get('attributes');
        System.assertEquals(2, attrs.size(), 'Calculated but null multiplier => no multiplier attr written');
    }

    /**
     * @description Verifies buildNodeUpdate returns null when the node's data path is empty.
     */
    @isTest
    static void buildNodeUpdate_nullDataPath_returnsNull() {
        Map<String, Object> node = itemNode(new List<Object>(), new Map<String, Object>());
        AttributeVolumeCalculator.PricingTierResult r =
            new AttributeVolumeCalculator.PricingTierResult(1.25, 'Calculated', 500, 'Feature_Options', 'Gold');
        System.assertEquals(null, AttributeVolumeCalculator.buildNodeUpdate(node, r, 50), 'empty dataPath => null');
    }

    // ---- buildResetNodeUpdate (SC-3390 / D-17) --------------------------------

    /**
     * @description Verifies the reset writes the tag's ListPrice onto Base_Price__c as a
     *              Unit Price mode payload and strips the context element from the data path.
     */
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

    /**
     * @description Verifies a missing ListPrice in the reset tag map defaults Base_Price__c to 0.
     */
    @isTest
    static void buildResetNodeUpdate_nullListPrice_zero() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, null);
        List<Object> attrs = (List<Object>) AttributeVolumeCalculator.buildResetNodeUpdate(node, new Map<String, Object>()).get('attributes');
        System.assertEquals(0, flattenDec(attrs).get('Base_Price__c'), 'missing ListPrice => 0');
    }

    /**
     * @description Verifies buildResetNodeUpdate returns null when the node's data path is empty.
     */
    @isTest
    static void buildResetNodeUpdate_nullDataPath_null() {
        Map<String, Object> node = itemNode(new List<Object>(), null);
        System.assertEquals(null, AttributeVolumeCalculator.buildResetNodeUpdate(node, new Map<String, Object>{ 'ListPrice' => 100 }));
    }

    // ---- buildAttributeExplainerText ------------------------------------------

    /**
     * @description Verifies the explainer text renders the correct phrasing for each of the three price
     *              modes: Calculated (base x multiplier), Unit Price, and Total Price.
     */
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

    /**
     * @description Verifies volume extraction parses a numeric string and returns null for blank,
     *              unparseable, or absent Attribute_Volume values.
     */
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

    /**
     * @description Verifies attribute-value lookup resolves by 'Attribute' name, falls back to
     *              'AttributeKeyName', and returns null for a missing name or null attribute list.
     */
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

    /**
     * @description Verifies the line-item id is read from the last data-path element, and an empty path yields null.
     */
    @isTest
    static void getLineItemIdFromDataPath_lastElement() {
        System.assertEquals('line', AttributeVolumeCalculator.getLineItemIdFromDataPath(
            itemNode(new List<Object>{ 'ctx', 'root', 'line' }, null)));
        System.assertEquals(null, AttributeVolumeCalculator.getLineItemIdFromDataPath(
            itemNode(new List<Object>(), null)), 'empty => null');
    }

    /**
     * @description Verifies the parent id is read from the second-to-last data-path element, and a path
     *              of size less than two yields null.
     */
    @isTest
    static void getParentIdFromDataPath_secondToLast() {
        System.assertEquals('parent', AttributeVolumeCalculator.getParentIdFromDataPath(
            itemNode(new List<Object>{ 'ctx', 'parent', 'child' }, null)));
        System.assertEquals(null, AttributeVolumeCalculator.getParentIdFromDataPath(
            itemNode(new List<Object>{ 'onlyOne' }, null)), 'size<2 => null');
    }

    // ---- groupAttributesByLineItem --------------------------------------------

    /**
     * @description Verifies attributes group by the ParentReference tag, fall back to the data-path
     *              second-to-last element when absent, and drop entries with no resolvable parent.
     */
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

    /**
     * @description Verifies boolean coercion from a tag across variants: real Boolean, 'true'/'1'/'YES'
     *              strings, 'false', null (returns null), missing key (null), and a nested {tagValue} wrapper.
     */
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

    /**
     * @description Verifies string extraction from a tag: flat string, numeric coerced to string, a nested
     *              {tagValue} wrapper, and null for null-valued or missing keys.
     */
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

    // ========================================================================
    // D-17 fallback (round 4): additional edge-case hardening — pure characterization,
    // zero behavioral risk. Pins branches the round-2 suite did not exercise.
    // ========================================================================

    /**
     * @description Verifies a null Lower_Bound__c is treated as 0 so that volume 0 matches the tier.
     */
    @isTest
    static void lookupTier_lowerBoundNull_defaultsZero() {
        // Lower_Bound__c null => treated as 0 (tier line: lower = Lower_Bound__c != null ? : 0)
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{ tier('Feature_Options', 'Gold', null, 100, 500, 1.25, 'Calculated') });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertNotEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 0, 'USD'),
            'volume 0 matches when lower bound null (defaults to 0)');
    }

    /**
     * @description Verifies both range bounds are inclusive (volume equal to lower or upper matches) while
     *              volumes just below the lower or just above the upper are excluded.
     */
    @isTest
    static void lookupTier_boundaryInclusive() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{ tier('Feature_Options', 'Gold', 10, 20, 500, 1.0, 'Unit Price') });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        System.assertNotEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 10, 'USD'), 'lower bound inclusive');
        System.assertNotEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 20, 'USD'), 'upper bound inclusive');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 9, 'USD'), 'below lower excluded');
        System.assertEquals(null, AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 21, 'USD'), 'above upper excluded');
    }

    /**
     * @description Verifies the lookup iterates past a first attribute with no tier key and matches the
     *              second attribute that does have one.
     */
    @isTest
    static void lookupTier_firstAttrNoKey_secondMatches() {
        // First attribute has no tier key; the loop must continue and match the second attribute.
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{ tier('Feature_Options', 'Gold', 0, 100, 500, 1.25, 'Calculated') });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{
            attrMap('NoKey_Attr', 'X'),
            attrMap('Feature_Options', 'Gold')
        };
        AttributeVolumeCalculator.PricingTierResult r =
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'USD');
        System.assertEquals('Feature_Options', r.attributeName, 'iterates past the no-key attr to the matching one');
    }

    /**
     * @description Verifies a Total Price tier carries its mode and base price through the result with a
     *              null multiplier.
     */
    @isTest
    static void lookupTier_totalPriceMode_carriesMode() {
        Map<String, List<Attribute_Tier_Pricing_Storage__c>> tierMap = AttributeVolumeCalculator.buildTierLookupMap(
            new List<Attribute_Tier_Pricing_Storage__c>{ tier('Feature_Options', 'Gold', 0, 100, 300, null, 'Total Price') });
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{ attrMap('Feature_Options', 'Gold') };
        AttributeVolumeCalculator.PricingTierResult r =
            AttributeVolumeCalculator.lookupTierFromMap(tierMap, PRODUCT_ID, PSM_ID, attrs, 50, 'USD');
        System.assertEquals('Total Price', r.priceMode);
        System.assertEquals(300, r.basePrice);
        System.assertEquals(null, r.multiplier);
    }

    /**
     * @description Verifies a non-Calculated (Total Price) mode never writes the multiplier attribute even
     *              when the result carries a non-null multiplier.
     */
    @isTest
    static void buildNodeUpdate_totalPriceMode_noMultiplierEvenIfPresent() {
        // Non-Calculated mode never writes the multiplier attr, even when multiplier is non-null.
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, new Map<String, Object>());
        AttributeVolumeCalculator.PricingTierResult r =
            new AttributeVolumeCalculator.PricingTierResult(2.0, 'Total Price', 300, 'Feature_Options', 'Gold');
        List<Object> attrs = (List<Object>) AttributeVolumeCalculator.buildNodeUpdate(node, r, 50).get('attributes');
        System.assertEquals(2, attrs.size(), 'Total Price => 2 attrs, no multiplier');
        System.assertEquals('Total Price', flattenStr(attrs).get('Attribute_Price_Mode__c'));
        System.assert(!flattenDec(attrs).containsKey('Attribute_Multiplier_Pct__c'));
    }

    /**
     * @description Verifies the reset resolves ListPrice from a nested {tagValue} wrapper and parses a
     *              string ListPrice onto Base_Price__c.
     */
    @isTest
    static void buildResetNodeUpdate_nestedAndStringListPrice() {
        Map<String, Object> node = itemNode(new List<Object>{ 'ctx', 'root', 'line' }, null);
        // nested {tagValue} wrapper
        List<Object> a1 = (List<Object>) AttributeVolumeCalculator.buildResetNodeUpdate(
            node, new Map<String, Object>{ 'ListPrice' => new Map<String, Object>{ 'tagValue' => 2600 } }).get('attributes');
        System.assertEquals(2600, flattenDec(a1).get('Base_Price__c'), 'ListPrice from nested tagValue wrapper');
        // string value
        List<Object> a2 = (List<Object>) AttributeVolumeCalculator.buildResetNodeUpdate(
            node, new Map<String, Object>{ 'ListPrice' => '1234.5' }).get('attributes');
        System.assertEquals(1234.5, flattenDec(a2).get('Base_Price__c'), 'ListPrice parsed from string');
    }

    /**
     * @description Verifies volume extraction parses decimal and negative string values (reset semantics
     *              for negatives are handled by the caller, not this method).
     */
    @isTest
    static void getAttributeVolumeValue_decimalAndNegative() {
        System.assertEquals(50.5, AttributeVolumeCalculator.getAttributeVolumeValue(
            new List<Map<String, Object>>{ attrMap('Attribute_Volume', '50.5') }), 'decimal volume parses');
        System.assertEquals(-5, AttributeVolumeCalculator.getAttributeVolumeValue(
            new List<Map<String, Object>>{ attrMap('Attribute_Volume', '-5') }), 'negative parses (reset handled by caller, not here)');
    }

    /**
     * @description Verifies attribute-value lookup returns the right value for each name when Attribute_Volume
     *              coexists with other attributes in the list.
     */
    @isTest
    static void getAttributeValue_volumeAmongManyAttrs() {
        List<Map<String, Object>> attrs = new List<Map<String, Object>>{
            attrMap('Feature_Options', 'Gold'),
            attrMap('Attribute_Volume', '75')
        };
        System.assertEquals('75', AttributeVolumeCalculator.getAttributeValue(attrs, 'Attribute_Volume'));
        System.assertEquals('Gold', AttributeVolumeCalculator.getAttributeValue(attrs, 'Feature_Options'));
    }

    /**
     * @description Verifies multiple attributes sharing one ParentReference group together under that single parent.
     */
    @isTest
    static void groupAttributes_multipleAttrsSameParent() {
        List<Object> attributeData = new List<Object>{
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'ParentReference' => 'LINE-A', 'Attribute' => 'F', 'AttributeValue' => 'Gold' } },
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>{ 'ParentReference' => 'LINE-A', 'Attribute' => 'Attribute_Volume', 'AttributeValue' => '50' } }
        };
        Map<String, List<Map<String, Object>>> out = new Map<String, List<Map<String, Object>>>();
        AttributeVolumeCalculator.groupAttributesByLineItem(attributeData, out);
        System.assertEquals(1, out.size());
        System.assertEquals(2, out.get('LINE-A').size(), 'both attrs group under the same parent');
    }

    /**
     * @description Verifies additional boolean coercions: case-insensitive 'TRUE', integer 1 -> true, '0'/'no'
     *              -> false, and an unrecognized token -> false.
     */
    @isTest
    static void getBooleanFromTag_moreCoercions() {
        Map<String, Object> m = new Map<String, Object>{
            'upper' => 'TRUE', 'intOne' => 1, 'zero' => '0', 'no' => 'no', 'arbitrary' => 'maybe'
        };
        System.assertEquals(true,  AttributeVolumeCalculator.getBooleanFromTag(m, 'upper'), 'case-insensitive TRUE');
        System.assertEquals(true,  AttributeVolumeCalculator.getBooleanFromTag(m, 'intOne'), 'integer 1 -> true');
        System.assertEquals(false, AttributeVolumeCalculator.getBooleanFromTag(m, 'zero'));
        System.assertEquals(false, AttributeVolumeCalculator.getBooleanFromTag(m, 'no'));
        System.assertEquals(false, AttributeVolumeCalculator.getBooleanFromTag(m, 'arbitrary'), 'unrecognized -> false');
    }
}