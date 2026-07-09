/**
 * @description Before-insert guard that corrects a QuoteLineItem's PricebookEntryId when the
 *              resolved PBE's currency differs from the parent Quote's currency.
 * @author Claude Code
 * @date 2026-07-09
 *
 * SC-3384 (multi-currency configured pricing). The managed RLM auto-add — e.g. the Year-1/Year-2
 * maintenance ProductConfigurationRules that add PIAMBK by Product2 Id (14OWC0000027izF2AQ /
 * 14OWC0000022Eyb2AE) — resolves a PricebookEntry WITHOUT a currency filter, so on a non-USD quote
 * it can pick the USD PBE. The platform then rejects the save with:
 *   "The price book entry currency code is different than the one assigned to the Quote.: Price Book Entry ID"
 *
 * Salesforce order-of-execution runs before-insert triggers (step 4) BEFORE the native
 * currency-consistency system validation (step 5), so re-pointing PricebookEntryId here — to the
 * SAME Product2 + Pricebook2 + ProductSellingModel in the Quote's currency — passes that validation.
 *
 * No-op for any line whose PBE currency already matches the quote (the happy path) => 0-delta.
 * If no matching-currency PBE exists (a genuine data gap), the line is left untouched and the
 * platform's native validation still fires — the guard never masks a missing-PBE data problem.
 */
public with sharing class QuoteLineItemCurrencyCorrectionHandler {

    /**
     * @description Re-points mis-currencied PricebookEntryId references on inserting quote lines
     *              to the equivalent PBE in the parent Quote's currency (in place, before insert).
     * @param newItems Trigger.new list of QuoteLineItem records being inserted.
     */
    public static void correctPricebookEntryCurrency(List<QuoteLineItem> newItems) {
        // Pass 1 — collect the PBEs actually referenced and the parent quotes.
        Set<Id> pbeIds = new Set<Id>();
        Set<Id> quoteIds = new Set<Id>();
        QuoteLineItem li;
        Integer idx;
        for (idx = 0; idx < newItems.size(); idx++) {
            li = newItems[idx];
            if (li.PricebookEntryId != null) {
                pbeIds.add(li.PricebookEntryId);
            }
            if (li.QuoteId != null) {
                quoteIds.add(li.QuoteId);
            }
        }
        if (pbeIds.isEmpty() || quoteIds.isEmpty()) {
            return;
        }

        // Resolve the referenced PBE identities (currency + the dimensions that key its currency siblings).
        Map<Id, PricebookEntry> pbeById = new Map<Id, PricebookEntry>([
            SELECT Id, CurrencyIsoCode, Product2Id, Pricebook2Id, ProductSellingModelId
            FROM PricebookEntry
            WHERE Id IN :pbeIds
        ]);
        Map<Id, Quote> quoteById = new Map<Id, Quote>([
            SELECT Id, CurrencyIsoCode
            FROM Quote
            WHERE Id IN :quoteIds
        ]);

        // Pass 2 — flag mismatches and gather the lookup dimensions for the correct-currency siblings.
        List<QuoteLineItem> mismatched = new List<QuoteLineItem>();
        Set<Id> needProductIds = new Set<Id>();
        Set<Id> needBookIds = new Set<Id>();
        Set<String> needCurrencies = new Set<String>();
        PricebookEntry pbe;
        Quote parentQuote;
        for (idx = 0; idx < newItems.size(); idx++) {
            li = newItems[idx];
            if (li.PricebookEntryId == null || li.QuoteId == null) {
                continue;
            }
            pbe = pbeById.get(li.PricebookEntryId);
            parentQuote = quoteById.get(li.QuoteId);
            if (pbe == null || parentQuote == null) {
                continue;
            }
            if (pbe.CurrencyIsoCode == parentQuote.CurrencyIsoCode) {
                continue; // already correct — no-op
            }
            mismatched.add(li);
            needProductIds.add(pbe.Product2Id);
            needBookIds.add(pbe.Pricebook2Id);
            needCurrencies.add(parentQuote.CurrencyIsoCode);
        }
        if (mismatched.isEmpty()) {
            return;
        }

        // Build the correct-currency lookup: product|book|psm|currency -> PBE Id.
        Map<String, Id> correctPbeByKey = new Map<String, Id>();
        for (PricebookEntry candidate : [
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, CurrencyIsoCode
            FROM PricebookEntry
            WHERE IsActive = true
            AND Product2Id IN :needProductIds
            AND Pricebook2Id IN :needBookIds
            AND CurrencyIsoCode IN :needCurrencies
        ]) {
            correctPbeByKey.put(
                buildKey(candidate.Product2Id, candidate.Pricebook2Id, candidate.ProductSellingModelId, candidate.CurrencyIsoCode),
                candidate.Id
            );
        }

        // Pass 3 — re-point each mismatched line, in place, to its Quote-currency sibling.
        Id correctPbeId;
        for (idx = 0; idx < mismatched.size(); idx++) {
            li = mismatched[idx];
            pbe = pbeById.get(li.PricebookEntryId);
            parentQuote = quoteById.get(li.QuoteId);
            correctPbeId = correctPbeByKey.get(
                buildKey(pbe.Product2Id, pbe.Pricebook2Id, pbe.ProductSellingModelId, parentQuote.CurrencyIsoCode)
            );
            if (correctPbeId != null) {
                li.PricebookEntryId = correctPbeId;
            } else {
                // Genuine data gap: no PBE for this product/book/PSM in the quote's currency.
                // Leave the line untouched so the platform's native validation surfaces the gap.
                System.debug(LoggingLevel.WARN, 'SC-3384 QLI currency-correction: no '
                    + parentQuote.CurrencyIsoCode + ' PricebookEntry for Product2 ' + pbe.Product2Id
                    + ' / Pricebook2 ' + pbe.Pricebook2Id + ' / PSM ' + pbe.ProductSellingModelId);
            }
        }
    }

    private static String buildKey(Id productId, Id bookId, Id psmId, String currencyIso) {
        return String.valueOf(productId) + '|' + String.valueOf(bookId) + '|'
            + String.valueOf(psmId) + '|' + currencyIso;
    }
}
