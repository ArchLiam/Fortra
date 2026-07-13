/**
 * @description Unit coverage for RenewalMaintenanceProvisionService guard and no-op paths. The full
 *              carryover-to-TermDefined swap is validated as a live RLM integration test: QuoteAction
 *              provenance and lifecycle-managed Assets are not insertable in Apex, and Quote DML is
 *              locked at the platform tier when RLM is enabled, so the DML path cannot be unit-built.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class RenewalMaintenanceProvisionServiceTest {

    /**
     * @description Bypass and empty/null inputs short-circuit before any query or DML, and bypass resets.
     */
    @isTest
    static void guardInputsAreNoOps() {
        Test.startTest();
        RenewalMaintenanceProvisionService.bypass = true;
        RenewalMaintenanceProvisionService.provision(new Set<Id>{ UserInfo.getUserId() });
        RenewalMaintenanceProvisionService.bypass = false;
        RenewalMaintenanceProvisionService.provision(null);
        RenewalMaintenanceProvisionService.provision(new Set<Id>());
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.isFalse(RenewalMaintenanceProvisionService.bypass, 'bypass should be reset after the run');
        Assert.areEqual(0, queriesUsed, 'guard paths must return before issuing any SOQL');
    }

    /**
     * @description A bulk set of ids that resolve to no maintenance carryover leaves the org unchanged
     *              and issues a single bulk query (no per-id SOQL).
     */
    @isTest
    static void bulkNonCarryoverQuotesAreNoOps() {
        Set<Id> quoteIds = new Set<Id>();
        for (Integer i = 0; i < 20; i++) {
            quoteIds.add(mockQuoteId(i));
        }

        Test.startTest();
        Integer before = Limits.getQueries();
        RenewalMaintenanceProvisionService.provision(quoteIds);
        Integer after = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(1, after - before,
            'a bulk provision with no carryovers must issue exactly one bulk query, not one per quote');
    }

    /**
     * @description SC-3346 anti-false-green telemetry (Stage 0): the missing-TermDefined-PBE Warning
     *              publishes through ExceptionLogger.safePublish without throwing, and the large-detail
     *              path truncates to MESSAGE_MAX. Telemetry must never toggle the bypass flag.
     */
    @isTest
    static void missingTermDefinedPbeWarningPublishesQuietly() {
        Set<String> many = new Set<String>();
        for (Integer i = 0; i < 5000; i++) {
            many.add('prod' + i + '|book' + i + '|USD'); // > MESSAGE_MAX joined -> exercises truncation
        }

        Test.startTest();
        RenewalMaintenanceProvisionService.publishMissingTermDefinedPbeWarning(
            new Set<String>{ 'p1|b1|USD', 'p2|b2|EUR' });
        RenewalMaintenanceProvisionService.publishMissingTermDefinedPbeWarning(many);
        Test.stopTest();

        Assert.isFalse(RenewalMaintenanceProvisionService.bypass,
            'telemetry must not leave bypass toggled');
    }

    /**
     * @description Deterministic, unique 15-char Quote id (dynamic key prefix) with no real record.
     * @param seed The row index.
     * @return A syntactically valid Quote id that does not correspond to a real record.
     */
    private static Id mockQuoteId(Integer seed) {
        String suffix = String.valueOf(seed);
        return Id.valueOf(
            Quote.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - suffix.length()) + suffix);
    }
}