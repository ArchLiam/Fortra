/**
 * Pure regional-services pricing calculation, extracted from RegionalServicesPricingPrehook (Wave 2 hook-thinning).
 * Plain-input / plain-output; unit-testable without the RCA runtime. Behavior-identical to the prior inline logic
 * (same lookup + rounding, just relocated).
 *
 * Formula: adjustedPrice = CEILING((listPrice x multiplier) / 5) x 5   (round UP to nearest $5)
 * Ref: docs/pricing-refactor/PRICING_REFACTOR_PLAN.md (Section 5.1 thin hook = adapter over testable service)
 */
public with sharing class RegionalPricingCalculator {

    @TestVisible private static final Decimal DEFAULT_MULTIPLIER = 1.0;

    /**
     * @description Country -> multiplier lookup (by name or code); default 1.0 when blank or unmatched.
     */
    public static Decimal getMultiplierForCountry(Map<String, Decimal> multipliers, String country) {
        if (String.isBlank(country)) {
            return DEFAULT_MULTIPLIER;
        }
        return multipliers.containsKey(country) ? multipliers.get(country) : DEFAULT_MULTIPLIER;
    }

    /**
     * @description Adjusted price rounded UP to the nearest $5. Null list -> null; null multiplier -> 1.0.
     */
    public static Decimal calculateAdjustedPrice(Decimal listPrice, Decimal multiplier) {
        if (listPrice == null) {
            return null;
        }
        if (multiplier == null) {
            multiplier = DEFAULT_MULTIPLIER;
        }
        Decimal rawPrice = listPrice * multiplier;
        // Round UP to nearest $5
        return (rawPrice / 5).setScale(0, System.RoundingMode.CEILING) * 5;
    }
}
