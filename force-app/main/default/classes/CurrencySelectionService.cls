public class CurrencySelectionService {
    
    public static String determineCurrencyForUser(Id userId) {
        User u = [SELECT Id, DefaultCurrencyIsoCode, Country, CompanyName 
                  FROM User WHERE Id = :userId];
        
        // Priority 1: User's default currency
        if (u.DefaultCurrencyIsoCode != null) {
            return u.DefaultCurrencyIsoCode;
        }
        
        // Priority 2: Country-based mapping
        Map<String, String> countryToCurrency = new Map<String, String>{
            'United States' => 'USD',
            'Canada' => 'CAD',
            'Australia' => 'AUD',
            // European countries
            'Germany' => 'EUR',
            'France' => 'EUR',
            'Italy' => 'EUR',
            'Spain' => 'EUR',
            'Netherlands' => 'EUR',
            'Belgium' => 'EUR',
            'Austria' => 'EUR',
            'Ireland' => 'EUR',
            'Portugal' => 'EUR',
            'Finland' => 'EUR',
            'Greece' => 'EUR',
            'Luxembourg' => 'EUR'
        };
        
        if (countryToCurrency.containsKey(u.Country)) {
            return countryToCurrency.get(u.Country);
        }
        
        // Priority 3: Default to USD
        return 'USD';
    }
    
    // Helper method to get currency for current user
    public static String determineCurrencyForCurrentUser() {
        return determineCurrencyForUser(UserInfo.getUserId());
    }
    
    // Method to check if currency change is allowed for an Order
    public static Boolean canChangeCurrencyOnOrder(String orderStatus) {
        Set<String> lockedStatuses = new Set<String>{
            'Activated',
            'In Fulfillment',
            'Fulfilled',
            'Completed'
        };
        
        return !lockedStatuses.contains(orderStatus);
    }
}