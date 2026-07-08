@IsTest
private class PartnerPricingPayloadBuilderTest {

    private static Map<String, Object> byName(List<Map<String, Object>> attrs, String name) {
        for (Map<String, Object> a : attrs) {
            if (name == (String) a.get('attributeName')) {
                return a;
            }
        }
        return null;
    }

    @IsTest
    static void buildAttributes_withDiscountAddsNetAndUnitPrice() {
        List<Map<String, Object>> detail = new List<Map<String, Object>>{
            new Map<String, Object>{ 'partnerId' => '001000000000001AAA', 'marginPercent' => 18 }
        };
        List<Map<String, Object>> a = PartnerPricingPayloadBuilder.buildPartnerPricingAttributes(
            1000, 820, 'Discount', detail, 18);
        // 7 fixed + NetUnitPrice + UnitPrice + Warning = 10
        System.assertEquals(10, a.size(), '7 fixed + Net/Unit (percent>0) + Warning');
        System.assertEquals(1000, byName(a, 'Pre_Partner_Price__c').get('attributeValue'));
        System.assertEquals(820, byName(a, 'Partner_Adjusted_Price__c').get('attributeValue'));
        System.assertEquals('Discount', byName(a, 'Partner_Pricing_Model_Applied__c').get('attributeValue'));
        System.assertEquals('System Calculated', byName(a, 'Partner_Pricing_Source__c').get('attributeValue'));
        System.assertEquals(820, byName(a, 'PartnerUnitPrice').get('attributeValue'));
        System.assertEquals(18, byName(a, 'PartnerDiscountPercent').get('attributeValue'));
        System.assertEquals(820, byName(a, 'NetUnitPrice').get('attributeValue'));
        System.assertEquals(820, byName(a, 'UnitPrice').get('attributeValue'));
        System.assertEquals(JSON.serialize(detail), byName(a, 'Partner_Margin_Detail__c').get('attributeValue'));
        System.assert(byName(a, 'Partner_Pricing_Warning__c') != null, 'Warning always present');
        System.assertEquals(null, byName(a, 'Partner_Pricing_Warning__c').get('attributeValue'));
    }

    @IsTest
    static void buildAttributes_zeroPercentOmitsNetAndUnitAndNullsMarginDetail() {
        List<Map<String, Object>> a = PartnerPricingPayloadBuilder.buildPartnerPricingAttributes(
            1000, 1000, 'Guaranteed Margin', new List<Map<String, Object>>(), 0);
        System.assertEquals(8, a.size(), '7 fixed + Warning, no Net/Unit when percent 0');
        System.assertEquals(null, byName(a, 'NetUnitPrice'), 'no NetUnitPrice when percent 0');
        System.assertEquals(null, byName(a, 'UnitPrice'), 'no UnitPrice when percent 0');
        System.assertEquals(null, byName(a, 'Partner_Margin_Detail__c').get('attributeValue'),
            'empty detail -> null');
    }
}
