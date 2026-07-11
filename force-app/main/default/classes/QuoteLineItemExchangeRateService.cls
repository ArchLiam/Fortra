/**
 * @description Captures and propagates the USD exchange rate for QuoteLineItems. Stamps
 *              Exchange_Rate_To_USD__c on each line from a dated-conversion lookup, and copies the
 *              rate to the parent Opportunity when the line's Quote is the Opportunity's syncing
 *              Quote. without sharing: the Opportunity copy is a best-effort system propagation
 *              that must not depend on the running user's record access, matching the prior
 *              in-trigger system context.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public without sharing class QuoteLineItemExchangeRateService {

    /**
     * @description Sets Exchange_Rate_To_USD__c on each line from a single dated-conversion-rate
     *              lookup keyed by CurrencyIsoCode. Mutates the lines in place (before-save context).
     * @param lines The QuoteLineItem records to stamp.
     */
    public static void stampRatesOnLines(List<QuoteLineItem> lines) {
        if (lines == null || lines.isEmpty()) {
            return;
        }

        List<DatedConversionRateLookup.Request> requests = new List<DatedConversionRateLookup.Request>();
        List<QuoteLineItem> itemsToStamp = new List<QuoteLineItem>();

        for (QuoteLineItem qli : lines) {
            if (String.isNotBlank(qli.CurrencyIsoCode)) {
                DatedConversionRateLookup.Request req = new DatedConversionRateLookup.Request();
                req.currencyIsoCode = qli.CurrencyIsoCode;
                requests.add(req);
                itemsToStamp.add(qli);
            }
        }

        if (requests.isEmpty()) {
            return;
        }

        List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(requests);
        for (Integer i = 0; i < itemsToStamp.size(); i++) {
            itemsToStamp[i].Exchange_Rate_To_USD__c = results[i].exchangeRate;
        }
    }

    /**
     * @description Propagates each line's Exchange_Rate_To_USD__c to its parent Opportunity, but
     *              only where the line's Quote is the Opportunity's syncing Quote. Uses a partial
     *              update so Opportunity validation-rule failures do not block the QuoteLineItem save.
     * @param lines The QuoteLineItem records whose rate should be propagated.
     */
    public static void propagateRatesToOpportunities(List<QuoteLineItem> lines) {
        if (lines == null || lines.isEmpty()) {
            return;
        }

        Map<Id, Decimal> quoteIdToRate = new Map<Id, Decimal>();
        for (QuoteLineItem qli : lines) {
            if (qli.Exchange_Rate_To_USD__c != null && qli.QuoteId != null) {
                quoteIdToRate.put(qli.QuoteId, qli.Exchange_Rate_To_USD__c);
            }
        }

        if (quoteIdToRate.isEmpty()) {
            return;
        }

        Map<Id, Quote> quotes = new Map<Id, Quote>([
            SELECT Id, OpportunityId, Opportunity.SyncedQuoteId
            FROM Quote
            WHERE Id IN :quoteIdToRate.keySet()
            AND OpportunityId != null
        ]);

        Map<Id, Opportunity> oppsToUpdate = new Map<Id, Opportunity>();
        for (Quote q : quotes.values()) {
            if (q.Id == q.Opportunity.SyncedQuoteId) {
                oppsToUpdate.put(q.OpportunityId, new Opportunity(
                    Id = q.OpportunityId,
                    Exchange_Rate_To_USD__c = quoteIdToRate.get(q.Id)
                ));
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            Database.update(oppsToUpdate.values(), false);
        }
    }
}
