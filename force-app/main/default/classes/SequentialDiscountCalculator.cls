/**
 * @description Pure sequential-discount primitive extracted from PartnerNetPricePosthook (Wave-2
 *              decomposition, build*Update tier — step 1). Centralizes the scale-2 / HALF_UP
 *              percent-off arithmetic that is copy-pasted inline across the derived-maintenance and
 *              attribute-stamp builders. No SOQL/DML/context/state — deterministic Decimal -> Decimal.
 *
 *              CONTRACT: returns `base` unchanged when percent is null or <= 0; otherwise
 *              base x (1 - percent/100), rounded to 2 decimals HALF_UP. This is the exact inline
 *              expression at the call sites; do NOT reuse it where a different scale/mode is expected.
 */
public with sharing class SequentialDiscountCalculator {

    public static Decimal applyDiscountPercent(Decimal base, Decimal percent) {
        if (percent == null || percent <= 0) {
            return base;
        }
        return (base * (1 - (percent / 100))).setScale(2, RoundingMode.HALF_UP);
    }
}
