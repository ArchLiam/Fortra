/**
 * Characterization tests for HardwarePricingCalculator (Wave 2 hook-thinning).
 * Pins the exact hardware pricing math extracted from HardwareAttributePricingPrehook so any future
 * change to the tables/formula must be deliberate. Pure — no DML, no RCA runtime.
 */
@isTest
private class HardwarePricingCalculatorTest {

    @isTest
    static void pGroupMultipliers_allTiers_andDefaults() {
        System.assertEquals(0.5,  HardwarePricingCalculator.getPGroupMultiplier('P05'));
        System.assertEquals(0.75, HardwarePricingCalculator.getPGroupMultiplier('P10'));
        System.assertEquals(1.0,  HardwarePricingCalculator.getPGroupMultiplier('P20'));
        System.assertEquals(1.5,  HardwarePricingCalculator.getPGroupMultiplier('P30'));
        System.assertEquals(2.0,  HardwarePricingCalculator.getPGroupMultiplier('P40'));
        System.assertEquals(3.0,  HardwarePricingCalculator.getPGroupMultiplier('P50'));
        System.assertEquals(4.0,  HardwarePricingCalculator.getPGroupMultiplier('P60'));
        System.assertEquals(1.0,  HardwarePricingCalculator.getPGroupMultiplier(null), 'blank -> default 1.0');
        System.assertEquals(1.0,  HardwarePricingCalculator.getPGroupMultiplier('P99'), 'unknown -> default 1.0');
    }

    @isTest
    static void userTierMultipliers_ranges_andDefaults() {
        System.assertEquals(1.0,  HardwarePricingCalculator.getUserTierMultiplier(1));
        System.assertEquals(1.0,  HardwarePricingCalculator.getUserTierMultiplier(10));
        System.assertEquals(1.25, HardwarePricingCalculator.getUserTierMultiplier(11));
        System.assertEquals(1.25, HardwarePricingCalculator.getUserTierMultiplier(50));
        System.assertEquals(1.5,  HardwarePricingCalculator.getUserTierMultiplier(51));
        System.assertEquals(2.0,  HardwarePricingCalculator.getUserTierMultiplier(101));
        System.assertEquals(2.5,  HardwarePricingCalculator.getUserTierMultiplier(251));
        System.assertEquals(3.0,  HardwarePricingCalculator.getUserTierMultiplier(501));
        System.assertEquals(3.0,  HardwarePricingCalculator.getUserTierMultiplier(999999));
        System.assertEquals(1.0,  HardwarePricingCalculator.getUserTierMultiplier(null), 'null -> default 1.0');
        System.assertEquals(1.0,  HardwarePricingCalculator.getUserTierMultiplier(0),    '0 -> default 1.0');
    }

    @isTest
    static void systemTypeDiscounts_andDefaults() {
        System.assertEquals(0.0,  HardwarePricingCalculator.getSystemTypeDiscount('Production'));
        System.assertEquals(25.0, HardwarePricingCalculator.getSystemTypeDiscount('Staging'));
        System.assertEquals(50.0, HardwarePricingCalculator.getSystemTypeDiscount('Test'));
        System.assertEquals(0.0,  HardwarePricingCalculator.getSystemTypeDiscount(null),      'blank -> default 0');
        System.assertEquals(0.0,  HardwarePricingCalculator.getSystemTypeDiscount('Unknown'), 'unknown -> default 0');
    }

    @isTest
    static void calculate_combinesTablesAndFormula() {
        // Worked example: $1,000, P30 (x1.5), 30 users (x1.25), Staging (25% off)
        // 1000 x 1.5 x 1.25 x 0.75 = 1406.25
        HardwarePricingCalculator.HardwarePriceResult r =
            HardwarePricingCalculator.calculate(1000, 'P30', 30, 'Staging');
        System.assertEquals(1.5,     r.pGroupMultiplier);
        System.assertEquals(1.25,    r.userTierMultiplier);
        System.assertEquals(25.0,    r.systemTypeDiscount);
        System.assertEquals(1.40625, r.combinedMultiplier, '1.5 x 1.25 x 0.75');
        System.assertEquals(1406.25, r.adjustedPrice, '1000 x 1.40625');
    }

    @isTest
    static void calculate_allDefaults_isListPrice() {
        // Unknown/blank attributes -> multiplier 1.0, discount 0 -> price == list
        HardwarePricingCalculator.HardwarePriceResult r =
            HardwarePricingCalculator.calculate(2000, null, null, null);
        System.assertEquals(1.0,  r.combinedMultiplier);
        System.assertEquals(2000, r.adjustedPrice);
    }
}