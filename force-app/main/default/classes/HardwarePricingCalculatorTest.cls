/**
 * Tests for HardwarePricingCalculator. D-14: the three pricing tables now come from the admin-editable
 * Hardware_Attribute_Pricing__mdt. Most tests INJECT a canonical in-memory table (mirroring the seed +
 * SDD §8 Rules 2/3/4) via loadFromRecords so the lookup math is pinned deterministically and independent
 * of the org's (editable) records — this is the "MDT-driven == old hardcoded, for every tier" proof.
 * deployedSeed_reproducesSdd additionally verifies the SHIPPED org seed reproduces those exact values.
 * Pure — no DML, no RCA runtime.
 */
@isTest
private class HardwarePricingCalculatorTest {

    // ── Canonical seed table (== deployed Hardware_Attribute_Pricing__mdt == SDD §8 Rules 2/3/4) ──
    private static Hardware_Attribute_Pricing__mdt pg(String key, Decimal val) {
        return new Hardware_Attribute_Pricing__mdt(Table_Type__c = 'pGroup', Attribute_Key__c = key, Value__c = val);
    }
    private static Hardware_Attribute_Pricing__mdt ut(Integer lo, Integer hi, Decimal val) {
        return new Hardware_Attribute_Pricing__mdt(Table_Type__c = 'UserTier', Min_Users__c = lo, Max_Users__c = hi, Value__c = val);
    }
    private static Hardware_Attribute_Pricing__mdt sysType(String key, Decimal val) {
        return new Hardware_Attribute_Pricing__mdt(Table_Type__c = 'SystemType', Attribute_Key__c = key, Value__c = val);
    }
    private static List<Hardware_Attribute_Pricing__mdt> seedRecords() {
        return new List<Hardware_Attribute_Pricing__mdt>{
            pg('P05', 0.5), pg('P10', 0.75), pg('P20', 1.0), pg('P30', 1.5), pg('P40', 2.0), pg('P50', 3.0), pg('P60', 4.0),
            ut(1, 10, 1.0), ut(11, 50, 1.25), ut(51, 100, 1.5), ut(101, 250, 2.0), ut(251, 500, 2.5), ut(501, null, 3.0),
            sysType('Production', 0.0), sysType('Staging', 25.0), sysType('Test', 50.0)
        };
    }
    /** Inject the canonical table so the getters resolve against it (not the org's records). */
    private static void injectSeed() {
        HardwarePricingCalculator.loadFromRecords(seedRecords());
    }

    // ========================================================================
    // MDT-driven == old hardcoded, every tier (deterministic, injected canonical table)
    // ========================================================================

    @isTest
    static void pGroupMultipliers_allTiers_andDefaults() {
        injectSeed();
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
        injectSeed();
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
        injectSeed();
        System.assertEquals(0.0,  HardwarePricingCalculator.getSystemTypeDiscount('Production'));
        System.assertEquals(25.0, HardwarePricingCalculator.getSystemTypeDiscount('Staging'));
        System.assertEquals(50.0, HardwarePricingCalculator.getSystemTypeDiscount('Test'));
        System.assertEquals(0.0,  HardwarePricingCalculator.getSystemTypeDiscount(null),      'blank -> default 0');
        System.assertEquals(0.0,  HardwarePricingCalculator.getSystemTypeDiscount('Unknown'), 'unknown -> default 0');
    }

    @isTest
    static void calculate_combinesTablesAndFormula() {
        injectSeed();
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
        injectSeed();
        // Unknown/blank attributes -> multiplier 1.0, discount 0 -> price == list
        HardwarePricingCalculator.HardwarePriceResult r =
            HardwarePricingCalculator.calculate(2000, null, null, null);
        System.assertEquals(1.0,  r.combinedMultiplier);
        System.assertEquals(2000, r.adjustedPrice);
    }

    @isTest
    static void calculate_testSystemType_50off() {
        injectSeed();
        // Test system type = 50% off: 1000 x 1.0 x 1.0 x 0.5 = 500
        HardwarePricingCalculator.HardwarePriceResult r = HardwarePricingCalculator.calculate(1000, null, null, 'Test');
        System.assertEquals(50.0, r.systemTypeDiscount);
        System.assertEquals(0.5,  r.combinedMultiplier);
        System.assertEquals(500,  r.adjustedPrice);
    }

