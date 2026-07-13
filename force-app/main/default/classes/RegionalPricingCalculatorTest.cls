/**
 * @description Characterization tests for RegionalPricingCalculator: pins the country
 *              multiplier lookup and the round-up-to-nearest-$5 adjusted-price formula
 *              extracted from RegionalServicesPricingPrehook. Pure unit tests with no DML
 *              or RCA runtime.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class RegionalPricingCalculatorTest {

    /**
     * @description Verifies getMultiplierForCountry returns the mapped multiplier for matched
     *              countries and falls back to the default (1.0) for unmatched, blank, and null keys.
     */
    @isTest
    static void getMultiplierForCountry_lookupAndDefaults() {
        Map<String, Decimal> m = new Map<String, Decimal>{ 'Germany' => 0.85, 'JP' => 0.75 };
        System.assertEquals(0.85, RegionalPricingCalculator.getMultiplierForCountry(m, 'Germany'));
        System.assertEquals(0.75, RegionalPricingCalculator.getMultiplierForCountry(m, 'JP'));
        System.assertEquals(1.0,  RegionalPricingCalculator.getMultiplierForCountry(m, 'Unknown'), 'unmatched -> 1.0');
        System.assertEquals(1.0,  RegionalPricingCalculator.getMultiplierForCountry(m, ''),        'blank -> 1.0');
        System.assertEquals(1.0,  RegionalPricingCalculator.getMultiplierForCountry(m, null),      'null -> 1.0');
    }

    /**
     * @description Verifies that an active multiplier row with a null Multiplier__c resolves to
     *              DEFAULT_MULTIPLIER (1.0), so the prehook's default short-circuit skips the line
     *              instead of adjusting off a null, while populated and not-found rows behave as before.
     */
    @isTest
    static void getMultiplierForCountry_nullMultiplier_resolvesToDefault_A6() {
        Map<String, Decimal> m = new Map<String, Decimal>{
            'Nullland' => null,      // Active row, null Multiplier__c (the A-6 edge)
            'Germany'  => 0.85       // normal populated row
        };
        System.assertEquals(1.0, RegionalPricingCalculator.getMultiplierForCountry(m, 'Nullland'),
            'A-6: null multiplier -> DEFAULT_MULTIPLIER (1.0) so the prehook skips the line');
        System.assertEquals(0.85, RegionalPricingCalculator.getMultiplierForCountry(m, 'Germany'),
            'populated multiplier still returned unchanged');
        System.assertEquals(1.0, RegionalPricingCalculator.getMultiplierForCountry(m, 'Nowhere'),
            'not-found country still resolves to DEFAULT_MULTIPLIER');
    }

    /**
     * @description Verifies effective-dating: isEffectiveOn includes only rows in effect on the
     *              evaluation date, treating null bounds as open-ended (inclusive window) and a
     *              null evaluation date as effective so no row is dropped when the date is unknown.
     */
    @isTest
    static void isEffectiveOn_rule14_effectiveDating() {
        Date today = Date.newInstance(2026, 7, 8);

        // No time bound at all -> always effective (preserves the prior active-only behavior).
        System.assertEquals(true, RegionalPricingCalculator.isEffectiveOn(null, null, today), 'null start + null end -> always effective');

        // Within an explicit window (bounds inclusive).
        System.assertEquals(true, RegionalPricingCalculator.isEffectiveOn(Date.newInstance(2026,1,1), Date.newInstance(2026,12,31), today), 'inside window -> effective');
        System.assertEquals(true, RegionalPricingCalculator.isEffectiveOn(today, today, today), 'asOf == start == end (inclusive) -> effective');
        System.assertEquals(true, RegionalPricingCalculator.isEffectiveOn(today, null, today), 'asOf == start, open end -> effective');
        System.assertEquals(true, RegionalPricingCalculator.isEffectiveOn(null, today, today), 'open start, asOf == end -> effective');

        // Outside the window -> excluded.
        System.assertEquals(false, RegionalPricingCalculator.isEffectiveOn(Date.newInstance(2026,8,1), null, today), 'future start -> not yet effective');
        System.assertEquals(false, RegionalPricingCalculator.isEffectiveOn(null, Date.newInstance(2026,6,30), today), 'past end -> expired');
        System.assertEquals(false, RegionalPricingCalculator.isEffectiveOn(Date.newInstance(2026,8,1), Date.newInstance(2026,12,31), today), 'window starts in the future -> excluded');

        // Defensive: null asOf -> treat as effective (never drop when the eval date is unknown).
        System.assertEquals(true, RegionalPricingCalculator.isEffectiveOn(Date.newInstance(2026,8,1), null, null), 'null asOf -> effective (defensive)');
    }

    /**
     * @description Verifies calculateAdjustedPrice applies the multiplier and rounds up to the
     *              nearest $5, returning null for a null list price and treating a null multiplier as 1.0.
     */
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