/**
 * @description Unit tests for AbaCurrencyCorrectionService.evaluate. Pure logic; relies only
 *              on the org's Currency_Conversion_Formula__mdt (static, Finance-governed rates). Every
 *              test encodes one of the adversarially-verified failure modes the design must not exhibit:
 *              per-unit scaling (qty>1), provenance vs value-identity (the collision cohort), idempotency
 *              (no FX compounding), USD 0-delta, the $0-USD-PBE cohort, and the no-governed-rate fail-safe.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class AbaCurrencyCorrectionServiceTest {

    // Confirmed live rates (Currency_Conversion_Formula__mdt.Conversion_Rate__c). If the CMDT drifts,
    // the EUR canary below flags it — that is intended (a config-drift alarm, not test flakiness).
    private static final String EUR = 'EUR';
    private static final String GBP = 'GBP';
    private static final String AUD = 'AUD';
    private static final String CAD = 'CAD';

    /**
     * @description Asserts two Decimals are within 0.0005 of each other, failing when actual is null.
     * @param expected the expected value
     * @param actual the computed value under test
     * @param msg the assertion message prefix used on failure
     */
    private static void assertClose(Decimal expected, Decimal actual, String msg) {
        System.assertNotEquals(null, actual, msg + ' (actual was null)');
        System.assert((expected - actual).abs() < 0.0005,
            msg + ' expected=' + expected + ' actual=' + actual);
    }

    /**
     * @description Returns the governed conversion rate for an ISO currency by converting 1 USD.
     * @param iso the ISO currency code to look up
     * @return the per-unit conversion rate for the currency
     */
    private static Decimal rateFor(String iso) {
        return Fortra_CurrencyConversionService.convertPrice(1, iso);
    }

    /**
     * @description Verifies a raw USD ABA override of 1575 on a EUR line localizes to the confirmed target 1471.995 per unit and total.
     */
    @isTest
    static void eurAampReproducesConfirmedTarget() {
        // AAMP: raw USD ABA Override 1575 on a EUR line -> confirmed business target 1471.995.
        AbaCurrencyCorrectionService.Correction c =
            AbaCurrencyCorrectionService.evaluate(1575, EUR, 1575, 1);
        System.assertEquals(true, c.writeNeeded, 'EUR AAMP must localize');
        assertClose(1471.995, c.localizedUnit, 'EUR AAMP per-unit');
        assertClose(1471.995, c.localizedTotal, 'EUR AAMP total (qty 1)');
    }

    /**
     * @description Verifies every demand currency (EUR, GBP, AUD, CAD) localizes the raw USD net by its governed rate.
     */
    @isTest
    static void allDemandCurrenciesScaleFromRawUsd() {
        for (String iso : new List<String>{ EUR, GBP, AUD, CAD }) {
            Decimal expected = 1575 * rateFor(iso);
            AbaCurrencyCorrectionService.Correction c =
                AbaCurrencyCorrectionService.evaluate(1575, iso, 1575, 1);
            System.assertEquals(true, c.writeNeeded, iso + ' must localize');
            assertClose(expected, c.localizedUnit, iso + ' per-unit');
        }
    }

    /**
     * @description Verifies a qty>1 line localizes per-unit as rawNet*rate with total = unit*qty, not double-scaled.
     */
    @isTest
    static void perUnitScalingHandlesQtyGreaterThanOne() {
        // Verdict-3 regression: a single-override, non-self-covering product at qty=2. The correct value
        // is per-unit rawNet * rate, with totals = unit * qty. A total-carrier read would 2x-overcharge
        // or miss the line entirely; provenance + per-unit avoids both.
        Decimal rawUnit = 1610; // product 01tWC00000DD1YwYAL: only override is 1610
        Decimal rate = rateFor(AUD);
        AbaCurrencyCorrectionService.Correction c =
            AbaCurrencyCorrectionService.evaluate(rawUnit, AUD, rawUnit, 2);
        System.assertEquals(true, c.writeNeeded, 'qty>1 AUD line must localize');
        assertClose(rawUnit * rate, c.localizedUnit, 'per-unit is rawNet*rate, not (rawNet*qty)*rate');
        assertClose(rawUnit * rate * 2, c.localizedTotal, 'total is per-unit * qty');
    }

    /**
     * @description Verifies a line whose net already equals raw*rate is a no-op, preventing FX compounding on re-run.
     */
    @isTest
    static void idempotentWhenAlreadyLocalized() {
        // Re-reprice / order-path re-run: current net already equals raw*rate -> no write (no compounding).
        Decimal localized = 1575 * rateFor(EUR);
        AbaCurrencyCorrectionService.Correction c =
            AbaCurrencyCorrectionService.evaluate(1575, EUR, localized, 1);
        System.assertEquals(false, c.writeNeeded, 'already-localized line must be a no-op');
    }

    /**
     * @description Verifies provenance uses the raw snapshot so a value-collision line localizes once and never double-scales.
     */
    @isTest
    static void collisionCohortIsSafeViaProvenance() {
        // VLM CAD: the actual ABA match snapshotted rawNet=360; 360*rate rounds onto another product
        // override (500). Value-identity would re-scale the localized 500 to 694; provenance uses the
        // snapshot (360) and, once the net equals 360*rate, is idempotent -> never double-scales.
        Decimal rate = rateFor(CAD);
        Decimal localized = 360 * rate; // ~500.004
        AbaCurrencyCorrectionService.Correction first =
            AbaCurrencyCorrectionService.evaluate(360, CAD, 360, 1);
        System.assertEquals(true, first.writeNeeded, 'first pass localizes from the true raw 360');
        assertClose(localized, first.localizedUnit, 'localizes 360, not the collided 500');

        AbaCurrencyCorrectionService.Correction second =
            AbaCurrencyCorrectionService.evaluate(360, CAD, localized, 1);
        System.assertEquals(false, second.writeNeeded, 'no re-scale of the already-localized collision line');
    }

    /**
     * @description Verifies a USD line is always a no-op (zero delta) since USD is authoritative.
     */
    @isTest
    static void usdIsAlwaysNoOp() {
        AbaCurrencyCorrectionService.Correction c =
            AbaCurrencyCorrectionService.evaluate(1575, 'USD', 1575, 1);
        System.assertEquals(false, c.writeNeeded, 'USD is authoritative: 0-delta');
    }

    /**
     * @description Verifies lines with no raw ABA snapshot (null or zero raw net) are never corrected.
     */
    @isTest
    static void nonAbaLineIsNoOp() {
        // No raw snapshot => not ABA-priced => never touched (list / partner / C-tier lines).
        System.assertEquals(false,
            AbaCurrencyCorrectionService.evaluate(null, EUR, 2943.99, 1).writeNeeded,
            'null raw net => no correction');
        System.assertEquals(false,
            AbaCurrencyCorrectionService.evaluate(0, EUR, 2943.99, 1).writeNeeded,
            'zero raw net => no correction');
    }

    /**
     * @description Verifies the $0-USD-PBE cohort localizes via the CMDT rate without divide-by-zero and never emits $0.
     */
    @isTest
    static void zeroPbeCohortLocalizesWithoutDivideByZero() {
        // $0-USD-PBE product: price lives entirely in the ABA override (e.g. 185430). CMDT rate needs no
        // PBE denominator, so it localizes with no divide-by-zero and never emits $0.
        Decimal raw = 185430;
        Decimal expected = raw * rateFor(EUR);
        AbaCurrencyCorrectionService.Correction c =
            AbaCurrencyCorrectionService.evaluate(raw, EUR, raw, 1);
        System.assertEquals(true, c.writeNeeded, '$0-PBE cohort still localizes');
        assertClose(expected, c.localizedUnit, '$0-PBE localizes via CMDT rate');
        System.assert(c.localizedUnit > 0, 'never $0');
    }

    /**
     * @description Verifies a currency with no governed rate leaves the line raw (no write) instead of zeroing it.
     */
    @isTest
    static void unknownCurrencyLeavesLineRawRatherThanZero() {
        // No governed rate for the currency: fail-safe leaves the line raw (no write), never $0.
        AbaCurrencyCorrectionService.Correction c =
            AbaCurrencyCorrectionService.evaluate(1000, 'ZZZ', 1000, 1);
        System.assertEquals(false, c.writeNeeded, 'no governed rate => leave raw, do not zero it');
    }

    /**
     * @description Verifies null or zero quantity is treated as 1 so the localized total equals the localized unit.
     */
    @isTest
    static void quantityNullOrZeroTreatedAsOne() {
        Decimal expected = 1575 * rateFor(EUR);
        AbaCurrencyCorrectionService.Correction cNull =
            AbaCurrencyCorrectionService.evaluate(1575, EUR, 1575, null);
        assertClose(expected, cNull.localizedTotal, 'null qty -> total == unit');
        AbaCurrencyCorrectionService.Correction cZero =
            AbaCurrencyCorrectionService.evaluate(1575, EUR, 1575, 0);
        assertClose(expected, cZero.localizedTotal, 'zero qty -> total == unit');
    }
}