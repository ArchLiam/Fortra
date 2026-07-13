/**
 * Invocable action that looks up exchange rates from a given currency to USD.
 *
 * Queries DatedConversionRate (Advanced Currency Management) for the given
 * ISO code and date, with CurrencyType fallback when no dated rate exists.
 * Returns the raw Salesforce ConversionRate value (the dated exchange rate
 * for the currency).
 *
 * Called from the QuoteLineItemExchangeRateTrigger to populate
 * Exchange_Rate_To_USD__c on QuoteLineItem at pricing time.
 */
public with sharing class DatedConversionRateLookup {

    @InvocableMethod(label='Get Dated Exchange Rate to USD'
                     description='Looks up the exchange rate from a given currency to USD using DatedConversionRate (ACM) with CurrencyType fallback'
                     category='Pricing')
    public static List<Result> getExchangeRates(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Step 1: Default null lookupDates to today and collect unique non-USD ISO codes
        // Note: Uses the maximum lookupDate across all requests for a single SOQL query.
        // This is safe because the flow invokes this once per transaction with today's date.
        Set<String> isoCodes = new Set<String>();
        Date maxDate = System.today();

        for (Request req : requests) {
            if (req.lookupDate == null) {
                req.lookupDate = System.today();
            }
            if (req.lookupDate > maxDate) {
                maxDate = req.lookupDate;
            }
            if (String.isNotBlank(req.currencyIsoCode) && req.currencyIsoCode != 'USD') {
                isoCodes.add(req.currencyIsoCode);
            }
        }

        // Step 2: Query DatedConversionRate for all non-USD codes
        Map<String, Decimal> rateMap = new Map<String, Decimal>();

        if (!isoCodes.isEmpty()) {
            for (DatedConversionRate dcr : [
                SELECT IsoCode, ConversionRate
                FROM DatedConversionRate
                WHERE IsoCode IN :isoCodes
                AND StartDate <= :maxDate
                AND NextStartDate > :maxDate
            ]) {
                rateMap.put(dcr.IsoCode, dcr.ConversionRate);
            }

            // Step 3: Fallback to CurrencyType for any codes not found
            Set<String> missingCodes = new Set<String>();
            for (String code : isoCodes) {
                if (!rateMap.containsKey(code)) {
                    missingCodes.add(code);
                }
            }

            if (!missingCodes.isEmpty()) {
                for (CurrencyType ct : [
                    SELECT IsoCode, ConversionRate
                    FROM CurrencyType
                    WHERE IsoCode IN :missingCodes
                    AND IsActive = true
                ]) {
                    rateMap.put(ct.IsoCode, ct.ConversionRate);
                }
            }
        }

        // Step 4: Build results — return the raw SF ConversionRate
        for (Request req : requests) {
            Result res = new Result();

            if (String.isBlank(req.currencyIsoCode) || req.currencyIsoCode == 'USD') {
                res.exchangeRate = 1.0;
            } else if (rateMap.containsKey(req.currencyIsoCode)) {
                res.exchangeRate = rateMap.get(req.currencyIsoCode);
            } else {
                res.exchangeRate = null;
            }

            results.add(res);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(label='Currency ISO Code' required=true
                          description='3-letter ISO currency code (e.g., EUR, GBP, JPY)')
        public String currencyIsoCode;

        @InvocableVariable(label='Lookup Date' required=false
                          description='Date for rate lookup. Defaults to today if not provided.')
        public Date lookupDate;
    }

    public class Result {
        @InvocableVariable(label='Exchange Rate'
                          description='Dated exchange rate from DatedConversionRate or CurrencyType')
        public Decimal exchangeRate;
    }
}