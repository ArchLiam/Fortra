@IsTest
private class PartnerPricingGateTest {

    // Wrap each field value in the RCA context tag shape { field: { tagValue: v } }.
    private static Map<String, Object> line(Map<String, Object> fields) {
        Map<String, Object> m = new Map<String, Object>();
        for (String k : fields.keySet()) {
            m.put(k, new Map<String, Object>{ 'tagValue' => fields.get(k) });
        }
        return m;
    }

    @IsTest
    static void needsDeferredPartnerPricing_trueWhenNetSetOverZeroPreProcedure() {
        // net > 0, no partner unit, pre-procedure price all zero/absent -> true
        System.assert(PartnerPricingGate.needsDeferredPartnerPricing(
            line(new Map<String, Object>{ 'NetUnitPrice' => 100 })), 'derived-maint deferred case');
    }

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

    @IsTest
    static void shouldSkipProcedureOwnedPartner_trueWhenNetEqualsPartnerUnit() {
        // procedureNet == partnerUnitPrice == commercial -> procedure owns it
        System.assert(PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            line(new Map<String, Object>{}), 100, null, 100), 'net == partner unit -> skip');
    }

    @IsTest
    static void shouldSkipProcedureOwnedPartner_trueWhenProcedureSourcedWithDiscount() {
        // partnerUnit 200, net 150 -> commercial 150 == net; source contains Procedure + discount>0 -> skip
        System.assert(PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            line(new Map<String, Object>{ 'Partner_Pricing_Source__c' => 'System Calculated (Procedure)' }),
            200, 10, 150), 'procedure-sourced with discount -> skip');
    }

    @IsTest
    static void shouldSkipProcedureOwnedPartner_falseCases() {
        System.assert(!PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            line(new Map<String, Object>{}), 0, null, 100), 'no partner unit -> false');
        // net 300 >= partnerUnit 200 -> commercial 200 != net; no procedure source -> false
        System.assert(!PartnerPricingGate.shouldSkipProcedureOwnedPartner(
            line(new Map<String, Object>{}), 200, 10, 300), 'net != commercial, no source -> false');
    }
}
