/**
 * @description Unit tests for CurrencyDisplayReconciliationService. The twin-match depends on the
 *              org's Currency_Conversion_Formula__mdt (static, Finance-governed rates), so expected
 *              values are derived from the live rate via convertPrice(1, iso) rather than hardcoded.
 *              The EUR canary flags a CMDT drift (intended alarm, not test flakiness).
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class CurrencyDisplayReconciliationServiceTest {

    private static final String EUR = 'EUR';
    private static final String CAD = 'CAD';
    private static final String USD = 'USD';

    /**
     * @description Governed rate for a currency, read from the live CMDT (convertPrice of 1 unit).
     * @param iso The currency ISO code.
     * @return The conversion rate applied to a USD amount for that currency.
     */
    private static Decimal rateFor(String iso) {
        Fortra_CurrencyConversionService.clearCache();
        return Fortra_CurrencyConversionService.convertPrice(1, iso);
    }

    /**
     * @description Asserts two Decimals are within 0.01 of each other, failing when actual is null.
     * @param expected The expected value.
     * @param actual The actual value.
     * @param label A descriptive assertion message.
     */
    private static void assertClose(Decimal expected, Decimal actual, String label) {
        Assert.isNotNull(actual, label + ' (was null)');
        Assert.isTrue((expected - actual).abs() <= 0.01,
            label + ' expected≈' + expected + ' actual=' + actual);
    }

    @isTest
    static void eurAbpLeakReconcilesToConvertedNet() {
        // AAM repro: Sales Price leaked raw USD 857.75 while the engine converted Net to 857.75 x rate.
        Decimal rawUsd = 857.75;
        Decimal convertedNet = (rawUsd * rateFor(EUR)).setScale(4, RoundingMode.HALF_UP);

        Test.startTest();
        CurrencyDisplayReconciliationService.Reconciliation rec =
            CurrencyDisplayReconciliationService.evaluate(EUR, rawUsd, convertedNet, convertedNet, false);
        Test.stopTest();

        Assert.isTrue(rec.writeNeeded, 'EUR ABP leak must reconcile');
        assertClose(convertedNet, rec.alignedUnit, 'aligned Sales Price == converted net');
        assertClose(convertedNet, rec.alignedTotal, 'aligned total == converted net total');
    }

    @isTest
    static void cadLeakReconcilesWhenRateAboveOne() {
        // CAD rate > 1: the raw USD Sales Price is LOWER than the converted net (converted up).
        Decimal rawUsd = 100;
        Decimal convertedNet = (rawUsd * rateFor(CAD)).setScale(4, RoundingMode.HALF_UP);

        CurrencyDisplayReconciliationService.Reconciliation rec =
            CurrencyDisplayReconciliationService.evaluate(CAD, rawUsd, convertedNet, convertedNet, false);

        Assert.isTrue(rec.writeNeeded, 'CAD leak must reconcile (rate > 1)');
        assertClose(convertedNet, rec.alignedUnit, 'CAD aligned Sales Price');
    }

    @isTest
    static void usdLineIsNeverTouched() {
        CurrencyDisplayReconciliationService.Reconciliation rec =
            CurrencyDisplayReconciliationService.evaluate(USD, 857.75, 801.66, 801.66, false);
        Assert.isFalse(rec.writeNeeded, 'USD line must not reconcile');
    }

    @isTest
    static void recordedDiscountBlocksReconciliation() {
        // Same numbers as the positive case, but a recorded discount => gross may legitimately differ.
        Decimal rawUsd = 857.75;
        Decimal convertedNet = (rawUsd * rateFor(EUR)).setScale(4, RoundingMode.HALF_UP);

        CurrencyDisplayReconciliationService.Reconciliation rec =
            CurrencyDisplayReconciliationService.evaluate(EUR, rawUsd, convertedNet, convertedNet, true);
        Assert.isFalse(rec.writeNeeded, 'a recorded discount must block reconciliation');
    }

    @isTest
    static void consistentLineIsNoOp() {
        // Sales Price already equals net (posthook-localized or list==net) => nothing to do.
        CurrencyDisplayReconciliationService.Reconciliation rec =
            CurrencyDisplayReconciliationService.evaluate(EUR, 770.11, 770.11, 770.11, false);
        Assert.isFalse(rec.writeNeeded, 'a consistent line must be a no-op');
    }

    @isTest
    static void nonCurrencyDivergenceIsLeftAlone() {
        // A 20% divergence is NOT the currency rate => not a leak, leave it (protects real discounts
        // that happen not to be recorded on the three discount tags).
        CurrencyDisplayReconciliationService.Reconciliation rec =
            CurrencyDisplayReconciliationService.evaluate(EUR, 1000, 800, 800, false);
        Assert.isFalse(rec.writeNeeded, 'a non-currency divergence must not reconcile');
    }

    @isTest
    static void nullAndZeroInputsAreNoOps() {
        Assert.isFalse(
            CurrencyDisplayReconciliationService.evaluate(EUR, null, 801.66, 801.66, false).writeNeeded,
            'null Sales Price is a no-op');
        Assert.isFalse(
            CurrencyDisplayReconciliationService.evaluate(EUR, 857.75, null, null, false).writeNeeded,
            'null net is a no-op');
        Assert.isFalse(
            CurrencyDisplayReconciliationService.evaluate(EUR, 0, 801.66, 801.66, false).writeNeeded,
            'zero Sales Price is a no-op');
        Assert.isFalse(
            CurrencyDisplayReconciliationService.evaluate(null, 857.75, 801.66, 801.66, false).writeNeeded,
            'blank currency is a no-op');
    }

    @isTest
    static void reconciliationIsIdempotent() {
        // After a prior reconciliation Sales Price == net, so a re-run finds no divergence.
        Decimal net = (857.75 * rateFor(EUR)).setScale(4, RoundingMode.HALF_UP);
        CurrencyDisplayReconciliationService.Reconciliation rec =
            CurrencyDisplayReconciliationService.evaluate(EUR, net, net, net, false);
        Assert.isFalse(rec.writeNeeded, 're-run on an already-aligned line must be a no-op');
    }

    @isTest
    static void alignedTotalFallsBackToNetUnitWhenTotalMissing() {
        Decimal rawUsd = 857.75;
        Decimal convertedNet = (rawUsd * rateFor(EUR)).setScale(4, RoundingMode.HALF_UP);
        CurrencyDisplayReconciliationService.Reconciliation rec =
            CurrencyDisplayReconciliationService.evaluate(EUR, rawUsd, convertedNet, null, false);
        Assert.isTrue(rec.writeNeeded, 'missing net total still reconciles');
        assertClose(convertedNet, rec.alignedTotal, 'alignedTotal falls back to net unit');
    }

    @isTest
    static void eurRateCanary() {
        // Config-drift alarm: the deployed EUR rate must remain the confirmed 0.9346.
        assertClose(0.9346, rateFor(EUR), 'EUR CMDT rate canary');
    }

    @isTest
    static void bulkEvaluationsAreStable() {
        Decimal rate = rateFor(EUR);
        for (Integer i = 1; i <= 25; i++) {
            Decimal rawUsd = 100 + i;
            Decimal net = (rawUsd * rate).setScale(4, RoundingMode.HALF_UP);
            CurrencyDisplayReconciliationService.Reconciliation rec =
                CurrencyDisplayReconciliationService.evaluate(EUR, rawUsd, net, net, false);
            Assert.isTrue(rec.writeNeeded, 'bulk row ' + i + ' must reconcile');
            assertClose(net, rec.alignedUnit, 'bulk row ' + i + ' aligned unit');
        }
    }
}
