/**
 * @description Before-insert guard that corrects a QuoteLineItem's PricebookEntryId when the
 *              resolved PricebookEntry's currency differs from the parent Quote's currency,
 *              re-pointing it to the equivalent PBE (same Product2, Pricebook2, and
 *              ProductSellingModel) in the Quote's currency so the native currency-consistency
 *              validation passes; lines that already match are a no-op and lines with no
 *              matching-currency PBE are left untouched for the platform's native validation.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
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

    /**
     * @description Builds the pipe-delimited composite key that identifies a PricebookEntry's
     *              currency siblings by product, book, selling model, and currency.
     * @param productId Product2 Id component of the key.
     * @param bookId Pricebook2 Id component of the key.
     * @param psmId ProductSellingModel Id component of the key.
     * @param currencyIso ISO currency code component of the key.
     * @return The pipe-delimited composite key string.
     */
    private static String buildKey(Id productId, Id bookId, Id psmId, String currencyIso) {
        return String.valueOf(productId) + '|' + String.valueOf(bookId) + '|'
            + String.valueOf(psmId) + '|' + currencyIso;
    }
}