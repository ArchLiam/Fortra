/**
 * @description Unit tests for QLDescriptionCalculator — the pure description-assembly logic
 *              extracted from QLDescriptionGeneratorPrehook. Exercises the string builders,
 *              payload builders, and queryTags-response parsers directly with in-memory inputs
 *              (no SOQL / DML / RCA runtime); ResolvedConfig is built in-memory via public fields.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class QLDescriptionCalculatorTest {

    // ---- helpers -------------------------------------------------------------

    /**
     * @description Builds a fully-populated ResolvedConfig fixture (segment names, unit-type
     *              attribute/trigger, and primary/fallback unit-quantity attributes) shared by the tests.
     * @return an in-memory ResolvedConfig with representative segment and unit settings
     */
    private static QLDescriptionGeneratorPrehook.ResolvedConfig cfg() {
        QLDescriptionGeneratorPrehook.ResolvedConfig c = new QLDescriptionGeneratorPrehook.ResolvedConfig();
        c.segmentNames = new List<String>{ 'PS_Service_Type', 'Feature_Options' };
        c.unitTypeAttr = 'Unit_Type';
        c.unitTypeTrigger = 'Per User';
        c.unitQtyPrimary = 'Attribute_Volume';
        c.unitQtyFallback = 'Number_of_Units';
        return c;
    }

    // ---- buildDescription ----------------------------------------------------

    /**
     * @description Verifies buildDescription concatenates the product name, the computed unit-type
     *              segment, and the ordered attribute segments into a single pipe-delimited string.
     */
    @isTest
    static void buildDescription_productPlusAttributes() {
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Per User', 'Attribute_Volume' => '100',
            'PS_Service_Type' => 'Prod', 'Feature_Options' => 'Advanced'
        };
        System.assertEquals(
            'MyProduct | Users: 100 | Prod | Advanced',
            QLDescriptionCalculator.buildDescription('MyProduct', attrs, cfg()),
            'product + unit-type segment + ordered attribute segments');
    }

    /**
     * @description Verifies buildDescription returns just the product name when the attribute map is
     *              null or empty (no segments to append).
     */
    @isTest
    static void buildDescription_productNameOnly() {
        System.assertEquals('FlatFee', QLDescriptionCalculator.buildDescription('FlatFee', null, cfg()), 'null attrs -> product name only');
        System.assertEquals('FlatFee', QLDescriptionCalculator.buildDescription('FlatFee', new Map<String, String>(), cfg()), 'empty attrs -> product name only');
    }

    /**
     * @description Verifies buildDescription returns null when there is nothing to render — no product
     *              name and no attributes (both null/blank and blank-name/empty-attrs cases).
     */
    @isTest
    static void buildDescription_nullWhenNothingToRender() {
        System.assertEquals(null, QLDescriptionCalculator.buildDescription(null, null, cfg()), 'no name + no attrs -> null');
        System.assertEquals(null, QLDescriptionCalculator.buildDescription('', new Map<String, String>(), cfg()), 'blank name + empty attrs -> null');
    }

    /**
     * @description Verifies buildDescription renders a repeated segment value only once, deduplicating
     *              identical values across segments.
     */
    @isTest
    static void buildDescription_dedupsRepeatedSegmentValues() {
        Map<String, String> attrs = new Map<String, String>{ 'PS_Service_Type' => 'X', 'Feature_Options' => 'X' };
        System.assertEquals('P | X', QLDescriptionCalculator.buildDescription('P', attrs, cfg()), 'duplicate segment value rendered once');
    }

    /**
     * @description Verifies buildDescription caps the result at 4000 characters and appends the
     *              " | [truncated]" marker when the assembled description exceeds the limit.
     */
    @isTest
    static void buildDescription_truncatesOver4000() {
        Map<String, String> attrs = new Map<String, String>{ 'PS_Service_Type' => 'A'.repeat(5000) };
        String d = QLDescriptionCalculator.buildDescription('P', attrs, cfg());
        System.assertEquals(4000, d.length(), 'truncated to the 4000 max');
        System.assert(d.endsWith(' | [truncated]'), 'truncation marker appended');
    }

    // ---- computeUnitTypeSegment ---------------------------------------------

    /**
     * @description Verifies computeUnitTypeSegment across its variants: the "Per User" trigger renders
     *              "Users: n" (or bare "Per User" with no quantity), other types render "type: n" (or bare
     *              type), and null/missing Unit_Type yields null.
     */
    @isTest
    static void computeUnitTypeSegment_variants() {
        System.assertEquals('Users: 50', QLDescriptionCalculator.computeUnitTypeSegment(new Map<String, String>{ 'Unit_Type' => 'Per User', 'Attribute_Volume' => '50' }, cfg()), 'Per User + qty -> Users: n');
        System.assertEquals('Per User', QLDescriptionCalculator.computeUnitTypeSegment(new Map<String, String>{ 'Unit_Type' => 'Per User' }, cfg()), 'Per User + no qty -> Per User');
        System.assertEquals('Node: 8', QLDescriptionCalculator.computeUnitTypeSegment(new Map<String, String>{ 'Unit_Type' => 'Node', 'Attribute_Volume' => '8' }, cfg()), 'other type + qty -> type: n');
        System.assertEquals('Node', QLDescriptionCalculator.computeUnitTypeSegment(new Map<String, String>{ 'Unit_Type' => 'Node' }, cfg()), 'other type + no qty -> type');
        System.assertEquals(null, QLDescriptionCalculator.computeUnitTypeSegment(null, cfg()), 'null attrs -> null');
        System.assertEquals(null, QLDescriptionCalculator.computeUnitTypeSegment(new Map<String, String>(), cfg()), 'no Unit_Type -> null');
    }

    // ---- resolveUnitQuantity -------------------------------------------------

    /**
     * @description Verifies resolveUnitQuantity returns the trimmed primary attribute when present, falls
     *              back to the trimmed fallback attribute otherwise, and returns null when neither exists.
     */
    @isTest
    static void resolveUnitQuantity_primaryFallbackAndTrim() {
        System.assertEquals('100', QLDescriptionCalculator.resolveUnitQuantity(new Map<String, String>{ 'Attribute_Volume' => '  100  ' }, cfg()), 'primary trimmed');
        System.assertEquals('36-65', QLDescriptionCalculator.resolveUnitQuantity(new Map<String, String>{ 'Number_of_Units' => ' 36-65 ' }, cfg()), 'fallback trimmed');
        System.assertEquals(null, QLDescriptionCalculator.resolveUnitQuantity(new Map<String, String>(), cfg()), 'neither -> null');
        System.assertEquals(null, QLDescriptionCalculator.resolveUnitQuantity(null, cfg()), 'null attrs -> null');
    }

    // ---- buildContextUpdate --------------------------------------------------

    /**
     * @description Verifies buildContextUpdate drops the root element from the data path and emits a single
     *              SalesTrxnItemDescription attribute carrying the supplied description value.
     */
    @isTest
    static void buildContextUpdate_dropsRootAndSetsDescriptionAttr() {
        List<Object> dp = new List<Object>{ 'root', 'lineNode' };
        Map<String, Object> upd = QLDescriptionCalculator.buildContextUpdate(dp, 'Some Desc');
        Map<String, Object> nodePath = (Map<String, Object>) upd.get('nodePath');
        System.assertEquals(new List<Object>{ 'lineNode' }, (List<Object>) nodePath.get('dataPath'), 'root element dropped');
        List<Object> attrs = (List<Object>) upd.get('attributes');
        Map<String, Object> a0 = (Map<String, Object>) attrs[0];
        System.assertEquals('SalesTrxnItemDescription', a0.get('attributeName'), 'writes the description context attr');
        System.assertEquals('Some Desc', a0.get('attributeValue'), 'carries the description');
    }

    // ---- buildContextUpdates -------------------------------------------------

    /**
     * @description Verifies buildContextUpdates produces an update for every line that has a description,
     *              including attribute-less lines that still resolve to a product-name-only description.
     */
    @isTest
    static void buildContextUpdates_includesProductNameOnlyLines() {
        Id lineA = '001000000000001';
        Id lineB = '001000000000002';
        Map<Id, List<Object>> dataPaths = new Map<Id, List<Object>>{
            lineA => new List<Object>{ 'root', 'a' },
            lineB => new List<Object>{ 'root', 'b' }
        };
        Map<Id, Map<String, String>> attrs = new Map<Id, Map<String, String>>{
            lineA => new Map<String, String>{ 'PS_Service_Type' => 'Prod' }
            // lineB: no attributes -> product-name-only description
        };
        Map<Id, String> names = new Map<Id, String>{ lineA => 'ProdA', lineB => 'ProdB' };
        List<Map<String, Object>> updates = QLDescriptionCalculator.buildContextUpdates(attrs, dataPaths, names, cfg());
        System.assertEquals(2, updates.size(), 'both lines produce a description (attribute-less line still gets product name)');
    }

    /**
     * @description Verifies buildContextUpdates skips lines that resolve to a null description (no product
     *              name and no attributes), emitting no update for them.
     */
    @isTest
    static void buildContextUpdates_skipsLinesWithNoDescription() {
        Id lineA = '001000000000003';
        Map<Id, List<Object>> dataPaths = new Map<Id, List<Object>>{ lineA => new List<Object>{ 'root', 'a' } };
        Map<Id, Map<String, String>> attrs = new Map<Id, Map<String, String>>();   // no attrs
        Map<Id, String> names = new Map<Id, String>();                              // no product name -> null description
        List<Map<String, Object>> updates = QLDescriptionCalculator.buildContextUpdates(attrs, dataPaths, names, cfg());
        System.assertEquals(0, updates.size(), 'line with neither name nor attrs is skipped');
    }

    // ---- parseConfiguredAttributes ------------------------------------------

    /**
     * @description Verifies parseConfiguredAttributes reads attributes from the nested tagValue shape,
     *              keying each attribute/value under its ParentReference line Id.
     */
    @isTest
    static void parseConfiguredAttributes_nestedTagValueShape() {
        Map<String, Object> resp = new Map<String, Object>{
            'SalesTransactionItemAttribute' => new List<Object>{
                new Map<String, Object>{
                    'tagValue' => new Map<String, Object>{
                        'ParentReference' => '001000000000001AAA',
                        'Attribute' => 'PS_Service_Type',
                        'AttributeValue' => 'Production'
                    },
                    'dataPath' => new List<Object>{ 'root', '001000000000001AAA', 'attrNode' }
                }
            }
        };
        Map<Id, Map<String, String>> parsed = QLDescriptionCalculator.parseConfiguredAttributes(resp);
        Id pid = Id.valueOf('001000000000001AAA');
        System.assertEquals('Production', parsed.get(pid).get('PS_Service_Type'), 'attribute parsed under parent line');
    }

    /**
     * @description Verifies parseConfiguredAttributes resolves the parent line from dataPath[size-2] when
     *              ParentReference is absent and falls back to AttributeKeyName when Attribute is blank.
     */
    @isTest
    static void parseConfiguredAttributes_attributeKeyNameFallback_andDataPathParent() {
        // No ParentReference -> parent resolved from dataPath[size-2]; Attribute blank -> AttributeKeyName used.
        Map<String, Object> resp = new Map<String, Object>{
            'SalesTransactionItemAttribute' => new List<Object>{
                new Map<String, Object>{
                    'tagValue' => new Map<String, Object>{
                        'AttributeKeyName' => 'Feature_Options',
                        'AttributeValue' => 'Adv'
                    },
                    'dataPath' => new List<Object>{ '001000000000001AAA', 'attrNode' }
                }
            }
        };
        Map<Id, Map<String, String>> parsed = QLDescriptionCalculator.parseConfiguredAttributes(resp);
        Id pid = Id.valueOf('001000000000001AAA');
        System.assertEquals('Adv', parsed.get(pid).get('Feature_Options'), 'dataPath-parent + AttributeKeyName fallback');
    }

    /**
     * @description Verifies parseConfiguredAttributes returns an empty map for a null response and for a
     *              response missing the SalesTransactionItemAttribute key.
     */
    @isTest
    static void parseConfiguredAttributes_nullAndEmpty() {
        System.assert(QLDescriptionCalculator.parseConfiguredAttributes(null).isEmpty(), 'null -> empty');
        System.assert(QLDescriptionCalculator.parseConfiguredAttributes(new Map<String, Object>()).isEmpty(), 'no key -> empty');
    }

    // ---- parseLineItemDataPaths ---------------------------------------------

    /**
     * @description Verifies parseLineItemDataPaths keys each line by the Id in the last data-path element
     *              and retains the full data path as the value.
     */
    @isTest
    static void parseLineItemDataPaths_extractsLineIdFromLastElement() {
        Map<String, Object> resp = new Map<String, Object>{
            'SalesTransactionItem' => new List<Object>{
                new Map<String, Object>{ 'dataPath' => new List<Object>{ 'root', '001000000000001AAA' } }
            }
        };
        Map<Id, List<Object>> parsed = QLDescriptionCalculator.parseLineItemDataPaths(resp);
        Id lid = Id.valueOf('001000000000001AAA');
        System.assert(parsed.containsKey(lid), 'line Id keyed from dataPath last element');
        System.assertEquals(new List<Object>{ 'root', '001000000000001AAA' }, parsed.get(lid), 'full dataPath retained');
    }

    /**
     * @description Verifies parseLineItemDataPaths skips entries whose last data-path element is not an Id
     *              and returns an empty map for a null response.
     */
    @isTest
    static void parseLineItemDataPaths_skipsNonIdLastElement_andNull() {
        Map<String, Object> resp = new Map<String, Object>{
            'SalesTransactionItem' => new List<Object>{
                new Map<String, Object>{ 'dataPath' => new List<Object>{ 'root', 'not-an-id' } }
            }
        };
        System.assert(QLDescriptionCalculator.parseLineItemDataPaths(resp).isEmpty(), 'non-Id last element skipped');
        System.assert(QLDescriptionCalculator.parseLineItemDataPaths(null).isEmpty(), 'null -> empty');
    }
}