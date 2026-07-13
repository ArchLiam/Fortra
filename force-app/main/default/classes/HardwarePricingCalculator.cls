/**
 * @description Computes hardware-adjusted pricing as a plain-input/plain-output, unit-testable
 *              service (extracted from HardwareAttributePricingPrehook): adjustedPrice = listPrice
 *              x pGroupMultiplier x userTierMultiplier x (1 - systemTypeDiscount/100), returned RAW
 *              (unrounded) for the caller to round. The three pricing tables (pGroup multipliers,
 *              user-count-tier multipliers, and system-type discounts) are read once per transaction
 *              from the admin-editable Hardware_Attribute_Pricing__mdt Custom Metadata Type, whose
 *              seeded values reproduce the prior hardcoded output byte-for-byte.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
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
        /**
         * @description Orders bands ascending by minUsers so contiguous bands evaluate low->high
         *              (open-ended top band last), reproducing the fixed declaration order of the
         *              prior hardcoded list.
         * @param o the other UserTierRange being compared
         * @return -1, 0, or 1 per the Comparable contract
         */
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
     * @description Computes the hardware-adjusted price from list price plus the three pricing
     *              attributes, returning each intermediate multiplier/discount and the RAW
     *              (unrounded) adjusted price.
     * @param listPrice the catalog list price to adjust
     * @param pGroup the hardware processor-group key driving the pGroup multiplier
     * @param usersPerPartition the user count per partition driving the user-tier multiplier
     * @param systemType the system-type key driving the discount percentage
     * @return a HardwarePriceResult holding each multiplier/discount and the raw adjusted price
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

    /**
     * @description Returns the pGroup multiplier from the MDT-backed table.
     * @param pGroup the processor-group key to look up
     * @return the configured multiplier, or 1.0 when pGroup is blank or unknown
     */
    @TestVisible
    public static Decimal getPGroupMultiplier(String pGroup) {
        if (String.isBlank(pGroup)) {
            return DEFAULT_MULTIPLIER;
        }
        ensureLoaded();
        return pGroupMultipliers.containsKey(pGroup) ? pGroupMultipliers.get(pGroup) : DEFAULT_MULTIPLIER;
    }

    /**
     * @description Returns the user-tier multiplier for the given user count from the MDT-backed bands.
     * @param usersPerPartition the user count per partition to band
     * @return the configured multiplier for the matching band, or 1.0 when null/non-positive or unmatched
     */
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

    /**
     * @description Returns the system-type discount percentage from the MDT-backed table.
     * @param systemType the system-type key to look up
     * @return the configured discount percentage, or 0 when systemType is blank or unknown
     */
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