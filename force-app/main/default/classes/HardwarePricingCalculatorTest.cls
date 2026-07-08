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

    // ========================================================================
    // D-17 fallback (round 4): additional edge-case hardening — pure characterization,
    // zero behavioral risk. Pins branches the round-3 suite did not exercise.
    // ========================================================================

    @isTest
    static void calculate_testSystemType_50off() {
        // Test system type = 50% off: 1000 x 1.0 x 1.0 x 0.5 = 500
        HardwarePricingCalculator.HardwarePriceResult r = HardwarePricingCalculator.calculate(1000, null, null, 'Test');
        System.assertEquals(50.0, r.systemTypeDiscount);
        System.assertEquals(0.5,  r.combinedMultiplier);
        System.assertEquals(500,  r.adjustedPrice);
    }

    @isTest
    static void calculate_maxMultipliers() {
        // P60 (x4) x 501 users (x3) x Production (0% off) = x12
        HardwarePricingCalculator.HardwarePriceResult r = HardwarePricingCalculator.calculate(1000, 'P60', 501, 'Production');
        System.assertEquals(12.0,  r.combinedMultiplier, '4 x 3 x 1');
        System.assertEquals(12000, r.adjustedPrice);
    }

    @isTest
    static void calculate_p05_staging() {
        // P05 (x0.5) x 5 users (x1.0) x Staging (25% off) = 0.375
        HardwarePricingCalculator.HardwarePriceResult r = HardwarePricingCalculator.calculate(1000, 'P05', 5, 'Staging');
        System.assertEquals(0.375, r.combinedMultiplier, '0.5 x 1.0 x 0.75');
        System.assertEquals(375,   r.adjustedPrice);
    }

    @isTest
    static void calculate_zeroAndNegativeListPrice() {
        System.assertEquals(0, HardwarePricingCalculator.calculate(0, 'P30', 30, 'Staging').adjustedPrice, 'zero list -> zero');
        // negative list passes through the multiplier unchanged (raw, unrounded)
        System.assertEquals(-1500, HardwarePricingCalculator.calculate(-1000, 'P30', null, null).adjustedPrice, '-1000 x 1.5');
    }

    @isTest
    static void userTierMultiplier_topBandOpenEnded_rule3() {
        // Hardware SDD §8 Rule 3: top band is "501+ = 3.0" (OPEN-ENDED, no upper cap).
        // Users at or beyond any finite cap must still resolve to the top-band 3.0x, not the 1.0x default.
        System.assertEquals(3.0, HardwarePricingCalculator.getUserTierMultiplier(1000000),   '1,000,000 users -> 501+ band 3.0x (open-ended)');
        System.assertEquals(3.0, HardwarePricingCalculator.getUserTierMultiplier(2000000000), '2,000,000,000 users -> 501+ band 3.0x (open-ended)');
    }

    @isTest
    static void userTierMultiplier_decimalTruncates() {
        // usersPerPartition.intValue() truncates toward zero before range matching
        System.assertEquals(1.0,  HardwarePricingCalculator.getUserTierMultiplier(10.9),  '10.9 -> 10 -> band 1..10');
        System.assertEquals(1.25, HardwarePricingCalculator.getUserTierMultiplier(11.0),  '11.0 -> band 11..50');
        System.assertEquals(1.25, HardwarePricingCalculator.getUserTierMultiplier(50.9),  '50.9 -> 50 -> band 11..50');
    }

    @isTest
    static void getPGroupMultiplier_caseSensitiveAndEmpty() {
        System.assertEquals(1.0, HardwarePricingCalculator.getPGroupMultiplier('p30'), 'case-sensitive map -> unknown -> default');
        System.assertEquals(1.0, HardwarePricingCalculator.getPGroupMultiplier(''),    'empty -> default');
    }

    @isTest
    static void getSystemTypeDiscount_caseSensitive() {
        System.assertEquals(0.0, HardwarePricingCalculator.getSystemTypeDiscount('staging'), 'lowercase not in map -> default 0');
        System.assertEquals(0.0, HardwarePricingCalculator.getSystemTypeDiscount('TEST'),    'uppercase not in map -> default 0');
    }
}
