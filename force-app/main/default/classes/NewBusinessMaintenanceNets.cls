/**
 * @description Output DTO carrying New-Business derived-maintenance nets across the
 *              NewMaintenanceNetCalculator -> PartnerNetPricePosthook boundary. Promoted verbatim
 *              from the posthook's private inner class (Wave-2 decomposition, build*Update step 4)
 *              so the extracted net calculator can return it. Field-bag only — no logic/SOQL/state,
 *              so relocation from inner to top-level is name-transparent (zero test/cross-class refs).
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class NewBusinessMaintenanceNets {
    public Decimal expectedListNet;
    public Decimal expectedCommercialNet;
    public Decimal partnerPercent;
    public Decimal softwareDiscount;
}