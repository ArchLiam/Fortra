/**
 * @description Unit tests for SequentialDiscountCalculator, validating percentage-based discount application and HALF_UP rounding behavior.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class SequentialDiscountCalculatorTest {

    /**
     * @description Verifies that applyDiscountPercent returns the unchanged base amount when the percent is null, zero, or negative.
     */
    @IsTest
    static void applyDiscountPercent_nullZeroNegativeReturnsBase() {
        System.assertEquals(1000, SequentialDiscountCalculator.applyDiscountPercent(1000, null), 'null percent -> base');
        System.assertEquals(1000, SequentialDiscountCalculator.applyDiscountPercent(1000, 0), 'zero percent -> base');
        System.assertEquals(1000, SequentialDiscountCalculator.applyDiscountPercent(1000, -5), 'negative percent -> base');
    }

    /**
     * @description Verifies that applyDiscountPercent applies a positive discount percentage and rounds the result to two decimals using HALF_UP.
     */
    @IsTest
    static void applyDiscountPercent_positiveRoundsHalfUp() {
        System.assertEquals(900.00, SequentialDiscountCalculator.applyDiscountPercent(1000, 10), '1000 less 10% = 900.00');
        System.assertEquals(855.00, SequentialDiscountCalculator.applyDiscountPercent(900, 5), '900 less 5% = 855.00');
        // 33.33 x 0.90 = 29.997 -> setScale(2, HALF_UP) = 30.00 (exercises rounding)
        System.assertEquals(30.00, SequentialDiscountCalculator.applyDiscountPercent(33.33, 10), 'HALF_UP rounds 29.997 -> 30.00');
    }
}