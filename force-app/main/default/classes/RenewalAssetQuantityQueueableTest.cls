/**
 * @description Unit coverage for RenewalAssetQuantityQueueable. The chained services run against the
 *              RLM-locked Quote/QuoteAction/Asset DML surface, which cannot be unit-built, so this
 *              exercises the guard/no-op happy path (empty + mock ids short-circuit inside the services)
 *              and the SC-3346 failure-telemetry helper directly.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class RenewalAssetQuantityQueueableTest {

    private class StepException extends Exception {}

    /**
     * @description execute() with no quotes runs both guarded steps to completion without throwing.
     */
    @isTest
    static void executeWithNoQuotesIsQuietNoOp() {
        Test.startTest();
        new RenewalAssetQuantityQueueable(null).execute(null);
        new RenewalAssetQuantityQueueable(new Set<Id>()).execute(null);
        Test.stopTest();

        Assert.isFalse(RenewalMaintenanceProvisionService.bypass,
            'guarded no-op execute must not leave the provisioner bypass toggled');
    }

    /**
     * @description SC-3346: the failure-telemetry helper publishes a Pricing_Exception__e Error through
     *              ExceptionLogger.safePublish without throwing back to the async job, for both a
     *              populated and an empty quote set.
     */
    @isTest
    static void publishFailureNeverThrows() {
        RenewalAssetQuantityQueueable withIds =
            new RenewalAssetQuantityQueueable(new Set<Id>{ UserInfo.getUserId() });
        RenewalAssetQuantityQueueable noIds =
            new RenewalAssetQuantityQueueable(new Set<Id>());

        Test.startTest();
        withIds.publishFailure('provision', new StepException('boom'));
        noIds.publishFailure('applyAssetQuantities', new StepException('boom'));
        Test.stopTest();

        Assert.isFalse(RenewalMaintenanceProvisionService.bypass, 'telemetry must not toggle bypass');
    }
}
