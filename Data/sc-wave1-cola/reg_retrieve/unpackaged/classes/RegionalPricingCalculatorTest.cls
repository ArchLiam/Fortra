/**
 * Characterization tests for RegionalPricingCalculator (Wave 2 hook-thinning).
 * Pins the country lookup + the round-up-to-nearest-$5 formula extracted from RegionalServicesPricingPrehook.
 * Pure — no DML, no RCA runtime.
 */
@isTest
private class RegionalPricingCalculatorTest {

    @isTest
    static void getMultiplierForCountry_lookupAndDefaults() {
        Map<String, Decimal> m = new Map<String, Decimal>{ 'Germany' => 0.85, 'JP' => 0.75 };
        System.assertEquals(0.85, RegionalPricingCalculator.getMultiplierForCountry(m, 'Germany'));
        System.assertEquals(0.75, RegionalPricingCalculator.getMultiplierForCountry(m, 'JP'));
        System.assertEquals(1.0,  RegionalPricingCalculator.getMultiplierForCountry(m, 'Unknown'), 'unmatched -> 1.0');
        System.assertEquals(1.0,  RegionalPricingCalculator.getMultiplierForCountry(m, ''),        'blank -> 1.0');
        System.assertEquals(1.0,  RegionalPricingCalculator.getMultiplierForCountry(m, null),      'null -> 1.0');
    }

    @isTest
    static void calculateAdjustedPrice_roundsUpToNearest5() {
        System.assertEquals(650.00,  RegionalPricingCalculator.calculateAdjustedPrice(1000.00, 0.65), '650 -> 650');
        System.assertEquals(75.00,   RegionalPricingCalculator.calculateAdjustedPrice(100.00, 0.72),  '72 -> up to 75');
        System.assertEquals(500.00,  RegionalPricingCalculator.calculateAdjustedPrice(500.00, 1.0),   '500 -> 500');
        System.assertEquals(815.00,  RegionalPricingCalculator.calculateAdjustedPrice(1247.00, 0.65), '810.55 -> up to 815 (design-doc example)');
        System.assertEquals(null,    RegionalPricingCalculator.calculateAdjustedPrice(null, 0.65),     'null list -> null');
        System.assertEquals(1000.00, RegionalPricingCalculator.calculateAdjustedPrice(1000.00, null),  'null multiplier -> 1.0');
    }
}