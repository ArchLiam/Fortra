/**
 * @description Unit tests for RenewalColaPayloadBuilder, verifying the attribute
 * composition of commit and maintenance renewal-COLA pricing payloads.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class RenewalColaPayloadBuilderTest {

    /**
     * @description Extracts the attributes list from a built payload map.
     * @param payload The payload map produced by the builder under test.
     * @return The list of attribute maps stored under the 'attributes' key.
     */
    private static List<Object> attrs(Map<String, Object> payload) {
        return (List<Object>) payload.get('attributes');
    }

    /**
     * @description Returns the attribute map at a given index of an attributes list.
     * @param a The attributes list to read from.
     * @param i The zero-based index of the attribute to retrieve.
     * @return The attribute map at the requested index.
     */
    private static Map<String, Object> at(List<Object> a, Integer i) {
        return (Map<String, Object>) a[i];
    }

    /**
     * @description Collects the set of attributeName values present in an attributes list.
     * @param a The attributes list to scan.
     * @return A set of the attributeName values found across all attributes.
     */
    private static Set<String> names(List<Object> a) {
        Set<String> s = new Set<String>();
        for (Integer i = 0; i < a.size(); i++) {
            s.add((String) at(a, i).get('attributeName'));
        }
        return s;
    }

    /**
     * @description Verifies a commit payload contains six OUTPUT-only fixed attributes plus the
     * partner and discount entries, EXCLUDES the input-oriented UnitPrice/InputUnitPrice (whose
     * presence would poison the updateContextAttributes batch — SC-3350), carries no COLA stamp,
     * and preserves the node data path.
     */
    @IsTest
    static void buildCommitPayload_sixOutputFixedNoColaStamp() {
        Object path = new List<Object>{ 'q', 'l' };
        Map<String, Object> p = RenewalColaPayloadBuilder.buildCommitPayload(path, 103.00, 206.00, 15, 10);
        List<Object> a = attrs(p);
        System.assertEquals(8, a.size(), '6 output-fixed + partner + discount');
        System.assertEquals('NetUnitPrice', at(a, 0).get('attributeName'));
        System.assertEquals(103.00, at(a, 0).get('attributeValue'));
        System.assertEquals('NetTotalPrice', at(a, 1).get('attributeName'));
        System.assertEquals('TotalPrice', at(a, 2).get('attributeName'));
        System.assertEquals('PartnerUnitPrice', at(a, 3).get('attributeName'));
        System.assertEquals('Subtotal', at(a, 4).get('attributeName'));
        System.assertEquals('TotalLineAmount', at(a, 5).get('attributeName'));
        System.assertEquals('PartnerDiscountPercent', at(a, 6).get('attributeName'));
        System.assertEquals('Discount', at(a, 7).get('attributeName'));
        Set<String> n = names(a);
        System.assert(!n.contains('InputUnitPrice'), 'SC-3350: input-type InputUnitPrice must NOT be in the batch');
        System.assert(!n.contains('UnitPrice'), 'SC-3350: input-oriented UnitPrice must NOT be in the batch');
        System.assert(!n.contains('COLACalculatedPrice__c'), 'commit payload carries NO COLA stamp');
        Map<String, Object> nodePath = (Map<String, Object>) p.get('nodePath');
        System.assertEquals(path, nodePath.get('dataPath'));
    }

    /**
     * @description Verifies a maintenance payload contains seven fixed attributes including
     * the COLA stamp, and omits Subtotal, TotalLineAmount, and null/zero discount entries.
     */
    @IsTest
    static void buildMaintenancePayload_sevenFixedWithColaStampNoSubtotal() {
        Map<String, Object> p = RenewalColaPayloadBuilder.buildMaintenancePayload(
            new List<Object>{ 'x' }, 103.00, 206.00, null, 0);
        List<Object> a = attrs(p);
        System.assertEquals(7, a.size(), '7 fixed, no discount conditionals');
        System.assertEquals('COLACalculatedPrice__c', at(a, 6).get('attributeName'));
        System.assertEquals(103.00, at(a, 6).get('attributeValue'));
        Set<String> n = names(a);
        System.assert(!n.contains('Subtotal') && !n.contains('TotalLineAmount'),
            'maintenance payload has no Subtotal/TotalLineAmount');
        System.assert(!n.contains('PartnerDiscountPercent') && !n.contains('Discount'),
            'null/zero discounts omitted');
    }
}