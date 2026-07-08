/**
 * Pure hardware-pricing calculation, extracted from HardwareAttributePricingPrehook (Wave 2 hook-thinning).
 * Plain-input / plain-output; unit-testable without the RCA runtime.
 *
 * D-14 (behavior-preserving config extraction): the three pricing tables — pGroup multipliers,
 * user-count-tier multipliers, and system-type discounts — are now read from the admin-editable
 * `Hardware_Attribute_Pricing__mdt` Custom Metadata Type, seeded with the EXACT prior hardcoded values
 * (Fortra-Products-Hardware-Solution-Design-Doc §8 Rules 2/3/4). Loaded once per transaction via
 * getAll() (NOT SOQL — no query-governor cost, matters for the SC-3447-sensitive waterfall). Lookup
 * semantics and lookup-miss defaults are unchanged; seeded config reproduces the old output byte-for-byte.
 *
 * Formula: adjustedPrice = listPrice x pGroupMultiplier x userTierMultiplier x (1 - systemTypeDiscount/100)
 * Note: adjustedPrice is returned RAW (unrounded); the caller rounds, matching the prior inline behavior.
 * Ref: docs/pricing-refactor/PRICING_REFACTOR_PLAN.md  (Section 5.1 thin-hook = adapter over testable service; D-14)
 */
public with sharing class HardwarePricingCalculator {

    // Lookup-MISS fallbacks (not table values — the safety default when a key/band is not configured).
    @TestVisible private static final Decimal DEFAULT_MULTIPLIER = 1.0;
    @TestVisible private static final Decimal DEFAULT_DISCOUNT = 0.0;

    // Hardware_Attribute_Pricing__mdt.Table_Type__c discriminator values.
    @TestVisible private static final String TYPE_PGROUP = 'pGroup';
    @TestVisible private static final String TYPE_USER_TIER = 'UserTier';
    @TestVisible private static final String TYPE_SYSTEM_TYPE = 'SystemType';

    // Config tables, lazily loaded once per transaction from the MDT (D-14). Null => not yet loaded.
    private static Map<String, Decimal> pGroupMultipliers;
    private static List<UserTierRange> userTierRanges;
    private static Map<String, Decimal> systemTypeDiscounts;

    private class UserTierRange implements Comparable {
        public Integer minUsers;
        public Integer maxUsers;   // null == open-ended top band (SDD §8 Rule 3: 501+ has no upper cap)
        public Decimal multiplier;
        public UserTierRange(Integer minU, Integer maxU, Decimal mult) {
            this.minUsers = minU;
            this.maxUsers = maxU;
            this.multiplier = mult;
        }
        // Ascending by minUsers so the contiguous bands evaluate low->high (open-ended top band last),
        // reproducing the fixed declaration order of the prior hardcoded list.
        public Integer compareTo(Object o) {
            Integer a = (this.minUsers == null) ? 0 : this.minUsers;
            Integer b = (((UserTierRange) o).minUsers == null) ? 0 : ((UserTierRange) o).minUsers;
            return (a < b) ? -1 : (a > b) ? 1 : 0;
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

    /** @description Get pGroup multiplier from the MDT-backed table (default 1.0 on blank/unknown). */
    @TestVisible
    public static Decimal getPGroupMultiplier(String pGroup) {
        if (String.isBlank(pGroup)) {
            return DEFAULT_MULTIPLIER;
        }
        ensureLoaded();
        return pGroupMultipliers.containsKey(pGroup) ? pGroupMultipliers.get(pGroup) : DEFAULT_MULTIPLIER;
    }

    /** @description Get user-tier multiplier for the user count from the MDT-backed bands (default 1.0). */
    @TestVisible
    public static Decimal getUserTierMultiplier(Decimal usersPerPartition) {
        if (usersPerPartition == null || usersPerPartition <= 0) {
            return DEFAULT_MULTIPLIER;
        }
        ensureLoaded();
        Integer users = usersPerPartition.intValue();
        for (UserTierRange range : userTierRanges) {
            // maxUsers == null => open-ended top band (SDD §8 Rule 3: 501+ = 3.0x, no upper cap).
            if (range.minUsers != null && users >= range.minUsers && (range.maxUsers == null || users <= range.maxUsers)) {
                return range.multiplier;
            }
        }
        return DEFAULT_MULTIPLIER;
    }

    /** @description Get system-type discount percentage from the MDT-backed table (default 0 on blank/unknown). */
    @TestVisible
    public static Decimal getSystemTypeDiscount(String systemType) {
        if (String.isBlank(systemType)) {
            return DEFAULT_DISCOUNT;
        }
        ensureLoaded();
        return systemTypeDiscounts.containsKey(systemType) ? systemTypeDiscounts.get(systemType) : DEFAULT_DISCOUNT;
    }

    /** @description Lazily load the three tables from Hardware_Attribute_Pricing__mdt (once per transaction). */
    private static void ensureLoaded() {
        if (pGroupMultipliers != null) {
            return;
        }
        loadFromRecords(Hardware_Attribute_Pricing__mdt.getAll().values());
    }

    /**
     * @description Rebuild the in-memory lookup tables from a set of MDT records. Also the test seam:
     *              unit tests inject a controlled table to prove the lookup reproduces the SDD values
     *              for every tier without coupling to the org's deployed (admin-editable) records.
     * @param recs MDT rows (each tagged by Table_Type__c: pGroup | UserTier | SystemType)
     */
    @TestVisible
    private static void loadFromRecords(List<Hardware_Attribute_Pricing__mdt> recs) {
        Map<String, Decimal> pg = new Map<String, Decimal>();
        List<UserTierRange> tiers = new List<UserTierRange>();
        Map<String, Decimal> st = new Map<String, Decimal>();
        for (Hardware_Attribute_Pricing__mdt r : recs) {
            if (r.Table_Type__c == TYPE_PGROUP) {
                if (String.isNotBlank(r.Attribute_Key__c)) {
                    pg.put(r.Attribute_Key__c, r.Value__c);
                }
            } else if (r.Table_Type__c == TYPE_USER_TIER) {
                Integer minU = (r.Min_Users__c == null) ? null : r.Min_Users__c.intValue();
                Integer maxU = (r.Max_Users__c == null) ? null : r.Max_Users__c.intValue();
                tiers.add(new UserTierRange(minU, maxU, r.Value__c));
            } else if (r.Table_Type__c == TYPE_SYSTEM_TYPE) {
                if (String.isNotBlank(r.Attribute_Key__c)) {
                    st.put(r.Attribute_Key__c, r.Value__c);
                }
            }
        }
        tiers.sort();
        pGroupMultipliers = pg;
        userTierRanges = tiers;
        systemTypeDiscounts = st;
    }
}
