/**
 * @description Pure first-renewal derived-maintenance net computation for the DPP pricing procedure —
 *              (source-asset gross base − prior partner$ − prior discretionary$) × (1 + COLA%) — the
 *              client three-component renewal model. Field-based, deterministic (no SOQL/DML/context),
 *              so the renewal-maintenance value is unit-testable in isolation and lives outside the
 *              COLA feature's classes.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class RenewalMaintenanceNetCalculator {

    /**
     * @description First-renewal maintenance net off the owned maintenance asset's gross per-unit base:
     *              (assetPrice − prior partner − prior discretionary) × (1 + COLA%). The prior discount
     *              dollars are netted exactly once (never re-applied as percentages). Worked example:
     *              (200 − 20 − 40) × 1.03 = 144.20.
     * @param assetPrice The prior maintenance asset's per-unit gross base price.
     * @param priorPartner The carried prior-year partner discount dollars (per unit).
     * @param priorDiscretionary The carried prior-year discretionary discount dollars (per unit).
     * @param lineDiscount The line's percent discount, used only when no discretionary dollars are carried.
     * @param colaPercent The COLA uplift percent to grow the net by.
     * @return The COLA-adjusted maintenance net, or null when assetPrice is null or the pre-COLA net is non-positive.
     */
    public static Decimal computeFirstRenewalNet(
        Decimal assetPrice,
        Decimal priorPartner,
        Decimal priorDiscretionary,
        Decimal lineDiscount,
        Decimal colaPercent
    ) {
        if (assetPrice == null) {
            return null;
        }
        Decimal partner = priorPartner != null ? priorPartner : 0;
        Decimal disc = priorDiscretionary != null && priorDiscretionary > 0
            ? priorDiscretionary
            : (lineDiscount != null && lineDiscount > 0
                ? ((assetPrice - partner) * (lineDiscount / 100)).setScale(2, System.RoundingMode.HALF_UP)
                : 0);
        Decimal cola = colaPercent != null ? colaPercent : 0;
        Decimal preColaNet = assetPrice - partner - disc;
        if (preColaNet <= 0) {
            return null;
        }
        return (preColaNet * (1 + (cola / 100))).setScale(2, System.RoundingMode.HALF_UP);
    }
}
