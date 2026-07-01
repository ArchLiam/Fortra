public class TextParse {
    
    @InvocableMethod(label='Parse Text Variables' 
                     description='Parse semicolon-delimited text into a collection variable or extract currency codes')
    public static List<OutputWrapper> parseText(List<InputWrapper> inputs) {
        List<OutputWrapper> outputs = new List<OutputWrapper>();
        
        for (InputWrapper input : inputs) {
            OutputWrapper output = new OutputWrapper();
            output.parsedValues = new List<String>();
            output.conversionRates = new List<Decimal>();
            output.currencyDataList = new List<CurrencyData>();
            output.currencyWithRates = new List<String>();
            
            if (String.isNotBlank(input.inputText)) {
                // Split by semicolon and trim each value
                List<String> values = input.inputText.split(';');
                for (String value : values) {
                    String trimmedValue = value.trim();
                    if (String.isNotBlank(trimmedValue)) {
                        // If extractCurrencyCode is true, extract ISO code from each value
                        if (input.extractCurrencyCode != null && input.extractCurrencyCode) {
                            String isoCode = extractCurrencyCode(trimmedValue);
                            if (String.isNotBlank(isoCode)) {
                                output.parsedValues.add(isoCode);
                                // Get conversion rate for each currency code
                                Decimal rate = getConversionRate(isoCode);
                                Decimal actualRate = rate != null ? rate : 1.0;
                                output.conversionRates.add(actualRate);
                                // Create CurrencyData object with both code and rate
                                output.currencyDataList.add(new CurrencyData(isoCode, actualRate));
                                // Add formatted string for Flow parsing "ISO:Rate"
                                output.currencyWithRates.add(isoCode + ':' + String.valueOf(actualRate));
                            }
                        } else {
                            // Otherwise add the full trimmed value
                            output.parsedValues.add(trimmedValue);
                        }
                    }
                }
                
                // Set single value if there's only one parsed value
                if (output.parsedValues.size() == 1) {
                    output.singleValue = output.parsedValues[0];
                    output.currencyCode = output.parsedValues[0]; // Also set currencyCode for backward compatibility
                    
                    // If we have a single currency code, also set the single conversionRate
                    if (input.extractCurrencyCode != null && input.extractCurrencyCode && !output.conversionRates.isEmpty()) {
                        output.conversionRate = output.conversionRates[0];
                    }
                }
            }
            
            outputs.add(output);
        }
        
        return outputs;
    }
    
    private static String extractCurrencyCode(String currencyString) {
        if (String.isBlank(currencyString)) {
            return null;
        }
        
        String trimmedInput = currencyString.trim();
        
        // Check if it's already just a 3-letter code
        if (trimmedInput.length() == 3 && trimmedInput.isAlpha()) {
            return trimmedInput.toUpperCase();
        }
        // Handle format "AUD - Australian Dollar" or "AUD-Australian Dollar"
        else if (trimmedInput.contains('-')) {
            String code = trimmedInput.substringBefore('-').trim();
            if (code.length() == 3 && code.isAlpha()) {
                return code.toUpperCase();
            }
        }
        // Handle format "AUD Australian Dollar" (space separator)
        else if (trimmedInput.contains(' ')) {
            String code = trimmedInput.substringBefore(' ').trim();
            if (code.length() == 3 && code.isAlpha()) {
                return code.toUpperCase();
            }
        }
        
        return null;
    }
    
    private static Decimal getConversionRate(String isoCode) {
        if (String.isBlank(isoCode)) {
            return null;
        }
        
        try {
            List<CurrencyType> currencies = [
                SELECT ConversionRate 
                FROM CurrencyType 
                WHERE IsoCode = :isoCode 
                AND IsActive = true 
                LIMIT 1
            ];
            
            if (!currencies.isEmpty()) {
                return currencies[0].ConversionRate;
            }
        } catch (Exception e) {
            // If query fails, return null
            System.debug('Error querying CurrencyType: ' + e.getMessage());
        }
        
        return null;
    }
    
    public class InputWrapper {
        @InvocableVariable(label='Input Text' 
                          description='Semicolon-delimited text to parse or currency string like "AUD - Australian Dollar"' 
                          required=true)
        public String inputText;
        
        @InvocableVariable(label='Extract Currency Code' 
                          description='Set to true to extract ISO currency code from strings like "AUD - Australian Dollar"' 
                          required=false)
        public Boolean extractCurrencyCode;
    }
    
    public class OutputWrapper {
        @InvocableVariable(label='Parsed Values' 
                          description='Collection of parsed text values')
        public List<String> parsedValues;
        
        @InvocableVariable(label='Single Value' 
                          description='Single string value (first parsed value or extracted currency code)')
        public String singleValue;
        
        @InvocableVariable(label='Currency Code' 
                          description='Extracted 3-letter ISO currency code when in currency extraction mode')
        public String currencyCode;
        
        @InvocableVariable(label='Conversion Rate' 
                          description='Currency conversion rate from CurrencyType for the extracted currency code')
        public Decimal conversionRate;
        
        @InvocableVariable(label='Conversion Rates' 
                          description='Collection of conversion rates corresponding to each parsed currency code')
        public List<Decimal> conversionRates;
        
        @InvocableVariable(label='Currency Data List' 
                          description='Collection of CurrencyData objects containing both ISO code and conversion rate for looping')
        public List<CurrencyData> currencyDataList;
        
        @InvocableVariable(label='Currency With Rates' 
                          description='Collection of strings formatted as "ISO:Rate" for easy parsing in Flow (e.g., "USD:1.0")')
        public List<String> currencyWithRates;
    }
    
    public class CurrencyData {
        @InvocableVariable(label='ISO Code' 
                          description='3-letter ISO currency code')
        public String isoCode;
        
        @InvocableVariable(label='Conversion Rate' 
                          description='Currency conversion rate from CurrencyType')
        public Decimal conversionRate;
        
        public CurrencyData(String code, Decimal rate) {
            this.isoCode = code;
            this.conversionRate = rate;
        }
    }
}