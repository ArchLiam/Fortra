/**
 * @description Unit coverage for AssetNetUnitPrice.perUnit — the shared per-unit recovery used by the
 *              amend net-carry and COLA renewal prehooks (SC-3501 quantity-fold-inflation fix).
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class AssetNetUnitPriceTest {

    /**
     * @description Verifies the per-unit is the extended Asset.Price total divided by the source asset
     *              quantity — the core of the fix: a multi-quantity asset (Price 273540 / Qty 10) must
     *              yield the 27354 per-unit, not the 273540 total.
     */
    @IsTest
    static void perUnit_dividesExtendedTotalByQuantity() {
        System.assertEquals(27354, AssetNetUnitPrice.perUnit(273540, 10), 'qty 10 -> per-unit 27354');
        System.assertEquals(21.60, AssetNetUnitPrice.perUnit(2160, 100), 'qty 100 -> per-unit 21.60');
        System.assertEquals(27354, AssetNetUnitPrice.perUnit(82062, 3), 'qty 3 -> per-unit 27354');
        System.assertEquals(59.99, AssetNetUnitPrice.perUnit(599.90, 10), 'qty 10 -> per-unit 59.99');
        System.assertEquals(4125, AssetNetUnitPrice.perUnit(8250000, 2000), 'qty 2000 -> per-unit 4125');
    }

    /**
     * @description Verifies a qty-1 (or null/zero/negative) source asset is a no-op: its Price already IS
     *              the per-unit, so the divide must not change it and must never divide by zero.
     */
    @IsTest
    static void perUnit_qtyOneOrMissingIsNoOp() {
        System.assertEquals(27354, AssetNetUnitPrice.perUnit(27354, 1), 'qty 1 -> unchanged');
        System.assertEquals(27354, AssetNetUnitPrice.perUnit(27354, null), 'null qty -> treat as 1');
        System.assertEquals(27354, AssetNetUnitPrice.perUnit(27354, 0), 'zero qty -> treat as 1, no div/0');
        System.assertEquals(27354, AssetNetUnitPrice.perUnit(27354, -5), 'negative qty -> treat as 1');
    }

    /**
     * @description Verifies a null asset total yields null (line left to procedure fallback) and that a
     *              non-terminating per-unit is rounded HALF_UP to two decimal places.
     */
    @IsTest
    static void perUnit_nullTotalReturnsNull_andRoundsHalfUp() {
        System.assertEquals(null, AssetNetUnitPrice.perUnit(null, 10), 'null total -> null');
        System.assertEquals(33.33, AssetNetUnitPrice.perUnit(100, 3), '100/3 -> 33.33 HALF_UP');
    }
}
