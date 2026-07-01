@IsTest
private class QuoteRenewalTypeHandlerTest {
    private static Quote buildQuote(String originalActionType, String quoteType) {
        return (Quote) JSON.deserialize(
            '{"OriginalActionType":"' + originalActionType + '","Quote_Type__c":"' + quoteType + '"}',
            Quote.class
        );
    }

    @IsTest
    static void applyRenewalQuoteType_noOpWhenNullOrEmpty() {
        Test.startTest();
        QuoteRenewalTypeHandler.applyRenewalQuoteType(null);
        QuoteRenewalTypeHandler.applyRenewalQuoteType(new List<Quote>());
        Test.stopTest();

        System.assert(true, 'Null and empty inputs should return without error');
    }

    @IsTest
    static void normalizeRenewalQuoteType_setsRenewalWhenOriginalActionIsRenew() {
        Quote quote = buildQuote(QuoteRenewalTypeHandler.ORIGINAL_ACTION_RENEW, 'Amendment');

        QuoteRenewalTypeHandler.normalizeRenewalQuoteType(quote);

        System.assertEquals(QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL, quote.Quote_Type__c);
    }

    @IsTest
    static void normalizeRenewalQuoteType_leavesNonRenewQuotesUnchanged() {
        Quote quote = buildQuote('New', 'New');

        QuoteRenewalTypeHandler.normalizeRenewalQuoteType(quote);

        System.assertEquals('New', quote.Quote_Type__c);
    }

    @IsTest
    static void normalizeRenewalQuoteType_preservesExistingRenewalType() {
        Quote quote = buildQuote(
            QuoteRenewalTypeHandler.ORIGINAL_ACTION_RENEW,
            QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );

        QuoteRenewalTypeHandler.normalizeRenewalQuoteType(quote);

        System.assertEquals(QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL, quote.Quote_Type__c);
    }

    @IsTest
    static void applyRenewalQuoteType_setsRenewalOnBatch() {
        List<Quote> quotes = new List<Quote>{
            buildQuote(QuoteRenewalTypeHandler.ORIGINAL_ACTION_RENEW, 'Amendment'),
            buildQuote('New', 'New')
        };

        Test.startTest();
        QuoteRenewalTypeHandler.applyRenewalQuoteType(quotes);
        Test.stopTest();

        System.assertEquals(QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL, quotes[0].Quote_Type__c);
        System.assertEquals('New', quotes[1].Quote_Type__c);
    }
}