    @isTest
    static void calculate_maxMultipliers() {
        injectSeed();
        // P60 (x4) x 501 users (x3) x Production (0% off) = x12
        HardwarePricingCalculator.HardwarePriceResult r = HardwarePricingCalculator.calculate(1000, 'P60', 501, 'Production');
        System.assertEquals(12.0,  r.combinedMultiplier, '4 x 3 x 1');
        System.assertEquals(12000, r.adjustedPrice);
    }

    @isTest
    static void calculate_p05_staging() {
        injectSeed();
        // P05 (x0.5) x 5 users (x1.0) x Staging (25% off) = 0.375
        HardwarePricingCalculator.HardwarePriceResult r = HardwarePricingCalculator.calculate(1000, 'P05', 5, 'Staging');
        System.assertEquals(0.375, r.combinedMultiplier, '0.5 x 1.0 x 0.75');
        System.assertEquals(375,   r.adjustedPrice);
    }

    @isTest
    static void calculate_zeroAndNegativeListPrice() {
        injectSeed();
        System.assertEquals(0, HardwarePricingCalculator.calculate(0, 'P30', 30, 'Staging').adjustedPrice, 'zero list -> zero');
        // negative list passes through the multiplier unchanged (raw, unrounded)
        System.assertEquals(-1500, HardwarePricingCalculator.calculate(-1000, 'P30', null, null).adjustedPrice, '-1000 x 1.5');
    }

    @isTest
    static void userTierMultiplier_topBandOpenEnded_rule3() {
        injectSeed();
        // Hardware SDD §8 Rule 3: top band is "501+ = 3.0" (OPEN-ENDED, no upper cap). Users at or beyond
        // any finite value must still resolve to the top-band 3.0x, not the 1.0x default. The seed row
        // UserTier_501_Plus carries a BLANK Max_Users__c -> open-ended.
        System.assertEquals(3.0, HardwarePricingCalculator.getUserTierMultiplier(1000000),   '1,000,000 users -> 501+ band 3.0x (open-ended)');
        System.assertEquals(3.0, HardwarePricingCalculator.getUserTierMultiplier(2000000000), '2,000,000,000 users -> 501+ band 3.0x (open-ended)');
    }

    @isTest
    static void userTierMultiplier_decimalTruncates() {
        injectSeed();
        // usersPerPartition.intValue() truncates toward zero before range matching
        System.assertEquals(1.0,  HardwarePricingCalculator.getUserTierMultiplier(10.9),  '10.9 -> 10 -> band 1..10');
        System.assertEquals(1.25, HardwarePricingCalculator.getUserTierMultiplier(11.0),  '11.0 -> band 11..50');
        System.assertEquals(1.25, HardwarePricingCalculator.getUserTierMultiplier(50.9),  '50.9 -> 50 -> band 11..50');
    }

    @isTest
    static void getPGroupMultiplier_caseSensitiveAndEmpty() {
        injectSeed();
        System.assertEquals(1.0, HardwarePricingCalculator.getPGroupMultiplier('p30'), 'case-sensitive map -> unknown -> default');
        System.assertEquals(1.0, HardwarePricingCalculator.getPGroupMultiplier(''),    'empty -> default');
    }

    @isTest
    static void getSystemTypeDiscount_caseSensitive() {
        injectSeed();
        System.assertEquals(0.0, HardwarePricingCalculator.getSystemTypeDiscount('staging'), 'lowercase not in map -> default 0');
        System.assertEquals(0.0, HardwarePricingCalculator.getSystemTypeDiscount('TEST'),    'uppercase not in map -> default 0');
    }

    // ========================================================================
    // D-14: MDT plumbing — shipped-seed integrity, admin-editability, empty-config safety
    // ========================================================================

