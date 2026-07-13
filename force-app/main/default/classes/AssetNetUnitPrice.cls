/**
 * @description Shared helper for the renewal/amend pricing prehooks: recovers a source Asset's per-unit
 *              net from its stored Price. In this org Asset.Price is the EXTENDED line total
 *              (per-unit x Quantity) — verified across the live asset book (e.g. EFT 7 Enterprise
 *              273540/qty10 = 27354, ARC 2160/qty100 = 21.60) — NOT the per-unit, so the per-unit is
 *              Price / Quantity. Used by AmendNetCarryPrehook (amend net-carry seed) and COLAUpliftPrehook
 *              (renewal COLA base), both of which derive a prior per-unit net from QuoteAction.SourceAsset.
 *              A qty-1 asset (whose Price already IS the per-unit) divides by 1 (no-op), which is why
 *              single-unit source assets never surfaced the quantity-fold inflation.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class AssetNetUnitPrice {

    /**
     * @description Per-unit net = assetTotalPrice / quantity, rounded HALF_UP to 2 dp (currency scale).
     *              A null or <=0 quantity is treated as 1: a qty-1 asset's Price already IS the per-unit,
     *              so the divide is a safe no-op and never divides by zero. Returns null when the asset
     *              total is null, so callers can fall back to their procedure default.
     * @param assetTotalPrice The source Asset.Price (extended line total = per-unit x quantity).
     * @param assetQuantity The source Asset.Quantity; null or <=0 is treated as 1.
     * @return The per-unit net rounded HALF_UP to 2 dp, or null when assetTotalPrice is null.
     */
    public static Decimal perUnit(Decimal assetTotalPrice, Decimal assetQuantity) {
        if (assetTotalPrice == null) {
            return null;
        }
        Decimal divisor = (assetQuantity != null && assetQuantity > 0) ? assetQuantity : 1;
        return (assetTotalPrice / divisor).setScale(2, System.RoundingMode.HALF_UP);
    }
}
