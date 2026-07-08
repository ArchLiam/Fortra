@IsTest
private class RenewalColaPayloadBuilderTest {

    private static List<Object> attrs(Map<String, Object> payload) {
        return (List<Object>) payload.get('attributes');
    }

    private static Map<String, Object> at(List<Object> a, Integer i) {
        return (Map<String, Object>) a[i];
    }

    private static Set<String> names(List<Object> a) {
        Set<String> s = new Set<String>();
        for (Integer i = 0; i < a.size(); i++) {
            s.add((String) at(a, i).get('attributeName'));
        }
        return s;
    }

    @IsTest
    static void buildCommitPayload_eightFixedNoColaStamp() {
        Object path = new List<Object>{ 'q', 'l' };
        Map<String, Object> p = RenewalColaPayloadBuilder.buildCommitPayload(path, 103.00, 206.00, 15, 10);
        List<Object> a = attrs(p);
        System.assertEquals(10, a.size(), '8 fixed + partner + discount');
        System.assertEquals('NetUnitPrice', at(a, 0).get('attributeName'));
        System.assertEquals(103.00, at(a, 0).get('attributeValue'));
        System.assertEquals('UnitPrice', at(a, 3).get('attributeName'));
        System.assertEquals('InputUnitPrice', at(a, 4).get('attributeName'));
        System.assertEquals('PartnerUnitPrice', at(a, 5).get('attributeName'));
        System.assertEquals('Subtotal', at(a, 6).get('attributeName'));
        System.assertEquals('TotalLineAmount', at(a, 7).get('attributeName'));
        System.assertEquals('PartnerDiscountPercent', at(a, 8).get('attributeName'));
        System.assertEquals('Discount', at(a, 9).get('attributeName'));
        System.assert(!names(a).contains('COLACalculatedPrice__c'), 'commit payload carries NO COLA stamp');
        Map<String, Object> nodePath = (Map<String, Object>) p.get('nodePath');
        System.assertEquals(path, nodePath.get('dataPath'));
    }

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
