/**
 * Pure hardware-pricing calculation, extracted from HardwareAttributePricingPrehook (Wave 2 hook-thinning).
 * Plain-input / plain-output; unit-testable without the RCA runtime. Behavior-identical to the prior inline
 * logic (same tables, same formula) — it was only relocated. This is also the future seam for
 * config-driving the multiplier tables (D-14).
 *
 * Formula: adjustedPrice = listPrice x pGroupMultiplier x userTierMultiplier x (1 - systemTypeDiscount/100)
 * Note: adjustedPrice is returned RAW (unrounded); the caller rounds, matching the prior inline behavior.
 * Ref: docs/pricing-refactor/PRICING_REFACTOR_PLAN.md  (Section 5.1 thin-hook = adapter over testable service; D-14)
 */
public with sharing class HardwarePricingCalculator {

    @TestVisible private static final Decimal DEFAULT_MULTIPLIER = 1.0;
    @TestVisible private static final Decimal DEFAULT_DISCOUNT = 0.0;

    // pGroup multiplier mappings (P05 through P60)
    private static final Map<String, Decimal> PGROUP_MULTIPLIERS = new Map<String, Decimal>{
        'P05' => 0.5,
        'P10' => 0.75,
        'P20' => 1.0,
        'P30' => 1.5,
        'P40' => 2.0,
        'P50' => 3.0,
        'P60' => 4.0
    };

    // User tier multiplier ranges
    private static final List<UserTierRange> USER_TIER_RANGES = new List<UserTierRange>{
        new UserTierRange(1, 10, 1.0),
        new UserTierRange(11, 50, 1.25),
        new UserTierRange(51, 100, 1.5),
        new UserTierRange(101, 250, 2.0),
        new UserTierRange(251, 500, 2.5),
        new UserTierRange(501, 999999, 3.0)
    };

    // System type discount mappings
    private static final Map<String, Decimal> SYSTEM_TYPE_DISCOUNTS = new Map<String, Decimal>{
        'Production' => 0.0,
        'Staging' => 25.0,
        'Test' => 50.0
    };

    private class UserTierRange {
        public Integer minUsers;
        public Integer maxUsers;
        public Decimal multiplier;
        public UserTierRange(Integer minU, Integer maxU, Decimal mult) {
            this.minUsers = minU;
            this.maxUsers = maxU;
            this.multiplier = mult;
        }
    }

    /** Result of a hardware price calculation. adjustedPrice is RAW (unrounded). */
    public class HardwarePriceResult {
        public Decimal pGroupMultiplier;
        public Decimal userTierMultiplier;
        public Decimal systemTypeDiscount;
        public Decimal combinedMultiplier;
        public Decimal adjustedPrice;
    }

    /**
     * @description Compute the hardware-adjusted price from list price + the three attributes.
     */
    public static HardwarePriceResult calculate(Decimal listPrice, String pGroup, Decimal usersPerPartition, String systemType) {
        HardwarePriceResult r = new HardwarePriceResult();
        r.pGroupMultiplier = getPGroupMultiplier(pGroup);
        r.userTierMultiplier = getUserTierMultiplier(usersPerPartition);
        r.systemTypeDiscount = getSystemTypeDiscount(systemType);
        r.combinedMultiplier = r.pGroupMultiplier * r.userTierMultiplier * (1 - r.systemTypeDiscount / 100);
        r.adjustedPrice = listPrice * r.combinedMultiplier;
        return r;
    }

    /** @description Get pGroup multiplier from static map (default 1.0). */
    @TestVisible
    public static Decimal getPGroupMultiplier(String pGroup) {
        if (String.isBlank(pGroup)) {
            return DEFAULT_MULTIPLIER;
        }
        return PGROUP_MULTIPLIERS.containsKey(pGroup) ? PGROUP_MULTIPLIERS.get(pGroup) : DEFAULT_MULTIPLIER;
    }

    /** @description Get user-tier multiplier based on user count (default 1.0). */
    @TestVisible
    public static Decimal getUserTierMultiplier(Decimal usersPerPartition) {
        if (usersPerPartition == null || usersPerPartition <= 0) {
            return DEFAULT_MULTIPLIER;
        }
        Integer users = usersPerPartition.intValue();
        for (UserTierRange range : USER_TIER_RANGES) {
            if (users >= range.minUsers && users <= range.maxUsers) {
                return range.multiplier;
            }
        }
        return DEFAULT_MULTIPLIER;
    }

    /** @description Get system-type discount percentage (default 0). */
    @TestVisible
    public static Decimal getSystemTypeDiscount(String systemType) {
        if (String.isBlank(systemType)) {
            return DEFAULT_DISCOUNT;
        }
        return SYSTEM_TYPE_DISCOUNTS.containsKey(systemType) ? SYSTEM_TYPE_DISCOUNTS.get(systemType) : DEFAULT_DISCOUNT;
    }
}