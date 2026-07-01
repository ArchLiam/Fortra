/**
 * @description Service class for currency conversion operations.
 *              Provides reusable methods for querying Currency_Conversion_Formula__mdt
 *              and applying conversion formulas to prices.
 *
 *              This service is used by:
 *              - Fortra_BulkPriceUpdateBatch for bulk product price updates
 *              - Flow-based single product currency price updates
 *
 *              Formula Format: Simple arithmetic expressions like "* 0.92" or "* 1.0"
 *              The formula is applied to the USD price to get the target currency price.
 *
 * @author Marc DeBrey
 * @version 1.0
 * @since 2026-01
 */
public with sharing class Fortra_CurrencyConversionService {

    // Cached formula records to avoid repeated CMDT queries
    private static Map<String, Currency_Conversion_Formula__mdt> formulaCache;

    /**
     * @description Get all active currency conversion formulas from Custom Metadata
     *              Results are cached for the transaction to minimize SOQL queries
     * @return Map of currency formulas keyed by ISO Code (EUR, GBP, etc.)
     */
    public static Map<String, Currency_Conversion_Formula__mdt> getActiveFormulas() {
        if (formulaCache == null) {
            formulaCache = new Map<String, Currency_Conversion_Formula__mdt>();

            for (Currency_Conversion_Formula__mdt formula : [
                SELECT MasterLabel, DeveloperName, ISO_Code__c, Conversion_Formula__c,
                       Conversion_Rate__c, Is_Active__c, Description__c
                FROM Currency_Conversion_Formula__mdt
                WHERE Is_Active__c = true
            ]) {
                if (String.isNotBlank(formula.ISO_Code__c)) {
                    formulaCache.put(formula.ISO_Code__c.toUpperCase(), formula);
                }
            }

            System.debug(LoggingLevel.INFO, 'CurrencyConversionService: Loaded ' +
                formulaCache.size() + ' active currency formulas');
        }

        return formulaCache;
    }

    /**
     * @description Get the formula record for a specific currency code
     * @param currencyCode The ISO currency code (e.g., EUR, GBP)
     * @return The Currency_Conversion_Formula__mdt record or null if not found
     */
    public static Currency_Conversion_Formula__mdt getFormula(String currencyCode) {
        if (String.isBlank(currencyCode)) {
            return null;
        }

        Map<String, Currency_Conversion_Formula__mdt> formulas = getActiveFormulas();
        return formulas.get(currencyCode.toUpperCase());
    }

    /**
     * @description Convert a USD price to a target currency using the stored formula
     * @param usdPrice The price in USD
     * @param targetCurrencyCode The target currency ISO code (e.g., EUR)
     * @return The converted price, or null if conversion not possible
     */
    public static Decimal convertPrice(Decimal usdPrice, String targetCurrencyCode) {
        if (usdPrice == null || String.isBlank(targetCurrencyCode)) {
            return null;
        }

        Currency_Conversion_Formula__mdt formula = getFormula(targetCurrencyCode);
        if (formula == null) {
            System.debug(LoggingLevel.WARN, 'CurrencyConversionService: No formula found for ' +
                targetCurrencyCode);
            return null;
        }

        if (formula.Conversion_Rate__c != null) {
            return usdPrice * formula.Conversion_Rate__c;
        }

        if (String.isBlank(formula.Conversion_Formula__c)) {
            System.debug(LoggingLevel.WARN, 'CurrencyConversionService: No rate or formula for ' +
                targetCurrencyCode);
            return null;
        }

        return applyFormula(usdPrice, formula.Conversion_Formula__c);
    }

    /**
     * @description Apply a formula string to a price value
     *              Supports simple arithmetic: * (multiply), / (divide), + (add), - (subtract)
     *              Examples: "* 0.92", "* 1.0", "* 1.15"
     * @param price The input price value
     * @param formulaString The formula to apply (e.g., "* 0.92")
     * @return The calculated result, or null if formula is invalid
     */
    @TestVisible
    public static Decimal applyFormula(Decimal price, String formulaString) {
        if (price == null || String.isBlank(formulaString)) {
            return null;
        }

        String formula = formulaString.trim();

        try {
            // Parse the operator and value
            String operator = formula.substring(0, 1);
            String valueStr = formula.substring(1).trim();
            Decimal value = Decimal.valueOf(valueStr);

            Decimal result;

            switch on operator {
                when '*' {
                    result = price * value;
                }
                when '/' {
                    if (value == 0) {
                        System.debug(LoggingLevel.ERROR, 'CurrencyConversionService: Division by zero in formula');
                        return null;
                    }
                    result = price / value;
                }
                when '+' {
                    result = price + value;
                }
                when '-' {
                    result = price - value;
                }
                when else {
                    System.debug(LoggingLevel.ERROR, 'CurrencyConversionService: Unknown operator: ' + operator);
                    return null;
                }
            }

            // Round to 2 decimal places
            return result.setScale(2, System.RoundingMode.HALF_UP);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CurrencyConversionService: Error applying formula "' +
                formulaString + '": ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description Get a list of all active currency codes
     * @return List of ISO currency codes (e.g., ['USD', 'EUR', 'GBP'])
     */
    public static List<String> getActiveCurrencyCodes() {
        return new List<String>(getActiveFormulas().keySet());
    }

    /**
     * @description Convert a USD price to all active currencies
     * @param usdPrice The price in USD
     * @return Map of currency code to converted price
     */
    public static Map<String, Decimal> convertToAllCurrencies(Decimal usdPrice) {
        Map<String, Decimal> results = new Map<String, Decimal>();

        if (usdPrice == null) {
            return results;
        }

        for (String currencyCode : getActiveFormulas().keySet()) {
            Decimal convertedPrice = convertPrice(usdPrice, currencyCode);
            if (convertedPrice != null) {
                results.put(currencyCode, convertedPrice);
            }
        }

        return results;
    }

    /**
     * @description Clear the formula cache (useful for testing)
     */
    @TestVisible
    public static void clearCache() {
        formulaCache = null;
    }

    /**
     * @description Wrapper class for currency conversion result with metadata
     */
    public class ConversionResult {
        public String currencyCode;
        public Decimal originalPrice;
        public Decimal convertedPrice;
        public String formulaApplied;
        public Boolean success;
        public String errorMessage;

        public ConversionResult(String code, Decimal original) {
            this.currencyCode = code;
            this.originalPrice = original;
            this.success = false;
        }
    }

    /**
     * @description Convert price with detailed result including success/error info
     * @param usdPrice The USD price to convert
     * @param targetCurrencyCode The target currency code
     * @return ConversionResult with full details
     */
    public static ConversionResult convertPriceWithDetails(Decimal usdPrice, String targetCurrencyCode) {
        ConversionResult result = new ConversionResult(targetCurrencyCode, usdPrice);

        if (usdPrice == null) {
            result.errorMessage = 'USD price is null';
            return result;
        }

        if (String.isBlank(targetCurrencyCode)) {
            result.errorMessage = 'Target currency code is blank';
            return result;
        }

        Currency_Conversion_Formula__mdt formula = getFormula(targetCurrencyCode);
        if (formula == null) {
            result.errorMessage = 'No conversion formula found for ' + targetCurrencyCode;
            return result;
        }

        if (String.isBlank(formula.Conversion_Formula__c)) {
            result.errorMessage = 'Conversion formula is blank for ' + targetCurrencyCode;
            return result;
        }

        Decimal converted = applyFormula(usdPrice, formula.Conversion_Formula__c);
        if (converted == null) {
            result.errorMessage = 'Failed to apply formula: ' + formula.Conversion_Formula__c;
            return result;
        }

        result.convertedPrice = converted;
        result.formulaApplied = formula.Conversion_Formula__c;
        result.success = true;
        return result;
    }
}