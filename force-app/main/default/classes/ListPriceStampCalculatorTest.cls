/**
 * @description Unit tests for ListPriceStampCalculator, covering partner/manual discount resolution, attribute-tier list price restamping, and derived maintenance list price calculation.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class ListPriceStampCalculatorTest {

    /**
     * @description Wraps each field value in the RCA context tag shape { field: { tagValue: v } } for use as calculator input.
     * @param fields Flat map of field name to raw value
     * @return Map of field name to a single-entry tagValue map
     */
    private static Map<String, Object> line(Map<String, Object> fields) {
        Map<String, Object> m = new Map<String, Object>();
        for (String k : fields.keySet()) {
            m.put(k, new Map<String, Object>{ 'tagValue' => fields.get(k) });
        }
        return m;
    }

    /**
     * @description Verifies that resolveStampedPartnerPercent prefers a positive PartnerDiscountPercent, falls back to Partner_Discount_Percent__c when that value is zero, and returns null when neither field is present.
     */
    @IsTest
    static void resolveStampedPartnerPercent_prefersPartnerDiscountPercent() {
        System.assertEquals(18, ListPriceStampCalculator.resolveStampedPartnerPercent(
            line(new Map<String, Object>{ 'PartnerDiscountPercent' => 18, 'Partner_Discount_Percent__c' => 5 })),
            'Positive PartnerDiscountPercent wins');
        System.assertEquals(5, ListPriceStampCalculator.resolveStampedPartnerPercent(
            line(new Map<String, Object>{ 'PartnerDiscountPercent' => 0, 'Partner_Discount_Percent__c' => 5 })),
            'Zero PartnerDiscountPercent falls back to Partner_Discount_Percent__c');
        System.assertEquals(null, ListPriceStampCalculator.resolveStampedPartnerPercent(
            line(new Map<String, Object>{})), 'Neither present -> null');
    }

    /**
     * @description Verifies that resolveStampedManualPercent prefers a positive ItemDiscountPercentage and falls back to Discount when ItemDiscountPercentage is zero.
     */
    @IsTest
    static void resolveStampedManualPercent_prefersItemDiscountPercentage() {
        System.assertEquals(12, ListPriceStampCalculator.resolveStampedManualPercent(
            line(new Map<String, Object>{ 'ItemDiscountPercentage' => 12, 'Discount' => 3 })),
            'Positive ItemDiscountPercentage wins');
        System.assertEquals(3, ListPriceStampCalculator.resolveStampedManualPercent(
            line(new Map<String, Object>{ 'ItemDiscountPercentage' => 0, 'Discount' => 3 })),
            'Zero ItemDiscountPercentage falls back to Discount');
    }

    /**
     * @description Verifies that resolveAttributeTierListPrice on a non-derived (Software) line stamps Base_Price__c only when it exceeds ListPrice, returns null when list is at or above base, and returns null when no base price exists.
     */
    @IsTest
    static void resolveAttributeTierListPrice_nonDerivedUsesBaseWhenAboveList() {
        System.assertEquals(200, ListPriceStampCalculator.resolveAttributeTierListPrice(
            line(new Map<String, Object>{ 'Fortra_Product_Type__c' => 'Software', 'Base_Price__c' => 200, 'ListPrice' => 150 }),
            null), 'base 200 > list 150 -> stamp base');
        System.assertEquals(null, ListPriceStampCalculator.resolveAttributeTierListPrice(
            line(new Map<String, Object>{ 'Fortra_Product_Type__c' => 'Software', 'Base_Price__c' => 200, 'ListPrice' => 250 }),
            null), 'list >= base -> no restamp');
        System.assertEquals(null, ListPriceStampCalculator.resolveAttributeTierListPrice(
            line(new Map<String, Object>{ 'Fortra_Product_Type__c' => 'Software' }),
            null), 'no base price -> null');
    }

    /**
     * @description Verifies that resolveAttributeTierListPrice on a derived (New Maintenance) line stamps NetUnitPrice only when it exceeds ListPrice and returns null when list is at or above net.
     */
    @IsTest
    static void resolveAttributeTierListPrice_derivedUsesNetWhenAboveList() {
        System.assertEquals(100, ListPriceStampCalculator.resolveAttributeTierListPrice(
            line(new Map<String, Object>{ 'Fortra_Product_Type__c' => 'New Maintenance', 'NetUnitPrice' => 100, 'ListPrice' => 80 }),
            null), 'derived: net 100 > list 80 -> stamp net');
        System.assertEquals(null, ListPriceStampCalculator.resolveAttributeTierListPrice(
            line(new Map<String, Object>{ 'Fortra_Product_Type__c' => 'New Maintenance', 'NetUnitPrice' => 100, 'ListPrice' => 100 }),
            null), 'derived: list >= net -> no restamp');
    }

    /**
     * @description Builds a QuoteLineItem from JSON so non-writeable (calculated) fields such as NetUnitPrice can be set in-memory for testing.
     * @param jsonBody JSON string of QuoteLineItem field values
     * @return Deserialized QuoteLineItem instance
     */
    private static QuoteLineItem qli(String jsonBody) {
        return (QuoteLineItem) JSON.deserialize(jsonBody, QuoteLineItem.class);
    }

    /**
     * @description Verifies that resolveDerivedMaintenanceListPrice returns the existing UnitPrice when it already exceeds NetUnitPrice.
     */
    @IsTest
    static void resolveDerivedMaintenanceListPrice_unitTopsNet() {
        QuoteLineItem q = qli('{"UnitPrice":500,"NetUnitPrice":300}');
        System.assertEquals(500, ListPriceStampCalculator.resolveDerivedMaintenanceListPrice(q, null, null),
            'UnitPrice already tops net -> use unit');
    }

    /**
     * @description Verifies that resolveDerivedMaintenanceListPrice derives the list price as Base_Price__c multiplied by the tier's maintenance rate.
     */
    @IsTest
    static void resolveDerivedMaintenanceListPrice_baseTimesRate() {
        Id lineId = '0QL000000000001AAA';
        QuoteLineItem q = qli('{"Id":"0QL000000000001AAA","UnitPrice":0,"NetUnitPrice":100,"Base_Price__c":1000}');
        Map<String, Decimal> rate = new Map<String, Decimal>{ 'gold' => 0.20 };
        Map<Id, String> tier = new Map<Id, String>{ lineId => 'gold' };
        System.assertEquals(200.00, ListPriceStampCalculator.resolveDerivedMaintenanceListPrice(q, rate, tier),
            'base 1000 x rate 0.20 = 200.00');
    }

    /**
     * @description Verifies that resolveDerivedMaintenanceListPrice grosses NetUnitPrice back up by the applicable discounts when neither UnitPrice nor Base_Price__c is available.
     */
    @IsTest
    static void resolveDerivedMaintenanceListPrice_netGrossedUpByDiscounts() {
        QuoteLineItem q = qli('{"UnitPrice":0,"NetUnitPrice":90,"PartnerDiscountPercent":10,"Discount":0}');
        System.assertEquals(100.00, ListPriceStampCalculator.resolveDerivedMaintenanceListPrice(q, null, null),
            'net 90 / (1-0.10) = 100.00');
    }

    /**
     * @description Verifies that resolveDerivedMaintenanceListPrice returns null when there is no unit, base, or net price signal to derive from.
     */
    @IsTest
    static void resolveDerivedMaintenanceListPrice_noSignalReturnsNull() {
        QuoteLineItem q = qli('{"UnitPrice":0,"NetUnitPrice":0}');
        System.assertEquals(null, ListPriceStampCalculator.resolveDerivedMaintenanceListPrice(q, null, null),
            'no unit/base/net -> null');
    }
}