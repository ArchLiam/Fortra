/**
 * @description Unit tests for QLDescriptionCalculator — the pure description-assembly logic
 *              extracted from QLDescriptionGeneratorPrehook (Wave-2 hook-thinning). Exercises the
 *              string builders, payload builders, and queryTags-response parsers directly with
 *              in-memory inputs (no SOQL / DML / RCA runtime). ResolvedConfig is built in-memory
 *              (public fields).
 */
@isTest
private class QLDescriptionCalculatorTest {

    // ---- helpers -------------------------------------------------------------

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

    @isTest
    static void buildDescription_productNameOnly() {
        System.assertEquals('FlatFee', QLDescriptionCalculator.buildDescription('FlatFee', null, cfg()), 'null attrs -> product name only');
        System.assertEquals('FlatFee', QLDescriptionCalculator.buildDescription('FlatFee', new Map<String, String>(), cfg()), 'empty attrs -> product name only');
    }

    @isTest
    static void buildDescription_nullWhenNothingToRender() {
        System.assertEquals(null, QLDescriptionCalculator.buildDescription(null, null, cfg()), 'no name + no attrs -> null');
        System.assertEquals(null, QLDescriptionCalculator.buildDescription('', new Map<String, String>(), cfg()), 'blank name + empty attrs -> null');
    }

    @isTest
    static void buildDescription_dedupsRepeatedSegmentValues() {
        Map<String, String> attrs = new Map<String, String>{ 'PS_Service_Type' => 'X', 'Feature_Options' => 'X' };
        System.assertEquals('P | X', QLDescriptionCalculator.buildDescription('P', attrs, cfg()), 'duplicate segment value rendered once');
    }

    @isTest
    static void buildDescription_truncatesOver4000() {
        Map<String, String> attrs = new Map<String, String>{ 'PS_Service_Type' => 'A'.repeat(5000) };
        String d = QLDescriptionCalculator.buildDescription('P', attrs, cfg());
        System.assertEquals(4000, d.length(), 'truncated to the 4000 max');
        System.assert(d.endsWith(' | [truncated]'), 'truncation marker appended');
    }

    // ---- computeUnitTypeSegment ---------------------------------------------

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

    @isTest
    static void resolveUnitQuantity_primaryFallbackAndTrim() {
        System.assertEquals('100', QLDescriptionCalculator.resolveUnitQuantity(new Map<String, String>{ 'Attribute_Volume' => '  100  ' }, cfg()), 'primary trimmed');
        System.assertEquals('36-65', QLDescriptionCalculator.resolveUnitQuantity(new Map<String, String>{ 'Number_of_Units' => ' 36-65 ' }, cfg()), 'fallback trimmed');
        System.assertEquals(null, QLDescriptionCalculator.resolveUnitQuantity(new Map<String, String>(), cfg()), 'neither -> null');
        System.assertEquals(null, QLDescriptionCalculator.resolveUnitQuantity(null, cfg()), 'null attrs -> null');
    }

    // ---- buildContextUpdate --------------------------------------------------

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

    @isTest
    static void parseConfiguredAttributes_nullAndEmpty() {
        System.assert(QLDescriptionCalculator.parseConfiguredAttributes(null).isEmpty(), 'null -> empty');
        System.assert(QLDescriptionCalculator.parseConfiguredAttributes(new Map<String, Object>()).isEmpty(), 'no key -> empty');
    }

    // ---- parseLineItemDataPaths ---------------------------------------------

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
