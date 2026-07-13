/**
 * @description Unit tests for PartnerPricingGate, verifying the deferred partner-pricing and procedure-owned-partner gating decisions across representative field shapes.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class PartnerPricingGateTest {

    /**
     * @description Wraps each field value in the RCA context tag shape { field: { tagValue: v } } to build a test line map.
     * @param fields Map of field name to raw value to wrap.
     * @return Map of field name to a { tagValue: value } wrapper map.
     */
    private static Map<String, Object> line(Map<String, Object> fields) {
        Map<String, Object> m = new Map<String, Object>();
        for (String k : fields.keySet()) {
            m.put(k, new Map<String, Object>{ 'tagValue' => fields.get(k) });
        }
        return m;
    }

    /**
     * @description Verifies needsDeferredPartnerPricing returns true when net is positive, no partner unit is set, and pre-procedure prices are zero/absent (the derived-maint deferred case).
     */
    @IsTest
    static void needsDeferredPartnerPricing_trueWhenNetSetOverZeroPreProcedure() {
        // net > 0, no partner unit, pre-procedure price all zero/absent -> true
        System.assert(PartnerPricingGate.needsDeferredPartnerPricing(
            line(new Map<String, Object>{ 'NetUnitPrice' => 100 })), 'derived-maint deferred case');
    }

    /**
     * @description Verifies needsDeferredPartnerPricing returns false when a partner unit is already set, when there is no net, and when a positive pre-procedure price exists.
     */
    @IsTest
    static void needsDeferredPartnerPricing_falseCases() {
        System.assert(!PartnerPricingGate.needsDeferredPartnerPricing(
            line(new Map<String, Object>{ 'PartnerUnitPrice' => 50, 'NetUnitPrice' => 100 })),
            'partner unit already set -> false');
        System.assert(!PartnerPricingGate.needsDeferredPartnerPricing(
            line(new Map<String, Object>{ 'NetUnitPrice' => 0 })), 'no net -> false');
        System.assert(!PartnerPricingGate.needsDeferredPartnerPricing(
            line(new Map<String, Object>{ 'NetUnitPrice' => 100, 'UnitPrice' => 120 })),
            'positive pre-procedure price -> false');
    }

    /**
     * @description Verifies shouldSkipProcedureOwnedPartner returns true when the procedure net equals the partner unit price (procedure owns the pricing).
     */
    @IsTest
    static void shouldSkipProcedureOwnedPartner_trueWhenNetEqualsPartnerUnit() {
        // procedureNet == partnerUnitPrice == commercial -> procedure owns it
        System.assert(PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            line(new Map<String, Object>{}), 100, null, 100), 'net == partner unit -> skip');
    }

    /**
     * @description Verifies shouldSkipProcedureOwnedPartner returns true when the commercial price equals net and the line is procedure-sourced with a positive discount.
     */
    @IsTest
    static void shouldSkipProcedureOwnedPartner_trueWhenProcedureSourcedWithDiscount() {
        // partnerUnit 200, net 150 -> commercial 150 == net; source contains Procedure + discount>0 -> skip
        System.assert(PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            line(new Map<String, Object>{ 'Partner_Pricing_Source__c' => 'System Calculated (Procedure)' }),
            200, 10, 150), 'procedure-sourced with discount -> skip');
    }

    /**
     * @description Verifies shouldSkipProcedureOwnedPartner returns false when there is no partner unit, and when net differs from the commercial price with no procedure source.
     */
    @IsTest
    static void shouldSkipProcedureOwnedPartner_falseCases() {
        System.assert(!PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            line(new Map<String, Object>{}), 0, null, 100), 'no partner unit -> false');
        // net 300 >= partnerUnit 200 -> commercial 200 != net; no procedure source -> false
        System.assert(!PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            line(new Map<String, Object>{}), 200, 10, 300), 'net != commercial, no source -> false');
    }
}