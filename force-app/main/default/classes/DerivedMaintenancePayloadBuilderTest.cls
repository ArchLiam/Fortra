/**
 * @description Unit tests for DerivedMaintenancePayloadBuilder, verifying the shape and ordering of
 * the attribute payloads produced for sequential-discount and fallback derived-maintenance pricing.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class DerivedMaintenancePayloadBuilderTest {

    /**
     * @description Extracts the 'attributes' list from a built pricing payload.
     * @param payload The payload map returned by the builder under test.
     * @return The list of attribute maps contained in the payload.
     */
    private static List<Object> attrs(Map<String, Object> payload) {
        return (List<Object>) payload.get('attributes');
    }

    /**
     * @description Returns the attribute map at the given index of an attributes list.
     * @param a The list of attribute maps.
     * @param i The zero-based index to retrieve.
     * @return The attribute map at the requested position.
     */
    private static Map<String, Object> at(List<Object> a, Integer i) {
        return (Map<String, Object>) a[i];
    }

    /**
     * @description Verifies that a sequential-discount payload emits all 10 fixed plus 3 conditional
     * attributes in the expected order and values when the conditional inputs are present, and that
     * the node path is carried through as the update path.
     */
    @IsTest
    static void buildSequentialDiscountPayload_allAttributesInOrderWhenConditionalsFire() {
        Object path = new List<Object>{ 'q', 'l' };
        Map<String, Object> p = DerivedMaintenancePayloadBuilder.buildSequentialDiscountPayload(
            path, 765.00, 1530.00, 850.00, 1000.00, 900.00, 15, 10);
        List<Object> a = attrs(p);
        System.assertEquals(13, a.size(), '10 fixed + 3 conditional attributes');

        System.assertEquals('NetUnitPrice', at(a, 0).get('attributeName'));
        System.assertEquals(765.00, at(a, 0).get('attributeValue'));
        System.assertEquals('NetTotalPrice', at(a, 1).get('attributeName'));
        System.assertEquals(1530.00, at(a, 1).get('attributeValue'));
        System.assertEquals('TotalPrice', at(a, 2).get('attributeName'));
        System.assertEquals('Subtotal', at(a, 3).get('attributeName'));
        System.assertEquals('TotalLineAmount', at(a, 4).get('attributeName'));
        System.assertEquals('PartnerUnitPrice', at(a, 5).get('attributeName'));
        System.assertEquals(850.00, at(a, 5).get('attributeValue'));
        System.assertEquals('ListPrice', at(a, 6).get('attributeName'));
        System.assertEquals(1000.00, at(a, 6).get('attributeValue'));
        System.assertEquals('UnitPrice', at(a, 7).get('attributeName'));
        System.assertEquals(1000.00, at(a, 7).get('attributeValue'));
        System.assertEquals('Pre_Partner_Price__c', at(a, 8).get('attributeName'));
        System.assertEquals('Partner_Pricing_Source__c', at(a, 9).get('attributeName'));
        System.assertEquals('System Calculated (Post-Procedure)', at(a, 9).get('attributeValue'));

        System.assertEquals('Base_Price__c', at(a, 10).get('attributeName'));
        System.assertEquals(900.00, at(a, 10).get('attributeValue'));
        System.assertEquals('PartnerDiscountPercent', at(a, 11).get('attributeName'));
        System.assertEquals(15, at(a, 11).get('attributeValue'));
        System.assertEquals('Discount', at(a, 12).get('attributeName'));
        System.assertEquals(10, at(a, 12).get('attributeValue'));

        Map<String, Object> nodePath = (Map<String, Object>) p.get('nodePath');
        System.assertEquals(path, nodePath.get('dataPath'), 'nodePath.dataPath = updatePath');
    }

    /**
     * @description Verifies that a sequential-discount payload contains only the 10 fixed attributes
     * and omits the Base_Price__c, PartnerDiscountPercent, and Discount attributes when their
     * conditional inputs are zero or null.
     */
    @IsTest
    static void buildSequentialDiscountPayload_conditionalsOmittedWhenZeroOrNull() {
        Map<String, Object> p = DerivedMaintenancePayloadBuilder.buildSequentialDiscountPayload(
            new List<Object>{ 'x' }, 765.00, 765.00, 850.00, 1000.00, null, 0, 0);
        List<Object> a = attrs(p);
        System.assertEquals(10, a.size(), 'only the 10 fixed attributes');
        for (Integer i = 0; i < a.size(); i++) {
            String name = (String) at(a, i).get('attributeName');
            System.assert(
                name != 'Base_Price__c' && name != 'PartnerDiscountPercent' && name != 'Discount',
                'no conditional attribute expected: ' + name);
        }
    }

    /**
     * @description Verifies that a fallback payload emits the 7 fixed attributes plus a conditional
     * PartnerDiscountPercent attribute (with the fallback pricing source) in the expected order and
     * values, and carries the node path through as the update path.
     */
    @IsTest
    static void buildFallbackPayload_sevenFixedPlusConditionalPartner() {
        Object path = new List<Object>{ 'q', 'l' };
        Map<String, Object> p = DerivedMaintenancePayloadBuilder.buildFallbackPayload(path, 62.48, 124.96, 15);
        List<Object> a = attrs(p);
        System.assertEquals(8, a.size(), '7 fixed + PartnerDiscountPercent');
        System.assertEquals('NetUnitPrice', at(a, 0).get('attributeName'));
        System.assertEquals(62.48, at(a, 0).get('attributeValue'));
        System.assertEquals('NetTotalPrice', at(a, 1).get('attributeName'));
        System.assertEquals(124.96, at(a, 1).get('attributeValue'));
        System.assertEquals('PartnerUnitPrice', at(a, 5).get('attributeName'));
        System.assertEquals(62.48, at(a, 5).get('attributeValue'));
        System.assertEquals('Partner_Pricing_Source__c', at(a, 6).get('attributeName'));
        System.assertEquals('System Calculated (Post-Procedure Fallback)', at(a, 6).get('attributeValue'));
        System.assertEquals('PartnerDiscountPercent', at(a, 7).get('attributeName'));
        System.assertEquals(15, at(a, 7).get('attributeValue'));
        Map<String, Object> nodePath = (Map<String, Object>) p.get('nodePath');
        System.assertEquals(path, nodePath.get('dataPath'));
    }

    /**
     * @description Verifies that a fallback payload contains only the 7 fixed attributes and omits
     * the PartnerDiscountPercent attribute when the partner discount input is null or zero.
     */
    @IsTest
    static void buildFallbackPayload_partnerOmittedWhenNullOrZero() {
        System.assertEquals(7, attrs(DerivedMaintenancePayloadBuilder.buildFallbackPayload(
            new List<Object>{ 'x' }, 62.48, 62.48, null)).size(), 'null partner% -> 7 fixed only');
        System.assertEquals(7, attrs(DerivedMaintenancePayloadBuilder.buildFallbackPayload(
            new List<Object>{ 'x' }, 62.48, 62.48, 0)).size(), 'zero partner% -> 7 fixed only');
    }
}