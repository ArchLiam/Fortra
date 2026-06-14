/**
 * @description Ensures asset-initiated renewal quotes use Quote_Type__c = Renewal so
 *              Product Configuration Rules (e.g. Year 2 Maintenance AutoAdd) evaluate correctly.
 *              QuoteTypeText__c is a formula of Quote_Type__c and is used by config rule criteria.
 */
public with sharing class QuoteRenewalTypeHandler {

    public static final String QUOTE_TYPE_RENEWAL = 'Renewal';
    public static final String ORIGINAL_ACTION_RENEW = 'Renew';

    public static void applyRenewalQuoteType(List<Quote> quotes) {
        if (quotes == null || quotes.isEmpty()) {
            return;
        }

        for (Quote quote : quotes) {
            normalizeRenewalQuoteType(quote);
        }
    }

    public static void normalizeRenewalQuoteType(Quote quote) {
        if (quote == null || quote.OriginalActionType != ORIGINAL_ACTION_RENEW) {
            return;
        }

        if (quote.Quote_Type__c != QUOTE_TYPE_RENEWAL) {
            quote.Quote_Type__c = QUOTE_TYPE_RENEWAL;
        }
    }
}