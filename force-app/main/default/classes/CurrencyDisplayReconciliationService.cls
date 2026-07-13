/**
 * @description Reconciles a non-USD line's "display" price fields (Sales Price / Subtotal /
 *              Total Line Amount) when they leaked a raw USD value while the pricing engine
 *              converted the matching "net" fields (Net Unit / Net Total / Total).
 *
 *              Attribute-based-priced (ABP) lines carry no flat catalog value for the
 *              ABA / PricebookEntry / ATPS provenance gate, so [[AbaCurrencyCorrectionService]]
 *              cannot localize them. The pricing engine converts their Net (via the governed rate)
 *              but leaves Sales Price / Subtotal / Total Line Amount at the raw USD figure, and
 *              books the difference as a phantom line adjustment — a split like Net 801.66 vs
 *              Sales Price 857.75 on an EUR line whose List Price is already correct.
 *
 *              This pure service decides, per line, whether the gross-vs-net divergence is purely a
 *              currency leak — the display value is the raw-USD twin of the already-converted net
 *              (display x governed rate == net) AND the line carries NO recorded discount that would
 *              legitimately separate gross from net — and, if so, returns the net values to align the
 *              display fields to. It aligns to the engine's own converted net (never re-converts), so
 *              it is exact and idempotent and cannot double-multiply a value already in quote currency.
 *
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class CurrencyDisplayReconciliationService {

    private static final String USD = 'USD';

    /**
     * @description Twin-match band: |display x rate - net| must be within max(1 cent, 0.1% of net).
     *              Wide enough to absorb the sub-cent gap between the engine converting the true
     *              (unrounded) USD net and this check converting the 2-dp display value; tight enough
     *              that only a divergence that is essentially exactly the currency rate qualifies.
     */
    @TestVisible
    private static final Decimal RELATIVE_TOLERANCE = 0.001;
    @TestVisible
    private static final Decimal ABSOLUTE_TOLERANCE = 0.01;

    /**
     * @description Outcome of evaluating one line. `writeNeeded` is true only when the line is a
     *              non-USD, non-discounted line whose display fields are the raw-USD twin of its
     *              already-converted net.
     */
    public class Reconciliation {
        public final Boolean writeNeeded;
        public final Decimal alignedUnit;
        public final Decimal alignedTotal;

        @TestVisible
        private Reconciliation(Boolean writeNeeded, Decimal alignedUnit, Decimal alignedTotal) {
            this.writeNeeded = writeNeeded;
            this.alignedUnit = alignedUnit;
            this.alignedTotal = alignedTotal;
        }
    }

    private static final Reconciliation NONE = new Reconciliation(false, null, null);

    /**
     * @description Decide whether a line's display fields leaked raw USD and, if so, the net values
     *              to align them to.
     * @param lineCurrency the line CurrencyIsoCode.
     * @param unitPrice the display Sales Price (raw USD when leaked).
     * @param netUnitPrice the converted net unit price (engine output; authoritative in quote currency).
     * @param netTotalPrice the converted net total price (engine output).
     * @param hasRecordedDiscount whether the line carries a real discount (gross may legitimately differ from net).
     * @return Reconciliation. writeNeeded=false (a no-op) when the line is USD, discounted, has no
     *         divergence, or the divergence is not exactly the currency conversion.
     */
    public static Reconciliation evaluate(
        String lineCurrency,
        Decimal unitPrice,
        Decimal netUnitPrice,
        Decimal netTotalPrice,
        Boolean hasRecordedDiscount
    ) {
        // USD is authoritative and never converted: 0-delta by construction.
        if (String.isBlank(lineCurrency) || USD.equalsIgnoreCase(lineCurrency)) {
            return NONE;
        }
        // A real discount legitimately separates gross (Sales Price) from net — never collapse it.
        if (hasRecordedDiscount == true) {
            return NONE;
        }
        if (unitPrice == null || unitPrice <= 0 || netUnitPrice == null || netUnitPrice <= 0) {
            return NONE;
        }
        // No divergence => nothing leaked (already consistent, e.g. list == net or posthook-localized).
        if (unitPrice.setScale(2, RoundingMode.HALF_UP) == netUnitPrice.setScale(2, RoundingMode.HALF_UP)) {
            return NONE;
        }
        // Twin confirmation: the display value must be the raw-USD twin of the converted net —
        // unitPrice x governedRate ~= netUnitPrice. This proves the divergence is exactly the currency
        // conversion (not an unrecorded adjustment) before we collapse the display fields onto the net.
        Decimal ratedUnit = Fortra_CurrencyConversionService.convertPrice(unitPrice, lineCurrency);
        if (ratedUnit == null || ratedUnit <= 0) {
            return NONE;
        }
        Decimal tolerance = netUnitPrice.abs() * RELATIVE_TOLERANCE;
        if (tolerance < ABSOLUTE_TOLERANCE) {
            tolerance = ABSOLUTE_TOLERANCE;
        }
        if ((ratedUnit - netUnitPrice).abs() > tolerance) {
            return NONE;
        }

        // Align the display fields to the engine's already-converted net (no re-convert => no FX
        // compounding, and exact consistency with Net Unit / Net Total / Total).
        Decimal alignedTotal = (netTotalPrice != null && netTotalPrice > 0) ? netTotalPrice : netUnitPrice;
        return new Reconciliation(true, netUnitPrice, alignedTotal);
    }
}
