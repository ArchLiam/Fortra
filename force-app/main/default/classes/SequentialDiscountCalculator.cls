/**
 * @description Pure, stateless sequential-discount primitive that centralizes the scale-2 / HALF_UP
 *              percent-off arithmetic shared by the derived-maintenance and attribute-stamp builders.
 *              No SOQL/DML/context/state — a deterministic Decimal-to-Decimal calculation. Returns the
 *              base unchanged when percent is null or non-positive; otherwise base x (1 - percent/100),
 *              rounded to 2 decimals HALF_UP.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class SequentialDiscountCalculator {

    /**
     * @description Applies a single percent-off discount to a base amount, returning the base
     *              unchanged when percent is null or <= 0; otherwise base x (1 - percent/100)
     *              rounded to 2 decimals using HALF_UP.
     * @param base The starting amount to discount.
     * @param percent The percentage to subtract (e.g. 20 for 20% off); null or non-positive is a no-op.
     * @return The discounted amount at scale 2, or the original base when no discount applies.
     */
    public static Decimal applyDiscountPercent(Decimal base, Decimal percent) {
        if (percent == null || percent <= 0) {
            return base;
        }
        return (base * (1 - (percent / 100))).setScale(2, RoundingMode.HALF_UP);
    }
}