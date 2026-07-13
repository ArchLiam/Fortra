/**
 * @description Pure-function parity coverage for the stamped-maintenance COLA net. Proves each duplicate
 *              calculator returns the identical net as the canonical
 *              COLAUpliftCalculator.computeStampedMaintenanceColaNet on every non-guard input, and that the
 *              guard-bearing RenewalMaintenanceColaCalculator preserves its contributor-base / null
 *              behavior. This locks equivalence before the duplicates are converged onto the canonical
 *              calculator. In-memory QuoteLineItems only — no SOQL, no DML, no reprice.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class COLAUpliftCalculatorParityTest {

    private static QuoteLineItem line(Decimal base, Decimal priorPartner, Decimal priorDisc,
            Decimal discount, Decimal cola) {
        return new QuoteLineItem(
            Base_Price__c = base,
            Prior_Partner_Discount__c = priorPartner,
            Prior_Discretionary_Discount__c = priorDisc,
            Discount = discount,
            COLA_Uplift_Percent__c = cola);
    }

    /**
     * @description The canonical calculator returns the exact expected net across representative shapes.
     */
    @isTest
    static void canonicalOracle() {
        Assert.areEqual(67.38, COLAUpliftCalculator.computeStampedMaintenanceColaNet(line(71, 8.52, null, 0, 7.85)),
            'partner-only, no discretionary: (71-8.52)*1.0785');
        Assert.areEqual(60.64, COLAUpliftCalculator.computeStampedMaintenanceColaNet(line(71, 8.52, 6.25, 10, 7.85)),
            'explicit prior discretionary overrides Discount%');
        Assert.areEqual(94.50, COLAUpliftCalculator.computeStampedMaintenanceColaNet(line(100, 0, null, 10, 5)),
            'discretionary derived from Discount%: (100-10)*1.05');
        Assert.areEqual(100.00, COLAUpliftCalculator.computeStampedMaintenanceColaNet(line(100, 0, null, 0, 0)),
            'zero COLA, no discounts: base unchanged');
        Assert.isNull(COLAUpliftCalculator.computeStampedMaintenanceColaNet(line(10, 12, null, 0, 5)),
            'non-positive pre-COLA net returns null');
    }

    /**
     * @description Both duplicate calculators return the identical net as canonical on every non-guard input.
     */
    @isTest
    static void duplicatesEqualCanonical() {
        List<QuoteLineItem> cases = new List<QuoteLineItem>{
            line(71, 8.52, null, 0, 7.85),
            line(71, 8.52, 6.25, 10, 7.85),
            line(100, 0, null, 10, 5),
            line(100, 0, null, 0, 0),
            line(5000, 250, null, 5, 3),
            line(934.60, null, null, 0, 7.85),
            line(287, 0, null, 0, 0)
        };
        for (QuoteLineItem qli : cases) {
            Decimal expected = COLAUpliftCalculator.computeStampedMaintenanceColaNet(qli);
            Assert.areEqual(expected, RenewalMaintenancePricingService.computeColaNet(qli),
                'RenewalMaintenancePricingService.computeColaNet must equal canonical (base ' + qli.Base_Price__c + ')');
            Assert.areEqual(expected, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(qli),
                'RenewalMaintenanceColaCalculator must equal canonical on non-guard input (base ' + qli.Base_Price__c + ')');
        }
    }

    /**
     * @description The null / zero-base guards return null (not NPE), and the contributor-base guard
     *              suppresses to the stamped prior net rather than a fresh uplift.
     */
    @isTest
    static void guardsBehavior() {
        Assert.isNull(RenewalMaintenancePricingService.computeColaNet(line(null, 0, null, 0, 5)),
            'null base returns null, not NPE');
        Assert.isNull(RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(line(0, 0, null, 0, 5)),
            'zero base returns null');

        // Base >= 10000 with pre-COLA net < 50% of base = contributor perpetual base on a maintenance line.
        QuoteLineItem contributor = line(20000, 0, 12000, 0, 5);       // preColaNet = 8000 < 10000
        Assert.isNull(RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(contributor),
            'contributor-base line with no stamped prior net is suppressed to null');

        QuoteLineItem contributorStamped = line(20000, 0, 12000, 0, 5);
        contributorStamped.COLACalculatedPrice__c = 3151.80;
        Assert.areEqual(3151.80, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(contributorStamped),
            'contributor-base line returns the stamped prior COLA net');
    }
}
