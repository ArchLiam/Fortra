public class CurrencyCodeExtractor {
    
    @InvocableMethod(label='Extract Currency ISO Code' 
                     description='Extract ISO code from currency strings like "AUD - Australian Dollar"')
    public static List<Result> extractCode(List<Request> requests) {
        List<Result> results = new List<Result>();
        
        for (Request req : requests) {
            Result res = new Result();
            
            if (String.isNotBlank(req.currencyText)) {
                String trimmed = req.currencyText.trim();
                
                // Check if it's already just a 3-letter code
                if (trimmed.length() == 3 && trimmed.isAlpha()) {
                    res.isoCode = trimmed.toUpperCase();
                }
                // Handle format "AUD - Australian Dollar"
                else if (trimmed.contains('-')) {
                    String code = trimmed.substringBefore('-').trim();
                    if (code.length() == 3 && code.isAlpha()) {
                        res.isoCode = code.toUpperCase();
                    }
                }
                // Handle format "AUD Australian Dollar"
                else if (trimmed.contains(' ')) {
                    String code = trimmed.substringBefore(' ').trim();
                    if (code.length() == 3 && code.isAlpha()) {
                        res.isoCode = code.toUpperCase();
                    }
                }
            }
            
            results.add(res);
        }
        
        return results;
    }
    
    public class Request {
        @InvocableVariable(label='Currency Text' required=true 
                          description='Text like "AUD - Australian Dollar"')
        public String currencyText;
    }
    
    public class Result {
        @InvocableVariable(label='ISO Code' 
                          description='3-letter ISO currency code')
        public String isoCode;
    }
}