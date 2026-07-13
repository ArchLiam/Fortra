/**
 * @description Unit tests for PartnerPricingPayloadBuilder, verifying the partner-pricing
 *              attribute payload for discount, zero-percent, and warning scenarios.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class PartnerPricingPayloadBuilderTest {

    /**
     * @description Finds the attribute map whose 'attributeName' equals the given name.
     * @param attrs the list of attribute maps to search
     * @param name the attributeName value to match
     * @return the matching attribute map, or null when none is found
     */
    private static Map<String, Object> byName(List<Map<String, Object>> attrs, String name) {
        for (Map<String, Object> a : attrs) {
            if (name == (String) a.get('attributeName')) {
                return a;
            }
        }
        return null;
    }

    /**
     * @description Verifies that a positive discount percent produces the full 11-attribute payload,
     *              including NetUnitPrice, UnitPrice, the custom audit percent, and a null warning.
     */
    @IsTest
    static void buildAttributes_withDiscountAddsNetAndUnitPrice() {
        List<Map<String, Object>> detail = new List<Map<String, Object>>{
            new Map<String, Object>{ 'partnerId' => '001000000000001AAA', 'marginPercent' => 18 }
        };
        List<Map<String, Object>> a = PartnerPricingPayloadBuilder.buildPartnerPricingAttributes(
            1000, 820, 'Discount', detail, 18, null);
        // 7 fixed + Partner_Discount_Percent__c + NetUnitPrice + UnitPrice + Warning = 11
        System.assertEquals(11, a.size(), '7 fixed + custom % + Net/Unit (percent>0) + Warning');
        System.assertEquals(1000, byName(a, 'Pre_Partner_Price__c').get('attributeValue'));
        System.assertEquals(820, byName(a, 'Partner_Adjusted_Price__c').get('attributeValue'));
        System.assertEquals('Discount', byName(a, 'Partner_Pricing_Model_Applied__c').get('attributeValue'));
        System.assertEquals('System Calculated', byName(a, 'Partner_Pricing_Source__c').get('attributeValue'));
        System.assertEquals(820, byName(a, 'PartnerUnitPrice').get('attributeValue'));
        System.assertEquals(18, byName(a, 'PartnerDiscountPercent').get('attributeValue'));
        // D-PARTNER-5: custom audit field now stamped on success, equal to the standard %
        System.assertEquals(18, byName(a, 'Partner_Discount_Percent__c').get('attributeValue'), 'D-PARTNER-5 custom % on success');
        System.assertEquals(820, byName(a, 'NetUnitPrice').get('attributeValue'));
        System.assertEquals(820, byName(a, 'UnitPrice').get('attributeValue'));
        System.assertEquals(JSON.serialize(detail), byName(a, 'Partner_Margin_Detail__c').get('attributeValue'));
        System.assert(byName(a, 'Partner_Pricing_Warning__c') != null, 'Warning always present');
        System.assertEquals(null, byName(a, 'Partner_Pricing_Warning__c').get('attributeValue'));
    }

    /**
     * @description Verifies that a zero discount percent omits NetUnitPrice and UnitPrice, still stamps
     *              the custom audit percent at 0, and nulls the margin detail when the detail list is empty.
     */
    @IsTest
    static void buildAttributes_zeroPercentOmitsNetAndUnitAndNullsMarginDetail() {
        List<Map<String, Object>> a = PartnerPricingPayloadBuilder.buildPartnerPricingAttributes(
            1000, 1000, 'Guaranteed Margin', new List<Map<String, Object>>(), 0, null);
        System.assertEquals(9, a.size(), '7 fixed + custom % + Warning, no Net/Unit when percent 0');
        System.assertEquals(null, byName(a, 'NetUnitPrice'), 'no NetUnitPrice when percent 0');
        System.assertEquals(null, byName(a, 'UnitPrice'), 'no UnitPrice when percent 0');
        System.assertEquals(0, byName(a, 'Partner_Discount_Percent__c').get('attributeValue'), 'custom % present even at 0');
        System.assertEquals(null, byName(a, 'Partner_Margin_Detail__c').get('attributeValue'),
            'empty detail -> null');
    }

    /**
     * @description Verifies that a non-null warning message flows through verbatim to the
     *              Partner_Pricing_Warning__c attribute value.
     */
    @IsTest
    static void buildAttributes_warningFlowsThrough() {
        List<Map<String, Object>> a = PartnerPricingPayloadBuilder.buildPartnerPricingAttributes(
            1000, 1000, 'Discount', new List<Map<String, Object>>(), 0,
            'Missing partner pricing model for: Acme Reseller');
        System.assertEquals('Missing partner pricing model for: Acme Reseller',
            byName(a, 'Partner_Pricing_Warning__c').get('attributeValue'), 'warning written verbatim');
    }
}