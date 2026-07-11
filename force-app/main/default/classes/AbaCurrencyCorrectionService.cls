/**
 * @description Currency correction for lines priced by the currency-blind Attribute-Based
 *              Adjustment (ABA) decision table (0lDa50000007BEuEAM). That native table has no
 *              CurrencyIsoCode input and holds only USD `Override` rows, so a non-USD line matches a
 *              USD Override and stamps the raw USD dollar figure under a foreign symbol. The base LIST
 *              price localizes correctly (per-currency PricebookEntry), but the configured
 *              Net/Subtotal/Total/UnitPrice carry raw USD.
 *
 *              The pricing procedure snapshots the raw per-unit USD net the ABA step produced into
 *              QuoteLineItem/OrderItem.ABA_Raw_Net__c (stamped ONLY on an actual ABA match). This pure
 *              service turns that snapshot into the localized value using the static, Finance-governed
 *              conversion rate (Currency_Conversion_Formula__mdt via Fortra_CurrencyConversionService)
 *              — NOT runtime CurrencyType.ConversionRate, and NOT a quote-time PBE division.
 *
 *              Design properties (each closes an adversarially-verified failure mode):
 *              - PROVENANCE, not value-identity: a non-null raw snapshot marks an ABA line, so a
 *                correctly-localized value that happens to equal a USD override (the collision cohort,
 *                e.g. VLM CAD 360*1.3889 == another override 500) is never re-scaled.
 *              - PER-UNIT: scales the per-unit raw net and derives totals as unit * quantity, so qty>1
 *                lines on non-self-covering products are handled (never reads Subtotal, a qty-scaled total).
 *              - IDEMPOTENT: when the current net already equals raw*rate (order-path re-run, re-reprice,
 *                convert), it emits no write — no FX compounding.
 *              - $0-immune: the CMDT rate needs no PricebookEntry denominator, so the $0-USD-PBE cohort
 *                localizes without divide-by-zero.
 *
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class AbaCurrencyCorrectionService {

    /**
     * @description Tolerance for the "already localized" idempotency compare. Kept small enough to
     *              distinguish a raw USD net from its localized value, large enough to absorb the
     *              natural-scale product (e.g. 1575 * 0.9346 = 1471.9950) vs a persisted round-trip.
     */
    @TestVisible
    private static final Decimal IDEMPOTENCY_EPSILON = 0.005;

    private static final String USD = 'USD';

    /**
     * @description Outcome of evaluating one line. `writeNeeded` is true only when the line is an
     *              ABA-priced, non-USD line with a governed rate whose net is NOT already localized.
     */
    public class Correction {
        public final Boolean writeNeeded;
        public final Decimal localizedUnit;
        public final Decimal localizedTotal;
        public final Decimal rawNet; // the raw USD override — persisted to ABA_Raw_Net__c for order-side provenance

        @TestVisible
        private Correction(Boolean writeNeeded, Decimal localizedUnit, Decimal localizedTotal, Decimal rawNet) {
            this.writeNeeded = writeNeeded;
            this.localizedUnit = localizedUnit;
            this.localizedTotal = localizedTotal;
            this.rawNet = rawNet;
        }
    }

    private static final Correction NONE = new Correction(false, null, null, null);

    /**
     * @description Decide whether and how to localize one line.
     * @param rawNet       ABA_Raw_Net__c — raw per-unit USD net stamped by the ABA step. Non-null/>0
     *                     is the provenance signal that the line was priced by the ABA table.
     * @param lineCurrency the line's CurrencyIsoCode.
     * @param currentNet   the line's current NetUnitPrice (post-procedure).
     * @param quantity     the line quantity (for total derivation).
     * @return Correction. writeNeeded=false (a no-op) when the line is not ABA-priced, is USD, has no
     *         governed rate, or is already localized.
     */
    public static Correction evaluate(Decimal rawNet, String lineCurrency, Decimal currentNet, Decimal quantity) {
        // Not ABA-priced: the procedure stamps ABA_Raw_Net__c only on an actual ABA Override match.
        if (rawNet == null || rawNet <= 0) {
            return NONE;
        }
        // USD is authoritative and unchanged: 0-delta by construction.
        if (String.isBlank(lineCurrency) || USD.equalsIgnoreCase(lineCurrency)) {
            return NONE;
        }
        // Static, governed rate (rawNet * Currency_Conversion_Formula__mdt.Conversion_Rate__c).
        // Reproduces the confirmed target exactly (e.g. 1575 EUR -> 1471.995) and needs no PBE denominator.
        Decimal localizedUnit = Fortra_CurrencyConversionService.convertPrice(rawNet, lineCurrency);
        // No governed rate for this currency: leave the line raw rather than emit a wrong/zero value.
        if (localizedUnit == null || localizedUnit <= 0) {
            return NONE;
        }

        Decimal qty = (quantity == null || quantity <= 0) ? 1 : quantity;
        Decimal localizedTotal = localizedUnit * qty;

        // Idempotency: already localized (order path has no ESD re-derive; convert / re-reprice). No write.
        if (currentNet != null && (currentNet - localizedUnit).abs() < IDEMPOTENCY_EPSILON) {
            return new Correction(false, localizedUnit, localizedTotal, rawNet);
        }
        return new Correction(true, localizedUnit, localizedTotal, rawNet);
    }
}