    /**
     * SEED CHARACTERIZATION: the DEPLOYED Hardware_Attribute_Pricing__mdt (read via getAll(), no
     * injection) reproduces the exact SDD values for every tier. This is what makes the S12 reprice
     * 0-delta. If the seed metadata is ever intentionally changed, update this test deliberately.
     */
    @isTest
    static void deployedSeed_reproducesSdd() {
        Map<String, Hardware_Attribute_Pricing__mdt> all = Hardware_Attribute_Pricing__mdt.getAll();
        System.assertEquals(16, all.size(), 'seed should ship exactly 16 rows (7 pGroup + 6 UserTier + 3 SystemType)');

        // pGroup
        System.assertEquals(0.5,  HardwarePricingCalculator.getPGroupMultiplier('P05'));
        System.assertEquals(0.75, HardwarePricingCalculator.getPGroupMultiplier('P10'));
        System.assertEquals(1.0,  HardwarePricingCalculator.getPGroupMultiplier('P20'));
        System.assertEquals(1.5,  HardwarePricingCalculator.getPGroupMultiplier('P30'));
        System.assertEquals(2.0,  HardwarePricingCalculator.getPGroupMultiplier('P40'));
        System.assertEquals(3.0,  HardwarePricingCalculator.getPGroupMultiplier('P50'));
        System.assertEquals(4.0,  HardwarePricingCalculator.getPGroupMultiplier('P60'));
        // user tiers (incl. open-ended top band from the shipped record)
        System.assertEquals(1.0,  HardwarePricingCalculator.getUserTierMultiplier(10));
        System.assertEquals(1.25, HardwarePricingCalculator.getUserTierMultiplier(50));
        System.assertEquals(1.5,  HardwarePricingCalculator.getUserTierMultiplier(100));
        System.assertEquals(2.0,  HardwarePricingCalculator.getUserTierMultiplier(250));
        System.assertEquals(2.5,  HardwarePricingCalculator.getUserTierMultiplier(500));
        System.assertEquals(3.0,  HardwarePricingCalculator.getUserTierMultiplier(501));
        System.assertEquals(3.0,  HardwarePricingCalculator.getUserTierMultiplier(1000000), 'shipped 501+ row is open-ended');
        // system types
        System.assertEquals(0.0,  HardwarePricingCalculator.getSystemTypeDiscount('Production'));
        System.assertEquals(25.0, HardwarePricingCalculator.getSystemTypeDiscount('Staging'));
        System.assertEquals(50.0, HardwarePricingCalculator.getSystemTypeDiscount('Test'));
    }

    /**
     * D-14 payoff: editing the MDT actually drives pricing (proves the table is read, not residually
     * hardcoded). An admin changing P30's multiplier or Staging's discount flows straight through.
     */
    @isTest
    static void mdtIsAdminEditable_valueFlowsThrough() {
        HardwarePricingCalculator.loadFromRecords(new List<Hardware_Attribute_Pricing__mdt>{
            pg('P30', 9.9),                 // admin re-priced P30
            ut(1, null, 1.0),               // single open-ended tier
            sysType('Staging', 10.0)        // admin changed Staging discount 25 -> 10
        });
        System.assertEquals(9.9,  HardwarePricingCalculator.getPGroupMultiplier('P30'), 'edited pGroup value must flow through');
        System.assertEquals(10.0, HardwarePricingCalculator.getSystemTypeDiscount('Staging'), 'edited discount must flow through');
        // 1000 x 9.9 (P30) x 1.0 (5 users) x (1 - 10/100) = 8910
        System.assertEquals(8910, HardwarePricingCalculator.calculate(1000, 'P30', 5, 'Staging').adjustedPrice);
    }

    /**
     * Safety: an empty/unseeded config resolves every lookup to the miss-defaults (1.0x / 0% discount),
     * i.e. price == list — never an exception.
     */
    @isTest
    static void emptyConfig_fallsToDefaults() {
        HardwarePricingCalculator.loadFromRecords(new List<Hardware_Attribute_Pricing__mdt>());
        System.assertEquals(1.0, HardwarePricingCalculator.getPGroupMultiplier('P30'), 'no config -> default multiplier');
        System.assertEquals(1.0, HardwarePricingCalculator.getUserTierMultiplier(100), 'no config -> default multiplier');
        System.assertEquals(0.0, HardwarePricingCalculator.getSystemTypeDiscount('Staging'), 'no config -> default discount');
        System.assertEquals(5000, HardwarePricingCalculator.calculate(5000, 'P30', 100, 'Staging').adjustedPrice, 'no config -> price == list');
    }
}
