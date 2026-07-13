/**
 * @description Provides pure, unit-testable regional-services pricing calculations (country multiplier lookup, effective-date evaluation, and adjusted-price rounding) with plain-input/plain-output signatures and no dependency on the RCA runtime. The adjusted price is CEILING((listPrice x multiplier) / 5) x 5, i.e. rounded up to the nearest $5.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class RegionalPricingCalculator {

    @TestVisible private static final Decimal DEFAULT_MULTIPLIER = 1.0;

    /**
     * @description Resolves a country to its pricing multiplier by name or code, returning DEFAULT_MULTIPLIER (1.0) when the country is blank, unmatched, or maps to a null multiplier.
     * @param multipliers Country name/code -> multiplier lookup map
     * @param country The country name or code to resolve
     * @return The matched multiplier, or DEFAULT_MULTIPLIER (1.0) when blank, unmatched, or null
     */
    public static Decimal getMultiplierForCountry(Map<String, Decimal> multipliers, String country) {
        if (String.isBlank(country)) {
            return DEFAULT_MULTIPLIER;
        }
        // A-6: an Active multiplier row with a null Multiplier__c has no real multiplier — resolve it
        // to DEFAULT_MULTIPLIER so the prehook's default-multiplier short-circuit SKIPS the line
        // (leaves it untouched) rather than adjusting a price off a null. Provably 0-delta today
        // (0 live rows have a null Multiplier__c). The not-found case still resolves to DEFAULT too.
        Decimal multiplier = multipliers.get(country);
        return multiplier != null ? multiplier : DEFAULT_MULTIPLIER;
    }

    /**
     * @description Whether a regional-pricing multiplier row is in effect as of a given date.
     *              Implements SDD Rule 14 / BR-007 (effective dating) for the CMDT
     *              Services_Regional_Pricing__mdt (Effective_Start_Date__c / Effective_End_Date__c).
     *              Bounds are INCLUSIVE: asOf == start (or == end) counts as effective. A null start
     *              means "no lower bound" (already started); a null end means "no upper bound" (never
     *              expires) — so a row with both dates null always loads, preserving prior behavior.
     *              Evaluated in memory because CMDT SOQL does not support the null-safe OR window and
     *              __mdt rows cannot be inserted in a unit test.
     * @param startDate Effective_Start_Date__c (nullable)
     * @param endDate   Effective_End_Date__c (nullable)
     * @param asOf      The date to evaluate against (typically Date.today())
     * @return true when the row is effective on asOf
     */
    public static Boolean isEffectiveOn(Date startDate, Date endDate, Date asOf) {
        if (asOf == null) {
            return true;
        }
        if (startDate != null && asOf < startDate) {
            return false; // not yet effective
        }
        if (endDate != null && asOf > endDate) {
            return false; // already expired
        }
        return true;
    }

    /**
     * @description Computes the adjusted price by multiplying the list price by the multiplier and rounding UP to the nearest $5; returns null for a null list price and treats a null multiplier as 1.0.
     * @param listPrice The base list price (nullable)
     * @param multiplier The regional multiplier (nullable; defaults to 1.0)
     * @return The adjusted price rounded up to the nearest $5, or null when listPrice is null
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