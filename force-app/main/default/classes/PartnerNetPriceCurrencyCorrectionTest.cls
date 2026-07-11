/**
 * @description Integration tests for the ABA currency-correction pass folded into
 *              PartnerNetPricePosthook (applyCurrencyCorrection + mergeCurrencyCorrectionIntoUpdate).
 *              Drives the @TestVisible seams with injected context tag maps (no DML): asserts the
 *              in-memory tag mutation, that a pure-ABA line gets a full localized write, that a
 *              partner-owned update keeps its (lower) net while gaining a localized Sales Price, and
 *              that USD / non-ABA lines are left untouched.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class PartnerNetPriceCurrencyCorrectionTest {

    // Real QuoteLineItem-prefixed Ids reused as fake context record ids (never DML'd here; the
    // currency + product tags are provided so no SOQL fallback fires).
    private static final String EUR_LINE = '0QLWC000003kmG14AI';
    private static final String USD_LINE = '0QLWC000003cAr34AE';
    private static final String LIST_LINE = '0QLWC000003cAEM4A2';
    private static final String AAMP_PRODUCT = '01tWC00000DD11YYAT';

    /**
     * @description Builds a PartnerNetPricePosthook with the known-USD-value gate pre-seeded (AAMP 1575)
     *              so the SOQL gate is bypassed in tests.
     * @return A posthook instance with testKnownUsdValues populated for the AAMP product.
     */
    // A posthook with the known-USD-value gate pre-seeded (AAMP 1575) so the SOQL gate is bypassed.
    private static PartnerNetPricePosthook hook() {
        PartnerNetPricePosthook h = new PartnerNetPricePosthook();
        h.testKnownUsdValues = new Map<Id, Set<String>>{
            Id.valueOf(AAMP_PRODUCT) => new Set<String>{ '1575.00' }
        };
        return h;
    }

    /**
     * @description Builds a fake context tag map representing one SalesTransactionItem line, wiring the
     *              currency, product, net and quantity tags (and optional ABA raw-net provenance).
     * @param recordId The line record id used as both key and update-path leaf.
     * @param rawNet The ABA raw net override to stamp as ABA_Raw_Net__c provenance, or null to omit.
     * @param iso The line currency ISO code.
     * @param net The NetUnitPrice tag value.
     * @param qty The Quantity tag value.
     * @return A mutable context tag map for the line.
     */
    private static Map<String, Object> line(String recordId, Object rawNet, String iso, Object net, Object qty) {
        Map<String, Object> m = new Map<String, Object>{
            '_recordId' => recordId,
            '_updatePath' => new List<Object>{ 'SalesTransactionItem', recordId },
            'STICurrencyIsoCode' => iso,
            'Product' => AAMP_PRODUCT,
            'NetUnitPrice' => net,
            'Quantity' => qty
        };
        if (rawNet != null) {
            m.put('ABA_Raw_Net__c', rawNet);
        }
        return m;
    }

    /**
     * @description Reads a named attribute value out of an emitted item-update's attributes list.
     * @param itemUpdate The emitted update map containing an 'attributes' list.
     * @param name The attributeName to look up.
     * @return The matching attributeValue as a Decimal, or null when not present.
     */
    private static Decimal attrValue(Map<String, Object> itemUpdate, String name) {
        List<Map<String, Object>> attrs = (List<Map<String, Object>>) itemUpdate.get('attributes');
        for (Map<String, Object> a : attrs) {
            if (name.equals(String.valueOf(a.get('attributeName')))) {
                return (Decimal) a.get('attributeValue');
            }
        }
        return null;
    }

    /**
     * @description Asserts that an actual Decimal is non-null and within 0.0005 of the expected value.
     * @param expected The expected value.
     * @param actual The actual value to compare.
     * @param msg The assertion message prefix.
     */
    private static void assertClose(Decimal expected, Decimal actual, String msg) {
        System.assertNotEquals(null, actual, msg + ' (null)');
        System.assert((expected - actual).abs() < 0.0005, msg + ' expected=' + expected + ' actual=' + actual);
    }

    /**
     * @description Verifies an EUR ABA line is corrected to its localized unit and that the in-memory
     *              NetUnitPrice tag is mutated to the localized base so downstream builders see it.
     */
    @isTest
    static void abaLineIsLocalizedAndTagsMutated() {
        PartnerNetPricePosthook hook = hook();
        Map<String, Object> eur = line(EUR_LINE, 1575, 'EUR', 1575, 1);
        List<Map<String, Object>> lines = new List<Map<String, Object>>{ eur };

        Map<Id, AbaCurrencyCorrectionService.Correction> corrections;
        Test.startTest();
        corrections = hook.applyCurrencyCorrection(lines);
        Test.stopTest();

        System.assertEquals(1, corrections.size(), 'EUR ABA line must be corrected');
        AbaCurrencyCorrectionService.Correction c = corrections.get(Id.valueOf(EUR_LINE));
        assertClose(1471.995, c.localizedUnit, 'localized unit');
        // NetUnitPrice tag mutated so the partner "lower-of" / COLA builders see the localized base.
        // (Other price fields are localized via the emitted update, not the in-memory tag.)
        assertClose(1471.995, (Decimal) eur.get('NetUnitPrice'), 'NetUnitPrice tag mutated');
    }

    /**
     * @description Verifies a USD ABA line and a non-ABA (no snapshot) line are not corrected and their
     *              NetUnitPrice tags are left untouched.
     */
    @isTest
    static void usdAndNonAbaLinesAreUntouched() {
        PartnerNetPricePosthook hook = hook();
        Map<String, Object> usd = line(USD_LINE, 1575, 'USD', 1575, 1);       // ABA but USD
        Map<String, Object> listLine = line(LIST_LINE, null, 'EUR', 467.30, 1); // non-ABA (no snapshot)
        List<Map<String, Object>> lines = new List<Map<String, Object>>{ usd, listLine };

        Map<Id, AbaCurrencyCorrectionService.Correction> corrections = hook.applyCurrencyCorrection(lines);

        System.assertEquals(0, corrections.size(), 'USD and non-ABA lines must not be corrected');
        System.assertEquals(1575, (Decimal) usd.get('NetUnitPrice'), 'USD net untouched');
        System.assertEquals(467.30, (Decimal) listLine.get('NetUnitPrice'), 'non-ABA net untouched');
    }

    /**
     * @description Verifies that when no partner/COLA update exists, the correction owns the write and
     *              emits fully localized NetUnitPrice, UnitPrice, Subtotal and TotalPrice while persisting
     *              the raw net as provenance.
     */
    @isTest
    static void pureAbaLineEmitsFullLocalizedWrite() {
        PartnerNetPricePosthook hook = hook();
        Map<String, Object> eur = line(EUR_LINE, 1575, 'EUR', 1575, 1);
        Map<Id, AbaCurrencyCorrectionService.Correction> corrections = hook.applyCurrencyCorrection(
            new List<Map<String, Object>>{ eur }
        );

        // No partner/COLA update for this line -> the correction owns the write.
        Map<String, Object> itemUpdate = hook.mergeCurrencyCorrectionIntoUpdate(null, eur, corrections);

        System.assertNotEquals(null, itemUpdate, 'pure ABA line must produce an update');
        assertClose(1471.995, attrValue(itemUpdate, 'NetUnitPrice'), 'NetUnitPrice localized');
        assertClose(1471.995, attrValue(itemUpdate, 'UnitPrice'), 'Sales Price (UnitPrice) localized');
        assertClose(1471.995, attrValue(itemUpdate, 'Subtotal'), 'Subtotal localized');
        assertClose(1471.995, attrValue(itemUpdate, 'TotalPrice'), 'TotalPrice localized');
        assertClose(1575, attrValue(itemUpdate, 'ABA_Raw_Net__c'), 'raw override persisted as provenance');
    }

    /**
     * @description Verifies that merging a correction into a partner-owned update preserves the partner's
     *              lower commercial net and total while adding a localized UnitPrice (Sales Price).
     */
    @isTest
    static void partnerOwnedUpdateKeepsNetAndGainsLocalizedSalesPrice() {
        PartnerNetPricePosthook hook = hook();
        Map<String, Object> eur = line(EUR_LINE, 1575, 'EUR', 1575, 1);
        Map<Id, AbaCurrencyCorrectionService.Correction> corrections = hook.applyCurrencyCorrection(
            new List<Map<String, Object>>{ eur }
        );

        // Simulate a partner update: it already set a LOWER commercial net (computed off the localized
        // base) and did not set UnitPrice. The merge must not clobber the partner net; it adds UnitPrice.
        Map<String, Object> partnerUpdate = new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => new List<Object>{ 'x' } },
            'attributes' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => 1200 },
                new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => 1200 }
            }
        };

        Map<String, Object> merged = hook.mergeCurrencyCorrectionIntoUpdate(partnerUpdate, eur, corrections);

        System.assertEquals(1200, attrValue(merged, 'NetUnitPrice'), 'partner net (lower-of) preserved');
        System.assertEquals(1200, attrValue(merged, 'TotalPrice'), 'partner total preserved');
        assertClose(1471.995, attrValue(merged, 'UnitPrice'), 'localized Sales Price added');
    }

    /**
     * @description Verifies the post-persist DML stamp localizes an ABA EUR line's Sales Price from the
     *              ABA_Raw_Net__c snapshot while leaving a USD ABA line's Sales Price unchanged.
     */
    @isTest
    static void salesPriceStampLocalizesAbaNonUsdLine() {
        // The context persist does not own UnitPrice, so the raw USD Sales Price survives there; the
        // reliable post-persist DML stamp localizes it from the ABA_Raw_Net__c snapshot.
        // CurrencyIsoCode is not writeable on QuoteLineItem (inherited from the parent Quote), so build
        // the stub via JSON.deserialize to populate it without DML.
        QuoteLineItem eur = (QuoteLineItem) JSON.deserialize(
            '{"attributes":{"type":"QuoteLineItem"},"Id":"' + EUR_LINE + '","CurrencyIsoCode":"EUR",' +
            '"ABA_Raw_Net__c":1575,"UnitPrice":1575,"Fortra_Product_Type__c":"Software"}',
            QuoteLineItem.class);
        QuoteLineItem upd = PartnerNetPricePosthook.buildAttributeListPriceStampUpdate(
            eur, new Map<String, Decimal>(), new Map<Id, String>(), new Set<Id>());
        System.assertNotEquals(null, upd, 'ABA EUR line should get a localized Sales Price stamp');
        assertClose(1472.00, upd.UnitPrice, '1575 * 0.9346 = 1471.995 -> 1472.00 (2dp)');

        // USD ABA line: Sales Price untouched (0-delta).
        QuoteLineItem usd = (QuoteLineItem) JSON.deserialize(
            '{"attributes":{"type":"QuoteLineItem"},"Id":"' + USD_LINE + '","CurrencyIsoCode":"USD",' +
            '"ABA_Raw_Net__c":1575,"UnitPrice":1575,"Fortra_Product_Type__c":"Software"}',
            QuoteLineItem.class);
        QuoteLineItem uUsd = PartnerNetPricePosthook.buildAttributeListPriceStampUpdate(
            usd, new Map<String, Decimal>(), new Map<Id, String>(), new Set<Id>());
        System.assertEquals(null, uUsd, 'USD line: no Sales Price change');
    }

    /**
     * @description Verifies a filtered-but-unmatched line carrying a pass-through list value (not one of
     *              the product's overrides) is gated out rather than double-localized.
     */
    @isTest
    static void unmatchedPassThroughValueIsGatedOut() {
        // A filtered-but-unmatched line carries a pass-through list value (2943.99) that is NOT one of
        // the product's overrides ({1575.00}). The gate must skip it -> no double-localization.
        PartnerNetPricePosthook h = hook();
        Map<String, Object> ln = line(EUR_LINE, 2943.99, 'EUR', 2943.99, 1);
        Map<Id, AbaCurrencyCorrectionService.Correction> corr =
            h.applyCurrencyCorrection(new List<Map<String, Object>>{ ln });
        System.assertEquals(0, corr.size(), 'pass-through list value must be gated out, not localized');
    }

    /**
     * @description Verifies isKnownUsdValue matches values against the known-USD set at two-decimal
     *              precision and returns false for non-USD values and a null set.
     */
    @isTest
    static void isKnownUsdValueMatchesTwoDecimal() {
        PartnerNetPricePosthook h = new PartnerNetPricePosthook();
        Set<String> known = new Set<String>{ '1575.00', '824.00', '199.00' };
        System.assertEquals(true, h.isKnownUsdValue(known, 1575), '1575 -> 1575.00 matches (ABA override)');
        System.assertEquals(true, h.isKnownUsdValue(known, 199.00), '199.00 matches (USD list, e.g. CCM)');
        System.assertEquals(false, h.isKnownUsdValue(known, 2943.99), 'non-USD value does not match');
        System.assertEquals(false, h.isKnownUsdValue(null, 1575), 'null set -> false');
    }

    /**
     * @description Verifies a non-ABA list/derived line whose net equals the injected USD PBE list value
     *              is recognized by the generalized gate and localized.
     */
    @isTest
    static void localizesListPricedLineWhenNetMatchesUsdList() {
        // CCM-style: a non-ABA list/derived line whose net is the USD PBE list (199). The generalized
        // gate (USD list injected here) recognizes it and localizes -> 199 * 0.9346 = 185.99.
        PartnerNetPricePosthook h = new PartnerNetPricePosthook();
        h.testKnownUsdValues = new Map<Id, Set<String>>{ Id.valueOf(AAMP_PRODUCT) => new Set<String>{ '199.00' } };
        Map<String, Object> eur = line(EUR_LINE, null, 'EUR', 199, 1);
        Map<Id, AbaCurrencyCorrectionService.Correction> corr =
            h.applyCurrencyCorrection(new List<Map<String, Object>>{ eur });
        System.assertEquals(1, corr.size(), 'USD-list net must localize');
        assertClose(185.9854, corr.get(Id.valueOf(EUR_LINE)).localizedUnit, '199 * 0.9346');
    }

    /**
     * @description Verifies that without ABA_Raw_Net__c provenance, the gate confirms the override carried
     *              on NetUnitPrice and the line localizes (quote-path bootstrap).
     */
    @isTest
    static void bootstrapsFromNetUnitPriceWhenNoProvenance() {
        // No ABA_Raw_Net__c stamped: on the quote path NetUnitPrice carries the raw override (1575).
        // The gate confirms it against the product's overrides and the line localizes.
        PartnerNetPricePosthook h = hook();
        Map<String, Object> eur = line(EUR_LINE, null, 'EUR', 1575, 1); // no ABA_Raw_Net__c tag
        Map<Id, AbaCurrencyCorrectionService.Correction> corr =
            h.applyCurrencyCorrection(new List<Map<String, Object>>{ eur });
        System.assertEquals(1, corr.size(), 'bootstrap from NetUnitPrice override must localize');
        assertClose(1471.995, corr.get(Id.valueOf(EUR_LINE)).localizedUnit, 'localized from bootstrapped 1575');
    }

    /**
     * @description Verifies that without provenance and with a NetUnitPrice that is a list value (not an
     *              override), the bootstrap path is gated out to avoid double-localization.
     */
    @isTest
    static void bootstrapGatedOutForNonOverride() {
        // No provenance and NetUnitPrice is a list value (not an override) -> gated out (no double-localize).
        PartnerNetPricePosthook h = hook();
        Map<String, Object> eur = line(EUR_LINE, null, 'EUR', 2943.99, 1);
        Map<Id, AbaCurrencyCorrectionService.Correction> corr =
            h.applyCurrencyCorrection(new List<Map<String, Object>>{ eur });
        System.assertEquals(0, corr.size(), 'bootstrapped non-override must be gated out');
    }
}